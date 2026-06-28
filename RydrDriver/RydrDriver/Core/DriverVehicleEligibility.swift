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
                minPerMile: 0.50,
                maxPerMile: 1.10,
                minPerMinute: 0.15,
                maxPerMinute: 0.25
            )
        case "xl":
            return .init(
                title: "Rydr XL",
                purpose: "Groups, larger parties, and luggage.",
                minPerMile: 0.50,
                maxPerMile: 1.25,
                minPerMinute: 0.15,
                maxPerMinute: 0.25
            )
        case "prestine":
            return .init(
                title: "Rydr Prestine",
                purpose: "Premium transportation with elevated vehicle standards.",
                minPerMile: 0.75,
                maxPerMile: 1.50,
                minPerMinute: 0.15,
                maxPerMinute: 0.35
            )
        case "executive":
            return .init(
                title: "Rydr Executive",
                purpose: "More Than A Ride. An Arrival.",
                minPerMile: 1.00,
                maxPerMile: 2.00,
                minPerMinute: 0.25,
                maxPerMinute: 0.50
            )
        default:
            return .init(
                title: "Rydr Go",
                purpose: "Affordable everyday transportation.",
                minPerMile: 0.50,
                maxPerMile: 1.00,
                minPerMinute: 0.15,
                maxPerMinute: 0.25
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
    let minPerMile: Double
    let maxPerMile: Double
    let minPerMinute: Double
    let maxPerMinute: Double

    var perMileRangeText: String {
        "$\(minPerMile.formattedRate) - $\(maxPerMile.formattedRate)/mi"
    }

    var perMinuteRangeText: String {
        "$\(minPerMinute.formattedRate) - $\(maxPerMinute.formattedRate)/min"
    }

    func clampedPerMile(_ value: Double) -> Double {
        min(max(value, minPerMile), maxPerMile)
    }

    func clampedPerMinute(_ value: Double) -> Double {
        min(max(value, minPerMinute), maxPerMinute)
    }
}

struct DriverRateSetting {
    var perMile: Double
    var perMinute: Double

    func dictionary(for rideType: String) -> [String: Any] {
        let pricing = RydrRideTierCatalog.pricing(for: rideType)
        return [
            "perMile": pricing.clampedPerMile(perMile),
            "perMinute": pricing.clampedPerMinute(perMinute)
        ]
    }

    static func defaultValue(for rideType: String) -> DriverRateSetting {
        let pricing = RydrRideTierCatalog.pricing(for: rideType)
        return DriverRateSetting(perMile: pricing.minPerMile, perMinute: pricing.minPerMinute)
    }
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
