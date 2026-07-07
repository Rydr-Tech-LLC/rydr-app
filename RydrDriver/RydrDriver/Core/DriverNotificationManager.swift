//
//  DriverNotificationManager.swift
//  Rydr Driver
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging
import UIKit
import UserNotifications

final class DriverNotificationManager {
    static let shared = DriverNotificationManager()

    private let db = Firestore.firestore()
    private let defaults = UserDefaults.standard
    private let lastTokenKey = "rydr.driver.notifications.lastFCMToken"
    private let lastUIDKey = "rydr.driver.notifications.lastUID"

    private init() {}

    func configureForLaunch(application: UIApplication = .shared) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error {
                Self.log("permission_request_failed", ["error": error.localizedDescription])
                return
            }

            Self.log("permission_request_completed", ["granted": "\(granted)"])
            DispatchQueue.main.async {
                application.registerForRemoteNotifications()
            }
        }
    }

    func handleAPNSTokenRegistration(_ deviceToken: Data) {
        Messaging.messaging().setAPNSToken(deviceToken, type: apnsTokenType)
        let tokenDescription = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        Self.log("apns_token_registered", [
            "environment": apnsEnvironment,
            "tokenPrefix": String(tokenDescription.prefix(12))
        ])
    }

    func handleAPNSTokenRegistrationFailure(_ error: Error) {
        Self.log("apns_registration_failed", ["error": error.localizedDescription])
    }

    func handleFCMTokenUpdate(_ token: String?) {
        guard let token, !token.isEmpty else {
            Self.log("fcm_token_empty")
            return
        }

        Self.log("fcm_token_updated", ["tokenPrefix": String(token.prefix(12))])
        Task {
            await saveTokenIfAuthenticated(token)
        }
    }

    func saveCurrentTokenForAuthenticatedUser() async {
        do {
            let token = try await currentFCMToken()
            await saveTokenIfAuthenticated(token)
        } catch {
            Self.log("current_fcm_token_failed", ["error": error.localizedDescription])
        }
    }

    func disableAndDeleteCurrentTokenForLogout(uid explicitUID: String? = nil) async {
        guard let uid = explicitUID ?? Auth.auth().currentUser?.uid ?? defaults.string(forKey: lastUIDKey) else {
            Self.log("logout_token_cleanup_skipped", ["reason": "missing_uid"])
            return
        }

        let storedToken = defaults.string(forKey: lastTokenKey)
        let resolvedToken: String?
        if let storedToken, !storedToken.isEmpty {
            resolvedToken = storedToken
        } else {
            resolvedToken = try? await currentFCMToken()
        }

        guard let token = resolvedToken, !token.isEmpty else {
            Self.log("logout_token_cleanup_skipped", ["reason": "missing_token"])
            return
        }

        await disableAndDeleteToken(token, uid: uid)
        defaults.removeObject(forKey: lastTokenKey)
        defaults.removeObject(forKey: lastUIDKey)
    }

    func handleForegroundNotification(_ userInfo: [AnyHashable: Any]) {
        let route = DriverNotificationRoute(userInfo: userInfo)
        Self.log("foreground_notification", route.logFields)
    }

    func handleNotificationTap(_ userInfo: [AnyHashable: Any]) {
        let route = DriverNotificationRoute(userInfo: userInfo)
        Self.log("notification_tap", route.logFields)
        // Routing hook: future navigation can observe this parsed route and open the target screen.
    }

    private func saveTokenIfAuthenticated(_ token: String) async {
        guard let uid = Auth.auth().currentUser?.uid else {
            Self.log("token_save_deferred", ["reason": "missing_authenticated_user"])
            return
        }

        let previousToken = defaults.string(forKey: lastTokenKey)
        let previousUID = defaults.string(forKey: lastUIDKey)

        if let previousToken,
           let previousUID,
           (previousToken != token || previousUID != uid) {
            await disableAndDeleteToken(previousToken, uid: previousUID)
        }

        let tokenRef = db
            .collection("drivers")
            .document(uid)
            .collection("notificationTokens")
            .document(token)

        let payload: [String: Any] = [
            "uid": uid,
            "role": "driver",
            "platform": "ios",
            "app": "driver",
            "bundleId": Bundle.main.bundleIdentifier ?? "unknown",
            "apnsEnvironment": apnsEnvironment,
            "fcmToken": token,
            "enabled": true,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
            "lastSeenAt": FieldValue.serverTimestamp()
        ]

        do {
            try await setData(payload, document: tokenRef, merge: true)
            defaults.set(token, forKey: lastTokenKey)
            defaults.set(uid, forKey: lastUIDKey)
            Self.log("token_saved", ["uid": uid, "tokenPrefix": String(token.prefix(12))])
        } catch {
            Self.log("token_save_failed", ["uid": uid, "error": error.localizedDescription])
        }
    }

    private func disableAndDeleteToken(_ token: String, uid: String) async {
        let tokenRef = db
            .collection("drivers")
            .document(uid)
            .collection("notificationTokens")
            .document(token)

        do {
            try await setData([
                "enabled": false,
                "updatedAt": FieldValue.serverTimestamp()
            ], document: tokenRef, merge: true)
            try await deleteDocument(tokenRef)
            Self.log("token_deleted", ["uid": uid, "tokenPrefix": String(token.prefix(12))])
        } catch {
            Self.log("token_delete_failed", ["uid": uid, "error": error.localizedDescription])
        }
    }

    private func currentFCMToken() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            Messaging.messaging().token { token, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let token, !token.isEmpty else {
                    continuation.resume(throwing: DriverNotificationManagerError.missingToken)
                    return
                }

                continuation.resume(returning: token)
            }
        }
    }

    private var apnsTokenType: MessagingAPNSTokenType {
        switch apnsEnvironment {
        case "development": return .sandbox
        case "production": return .prod
        default: return .unknown
        }
    }

    private var apnsEnvironment: String {
        #if targetEnvironment(simulator)
        return "simulator"
        #elseif DEBUG
        return "development"
        #else
        return "production"
        #endif
    }

    private func setData(_ data: [String: Any], document: DocumentReference, merge: Bool) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            document.setData(data, merge: merge) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func deleteDocument(_ document: DocumentReference) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            document.delete { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private static func log(_ event: String, _ fields: [String: String] = [:]) {
        let details = fields
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        print("[RydrNotifications][driver] \(event)\(details.isEmpty ? "" : " \(details)")")
    }
}

