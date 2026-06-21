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
    @AppStorage("appAppearance") private var appAppearance = RydrAppAppearance.system.rawValue

    var body: some Scene {
        WindowGroup {
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
            .preferredColorScheme(RydrAppAppearance(rawValue: appAppearance)?.colorScheme)
        }
    }
}


