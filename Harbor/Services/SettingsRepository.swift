import Foundation

/// 用户偏好持久化（不含订阅源与已读链接；那些在 FeedRepository）
struct PersistedAppSettings: Codable {
    var fontSize: Double = 17
    var listTitleFontSize: Double = 18
    var listSummaryFontSize: Double = 15
    var readerTitleFontSize: Double = 24
    var aiSummaryFontSize: Double = 22
    var feedTitleFontSize: Double = 17
    var groupTitleFontSize: Double = 13
    var titleDisplayMode: TitleDisplayMode = .original
    var defaultTranslationEngine: TranslationEngine = .google
    var translationEngineChain: [TranslationEngine] = TranslationEngine.allCases
    var showReadArticles: Bool = false
    var translationPrompt: String = AppStore.defaultTranslationPrompt
    var summaryPrompt: String = AppStore.defaultSummaryPrompt
    var explainPrompt: String = AppStore.defaultExplainPrompt
    var readRetentionDays: Int = 7
    var fullContentCacheDays: Int = 30
    var fullContentURLPrefixEnabled: Bool = false
    var fullContentURLPrefix: String = ""
    var globalSummaryPresetID: String = SummaryPromptPreset.standardID
    var summaryPromptPresets: [SummaryPromptPreset] = SummaryPromptPreset.builtInDefaults
    var smartInterestFilterEnabled: Bool = false
    var autoMarkLowInterestRead: Bool = false
    var lowInterestThreshold: Double = 0.35
    var sortByInterestScore: Bool = false
    var modelRoutingEnabled: Bool = false
    var modelRoutingShortLimit: Int = 600
    var interestWeights: [String: Double] = [:]
    var ttsVoice: String = ""
    var ttsRate: Double = 1.2
    var colorThemeRaw: String = ""
    var appearanceModeRaw: String = ""
    var appFontFamilyRaw: String = ""
    var feedSortModeRaw: String = ""
    var targetLanguage: AppLanguage = .zhHans
    var translationConcurrency: Int = 0
    var microsoftTranslateRegion: String = "global"
    var lingvaCustomBase: String = ""
    var aiOutputLanguage: AppLanguage = .zhHans
    var aiProviders: [AIProvider] = []
    var defaultSummaryProviderID: UUID?
    var defaultTranslationProviderID: UUID?
    var defaultExplainProviderID: UUID?
    var aiBlacklistTerms: [String] = []
    var articleBlacklistTerms: [String] = []
    var aiBlacklistFallbackProviderID: UUID?
    var defaultChatProviderID: UUID?
}

