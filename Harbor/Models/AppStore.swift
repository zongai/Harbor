import Foundation
import SwiftUI

@Observable
@MainActor
class AppStore: AIService.Runtime {
    // MARK: - 订阅数据域（与 SessionChrome 分观察）
    var feeds: [RSSFeed] = []
    var groups: [FeedGroup] = []
    var collapsedGroupIDs: Set<UUID> = []
    var isUngroupedCollapsed: Bool = false
    var selectedFeedID: UUID?
    /// 文章已读/收藏等标志变更序号
    private(set) var articleFlagsEpoch: UInt64 = 0

    /// 订阅列表 section 快照缓存（仅 token 变化时重建）
    private var _feedSectionsCacheToken: Int = 0
    private var _feedSectionsSnapshot: [(sectionID: String, group: FeedGroup?, feeds: [RSSFeed])] = []

    /// article.id → feed.id（变更时维护，避免按 id 全库扫描）
    private var articleIDToFeedID: [UUID: UUID] = [:]

    /// 全文抓取 in-flight：canonical link → Task（AppStore 层，含前缀 URL 差异）
    private var fullContentInflight: [String: Task<Article, Error>] = [:]

    /// 会话 UI 进度域（独立 @Observable）
    let chrome = SessionChromeState()

    /// 文章级世代（已读/收藏/单篇更新）
    let articleFlags = ArticleFlagsIndex()

    /// 用户偏好 / 引擎配置域（独立 @Observable）
    let settings = SettingsStore()

    // MARK: - Settings 域桥接（存储在 SettingsStore，兼容 AppStore 内访问与协议）
    var fontSize: Double {
        get { settings.fontSize }
        set { settings.fontSize = newValue }
    }

    var listTitleFontSize: Double {
        get { settings.listTitleFontSize }
        set { settings.listTitleFontSize = newValue }
    }

    var listSummaryFontSize: Double {
        get { settings.listSummaryFontSize }
        set { settings.listSummaryFontSize = newValue }
    }

    var readerTitleFontSize: Double {
        get { settings.readerTitleFontSize }
        set { settings.readerTitleFontSize = newValue }
    }

    var aiSummaryFontSize: Double {
        get { settings.aiSummaryFontSize }
        set { settings.aiSummaryFontSize = newValue }
    }

    var feedTitleFontSize: Double {
        get { settings.feedTitleFontSize }
        set { settings.feedTitleFontSize = newValue }
    }

    var groupTitleFontSize: Double {
        get { settings.groupTitleFontSize }
        set { settings.groupTitleFontSize = newValue }
    }

    var titleDisplayMode: TitleDisplayMode {
        get { settings.titleDisplayMode }
        set { settings.titleDisplayMode = newValue }
    }

    var defaultTranslationEngine: TranslationEngine {
        get { settings.defaultTranslationEngine }
        set { settings.defaultTranslationEngine = newValue }
    }

    var translationEngineChain: [TranslationEngine] {
        get { settings.translationEngineChain }
        set { settings.translationEngineChain = newValue }
    }

    var aiProviders: [AIProvider] {
        get { settings.aiProviders }
        set { settings.aiProviders = newValue }
    }

    var defaultSummaryProviderID: UUID? {
        get { settings.defaultSummaryProviderID }
        set { settings.defaultSummaryProviderID = newValue }
    }

    var defaultTranslationProviderID: UUID? {
        get { settings.defaultTranslationProviderID }
        set { settings.defaultTranslationProviderID = newValue }
    }

    var defaultExplainProviderID: UUID? {
        get { settings.defaultExplainProviderID }
        set { settings.defaultExplainProviderID = newValue }
    }

    var aiBlacklistTerms: [String] {
        get { settings.aiBlacklistTerms }
        set { settings.aiBlacklistTerms = newValue }
    }

    var articleBlacklistTerms: [String] {
        get { settings.articleBlacklistTerms }
        set { settings.articleBlacklistTerms = newValue }
    }

    var aiBlacklistFallbackProviderID: UUID? {
        get { settings.aiBlacklistFallbackProviderID }
        set { settings.aiBlacklistFallbackProviderID = newValue }
    }

    var showReadArticles: Bool {
        get { settings.showReadArticles }
        set { settings.showReadArticles = newValue }
    }

    var showUnreadCount: Bool {
        get { settings.showUnreadCount }
        set { settings.showUnreadCount = newValue }
    }

    var translationPrompt: String {
        get { settings.translationPrompt }
        set { settings.translationPrompt = newValue }
    }

    var translationRefinementPrompt: String {
        get { settings.translationRefinementPrompt }
        set { settings.translationRefinementPrompt = newValue }
    }

    var summaryPrompt: String {
        get { settings.summaryPrompt }
        set { settings.summaryPrompt = newValue }
    }

    var explainPrompt: String {
        get { settings.explainPrompt }
        set { settings.explainPrompt = newValue }
    }

    var readRetentionDays: Int {
        get { settings.readRetentionDays }
        set { settings.readRetentionDays = newValue }
    }

    var fullContentCacheDays: Int {
        get { settings.fullContentCacheDays }
        set { settings.fullContentCacheDays = newValue }
    }

    var fullContentURLPrefixEnabled: Bool {
        get { settings.fullContentURLPrefixEnabled }
        set { settings.fullContentURLPrefixEnabled = newValue }
    }

    var fullContentURLPrefix: String {
        get { settings.fullContentURLPrefix }
        set { settings.fullContentURLPrefix = newValue }
    }

    var globalSummaryPresetID: String {
        get { settings.globalSummaryPresetID }
        set { settings.globalSummaryPresetID = newValue }
    }

    var summaryPromptPresets: [SummaryPromptPreset] {
        get { settings.summaryPromptPresets }
        set { settings.summaryPromptPresets = newValue }
    }

    var smartInterestFilterEnabled: Bool {
        get { settings.smartInterestFilterEnabled }
        set { settings.smartInterestFilterEnabled = newValue }
    }

    var autoMarkLowInterestRead: Bool {
        get { settings.autoMarkLowInterestRead }
        set { settings.autoMarkLowInterestRead = newValue }
    }

    var lowInterestThreshold: Double {
        get { settings.lowInterestThreshold }
        set { settings.lowInterestThreshold = newValue }
    }

    var sortByInterestScore: Bool {
        get { settings.sortByInterestScore }
        set { settings.sortByInterestScore = newValue }
    }

    var modelRoutingEnabled: Bool {
        get { settings.modelRoutingEnabled }
        set { settings.modelRoutingEnabled = newValue }
    }

    var modelRoutingShortLimit: Int {
        get { settings.modelRoutingShortLimit }
        set { settings.modelRoutingShortLimit = newValue }
    }

    var interestWeights: [String: Double] {
        get { settings.interestWeights }
        set { settings.interestWeights = newValue }
    }

    var ttsVoice: String {
        get { settings.ttsVoice }
        set { settings.ttsVoice = newValue }
    }

    var ttsRate: Double {
        get { settings.ttsRate }
        set { settings.ttsRate = newValue }
    }

    var colorTheme: ReadingTheme {
        get { settings.colorTheme }
        set { settings.colorTheme = newValue }
    }

    var appearanceMode: AppearanceMode {
        get { settings.appearanceMode }
        set { settings.appearanceMode = newValue }
    }

    var appFontFamily: AppFontFamily {
        get { settings.appFontFamily }
        set { settings.appFontFamily = newValue }
    }

    var feedSortMode: FeedSortMode {
        get { settings.feedSortMode }
        set { settings.feedSortMode = newValue }
    }

    var targetLanguage: AppLanguage {
        get { settings.targetLanguage }
        set { settings.targetLanguage = newValue }
    }

    var translationConcurrency: Int {
        get { settings.translationConcurrency }
        set { settings.translationConcurrency = newValue }
    }

    var aiOutputLanguage: AppLanguage {
        get { settings.aiOutputLanguage }
        set { settings.aiOutputLanguage = newValue }
    }

    var microsoftTranslateRegion: String {
        get { settings.microsoftTranslateRegion }
        set { settings.microsoftTranslateRegion = newValue }
    }

    var lingvaCustomBase: String {
        get { settings.lingvaCustomBase }
        set { settings.lingvaCustomBase = newValue }
    }

    var defaultChatProviderID: UUID? {
        get { settings.defaultChatProviderID }
        set { settings.defaultChatProviderID = newValue }
    }


    /// 翻译引擎链与限流（与 UI 状态分离）
    let translationCoordinator = TranslationCoordinator()
    /// 刷新会话号：递增即取消进行中的 refreshAll
    private var refreshSessionID = 0
    /// 已读/收藏等引起的 feeds 全量落盘防抖任务
    private var pendingFeedsPersistTask: Task<Void, Never>?
    private static let feedsPersistDelayNs: UInt64 = 1_200_000_000

    // 兼容访问 → chrome（Observation 追踪 chrome 内属性）
    var isLoading: Bool {
        get { chrome.isLoading }
        set { chrome.isLoading = newValue }
    }
    var isRefreshingAll: Bool {
        get { chrome.isRefreshingAll }
        set { chrome.isRefreshingAll = newValue }
    }
    var refreshProgressCurrent: Int {
        get { chrome.refreshProgressCurrent }
        set { chrome.refreshProgressCurrent = newValue }
    }
    var refreshProgressTotal: Int {
        get { chrome.refreshProgressTotal }
        set { chrome.refreshProgressTotal = newValue }
    }
    var refreshProgressTitle: String {
        get { chrome.refreshProgressTitle }
        set { chrome.refreshProgressTitle = newValue }
    }
    var listTranslationProgressText: String {
        get { chrome.listTranslationProgressText }
        set { chrome.listTranslationProgressText = newValue }
    }
    var listTranslationSessionID: Int { chrome.listTranslationSessionID }

    var errorMessage: String?

    /// AI 对话历史（本地持久化）— 会话数据，非偏好配置
    var chatConversations: [ChatConversation] = []
    /// 当前打开的对话
    var activeChatID: UUID?

    static let defaultTranslationPrompt = """
你是专业译者。将下面内容翻译成{{lang}}。

要求：
- 只输出译文，不要前言、注释、双语对照或「译文如下」之类说明
- 忠实原意，专有名词可保留原文或通用译法
- 保持段落与换行；不要添加原文没有的标题或列表序号
- 若原文含 [[IMG_数字]] 等占位符，原样保留

{{text}}
"""

    /// 更高质量重译：机器初译 + AI 对照原文审校（占位符见设置说明）
    static let defaultTranslationRefinementPrompt = """
你是翻译审校。根据【原文】校对并润色【初译】，输出最终{{lang}}译文。

原则：
- 以原文含义为准；初译只是草稿，有冲突时按原文改
- 准确：不增删事实、数字、专名与逻辑；已准确自然则少改
- 自然：消除翻译腔，符合{{lang}}表达习惯
- 一致：术语、人名、机构译名前后统一
- 保格式：换行、列表、[[IMG_数字]]、URL、代码与 {{变量}} 等占位符原样保留
- 只输出最终译文，不要解释、标题或引号包裹

【原文】
{{source}}

【初译】
{{translation}}
"""

    static let defaultSummaryPrompt = """
你是资讯编辑。用{{lang}}按 5W1H 压缩下文核心信息。

覆盖（有则写，无则跳过）：谁、什么时间、做了什么、为什么、影响是什么。
要求：
- 3～5 句，每句一行；不要序号、不要「摘要如下」
- 只写原文能支撑的事实；观点须归因（如「作者认为」「据该报道」）
- 时间尽量具体；不要用「最近」「据悉」代替原文已有日期
- 总长约 120～220 字

标题：{{title}}

正文：
{{content}}
"""

    static let defaultExplainPrompt = """
你是知识助手。用简洁的{{lang}}解释用户选中的文字。

要求：
- 只输出解释本身：词义、专有名词、背景或在语境中的含义
- 2～6 句为宜，可分段；不要标题，不要复述整段原文
- 不确定时说明不确定，不要编造
- 不要推荐产品或扩展无关话题

选中文字：
{{text}}
"""


    private var readArticleLinks: Set<String> = []
    /// 收藏链接即时集（与 feeds 防抖分离）
    private var favoriteArticleLinks: Set<String> = []

    /// iCloud 同步开关（默认开）
    var iCloudSyncEnabled: Bool {
        get { ICloudSyncService.isEnabled }
        set {
            ICloudSyncService.isEnabled = newValue
            if newValue {
                scheduleICloudPush()
                pullICloudIfNeeded()
            }
        }
    }
    var iCloudLastSyncText: String = ""
    private var iCloudObserver: NSObjectProtocol?
    private var iCloudPushTask: Task<Void, Never>?
    private var isApplyingICloud = false

    init() {
        loadFromStorage()
        startICloudSync()
        _ = applyArticleBlacklist()
        if feeds.isEmpty { seedSampleData() }
        if UserDefaults.standard.string(forKey: "defaultTranslationEngine") == "Gemini" {
            defaultTranslationEngine = .ai
            if defaultTranslationProviderID == nil {
                defaultTranslationProviderID = aiProviders.first(where: { $0.kind == "gemini" })?.id
            }
        }
        if defaultSummaryProviderID == nil {
            defaultSummaryProviderID = aiProviders.first?.id
        }
        if defaultExplainProviderID == nil {
            defaultExplainProviderID = defaultSummaryProviderID ?? aiProviders.first?.id
        }
        if defaultChatProviderID == nil {
            defaultChatProviderID = defaultSummaryProviderID ?? aiProviders.first?.id
        }
        rebuildReadLinksFromArticles()
        purgeOldReadArticles()
        pruneFullContentCache()
    }

