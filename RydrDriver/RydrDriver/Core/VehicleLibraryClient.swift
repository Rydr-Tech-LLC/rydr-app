//
//  VehicleLibraryClient.swift
//  Rydr Driver
//
//  Thin async wrapper around the Vehicle Library System's Firebase Cloud
//  Functions (Rydr_Firebase/functions): VIN decoding via the free NHTSA
//  decoder and generic vehicle image matching. The driver app never talks
//  to NHTSA or Firebase Storage directly — every call goes through these
//  callable functions, which run with backend privileges and keep the
//  decode/image-matching logic in one shared place for both the Driver and
//  Rider apps.
//

import Foundation
import FirebaseFunctions

/// The fixed 11-color list drivers choose from. Keep in sync with
/// Rydr_Firebase/functions/src/types.ts `VEHICLE_COLORS` and Mission
/// Control's color filter.
enum VehicleColor: String, CaseIterable, Identifiable {
    case black = "Black"
    case white = "White"
    case silver = "Silver"
    case gray = "Gray"
    case blue = "Blue"
    case red = "Red"
    case green = "Green"
    case brown = "Brown"
    case gold = "Gold"
    case yellow = "Yellow"
    case orange = "Orange"

    var id: String { rawValue }
}

/// Result of decoding a VIN via NHTSA (cached server-side — see
/// VehicleDecoderService). Mirrors `VinDecodeCacheEntry` in the Cloud
/// Functions package, trimmed to what the signup UI needs.
struct DecodedVehicleInfo: Equatable {
    var vin: String
    var make: String
    var model: String
    var year: String
    var trim: String?
    var bodyStyle: String?
    var driveType: String?
    var fuelType: DriverVehicleFuelType

    var summaryText: String {
        var parts = [year, make, model]
        if let trim, !trim.isEmpty { parts.append(trim) }
        return parts.filter { !$0.isEmpty }.joined(separator: " ")
    }
}

/// Result of resolving a generic vehicle image for a decoded vehicle +
/// chosen color, via the 5-tier fallback chain in VehicleImageService.
/// `status == "missing"` means even the generic body-style placeholder
/// hasn't been uploaded yet — the UI should show a local car icon, never a
/// broken image link.
struct VehicleImageInfo: Equatable {
    var color: String
    var imageUrl: String?
    var imagePath: String?
    var matchTier: Int?
    var status: String // "matched" | "fallback" | "missing"
}

enum VehicleLibraryClientError: LocalizedError {
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The Vehicle Library service returned an unexpected response."
        case .server(let message):
            return message
        }
    }
}

enum VehicleLibraryClient {
    private static var functions: Functions { Functions.functions() }

    /// Calls the `decodeVin` callable function. Used to populate the
    /// "Year Make Model Trim" summary as soon as the driver taps "Decode
    /// Vehicle" — before any color has been chosen and before anything is
    /// written to their driver record.
    static func decodeVin(_ vin: String) async throws -> DecodedVehicleInfo {
        let result = try await functions.httpsCallable("decodeVin").call(["vin": vin])
        guard let data = result.data as? [String: Any] else {
            throw VehicleLibraryClientError.invalidResponse
        }
        let make = data["make"] as? String ?? ""
        let model = data["model"] as? String ?? ""
        let modelYear = data["modelYear"]
        let year: String
        if let intYear = modelYear as? Int {
            year = String(intYear)
        } else if let numberYear = modelYear as? NSNumber {
            year = numberYear.stringValue
        } else {
            year = ""
        }

        guard !make.isEmpty, !model.isEmpty, !year.isEmpty else {
            throw VehicleLibraryClientError.server("We couldn't determine this vehicle's make, model, and year from the VIN.")
        }

        return DecodedVehicleInfo(
            vin: data["vin"] as? String ?? vin,
            make: make,
            model: model,
            year: year,
            trim: data["trim"] as? String,
            bodyStyle: data["bodyStyle"] as? String,
            driveType: data["driveType"] as? String,
            fuelType: DriverVehicleFuelType.fromNHTSA(data["fuelTypePrimary"] as? String)
        )
    }

