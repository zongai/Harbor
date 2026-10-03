import Foundation

/// 用户偏好 / 引擎配置域 — 与 feeds、SessionChrome 分观察
@Observable
@MainActor
final class SettingsStore {
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
    var aiProviders: [AIProvider] = [
        AIProvider(id: UUID(), name: "OpenAI", baseURL: "https://api.openai.com/v1", model: "gpt-4o-mini", kind: "openai"),
        AIProvider(id: UUID(), name: "Anthropic", baseURL: "https://api.anthropic.com/v1", model: "claude-3-haiku-20240307", kind: "openai"),
        AIProvider(id: UUID(), name: "Gemini", baseURL: "https://generativelanguage.googleapis.com/v1beta", model: "gemini-2.0-flash", kind: "gemini")
    ]
    var defaultSummaryProviderID: UUID?
    var defaultTranslationProviderID: UUID?
    var defaultExplainProviderID: UUID?
    var aiBlacklistTerms: [String] = []
    var articleBlacklistTerms: [String] = []
    var aiBlacklistFallbackProviderID: UUID?
    var showReadArticles: Bool = false
    /// 订阅列表是否显示未读数字角标（默认开启）
    var showUnreadCount: Bool = true
    var translationPrompt: String = AppStore.defaultTranslationPrompt
    /// AI 审校润色（更高质量重译）：对照原文 + 初译
    var translationRefinementPrompt: String = AppStore.defaultTranslationRefinementPrompt
    var summaryPrompt: String = AppStore.defaultSummaryPrompt
    var explainPrompt: String = AppStore.defaultExplainPrompt
    var readRetentionDays: Int = 7
    var fullContentCacheDays: Int = 30
    /// Wi‑Fi 下预缓存全文与图片（默认开）
    var wifiPrefetchFullContent: Bool = true
    /// 每轮最多预缓存文章数
    var wifiPrefetchMaxArticles: Int = 30
    /// 仅预缓存未读
    var wifiPrefetchUnreadOnly: Bool = true
    var fullContentURLPrefixEnabled: Bool = false
    var fullContentURLPrefix: String = ""
    var globalSummaryPresetID: String = SummaryPromptPreset.standardID
    var summaryPromptPresets: [SummaryPromptPreset] = SummaryPromptPreset.builtInDefaults
    var smartInterestFilterEnabled: Bool = false
    var autoMarkLowInterestRead: Bool = false
    var lowInterestThreshold: Double = 0.35
    var sortByInterestScore: Bool = false
    var modelRoutingEnabled: Bool = false
    var modelRoutingShortLimit: Int = 800
    var interestWeights: [String: Double] = [:]
    var ttsVoice: String = ""
    var ttsRate: Double = 1.2
    var colorTheme: ReadingTheme = .classicLight
    var appearanceMode: AppearanceMode = .system
    var appFontFamily: AppFontFamily = .system
    var feedSortMode: FeedSortMode = .unreadThenTitle
    var targetLanguage: AppLanguage = .zhHans
    var translationConcurrency: Int = 0
    /// 译文是否为目标语言；否时换引擎重译（默认开）
    var verifyTranslationLanguage: Bool = true
    var aiOutputLanguage: AppLanguage = .zhHans
    var microsoftTranslateRegion: String = "global"
    var lingvaCustomBase: String = ""
    var defaultChatProviderID: UUID?

    // MARK: - 书籍阅读
    /// original / translation / bilingual
    var bookDefaultReadingMode: String = BookReadingMode.original.rawValue
    var bookTTSRate: Double = 1.0
    var bookAutoLanguageVoice: Bool = true
}

