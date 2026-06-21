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
    var usedAt: Timestamp?
    var transferredAt: Timestamp?
    var expiresAt: Timestamp?
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
                DispatchQueue.main.async {
                    self.codes = (snap?.documents ?? []).map(Self.makeCode)
                    self.errorMessage = nil
                }
            }
    }

    func refreshCodes() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.collection("users").document(uid)
            .collection("rydrBankCodes")
            .order(by: "createdAt", descending: true)
            .getDocuments { [weak self] snap, err in
                guard let self = self else { return }
                if let err {
                    DispatchQueue.main.async { self.errorMessage = err.localizedDescription }
                    return
                }

                DispatchQueue.main.async {
                    self.codes = (snap?.documents ?? []).map(Self.makeCode)
                    self.errorMessage = nil
                }
            }
    }

    private static func makeCode(from doc: QueryDocumentSnapshot) -> RydrBankCode {
        let d = doc.data()
        return RydrBankCode(
            id: doc.documentID,
            code: d["code"] as? String ?? "",
            status: d["status"] as? String ?? "active",
            maxMiles: d["maxMiles"] as? Int ?? 15,
            rewardGroup: d["rewardGroup"] as? String ?? "go_eco",
            rewardLabel: d["rewardLabel"] as? String ?? rewardLabel(for: d["rewardGroup"] as? String ?? "go_eco"),
            createdAt: d["createdAt"] as? Timestamp,
            usedAt: d["usedAt"] as? Timestamp,
            transferredAt: d["transferredAt"] as? Timestamp,
            expiresAt: d["expiresAt"] as? Timestamp,
            reservedRideId: d["reservedRideId"] as? String,
            usedRideId: d["usedRideId"] as? String,
            originalOwnerUid: d["originalOwnerUid"] as? String ?? "",
            transferCount: d["transferCount"] as? Int ?? 0,
            transferable: d["transferable"] as? Bool ?? true
        )
    }

    private static func rewardLabel(for group: String) -> String {
        switch group {
        case "xl": return "Rydr XL"
        case "prestine": return "Rydr Prestine"
        case "executive": return "Rydr Executive"
        default: return "Rydr Go / Rydr Eco"
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
    @Environment(\.colorScheme) private var colorScheme
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
    @State private var devMintRideType = "Rydr Go"
    // TEMP END

    // Copy confirmation
    @State private var showCopyAlert = false
    @State private var copiedCode: String?

    var body: some View {
        ZStack {
            bankBackground
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    bankHeader
                    balanceCard
                    activeCodesSection
                    earnMoreCard
                    devMintSection

                    if let error = vm.errorMessage {
                        Text(error)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                .padding(.top, 20)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
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

    private var bankBackground: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color.black,
                    Color(red: 0.055, green: 0.045, blue: 0.05),
                    Color(red: 0.10, green: 0.035, blue: 0.045)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        return LinearGradient(
            colors: [
                Color.white,
                Color(red: 0.995, green: 0.985, blue: 0.988),
                Color(red: 1.0, green: 0.95, blue: 0.955)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var cardBackground: Color {
        colorScheme == .dark ? Color(red: 0.085, green: 0.085, blue: 0.095) : .white
    }

    private var bankHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("RydrBank")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundColor(colorScheme == .dark ? .white : Color(red: 0.04, green: 0.05, blue: 0.08))

                (
                    Text("Earn ")
                        .foregroundStyle(.secondary)
                    + Text("free rides. ")
                        .foregroundStyle(Styles.rydrGradient)
                        .fontWeight(.bold)
                    + Text("Unlock more possibilities.")
                        .foregroundStyle(.secondary)
                )
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell")
                        .font(.headline.weight(.bold))
                        .foregroundColor(colorScheme == .dark ? .white : Color(red: 0.05, green: 0.08, blue: 0.14))
                        .frame(width: 48, height: 48)
                        .background(Color(.secondarySystemGroupedBackground).opacity(0.94))
                        .clipShape(Circle())
                        .shadow(color: Color.red.opacity(0.10), radius: 16, x: 0, y: 8)

                    Circle()
                        .fill(Color.red)
                        .frame(width: 7, height: 7)
                        .offset(x: -9, y: 9)
                }
            }
            .accessibilityLabel("RydrBank notifications")
        }
        .padding(.horizontal, 24)
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
        ZStack(alignment: .trailing) {
            Styles.rydrGradient

            RydrBankWalletArt()
                .frame(width: 170, height: 145)
                .offset(x: 14, y: 7)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 10) {
                Text("RydrBank Balance")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.92))

                Text("\(vm.summary.codesAvailable)")
                    .font(.system(size: 54, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)

                Text("Banked free rides")
                    .font(.headline.weight(.bold))
                    .foregroundColor(.white)

                HStack(spacing: 8) {
                    Text("Up to 15 miles each")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.16))
                        .clipShape(Capsule())

                    Image(systemName: "info.circle")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white.opacity(0.86))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 204)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color.red.opacity(0.24), radius: 22, x: 0, y: 14)
        .padding(.horizontal, 24)
    }

    private var progressSection: some View {
        VStack(spacing: 10) {
            progressCard(title: "Rydr Go / Rydr Eco", icon: "leaf.fill", rewardGroup: "go_eco")
            progressCard(title: "Rydr XL", icon: "bus.fill", rewardGroup: "xl")
            progressCard(title: "Rydr Prestine", icon: "sparkles", rewardGroup: "prestine")
            progressCard(title: "Rydr Executive", icon: "briefcase.fill", rewardGroup: "executive")
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
                .fill(cardBackground)
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
        vm.codes.filter { $0.status == "used" || $0.status == "void" || $0.status == "expired" }
    }

    private var activeCodesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your Codes")
                        .font(.title3.weight(.bold))
                        .foregroundColor(colorScheme == .dark ? .white : Color(red: 0.05, green: 0.08, blue: 0.14))
                    Text("Active RydrBank codes ready to apply, reserve, or transfer.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                NavigationLink {
                    RydrBankHistoryView(codes: usedOrTransferred)
                } label: {
                    Label("View history", systemImage: "clock.arrow.circlepath")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Styles.rydrGradient)
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background(cardBackground)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.red.opacity(0.14), lineWidth: 1))
                }

                Text("\(activeOrReserved.count)")
                    .font(.headline.weight(.bold))
                    .foregroundColor(.white)
                    .frame(width: 38, height: 38)
                    .background(Styles.rydrGradient)
                    .clipShape(Circle())
                    .accessibilityLabel("\(activeOrReserved.count) active codes")
            }

            if activeOrReserved.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Image(systemName: "ticket")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(Styles.rydrGradient)
                            .frame(width: 48, height: 48)
                            .background(Styles.rydrGradient.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("No active codes yet")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("Minted codes appear here when RydrBank confirms an active reward code for your account.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        vm.refreshCodes()
                    } label: {
                        Label("Refresh Codes", systemImage: "arrow.clockwise")
                            .font(.footnote.weight(.bold))
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                .padding(16)
                .background(Color(.secondarySystemBackground).opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                VStack(spacing: 10) {
                    ForEach(activeOrReserved) { code in
                        activeCodeRow(code)
                    }
                }
            }
        }
        .padding(.horizontal, 24)
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

    private var earnMoreCard: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Styles.rydrGradient.opacity(0.10))
                    .frame(width: 58, height: 58)
                Image(systemName: "ticket")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Styles.rydrGradient)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Earn more free rides")
                    .font(.headline.weight(.bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(red: 0.05, green: 0.08, blue: 0.14))
                Text("Take eligible rides and bank more RydrBank codes.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            NavigationLink {
                RydrBankProgressView(summary: vm.summary)
            } label: {
                Text("View progress")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .background(Styles.rydrGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(16)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 6)
        .padding(.horizontal, 24)
    }

    private var devMintSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Alpha Testing", systemImage: "hammer")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Text("Mint 10 eligible test rides into one RydrBank reward group. This is only for simulator/beta verification.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Menu {
                Button("Rydr Go / Rydr Eco") { devMintRideType = "Rydr Go" }
                Button("Rydr XL") { devMintRideType = "Rydr XL" }
                Button("Rydr Prestine") { devMintRideType = "Rydr Prestine" }
                Button("Rydr Executive") { devMintRideType = "Rydr Executive" }
            } label: {
                HStack {
                    Text("Reward group")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(displayRideType(devMintRideType))
                        .fontWeight(.semibold)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            Button {
                mintDevRides()
            } label: {
                HStack(spacing: 8) {
                    if isMinting { ProgressView().tint(.white) }
                    Text(isMinting ? "Minting..." : "Mint 10 Eligible Rides")
                        .font(.headline.weight(.bold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
            }
            .background(Styles.rydrGradient.opacity(isMinting ? 0.55 : 1))
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .disabled(isMinting)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground).opacity(0.7))
        )
        .padding(.horizontal)
        .alert("RydrBank", isPresented: $showMintAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(mintAlert ?? "")
        }
    }

    // MARK: - Rows

    private func activeCodeRow(_ code: RydrBankCode) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Styles.rydrGradient.opacity(0.10))
                        .frame(width: 54, height: 54)
                    Image(systemName: "checkmark.seal")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Styles.rydrGradient)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(code.code)
                        .font(.headline.weight(.heavy))
                        .foregroundColor(colorScheme == .dark ? .white : Color(red: 0.05, green: 0.08, blue: 0.14))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .textSelection(.enabled)

                    Text(code.rewardLabel)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Styles.rydrGradient)
                        .lineLimit(1)
                }

                Spacer(minLength: 2)

                Button {
                    UIPasteboard.general.string = code.code
                    copiedCode = code.code
                    showCopyAlert = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.headline.weight(.bold))
                        .foregroundColor(.secondary)
                        .frame(width: 48, height: 48)
                        .background(Color.red.opacity(0.08))
                        .clipShape(Circle())
                }
                .accessibilityLabel("Copy \(code.code)")

                if code.transferCount == 0 && code.transferable {
                    Button {
                        codePendingTransfer = code
                        transferTargetEmail = ""
                        transferFriendName = ""
                        transferFriendPhone = ""
                        showTransferSheet = true
                    } label: {
                        VStack(spacing: 5) {
                            Text("Transfer")
                                .font(.caption.weight(.bold))
                            Image(systemName: "arrow.right")
                                .font(.caption.weight(.bold))
                        }
                        .foregroundColor(.white)
                        .frame(width: 74)
                        .frame(maxHeight: .infinity)
                        .background(Styles.rydrGradient)
                    }
                    .accessibilityLabel("Transfer \(code.code)")
                }
            }
            .padding(14)
            .padding(.trailing, 0)

            HStack(spacing: 8) {
                codeTag("Ready to use", icon: "checkmark.circle.fill")
                if code.transferCount == 0 && code.transferable {
                    codeTag("Transferable once", icon: "doc.on.doc")
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(code.code), \(label(for: code))")
    }

    private func codeTag(_ text: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption2.weight(.semibold))
            Text(text)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemBackground))
        .clipShape(Capsule())
    }

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
                .fill(cardBackground)
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

    private func displayRideType(_ rideType: String) -> String {
        rideType == "Rydr Go" ? "Rydr Go / Rydr Eco" : rideType
    }

    private func mintDevRides() {
        Task {
            isMinting = true
            do {
                if let code = try await RydrBankAPI.mintTenDevRides(rideType: devMintRideType) {
                    mintAlert = "Minted \(displayRideType(devMintRideType)) code: \(code)"
                } else {
                    mintAlert = "No code minted. If some rides were already counted, run again."
                }
                vm.refreshCodes()
                showMintAlert = true
            } catch {
                mintAlert = "Mint failed: \(error.localizedDescription)"
                showMintAlert = true
            }
            isMinting = false
        }
    }
}

