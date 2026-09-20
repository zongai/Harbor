import Foundation

/// 离线缓存：订阅数据、Feed XML、文章全文 HTML、简单图片字节
/// 目录：Application Support/IosRss/（历史路径，重命名为 Harbor 后仍沿用以保留离线数据）
enum OfflineCache {

    // MARK: - Paths

    private static let rootName = "IosRss"

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

    /// 稳定缓存键：djb2 + 长度，避免路径注入与过长 URL
    private static func key(for raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var hash: UInt64 = 5381
        for b in s.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(b)
        }
        return String(format: "%016llx_%d", hash, s.utf8.count)
    }

    // MARK: - Feeds persistence (replaces large UserDefaults blob)

    static func saveFeeds(_ feeds: [RSSFeed]) {
        do {
            let data = try JSONEncoder().encode(feeds)
            try data.write(to: feedsFileURL, options: [.atomic])
            // 同步一份到 UserDefaults 作小备份（仅 id/title/url，避免撑爆）
            let light = feeds.map { LightFeed(id: $0.id, title: $0.title, url: $0.url) }
            if let lightData = try? JSONEncoder().encode(light) {
                UserDefaults.standard.set(lightData, forKey: "feeds_light")
            }
        } catch {
            // 回退：仍写入 UserDefaults，保证不丢数据
            if let data = try? JSONEncoder().encode(feeds) {
                UserDefaults.standard.set(data, forKey: "feeds")
            }
        }
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

    static func saveArticleHTML(link: String, html: String) {
        guard !link.isEmpty, !html.isEmpty else { return }
        let file = articlesDir.appendingPathComponent(key(for: link) + ".html")
        try? html.data(using: .utf8)?.write(to: file, options: [.atomic])
        // 元数据：写入时间，便于清理
        let meta = articlesDir.appendingPathComponent(key(for: link) + ".meta")
        let ts = "\(Date().timeIntervalSince1970)"
        try? ts.data(using: .utf8)?.write(to: meta, options: [.atomic])
    }

    static func loadArticleHTML(link: String) -> String? {
        guard !link.isEmpty else { return nil }
        let file = articlesDir.appendingPathComponent(key(for: link) + ".html")
        guard let data = try? Data(contentsOf: file),
              let html = String(data: data, encoding: .utf8),
              !html.isEmpty else { return nil }
        return html
    }

    static func hasArticleHTML(link: String) -> Bool {
        loadArticleHTML(link: link) != nil
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
        URLCache.shared = URLCache(memoryCapacity: memory, diskCapacity: disk, diskPath: "IosRssURLCache")
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
