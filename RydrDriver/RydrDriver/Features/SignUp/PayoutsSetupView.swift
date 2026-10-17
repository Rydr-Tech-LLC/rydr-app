//
//  PayoutsSetupView.swift
//  Rydr Driver
//
//  Payout setup stays inside Rydr using Connect embedded onboarding.
//  Completion is confirmed by the backend, never by a manual toggle.

import SwiftUI
import FirebaseAuth

struct PayoutsSetupView: View {
    let uid: String
    let email: String
    let firstName: String
    let lastName: String
    let phone: String
    let dob: Date
    let street: String
    let addressLine2: String
    let city: String
    let state: String
    let zip: String

    var currentStep: Int = 8
    var totalSteps: Int = 8

    @Binding var connectOnboarded: Bool
    /// Called when the flow finishes. Passes the Stripe Connect accountId (if one was created) so the
    /// caller can persist it. Called automatically once payouts are confirmed enabled — no manual
    /// confirmation step is ever required.
    var onNext: (String?) -> Void
    var createAccount: (() async throws -> String)? = nil

    @State private var accountId: String?
    @State private var isPresenting = false
    @State private var isLoading = false
    @State private var isCheckingStatus = false
    @State private var message: String?
    @State private var isError = false
    @State private var hasAttemptedOnboarding = false
    @State private var heroAppeared = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                DriverOnboardingStepIndicator(currentStep: currentStep, totalSteps: totalSteps, stepTitle: "Payouts")

