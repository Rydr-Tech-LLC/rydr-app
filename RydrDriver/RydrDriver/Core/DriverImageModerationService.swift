//
//  DriverImageModerationService.swift
//  RydrDriver
//
//  Driver-app counterpart to the rider app's ImageModerationService. Uploads
//  a driver-chosen profile photo to a pending Storage path, asks the
//  rydr-backend /moderation/check-image route to run it through Google
//  Cloud Vision SafeSearch, then either promotes it to a permanent path
//  (approved) or deletes it (rejected / needs review).
//
//  This reuses the exact same backend endpoint (and therefore the exact
//  same Vision API client/credentials) that already powers rider profile
//  photo moderation — the backend's storagePathBelongsToUser check already
//  recognizes driverProfilePhotos/{uid}/... paths, it just never got called
//  from this app until now.
//

import Foundation
import UIKit
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

enum DriverImageModerationVerdict: String {
    case approved
    case needsReview = "needs_review"
    case rejected
}

enum DriverImageModerationError: LocalizedError {
    case notSignedIn
    case imageEncodingFailed
    case uploadFailed(Error)
    case requestFailed(Error)
    case invalidServerResponse
    case rejected(reason: String?)
    case needsReview

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Sign in before updating your profile photo."
        case .imageEncodingFailed:
            return "Could not prepare that image."
        case .uploadFailed:
            return "Photo upload failed. Check your connection and try again."
        case .requestFailed:
            return "Couldn't reach Rydr to verify that photo. Try again in a moment."
        case .invalidServerResponse:
            return "Rydr couldn't verify that photo right now. Try again in a moment."
        case .rejected:
            return "That photo doesn't meet Rydr's photo guidelines. Please choose a different one."
        case .needsReview:
            return "That photo needs manual review and couldn't be auto-approved. Please choose a different one for now."
        }
    }
}

/// Decoded response from POST /moderation/check-image
private struct DriverModerationCheckResponse: Decodable {
    let ok: Bool
    let verdict: String
    let flagged: [FlaggedCategory]?

    struct FlaggedCategory: Decodable {
        let category: String
        let likelihood: String
    }
}

@MainActor
final class DriverImageModerationService {
    static let shared = DriverImageModerationService()

    private init() {}

    private var backendBase: URL {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "RYDR_BACKEND_BASE_URL") as? String,
           let url = URL(string: raw) {
            return url
        }
        // Falls back to the known production backend if the Info.plist key is ever missing.
        return URL(string: "https://rydr-backend-2c19.onrender.com")!
    }

    /// Uploads `image` as the driver's profile photo, moderates it, and on
    /// approval writes the final download URL to `drivers/{uid}.profilePhotoURL`.
    /// Returns the approved download URL.
    func submitProfilePhoto(_ image: UIImage) async throws -> URL {
        guard let user = Auth.auth().currentUser else {
            throw DriverImageModerationError.notSignedIn
        }
        let uid = user.uid

        guard let jpegData = Self.encodeForUpload(image) else {
            throw DriverImageModerationError.imageEncodingFailed
        }

        // Must match the storage.rules pattern for driverProfilePhotos/{uid}/{fileName}:
        // fileName.matches('pending-[0-9]+\.jpg')
        let pendingPath = "driverProfilePhotos/\(uid)/pending-\(Int(Date().timeIntervalSince1970)).jpg"
        let pendingRef = Storage.storage().reference(withPath: pendingPath)

        do {
            let metadata = StorageMetadata()
            metadata.contentType = "image/jpeg"
            _ = try await pendingRef.putDataAsync(jpegData, metadata: metadata)
        } catch {
            throw DriverImageModerationError.uploadFailed(error)
        }

        do {
            let verdictResult = try await checkImage(storagePath: pendingPath)

            switch DriverImageModerationVerdict(rawValue: verdictResult.verdict) {
            case .approved:
                let finalURL = try await promoteToProfilePhoto(jpegData: jpegData, uid: uid)
                try? await pendingRef.delete()
                return finalURL

            case .rejected:
                try? await pendingRef.delete()
                try? await clearPendingState(uid: uid)
                throw DriverImageModerationError.rejected(reason: verdictResult.flagged?.first?.category)

            case .needsReview, .none:
                try? await pendingRef.delete()
                try? await clearPendingState(uid: uid)
                throw DriverImageModerationError.needsReview
            }
        } catch let error as DriverImageModerationError {
            throw error
        } catch {
            try? await pendingRef.delete()
            throw DriverImageModerationError.requestFailed(error)
        }
    }

    // MARK: - Backend call

    private func checkImage(storagePath: String) async throws -> DriverModerationCheckResponse {
        var request = URLRequest(url: backendBase.appendingPathComponent("moderation/check-image"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["storagePath": storagePath])

        if let user = Auth.auth().currentUser, let token = try? await user.getIDToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw DriverImageModerationError.invalidServerResponse
        }

        return try JSONDecoder().decode(DriverModerationCheckResponse.self, from: data)
    }

    // MARK: - Finalizing an approved photo

    private func promoteToProfilePhoto(jpegData: Data, uid: String) async throws -> URL {
        // Mirrors the rider app's permanent profilePhotos/{uid}.jpg path, just
        // under a driver-specific prefix (see the new driverProfilePhotos/{fileName}
        // storage.rules block — distinct from the pending driverProfilePhotos/{uid}/{fileName} one).
        let finalRef = Storage.storage().reference(withPath: "driverProfilePhotos/\(uid).jpg")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        do {
            _ = try await finalRef.putDataAsync(jpegData, metadata: metadata)
            let url = try await finalRef.downloadURL()

            try await Firestore.firestore()
                .collection("drivers").document(uid)
                .setData([
                    "profilePhotoURL": url.absoluteString,
                    "profilePhotoReviewStatus": "approved",
                    "pendingProfilePhotoURL": FieldValue.delete(),
                    "pendingProfilePhotoPath": FieldValue.delete(),
                    "profilePhotoUpdatedAt": FieldValue.serverTimestamp()
                ], merge: true)

            return url
        } catch {
            throw DriverImageModerationError.uploadFailed(error)
        }
    }

    private func clearPendingState(uid: String) async throws {
        try await Firestore.firestore()
            .collection("drivers").document(uid)
            .setData([
                "pendingProfilePhotoURL": FieldValue.delete(),
                "pendingProfilePhotoPath": FieldValue.delete(),
                "profilePhotoReviewStatus": "approved",
                "profilePhotoUpdatedAt": FieldValue.serverTimestamp()
            ], merge: true)
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
