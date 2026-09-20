import Foundation
import Security

// MARK: - App Version

enum AppVersion {
    /// 营销版本，如 1.3（MARKETING_VERSION）
    static var marketing: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.3"
    }
    /// 工程构建号，如 10（CURRENT_PROJECT_VERSION）
    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "32"
    }
    /// CI 在编译前写入 run_number；本地为空字符串
    /// 勿改字面量格式，build.yml 依赖此行做 sed 替换
    static let githubBuildNumber: String = ""
    /// GitHub Actions run_number（优先编译期常量，其次 Info.plist）
    static var githubBuild: String? {
        if !githubBuildNumber.isEmpty { return githubBuildNumber }
        for key in ["HarborGitHubBuild", "IosRssGitHubBuild", "GitHubBuild", "CI_BUILD_NUMBER"] {
            if let v = Bundle.main.infoDictionary?[key] as? String, !v.isEmpty { return v }
            if let n = Bundle.main.infoDictionary?[key] as? NSNumber { return n.stringValue }
        }
        return nil
    }
    /// 展示：CI 为 v1.3-35-buildN；本地为 v1.3-35
    static var display: String {
        if let g = githubBuild {
            return "v\(marketing)-\(build)-build\(g)"
        }
        return "v\(marketing)-\(build)"
    }
}

// MARK: - Core Models

/// 订阅源分组（类似文件夹）
struct FeedGroup: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var sortOrder: Int = 0

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: FeedGroup, rhs: FeedGroup) -> Bool { lhs.id == rhs.id }
}