private struct RydrBankWalletArt: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.10))
                .frame(width: 130, height: 90)
                .rotationEffect(.degrees(-12))
                .offset(x: -12, y: -4)

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.92))
                .frame(width: 58, height: 92)
                .rotationEffect(.degrees(18))
                .offset(x: 26, y: -34)
                .overlay(
                    VStack(spacing: 5) {
                        Text("Rydr")
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(Styles.rydrGradient)
                        Rectangle().fill(Color.black.opacity(0.12)).frame(width: 34, height: 4)
                        Rectangle().fill(Color.black.opacity(0.08)).frame(width: 30, height: 4)
                        Rectangle().fill(Color.black.opacity(0.08)).frame(width: 36, height: 4)
                    }
                    .rotationEffect(.degrees(18))
                    .offset(x: 26, y: -34)
                )

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.86, green: 0.14, blue: 0.21), Color(red: 0.62, green: 0.05, blue: 0.16)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 124, height: 86)
                .overlay(
                    Image("RydrBankWalletR")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                        .opacity(0.92)
                )
                .offset(y: 22)

            Capsule()
                .fill(Color.white.opacity(0.22))
                .frame(width: 32, height: 20)
                .offset(x: 58, y: 18)
        }
    }
}

private struct RydrBankProgressView: View {
    @Environment(\.colorScheme) private var colorScheme
    let summary: RydrBankSummary

