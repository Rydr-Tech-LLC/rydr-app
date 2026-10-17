//
//  Rydr_DriverApp.swift
//  Rydr Driver
//
//  Created by Khris Nunnally on 8/30/25.
//

import SwiftUI
import UIKit
import FirebaseCore
import FirebaseAuth
import FirebaseAppCheck
import FirebaseMessaging
import GoogleSignIn
import UserNotifications

private final class RydrDriverAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
  func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
    if #available(iOS 14.0, *) {
      return AppAttestProvider(app: app)
    }
    return DeviceCheckProvider(app: app)
  }
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
    // App Attest only validates against Apple's *production* attestation
    // environment, but a Debug-configuration build run from Xcode — even on
    // a real device — is signed for the *development* App Attest
    // environment. Firebase App Check's App Attest exchange rejects those
    // with "App attestation failed" / 403, which then trips the SDK's local
    // throttle ("Too many attempts"). So: any Debug build (simulator or real
    // device) uses the Debug provider; only Release/TestFlight/App Store
    // builds use real App Attest/DeviceCheck.
    #if targetEnvironment(simulator) || DEBUG
    AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
    print("AppCheck: Driver debug provider (debug build)")
    #else
    AppCheck.setAppCheckProviderFactory(RydrDriverAppCheckProviderFactory())
    print("AppCheck: Driver App Attest / DeviceCheck provider")
    #endif

    FirebaseApp.configure()
    if let clientID = FirebaseApp.app()?.options.clientID, !clientID.isEmpty {
      GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
    } else {
      print("Google Sign-In configuration failed: missing Firebase client ID")
    }

    UNUserNotificationCenter.current().delegate = self
    Messaging.messaging().delegate = self
    DriverNotificationManager.shared.configureForLaunch(application: application)

    #if DEBUG
    if ProcessInfo.processInfo.arguments.contains("-RydrUseFirebaseTestPhoneNumbers") {
      RydrWorkspace.auth.settings?.isAppVerificationDisabledForTesting = true
    }
    #endif

    return true
  }

  func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    if RydrWorkspace.auth.canHandleNotification(userInfo) {
      completionHandler(.noData)
      return
    }
    completionHandler(.noData)
  }

  func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    DriverNotificationManager.shared.handleAPNSTokenRegistration(deviceToken)
  }

  func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    DriverNotificationManager.shared.handleAPNSTokenRegistrationFailure(error)
  }

  func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
    DriverNotificationManager.shared.handleFCMTokenUpdate(fcmToken)
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if let workspace = notification.request.content.userInfo["workspace"] as? String,
       workspace != RydrWorkspace.identifier {
      completionHandler([])
      return
    }
    DriverNotificationManager.shared.handleForegroundNotification(notification.request.content.userInfo)
    completionHandler([.banner, .sound, .badge])
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    DriverNotificationManager.shared.handleNotificationTap(response.notification.request.content.userInfo)
    completionHandler()
  }
}

@main
struct Rydr_DriverApp: App {
  // register app delegate for Firebase setup
  @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
  var body: some Scene {
    WindowGroup {
      #if DEBUG && targetEnvironment(simulator)
      if ProcessInfo.processInfo.arguments.contains("-RydrSplashUITest") {
                SplashPreviewFixture()
            } else if ProcessInfo.processInfo.arguments.contains("-RydrSMSUITest") {
        NavigationStack { DriverLoginView().environmentObject(DriverSessionManager()) }
      } else if ProcessInfo.processInfo.arguments.contains("-DriverManagedPayoutE2E") {
        DriverManagedPayoutE2E()
      } else if ProcessInfo.processInfo.arguments.contains("-DriverSubmittedUITest") {
        DriverSubmittedUITestFixture()
      } else if ProcessInfo.processInfo.arguments.contains("-DriverOnboardingResumeUITest") {
        DriverOnboardingResumeUITestFixture()
      } else if ProcessInfo.processInfo.arguments.contains("-DriverPayoutMethodsUITest") {
        DriverPayoutMethodsUITestFixture()
      } else if ProcessInfo.processInfo.arguments.contains("-DriverPayoutErrorUITest") {
        NavigationStack { DriverPayoutErrorUITestFixture() }
      } else if ProcessInfo.processInfo.arguments.contains("-DriverIdentityUITest") {
        NavigationStack { DriverIdentityUITestFixture() }
      } else if ProcessInfo.processInfo.arguments.contains("-DriverDocumentUITest") {
        NavigationStack { DriverDocumentUITestFixture() }
      } else { RydrWorkspaceGate { DriverWorkspaceContent() } }
      #else
      RydrWorkspaceGate { DriverWorkspaceContent() }
      #endif
    }
  }
}

