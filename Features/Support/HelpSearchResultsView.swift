//
//  HelpSearchResultsView.swift
//  RydrPlayground
//
//  Search result list for Help & Support.
//

import SwiftUI

struct HelpSearchResultsView: View {
    let query: String
    let results: [HelpArticle]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Search results")
                .font(.headline)

            if results.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label("No articles found", systemImage: "magnifyingglass")
                        .font(.subheadline.weight(.semibold))
                    Text("We can still help. Tell Rydr support what you are looking for.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    NavigationLink {
                        ContactSupportView(
                            prefilledSubject: "Help search: \(query)",
                            prefilledDescription: "I searched for: \(query)"
                        )
                    } label: {
                        Text("Contact support")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                ForEach(results) { article in
                    HelpArticleRow(article: article)
                }
            }
        }
    }
}

struct HelpArticleRow: View {
    let article: HelpArticle

    var body: some View {
        NavigationLink {
            HelpArticleDetailView(article: article)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: article.category.icon)
                    .foregroundStyle(Styles.rydrGradient)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text(article.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(article.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Text(article.category.rawValue)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding(12)
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
