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

@MainActor
class UserSessionManager: ObservableObject {
    @AppStorage("isLoggedIn") var isLoggedIn: Bool = false
    @AppStorage("userName") var userName: String = ""
    @AppStorage("userEmail") var userEmail: String = ""

    func login(name: String, email: String) {
        userName = name
        userEmail = email
        isLoggedIn = true
    }

    func logout() {
        userName = ""
        userEmail = ""
        isLoggedIn = false
    }

    /// Load rider info from Firestore and compute a display name.
    func loadUserProfile() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        Firestore.firestore()
            .collection("riders").document(uid)
            .getDocument { snap, _ in
                guard let data = snap?.data() else { return }

                let first = data["firstName"] as? String ?? ""
                let last  = data["lastName"] as? String ?? ""
                let preferred = data["preferredName"] as? String ?? ""
                let emailFromDb = data["email"] as? String

                let legal = [first, last]
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespaces)

                Task { @MainActor in
                    self.userName = preferred.isEmpty
                        ? (legal.isEmpty ? "Rydr User" : legal)
                        : preferred

                    if let emailFromDb { self.userEmail = emailFromDb }
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

