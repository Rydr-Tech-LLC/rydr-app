//
//  SupportTicketService.swift
//  RydrPlayground
//
//  Firestore-backed support tickets, support chat messages, and callback requests.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

struct SupportTicket: Identifiable, Equatable, Hashable {
    let id: String
    let ticketId: String
    let userId: String
    let userRole: String
    let rideId: String?
    let category: String
    let issueType: String
    let subject: String
    let description: String
    let status: String
    let priority: String
    let contactPreference: String
    let createdAt: Date?
    let updatedAt: Date?
}

struct SupportMessage: Identifiable, Equatable {
    let id: String
    let senderId: String
    let senderRole: String
    let text: String
    let createdAt: Date
    let isRead: Bool
}

struct SupportTicketDraft {
    var rideId: String?
    var category: String
    var issueType: String
    var subject: String
    var description: String
    var priority: String = "normal"
    var contactPreference: String = "chat"
}

struct SupportCallRequestDraft {
    var rideId: String?
    var topic: String
    var preferredDate: Date
    var preferredTimeWindow: String
    var phoneNumber: String
    var notes: String
}

enum SupportTicketServiceError: LocalizedError {
    case notSignedIn
    case emptyDescription
    case emptyMessage
    case emptyPhoneNumber
    case missingTicket
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Please sign in to contact Rydr support."
        case .emptyDescription:
            return "Tell us what happened so we can review your request."
        case .emptyMessage:
            return "Enter a message first."
        case .emptyPhoneNumber:
            return "Enter a phone number for the callback request."
        case .missingTicket:
            return "This support ticket could not be found."
        case .unauthorized:
            return "You do not have access to this support request."
        }
    }
}

final class SupportTicketService {
    private let db = Firestore.firestore()

    func createTicket(_ draft: SupportTicketDraft) async throws -> SupportTicket {
        let userId = try currentUserId()
        let subject = draft.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else { throw SupportTicketServiceError.emptyDescription }

        let ticketRef = db.collection("supportTickets").document()
        let ticketId = ticketRef.documentID
        var payload: [String: Any] = [
            "ticketId": ticketId,
            "userId": userId,
            "userRole": "rider",
            "category": draft.category,
            "issueType": draft.issueType,
            "subject": subject.isEmpty ? draft.issueType : subject,
            "description": description,
            "status": "open",
            "priority": draft.priority,
            "contactPreference": draft.contactPreference,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let rideId = normalizedOptional(draft.rideId) {
            payload["rideId"] = rideId
        }

        try await setData(payload, document: ticketRef, merge: false)

        try await addData([
            "senderId": userId,
            "senderRole": "rider",
            "text": description,
            "createdAt": FieldValue.serverTimestamp(),
            "isRead": false
        ], collection: ticketRef.collection("messages"))

        return SupportTicket(
            id: ticketId,
            ticketId: ticketId,
            userId: userId,
            userRole: "rider",
            rideId: normalizedOptional(draft.rideId),
            category: draft.category,
            issueType: draft.issueType,
            subject: subject.isEmpty ? draft.issueType : subject,
            description: description,
            status: "open",
            priority: draft.priority,
            contactPreference: draft.contactPreference,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    func listenToTicketMessages(
        ticketId: String,
        onChange: @escaping (Result<[SupportMessage], Error>) -> Void
    ) async throws -> ListenerRegistration {
        let userId = try currentUserId()
        let ticketRef = db.collection("supportTickets").document(ticketId)
        let snapshot = try await getDocument(ticketRef)
        guard snapshot.exists else { throw SupportTicketServiceError.missingTicket }
        try validateTicket(snapshot: snapshot, userId: userId)

        return ticketRef
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

    func sendMessage(ticketId: String, text: String) async throws {
        let userId = try currentUserId()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SupportTicketServiceError.emptyMessage }

        let ticketRef = db.collection("supportTickets").document(ticketId)
        let snapshot = try await getDocument(ticketRef)
        guard snapshot.exists else { throw SupportTicketServiceError.missingTicket }
        try validateTicket(snapshot: snapshot, userId: userId)

        try await addData([
            "senderId": userId,
            "senderRole": "rider",
            "text": trimmed,
            "createdAt": FieldValue.serverTimestamp(),
            "isRead": false
        ], collection: ticketRef.collection("messages"))

        try await setData([
            "status": "open",
            "updatedAt": FieldValue.serverTimestamp()
        ], document: ticketRef, merge: true)
    }

    func createCallRequest(_ draft: SupportCallRequestDraft) async throws -> String {
        let userId = try currentUserId()
        let phoneNumber = draft.phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phoneNumber.isEmpty else { throw SupportTicketServiceError.emptyPhoneNumber }

        let requestRef = db.collection("supportCallRequests").document()
        let requestId = requestRef.documentID
        var payload: [String: Any] = [
            "requestId": requestId,
            "userId": userId,
            "userRole": "rider",
            "topic": draft.topic,
            "preferredDate": Timestamp(date: draft.preferredDate),
            "preferredTimeWindow": draft.preferredTimeWindow,
            "phoneNumber": phoneNumber,
            "notes": draft.notes.trimmingCharacters(in: .whitespacesAndNewlines),
            "status": "requested",
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let rideId = normalizedOptional(draft.rideId) {
            payload["rideId"] = rideId
        }

        try await setData(payload, document: requestRef, merge: false)
        return requestId
    }

    func closeTicket(ticketId: String) async throws {
        let userId = try currentUserId()
        let ticketRef = db.collection("supportTickets").document(ticketId)
        let snapshot = try await getDocument(ticketRef)
        guard snapshot.exists else { throw SupportTicketServiceError.missingTicket }
        try validateTicket(snapshot: snapshot, userId: userId)

        try await setData([
            "status": "closed",
            "updatedAt": FieldValue.serverTimestamp()
        ], document: ticketRef, merge: true)
    }

    private func currentUserId() throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw SupportTicketServiceError.notSignedIn
        }
        return uid
    }

    private func normalizedOptional(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func validateTicket(snapshot: DocumentSnapshot, userId: String) throws {
        let data = snapshot.data() ?? [:]
        guard (data["userId"] as? String) == userId,
              (data["userRole"] as? String) == "rider" else {
            throw SupportTicketServiceError.unauthorized
        }
    }

    private static func makeMessage(from document: QueryDocumentSnapshot) -> SupportMessage? {
        let data = document.data()
        guard let senderId = data["senderId"] as? String,
              let senderRole = data["senderRole"] as? String,
              let text = data["text"] as? String else {
            return nil
        }

        return SupportMessage(
            id: document.documentID,
            senderId: senderId,
            senderRole: senderRole,
            text: text,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
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
                    continuation.resume(throwing: SupportTicketServiceError.missingTicket)
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