struct RSSFeed: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var url: String
    var faviconURL: String?
    var unreadCount: Int = 0
    var articles: [Article] = []
    var lastFetched: Date?
    /// 所属分组；nil = 未分组
    var groupID: UUID?
    /// 是否对该源自动/手动抓取全文；默认开启
    var fetchFullContentEnabled: Bool = true
    /// 是否在阅读页提供「评论」入口（如 Substack）；默认关闭
    var fetchCommentsEnabled: Bool = false
    /// 是否已对该源执行过图标获取（成功或失败后均为 true，后台用）
    var faviconFetchDone: Bool = false
    /// 列表进入时是否自动翻译非目标语言且未译条目
    var autoTranslateEnabled: Bool = true
    /// 全文抓取时是否对该源使用全局 URL 前缀（需在设置中开启并配置前缀）
    var useFullContentURLPrefix: Bool = false
    /// 该源摘要 Prompt 预设 ID；`"global"` 表示跟随全局
    var summaryPromptPresetID: String = SummaryPromptPreset.globalID
    /// 同组内排序（越小越靠前）
    var sortOrder: Int = 0
    /// 最近一次刷新失败原因（成功时清空）；列表行展示
    var lastRefreshError: String? = nil

    enum CodingKeys: String, CodingKey {
        case id, title, url, faviconURL, unreadCount, articles, lastFetched, groupID
        case fetchFullContentEnabled, fetchCommentsEnabled, faviconFetchDone, autoTranslateEnabled
        case useFullContentURLPrefix, summaryPromptPresetID, summaryPromptPreset, sortOrder
        case lastRefreshError
    }

    init(id: UUID = UUID(), title: String, url: String, faviconURL: String? = nil,
         unreadCount: Int = 0, articles: [Article] = [], lastFetched: Date? = nil,
         groupID: UUID? = nil, fetchFullContentEnabled: Bool = true,
         fetchCommentsEnabled: Bool = false,
         faviconFetchDone: Bool = false,
         autoTranslateEnabled: Bool = true,
         useFullContentURLPrefix: Bool = false,
         summaryPromptPresetID: String = SummaryPromptPreset.globalID,
         sortOrder: Int = 0,
         lastRefreshError: String? = nil) {
        self.id = id
        self.title = title
        self.url = url
        self.faviconURL = faviconURL
        self.unreadCount = unreadCount
        self.articles = articles
        self.lastFetched = lastFetched
        self.groupID = groupID
        self.fetchFullContentEnabled = fetchFullContentEnabled
        self.fetchCommentsEnabled = fetchCommentsEnabled
        self.faviconFetchDone = faviconFetchDone
        self.autoTranslateEnabled = autoTranslateEnabled
        self.useFullContentURLPrefix = useFullContentURLPrefix
        self.summaryPromptPresetID = summaryPromptPresetID
        self.sortOrder = sortOrder
        self.lastRefreshError = lastRefreshError
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decode(String.self, forKey: .title)
        url = try c.decode(String.self, forKey: .url)
        faviconURL = try c.decodeIfPresent(String.self, forKey: .faviconURL)
        unreadCount = try c.decodeIfPresent(Int.self, forKey: .unreadCount) ?? 0
        articles = try c.decodeIfPresent([Article].self, forKey: .articles) ?? []
        lastFetched = try c.decodeIfPresent(Date.self, forKey: .lastFetched)
        groupID = try c.decodeIfPresent(UUID.self, forKey: .groupID)
        fetchFullContentEnabled = try c.decodeIfPresent(Bool.self, forKey: .fetchFullContentEnabled) ?? true
        fetchCommentsEnabled = try c.decodeIfPresent(Bool.self, forKey: .fetchCommentsEnabled) ?? false
        faviconFetchDone = try c.decodeIfPresent(Bool.self, forKey: .faviconFetchDone) ?? false
        autoTranslateEnabled = try c.decodeIfPresent(Bool.self, forKey: .autoTranslateEnabled) ?? true
        useFullContentURLPrefix = try c.decodeIfPresent(Bool.self, forKey: .useFullContentURLPrefix) ?? false
        if let id = try c.decodeIfPresent(String.self, forKey: .summaryPromptPresetID), !id.isEmpty {
            summaryPromptPresetID = id
        } else if let legacy = try c.decodeIfPresent(String.self, forKey: .summaryPromptPreset), !legacy.isEmpty {
            summaryPromptPresetID = legacy
        } else {
            summaryPromptPresetID = SummaryPromptPreset.globalID
        }
        sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        lastRefreshError = try c.decodeIfPresent(String.self, forKey: .lastRefreshError)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(url, forKey: .url)
        try c.encodeIfPresent(faviconURL, forKey: .faviconURL)
        try c.encode(unreadCount, forKey: .unreadCount)
        try c.encode(articles, forKey: .articles)
        try c.encodeIfPresent(lastFetched, forKey: .lastFetched)
        try c.encodeIfPresent(groupID, forKey: .groupID)
        try c.encode(fetchFullContentEnabled, forKey: .fetchFullContentEnabled)
        try c.encode(fetchCommentsEnabled, forKey: .fetchCommentsEnabled)
        try c.encode(faviconFetchDone, forKey: .faviconFetchDone)
        try c.encode(autoTranslateEnabled, forKey: .autoTranslateEnabled)
        try c.encode(useFullContentURLPrefix, forKey: .useFullContentURLPrefix)
        try c.encode(summaryPromptPresetID, forKey: .summaryPromptPresetID)
        try c.encode(sortOrder, forKey: .sortOrder)
        try c.encodeIfPresent(lastRefreshError, forKey: .lastRefreshError)
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: RSSFeed, rhs: RSSFeed) -> Bool { lhs.id == rhs.id }
}

struct TextHighlight: Identifiable, Codable, Hashable {
    var id = UUID()
    var text: String
    var note: String = ""
    var createdAt: Date = Date()
}

struct Article: Identifiable, Codable, Hashable {
    var id = UUID()
    var feedID: UUID
    var feedTitle: String
    var title: String
    var link: String
    var summary: String
    var content: String
    var publishedDate: Date?
    var isRead: Bool = false
    var isFavorite: Bool = false
    var translatedTitle: String?
    var translatedSummary: String?
    var translatedContent: String?
    /// 正文译文实际使用的翻译引擎展示名（如「Google 翻译」）
    var translationEngineName: String?
    var aiSummary: String?
    /// 生成该摘要时使用的 AI Provider 名称
    var aiSummaryProvider: String?
    /// 兴趣评分 0～1；nil 表示尚未计算
    var interestScore: Double?
    /// 是否已从原文页抓取过全文
    var hasFullContent: Bool = false
    /// RSS/Atom `<comments>` 讨论页（如 HN item），优先于 link 抓评论
    var commentsURL: String? = nil
    /// 阅读进度 0～1
    var readingProgress: Double = 0
    /// 用户高亮摘录
    var highlights: [TextHighlight] = []

