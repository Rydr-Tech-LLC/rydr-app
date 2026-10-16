//
//  UserViewModel.swift
//  RydrPlayground
//
//  Created by Khris Nunnally on 7/27/25.
//


import Foundation
import FirebaseAuth
import FirebaseFirestore

class UserViewModel: ObservableObject {
    @Published var userName: String = "Rider"

    init() {
        loadUserName()
    }

    func loadUserName() {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        RydrWorkspace.firestore.collection("users").document(uid).getDocument { doc, error in
            if let doc = doc, let data = doc.data() {
                DispatchQueue.main.async {
                    self.userName = data["name"] as? String ?? "Rider"
                }
            } else if let error = error {
                print("❌ Failed to load user name: \(error.localizedDescription)")
            }
        }
    }
}
