//
//  DriverEarningsService.swift
//  RydrDriver
//
//  Computes real fare-insights metrics (today/week/month earnings,
//  acceptance rate, completion rate, recent trips) from the driver's actual
//  `rides` and `rideRequests` documents in Firestore — replaces the
//  previously hardcoded numbers in FareInsightsView.
//

import Foundation
import FirebaseFirestore

struct DriverRecentTrip: Identifiable {
    let id: String
    let pickup: String
    let dropoff: String
    let fare: Decimal
    let completedAt: Date?
}

struct DriverEarningsSummary {
    var todayEarnings: Decimal = 0
    var weekEarnings: Decimal = 0
    var monthEarnings: Decimal = 0
    /// nil until there's at least one decided (accepted/declined/missed) request to measure.
    var acceptanceRate: Double?
    /// nil until there's at least one accepted request to measure against.
    var completionRate: Double?
    var recentTrips: [DriverRecentTrip] = []

    static let empty = DriverEarningsSummary()
}

@MainActor
final class DriverEarningsService {
    static let shared = DriverEarningsService()

    private init() {}

    /// Pulls the driver's completed rides (capped at the most recent 200, which
    /// comfortably covers a rolling month for any active driver) plus their
    /// most recent ride requests, and derives every Fare Insights metric from
    /// that real data — no placeholder numbers.
    func fetchSummary(uid: String) async throws -> DriverEarningsSummary {
        let db = Firestore.firestore()

        async let ridesQuery = db.collection("rides")
            .whereField("driverId", isEqualTo: uid)
            .whereField("status", isEqualTo: "completed")
            .order(by: "updatedAt", descending: true)
            .limit(to: 200)
            .getDocuments()

        async let requestsQuery = db.collection("rideRequests")
            .whereField("driverId", isEqualTo: uid)
            .limit(to: 200)
            .getDocuments()

        let (ridesSnapshot, requestsSnapshot) = try await (ridesQuery, requestsQuery)

        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? startOfToday
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? startOfToday

        var summary = DriverEarningsSummary()
        var trips: [DriverRecentTrip] = []

        for document in ridesSnapshot.documents {
            let data = document.data()
            let fare = Self.decimal(data["fare"] ?? data["finalFare"] ?? data["estimatedFare"]) ?? 0
            let completedAt = Self.date(data["completedAt"]) ?? Self.date(data["updatedAt"])

            if let completedAt {
                if completedAt >= startOfMonth { summary.monthEarnings += fare }
                if completedAt >= startOfWeek { summary.weekEarnings += fare }
                if completedAt >= startOfToday { summary.todayEarnings += fare }
            }

            trips.append(DriverRecentTrip(
                id: document.documentID,
                pickup: data["pickup"] as? String ?? "Pickup",
                dropoff: data["dropoff"] as? String ?? "Drop-off",
                fare: fare,
                completedAt: completedAt
            ))
        }

        summary.recentTrips = Array(trips.prefix(5))

        var accepted = 0
        var declinedOrMissed = 0
        for document in requestsSnapshot.documents {
            let status = (document.data()["status"] as? String ?? "").lowercased()
            switch status {
            case "accepted":
                accepted += 1
            case "declined", "missed":
                declinedOrMissed += 1
            default:
                break
            }
        }

        let decided = accepted + declinedOrMissed
        if decided > 0 {
            summary.acceptanceRate = Double(accepted) / Double(decided)
        }
        if accepted > 0 {
            // Completed-ride count is the real-data proxy for "of the rides you
            // accepted, how many did you actually finish" since rideRequests
            // never transitions to "completed" itself (only the rides doc does).
            summary.completionRate = min(1, Double(ridesSnapshot.documents.count) / Double(accepted))
        }

        return summary
    }

    private static func decimal(_ value: Any?) -> Decimal? {
        if let value = value as? Decimal { return value }
        if let value = value as? Double { return Decimal(value) }
        if let value = value as? Int { return Decimal(value) }
        if let value = value as? NSNumber { return value.decimalValue }
        if let value = value as? String { return Decimal(string: value) }
        return nil
    }

    private static func date(_ value: Any?) -> Date? {
        if let timestamp = value as? Timestamp { return timestamp.dateValue() }
        if let date = value as? Date { return date }
        return nil
    }
}
