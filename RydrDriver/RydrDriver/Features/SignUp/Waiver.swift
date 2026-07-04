//
//  Waiver.swift
//  Rydr Driver
//

import SwiftUI

struct BetaWaiverView: View {
    var onAgree: () -> Void
    var onDecline: () -> Void

    @Environment(\.openURL) private var openURL

    private let termsURL = URL(string: "https://rydr-go.com/terms.html")!
    private let privacyURL = URL(string: "https://rydr-go.com/privacy.html")!

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 8) {
                    Image("Rydr - Driver")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 58, height: 58)
                        .accessibilityHidden(true)

                    Text("Beta Waiver")
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(Styles.rydrGradient)

                    Text("Rydr Driver is in beta. You must accept these beta terms before creating a driver account.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
                .padding(.top, 12)

                VStack(alignment: .leading, spacing: 14) {
                    waiverRow(icon: "wrench.and.screwdriver.fill", text: "The driver app is pre-release software. Features, service areas, compensation workflows, and policies may change during testing.")
                    waiverRow(icon: "exclamationmark.triangle.fill", text: "Bugs, outages, inaccurate estimates, incomplete functionality, crashes, data loss, and unexpected behavior may occur.")
                    waiverRow(icon: "location.fill", text: "Beta services may be limited by geography, operating hours, driver availability, testing schedules, feature flags, and technical constraints.")
                    waiverRow(icon: "bubble.left.and.bubble.right.fill", text: "Rydr may contact you about testing activities, surveys, bug reports, feature validation, and beta operational announcements.")
                    waiverRow(icon: "lock.shield.fill", text: "Non-public beta features, screenshots, pricing concepts, workflows, documentation, and unreleased functionality should not be shared publicly unless Rydr authorizes it.")
                    waiverRow(icon: "shield.lefthalf.filled", text: "Nothing in this beta waiver limits safety reporting, emergency rights, or rights related to unlawful conduct, assault, discrimination, harassment, or intentional misconduct.")
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.gray.opacity(0.18), lineWidth: 1)
                )

                HStack(spacing: 4) {
                    Text("By agreeing, you also accept Rydr's")
                        .foregroundStyle(.secondary)
                    Button("Terms") { openURL(termsURL) }
                        .foregroundStyle(Styles.rydrGradient)
                    Text("and")
                        .foregroundStyle(.secondary)
                    Button("Privacy Policy") { openURL(privacyURL) }
                        .foregroundStyle(Styles.rydrGradient)
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.plain)
                .lineLimit(2)
                .minimumScaleFactor(0.78)

                SignupContinueButton(title: "I Agree", systemImage: "checkmark.shield.fill", action: onAgree)

                Button {
                    onDecline()
                } label: {
                    Text("I Decline")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                }
                .foregroundStyle(Styles.rydrGradient)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Styles.rydrGradient, lineWidth: 1.2)
                )

                SignupInfoCard(
                    icon: "info.circle.fill",
                    title: "Required for beta",
                    message: "Declining returns you to sign in. Beta participation is not available without this agreement."
                )
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 30)
        }
        .background(Color(.systemBackground))
        .navigationBarBackButtonHidden(true)
    }

    private func waiverRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.1))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Styles.rydrGradient)
            }

            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    BetaWaiverView(onAgree: {}, onDecline: {})
}
