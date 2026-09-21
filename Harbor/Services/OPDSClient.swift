import Foundation

// MARK: - Models

struct OPDSCatalog: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var url: String
    var addedAt: Date
    /// 可选 HTTP Basic 用户名；密码存 Keychain，不进 JSON
    var username: String?

    init(
        id: UUID = UUID(),
        title: String,
        url: String,
        addedAt: Date = Date(),
        username: String? = nil
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.addedAt = addedAt
        self.username = username
    }

    var hasCredentials: Bool {
        !(username ?? "").isEmpty
    }
}

enum OPDSCredentialStore {
    private static func key(_ catalogID: UUID) -> String {
        "opds_password_\(catalogID.uuidString)"
    }

    static func savePassword(_ password: String?, catalogID: UUID) {
        let k = key(catalogID)
        let p = password?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if p.isEmpty {
            Keychain.delete(key: k)
        } else {
            Keychain.save(key: k, value: p)
        }
    }

    static func password(catalogID: UUID) -> String? {
        let p = Keychain.load(key: key(catalogID))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return p.isEmpty ? nil : p
    }

    static func delete(catalogID: UUID) {
        Keychain.delete(key: key(catalogID))
    }
}

struct OPDSFeed: Sendable {
    var title: String
    var entries: [OPDSEntry]
    var nextURL: String?
    var searchURL: String?
}

struct OPDSEntry: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var authors: [String]
    var summary: String?
    var language: String?
    var published: String?
    var coverURL: String?
    var navigationURL: String?
    var acquisitionLinks: [OPDSAcquisition]

    var preferredEPUBURL: String? {
        if let epub = acquisitionLinks.first(where: {
            $0.type.lowercased().contains("epub") || $0.href.lowercased().hasSuffix(".epub")
        }) {
            return epub.href
        }
        return acquisitionLinks.first?.href
    }

    var isNavigation: Bool { navigationURL != nil && preferredEPUBURL == nil }
}

struct OPDSAcquisition: Hashable, Sendable {
    var href: String
    var type: String
    var rel: String
}

enum OPDSError: LocalizedError {
    case badURL
    case http(Int)
    case parse(String)
    case noEPUB
    case cancelled
    case download(String)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .badURL: return "OPDS 地址无效。请使用完整 URL（可省略 https://，例如 opds.example.com/catalog）"
        case .unauthorized: return "认证失败，请检查用户名和密码"
        case .http(let c): return "OPDS 服务器错误 HTTP \(c)"
        case .parse(let s): return "OPDS 解析失败：\(s)"
        case .noEPUB: return "该条目没有 EPUB 下载链接"
        case .cancelled: return "已取消"
        case .download(let s): return s
        }
    }
}

// MARK: - Client

