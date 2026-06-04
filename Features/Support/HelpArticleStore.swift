//
//  HelpArticleStore.swift
//  RydrPlayground
//
//  Static MVP help article catalog.
//

import Foundation

enum HelpArticleStore {
    static let articles: [HelpArticle] = [
        article(
            id: "book-a-ride",
            title: "How do I book a ride?",
            category: .booking,
            keywords: ["request", "pickup", "drop-off", "driver"],
            summary: "Choose your ride type, enter pickup and drop-off details, then select a driver.",
            body: """
            Start from the Ride tab, choose the Rydr tier that fits your trip, and enter your pickup and drop-off.

            Rydr will show nearby available drivers with their vehicle details, rating, and driver-set rates. Choose a driver, review the estimate, and submit your ride request.

            Once a driver accepts, your ride moves into progress and you can follow arrival details from the ride screen.
            """,
            relatedArticleIds: ["nearby-drivers", "three-drivers"]
        ),
        article(
            id: "nearby-drivers",
            title: "How does Rydr choose nearby drivers?",
            category: .booking,
            keywords: ["nearby", "matching", "available", "driver selection"],
            summary: "Nearby drivers are shown based on availability, distance, ride tier, and app readiness.",
            body: """
            Rydr looks for drivers who are available for your selected tier and close enough to reasonably accept the trip.

            Driver availability can change quickly. If a driver does not accept, you can return to the list and choose another nearby driver.
            """,
            relatedArticleIds: ["three-drivers", "book-a-ride"]
        ),
        article(
            id: "three-drivers",
            title: "Why do I see only three drivers?",
            category: .booking,
            keywords: ["three", "drivers", "cards", "selection"],
            summary: "Rydr keeps driver selection focused so riders can compare a small, relevant group.",
            body: """
            Rydr may show a focused set of nearby drivers so choosing feels simple and fast.

            The list can change based on driver availability, distance, ride tier, and whether another rider has requested a driver first.
            """,
            relatedArticleIds: ["nearby-drivers"]
        ),
        article(
            id: "ride-prices",
            title: "How Rydr calculates ride prices",
            category: .payments,
            keywords: ["fare", "price", "per mile", "per minute", "subtotal"],
            summary: "Ride estimates use the selected driver's per-mile and per-minute rates, plus Rydr pricing rules.",
            body: """
            Rydr estimates the ride subtotal from estimated miles and minutes using the selected driver's approved rates.

            A platform minimum subtotal may apply for short or low-cost rides. After the ride subtotal is set, Rydr adds the booking fee for the selected ride tier and distance.

            Your final charge may also reflect eligible rewards, wait-time charges, refunds, or adjustments.
            """,
            relatedArticleIds: ["booking-fee", "minimum-fare"]
        ),
        article(
            id: "booking-fee",
            title: "What is the booking fee?",
            category: .payments,
            keywords: ["fee", "booking", "service fee"],
            summary: "The booking fee helps support the Rydr platform and can vary by ride tier and distance.",
            body: """
            The booking fee is added after the ride subtotal is calculated.

            It helps support platform operations, payment processing, support, safety tooling, and ongoing improvements to the Rydr experience.
            """,
            relatedArticleIds: ["ride-prices", "minimum-fare"]
        ),
        article(
            id: "minimum-fare",
            title: "Why was I charged a minimum fare?",
            category: .payments,
            keywords: ["minimum", "minimum fare", "short ride", "adjustment"],
            summary: "Some short rides have a minimum ride subtotal before the booking fee is added.",
            body: """
            Rydr applies a minimum ride subtotal for short or low-cost rides.

            This does not change the driver's selected per-mile or per-minute rates. It is a rider fare rule that keeps completed rides above the minimum subtotal for the selected ride tier.
            """,
            relatedArticleIds: ["ride-prices", "booking-fee", "dispute-charge"]
        ),
        article(
            id: "dispute-charge",
            title: "How do I dispute a charge?",
            category: .payments,
            keywords: ["dispute", "charge", "incorrect", "refund", "fare"],
            summary: "Open Help & Support, choose Dispute a charge, and tell us what happened.",
            body: """
            If a charge looks wrong, open Help & Support and choose Dispute a charge.

            Include the ride reference if you have it, the issue type, the amount in question, and a short explanation. Rydr support will review the request and follow up through your selected contact method.
            """,
            relatedArticleIds: ["ride-prices", "refunds"]
        ),
        article(
            id: "cancellations",
            title: "How cancellations work",
            category: .cancellations,
            keywords: ["cancel", "cancellation", "fee", "driver"],
            summary: "Cancellation options depend on whether the driver is on the way or the ride has started.",
            body: """
            You can cancel before pickup from the ride options screen. Rydr may help you find another driver when the cancellation happens before pickup.

            If a ride is already in progress, ending the ride can create a prorated receipt.
            """,
            relatedArticleIds: ["refunds", "driver-cancelled"]
        ),
        article(
            id: "refunds",
            title: "When refunds may apply",
            category: .cancellations,
            keywords: ["refund", "credit", "adjustment"],
            summary: "Refunds or adjustments may apply when the charge does not match what happened on the trip.",
            body: """
            Rydr support reviews refund requests based on trip details, timing, driver status, and the issue you report.

            If you believe a charge is incorrect, submit a ride help request or dispute so support can review it.
            """,
            relatedArticleIds: ["dispute-charge", "cancellations"]
        ),
        article(
            id: "driver-cancelled",
            title: "What if my driver cancelled?",
            category: .cancellations,
            keywords: ["driver cancelled", "reassign", "no show"],
            summary: "If a driver cancels, you can request another nearby driver.",
            body: """
            Driver availability can change. If a driver cancels before pickup, return to the driver list and request another available driver.

            If you were charged after a driver cancellation, contact support so we can review the ride.
            """,
            relatedArticleIds: ["refunds", "nearby-drivers"]
        ),
        article(
            id: "rydrbank-overview",
            title: "How RydrBank works",
            category: .rydrBank,
            keywords: ["RydrBank", "rewards", "free ride", "progress"],
            summary: "RydrBank tracks eligible ride progress toward rider rewards.",
            body: """
            RydrBank helps riders track eligible ride progress toward rewards such as free ride value.

            Your progress depends on eligible completed rides, distance, and reward rules shown in the app.
            """,
            relatedArticleIds: ["free-ride", "rydrbank-missing"]
        ),
        article(
            id: "free-ride",
            title: "When do I earn a free ride?",
            category: .rydrBank,
            keywords: ["free ride", "reward", "earn"],
            summary: "Free ride eligibility depends on RydrBank progress and eligible completed rides.",
            body: """
            RydrBank progress is earned through eligible completed rides.

            When you reach the required progress, the app will show available reward value that can be applied according to current RydrBank rules.
            """,
            relatedArticleIds: ["rydrbank-overview"]
        ),
        article(
            id: "rydrbank-missing",
            title: "Why did my ride not count toward RydrBank?",
            category: .rydrBank,
            keywords: ["missing", "not counted", "reward progress"],
            summary: "Some rides may not qualify or may need time to appear.",
            body: """
            RydrBank progress may take a short time to update after a ride completes.

            If a completed eligible ride still does not appear, contact support with the ride reference so we can review it.
            """,
            relatedArticleIds: ["rydrbank-overview", "contact-support"]
        ),
        article(
            id: "saferydr-overview",
            title: "What is SafeRydr?",
            category: .safeRydr,
            keywords: ["SafeRydr", "recording", "safety"],
            summary: "SafeRydr is Rydr's safety-focused tooling for ride-related concerns.",
            body: """
            SafeRydr is designed to support rider and driver safety during Rydr experiences.

            As SafeRydr features expand, Rydr will explain when safety tools are active and how related information is handled.
            """,
            relatedArticleIds: ["saferydr-recordings", "safety-emergency"]
        ),
        article(
            id: "saferydr-recordings",
            title: "How SafeRydr recordings work",
            category: .safeRydr,
            keywords: ["recording", "audio", "video", "privacy"],
            summary: "SafeRydr recordings are intended for safety review, not general sharing.",
            body: """
            SafeRydr recordings, when available, are intended to help review safety-related issues.

            Rydr should clearly communicate recording behavior and access rules before these features are used in production.
            """,
            relatedArticleIds: ["saferydr-access"]
        ),
        article(
            id: "saferydr-access",
            title: "Who can access SafeRydr recordings?",
            category: .safeRydr,
            keywords: ["access", "privacy", "recording"],
            summary: "Access should be limited to authorized safety review needs.",
            body: """
            SafeRydr recording access should be limited to authorized review for safety, support, legal, or compliance needs.

            If you have a safety concern, submit a safety report so Rydr can review the details.
            """,
            relatedArticleIds: ["report-safety"]
        ),
        article(
            id: "cash-hub-overview",
            title: "What is Cash Rydr Hub?",
            category: .cashHub,
            keywords: ["Cash Hub", "cash ride", "post request"],
            summary: "Cash Rydr Hub is a separate community-style ride request area.",
            body: """
            Cash Rydr Hub is separate from standard Rydr ride booking.

            It helps riders post Cash Hub ride requests and manage related activity in that feature area.
            """,
            relatedArticleIds: ["cash-hub-standard", "cash-hub-report"]
        ),
        article(
            id: "cash-hub-standard",
            title: "Is Cash Rydr Hub the same as a Rydr ride?",
            category: .cashHub,
            keywords: ["standard ride", "cash", "difference"],
            summary: "No. Cash Rydr Hub is separate from standard Rydr ride booking.",
            body: """
            Standard Rydr rides and Cash Rydr Hub activity are separate experiences.

            Standard Rydr rides use the rider-side booking flow, driver selection, pricing, and ride progress screens. Cash Rydr Hub has its own request and response flow.
            """,
            relatedArticleIds: ["cash-hub-overview"]
        ),
        article(
            id: "cash-hub-report",
            title: "How do I report a Cash Hub issue?",
            category: .cashHub,
            keywords: ["report", "Cash Hub", "issue"],
            summary: "Use Help & Support and include that the issue happened in Cash Rydr Hub.",
            body: """
            Open Help & Support, choose Contact support, and describe the Cash Rydr Hub issue.

            Include any request reference, driver profile name, time, and details that help support understand what happened.
            """,
            relatedArticleIds: ["contact-support"]
        ),
        article(
            id: "profile-update",
            title: "Updating your profile",
            category: .account,
            keywords: ["profile", "name", "address", "email"],
            summary: "Profile details can be managed from the Profile tab.",
            body: """
            Open Profile, then Personal Information to review and update account details.

            Keeping your profile current helps support and ride flows use the right contact information.
            """,
            relatedArticleIds: ["phone-number", "payment-methods"]
        ),
        article(
            id: "phone-number",
            title: "Changing your phone number",
            category: .account,
            keywords: ["phone", "number", "verification"],
            summary: "Phone number changes may require verification.",
            body: """
            Your phone number is part of your account contact and sign-in experience.

            If you cannot update it or verification fails, contact support and include the number you want reviewed.
            """,
            relatedArticleIds: ["profile-update"]
        ),
        article(
            id: "payment-methods",
            title: "Managing payment methods",
            category: .account,
            keywords: ["payment", "card", "wallet"],
            summary: "Payment methods are managed from your Profile tab.",
            body: """
            Open Profile, then Payment Methods to review saved cards or add a new payment method.

            If a card fails or does not appear correctly, contact support with the card brand and last four digits only. Do not send full card numbers.
            """,
            relatedArticleIds: ["ride-prices", "dispute-charge"]
        ),
        article(
            id: "safety-emergency",
            title: "What to do in an emergency",
            category: .safety,
            keywords: ["emergency", "911", "danger", "urgent"],
            summary: "Call emergency services immediately if you are in danger.",
            body: """
            Call 911 or local emergency services immediately if you are in danger.

            After you are safe, you can report the issue to Rydr support so our team can review the account, trip, or Cash Hub activity.
            """,
            relatedArticleIds: ["report-safety", "share-trip"]
        ),
        article(
            id: "report-safety",
            title: "Reporting a safety issue",
            category: .safety,
            keywords: ["safety", "report", "unsafe", "incident"],
            summary: "Tell Rydr what happened so support can review the issue.",
            body: """
            If there is immediate danger, call 911 or local emergency services first.

            To report a safety issue to Rydr, choose Contact support or Get help with a ride and select Safety concern. Include what happened, when it happened, and any ride reference you have.
            """,
            relatedArticleIds: ["safety-emergency", "saferydr-overview"]
        ),
        article(
            id: "share-trip",
            title: "Sharing trip details",
            category: .safety,
            keywords: ["share", "trip", "ETA", "status"],
            summary: "Use ride sharing tools to keep trusted contacts updated.",
            body: """
            During an active ride, use the ride screen's share option to send trip status and ETA details to someone you trust.

            Sharing trip details can help others know your route and expected timing.
            """,
            relatedArticleIds: ["safety-emergency"]
        )
    ]

    static var suggestedArticles: [HelpArticle] {
        ["book-a-ride", "ride-prices", "minimum-fare", "dispute-charge", "safety-emergency"]
            .compactMap(article(withId:))
    }

    static func articles(in category: HelpArticleCategory) -> [HelpArticle] {
        articles.filter { $0.category == category }
    }

    static func article(withId id: String) -> HelpArticle? {
        articles.first { $0.id == id }
    }

    static func search(_ query: String) -> [HelpArticle] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }
        return articles.filter { $0.matches(normalized) }
    }

    private static func article(
        id: String,
        title: String,
        category: HelpArticleCategory,
        keywords: [String],
        summary: String,
        body: String,
        relatedArticleIds: [String] = []
    ) -> HelpArticle {
        HelpArticle(
            id: id,
            title: title,
            category: category,
            keywords: keywords,
            summary: summary,
            body: body,
            relatedArticleIds: relatedArticleIds
        )
    }
}
