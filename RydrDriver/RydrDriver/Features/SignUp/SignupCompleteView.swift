//
//  SignupCompleteView.swift
//  Rydr Driver
//
//  Final screen of driver signup, shown once all onboarding steps are
//  submitted. Extracted out of DriverSignupCoordinator.swift and lightly
//  restyled to match the premium onboarding design language.
//

import SwiftUI

struct SignupCompleteView: View {
    var onFinish: (() -> Void)? = nil

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            ZStack {
                Circle().fill(Color.green.opacity(0.12)).frame(width: 120, height: 120)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
                    .symbolRenderingMode(.hierarchical)
            }
            .scaleEffect(appeared ? 1 : 0.7)
            .opacity(appeared ? 1 : 0)
            .onAppear {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) { appeared = true }
            }

            VStack(spacing: 10) {
                Text("Application Submitted")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(Styles.rydrGradient)

                Text("We'll notify you when your driver application review is complete. Background checks remain required and will be completed when Rydr opens the next screening phase.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
            }

            SignupContinueButton(title: "Done") { onFinish?() }
                .padding(.top, 8)

            Spacer()
        }
        .padding(.horizontal, 24)
        .background(Color(.systemBackground))
    }
}
