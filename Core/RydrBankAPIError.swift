//
//  RydrBankAPIError.swift
//  RydrPlayground
//
//  Created by Khris Nunnally on 8/19/25.
//


import Foundation
import FirebaseAuth

enum RydrBankAPIError: Error, LocalizedError {
    case notSignedIn
    case badResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "You must be signed in."
        case .badResponse: return "Unexpected server response."
        case .server(let msg): return msg
        }
    }
}

struct RydrBankAPI {
    // ⚠️ set your Render base URL
    static let base = URL(string: "https://rydr-bank.onrender.com")!

    // MARK: - Core request
    private static func authedRequest(path: String, json: [String: Any]) async throws -> [String: Any] {
        guard let user = Auth.auth().currentUser else { throw RydrBankAPIError.notSignedIn }
        let token = try await user.getIDToken()

        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: json, options: [])

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 20
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw RydrBankAPIError.badResponse }

        // 2xx success → parse json (or empty)
        if (200..<300).contains(http.statusCode) {
            if data.isEmpty { return [:] }
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            return obj
        }

        // Non-2xx → surface server error json.message/error if present
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let msg = (obj["error"] as? String) ?? (obj["message"] as? String) ?? "Server error"
            throw RydrBankAPIError.server(msg)
        }
        throw RydrBankAPIError.badResponse
    }

    // MARK: - Public calls

    static func preview(code: String, bookingId: String?, rideType: String, distanceMi: Double) async throws -> [String: Any] {
        try await authedRequest(path: "promo/preview", json: [
            "code": code,
            "bookingId": bookingId ?? "",
            "rideType": rideType,
            "distanceMi": distanceMi
        ])
    }

    static func release(code: String) async throws {
        _ = try await authedRequest(path: "promo/release", json: ["code": code])
    }

    static func consume(code: String, rideId: String, rideType: String, distanceMi: Double) async throws {
        _ = try await authedRequest(path: "promo/consume", json: [
            "code": code,
            "rideId": rideId,
            "rideType": rideType,
            "distanceMi": distanceMi
        ])
    }

    /// Used by the ride pipeline when a completed ride should count toward RydrBank.
    static func rideComplete(rideId: String, distanceMi: Double, rideType: String) async throws -> [String: Any] {
        try await authedRequest(path: "rides/complete", json: [
            "rideId": rideId,
            "distanceMi": distanceMi,
            "rideType": rideType
        ])
    }
}
