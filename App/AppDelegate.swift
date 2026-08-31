//
//  AppDelegate.swift
//  RydrPlayground
//
//  Created by Khris Nunnally on 6/15/25.
//

import UIKit
import FirebaseCore
import FirebaseAuth
import FirebaseAppCheck
import FirebaseMessaging
import GoogleSignIn
import UserNotifications

enum RiderGoogleSignInCoordinator {
  private static let errorDomain = "RiderGoogleSignIn"

  @MainActor
  static func configure() throws {
    guard let clientID = FirebaseApp.app()?.options.clientID, !clientID.isEmpty else {
      throw NSError(
        domain: errorDomain,
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Missing Firebase client ID for Google sign-in."]
      )
    }
    GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
  }

  @MainActor
  static func presentingViewController() throws -> UIViewController {
    try configure()
    // Always begin an explicit Google account-selection flow. Firebase
    // sign-out and Google sign-out are independent, and older app versions
    // could leave a previous Google user cached on the device.
    GIDSignIn.sharedInstance.signOut()
    guard let windowScene = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene })
      .first(where: { $0.activationState == .foregroundActive }),
      let rootViewController = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        ?? windowScene.windows.first?.rootViewController else {
      throw NSError(
        domain: errorDomain,
        code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Unable to open Google sign-in."]
      )
    }
    return topViewController(from: rootViewController)
  }

  @MainActor
  static func signIn(
    withPresenting viewController: UIViewController,
    expectedEmail rawExpectedEmail: String,
    completion: @escaping (GIDSignInResult?, Error?) -> Void
  ) {
    let expectedEmail = rawExpectedEmail
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    guard isValidEmail(expectedEmail) else {
      completion(nil, NSError(
        domain: errorDomain,
        code: 3,
        userInfo: [NSLocalizedDescriptionKey: "Enter the Google email address you want to use, then try again."]
      ))
      return
    }

    GIDSignIn.sharedInstance.signIn(
      withPresenting: viewController,
      hint: expectedEmail
    ) { result, error in
      if let error {
        completion(nil, error)
        return
      }

      let selectedEmail = result?.user.profile?.email
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased() ?? ""
      guard selectedEmail == expectedEmail else {
        GIDSignIn.sharedInstance.signOut()
        completion(nil, NSError(
          domain: errorDomain,
          code: 4,
          userInfo: [
            NSLocalizedDescriptionKey: "Google selected \(selectedEmail.isEmpty ? "a different account" : selectedEmail). Please try again with \(expectedEmail)."
          ]
        ))
        return
      }

      completion(result, nil)
    }
  }

  private static func isValidEmail(_ email: String) -> Bool {
    let pattern = "(?:[A-Z0-9a-z._%+-]+)@(?:[A-Z0-9a-z.-]+)\\.[A-Za-z]{2,64}"
    return NSPredicate(format: "SELF MATCHES %@", pattern).evaluate(with: email)
  }

  @MainActor
  private static func topViewController(from viewController: UIViewController) -> UIViewController {
    if let presented = viewController.presentedViewController {
      return topViewController(from: presented)
    }
    if let navigationController = viewController as? UINavigationController,
       let visible = navigationController.visibleViewController {
      return topViewController(from: visible)
    }
    if let tabController = viewController as? UITabBarController,
       let selected = tabController.selectedViewController {
      return topViewController(from: selected)
    }
    return viewController
  }
}

private final class RydrAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
  func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
    if #available(iOS 14.0, *) {
      return AppAttestProvider(app: app)
    }
    return DeviceCheckProvider(app: app)
  }
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {

    // ✅ App Check provider MUST be set BEFORE FirebaseApp.configure()
    #if DEBUG
    // Debug builds: use the debug provider on simulator and physical devices.
    // The printed debug token must be registered in Firebase App Check.
    AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
    print("🔐 AppCheck: Debug provider")
    #else
    // Devices: prefer App Attest (iOS 14+), fallback to DeviceCheck
    AppCheck.setAppCheckProviderFactory(RydrAppCheckProviderFactory())
    print("🔐 AppCheck: App Attest / DeviceCheck provider (device)")
    #endif

    // ✅ Firebase
    FirebaseApp.configure()
    do {
      try RiderGoogleSignInCoordinator.configure()
    } catch {
      print("⚠️ Google Sign-In configuration failed: \(error.localizedDescription)")
    }

    // Sanity-check FirebaseOptions immediately after configure(). A missing
    // CLIENT_ID (sourced from GoogleService-Info.plist) silently breaks
    // Phone Auth's reCAPTCHA fallback flow with the backend error "The
    // request does not contain a client identifier," and also breaks Google
    // Sign-In. Surface that loudly in DEBUG instead of failing mysteriously
    // at verifyPhoneNumber() time.
    #if DEBUG
    if let options = FirebaseApp.app()?.options {
      print("🔥 Firebase options — googleAppID: \(options.googleAppID), bundleID: \(options.bundleID), projectID: \(options.projectID ?? "nil"), gcmSenderID: \(options.gcmSenderID), clientID: \(options.clientID ?? "nil")")
      if options.clientID == nil {
        print("⚠️ FirebaseOptions.clientID is nil — Phone Auth reCAPTCHA fallback and Google Sign-In will fail. Re-download GoogleService-Info.plist for this bundle ID from the Firebase console (ensure Google Sign-In is enabled for the iOS app) and replace the bundled file.")
      }
    } else {
      assertionFailure("FirebaseApp.app() is nil immediately after FirebaseApp.configure() — Firebase did not initialize.")
    }
    #endif

    UNUserNotificationCenter.current().delegate = self
    Messaging.messaging().delegate = self
    NotificationManager.shared.configureForLaunch(application: application)

    // Keep Firebase Phone Auth on the real verification path. If test phone
    // numbers are needed later, enable Firebase's testing bypass only in a
    // dedicated local/debug harness so production-like builds still send and
    // verify real SMS codes.

    Task { @MainActor in
      await RydrStripeBackendConfig.configureStripePublishableKeyIfNeeded()
    }

    return true
  }

  // Firebase phone auth deep link handler
  func application(
    _ application: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey : Any] = [:]
  ) -> Bool {
    return GIDSignIn.sharedInstance.handle(url) || Auth.auth().canHandle(url)
  }

  // Remote notifications passthrough (leave as-is)
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
    NotificationManager.shared.handleAPNSTokenRegistration(deviceToken)
  }

  func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    NotificationManager.shared.handleAPNSTokenRegistrationFailure(error)
  }

  func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
    NotificationManager.shared.handleFCMTokenUpdate(fcmToken)
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    NotificationManager.shared.handleForegroundNotification(notification.request.content.userInfo)
    completionHandler([.banner, .sound, .badge])
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    NotificationManager.shared.handleNotificationTap(response.notification.request.content.userInfo)
    completionHandler()
  }
}
