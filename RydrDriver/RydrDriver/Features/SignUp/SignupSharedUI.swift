//
//  SignupSharedUI.swift
//  Rydr Driver
//
//  Small shared building blocks used by multiple signup/onboarding screens:
//  a dashed-border document upload box and a SafariView wrapper for
//  presenting hosted flows (Stripe Connect, Stripe Identity, Checkr).
//  Pulled out of DriverSignupCoordinator.swift so each screen file can stay
//  focused on its own UI.
//

import SwiftUI
import SafariServices

/// Dashed-border upload affordance used for license photos, vehicle
/// registration, and insurance card uploads.
struct UploadBox: View {
    var label: String
    var systemImage: String = "tray.and.arrow.up"

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.08))
                    .frame(width: 40, height: 40)
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Styles.rydrGradient)
            }
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 110)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.gray.opacity(0.35), style: StrokeStyle(lineWidth: 1.2, dash: [6, 5]))
        )
    }
}

/// Hosted-flow presenter (Stripe Connect onboarding, Stripe Identity, Checkr Apply).
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}

/// Reusable "your information is safe/secure" reassurance card shown at the
/// bottom of most signup steps, matching the mockups.
struct SignupInfoCard: View {
    var icon: String = "lock.shield.fill"
    var title: String
    var message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(Color.red.opacity(0.1)).frame(width: 40, height: 40)
                Image(systemName: icon)
                    .foregroundStyle(Styles.rydrGradient)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.red.opacity(0.06)))
    }
}

/// Shared full-width gradient continue button (lock-step visual language
/// with the phone-entry/code-entry screens): label on the left, arrow badge
/// on the right, disabled state falls back to gray.
struct SignupContinueButton: View {
    var title: String
    var systemImage: String? = nil
    var isEnabled: Bool = true
    var isLoading: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(isLoading ? "Please wait..." : title)
                    .fontWeight(.semibold)
                Spacer()
                ZStack {
                    Circle().fill(Color.white.opacity(0.25)).frame(width: 28, height: 28)
                    if isLoading {
                        ProgressView().tint(.white).scaleEffect(0.7)
                    } else {
                        Image(systemName: "arrow.right").font(.caption.weight(.bold))
                    }
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 54)
        }
        .disabled(!isEnabled || isLoading)
        .foregroundColor(.white)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isEnabled && !isLoading ? AnyShapeStyle(Styles.rydrGradient) : AnyShapeStyle(Color.gray.opacity(0.5)))
        )
        .shadow(color: Color.red.opacity(isEnabled ? 0.22 : 0), radius: 12, y: 6)
    }
}
