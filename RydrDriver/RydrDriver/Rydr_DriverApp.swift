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

private final class RydrDriverAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
  func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
    if #available(iOS 14.0, *) {
      return AppAttestProvider(app: app)
    }
    return DeviceCheckProvider(app: app)
  }
}

class AppDelegate: NSObject, UIApplicationDelegate {
  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
    #if targetEnvironment(simulator)
    AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
    print("AppCheck: Driver debug provider (simulator)")
    #else
    AppCheck.setAppCheckProviderFactory(RydrDriverAppCheckProviderFactory())
    print("AppCheck: Driver App Attest / DeviceCheck provider")
    #endif

    FirebaseApp.configure()

    #if DEBUG
    Auth.auth().settings?.isAppVerificationDisabledForTesting = true
    #endif

    return true
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