    /// 是否已翻译：以正文译文为准（非仅标题/摘要）
    var hasTranslatedBody: Bool {
        guard let c = translatedContent?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return !c.isEmpty
    }

    enum CodingKeys: String, CodingKey {
        case id, feedID, feedTitle, title, link, summary, content
        case publishedDate, isRead, isFavorite, translatedTitle, translatedSummary, translatedContent
        case translationEngineName
        case aiSummary, aiSummaryProvider, interestScore, hasFullContent, commentsURL, readingProgress, highlights
    }

    init(id: UUID = UUID(), feedID: UUID, feedTitle: String, title: String, link: String,
         summary: String, content: String, publishedDate: Date? = nil, isRead: Bool = false,
         isFavorite: Bool = false,
         translatedTitle: String? = nil, translatedSummary: String? = nil,
         translatedContent: String? = nil,
         translationEngineName: String? = nil,
         aiSummary: String? = nil,
         aiSummaryProvider: String? = nil,
         interestScore: Double? = nil,
         hasFullContent: Bool = false,
         commentsURL: String? = nil,
         readingProgress: Double = 0,
         highlights: [TextHighlight] = []) {
        self.id = id
        self.feedID = feedID
        self.feedTitle = feedTitle
        self.title = title
        self.link = link
        self.summary = summary
        self.content = content
        self.publishedDate = publishedDate
        self.isRead = isRead
        self.isFavorite = isFavorite
        self.translatedTitle = translatedTitle
        self.translatedSummary = translatedSummary
        self.translatedContent = translatedContent
        self.translationEngineName = translationEngineName
        self.aiSummary = aiSummary
        self.aiSummaryProvider = aiSummaryProvider
        self.interestScore = interestScore
        self.hasFullContent = hasFullContent
        self.commentsURL = commentsURL
        self.readingProgress = readingProgress
        self.highlights = highlights
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        feedID = try c.decode(UUID.self, forKey: .feedID)
        feedTitle = try c.decode(String.self, forKey: .feedTitle)
        title = try c.decode(String.self, forKey: .title)
        link = try c.decode(String.self, forKey: .link)
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        publishedDate = try c.decodeIfPresent(Date.self, forKey: .publishedDate)
        isRead = try c.decodeIfPresent(Bool.self, forKey: .isRead) ?? false
        isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        translatedTitle = try c.decodeIfPresent(String.self, forKey: .translatedTitle)
        translatedSummary = try c.decodeIfPresent(String.self, forKey: .translatedSummary)
        translatedContent = try c.decodeIfPresent(String.self, forKey: .translatedContent)
        translationEngineName = try c.decodeIfPresent(String.self, forKey: .translationEngineName)
        aiSummary = try c.decodeIfPresent(String.self, forKey: .aiSummary)
        aiSummaryProvider = try c.decodeIfPresent(String.self, forKey: .aiSummaryProvider)
        interestScore = try c.decodeIfPresent(Double.self, forKey: .interestScore)
        hasFullContent = try c.decodeIfPresent(Bool.self, forKey: .hasFullContent) ?? false
        commentsURL = try c.decodeIfPresent(String.self, forKey: .commentsURL)
        readingProgress = try c.decodeIfPresent(Double.self, forKey: .readingProgress) ?? 0
        highlights = try c.decodeIfPresent([TextHighlight].self, forKey: .highlights) ?? []
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Article, rhs: Article) -> Bool { lhs.id == rhs.id }

    var relativeTime: String {
        guard let date = publishedDate else { return "" }
        let diff = Date().timeIntervalSince(date)
        // 超过 30 天显示具体年月日（复用静态 formatter，避免列表每行反复创建）
        if diff >= 30 * 86400 {
            return Self.dayFormatter.string(from: date)
        }
        if diff < 3600 { return "\(max(0, Int(diff / 60)))分钟前" }
        if diff < 86400 { return "\(Int(diff / 3600))小时前" }
        return "\(Int(diff / 86400))天前"
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日"
        return f
    }()