enum SettingsRepository {
    static func save(_ s: PersistedAppSettings) {
        let d = UserDefaults.standard
        d.set(s.fontSize, forKey: "fontSize")
        d.set(s.listTitleFontSize, forKey: "listTitleFontSize")
        d.set(s.listSummaryFontSize, forKey: "listSummaryFontSize")
        d.set(s.readerTitleFontSize, forKey: "readerTitleFontSize")
        d.set(s.aiSummaryFontSize, forKey: "aiSummaryFontSize")
        d.set(s.feedTitleFontSize, forKey: "feedTitleFontSize")
        d.set(s.groupTitleFontSize, forKey: "groupTitleFontSize")
        d.set(s.titleDisplayMode.rawValue, forKey: "titleDisplayMode")
        d.set(s.defaultTranslationEngine.rawValue, forKey: "defaultTranslationEngine")
        d.set(s.translationEngineChain.map(\.rawValue), forKey: "translationEngineChain")
        d.set(s.showReadArticles, forKey: "showReadArticles")
        d.set(s.translationPrompt, forKey: "translationPrompt")
        d.set(s.summaryPrompt, forKey: "summaryPrompt")
        d.set(s.explainPrompt, forKey: "explainPrompt")
        d.set(s.readRetentionDays, forKey: "readRetentionDays")
        d.set(s.fullContentCacheDays, forKey: "fullContentCacheDays")
        d.set(s.fullContentURLPrefixEnabled, forKey: "fullContentURLPrefixEnabled")
        d.set(s.fullContentURLPrefix, forKey: "fullContentURLPrefix")
        d.set(s.globalSummaryPresetID, forKey: "globalSummaryPresetID")
        if let data = try? JSONEncoder().encode(s.summaryPromptPresets) {
            d.set(data, forKey: "summaryPromptPresets")
        }
        d.set(s.smartInterestFilterEnabled, forKey: "smartInterestFilterEnabled")
        d.set(s.autoMarkLowInterestRead, forKey: "autoMarkLowInterestRead")
        d.set(s.lowInterestThreshold, forKey: "lowInterestThreshold")
        d.set(s.sortByInterestScore, forKey: "sortByInterestScore")
        d.set(s.modelRoutingEnabled, forKey: "modelRoutingEnabled")
        d.set(s.modelRoutingShortLimit, forKey: "modelRoutingShortLimit")
        if let data = try? JSONEncoder().encode(s.interestWeights) {
            d.set(data, forKey: "interestWeights")
        }
        d.set(s.ttsVoice, forKey: "ttsVoice")
        d.set(s.ttsRate, forKey: "ttsRate")
        if !s.colorThemeRaw.isEmpty { d.set(s.colorThemeRaw, forKey: "colorTheme") }
        if !s.appearanceModeRaw.isEmpty { d.set(s.appearanceModeRaw, forKey: "appearanceMode") }
        if !s.appFontFamilyRaw.isEmpty { d.set(s.appFontFamilyRaw, forKey: "appFontFamily") }
        if !s.feedSortModeRaw.isEmpty { d.set(s.feedSortModeRaw, forKey: "feedSortMode") }
        d.set(s.targetLanguage.rawValue, forKey: "targetLanguage")
        d.set(s.translationConcurrency, forKey: "translationConcurrency")
        d.set(s.microsoftTranslateRegion, forKey: "microsoftTranslateRegion")
        d.set(s.lingvaCustomBase, forKey: "lingvaCustomBase")
        d.set(s.aiOutputLanguage.rawValue, forKey: "aiOutputLanguage")
        if let data = try? JSONEncoder().encode(s.aiProviders) {
            d.set(data, forKey: "aiProviders")
        }
        setUUID(s.defaultSummaryProviderID, key: "defaultSummaryProviderID")
        setUUID(s.defaultTranslationProviderID, key: "defaultTranslationProviderID")
        setUUID(s.defaultExplainProviderID, key: "defaultExplainProviderID")
        setUUID(s.aiBlacklistFallbackProviderID, key: "aiBlacklistFallbackProviderID")
        setUUID(s.defaultChatProviderID, key: "defaultChatProviderID")
        if let data = try? JSONEncoder().encode(s.aiBlacklistTerms) {
            d.set(data, forKey: "aiBlacklistTerms")
        }
        if let data = try? JSONEncoder().encode(s.articleBlacklistTerms) {
            d.set(data, forKey: "articleBlacklistTerms")
        }
    }

