import Foundation
enum FeedParser {
    static func parse(data: Data, feedID: UUID, feedTitle: String) -> [Article] {
        guard let raw = String(data: data, encoding: .utf8) ??
              String(data: data, encoding: .isoLatin1) else { return [] }
        if raw.contains("<feed") && raw.contains("xmlns") {
            return parseAtom(raw, feedID: feedID, feedTitle: feedTitle)
        } else {
            return parseRSS(raw, feedID: feedID, feedTitle: feedTitle)
        }
    }
    static func extractFeedTitle(from data: Data) -> String? {
        guard let raw = String(data: data, encoding: .utf8) ??
              String(data: data, encoding: .isoLatin1) else { return nil }
        if raw.contains("<feed") && raw.contains("xmlns") {
            if let feedBlock = firstTopLevelBlock(raw, tag: "feed") {
                if let t = extractTag("title", from: feedBlock) {
                    let cleaned = stripHTML(t).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleaned.isEmpty { return cleaned }
                }
            }
        } else {
            if let channel = firstTopLevelBlock(raw, tag: "channel") {
                if let t = extractTag("title", from: channel) {
                    let cleaned = stripHTML(t).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleaned.isEmpty { return cleaned }
                }
            }
        }
        return nil
    }
    static func extractFeedLink(from data: Data) -> String? {
        guard let raw = String(data: data, encoding: .utf8) ??
              String(data: data, encoding: .utf16) ??
              String(data: data, encoding: .isoLatin1) else { return nil }
        if raw.contains("<feed") && raw.contains("xmlns") {
            if let feedBlock = firstTopLevelBlock(raw, tag: "feed") {
                let href = extractLinkHref(from: feedBlock)
                if !href.isEmpty { return href.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
        } else if let channel = firstTopLevelBlock(raw, tag: "channel") {
            if let link = extractTag("link", from: channel) {
                let cleaned = stripHTML(link).trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty { return cleaned }
            }
        }
        return nil
    }
    static func extractFeedImage(from data: Data) -> String? {
        guard let raw = String(data: data, encoding: .utf8) ??
              String(data: data, encoding: .isoLatin1) else { return nil }
        if let url = extractRSSImageURL(from: raw) { return url }
        let headScope: String = {
            if let channel = firstTopLevelBlock(raw, tag: "channel") { return channel }
            if let feed = firstTopLevelBlock(raw, tag: "feed") { return feed }
            return String(raw.prefix(12_000))
        }()
        if let href = extractAttrHref(tagName: "itunes:image", from: headScope)
            ?? extractAttrHref(tagName: "media:thumbnail", from: headScope)
            ?? extractAttrHref(tagName: "media:content", from: headScope) {
            if looksLikeImageURL(href) { return href }
        }
        if raw.contains("<feed") {
            let scope = firstTopLevelBlock(raw, tag: "feed") ?? raw
            for tag in ["icon", "logo"] {
                if let v = extractTag(tag, from: scope) {
                    let u = stripHTML(v).trimmingCharacters(in: .whitespacesAndNewlines)
                    if looksLikeImageURL(u) { return u }
                }
            }
        }
        return nil
    }
    private static func extractRSSImageURL(from raw: String) -> String? {
        let patterns = [
            #"<image\\b[^>]*>[\\s\\S]*?<url[^>]*>\\s*([^<]+?)\\s*</url>"#,
            #"<image>\\s*<url>\\s*([^<]+?)\\s*</url>"#,
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
               let range = Range(match.range(at: 1), in: raw) {
                let u = stripHTML(String(raw[range])).trimmingCharacters(in: .whitespacesAndNewlines)
                if looksLikeImageURL(u) { return u }
            }
        }
        if let imageBlock = extractBlocks(from: raw, tag: "image").first,
           let url = extractTag("url", from: imageBlock) {
            let u = stripHTML(url).trimmingCharacters(in: .whitespacesAndNewlines)
            if looksLikeImageURL(u) { return u }
        }
        return nil
    }
    static func resolveFaviconURL(from data: Data, feedURL: String) -> String? {
        if let fromFeed = extractFeedImage(from: data), !fromFeed.isEmpty {
            return absoluteURL(fromFeed, relativeTo: feedURL)
        }
        let site = extractChannelOrFeedLink(from: data).flatMap { absoluteURL($0, relativeTo: feedURL) }
        return siteFaviconURL(for: site ?? feedURL)
    }
    static func extractChannelOrFeedLink(from data: Data) -> String? {
        guard let raw = String(data: data, encoding: .utf8) ??
                String(data: data, encoding: .isoLatin1) else { return nil }
        if let channel = firstTopLevelBlock(raw, tag: "channel") {
            if let link = extractTag("link", from: channel) {
                let u = stripHTML(link).trimmingCharacters(in: .whitespacesAndNewlines)
                if looksLikeImageURL(u) || u.lowercased().hasPrefix("http") { return u }
            }
        }
        if raw.contains("<feed") {
            let scope = firstTopLevelBlock(raw, tag: "feed") ?? raw
            if let href = extractAtomHtmlLink(from: scope) { return href }
        }
        return nil
    }
    private static func extractAtomHtmlLink(from scope: String) -> String? {
        let patterns = [
            #"<link\\b[^>]*rel\\s*=\\s*[\"']alternate[\"'][^>]*href\\s*=\\s*[\"']([^\"']+)[\"'][^>]*/?>"#,
            #"<link\\b[^>]*href\\s*=\\s*[\"']([^\"']+)[\"'][^>]*rel\\s*=\\s*[\"']alternate[\"'][^>]*/?>"#,
            #"<link\\b[^>]*rel\\s*=\\s*[\"'](?:self)?[\"'][^>]*href\\s*=\\s*[\"']([^\"']+)[\"'][^>]*/?>"#,
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: scope, range: NSRange(scope.startIndex..., in: scope)),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: scope) {
                let u = String(scope[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !u.isEmpty { return u }
            }
        }
        return nil
    }
    static func siteFaviconURL(for feedURL: String) -> String? { faviconCandidates(for: feedURL).first }
    /// 候选顺序：优先 UIImage 易解码的 PNG 服务，站点路径次之；.ico 靠后（UIImage 常无法解码）
    static func faviconCandidates(for feedOrSiteURL: String) -> [String] {
        guard let host = hostOf(feedOrSiteURL) else { return [] }
        let scheme: String = {
            if let s = URL(string: feedOrSiteURL)?.scheme, s == "http" || s == "https" { return s }
            return "https"
        }()
        let root = "\(scheme)://\(host)"
        let bareHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        var list: [String] = [
            // 第三方 PNG（解码稳）
            "https://www.google.com/s2/favicons?domain=\(bareHost)&sz=128",
            "https://www.google.com/s2/favicons?domain=\(host)&sz=128",
            "https://icons.duckduckgo.com/ip3/\(bareHost).ico",
            "https://icons.duckduckgo.com/ip3/\(host).ico",
            // 站点常见路径
            "\(root)/apple-touch-icon.png",
            "\(root)/apple-touch-icon-precomposed.png",
            "\(root)/favicon.png",
            "\(root)/favicon.ico",
        ]
        if bareHost != host {
            list.append(contentsOf: [
                "\(scheme)://\(bareHost)/apple-touch-icon.png",
                "\(scheme)://\(bareHost)/favicon.png",
                "\(scheme)://\(bareHost)/favicon.ico",
            ])
        }
        var seen = Set<String>()
        return list.filter { seen.insert($0).inserted }
    }
    static func hostOf(_ urlString: String) -> String? {
        if let h = URL(string: urlString)?.host, !h.isEmpty { return h }
        var s = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = s.range(of: "://") { s = String(s[r.upperBound...]) }
        if let slash = s.firstIndex(of: "/") { s = String(s[..<slash]) }
        if let at = s.firstIndex(of: "@") { s = String(s[s.index(after: at)...]) }
        return s.isEmpty ? nil : s
    }
    private static func looksLikeImageURL(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ("&" + "amp;"), with: "&").lowercased()
        guard t.hasPrefix("http://") || t.hasPrefix("https://") || t.hasPrefix("/") else { return false }
        return true
    }
    private static func absoluteURL(_ maybeRelative: String, relativeTo base: String) -> String {
        var t = maybeRelative.trimmingCharacters(in: .whitespacesAndNewlines)
        t = t.replacingOccurrences(of: ("&" + "amp;"), with: "&")
        if t.lowercased().hasPrefix("http://") || t.lowercased().hasPrefix("https://") { return t }
        if let baseURL = URL(string: base), let resolved = URL(string: t, relativeTo: baseURL) {
            return resolved.absoluteURL.absoluteString
        }
        return t
    }
    private static func extractAttrHref(tagName: String, from xml: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: tagName)
        let pattern = "<\(escaped)\\b[^>]*(?:href|url|src)\\s*=\\s*[\"']([^\"']+)[\"'][^>]*/?>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              let range = Range(match.range(at: 1), in: xml) else { return nil }
        return String(xml[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private static func firstTopLevelBlock(_ xml: String, tag: String) -> String? {
        extractBlocks(from: xml, tag: tag).first
    }
    private static func parseRSS(_ xml: String, feedID: UUID, feedTitle: String) -> [Article] {
        let items = extractBlocks(from: xml, tag: "item")
        return items.compactMap { block -> Article? in
            let title = extractTag("title", from: block) ?? ""
            guard !title.isEmpty else { return nil }
            let link = extractTag("link", from: block) ?? extractTag("guid", from: block) ?? ""
            let description = extractTag("description", from: block) ?? extractTag("summary", from: block) ?? ""
            let content = extractTag("content:encoded", from: block) ?? extractTag("content", from: block) ?? description
            let pubDate = extractTag("pubDate", from: block) ?? extractTag("published", from: block) ?? ""
            let commentsRaw = extractTag("comments", from: block)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let commentsURL = commentsRaw.hasPrefix("http") ? commentsRaw : nil
            return Article(id: UUID(), feedID: feedID, feedTitle: feedTitle, title: stripHTML(title),
                link: link.trimmingCharacters(in: .whitespacesAndNewlines),
                summary: String(stripHTML(description).prefix(200)),
                content: content.isEmpty ? description : content, publishedDate: parseDate(pubDate), isRead: false,
                commentsURL: commentsURL)
        }
    }
    private static func parseAtom(_ xml: String, feedID: UUID, feedTitle: String) -> [Article] {
        let entries = extractBlocks(from: xml, tag: "entry")
        return entries.compactMap { block -> Article? in
            let title = extractTag("title", from: block) ?? ""
            guard !title.isEmpty else { return nil }
            let link = extractLinkHref(from: block)
            let summary = extractTag("summary", from: block) ?? ""
            let content = extractTag("content", from: block) ?? summary
            let published = extractTag("published", from: block) ?? extractTag("updated", from: block) ?? ""
            return Article(id: UUID(), feedID: feedID, feedTitle: feedTitle, title: stripHTML(title), link: link,
                summary: String(stripHTML(summary).prefix(200)), content: content.isEmpty ? summary : content,
                publishedDate: parseDate(published), isRead: false)
        }
    }
    static func extractBlocks(from xml: String, tag: String) -> [String] {
        var blocks: [String] = []
        var search = xml
        let open = "<\(tag)"; let close = "</\(tag)>"
        while let start = search.range(of: open, options: .caseInsensitive) {
            guard let end = search.range(of: close, options: .caseInsensitive, range: start.upperBound..<search.endIndex) else { break }
            blocks.append(String(search[start.lowerBound..<end.upperBound]))
            search = String(search[end.upperBound...])
        }
        return blocks
    }
    static func extractTag(_ tag: String, from xml: String) -> String? {
        let openPat = "<\(tag)[^>]*>"; let closePat = "</\(tag)>"
        guard let openRange = xml.range(of: openPat, options: [.regularExpression, .caseInsensitive]),
              let closeRange = xml.range(of: closePat, options: [.regularExpression, .caseInsensitive],
                                         range: openRange.upperBound..<xml.endIndex) else { return nil }
        var content = String(xml[openRange.upperBound..<closeRange.lowerBound])
        if content.hasPrefix("<![CDATA[") && content.hasSuffix("]]>") {
            content = String(content.dropFirst(9).dropLast(3))
        }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    private static func extractLinkHref(from xml: String) -> String {
        let pattern = #"<link[^>]+href=[\"']([^\"']+)[\"'][^>]*/>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              let range = Range(match.range(at: 1), in: xml) else { return "" }
        return String(xml[range])
    }
    static func stripHTML(_ html: String) -> String { HTMLUtils.stripTags(html) }
    static func parseDate(_ str: String) -> Date? {
        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let formatters = ["EEE, dd MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm:ss zzz",
            "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ss.SSSZ", "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"]
        let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX")
        for fmt in formatters { df.dateFormat = fmt; if let date = df.date(from: trimmed) { return date } }
        return nil
    }
}
enum FeedNaming {
    static func resolveTitle(parsed: String?, url: String) -> String {
        if let t = parsed?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { return t }
        return domainName(from: url)
    }
    static func domainName(from urlString: String) -> String {
        var s = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: s), let host = url.host, !host.isEmpty { return stripWWW(host) }
        if let range = s.range(of: "://") { s = String(s[range.upperBound...]) }
        if let slash = s.firstIndex(of: "/") { s = String(s[..<slash]) }
        if let q = s.firstIndex(of: "?") { s = String(s[..<q]) }
        if let hash = s.firstIndex(of: "#") { s = String(s[..<hash]) }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return stripWWW(s).isEmpty ? urlString : stripWWW(s)
    }
    private static func stripWWW(_ host: String) -> String {
        host.lowercased().hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
/// RSSHub 公共实例兼容：官方站常遇 Cloudflare，自动换同源路径镜像
enum RSSHubSupport {
    /// 优先保留用户原主机，失败后再试镜像
    static let mirrorHosts: [String] = [
        "rsshub.app",
        "rsshub.rssforever.com",
        "hub.slarker.me",
        "rsshub.pseudoyu.com",
        "rss.owo.nz",
        "rsshub.rss.tips",
    ]

    /// Folo 客户端标识（rsshub.app 等对非浏览器 UA 更友好）
    static let foloUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Folo/0.5.7.152"

    /// 为 RSSHub 请求写入 UA / App 头（无具体 Cookie 值时不设 Cookie）
    static func applyRequestHeaders(to request: inout URLRequest) {
        request.setValue(foloUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("Folo Mobile", forHTTPHeaderField: "X-App-Name")
        request.setValue("mobile/ios/iphone", forHTTPHeaderField: "X-App-Platform")
        request.setValue(
            "application/rss+xml, application/atom+xml, application/xml, text/xml, */*;q=0.8",
            forHTTPHeaderField: "Accept"
        )
        request.setValue("https://rsshub.app/", forHTTPHeaderField: "Referer")
    }

    static func isRSSHubURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(), !host.isEmpty else { return false }
        if host == "rsshub.app" || host.hasPrefix("rsshub.") { return true }
        if host.contains("rsshub") { return true }
        return mirrorHosts.contains(host)
    }

    static func isRSSHubURLString(_ s: String) -> Bool {
        guard let u = URL(string: s) else { return false }
        return isRSSHubURL(u)
    }

    /// 同一 path + query，替换主机后的候选列表（原主机在前）
    static func candidateURLs(for url: URL) -> [URL] {
        guard isRSSHubURL(url),
              var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return [url]
        }
        let originalHost = (comps.host ?? "").lowercased()
        var hosts: [String] = []
        if !originalHost.isEmpty { hosts.append(originalHost) }
        for h in mirrorHosts where !hosts.contains(h) { hosts.append(h) }
        var result: [URL] = []
        var seen = Set<String>()
        for host in hosts {
            comps.host = host
            comps.scheme = "https"
            guard let u = comps.url else { continue }
            let key = u.absoluteString
            if seen.insert(key).inserted { result.append(u) }
        }
        return result.isEmpty ? [url] : result
    }

    static func looksLikeCloudflareOrHTMLGate(_ data: Data) -> Bool {
        guard let raw = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else { return false }
        let head = raw.prefix(2500).lowercased()
        if head.contains("just a moment") { return true }
        if head.contains("cf-browser-verification") || head.contains("challenge-platform") { return true }
        if head.contains("cdn-cgi/challenge") { return true }
        if head.contains("<html") && !looksLikeFeedXML(data) { return true }
        return false
    }

    static func looksLikeFeedXML(_ data: Data) -> Bool {
        guard let raw = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else { return false }
        let head = raw.prefix(4096).lowercased()
        if head.contains("<rss") || head.contains("<feed") || head.contains("<rdf:rdf") { return true }
        if head.contains("<channel") && (head.contains("<item") || head.contains("<title")) { return true }
        return false
    }
}

struct FeedDiscovery {
    static func discoverFeeds(from url: URL) async throws -> [DiscoveredFeed] {
        var finalURL = url
        if url.scheme == nil || (url.scheme?.isEmpty ?? true) {
            finalURL = URL(string: "https://\(url.absoluteString)") ?? url
        }
        guard NetworkURLPolicy.isAllowed(finalURL) else {
            throw URLError(.badURL)
        }

        // RSSHub 路由本身就是 Feed：带镜像重试拉取，成功才返回
        if RSSHubSupport.isRSSHubURL(finalURL) {
            let (data, resolved) = try await fetchRSSHubFeed(from: finalURL)
            let articles = FeedParser.parse(data: data, feedID: UUID(), feedTitle: "")
            let title = FeedNaming.resolveTitle(
                parsed: FeedParser.extractFeedTitle(from: data),
                url: resolved.absoluteString
            )
            if articles.isEmpty && FeedParser.extractFeedTitle(from: data) == nil {
                throw URLError(.cannotParseResponse)
            }
            // 仍用用户输入的 URL 作为订阅地址，避免列表被换成镜像域名
            return [DiscoveredFeed(title: title, url: finalURL.absoluteString)]
        }

        let (data, _) = try await URLSession.shared.data(from: finalURL)
        if RSSHubSupport.looksLikeCloudflareOrHTMLGate(data) {
            throw URLError(.noPermissionsToReadFile)
        }
        let articles = FeedParser.parse(data: data, feedID: UUID(), feedTitle: "")
        if !articles.isEmpty {
            let title = FeedNaming.resolveTitle(parsed: FeedParser.extractFeedTitle(from: data), url: finalURL.absoluteString)
            return [DiscoveredFeed(title: title, url: finalURL.absoluteString)]
        }
        return [DiscoveredFeed(title: FeedNaming.domainName(from: finalURL.absoluteString), url: finalURL.absoluteString)]
    }

    /// 拉取 RSSHub（含镜像回退），返回 (data, 实际成功的 URL)
    static func fetchRSSHubFeed(from url: URL) async throws -> (Data, URL) {
        var lastError: Error = URLError(.badServerResponse)
        for candidate in RSSHubSupport.candidateURLs(for: url) {
            do {
                var request = URLRequest(url: candidate, timeoutInterval: 20)
                RSSHubSupport.applyRequestHeaders(to: &request)
                request.cachePolicy = .reloadIgnoringLocalCacheData
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    lastError = URLError(.badServerResponse)
                    continue
                }
                if RSSHubSupport.looksLikeCloudflareOrHTMLGate(data) {
                    lastError = URLError(.noPermissionsToReadFile)
                    continue
                }
                if !RSSHubSupport.looksLikeFeedXML(data) {
                    lastError = URLError(.cannotParseResponse)
                    continue
                }
                return (data, candidate)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }
}
struct DiscoveredFeed: Identifiable { let id = UUID(); let title: String; let url: String }
struct OPMLItem { let title: String; let url: String; var groupName: String? = nil }
struct OPMLParser {
    let data: Data
    func parse() -> [OPMLItem] {
        guard var xml = decodeXMLString(data) else { return [] }
        if xml.hasPrefix("\u{FEFF}") { xml = String(xml.dropFirst()) }
        xml = xml.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        xml = HTMLUtils.decodeEntities(xml)
        var items: [OPMLItem] = []; var seen = Set<String>()
        var currentGroup: String? = nil
        let outlinePattern = "<outline\\b[^>]*(?:/>|>)"
        if let regex = try? NSRegularExpression(pattern: outlinePattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            for match in regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)) {
                guard let matchRange = Range(match.range, in: xml) else { continue }
                let tag = String(xml[matchRange])
                if let rawURL = firstFeedURL(in: tag) {
                    appendItem(url: rawURL, title: titleFromOutline(tag), groupName: currentGroup, seen: &seen, into: &items)
                } else if let folder = titleFromOutline(tag), !folder.isEmpty {
                    currentGroup = folder
                }
            }
        }
        if items.isEmpty {
            for (url, nearby) in scanGlobalFeedURLs(in: xml) {
                appendItem(url: url, title: titleNearURL(in: nearby), seen: &seen, into: &items)
            }
        }
        if items.isEmpty { items.append(contentsOf: parseLinkAlternateFeeds(from: xml, seen: &seen)) }
        return items
    }
    private func appendItem(url raw: String, title: String?, groupName: String? = nil, seen: inout Set<String>, into items: inout [OPMLItem]) {
        let url = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty, looksLikeURL(url) else { return }
        let canonical = FeedURL.canonical(url)
        guard !canonical.isEmpty, !seen.contains(canonical) else { return }
        seen.insert(canonical)
        items.append(OPMLItem(title: FeedNaming.resolveTitle(parsed: title, url: url), url: url, groupName: groupName))
    }
    private func titleFromOutline(_ tag: String) -> String? {
        if let t = extractAttr("text", from: tag) ?? extractAttr("title", from: tag) {
            let cleaned = t.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? nil : cleaned
        }
        return nil
    }
    private func scanGlobalFeedURLs(in xml: String) -> [(url: String, context: String)] {
        var results: [(String, String)] = []
        for key in ["xmlUrl", "xmlurl", "xmlURL", "XMLUrl", "xml_url"] {
            let pattern = "\(NSRegularExpression.escapedPattern(for: key))\\s*=\\s*[\"']([^\"']+)[\"']"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            for match in regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)) {
                guard match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: xml) else { continue }
                let url = String(xml[r])
                let full = match.range
                let start = max(0, full.location - 80)
                let end = min(xml.utf16.count, full.location + full.length + 80)
                let ctxRange = NSRange(location: start, length: end - start)
                let context = Range(ctxRange, in: xml).map { String(xml[$0]) } ?? ""
                if looksLikeURL(url) { results.append((url, context)) }
            }
        }
        return results
    }
    private func titleNearURL(in context: String) -> String? {
        extractAttr("text", from: context) ?? extractAttr("title", from: context)
    }
    private func decodeXMLString(_ data: Data) -> String? {
        var bytes = data
        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF { bytes = bytes.dropFirst(3) }
        if let s = String(data: bytes, encoding: .utf8), !s.isEmpty { return s }
        if let s = String(data: data, encoding: .utf16), !s.isEmpty { return s }
        if let s = String(data: data, encoding: .isoLatin1), !s.isEmpty { return s }
        let s = String(decoding: bytes, as: UTF8.self)
        return s.isEmpty ? nil : s
    }
    private func firstFeedURL(in tag: String) -> String? {
        for key in ["xmlUrl", "xmlurl", "xmlURL", "XMLUrl", "xml_url"] {
            if let v = extractAttr(key, from: tag), looksLikeURL(v) { return v }
        }
        let type = (extractAttr("type", from: tag) ?? "").lowercased()
        let isFeedType = type.contains("rss") || type.contains("atom") || type == "feed"
        if let v = extractAttr("url", from: tag), looksLikeURL(v), isFeedType || looksLikeFeedURL(v) { return v }
        if let v = extractAttr("htmlUrl", from: tag), looksLikeFeedURL(v) { return v }
        return nil
    }
    private func looksLikeURL(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return t.hasPrefix("http://") || t.hasPrefix("https://") || t.hasPrefix("feed://")
    }
    private func looksLikeFeedURL(_ s: String) -> Bool {
        guard looksLikeURL(s) else { return false }
        let t = s.lowercased()
        return t.contains("rss") || t.contains("atom") || t.contains("feed") || t.contains(".xml")
    }
    private func extractAttr(_ attr: String, from tag: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: attr)
        let pattern = "\(escaped)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s/>]+))"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)) else { return nil }
        for i in 1...3 {
            if match.numberOfRanges > i, let range = Range(match.range(at: i), in: tag) {
                let value = String(tag[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { return value }
            }
        }
        return nil
    }
    private func parseLinkAlternateFeeds(from xml: String, seen: inout Set<String>) -> [OPMLItem] {
        var items: [OPMLItem] = []
        let pattern = "<link\\b[^>]*>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        for match in regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)) {
            guard let r = Range(match.range, in: xml) else { continue }
            let tag = String(xml[r])
            let type = (extractAttr("type", from: tag) ?? "").lowercased()
            let rel = (extractAttr("rel", from: tag) ?? "").lowercased()
            let isFeed = type.contains("rss") || type.contains("atom") || type.contains("xml")
            guard isFeed || (rel == "alternate" && (type.contains("rss") || type.contains("atom"))) else { continue }
            guard let href = extractAttr("href", from: tag), looksLikeURL(href) else { continue }
            appendItem(url: href, title: extractAttr("title", from: tag), seen: &seen, into: &items)
        }
        return items
    }
}
