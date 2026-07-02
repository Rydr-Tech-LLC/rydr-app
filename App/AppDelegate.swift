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
import Stripe
import UserNotifications

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

    // ✅ Stripe publishable key
    if let configuredKey = Bundle.main.object(forInfoDictionaryKey: "STRIPE_PUBLISHABLE_KEY") as? String,
       !configuredKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      StripeAPI.defaultPublishableKey = configuredKey
      print("💳 Stripe PK loaded from Info.plist")
    } else {
      #if DEBUG
      StripeAPI.defaultPublishableKey = "pk_test_51RcVGmBOkTOLtDHQgAvZmOvsvTxIqlcD3zLFgpkWD5pCQawjrFRBV3SjufrmGRb15GjVA7i351P1zfF7vbZ2J5gc00VuR0AYPc"
      print("💳 Stripe test PK loaded for DEBUG")
      #else
      assertionFailure("Missing STRIPE_PUBLISHABLE_KEY in Info.plist for Release builds.")
      StripeAPI.defaultPublishableKey = ""
      #endif
    }

    return true
  }

  // Firebase phone auth deep link handler
  func application(
    _ application: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey : Any] = [:]
  ) -> Bool {
    return Auth.auth().canHandle(url)
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
