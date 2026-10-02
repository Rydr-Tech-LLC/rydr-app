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
        _ = uid
        let value = try await RydrBackendService.fetchDriverEarningsSummary()
        let formatter = ISO8601DateFormatter()
        return DriverEarningsSummary(
            todayEarnings: Decimal(value.todayCents) / 100,
            weekEarnings: Decimal(value.weekCents) / 100,
            monthEarnings: Decimal(value.monthCents) / 100,
            acceptanceRate: value.acceptanceRate,
            completionRate: value.completionRate,
            recentTrips: value.recentTrips.map { .init(id:$0.id,pickup:$0.pickup,dropoff:$0.dropoff,fare:Decimal($0.fareCents)/100,completedAt:$0.completedAt.flatMap(formatter.date)) }
        )
    }

    private static func decimal(_ value: Any?) -> Decimal? {
        if let value = value as? Decimal { return value }
        if let value = value as? Double { return Decimal(value) }
        if let value = value as? Int { return Decimal(value) }
        if let value = value as? NSNumber { return value.decimalValue }
        if let value = value as? String { return Decimal(string: value) }
        return nil
    }

    private static func dollarsFromCents(_ value: Any?) -> Decimal? {
        guard let cents = decimal(value) else { return nil }
        return cents / 100
    }

    private static func date(_ value: Any?) -> Date? {
        if let timestamp = value as? Timestamp { return timestamp.dateValue() }
        if let date = value as? Date { return date }
        return nil
    }
}
