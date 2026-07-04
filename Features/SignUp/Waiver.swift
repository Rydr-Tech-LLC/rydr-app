//
//  Waiver.swift
//  RydrPlayground
//

import SwiftUI

struct BetaWaiverView: View {
    var onAgree: () -> Void
    var onDecline: () -> Void

    @Environment(\.openURL) private var openURL

    private let termsURL = URL(string: "https://rydr-go.com/terms.html")!
    private let privacyURL = URL(string: "https://rydr-go.com/privacy.html")!

    var body: some View {
        SignupScreenScaffold(
            activeStep: 0,
            hero: {
                SignupAtlantaHero()
            },
            content: {
                VStack(spacing: 18) {
                    SignupBrandHeader()

                    SignupFormPanel {
                        SignupStepHeader(active: 0)

                        VStack(spacing: 10) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 34, weight: .bold))
                                .foregroundStyle(SignupPalette.redGradient)

                            Text("Beta Waiver")
                                .font(.system(size: 27, weight: .black, design: .rounded))
                                .foregroundStyle(SignupPalette.ink)
                                .multilineTextAlignment(.center)

                            Text("Rydr is currently in beta. Please review and accept these beta terms before creating your account.")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(SignupPalette.muted)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            WaiverFactRow(icon: "wrench.and.screwdriver.fill", text: "The app is pre-release software. Features may change, be limited, stop working, or be removed during testing.")
                            WaiverFactRow(icon: "exclamationmark.triangle.fill", text: "Bugs, outages, inaccurate estimates, crashes, incomplete functionality, and unexpected behavior may occur.")
                            WaiverFactRow(icon: "location.fill", text: "Beta service may be limited by geography, testing schedules, driver availability, feature flags, and operational constraints.")
                            WaiverFactRow(icon: "bubble.left.and.bubble.right.fill", text: "Rydr may contact you about testing activities, surveys, bug reports, feature validation, and beta announcements.")
                            WaiverFactRow(icon: "lock.shield.fill", text: "Non-public beta features, screenshots, pricing concepts, workflows, and unreleased functionality should not be shared publicly unless Rydr authorizes it.")
                            WaiverFactRow(icon: "shield.lefthalf.filled", text: "Nothing in this beta waiver limits safety reporting, emergency rights, or rights related to unlawful conduct, assault, discrimination, harassment, or intentional misconduct.")
                        }
                        .padding(14)
                        .background(SignupPalette.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(SignupPalette.softLine, lineWidth: 1)
                        }

                        HStack(spacing: 4) {
                            Text("By agreeing, you also accept Rydr's")
                                .foregroundStyle(SignupPalette.muted)
                            Button("Terms") { openURL(termsURL) }
                                .foregroundStyle(SignupPalette.red)
                            Text("and")
                                .foregroundStyle(SignupPalette.muted)
                            Button("Privacy Policy") { openURL(privacyURL) }
                                .foregroundStyle(SignupPalette.red)
                        }
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .buttonStyle(.plain)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)

                        Button("I Agree") {
                            onAgree()
                        }
                        .buttonStyle(SignupPrimaryButtonStyle())

                        Button {
                            onDecline()
                        } label: {
                            Text("I Decline")
                                .font(.system(size: 15, weight: .black, design: .rounded))
                                .foregroundStyle(SignupPalette.red)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(SignupPalette.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(SignupPalette.softLine, lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            },
            onBack: { onDecline() }
        )
        .navigationBarBackButtonHidden(true)
    }
}

private struct WaiverFactRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(SignupPalette.red)
                .frame(width: 20, height: 20)
            Text(text)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(SignupPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    BetaWaiverView(onAgree: {}, onDecline: {})
}