private enum DriverNotificationManagerError: LocalizedError {
    case missingToken

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "Firebase Messaging did not return an FCM token."
        }
    }
}

struct DriverNotificationRoute {
    let type: String
    let target: String
    let rideId: String?
    let requestId: String?
    let chatId: String?

    init(userInfo: [AnyHashable: Any]) {
        type = Self.stringValue(userInfo["type"])
        target = Self.stringValue(userInfo["target"])
        rideId = Self.optionalStringValue(userInfo["rideId"])
        requestId = Self.optionalStringValue(userInfo["requestId"])
        chatId = Self.optionalStringValue(userInfo["chatId"])
    }

    var logFields: [String: String] {
        var fields = [
            "type": type,
            "target": target
        ]
        if let rideId { fields["rideId"] = rideId }
        if let requestId { fields["requestId"] = requestId }
        if let chatId { fields["chatId"] = chatId }
        return fields
    }

    private static func stringValue(_ value: Any?) -> String {
        optionalStringValue(value) ?? "unknown"
    }

    private static func optionalStringValue(_ value: Any?) -> String? {
        if let value = value as? String, !value.isEmpty {
            return value
        }
        if let value = value as? CustomStringConvertible {
            let description = value.description
            return description.isEmpty ? nil : description
        }
        return nil
    }
}
