//
//  DriverRideChatService.swift
//  RydrDriver
//
//  Firestore-backed encrypted ride chat for active driver-rider trips.
//

import Foundation
import CryptoKit
import FirebaseAuth
import FirebaseFirestore

typealias DriverRideChatListener = ListenerRegistration

struct DriverRideChatMessage: Identifiable, Equatable {
    let id: String
    let senderId: String
    let senderRole: String
    let text: String
    let createdAt: Date
    var isPrivateDriverNote: Bool = false
}

enum DriverRideChatError: LocalizedError {
    case notSignedIn
    case unauthorized
    case missingChat

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Sign in before using ride chat."
        case .unauthorized:
            return "You do not have access to this ride chat."
        case .missingChat:
            return "This ride chat could not be found."
        }
    }
}

final class DriverRideChatService {
    private let db = Firestore.firestore()

    func createOrInitializeChat(rideId: String, riderId: String, driverId: String) async throws {
        try requireParticipant(riderId: riderId, driverId: driverId)

        let chatRef = db.collection("rideChats").document(rideId)
        let data: [String: Any] = [
            "rideId": rideId,
            "riderId": riderId,
            "driverId": driverId,
            "participants": [riderId, driverId].sorted(),
            "status": "active",
            "updatedAt": FieldValue.serverTimestamp()
        ]
        try await setData(data, document: chatRef, merge: true)
    }

    func listenToMessages(
        rideId: String,
        riderId: String,
        driverId: String,
        onChange: @escaping (Result<[DriverRideChatMessage], Error>) -> Void
    ) async throws -> ListenerRegistration {
        try requireParticipant(riderId: riderId, driverId: driverId)

        let chatRef = db.collection("rideChats").document(rideId)
        let snapshot = try await getDocument(chatRef)
        guard snapshot.exists else { throw DriverRideChatError.missingChat }
        try validateChat(snapshot: snapshot, riderId: riderId, driverId: driverId)

        return chatRef
            .collection("messages")
            .order(by: "createdAt", descending: false)
            .addSnapshotListener { snapshot, error in
                if let error {
                    onChange(.failure(error))
                    return
                }
                let messages = (snapshot?.documents ?? []).compactMap {
                    Self.makeMessage(from: $0, rideId: rideId, riderId: riderId, driverId: driverId)
                }
                onChange(.success(messages))
            }
    }

    func stopListening(_ listener: DriverRideChatListener?) {
        listener?.remove()
    }

    func listenToDriverPrivateMessages(
        rideId: String,
        riderId: String,
        driverId: String,
        onChange: @escaping (Result<[DriverRideChatMessage], Error>) -> Void
    ) async throws -> ListenerRegistration {
        try requireDriver(driverId: driverId)

        let chatRef = db.collection("rideChats").document(rideId)
        let snapshot = try await getDocument(chatRef)
        guard snapshot.exists else { throw DriverRideChatError.missingChat }
        try validateChat(snapshot: snapshot, riderId: riderId, driverId: driverId)

        return chatRef
            .collection("driverPrivateMessages")
            .order(by: "createdAt", descending: false)
            .addSnapshotListener { snapshot, error in
                if let error {
                    onChange(.failure(error))
                    return
                }
                let messages = (snapshot?.documents ?? []).compactMap { Self.makePrivateMessage(from: $0, driverId: driverId) }
                onChange(.success(messages))
            }
    }

    func addDriverPrivatePreferenceNote(
        rideId: String,
        riderId: String,
        driverId: String,
        summaryText: String
    ) async throws {
        try requireDriver(driverId: driverId)
        let trimmed = summaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try await createOrInitializeChat(rideId: rideId, riderId: riderId, driverId: driverId)
        try await addData([
            "senderId": driverId,
            "senderRole": "system",
            "text": "Rider preferences:\n\(trimmed)",
            "visibility": "driverOnly",
            "createdAt": FieldValue.serverTimestamp()
        ], collection: db.collection("rideChats").document(rideId).collection("driverPrivateMessages"))
    }

