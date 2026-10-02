//
//  RydrBankAPIError.swift
//  RydrPlayground
//
//  Created by Khris Nunnally on 8/19/25.
//


import Foundation
import FirebaseAuth
import FirebaseAppCheck

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
    static func rideComplete(rideId: String) async throws -> [String: Any] {
        try await authedRequest(path: "rides/complete", json: [
            "rideId": rideId
        ])
    }
}

/// Firebase Auth proves and links credentials; this backend call owns the
/// canonical Rider phone index and records the providers attached to the UID.
enum RiderBackendIdentityService {
    static func sync() async throws {
        guard let user = Auth.auth().currentUser else { throw RydrBankAPIError.notSignedIn }
        guard let rawBase = Bundle.main.object(forInfoDictionaryKey: "RYDR_BACKEND_BASE_URL") as? String,
              let base = URL(string: rawBase),
              let url = URL(string: "/account/identity/sync", relativeTo: base) else {
            throw URLError(.badURL)
        }
        let token = try await user.getIDToken()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["role": "rider"])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw RydrBankAPIError.server(body?["error"] as? String ?? "Account identity could not be synchronized.")
        }
    }
}

enum RiderCashHubBackend {
    private static func appCheckToken() async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            AppCheck.appCheck().token(forcingRefresh: false) { token, error in
                if let error { continuation.resume(throwing: error) }
                else if let token { continuation.resume(returning: token.token) }
                else { continuation.resume(throwing: URLError(.userAuthenticationRequired)) }
            }
        }
    }

    private static func send(path: String, method: String = "POST", body: [String: Any]) async throws {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "RYDR_BACKEND_BASE_URL") as? String,
              let base = URL(string: raw), let url = URL(string: path, relativeTo: base),
              let user = Auth.auth().currentUser else { throw URLError(.userAuthenticationRequired) }
        var request = URLRequest(url: url); request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(try await user.getIDToken())", forHTTPHeaderField: "Authorization")
        request.setValue(try await appCheckToken(), forHTTPHeaderField: "X-Firebase-AppCheck")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data,response)=try await URLSession.shared.data(for: request)
        guard let http=response as? HTTPURLResponse,(200..<300).contains(http.statusCode) else {
            let object=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any]
            throw NSError(domain:"RiderCashHubBackend",code:(response as? HTTPURLResponse)?.statusCode ?? -1,userInfo:[NSLocalizedDescriptionKey:object?["error"] as? String ?? "Cash Hub request failed."])
        }
    }
    static func create(_ body:[String:Any]) async throws { var value=body;value["idempotencyKey"]=UUID().uuidString;try await send(path:"/cash-hub/requests",body:value) }
    static func acceptTerms() async throws { try await send(path:"/cash-hub/access/accept",body:["role":"rider"]) }
    static func optOut() async throws { try await send(path:"/cash-hub/access/opt-out",body:["role":"rider"]) }
    static func command(requestId:String, action:String, body:[String:Any]=[:]) async throws { var value=body;value["action"]=action;value["idempotencyKey"]=UUID().uuidString;try await send(path:"/cash-hub/requests/\(requestId)/command",body:value) }
    static func offer(requestId:String, body:[String:Any]) async throws { var value=body;value["idempotencyKey"]=UUID().uuidString;try await send(path:"/cash-hub/requests/\(requestId)/offers",body:value) }
    static func message(conversationId:String, text:String, kind:String) async throws { try await send(path:"/cash-hub/conversations/\(conversationId)/messages",body:["message":text,"kind":kind,"idempotencyKey":UUID().uuidString]) }
}

enum RiderSafetyBackend {
    static func submit(_ body: [String: Any]) async throws {
        guard let raw=Bundle.main.object(forInfoDictionaryKey:"RYDR_BACKEND_BASE_URL") as? String,let base=URL(string:raw),let url=URL(string:"/safety/reports",relativeTo:base),let user=Auth.auth().currentUser else{throw URLError(.userAuthenticationRequired)}
        var request=URLRequest(url:url);request.httpMethod="POST";request.setValue("application/json",forHTTPHeaderField:"Content-Type");request.setValue("Bearer \(try await user.getIDToken())",forHTTPHeaderField:"Authorization");request.httpBody=try JSONSerialization.data(withJSONObject:body)
        let (data,response)=try await URLSession.shared.data(for:request);guard let http=response as? HTTPURLResponse,(200..<300).contains(http.statusCode) else{let object=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any];throw NSError(domain:"RiderSafetyBackend",code:(response as? HTTPURLResponse)?.statusCode ?? -1,userInfo:[NSLocalizedDescriptionKey:object?["error"] as? String ?? "Report failed."])}
    }
}