    /// RSS 摘要是否偏短，适合触发全文抓取（不检查源级开关）
    var needsFullContentFetch: Bool {
        if hasFullContent { return false }
        let plain = HTMLUtils.stripTags(content)
        return plain.count < 400
    }
}

/// 订阅源列表排序
enum AppLanguage: String, CaseIterable, Codable, Identifiable {
    case zhHans, zhHant, en, ja, ko, fr, de, es

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        case .en: return "English"
        case .ja: return "日本語"
        case .ko: return "한국어"
        case .fr: return "Français"
        case .de: return "Deutsch"
        case .es: return "Español"
        }
    }

    /// Google Translate `tl`
    var googleCode: String {
        switch self {
        case .zhHans: return "zh-CN"
        case .zhHant: return "zh-TW"
        case .en: return "en"
        case .ja: return "ja"
        case .ko: return "ko"
        case .fr: return "fr"
        case .de: return "de"
        case .es: return "es"
        }
    }

    /// Microsoft Translator `to`
    var microsoftCode: String {
        switch self {
        case .zhHans: return "zh-Hans"
        case .zhHant: return "zh-Hant"
        default: return googleCode
        }
    }

    /// MyMemory `langpair` 目标端，如 zh-CN
    var mymemoryCode: String { googleCode }


    /// DeepL `target_lang`：主语言大写，脚本子码保持规范大小写（Readest 实测 `ZH-HANT` 会 500，`ZH-Hant` 正常）
    var deeplCode: String {
        switch self {
        case .zhHans: return "ZH-Hans"
        case .zhHant: return "ZH-Hant"
        case .en: return "EN"
        case .ja: return "JA"
        case .ko: return "KO"
        case .fr: return "FR"
        case .de: return "DE"
        case .es: return "ES"
        }
    }

    /// 写入 AI Prompt 的语言称呼
    var promptLabel: String {
        switch self {
        case .zhHans: return "简体中文"
        case .zhHant: return "繁体中文"
        case .en: return "English"
        case .ja: return "日本語"
        case .ko: return "한국어"
        case .fr: return "French"
        case .de: return "German"
        case .es: return "Spanish"
        }
    }

    /// 系统 Translation 框架用的 BCP-47 标识
    var translationLanguageIdentifier: String {
        switch self {
        case .zhHans: return "zh-Hans"
        case .zhHant: return "zh-Hant"
        case .en: return "en"
        case .ja: return "ja"
        case .ko: return "ko"
        case .fr: return "fr"
        case .de: return "de"
        case .es: return "es"
        }
    }

    var isChinese: Bool { self == .zhHans || self == .zhHant }
}

enum FeedSortMode: String, CaseIterable, Codable, Identifiable {
    case unreadThenTitle
    case title
    case lastFetched
    case manual

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .unreadThenTitle: return "未读优先（自动）"
        case .title: return "名称"
        case .lastFetched: return "最近更新"
        case .manual: return "手动排序"
        }
    }
}


enum TitleDisplayMode: String, CaseIterable, Codable {
    case original = "原文"
    case translated = "译文"
    case bilingual = "双语对照"
}

enum TranslationEngine: String, CaseIterable, Codable {
    case google = "Google 翻译"
    case mymemory = "MyMemory（免 Key）"
    case lingva = "Lingva（免 Key）"
    case yandex = "Yandex（免 Key）"
    case azure = "Azure/Bing（免 Key）"
    case microsoft = "Microsoft 翻译"
    case deepl = "DeepL"
    case ai = "AI 翻译"   // Gemini / OpenAI / Anthropic 等统一走 AI Provider

    /// 无需 API Key 的引擎
    var isFreeNoKey: Bool {
        switch self {
        case .google, .mymemory, .lingva, .yandex, .azure: return true
        default: return false
        }
    }
}

// MARK: - Prompt 预设（内置 + 可自定义）

struct SummaryPromptPreset: Identifiable, Codable, Hashable {
    /// 稳定 ID：内置为 fixed 字符串，自定义为 UUID 字符串
    var id: String
    var name: String
    var template: String
    /// 内置不可删除；模板可改，恢复默认时写回 builtInDefaults
    var isBuiltIn: Bool

