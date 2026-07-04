//
//  TermsVerificationView.swift
//  RydrSignupFlow
//

import SwiftUI
import StripeIdentity

struct TermsAndVerificationView: View {
    @Binding var termsAccepted: Bool
    @Binding var wantsVerification: Bool
    var onSubmit: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showError = false
    @State private var isStartingIdentityVerification = false
    @State private var verificationMessage: String?
    @State private var verificationIsError = false
    private let termsURL = URL(string: "https://rydr-go.com/terms.html")!
    private let privacyURL = URL(string: "https://rydr-go.com/privacy.html")!

    var body: some View {
        ZStack {
            SignupPalette.background.ignoresSafeArea()
            CompletionHero()
                .frame(height: 280)
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(edges: .top)
                .accessibilityHidden(true)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    SignupBackButton { dismiss() }
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer(minLength: 176)

                    SignupFormPanel {
                        SignupStepHeader(active: 3)

                        VStack(spacing: 8) {
                            Text("Finish Your Account")
                                .font(.system(size: 25, weight: .black, design: .rounded))
                                .foregroundStyle(SignupPalette.ink)
                                .multilineTextAlignment(.center)
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)

                            Text("Verify now for a trusted rider badge,\nor skip and do it later.")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(SignupPalette.muted)
                                .multilineTextAlignment(.center)
                                .lineSpacing(2)
                        }

                        verifiedRiderSection

                        termsAgreementSection

                        if showError && !termsAccepted {
                            Text("You must accept the Terms of Use and Privacy Policy to continue.")
                                .foregroundStyle(SignupPalette.red)
                                .font(.caption.weight(.bold))
                                .multilineTextAlignment(.center)
                        }

                        if let verificationMessage {
                            Text(verificationMessage)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(verificationIsError ? SignupPalette.red : SignupPalette.success)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Button {
                            startStripeIdentityVerification()
                        } label: {
                            HStack(spacing: 8) {
                                if isStartingIdentityVerification {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "person.text.rectangle.fill")
                                }
                                Text(isStartingIdentityVerification ? "Opening Stripe Identity..." : "Verify with Stripe Identity")
                            }
                        }
                        .buttonStyle(SignupPrimaryButtonStyle())
                        .disabled(isStartingIdentityVerification)
                        .padding(.top, 4)

                        Button {
                            submitWithoutVerification()
                        } label: {
                            Text("Skip for Now")
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
                        .disabled(isStartingIdentityVerification)

                        SignupSecurityFooter(text: "Your information is secure and private.")
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 28)
                .frame(maxWidth: 430)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
    }
}

private extension TermsAndVerificationView {
    var termsAgreementSection: some View {
        HStack(spacing: 7) {
            Button {
                termsAccepted.toggle()
            } label: {
                Image(systemName: termsAccepted ? "checkmark.square.fill" : "square")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(SignupPalette.red)
            }
            .buttonStyle(.plain)

            Text("I agree to the ")
                .foregroundStyle(SignupPalette.muted)

            Button("Terms of Use") {
                openURL(termsURL)
            }
            .buttonStyle(.plain)
            .foregroundStyle(SignupPalette.red)

            Text("and")
                .foregroundStyle(SignupPalette.muted)

            Button("Privacy Policy") {
                openURL(privacyURL)
            }
            .buttonStyle(.plain)
            .foregroundStyle(SignupPalette.red)
        }
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var verifiedRiderSection: some View {
        HStack(spacing: 13) {
            ZStack {
                Circle()
                    .fill(SignupPalette.red.opacity(0.09))
                    .frame(width: 42, height: 42)
                Image(systemName: wantsVerification ? "checkmark.seal.fill" : "checkmark.seal")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(SignupPalette.red)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Verified Rider (Optional)")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(SignupPalette.ink)
                Text("Stripe Identity handles your ID and selfie securely. You can skip this and verify from Profile later.")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(SignupPalette.muted)
                    .lineLimit(3)
                    .minimumScaleFactor(0.84)
            }

            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 18, weight: .black))
                .foregroundStyle(SignupPalette.red)
        }
        .padding(13)
        .background(SignupPalette.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(SignupPalette.softLine, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 6)
    }

