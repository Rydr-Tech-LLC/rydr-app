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

#if DEBUG
enum DriverApprovalDebugBypass {
    static let defaultsKey = "debugDriverApprovalBypassEnabled"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: defaultsKey)
    }

    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: defaultsKey)
    }

    static func isApproved(data: [String: Any]) -> Bool {
        if isEnabled { return true }
        let status = (data["backgroundCheckStatus"] as? String)?.lowercased() ?? "pending"
        let passed = (data["backgroundCheckPassed"] as? Bool) ?? false
        let allowedByString = ["passed", "clear", "approved", "complete", "completed"].contains(status)
        return passed || allowedByString
    }
}
#endif

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
    }

    func login(name: String, email: String) {
        driverName = name
        driverEmail = email
        isLoggedIn = true
        #if DEBUG
        canGoOnline = DriverApprovalDebugBypass.isEnabled
        #else
        canGoOnline = false // default until background check passes
        #endif
        startDriverStatusListener()
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
                #if DEBUG
                self.canGoOnline = DriverApprovalDebugBypass.isApproved(data: data)
                #else
                let status = (data["backgroundCheckStatus"] as? String)?.lowercased() ?? "pending"
                let passed = (data["backgroundCheckPassed"] as? Bool) ?? false
                let allowedByString = ["passed", "clear", "approved", "complete", "completed"].contains(status)
                self.canGoOnline = passed || allowedByString
                #endif
            }
        }
    }
}
