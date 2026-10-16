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

    var body: some Scene {
        WindowGroup { RydrWorkspaceGate { RiderWorkspaceContent() } }
    }
}

private struct RiderWorkspaceContent: View {
    @StateObject private var session = UserSessionManager()
    @State private var showSplash = true
    @State private var prestineLightAppearance = false
    @AppStorage("appAppearance") private var appAppearance = RydrAppAppearance.system.rawValue

    var body: some View {
            Group {
                #if DEBUG && targetEnvironment(simulator)
                if ProcessInfo.processInfo.arguments.contains("-RydrSignupUITest") {
                    SignupAccountUIFixture()
                } else if ProcessInfo.processInfo.arguments.contains("-RydrPromotionsUITest") {
                    RiderPromotionPanel()
                } else if ProcessInfo.processInfo.arguments.contains("-PrestineBookingUITest") {
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


#if DEBUG && targetEnvironment(simulator)
private struct SignupAccountUIFixture: View {
    @State private var email = "rider@example.com"
    @State private var password = "Simulator123!"
    @State private var confirmation = "Simulator123!"
    @State private var advanced = false
    @State private var message = ""
    var body: some View {
        NavigationStack {
            if advanced {
                Text("Account step continued").accessibilityIdentifier("signupContinued")
            } else {
                EmailAndPasswordView(email: $email, password: $password, confirmPassword: $confirmation,
                                     submissionError: message) {
                    if ProcessInfo.processInfo.arguments.contains("-RydrSignupErrorUITest") {
                        message = "That email is already linked to an account. Log in with that account, or use a different email for this phone number."
                    } else { advanced = true }
                }
            }
        }
    }
}
#endif