    func submitWithoutVerification() {
        guard termsAccepted else {
            withAnimation { showError = true }
            return
        }
        wantsVerification = false
        showError = false
        verificationMessage = nil
        onSubmit()
    }

    func startStripeIdentityVerification() {
        guard termsAccepted else {
            withAnimation { showError = true }
            return
        }
        guard !isStartingIdentityVerification else { return }

        wantsVerification = true
        showError = false
        verificationMessage = nil
        verificationIsError = false
        isStartingIdentityVerification = true

        Task {
            do {
                let clientSecret = try await RiderIdentityVerificationService.shared.createSession()
                let result = try await RiderIdentityVerificationService.shared.presentVerification(clientSecret: clientSecret)
                await MainActor.run {
                    isStartingIdentityVerification = false
                    handleStripeIdentityResult(result)
                }
            } catch {
                await MainActor.run {
                    isStartingIdentityVerification = false
                    verificationIsError = true
                    verificationMessage = error.localizedDescription
                }
            }
        }
    }

    func handleStripeIdentityResult(_ result: IdentityVerificationSheet.VerificationFlowResult) {
        switch result {
        case .flowCompleted:
            verificationIsError = false
            verificationMessage = "Verification submitted. Stripe will confirm your verified rider badge."
            onSubmit()
        case .flowCanceled:
            verificationIsError = true
            verificationMessage = "Verification was canceled. You can try again or skip for now."
        case .flowFailed(let error):
            verificationIsError = true
            verificationMessage = error.localizedDescription
        }
    }
}

private struct CompletionHero: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.white,
                    Color(red: 1.0, green: 0.96, blue: 0.965),
                    SignupPalette.background.opacity(0.92)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            CompletionSparkles()
                .fill(SignupPalette.red.opacity(0.34))
                .frame(width: 360, height: 210)
                .offset(y: 10)
            ProfileCompletionRing()
                .frame(width: 148, height: 148)
                .offset(y: 42)
            Text("Almost There!")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(SignupPalette.red)
                .offset(y: 142)
        }
    }
}

private struct ProfileCompletionRing: View {
    private let progress: Double = 0.85

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(red: 0.925, green: 0.925, blue: 0.925), lineWidth: 11)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    SignupPalette.redGradient,
                    style: StrokeStyle(lineWidth: 11, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: SignupPalette.red.opacity(0.28), radius: 9, x: 0, y: 3)

            Circle()
                .fill(.white)
                .padding(31)
                .overlay {
                    Circle()
                        .stroke(Color(red: 0.96, green: 0.96, blue: 0.96), lineWidth: 1.5)
                        .padding(31)
                }

            VStack(spacing: 4) {
                Text("85%")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(Color(red: 0.13, green: 0.13, blue: 0.13))
                    .lineLimit(1)
            }
        }
        .shadow(color: Color.black.opacity(0.07), radius: 18, x: 0, y: 12)
    }
}

private struct CompletionSparkles: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let points: [(CGFloat, CGFloat, CGFloat)] = [
            (0.08, 0.22, 5), (0.18, 0.56, 3), (0.27, 0.18, 3), (0.42, 0.08, 4),
            (0.63, 0.16, 3), (0.80, 0.30, 5), (0.90, 0.62, 3), (0.14, 0.78, 4),
            (0.38, 0.74, 3), (0.72, 0.78, 4), (0.55, 0.36, 2), (0.32, 0.46, 2),
            (0.86, 0.12, 2), (0.05, 0.48, 2)
        ]

        for (xRatio, yRatio, size) in points {
            let center = CGPoint(x: rect.width * xRatio, y: rect.height * yRatio)
            path.move(to: CGPoint(x: center.x, y: center.y - size))
            path.addLine(to: CGPoint(x: center.x + size, y: center.y))
            path.addLine(to: CGPoint(x: center.x, y: center.y + size))
            path.addLine(to: CGPoint(x: center.x - size, y: center.y))
            path.closeSubpath()
        }

        return path
    }
}
