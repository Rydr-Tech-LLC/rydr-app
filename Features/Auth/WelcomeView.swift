//
//  WelcomeView.swift
//  RydrPlayground
//
//  Created by Khris Nunnally on 6/14/25.
//
import SwiftUI

struct WelcomeView: View {
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {

                // Logo
                Image("RydrLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 300, height: 300)
                    .padding(.top, 50)

                Text("Choose how to use Rydr")
                    .font(.largeTitle)
                    .bold()
                    .padding(.horizontal)

                NavigationLink(destination: SignupCoordinator()) {
                    Text("Continue as Rider")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GradientButtonStyle())

                NavigationLink(destination: CashHubSignupView()) {
                    Text("Use Cash Rydr Hub")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GradientButtonStyle())

                NavigationLink(destination: LoginView()) {
                    Text("Log In to Existing Account")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Spacer()
            }
            .padding()
        }
    }
}

#Preview {
    WelcomeView()
        .environmentObject(UserSessionManager())
}
