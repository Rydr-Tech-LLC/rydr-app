//
//  RydrBankSummary.swift
//  RydrPlayground
//
//  Created by Khris Nunnally on 8/19/25.
//

import SwiftUI
import UIKit
import FirebaseAuth
import FirebaseFirestore

// MARK: - Models

struct RydrBankRideTypeProgress: Codable {
    var eligibleCount: Int = 0
    var totalEligible: Int = 0
    var codesEarned: Int = 0
}

struct RydrBankSummary: Codable {
    var eligibleCount: Int = 0           // progress since last reward
    var totalEligible: Int = 0           // lifetime eligible rides (5+ mi)
    var codesEarned: Int = 0             // lifetime codes minted
    var codesAvailable: Int = 0          // currently active codes
    var progressByRideType: [String: RydrBankRideTypeProgress] = [:]

    enum CodingKeys: String, CodingKey {
        case eligibleCount, totalEligible, codesEarned, codesAvailable, progressByRideType
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        eligibleCount = try container.decodeIfPresent(Int.self, forKey: .eligibleCount) ?? 0
        totalEligible = try container.decodeIfPresent(Int.self, forKey: .totalEligible) ?? 0
        codesEarned = try container.decodeIfPresent(Int.self, forKey: .codesEarned) ?? 0
        codesAvailable = try container.decodeIfPresent(Int.self, forKey: .codesAvailable) ?? 0
        progressByRideType = try container.decodeIfPresent([String: RydrBankRideTypeProgress].self, forKey: .progressByRideType) ?? [:]
    }
}

struct RydrBankCode: Identifiable {
    var id: String?
    var code: String
    var status: String                   // "active" | "reserved" | "used" | "void"
    var maxMiles: Int = 15
    var rewardGroup: String = "go_eco"
    var rewardLabel: String = "Rydr Go / Rydr Eco"
    var createdAt: Timestamp?
    var reservedRideId: String?
    var usedRideId: String?

    // transfer fields
    var originalOwnerUid: String
    var transferCount: Int = 0           // 0 or 1
    var transferable: Bool = true        // false after transfer
}

// MARK: - ViewModel

final class RydrBankVM: ObservableObject {
    @Published var summary = RydrBankSummary()
    @Published var codes: [RydrBankCode] = []
    @Published var errorMessage: String?

    private let db = Firestore.firestore()
    private var summaryListener: ListenerRegistration?
    private var codesListener: ListenerRegistration?

