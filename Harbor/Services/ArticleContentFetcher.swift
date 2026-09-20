import Foundation

/// 从文章原文页抓取完整正文（启发式 Readability 风格提取）
/// 参考常见 RSS 阅读器：拉取 HTML → 去噪 → 候选区块打分 → 输出干净 HTML
enum ArticleContentFetcher {

    struct Result {
        let title: String?
        let contentHTML: String
        let textLength: Int
    }

    enum FetchError: LocalizedError {
        case invalidURL
        case network(String)
        case emptyContent
        case tooShort
        /// Cloudflare / 人机验证等，需在浏览器中打开
        case cloudflareChallenge

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "无效的文章链接"
            case .network(let msg): return "网络错误：\(msg)"
            case .emptyContent: return "未能提取到正文内容"
            case .tooShort: return "提取到的正文过短，可能被网站拦截"
            case .cloudflareChallenge: return "网站开启了 Cloudflare 人机验证，应用内无法抓取全文，请用浏览器打开"
            }
        }

        var isCloudflare: Bool {
            if case .cloudflareChallenge = self { return true }
            return false
        }
    }

    static func fetchFullContent(from urlString: String) async throws -> Result {
        guard let url = NetworkURLPolicy.validate(urlString) else {
            throw FetchError.invalidURL
        }

        if let cached = OfflineCache.loadArticleHTML(link: urlString), !cached.isEmpty {
            let len = HTMLUtils.stripTags(cached).count
            if len >= 80 {
                return Result(title: nil, contentHTML: cached, textLength: len)
            }
        }

        // 少数派：优先官方 JSON API（正文含完整 img）
        if let apiResult = await fetchSspaiAPI(pageURL: url) {
            OfflineCache.saveArticleHTML(link: urlString, html: apiResult.contentHTML)
            return apiResult
        }

        // Sixth Tone：__NEXT_DATA__ 含完整正文 + textImageList 配图
        if isSixthToneHost(url.host) {
            if let st = await fetchSixthToneContent(pageURL: url) {
                OfflineCache.saveArticleHTML(link: urlString, html: st.contentHTML)
                return st
            }
        }

        // SCMP：正文在 __NEXT_DATA__（GraphQL payload），通用 HTML 启发式几乎抓不到
        if isSCMPHost(url.host) {
            if let scmp = await fetchSCMPContent(pageURL: url) {
                OfflineCache.saveArticleHTML(link: urlString, html: scmp.contentHTML)
                return scmp
            }
        }

        // WordPress 站点（如 Visual Capitalist）：优先 slug REST，常可绕过部分前端门禁
        if isWordPressChartHost(url.host),
           let wp = await fetchWordPressBySlug(pageURL: url) {
            OfflineCache.saveArticleHTML(link: urlString, html: wp.content)
            let len = HTMLUtils.stripTags(wp.content).count
            if len >= 80 {
                return Result(title: wp.title, contentHTML: wp.content, textLength: len)
            }
        }

        var request = URLRequest(url: url, timeoutInterval: 25)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9,zh-CN;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("https://www.google.com/", forHTTPHeaderField: "Referer")
        request.setValue("1", forHTTPHeaderField: "Upgrade-Insecure-Requests")
        // 全文抓取不要用可能过期的空壳缓存
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            if let cached = OfflineCache.loadArticleHTML(link: urlString), !cached.isEmpty {
                let len = HTMLUtils.stripTags(cached).count
                return Result(title: nil, contentHTML: cached, textLength: len)
            }
            throw FetchError.network(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            if let cached = OfflineCache.loadArticleHTML(link: urlString), !cached.isEmpty {
                let len = HTMLUtils.stripTags(cached).count
                return Result(title: nil, contentHTML: cached, textLength: len)
            }
            throw FetchError.network("HTTP \(http.statusCode)")
        }

        let html = decodeHTML(data: data) ?? ""
        guard !html.isEmpty else { throw FetchError.emptyContent }

        // 已有可用 __NEXT_DATA__ 正文时，不要因页尾 CF 脚本误判为人机验证
        if isCloudflareChallenge(html: html, response: response),
           extractSCMP(from: html, baseURL: url) == nil,
           extractSixthTone(from: html, baseURL: url) == nil {
            throw FetchError.cloudflareChallenge
        }

        // Sixth Tone：从页面内嵌 __NEXT_DATA__ 提取（避免脚本被通用去噪删掉后丢失正文图）
        if isSixthToneHost(url.host), let st = extractSixthTone(from: html, baseURL: url) {
            OfflineCache.saveArticleHTML(link: urlString, html: st.contentHTML)
            return st
        }

        // SCMP / 同类 Next 文章
        if let scmp = extractSCMP(from: html, baseURL: url) {
            OfflineCache.saveArticleHTML(link: urlString, html: scmp.contentHTML)
            return scmp
        }

        var extracted = extractArticle(from: html, baseURL: url)
        var plainLen = HTMLUtils.stripTags(extracted.content).count

        // HTML 启发式过短时，尝试 WordPress REST API（量子位等 WP 站点）
        if plainLen < 400, let wp = await fetchWordPressContent(pageURL: url, pageHTML: html) {
            let wpLen = HTMLUtils.stripTags(wp.content).count
            if wpLen > plainLen {
                extracted = wp
                plainLen = wpLen
            }
        }

        if plainLen < 80 {
            // 过短也可能是挑战页漏检，再扫一次常见 CF 文案
            if isCloudflareChallenge(html: html, response: response) {
                throw FetchError.cloudflareChallenge
            }
            throw FetchError.tooShort
        }
        OfflineCache.saveArticleHTML(link: urlString, html: extracted.content)
        return Result(title: extracted.title, contentHTML: extracted.content, textLength: plainLen)
    }

    /// 识别 Cloudflare / 常见人机验证页（正文抓取无法完成）
    private static func isCloudflareChallenge(html: String, response: URLResponse) -> Bool {
        if let http = response as? HTTPURLResponse {
            let code = http.statusCode
            if code == 403 || code == 503 {
                let server = (http.value(forHTTPHeaderField: "Server") ?? "").lowercased()
                if server.contains("cloudflare") { return true }
            }
            // CF 常通过这些响应头标记
            if http.value(forHTTPHeaderField: "cf-mitigated") != nil { return true }
        }
        // 只扫前 12KB，避免对整篇正文 lowercased 造成多余内存与 CPU
        let head = html.prefix(12_288)
        let lower = head.lowercased()
        let markers = [
            "cf-browser-verification",
            "cf-challenge",
            "challenge-platform",
            "cdn-cgi/challenge",
            "just a moment...",
            "checking your browser",
            "enable javascript and cookies to continue",
            "attention required! | cloudflare",
            "请完成安全验证",
            "人机验证",
            "verify you are human",
            "managed_challenge",
            "turnstile"
        ]
        return markers.contains { lower.contains($0) }
    }

    // MARK: - WordPress REST fallback

    private static func fetchWordPressContent(pageURL: URL, pageHTML: String) async -> Extracted? {
        var apiURL: URL?
        if let link = matchFirst(#"<link[^>]+type=[\"']application/json[\"'][^>]+href=[\"']([^\"']+)[\"']"#, in: pageHTML)
            ?? matchFirst(#"<link[^>]+href=[\"']([^\"']+)[\"'][^>]+type=[\"']application/json[\"']"#, in: pageHTML) {
            apiURL = URL(string: link)
        }
        if apiURL == nil, let id = matchFirst(#"/wp-json/wp/v2/posts/(\d+)"#, in: pageHTML) {
            if var comps = URLComponents(url: pageURL, resolvingAgainstBaseURL: false) {
                comps.path = "/wp-json/wp/v2/posts/\(id)"
                comps.query = nil
                comps.fragment = nil
                apiURL = comps.url
            }
        }
        if apiURL == nil {
            let postID = matchFirst(#"[?&]p=(\d+)"#, in: pageURL.absoluteString)
                ?? matchFirst(#"/\d{4}/\d{2}/(\d+)\.html"#, in: pageURL.absoluteString)
            if let postID, var comps = URLComponents(url: pageURL, resolvingAgainstBaseURL: false) {
                comps.path = "/wp-json/wp/v2/posts/\(postID)"
                comps.query = nil
                comps.fragment = nil
                apiURL = comps.url
            }
        }
        guard let apiURL else { return nil }

        var request = URLRequest(url: apiURL, timeoutInterval: 15)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return nil
            }
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            let contentHTML: String? = {
                if let content = obj["content"] as? [String: Any],
                   let rendered = content["rendered"] as? String { return rendered }
                return nil
            }()
            let title: String? = {
                if let t = obj["title"] as? [String: Any], let rendered = t["rendered"] as? String {
                    return HTMLUtils.stripTags(rendered).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                return nil
            }()
            guard let contentHTML, !contentHTML.isEmpty else { return nil }
            let cleaned = cleanContentHTML(contentHTML, baseURL: pageURL)
            let len = HTMLUtils.stripTags(cleaned).count
            guard len >= 120 else { return nil }
            return Extracted(title: title, content: cleaned)
        } catch {
            return nil
        }
    }

    // MARK: - Encoding

    private static func decodeHTML(data: Data) -> String? {
        if let s = String(data: data, encoding: .utf8) { return s }
        if let s = String(data: data, encoding: .isoLatin1) { return s }
        if let probe = String(data: data.prefix(2048), encoding: .isoLatin1),
           let range = probe.range(of: #"charset=[\"']?([^\"'>\s]+)"#, options: .regularExpression) {
            let matched = String(probe[range])
            if matched.lowercased().contains("gb") {
                let cfEnc = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
                return String(data: data, encoding: String.Encoding(rawValue: cfEnc))
            }
        }
        return String(data: data, encoding: .windowsCP1252)
    }

    private struct Extracted {
        var title: String?
        var content: String
    }

    /// 少数派公开 API：`/api/v1/articles/{id}`，body 为带图 HTML
    private static func fetchSspaiAPI(pageURL: URL) async -> Result? {
        let host = pageURL.host?.lowercased() ?? ""
        guard host == "sspai.com" || host.hasSuffix(".sspai.com") else { return nil }
        let parts = pageURL.path.split(separator: "/").map(String.init)
        guard let pIdx = parts.firstIndex(of: "post"),
              pIdx + 1 < parts.count,
              parts[pIdx + 1].allSatisfy({ $0.isNumber }) else {
            return nil // /prime/story/slug 无公开 id，走 HTML 提取
        }
        let articleID = parts[pIdx + 1]
        guard let apiURL = URL(string: "https://sspai.com/api/v1/articles/\(articleID)") else { return nil }

        var request = URLRequest(url: apiURL, timeoutInterval: 20)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://sspai.com/", forHTTPHeaderField: "Referer")

        let data: Data
        do {
            let (d, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            data = d
        } catch {
            return nil
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let body = json["body"] as? String, !body.isEmpty else {
            return nil
        }
        var html = body
        // 封面图
        if let banner = json["banner"] as? String, !banner.isEmpty {
            let bannerURL: String
            if banner.hasPrefix("http") {
                bannerURL = banner
            } else {
                bannerURL = "https://cdnfile.sspai.com/" + banner.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            }
            if !html.localizedCaseInsensitiveContains(bannerURL) {
                html = "<p><img src=\"\(bannerURL)\" /></p>\n" + html
            }
        }
        // 规范化相对协议图片
        html = html.replacingOccurrences(of: "src=\"//", with: "src=\"https://")
        html = html.replacingOccurrences(of: "src='//", with: "src='https://")
        let cleaned = cleanContentHTML(html, baseURL: pageURL)
        let len = HTMLUtils.stripTags(cleaned).count
        guard len >= 80 else { return nil }
        let title = (json["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return Result(title: title, contentHTML: cleaned, textLength: len)
    }

    // MARK: - SCMP (Next.js __NEXT_DATA__ GraphQL payload)

    private static func isSCMPHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "scmp.com"
            || host.hasSuffix(".scmp.com")
            || host == "i-scmp.com"
            || host.hasSuffix(".i-scmp.com")
    }

    private static func fetchSCMPContent(pageURL: URL) async -> Result? {
        var request = URLRequest(url: pageURL, timeoutInterval: 28)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("https://www.scmp.com/", forHTTPHeaderField: "Referer")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return nil
            }
            guard let html = decodeHTML(data: data), !html.isEmpty else { return nil }
            return extractSCMP(from: html, baseURL: pageURL)
        } catch {
            return nil
        }
    }

    /// 从 SCMP `__NEXT_DATA__` 取 article.body（text / json 段落）+ 封面图
    private static func extractSCMP(from html: String, baseURL: URL) -> Result? {
        guard let jsonText = matchFirst(
            #"<script[^>]*id=[\"']__NEXT_DATA__[\"'][^>]*>([\s\S]*?)</script>"#,
            in: html
        ) else { return nil }
        guard let data = jsonText.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let props = root["props"] as? [String: Any],
              let pageProps = props["pageProps"] as? [String: Any] else {
            return nil
        }

        let article: [String: Any]? = {
            if let payload = pageProps["payload"] as? [String: Any] {
                if let dataObj = payload["data"] as? [String: Any],
                   let art = dataObj["article"] as? [String: Any] {
                    return art
                }
                if let json = payload["json"] as? [String: Any],
                   let dataObj = json["data"] as? [String: Any],
                   let art = dataObj["article"] as? [String: Any] {
                    return art
                }
            }
            if let art = pageProps["article"] as? [String: Any] { return art }
            return nil
        }()
        guard let article else { return nil }

        let title = (article["headline"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? (article["socialHeadline"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var parts: [String] = []

        if let images = article["images"] as? [[String: Any]] {
            for img in images {
                if let url = scmpBestImageURL(from: img), !url.isEmpty {
                    parts.append("<p><img src=\"\(url)\" /></p>")
                    break
                }
            }
        }

        if let body = article["body"] as? [String: Any] {
            var gotParas = false
            if let jsonNodes = body["json"] as? [[String: Any]] {
                let htmlParts = scmpParagraphsHTML(from: jsonNodes)
                if !htmlParts.isEmpty {
                    parts.append(contentsOf: htmlParts)
                    gotParas = true
                }
            }
            if !gotParas, let plain = body["text"] as? String {
                let paras = plain
                    .components(separatedBy: CharacterSet.newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                for p in paras {
                    parts.append("<p>\(escapeHTMLText(p))</p>")
                }
            }
        }

        let merged = parts.joined(separator: "\n")
        let cleaned = cleanContentHTML(merged, baseURL: baseURL)
        let len = HTMLUtils.stripTags(cleaned).count
        guard len >= 80 else { return nil }
        return Result(title: title, contentHTML: cleaned, textLength: len)
    }

    private static func scmpBestImageURL(from img: [String: Any]) -> String? {
        let preferredKeys = [
            "1280x720", "768x768", "og_image_scmp_generic", "generic_og",
            "og_image_style", "url"
        ]
        for key in preferredKeys {
            if let s = img[key] as? String, s.hasPrefix("http") { return s }
            if let obj = img[key] as? [String: Any],
               let s = obj["url"] as? String, s.hasPrefix("http") {
                return s
            }
        }
        for (_, v) in img {
            if let s = v as? String, s.hasPrefix("http"), s.contains("cdn.i-scmp.com") {
                return s
            }
            if let obj = v as? [String: Any],
               let s = obj["url"] as? String, s.hasPrefix("http") {
                return s
            }
        }
        return nil
    }

    private static func scmpParagraphsHTML(from nodes: [[String: Any]]) -> [String] {
        var out: [String] = []
        out.reserveCapacity(nodes.count)
        for node in nodes {
            let type = (node["type"] as? String)?.lowercased() ?? ""
            switch type {
            case "p", "paragraph":
                let text = scmpCollectText(node).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                out.append("<p>\(escapeHTMLText(text))</p>")
            case "h1", "h2", "h3", "h4":
                let text = scmpCollectText(node).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                out.append("<\(type)>\(escapeHTMLText(text))</\(type)>")
            case "blockquote":
                let text = scmpCollectText(node).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                out.append("<blockquote><p>\(escapeHTMLText(text))</p></blockquote>")
            default:
                continue
            }
        }
        return out
    }

    private static func scmpCollectText(_ node: Any) -> String {
        if let s = node as? String { return s }
        if let arr = node as? [Any] {
            return arr.map { scmpCollectText($0) }.joined()
        }
        guard let dict = node as? [String: Any] else { return "" }
        if let data = dict["data"] as? String { return data }
        if let text = dict["text"] as? String { return text }
        if let children = dict["children"] as? [Any] {
            return children.map { scmpCollectText($0) }.joined()
        }
        return ""
    }

    // MARK: - Sixth Tone (Next.js __NEXT_DATA__)

    private static func isSixthToneHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "sixthtone.com" || host.hasSuffix(".sixthtone.com")
    }

    /// 拉取页面并解析 __NEXT_DATA__（与 sspai 一样走专用通道，避免通用启发式丢图）
    private static func fetchSixthToneContent(pageURL: URL) async -> Result? {
        var request = URLRequest(url: pageURL, timeoutInterval: 25)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("https://www.sixthtone.com/", forHTTPHeaderField: "Referer")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return nil
            }
            guard let html = decodeHTML(data: data), !html.isEmpty else { return nil }
            return extractSixthTone(from: html, baseURL: pageURL)
        } catch {
            return nil
        }
    }

    /// 从页面 `__NEXT_DATA__` 取出 detailData.data.content + textImageList 配图
    private static func extractSixthTone(from html: String, baseURL: URL) -> Result? {
        guard let jsonText = matchFirst(
            #"<script[^>]*id=[\"']__NEXT_DATA__[\"'][^>]*>([\s\S]*?)</script>"#,
            in: html
        ) else { return nil }
        guard let data = jsonText.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let props = root["props"] as? [String: Any],
              let pageProps = props["pageProps"] as? [String: Any] else {
            return nil
        }

        // detailData 可能是 { code, data: {...} } 或直接为文章对象
        let article: [String: Any]? = {
            if let detail = pageProps["detailData"] as? [String: Any] {
                if let inner = detail["data"] as? [String: Any] { return inner }
                if detail["content"] != nil { return detail }
            }
            if let d = pageProps["data"] as? [String: Any] { return d }
            return nil
        }()
        guard let article else { return nil }

        let contentHTML = (article["content"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !contentHTML.isEmpty else { return nil }

        let title = (article["name"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var parts: [String] = []

        // 封面图（headPic / bigPic）
        let cover = (article["headPic"] as? String)
            ?? (article["bigPic"] as? String)
            ?? (article["smallPic"] as? String)
        if let cover, !cover.isEmpty, contentHTML.range(of: cover, options: .caseInsensitive) == nil {
            parts.append("<p><img src=\"\(absoluteSixthToneURL(cover, base: baseURL))\" /></p>")
        }

        parts.append(contentHTML)

        // 正文内通常无 <img>，配图在 textImageList
        if let images = article["textImageList"] as? [[String: Any]] {
            for img in images {
                guard let rawURL = img["url"] as? String, !rawURL.isEmpty else { continue }
                let abs = absoluteSixthToneURL(rawURL, base: baseURL)
                if contentHTML.range(of: abs, options: .caseInsensitive) != nil
                    || contentHTML.range(of: rawURL, options: .caseInsensitive) != nil {
                    continue
                }
                var block = "<figure><img src=\"\(abs)\" />"
                if let desc = img["desc"] as? String {
                    let caption = HTMLUtils.stripTags(desc)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !caption.isEmpty {
                        block += "<figcaption>\(escapeHTMLText(caption))</figcaption>"
                    }
                }
                block += "</figure>"
                parts.append(block)
            }
        }

        let merged = parts.joined(separator: "\n")
        let cleaned = cleanContentHTML(merged, baseURL: baseURL)
        let len = HTMLUtils.stripTags(cleaned).count
        guard len >= 80 else { return nil }
        return Result(title: title, contentHTML: cleaned, textLength: len)
    }

    private static func absoluteSixthToneURL(_ raw: String, base: URL) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("//") { return "https:" + t }
        if t.hasPrefix("http://") || t.hasPrefix("https://") { return t }
        if let u = URL(string: t, relativeTo: base)?.absoluteString { return u }
        return t
    }

    private static func escapeHTMLText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func extractArticle(from html: String, baseURL: URL) -> Extracted {

        var work = html
        let noiseTags = ["script", "style", "noscript", "svg", "iframe", "object", "embed", "form", "nav", "footer", "header", "aside"]
        for tag in noiseTags {
            work = removeTagBlocks(work, tag: tag)
        }
        work = work.replacingOccurrences(of: #"<!--[\s\S]*?-->"#, with: "", options: .regularExpression)

        let title = extractTitle(from: html)

        // 站点特化：在通用语义标签之前尝试（避免 <article> 只匹配到订阅墙短文）
        if let site = extractByKnownSite(work, host: baseURL.host?.lowercased() ?? "") {
            let cleaned = cleanContentHTML(truncateArticleTail(site), baseURL: baseURL)
            if HTMLUtils.stripTags(cleaned).count >= 200 {
                return Extracted(title: title, content: cleaned)
            }
        }

        if let semantic = extractBySemanticTags(work) {
            let cleaned = cleanContentHTML(truncateArticleTail(semantic), baseURL: baseURL)
            // 语义块若明显短于全文启发式，继续往下试
            let semLen = HTMLUtils.stripTags(cleaned).count
            if semLen >= 800 {
                return Extracted(title: title, content: cleaned)
            }
            if let candidate = extractByHeuristics(work) {
                let cand = cleanContentHTML(truncateArticleTail(candidate), baseURL: baseURL)
                if HTMLUtils.stripTags(cand).count > semLen + 200 {
                    return Extracted(title: title, content: cand)
                }
            }
            if semLen >= 120 {
                return Extracted(title: title, content: cleaned)
            }
        }

        if let candidate = extractByHeuristics(work) {
            let cleaned = cleanContentHTML(truncateArticleTail(candidate), baseURL: baseURL)
            if HTMLUtils.stripTags(cleaned).count >= 80 {
                return Extracted(title: title, content: cleaned)
            }
        }

        let paragraphs = collectParagraphs(work)
        if !paragraphs.isEmpty {
            let joined = paragraphs.map { "<p>\($0)</p>" }.joined(separator: "\n")
            return Extracted(title: title, content: cleanContentHTML(joined, baseURL: baseURL))
        }

        let plain = HTMLUtils.stripTags(work)
        return Extracted(title: title, content: "<p>\(plain.prefix(8000))</p>")
    }

    private static func extractTitle(from html: String) -> String? {
        if let og = matchFirst(#"<meta[^>]+property=[\"']og:title[\"'][^>]+content=[\"']([^\"']+)[\"']"#, in: html)
            ?? matchFirst(#"<meta[^>]+content=[\"']([^\"']+)[\"'][^>]+property=[\"']og:title[\"']"#, in: html) {
            return HTMLUtils.decodeEntities(og).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let t = matchFirst(#"<title[^>]*>([\s\S]*?)</title>"#, in: html) {
            return HTMLUtils.decodeEntities(t).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let h1 = matchFirst(#"<h1[^>]*>([\s\S]*?)</h1>"#, in: html) {
            return HTMLUtils.stripTags(h1).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    /// 已知站点正文容器（Foreign Affairs / CarNewsChina 等）
    private static func extractByKnownSite(_ html: String, host: String) -> String? {
        let selectors: [String]
        if host == "foreignaffairs.com" || host.hasSuffix(".foreignaffairs.com") {
            // 正文在 paywall-content / article-dropcap--inner；外层含分享与订阅 CTA
            selectors = [
                "paywall-content",
                "article-dropcap--inner",
                "article__body-content",
                "rich-text__inner"
            ]
        } else if host == "foreignpolicy.com" || host.hasSuffix(".foreignpolicy.com") {
            selectors = [
                "content-gated--main-article",
                "content-gated",
                "post-content-main",
                "content-ungated",
                "post-content"
            ]
        } else if host == "visualcapitalist.com" || host.hasSuffix(".visualcapitalist.com") {
            selectors = [
                "entry-content",
                "post-content",
                "wp-block-post-content",
                "article-content",
                "single-content",
                "content-inner"
            ]
        } else if host == "sspai.com" || host.hasSuffix(".sspai.com") {
            selectors = [
                "article__main__content",
                "wangEditor-txt",
                "prime__story__body",
                "article-body",
                "normal-article"
            ]
        } else if host == "carnewschina.com" || host.hasSuffix(".carnewschina.com") {
            // WP REST 常需鉴权；正文在 js-main-post（比整篇 <article> 少侧栏/订阅页脚）
            selectors = [
                "js-main-post",
                "post_detail__content",
                "post-detail__content"
            ]
        } else {
            selectors = []
        }
        var best: String?
        var bestLen = 0
        for token in selectors {
            let escaped = NSRegularExpression.escapedPattern(for: token)
            let pattern = "<(div|section)([^>]*class=[\"'][^\"']*" + escaped + "[^\"']*[\"'][^>]*)>"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let ns = html as NSString
            for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
                guard match.numberOfRanges >= 2,
                      let tagRange = Range(match.range(at: 1), in: html),
                      let fullOpen = Range(match.range, in: html) else { continue }
                let tag = String(html[tagRange])
                guard var block = extractBalancedFromOpen(html, openEnd: fullOpen.upperBound, tag: tag) else { continue }
                // 截掉推荐/评论/订阅页脚，避免正文后大片空白与噪音
                block = truncateArticleTail(block)
                let len = HTMLUtils.stripTags(block).count
                if len > bestLen {
                    bestLen = len
                    best = block
                }
            }
        }
        if let best, host == "foreignaffairs.com" || host.hasSuffix(".foreignaffairs.com") {
            return sanitizeForeignAffairsBody(best)
        }
        return bestLen >= 200 ? best : nil
    }

    /// Foreign Affairs：去掉订阅 CTA、JS 提示，保留段落正文
    private static func sanitizeForeignAffairsBody(_ html: String) -> String {
        var work = truncateArticleTail(html)
        // 去掉文末 Loading / enable JavaScript 行
        work = work.replacingOccurrences(
            of: #"<p[^>]*>\s*Loading\.\.\.\s*</p>"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        work = work.replacingOccurrences(
            of: #"<[^>]+>\s*Please enable JavaScript[\s\S]*?function properly\.?\s*</[^>]+>"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        // 去掉仅含 Share / Subscribe 工具条短段
        work = work.replacingOccurrences(
            of: #"<p[^>]*>\s*(?:Share|Subscribe|Sign In|Sign in)\s*</p>"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        let textLen = HTMLUtils.stripTags(work).trimmingCharacters(in: .whitespacesAndNewlines).count
        return textLen >= 200 ? work : html
    }

    /// 去掉正文末尾的推荐阅读、评论、邮件订阅等尾巴（仅截后半段命中，避免误伤正文）
    private static func truncateArticleTail(_ html: String) -> String {
        guard html.count > 400 else { return html }
        let markers = [
            "Recommended for you",
            "Most important news in your inbox",
            "Show all 27 topics",
            "0 of 27 topics selected",
            "Bundle into one email per day",
            "Join our Telegram",
            "Follow us on Google News",
            "Subscribe to Foreign Affairs",
            "Already a subscriber?",
            "Please enable JavaScript for this site",
            "Unlock access to the Foreign Affairs",
            "Paywall-free reading",
            "Sign up to our free newsletter",
            "If you found this post interesting",
            "Continue reading on the free Voronoi",
            "class=\"comments\"",
            "id=\"comments\"",
            "class=\"related",
            "class=\"post-related",
            "class=\"recommend"
        ]
        // 只在正文约 35% 之后查找尾巴标记
        let minOffset = html.index(html.startIndex, offsetBy: html.count * 35 / 100)
        var cut: String.Index?
        let lower = html.lowercased()
        for m in markers {
            if let r = lower.range(of: m.lowercased(), range: minOffset..<lower.endIndex) {
                let idx = r.lowerBound
                if cut == nil || idx < cut! { cut = idx }
            }
        }
        // Source: 保留该行，在其后截断
        if let r = html.range(
            of: #"<p[^>]*>\s*Source\s*:"#,
            options: [.regularExpression, .caseInsensitive],
            range: minOffset..<html.endIndex
        ) {
            if let close = html.range(of: "</p>", options: .caseInsensitive, range: r.lowerBound..<html.endIndex) {
                let after = close.upperBound
                if cut == nil || after < cut! { cut = after }
            }
        }
        if let cut { return String(html[..<cut]) }
        return html
    }

    private static func extractBySemanticTags(_ html: String) -> String? {

        for tag in ["article", "main"] {
            if let block = extractBalancedTagContent(html, tag: tag) {
                let textLen = HTMLUtils.stripTags(block).count
                if textLen >= 120 { return block }
            }
        }
        if let open = firstMatchRange(#"<([a-zA-Z0-9]+)[^>]*role=[\"']main[\"'][^>]*>"#, in: html),
           let tagName = matchFirst(#"<([a-zA-Z0-9]+)[^>]*role=[\"']main[\"']"#, in: html),
           let block = extractBalancedFromOpen(html, openEnd: open.upperBound, tag: tagName) {
            let textLen = HTMLUtils.stripTags(block).count
            if textLen >= 120 { return block }
        }
        return nil
    }

    private static func extractByHeuristics(_ html: String) -> String? {
        // 平衡标签匹配，避免嵌套 div 被非贪婪正则截断（量子位等站点）
        let openPattern = #"<(div|section|td|article)([^>]*(?:class|id)=[\"'][^\"']*(?:article|post|content|entry|story|body|main|text|rich|detail|dropcap|paywall|gated|ungated)[^\"']*[\"'][^>]*)>"#
        guard let regex = try? NSRegularExpression(pattern: openPattern, options: .caseInsensitive) else { return nil }
        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))

        var best: (score: Double, html: String)?
        for match in matches {
            guard match.numberOfRanges >= 3,
                  let tagRange = Range(match.range(at: 1), in: html),
                  let fullOpen = Range(match.range, in: html) else { continue }
            let tag = String(html[tagRange])
            let openAttrs = Range(match.range(at: 2), in: html).map { String(html[$0]) } ?? ""
            let openLower = openAttrs.lowercased()

            let skipTokens = ["text_box", "picture_text", "sidebar", "related", "recommend",
                              "comment", "share_box", "share_pc", "nav_", "menu", "footer",
                              "breadcrumb", "pagination", "hot-list", "hot_list"]
            if skipTokens.contains(where: { openLower.contains($0) }) { continue }

            guard let block = extractBalancedFromOpen(html, openEnd: fullOpen.upperBound, tag: tag) else { continue }
            let score = scoreBlock(block, openAttrs: openAttrs)
            if score > (best?.score ?? 0) {
                best = (score, block)
            }
        }
        if let best, HTMLUtils.stripTags(best.html).count >= 200 {
            return best.html
        }
        return best.map { HTMLUtils.stripTags($0.html).count >= 120 ? $0.html : nil } ?? nil
    }

    private static func scoreBlock(_ html: String, openAttrs: String = "") -> Double {
        let text = HTMLUtils.stripTags(html)
        let len = Double(text.count)
        guard len > 50 else { return 0 }

        let pCount = countMatches(#"<p[\s>]"#, in: html)
        let commaCount = text.filter { $0 == "," || $0 == "，" }.count
        let linkTextLen = extractLinkTextLength(html)
        let linkDensity = len > 0 ? Double(linkTextLen) / len : 1

        var score = len * 0.01
        score += Double(pCount) * 4
        score += Double(commaCount) * 0.5
        if linkDensity > 0.35 { score *= 0.25 }
        else if linkDensity > 0.2 { score *= 0.55 }

        let lower = (html + " " + openAttrs).lowercased()
        for bad in ["comment", "share", "related", "recommend", "sidebar", "footer", "nav", "advert", "promo", "text_box", "picture_text"] {
            if lower.contains(bad) { score *= 0.4 }
        }
        for good in ["entry-content", "post-content", "article-content", "article_content",
                     "post_content", "single-content", "rich-content", "article-body", "post-body",
                     "article__body", "body-content", "paywall-content", "rich-text", "dropcap",
                     "content-gated", "content-ungated", "post-content-main",
                     "wangEditor", "article__main", "prime__story",
                     "js-main-post", "post_detail__content", "post-detail__content"] {
            if openAttrs.lowercased().contains(good) { score *= 2.5; break }
        }
        if openAttrs.lowercased().contains("class=\"article\"")
            || openAttrs.lowercased().contains("class='article'")
            || openAttrs.lowercased().contains(" article ") {
            score *= 1.8
        }
        if len < 400 { score *= 0.5 }
        if len < 200 { score *= 0.4 }
        return score
    }

    private static func extractLinkTextLength(_ html: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: #"<a[^>]*>([\s\S]*?)</a>"#, options: .caseInsensitive) else { return 0 }
        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        var total = 0
        for m in matches {
            if m.numberOfRanges >= 2, let r = Range(m.range(at: 1), in: html) {
                total += HTMLUtils.stripTags(String(html[r])).count
            }
        }
        return total
    }

    private static func collectParagraphs(_ html: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"<p[^>]*>([\s\S]*?)</p>"#, options: .caseInsensitive) else { return [] }
        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        var result: [String] = []
        for m in matches {
            if m.numberOfRanges >= 2, let r = Range(m.range(at: 1), in: html) {
                let text = HTMLUtils.stripTags(String(html[r])).trimmingCharacters(in: .whitespacesAndNewlines)
                if text.count >= 40 {
                    result.append(HTMLUtils.decodeEntities(text))
                }
            }
        }
        return result
    }

    private static func removeTagBlocks(_ html: String, tag: String) -> String {
        var result = html
        let pair = "<\(tag)\\b[^>]*>[\\s\\S]*?</\(tag)>"
        result = result.replacingOccurrences(of: pair, with: "", options: [.regularExpression, .caseInsensitive])
        let selfClosing = "<\(tag)\\b[^>]*/?>"
        result = result.replacingOccurrences(of: selfClosing, with: "", options: [.regularExpression, .caseInsensitive])
        return result
    }

    private static func extractBalancedTagContent(_ html: String, tag: String) -> String? {
        let openPattern = "<\(tag)\\b[^>]*>"
        guard let regex = try? NSRegularExpression(pattern: openPattern, options: .caseInsensitive) else { return nil }
        let ns = html as NSString
        let opens = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        var best: String?
        var bestLen = 0
        for open in opens {
            guard let openRange = Range(open.range, in: html) else { continue }
            if let block = extractBalancedFromOpen(html, openEnd: openRange.upperBound, tag: tag) {
                let len = HTMLUtils.stripTags(block).count
                if len > bestLen {
                    bestLen = len
                    best = block
                }
            }
        }
        return best
    }

    private static func extractBalancedFromOpen(_ html: String, openEnd: String.Index, tag: String) -> String? {
        var depth = 1
        let search = String(html[openEnd...])
        let pattern = "<(/?)\(tag)\\b[^>]*>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = search as NSString
        let matches = regex.matches(in: search, range: NSRange(location: 0, length: ns.length))
        for m in matches {
            guard let full = Range(m.range, in: search),
                  let slashRange = Range(m.range(at: 1), in: search) else { continue }
            let isClose = !search[slashRange].isEmpty
            let token = String(search[full])
            if token.hasSuffix("/>") { continue }
            if isClose {
                depth -= 1
                if depth == 0 {
                    let innerEnd = search.index(search.startIndex, offsetBy: m.range.location)
                    return String(search[search.startIndex..<innerEnd])
                }
            } else {
                depth += 1
            }
        }
        return nil
    }

    private static func firstMatchRange(_ pattern: String, in text: String) -> Range<String.Index>? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return Range(m.range, in: text)
    }

    private static func cleanContentHTML(_ html: String, baseURL: URL) -> String {
        var work = html
        for tag in ["script", "style", "noscript", "iframe", "button", "input", "select", "textarea"] {
            work = removeTagBlocks(work, tag: tag)
        }
        // 去掉文内广告 / 会员推广块（CarNewsChina 等）
        work = removeBlocksWithClassTokens(work, tokens: [
            "ad__horizontal", "ad__in_article", "adsbygoogle", "ad-slot",
            "membership", "become-member", "newsletter-signup",
            "content__membership", "subscribe-box",
            // Foreign Affairs：订阅墙/弹层；勿用裸 "paywall"（会误删 paywall-content 正文）
            "paywall-free-article", "paywall-modal", "paywall-overlay",
            "js--fa-overlay", "newsletter-backdrop", "article-tools"
        ])
        // 去掉仅含空白的标签与连续空段落，减少阅读页大片留白
        work = work.replacingOccurrences(
            of: #"<p[^>]*>\s*(?:&nbsp;|\u{00A0}|\s)*\s*</p>"#,
            with: "",
            options: .regularExpression
        )
        work = work.replacingOccurrences(
            of: #"<div[^>]*>\s*(?:&nbsp;|\u{00A0}|\s)*\s*</div>"#,
            with: "",
            options: .regularExpression
        )
        work = work.replacingOccurrences(
            of: #"<span[^>]*>\s*(?:&nbsp;|\u{00A0}|\s)*\s*</span>"#,
            with: "",
            options: .regularExpression
        )
        work = work.replacingOccurrences(
            of: #"(?:<br\s*/?\s*>\s*){3,}"#,
            with: "<br><br>",
            options: .regularExpression
        )
        // 追踪像素 / 极小占位图
        work = work.replacingOccurrences(
            of: #"<img[^>]*(?:width=[\"']1[\"']|height=[\"']1[\"']|fly-images)[^>]*/?>"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        work = promoteLazyAndSrcsetImages(work)
        work = absolutizeAttributes(work, attr: "src", baseURL: baseURL)
        work = absolutizeAttributes(work, attr: "href", baseURL: baseURL)
        work = HTMLUtils.decodeEntities(work)
        work = work.replacingOccurrences(of: #"\n{3,}"# , with: "\n\n", options: .regularExpression)
        return work.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 删除 class 含指定 token 的 div/section/aside 块（平衡标签）
    private static func removeBlocksWithClassTokens(_ html: String, tokens: [String]) -> String {
        guard !tokens.isEmpty else { return html }
        let tokenAlt = tokens.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        let openPattern = "<(div|section|aside)([^>]*class=[\"'][^\"']*(?:" + tokenAlt + ")[^\"']*[\"'][^>]*)>"
        guard let regex = try? NSRegularExpression(pattern: openPattern, options: .caseInsensitive) else { return html }
        var work = html
        var guardCounter = 0
        while guardCounter < 40 {
            guardCounter += 1
            let ns = work as NSString
            guard let match = regex.firstMatch(in: work, range: NSRange(location: 0, length: ns.length)),
                  match.numberOfRanges >= 2,
                  let tagRange = Range(match.range(at: 1), in: work),
                  let fullOpen = Range(match.range, in: work) else { break }
            let tag = String(work[tagRange])
            let openStart = fullOpen.lowerBound
            let afterOpen = fullOpen.upperBound
            if let inner = extractBalancedFromOpen(work, openEnd: afterOpen, tag: tag) {
                let contentEnd = work.index(afterOpen, offsetBy: inner.count)
                let closePattern = "</\(tag)>"
                if let close = work.range(of: closePattern, options: .caseInsensitive, range: contentEnd..<work.endIndex) {
                    work.removeSubrange(openStart..<close.upperBound)
                } else {
                    work.removeSubrange(openStart..<contentEnd)
                }
            } else {
                work.removeSubrange(fullOpen)
            }
        }
        return work
    }

    private static func absolutizeAttributes(_ html: String, attr: String, baseURL: URL) -> String {
        let realPat = "(" + attr + "=[\"'])([^\"']+)([\"'])"
        guard let regex = try? NSRegularExpression(pattern: realPat, options: .caseInsensitive) else { return html }
        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length)).reversed()
        var result = html
        for m in matches {
            guard m.numberOfRanges >= 4,
                  let valRange = Range(m.range(at: 2), in: result),
                  let fullRange = Range(m.range, in: result) else { continue }
            let value = String(result[valRange])
            if value.hasPrefix("http://") || value.hasPrefix("https://") || value.hasPrefix("data:") || value.hasPrefix("#") {
                continue
            }
            if let absolute = URL(string: value, relativeTo: baseURL)?.absoluteString {
                let prefix = String(result[Range(m.range(at: 1), in: result)!])
                let suffix = String(result[Range(m.range(at: 3), in: result)!])
                result.replaceSubrange(fullRange, with: "\(prefix)\(absolute)\(suffix)")
            }
        }
        return result
    }


    private static func isWordPressChartHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "visualcapitalist.com"
            || host.hasSuffix(".visualcapitalist.com")
            || host == "voronoiapp.com"
            || host.hasSuffix(".voronoiapp.com")
    }

    /// 按 slug 拉 WP REST：`/wp-json/wp/v2/posts?slug=...&_embed=1`
    private static func fetchWordPressBySlug(pageURL: URL) async -> Extracted? {
        let path = pageURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !path.isEmpty else { return nil }
        // /cp/slug/ 或 /year/month/slug/ → 取最后一段
        let slug = path.split(separator: "/").last.map(String.init) ?? path
        guard !slug.isEmpty, slug != "cp" else { return nil }
        guard var comps = URLComponents(url: pageURL, resolvingAgainstBaseURL: false) else { return nil }
        comps.path = "/wp-json/wp/v2/posts"
        comps.queryItems = [
            URLQueryItem(name: "slug", value: slug),
            URLQueryItem(name: "_embed", value: "1")
        ]
        comps.fragment = nil
        guard let apiURL = comps.url else { return nil }

        var request = URLRequest(url: apiURL, timeoutInterval: 18)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(pageURL.absoluteString, forHTTPHeaderField: "Referer")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return nil
            }
            guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let obj = arr.first else { return nil }
            var contentHTML = (obj["content"] as? [String: Any])?["rendered"] as? String ?? ""
            let title: String? = {
                if let t = obj["title"] as? [String: Any], let rendered = t["rendered"] as? String {
                    return HTMLUtils.stripTags(rendered).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                return nil
            }()
            // 特色图 / Jetpack 图：图表站正文常依赖首图
            if let featured = featuredImageURL(fromWordPress: obj) {
                let lower = contentHTML.lowercased()
                let featuredKey = featured.split(separator: "?").first.map(String.init) ?? featured
                if !lower.contains(featuredKey.lowercased()) {
                    contentHTML = "<p><img src=\"" + featured + "\" alt=\"\"></p>\n" + contentHTML
                }
            }
            // 正文里再扫一遍 figure/img 懒加载字段
            contentHTML = promoteLazyAndSrcsetImages(contentHTML)
            guard !contentHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let cleaned = cleanContentHTML(contentHTML, baseURL: pageURL)
            let len = HTMLUtils.stripTags(cleaned).count
            let imgCount = cleaned.lowercased().components(separatedBy: "<img").count - 1
            // 图表文：允许正文偏短但有图
            guard len >= 80 || imgCount >= 1 else { return nil }
            return Extracted(title: title, content: cleaned)
        } catch {
            return nil
        }
    }

    private static func featuredImageURL(fromWordPress obj: [String: Any]) -> String? {
        if let jet = obj["jetpack_featured_media_url"] as? String, !jet.isEmpty {
            return jet
        }
        if let emb = obj["_embedded"] as? [String: Any],
           let media = emb["wp:featuredmedia"] as? [[String: Any]],
           let first = media.first {
            if let src = first["source_url"] as? String, !src.isEmpty { return src }
            if let details = first["media_details"] as? [String: Any],
               let sizes = details["sizes"] as? [String: Any] {
                for key in ["full", "large", "medium_large", "medium"] {
                    if let s = sizes[key] as? [String: Any],
                       let u = s["source_url"] as? String, !u.isEmpty {
                        return u
                    }
                }
            }
            // 部分主题把大图放在 guid
            if let guid = first["guid"] as? [String: Any],
               let rendered = guid["rendered"] as? String, !rendered.isEmpty {
                return rendered
            }
        }
        if let yoast = obj["yoast_head_json"] as? [String: Any],
           let og = yoast["og_image"] as? [[String: Any]],
           let url = og.first?["url"] as? String, !url.isEmpty {
            return url
        }
        return nil
    }

    /// 将 data-src / data-lazy-src / srcset 提升为可用的 src（取最大宽度）
    private static func promoteLazyAndSrcsetImages(_ html: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"<img\b[^>]*>"#,
            options: .caseInsensitive
        ) else { return html }
        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length)).reversed()
        var result = html
        for m in matches {
            guard let range = Range(m.range, in: result) else { continue }
            let tag = String(result[range])
            let promoted = promoteSingleImageTag(tag)
            if promoted != tag {
                result.replaceSubrange(range, with: promoted)
            }
        }
        return result
    }

    private static func promoteSingleImageTag(_ tag: String) -> String {
        func attr(_ name: String) -> String? {
            let pat = name + #"=[\"']([^\"']+)[\"']"#
            guard let re = try? NSRegularExpression(pattern: pat, options: .caseInsensitive) else { return nil }
            let ns = tag as NSString
            guard let m = re.firstMatch(in: tag, range: NSRange(location: 0, length: ns.length)),
                  m.numberOfRanges >= 2,
                  let r = Range(m.range(at: 1), in: tag) else { return nil }
            return String(tag[r])
        }
        let existingSrc = attr("src")
        let candidates = [
            attr("data-src"),
            attr("data-lazy-src"),
            attr("data-original"),
            attr("data-full-url"),
            attr("data-large_image"),
            attr("data-url"),
            attr("data-lazy-srcset").flatMap { bestURLFromSrcset($0) },
            bestURLFromSrcset(attr("data-srcset")),
            bestURLFromSrcset(attr("srcset")),
            existingSrc
        ].compactMap { $0 }.filter { !$0.isEmpty && !$0.hasPrefix("data:") }

        // 现有 src 若是 1x1 / placeholder，优先换掉
        let srcIsPlaceholder: Bool = {
            guard let s = existingSrc?.lowercased() else { return true }
            if s.contains("placeholder") || s.contains("data:image") { return true }
            if s.contains("1x1") || s.contains("blank.gif") || s.contains("pixel") { return true }
            return false
        }()

        guard let best = candidates.first else { return tag }
        if let existingSrc, !srcIsPlaceholder,
           existingSrc.hasPrefix("http"),
           candidates.first == existingSrc {
            return tag
        }
        // 重写 src，保留其它属性（去掉空 src）
        var out = tag
        if let re = try? NSRegularExpression(pattern: #"\s+src=[\"'][^\"']*[\"']"#, options: .caseInsensitive) {
            out = re.stringByReplacingMatches(in: out, range: NSRange(location: 0, length: (out as NSString).length), withTemplate: "")
        }
        if out.lowercased().hasPrefix("<img") {
            out = "<img src=\"\(best)\"" + out.dropFirst(4)
        }
        return out
    }

    private static func bestURLFromSrcset(_ srcset: String?) -> String? {
        guard let srcset, !srcset.isEmpty else { return nil }
        var bestURL: String?
        var bestW = -1
        for part in srcset.split(separator: ",") {
            let bits = part.trimmingCharacters(in: .whitespaces).split(separator: " ")
            guard let url = bits.first.map(String.init), !url.isEmpty else { continue }
            var w = 0
            if bits.count >= 2 {
                let desc = bits[1].lowercased()
                if desc.hasSuffix("w") {
                    w = Int(desc.dropLast()) ?? 0
                } else if desc.hasSuffix("x") {
                    w = Int((Double(desc.dropLast()) ?? 1) * 1000)
                }
            }
            if w >= bestW {
                bestW = w
                bestURL = url
            } else if bestURL == nil {
                bestURL = url
            }
        }
        return bestURL
    }


    private static func matchFirst(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges >= 2,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    private static func countMatches(_ pattern: String, in text: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return 0 }
        return regex.numberOfMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
    }
}
