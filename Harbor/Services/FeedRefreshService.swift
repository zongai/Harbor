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
        /// 全量刷新时的并行源数量
        static let refreshConcurrency = 8
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

    static func fetchFeedData(from url: URL) async throws -> Data {
        if RSSHubSupport.isRSSHubURL(url) {
            let (data, _) = try await FeedDiscovery.fetchRSSHubFeed(from: url)
            return data
        }
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("application/rss+xml, application/atom+xml, application/xml, text/xml, */*;q=0.8", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await HTTP.session.data(for: request)
        let host = url.host
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw FetchError.httpStatus(code: http.statusCode, host: host)
        }
        if data.isEmpty {
            throw FetchError.emptyBody(host: host)
        }
        if RSSHubSupport.looksLikeCloudflareOrHTMLGate(data) {
            throw FetchError.cloudflareOrGate(host: host)
        }
        return data
    }
}