    private let groups: [(title: String, icon: String, key: String)] = [
        ("Rydr Go / Rydr Eco", "leaf.fill", "go_eco"),
        ("Rydr XL", "bus.fill", "xl"),
        ("Rydr Prestine", "sparkles", "prestine"),
        ("Rydr Executive", "briefcase.fill", "executive")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ride Progress")
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                    Text("Complete 10 eligible rides of 5 miles or more in a reward group to earn a matching RydrBank code.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 18)

                ForEach(groups, id: \.key) { group in
                    progressCard(title: group.title, icon: group.icon, progress: progress(for: group.key))
                }
            }
            .padding(.bottom, 28)
        }
        .background((colorScheme == .dark ? Color.black : Color(.systemGroupedBackground)).ignoresSafeArea())
        .navigationTitle("Progress")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func progress(for rewardGroup: String) -> RydrBankRideTypeProgress {
        if let progress = summary.progressByRideType[rewardGroup] {
            return progress
        }
        if rewardGroup == "go_eco" {
            return RydrBankRideTypeProgress(
                eligibleCount: summary.eligibleCount,
                totalEligible: summary.totalEligible,
                codesEarned: summary.codesEarned
            )
        }
        return RydrBankRideTypeProgress()
    }

    private func progressCard(title: String, icon: String, progress: RydrBankRideTypeProgress) -> some View {
        let current = progress.eligibleCount % 10
        let remaining = max(0, 10 - current)

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: icon)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Styles.rydrGradient)
                    .frame(width: 42, height: 42)
                    .background(Styles.rydrGradient.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline.weight(.bold))
                    Text("\(progress.totalEligible) lifetime eligible rides")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(current)/10")
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(Styles.rydrGradient)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black.opacity(0.08))
                    Capsule()
                        .fill(Styles.rydrGradient)
                        .frame(width: geo.size.width * CGFloat(current) / 10.0)
                }
            }
            .frame(height: 10)

            Text(current == 0 && progress.eligibleCount > 0
                 ? "A code was earned for the last 10 eligible rides. Start this group again to earn another."
                 : "\(remaining) more eligible \(remaining == 1 ? "ride" : "rides") to earn a \(title) code.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(colorScheme == .dark ? Color(red: 0.085, green: 0.085, blue: 0.095) : .white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
        .padding(.horizontal, 24)
    }
}

