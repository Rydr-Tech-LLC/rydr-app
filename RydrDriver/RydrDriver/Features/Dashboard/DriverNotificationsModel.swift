import Foundation
import FirebaseFirestore

enum DriverNotificationPriority: String, Equatable {
    case normal
    case high
    case urgent

    var sortRank: Int {
        switch self {
        case .urgent: return 3
        case .high: return 2
        case .normal: return 1
        }
    }
}

enum DriverNotificationSource: Equatable {
    case system
    case local
}

struct DriverNotificationItem: Identifiable, Equatable {
    let id: String
    let type: String
    let title: String
    let message: String
    let createdAt: Date
    var isRead: Bool
    let source: DriverNotificationSource
    let priority: DriverNotificationPriority
    let relatedId: String?

    init(
        id: String,
        type: String,
        title: String,
        message: String,
        createdAt: Date,
        isRead: Bool,
        source: DriverNotificationSource,
        priority: DriverNotificationPriority = .normal,
        relatedId: String? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.message = message
        self.createdAt = createdAt
        self.isRead = isRead
        self.source = source
        self.priority = priority
        self.relatedId = relatedId
    }

    init(document: QueryDocumentSnapshot) {
        let data = document.data()
        id = document.documentID
        type = data["type"] as? String ?? "driver_update"
        title = data["title"] as? String ?? Self.defaultTitle(for: type)
        message = data["message"] as? String ?? data["body"] as? String ?? "Open Rydr for details."
        createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
            ?? (data["updatedAt"] as? Timestamp)?.dateValue()
            ?? Date()
        isRead = data["isRead"] as? Bool ?? false
        source = .system
        priority = DriverNotificationPriority(rawValue: data["priority"] as? String ?? "normal") ?? .normal
        relatedId = data["rideId"] as? String
            ?? data["requestId"] as? String
            ?? data["penaltyId"] as? String
            ?? data["appealId"] as? String
    }

    var icon: String {
        switch type {
        case "new_ride_request": return "car.fill"
        case "missed_ride_request": return "clock.badge.exclamationmark.fill"
        case "demand_high", "demand_moderate": return "flame.fill"
        case "safety_penalty": return "exclamationmark.shield.fill"
        case "appeal_decision": return "checkmark.seal.fill"
        default: return "bell.fill"
        }
    }

    static func sort(_ lhs: DriverNotificationItem, _ rhs: DriverNotificationItem) -> Bool {
        if lhs.isRead != rhs.isRead { return !lhs.isRead }
        if lhs.priority.sortRank != rhs.priority.sortRank { return lhs.priority.sortRank > rhs.priority.sortRank }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        return lhs.id < rhs.id
    }

    private static func defaultTitle(for type: String) -> String {
        switch type {
        case "new_ride_request": return "New ride request"
        case "missed_ride_request": return "Missed ride request"
        case "demand_high": return "High demand nearby"
        case "demand_moderate": return "Demand building nearby"
        case "safety_penalty": return "Safety marker added"
        case "appeal_decision": return "Appeal decision updated"
        default: return "Driver notification"
        }
    }
}
