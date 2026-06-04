//
//  RideChatService.swift
//  RydrPlayground
//
//  Firestore-backed rider-driver chat for active rides.
//

import Foundation
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
        let snapshot = try await getDocument(chatRef)
        var data: [String: Any] = [
            "rideId": rideId,
            "riderId": riderId,
            "driverId": driverId,
            "status": "active",
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if snapshot.exists {
            try validateChat(snapshot: snapshot, riderId: riderId, driverId: driverId)
        } else {
            data["createdAt"] = FieldValue.serverTimestamp()
        }
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
                let messages = (snapshot?.documents ?? []).compactMap(Self.makeMessage)
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
        try await addData([
            "senderId": senderId,
            "senderRole": senderRole,
            "text": trimmed,
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

    private static func makeMessage(from document: QueryDocumentSnapshot) -> ChatMessage? {
        let data = document.data()
        guard let senderId = data["senderId"] as? String,
              let senderRole = data["senderRole"] as? String,
              let text = data["text"] as? String else {
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
