//
//  RydrPlaygroundApp.swift
//  RydrPlayground
//
//  Created by Khris Nunnally on 6/11/25.
//

import SwiftUI
import Firebase

@main
struct RydrApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var session = UserSessionManager()
    @State private var showSplash = true
    @State private var prestineLightAppearance = false
    @AppStorage("appAppearance") private var appAppearance = RydrAppAppearance.system.rawValue

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG && targetEnvironment(simulator)
                if ProcessInfo.processInfo.arguments.contains("-PrestineBookingUITest") {
                    NavigationStack { RideTypeSelectionView(userName: "Test Rider") }
                        .environmentObject(session)
                        .environmentObject(RideManager())
                } else {
                    appContent
                }
                #else
                appContent
                #endif
            }
            .onPreferenceChange(PrestineLightAppearancePreference.self) { prestineLightAppearance = $0 }
            .preferredColorScheme(prestineLightAppearance && session.selectedTab == .ride ? .light : RydrAppAppearance(rawValue: appAppearance)?.colorScheme)
            .hideKeyboardOnTap()
        }
    }

    private var appContent: some View {
        Group {
                if showSplash {
                    SplashVideoView { showSplash = false }
                } else {
                    if session.isLoggedIn {
                        MainTabView().environmentObject(session)
                    } else {
                        WelcomeView().environmentObject(session)
                    }
                }
        }
    }
}