    static func load() -> PersistedAppSettings {
        let d = UserDefaults.standard
        var s = PersistedAppSettings()
        s.fontSize = d.object(forKey: "fontSize") as? Double ?? 17
        s.listTitleFontSize = d.object(forKey: "listTitleFontSize") as? Double ?? 18
        s.listSummaryFontSize = d.object(forKey: "listSummaryFontSize") as? Double ?? 15
        s.readerTitleFontSize = d.object(forKey: "readerTitleFontSize") as? Double ?? 24
        s.aiSummaryFontSize = d.object(forKey: "aiSummaryFontSize") as? Double ?? 22
        s.feedTitleFontSize = d.object(forKey: "feedTitleFontSize") as? Double ?? 17
        s.groupTitleFontSize = d.object(forKey: "groupTitleFontSize") as? Double ?? 13
        if let raw = d.string(forKey: "titleDisplayMode"),
           let mode = TitleDisplayMode(rawValue: raw) {
            s.titleDisplayMode = mode
        }
        if let region = d.string(forKey: "microsoftTranslateRegion"), !region.isEmpty {
            s.microsoftTranslateRegion = region
        }
        if let lingva = d.string(forKey: "lingvaCustomBase") {
            s.lingvaCustomBase = lingva
        }
        if let raw = d.string(forKey: "defaultTranslationEngine") {
            if raw.contains("Lingva") || raw.contains("Libre") {
                s.defaultTranslationEngine = .google
            } else if let engine = TranslationEngine(rawValue: raw) {
                s.defaultTranslationEngine = engine
            }
        }
        if let arr = d.array(forKey: "translationEngineChain") as? [String] {
            let parsed = arr.compactMap { TranslationEngine(rawValue: $0) }
            if !parsed.isEmpty {
                var seen = Set<TranslationEngine>()
                s.translationEngineChain = parsed.filter { seen.insert($0).inserted }
            }
        } else {
            var chain = [TranslationEngine.google]
            for e in TranslationEngine.allCases where e != .google {
                chain.append(e)
            }
            s.translationEngineChain = chain
        }
        // 持久化链若为空则回退默认
        if s.translationEngineChain.isEmpty {
            s.translationEngineChain = TranslationEngine.allCases
        }
        if let first = s.translationEngineChain.first {
            s.defaultTranslationEngine = first
        }
        s.showReadArticles = d.object(forKey: "showReadArticles") as? Bool ?? false
        if let p = d.string(forKey: "translationPrompt") { s.translationPrompt = p }
        if let p = d.string(forKey: "summaryPrompt") { s.summaryPrompt = p }
        if let p = d.string(forKey: "explainPrompt") { s.explainPrompt = p }
        s.readRetentionDays = d.object(forKey: "readRetentionDays") as? Int ?? 7
        s.fullContentCacheDays = d.object(forKey: "fullContentCacheDays") as? Int ?? 30
        s.fullContentURLPrefixEnabled = d.object(forKey: "fullContentURLPrefixEnabled") as? Bool ?? false
        s.fullContentURLPrefix = d.string(forKey: "fullContentURLPrefix") ?? ""
        if let data = d.data(forKey: "summaryPromptPresets"),
           let list = try? JSONDecoder().decode([SummaryPromptPreset].self, from: data), !list.isEmpty {
            s.summaryPromptPresets = list
        }
        if let raw = d.string(forKey: "globalSummaryPresetID"), !raw.isEmpty {
            s.globalSummaryPresetID = raw == SummaryPromptPreset.globalID ? SummaryPromptPreset.standardID : raw
        } else if let legacy = d.string(forKey: "globalSummaryPreset"), !legacy.isEmpty {
            s.globalSummaryPresetID = legacy == "global" ? SummaryPromptPreset.standardID : legacy
        }
        s.smartInterestFilterEnabled = d.object(forKey: "smartInterestFilterEnabled") as? Bool ?? false
        s.autoMarkLowInterestRead = d.object(forKey: "autoMarkLowInterestRead") as? Bool ?? false
        if d.object(forKey: "lowInterestThreshold") != nil {
            s.lowInterestThreshold = min(1, max(0, d.double(forKey: "lowInterestThreshold")))
        }
        s.sortByInterestScore = d.object(forKey: "sortByInterestScore") as? Bool ?? false
        s.modelRoutingEnabled = d.object(forKey: "modelRoutingEnabled") as? Bool ?? false
        if d.object(forKey: "modelRoutingShortLimit") != nil {
            s.modelRoutingShortLimit = max(100, d.integer(forKey: "modelRoutingShortLimit"))
        }
        if let data = d.data(forKey: "interestWeights"),
           let map = try? JSONDecoder().decode([String: Double].self, from: data) {
            s.interestWeights = map
        }
        s.ttsVoice = d.string(forKey: "ttsVoice") ?? ""
        if d.object(forKey: "ttsRate") != nil {
            s.ttsRate = min(2.0, max(0.5, d.double(forKey: "ttsRate")))
        }
        s.colorThemeRaw = d.string(forKey: "colorTheme") ?? ""
        s.appearanceModeRaw = d.string(forKey: "appearanceMode") ?? ""
        s.appFontFamilyRaw = d.string(forKey: "appFontFamily") ?? ""
        s.feedSortModeRaw = d.string(forKey: "feedSortMode") ?? ""
        if let raw = d.string(forKey: "targetLanguage"),
           let lang = AppLanguage(rawValue: raw) {
            s.targetLanguage = lang
        }
        if d.object(forKey: "translationConcurrency") != nil {
            s.translationConcurrency = min(8, max(0, d.integer(forKey: "translationConcurrency")))
        }
        if let raw = d.string(forKey: "aiOutputLanguage"),
           let lang = AppLanguage(rawValue: raw) {
            s.aiOutputLanguage = lang
        }
        if let data = d.data(forKey: "aiProviders"),
           let decoded = try? JSONDecoder().decode([AIProvider].self, from: data) {
            s.aiProviders = decoded
        }
        s.defaultSummaryProviderID = uuid(d, "defaultSummaryProviderID")
        s.defaultTranslationProviderID = uuid(d, "defaultTranslationProviderID")
        s.defaultExplainProviderID = uuid(d, "defaultExplainProviderID")
        s.aiBlacklistFallbackProviderID = uuid(d, "aiBlacklistFallbackProviderID")
        s.defaultChatProviderID = uuid(d, "defaultChatProviderID")
        if let data = d.data(forKey: "aiBlacklistTerms"),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            s.aiBlacklistTerms = decoded
        }
        if let data = d.data(forKey: "articleBlacklistTerms"),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            s.articleBlacklistTerms = decoded
        }
        return s
    }

    private static func setUUID(_ id: UUID?, key: String) {
        if let id {
            UserDefaults.standard.set(id.uuidString, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private static func uuid(_ d: UserDefaults, _ key: String) -> UUID? {
        guard let s = d.string(forKey: key) else { return nil }
        return UUID(uuidString: s)
    }
}
