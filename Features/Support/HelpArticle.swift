//
//  HelpArticle.swift
//  RydrPlayground
//
//  Local help center article model. This can later move to Firestore or Remote Config.
//

import Foundation

enum HelpArticleCategory: String, CaseIterable, Identifiable {
    case booking = "Booking a Ride"
    case payments = "Payments & Charges"
    case cancellations = "Cancellations & Refunds"
    case rydrBank = "RydrBank Rewards"
    case safeRydr = "SafeRydr"
    case cashHub = "Cash Rydr Hub"
    case account = "Account & Profile"
    case safety = "Safety"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .booking: return "car.fill"
        case .payments: return "creditcard.fill"
        case .cancellations: return "arrow.uturn.backward.circle.fill"
        case .rydrBank: return "banknote.fill"
        case .safeRydr: return "record.circle.fill"
        case .cashHub: return "rectangle.on.rectangle.angled"
        case .account: return "person.crop.circle.fill"
        case .safety: return "shield.lefthalf.filled"
        }
    }
}

struct HelpArticle: Identifiable, Equatable {
    let id: String
    let title: String
    let category: HelpArticleCategory
    let keywords: [String]
    let summary: String
    let body: String
    let relatedArticleIds: [String]

    func matches(_ query: String) -> Bool {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return true }

        let searchableText = ([title, category.rawValue, summary, body] + keywords)
            .joined(separator: " ")
            .lowercased()
        return searchableText.contains(normalizedQuery)
    }
}