private struct DriverWorkspaceContent: View {
  @StateObject private var session = DriverSessionManager()
  var body: some View {
      NavigationStack {
        DriverRootView()
      }
      .environmentObject(session)
      .hideKeyboardOnTap()
      .onOpenURL { url in
        _ = GIDSignIn.sharedInstance.handle(url) || RydrWorkspace.auth.canHandle(url)
      }
  }
}

private struct DriverRootView: View {
    @EnvironmentObject var session: DriverSessionManager
    @State private var didFinishSplash = false

    private var simulatorWalletNavigationTest: Bool {
        #if DEBUG && targetEnvironment(simulator)
        return ProcessInfo.processInfo.arguments.contains("-RydrWalletNavigationUITest")
        #else
        return false
        #endif
    }

    var body: some View {
        Group {
            if simulatorWalletNavigationTest {
                DriverDashboardView()
            } else if !didFinishSplash {
                RydrSplashView {
                    didFinishSplash = true
                }
            } else if session.isLoggedIn {
                DriverOnboardingGate { DriverDashboardView().onAppear { session.startDriverStatusListener() } }
                    .id("\(RydrWorkspace.identifier ?? "unresolved"):\(RydrWorkspace.auth.currentUser?.uid ?? "signed-out"):\(session.onboardingResumeRequestID)")
            } else {
                DriverLoginView()
            }
        }
        .onAppear {
            session.restoreSessionIfPossible()
            #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("-RydrDocumentReminderUITest") {
                DriverNotificationManager.shared.handleNotificationTap(["type": "driverDocumentReminder", "target": "documents"])
            }
            #endif
        }
    }
}


private struct DriverOnboardingGate<Content: View>: View {
    @EnvironmentObject private var session: DriverSessionManager
    var fetchStatus: () async throws -> DriverOnboardingSnapshot = { try await RydrBackendService.onboardingStatus() }
    @ViewBuilder var content: () -> Content
    @State private var snapshot: DriverOnboardingSnapshot?
    @State private var failed = false
    var body: some View {
        Group {
            if let snapshot {
                if snapshot.completed { content() }
                else { DriverSignupCoordinator(resumeSnapshot: snapshot, onCompleted: { Task { await reload() } }).id(snapshot.nextStep) }
            } else if failed {
                VStack(spacing: 20) {
                    Text("We couldn't confirm your onboarding progress. Please try again.").accessibilityIdentifier("driverOnboardingError")
                    Button("Retry") { Task { await reload() } }
                    Button("Sign out") { session.logout() }
                }.padding()
            } else { RydrLoadingView() }
        }.task { await reload() }
    }
    @MainActor private func reload() async {
        snapshot = nil; failed = false; session.canGoOnline = false
        do {
            let result = try await fetchStatus()
            guard result.completed || result.nextStep == "phone" || result.nextStep.flatMap(DriverSignupStep.resumeStep) != nil else { throw URLError(.cannotParseResponse) }
            snapshot = result
        } catch { failed = true }
    }
}