private enum RydrBankHistoryRange: String, CaseIterable {
    case days30 = "30 days"
    case days60 = "60 days"
    case days90 = "90 days"

    var days: Int {
        switch self {
        case .days30: return 30
        case .days60: return 60
        case .days90: return 90
        }
    }
}

private enum RydrBankHistoryStatus: String, CaseIterable {
    case all = "All"
    case used = "Used"
    case transferred = "Transferred"
    case expired = "Expired"
}

private struct RydrBankHistoryView: View {
    @Environment(\.colorScheme) private var colorScheme
    let codes: [RydrBankCode]
    @State private var range: RydrBankHistoryRange = .days30
    @State private var status: RydrBankHistoryStatus = .all

    private var filteredCodes: [RydrBankCode] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -range.days, to: Date()) ?? .distantPast
        return codes
            .filter { code in
                guard code.historyDate >= cutoff else { return false }
                switch status {
                case .all: return true
                case .used: return code.status == "used"
                case .transferred: return code.status == "void"
                case .expired: return code.status == "expired"
                }
            }
            .sorted { $0.historyDate > $1.historyDate }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Code History")
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                    Text("Review used, transferred, and expired RydrBank codes.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Picker("Date range", selection: $range) {
                    ForEach(RydrBankHistoryRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Status", selection: $status) {
                    ForEach(RydrBankHistoryStatus.allCases, id: \.self) { status in
                        Text(status.rawValue).tag(status)
                    }
                }
                .pickerStyle(.segmented)

                if filteredCodes.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(Styles.rydrGradient)
                        Text("No matching history")
                            .font(.headline.weight(.bold))
                        Text("Try a wider date range or a different status filter.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(30)
                    .background(colorScheme == .dark ? Color(red: 0.085, green: 0.085, blue: 0.095) : .white)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                } else {
                    VStack(spacing: 12) {
                        ForEach(filteredCodes) { code in
                            historyRow(code)
                        }
                    }
                }
            }
            .padding(24)
        }
        .background((colorScheme == .dark ? Color.black : Color(.systemGroupedBackground)).ignoresSafeArea())
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func historyRow(_ code: RydrBankCode) -> some View {
        HStack(spacing: 12) {
            Image(systemName: code.historyIcon)
                .font(.headline.weight(.bold))
                .foregroundStyle(Styles.rydrGradient)
                .frame(width: 46, height: 46)
                .background(Styles.rydrGradient.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(code.code)
                    .font(.headline.weight(.bold))
                Text(code.rewardLabel)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Styles.rydrGradient)
                Text("\(code.historyLabel) • \(code.historyDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(14)
        .background(colorScheme == .dark ? Color(red: 0.085, green: 0.085, blue: 0.095) : .white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 4)
    }
}

private extension RydrBankCode {
    var historyDate: Date {
        if status == "used", let usedAt { return usedAt.dateValue() }
        if status == "void", let transferredAt { return transferredAt.dateValue() }
        if status == "expired", let expiresAt { return expiresAt.dateValue() }
        return createdAt?.dateValue() ?? .distantPast
    }

    var historyLabel: String {
        switch status {
        case "used": return "Used"
        case "void": return "Transferred"
        case "expired": return "Expired"
        default: return status.capitalized
        }
    }

    var historyIcon: String {
        switch status {
        case "used": return "checkmark.seal"
        case "void": return "arrow.uturn.right.circle"
        case "expired": return "timer"
        default: return "ticket"
        }
    }
}