    static let globalID = "global"
    static let standardID = "standard"
    static let techBriefID = "techBrief"
    static let academicID = "academic"
    static let investmentID = "investment"
    static let newsBriefID = "newsBrief"
    static let productReviewID = "productReview"

    static let globalName = "跟随全局"

    static var builtInDefaults: [SummaryPromptPreset] {
        [
            SummaryPromptPreset(
                id: standardID,
                name: "标准摘要",
                isBuiltIn: true,
                template: """
你是资深编辑。用{{lang}}按 5W1H 压缩核心信息（谁、何时、做了什么、为何、影响）。

要求：
- 3～5 句，每句一行；不要序号、不要「摘要如下」
- 只写原文可支撑的事实；观点须归因
- 时间尽量具体；专有名词可保留原文

标题：{{title}}

内容：{{content}}
"""
            ),
            SummaryPromptPreset(
                id: techBriefID,
                name: "科技速览",
                isBuiltIn: true,
                template: """
你是科技媒体编辑。用{{lang}}写「科技速览」。

结构（每条一行，无序号）：
- 发生了什么（产品/技术/公司）
- 相对现状的变化点
- 谁推动、影响谁
- 若有时间表/参数，单独点出

禁止复述标题；专有名词可中英并存。

标题：{{title}}

内容：{{content}}
"""
            ),
            SummaryPromptPreset(
                id: academicID,
                name: "学术精读",
                isBuiltIn: true,
                template: """
你是学术助理。用{{lang}}做精读摘要，覆盖：
问题与动机 → 方法/数据 → 主要发现 → 局限或待验证点。
每部分 1～2 句，分行输出，无序号标题。术语准确，必要处保留英文。

标题：{{title}}

内容：{{content}}
"""
            ),
            SummaryPromptPreset(
                id: investmentID,
                name: "投资要点",
                isBuiltIn: true,
                template: """
你是买方分析助理。用{{lang}}提炼投资相关信息（非投资建议）：
- 标的/公司与事件类型（业绩、融资、产品、监管、人事等）
- 对收入、成本、竞争或估值的可能含义
- 关键数字与时间点
- 主要风险与不确定因素
每条一行，3～6 条，无序号，不写「建议买入/卖出」。

标题：{{title}}

内容：{{content}}
"""
            ),
            SummaryPromptPreset(
                id: newsBriefID,
                name: "新闻简报",
                isBuiltIn: true,
                template: """
你是通讯社编辑。用{{lang}}写客观新闻简报（5W1H）：
- 导语：何人、何时、何地、做了什么
- 原因与直接影响（原文有则写）
- 各方立场须归因，勿写成定论
- 连续报道可在首句用极简「前情」
共 3～5 句，每句一行；不用「最近」「据悉」代替原文日期。

标题：{{title}}

内容：{{content}}
"""
            ),
            SummaryPromptPreset(
                id: productReviewID,
                name: "产品评测",
                isBuiltIn: true,
                template: """
你是数码/产品编辑。用{{lang}}整理评测要点：
- 产品定位与核心卖点
- 关键规格/体验结论（性能、续航、影像、系统等有则写）
- 优点与槽点
- 适合谁、不适合谁
每条一行，无序号，不写购买链接话术。

标题：{{title}}

内容：{{content}}
"""
            )
        ]
    }

    init(id: String, name: String, isBuiltIn: Bool, template: String) {
        self.id = id
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.template = template
    }
}

// MARK: - AI Provider