    func start() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        listenSummary(uid: uid)
        listenCodes(uid: uid)
    }
    func stop() {
        summaryListener?.remove()
        codesListener?.remove()
        summaryListener = nil
        codesListener = nil
    }

    private func listenSummary(uid: String) {
        summaryListener = db.collection("users").document(uid)
            .addSnapshotListener { [weak self] snap, err in
                guard let self = self else { return }
                if let err = err { self.errorMessage = err.localizedDescription; return }
                guard let dict = snap?.data()?["rydrBank"] as? [String: Any] else { return }
                do {
                    let data = try JSONSerialization.data(withJSONObject: dict)
                    let decoded = try JSONDecoder().decode(RydrBankSummary.self, from: data)
                    DispatchQueue.main.async { self.summary = decoded }
                } catch {
                    self.errorMessage = "Decode error: \(error.localizedDescription)"
                }
            }
    }

    private func listenCodes(uid: String) {
        codesListener = db.collection("users").document(uid)
            .collection("rydrBankCodes")
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snap, err in
                guard let self = self else { return }
                if let err = err { self.errorMessage = err.localizedDescription; return }
                self.codes = (snap?.documents ?? []).map { doc in
                    let d = doc.data()
                    return RydrBankCode(
                        id: doc.documentID,
                        code: d["code"] as? String ?? "",
                        status: d["status"] as? String ?? "active",
                        maxMiles: d["maxMiles"] as? Int ?? 15,
                        rewardGroup: d["rewardGroup"] as? String ?? "go_eco",
                        rewardLabel: d["rewardLabel"] as? String ?? "Rydr Go / Rydr Eco",
                        createdAt: d["createdAt"] as? Timestamp,
                        reservedRideId: d["reservedRideId"] as? String,
                        usedRideId: d["usedRideId"] as? String,
                        originalOwnerUid: d["originalOwnerUid"] as? String ?? "",
                        transferCount: d["transferCount"] as? Int ?? 0,
                        transferable: d["transferable"] as? Bool ?? true
                    )
                }
            }
    }

    // MARK: - Transfer (one time)

    private func makeError(_ message: String) -> Error {
        NSError(domain: "RydrBank", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    // Updated to carry optional friend name/phone in payload (backend can ignore safely)
    func transfer(code: RydrBankCode,
                  to email: String,
                  friendName: String? = nil,
                  friendPhone: String? = nil,
                  completion: @escaping (Result<Void, Error>) -> Void) {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty else {
            completion(.failure(makeError("Please enter a valid email.")))
            return
        }
        guard code.status == "active", code.transferCount == 0, code.transferable else {
            completion(.failure(makeError("This code cannot be transferred.")))
            return
        }

        Task {
            guard let user = Auth.auth().currentUser else {
                completion(.failure(makeError("You must be logged in.")))
                return
            }
            do {
                let idToken = try await user.getIDToken()
                var req = URLRequest(url: URL(string: "https://rydr-bank.onrender.com/promo/transfer")!)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")

                var payload: [String: Any] = ["code": code.code, "recipientEmail": email]
                if let n = friendName, !n.trimmingCharacters(in: .whitespaces).isEmpty { payload["recipientName"] = n }
                if let p = friendPhone, !p.trimmingCharacters(in: .whitespaces).isEmpty { payload["recipientPhone"] = p }

                req.httpBody = try JSONSerialization.data(withJSONObject: payload)

                let (_, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                    completion(.success(()))
                } else {
                    completion(.failure(makeError("Transfer failed. Please try again.")))
                }
            } catch {
                completion(.failure(error))
            }
        }
    }
}

// MARK: - View

struct RydrBankView: View {
    @StateObject private var vm = RydrBankVM()

    // Transfer sheet state
    @State private var showTransferSheet = false
    @State private var transferTargetEmail = ""
    @State private var codePendingTransfer: RydrBankCode?
    @State private var transferFriendName = ""
    @State private var transferFriendPhone = ""

    // TEMP START: Dev mint helpers (remove when done testing)
    @State private var isMinting = false
    @State private var mintAlert: String?
    @State private var showMintAlert = false
    // TEMP END

    // Copy confirmation
    @State private var showCopyAlert = false
    @State private var copiedCode: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                balanceCard
                progressSection
                activeCodesSection
                usedCodesSection

                // TEMP START: Dev button to mint 10 eligible rides and (likely) earn a code
                Button {
                    Task {
                        isMinting = true
                        do {
                            if let code = try await RydrBankAPI.mintTenDevRides() {
                                mintAlert = "Minted code: \(code)"
                            } else {
                                mintAlert = "No code minted. If some rides were already counted, run again."
                            }
                            showMintAlert = true
                        } catch {
                            mintAlert = "Mint failed: \(error.localizedDescription)"
                            showMintAlert = true
                        }
                        isMinting = false
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isMinting { ProgressView() }
                        Text(isMinting ? "Minting…" : "Dev: Mint 10 Eligible Rides")
                            .bold()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .padding(.horizontal)
                .alert("RydrBank", isPresented: $showMintAlert) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(mintAlert ?? "")
                }
                // TEMP END

                Text("Earn 1 banked ride after every 10 completed rides of 5 miles or more in the matching ride type. Rydr Go and Rydr Eco share progress. Each banked ride covers one trip up to 15 miles.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
            .padding(.top, 12)
            .navigationTitle("RydrBank")
        }
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
        .sheet(isPresented: $showTransferSheet) {
            TransferSheet
        }
        .alert("Copied", isPresented: $showCopyAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Promo code \(copiedCode ?? "") copied to clipboard.")
        }
    }

    // MARK: - Transfer Sheet (uses Styles.rydrGradient directly; no undefined gradientColors)

    private var TransferSheet: some View {
        NavigationView {
            VStack(spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    Rectangle()
                        .fill(Styles.rydrGradient)   // ✅ use your existing gradient style
                        .frame(height: 120)
                        .ignoresSafeArea()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Transfer Code")
                            .font(.title2).bold()
                            .foregroundColor(.white)
                        if let c = codePendingTransfer?.code {
                            Text(c).font(.subheadline).foregroundColor(.white.opacity(0.9))
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                }

                Form {
                    Section(header: Text("Recipient")) {
                        TextField("Friend’s name (optional)", text: $transferFriendName)
                            .textContentType(.name)
                        TextField("Friend’s email", text: $transferTargetEmail)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                        TextField("Phone (optional, +15555551212)", text: $transferFriendPhone)
                            .keyboardType(.phonePad)
                    }

                    Section {
                        Button {
                            submitTransfer()
                        } label: {
                            HStack { Spacer(); Text("Send Transfer").fontWeight(.semibold); Spacer() }
                        }
                        .disabled(!canSubmitTransfer)

                        Button("Cancel", role: .cancel) {
                            cancelTransferPrompt()
                        }
                    }
                }
            }
            .navigationBarHidden(true)
        }
    }

    private var canSubmitTransfer: Bool {
        let email = transferTargetEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        return email.contains("@") && email.contains(".") && codePendingTransfer != nil
    }

    // MARK: - Sections

    private var balanceCard: some View {
        VStack(spacing: 10) {
            Text("RydrBank Balance")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("\(vm.summary.codesAvailable)")
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(Styles.rydrGradient)
            Text("Banked free rides (up to 15 miles each)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.white)
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
        )
        .padding(.horizontal)
    }

    private var progressSection: some View {
        VStack(spacing: 10) {
            progressCard(title: "Rydr Go / Rydr Eco", icon: "leaf.fill", rewardGroup: "go_eco")
            progressCard(title: "Rydr XL", icon: "bus.fill", rewardGroup: "xl")
            progressCard(title: "Rydr Prestine", icon: "sparkles", rewardGroup: "prestine")
        }
    }

    @ViewBuilder
    private func progressCard(title: String, icon: String, rewardGroup: String) -> some View {
        let eligibleCount = progress(for: rewardGroup).eligibleCount
        let eligibleModulo = eligibleCount % 10
        let progress = max(0, min(eligibleModulo, 10))
        let remaining = max(0, 10 - progress)

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(Styles.rydrGradient)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(progress)/10")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray5))
                        .frame(height: 10)
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Styles.rydrGradient)
                        .frame(width: geo.size.width * CGFloat(progress) / 10.0, height: 10)
                        .animation(.easeInOut(duration: 0.25), value: progress)
                }
            }
            .frame(height: 10)

            Text(remaining == 0
                 ? "Reward ready! Your next eligible \(title) ride will mint a matching code."
                 : "\(remaining) more eligible \(remaining == 1 ? "ride" : "rides") to earn a \(title) code.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.white)
                .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 3)
        )
        .padding(.horizontal)
    }

    private func progress(for rewardGroup: String) -> RydrBankRideTypeProgress {
        if let progress = vm.summary.progressByRideType[rewardGroup] {
            return progress
        }

        if rewardGroup == "go_eco" {
            return RydrBankRideTypeProgress(
                eligibleCount: vm.summary.eligibleCount,
                totalEligible: vm.summary.totalEligible,
                codesEarned: vm.summary.codesEarned
            )
        }

        return RydrBankRideTypeProgress()
    }

    private var activeOrReserved: [RydrBankCode] {
        vm.codes.filter { $0.status == "active" || $0.status == "reserved" }
    }
    private var usedOrTransferred: [RydrBankCode] {
        vm.codes.filter { $0.status == "used" || $0.status == "void" }
    }

    private var activeCodesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Your Codes")
                    .font(.headline)
                    .foregroundStyle(Styles.rydrGradient)
                Spacer()
            }
            .padding(.horizontal)

            if activeOrReserved.isEmpty {
                Text("No active codes. Complete rides or check Used Codes below.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            } else {
                VStack(spacing: 10) {
                    ForEach(activeOrReserved) { code in
                        codeRow(code, readOnly: false)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var usedCodesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if usedOrTransferred.isEmpty { EmptyView() } else {
                HStack {
                    Text("Recently Used/Transferred")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal)

                VStack(spacing: 10) {
                    ForEach(usedOrTransferred) { code in
                        codeRow(code, readOnly: true)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func codeRow(_ code: RydrBankCode, readOnly: Bool) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Styles.rydrGradient.opacity(0.12))
                    .frame(width: 48, height: 48)
                Image(systemName: icon(for: code.status))
                    .foregroundStyle(Styles.rydrGradient)
                    .font(.system(size: 20, weight: .bold))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(code.code)
                    .font(.subheadline).bold()
                    .textSelection(.enabled)
                Text(code.rewardLabel)
                    .font(.caption)
                    .foregroundStyle(Styles.rydrGradient)

                HStack(spacing: 8) {
                    if code.status == "active" {
                        Text("Ready to use")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if code.transferCount == 0 && code.transferable {
                            Text("Transferable once")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if code.status == "reserved" {
                        statusBadge("Reserved")
                    } else if code.status == "used" {
                        statusBadge("Used", outlined: true)
                    } else if code.status == "void" {
                        statusBadge("Transferred", outlined: true)
                    }
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    UIPasteboard.general.string = code.code
                    copiedCode = code.code
                    showCopyAlert = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 16, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .tint(.gray)
                .disabled(readOnly)

                if !readOnly, code.status == "active", code.transferCount == 0, code.transferable {
                    Button("Transfer") {
                        codePendingTransfer = code
                        transferTargetEmail = ""
                        transferFriendName = ""
                        transferFriendPhone = ""
                        showTransferSheet = true
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.white)
                .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        )
        .opacity(readOnly ? 0.75 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(code.code), \(label(for: code))")
    }

    private func icon(for status: String) -> String {
        switch status {
        case "active": return "checkmark.seal"
        case "reserved": return "hourglass"
        case "used": return "seal"
        case "void": return "arrow.uturn.right.circle" // transferred
        default: return "questionmark"
        }
    }

    private func label(for code: RydrBankCode) -> String {
        switch code.status {
        case "active":
            return code.transferCount == 0 && code.transferable
                ? "Ready to use • Transferable once"
                : "Ready to use"
        case "reserved": return "Reserved for an upcoming ride"
        case "used": return "Redeemed"
        case "void": return "Transferred"
        default: return "Unavailable"
        }
    }

    @ViewBuilder
    private func statusBadge(_ text: String, outlined: Bool = false) -> some View {
        let shape = Capsule()
        if outlined {
            Text(text)
                .font(.caption2).bold()
                .padding(.vertical, 5).padding(.horizontal, 8)
                .overlay(shape.stroke(LinearGradient(colors: [Color(.systemPink), Color(.systemRed)], startPoint: .leading, endPoint: .trailing), lineWidth: 1))
                .foregroundColor(.secondary)
        } else {
            Text(text)
                .font(.caption2).bold()
                .padding(.vertical, 5).padding(.horizontal, 8)
                .background(Styles.rydrGradient.opacity(0.15))
                .clipShape(shape)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func submitTransfer() {
        guard let code = codePendingTransfer else { return }
        vm.transfer(code: code,
                    to: transferTargetEmail,
                    friendName: transferFriendName,
                    friendPhone: transferFriendPhone) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    showTransferSheet = false
                    clearTransferForm()
                case .failure(let error):
                    vm.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func clearTransferForm() {
        codePendingTransfer = nil
        transferTargetEmail = ""
        transferFriendName = ""
        transferFriendPhone = ""
    }

    private func cancelTransferPrompt() {
        showTransferSheet = false
        clearTransferForm()
    }
}
