//
//  ImageModerationService.swift
//  RydrPlayground
//
//  Uploads a rider-chosen image to a pending Storage path, asks the
//  rydr-backend /moderation/check-image route to run it through Google
//  Cloud Vision SafeSearch, then either promotes it to a permanent path
//  (approved) or deletes it (rejected / needs review).
//

import Foundation
import UIKit
import FirebaseAuth
import FirebaseFirestore
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
        case .uploadFailed:
            return "The photo couldn't be uploaded. Check your connection and try again."
        case .requestFailed:
            return "Couldn't reach Rydr to verify that photo. Try again in a moment."
        case .authenticationTokenUnavailable:
            return "Your session expired. Sign in again before uploading a photo."
        case .invalidServerResponse:
            return "Rydr couldn't verify that photo right now. Try again in a moment."
        case .missingBackendConfiguration:
            return "Rydr photo verification is missing its backend configuration."
        case .rejected:
            return "That photo doesn't meet Rydr's photo guidelines. Please choose a different one."
        case .needsReview:
            return "That photo is being reviewed and couldn't be auto-approved. Please choose a different one for now."
        }
    }
}

/// Decoded response from POST /moderation/check-image
private struct ModerationCheckResponse: Decodable {
    let ok: Bool
    let verdict: String
    let flagged: [FlaggedCategory]?

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
    /// approval writes the final download URL to `riders/{uid}.photoURL`.
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
                let finalURL = try await promoteToProfilePhoto(jpegData: jpegData, uid: uid)
                try? await pendingRef.delete()
                return finalURL

            case .rejected:
                try? await pendingRef.delete()
                throw ImageModerationError.rejected(reason: verdictResult.flagged?.first?.category)

            case .needsReview, .none:
                try? await pendingRef.delete()
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
        var request = URLRequest(url: backendBase.appendingPathComponent("moderation/check-image"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["storagePath": storagePath])

        guard let user = Auth.auth().currentUser else {
            throw ImageModerationError.notSignedIn
        }
        let token: String
        do {
            token = try await user.getIDToken()
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

    // MARK: - Finalizing an approved photo

    private func promoteToProfilePhoto(jpegData: Data, uid: String) async throws -> URL {
        let finalRef = Storage.storage().reference(withPath: "profilePhotos/\(uid).jpg")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        do {
            _ = try await finalRef.putDataAsync(jpegData, metadata: metadata)
            let url = try await finalRef.downloadURL()

            try await Firestore.firestore()
                .collection("riders").document(uid)
                .setData(["photoURL": url.absoluteString], merge: true)

            return url
        } catch {
            throw ImageModerationError.uploadFailed(error)
        }
    }

    // MARK: - Helpers

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