#if DEBUG && targetEnvironment(simulator)
private struct DriverOnboardingResumeUITestFixture: View {
    @StateObject private var session = DriverSessionManager()
    var body: some View {
        DriverOnboardingGate(fetchStatus: {
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-ResumeLoading") { try await Task.sleep(for: .seconds(6)) }
            if args.contains("-ResumeUnavailable") { throw URLError(.notConnectedToInternet) }
            let step = args.contains("-ResumeAddress") ? "address" : "payouts"
            let object: [String: Any] = ["completed": args.contains("-ResumeComplete"), "nextStep": step, "cashHubOnly": false, "profile": ["firstName": "Test", "lastName": "Driver", "email": "fixture@example.com", "phoneNumber": "+16783220004", "address": ["street": "1 Main St", "city": "Atlanta", "state": "GA", "zip": "30303"]]]
            return try JSONDecoder().decode(DriverOnboardingSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        }) { Text("Driver dashboard").accessibilityIdentifier("driverDashboardFixture") }
        .environmentObject(session)
    }
}
#endif

#if DEBUG && targetEnvironment(simulator)
private struct DriverSubmittedUITestFixture: View {
    @StateObject private var session = DriverSessionManager()
    private var submittedSnapshot: DriverOnboardingSnapshot {
        try! JSONDecoder().decode(DriverOnboardingSnapshot.self, from: Data("{\"completed\":false,\"nextStep\":\"complete\",\"cashHubOnly\":false,\"profile\":{}}".utf8))
    }
    @State private var submitted = true
    @State private var showNotice = false
    @StateObject private var dashboard = DriverDashboardVM()
    private var access: DriverDrivingAccess {
        let json: String
        if ProcessInfo.processInfo.arguments.contains("-ChecklistClear") { json = #"{"allowed":true,"title":"Ready to drive","message":"Your required account checks are complete.","buttonTitle":"Got it","reasons":[],"checks":[{"code":"identity","title":"Identity verification","message":"No current identity restriction.","blocking":false,"status":"cleared","statusLabel":"Cleared"},{"code":"documents","title":"Document review","message":"No current document restriction.","blocking":false,"status":"cleared","statusLabel":"Cleared"},{"code":"background_check","title":"Background screening","message":"Screening is not required in the current beta phase.","blocking":false,"status":"not_required","statusLabel":"Not required"},{"code":"safety_review","title":"Safety review","message":"There is no active safety hold on your account.","blocking":false,"status":"cleared","statusLabel":"No hold"},{"code":"payout_setup","title":"Payout setup","message":"No current payout setup restriction.","blocking":false,"status":"cleared","statusLabel":"Ready"},{"code":"account_approval","title":"Rydr account review","message":"Your account is approved to drive.","blocking":false,"status":"cleared","statusLabel":"Approved"}]}"# }
        else if ProcessInfo.processInfo.arguments.contains("-ChecklistMixed") { json = #"{"allowed":false,"title":"Your driving checklist","message":"1 item needs attention before you can go online. Highlighted items are the only checks blocking access.","buttonTitle":"Got it","reasons":[{"code":"documents","title":"Document review","message":"Your required documents are awaiting review or need an update. Driving unlocks after all required documents are approved."}],"checks":[{"code":"identity","title":"Identity verification","message":"No current identity restriction.","blocking":false,"status":"cleared","statusLabel":"Cleared"},{"code":"documents","title":"Document review","message":"Your required documents are awaiting review or need an update. Driving unlocks after all required documents are approved.","blocking":true,"status":"blocking","statusLabel":"Needs attention"},{"code":"background_check","title":"Background screening","message":"Screening is not required in the current beta phase.","blocking":false,"status":"not_required","statusLabel":"Not required"},{"code":"safety_review","title":"Safety review","message":"There is no active safety hold on your account.","blocking":false,"status":"cleared","statusLabel":"No hold"},{"code":"payout_setup","title":"Payout setup","message":"No current payout setup restriction.","blocking":false,"status":"cleared","statusLabel":"Ready"},{"code":"account_approval","title":"Rydr account review","message":"Your account is approved to drive.","blocking":false,"status":"cleared","statusLabel":"Approved"}]}"# }
        else { json = #"{"allowed":false,"title":"A few things before you drive","message":"You’re welcome on your Dashboard. Going online will unlock once the items below are cleared.","buttonTitle":"Got it","reasons":[{"code":"identity","title":"Identity verification","message":"Stripe is reviewing your identity."},{"code":"documents","title":"Document review","message":"Your required documents are awaiting review."},{"code":"background_check","title":"Background screening","message":"Complete the required background screening before driving."},{"code":"safety_review","title":"Account access paused","message":"Rydr is reviewing a safety or account concern."}]}"# }
        return try! JSONDecoder().decode(DriverDrivingAccess.self, from: Data(json.utf8))
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Driver dashboard").font(.largeTitle).accessibilityIdentifier("submittedDashboard")
                if ProcessInfo.processInfo.arguments.contains("-RealOnlineDock") {
                    DriverDashboardActionDock(vm: dashboard, onFiltersTapped: {}, onRateCardTapped: {}, onCashHubTapped: {}, onProfileTapped: {})
                } else {
                    Button("Go Online") { showNotice = !access.allowed }.accessibilityIdentifier("submittedGoOnline")
                }
            }.onAppear { dashboard.drivingAccessTestResponse = access }
            .sheet(item: $dashboard.drivingAccessNotice) { DriverDrivingAccessSheet(access: $0) }
            .sheet(isPresented: $submitted) {
                DriverSignupCoordinator(resumeSnapshot: submittedSnapshot, verifyCompletion: {
                    if ProcessInfo.processInfo.arguments.contains("-CompletionUnavailable") { throw URLError(.notConnectedToInternet) }
                    return true
                }, onCompleted: { submitted = false }).environmentObject(session)
            }.sheet(isPresented: $showNotice) { DriverDrivingAccessSheet(access: access) }
        }
    }
}
#endif

#if DEBUG && targetEnvironment(simulator)
private struct SplashPreviewFixture: View {
    @State private var complete = false
    var body: some View {
        Group {
            if complete { Text("Ready").accessibilityIdentifier("splashComplete") }
            else { RydrSplashView { complete = true } }
        }.preferredColorScheme(ProcessInfo.processInfo.arguments.contains("-SplashDark") ? .dark : .light)
    }
}
#endif
