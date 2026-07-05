//
//  RideChatService.swift
//  RydrPlayground
//
//  Firestore-backed rider-driver chat for active rides.
//

import Foundation
import CryptoKit
import FirebaseAuth
import FirebaseFirestore

struct RideChat: Identifiable, Equatable {
    let id: String
    let rideId: String
    let riderId: String
    let driverId: String
    let status: String
    let createdAt: Date?
    let updatedAt: Date?
}

struct ChatMessage: Identifiable, Equatable {
    let id: String
    let senderId: String
    let senderRole: String
    let text: String
    let createdAt: Date
    let isRead: Bool
}

enum RideChatServiceError: LocalizedError {
    case notSignedIn
    case unauthorized
    case emptyMessage
    case closed
    case missingChat

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "You must be signed in to use ride chat."
        case .unauthorized:
            return "You do not have access to this ride chat."
        case .emptyMessage:
            return "Enter a message first."
        case .closed:
            return "This ride chat is closed."
        case .missingChat:
            return "This ride chat could not be found."
        }
    }
}

final class RideChatService {
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
        onChange: @escaping (Result<[ChatMessage], Error>) -> Void
    ) async throws -> ListenerRegistration {
        try requireParticipant(riderId: riderId, driverId: driverId)

        let chatRef = db.collection("rideChats").document(rideId)
        let snapshot = try await getDocument(chatRef)
        guard snapshot.exists else { throw RideChatServiceError.missingChat }
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

    func sendMessage(rideId: String, riderId: String, driverId: String, text: String) async throws {
        let senderId = try requireParticipant(riderId: riderId, driverId: driverId)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RideChatServiceError.emptyMessage }

        let chatRef = db.collection("rideChats").document(rideId)
        let chatSnapshot = try await getDocument(chatRef)
        guard chatSnapshot.exists else { throw RideChatServiceError.missingChat }
        let data = try validateChat(snapshot: chatSnapshot, riderId: riderId, driverId: driverId)
        guard (data["status"] as? String) != "closed" else {
            throw RideChatServiceError.closed
        }

        let senderRole = senderId == riderId ? "rider" : "driver"
        let encrypted = try RideChatCrypto.encrypt(trimmed, rideId: rideId, riderId: riderId, driverId: driverId)
        try await addData([
            "senderId": senderId,
            "senderRole": senderRole,
            "ciphertext": encrypted.ciphertext,
            "nonce": encrypted.nonce,
            "algorithm": encrypted.algorithm,
            "keyVersion": encrypted.keyVersion,
            "recipientKeyIds": encrypted.recipientKeyIds,
            "createdAt": FieldValue.serverTimestamp(),
            "isRead": false
        ], collection: chatRef.collection("messages"))

        try await setData([
            "updatedAt": FieldValue.serverTimestamp()
        ], document: chatRef, merge: true)
    }

    func closeChat(rideId: String, riderId: String, driverId: String) async throws {
        try requireParticipant(riderId: riderId, driverId: driverId)

        let chatRef = db.collection("rideChats").document(rideId)
        let snapshot = try await getDocument(chatRef)
        guard snapshot.exists else { return }
        _ = try validateChat(snapshot: snapshot, riderId: riderId, driverId: driverId)

        try await setData([
            "status": "closed",
            "updatedAt": FieldValue.serverTimestamp()
        ], document: chatRef, merge: true)
    }

    @discardableResult
    private func requireParticipant(riderId: String, driverId: String) throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw RideChatServiceError.notSignedIn
        }
        guard uid == riderId || uid == driverId else {
            throw RideChatServiceError.unauthorized
        }
        return uid
    }

    @discardableResult
    private func validateChat(snapshot: DocumentSnapshot, riderId: String, driverId: String) throws -> [String: Any] {
        let data = snapshot.data() ?? [:]
        guard (data["riderId"] as? String) == riderId,
              (data["driverId"] as? String) == driverId else {
            throw RideChatServiceError.unauthorized
        }
        return data
    }

    private static func makeMessage(
        from document: QueryDocumentSnapshot,
        rideId: String,
        riderId: String,
        driverId: String
    ) -> ChatMessage? {
        let data = document.data()
        guard let senderId = data["senderId"] as? String,
              let senderRole = data["senderRole"] as? String else {
            return nil
        }
        let text: String
        if let ciphertext = data["ciphertext"] as? String,
           let nonce = data["nonce"] as? String {
            text = RideChatCrypto.decryptBestEffort(
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
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        return ChatMessage(
            id: document.documentID,
            senderId: senderId,
            senderRole: senderRole,
            text: text,
            createdAt: createdAt,
            isRead: data["isRead"] as? Bool ?? false
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
                    continuation.resume(throwing: RideChatServiceError.missingChat)
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

private struct EncryptedRideMessage {
    let ciphertext: String
    let nonce: String
    let algorithm: String
    let keyVersion: Int
    let recipientKeyIds: [String]
}

private enum RideChatCrypto {
    static func encrypt(_ plaintext: String, rideId: String, riderId: String, driverId: String) throws -> EncryptedRideMessage {
        let nonce = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(Data(plaintext.utf8), using: chatKey(rideId: rideId, riderId: riderId, driverId: driverId), nonce: nonce)
        guard let combined = sealedBox.combined else {
            throw RideChatServiceError.emptyMessage
        }
        return EncryptedRideMessage(
            ciphertext: combined.base64EncodedString(),
            nonce: Data(nonce).base64EncodedString(),
            algorithm: "AES.GCM.v1",
            keyVersion: 1,
            recipientKeyIds: [riderId, driverId].sorted()
        )
    }

    static func decryptBestEffort(ciphertext: String, nonce: String, rideId: String, riderId: String, driverId: String) -> String? {
        guard let combined = Data(base64Encoded: ciphertext),
              Data(base64Encoded: nonce) != nil else {
            return nil
        }

        guard let sealedBox = try? AES.GCM.SealedBox(combined: combined),
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
