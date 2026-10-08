//
//  DriverRideTierCatalog.swift
//  Rydr Driver
//
//  Shared display names and driver-entered rate-card values. Vehicle
//  eligibility and suggested prices are resolved by the backend.
//

import Foundation

enum RydrRideTierCatalog {
    nonisolated static var orderedRideTypes: [String] {
        ["Rydr Go", "Rydr Eco", "Rydr XL", "Rydr Prestine", "Rydr Executive"]
    }

    nonisolated static func metadata(for rideType: String) -> RydrRideTierMetadata {
        switch canonicalRideType(rideType) {
        case "eco":
            return .init(
                title: "Rydr Eco",
                purpose: "Electric and environmentally conscious transportation."
            )
        case "xl":
            return .init(
                title: "Rydr XL",
                purpose: "Groups, larger parties, and luggage."
            )
        case "prestine":
            return .init(
                title: "Rydr Prestine",
                purpose: "Premium transportation with elevated vehicle standards."
            )
        case "executive":
            return .init(
                title: "Rydr Executive",
                purpose: "More Than A Ride. An Arrival."
            )
        default:
            return .init(
                title: "Rydr Go",
                purpose: "Affordable everyday transportation."
            )
        }
    }

    nonisolated static func canonicalRideType(_ rideType: String) -> String {
        let key = rideType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if key == "rydr" || key == "rydr go" || key == "go" { return "go" }
        if key == "rydr eco" || key == "eco" { return "eco" }
        if key == "rydr xl" || key == "xl" { return "xl" }
        if key == "rydr prestine" || key == "rydr pristine" || key == "prestine" || key == "pristine" { return "prestine" }
        if key == "rydr executive" || key == "executive" { return "executive" }
        return key
    }

    nonisolated static func normalizedRideTypes(_ rideTypes: [String]) -> [String] {
        let canonical = Set(rideTypes.map(canonicalRideType))
        return orderedRideTypes.filter { canonical.contains(canonicalRideType($0)) }
    }

}

struct RydrRideTierMetadata {
    let title: String
    let purpose: String
}

struct DriverRateSetting: Equatable {
    var minimumFare: Double
    var perMile: Double
    var perMinute: Double
    var useSuggestedPricing: Bool

    func dictionary(for rideType: String) -> [String: Any] {
        return [
            "minimumFare": max(0, minimumFare).currencyRounded,
            "perMile": max(0, perMile).currencyRounded,
            "perMinute": max(0, perMinute).currencyRounded,
            "useSuggestedPricing": useSuggestedPricing
        ]
    }

    static var empty: DriverRateSetting {
        return DriverRateSetting(
            minimumFare: 0,
            perMile: 0,
            perMinute: 0,
            useSuggestedPricing: false
        )
    }
}

private extension Double {
    var currencyRounded: Double { (self * 100).rounded() / 100 }
}

enum DriverVehicleFuelType: String, CaseIterable, Identifiable {
    case gas = "Gas"
    case hybrid = "Hybrid"
    case electric = "Electric"

    var id: String { rawValue }

    /// Maps NHTSA's free-text `FuelTypePrimary` (e.g. "Gasoline",
    /// "Flexible Fuel Vehicle (FFV)", "Electric", "Compressed Natural Gas
    /// (CNG)") onto our three-way eligibility fuel type. Used when a
    /// vehicle's fuel type comes from a VIN decode instead of manual entry
    /// — see VehicleInfoView's VIN decode flow.
    static func fromNHTSA(_ raw: String?) -> DriverVehicleFuelType {
        guard let raw else { return .gas }
        let normalized = raw.lowercased()
        if normalized.contains("electric") { return .electric }
        if normalized.contains("hybrid") { return .hybrid }
        return .gas
    }
}
