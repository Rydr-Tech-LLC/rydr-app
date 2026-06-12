//
//  SplashVideoView.swift
//  Rydr Driver
//
//  SwiftUI logo splash for the driver app.
//

import SwiftUI

struct SplashVideoView: View {
    let onFinished: () -> Void

    @State private var logoVisible = false
    @State private var pulse = false
    @State private var fadeOut = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black,
                    Color(red: 0.18, green: 0.01, blue: 0.05),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Styles.rydrGradient)
                .frame(width: 260, height: 260)
                .blur(radius: 70)
                .opacity(pulse ? 0.42 : 0.2)
                .scaleEffect(pulse ? 1.16 : 0.86)

            Image("Rydr - Driver")
                .resizable()
                .scaledToFit()
                .frame(width: 235, height: 235)
                .scaleEffect(logoVisible ? (pulse ? 1.03 : 1.0) : 0.82)
                .opacity(logoVisible ? 1 : 0)
                .shadow(color: Color.red.opacity(0.32), radius: pulse ? 24 : 12, y: 10)
                .accessibilityLabel("Rydr Driver logo")
        }
        .opacity(fadeOut ? 0 : 1)
        .onAppear(perform: startAnimation)
    }

    private func startAnimation() {
        withAnimation(.spring(response: 0.72, dampingFraction: 0.82)) {
            logoVisible = true
        }

        withAnimation(.easeInOut(duration: 1.15).repeatCount(2, autoreverses: true)) {
            pulse = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.15) {
            withAnimation(.easeOut(duration: 0.45)) {
                fadeOut = true
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.65) {
            onFinished()
        }
    }
}
