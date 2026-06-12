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

@MainActor
class UserSessionManager: ObservableObject {
    @AppStorage("isLoggedIn") var isLoggedIn: Bool = false
    @AppStorage("userName") var userName: String = ""
    @AppStorage("userEmail") var userEmail: String = ""
    @Published var selectedTab: MainAppTab = .ride
    @Published private(set) var accountAccess: RydrAccountAccess?

    var hasRiderAccess: Bool { accountAccess == .rider }
    var isCashHubOnly: Bool { accountAccess == .cashHubOnly }

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
        isLoggedIn = true
        if access == nil {
            loadUserProfile()
        }
    }

    func logout() {
        userName = ""
        userEmail = ""
        selectedTab = .ride
        accountAccess = nil
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
                    }
                    return
                }

                let first = data["firstName"] as? String ?? ""
                let last  = data["lastName"] as? String ?? ""
                let preferred = data["preferredName"] as? String ?? ""
                let emailFromDb = data["email"] as? String
                let completedRiderTerms = data["agreedToTerms"] as? Bool ?? false
                let explicitRiderAccess = data["hasRydrRiderAccess"] as? Bool ?? false
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
                    if !hasRiderAccess && self.selectedTab != .profile {
                        self.selectedTab = .cashHub
                    }
                    self.isLoggedIn = true
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

        let payload: [String: Any] = [
            "preferredName": preferredName,
            "email": email,
            "phoneNumber": phone,
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

        Firestore.firestore()
            .collection("riders").document(uid)
            .setData(payload, merge: true) { err in
                completion(err)
            }
    }
}
