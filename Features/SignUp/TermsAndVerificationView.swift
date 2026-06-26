//
//  TermsVerificationView.swift
//  RydrSignupFlow
//

import SwiftUI
import PhotosUI

struct TermsAndVerificationView: View {
    @Binding var termsAccepted: Bool
    @Binding var wantsVerification: Bool
    @Binding var idFront: PhotosPickerItem?
    @Binding var idBack: PhotosPickerItem?
    @Binding var selfie: PhotosPickerItem?
    var onSubmit: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showTermsModal = false
    @State private var showPrivacyModal = false
    @State private var showError = false

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
                            Text("Verify Your Identity")
                                .font(.system(size: 25, weight: .black, design: .rounded))
                                .foregroundStyle(SignupPalette.ink)
                                .multilineTextAlignment(.center)
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)

                            Text("This helps keep our community\nsafe and trusted.")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(SignupPalette.muted)
                                .multilineTextAlignment(.center)
                                .lineSpacing(2)
                        }

                        uploadSection

                        verifiedRiderSection

                        termsAgreementSection

                        if showError && !termsAccepted {
                            Text("You must accept the Terms of Use and Privacy Policy to continue.")
                                .foregroundStyle(SignupPalette.red)
                                .font(.caption.weight(.bold))
                                .multilineTextAlignment(.center)
                        }

                        Button("Create Account") {
                            if termsAccepted {
                                showError = false
                                onSubmit()
                            } else {
                                withAnimation { showError = true }
                            }
                        }
                        .buttonStyle(SignupPrimaryButtonStyle())
                        .padding(.top, 4)

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
        .sheet(isPresented: $showTermsModal) {
            TermsModalView()
        }
        .sheet(isPresented: $showPrivacyModal) {
            PrivacyModalView()
        }
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
                showTermsModal = true
            }
            .buttonStyle(.plain)
            .foregroundStyle(SignupPalette.red)

            Text("and")
                .foregroundStyle(SignupPalette.muted)

            Button("Privacy Policy") {
                showPrivacyModal = true
            }
            .buttonStyle(.plain)
            .foregroundStyle(SignupPalette.red)
        }
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var verifiedRiderSection: some View {
        Button {
            wantsVerification.toggle()
        } label: {
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
                    Text("Get priority support and build trust\nin the community.")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(SignupPalette.muted)
                        .lineLimit(2)
                        .minimumScaleFactor(0.84)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(SignupPalette.red)
            }
        }
        .buttonStyle(.plain)
        .padding(13)
        .padding(15)
        .background(SignupPalette.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(SignupPalette.softLine, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 6)
    }

    var uploadSection: some View {
        VStack(spacing: 11) {
            PhotosPicker(selection: $idFront, matching: .images) {
                VerificationUploadRow(title: "State ID (Front)", subtitle: "Upload a clear photo", isSelected: idFront != nil)
            }

            PhotosPicker(selection: $idBack, matching: .images) {
                VerificationUploadRow(title: "State ID (Back)", subtitle: "Upload a clear photo", isSelected: idBack != nil)
            }

            PhotosPicker(selection: $selfie, matching: .images) {
                VerificationUploadRow(title: "Selfie", subtitle: "Take a clear selfie", isSelected: selfie != nil, icon: "person.crop.square.dashed")
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

private struct VerificationUploadRow: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    var icon: String = "person.text.rectangle"

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(isSelected ? SignupPalette.success : SignupPalette.muted)
                .frame(width: 36, height: 36)
                .background((isSelected ? SignupPalette.success : SignupPalette.muted).opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(SignupPalette.ink)
                Text(subtitle)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(SignupPalette.muted)
            }

            Spacer()

            Image(systemName: isSelected ? "checkmark.circle" : "icloud.and.arrow.up")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(isSelected ? SignupPalette.success : SignupPalette.red)
        }
        .padding(.horizontal, 14)
        .frame(height: 62)
        .background(SignupPalette.field, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(SignupPalette.softLine, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.035), radius: 8, x: 0, y: 5)
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