    @discardableResult
    private func requireParticipant(riderId: String, driverId: String) throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw DriverRideChatError.notSignedIn
        }
        guard uid == riderId || uid == driverId else {
            throw DriverRideChatError.unauthorized
        }
        return uid
    }

    @discardableResult
    private func requireDriver(driverId: String) throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw DriverRideChatError.notSignedIn
        }
        guard uid == driverId else {
            throw DriverRideChatError.unauthorized
        }
        return uid
    }

    @discardableResult
    private func validateChat(snapshot: DocumentSnapshot, riderId: String, driverId: String) throws -> [String: Any] {
        let data = snapshot.data() ?? [:]
        guard (data["riderId"] as? String) == riderId,
              (data["driverId"] as? String) == driverId else {
            throw DriverRideChatError.unauthorized
        }
        return data
    }

    private static func makeMessage(
        from document: QueryDocumentSnapshot,
        rideId: String,
        riderId: String,
        driverId: String
    ) -> DriverRideChatMessage? {
        let data = document.data()
        guard let senderId = data["senderId"] as? String,
              let senderRole = data["senderRole"] as? String else {
            return nil
        }

        let text: String
        if let ciphertext = data["ciphertext"] as? String,
           let nonce = data["nonce"] as? String {
            text = DriverRideChatCrypto.decryptBestEffort(
                ciphertext: ciphertext,
                nonce: nonce,
                rideId: rideId,
                riderId: riderId,
                driverId: driverId
            ) ?? "Encrypted message unavailable"
        } else if let legacyText = data["text"] as? String {
            text = legacyText
        } else {
            return nil
        }

        return DriverRideChatMessage(
            id: document.documentID,
            senderId: senderId,
            senderRole: senderRole,
            text: text,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        )
    }

    private static func makePrivateMessage(from document: QueryDocumentSnapshot, driverId: String) -> DriverRideChatMessage? {
        let data = document.data()
        guard let text = data["text"] as? String else { return nil }
        return DriverRideChatMessage(
            id: "driver-private-\(document.documentID)",
            senderId: data["senderId"] as? String ?? driverId,
            senderRole: data["senderRole"] as? String ?? "system",
            text: text,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
            isPrivateDriverNote: true
        )
    }

    private func getDocument(_ document: DocumentReference) async throws -> DocumentSnapshot {
        try await withCheckedThrowingContinuation { continuation in
            document.getDocument { snapshot, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let snapshot {
                    continuation.resume(returning: snapshot)
                } else {
                    continuation.resume(throwing: DriverRideChatError.missingChat)
                }
            }
        }
    }

    private func setData(_ data: [String: Any], document: DocumentReference, merge: Bool) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            document.setData(data, merge: merge) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func addData(_ data: [String: Any], collection: CollectionReference) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            collection.addDocument(data: data) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}

struct DriverEncryptedRideMessage {
    let ciphertext: String
    let nonce: String
    let algorithm: String
    let keyVersion: Int
    let recipientKeyIds: [String]
}

enum DriverRideChatCrypto {
    static func encrypt(_ plaintext: String, rideId: String, riderId: String, driverId: String) throws -> DriverEncryptedRideMessage {
        let nonce = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(Data(plaintext.utf8), using: chatKey(rideId: rideId, riderId: riderId, driverId: driverId), nonce: nonce)
        guard let combined = sealedBox.combined else {
            throw DriverRideChatError.missingChat
        }
        return DriverEncryptedRideMessage(
            ciphertext: combined.base64EncodedString(),
            nonce: Data(nonce).base64EncodedString(),
            algorithm: "AES.GCM.v1",
            keyVersion: 1,
            recipientKeyIds: [riderId, driverId].sorted()
        )
    }

    static func decryptBestEffort(ciphertext: String, nonce: String, rideId: String, riderId: String, driverId: String) -> String? {
        guard let combined = Data(base64Encoded: ciphertext),
              Data(base64Encoded: nonce) != nil,
              let sealedBox = try? AES.GCM.SealedBox(combined: combined),
              let opened = try? AES.GCM.open(sealedBox, using: chatKey(rideId: rideId, riderId: riderId, driverId: driverId)) else {
            return nil
        }
        return String(data: opened, encoding: .utf8)
    }

    private static func chatKey(rideId: String, riderId: String, driverId: String) -> SymmetricKey {
        let material = "rydr-chat-v1|\(rideId)|\(riderId)|\(driverId)"
        return SymmetricKey(data: SHA256.hash(data: Data(material.utf8)))
    }
}
