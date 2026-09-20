import Foundation

/// 纯函数搜索，便于单测与后续索引优化
enum ArticleSearchService {
    /// - Parameter includeFullText: 是否扫描已抓取正文（默认 false，避免大库键入卡顿）
    static func search(
        feeds: [RSSFeed],
        query: String,
        limit: Int = 50,
        includeFullText: Bool = false
    ) -> [Article] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        var hits: [(score: Int, article: Article)] = []
        for feed in feeds {
            for article in feed.articles {
                var score = 0
                let title = (article.translatedTitle ?? article.title).lowercased()
                if title.contains(q) { score += 8 }

                let summary = HTMLUtils.stripTags(article.translatedSummary ?? article.summary).lowercased()
                if summary.contains(q) { score += 4 }

                // 默认不扫全文：strip 大段 HTML 成本高
                if includeFullText {
                    if article.hasFullContent {
                        let body = HTMLUtils.stripTags(article.translatedContent ?? article.content).lowercased()
                        if body.contains(q) { score += 2 }
                    } else if let tc = article.translatedContent?.lowercased(), tc.contains(q) {
                        score += 2
                    }
                }

                if score > 0 {
                    hits.append((score, article))
                }
            }
        }
        return hits.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            let d0 = $0.article.publishedDate ?? .distantPast
            let d1 = $1.article.publishedDate ?? .distantPast
            return d0 > d1
        }
        .prefix(limit)
        .map(\.article)
    }
}