enum OPDSClient {
    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 60
        cfg.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: cfg)
    }()

    static func fetchFeed(
        from urlString: String,
        username: String? = nil,
        password: String? = nil
    ) async throws -> OPDSFeed {
        guard let url = NetworkURLPolicy.validateOPDS(urlString) else { throw OPDSError.badURL }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue(
            "application/atom+xml;profile=opds-catalog, application/atom+xml, application/xml, text/xml, */*;q=0.8",
            forHTTPHeaderField: "Accept"
        )
        req.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 HarborOPDS/1.0",
            forHTTPHeaderField: "User-Agent"
        )
        applyBasicAuth(to: &req, username: username, password: password)
        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw OPDSError.unauthorized
            }
            if !(200...299).contains(http.statusCode) {
                throw OPDSError.http(http.statusCode)
            }
        }
        guard let xml = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
            throw OPDSError.parse("无法解码响应")
        }
        // OPDS 2 JSON (minimal)
        if xml.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
            return try parseOPDS2JSON(data)
        }
        return parseAtom(xml, baseURL: url)
    }

    /// 下载到临时文件，返回本地 URL
    static func downloadEPUB(
        from urlString: String,
        username: String? = nil,
        password: String? = nil,
        progress: (@Sendable (Double) -> Void)? = nil,
        isCancelled: (() -> Bool)? = nil
    ) async throws -> URL {
        guard let url = NetworkURLPolicy.validateOPDS(urlString) else { throw OPDSError.badURL }
        var req = URLRequest(url: url, timeoutInterval: 60)
        req.setValue("application/epub+zip, application/octet-stream, */*;q=0.5", forHTTPHeaderField: "Accept")
        applyBasicAuth(to: &req, username: username, password: password)

        let (bytes, response) = try await session.bytes(for: req)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw OPDSError.unauthorized
            }
            if !(200...299).contains(http.statusCode) {
                throw OPDSError.http(http.statusCode)
            }
        }
        let total = response.expectedContentLength
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("opds-\(UUID().uuidString).epub")
        FileManager.default.createFile(atPath: tmp.path, contents: nil)
        let handle = try FileHandle(forWritingTo: tmp)
        defer { try? handle.close() }

        var received: Int64 = 0
        var buffer = Data()
        buffer.reserveCapacity(64 * 1024)
        for try await b in bytes {
            if isCancelled?() == true {
                try? FileManager.default.removeItem(at: tmp)
                throw OPDSError.cancelled
            }
            buffer.append(b)
            if buffer.count >= 32 * 1024 {
                try handle.write(contentsOf: buffer)
                received += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                if total > 0 {
                    progress?(min(1, Double(received) / Double(total)))
                }
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            received += Int64(buffer.count)
        }
        if total > 0 {
            progress?(1)
        }
        // 简单校验：ZIP 头 PK
        let head = try Data(contentsOf: tmp, options: [.mappedIfSafe])
        if head.count < 4 || head[0] != 0x50 || head[1] != 0x4B {
            try? FileManager.default.removeItem(at: tmp)
            throw OPDSError.download("下载内容不是有效的 EPUB/ZIP")
        }
        return tmp
    }

    private static func applyBasicAuth(to request: inout URLRequest, username: String?, password: String?) {
        let user = username?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !user.isEmpty else { return }
        let pass = password ?? ""
        let token = Data("\(user):\(pass)".utf8).base64EncodedString()
        request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
    }

    // MARK: - Atom OPDS 1.x

    private static func parseAtom(_ xml: String, baseURL: URL) -> OPDSFeed {
        let feedTitle = firstTag("title", in: xml) ?? baseURL.host ?? "OPDS"
        var nextURL: String?
        var searchURL: String?
        for link in matchTags("link", in: xmlPrefix(xml, limit: 8000)) {
            let rel = attr("rel", in: link) ?? ""
            let href = absURL(attr("href", in: link), base: baseURL)
            if rel.contains("next") { nextURL = href }
            if rel.contains("search") { searchURL = href }
        }

        var entries: [OPDSEntry] = []
        for block in matchBlocks("entry", in: xml) {
            let title = firstTag("title", in: block) ?? "未命名"
            let id = firstTag("id", in: block) ?? title
            var authors: [String] = []
            for ab in matchBlocks("author", in: block) {
                if let n = firstTag("name", in: ab) { authors.append(n) }
            }
            let summary = firstTag("summary", in: block) ?? firstTag("content", in: block)
            let language = firstTag("dc:language", in: block) ?? firstTag("language", in: block)
            let published = firstTag("published", in: block) ?? firstTag("dc:date", in: block)

            var cover: String?
            var nav: String?
            var acq: [OPDSAcquisition] = []
            for link in matchTags("link", in: block) {
                let rel = (attr("rel", in: link) ?? "").lowercased()
                let type = (attr("type", in: link) ?? "").lowercased()
                guard let hrefRaw = attr("href", in: link) else { continue }
                let href = absURL(hrefRaw, base: baseURL) ?? hrefRaw
                if rel.contains("image") || rel.contains("thumbnail") || type.hasPrefix("image/") {
                    if cover == nil { cover = href }
                }
                if rel.contains("acquisition") {
                    acq.append(OPDSAcquisition(href: href, type: type, rel: rel))
                }
                // 无 acquisition 时，epub 类型也视为可下载
                if type.contains("epub") && !rel.contains("acquisition") {
                    acq.append(OPDSAcquisition(href: href, type: type, rel: rel))
                }
                if (rel.contains("subsection") || rel == "alternate" || type.contains("opds-catalog"))
                    && !type.contains("epub") {
                    if nav == nil { nav = href }
                }
            }
            // 纯导航条目：有 subsection 且无 epub
            if acq.isEmpty, let nav {
                entries.append(OPDSEntry(
                    id: id, title: strip(title), authors: authors,
                    summary: summary.map(strip), language: language, published: published,
                    coverURL: cover, navigationURL: nav, acquisitionLinks: []
                ))
            } else {
                entries.append(OPDSEntry(
                    id: id, title: strip(title), authors: authors,
                    summary: summary.map(strip), language: language, published: published,
                    coverURL: cover, navigationURL: nav, acquisitionLinks: acq
                ))
            }
        }
        return OPDSFeed(title: strip(feedTitle), entries: entries, nextURL: nextURL, searchURL: searchURL)
    }

    private static func parseOPDS2JSON(_ data: Data) throws -> OPDSFeed {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OPDSError.parse("OPDS2 JSON 无效")
        }
        let title = (obj["metadata"] as? [String: Any])?["title"] as? String ?? "OPDS"
        var entries: [OPDSEntry] = []
        let pubs = (obj["publications"] as? [[String: Any]]) ?? []
        let groups = (obj["groups"] as? [[String: Any]]) ?? []
        let navs = (obj["navigation"] as? [[String: Any]]) ?? []
        for p in pubs {
            let meta = p["metadata"] as? [String: Any] ?? [:]
            let t = meta["title"] as? String ?? "未命名"
            let id = meta["identifier"] as? String ?? t
            let authors = ((meta["author"] as? [[String: Any]]) ?? []).compactMap { $0["name"] as? String }
            var acq: [OPDSAcquisition] = []
            var cover: String?
            if let links = p["links"] as? [[String: Any]] {
                for l in links {
                    let href = l["href"] as? String ?? ""
                    let type = (l["type"] as? String ?? "").lowercased()
                    let rel = (l["rel"] as? String ?? "").lowercased()
                    if type.contains("epub") || rel.contains("acquisition") {
                        acq.append(OPDSAcquisition(href: href, type: type, rel: rel))
                    }
                    if type.hasPrefix("image") { cover = href }
                }
            }
            if let images = p["images"] as? [[String: Any]], cover == nil {
                cover = images.first?["href"] as? String
            }
            entries.append(OPDSEntry(
                id: id, title: t, authors: authors, summary: meta["description"] as? String,
                language: meta["language"] as? String, published: nil, coverURL: cover,
                navigationURL: nil, acquisitionLinks: acq
            ))
        }
        for n in navs + groups {
            let t = (n["title"] as? String) ?? "目录"
            let href = (n["href"] as? String) ?? ((n["links"] as? [[String: Any]])?.first?["href"] as? String)
            if let href {
                entries.append(OPDSEntry(
                    id: href, title: t, authors: [], summary: nil, language: nil, published: nil,
                    coverURL: nil, navigationURL: href, acquisitionLinks: []
                ))
            }
        }
        return OPDSFeed(title: title, entries: entries, nextURL: nil, searchURL: nil)
    }

    // MARK: - XML helpers

    private static func xmlPrefix(_ s: String, limit: Int) -> String {
        if s.count <= limit { return s }
        return String(s.prefix(limit))
    }

    private static func matchBlocks(_ tag: String, in text: String) -> [String] {
        let pattern = "<\(tag)\\b[^>]*>([\\s\\S]*?)</\(tag)>"
        return matches(pattern, in: text)
    }

    private static func matchTags(_ tag: String, in text: String) -> [String] {
        matches("<\(tag)\\b[^>]*/?>", in: text)
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return re.matches(in: text, range: range).compactMap { m in
            guard let r = Range(m.range, in: text) else { return nil }
            return String(text[r])
        }
    }

    private static func firstTag(_ name: String, in text: String) -> String? {
        let pattern = "<\(name)\\b[^>]*>([\\s\\S]*?)</\(name)>"
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    private static func attr(_ name: String, in tag: String) -> String? {
        let patterns = [
            "\(name)\\s*=\\s*\"([^\"]+)\"",
            "\(name)\\s*=\\s*'([^']+)'"
        ]
        for p in patterns {
            if let re = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]),
               let m = re.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
               m.numberOfRanges > 1,
               let r = Range(m.range(at: 1), in: tag) {
                return String(tag[r])
            }
        }
        return nil
    }

    private static func absURL(_ href: String?, base: URL) -> String? {
        guard let href, !href.isEmpty else { return nil }
        if href.hasPrefix("http://") || href.hasPrefix("https://") { return href }
        return URL(string: href, relativeTo: base)?.absoluteString
    }

    private static func strip(_ s: String) -> String {
        var t = s
        if let re = try? NSRegularExpression(pattern: "<[^>]+>") {
            t = re.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: "")
        }
        return t.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