                heroIllustration
                    .opacity(heroAppeared ? 1 : 0)
                    .scaleEffect(heroAppeared ? 1 : 0.92)
                    .onAppear {
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.05)) {
                            heroAppeared = true
                        }
                    }

                VStack(spacing: 10) {
                    Text("Set Up Your Payouts")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(Styles.rydrGradient)
                        .multilineTextAlignment(.center)

                    Text("Connect your bank account to receive your Rydr earnings. You can also add a debit card for Instant Payouts.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)

                    HStack(spacing: 6) {
                        Text("🔒")
                        Text("Secure. Encrypted. Powered by Stripe.")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.secondary.opacity(0.85))
                }

                infoRows

                stripePartnerCard

                statusArea

                SignupContinueButton(
                    title: "Set Up Payouts",
                    systemImage: "lock.fill",
                    isEnabled: !isLoading && !isCheckingStatus && !connectOnboarded,
                    isLoading: isLoading,
                    action: { Task { await startOnboarding() } }
                )
                .fullScreenCover(isPresented: $isPresenting, onDismiss: {
                    Task { await refreshStatus() }
                }) {
                    DriverPayoutAccountView(purpose: .onboarding)
                }
                .opacity(connectOnboarded ? 0.4 : 1)
                .disabled(connectOnboarded)

                HStack(spacing: 6) {
                    Image(systemName: "clock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("This usually takes about 2–3 minutes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 24)
            .padding(.top, 6)
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Hero

    private var heroIllustration: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.red.opacity(0.18), Color.red.opacity(0.0)],
                        center: .center, startRadius: 4, endRadius: 110
                    )
                )
                .frame(width: 200, height: 200)

            // Bank building, back layer
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.systemBackground))
                .frame(width: 96, height: 96)
                .shadow(color: .black.opacity(0.08), radius: 12, y: 8)
                .overlay(
                    Image(systemName: "building.columns.fill")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(Styles.rydrGradient)
                )
                .rotationEffect(.degrees(-8))
                .offset(x: -34, y: 18)

            // Floating bank card, front layer
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Styles.rydrGradient)
                .frame(width: 110, height: 70)
                .shadow(color: .red.opacity(0.3), radius: 14, y: 10)
                .overlay(
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "wave.3.right")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.85))
                        Spacer()
                        HStack(spacing: 4) {
                            ForEach(0..<4, id: \.self) { _ in
                                Circle().fill(Color.white.opacity(0.6)).frame(width: 4, height: 4)
                            }
                        }
                    }
                    .padding(10)
                )
                .rotationEffect(.degrees(6))
                .offset(x: 26, y: -10)

            // Shield + checkmark badge, top layer
            ZStack {
                Circle()
                    .fill(Color(.systemBackground))
                    .frame(width: 52, height: 52)
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Styles.rydrGradient)
            }
            .offset(x: 44, y: 36)
        }
        .frame(height: 160)
        .accessibilityLabel("Your earnings are protected")
    }

    // MARK: - Info rows

    private var infoRows: some View {
        VStack(spacing: 10) {
            PayoutInfoRow(
                icon: "building.columns.fill",
                title: "Direct Deposit (ACH)",
                subtitle: "Receive automatic deposits directly into your bank account."
            )
            PayoutInfoRow(
                icon: "bolt.fill",
                title: "Instant Payouts (Optional)",
                subtitle: "Transfer earnings to an eligible debit card within minutes."
            )
            PayoutInfoRow(
                icon: "shield.lefthalf.filled",
                title: "Bank-Level Security",
                subtitle: "Your financial information is securely handled through Stripe."
            )
        }
    }

    // MARK: - Stripe partner card

    private var stripePartnerCard: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 6) {
                Text("stripe")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundColor(.primary)
                Text("Verified Partner")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Styles.rydrGradient))
            }
            .frame(width: 88)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Why we use Stripe")
                    .font(.subheadline.weight(.semibold))
                Text("Stripe securely handles identity verification, bank account setup, and payouts using industry-leading security standards.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemBackground)))
    }

    // MARK: - Status area (auto status, no manual confirmation)

    @ViewBuilder
    private var statusArea: some View {
        if isCheckingStatus {
            HStack(spacing: 10) {
                ProgressView()
                Text("Checking your payout setup…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemBackground)))
        } else if connectOnboarded {
            HStack(spacing: 10) {
                Text("✅").font(.title3)
                Text("Payouts Connected")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.green)
                Spacer()
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.green.opacity(0.1)))
        } else if let message {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isError ? "exclamationmark.triangle.fill" : "info.circle.fill")
                    .foregroundColor(isError ? .orange : .secondary)
                Text(message)
                    .accessibilityIdentifier("payoutSetupMessage")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemBackground)))
        }
    }

    // MARK: - Backend integration

    private var stripeBackendBase: URL { URL(string: "https://rydr-stripe-backend.onrender.com")! }

    private func dobDictionary() -> [String: Int] {
        let components = Calendar.current.dateComponents([.day, .month, .year], from: dob)
        return [
            "day": components.day ?? 1,
            "month": components.month ?? 1,
            "year": components.year ?? 2000,
        ]
    }

    private func addressDictionary() -> [String: String] {
        var dict: [String: String] = [
            "line1": street,
            "city": city,
            "state": state,
            "postal_code": zip,
        ]
        if !addressLine2.isEmpty { dict["line2"] = addressLine2 }
        return dict
    }

    @MainActor
    private func startOnboarding() async {
        guard !isLoading, !isCheckingStatus, !connectOnboarded else { return }
        guard !uid.isEmpty else {
            message = "Missing account information. Please restart signup."
            isError = true
            return
        }

        isLoading = true
        isError = false
        message = nil
        hasAttemptedOnboarding = true
        defer { isLoading = false }

        do {
            let resolvedAccountId: String
            if let accountId {
                resolvedAccountId = accountId
            } else {
                if let createAccount { resolvedAccountId = try await createAccount() }
                else { resolvedAccountId = try await createConnectAccount() }
                accountId = resolvedAccountId
            }

            isPresenting = true
        } catch {
            message = error.localizedDescription
            isError = true
        }
    }

    private func createConnectAccount() async throws -> String {
        var request = RydrWorkspace.urlRequest(url: stripeBackendBase.appendingPathComponent("connect/accounts"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = try await RydrWorkspace.auth.currentUser?.getIDToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "email": email,
            "firstName": firstName,
            "lastName": lastName,
            "phone": phone,
            "dob": dobDictionary(),
            "address": addressDictionary(),
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw DriverConnectServiceError.response(data: data, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        let decoded = try JSONDecoder().decode(ConnectAccountResponse.self, from: data)
        return decoded.accountId
    }

    /// Polls the backend for Stripe Connect account status after the driver returns from the
    /// embedded onboarding screen. No manual confirmation is ever required: if payouts are enabled
    /// we mark the step complete and automatically advance; otherwise we surface a gentle
    /// "not finished yet" message while keeping the Set Up Payouts button available to retry.
    @MainActor
    private func refreshStatus() async {
        guard let accountId, hasAttemptedOnboarding else { return }
        isCheckingStatus = true
        defer { isCheckingStatus = false }

        var request = RydrWorkspace.urlRequest(url: stripeBackendBase.appendingPathComponent("connect/status"))
        request.httpMethod = "GET"
        if let token = try? await RydrWorkspace.auth.currentUser?.getIDToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let status = try JSONDecoder().decode(ConnectStatusResponse.self, from: data)
            if status.payoutsEnabled {
                withAnimation { connectOnboarded = true }
                message = nil
                isError = false
                // Give the driver a beat to see the success state, then advance automatically —
                // no manual confirmation required.
                try? await Task.sleep(nanoseconds: 1_100_000_000)
                onNext(accountId)
            } else if status.requirementsDue.isEmpty {
                // Nothing left for the driver to submit, but Stripe hasn't enabled payouts yet —
                // most commonly an identity document is still under review. This is NOT the same
                // as being done, so we must not advance the signup flow here: doing so would
                // strand the driver in a state where payouts silently never finish enabling, with
                // no way back into this step (see Phase 4 bug report).
                message = "Stripe is verifying your information — this can take a little while. We'll let you know once it's done."
                isError = false
            } else {
                message = "We couldn't confirm your payout setup yet. Please complete payout setup in Rydr."
                isError = false
            }
        } catch {
            message = "We couldn't confirm your payout setup yet. Please complete payout setup in Rydr."
            isError = false
        }
    }

    struct ConnectAccountResponse: Decodable { let accountId: String }
    struct ConnectStatusResponse: Decodable {
        let chargesEnabled: Bool
        let payoutsEnabled: Bool
        let requirementsDue: [String]

        enum CodingKeys: String, CodingKey {
            case chargesEnabled = "charges_enabled"
            case payoutsEnabled = "payouts_enabled"
            case requirementsDue = "requirements_due"
        }
    }
}

/// One row in the three-row "what you're connecting" info list — icon,
/// title, subtitle, trailing chevron. Informational only (no navigation).
private struct PayoutInfoRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.red.opacity(0.1)).frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Styles.rydrGradient)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary.opacity(0.6))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemBackground)))
    }
}


