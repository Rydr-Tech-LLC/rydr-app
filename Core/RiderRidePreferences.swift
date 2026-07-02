//
//  RiderRidePreferences.swift
//  RydrPlayground
//

import Foundation
import FirebaseFirestore

struct RiderRidePreferences: Equatable {
    static let defaultValue = RiderRidePreferences(
        musicType: "No preference",
        climate: "Neutral",
        conversation: "Light",
        genderPreference: "No preference"
    )

    var musicType: String
    var climate: String
    var conversation: String
    var genderPreference: String

    var isDefault: Bool {
        musicType == Self.defaultValue.musicType
            && climate == Self.defaultValue.climate
            && conversation == Self.defaultValue.conversation
            && genderPreference == Self.defaultValue.genderPreference
    }

    var hasShareablePreferences: Bool {
        !shareableSummaryItems.isEmpty
    }

    var shareableSummaryItems: [String] {
        var items: [String] = []
        if musicType != Self.defaultValue.musicType {
            items.append("Music: \(musicType)")
        }
        if climate != Self.defaultValue.climate {
            items.append("Climate: \(climate)")
        }
        if conversation != Self.defaultValue.conversation {
            items.append("Conversation: \(conversation)")
        }
        return items
    }

    var shareableSummaryText: String {
        shareableSummaryItems.joined(separator: "\n")
    }

    var firestoreData: [String: Any] {
        [
            "musicType": musicType,
            "climate": climate,
            "conversation": conversation,
            "genderPreference": genderPreference,
            "updatedAt": FieldValue.serverTimestamp()
        ]
    }

    var rideRequestPayload: [String: Any]? {
        guard hasShareablePreferences else { return nil }
        return [
            "musicType": musicType,
            "climate": climate,
            "conversation": conversation,
            "summaryItems": shareableSummaryItems,
            "summaryText": shareableSummaryText
        ]
    }

    init(musicType: String, climate: String, conversation: String, genderPreference: String) {
        self.musicType = musicType
        self.climate = climate
        self.conversation = conversation
        self.genderPreference = genderPreference
    }

    init(data: [String: Any]) {
        musicType = data["musicType"] as? String ?? Self.defaultValue.musicType
        climate = data["climate"] as? String ?? Self.defaultValue.climate
        conversation = data["conversation"] as? String ?? Self.defaultValue.conversation
        genderPreference = data["genderPreference"] as? String
            ?? data["driverPreference"] as? String
            ?? Self.defaultValue.genderPreference
    }
}

final class RiderRidePreferenceStore {
    private let db = Firestore.firestore()

    func load(uid: String) async throws -> RiderRidePreferences {
        let snapshot = try await db.collection("riders")
            .document(uid)
            .collection("ridePreferences")
            .document("current")
            .getDocument()
        guard let data = snapshot.data() else { return .defaultValue }
        return RiderRidePreferences(data: data)
    }

    func save(_ preferences: RiderRidePreferences, uid: String) async throws {
        try await db.collection("riders")
            .document(uid)
            .collection("ridePreferences")
            .document("current")
            .setData(preferences.firestoreData, merge: true)
    }
}