struct AIProvider: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var baseURL: String
    /// 当前默认使用的模型（摘要/翻译/解释等走此模型）
    var model: String
    /// 该 Provider 下可用的模型列表（可多个）；为空时回退为 [model]
    var models: [String] = []
    /// 短文本/便宜路由时使用的模型；空则与 model 相同
    var economyModel: String = ""
    /// 特殊标识：gemini 走 Google Generative Language API，其余走 OpenAI 兼容接口
    var kind: String = "openai" // "openai" | "gemini"
    var isDefaultSummary: Bool = false
    var isDefaultTranslation: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, name, baseURL, model, models, economyModel, kind, isDefaultSummary, isDefaultTranslation
    }

    init(
        id: UUID = UUID(),
        name: String,
        baseURL: String,
        model: String,
        models: [String] = [],
        economyModel: String = "",
        kind: String = "openai",
        isDefaultSummary: Bool = false,
        isDefaultTranslation: Bool = false
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.model = model
        self.models = models
        self.economyModel = economyModel
        self.kind = kind
        self.isDefaultSummary = isDefaultSummary
        self.isDefaultTranslation = isDefaultTranslation
        normalizeModels()
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        baseURL = try c.decode(String.self, forKey: .baseURL)
        model = try c.decode(String.self, forKey: .model)
        models = try c.decodeIfPresent([String].self, forKey: .models) ?? []
        economyModel = try c.decodeIfPresent(String.self, forKey: .economyModel) ?? ""
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "openai"
        isDefaultSummary = try c.decodeIfPresent(Bool.self, forKey: .isDefaultSummary) ?? false
        isDefaultTranslation = try c.decodeIfPresent(Bool.self, forKey: .isDefaultTranslation) ?? false
        if name.lowercased().contains("gemini") { kind = "gemini" }
        normalizeModels()
    }

    /// 去重、去空；保证 model 在列表中且列表非空
    mutating func normalizeModels() {
        var seen = Set<String>()
        var list: [String] = []
        for raw in models + [model] {
            let m = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !m.isEmpty, !seen.contains(m) else { continue }
            seen.insert(m)
            list.append(m)
        }
        if list.isEmpty {
            models = []
            return
        }
        models = list
        if model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !seen.contains(model) {
            model = list[0]
        }
    }

    /// 可选模型（至少包含当前默认 model）
    var availableModels: [String] {
        var p = self
        p.normalizeModels()
        return p.models.isEmpty ? (model.isEmpty ? [] : [model]) : p.models
    }

    /// 使用指定模型的副本（不改动 Provider 默认 model）
    func using(model selected: String) -> AIProvider {
        var p = self
        let m = selected.trimmingCharacters(in: .whitespacesAndNewlines)
        if !m.isEmpty { p.model = m }
        return p
    }

    static let openAITemplate = AIProvider(
        name: "OpenAI",
        baseURL: "https://api.openai.com/v1",
        model: "gpt-4o-mini",
        models: ["gpt-4o-mini", "gpt-4o", "gpt-4.1-mini", "o4-mini"],
        kind: "openai"
    )
    static let anthropicTemplate = AIProvider(
        name: "Anthropic",
        baseURL: "https://api.anthropic.com/v1",
        model: "claude-3-haiku-20240307",
        models: ["claude-3-haiku-20240307", "claude-3-5-haiku-latest", "claude-sonnet-4-20250514"],
        kind: "openai"
    )
    static let geminiTemplate = AIProvider(
        name: "Gemini",
        baseURL: "https://generativelanguage.googleapis.com/v1beta",
        model: "gemini-2.0-flash",
        models: ["gemini-2.0-flash", "gemini-2.5-flash", "gemini-2.5-pro"],
        kind: "gemini"
    )
}

// MARK: - AI Chat

enum ChatRole: String, Codable, Hashable {
    case user
    case assistant
    case system
}

struct ChatMessage: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var role: ChatRole
    var content: String
    var createdAt: Date = Date()
    /// 本条回复使用的 Provider（仅 assistant 有意义）
    var providerID: UUID? = nil
    var providerName: String? = nil
    var isError: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, role, content, createdAt, providerID, providerName, isError
    }

    init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String,
        createdAt: Date = Date(),
        providerID: UUID? = nil,
        providerName: String? = nil,
        isError: Bool = false
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.providerID = providerID
        self.providerName = providerName
        self.isError = isError
    }
}

struct ChatConversation: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var providerID: UUID?
    /// 本会话使用的模型；nil 则用 Provider 默认 model
    var model: String? = nil
    var messages: [ChatMessage] = []
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    /// 系统提示（可选）；空则用默认
    var systemPrompt: String = ""

    enum CodingKeys: String, CodingKey {
        case id, title, providerID, model, messages, createdAt, updatedAt, systemPrompt
    }

    init(
        id: UUID = UUID(),
        title: String = "新对话",
        providerID: UUID? = nil,
        model: String? = nil,
        messages: [ChatMessage] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        systemPrompt: String = ""
    ) {
        self.id = id
        self.title = title
        self.providerID = providerID
        self.model = model
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.systemPrompt = systemPrompt
    }

    var previewText: String {
        messages.last(where: { $0.role == .user || $0.role == .assistant })?.content
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "暂无消息"
    }
}

