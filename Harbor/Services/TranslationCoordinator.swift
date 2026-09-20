import Foundation

/// 翻译引擎链、限流冷却与并发解析（不持有 API Key，由调用方注入执行闭包）
final class TranslationCoordinator: @unchecked Sendable {
    private var limitedUntil: [TranslationEngine: Date] = [:]
    private let lock = NSLock()

    /// 有效引擎顺序：去重并跳过冷却中的；若全部在冷却则硬试
    func effectiveChain(
        configured: [TranslationEngine],
        fallbackAll: [TranslationEngine] = TranslationEngine.allCases
    ) -> [TranslationEngine] {
        let source = configured.isEmpty ? fallbackAll : configured
        var seen = Set<TranslationEngine>()
        var list: [TranslationEngine] = []
        for e in source {
            guard seen.insert(e).inserted else { continue }
            if isCooling(e) { continue }
            list.append(e)
        }
        if list.isEmpty {
            seen.removeAll()
            for e in source {
                guard seen.insert(e).inserted else { continue }
                list.append(e)
            }
        }
        return list
    }

    func isCooling(_ engine: TranslationEngine) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let until = limitedUntil[engine] else { return false }
        if until > Date() { return true }
        limitedUntil[engine] = nil
        return false
    }

    func markLimited(_ engine: TranslationEngine, minutes: Double = 5) {
        lock.lock()
        limitedUntil[engine] = Date().addingTimeInterval(minutes * 60)
        lock.unlock()
    }

    func clearLimit(_ engine: TranslationEngine) {
        lock.lock()
        limitedUntil[engine] = nil
        lock.unlock()
    }

    func resolvedConcurrency(
        for engine: TranslationEngine,
        userSetting: Int,
        override: Int? = nil
    ) -> Int {
        if let o = override, o > 0 { return min(8, o) }
        if userSetting > 0 { return min(8, userSetting) }
        // Google 默认可略抬高：请求闸在 GoogleTranslate 内再限到 4，避免 429
        switch engine {
        case .ai: return 4
        case .google: return 4
        case .mymemory, .lingva: return 3
        case .yandex: return 3
        case .azure: return 4
        case .microsoft: return 3
        case .deepl: return 3
        }
    }

    /// 规范化链：去重，空则 google
    static func normalizedChain(_ chain: [TranslationEngine]) -> [TranslationEngine] {
        var seen = Set<TranslationEngine>()
        let list = chain.filter { seen.insert($0).inserted }
        return list.isEmpty ? [.google] : list
    }
}
