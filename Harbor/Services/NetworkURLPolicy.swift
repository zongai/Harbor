import Foundation

/// 拦截明显危险/内网目标，降低恶意 feed / 正文链接的 SSRF 面
enum NetworkURLPolicy {
    static func isAllowed(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        guard let host = url.host?.lowercased(), !host.isEmpty else { return false }
        if host == "localhost" || host.hasSuffix(".localhost") { return false }
        if host.hasSuffix(".local") { return false }
        if host == "0.0.0.0" { return false }

        // IPv6 loopback / link-local / ULA
        let h = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if h == "::1" || h.hasPrefix("fe80:") || h.hasPrefix("fc") || h.hasPrefix("fd") {
            return false
        }

        // Literal IPv4
        if let parts = ipv4Parts(host) {
            return !isPrivateIPv4(parts)
        }
        return true
    }

    static func validate(_ urlString: String) -> URL? {
        guard let url = URL(string: urlString), isAllowed(url) else { return nil }
        return url
    }

    // MARK: - OPDS（用户主动输入，规则更宽松）

    /// 规范化用户输入并校验：自动补全 https、允许局域网，拒绝空主机
    static func validateOPDS(_ urlString: String) -> URL? {
        guard let url = normalizeUserEnteredURL(urlString) else { return nil }
        return isAllowedOPDS(url) ? url : nil
    }

    static func normalizeUserEnteredURL(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // 不可见字符 / BOM / 不间断空格
        let junk: [String] = [
            "\u{200B}", "\u{200C}", "\u{200D}", "\u{FEFF}", "\u{00A0}"
        ]
        for j in junk {
            s = s.replacingOccurrences(of: j, with: j == "\u{00A0}" ? " " : "")
        }
        // 去掉包裹引号
        while s.count >= 2 {
            let pairs: [(Character, Character)] = [
                ("\"", "\""), ("'", "'"), ("“", "”"), ("‘", "’")
            ]
            var stripped = false
            for (a, b) in pairs {
                if s.first == a, s.last == b {
                    s = String(s.dropFirst().dropLast())
                    stripped = true
                    break
                }
            }
            if !stripped { break }
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !s.isEmpty else { return nil }

        let lower = s.lowercased()
        // 已写明 http:// 或 https:// 时原样保留（明确允许明文 HTTP）
        if !lower.hasPrefix("http://"), !lower.hasPrefix("https://") {
            // 无 scheme：局域网 / localhost 默认 http，其余默认 https
            let hostPart = s.split(separator: "/", maxSplits: 1).first.map(String.init) ?? s
            let hostOnly = hostPart.split(separator: ":").first.map(String.init)?.lowercased() ?? ""
            if hostOnly == "localhost"
                || hostOnly.hasSuffix(".local")
                || hostOnly.hasSuffix(".lan")
                || looksLikePrivateIPv4Host(hostOnly) {
                s = "http://" + s
            } else {
                s = "https://" + s
            }
        }

        if let components = URLComponents(string: s), let url = components.url,
           url.host?.isEmpty == false {
            return url
        }
        // 空格 → %20 再试
        let spaced = s.replacingOccurrences(of: " ", with: "%20")
        if let components = URLComponents(string: spaced), let url = components.url,
           url.host?.isEmpty == false {
            return url
        }
        return nil
    }

    /// OPDS 允许私有网段（Calibre / 家庭服务器）；仍要求 http(s) + 非空 host
    static func isAllowedOPDS(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        guard let host = url.host?.lowercased(), !host.isEmpty else { return false }
        if host == "0.0.0.0" { return false }
        return true
    }

    // MARK: - Private

    private static func looksLikePrivateIPv4Host(_ host: String) -> Bool {
        if let parts = ipv4Parts(host) {
            return isPrivateIPv4(parts)
        }
        return false
    }

    private static func ipv4Parts(_ host: String) -> [UInt8]? {
        let parts = host.split(separator: ".")
        guard parts.count == 4 else { return nil }
        var out: [UInt8] = []
        for p in parts {
            guard let v = UInt8(p) else { return nil }
            out.append(v)
        }
        return out
    }

    private static func isPrivateIPv4(_ p: [UInt8]) -> Bool {
        guard p.count == 4 else { return false }
        if p[0] == 10 { return true }
        if p[0] == 127 { return true }
        if p[0] == 0 { return true }
        if p[0] == 169 && p[1] == 254 { return true }
        if p[0] == 172 && (16...31).contains(p[1]) { return true }
        if p[0] == 192 && p[1] == 168 { return true }
        if p[0] == 100 && (64...127).contains(p[1]) { return true } // CGNAT
        return false
    }
}