// MARK: - Keychain (Security.framework; migrates legacy UserDefaults Base64)

enum Keychain {
    private static let service = "com.example.IosRss.keys"
    private static let legacyPrefix = "feed_kc_"

    static func save(key: String, value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        // 同步版（iCloud 钥匙串，换机自动带上 API Key）
        var addSync = query
        addSync[kSecValueData as String] = data
        addSync[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        addSync[kSecAttrSynchronizable as String] = kCFBooleanTrue!
        let syncStatus = SecItemAdd(addSync as CFDictionary, nil)
        if syncStatus != errSecSuccess {
            // 设备不支持 iCloud 钥匙串时回退本机
            var addLocal = query
            addLocal[kSecValueData as String] = data
            addLocal[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            addLocal[kSecAttrSynchronizable as String] = kCFBooleanFalse!
            SecItemAdd(addLocal as CFDictionary, nil)
        }
        UserDefaults.standard.removeObject(forKey: legacyPrefix + key)
    }

    static func load(key: String) -> String? {
        // 先查可同步项，再查本机项
        for sync in [true, false] {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
                kSecAttrSynchronizable as String: sync ? kCFBooleanTrue! : kCFBooleanFalse!
            ]
            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            if status == errSecSuccess, let data = item as? Data,
               let s = String(data: data, encoding: .utf8), !s.isEmpty {
                return s
            }
        }
        // 兼容未写 synchronizable 的旧条目
        let legacyQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(legacyQuery as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data,
           let s = String(data: data, encoding: .utf8), !s.isEmpty {
            // 升级为可同步
            save(key: key, value: s)
            return s
        }
        if let encoded = UserDefaults.standard.string(forKey: legacyPrefix + key),
           let data = Data(base64Encoded: encoded),
           let s = String(data: data, encoding: .utf8), !s.isEmpty {
            save(key: key, value: s)
            return s
        }
        return nil
    }

    static func delete(key: String) {
        for sync in [true, false] {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key,
                kSecAttrSynchronizable as String: sync ? kCFBooleanTrue! : kCFBooleanFalse!
            ]
            SecItemDelete(query as CFDictionary)
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: legacyPrefix + key)
    }
}

// MARK: - Collection helpers

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0, !isEmpty else { return isEmpty ? [] : [self] }
        var result: [[Element]] = []
        result.reserveCapacity((count + size - 1) / size)
        var i = startIndex
        while i < endIndex {
            let j = index(i, offsetBy: size, limitedBy: endIndex) ?? endIndex
            result.append(Array(self[i..<j]))
            i = j
        }
        return result
    }
}

// MARK: - Import result

struct SubscriptionImportResult {
    var added: Int = 0
    var skipped: Int = 0
    var kind: String = "" // "opml" | "rss" | "empty"
}

enum FeedURL {
    static func canonical(_ raw: String) -> String {
        var s = HTMLUtils.decodeEntities(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        s = expandCustomSchemes(s)
        if s.lowercased().hasPrefix("feed://") {
            s = "https://" + String(s.dropFirst(7))
        }
        if s.hasSuffix("/") { s = String(s.dropLast()) }
        return s
    }

    /// `rsshub://zaobao/realtime` → `https://rsshub.app/zaobao/realtime`
    static func expandCustomSchemes(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        guard lower.hasPrefix("rsshub://") || lower.hasPrefix("rsshub:/") else { return trimmed }

        // 去掉 scheme（兼容 rsshub:// 与 rsshub:/）
        var rest: String
        if lower.hasPrefix("rsshub://") {
            rest = String(trimmed.dropFirst("rsshub://".count))
        } else {
            rest = String(trimmed.dropFirst("rsshub:/".count))
        }
        while rest.hasPrefix("/") { rest = String(rest.dropFirst()) }

        // 保留 path + query + fragment
        return rest.isEmpty ? "https://rsshub.app" : "https://rsshub.app/\(rest)"
    }
}
