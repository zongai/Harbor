import Foundation

/// 离线缓存：订阅数据、Feed XML、文章全文 HTML、简单图片字节
/// 目录：Application Support/Harbor/
enum OfflineCache {

    // MARK: - Paths

    private static let rootName = "Harbor"

    private static var rootURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let url = base.appendingPathComponent(rootName, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static var feedsFileURL: URL {
        rootURL.appendingPathComponent("feeds.json")
    }

    private static var chatsFileURL: URL {
        rootURL.appendingPathComponent("chat_conversations.json")
    }

    private static var articlesDir: URL {
        let u = rootURL.appendingPathComponent("articles", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    private static var feedXMLDir: URL {
        let u = rootURL.appendingPathComponent("feeds_xml", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    private static var imagesDir: URL {
        let u = rootURL.appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    /// 源图标专用目录，清理内容缓存时保留
    private static var faviconDir: URL {
        let u = rootURL.appendingPathComponent("favicons", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    /// 与 AppStore.canonicalLink 对齐：读写正文必须用同一规范化 link
    static func normalizeLink(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasSuffix("/") { s = String(s.dropLast()) }
        if let url = URL(string: s), var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            comps.fragment = nil
            if let host = comps.host { comps.host = host.lowercased() }
            if let scheme = comps.scheme { comps.scheme = scheme.lowercased() }
            if let rebuilt = comps.url?.absoluteString {
                s = rebuilt
                if s.hasSuffix("/") { s = String(s.dropLast()) }
            }
        }
        return s
    }

    /// 稳定缓存键：规范化 URL → djb2 + 长度
    private static func key(for raw: String) -> String {
        let s = normalizeLink(raw).lowercased()
        var hash: UInt64 = 5381
        for b in s.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(b)
        }
        return String(format: "%016llx_%d", hash, s.utf8.count)
    }

    // MARK: - Feeds persistence (replaces large UserDefaults blob)

    /// 正文阈值：与 AppStore.heavyBodyThreshold 对齐，写入 feeds.json 前剥离大正文
    private static let heavyBodyThreshold = 1_200

    /// 元数据快照：大正文/译文写入独立 HTML 文件后再编码，缩小 feeds.json 与崩溃窗口风险
    static func saveFeeds(_ feeds: [RSSFeed]) {
        let slim = feedsForMetadataPersistence(feeds)
        do {
            let data = try JSONEncoder().encode(slim)
            try data.write(to: feedsFileURL, options: [.atomic])
            let light = slim.map { LightFeed(id: $0.id, title: $0.title, url: $0.url) }
            if let lightData = try? JSONEncoder().encode(light) {
                UserDefaults.standard.set(lightData, forKey: "feeds_light")
            }
        } catch {
            if let data = try? JSONEncoder().encode(slim) {
                UserDefaults.standard.set(data, forKey: "feeds")
            }
        }
    }

    /// 将正文落到 article HTML 缓存，feeds 内只保留元数据与短字段
    private static func feedsForMetadataPersistence(_ feeds: [RSSFeed]) -> [RSSFeed] {
        var copy = feeds
        for i in copy.indices {
            for j in copy[i].articles.indices {
                var a = copy[i].articles[j]
                if a.content.count >= heavyBodyThreshold {
                    saveArticleHTML(link: a.link, html: a.content)
                    a.hasFullContent = true
                    a.content = ""
                }
                if let translated = a.translatedContent, translated.count >= heavyBodyThreshold {
                    saveTranslatedHTML(link: a.link, html: translated)
                    a.translatedContent = nil
                }
                copy[i].articles[j] = a
            }
        }
        return copy
    }

    static func loadFeeds() -> [RSSFeed]? {
        // 1) 磁盘主存储
        if let data = try? Data(contentsOf: feedsFileURL),
           let feeds = try? JSONDecoder().decode([RSSFeed].self, from: data) {
            return feeds
        }
        // 2) 迁移旧 UserDefaults
        if let data = UserDefaults.standard.data(forKey: "feeds"),
           let feeds = try? JSONDecoder().decode([RSSFeed].self, from: data) {
            saveFeeds(feeds)
            UserDefaults.standard.removeObject(forKey: "feeds")
            return feeds
        }
        return nil
    }

    private struct LightFeed: Codable {
        var id: UUID
        var title: String
        var url: String
    }

    // MARK: - AI Chat conversations

    static func saveChatConversations(_ conversations: [ChatConversation]) {
        do {
            let data = try JSONEncoder().encode(conversations)
            try data.write(to: chatsFileURL, options: [.atomic])
        } catch {
            if let data = try? JSONEncoder().encode(conversations) {
                UserDefaults.standard.set(data, forKey: "chat_conversations")
            }
        }
    }

    static func loadChatConversations() -> [ChatConversation]? {
        if let data = try? Data(contentsOf: chatsFileURL),
           let list = try? JSONDecoder().decode([ChatConversation].self, from: data) {
            return list
        }
        if let data = UserDefaults.standard.data(forKey: "chat_conversations"),
           let list = try? JSONDecoder().decode([ChatConversation].self, from: data) {
            saveChatConversations(list)
            UserDefaults.standard.removeObject(forKey: "chat_conversations")
            return list
        }
        return nil
    }

    // MARK: - Article full HTML

    /// 统一写路径：正文只按规范化 link 落盘（列表内存不持正文）
    static func saveArticleHTML(link: String, html: String) {
        persistArticleBody(link: link, html: html)
    }

    static func persistArticleBody(link: String, html: String) {
        let norm = normalizeLink(link)
        guard !norm.isEmpty, !html.isEmpty else { return }
        let file = articlesDir.appendingPathComponent(key(for: norm) + ".html")
        try? html.data(using: .utf8)?.write(to: file, options: [.atomic])
        let meta = articlesDir.appendingPathComponent(key(for: norm) + ".meta")
        let ts = "\(Date().timeIntervalSince1970)"
        try? ts.data(using: .utf8)?.write(to: meta, options: [.atomic])
    }

    /// 统一读路径：阅读页按 link 从磁盘水合
    static func loadArticleHTML(link: String) -> String? {
        loadArticleBody(link: link)
    }

    static func loadArticleBody(link: String) -> String? {
        let norm = normalizeLink(link)
        guard !norm.isEmpty else { return nil }
        let file = articlesDir.appendingPathComponent(key(for: norm) + ".html")
        guard let data = try? Data(contentsOf: file),
              let html = String(data: data, encoding: .utf8),
              !html.isEmpty else { return nil }
        return html
    }

    static func hasArticleHTML(link: String) -> Bool {
        hasArticleBody(link: link)
    }

    static func hasArticleBody(link: String) -> Bool {
        let norm = normalizeLink(link)
        guard !norm.isEmpty else { return false }
        let file = articlesDir.appendingPathComponent(key(for: norm) + ".html")
        return FileManager.default.fileExists(atPath: file.path)
    }

    static func saveTranslatedHTML(link: String, html: String) {
        let link = normalizeLink(link)
        guard !link.isEmpty, !html.isEmpty else { return }
        let file = articlesDir.appendingPathComponent(key(for: link) + ".translated.html")
        try? html.data(using: .utf8)?.write(to: file, options: [.atomic])
    }

    static func loadTranslatedHTML(link: String) -> String? {
        let link = normalizeLink(link)
        guard !link.isEmpty else { return nil }
        let file = articlesDir.appendingPathComponent(key(for: link) + ".translated.html")
        guard let data = try? Data(contentsOf: file),
              let html = String(data: data, encoding: .utf8),
              !html.isEmpty else { return nil }
        return html
    }

    // MARK: - Feed XML snapshot

    static func saveFeedXML(url: String, data: Data) {
        guard !url.isEmpty, !data.isEmpty else { return }
        let file = feedXMLDir.appendingPathComponent(key(for: url) + ".xml")
        try? data.write(to: file, options: [.atomic])
    }

    static func loadFeedXML(url: String) -> Data? {
        guard !url.isEmpty else { return nil }
        let file = feedXMLDir.appendingPathComponent(key(for: url) + ".xml")
        return try? Data(contentsOf: file)
    }

    // MARK: - Image bytes（正文配图等）

    static func saveImage(url: String, data: Data) {
        guard !url.isEmpty, !data.isEmpty else { return }
        let file = imagesDir.appendingPathComponent(key(for: url) + ".bin")
        try? data.write(to: file, options: [.atomic])
    }

    static func loadImage(url: String) -> Data? {
        guard !url.isEmpty else { return nil }
        let prefix = key(for: url)
        let primary = imagesDir.appendingPathComponent(prefix + ".bin")
        if let data = try? Data(contentsOf: primary) { return data }
        guard let files = try? FileManager.default.contentsOfDirectory(at: imagesDir, includingPropertiesForKeys: nil) else {
            return nil
        }
        if let match = files.first(where: { $0.lastPathComponent.hasPrefix(prefix) }) {
            return try? Data(contentsOf: match)
        }
        return nil
    }

    // MARK: - Favicon（与内容缓存隔离，清理其他缓存不删除）

    static func saveFavicon(key raw: String, data: Data) {
        guard !raw.isEmpty else { return }
        let file = faviconDir.appendingPathComponent(key(for: raw) + ".bin")
        try? data.write(to: file, options: [.atomic])
    }

    /// 返回 nil 表示无缓存；空 Data 表示曾拉取失败（占位）
    static func loadFavicon(key raw: String) -> Data? {
        guard !raw.isEmpty else { return nil }
        let file = faviconDir.appendingPathComponent(key(for: raw) + ".bin")
        return try? Data(contentsOf: file)
    }

    static func faviconCacheSize() -> Int64 {
        directorySize(faviconDir)
    }

    static func clearFaviconCache() {
        removeContents(of: faviconDir)
    }

    // MARK: - Size / Clear / Prune

    /// 总缓存字节数（含 feeds.json）
    static func totalSize() -> Int64 {
        directorySize(rootURL)
    }

    /// 仅内容缓存（文章 HTML + feed XML + 图片），不含 feeds.json
    static func contentCacheSize() -> Int64 {
        directorySize(articlesDir) + directorySize(feedXMLDir) + directorySize(imagesDir)
    }

    static func formattedSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    /// 清空文章 HTML / Feed XML / 图片，保留订阅列表
    static func clearContentCache() {
        clearContentCache(progress: nil)
    }

    /// 分步清理并回报进度 0～1（主线程回调由调用方保证）
    static func clearContentCache(progress: ((Double, String) -> Void)?) {
        let steps: [(String, () -> Void)] = [
            ("清理文章缓存…", { removeContents(of: articlesDir) }),
            ("清理 Feed 快照…", { removeContents(of: feedXMLDir) }),
            ("清理图片缓存…", { removeContents(of: imagesDir) }),
            ("清理 URLCache…", { URLCache.shared.removeAllCachedResponses() })
        ]
        let total = Double(steps.count)
        for (i, step) in steps.enumerated() {
            progress?(Double(i) / total, step.0)
            step.1()
            progress?(Double(i + 1) / total, step.0)
        }
        progress?(1, "完成")
    }

    /// 删除超过 maxAge 的文章 HTML（默认 30 天）
    static func pruneArticleHTML(maxAge: TimeInterval = 30 * 24 * 3600) {
        let cutoff = Date().timeIntervalSince1970 - maxAge
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: articlesDir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        for file in files where file.pathExtension == "html" {
            let meta = file.deletingPathExtension().appendingPathExtension("meta")
            var ts = cutoff - 1
            if let data = try? Data(contentsOf: meta),
               let s = String(data: data, encoding: .utf8),
               let v = Double(s) {
                ts = v
            } else if let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
                      let mod = attrs[.modificationDate] as? Date {
                ts = mod.timeIntervalSince1970
            }
            if ts < cutoff {
                try? FileManager.default.removeItem(at: file)
                try? FileManager.default.removeItem(at: meta)
            }
        }
    }

    // MARK: - URLCache bootstrap

    /// 扩大系统 URLCache，便于 HTML/图片网络层离线命中
    static func configureURLCache() {
        let memory = 32 * 1024 * 1024
        let disk = 200 * 1024 * 1024
        URLCache.shared = URLCache(memoryCapacity: memory, diskCapacity: disk, diskPath: "HarborURLCache")
    }

    // MARK: - Helpers

    private static func directorySize(_ url: URL) -> Int64 {
        var total: Int64 = 0
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize else { continue }
            total += Int64(size)
        }
        return total
    }

    private static func removeContents(of dir: URL) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return
        }
        for f in files {
            try? FileManager.default.removeItem(at: f)
        }
    }
}
