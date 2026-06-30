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

    UNUserNotificationCenter.current().delegate = self
    Messaging.messaging().delegate = self
    DriverNotificationManager.shared.configureForLaunch(application: application)

    #if DEBUG
    Auth.auth().settings?.isAppVerificationDisabledForTesting = true
    #endif

    return true
  }

  func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    if Auth.auth().canHandleNotification(userInfo) {
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
  @StateObject private var session = DriverSessionManager()

  var body: some Scene {
    WindowGroup {
      NavigationStack {
        DriverRootView()
      }
      .environmentObject(session)
      .onOpenURL { url in
        _ = Auth.auth().canHandle(url)
      }
    }
  }
}

private struct DriverRootView: View {
    @EnvironmentObject var session: DriverSessionManager
    @State private var didFinishSplash = false

    var body: some View {
        Group {
            if !didFinishSplash {
                SplashVideoView {
                    didFinishSplash = true
                }
            } else if session.isLoggedIn {
                DriverDashboardView()
            } else {
                DriverLoginView()
            }
        }
        .onAppear {
            session.restoreSessionIfPossible()
        }
    }
}
