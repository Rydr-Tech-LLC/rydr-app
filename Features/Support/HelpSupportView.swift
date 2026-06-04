//
//  HelpSupportView.swift
//  RydrPlayground
//
//  Rider-side Help & Support home.
//

import SwiftUI

struct HelpSupportView: View {
    @EnvironmentObject private var rideManager: RideManager
    @State private var searchText = ""

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchResults: [HelpArticle] {
        HelpArticleStore.search(trimmedSearch)
    }

    private var recentRides: [Receipt] {
        Array(rideManager.history.prefix(3))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                searchField

                if trimmedSearch.isEmpty {
                    quickActions
                    categories
                    recentRideHelp
                    suggestedArticles
                } else {
                    HelpSearchResultsView(query: trimmedSearch, results: searchResults)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Help & Support")
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search help articles", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How can we help?")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                SupportQuickAction(
                    title: "Get help with a ride",
                    icon: "car.fill",
                    destination: AnyView(RideHelpView())
                )
                SupportQuickAction(
                    title: "Dispute a charge",
                    icon: "creditcard.trianglebadge.exclamationmark",
                    destination: AnyView(RideDisputeView())
                )
                SupportQuickAction(
                    title: "Contact support",
                    icon: "bubble.left.and.bubble.right.fill",
                    destination: AnyView(ContactSupportView())
                )
                SupportQuickAction(
                    title: "Schedule a call",
                    icon: "phone.badge.clock.fill",
                    destination: AnyView(ScheduleCallRequestView())
                )
            }
        }
    }

    private var categories: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Browse by category")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(HelpArticleCategory.allCases) { category in
                    NavigationLink {
                        HelpCategoryArticlesView(category: category)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: category.icon)
                                .foregroundStyle(Styles.rydrGradient)
                                .frame(width: 22)
                            Text(category.rawValue)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(12)
                        .frame(minHeight: 58)
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.black.opacity(0.06), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var recentRideHelp: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent ride help")
                    .font(.headline)
                Spacer()
                NavigationLink("View all") {
                    RideHelpView()
                }
                .font(.caption.weight(.semibold))
            }

            if recentRides.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No recent rides available yet")
                        .font(.subheadline.weight(.semibold))
                    Text("You can still enter a ride reference manually if you have one.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    NavigationLink {
                        RideHelpView()
                    } label: {
                        Text("Enter ride reference")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )
            } else {
                ForEach(recentRides) { receipt in
                    NavigationLink {
                        RideHelpView(prefilledRideId: receipt.rideId.uuidString)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundStyle(Styles.rydrGradient)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(short(receipt.pickup) + " to " + short(receipt.dropoff))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(receipt.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("$" + String(format: "%.2f", receipt.fare))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var suggestedArticles: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Suggested articles")
                .font(.headline)

            ForEach(HelpArticleStore.suggestedArticles) { article in
                HelpArticleRow(article: article)
            }
        }
    }

    private func short(_ value: String) -> String {
        value.split(separator: ",").first.map(String.init) ?? value
    }
}

private struct SupportQuickAction: View {
    let title: String
    let icon: String
    let destination: AnyView

    var body: some View {
        NavigationLink {
            destination
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Styles.rydrGradient)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(height: 112)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct HelpCategoryArticlesView: View {
    let category: HelpArticleCategory

    private var articles: [HelpArticle] {
        HelpArticleStore.articles(in: category)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(articles) { article in
                    HelpArticleRow(article: article)
                }

                if category == .safety {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Emergency help", systemImage: "exclamationmark.triangle.fill")
                            .font(.headline)
                            .foregroundStyle(.red)
                        Text("Call 911 or local emergency services immediately if you are in danger.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        NavigationLink {
                            ContactSupportView(
                                prefilledSubject: "Safety issue",
                                prefilledCategory: "Safety",
                                prefilledIssueType: "Safety concern"
                            )
                        } label: {
                            Text("Report a safety issue to Rydr")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.red.opacity(0.18), lineWidth: 1)
                    )
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(category.rawValue)
    }
}
