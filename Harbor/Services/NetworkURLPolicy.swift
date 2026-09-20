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
