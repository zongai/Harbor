import Foundation

/// 订阅源网络拉取（与 AppStore UI 状态解耦）
enum FeedRefreshService {
    enum HTTP {
        static let session: URLSession = {
            let cfg = URLSessionConfiguration.ephemeral
            cfg.timeoutIntervalForRequest = 12
            cfg.timeoutIntervalForResource = 18
            cfg.httpMaximumConnectionsPerHost = 6
            cfg.waitsForConnectivity = false
            cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
            return URLSession(configuration: cfg)
        }()
        /// 全量刷新时的并行源数量（与 Gate 协同，避免打爆源站）
        static let refreshConcurrency = 6
    }

    /// 全局限流：同时进行的 Feed HTTP 请求上限（源站友好）
    actor FeedRequestGate {
        static let shared = FeedRequestGate()
        private let maxConcurrent = 5
        private var running = 0
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func enter() async {
            if running < maxConcurrent {
                running += 1
                return
            }
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                waiters.append(cont)
            }
            running += 1
        }

        func leave() {
            running = max(0, running - 1)
            if !waiters.isEmpty {
                let cont = waiters.removeFirst()
                cont.resume()
            }
        }
    }

    /// 带可读说明的拉取错误（供列表展示）
    enum FetchError: LocalizedError {
        case httpStatus(code: Int, host: String?)
        case cloudflareOrGate(host: String?)
        case emptyBody(host: String?)
        case notFeedContent(host: String?)

        var errorDescription: String? {
            switch self {
            case .httpStatus(let code, let host):
                let where_ = host.map { "（\($0)）" } ?? ""
                switch code {
                case 401, 403:
                    return "服务器拒绝访问 HTTP \(code)\(where_)，可能需登录或已屏蔽抓取"
                case 404:
                    return "Feed 地址不存在 HTTP 404\(where_)，请检查订阅链接"
                case 410:
                    return "Feed 已失效 HTTP 410\(where_)"
                case 429:
                    return "请求过于频繁 HTTP 429\(where_)，请稍后再试"
                case 500...599:
                    return "源站服务器错误 HTTP \(code)\(where_)，可稍后重试"
                default:
                    return "服务器返回异常 HTTP \(code)\(where_)"
                }
            case .cloudflareOrGate(let host):
                let where_ = host.map { "（\($0)）" } ?? ""
                return "源站开启了访问验证（如 Cloudflare）\(where_)，应用内无法读取 Feed"
            case .emptyBody(let host):
                let where_ = host.map { "（\($0)）" } ?? ""
                return "服务器返回空内容\(where_)"
            case .notFeedContent(let host):
                let where_ = host.map { "（\($0)）" } ?? ""
                return "返回内容不是有效的 RSS/Atom\(where_)"
            }
        }
    }


    struct FeedFetchResult: Sendable {
        let data: Data
        let etag: String?
        let lastModified: String?
        /// 304 Not Modified：可沿用本地 XML
        let notModified: Bool
    }

    /// 条件请求 + 全局限流。源站不支持 ETag/Last-Modified 时退化为普通 GET。
    nonisolated static func fetchFeedData(
        from url: URL,
        etag: String? = nil,
        lastModified: String? = nil
    ) async throws -> FeedFetchResult {
        if RSSHubSupport.isRSSHubURL(url) {
            await FeedRequestGate.shared.enter()
            defer { Task { await FeedRequestGate.shared.leave() } }
            let (data, _) = try await FeedDiscovery.fetchRSSHubFeed(from: url)
            return FeedFetchResult(data: data, etag: nil, lastModified: nil, notModified: false)
        }

        await FeedRequestGate.shared.enter()
        defer { Task { await FeedRequestGate.shared.leave() } }

        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue(
            "application/rss+xml, application/atom+xml, application/xml, text/xml, */*;q=0.8",
            forHTTPHeaderField: "Accept"
        )
        // 条件请求（源站不认则忽略，仍返回 200）
        if let etag, !etag.isEmpty {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastModified, !lastModified.isEmpty {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await HTTP.session.data(for: request)
        let host = url.host
        let http = response as? HTTPURLResponse
        let code = http?.statusCode ?? 0

        if code == 304 {
            return FeedFetchResult(data: Data(), etag: etag, lastModified: lastModified, notModified: true)
        }
        if let http, !(200...299).contains(http.statusCode) {
            throw FetchError.httpStatus(code: http.statusCode, host: host)
        }
        if data.isEmpty {
            throw FetchError.emptyBody(host: host)
        }
        if RSSHubSupport.looksLikeCloudflareOrHTMLGate(data) {
            throw FetchError.cloudflareOrGate(host: host)
        }
        let newEtag = http?.value(forHTTPHeaderField: "ETag")
        let newLM = http?.value(forHTTPHeaderField: "Last-Modified")
        return FeedFetchResult(data: data, etag: newEtag, lastModified: newLM, notModified: false)
    }

    /// 兼容旧调用：只要 Data
    nonisolated static func fetchFeedData(from url: URL) async throws -> Data {
        let r = try await fetchFeedData(from: url, etag: nil, lastModified: nil)
        if r.notModified { return Data() }
        return r.data
    }

    /// 网络拉取 + XML 解析结果（值类型，跨隔离域安全传递）
    struct ParsedFeedPayload: Sendable {
        let data: Data
        let articles: [Article]
        let resolvedURL: URL
        let upgradedToHTTPS: Bool
        /// 304：无新数据，调用方应跳过 merge 或仅更新 lastFetched
        let notModified: Bool
    }

    /// 拉取 + 解析在 nonisolated 执行；条件请求 + 限流；主线程只 merge
    nonisolated static func fetchAndParse(
        url: URL,
        feedID: UUID,
        feedTitle: String,
        cacheKeyURLString: String
    ) async throws -> ParsedFeedPayload {
        let requestSeed = url
        let id = feedID
        let title = feedTitle
        let cacheKey = cacheKeyURLString
        let validators = OfflineCache.loadFeedValidators(url: cacheKey)

        var requestURL = requestSeed
        var upgraded = false
        let fetch: FeedFetchResult
        do {
            fetch = try await fetchFeedData(
                from: requestURL,
                etag: validators?.etag,
                lastModified: validators?.lastModified
            )
        } catch let firstError {
            guard requestURL.scheme?.lowercased() == "http",
                  var comps = URLComponents(url: requestURL, resolvingAgainstBaseURL: false) else {
                throw firstError
            }
            comps.scheme = "https"
            guard let httpsURL = comps.url, NetworkURLPolicy.isAllowed(httpsURL) else {
                throw firstError
            }
            fetch = try await fetchFeedData(
                from: httpsURL,
                etag: validators?.etag,
                lastModified: validators?.lastModified
            )
            requestURL = httpsURL
            upgraded = true
        }

        if fetch.notModified {
            let cached = OfflineCache.loadFeedXML(url: cacheKey) ?? Data()
            let articles = cached.isEmpty ? [] : FeedParser.parse(data: cached, feedID: id, feedTitle: title)
            return ParsedFeedPayload(
                data: cached,
                articles: articles,
                resolvedURL: requestURL,
                upgradedToHTTPS: upgraded,
                notModified: true
            )
        }

        OfflineCache.saveFeedXML(url: cacheKey, data: fetch.data)
        OfflineCache.saveFeedValidators(url: cacheKey, etag: fetch.etag, lastModified: fetch.lastModified)
        let articles = FeedParser.parse(data: fetch.data, feedID: id, feedTitle: title)
        return ParsedFeedPayload(
            data: fetch.data,
            articles: articles,
            resolvedURL: requestURL,
            upgradedToHTTPS: upgraded,
            notModified: false
        )
    }

    /// 仅解析离线 XML（nonisolated）
    nonisolated static func parseOffline(data: Data, feedID: UUID, feedTitle: String) async -> [Article] {
        FeedParser.parse(data: data, feedID: feedID, feedTitle: feedTitle)
    }
}
