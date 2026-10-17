//
//  SplashCoordinatorView.swift
//  RydrPlayground
//
//  Created by Khris Nunnally on 6/14/25.
//
import SwiftUI

struct SplashCoordinatorView: View {
    @EnvironmentObject var session: UserSessionManager
    @State private var showMainApp = false

    var body: some View {
        Group {
            if showMainApp {
                if session.isLoggedIn {
                    MainTabView()
                        .environmentObject(session)
                } else {
                    WelcomeView()
                        .environmentObject(session)
                }
            } else {
                RydrSplashView {
                    withAnimation {
                        showMainApp = true
                    }
                }
            }
        }
    }
}