    static func canonicalLink(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasSuffix("/") { s = String(s.dropLast()) }
        if let url = URL(string: s), var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            comps.fragment = nil
            if let host = comps.host { comps.host = host.lowercased() }
            if let scheme = comps.scheme { comps.scheme = scheme.lowercased() }
            if let rebuilt = comps.url?.absoluteString {
                s = rebuilt
                if s.hasSuffix("/") { s = String(s.dropLast()) }
            }
        }
        return s
    }

    private func rebuildReadLinksFromArticles() {
        for article in allArticles where article.isRead {
            let key = Self.canonicalLink(article.link)
            if !key.isEmpty { readArticleLinks.insert(key) }
        }
        persistReadLinks()
    }

    private func persistReadLinks() {
        FeedRepository.saveReadLinks(readArticleLinks)
    }

    private func loadReadLinks() {
        readArticleLinks = FeedRepository.loadReadLinks()
    }

    private func persistFavoriteLinks() {
        FeedRepository.saveFavoriteLinks(favoriteArticleLinks)
    }

    private func loadFavoriteLinks() {
        favoriteArticleLinks = FeedRepository.loadFavoriteLinks()
    }

    private func rememberFavoriteLink(_ link: String) {
        let key = Self.canonicalLink(link)
        guard !key.isEmpty else { return }
        if favoriteArticleLinks.insert(key).inserted { persistFavoriteLinks() }
    }

    private func forgetFavoriteLink(_ link: String) {
        let key = Self.canonicalLink(link)
        guard !key.isEmpty else { return }
        if favoriteArticleLinks.remove(key) != nil { persistFavoriteLinks() }
    }

    /// 启动或合并后：用即时链接集恢复已读/收藏（防抖窗口杀进程后的兜底）
    private func applyFlagLinksToFeeds() {
        guard !readArticleLinks.isEmpty || !favoriteArticleLinks.isEmpty else { return }
        for i in feeds.indices {
            for j in feeds[i].articles.indices {
                let key = Self.canonicalLink(feeds[i].articles[j].link)
                guard !key.isEmpty else { continue }
                if readArticleLinks.contains(key) {
                    feeds[i].articles[j].isRead = true
                }
                if favoriteArticleLinks.contains(key) {
                    feeds[i].articles[j].isFavorite = true
                }
            }
            feeds[i].unreadCount = feeds[i].articles.filter { !$0.isRead }.count
        }
        // 若收藏集为空则从现有 feeds 反填一次（迁移旧数据）
        if favoriteArticleLinks.isEmpty {
            for a in feeds.flatMap { $0.articles } where a.isFavorite {
                let key = Self.canonicalLink(a.link)
                if !key.isEmpty { favoriteArticleLinks.insert(key) }
            }
            if !favoriteArticleLinks.isEmpty { persistFavoriteLinks() }
        }
    }

    private func rememberReadLink(_ link: String) {
        let key = Self.canonicalLink(link)
        guard !key.isEmpty else { return }
        if readArticleLinks.insert(key).inserted { persistReadLinks() }
    }

    private func forgetReadLink(_ link: String) {
        let key = Self.canonicalLink(link)
        guard !key.isEmpty else { return }
        if readArticleLinks.remove(key) != nil { persistReadLinks() }
    }

    var allArticles: [Article] {
        feeds.flatMap { $0.articles }.sorted { ($0.publishedDate ?? .distantPast) > ($1.publishedDate ?? .distantPast) }
    }

    var favoriteArticles: [Article] { allArticles.filter(\.isFavorite) }

    func articlesForFeed(_ feedID: UUID) -> [Article] {
        feeds.first(where: { $0.id == feedID })?.articles ?? []
    }

    /// 单篇快照（按 feed 定位，避免 allArticles flatMap）
    func articleSnapshot(id: UUID, feedID: UUID) -> Article? {
        guard let i = feeds.firstIndex(where: { $0.id == feedID }),
              let j = feeds[i].articles.firstIndex(where: { $0.id == id }) else { return nil }
        return feeds[i].articles[j]
    }

    /// 仅用 article.id：走辅助索引
    func articleSnapshot(id: UUID) -> Article? {
        guard let feedID = articleIDToFeedID[id] else {
            // 索引未命中时重建一次再试
            rebuildArticleIndex()
            guard let feedID = articleIDToFeedID[id] else { return nil }
            return articleSnapshot(id: id, feedID: feedID)
        }
        return articleSnapshot(id: id, feedID: feedID)
    }

    private func rebuildArticleIndex() {
        var map: [UUID: UUID] = [:]
        map.reserveCapacity(feeds.reduce(0) { $0 + $1.articles.count })
        for f in feeds {
            for a in f.articles {
                map[a.id] = f.id
            }
        }
        articleIDToFeedID = map
    }

    private func indexArticle(_ articleID: UUID, feedID: UUID) {
        articleIDToFeedID[articleID] = feedID
    }

    private func recomputeUnreadCount(at feedIndex: Int) {
        guard feeds.indices.contains(feedIndex) else { return }
        feeds[feedIndex].unreadCount = feeds[feedIndex].articles.reduce(0) { $0 + ($1.isRead ? 0 : 1) }
    }

    /// 超过此长度的正文/译文不进列表内存，只按 link 存 Offline cache
    private static let heavyBodyThreshold = 400

    /// 按需从 OfflineCache 按 **规范化 link** 水合正文与译文（阅读/翻译唯一读路径）。
    /// 注意：缓存里可能是 RSS 摘要（evacuate 落盘），**不得**因此把 `hasFullContent` 标为 true，
    /// 否则长摘要会跳过自动全文抓取，只能靠用户手动「重新获取」。
    func hydratedArticle(_ article: Article) -> Article {
        var a = article
        if a.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let html = OfflineCache.loadArticleBody(link: a.link), !html.isEmpty {
            a.content = html
            // 仅恢复正文；hasFullContent 只由成功的 fetchFullContent 写入
        }
        let tc = a.translatedContent?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if tc.isEmpty, let translated = OfflineCache.loadTranslatedHTML(link: a.link), !translated.isEmpty {
            a.translatedContent = translated
        }
        return a
    }

    /// 列表侧只保留元数据：正文/大译文写入 cache 后从内存清空（读写统一走 Offline cache）。
    /// **不得**在仅因长度落盘时把 `hasFullContent` 标为 true——否则会阻断真实全文抓取，且缓存未命中时正文永久空白。
    private func evacuateHeavyBodies(in article: inout Article) {
        let content = article.content
        if !content.isEmpty, content.count >= Self.heavyBodyThreshold {
            OfflineCache.persistArticleBody(link: article.link, html: content)
            article.content = ""
        } else if article.hasFullContent, !content.isEmpty {
            // 已确认全文：落盘后清内存，读路径走 cache
            OfflineCache.persistArticleBody(link: article.link, html: content)
            article.content = ""
        }
        if let translated = article.translatedContent, translated.count >= Self.heavyBodyThreshold {
            OfflineCache.saveTranslatedHTML(link: article.link, html: translated)
            article.translatedContent = nil
        }
    }

    /// 刷新合并后的文章：不把 RSS/全文 content 留在列表内存
    private func metadataOnly(_ article: Article) -> Article {
        var a = article
        evacuateHeavyBodies(in: &a)
        return a
    }

    private func evacuateAllHeavyBodiesInMemory() {
        for i in feeds.indices {
            for j in feeds[i].articles.indices {
                evacuateHeavyBodies(in: &feeds[i].articles[j])
            }
        }
    }

    /// 纠正误标：`hasFullContent` 但内存与磁盘都无正文 → 清标志，允许重新抓取
    private func recoverOrphanFullContentFlags() {
        var changed = false
        for i in feeds.indices {
            for j in feeds[i].articles.indices {
                let a = feeds[i].articles[j]
                guard a.hasFullContent else { continue }
                let mem = a.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !mem.isEmpty { continue }
                if OfflineCache.hasArticleBody(link: a.link) { continue }
                feeds[i].articles[j].hasFullContent = false
                changed = true
            }
        }
        if changed {
            articleFlagsEpoch &+= 1
            scheduleFeedsPersist()
        }
    }

    func markAsRead(_ article: Article) {
        for i in feeds.indices {
            if let j = feeds[i].articles.firstIndex(where: { $0.id == article.id }) {
                if !feeds[i].articles[j].isRead {
                    // 就地改字段 + unreadCount；不整源 feeds[i]= 赋值
                    feeds[i].articles[j].isRead = true
                    feeds[i].unreadCount = max(0, feeds[i].unreadCount - 1)
                    articleFlags.bump(feeds[i].articles[j].id)
                    articleFlagsEpoch &+= 1
                }
                rememberReadLink(feeds[i].articles[j].link)
            }
        }
        scheduleFeedsPersist()
    }

    func markAsUnread(_ article: Article) {
        for i in feeds.indices {
            if let j = feeds[i].articles.firstIndex(where: { $0.id == article.id }) {
                if feeds[i].articles[j].isRead {
                    feeds[i].articles[j].isRead = false
                    feeds[i].unreadCount += 1
                    articleFlags.bump(feeds[i].articles[j].id)
                    articleFlagsEpoch &+= 1
                }
                forgetReadLink(feeds[i].articles[j].link)
            }
        }
        scheduleFeedsPersist()
    }

    func markAllAsRead(in feedID: UUID) {
        guard let i = feeds.firstIndex(where: { $0.id == feedID }) else { return }
        var changed = false
        for j in feeds[i].articles.indices where !feeds[i].articles[j].isRead {
            feeds[i].articles[j].isRead = true
            rememberReadLink(feeds[i].articles[j].link)
            changed = true
        }
        if changed {
            feeds[i].unreadCount = 0
            articleFlags.bumpAll(feeds[i].articles.map(\.id))
            articleFlagsEpoch &+= 1
            scheduleFeedsPersist()
        }
    }

    func toggleFavorite(_ article: Article) {
        for i in feeds.indices {
            if let j = feeds[i].articles.firstIndex(where: { $0.id == article.id }) {
                let willFavorite = !feeds[i].articles[j].isFavorite
                feeds[i].articles[j].isFavorite.toggle()
                if willFavorite {
                    boostInterest(from: feeds[i].articles[j])
                    rememberFavoriteLink(feeds[i].articles[j].link)
                } else {
                    forgetFavoriteLink(feeds[i].articles[j].link)
                }
                articleFlags.bump(feeds[i].articles[j].id)
                articleFlagsEpoch &+= 1
            }
        }
        scheduleFeedsPersist()
    }

    func persistSettings() {
        SettingsRepository.save(makePersistedSettings())
        scheduleICloudPush(kind: .settings)
    }

    func updateArticle(_ article: Article) {
        var article = article
        evacuateHeavyBodies(in: &article)
        // 优先索引定位
        let feedID = articleIDToFeedID[article.id] ?? article.feedID
        if let i = feeds.firstIndex(where: { $0.id == feedID }),
           let j = feeds[i].articles.firstIndex(where: { $0.id == article.id }) {
            let wasRead = feeds[i].articles[j].isRead
            feeds[i].articles[j] = article
            if wasRead != article.isRead {
                feeds[i].unreadCount += article.isRead ? -1 : 1
                feeds[i].unreadCount = max(0, feeds[i].unreadCount)
            }
            indexArticle(article.id, feedID: feeds[i].id)
            articleFlags.bump(article.id)
        } else {
            for i in feeds.indices {
                if let j = feeds[i].articles.firstIndex(where: { $0.id == article.id }) {
                    let wasRead = feeds[i].articles[j].isRead
                    feeds[i].articles[j] = article
                    if wasRead != article.isRead {
                        feeds[i].unreadCount += article.isRead ? -1 : 1
                        feeds[i].unreadCount = max(0, feeds[i].unreadCount)
                    }
                    indexArticle(article.id, feedID: feeds[i].id)
                    articleFlags.bump(article.id)
                    break
                }
            }
        }
        saveToStorage()
    }

    /// - Parameter persist: 批量翻译时可传 false，结束后再统一 saveToStorage，避免每批写盘
    func applyListTranslations(
        _ updates: [(id: UUID, title: String?, summary: String?)],
        persist: Bool = true
    ) {
        guard !updates.isEmpty else { return }
        var byID: [UUID: (title: String?, summary: String?)] = [:]
        byID.reserveCapacity(updates.count)
        for u in updates {
            var merged = byID[u.id] ?? (nil, nil)
            if let t = u.title { merged.title = t }
            if let s = u.summary { merged.summary = s }
            byID[u.id] = merged
        }
        var remaining = byID.count
        var changed = false
        for i in feeds.indices {
            guard remaining > 0 else { break }
            for j in feeds[i].articles.indices {
                guard let patch = byID[feeds[i].articles[j].id] else { continue }
                if let t = patch.title { feeds[i].articles[j].translatedTitle = t; changed = true }
                if let s = patch.summary { feeds[i].articles[j].translatedSummary = s; changed = true }
                remaining -= 1
                if remaining == 0 { break }
            }
        }
        if changed, persist { saveToStorage() }
    }

    func addFeed(_ feed: RSSFeed) {
        var f = feed
        f.sortOrder = (feeds.map(\.sortOrder).max() ?? -1) + 1
        feeds.append(f)
        saveToStorage()
    }
    func deleteFeed(at offsets: IndexSet) { feeds.remove(atOffsets: offsets); saveToStorage() }

    func deleteAllFeeds() {
        feeds = []
        saveToStorage()
    }

    // MARK: - Settings export / import / AI probe

    /// 设置备份中的源级偏好（不含文章正文，按 URL 匹配恢复）
    struct FeedSettingsSnapshot: Codable {
        var url: String
        var title: String?
        /// 分组名（跨设备比 UUID 更稳）
        var groupName: String?
        var fetchFullContentEnabled: Bool?
        var fetchCommentsEnabled: Bool?
        var autoTranslateEnabled: Bool?
        var useFullContentURLPrefix: Bool?
        var summaryPromptPresetID: String?
        var sortOrder: Int?
    }

    struct GroupSettingsSnapshot: Codable {
        var name: String
        var sortOrder: Int?
    }

    struct SettingsExportPayload: Codable {
        var version: Int
        /// v6+：完整偏好快照（与本地 PersistedAppSettings 同构；新增设置自动覆盖）
        var settings: PersistedAppSettings?
        // —— 以下为 v1–v5 扁平字段，继续写出以兼容旧导入；新字段以 settings 为准 ——
        var fontSize: Double
        var listTitleFontSize: Double
        var listSummaryFontSize: Double
        var readerTitleFontSize: Double
        var aiSummaryFontSize: Double
        var feedTitleFontSize: Double
        var groupTitleFontSize: Double
        var titleDisplayMode: String
        var defaultTranslationEngine: String
        var showReadArticles: Bool
        var showUnreadCount: Bool?
        var translationPrompt: String
        var summaryPrompt: String
        var explainPrompt: String
        var readRetentionDays: Int
        var fullContentCacheDays: Int
        var fullContentURLPrefixEnabled: Bool?
        var fullContentURLPrefix: String?
        var feedSortMode: String?
        var appFontFamily: String?
        var targetLanguage: String?
        var aiOutputLanguage: String?
        var translationEngineChain: [String]?
        var translationConcurrency: Int?
        var microsoftTranslateRegion: String?
        var lingvaCustomBase: String?
        var globalSummaryPresetID: String?
        var summaryPromptPresets: [SummaryPromptPreset]?
        var smartInterestFilterEnabled: Bool?
        var autoMarkLowInterestRead: Bool?
        var lowInterestThreshold: Double?
        var sortByInterestScore: Bool?
        var modelRoutingEnabled: Bool?
        var modelRoutingShortLimit: Int?
        var interestWeights: [String: Double]?
        var defaultChatProviderID: UUID?
        var ttsVoice: String
        var ttsRate: Double?
        var colorTheme: String
        var appearanceMode: String?
        var aiBlacklistTerms: [String]
        var articleBlacklistTerms: [String]
        var defaultSummaryProviderID: UUID?
        var defaultTranslationProviderID: UUID?
        var defaultExplainProviderID: UUID?
        var aiBlacklistFallbackProviderID: UUID?
        var aiProviders: [AIProvider]
        var translationKeys: [String: String]?
        var aiKeys: [String: String]?
        var bookDefaultReadingMode: String?
        var bookTTSRate: Double?
        var bookAutoLanguageVoice: Bool?
        var groups: [GroupSettingsSnapshot]?
        var feeds: [FeedSettingsSnapshot]?
    }

    func exportSettingsJSON(includeSecrets: Bool = false) throws -> Data {
        let groupNameByID = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0.name) })
        let feedSnaps: [FeedSettingsSnapshot] = feeds.map { f in
            FeedSettingsSnapshot(
                url: f.url,
                title: f.title,
                groupName: f.groupID.flatMap { groupNameByID[$0] },
                fetchFullContentEnabled: f.fetchFullContentEnabled,
                fetchCommentsEnabled: f.fetchCommentsEnabled,
                autoTranslateEnabled: f.autoTranslateEnabled,
                useFullContentURLPrefix: f.useFullContentURLPrefix,
                summaryPromptPresetID: f.summaryPromptPresetID,
                sortOrder: f.sortOrder
            )
        }
        let groupSnaps: [GroupSettingsSnapshot] = groups.map {
            GroupSettingsSnapshot(name: $0.name, sortOrder: $0.sortOrder)
        }
        let snap = makePersistedSettings()
        let payload = SettingsExportPayload(
            version: 6,
            settings: snap,
            fontSize: fontSize,
            listTitleFontSize: listTitleFontSize,
            listSummaryFontSize: listSummaryFontSize,
            readerTitleFontSize: readerTitleFontSize,
            aiSummaryFontSize: aiSummaryFontSize,
            feedTitleFontSize: feedTitleFontSize,
            groupTitleFontSize: groupTitleFontSize,
            titleDisplayMode: titleDisplayMode.rawValue,
            defaultTranslationEngine: defaultTranslationEngine.rawValue,
            showReadArticles: showReadArticles,
            showUnreadCount: showUnreadCount,
            translationPrompt: translationPrompt,
            summaryPrompt: summaryPrompt,
            explainPrompt: explainPrompt,
            readRetentionDays: readRetentionDays,
            fullContentCacheDays: fullContentCacheDays,
            fullContentURLPrefixEnabled: fullContentURLPrefixEnabled,
            fullContentURLPrefix: fullContentURLPrefix,
            feedSortMode: feedSortMode.rawValue,
            appFontFamily: appFontFamily.rawValue,
            targetLanguage: targetLanguage.rawValue,
            aiOutputLanguage: aiOutputLanguage.rawValue,
            translationEngineChain: translationEngineChain.map(\.rawValue),
            translationConcurrency: translationConcurrency,
            microsoftTranslateRegion: microsoftTranslateRegion,
            lingvaCustomBase: lingvaCustomBase,
            globalSummaryPresetID: globalSummaryPresetID,
            summaryPromptPresets: summaryPromptPresets,
            smartInterestFilterEnabled: smartInterestFilterEnabled,
            autoMarkLowInterestRead: autoMarkLowInterestRead,
            lowInterestThreshold: lowInterestThreshold,
            sortByInterestScore: sortByInterestScore,
            modelRoutingEnabled: modelRoutingEnabled,
            modelRoutingShortLimit: modelRoutingShortLimit,
            interestWeights: interestWeights,
            defaultChatProviderID: defaultChatProviderID,
            ttsVoice: ttsVoice,
            ttsRate: ttsRate,
            colorTheme: colorTheme.rawValue,
            appearanceMode: appearanceMode.rawValue,
            aiBlacklistTerms: aiBlacklistTerms,
            articleBlacklistTerms: articleBlacklistTerms,
            defaultSummaryProviderID: defaultSummaryProviderID,
            defaultTranslationProviderID: defaultTranslationProviderID,
            defaultExplainProviderID: defaultExplainProviderID,
            aiBlacklistFallbackProviderID: aiBlacklistFallbackProviderID,
            aiProviders: aiProviders,
            translationKeys: includeSecrets ? [
                "google_translate_key": loadGoogleKeys().joined(separator: "\n"),
                "microsoft_translate_key": loadMicrosoftKeys().joined(separator: "\n"),
                "deepl_translate_key": loadDeepLKeys().joined(separator: "\n")
            ].filter { !$0.value.isEmpty } : nil,
            aiKeys: includeSecrets ? Dictionary(uniqueKeysWithValues: aiProviders.compactMap { p -> (String, String)? in
                let keys = loadAIKeys(for: p.id)
                guard !keys.isEmpty else { return nil }
                return (p.id.uuidString, keys.joined(separator: "\n"))
            }) : nil,
            bookDefaultReadingMode: settings.bookDefaultReadingMode,
            bookTTSRate: settings.bookTTSRate,
            bookAutoLanguageVoice: settings.bookAutoLanguageVoice,
            groups: groupSnaps,
            feeds: feedSnaps
        )
        return try JSONEncoder().encode(payload)
    }

    func importSettingsJSON(_ data: Data) throws {
        let payload = try JSONDecoder().decode(SettingsExportPayload.self, from: data)
        // v6+：整包偏好快照优先（覆盖所有已注册设置，含日后新增字段）
        if let snap = payload.settings {
            applyPersistedSettings(snap)
        } else {
            applyLegacyFlatSettingsExport(payload)
        }
        // API Key 与源级开关在快照外，始终按 payload 合并
        for (k, v) in (payload.translationKeys ?? [:]) where !v.isEmpty {
            if k == "deepl_translate_key" {
                let parts = v.components(separatedBy: CharacterSet.newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                saveDeepLKeys(parts.isEmpty ? [v] : parts)
            } else {
                Keychain.save(key: k, value: v)
            }
        }
        for (idStr, v) in (payload.aiKeys ?? [:]) where !v.isEmpty {
            guard let uuid = UUID(uuidString: idStr) else { continue }
            let parts = v.components(separatedBy: CharacterSet.newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            saveAIKeys(for: uuid, keys: parts.isEmpty ? [v] : parts)
        }
        applyImportedFeedAndGroupSettings(
            groups: payload.groups ?? [],
            feeds: payload.feeds ?? []
        )
        saveToStorage()
    }

    /// v5 及更早扁平备份
    private func applyLegacyFlatSettingsExport(_ payload: SettingsExportPayload) {
        fontSize = payload.fontSize
        listTitleFontSize = payload.listTitleFontSize
        listSummaryFontSize = payload.listSummaryFontSize
        readerTitleFontSize = payload.readerTitleFontSize
        aiSummaryFontSize = payload.aiSummaryFontSize
        feedTitleFontSize = payload.feedTitleFontSize
        groupTitleFontSize = payload.groupTitleFontSize
        if let m = TitleDisplayMode(rawValue: payload.titleDisplayMode) { titleDisplayMode = m }
        if let e = TranslationEngine(rawValue: payload.defaultTranslationEngine) { defaultTranslationEngine = e }
        showReadArticles = payload.showReadArticles
        if let v = payload.showUnreadCount { showUnreadCount = v }
        translationPrompt = payload.translationPrompt
        summaryPrompt = payload.summaryPrompt
        explainPrompt = payload.explainPrompt
        readRetentionDays = payload.readRetentionDays
        fullContentCacheDays = payload.fullContentCacheDays
        if let enabled = payload.fullContentURLPrefixEnabled {
            fullContentURLPrefixEnabled = enabled
        }
        if let prefix = payload.fullContentURLPrefix {
            fullContentURLPrefix = prefix
        }
        if let fam = payload.appFontFamily, let f = AppFontFamily(rawValue: fam) {
            appFontFamily = f
        }
        if let raw = payload.targetLanguage, let lang = AppLanguage(rawValue: raw) {
            targetLanguage = lang
        }
        if let raw = payload.aiOutputLanguage, let lang = AppLanguage(rawValue: raw) {
            aiOutputLanguage = lang
        }
        if let chain = payload.translationEngineChain {
            let engines = chain.compactMap { TranslationEngine(rawValue: $0) }
            if !engines.isEmpty { translationEngineChain = engines }
        }
        if let n = payload.translationConcurrency {
            translationConcurrency = max(0, n)
        }
        if let region = payload.microsoftTranslateRegion {
            microsoftTranslateRegion = region
        }
        if let base = payload.lingvaCustomBase {
            lingvaCustomBase = base
        }
        if let id = payload.globalSummaryPresetID, !id.isEmpty {
            globalSummaryPresetID = id
        }
        if let presets = payload.summaryPromptPresets, !presets.isEmpty {
            summaryPromptPresets = presets
        }
        if let v = payload.smartInterestFilterEnabled { smartInterestFilterEnabled = v }
        if let v = payload.autoMarkLowInterestRead { autoMarkLowInterestRead = v }
        if let v = payload.lowInterestThreshold {
            lowInterestThreshold = min(1, max(0, v))
        }
        if let v = payload.sortByInterestScore { sortByInterestScore = v }
        if let v = payload.modelRoutingEnabled { modelRoutingEnabled = v }
        if let v = payload.modelRoutingShortLimit {
            modelRoutingShortLimit = max(100, v)
        }
        if let w = payload.interestWeights { interestWeights = w }
        if let id = payload.defaultChatProviderID { defaultChatProviderID = id }
        ttsVoice = payload.ttsVoice
        if let r = payload.ttsRate {
            ttsRate = min(2.0, max(0.5, r))
            settings.bookTTSRate = ttsRate
        }
        if let mode = payload.bookDefaultReadingMode, !mode.isEmpty {
            settings.bookDefaultReadingMode = mode
        }
        if let r = payload.bookTTSRate {
            settings.bookTTSRate = min(2.0, max(0.5, r))
            ttsRate = settings.bookTTSRate
        }
        if let v = payload.bookAutoLanguageVoice {
            settings.bookAutoLanguageVoice = v
        }
        if let th = ReadingTheme(rawValue: payload.colorTheme) {
            colorTheme = th
        } else {
            switch payload.colorTheme {
            case "azure": colorTheme = .classicLight
            case "sepia": colorTheme = .sepiaPaper
            case "midnight": colorTheme = .midnightBlue
            case "forest": colorTheme = .forestSage
            case "graphite": colorTheme = .nightDark
            default: break
            }
        }
        if let raw = payload.appearanceMode, let mode = AppearanceMode(rawValue: raw) { appearanceMode = mode }
        aiBlacklistTerms = payload.aiBlacklistTerms
        articleBlacklistTerms = payload.articleBlacklistTerms
        defaultSummaryProviderID = payload.defaultSummaryProviderID
        defaultTranslationProviderID = payload.defaultTranslationProviderID
        defaultExplainProviderID = payload.defaultExplainProviderID
        aiBlacklistFallbackProviderID = payload.aiBlacklistFallbackProviderID
        if !payload.aiProviders.isEmpty { aiProviders = payload.aiProviders }
        if let sortRaw = payload.feedSortMode, let sort = FeedSortMode(rawValue: sortRaw) {
            feedSortMode = sort
        }
    }

    /// 将备份中的分组与源级开关合并到当前订阅（按 URL / 分组名匹配，不删已有源）
    private func applyImportedFeedAndGroupSettings(
        groups groupSnaps: [GroupSettingsSnapshot],
        feeds feedSnaps: [FeedSettingsSnapshot]
    ) {
        guard !groupSnaps.isEmpty || !feedSnaps.isEmpty else { return }

        for g in groupSnaps {
            let name = g.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            if let idx = groups.firstIndex(where: { $0.name == name }) {
                if let order = g.sortOrder {
                    groups[idx].sortOrder = order
                }
            } else {
                groups.append(FeedGroup(name: name, sortOrder: g.sortOrder ?? groups.count))
            }
        }
        FeedRepository.saveGroups(groups)

        let groupIDByName = Dictionary(uniqueKeysWithValues: groups.map { ($0.name, $0.id) })
        var touched = false
        for snap in feedSnaps {
            let key = Self.canonicalLink(snap.url)
            guard !key.isEmpty else { continue }
            guard let i = feeds.firstIndex(where: { Self.canonicalLink($0.url) == key }) else { continue }
            if let v = snap.fetchFullContentEnabled { feeds[i].fetchFullContentEnabled = v }
            if let v = snap.fetchCommentsEnabled { feeds[i].fetchCommentsEnabled = v }
            if let v = snap.autoTranslateEnabled { feeds[i].autoTranslateEnabled = v }
            if let v = snap.useFullContentURLPrefix { feeds[i].useFullContentURLPrefix = v }
            if let v = snap.summaryPromptPresetID, !v.isEmpty { feeds[i].summaryPromptPresetID = v }
            if let v = snap.sortOrder { feeds[i].sortOrder = v }
            if let title = snap.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                feeds[i].title = title
            }
            if let gName = snap.groupName?.trimmingCharacters(in: .whitespacesAndNewlines), !gName.isEmpty {
                feeds[i].groupID = groupIDByName[gName]
            }
            touched = true
        }
        if touched {
            articleFlagsEpoch &+= 1
            rebuildArticleIndex()
        }
    }


    /// 单 Key 连通性探测（用于设置页 Key 行旁标记）
    func probeGoogleKey(_ key: String) async -> Bool {
        // 兼容旧调用；Google 已固定无 Key
        do {
            let out = try await GoogleTranslate.translate(text: "Hello", targetLang: targetLanguage.googleCode)
            return !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } catch {
            return false
        }
    }


    func probeMicrosoftKey(_ key: String) async -> Bool {
        do {
            let out = try await MicrosoftTranslate.translate(
                text: "Hello",
                apiKey: key,
                region: microsoftTranslateRegion,
                targetLang: targetLanguage.microsoftCode
            )
            return !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } catch {
            return false
        }
    }

    func probeDeepLKey(_ key: String) async -> Bool {
        do {
            let out = try await DeepLTranslate.translate(
                text: "Hello",
                apiKey: key,
                targetLang: targetLanguage.deeplCode
            )
            return !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } catch {
            return false
        }
    }

    func probeAIKey(provider: AIProvider, key: String) async -> Bool {
        let prompt = "Reply with exactly: OK"
        do {
            let text = try await callAI(prompt: prompt, provider: provider, apiKey: key, maxTokens: 16)
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } catch {
            return false
        }
    }

    private func maskKeyForTest(_ key: String) -> String {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard k.count > 8 else { return String(repeating: "•", count: max(4, k.count)) }
        return String(k.prefix(4)) + "…" + String(k.suffix(4))
    }

    /// 仅测试指定 Provider：逐个 Key 验证是否可用
    func testAIProvider(_ providerID: UUID?) async throws -> String {
        guard let id = providerID,
              let provider = aiProviders.first(where: { $0.id == id }) else {
            throw TranslationError.noProvider
        }
        let keys = loadAIKeys(for: id)
        guard !keys.isEmpty else {
            throw TranslationError.apiError("未配置 API Key")
        }
        let prompt = "You are a connectivity probe. Reply with exactly the two letters: OK"
        var lines: [String] = ["\(provider.name)：共 \(keys.count) 个 Key"]
        var okCount = 0
        for (i, key) in keys.enumerated() {
            let label = "Key\(i + 1) (\(maskKeyForTest(key)))"
            do {
                let text = try await callAI(prompt: prompt, provider: provider, apiKey: key, maxTokens: 32)
                let preview = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if preview.isEmpty {
                    lines.append("• \(label)：不可用（空响应）")
                } else {
                    okCount += 1
                    lines.append("• \(label)：可用")
                }
            } catch {
                lines.append("• \(label)：不可用 — \(error.localizedDescription)")
            }
        }
        lines.append(okCount > 0 ? "结果：\(okCount)/\(keys.count) 可用" : "结果：全部不可用")
        if okCount == 0 {
            throw TranslationError.apiError(lines.joined(separator: "\n"))
        }
        return lines.joined(separator: "\n")
    }

    /// 测试翻译引擎：标明对应 Key 是否可用（多 Key 时逐个测）
    func testTranslationEngine(_ engine: TranslationEngine? = nil) async throws -> String {
        let eng = engine ?? defaultTranslationEngine
        let sample = "Hello, world."
        switch eng {
        case .google:
            do {
                let out = try await GoogleTranslate.translate(text: sample, targetLang: targetLanguage.googleCode)
                let preview = out.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !preview.isEmpty else { throw TranslationError.apiError("返回空译文") }
                return "Google（免 Key）：可用\n试译：\(preview.prefix(60))"
            } catch {
                throw TranslationError.apiError("Google（免 Key）：不可用 — \(error.localizedDescription)")
            }
        case .mymemory:
            do {
                let out = try await MyMemoryTranslate.translate(text: sample, targetLang: targetLanguage.mymemoryCode)
                let preview = out.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !preview.isEmpty else { throw TranslationError.apiError("MyMemory 返回空译文") }
                return "MyMemory（无需 Key）：可用\n试译：\(preview.prefix(60))"
            } catch {
                throw TranslationError.apiError("MyMemory（无需 Key）：不可用 — \(error.localizedDescription)")
            }
        case .lingva:
            do {
                let out = try await LingvaTranslate.translate(
                    text: sample,
                    targetLang: targetLanguage.googleCode,
                    customBase: lingvaCustomBase.isEmpty ? nil : lingvaCustomBase
                )
                let preview = out.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !preview.isEmpty else { throw TranslationError.apiError("Lingva 返回空译文") }
                let hostHint = lingvaCustomBase.isEmpty ? "公共实例" : lingvaCustomBase
                return "Lingva（\(hostHint)）：可用\n试译：\(preview.prefix(60))"
            } catch {
                throw TranslationError.apiError("Lingva：不可用 — \(error.localizedDescription)")
            }
        case .yandex:
            do {
                let out = try await YandexTranslate.translate(text: sample, targetLang: targetLanguage.googleCode)
                let preview = out.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !preview.isEmpty else { throw TranslationError.apiError("Yandex 返回空译文") }
                return "Yandex（免 Key）：可用\n试译：\(preview.prefix(60))"
            } catch {
                throw TranslationError.apiError("Yandex：不可用 — \(error.localizedDescription)")
            }
        case .azure:
            do {
                let out = try await AzureBingTranslate.translate(text: sample, targetLang: targetLanguage.microsoftCode)
                let preview = out.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !preview.isEmpty else { throw TranslationError.apiError("Azure/Bing 返回空译文") }
                return "Azure/Bing（免 Key）：可用\n试译：\(preview.prefix(60))"
            } catch {
                throw TranslationError.apiError("Azure/Bing：不可用 — \(error.localizedDescription)")
            }
        case .microsoft:
            let keys = loadMicrosoftKeys()
            guard !keys.isEmpty else { throw TranslationError.apiError("Microsoft：未配置 API Key") }
            var lines: [String] = ["Microsoft：共 \(keys.count) 个 Key · 区域 \(microsoftTranslateRegion.isEmpty ? "global" : microsoftTranslateRegion)"]
            var ok = 0
            for (i, key) in keys.enumerated() {
                let label = "Key\(i + 1) (\(maskKeyForTest(key)))"
                do {
                    let out = try await MicrosoftTranslate.translate(text: sample, apiKey: key, region: microsoftTranslateRegion, targetLang: targetLanguage.microsoftCode)
                    if out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        lines.append("• \(label)：不可用（空译文）")
                    } else {
                        ok += 1
                        lines.append("• \(label)：可用")
                    }
                } catch {
                    lines.append("• \(label)：不可用 — \(error.localizedDescription)")
                }
            }
            lines.append(ok > 0 ? "结果：\(ok)/\(keys.count) 可用" : "结果：全部不可用")
            if ok == 0 { throw TranslationError.apiError(lines.joined(separator: "\n")) }
            return lines.joined(separator: "\n")
        case .deepl:
            let keys = loadDeepLKeys()
            guard !keys.isEmpty else {
                throw TranslationError.apiError("DeepL：未配置 API Key")
            }
            var lines: [String] = ["DeepL：共 \(keys.count) 个 Key"]
            var okCount = 0
            let lang = targetLanguage.deeplCode
            for (i, key) in keys.enumerated() {
                let label = "Key\(i + 1) (\(maskKeyForTest(key)))"
                do {
                    let out = try await DeepLTranslate.translate(text: sample, apiKey: key, targetLang: lang)
                    let preview = out.trimmingCharacters(in: .whitespacesAndNewlines)
                    if preview.isEmpty {
                        lines.append("• \(label)：不可用（空译文）")
                    } else {
                        okCount += 1
                        lines.append("• \(label)：可用 — \(preview.prefix(40))")
                    }
                } catch {
                    lines.append("• \(label)：不可用 — \(error.localizedDescription)")
                }
            }
            lines.append(okCount > 0 ? "结果：\(okCount)/\(keys.count) 可用" : "结果：全部不可用")
            if okCount == 0 {
                throw TranslationError.apiError(lines.joined(separator: "\n"))
            }
            return lines.joined(separator: "\n")
        case .ai:
            let id = defaultTranslationProviderID ?? defaultSummaryProviderID
            return try await testAIProvider(id)
        }
    }


    var feedsByGroup: [(group: FeedGroup?, feeds: [RSSFeed])] {
        let sortedGroups = groups.sorted { $0.sortOrder < $1.sortOrder || ($0.sortOrder == $1.sortOrder && $0.name < $1.name) }
        var sections: [(FeedGroup?, [RSSFeed])] = []
        for g in sortedGroups {
            let items = sortedFeeds(feeds.filter { $0.groupID == g.id })
            if !items.isEmpty { sections.append((g, items)) }
        }
        let ungrouped = sortedFeeds(feeds.filter { feed in
            guard let gid = feed.groupID else { return true }
            return !groups.contains(where: { $0.id == gid })
        })
        if !ungrouped.isEmpty || sections.isEmpty { sections.append((nil, ungrouped)) }
        return sections
    }

    /// 列表可见 section：稳定快照 + 显式依赖关键字段。
    /// token 包含：feeds 结构/未读/标题/排序/分组、showReadArticles、sortMode、articleFlagsEpoch。
    /// chrome 进度等不参与 token，避免刷新条牵动整表重建。
    func visibleFeedSectionsSnapshot() -> [(sectionID: String, group: FeedGroup?, feeds: [RSSFeed])] {
        let token = feedSectionsCacheToken()
        if token == _feedSectionsCacheToken {
            return _feedSectionsSnapshot
        }
        let built: [(sectionID: String, group: FeedGroup?, feeds: [RSSFeed])] = feedsByGroup.compactMap { section in
            let items = showReadArticles
                ? section.feeds
                : section.feeds.filter { $0.unreadCount > 0 }
            guard !items.isEmpty else { return nil }
            let sid = section.group?.id.uuidString ?? "__ungrouped__"
            return (sid, section.group, items)
        }
        _feedSectionsCacheToken = token
        _feedSectionsSnapshot = built
        return built
    }

    private func feedSectionsCacheToken() -> Int {
        var hasher = Hasher()
        hasher.combine(articleFlagsEpoch)
        hasher.combine(showReadArticles)
        hasher.combine(feedSortMode.rawValue)
        hasher.combine(groups.count)
        for g in groups {
            hasher.combine(g.id)
            hasher.combine(g.sortOrder)
            hasher.combine(g.name)
        }
        hasher.combine(feeds.count)
        for f in feeds {
            hasher.combine(f.id)
            hasher.combine(f.groupID)
            hasher.combine(f.unreadCount)
            hasher.combine(f.title)
            hasher.combine(f.sortOrder)
            hasher.combine(f.lastFetched?.timeIntervalSince1970 ?? 0)
            hasher.combine(f.lastRefreshError)
            hasher.combine(f.faviconURL)
        }
        return hasher.finalize()
    }

    /// 按当前 `feedSortMode` 对源列表排序
    func sortedFeeds(_ list: [RSSFeed]) -> [RSSFeed] {
        switch feedSortMode {
        case .unreadThenTitle:
            return list.sorted {
                if $0.unreadCount != $1.unreadCount { return $0.unreadCount > $1.unreadCount }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        case .title:
            return list.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .lastFetched:
            return list.sorted {
                let a = $0.lastFetched ?? .distantPast
                let b = $1.lastFetched ?? .distantPast
                if a != b { return a > b }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        case .manual:
            return list.sorted {
                if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        }
    }

    /// 同组内重排：source/destination 为该组可见列表中的下标
    func reorderFeeds(groupID: UUID?, from source: IndexSet, to destination: Int) {
        var ids = feeds
            .filter { feed in
                if let groupID { return feed.groupID == groupID }
                return feed.groupID == nil || !groups.contains(where: { $0.id == feed.groupID })
            }
            .sorted { $0.sortOrder < $1.sortOrder || ($0.sortOrder == $1.sortOrder && $0.title < $1.title) }
            .map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        for (order, id) in ids.enumerated() {
            guard let idx = feeds.firstIndex(where: { $0.id == id }) else { continue }
            var f = feeds[idx]
            f.sortOrder = order
            feeds[idx] = f
        }
        saveToStorage()
    }

    func addGroup(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if groups.contains(where: { $0.name == trimmed }) { return }
        let order = (groups.map(\.sortOrder).max() ?? -1) + 1
        groups.append(FeedGroup(name: trimmed, sortOrder: order))
        saveToStorage()
    }

    func renameGroup(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let idx = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[idx].name = trimmed
        saveToStorage()
    }

    func deleteGroup(_ id: UUID) {
        for i in feeds.indices where feeds[i].groupID == id { feeds[i].groupID = nil }
        groups.removeAll { $0.id == id }
        saveToStorage()
    }

    func moveFeed(_ feedID: UUID, toGroup groupID: UUID?) {
        guard let idx = feeds.firstIndex(where: { $0.id == feedID }) else { return }
        feeds[idx].groupID = groupID
        saveToStorage()
    }

    func group(for feed: RSSFeed) -> FeedGroup? {
        guard let gid = feed.groupID else { return nil }
        return groups.first { $0.id == gid }
    }

    func isGroupCollapsed(_ groupID: UUID?) -> Bool {
        if let id = groupID { return collapsedGroupIDs.contains(id) }
        return isUngroupedCollapsed
    }

    func toggleGroupCollapsed(_ groupID: UUID?) {
        if let id = groupID {
            if collapsedGroupIDs.contains(id) { collapsedGroupIDs.remove(id) }
            else { collapsedGroupIDs.insert(id) }
        } else {
            isUngroupedCollapsed.toggle()
        }
        persistCollapsedGroups()
    }

    private func persistCollapsedGroups() {
        FeedRepository.saveCollapsedState(groupIDs: collapsedGroupIDs, isUngroupedCollapsed: isUngroupedCollapsed)
    }

    private func loadCollapsedGroups() {
        collapsedGroupIDs = FeedRepository.loadCollapsedGroupIDs()
        isUngroupedCollapsed = FeedRepository.loadIsUngroupedCollapsed()
    }

    func purgeOldReadArticles() {
        let days = max(0, readRetentionDays)
        guard days > 0 else { return }
        let cutoff = Date().addingTimeInterval(-TimeInterval(days) * 24 * 3600)
        var changed = false
        for i in feeds.indices {
            let before = feeds[i].articles.count
            feeds[i].articles.removeAll { article in
                guard article.isRead else { return false }
                if article.isFavorite { return false }
                if let date = article.publishedDate { return date < cutoff }
                return true
            }
            if feeds[i].articles.count != before {
                feeds[i].unreadCount = feeds[i].articles.filter { !$0.isRead }.count
                changed = true
            }
        }
        if changed { saveToStorage() }
    }

    func pruneFullContentCache() {
        let days = max(0, fullContentCacheDays)
        if days == 0 { return }
        OfflineCache.pruneArticleHTML(maxAge: TimeInterval(days) * 24 * 3600)
    }

    func refreshFeed(_ feedID: UUID) async {
        _ = await refreshFeedResult(feedID)
    }

    /// 刷新单个源；返回失败说明（已含源名），成功返回 nil
    @discardableResult
    func refreshFeedResult(_ feedID: UUID, manageLoading: Bool = true, persist: Bool = true) async -> String? {
        guard let idx = feeds.firstIndex(where: { $0.id == feedID }) else { return nil }
        let feedTitle = feeds[idx].title.isEmpty ? "未命名源" : feeds[idx].title
        let urlStr = feeds[idx].url
        guard var url = NetworkURLPolicy.validate(urlStr) else {
            let reason = "不允许的地址（仅支持公网 http/https）"
            setFeedRefreshError(feedID, reason: reason, persist: persist)
            let msg = "「\(feedTitle)」：\(reason)"
            if manageLoading { errorMessage = msg }
            return msg
        }
        if manageLoading {
            withAnimation(.easeInOut(duration: 0.28)) {
                isLoading = true
                if !isRefreshingAll {
                    refreshProgressTotal = 1
                    refreshProgressCurrent = 1
                    refreshProgressTitle = feedTitle
                }
            }
        }
        defer {
            if manageLoading, !isRefreshingAll {
                Task { @MainActor in
                    withAnimation(.easeInOut(duration: 0.25)) {
                        refreshProgressTitle = "完成"
                    }
                    try? await Task.sleep(nanoseconds: 280_000_000)
                    withAnimation(.easeInOut(duration: 0.35)) {
                        isLoading = false
                        refreshProgressCurrent = 0
                        refreshProgressTotal = 0
                        refreshProgressTitle = ""
                    }
                }
            }
        }
        do {
            // 网络 + 解析在 FeedRefreshService.nonisolated 完成；此处仅 MainActor 合并
            let payload = try await FeedRefreshService.fetchAndParse(
                url: url,
                feedID: feedID,
                feedTitle: feedTitle,
                cacheKeyURLString: urlStr
            )
            if payload.notModified {
                // 304：源站无更新，跳过 merge，仅刷新时间戳
                if let i = feeds.firstIndex(where: { $0.id == feedID }) {
                    feeds[i].lastFetched = Date()
                }
                clearFeedRefreshError(feedID, persist: persist)
                if persist { scheduleFeedsPersist() }
            } else {
                applyParsedFeed(
                    data: payload.data,
                    preParsedArticles: payload.articles,
                    feedID: feedID,
                    urlStr: urlStr,
                    persist: persist
                )
                if payload.upgradedToHTTPS,
                   let i = feeds.firstIndex(where: { $0.id == feedID }) {
                    feeds[i].url = payload.resolvedURL.absoluteString
                    if persist { saveToStorage() }
                }
                clearFeedRefreshError(feedID, persist: persist)
            }
            return nil
        } catch {
            if let cached = OfflineCache.loadFeedXML(url: urlStr) {
                let articles = await FeedRefreshService.parseOffline(
                    data: cached,
                    feedID: feedID,
                    feedTitle: feedTitle
                )
                applyParsedFeed(
                    data: cached,
                    preParsedArticles: articles,
                    feedID: feedID,
                    urlStr: urlStr,
                    persist: persist
                )
                let detail = Self.friendlyNetworkError(error)
                let reason = "已用本地缓存（\(detail)）"
                setFeedRefreshError(feedID, reason: reason, persist: persist)
                let msg = "「\(feedTitle)」：\(reason)"
                if manageLoading { errorMessage = msg }
                return msg
            } else {
                let reason = Self.friendlyNetworkError(error)
                setFeedRefreshError(feedID, reason: reason, persist: persist)
                let msg = "「\(feedTitle)」：\(reason)"
                if manageLoading { errorMessage = msg }
                return msg
            }
        }
    }

    private func setFeedRefreshError(_ feedID: UUID, reason: String, persist: Bool) {
        guard let i = feeds.firstIndex(where: { $0.id == feedID }) else { return }
        let clipped = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clipped.isEmpty else { return }
        if feeds[i].lastRefreshError == clipped { return }
        feeds[i].lastRefreshError = clipped
        // 批量 refreshAll 结束时统一落盘；单源刷新可即时持久化
        if persist { saveToStorage() }
    }

    private func clearFeedRefreshError(_ feedID: UUID, persist: Bool) {
        guard let i = feeds.firstIndex(where: { $0.id == feedID }) else { return }
        guard feeds[i].lastRefreshError != nil else { return }
        feeds[i].lastRefreshError = nil
        if persist { saveToStorage() }
    }

    private static func friendlyNetworkError(_ error: Error) -> String {
        // 优先使用带状态码/主机的明确错误
        if let fetch = error as? FeedRefreshService.FetchError {
            return fetch.errorDescription ?? "网络异常"
        }
        if let urlErr = error as? URLError {
            switch urlErr.code {
            case .notConnectedToInternet:
                return "设备未连接网络，请检查 Wi‑Fi 或蜂窝数据"
            case .timedOut:
                return "连接超时（约 12 秒无响应），源站可能较慢或不可达"
            case .cannotFindHost, .dnsLookupFailed:
                return "无法解析主机名，请检查订阅地址是否正确"
            case .cannotConnectToHost:
                return "无法连接到服务器，源站可能宕机或拒绝连接"
            case .networkConnectionLost:
                return "网络连接中断，请稍后重试"
            case .secureConnectionFailed:
                return "安全连接失败（证书或 TLS 异常）"
            case .serverCertificateUntrusted, .serverCertificateHasBadDate,
                 .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot:
                return "服务器证书不受信任，无法建立 HTTPS"
            case .appTransportSecurityRequiresSecureConnection:
                return "需要 HTTPS 连接（系统 ATS 限制了明文 HTTP）"
            case .noPermissionsToReadFile:
                return "源站开启了访问验证（如 Cloudflare），应用内无法读取 Feed"
            case .cannotParseResponse:
                return "无法解析为有效的 RSS/Atom 内容"
            case .badServerResponse:
                return "服务器响应异常"
            case .badURL, .unsupportedURL:
                return "订阅地址无效"
            case .dataNotAllowed:
                return "当前网络策略不允许数据访问（如关闭了蜂窝数据）"
            case .internationalRoamingOff:
                return "国际漫游已关闭，无法访问网络"
            case .callIsActive:
                return "通话中，网络暂时不可用"
            case .cancelled:
                return "请求已取消"
            default:
                break
            }
        }
        let ns = error as NSError
        let text = error.localizedDescription
        if text.localizedCaseInsensitiveContains("App Transport Security")
            || text.localizedCaseInsensitiveContains("secure connection") {
            return "该源使用了不安全的 HTTP。请确认系统允许，或改用 HTTPS 地址。"
        }
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorNotConnectedToInternet: return "设备未连接网络，请检查 Wi‑Fi 或蜂窝数据"
            case NSURLErrorTimedOut: return "连接超时（约 12 秒无响应），源站可能较慢或不可达"
            case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed: return "无法解析主机名，请检查订阅地址是否正确"
            case NSURLErrorCannotConnectToHost: return "无法连接到服务器，源站可能宕机或拒绝连接"
            case NSURLErrorNetworkConnectionLost: return "网络连接中断，请稍后重试"
            case NSURLErrorAppTransportSecurityRequiresSecureConnection: return "需要 HTTPS 连接（系统 ATS 限制了明文 HTTP）"
            case NSURLErrorNoPermissionsToReadFile:
                return "源站开启了访问验证（如 Cloudflare），应用内无法读取 Feed"
            case NSURLErrorCannotParseResponse:
                return "无法解析为有效的 RSS/Atom 内容"
            default: break
            }
        }
        // 仍不明确时给出简短原文，避免只显示「网络异常」
        let clipped = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if clipped.isEmpty { return "网络请求失败，请稍后重试" }
        if clipped.count > 80 { return String(clipped.prefix(80)) + "…" }
        return clipped
    }

    private func applyParsedFeed(
        data: Data,
        preParsedArticles: [Article]? = nil,
        feedID: UUID,
        urlStr: String,
        persist: Bool = true
    ) {
        // 刷新过程中禁用隐式动画，避免列表因未读数/排序变化而“自动展开/折叠”
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            applyParsedFeedUnanimated(
                data: data,
                preParsedArticles: preParsedArticles,
                feedID: feedID,
                urlStr: urlStr,
                persist: persist
            )
        }
    }

    private func applyParsedFeedUnanimated(
        data: Data,
        preParsedArticles: [Article]?,
        feedID: UUID,
        urlStr: String,
        persist: Bool
    ) {
        // 并发刷新时 idx 可能过期，始终按 feedID 重定位
        guard let idx = feeds.firstIndex(where: { $0.id == feedID }) else { return }
        let parsed = preParsedArticles ?? FeedParser.parse(data: data, feedID: feedID, feedTitle: feeds[idx].title)
        var existingByLink: [String: Int] = [:]
        for (i, a) in feeds[idx].articles.enumerated() {
            let key = Self.canonicalLink(a.link)
            if !key.isEmpty { existingByLink[key] = i }
        }
        var newArticles: [Article] = []
        for var article in parsed {
            let key = Self.canonicalLink(article.link)
            if key.isEmpty { continue }
            if let ei = existingByLink[key] {
                // 刷新时补全 commentsURL（HN 等）
                if let c = article.commentsURL, !c.isEmpty,
                   feeds[idx].articles[ei].commentsURL == nil {
                    feeds[idx].articles[ei].commentsURL = c
                }
                continue
            }
            if readArticleLinks.contains(key) { article.isRead = true }
            if favoriteArticleLinks.contains(key) { article.isFavorite = true }
            // 仅标记有缓存，不把全文读入列表内存
            if OfflineCache.hasArticleBody(link: article.link) {
                article.hasFullContent = true
                article.content = ""
            } else if !article.content.isEmpty {
                // RSS 自带长 content → 落盘后列表只留元数据
                article = metadataOnly(article)
            }
            newArticles.append(article)
        }
        // 文章黑名单：新条目直接标已读
        for i in newArticles.indices {
            if matchesArticleBlacklist(newArticles[i]) {
                newArticles[i].isRead = true
                let key = Self.canonicalLink(newArticles[i].link)
                if !key.isEmpty { readArticleLinks.insert(key) }
            }
        }
        newArticles = newArticles.map { metadataOnly($0) }
        let newUnread = newArticles.reduce(0) { $0 + ($1.isRead ? 0 : 1) }
        feeds[idx].articles.insert(contentsOf: newArticles, at: 0)
        feeds[idx].unreadCount += newUnread
        for a in newArticles {
            indexArticle(a.id, feedID: feeds[idx].id)
        }
        feeds[idx].lastFetched = Date()
        // 仅解析/更新图标 URL，真正下载由 FeedIcon 负责（勿在此标记 faviconFetchDone）
        if let resolved = FeedParser.resolveFaviconURL(from: data, feedURL: urlStr) {
            var feed = feeds[idx]
            let current = feed.faviconURL ?? ""
            let isFallbackOnly = current.isEmpty
                || current.contains("duckduckgo.com/ip3/")
                || current.contains("google.com/s2/favicons")
            let fromFeed = FeedParser.extractFeedImage(from: data) != nil
            if isFallbackOnly || fromFeed {
                if feed.faviconURL != resolved {
                    feed.faviconURL = resolved
                    // URL 变更时允许重新下载
                    if feed.faviconFetchDone {
                        feed.faviconFetchDone = false
                    }
                    feeds[idx] = feed
                }
            }
        }
        if smartInterestFilterEnabled {
            applyInterestScoring(toFeed: feedID)
        }
        if persist {
            purgeOldReadArticles()
            pruneFullContentCache()
            saveToStorage()
        }
    }

    func cancelRefreshAll() {
        refreshSessionID += 1
        withAnimation(.easeInOut(duration: 0.3)) {
            isRefreshingAll = false
            isLoading = false
            refreshProgressCurrent = 0
            refreshProgressTotal = 0
            refreshProgressTitle = ""
        }
        // 取消时仍落盘当前已拉到的数据
        saveToStorage()
    }

    func cancelListTranslation() {
        chrome.cancelListTranslation()
    }

    @discardableResult
    func beginListTranslationSession() -> Int {
        chrome.beginListTranslationSession()
    }

    func isListTranslationSessionActive(_ session: Int) -> Bool {
        session == listTranslationSessionID
    }

    func refreshAll() async {
        let snapshot = feeds
        guard !snapshot.isEmpty else { return }
        refreshSessionID += 1
        let session = refreshSessionID
        withAnimation(.easeInOut(duration: 0.28)) {
            isRefreshingAll = true
            isLoading = true
            refreshProgressTotal = snapshot.count
            refreshProgressCurrent = 0
            refreshProgressTitle = "准备中…"
        }
        var failures: [String] = []
        let limit = max(1, FeedRefreshService.HTTP.refreshConcurrency)
        var completed = 0
        // 按批次并行，避免同时打满所有源
        var offset = 0
        var cancelled = false
        while offset < snapshot.count {
            if session != refreshSessionID {
                cancelled = true
                break
            }
            let end = min(offset + limit, snapshot.count)
            let batch = Array(snapshot[offset..<end])
            await withTaskGroup(of: (UUID, String, Result<FeedRefreshService.ParsedFeedPayload, Error>).self) { group in
                for feed in batch {
                    let title = feed.title.isEmpty ? "未命名源" : feed.title
                    let id = feed.id
                    let urlStr = feed.url
                    group.addTask {
                        // 非 MainActor：只做网络 + 解析；取消在主线程 for-await 中丢弃结果
                        guard let url = NetworkURLPolicy.validate(urlStr) else {
                            let err = NSError(
                                domain: "Harbor.FeedRefresh",
                                code: 1,
                                userInfo: [NSLocalizedDescriptionKey: "不允许的地址（仅支持公网 http/https）"]
                            )
                            return (id, title, .failure(err))
                        }
                        do {
                            let payload = try await FeedRefreshService.fetchAndParse(
                                url: url,
                                feedID: id,
                                feedTitle: title,
                                cacheKeyURLString: urlStr
                            )
                            return (id, title, .success(payload))
                        } catch {
                            return (id, title, .failure(error))
                        }
                    }
                }
                for await (id, title, outcome) in group {
                    if session != refreshSessionID {
                        cancelled = true
                        group.cancelAll()
                        break
                    }
                    completed += 1
                    refreshProgressCurrent = completed
                    refreshProgressTitle = title
                    switch outcome {
                    case .success(let payload):
                        if payload.notModified {
                            if let i = feeds.firstIndex(where: { $0.id == id }) {
                                feeds[i].lastFetched = Date()
                            }
                            clearFeedRefreshError(id, persist: false)
                        } else {
                            applyParsedFeed(
                                data: payload.data,
                                preParsedArticles: payload.articles,
                                feedID: id,
                                urlStr: feeds.first(where: { $0.id == id })?.url ?? "",
                                persist: false
                            )
                            if payload.upgradedToHTTPS,
                               let i = feeds.firstIndex(where: { $0.id == id }) {
                                feeds[i].url = payload.resolvedURL.absoluteString
                            }
                            clearFeedRefreshError(id, persist: false)
                        }
                    case .failure(let error):
                        let urlStr = feeds.first(where: { $0.id == id })?.url ?? ""
                        if let cached = OfflineCache.loadFeedXML(url: urlStr), !cached.isEmpty {
                            let articles = await FeedRefreshService.parseOffline(
                                data: cached,
                                feedID: id,
                                feedTitle: title
                            )
                            applyParsedFeed(
                                data: cached,
                                preParsedArticles: articles,
                                feedID: id,
                                urlStr: urlStr,
                                persist: false
                            )
                            let detail = Self.friendlyNetworkError(error)
                            let reason = "已用本地缓存（\(detail)）"
                            setFeedRefreshError(id, reason: reason, persist: false)
                            failures.append("「\(title)」：\(reason)")
                        } else {
                            let reason = Self.friendlyNetworkError(error)
                            setFeedRefreshError(id, reason: reason, persist: false)
                            failures.append("「\(title)」：\(reason)")
                        }
                    }
                }
            }
            if cancelled { break }
            offset = end
            // 批次间让出主线程，降低列表卡顿
            await Task.yield()
        }
        // 全部源刷新完后统一落盘，避免每源写一次磁盘
        purgeOldReadArticles()
        pruneFullContentCache()
        saveToStorage()
        if session != refreshSessionID {
            return
        }
        // 收尾：先走到 100%，再淡出，避免进度条突然消失
        withAnimation(.easeInOut(duration: 0.28)) {
            refreshProgressCurrent = cancelled ? completed : snapshot.count
            refreshProgressTitle = cancelled ? "已取消" : "完成"
        }
        try? await Task.sleep(nanoseconds: 320_000_000)
        if session != refreshSessionID { return }
        withAnimation(.easeInOut(duration: 0.35)) {
            isRefreshingAll = false
            isLoading = false
            refreshProgressCurrent = 0
            refreshProgressTotal = 0
            refreshProgressTitle = ""
        }
        if failures.isEmpty {
            errorMessage = nil
        } else if failures.count == 1 {
            errorMessage = failures[0]
        } else {
            // 摘要：源名 + 原因（最多 3 条），其余只计数量
            let preview = failures.prefix(3).joined(separator: "；")
            let extra = failures.count > 3 ? "；…共 \(failures.count) 个源失败" : ""
            errorMessage = preview + extra
        }
    }

    func containsBlacklistedTerm(_ text: String) -> Bool {
        let haystack = text.lowercased()
        for raw in aiBlacklistTerms {
            let term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty else { continue }
            if haystack.contains(term.lowercased()) { return true }
        }
        return false
    }

    func matchesArticleBlacklist(_ article: Article) -> Bool {
        !(articleBlacklistMatchedTerms(article).isEmpty)
    }

    func articleBlacklistMatchedTerms(_ article: Article) -> [String] {
        guard !articleBlacklistTerms.isEmpty else { return [] }
        let haystack = (article.title + "\n" + article.summary).lowercased()
        var hits: [String] = []
        for raw in articleBlacklistTerms {
            let term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty else { continue }
            if haystack.contains(term.lowercased()) { hits.append(term) }
        }
        return hits
    }

    func articleBlacklistReason(for article: Article) -> String? {
        let hits = articleBlacklistMatchedTerms(article)
        guard !hits.isEmpty else { return nil }
        let words = hits.prefix(4).joined(separator: "、")
        return "黑名单：" + words + (article.isRead ? " · 已自动标已读" : "")
    }

    /// 将命中文章黑名单的条目标为已读
    /// 将命中文章黑名单的条目标为已读（不写 readArticleLinks 以外的额外逻辑）
    @discardableResult
    func applyArticleBlacklist(in feedID: UUID? = nil) -> Int {
        var marked = 0
        let indices: [Int]
        if let feedID, let idx = feeds.firstIndex(where: { $0.id == feedID }) {
            indices = [idx]
        } else {
            indices = Array(feeds.indices)
        }
        for i in indices {
            var feed = feeds[i]
            var changed = false
            for j in feed.articles.indices {
                guard !feed.articles[j].isRead else { continue }
                guard matchesArticleBlacklist(feed.articles[j]) else { continue }
                feed.articles[j].isRead = true
                let key = Self.canonicalLink(feed.articles[j].link)
                if !key.isEmpty { readArticleLinks.insert(key) }
                marked += 1
                changed = true
            }
            if changed {
                feed.unreadCount = feed.articles.filter { !$0.isRead }.count
                feeds[i] = feed
            }
        }
        if marked > 0 {
            persistReadLinks()
            saveToStorage()
        }
        return marked
    }

    func resolveAIProvider(preferredID: UUID?, forText text: String) -> AIProvider? {
        let preferred = preferredID.flatMap { id in aiProviders.first(where: { $0.id == id }) } ?? aiProviders.first
        guard let preferred else { return nil }
        guard containsBlacklistedTerm(text),
              let fallbackID = aiBlacklistFallbackProviderID,
              fallbackID != preferred.id,
              let fallback = aiProviders.first(where: { $0.id == fallbackID }) else {
            return preferred
        }
        return fallback
    }

    /// AI 调用顺序：优先 preferred（含黑名单切换），再其余 Provider；跳过无 Key 的
    func orderedAIProviders(preferredID: UUID?, forText text: String) -> [AIProvider] {
        var ordered: [AIProvider] = []
        var seen = Set<UUID>()
        if let first = resolveAIProvider(preferredID: preferredID, forText: text) {
            ordered.append(first)
            seen.insert(first.id)
        }
        for p in aiProviders where !seen.contains(p.id) {
            ordered.append(p)
            seen.insert(p.id)
        }
        return ordered
    }

    /// 判断 AI 返回是否像错误信息（部分网关用 200 + 正文报错）
    static func looksLikeAIErrorResponse(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return true }
        if t.count > 400 { return false }
        let lower = t.lowercased()
        let needles = [
            "error", "invalid api key", "incorrect api key", "authentication",
            "unauthorized", "forbidden", "rate limit", "quota", "overloaded",
            "model not found", "does not exist", "permission denied",
            "请求失败", "无效的", "未配置", "余额不足", "频率限制", "鉴权失败",
            "api key", "access denied", "service unavailable"
        ]
        return needles.contains { lower.contains($0) }
    }


    // MARK: - AI Provider 多 Key

    /// 读取某 Provider 的全部 Key（兼容旧版单 Key）
    func loadAIKeys(for providerID: UUID) -> [String] {
        let multiKey = "ai_keys_\(providerID.uuidString)"
        if let raw = Keychain.load(key: multiKey), !raw.isEmpty,
           let data = raw.data(using: .utf8),
           let arr = try? JSONDecoder().decode([String].self, from: data) {
            return arr.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        // 兼容旧单 Key
        let legacy = Keychain.load(key: "ai_key_\(providerID.uuidString)") ?? ""
        let one = legacy.trimmingCharacters(in: .whitespacesAndNewlines)
        return one.isEmpty ? [] : [one]
    }

    func saveAIKeys(for providerID: UUID, keys: [String]) {
        let cleaned = keys.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let multiKey = "ai_keys_\(providerID.uuidString)"
        let legacyKey = "ai_key_\(providerID.uuidString)"
        if cleaned.isEmpty {
            Keychain.delete(key: multiKey)
            Keychain.delete(key: legacyKey)
            return
        }
        if let data = try? JSONEncoder().encode(cleaned), let raw = String(data: data, encoding: .utf8) {
            Keychain.save(key: multiKey, value: raw)
        }
        // 同步首个 Key 到旧字段，兼容未升级逻辑
        Keychain.save(key: legacyKey, value: cleaned[0])
    }

    
    // MARK: - DeepL 多 Key

    func loadDeepLKeys() -> [String] {
        let multiKey = "deepl_translate_keys"
        if let raw = Keychain.load(key: multiKey), !raw.isEmpty {
            if let data = raw.data(using: .utf8),
               let arr = try? JSONDecoder().decode([String].self, from: data) {
                return arr.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            }
            // 兼容误存成换行拼接
            let parts = raw.components(separatedBy: CharacterSet.newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if parts.count > 1 { return parts }
        }
        let legacy = Keychain.load(key: "deepl_translate_key") ?? ""
        let legacyParts = legacy.components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if legacyParts.count > 1 { return legacyParts }
        let one = legacy.trimmingCharacters(in: .whitespacesAndNewlines)
        return one.isEmpty ? [] : [one]
    }

    func saveDeepLKeys(_ keys: [String]) {
        var seen = Set<String>()
        let cleaned = keys
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
        let multiKey = "deepl_translate_keys"
        let legacyKey = "deepl_translate_key"
        if cleaned.isEmpty {
            Keychain.delete(key: multiKey)
            Keychain.delete(key: legacyKey)
            return
        }
        guard let data = try? JSONEncoder().encode(cleaned),
              let raw = String(data: data, encoding: .utf8) else {
            Keychain.save(key: legacyKey, value: cleaned.joined(separator: "\n"))
            return
        }
        Keychain.save(key: multiKey, value: raw)
        Keychain.save(key: legacyKey, value: cleaned[0])
        // 回读校验：钥匙串同步竞态时再强制写一次
        if loadDeepLKeys() != cleaned {
            Keychain.delete(key: multiKey)
            Keychain.delete(key: legacyKey)
            Keychain.save(key: multiKey, value: raw)
            Keychain.save(key: legacyKey, value: cleaned[0])
        }
    }

    // MARK: - Google / Microsoft 多 Key

    private var googleKeyRoundRobin: Int = 0
    private var microsoftKeyRoundRobin: Int = 0

    func loadGoogleKeys() -> [String] {
        loadMultiKeys(multiKey: "google_translate_keys", legacyKey: "google_translate_key")
    }

    func saveGoogleKeys(_ keys: [String]) {
        saveMultiKeys(keys, multiKey: "google_translate_keys", legacyKey: "google_translate_key")
    }

    func loadMicrosoftKeys() -> [String] {
        loadMultiKeys(multiKey: "microsoft_translate_keys", legacyKey: "microsoft_translate_key")
    }

    func saveMicrosoftKeys(_ keys: [String]) {
        saveMultiKeys(keys, multiKey: "microsoft_translate_keys", legacyKey: "microsoft_translate_key")
    }

    private func loadMultiKeys(multiKey: String, legacyKey: String) -> [String] {
        if let raw = Keychain.load(key: multiKey), !raw.isEmpty,
           let data = raw.data(using: .utf8),
           let arr = try? JSONDecoder().decode([String].self, from: data) {
            return arr.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        let legacy = (Keychain.load(key: legacyKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return legacy.isEmpty ? [] : [legacy]
    }

    private func saveMultiKeys(_ keys: [String], multiKey: String, legacyKey: String) {
        var seen = Set<String>()
        let cleaned = keys
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
        if cleaned.isEmpty {
            Keychain.delete(key: multiKey)
            Keychain.delete(key: legacyKey)
            return
        }
        guard let data = try? JSONEncoder().encode(cleaned),
              let raw = String(data: data, encoding: .utf8) else {
            Keychain.save(key: legacyKey, value: cleaned.joined(separator: "\n"))
            return
        }
        Keychain.save(key: multiKey, value: raw)
        Keychain.save(key: legacyKey, value: cleaned[0])
        if loadMultiKeys(multiKey: multiKey, legacyKey: legacyKey) != cleaned {
            Keychain.delete(key: multiKey)
            Keychain.delete(key: legacyKey)
            Keychain.save(key: multiKey, value: raw)
            Keychain.save(key: legacyKey, value: cleaned[0])
        }
    }

    func translateWithGoogle(_ text: String, targetLang: String) async throws -> String {
        try await GoogleTranslate.translate(text: text, targetLang: targetLang)
    }


    /// Microsoft：多 Key 轮询，自动跳过无效/限流 Key
    func translateWithMicrosoft(_ text: String, targetLang: String) async throws -> String {
        let allKeys = loadMicrosoftKeys()
        guard !allKeys.isEmpty else { throw TranslationError.apiError("未配置 Microsoft API Key") }
        let keys = microsoftKeyCooldown.availableKeys(from: allKeys)
        let region = microsoftTranslateRegion
        let start = microsoftKeyRoundRobin % keys.count
        var lastError: Error = TranslationError.apiError("Microsoft 全部 Key 不可用")
        for offset in 0..<keys.count {
            let idx = (start + offset) % keys.count
            let key = keys[idx]
            do {
                let out = try await MicrosoftTranslate.translate(text: text, apiKey: key, region: region, targetLang: targetLang)
                microsoftKeyRoundRobin = (allKeys.firstIndex(of: key) ?? idx) + 1
                return out
            } catch {
                lastError = error
                microsoftKeyCooldown.mark(key, kind: Self.keyFailureKind(error))
                continue
            }
        }
        throw lastError
    }


    // MARK: - DeepL 多 Key 调度
    // 低并发：固定顺序 + 额度耗尽（456）再切换下一把（粘性）
    // 高并发：Round Robin + 429 短冷却 + 456 自动剔除 + 成功次数统计

    private var deeplKeyRoundRobin: Int = 0
    /// 低并发粘性：当前固定使用的 Key 在全量列表中的下标
    private var deeplStickyIndex: Int = 0
    /// 成功请求计数（指纹 → 次数），便于观察各 Key 用量
    private var deeplKeySuccessCount: [String: Int] = [:]

    /// 并发度 > 1 视为高并发（含用户设为 0 时 DeepL 默认 3）
    private var isDeepLHighConcurrency: Bool {
        resolvedTranslationConcurrency(for: .deepl) > 1
    }

    private func deeplKeyFingerprint(_ key: String) -> String {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if k.count <= 8 { return k }
        return String(k.prefix(6)) + "#" + String(k.suffix(6)) + "#\(k.count)"
    }

    private func recordDeepLSuccess(key: String) {
        let id = deeplKeyFingerprint(key)
        deeplKeySuccessCount[id, default: 0] += 1
    }

    /// 按模式排出本轮尝试顺序（仅含当前可用 Key）
    private func orderedDeepLKeys(available: [String], allKeys: [String]) -> [String] {
        guard !available.isEmpty else { return [] }
        if isDeepLHighConcurrency {
            // Round Robin：从全局游标起转一圈
            let start = deeplKeyRoundRobin % available.count
            return (0..<available.count).map { available[(start + $0) % available.count] }
        }
        // 低并发：粘在 sticky 对应的那把上；若已不可用则按全量顺序找下一把
        if deeplStickyIndex >= allKeys.count { deeplStickyIndex = 0 }
        let sticky = allKeys[deeplStickyIndex]
        if available.contains(sticky) {
            let rest = available.filter { $0 != sticky }
            return [sticky] + rest
        }
        // sticky 已被剔除/冷却：落到全量顺序中下一把仍可用的
        for offset in 0..<allKeys.count {
            let idx = (deeplStickyIndex + offset) % allKeys.count
            let k = allKeys[idx]
            if available.contains(k) {
                deeplStickyIndex = idx
                let rest = available.filter { $0 != k }
                return [k] + rest
            }
        }
        return available
    }

    private func noteDeepLKeyUsed(_ key: String, allKeys: [String], highConcurrency: Bool) {
        if highConcurrency {
            if let i = allKeys.firstIndex(of: key) {
                deeplKeyRoundRobin = i + 1
            } else {
                deeplKeyRoundRobin += 1
            }
        } else if let i = allKeys.firstIndex(of: key) {
            deeplStickyIndex = i
        }
    }

    private func noteDeepLKeyFailed(_ key: String, kind: KeyFailureKind, allKeys: [String]) {
        deeplKeyCooldown.mark(key, kind: kind)
        // 456 / 无效：粘性与 RR 都跳到下一把，避免反复打死 Key
        if kind == .quotaExhausted || kind == .invalid, let i = allKeys.firstIndex(of: key) {
            deeplStickyIndex = (i + 1) % max(allKeys.count, 1)
            deeplKeyRoundRobin = (i + 1) % max(allKeys.count, 1)
        }
    }

    /// DeepL 单条：低并发固定顺序粘性；高并发 RR
    func translateWithDeepL(_ text: String, targetLang: String) async throws -> String {
        let allKeys = loadDeepLKeys()
        guard !allKeys.isEmpty else { throw TranslationError.apiError("未配置 DeepL API Key") }
        let high = isDeepLHighConcurrency
        let available = deeplKeyCooldown.availableKeys(from: allKeys)
        let ordered = orderedDeepLKeys(available: available, allKeys: allKeys)
        var lastError: Error = TranslationError.apiError("DeepL 全部 Key 不可用")
        for key in ordered {
            do {
                let out = try await DeepLTranslate.translate(text: text, apiKey: key, targetLang: targetLang)
                recordDeepLSuccess(key: key)
                noteDeepLKeyUsed(key, allKeys: allKeys, highConcurrency: high)
                return out
            } catch {
                lastError = error
                let kind = Self.keyFailureKind(error)
                noteDeepLKeyFailed(key, kind: kind, allKeys: allKeys)
                continue
            }
        }
        do {
            return try await GoogleTranslate.translate(text: text, targetLang: targetLanguage.googleCode)
        } catch {
            throw lastError
        }
    }

    /// DeepL 批量：高并发时并行分批 + 每批 RR；低并发串行粘性
    func translateTextsWithDeepL(_ texts: [String], targetLang: String) async -> [String?] {
        let allKeys = loadDeepLKeys()
        guard !allKeys.isEmpty else {
            return Array(repeating: nil, count: texts.count)
        }
        let high = isDeepLHighConcurrency
        let parallelism = high
            ? min(resolvedTranslationConcurrency(for: .deepl), max(1, allKeys.count))
            : 1
        return await translateNativeBatchParallel(texts, chunkSize: 30, parallelism: parallelism) { chunk in
            let available = self.deeplKeyCooldown.availableKeys(from: self.loadDeepLKeys())
            guard !available.isEmpty else { throw TranslationError.apiError("DeepL 无可用 Key") }
            let ordered = self.orderedDeepLKeys(available: available, allKeys: allKeys)
            var lastError: Error?
            for key in ordered {
                do {
                    let r = try await DeepLTranslate.translate(texts: chunk, apiKey: key, targetLang: targetLang)
                    self.recordDeepLSuccess(key: key)
                    self.noteDeepLKeyUsed(key, allKeys: allKeys, highConcurrency: high)
                    return r
                } catch {
                    lastError = error
                    let kind = Self.keyFailureKind(error)
                    self.noteDeepLKeyFailed(key, kind: kind, allKeys: allKeys)
                    continue
                }
            }
            throw lastError ?? TranslationError.apiError("DeepL 无可用 Key")
        }
    }

    /// Microsoft 原生批量：一次请求多句，顺序与输入一致
    func translateTextsWithMicrosoft(_ texts: [String], targetLang: String) async -> [String?] {
        let keys = loadMicrosoftKeys()
        guard !keys.isEmpty else {
            return Array(repeating: nil, count: texts.count)
        }
        let region = microsoftTranslateRegion
        // Azure 单次建议 ≤100 段；列表用 40 兼顾延迟
        return await translateNativeBatchParallel(texts, chunkSize: 40, parallelism: min(3, max(1, keys.count))) { chunk in
            let ks = self.microsoftKeyCooldown.availableKeys(from: self.loadMicrosoftKeys())
            guard !ks.isEmpty else { throw TranslationError.apiError("Microsoft 无可用 Key") }
            let i = self.microsoftKeyRoundRobin % ks.count
            let key = ks[i]
            self.microsoftKeyRoundRobin = i + 1
            do {
                return try await MicrosoftTranslate.translate(
                    texts: chunk,
                    apiKey: key,
                    region: region,
                    targetLang: targetLang
                )
            } catch {
                self.microsoftKeyCooldown.mark(key, kind: Self.keyFailureKind(error))
                for k in self.microsoftKeyCooldown.availableKeys(from: self.loadMicrosoftKeys()) where k != key {
                    do {
                        return try await MicrosoftTranslate.translate(
                            texts: chunk,
                            apiKey: k,
                            region: region,
                            targetLang: targetLang
                        )
                    } catch {
                        self.microsoftKeyCooldown.mark(k, kind: Self.keyFailureKind(error))
                        continue
                    }
                }
                throw error
            }
        }
    }

    static func isQuotaOrAuthError(_ error: Error) -> Bool {
        keyFailureKind(error) != .other
    }

    enum KeyFailureKind {
        case invalid          // 401/403：Key 无效，长冷却
        case limited          // 429：限流，短冷却
        case quotaExhausted   // 456 / 额度耗尽：本会话剔除（不自动回池）
        case other
    }

    static func keyFailureKind(_ error: Error) -> KeyFailureKind {
        let msg = error.localizedDescription.lowercased()
        // 先匹配 456 / quota，避免被笼统 "exceed" 误判为 429
        let quotaTokens = [" 456", "456:", "quota exceeded", "quota_exceeded", "character limit",
                           "cost limit", "额度耗尽", "配额用尽", "已用尽"]
        for t in quotaTokens where msg.contains(t) { return .quotaExhausted }
        if msg.contains("456") { return .quotaExhausted }

        let invalidTokens = ["401", "403", "unauthorized", "forbidden", "invalid api", "invalid key",
                             "authentication", "鉴权", "授权", "无效", "not valid", "incorrect api"]
        for t in invalidTokens where msg.contains(t) { return .invalid }

        let limitedTokens = ["429", "rate limit", "too many", "resource exhausted", "限流", "throttle"]
        for t in limitedTokens where msg.contains(t) { return .limited }

        // 无状态码时的模糊配额词
        if msg.contains("quota") || msg.contains("额度") || msg.contains("配额") {
            return .quotaExhausted
        }
        return .other
    }

    /// 多 Key 冷却：429 短冷却；401/403 长冷却；456 本会话剔除（不因「全部不可用」而清空）
    private struct KeyCooldownBook {
        private var until: [String: Date] = [:]
        /// 456 剔除：会话内不再使用（除非用户改 Key 列表触发自然换指纹）
        private var exhausted: Set<String> = []
        private let invalidCooldown: TimeInterval = 3600
        private let limitedCooldown: TimeInterval = 300

        private func fp(_ key: String) -> String {
            let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
            if k.count <= 8 { return k }
            return String(k.prefix(6)) + "#" + String(k.suffix(6)) + "#\(k.count)"
        }

        mutating func isAvailable(_ key: String, now: Date = Date()) -> Bool {
            let id = fp(key)
            if exhausted.contains(id) { return false }
            if let u = until[id], u > now { return false }
            if let u = until[id], u <= now { until.removeValue(forKey: id) }
            return true
        }

        mutating func mark(_ key: String, kind: KeyFailureKind, now: Date = Date()) {
            let id = fp(key)
            switch kind {
            case .invalid:
                until[id] = now.addingTimeInterval(invalidCooldown)
            case .limited:
                until[id] = now.addingTimeInterval(limitedCooldown)
            case .quotaExhausted:
                exhausted.insert(id)
                until.removeValue(forKey: id)
            case .other:
                until[id] = now.addingTimeInterval(20)
            }
        }

        /// 可用 Key；若仅剩冷却中的（非 456 剔除），清空短冷却避免卡死；456 剔除的不会因卡死而恢复
        mutating func availableKeys(from keys: [String]) -> [String] {
            let open = keys.filter { isAvailable($0) }
            if !open.isEmpty { return open }
            // 全部不可用：只清 429/其它短冷却，保留 exhausted
            until.removeAll()
            let after = keys.filter { isAvailable($0) }
            if !after.isEmpty { return after }
            // 若全被 456 剔除，仍返回空，由上层回退其它引擎
            return []
        }
    }

    private var deeplKeyCooldown = KeyCooldownBook()
    private var microsoftKeyCooldown = KeyCooldownBook()
    private var aiKeyCooldown: [UUID: KeyCooldownBook] = [:]

/// 轮询取下一个 Key（负载均衡）；无 Key 返回 nil
    private var aiKeyRoundRobin: [UUID: Int] = [:]

    func nextAIKey(for providerID: UUID) -> String? {
        let keys = loadAIKeys(for: providerID)
        guard !keys.isEmpty else { return nil }
        let start = aiKeyRoundRobin[providerID] ?? 0
        let idx = start % keys.count
        aiKeyRoundRobin[providerID] = idx + 1
        return keys[idx]
    }

    /// 多 Key 轮询：自动跳过冷却中的无效/限流 Key
    func callAIWithProviderKeys(
        provider: AIProvider,
        prompt: String,
        maxTokens: Int,
        modelOverride: String? = nil
    ) async throws -> String {
        let allKeys = loadAIKeys(for: provider.id)
        guard !allKeys.isEmpty else { throw TranslationError.apiError("未配置 API Key") }
        var book = aiKeyCooldown[provider.id] ?? KeyCooldownBook()
        let keys = book.availableKeys(from: allKeys)
        let start = (aiKeyRoundRobin[provider.id] ?? 0) % keys.count
        var lastError: Error = TranslationError.apiError("全部 Key 失败")
        for offset in 0..<keys.count {
            let idx = (start + offset) % keys.count
            let key = keys[idx]
            do {
                let raw = try await callAI(
                    prompt: prompt,
                    provider: provider,
                    apiKey: key,
                    maxTokens: maxTokens,
                    modelOverride: modelOverride
                )
                let text = AIResponseSanitizer.stripThinking(raw)
                if text.isEmpty || Self.looksLikeAIErrorResponse(text) {
                    // 内容像错误：标记短暂冷却并换 Key
                    book.mark(key, kind: .other)
                    aiKeyCooldown[provider.id] = book
                    lastError = TranslationError.apiError(text.isEmpty ? "空响应" : text)
                    continue
                }
                aiKeyRoundRobin[provider.id] = (allKeys.firstIndex(of: key) ?? idx) + 1
                aiKeyCooldown[provider.id] = book
                return text
            } catch {
                lastError = error
                let kind = Self.keyFailureKind(error)
                book.mark(key, kind: kind)
                aiKeyCooldown[provider.id] = book
                continue
            }
        }
        aiKeyCooldown[provider.id] = book
        throw lastError
    }

    /// 模型路由：短文本 + 已配置 economyModel 时用便宜模型；解释等强制强模型
    func resolvedModel(for provider: AIProvider, probeText: String, preferStrong: Bool) -> String? {
        guard modelRoutingEnabled, !preferStrong else { return nil }
        let eco = provider.economyModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !eco.isEmpty, eco != provider.model else { return nil }
        let len = HTMLUtils.stripTags(probeText).count
        if len <= max(100, modelRoutingShortLimit) { return eco }
        return nil
    }

    /// 依次尝试可用 AI Provider，全部失败再抛错
    func callAIWithFailover(
        preferredID: UUID?,
        probeText: String,
        maxTokens: Int = 500,
        preferStrongModel: Bool = false,
        buildPrompt: () -> String
    ) async throws -> (text: String, provider: AIProvider) {
        let providers = orderedAIProviders(preferredID: preferredID, forText: probeText)
        guard !providers.isEmpty else { throw TranslationError.noProvider }
        let prompt = buildPrompt()
        var lastError: Error = TranslationError.noProvider
        var triedAnyKey = false
        for provider in providers {
            let keys = loadAIKeys(for: provider.id)
            guard !keys.isEmpty else { continue }
            triedAnyKey = true
            do {
                let model = resolvedModel(for: provider, probeText: probeText, preferStrong: preferStrongModel)
                let text = try await callAIWithProviderKeys(
                    provider: provider,
                    prompt: prompt,
                    maxTokens: maxTokens,
                    modelOverride: model
                )
                return (text, provider)
            } catch {
                lastError = error
                continue
            }
        }
        if !triedAnyKey { throw TranslationError.apiError("未配置任何可用的 API Key") }
        throw lastError
    }

    /// 实际用于翻译的引擎顺序（去重、过滤冷却中的引擎；空则回退全部）
    func effectiveTranslationChain() -> [TranslationEngine] {
        translationCoordinator.effectiveChain(configured: translationEngineChain)
    }

    /// 将某引擎移到链中指定位置 / 增删后同步 defaultTranslationEngine
    func setTranslationEngineChain(_ chain: [TranslationEngine]) {
        translationEngineChain = TranslationCoordinator.normalizedChain(chain)
        defaultTranslationEngine = translationEngineChain[0]
        persistSettings()
    }

    func moveTranslationEngine(from source: IndexSet, to destination: Int) {
        var chain = translationEngineChain
        chain.move(fromOffsets: source, toOffset: destination)
        setTranslationEngineChain(chain)
    }

    func toggleTranslationEngineInChain(_ engine: TranslationEngine) {
        var chain = translationEngineChain
        if let idx = chain.firstIndex(of: engine) {
            guard chain.count > 1 else { return } // 至少保留一个
            chain.remove(at: idx)
        } else {
            chain.append(engine)
        }
        setTranslationEngineChain(chain)
    }

    private func isTranslationEngineCooling(_ engine: TranslationEngine) -> Bool {
        translationCoordinator.isCooling(engine)
    }

    private func markTranslationEngineLimited(_ engine: TranslationEngine, minutes: Double = 5) {
        translationCoordinator.markLimited(engine, minutes: minutes)
    }

    /// 引擎是否已配置到可调用（缺 Key 的引擎跳过）
    func isTranslationEngineReady(_ engine: TranslationEngine) -> Bool {
        switch engine {
        case .google, .mymemory, .lingva, .yandex, .azure: return true
        case .microsoft: return !loadMicrosoftKeys().isEmpty
        case .deepl: return !loadDeepLKeys().isEmpty
        case .ai:
            return aiProviders.contains { !loadAIKeys(for: $0.id).isEmpty }
        }
    }

    private func translateWithEngine(_ engine: TranslationEngine, text: String) async throws -> String {
        let lang = targetLanguage
        switch engine {
        case .google:
            return try await translateWithGoogle(text, targetLang: lang.googleCode)
        case .mymemory:
            return try await MyMemoryTranslate.translate(text: text, targetLang: lang.mymemoryCode)
        case .lingva:
            return try await LingvaTranslate.translate(
                text: text,
                targetLang: lang.googleCode,
                customBase: lingvaCustomBase.isEmpty ? nil : lingvaCustomBase
            )
        case .yandex:
            return try await YandexTranslate.translate(text: text, targetLang: lang.googleCode)
        case .azure:
            return try await AzureBingTranslate.translate(text: text, targetLang: lang.microsoftCode)
        case .microsoft:
            return try await translateWithMicrosoft(text, targetLang: lang.microsoftCode)
        case .deepl:
            return try await translateWithDeepL(text, targetLang: lang.deeplCode)
        case .ai:
            let preferred = defaultTranslationProviderID ?? defaultSummaryProviderID
            let template = translationPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? AppStore.defaultTranslationPrompt : translationPrompt
            var prompt = template
                .replacingOccurrences(of: "{{lang}}", with: lang.promptLabel)
                .replacingOccurrences(of: "{{text}}", with: text)
            if !template.contains("{{text}}") { prompt += "\n\n" + text }
            let (result, _) = try await callAIWithFailover(
                preferredID: preferred,
                probeText: text,
                maxTokens: 2048,
                buildPrompt: { prompt }
            )
            return result
        }
    }

    /// 最近一次成功翻译使用的引擎（供阅读页展示）
    private(set) var lastUsedTranslationEngine: TranslationEngine?

    /// - Parameter excluding: 跳过的引擎（例如重译时排除某些引擎）
    func translateText(_ text: String, excluding: Set<TranslationEngine> = []) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // 简繁转换：正文已是另一侧中文时本地映射，不走翻译 API（与设置说明一致）
        if ChineseScript.needsConversion(text: trimmed, to: targetLanguage) {
            let converted = ChineseScript.convert(trimmed, to: targetLanguage)
            if converted != trimmed {
                lastUsedTranslationEngine = nil
                TranslationCache.set(
                    converted,
                    text: trimmed,
                    targetLang: targetLanguage,
                    provider: "zh-script"
                )
                return converted
            }
        }

        // 缓存命中（参考 Readest：原文 + 目标语 + 引擎）
        let cacheProviders = effectiveTranslationChain().filter { !excluding.contains($0) }
        for engine in cacheProviders {
            if let cached = TranslationCache.get(
                text: trimmed,
                targetLang: targetLanguage,
                provider: engine.rawValue
            ), !cached.isEmpty {
                lastUsedTranslationEngine = engine
                return cached
            }
        }

        let chain = effectiveTranslationChain().filter { !excluding.contains($0) }
        var lastError: Error = TranslationError.apiError("没有可用的翻译引擎")
        for engine in chain {
            guard isTranslationEngineReady(engine) else { continue }
            do {
                let raw = try await translateWithEngine(engine, text: trimmed)
                var result = TranslationPolish.polish(raw, targetLang: targetLanguage)
                // API 结果若仍是另一侧中文，再做一次本地简繁对齐
                if ChineseScript.needsConversion(text: result, to: targetLanguage) {
                    result = ChineseScript.convert(result, to: targetLanguage)
                }
                lastUsedTranslationEngine = engine
                TranslationCache.set(
                    result,
                    text: trimmed,
                    targetLang: targetLanguage,
                    provider: engine.rawValue
                )
                return result
            } catch {
                lastError = error
                if Self.keyFailureKind(error) == .limited {
                    markTranslationEngineLimited(engine)
                    continue
                }
                // 配置/鉴权类错误：跳过该引擎；其它错误也尝试下一个以提高成功率
                continue
            }
        }
        throw lastError
    }

    /// 解析实际并发度：显式参数 > 用户设置 > 引擎默认（偏稳，避免限流导致大片失败）
    func resolvedTranslationConcurrency(for engine: TranslationEngine, override: Int? = nil) -> Int {
        translationCoordinator.resolvedConcurrency(
            for: engine,
            userSetting: translationConcurrency,
            override: override
        )
    }

    /// 列表/批量翻译入口：按首选引擎选最优路径
    /// - DeepL / Microsoft：原生「一次请求多句」（非拼串），吞吐高且按条独立译
    /// - Google：kiss Google2 translateHtml（去重 + 按字符切批 + 并发池 + 按 index 回填）
    /// - AI：多 Provider 分片并发
    /// - Lingva / MyMemory：单条请求 + 受控并发
    /// 批量缺口用引擎链单条补齐，避免整批失败
    /// 简繁转换：已是另一侧中文的条目本地映射，不占用 API 名额
    func translateTexts(_ texts: [String], concurrency: Int? = nil) async -> [String?] {
        guard !texts.isEmpty else { return [] }
        let lang = targetLanguage

        // 先本地简繁转换，再对剩余条目走 API
        var results: [String?] = Array(repeating: nil, count: texts.count)
        var needAPI: [(Int, String)] = []
        needAPI.reserveCapacity(texts.count)
        for (i, text) in texts.enumerated() {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                results[i] = ""
                continue
            }
            if ChineseScript.needsConversion(text: trimmed, to: lang) {
                let converted = ChineseScript.convert(trimmed, to: lang)
                if converted != trimmed {
                    results[i] = converted
                    TranslationCache.set(converted, text: trimmed, targetLang: lang, provider: "zh-script")
                    continue
                }
            }
            needAPI.append((i, text))
        }
        if needAPI.isEmpty { return results }

        let apiTexts = needAPI.map(\.1)
        let chain = effectiveTranslationChain()
        let primary = chain.first(where: { isTranslationEngineReady($0) && !isTranslationEngineCooling($0) })
            ?? chain.first(where: { isTranslationEngineReady($0) })
            ?? defaultTranslationEngine
        let limit = resolvedTranslationConcurrency(for: primary, override: concurrency)

        var apiResults: [String?]
        var usedPrimary = false

        switch primary {
        case .deepl:
            apiResults = await translateTextsWithDeepL(apiTexts, targetLang: targetLanguage.deeplCode)
            usedPrimary = apiResults.contains(where: { $0?.isEmpty == false })
            if usedPrimary { lastUsedTranslationEngine = .deepl }
        case .microsoft:
            apiResults = await translateTextsWithMicrosoft(apiTexts, targetLang: targetLanguage.microsoftCode)
            usedPrimary = apiResults.contains(where: { $0?.isEmpty == false })
            if usedPrimary { lastUsedTranslationEngine = .microsoft }
        case .ai:
            apiResults = await translateTextsWithAIProviders(apiTexts, perProviderConcurrency: max(1, limit))
            usedPrimary = apiResults.contains(where: { $0?.isEmpty == false })
            if usedPrimary { lastUsedTranslationEngine = .ai }
        case .google:
            // kiss 流程：缓存命中跳过 → Google2 批量 → 缺口单条补齐
            var batchOut: [String?] = Array(repeating: nil, count: apiTexts.count)
            var needFetch: [(Int, String)] = []
            for (j, t) in apiTexts.enumerated() {
                if let cached = TranslationCache.get(
                    text: t, targetLang: lang, provider: TranslationEngine.google.rawValue
                ), !cached.isEmpty {
                    batchOut[j] = cached
                } else {
                    needFetch.append((j, t))
                }
            }
            if !needFetch.isEmpty {
                let fetched = await GoogleTranslate.translate(
                    texts: needFetch.map(\.1),
                    targetLang: targetLanguage.googleCode
                )
                for (k, (j, _)) in needFetch.enumerated() where k < fetched.count {
                    batchOut[j] = fetched[k]
                }
            }
            apiResults = batchOut
            usedPrimary = apiResults.contains(where: { $0?.isEmpty == false })
            if usedPrimary { lastUsedTranslationEngine = .google }
        case .azure:
            // Bing Edge 免 Key 批量（与 Google2 同骨架）
            var batchOut: [String?] = Array(repeating: nil, count: apiTexts.count)
            var needFetch: [(Int, String)] = []
            for (j, t) in apiTexts.enumerated() {
                if let cached = TranslationCache.get(
                    text: t, targetLang: lang, provider: TranslationEngine.azure.rawValue
                ), !cached.isEmpty {
                    batchOut[j] = cached
                } else {
                    needFetch.append((j, t))
                }
            }
            if !needFetch.isEmpty {
                let fetched = await AzureBingTranslate.translate(
                    texts: needFetch.map(\.1),
                    targetLang: targetLanguage.microsoftCode
                )
                for (k, (j, _)) in needFetch.enumerated() where k < fetched.count {
                    batchOut[j] = fetched[k]
                }
            }
            apiResults = batchOut
            usedPrimary = apiResults.contains(where: { $0?.isEmpty == false })
            if usedPrimary { lastUsedTranslationEngine = .azure }
        case .mymemory, .lingva, .yandex:
            // 无稳定多句批量 API：并发单条（每条仍走完整引擎链，含简繁）
            let concurrent = await translateConcurrently(apiTexts, concurrency: limit)
            for (j, (origIdx, _)) in needAPI.enumerated() {
                if j < concurrent.count { results[origIdx] = concurrent[j] }
            }
            return results
        }

        // 首选批量有缺口时，用引擎链单条补（排除已失败的首选，避免重复撞限流）
        if apiResults.contains(where: { $0 == nil || $0?.isEmpty == true }) {
            let exclude: Set<TranslationEngine> = usedPrimary ? [primary] : []
            apiResults = await fillMissingTranslations(apiResults, texts: apiTexts, excluding: exclude, concurrency: limit)
        }
        // 批量结果润色 + 简繁对齐 + 写入缓存
        let providerKey = primary.rawValue
        for j in apiResults.indices {
            guard let raw = apiResults[j], !raw.isEmpty else { continue }
            var polished = TranslationPolish.polish(raw, targetLang: lang)
            if ChineseScript.needsConversion(text: polished, to: lang) {
                polished = ChineseScript.convert(polished, to: lang)
            }
            apiResults[j] = polished
            if j < apiTexts.count {
                TranslationCache.set(polished, text: apiTexts[j], targetLang: lang, provider: providerKey)
            }
        }
        for (j, (origIdx, _)) in needAPI.enumerated() {
            if j < apiResults.count { results[origIdx] = apiResults[j] }
        }
        return results
    }

    /// 仅补全失败项，避免对已成功条目重复请求
    private func fillMissingTranslations(
        _ results: [String?],
        texts: [String],
        excluding: Set<TranslationEngine>,
        concurrency: Int
    ) async -> [String?] {
        var out = results
        var missing: [(Int, String)] = []
        missing.reserveCapacity(texts.count)
        for (i, r) in results.enumerated() where i < texts.count {
            if r == nil || r?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                missing.append((i, texts[i]))
            }
        }
        guard !missing.isEmpty else { return out }

        await withTaskGroup(of: (Int, String?).self) { group in
            var next = 0
            let spawn = min(max(concurrency, 1), missing.count)
            func submit(_ job: (Int, String)) {
                let (idx, text) = job
                group.addTask {
                    let r = try? await self.translateText(text, excluding: excluding)
                    let trimmed = r?.trimmingCharacters(in: .whitespacesAndNewlines)
                    return (idx, (trimmed?.isEmpty == false) ? trimmed : nil)
                }
            }
            while next < spawn {
                submit(missing[next]); next += 1
            }
            for await (idx, val) in group {
                if let val { out[idx] = val }
                if next < missing.count {
                    submit(missing[next]); next += 1
                }
            }
        }
        return out
    }

    /// AI 多 Provider：轮询分片，每 Provider 独立并发，总吞吐 ≈ Provider数 × 每路并发
    private func translateTextsWithAIProviders(_ texts: [String], perProviderConcurrency: Int) async -> [String?] {
        let preferred = defaultTranslationProviderID ?? defaultSummaryProviderID
        let providers = orderedAIProviders(preferredID: preferred, forText: texts.first ?? "").filter { p in
            !loadAIKeys(for: p.id).isEmpty
        }
        guard !providers.isEmpty else {
            return await translateConcurrently(texts, concurrency: perProviderConcurrency)
        }
        if providers.count == 1 {
            return await translateConcurrently(texts, concurrency: perProviderConcurrency)
        }
        // 分片：index % n → provider
        var buckets: [[(Int, String)]] = Array(repeating: [], count: providers.count)
        for (i, text) in texts.enumerated() {
            buckets[i % providers.count].append((i, text))
        }
        var results = Array<String?>(repeating: nil, count: texts.count)
        await withTaskGroup(of: [(Int, String?)].self) { group in
            for (pIdx, provider) in providers.enumerated() {
                let jobs = buckets[pIdx]
                guard !jobs.isEmpty else { continue }
                group.addTask {
                    await self.translateBucket(jobs, provider: provider, concurrency: perProviderConcurrency)
                }
            }
            for await part in group {
                for (idx, val) in part { results[idx] = val }
            }
        }
        return results
    }

    private func translateBucket(_ jobs: [(Int, String)], provider: AIProvider, concurrency: Int) async -> [(Int, String?)] {
        var out: [(Int, String?)] = []
        out.reserveCapacity(jobs.count)
        await withTaskGroup(of: (Int, String?).self) { group in
            var next = 0
            let spawn = min(max(concurrency, 1), jobs.count)
            while next < spawn {
                let (idx, text) = jobs[next]
                next += 1
                group.addTask {
                    let r = try? await self.translateTextWithProvider(text, provider: provider)
                    let trimmed = r?.trimmingCharacters(in: .whitespacesAndNewlines)
                    return (idx, (trimmed?.isEmpty == false) ? trimmed : nil)
                }
            }
            for await item in group {
                out.append(item)
                if next < jobs.count {
                    let (idx, text) = jobs[next]
                    next += 1
                    group.addTask {
                        let r = try? await self.translateTextWithProvider(text, provider: provider)
                        let trimmed = r?.trimmingCharacters(in: .whitespacesAndNewlines)
                        return (idx, (trimmed?.isEmpty == false) ? trimmed : nil)
                    }
                }
            }
        }
        return out
    }

    /// 指定 Provider 翻译（不做 failover，供多路分片使用）
    private func translateTextWithProvider(_ text: String, provider: AIProvider) async throws -> String {
        let lang = targetLanguage
        let template = translationPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? AppStore.defaultTranslationPrompt : translationPrompt
        var prompt = template
            .replacingOccurrences(of: "{{lang}}", with: lang.promptLabel)
            .replacingOccurrences(of: "{{text}}", with: text)
        if !template.contains("{{text}}") { prompt += "\n\n" + text }
        return try await callAIWithProviderKeys(provider: provider, prompt: prompt, maxTokens: 2048)
    }

    /// 多批并行（用于 Microsoft / DeepL 批量 API）
    private func translateNativeBatchParallel(
        _ texts: [String],
        chunkSize: Int,
        parallelism: Int,
        call: @escaping ([String]) async throws -> [String]
    ) async -> [String?] {
        let chunks: [[String]] = texts.chunked(into: max(1, chunkSize))
        var results = Array<String?>(repeating: nil, count: texts.count)
        await withTaskGroup(of: (Int, [String?]).self) { group in
            var next = 0
            let spawn = min(max(parallelism, 1), chunks.count)
            func submit(_ chunkIndex: Int) {
                let chunk = chunks[chunkIndex]
                group.addTask {
                    let translated = try? await call(chunk)
                    let mapped: [String?] = (translated ?? []).map { $0.isEmpty ? nil : $0 }
                    // pad
                    var row = mapped
                    while row.count < chunk.count { row.append(nil) }
                    return (chunkIndex, Array(row.prefix(chunk.count)))
                }
            }
            while next < spawn {
                submit(next); next += 1
            }
            for await (chunkIndex, row) in group {
                let base = chunkIndex * max(1, chunkSize)
                // recompute base from chunk sizes - safer by scanning
                var offset = 0
                for i in 0..<chunkIndex { offset += chunks[i].count }
                for (j, val) in row.enumerated() where offset + j < results.count {
                    results[offset + j] = val
                }
                if next < chunks.count {
                    submit(next); next += 1
                }
            }
        }
        return results
    }

    private func translateNativeBatch(_ texts: [String], chunkSize: Int, call: ([String]) async throws -> [String]) async -> [String?] {
        var out = Array<String?>(repeating: nil, count: texts.count)
        var offset = 0
        for chunk in texts.chunked(into: chunkSize) {
            do {
                let translated = try await call(chunk)
                for (i, t) in translated.enumerated() where offset + i < out.count {
                    let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
                    out[offset + i] = trimmed.isEmpty ? nil : trimmed
                }
            } catch {
                for (i, text) in chunk.enumerated() {
                    if let r = try? await translateText(text) {
                        let trimmed = r.trimmingCharacters(in: .whitespacesAndNewlines)
                        out[offset + i] = trimmed.isEmpty ? nil : trimmed
                    }
                }
            }
            offset += chunk.count
        }
        return out
    }

    private func translateConcurrently(_ texts: [String], concurrency: Int) async -> [String?] {
        var results = Array<String?>(repeating: nil, count: texts.count)
        await withTaskGroup(of: (Int, String?).self) { group in
            var next = 0
            let spawn = min(max(concurrency, 1), texts.count)
            while next < spawn {
                let i = next; let text = texts[i]
                group.addTask {
                    let r = try? await self.translateText(text)
                    let trimmed = r?.trimmingCharacters(in: .whitespacesAndNewlines)
                    return (i, (trimmed?.isEmpty == false) ? trimmed : nil)
                }
                next += 1
            }
            for await (index, result) in group {
                results[index] = result
                if next < texts.count {
                    let i = next; let text = texts[i]; next += 1
                    group.addTask {
                        let r = try? await self.translateText(text)
                        let trimmed = r?.trimmingCharacters(in: .whitespacesAndNewlines)
                        return (i, (trimmed?.isEmpty == false) ? trimmed : nil)
                    }
                }
            }
        }
        return results
    }

    func translateLongText(
        _ text: String,
        maxChunkChars: Int = 1800,
        excluding: Set<TranslationEngine> = []
    ) async throws -> String {
        let chunks = Self.splitTextIntoChunks(text, maxChars: maxChunkChars)
        guard !chunks.isEmpty else { return "" }
        if chunks.count == 1 { return try await translateText(chunks[0], excluding: excluding) }
        let primary = effectiveTranslationChain().first(where: { !excluding.contains($0) }) ?? defaultTranslationEngine
        let chunkLimit = min(2, max(1, resolvedTranslationConcurrency(for: primary)))
        return try await withThrowingTaskGroup(of: (Int, String).self) { group in
            var next = 0
            let spawn = min(chunkLimit, chunks.count)
            while next < spawn {
                let index = next
                let chunk = chunks[index]
                next += 1
                group.addTask { (index, try await self.translateText(chunk, excluding: excluding)) }
            }
            var ordered = Array(repeating: "", count: chunks.count)
            for try await (index, result) in group {
                ordered[index] = result
                if next < chunks.count {
                    let i = next
                    let chunk = chunks[i]
                    next += 1
                    group.addTask { (i, try await self.translateText(chunk, excluding: excluding)) }
                }
            }
            return ordered.joined(separator: "\n\n")
        }
    }

    /// 机器初译（排除 AI）→ 按块 AI 审校润色。用于「更高质量重新翻译」
    func translateLongTextWithAIRefinement(
        _ text: String,
        maxChunkChars: Int = 1600
    ) async throws -> String {
        guard !aiProviders.isEmpty else {
            throw TranslationError.apiError("更高质量重译需要配置 AI 服务商")
        }
        let chunks = Self.splitTextIntoChunks(text, maxChars: maxChunkChars)
        guard !chunks.isEmpty else { return "" }
        // 初译不用 AI，避免「AI 译完再 AI 审」叠床架屋；审校专用 AI
        let draftExclude: Set<TranslationEngine> = [.ai]
        var refined: [String] = []
        refined.reserveCapacity(chunks.count)
        for chunk in chunks {
            let draft = try await translateText(chunk, excluding: draftExclude)
            let polished = try await refineTranslation(source: chunk, initial: draft)
            refined.append(polished)
        }
        lastUsedTranslationEngine = .ai
        return refined.joined(separator: "\n\n")
    }

    /// 对照原文审校初译；Prompt 可在设置中编辑
    func refineTranslation(source: String, initial: String) async throws -> String {
        let src = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = initial.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !src.isEmpty else { return draft }
        if draft.isEmpty {
            return try await translateText(src, excluding: [])
        }
        let lang = targetLanguage
        let template = translationRefinementPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? AppStore.defaultTranslationRefinementPrompt
            : translationRefinementPrompt
        var prompt = template
            .replacingOccurrences(of: "{{lang}}", with: lang.promptLabel)
            .replacingOccurrences(of: "{{source}}", with: src)
            .replacingOccurrences(of: "{{SOURCE_TEXT}}", with: src)
            .replacingOccurrences(of: "{{translation}}", with: draft)
            .replacingOccurrences(of: "{{INITIAL_TRANSLATION}}", with: draft)
            .replacingOccurrences(of: "{{GLOSSARY}}", with: "")
        if !template.contains("{{source}}") && !template.contains("{{SOURCE_TEXT}}") {
            prompt += "\n\n【原文】\n" + src
        }
        if !template.contains("{{translation}}") && !template.contains("{{INITIAL_TRANSLATION}}") {
            prompt += "\n\n【初译】\n" + draft
        }
        let preferred = defaultTranslationProviderID ?? defaultSummaryProviderID
        let (result, _) = try await callAIWithFailover(
            preferredID: preferred,
            probeText: src,
            maxTokens: 4096,
            buildPrompt: { prompt }
        )
        let cleaned = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? draft : cleaned
    }

    static func splitTextIntoChunks(_ text: String, maxChars: Int) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if trimmed.count <= maxChars { return [trimmed] }
        var chunks: [String] = []
        var current = ""
        for para in trimmed.components(separatedBy: CharacterSet.newlines) {
            let p = para.trimmingCharacters(in: .whitespaces)
            if p.isEmpty { continue }
            if current.isEmpty {
                if p.count > maxChars { chunks.append(contentsOf: splitBySentence(p, maxChars: maxChars)) }
                else { current = p }
            } else if current.count + p.count + 1 <= maxChars {
                current += "\n" + p
            } else {
                chunks.append(current)
                if p.count > maxChars {
                    chunks.append(contentsOf: splitBySentence(p, maxChars: maxChars))
                    current = ""
                } else { current = p }
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    private static func splitBySentence(_ text: String, maxChars: Int) -> [String] {
        var result: [String] = []
        var current = ""
        let separators = CharacterSet(charactersIn: ".!?。！？\n")
        var buffer = ""
        for ch in text {
            buffer.append(ch)
            if String(ch).rangeOfCharacter(from: separators) != nil {
                if current.count + buffer.count <= maxChars { current += buffer }
                else {
                    if !current.isEmpty { result.append(current) }
                    current = buffer
                }
                buffer = ""
            }
        }
        if !buffer.isEmpty {
            if current.count + buffer.count <= maxChars { current += buffer }
            else {
                if !current.isEmpty { result.append(current) }
                current = buffer
            }
        }
        if !current.isEmpty { result.append(current) }
        var final: [String] = []
        for piece in result {
            if piece.count <= maxChars { final.append(piece) }
            else {
                var start = piece.startIndex
                while start < piece.endIndex {
                    let end = piece.index(start, offsetBy: maxChars, limitedBy: piece.endIndex) ?? piece.endIndex
                    final.append(String(piece[start..<end]))
                    start = end
                }
            }
        }
        return final
    }

    /// 合并内置默认与已存预设（保证内置始终存在）
    func ensureSummaryPromptPresets() {
        var byID = Dictionary(uniqueKeysWithValues: summaryPromptPresets.map { ($0.id, $0) })
        for built in SummaryPromptPreset.builtInDefaults {
            if byID[built.id] == nil {
                byID[built.id] = built
            } else if var existing = byID[built.id] {
                existing.isBuiltIn = true
                if existing.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    existing.name = built.name
                }
                byID[built.id] = existing
            }
        }
        // 内置在前，自定义在后
        let builtIDs = SummaryPromptPreset.builtInDefaults.map(\.id)
        var ordered: [SummaryPromptPreset] = []
        for id in builtIDs {
            if let p = byID[id] { ordered.append(p) }
        }
        for p in summaryPromptPresets where !builtIDs.contains(p.id) {
            ordered.append(p)
        }
        summaryPromptPresets = ordered
        if !summaryPromptPresets.contains(where: { $0.id == globalSummaryPresetID }) {
            globalSummaryPresetID = SummaryPromptPreset.standardID
        }
    }

    func preset(forID id: String) -> SummaryPromptPreset? {
        if id == SummaryPromptPreset.globalID { return nil }
        return summaryPromptPresets.first(where: { $0.id == id })
    }

    func displayName(forPresetID id: String) -> String {
        if id == SummaryPromptPreset.globalID { return SummaryPromptPreset.globalName }
        return preset(forID: id)?.name ?? id
    }

    /// 解析源级 / 全局摘要 Prompt
    func resolvedSummaryPrompt(for article: Article) -> String {
        ensureSummaryPromptPresets()
        var presetID = feeds.first(where: { $0.id == article.feedID })?.summaryPromptPresetID
            ?? SummaryPromptPreset.globalID
        if presetID.isEmpty || presetID == SummaryPromptPreset.globalID {
            presetID = globalSummaryPresetID
        }
        if let preset = preset(forID: presetID) {
            let t = preset.template.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }
        // 标准预设且用户改过全局 summaryPrompt 时回退
        let custom = summaryPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty { return custom }
        return SummaryPromptPreset.builtInDefaults.first(where: { $0.id == SummaryPromptPreset.standardID })?.template
            ?? AppStore.defaultSummaryPrompt
    }

    func upsertSummaryPreset(_ preset: SummaryPromptPreset) {
        ensureSummaryPromptPresets()
        if let idx = summaryPromptPresets.firstIndex(where: { $0.id == preset.id }) {
            summaryPromptPresets[idx] = preset
        } else {
            summaryPromptPresets.append(preset)
        }
        persistSettings()
    }

    func deleteSummaryPreset(id: String) {
        ensureSummaryPromptPresets()
        guard let p = summaryPromptPresets.first(where: { $0.id == id }), !p.isBuiltIn else { return }
        summaryPromptPresets.removeAll { $0.id == id }
        if globalSummaryPresetID == id {
            globalSummaryPresetID = SummaryPromptPreset.standardID
        }
        for i in feeds.indices where feeds[i].summaryPromptPresetID == id {
            feeds[i].summaryPromptPresetID = SummaryPromptPreset.globalID
        }
        persistSettings()
        saveToStorage()
    }

    func resetSummaryPresetToDefault(id: String) {
        guard let built = SummaryPromptPreset.builtInDefaults.first(where: { $0.id == id }) else { return }
        upsertSummaryPreset(built)
    }

    func generateSummary(for article: Article) async throws -> (text: String, providerName: String) {
        try await AIService.generateSummary(article: article, runtime: self)
    }

    static func migrateLegacyDefaultPrompts(translation: inout String, summary: inout String, explain: inout String) {
        func normalize(_ s: String) -> String {
            s.replacingOccurrences(of: "\r\n", with: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let legacyTranslation = "请将以下内容翻译成{{lang}}，只输出译文，不要解释：\n\n{{text}}"
        let legacySummary = "请用3-5句话概括以下文章的核心内容，用{{lang}}回答。每句话单独一行，不要使用1. 2. 3.等序号，不要加标题：\n\n标题：{{title}}\n\n内容：{{content}}"
        let legacyExplain = "请用简洁的{{lang}}解释下面这段文字（词义、专有名词、语境或背景）。只输出解释，不要标题，不要复述整段原文：\n\n{{text}}"
        if normalize(translation) == normalize(legacyTranslation) || translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            translation = defaultTranslationPrompt
        }
        if normalize(summary) == normalize(legacySummary) || summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            summary = defaultSummaryPrompt
        }
        if normalize(explain) == normalize(legacyExplain) || explain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            explain = defaultExplainPrompt
        }
    }

    static func cleanSummaryText(_ text: String) -> String {
        AIService.cleanSummaryText(text)
    }

    func explainText(_ text: String) async throws -> String {
        try await AIService.explainText(text, promptTemplate: explainPrompt, runtime: self)
    }

    // MARK: - 兴趣画像 / 评分 / 不感兴趣

    /// 从标题+摘要提取简易词元（中文双字 + 英文词）
    static func interestTokens(from text: String) -> [String] {
        let plain = HTMLUtils.stripTags(text).lowercased()
        var tokens: [String] = []
        var seen = Set<String>()
        let letters = plain.unicodeScalars.map { Character($0) }
        // 英文词
        let eng = plain.replacingOccurrences(of: #"[^a-z0-9\s]"#, with: " ", options: .regularExpression)
        for w in eng.split(whereSeparator: { $0.isWhitespace }) {
            let s = String(w)
            guard s.count >= 3, seen.insert(s).inserted else { continue }
            tokens.append(s)
        }
        // 中文双字
        let chars = Array(plain).filter { ch in
            ch.unicodeScalars.allSatisfy { s in
                (s.value >= 0x4E00 && s.value <= 0x9FFF)
            }
        }
        if chars.count >= 2 {
            for i in 0..<(chars.count - 1) {
                let bi = String(chars[i]) + String(chars[i + 1])
                if seen.insert(bi).inserted { tokens.append(bi) }
            }
        }
        _ = letters
        return Array(tokens.prefix(40))
    }

    /// 全库搜索：默认仅标题+摘要（`includeFullText` 为 true 时才扫正文）
    func searchArticles(query: String, limit: Int = 50, includeFullText: Bool = false) -> [Article] {
        ArticleSearchService.search(
            feeds: feeds,
            query: query,
            limit: limit,
            includeFullText: includeFullText
        )
    }

    /// 兴趣分可解释：命中的正/负向词
    func interestExplanation(for article: Article) -> String? {
        guard smartInterestFilterEnabled, !interestWeights.isEmpty else { return nil }
        // 高分且非低分场景不计算，降低列表滚动开销
        if let s = article.interestScore, s >= lowInterestThreshold + 0.05 { return nil }
        let tokens = Self.interestTokens(from: article.title + " " + article.summary)
        var pos: [(String, Double)] = []
        var neg: [(String, Double)] = []
        for t in tokens {
            guard let w = interestWeights[t] else { continue }
            if w > 0.05 { pos.append((t, w)) }
            else if w < -0.05 { neg.append((t, w)) }
        }
        pos.sort { $0.1 > $1.1 }
        neg.sort { $0.1 < $1.1 }
        var parts: [String] = []
        if let s = article.interestScore {
            parts.append(String(format: "兴趣分 %.0f%%", s * 100))
        }
        if !neg.isEmpty {
            let words = neg.prefix(4).map(\.0).joined(separator: "、")
            parts.append("降权：\(words)")
        }
        if !pos.isEmpty {
            let words = pos.prefix(4).map(\.0).joined(separator: "、")
            parts.append("加权：\(words)")
        }
        if article.interestScore != nil, article.interestScore! < lowInterestThreshold {
            parts.append("低于阈值，可能沉底或自动已读")
        }
        guard parts.count > 1 || (article.interestScore != nil && (!pos.isEmpty || !neg.isEmpty)) else {
            if let s = article.interestScore {
                return String(format: "兴趣分 %.0f%%（无关键词命中，中性）", s * 100)
            }
            return nil
        }
        return parts.joined(separator: " · ")
    }

    func scoreInterest(for article: Article) -> Double {
        guard !interestWeights.isEmpty else { return 0.5 }
        let tokens = Self.interestTokens(from: article.title + " " + article.summary)
        guard !tokens.isEmpty else { return 0.5 }
        var sum = 0.0
        var hit = 0
        for t in tokens {
            if let w = interestWeights[t] {
                sum += w
                hit += 1
            }
        }
        if hit == 0 { return 0.45 }
        let avg = sum / Double(hit)
        // 映射到 0～1
        return min(1, max(0, 0.5 + avg * 0.5))
    }

    func applyInterestScoring(toFeed feedID: UUID? = nil) {
        guard smartInterestFilterEnabled else { return }
        let targets: [Int]
        if let feedID, let i = feeds.firstIndex(where: { $0.id == feedID }) {
            targets = [i]
        } else {
            targets = Array(feeds.indices)
        }
        var changed = false
        for i in targets {
            for j in feeds[i].articles.indices {
                let article = feeds[i].articles[j]
                let score = scoreInterest(for: article)
                if feeds[i].articles[j].interestScore != score {
                    feeds[i].articles[j].interestScore = score
                    changed = true
                }
                if autoMarkLowInterestRead,
                   !article.isFavorite,
                   !article.isRead,
                   score < lowInterestThreshold {
                    feeds[i].articles[j].isRead = true
                    rememberReadLink(feeds[i].articles[j].link)
                    changed = true
                }
            }
            feeds[i].unreadCount = feeds[i].articles.filter { !$0.isRead }.count
        }
        if changed { saveToStorage() }
    }

    /// 用户点「不感兴趣」：降权相关词、标已读
    func markNotInterested(_ article: Article) {
        let tokens = Self.interestTokens(from: article.title + " " + article.summary)
        for t in tokens {
            let cur = interestWeights[t] ?? 0
            interestWeights[t] = max(-2.0, cur - 0.35)
        }
        // 收藏正向信号：打开/收藏可在别处加分；这里只处理负反馈
        markAsRead(article)
        if let i = feeds.firstIndex(where: { $0.id == article.feedID }),
           let j = feeds[i].articles.firstIndex(where: { $0.id == article.id }) {
            feeds[i].articles[j].interestScore = scoreInterest(for: feeds[i].articles[j])
        }
        persistSettings()
        saveToStorage()
    }

    /// 正向反馈（收藏时调用）
    func boostInterest(from article: Article) {
        let tokens = Self.interestTokens(from: article.title + " " + article.summary)
        for t in tokens.prefix(12) {
            let cur = interestWeights[t] ?? 0
            interestWeights[t] = min(2.0, cur + 0.25)
        }
        // 仅写设置（含兴趣权重）；不触发全量 feeds encode（由 scheduleFeedsPersist 合并）
        SettingsRepository.save(makePersistedSettings())
    }

    func setFeedSummaryPreset(_ feedID: UUID, presetID: String) {
        guard let idx = feeds.firstIndex(where: { $0.id == feedID }) else { return }
        var feed = feeds[idx]
        feed.summaryPromptPresetID = presetID
        feeds[idx] = feed
        saveToStorage()
    }

    func renameFeed(_ feedID: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let idx = feeds.firstIndex(where: { $0.id == feedID }) else { return }
        // 整元素重写，确保 @Observable 能追踪到 feeds 变化并刷新列表
        var feed = feeds[idx]
        feed.title = trimmed
        for j in feed.articles.indices {
            feed.articles[j].feedTitle = trimmed
        }
        feeds[idx] = feed
        saveToStorage()
    }

    func setFeedFetchFullContent(_ feedID: UUID, enabled: Bool) {
        guard let idx = feeds.firstIndex(where: { $0.id == feedID }) else { return }
        var feed = feeds[idx]
        feed.fetchFullContentEnabled = enabled
        feeds[idx] = feed
        saveToStorage()
    }

    func setFeedFetchComments(_ feedID: UUID, enabled: Bool) {
        guard let idx = feeds.firstIndex(where: { $0.id == feedID }) else { return }
        var feed = feeds[idx]
        feed.fetchCommentsEnabled = enabled
        feeds[idx] = feed
        saveToStorage()
    }

    func setFeedAutoTranslate(_ feedID: UUID, enabled: Bool) {
        guard let idx = feeds.firstIndex(where: { $0.id == feedID }) else { return }
        var feed = feeds[idx]
        feed.autoTranslateEnabled = enabled
        feeds[idx] = feed
        saveToStorage()
    }

    func setFeedUseFullContentURLPrefix(_ feedID: UUID, enabled: Bool) {
        guard let idx = feeds.firstIndex(where: { $0.id == feedID }) else { return }
        var feed = feeds[idx]
        feed.useFullContentURLPrefix = enabled
        feeds[idx] = feed
        saveToStorage()
    }

    /// 根据全局开关、源开关与前缀，生成实际抓取 URL；缓存仍用原始 article.link
    func fullContentFetchURL(for article: Article) -> String {
        let original = article.link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard fullContentURLPrefixEnabled else { return original }
        guard let feed = feeds.first(where: { $0.id == article.feedID }),
              feed.useFullContentURLPrefix else { return original }
        let prefix = fullContentURLPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prefix.isEmpty, !original.isEmpty else { return original }
        // 避免重复拼接
        if original.hasPrefix(prefix) { return original }
        return prefix + original
    }

    func markFaviconFetchDone(_ feedID: UUID) {
        guard let idx = feeds.firstIndex(where: { $0.id == feedID }) else { return }
        guard !feeds[idx].faviconFetchDone else { return }
        var feed = feeds[idx]
        feed.faviconFetchDone = true
        feeds[idx] = feed
        saveToStorage()
    }

    func isFullContentEnabled(for article: Article) -> Bool {
        feeds.first(where: { $0.id == article.feedID })?.fetchFullContentEnabled ?? true
    }

    func isCommentsEnabled(for article: Article) -> Bool {
        feeds.first(where: { $0.id == article.feedID })?.fetchCommentsEnabled ?? false
    }

    /// - Parameter force: 为 true 时忽略本地正文缓存，重新从网络抓取（用户再次点「获取全文」）
    func fetchFullContent(for article: Article, force: Bool = false) async throws -> Article {
        guard isFullContentEnabled(for: article) else {
            throw TranslationError.apiError("该订阅源已关闭全文获取")
        }
        let linkKey = Self.canonicalLink(article.link)

        // 非强制：优先复用 offline cache / 内存正文
        if !force {
            if let cached = OfflineCache.loadArticleBody(link: article.link), !cached.isEmpty,
               HTMLUtils.stripTags(cached).count >= 400 {
                var updated = article
                updated.content = cached
                updated.hasFullContent = true
                if let i = feeds.firstIndex(where: { $0.id == article.feedID }),
                   let j = feeds[i].articles.firstIndex(where: { $0.id == article.id }),
                   !feeds[i].articles[j].hasFullContent {
                    feeds[i].articles[j].hasFullContent = true
                    feeds[i].articles[j].content = ""
                    articleFlags.bump(article.id)
                    scheduleFeedsPersist()
                }
                return updated
            }
            if article.hasFullContent, !article.content.isEmpty,
               HTMLUtils.stripTags(article.content).count >= 400 {
                OfflineCache.persistArticleBody(link: article.link, html: article.content)
                if let i = feeds.firstIndex(where: { $0.id == article.feedID }),
                   let j = feeds[i].articles.firstIndex(where: { $0.id == article.id }) {
                    feeds[i].articles[j].content = ""
                    feeds[i].articles[j].hasFullContent = true
                }
                return article
            }
        }

        // in-flight 去重：强制刷新使用独立 key，避免吃到未 force 的进行中任务
        let inflightKey = force ? linkKey + "#force" : linkKey
        if let existing = fullContentInflight[inflightKey] {
            return try await existing.value
        }
        let task = Task<Article, Error> { @MainActor in
            let fetchURL = self.fullContentFetchURL(for: article)
            let result = try await ArticleContentFetcher.fetchFullContent(from: fetchURL, forceReload: force)
            OfflineCache.persistArticleBody(link: article.link, html: result.contentHTML)
            if let i = self.feeds.firstIndex(where: { $0.id == article.feedID }),
               let j = self.feeds[i].articles.firstIndex(where: { $0.id == article.id }) {
                self.feeds[i].articles[j].hasFullContent = true
                self.feeds[i].articles[j].content = ""
                self.articleFlags.bump(article.id)
            }
            self.scheduleFeedsPersist()
            var forReader = article
            forReader.content = result.contentHTML
            forReader.hasFullContent = true
            return forReader
        }
        fullContentInflight[inflightKey] = task
        defer { fullContentInflight[inflightKey] = nil }
        return try await task.value
    }

    func clearOfflineContentCache() { OfflineCache.clearContentCache() }
    func cacheSizeDescription() -> String { OfflineCache.formattedSize(OfflineCache.contentCacheSize()) }

    var isClearingCache = false
    var cacheClearProgress: Double = 0
    var cacheClearStatus: String = ""

    func clearOfflineContentCacheAsync() async {
        guard !isClearingCache else { return }
        isClearingCache = true
        cacheClearProgress = 0
        cacheClearStatus = "准备清理…"
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            var finished = false
            DispatchQueue.global(qos: .userInitiated).async {
                OfflineCache.clearContentCache { value, status in
                    DispatchQueue.main.async {
                        self.cacheClearProgress = value
                        self.cacheClearStatus = status
                        if value >= 1, !finished {
                            finished = true
                            self.isClearingCache = false
                            self.cacheClearStatus = "已清除"
                            cont.resume()
                        }
                    }
                }
            }
        }
    }

    func updateReadingProgress(articleID: UUID, progress: Double, persist: Bool = true) {
        let p = min(1, max(0, progress))
        for i in feeds.indices {
            if let j = feeds[i].articles.firstIndex(where: { $0.id == articleID }) {
                let old = feeds[i].articles[j].readingProgress
                if abs(old - p) < 0.05, p < 0.98 { return }
                feeds[i].articles[j].readingProgress = p
                // 默认仅在离开阅读页等时机 persist，避免滚动写盘卡顿
                if persist { saveToStorage() }
                return
            }
        }
    }

    func addHighlight(articleID: UUID, text: String, note: String = "") {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        for i in feeds.indices {
            if let j = feeds[i].articles.firstIndex(where: { $0.id == articleID }) {
                var list = feeds[i].articles[j].highlights
                if list.contains(where: { $0.text == t }) { return }
                list.insert(TextHighlight(text: t, note: note), at: 0)
                if list.count > 50 { list = Array(list.prefix(50)) }
                feeds[i].articles[j].highlights = list
                saveToStorage()
                return
            }
        }
    }

    func removeHighlight(articleID: UUID, highlightID: UUID) {
        for i in feeds.indices {
            if let j = feeds[i].articles.firstIndex(where: { $0.id == articleID }) {
                feeds[i].articles[j].highlights.removeAll { $0.id == highlightID }
                saveToStorage()
                return
            }
        }
    }


    func exportOPML() -> String {
        var lines: [String] = ["<?xml version=\"1.0\" encoding=\"UTF-8\"?>", "<opml version=\"2.0\">", "  <head><title>Harbor Subscriptions</title></head>", "  <body>"]
        func xmlEscape(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "\u{0026}amp;").replacingOccurrences(of: "<", with: "\u{0026}lt;").replacingOccurrences(of: ">", with: "\u{0026}gt;").replacingOccurrences(of: "\"", with: "\u{0026}quot;")
        }
        for section in feedsByGroup {
            if let g = section.group {
                lines.append("    <outline text=\"\(xmlEscape(g.name))\" title=\"\(xmlEscape(g.name))\">")
                for f in section.feeds {
                    lines.append("      <outline type=\"rss\" text=\"\(xmlEscape(f.title))\" title=\"\(xmlEscape(f.title))\" xmlUrl=\"\(xmlEscape(f.url))\" />")
                }
                lines.append("    </outline>")
            } else {
                for f in section.feeds {
                    lines.append("    <outline type=\"rss\" text=\"\(xmlEscape(f.title))\" title=\"\(xmlEscape(f.title))\" xmlUrl=\"\(xmlEscape(f.url))\" />")
                }
            }
        }
        lines.append("  </body>")
        lines.append("</opml>")
        return lines.joined(separator: "\n")
    }


    func writeExportFile(content: String, filename: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            guard let data = content.data(using: .utf8) else { return nil }
            try data.write(to: url, options: .atomic)
            return url
        } catch { return nil }
    }

    @discardableResult
    func importSubscriptions(data: Data) -> SubscriptionImportResult {
        let items = OPMLParser(data: data).parse()
        if !items.isEmpty {
            var added = 0; var skipped = 0
            let existing = Set(feeds.map { Self.canonicalLink($0.url) })
            for item in items {
                let key = Self.canonicalLink(item.url)
                guard !key.isEmpty else { continue }
                if existing.contains(key) { skipped += 1; continue }
                var feed = RSSFeed(title: item.title.isEmpty ? key : item.title, url: item.url)
                feed.fetchCommentsEnabled = CommentFetcher.shouldAutoEnableComments(feedURL: item.url)
                if let gname = item.groupName, !gname.isEmpty {
                    if let g = groups.first(where: { $0.name == gname }) { feed.groupID = g.id }
                    else {
                        let order = (groups.map(\.sortOrder).max() ?? -1) + 1
                        let g = FeedGroup(name: gname, sortOrder: order)
                        groups.append(g); feed.groupID = g.id
                    }
                }
                feeds.append(feed); added += 1
            }
            if added > 0 { saveToStorage() }
            return SubscriptionImportResult(added: added, skipped: skipped, kind: "opml")
        }
        if let link = FeedParser.extractFeedLink(from: data), !link.isEmpty {
            let url = Self.canonicalLink(link)
            if feeds.contains(where: { Self.canonicalLink($0.url) == url }) {
                return SubscriptionImportResult(added: 0, skipped: 1, kind: "rss")
            }
            let title = FeedParser.extractFeedTitle(from: data) ?? url
            var feed = RSSFeed(title: title, url: link)
            feed.fetchCommentsEnabled = CommentFetcher.shouldAutoEnableComments(feedURL: link)
            feeds.append(feed)
            saveToStorage()
            return SubscriptionImportResult(added: 1, skipped: 0, kind: "rss")
        }
        return SubscriptionImportResult(added: 0, skipped: 0, kind: "empty")
    }

    func makePersistedSettings() -> PersistedAppSettings {
        PersistedAppSettings(
            fontSize: fontSize,
            listTitleFontSize: listTitleFontSize,
            listSummaryFontSize: listSummaryFontSize,
            readerTitleFontSize: readerTitleFontSize,
            aiSummaryFontSize: aiSummaryFontSize,
            feedTitleFontSize: feedTitleFontSize,
            groupTitleFontSize: groupTitleFontSize,
            titleDisplayMode: titleDisplayMode,
            defaultTranslationEngine: defaultTranslationEngine,
            translationEngineChain: translationEngineChain,
            showReadArticles: showReadArticles,
            showUnreadCount: showUnreadCount,
            translationPrompt: translationPrompt,
            translationRefinementPrompt: translationRefinementPrompt,
            summaryPrompt: summaryPrompt,
            explainPrompt: explainPrompt,
            readRetentionDays: readRetentionDays,
            fullContentCacheDays: fullContentCacheDays,
            fullContentURLPrefixEnabled: fullContentURLPrefixEnabled,
            fullContentURLPrefix: fullContentURLPrefix,
            globalSummaryPresetID: globalSummaryPresetID,
            summaryPromptPresets: summaryPromptPresets,
            smartInterestFilterEnabled: smartInterestFilterEnabled,
            autoMarkLowInterestRead: autoMarkLowInterestRead,
            lowInterestThreshold: lowInterestThreshold,
            sortByInterestScore: sortByInterestScore,
            modelRoutingEnabled: modelRoutingEnabled,
            modelRoutingShortLimit: modelRoutingShortLimit,
            interestWeights: interestWeights,
            ttsVoice: ttsVoice,
            ttsRate: ttsRate,
            colorThemeRaw: colorTheme.rawValue,
            appearanceModeRaw: appearanceMode.rawValue,
            appFontFamilyRaw: appFontFamily.rawValue,
            feedSortModeRaw: feedSortMode.rawValue,
            targetLanguage: targetLanguage,
            translationConcurrency: translationConcurrency,
            microsoftTranslateRegion: microsoftTranslateRegion,
            lingvaCustomBase: lingvaCustomBase,
            aiOutputLanguage: aiOutputLanguage,
            aiProviders: aiProviders,
            defaultSummaryProviderID: defaultSummaryProviderID,
            defaultTranslationProviderID: defaultTranslationProviderID,
            defaultExplainProviderID: defaultExplainProviderID,
            aiBlacklistTerms: aiBlacklistTerms,
            articleBlacklistTerms: articleBlacklistTerms,
            aiBlacklistFallbackProviderID: aiBlacklistFallbackProviderID,
            defaultChatProviderID: defaultChatProviderID,
            bookDefaultReadingMode: settings.bookDefaultReadingMode,
            bookTTSRate: settings.bookTTSRate,
            bookAutoLanguageVoice: settings.bookAutoLanguageVoice
        )
    }

    func applyPersistedSettings(_ s: PersistedAppSettings) {
        fontSize = s.fontSize
        listTitleFontSize = s.listTitleFontSize
        listSummaryFontSize = s.listSummaryFontSize
        readerTitleFontSize = s.readerTitleFontSize
        aiSummaryFontSize = s.aiSummaryFontSize
        feedTitleFontSize = s.feedTitleFontSize
        groupTitleFontSize = s.groupTitleFontSize
        titleDisplayMode = s.titleDisplayMode
        defaultTranslationEngine = s.defaultTranslationEngine
        translationEngineChain = s.translationEngineChain
        showReadArticles = s.showReadArticles
        showUnreadCount = s.showUnreadCount
        translationPrompt = s.translationPrompt
        translationRefinementPrompt = s.translationRefinementPrompt
        summaryPrompt = s.summaryPrompt
        explainPrompt = s.explainPrompt
        Self.migrateLegacyDefaultPrompts(
            translation: &translationPrompt,
            summary: &summaryPrompt,
            explain: &explainPrompt
        )
        readRetentionDays = s.readRetentionDays
        fullContentCacheDays = s.fullContentCacheDays
        fullContentURLPrefixEnabled = s.fullContentURLPrefixEnabled
        fullContentURLPrefix = s.fullContentURLPrefix
        globalSummaryPresetID = s.globalSummaryPresetID
        summaryPromptPresets = s.summaryPromptPresets
        ensureSummaryPromptPresets()
        if !summaryPromptPresets.contains(where: { $0.id == globalSummaryPresetID }) {
            globalSummaryPresetID = SummaryPromptPreset.standardID
        }
        smartInterestFilterEnabled = s.smartInterestFilterEnabled
        autoMarkLowInterestRead = s.autoMarkLowInterestRead
        lowInterestThreshold = s.lowInterestThreshold
        sortByInterestScore = s.sortByInterestScore
        modelRoutingEnabled = s.modelRoutingEnabled
        modelRoutingShortLimit = s.modelRoutingShortLimit
        interestWeights = s.interestWeights
        ttsVoice = s.ttsVoice
        ttsRate = s.ttsRate
        settings.bookDefaultReadingMode = s.bookDefaultReadingMode
        settings.bookTTSRate = s.bookTTSRate
        settings.bookAutoLanguageVoice = s.bookAutoLanguageVoice
        if let theme = ReadingTheme(rawValue: s.colorThemeRaw) {
            colorTheme = theme
        } else {
            switch s.colorThemeRaw {
            case "azure": colorTheme = .classicLight
            case "sepia": colorTheme = .sepiaPaper
            case "midnight": colorTheme = .midnightBlue
            case "forest": colorTheme = .forestSage
            case "graphite": colorTheme = .nightDark
            default: break
            }
        }
        if let mode = AppearanceMode(rawValue: s.appearanceModeRaw) {
            appearanceMode = mode
        }
        if let font = AppFontFamily(rawValue: s.appFontFamilyRaw) {
            appFontFamily = font
        }
        if let sort = FeedSortMode(rawValue: s.feedSortModeRaw) {
            feedSortMode = sort
        }
        targetLanguage = s.targetLanguage
        translationConcurrency = s.translationConcurrency
        microsoftTranslateRegion = s.microsoftTranslateRegion
        lingvaCustomBase = s.lingvaCustomBase
        aiOutputLanguage = s.aiOutputLanguage
        aiProviders = s.aiProviders
        defaultSummaryProviderID = s.defaultSummaryProviderID
        defaultTranslationProviderID = s.defaultTranslationProviderID
        defaultExplainProviderID = s.defaultExplainProviderID
        aiBlacklistTerms = s.aiBlacklistTerms
        articleBlacklistTerms = s.articleBlacklistTerms
        aiBlacklistFallbackProviderID = s.aiBlacklistFallbackProviderID
        defaultChatProviderID = s.defaultChatProviderID
    }

    /// 高频路径防抖写入 feeds 元数据快照。
    /// 崩溃窗口约定：
    /// - 已读 / 收藏：UserDefaults 链接集**即时**落盘（不依赖本防抖）
    /// - 正文：OfflineCache HTML 在 evacuate / saveFeeds 时落盘
    /// - feeds.json：合并后的元数据（标题/摘要/标志），杀进程最多丢防抖间隔内的非标志字段
    private func scheduleFeedsPersist() {
        pendingFeedsPersistTask?.cancel()
        pendingFeedsPersistTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.feedsPersistDelayNs)
            guard !Task.isCancelled else { return }
            pendingFeedsPersistTask = nil
            evacuateAllHeavyBodiesInMemory()
            FeedRepository.saveFeeds(feeds)
            persistReadLinks()
            persistFavoriteLinks()
            // 已读/收藏路径：长防抖推 iCloud，避免每次点已读都全量推
            scheduleICloudPush(kind: .readState)
        }
    }

    /// 立即写入待定的 feeds（进入后台 / 完整 save / 刷新结束）
    func flushPendingFeedsPersist() {
        pendingFeedsPersistTask?.cancel()
        pendingFeedsPersistTask = nil
        evacuateAllHeavyBodiesInMemory()
        FeedRepository.saveFeeds(feeds)
        persistReadLinks()
        persistFavoriteLinks()
    }

    func saveToStorage() {
        // 合并未刷盘的已读/收藏变更，避免被后续逻辑覆盖为旧快照
        pendingFeedsPersistTask?.cancel()
        pendingFeedsPersistTask = nil
        evacuateAllHeavyBodiesInMemory()
        FeedRepository.saveFeeds(feeds)
        FeedRepository.saveGroups(groups)
        persistCollapsedGroups()
        persistReadLinks()
        persistFavoriteLinks()
        SettingsRepository.save(makePersistedSettings())
        OfflineCache.saveChatConversations(chatConversations)
        scheduleICloudPush(kind: .catalog)
    }

    func loadFromStorage() {
        feeds = FeedRepository.loadFeeds()
        groups = FeedRepository.loadGroups()
        loadCollapsedGroups()
        loadReadLinks()
        loadFavoriteLinks()
        applyFlagLinksToFeeds()
        rebuildArticleIndex()
        applyPersistedSettings(SettingsRepository.load())
        if let loaded = OfflineCache.loadChatConversations() {
            chatConversations = loaded.sorted { $0.updatedAt > $1.updatedAt }
        }
        // 启动后剥离已落盘的大正文，降低常驻内存；并纠正无缓存的误标全文
        evacuateAllHeavyBodiesInMemory()
        recoverOrphanFullContentFlags()
    }

    // MARK: - iCloud 同步

    private func startICloudSync() {
        iCloudObserver = ICloudSyncService.startObserving { [weak self] in
            self?.pullICloudIfNeeded()
        }
        // 启动时先 synchronize，再尝试拉云端
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            pullICloudIfNeeded()
            // 本机有数据且云端空/更旧时推上去
            scheduleICloudPush()
            refreshICloudStatusText()
        }
    }

    /// iCloud 推送动机：设置变更应更快；已读/收藏可更长防抖，减少无意义全量推
    enum ICloudPushKind {
        case settings
        case catalog
        case readState

        var delayNs: UInt64 {
            switch self {
            case .settings: return 500_000_000
            case .catalog: return 800_000_000
            case .readState: return 3_000_000_000
            }
        }
    }

    func scheduleICloudPush(kind: ICloudPushKind = .catalog) {
        guard ICloudSyncService.isEnabled, !isApplyingICloud else { return }
        iCloudPushTask?.cancel()
        let delay = kind.delayNs
        iCloudPushTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            pushToICloudNow()
        }
    }

    func pushToICloudNow() {
        guard ICloudSyncService.isEnabled, !isApplyingICloud else { return }
        let settingsData = try? JSONEncoder().encode(makePersistedSettingsForCloud())
        let favoriteLinks = feeds.flatMap { $0.articles }.filter(\.isFavorite).map(\.link)
        ICloudSyncService.push(
            feeds: feeds,
            groups: groups,
            settingsData: settingsData,
            readLinks: readArticleLinks,
            favoriteLinks: favoriteLinks,
            collapsedGroupIDs: collapsedGroupIDs,
            isUngroupedCollapsed: isUngroupedCollapsed
        )
        refreshICloudStatusText()
    }

    func pullICloudIfNeeded() {
        guard ICloudSyncService.isEnabled else { return }
        guard let snap = ICloudSyncService.pullIfNewer() else {
            refreshICloudStatusText()
            return
        }
        applyICloudSnapshot(snap)
    }

    /// 设置页「立即同步」：强制拉再推
    func syncICloudNow() {
        guard ICloudSyncService.isEnabled else { return }
        if let snap = ICloudSyncService.forcePull(),
           let local = ICloudSyncService.lastLocalPushAt,
           snap.updatedAt > local {
            applyICloudSnapshot(snap)
        } else if let snap = ICloudSyncService.forcePull(), ICloudSyncService.lastLocalPushAt == nil {
            applyICloudSnapshot(snap)
        }
        pushToICloudNow()
        refreshICloudStatusText()
    }

    private func applyICloudSnapshot(_ snap: ICloudSyncService.Snapshot) {
        isApplyingICloud = true
        defer {
            isApplyingICloud = false
            ICloudSyncService.lastLocalPushAt = snap.updatedAt
            refreshICloudStatusText()
        }

        // 分组
        groups = snap.groups

        // 源：按 URL 合并，保留本机文章与全文缓存关联
        let localByURL = Dictionary(feeds.map { (Self.canonicalLink($0.url), $0) }, uniquingKeysWith: { a, _ in a })
        var merged: [RSSFeed] = []
        var seen = Set<String>()
        for rec in snap.feeds {
            let key = Self.canonicalLink(rec.url)
            if seen.contains(key) { continue }
            seen.insert(key)
            if var existing = localByURL[key] {
                rec.applyMetadata(to: &existing)
                // 若云端 id 不同，保持本机 id 以免破坏本地引用
                merged.append(existing)
            } else {
                merged.append(rec.makeFeed())
            }
        }
        feeds = merged

        collapsedGroupIDs = Set(snap.collapsedGroupIDs)
        isUngroupedCollapsed = snap.isUngroupedCollapsed
        FeedRepository.saveCollapsedState(groupIDs: collapsedGroupIDs, isUngroupedCollapsed: isUngroupedCollapsed)

        // 已读
        readArticleLinks.formUnion(snap.readLinks)
        for i in feeds.indices {
            for j in feeds[i].articles.indices {
                let link = Self.canonicalLink(feeds[i].articles[j].link)
                if readArticleLinks.contains(link) {
                    feeds[i].articles[j].isRead = true
                }
            }
        }

        // 收藏链接
        let favSet = Set(snap.favoriteLinks.map { Self.canonicalLink($0) })
        if !favSet.isEmpty {
            for i in feeds.indices {
                for j in feeds[i].articles.indices {
                    if favSet.contains(Self.canonicalLink(feeds[i].articles[j].link)) {
                        feeds[i].articles[j].isFavorite = true
                    }
                }
            }
        }

        // 设置（密钥走 iCloud 钥匙串，不进快照）
        if let data = snap.settingsData,
           let decoded = try? JSONDecoder().decode(PersistedAppSettings.self, from: data) {
            applyPersistedSettings(decoded)
        }

        FeedRepository.saveFeeds(feeds)
        FeedRepository.saveGroups(groups)
        persistReadLinks()
        SettingsRepository.save(makePersistedSettings())
    }

    private func refreshICloudStatusText() {
        let fmt = DateFormatter()
        fmt.dateStyle = .short
        fmt.timeStyle = .short
        if let cloud = ICloudSyncService.cloudUpdatedAt {
            iCloudLastSyncText = "云端：\(fmt.string(from: cloud))"
        } else if let local = ICloudSyncService.lastLocalPushAt {
            iCloudLastSyncText = "本机已上传：\(fmt.string(from: local))"
        } else {
            iCloudLastSyncText = ICloudSyncService.isEnabled ? "等待首次同步…" : "已关闭"
        }
    }

    /// 云端设置快照（不含密钥）
    private func makePersistedSettingsForCloud() -> PersistedAppSettings {
        makePersistedSettings()
    }

    // MARK: - AI Chat

    static let defaultChatSystemPrompt = """
你是有帮助的助手。用清晰、简洁的语言回答用户问题。
若用户使用中文，优先用中文回复。
"""

    /// 已配置 API Key 的 Provider（对话页仅允许选用这些）
    var chatCapableProviders: [AIProvider] {
        aiProviders.filter { !loadAIKeys(for: $0.id).isEmpty }
    }

    @discardableResult
    func createChatConversation(providerID: UUID? = nil, model: String? = nil) -> ChatConversation {
        let pid = providerID
            ?? defaultChatProviderID
            ?? chatCapableProviders.first?.id
            ?? aiProviders.first?.id
        let provider = pid.flatMap { id in aiProviders.first(where: { $0.id == id }) }
        let resolvedModel = model
            ?? provider?.model
            ?? provider?.availableModels.first
        var conv = ChatConversation(
            title: "新对话",
            providerID: pid,
            model: resolvedModel,
            systemPrompt: Self.defaultChatSystemPrompt
        )
        chatConversations.insert(conv, at: 0)
        activeChatID = conv.id
        persistChat()
        return conv
    }

    func deleteChatConversation(_ id: UUID) {
        chatConversations.removeAll { $0.id == id }
        if activeChatID == id {
            activeChatID = chatConversations.first?.id
        }
        persistChat()
    }

    func deleteChatConversations(at offsets: IndexSet) {
        let sorted = chatConversations
        let ids = offsets.map { sorted[$0].id }
        chatConversations.removeAll { ids.contains($0.id) }
        if let active = activeChatID, ids.contains(active) {
            activeChatID = chatConversations.first?.id
        }
        persistChat()
    }

    func clearAllChatConversations() {
        chatConversations = []
        activeChatID = nil
        persistChat()
    }

    func renameChatConversation(_ id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let idx = chatConversations.firstIndex(where: { $0.id == id }) else { return }
        chatConversations[idx].title = trimmed
        chatConversations[idx].updatedAt = Date()
        persistChat()
    }

    func setChatProvider(conversationID: UUID, providerID: UUID, model: String? = nil) {
        guard chatCapableProviders.contains(where: { $0.id == providerID }) else { return }
        guard let idx = chatConversations.firstIndex(where: { $0.id == conversationID }) else { return }
        chatConversations[idx].providerID = providerID
        if let model, !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            chatConversations[idx].model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let p = aiProviders.first(where: { $0.id == providerID }) {
            // 切换 Provider 时若未指定模型，落到该 Provider 默认模型
            chatConversations[idx].model = p.model
        }
        chatConversations[idx].updatedAt = Date()
        defaultChatProviderID = providerID
        persistChat()
        saveToStorage()
    }

    func setChatModel(conversationID: UUID, model: String) {
        let m = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !m.isEmpty,
              let idx = chatConversations.firstIndex(where: { $0.id == conversationID }) else { return }
        chatConversations[idx].model = m
        chatConversations[idx].updatedAt = Date()
        persistChat()
    }

    func clearChatMessages(_ conversationID: UUID) {
        guard let idx = chatConversations.firstIndex(where: { $0.id == conversationID }) else { return }
        chatConversations[idx].messages = []
        chatConversations[idx].updatedAt = Date()
        persistChat()
    }

    /// 发送用户消息并请求回复；仅可使用已配置 Key 的 Provider
    func sendChatMessage(conversationID: UUID, text: String) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let idx = chatConversations.firstIndex(where: { $0.id == conversationID }) else {
            throw TranslationError.apiError("对话不存在")
        }

        var conv = chatConversations[idx]
        let userMsg = ChatMessage(role: .user, content: trimmed)
        conv.messages.append(userMsg)
        if conv.title == "新对话" {
            conv.title = String(trimmed.prefix(24))
        }
        conv.updatedAt = Date()
        chatConversations[idx] = conv
        persistChat()

        let providerID = conv.providerID
            ?? defaultChatProviderID
            ?? chatCapableProviders.first?.id
        guard let providerID,
              let provider = chatCapableProviders.first(where: { $0.id == providerID })
                ?? aiProviders.first(where: { $0.id == providerID }),
              !loadAIKeys(for: provider.id).isEmpty else {
            var c = chatConversations[idx]
            c.messages.append(ChatMessage(
                role: .assistant,
                content: "未配置可用的 AI Provider 或 API Key。请到设置 → AI 设置中添加。",
                isError: true
            ))
            c.updatedAt = Date()
            chatConversations[idx] = c
            persistChat()
            throw TranslationError.noProvider
        }

        // 若会话绑定的 Provider 已无 Key，自动切到第一个可用
        var resolved: AIProvider = {
            if chatCapableProviders.contains(where: { $0.id == provider.id }) { return provider }
            return chatCapableProviders.first ?? provider
        }()
        // 会话级模型覆盖（多模型 Provider）
        let sessionModel = (chatConversations.first(where: { $0.id == conversationID })?.model
            ?? conv.model)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !sessionModel.isEmpty {
            resolved = resolved.using(model: sessionModel)
        }
        if conv.providerID != resolved.id {
            conv.providerID = resolved.id
            if let i = chatConversations.firstIndex(where: { $0.id == conversationID }) {
                chatConversations[i].providerID = resolved.id
            }
        }

        var history: [(role: ChatRole, content: String)] = []
        let system = conv.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !system.isEmpty {
            history.append((.system, system))
        }
        // 限制上下文长度，避免超长请求
        let recent = (chatConversations.first(where: { $0.id == conversationID })?.messages ?? conv.messages)
            .filter { !$0.isError }
            .suffix(40)
        for m in recent {
            history.append((m.role, m.content))
        }

        do {
            let reply = try await callAIChatWithProviderKeys(
                provider: resolved,
                messages: history,
                maxTokens: 2048
            )
            let assistant = ChatMessage(
                role: .assistant,
                content: reply,
                providerID: resolved.id,
                providerName: "\(resolved.name) · \(resolved.model)"
            )
            if let i = chatConversations.firstIndex(where: { $0.id == conversationID }) {
                var c = chatConversations[i]
                c.messages.append(assistant)
                c.updatedAt = Date()
                chatConversations[i] = c
                chatConversations.sort { $0.updatedAt > $1.updatedAt }
                persistChat()
            }
        } catch {
            if let i = chatConversations.firstIndex(where: { $0.id == conversationID }) {
                var c = chatConversations[i]
                c.messages.append(ChatMessage(
                    role: .assistant,
                    content: error.localizedDescription,
                    providerID: resolved.id,
                    providerName: resolved.name,
                    isError: true
                ))
                c.updatedAt = Date()
                chatConversations[i] = c
                persistChat()
            }
            throw error
        }
    }

    private func callAIChatWithProviderKeys(
        provider: AIProvider,
        messages: [(role: ChatRole, content: String)],
        maxTokens: Int
    ) async throws -> String {
        let allKeys = loadAIKeys(for: provider.id)
        guard !allKeys.isEmpty else { throw TranslationError.apiError("未配置 API Key") }
        var book = aiKeyCooldown[provider.id] ?? KeyCooldownBook()
        let keys = book.availableKeys(from: allKeys)
        let start = (aiKeyRoundRobin[provider.id] ?? 0) % keys.count
        var lastError: Error = TranslationError.apiError("全部 Key 失败")
        for offset in 0..<keys.count {
            let idx = (start + offset) % keys.count
            let key = keys[idx]
            do {
                let raw = try await callAIChat(messages: messages, provider: provider, apiKey: key, maxTokens: maxTokens)
                let text = AIResponseSanitizer.stripThinking(raw)
                if text.isEmpty || Self.looksLikeAIErrorResponse(text) {
                    book.mark(key, kind: .other)
                    aiKeyCooldown[provider.id] = book
                    lastError = TranslationError.apiError(text.isEmpty ? "空响应" : text)
                    continue
                }
                aiKeyRoundRobin[provider.id] = (allKeys.firstIndex(of: key) ?? idx) + 1
                aiKeyCooldown[provider.id] = book
                return text
            } catch {
                lastError = error
                book.mark(key, kind: Self.keyFailureKind(error))
                aiKeyCooldown[provider.id] = book
                continue
            }
        }
        aiKeyCooldown[provider.id] = book
        throw lastError
    }

    private func persistChat() {
        OfflineCache.saveChatConversations(chatConversations)
    }

    private func seedSampleData() {}
}
