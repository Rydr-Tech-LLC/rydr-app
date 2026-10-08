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

        var payload: [String: Any] = [
            "category": draft.category,
            "issueType": draft.issueType,
            "subject": subject.isEmpty ? draft.issueType : subject,
            "description": description,
            "status": "open",
            "priority": draft.priority,
            "contactPreference": draft.contactPreference
        ]
        if let rideId = normalizedOptional(draft.rideId) {
            payload["rideId"] = rideId
        }

        let response = try await backend(path: "/support/tickets", body: payload)
        guard let ticketId = response["ticketId"] as? String else { throw SupportTicketServiceError.missingTicket }

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

        _ = try await backend(path: "/support/tickets/\(ticketId)/message", body: ["text": trimmed])
    }

    func createCallRequest(_ draft: SupportCallRequestDraft) async throws -> String {
        _ = try currentUserId()
        let phoneNumber = draft.phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phoneNumber.isEmpty else { throw SupportTicketServiceError.emptyPhoneNumber }

        var payload: [String: Any] = [
            "topic": draft.topic,
            "preferredDate": ISO8601DateFormatter().string(from: draft.preferredDate),
            "preferredTimeWindow": draft.preferredTimeWindow,
            "phoneNumber": phoneNumber,
            "notes": draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        ]
        if let rideId = normalizedOptional(draft.rideId) {
            payload["rideId"] = rideId
        }

        let response = try await backend(path: "/support/call-requests", body: payload)
        guard let requestId = response["requestId"] as? String else { throw SupportTicketServiceError.missingTicket }
        return requestId
    }

    func closeTicket(ticketId: String) async throws {
        let userId = try currentUserId()
        let ticketRef = db.collection("supportTickets").document(ticketId)
        let snapshot = try await getDocument(ticketRef)
        guard snapshot.exists else { throw SupportTicketServiceError.missingTicket }
        try validateTicket(snapshot: snapshot, userId: userId)

        _ = try await backend(path: "/support/tickets/\(ticketId)/close", body: [:])
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

    private func backend(path: String, body: [String: Any]) async throws -> [String: Any] {
        guard let raw=Bundle.main.object(forInfoDictionaryKey:"RYDR_BACKEND_BASE_URL") as? String,let base=URL(string:raw),let url=URL(string:path,relativeTo:base),let user=Auth.auth().currentUser else{throw SupportTicketServiceError.notSignedIn}
        var request=URLRequest(url:url);request.httpMethod="POST";request.setValue("application/json",forHTTPHeaderField:"Content-Type");request.setValue("Bearer \(try await user.getIDToken())",forHTTPHeaderField:"Authorization");request.httpBody=try JSONSerialization.data(withJSONObject:body)
        let(data,response)=try await URLSession.shared.data(for:request);guard let http=response as? HTTPURLResponse,(200..<300).contains(http.statusCode) else{throw NSError(domain:"SupportTicketService",code:(response as? HTTPURLResponse)?.statusCode ?? -1,userInfo:[NSLocalizedDescriptionKey:"Support request failed."])}
        return (try JSONSerialization.jsonObject(with:data) as? [String:Any]) ?? [:]
    }
}
