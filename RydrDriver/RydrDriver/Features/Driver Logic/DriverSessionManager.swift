//
//  DriverSessionManager.swift
//  Rydr Driver
//
//  Created by Assistant on 10/9/25.
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

enum DriverApprovalPolicy {
    static func isApproved(data: [String: Any]) -> Bool {
        let status = (data["driverApprovalStatus"] as? String)?.lowercased()
            ?? (data["approvalStatus"] as? String)?.lowercased()
            ?? "pending"
        let approvedByMissionControl = status == "approved"
        let legacyApproved = (data["isApproved"] as? Bool) ?? false
        let accountStatus = (data["accountStatus"] as? String)?.lowercased()
        let safetyReviewStatus = (data["safetyReviewStatus"] as? String)?.lowercased()
        let hasSafetyHold = (data["safetyHold"] as? Bool) ?? false
        let isSafetySuspended = accountStatus == "suspended" || safetyReviewStatus == "suspended" || hasSafetyHold
        return (approvedByMissionControl || legacyApproved) && !isSafetySuspended
    }
}

final class DriverSessionManager: ObservableObject {
    @Published var driverName: String = ""
    @Published var driverEmail: String = ""
    @Published var isLoggedIn: Bool = false
    @Published var canGoOnline: Bool = false

    private var driverListener: ListenerRegistration?

    deinit { driverListener?.remove() }

    func restoreSessionIfPossible() {
        guard !isLoggedIn, let user = Auth.auth().currentUser else { return }
        login(name: user.displayName ?? "Rydr Driver", email: user.email ?? "")
        Firestore.firestore().collection("drivers").document(user.uid).getDocument { [weak self] snapshot, _ in
            guard let self else { return }
            let data = snapshot?.data() ?? [:]
            let resolvedName = Self.publicDisplayName(from: data, authUser: user)
            let resolvedEmail = data["email"] as? String ?? user.email ?? ""
            DispatchQueue.main.async {
                guard self.isLoggedIn else { return }
                self.driverName = resolvedName
                self.driverEmail = resolvedEmail
            }
        }
    }

    func login(name: String, email: String) {
        driverName = name
        driverEmail = email
        isLoggedIn = true
        canGoOnline = false // default until Firestore confirms approval.
        Task {
            await DriverNotificationManager.shared.saveCurrentTokenForAuthenticatedUser()
        }
        startDriverStatusListener()
    }

    func logout() {
        let uid = Auth.auth().currentUser?.uid
        Task {
            await DriverNotificationManager.shared.disableAndDeleteCurrentTokenForLogout(uid: uid)
        }
        driverListener?.remove()
        driverListener = nil
        try? Auth.auth().signOut()
        driverName = ""
        driverEmail = ""
        isLoggedIn = false
        canGoOnline = false
    }

    private static func publicDisplayName(from data: [String: Any], authUser: User?) -> String {
        let first = (data["firstName"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let last = (data["lastName"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let legalName = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        if !legalName.isEmpty { return legalName }

        if let displayName = data["displayName"] as? String {
            let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, trimmed != "Rydr Driver" { return trimmed }
        }

        if let authName = authUser?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !authName.isEmpty,
           authName != "Rydr Driver" {
            return authName
        }

        return "Rydr Driver"
    }

    /// Observes the driver's Firestore document for background check status updates.
    func startDriverStatusListener() {
        driverListener?.remove()
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let doc = Firestore.firestore().collection("drivers").document(uid)
        driverListener = doc.addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }
            guard error == nil, let data = snapshot?.data() else { return }
            DispatchQueue.main.async {
                self.canGoOnline = DriverApprovalPolicy.isApproved(data: data)
            }
        }
    }
}
