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
                .frame(height: 315)
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(edges: .top)
                .accessibilityHidden(true)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 15) {
                    SignupBackButton { dismiss() }
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer(minLength: 130)

                    VStack(spacing: 3) {
                        HStack(spacing: 6) {
                            Text("Almost")
                                .foregroundStyle(SignupPalette.ink)
                            Text("Done!")
                                .foregroundStyle(SignupPalette.red)
                        }
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .lineLimit(1)
                        Text("A few quick steps to finish\ncreating your account.")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(SignupPalette.muted)
                            .multilineTextAlignment(.center)
                    }

                    termsAgreementSection

                    if showError && !termsAccepted {
                        Text("You must accept the Terms of Use and Privacy Policy to continue.")
                            .foregroundStyle(SignupPalette.red)
                            .font(.caption.weight(.bold))
                            .multilineTextAlignment(.center)
                    }

                    verificationToggleSection

                    if wantsVerification {
                        uploadSection
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

                    SignupProgressDots(active: 3)
                        .padding(.top, 6)
                }
                .padding(.horizontal, 28)
                .padding(.top, 16)
                .padding(.bottom, 28)
                .frame(maxWidth: 440)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "doc.text")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(SignupPalette.red)
                    .frame(width: 26)

                Text("I agree to the Terms of Use\nand Privacy Policy")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(SignupPalette.ink)

                Spacer()

                Toggle("", isOn: $termsAccepted)
                    .labelsHidden()
                    .toggleStyle(SwitchToggleStyle(tint: SignupPalette.red))
            }

            HStack(spacing: 8) {
                Spacer()
                Button("View Terms of Use") { showTermsModal = true }
                Text("|")
                    .foregroundStyle(SignupPalette.muted.opacity(0.55))
                Button("View Privacy Policy") { showPrivacyModal = true }
                Spacer()
            }
            .font(.system(size: 11, weight: .black, design: .rounded))
            .foregroundStyle(SignupPalette.red)
        }
        .padding(15)
        .background(SignupPalette.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(SignupPalette.red.opacity(0.11), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 7)
    }

    var verificationToggleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(SignupPalette.red)
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Become a Verified Rider (optional)")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(SignupPalette.ink)
                    Text("Upload the following to be verified:")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(SignupPalette.muted)
                }

                Spacer()

                Toggle("", isOn: $wantsVerification)
                    .labelsHidden()
                    .toggleStyle(SwitchToggleStyle(tint: SignupPalette.red))
            }
        }
        .padding(15)
        .background(SignupPalette.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(SignupPalette.red.opacity(0.11), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 7)
    }

    var uploadSection: some View {
        VStack(spacing: 10) {
            PhotosPicker(selection: $idFront, matching: .images) {
                VerificationUploadRow(label: "Upload State ID (Front)", isSelected: idFront != nil)
            }

            PhotosPicker(selection: $idBack, matching: .images) {
                VerificationUploadRow(label: "Upload State ID (Back)", isSelected: idBack != nil)
            }

            PhotosPicker(selection: $selfie, matching: .images) {
                VerificationUploadRow(label: "Upload Selfie", isSelected: selfie != nil, icon: "person")
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

private struct VerificationUploadRow: View {
    let label: String
    let isSelected: Bool
    var icon: String = "person.text.rectangle"

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(isSelected ? SignupPalette.red : SignupPalette.muted)
                .frame(width: 22)
            Text(label)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(SignupPalette.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(SignupPalette.muted.opacity(0.70))
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(SignupPalette.field, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(SignupPalette.red.opacity(isSelected ? 0.40 : 0.10), lineWidth: 1)
        }
    }
}

private struct CompletionHero: View {
    var body: some View {
        ZStack {
            SignupRoadHero()
            SignupMiniCity()
                .fill(SignupPalette.red.opacity(0.16))
                .frame(width: 210, height: 150)
                .offset(x: 0, y: 55)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 68, weight: .black))
                .foregroundStyle(.white, SignupPalette.red)
                .shadow(color: SignupPalette.red.opacity(0.45), radius: 18, x: 0, y: 9)
                .offset(y: 20)
            CompletionCar()
                .frame(width: 150, height: 86)
                .offset(y: 108)
        }
    }
}

private struct CompletionCar: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white, Color(red: 0.28, green: 0.29, blue: 0.34)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 138, height: 56)
                .shadow(color: Color.black.opacity(0.25), radius: 10, x: 0, y: 7)
            HStack(spacing: 34) {
                RoundedRectangle(cornerRadius: 4).fill(SignupPalette.red).frame(width: 38, height: 8)
                RoundedRectangle(cornerRadius: 4).fill(SignupPalette.red).frame(width: 38, height: 8)
            }
            .offset(y: -2)
            Text("R")
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(SignupPalette.red)
                .offset(y: 17)
        }
    }
}