struct DriverConnectServiceError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    static func response(data: Data, status: Int) -> DriverConnectServiceError {
        struct Payload: Decodable { let error: String?; let message: String? }
        let body = try? JSONDecoder().decode(Payload.self, from: data)
        if let message = body?.message, !message.isEmpty {
            return DriverConnectServiceError(message: String(message.prefix(500)))
        }
        switch status {
        case 401: return DriverConnectServiceError(message: "Your session has expired. Sign in again before setting up payouts.")
        case 403: return DriverConnectServiceError(message: "Payout setup is not available for this account in the selected workspace. Contact Rydr support.")
        case 400: return DriverConnectServiceError(message: "Check your name, date of birth, phone number, and address before setting up payouts.")
        default: return DriverConnectServiceError(message: "Payout setup is temporarily unavailable. Please try again, or contact Rydr support if this continues.")
        }
    }
}

#if DEBUG && targetEnvironment(simulator)
struct DriverPayoutErrorUITestFixture: View {
    @State private var connected = false
    var body: some View {
        PayoutsSetupView(uid: "fixture-only", email: "fixture@example.com", firstName: "Test", lastName: "Driver", phone: "+16783220004", dob: Date(), street: "1 Main St", addressLine2: "", city: "Atlanta", state: "GA", zip: "30303", connectOnboarded: $connected, onNext: { _ in }, createAccount: {
            let data = Data(#"{"error":"connect_account_creation_restricted","message":"Payout setup is temporarily unavailable. Rydr support must resolve a Stripe account restriction. Please try again later."}"#.utf8)
            throw DriverConnectServiceError.response(data: data, status: 503)
        })
    }
}
#endif
