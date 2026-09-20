import SwiftUI

/// 全库搜索：标题、摘要、已抓全文（译文优先显示）
struct SearchView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    @State private var query = ""
    @State private var results: [Article] = []
    @State private var isSearching = false

    var body: some View {
        NavigationStack {
            List {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView {
                        Label {
                            Text("搜索文章")
                                .font(AppTypography.section())
                        } icon: {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(theme.muted)
                        }
                    } description: {
                        Text("匹配标题、摘要与已抓取的全文")
                            .font(AppTypography.body())
                            .foregroundStyle(theme.muted)
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init(top: 80, leading: AppLayout.listHorizontalPadding, bottom: 40, trailing: AppLayout.listHorizontalPadding))
                } else if isSearching {
                    HStack(spacing: AppSpacing.sm) {
                        ProgressView()
                            .tint(theme.accent)
                        Text("搜索中…")
                            .font(AppTypography.body())
                            .foregroundStyle(theme.muted)
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                } else if results.isEmpty {
                    ContentUnavailableView {
                        Label {
                            Text("无结果")
                                .font(AppTypography.section())
                        } icon: {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(theme.muted)
                        }
                    } description: {
                        Text("没有匹配「\(query)」的文章")
                            .font(AppTypography.body())
                            .foregroundStyle(theme.muted)
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(results) { article in
                        NavigationLink {
                            ArticleReaderView(article: article)
                        } label: {
                            SearchResultRow(article: article, query: query)
                        }
                        .listRowInsets(EdgeInsets(
                            top: 0,
                            leading: AppLayout.listHorizontalPadding,
                            bottom: 0,
                            trailing: AppLayout.listHorizontalPadding
                        ))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.plain)
            .appScreenBackground()
            .navigationTitle("搜索")
            .searchable(text: $query, prompt: "标题、摘要、全文")
            .onChange(of: query) { _, newValue in
                scheduleSearch(newValue)
            }
        }
    }

    private func scheduleSearch(_ q: String) {
        let trimmed = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            isSearching = false
            return
        }
        isSearching = true
        // 轻量防抖：短查询同步即可
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard query.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed else { return }
            results = store.searchArticles(query: trimmed, limit: 80)
            isSearching = false
        }
    }
}

private struct SearchResultRow: View {
    @Environment(\.theme) private var theme
    let article: Article
    let query: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                // Title
                Text(titleText)
                    .font(AppTypography.font(size: 17, weight: .semibold))
                    .foregroundStyle(theme.text)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                // Excerpt
                if let snippet = snippetText {
                    Text(snippet)
                        .font(AppTypography.listSummary(size: 14))
                        .foregroundStyle(theme.muted)
                        .lineLimit(2)
                }

                // Metadata
                HStack(spacing: 6) {
                    Text(article.feedTitle)
                        .font(AppTypography.caption())
                        .foregroundStyle(theme.muted)
                    if !article.relativeTime.isEmpty {
                        Text("·")
                            .font(AppTypography.caption())
                            .foregroundStyle(theme.muted.opacity(0.45))
                        Text(article.relativeTime)
                            .font(AppTypography.caption())
                            .foregroundStyle(theme.muted)
                    }
                    if article.hasFullContent {
                        Text("全文")
                            .font(AppTypography.caption())
                            .fontWeight(.semibold)
                            .foregroundStyle(theme.accent)
                    }
                }
            }
            .padding(.vertical, AppSpacing.md)
            Divider()
                .opacity(0.4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(titleText)，\(article.feedTitle)")
    }

    private var titleText: String {
        if let t = article.translatedTitle, !t.isEmpty { return t }
        return article.title
    }

    private var snippetText: String? {
        let q = query.lowercased()
        let candidates: [String] = [
            article.translatedSummary,
            article.summary,
            article.translatedContent.map { String(HTMLUtils.stripTags($0).prefix(400)) },
            article.hasFullContent ? String(HTMLUtils.stripTags(article.content).prefix(400)) : nil
        ].compactMap { $0 }.map { HTMLUtils.stripTags($0) }
        for c in candidates {
            let lower = c.lowercased()
            if let r = lower.range(of: q) {
                let start = lower.index(r.lowerBound, offsetBy: -24, limitedBy: lower.startIndex) ?? lower.startIndex
                let end = lower.index(r.upperBound, offsetBy: 48, limitedBy: lower.endIndex) ?? lower.endIndex
                let slice = String(c[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
                return (start == lower.startIndex ? "" : "…") + slice + (end == lower.endIndex ? "" : "…")
            }
        }
        let summary = HTMLUtils.stripTags(article.translatedSummary ?? article.summary)
        return summary.isEmpty ? nil : String(summary.prefix(100))
    }
}
