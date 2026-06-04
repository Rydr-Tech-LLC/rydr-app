//
//  HelpArticleDetailView.swift
//  RydrPlayground
//
//  Help center article detail screen.
//

import SwiftUI

struct HelpArticleDetailView: View {
    let article: HelpArticle

    private var relatedArticles: [HelpArticle] {
        article.relatedArticleIds.compactMap(HelpArticleStore.article(withId:))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Label(article.category.rawValue, systemImage: article.category.icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Styles.rydrGradient)

                    Text(article.title)
                        .font(.title2.weight(.bold))

                    Text(article.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Divider()

                Text(article.body)
                    .font(.body)
                    .lineSpacing(4)

                if !relatedArticles.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Related articles")
                            .font(.headline)

                        ForEach(relatedArticles) { related in
                            NavigationLink {
                                HelpArticleDetailView(article: related)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: related.category.icon)
                                        .foregroundStyle(Styles.rydrGradient)
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(related.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Text(related.summary)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(12)
                                .background(Color(.secondarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                NavigationLink {
                    ContactSupportView(prefilledSubject: article.title, prefilledCategory: article.category.rawValue)
                } label: {
                    Label("Contact support", systemImage: "bubble.left.and.bubble.right.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(RydrProminentButton())
                .padding(.top, 4)
            }
            .padding()
        }
        .navigationTitle("Help article")
        .navigationBarTitleDisplayMode(.inline)
    }
}
