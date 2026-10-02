//
//  ImageModerationService.swift
//  RydrPlayground
//
//  Uploads a rider-chosen image to a pending Storage path, asks the
//  rydr-backend finalization route to run Google Cloud Vision SafeSearch.
//  The backend then promotes approved bytes and owns the profile URL write.
//

import Foundation
import UIKit
import FirebaseAuth
import FirebaseStorage

enum ImageModerationVerdict: String {
    case approved
    case needsReview = "needs_review"
    case rejected
}

enum ImageModerationError: LocalizedError {
    case notSignedIn
    case imageEncodingFailed
    case uploadFailed(Error)
    case requestFailed(Error)
    case authenticationTokenUnavailable
    case invalidServerResponse(status: Int, body: String?)
    case missingBackendConfiguration
    case rejected(reason: String?)
    case needsReview

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "You need to be signed in to upload a photo."
        case .imageEncodingFailed:
            return "That image couldn't be processed. Try a different photo."
        case .uploadFailed(let error):
            return "The photo couldn't be uploaded: \(error.localizedDescription)"
        case .requestFailed(let error):
            return "Couldn't reach Rydr to verify that photo: \(error.localizedDescription)"
        case .authenticationTokenUnavailable:
            return "Your session expired. Sign in again before uploading a photo."
        case .invalidServerResponse(let status, let body):
            if let message = Self.backendMessage(from: body) {
                return "Rydr couldn't verify that photo: \(message)"
            }
            return "Rydr couldn't verify that photo right now. The service returned HTTP \(status)."
        case .missingBackendConfiguration:
            return "Rydr photo verification is missing its backend configuration."
        case .rejected:
            return "That photo doesn't meet Rydr's photo guidelines. Please choose a different one."
        case .needsReview:
            return "That photo is being reviewed and couldn't be auto-approved. Please choose a different one for now."
        }
    }

    private static func backendMessage(from body: String?) -> String? {
        guard
            let body,
            let data = body.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        if let message = object["message"] as? String, !message.isEmpty {
            return message
        }
        if let error = object["error"] as? String, !error.isEmpty {
            return error
        }
        return nil
    }
}

/// Decoded response from POST /moderation/profile-photo/finalize
private struct ModerationCheckResponse: Decodable {
    let ok: Bool
    let verdict: String
    let flagged: [FlaggedCategory]?
    let photoURL: String?

    struct FlaggedCategory: Decodable {
        let category: String
        let likelihood: String
    }
}

@MainActor
final class ImageModerationService {
    static let shared = ImageModerationService()

    private init() {}

    private func resolvedBackendBase() throws -> URL {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "RYDR_BACKEND_BASE_URL") as? String,
           let url = URL(string: raw),
           !raw.isEmpty {
            return url
        }
        throw ImageModerationError.missingBackendConfiguration
    }

    /// Uploads `image` as the rider's profile photo, moderates it, and on
    /// approval lets the backend write the final URL to `riders/{uid}.photoURL`.
    /// Returns the approved download URL.
    func submitProfilePhoto(_ image: UIImage) async throws -> URL {
        guard let user = Auth.auth().currentUser else {
            throw ImageModerationError.notSignedIn
        }
        let uid = user.uid

        guard let jpegData = Self.encodeForUpload(image) else {
            throw ImageModerationError.imageEncodingFailed
        }

        let pendingPath = "pendingProfilePhotos/\(uid)/\(UUID().uuidString).jpg"
        let pendingRef = Storage.storage().reference(withPath: pendingPath)

        do {
            let metadata = StorageMetadata()
            metadata.contentType = "image/jpeg"
            _ = try await pendingRef.putDataAsync(jpegData, metadata: metadata)
        } catch {
            throw ImageModerationError.uploadFailed(error)
        }

        do {
            let verdictResult = try await checkImage(storagePath: pendingPath)

            switch ImageModerationVerdict(rawValue: verdictResult.verdict) {
            case .approved:
                guard let value = verdictResult.photoURL, let finalURL = URL(string: value) else {
                    throw ImageModerationError.invalidServerResponse(status: 200, body: nil)
                }
                return finalURL

            case .rejected:
                throw ImageModerationError.rejected(reason: verdictResult.flagged?.first?.category)

            case .needsReview, .none:
                throw ImageModerationError.needsReview
            }
        } catch let error as ImageModerationError {
            throw error
        } catch {
            try? await pendingRef.delete()
            throw ImageModerationError.requestFailed(error)
        }
    }

    // MARK: - Backend call

    private func checkImage(storagePath: String) async throws -> ModerationCheckResponse {
        let backendBase = try resolvedBackendBase()
        var request = URLRequest(url: backendBase.appendingPathComponent("moderation/profile-photo/finalize"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["storagePath": storagePath])

        guard let user = Auth.auth().currentUser else {
            throw ImageModerationError.notSignedIn
        }
        let token: String
        do {
            token = try await refreshedIDToken(for: user)
        } catch {
            print("Rydr image moderation auth token failed:", error.localizedDescription)
            throw ImageModerationError.authenticationTokenUnavailable
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ImageModerationError.invalidServerResponse(status: -1, body: nil)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            print("Rydr image moderation failed:", httpResponse.statusCode, body ?? "<empty body>")
            throw ImageModerationError.invalidServerResponse(status: httpResponse.statusCode, body: body)
        }

        return try JSONDecoder().decode(ModerationCheckResponse.self, from: data)
    }

    // MARK: - Helpers

    private func refreshedIDToken(for user: User) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            user.getIDTokenForcingRefresh(true) { token, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let token {
                    continuation.resume(returning: token)
                } else {
                    continuation.resume(throwing: ImageModerationError.authenticationTokenUnavailable)
                }
            }
        }
    }

    private static func encodeForUpload(_ image: UIImage) -> Data? {
        let maxDimension: CGFloat = 1024
        let resized = image.resized(maxDimension: maxDimension)
        return resized.jpegData(compressionQuality: 0.8)
    }
}

private extension UIImage {
    func resized(maxDimension: CGFloat) -> UIImage {
        let largestSide = max(size.width, size.height)
        guard largestSide > maxDimension else { return self }

        let scale = maxDimension / largestSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
