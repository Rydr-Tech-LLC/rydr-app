//
//  DriverVehicleEligibility.swift
//  Rydr Driver
//
//  Determines which standard Rydr ride types a driver's vehicle can receive.
//

import Foundation

enum RydrRideTierCatalog {
    nonisolated static var orderedRideTypes: [String] {
        ["Rydr Go", "Rydr Eco", "Rydr XL", "Rydr Prestine", "Rydr Executive"]
    }

    nonisolated static func pricing(for rideType: String) -> RydrDriverTierPricing {
        switch canonicalRideType(rideType) {
        case "eco":
            return .init(
                title: "Rydr Eco",
                purpose: "Electric and environmentally conscious transportation.",
                suggestedPerMile: 1.10,
                suggestedPerMinute: 0.25
            )
        case "xl":
            return .init(
                title: "Rydr XL",
                purpose: "Groups, larger parties, and luggage.",
                suggestedPerMile: 1.25,
                suggestedPerMinute: 0.25
            )
        case "prestine":
            return .init(
                title: "Rydr Prestine",
                purpose: "Premium transportation with elevated vehicle standards.",
                suggestedPerMile: 1.50,
                suggestedPerMinute: 0.35
            )
        case "executive":
            return .init(
                title: "Rydr Executive",
                purpose: "More Than A Ride. An Arrival.",
                suggestedPerMile: 2.00,
                suggestedPerMinute: 0.50
            )
        default:
            return .init(
                title: "Rydr Go",
                purpose: "Affordable everyday transportation.",
                suggestedPerMile: 1.00,
                suggestedPerMinute: 0.25
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

    nonisolated static func expandedRideTypes(for approvedRideTypes: [String], hasXLVehicle: Bool) -> [String] {
        var expanded = Set(normalizedRideTypes(approvedRideTypes))
        if expanded.contains("Rydr Executive") {
            expanded.insert("Rydr Prestine")
            expanded.insert("Rydr Go")
            if hasXLVehicle { expanded.insert("Rydr XL") }
        }
        if expanded.contains("Rydr Prestine") {
            expanded.insert("Rydr Go")
            if hasXLVehicle { expanded.insert("Rydr XL") }
        }
        return orderedRideTypes.filter { expanded.contains($0) }
    }
}

struct RydrDriverTierPricing {
    let title: String
    let purpose: String
    let suggestedPerMile: Double
    let suggestedPerMinute: Double
    let suggestedMinimumFare: Double = 7.00

    func suggestedRates(for demand: DriverDemandLevel) -> DriverRateSetting {
        let adjustment: Double
        switch demand {
        case .low: adjustment = -0.10
        case .moderate: adjustment = 0.10
        case .high: adjustment = 0.20
        }
        return DriverRateSetting(
            minimumFare: suggestedMinimumFare,
            perMile: max(0, suggestedPerMile + adjustment),
            perMinute: max(0, suggestedPerMinute + adjustment),
            useSuggestedPricing: true
        )
    }
}

struct DriverRateSetting {
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

    static func defaultValue(for rideType: String) -> DriverRateSetting {
        let pricing = RydrRideTierCatalog.pricing(for: rideType)
        return DriverRateSetting(
            minimumFare: pricing.suggestedMinimumFare,
            perMile: pricing.suggestedPerMile,
            perMinute: pricing.suggestedPerMinute,
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

struct DriverVehicleEligibility {
    let make: String
    let model: String
    let year: Int?
    let fuelType: DriverVehicleFuelType

    var eligibleRideTypes: [String] {
        var rideTypes: [String] = []

        if isGoEligible {
            rideTypes.append("Rydr Go")
        }

        if fuelType == .electric {
            rideTypes.append("Rydr Eco")
        }

        if isXLEligible {
            rideTypes.append("Rydr XL")
        }

        return rideTypes
    }

    func expandedEligibleRideTypes(with approvedRideTypes: [String]) -> [String] {
        RydrRideTierCatalog.expandedRideTypes(
            for: eligibleRideTypes + approvedRideTypes,
            hasXLVehicle: isXLEligible
        )
    }

    var vehicleClass: String {
        if fuelType == .electric { return "electric" }
        if isXLEligible { return "xl" }
        if isGoEligible { return "go" }
        return "manual_review"
    }

    var requiresManualReview: Bool {
        eligibleRideTypes.isEmpty
    }

    static func vehicleClass(for rideTypes: [String]) -> String {
        let canonical = Set(rideTypes.map(RydrRideTierCatalog.canonicalRideType))
        if canonical.contains("Rydr XL") { return "xl" }
        if canonical.contains("Rydr Eco") { return "electric" }
        if canonical.contains("Rydr Go") { return "go" }
        return "manual_review"
    }

    private var normalizedMake: String {
        Self.normalized(make)
    }

    private var normalizedModel: String {
        Self.normalized(model)
    }

    private var isGoEligible: Bool {
        fuelType == .electric ||
        Self.goEligibleMakes.contains(normalizedMake) ||
        Self.goEligibleModelFragments.contains(where: { normalizedModel.contains($0) })
    }

    private var isXLEligible: Bool {
        Self.xlModelFragments.contains(where: { normalizedModel.contains($0) })
    }

    static func evaluate(make: String, model: String, year: String, fuelType: String) -> DriverVehicleEligibility {
        DriverVehicleEligibility(
            make: make,
            model: model,
            year: Int(year.filter(\.isNumber)),
            fuelType: DriverVehicleFuelType(rawValue: fuelType) ?? .gas
        )
    }

    private static func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let goEligibleMakes: Set<String> = [
        "acura",
        "audi",
        "bmw",
        "buick",
        "cadillac",
        "chevrolet",
        "chevy",
        "chrysler",
        "dodge",
        "ford",
        "genesis",
        "gmc",
        "honda",
        "hyundai",
        "infiniti",
        "kia",
        "lexus",
        "lincoln",
        "mazda",
        "mercedes benz",
        "mercedes-benz",
        "mitsubishi",
        "nissan",
        "subaru",
        "tesla",
        "toyota",
        "volkswagen",
        "volvo"
    ]

    private static let goEligibleModelFragments = [
        "accord",
        "altima",
        "camry",
        "civic",
        "corolla",
        "elantra",
        "equinox",
        "fusion",
        "malibu",
        "maxima",
        "sentra",
        "sonata",
        "soul",
        "sportage",
        "tucson",
        "cr v",
        "crv",
        "cx 5",
        "cx5",
        "escape",
        "forester",
        "rav4",
        "rogue",
        "model 3",
        "model y",
        "ioniq",
        "leaf",
        "mach e",
        "mustang mach e",
        "ev6",
        "bolt"
    ]

    private static let xlModelFragments = [
        "armada",
        "ascent",
        "atlas",
        "carnival",
        "enclave",
        "escalade",
        "expedition",
        "explorer",
        "grand caravan",
        "highlander",
        "navigator",
        "odyssey",
        "pacifica",
        "palisade",
        "pilot",
        "sienna",
        "suburban",
        "tahoe",
        "telluride",
        "traverse",
        "yukon"
    ]
}

private extension Double {
    var formattedRate: String {
        String(format: "%.2f", self)
    }
}