    /// Calls `getVehicleImage` to preview the matching generic vehicle
    /// image as soon as the driver picks a color — before the final
    /// `submitVehicleVin` write.
    static func getVehicleImage(decoded: DecodedVehicleInfo, color: VehicleColor) async throws -> VehicleImageInfo {
        var payload: [String: Any] = [
            "make": decoded.make,
            "model": decoded.model,
            "year": Int(decoded.year) ?? decoded.year,
            "color": color.rawValue
        ]
        if let trim = decoded.trim { payload["trim"] = trim }
        if let bodyStyle = decoded.bodyStyle { payload["bodyStyle"] = bodyStyle }

        let result = try await functions.httpsCallable("getVehicleImage").call(payload)
        guard let data = result.data as? [String: Any] else {
            throw VehicleLibraryClientError.invalidResponse
        }
        let status = data["status"] as? String ?? "missing"
        let match = data["result"] as? [String: Any]
        return VehicleImageInfo(
            color: color.rawValue,
            imageUrl: match?["imageUrl"] as? String,
            imagePath: match?["storagePath"] as? String,
            matchTier: match?["tier"] as? Int,
            status: status
        )
    }

    /// Calls `submitVehicleVin` — the single authoritative write. Re-decodes
    /// (cheap; cached) and re-matches the image server-side, then writes
    /// every resulting field onto `drivers/{uid}.vehicle` atomically. This
    /// is what the signup flow's final "Continue" tap should call, so the
    /// stored record is always self-consistent even if the on-screen
    /// preview state ever drifted.
    static func submitVehicleVin(vin: String, color: VehicleColor) async throws -> VehicleImageInfo {
        let result = try await functions.httpsCallable("submitVehicleVin").call(["vin": vin, "color": color.rawValue])
        guard let data = result.data as? [String: Any] else {
            throw VehicleLibraryClientError.invalidResponse
        }
        let vehicle = data["vehicle"] as? [String: Any]
        return VehicleImageInfo(
            color: color.rawValue,
            imageUrl: vehicle?["imageUrl"] as? String,
            imagePath: vehicle?["imagePath"] as? String,
            matchTier: vehicle?["imageMatchTier"] as? Int,
            status: data["vehicleImageStatus"] as? String ?? "missing"
        )
    }

    /// Fallback for when `decodeVin`/`submitVehicleVin` can't resolve a VIN
    /// (NHTSA has no data for it, the VIN was mistyped/unreadable, etc.).
    /// The driver types make/model/year themselves; this is the single
    /// authoritative write for that path, mirroring `submitVehicleVin` but
    /// skipping NHTSA entirely. Server marks the record `vinDecodeStatus:
    /// "manual"` so Mission Control can flag it for a quick human check.
    static func submitVehicleManual(_ info: ManualVehicleInfo, color: VehicleColor) async throws -> VehicleImageInfo {
        var payload: [String: Any] = [
            "make": info.make,
            "model": info.model,
            "year": Int(info.year) ?? info.year,
            "color": color.rawValue
        ]
        if let vin = info.vin, !vin.isEmpty { payload["vin"] = vin }
        if let trim = info.trim, !trim.isEmpty { payload["trim"] = trim }
        payload["fuelType"] = info.fuelType.rawValue

        let result = try await functions.httpsCallable("submitVehicleManual").call(payload)
        guard let data = result.data as? [String: Any] else {
            throw VehicleLibraryClientError.invalidResponse
        }
        let vehicle = data["vehicle"] as? [String: Any]
        return VehicleImageInfo(
            color: color.rawValue,
            imageUrl: vehicle?["imageUrl"] as? String,
            imagePath: vehicle?["imagePath"] as? String,
            matchTier: vehicle?["imageMatchTier"] as? Int,
            status: data["vehicleImageStatus"] as? String ?? "missing"
        )
    }
}

/// What the driver types in by hand when VIN decode fails. Mirrors
/// `DecodedVehicleInfo` minus the fields only NHTSA can provide
/// (bodyStyle/driveType are left for Mission Control's manual review).
struct ManualVehicleInfo: Equatable {
    var vin: String?
    var make: String
    var model: String
    var year: String
    var trim: String?
    var fuelType: DriverVehicleFuelType
}
