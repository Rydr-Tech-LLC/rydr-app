//
//  UserSessionManager 2.swift
//  RydrPlayground
//
//  Created by Khris Nunnally on 8/6/25.
//
import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import UIKit

enum MainAppTab: Hashable {
    case ride
    case cashHub
    case profile
    case bank
    case activity
}

enum RydrAccountAccess {
    case rider
    case cashHubOnly
}

enum RydrAppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@MainActor
class UserSessionManager: ObservableObject {
    @AppStorage("isLoggedIn") var isLoggedIn: Bool = false
    @AppStorage("userName") var userName: String = ""
    @AppStorage("userEmail") var userEmail: String = ""
    @Published var selectedTab: MainAppTab = .ride
    @Published private(set) var accountAccess: RydrAccountAccess?
    @Published var verifiedBadge: Bool = false
    @Published var studentAmbassadorBadge: Bool = false

    var hasRiderAccess: Bool { accountAccess == .rider }
    var isCashHubOnly: Bool { accountAccess == .cashHubOnly }

    private func normalizedE164Phone(_ value: String) -> String {
        let digits = value.filter { $0.isNumber }
        if digits.count == 11, digits.first == "1" {
            return "+\(digits)"
        }
        return "+1\(String(digits.suffix(10)))"
    }

    func login(
        name: String,
        email: String,
        startingTab: MainAppTab = .ride,
        access: RydrAccountAccess? = nil
    ) {
        userName = name
        userEmail = email
        selectedTab = startingTab
        accountAccess = access
        verifiedBadge = false
        studentAmbassadorBadge = false
        isLoggedIn = true
        Task {
            await NotificationManager.shared.saveCurrentTokenForAuthenticatedUser()
        }
        if access == nil {
            loadUserProfile()
        }
    }

    func logout() {
        let uid = Auth.auth().currentUser?.uid
        Task {
            await NotificationManager.shared.disableAndDeleteCurrentTokenForLogout(uid: uid)
        }
        userName = ""
        userEmail = ""
        selectedTab = .ride
        accountAccess = nil
        verifiedBadge = false
        studentAmbassadorBadge = false
        isLoggedIn = false
    }

    /// Load rider info from Firestore and compute a display name.
    func loadUserProfile() {
        guard let user = Auth.auth().currentUser else {
            logout()
            return
        }
        let uid = user.uid
        let displayName = user.displayName
        let authEmail = user.email
        Firestore.firestore()
            .collection("riders").document(uid)
            .getDocument { snap, _ in
                guard let data = snap?.data() else {
                    Task { @MainActor in
                        self.userName = displayName ?? "Rydr User"
                        self.userEmail = authEmail ?? ""
                        self.accountAccess = .cashHubOnly
                        self.selectedTab = .profile
                        self.isLoggedIn = true
                        Task {
                            await NotificationManager.shared.saveCurrentTokenForAuthenticatedUser()
                        }
                    }
                    return
                }

                let first = data["firstName"] as? String ?? ""
                let last  = data["lastName"] as? String ?? ""
                let preferred = data["preferredName"] as? String ?? ""
                let emailFromDb = data["email"] as? String
                let completedRiderTerms = data["agreedToTerms"] as? Bool ?? false
                let explicitRiderAccess = data["hasRydrRiderAccess"] as? Bool ?? false
                let identityStatus = (data["identityStatus"] as? String ?? "").lowercased()
                let hasVerifiedBadge =
                    (data["verifiedBadge"] as? Bool)
                    ?? (data["verifiedRider"] as? Bool)
                    ?? (data["identityVerified"] as? Bool)
                    ?? (identityStatus == "verified")
                let badges = data["badges"] as? [String: Any] ?? [:]
                let studentAmbassador = badges["studentAmbassador"] as? [String: Any] ?? [:]
                let hasStudentAmbassadorBadge =
                    (studentAmbassador["active"] as? Bool) ?? ((data["betaRole"] as? String) == "studentAmbassador")
                let address = data["address"] as? [String: Any] ?? [:]
                let hasRiderAddress = ["street", "city", "state", "zip"].contains { key in
                    !(address[key] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                let hasRiderAccess = explicitRiderAccess || completedRiderTerms || hasRiderAddress

                let legal = [first, last]
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespaces)

                Task { @MainActor in
                    self.userName = preferred.isEmpty
                        ? (legal.isEmpty ? "Rydr User" : legal)
                        : preferred

                    if let emailFromDb { self.userEmail = emailFromDb }
                    self.accountAccess = hasRiderAccess ? .rider : .cashHubOnly
                    self.verifiedBadge = hasVerifiedBadge
                    self.studentAmbassadorBadge = hasStudentAmbassadorBadge
                    if !hasRiderAccess && self.selectedTab != .profile {
                        self.selectedTab = .cashHub
                    }
                    self.isLoggedIn = true
                    Task {
                        await NotificationManager.shared.saveCurrentTokenForAuthenticatedUser()
                    }
                }
            }
    }

    /// Update editable fields of personal info.
    func updatePersonalInfo(
        preferredName: String,
        email: String,
        phone: String,
        street: String,
        line2: String,
        city: String,
        state: String,
        zip: String,
        completion: @escaping (Error?) -> Void
    ) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion(NSError(domain: "NoUser", code: 0))
            return
        }
        let e164Phone = normalizedE164Phone(phone)

        let payload: [String: Any] = [
            "preferredName": preferredName,
            "email": email,
            "phoneNumber": e164Phone,
            "phoneE164": e164Phone,
            "address": [
                "street": street,
                "line2": line2,
                "city": city,
                "state": state,
                "zip": zip
            ]
        ]

        // Keep local display name in sync
        Task { @MainActor in
            self.userName = preferredName.isEmpty ? self.userName : preferredName
            self.userEmail = email
        }

        let riderRef = Firestore.firestore().collection("riders").document(uid)
        riderRef.getDocument { snapshot, _ in
            let existingPhone = snapshot?.data()?["phoneE164"] as? String
                ?? snapshot?.data()?["phoneNumber"] as? String

            riderRef.setData(payload, merge: true) { err in
                if err == nil {
                    Firestore.firestore().collection("riderPhoneIndex")
                        .document(e164Phone)
                        .setData([
                            "uid": uid,
                            "createdAt": FieldValue.serverTimestamp()
                        ], merge: true)

                    if let existingPhone,
                       !existingPhone.isEmpty,
                       existingPhone != e164Phone {
                        Firestore.firestore().collection("riderPhoneIndex")
                            .document(existingPhone)
                            .getDocument { indexSnapshot, _ in
                                guard indexSnapshot?.data()?["uid"] as? String == uid else { return }
                                indexSnapshot?.reference.delete()
                            }
                    }
                }
                completion(err)
            }
        }
    }
}
