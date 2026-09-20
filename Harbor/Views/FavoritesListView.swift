import SwiftUI

struct FavoritesListView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    @State private var readingIDs: Set<UUID> = []

    private var articles: [Article] {
        store.favoriteArticles
            .sorted { ($0.publishedDate ?? .distantPast) > ($1.publishedDate ?? .distantPast) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(articles) { article in
                    let showTranslation = article.hasTranslatedBody
                        || (article.translatedTitle?.isEmpty == false)
                        || (article.translatedSummary?.isEmpty == false)
                    NavigationLink(value: article) {
                        ArticleRow(
                            article: article,
                            showTranslation: showTranslation,
                            preferUnreadStyle: true
                        )
                    }
                    .listRowInsets(EdgeInsets(
                        top: 0,
                        leading: AppLayout.listHorizontalPadding,
                        bottom: 0,
                        trailing: AppLayout.listHorizontalPadding
                    ))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            store.toggleFavorite(article)
                        } label: {
                            Label("取消收藏", systemImage: "star.slash")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .appScreenBackground()
            .navigationTitle("收藏")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: Article.self) { article in
                ArticleReaderView(article: article, browseFavorites: true)
                    .onAppear {
                        readingIDs.insert(article.id)
                        store.markAsRead(article)
                    }
            }
            .overlay {
                if articles.isEmpty {
                    ContentUnavailableView {
                        Label {
                            Text("暂无收藏")
                                .font(AppTypography.section())
                        } icon: {
                            Image(systemName: "star")
                                .foregroundStyle(theme.muted)
                        }
                    } description: {
                        Text("在文章列表左滑收藏，或在阅读页点星号。收藏不会被自动清理。")
                            .font(AppTypography.body())
                            .foregroundStyle(theme.muted)
                    }
                }
            }
        }
    }
}
