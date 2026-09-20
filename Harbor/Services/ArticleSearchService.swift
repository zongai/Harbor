import Foundation

/// 纯函数搜索：先标题/摘要，再按需批量扫 offline 正文（按 link）
enum ArticleSearchService {
    struct Hit: Sendable {
        let score: Int
        let article: Article
    }

    /// 标题 + 摘要（列表内存元数据），不含全文
    static func searchMetadata(
        feeds: [RSSFeed],
        query: String,
        limit: Int = 80
    ) -> [Article] {
        rank(hits: metadataHits(feeds: feeds, query: query), limit: limit)
    }

    /// 兼容旧入口
    static func search(
        feeds: [RSSFeed],
        query: String,
        limit: Int = 50,
        includeFullText: Bool = false
    ) -> [Article] {
        if !includeFullText {
            return searchMetadata(feeds: feeds, query: query, limit: limit)
        }
        var hits = metadataHits(feeds: feeds, query: query)
        let existing = Set(hits.map { $0.article.id })
        hits.append(contentsOf: fullTextHits(
            feeds: feeds,
            query: query,
            excludingIDs: existing,
            loadBody: { link in
                // 内存 content 优先，否则磁盘
                for feed in feeds {
                    if let a = feed.articles.first(where: { $0.link == link }) {
                        if !a.content.isEmpty { return a.content }
                        if let t = a.translatedContent, !t.isEmpty { return t }
                    }
                }
                return OfflineCache.loadArticleBody(link: link)
            }
        ))
        return rank(hits: hits, limit: limit)
    }

    /// 异步补全：仅扫描 hasFullContent、且尚未命中的文章；按 batch 从 offline cache 读正文
    static func searchFullTextSupplement(
        feeds: [RSSFeed],
        query: String,
        excludingIDs: Set<UUID>,
        limit: Int = 40,
        batchSize: Int = 24
    ) -> [Article] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }

        var candidates: [Article] = []
        for feed in feeds {
            for article in feed.articles {
                guard article.hasFullContent else { continue }
                guard !excludingIDs.contains(article.id) else { continue }
                candidates.append(article)
            }
        }
        // 新文优先
        candidates.sort {
            ($0.publishedDate ?? .distantPast) > ($1.publishedDate ?? .distantPast)
        }

        var hits: [Hit] = []
        var index = 0
        while index < candidates.count, hits.count < limit {
            let end = min(index + batchSize, candidates.count)
            let batch = Array(candidates[index..<end])
            index = end
            for article in batch {
                let bodyRaw: String
                if !article.content.isEmpty {
                    bodyRaw = article.translatedContent ?? article.content
                } else if let disk = OfflineCache.loadArticleBody(link: article.link) {
                    bodyRaw = disk
                } else if let t = article.translatedContent, !t.isEmpty {
                    bodyRaw = t
                } else {
                    continue
                }
                let body = HTMLUtils.stripTags(bodyRaw).lowercased()
                if body.contains(q) {
                    hits.append(Hit(score: 2, article: article))
                }
            }
        }
        return rank(hits: hits, limit: limit)
    }

    // MARK: - Private

    private static func metadataHits(feeds: [RSSFeed], query: String) -> [Hit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        var hits: [Hit] = []
        for feed in feeds {
            for article in feed.articles {
                var score = 0
                let title = (article.translatedTitle ?? article.title).lowercased()
                if title.contains(q) { score += 8 }

                let summary = HTMLUtils.stripTags(article.translatedSummary ?? article.summary).lowercased()
                if summary.contains(q) { score += 4 }

                if score > 0 {
                    hits.append(Hit(score: score, article: article))
                }
            }
        }
        return hits
    }

    private static func fullTextHits(
        feeds: [RSSFeed],
        query: String,
        excludingIDs: Set<UUID>,
        loadBody: (String) -> String?
    ) -> [Hit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        var hits: [Hit] = []
        for feed in feeds {
            for article in feed.articles {
                guard !excludingIDs.contains(article.id) else { continue }
                guard article.hasFullContent || !(article.translatedContent ?? "").isEmpty else { continue }
                let raw = loadBody(article.link) ?? article.translatedContent ?? article.content
                guard !raw.isEmpty else { continue }
                if HTMLUtils.stripTags(raw).lowercased().contains(q) {
                    hits.append(Hit(score: 2, article: article))
                }
            }
        }
        return hits
    }

    private static func rank(hits: [Hit], limit: Int) -> [Article] {
        hits.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            let d0 = $0.article.publishedDate ?? .distantPast
            let d1 = $1.article.publishedDate ?? .distantPast
            return d0 > d1
        }
        .prefix(limit)
        .map(\.article)
    }
}
