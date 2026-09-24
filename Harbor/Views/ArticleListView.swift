import SwiftUI

struct ArticleListView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let feed: RSSFeed

    @State private var showAllTranslations = false
    @State private var isTranslatingAll = false
    @State private var isInitialLoading = false
    @State private var translationDone = 0
    @State private var translationTotal = 0
    /// 正在阅读中的文章：保持可见，避免 push 过程中从列表消失导致导航异常
    @State private var readingIDs: Set<UUID> = []
    /// 当前打开的阅读页文章；返回时清空并刷新过滤
    @State private var openedArticleID: UUID?
    /// 本页已尝试自动翻译的文章（避免重复请求）
    @State private var autoTranslateAttemptedIDs: Set<UUID> = []

    /// 列表翻译每批任务数（标题/摘要各一条 job；进度按文章条数计）
    /// 仅用于进度刷新粒度；实际并发由 AppStore.translateTexts 控制
    private let translationBatchSize = 24

    private var articles: [Article] {
        // 显式依赖 openedArticleID / readingIDs / 已读收藏序号，保证标志变更后重新过滤
        let _ = openedArticleID
        let _ = readingIDs
        let _ = store.articleFlagsEpoch
        var all = store.articlesForFeed(feed.id)
        if store.sortByInterestScore && store.smartInterestFilterEnabled {
            all.sort {
                let s0 = $0.interestScore ?? 0.5
                let s1 = $1.interestScore ?? 0.5
                if abs(s0 - s1) > 0.02 { return s0 > s1 }
                return ($0.publishedDate ?? .distantPast) > ($1.publishedDate ?? .distantPast)
            }
        } else {
            // 多数源入库已是新→旧；仅在乱序时排序，减少每次 body 的 O(n log n)
            if !Self.isSortedByDateDescending(all) {
                all.sort { ($0.publishedDate ?? .distantPast) > ($1.publishedDate ?? .distantPast) }
            }
        }
        if store.showReadArticles {
            return all
        }
        return all.filter { article in
            !article.isRead || readingIDs.contains(article.id) || openedArticleID == article.id
        }
    }

    /// 抽样检查是否已按发布时间降序（O(n)，远小于乱序时全量 sort）
    private static func isSortedByDateDescending(_ items: [Article]) -> Bool {
        guard items.count > 1 else { return true }
        var prev = items[0].publishedDate ?? .distantPast
        for i in 1..<items.count {
            let d = items[i].publishedDate ?? .distantPast
            if d > prev { return false }
            prev = d
        }
        return true
    }

    private var liveFeedTitle: String {
        store.feeds.first(where: { $0.id == feed.id })?.title ?? feed.title
    }

    var body: some View {
        List {
            ForEach(articles) { article in
                NavigationLink(value: article) {
                    ArticleRow(article: article, showTranslation: showAllTranslations)
                }
                // 仅用 id + 已读 + 是否显示译文；译文内容变化由 ArticleRow 读最新 article 字段刷新
                // （避免把整段译文塞进 id 导致行身份频繁失效、List 复用失败）
                .id("\(article.id.uuidString)-\(article.isRead)-\(showAllTranslations)-\(article.translatedTitle == nil ? 0 : 1)-\(article.translatedSummary == nil ? 0 : 1)")
                .listRowInsets(EdgeInsets(
                    top: 0,
                    leading: AppLayout.listHorizontalPadding,
                    bottom: 0,
                    trailing: AppLayout.listHorizontalPadding
                ))
                .listRowSeparator(.hidden)
                .swipeActions(edge: .leading) {
                    Button {
                        store.toggleFavorite(article)
                    } label: {
                        Label(article.isFavorite ? "取消收藏" : "收藏",
                              systemImage: article.isFavorite ? "star.slash.fill" : "star.fill")
                    }
                    .tint(.orange)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    if article.isRead {
                        Button {
                            store.markAsUnread(article)
                        } label: {
                            Label("未读", systemImage: "envelope.badge")
                        }
                        .tint(.blue)
                    } else {
                        Button {
                            store.markAsRead(article)
                        } label: {
                            Label("已读", systemImage: "envelope.open")
                        }
                        .tint(.green)
                    }
                    Button(role: .destructive) {
                        store.markNotInterested(article)
                    } label: {
                        Label("不感兴趣", systemImage: "hand.thumbsdown")
                    }
                }
                .contextMenu {
                    Button {
                        store.markNotInterested(article)
                    } label: {
                        Label("不感兴趣", systemImage: "hand.thumbsdown")
                    }
                    if article.isRead {
                        Button { store.markAsUnread(article) } label: {
                            Label("标为未读", systemImage: "envelope.badge")
                        }
                    } else {
                        Button { store.markAsRead(article) } label: {
                            Label("标为已读", systemImage: "envelope.open")
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        // 只跟数量变化动画，避免每次 body 对全表 map(\.id)
        .animation(AppMotion.optional(AppMotion.list, reduceMotion: reduceMotion), value: articles.count)
        .appScreenBackground()
        .navigationTitle(liveFeedTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Article.self) { article in
            ArticleReaderView(article: article, feedID: feed.id)
                .onAppear {
                    openedArticleID = article.id
                    readingIDs.insert(article.id)
                    store.markAsRead(article)
                }
                .onDisappear {
                    // 离开阅读页：清掉占位，列表立刻按已读过滤隐藏
                    if openedArticleID == article.id {
                        openedArticleID = nil
                    }
                    if reduceMotion {
                        readingIDs.remove(article.id)
                    } else {
                        withAnimation(AppMotion.list) {
                            readingIDs.remove(article.id)
                        }
                    }
                }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await toggleTranslateAll() }
                } label: {
                    if isTranslatingAll {
                        ListTranslationChromeProgress()
                    } else {
                        Label(
                            showAllTranslations ? "显示原文" : "翻译列表",
                            systemImage: "translate"
                        )
                        .symbolVariant(showAllTranslations ? .fill : .none)
                    }
                }
                .labelStyle(.iconOnly)
                .accessibilityLabel(showAllTranslations ? "显示原文标题" : "翻译列表")
                .disabled(isTranslatingAll)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    store.markAllAsRead(in: feed.id)
                } label: {
                    Label("全部已读", systemImage: "checklist")
                }
                .labelStyle(.iconOnly)
                .accessibilityLabel("全部已读")
            }
        }
        .overlay {
            if isInitialLoading {
                VStack(spacing: AppSpacing.sm) {
                    ProgressView()
                        .tint(theme.accent)
                    Text("正在加载文章…")
                        .font(AppTypography.body())
                        .foregroundStyle(theme.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.background.opacity(0.92))
            } else if articles.isEmpty {
                ContentUnavailableView {
                    Label {
                        Text(store.showReadArticles ? "暂无文章" : "暂无未读文章")
                            .font(AppTypography.section())
                    } icon: {
                        Image(systemName: "newspaper")
                            .foregroundStyle(theme.muted)
                    }
                } description: {
                    Text(store.showReadArticles
                         ? "下拉刷新，或稍后再来。"
                         : "当前仅显示未读。可在设置中开启「显示已读文章」。")
                    .font(AppTypography.body())
                    .foregroundStyle(theme.muted)
                } actions: {
                    if !store.showReadArticles {
                        Button("显示已读文章") {
                            store.showReadArticles = true
                            store.persistSettings()
                        }
                        .buttonStyle(.bordered)
                        .tint(theme.accent)
                    }
                    Button("刷新") {
                        Task { await store.refreshFeed(feed.id) }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .refreshable {
            // 单源刷新：仍 await 完成后再自动译，避免译到旧列表
            await store.refreshFeed(feed.id)
            await autoTranslatePending(force: true)
        }
        .task(id: feed.id) {
            autoTranslateAttemptedIDs = []
            await loadIfNeeded()
            // 本 feed 已有缓存译文时，打开列表直接显示译文
            let hasCachedTranslation = store.articlesForFeed(feed.id).contains {
                ($0.translatedTitle?.isEmpty == false) || ($0.translatedSummary?.isEmpty == false)
            }
            if hasCachedTranslation {
                showAllTranslations = true
            }
            // 开启自动翻译的源：进入列表即翻译未译条目
            await autoTranslatePending(force: true)
        }
        .onChange(of: articles.count) { _, _ in
            Task { await autoTranslatePending(force: false) }
        }
    }

    /// 第一次打开且本地还没有文章时自动拉取，避免空白列表
    private func loadIfNeeded() async {
        if !store.articlesForFeed(feed.id).isEmpty { return }
        isInitialLoading = true
        await store.refreshFeed(feed.id)
        isInitialLoading = false
    }

    /// 自动翻译：仅处理「未译且非目标中文」的标题 / 摘要
    private func autoTranslatePending(force: Bool) async {
        guard !isTranslatingAll else { return }
        let live = store.feeds.first(where: { $0.id == feed.id })
        let feedEnabled = live?.autoTranslateEnabled ?? false
        guard feedEnabled else { return }
        // 仅翻译当前列表会显示的文章（已隐藏的已读条目跳过）
        let snapshot = store.articlesForFeed(feed.id).filter { article in
            if store.showReadArticles { return true }
            return !article.isRead
                || readingIDs.contains(article.id)
                || openedArticleID == article.id
        }
        var jobs: [ListTranslationJob] = []
        jobs.reserveCapacity(snapshot.count * 2)
        var skipMark: [(id: UUID, title: String?, summary: String?)] = []

        for article in snapshot {
            if !force && autoTranslateAttemptedIDs.contains(article.id) { continue }
            autoTranslateAttemptedIDs.insert(article.id)

            // 语言判定只抽样，避免对全文 content 做 plainText（长文列表 CPU 高）
            let title = article.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let preview = HTMLUtils.plainText(article.summary)
            let langSample = Self.languageSample(title: title, preview: preview, content: article.content)
            let bodyIsTarget = !langSample.isEmpty
                && ListLanguageDetect.isMostlyTarget(langSample, language: store.targetLanguage)

            // 正文已是目标语言：标题/摘要直接标为「已对齐」，不发起翻译
            if bodyIsTarget {
                var tMark: String? = nil
                var sMark: String? = nil
                if article.translatedTitle == nil, !title.isEmpty { tMark = title }
                if article.translatedSummary == nil, !preview.isEmpty { sMark = preview }
                if tMark != nil || sMark != nil {
                    skipMark.append((article.id, tMark, sMark))
                }
                continue
            }

            // 标题（列表展示用；是否需译已由正文语言判定）
            if article.translatedTitle == nil, !title.isEmpty {
                jobs.append(ListTranslationJob(articleID: article.id, field: .title, text: title))
            }

            // 摘要预览
            if article.translatedSummary == nil, !preview.isEmpty {
                jobs.append(ListTranslationJob(articleID: article.id, field: .summary, text: preview))
            }
        }

        if !skipMark.isEmpty {
            store.applyListTranslations(skipMark, persist: jobs.isEmpty)
            showAllTranslations = true
        }
        guard !jobs.isEmpty else {
            if snapshot.contains(where: {
                $0.hasTranslatedBody
                    || ($0.translatedTitle?.isEmpty == false)
                    || ($0.translatedSummary?.isEmpty == false)
            }) {
                showAllTranslations = true
            }
            return
        }

        showAllTranslations = true
        await runTranslationJobs(jobs)
    }

    /// 一次点击：分批翻译所有标题和预览；再次点击切换回原文
    private func toggleTranslateAll() async {
        if showAllTranslations {
            showAllTranslations = false
            return
        }
        showAllTranslations = true

        let snapshot = articles
        var jobs: [ListTranslationJob] = []
        jobs.reserveCapacity(snapshot.count * 2)
        var skipMark: [(id: UUID, title: String?, summary: String?)] = []
        for article in snapshot {
            let title = article.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let preview = HTMLUtils.plainText(article.summary)
            let langSample = Self.languageSample(title: title, preview: preview, content: article.content)
            let bodyIsTarget = !langSample.isEmpty
                && ListLanguageDetect.isMostlyTarget(langSample, language: store.targetLanguage)

            if bodyIsTarget {
                var tMark: String? = nil
                var sMark: String? = nil
                if article.translatedTitle == nil, !title.isEmpty { tMark = title }
                if article.translatedSummary == nil, !preview.isEmpty { sMark = preview }
                if tMark != nil || sMark != nil {
                    skipMark.append((article.id, tMark, sMark))
                }
                continue
            }
            if article.translatedTitle == nil, !title.isEmpty {
                jobs.append(ListTranslationJob(articleID: article.id, field: .title, text: title))
            }
            if article.translatedSummary == nil, !preview.isEmpty {
                jobs.append(ListTranslationJob(articleID: article.id, field: .summary, text: preview))
            }
        }
        if !skipMark.isEmpty {
            store.applyListTranslations(skipMark, persist: jobs.isEmpty)
        }
        guard !jobs.isEmpty else { return }
        await runTranslationJobs(jobs)
    }

    private func runTranslationJobs(_ jobs: [ListTranslationJob]) async {
        let session = store.beginListTranslationSession()
        isTranslatingAll = true
        // 进度按「文章条数」计，不按标题/摘要 job 数
        var remainingJobsByArticle: [UUID: Int] = [:]
        remainingJobsByArticle.reserveCapacity(jobs.count)
        for job in jobs {
            remainingJobsByArticle[job.articleID, default: 0] += 1
        }
        let articleTotal = remainingJobsByArticle.count
        translationDone = 0
        translationTotal = articleTotal
        store.chrome.listTranslationProgressText = "0/\(articleTotal)"

        // 整表一次交给底层并发池，避免「小批串行等待」把并发抵消掉
        // 仍按 batch 切片只为分段刷新进度与列表；批次间不落盘，结束统一 save
        for batch in jobs.chunked(into: translationBatchSize) {
            guard store.isListTranslationSessionActive(session) else {
                isTranslatingAll = false
                translationTotal = 0
                translationDone = 0
                store.saveToStorage()
                return
            }
            let results = await store.translateTexts(batch.map(\.text))
            var updates: [(id: UUID, title: String?, summary: String?)] = []
            updates.reserveCapacity(batch.count)
            for (job, result) in zip(batch, results) {
                if let left = remainingJobsByArticle[job.articleID] {
                    let next = left - 1
                    if next <= 0 {
                        remainingJobsByArticle.removeValue(forKey: job.articleID)
                        translationDone += 1
                        store.chrome.listTranslationProgressText = "\(translationDone)/\(translationTotal)"
                    } else {
                        remainingJobsByArticle[job.articleID] = next
                    }
                }
                guard let result, !result.isEmpty else { continue }
                switch job.field {
                case .title:
                    updates.append((job.articleID, result, nil))
                case .summary:
                    updates.append((job.articleID, nil, result))
                }
            }
            if !updates.isEmpty {
                store.applyListTranslations(updates, persist: false)
            }
        }
        store.saveToStorage()

        isTranslatingAll = false
        translationDone = 0
        store.chrome.listTranslationProgressText = ""
        translationTotal = 0
    }

    /// 语言抽样：优先标题+摘要；正文只取前约 400 字符做 plainText，避免长文列表卡顿
    private static func languageSample(title: String, preview: String, content: String) -> String {
        if !title.isEmpty || !preview.isEmpty {
            let joined = [title, preview].filter { !$0.isEmpty }.joined(separator: "\n")
            // 标题摘要已够长则不必扫正文
            if joined.count >= 40 { return joined }
        }
        let head = content.count > 600 ? String(content.prefix(600)) : content
        let bodyHead = HTMLUtils.plainText(head)
        if bodyHead.count >= 40 { return String(bodyHead.prefix(240)) }
        return [title, preview, bodyHead].filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

/// 列表翻译用：粗判文本是否已是目标中文，避免无谓请求
enum ListLanguageDetect {
    /// 文本是否已接近目标语言（用于跳过翻译）
    /// 简繁分计：简体目标时，繁体正文仍需转换；反之亦然
    static func isMostlyTarget(_ text: String, language: AppLanguage) -> Bool {
        if language == .zhHans {
            guard isMostlyChinese(text) else { return false }
            // 明显偏繁体则不算已是简体目标
            return ChineseScript.detect(text) != .traditional
        }
        if language == .zhHant {
            guard isMostlyChinese(text) else { return false }
            return ChineseScript.detect(text) != .simplified
        }
        if language == .ja { return isMostlyJapanese(text) }
        if language == .ko { return isMostlyKorean(text) }
        // 拉丁系：CJK 占比很低且拉丁字母足够
        return isMostlyLatin(text)
    }

    static func isMostlyJapanese(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        var jp = 0, letters = 0
        for ch in trimmed {
            if ch.isNewline || ch.isWhitespace || ch.isPunctuation || ch.isSymbol || ch.isNumber { continue }
            letters += 1
            if let v = ch.unicodeScalars.first?.value {
                // Hiragana, Katakana, CJK
                if (0x3040...0x30FF).contains(v) || (0x4E00...0x9FFF).contains(v) { jp += 1 }
            }
        }
        guard letters > 0 else { return false }
        return Double(jp) / Double(letters) >= 0.35
    }

    static func isMostlyKorean(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        var ko = 0, letters = 0
        for ch in trimmed {
            if ch.isNewline || ch.isWhitespace || ch.isPunctuation || ch.isSymbol || ch.isNumber { continue }
            letters += 1
            if let v = ch.unicodeScalars.first?.value, (0xAC00...0xD7AF).contains(v) { ko += 1 }
        }
        guard letters > 0 else { return false }
        return Double(ko) / Double(letters) >= 0.35
    }

    static func isMostlyLatin(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        var latin = 0, letters = 0, cjk = 0
        for ch in trimmed {
            if ch.isNewline || ch.isWhitespace || ch.isPunctuation || ch.isSymbol || ch.isNumber { continue }
            letters += 1
            if isCJK(ch) { cjk += 1 }
            else if ch.isLetter { latin += 1 }
        }
        guard letters > 0 else { return false }
        return Double(cjk) / Double(letters) < 0.15 && Double(latin) / Double(letters) >= 0.5
    }

    /// 汉字占比足够高，或短文本中含明显汉字时视为中文
    static func isMostlyChinese(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        var cjk = 0
        var letters = 0
        for ch in trimmed {
            if ch.isNewline || ch.isWhitespace || ch.isPunctuation || ch.isSymbol || ch.isNumber {
                continue
            }
            letters += 1
            if isCJK(ch) { cjk += 1 }
        }
        guard letters > 0 else { return false }
        // 短标题：有 ≥2 个汉字且汉字 ≥ 拉丁字母
        if letters <= 12 {
            return cjk >= 2 && Double(cjk) / Double(letters) >= 0.4
        }
        return Double(cjk) / Double(letters) >= 0.35
    }

    private static func isCJK(_ ch: Character) -> Bool {
        guard let v = ch.unicodeScalars.first?.value else { return false }
        switch v {
        case 0x4E00...0x9FFF,   // CJK Unified
             0x3400...0x4DBF,   // Extension A
             0xF900...0xFAFF,   // Compatibility
             0x3000...0x303F,   // CJK symbols/punct
             0xFF00...0xFFEF:   // Fullwidth
            return true
        default:
            return false
        }
    }
}

// MARK: - 简繁脚本粗判（用于决定是否需要繁简转换）

enum ChineseScript {
    case simplified
    case traditional
    case unknown

    /// 用「仅简 / 仅繁」特征字计数判断；样本过短或中性字过多时返回 unknown
    static func detect(_ text: String) -> ChineseScript {
        let sample = text.count > 800 ? String(text.prefix(800)) : text
        var simp = 0
        var trad = 0
        for ch in sample {
            if simplifiedOnly.contains(ch) { simp += 1 }
            else if traditionalOnly.contains(ch) { trad += 1 }
        }
        let total = simp + trad
        guard total >= 2 else { return .unknown }
        // 一侧明显占优
        if simp >= trad * 2 + 1 { return .simplified }
        if trad >= simp * 2 + 1 { return .traditional }
        if simp > trad { return .simplified }
        if trad > simp { return .traditional }
        return .unknown
    }

    /// 是否需要相对目标语言做繁简转换
    static func needsConversion(text: String, to target: AppLanguage) -> Bool {
        guard target.isChinese, ListLanguageDetect.isMostlyChinese(text) else { return false }
        let script = detect(text)
        switch target {
        case .zhHans: return script == .traditional
        case .zhHant: return script == .simplified
        default: return false
        }
    }

// MARK: - 本地简繁转换（OpenCC 单字表，Apache-2.0）
    // 仅字符级映射（一对多取首选），用于目标为简/繁且正文已是另一侧中文时免调 API

    private static let _stKeys = "㐷㐹㐽㑇㑈㑔㑩㓆㓥㓰㔉㖊㖞㘎㚯㛀㛟㛠㛣㛤㛿㟆㟜㟥㡎㤘㤽㥪㧏㧐㧑㧟㧰㨫㭎㭏㭣㭤㭴㱩㱮㲿㳔㳕㳠㳡㳢㳽㴋㶉㶶㶽㺍㻅㻏㻘䀥䁖䂵䃅䅉䅟䅪䇲䉤䌶䌷䌸䌹䌺䌻䌼䌽䌾䌿䍀䍁䍠䎬䏝䑽䓓䓕䓖䓨䗖䘛䘞䙊䙌䙓䜣䜤䜥䜧䜩䝙䞌䞍䞎䞐䟢䢀䢁䢂䥺䥽䥾䥿䦀䦁䦂䦃䦅䦆䦶䦷䩄䭪䯃䯄䯅䲝䲞䲟䲠䲡䲢䲣䴓䴔䴕䴖䴗䴘䴙䶮万与丑专业丛东丝丢两严丧个丰临为丽举么义乌乐乔习乡书买乱争于亏云亘亚产亩亲亵亸亿仅仆从仑仓仪们价众优伙会伛伞伟传伡伣伤伥伦伧伪伫体余佣佥侠侣侥侦侧侨侩侪侬侭俣俦俨俩俪俫俭债倾偬偻偾偿傤傥傧储傩儿兑兖党兰关兴兹养兽冁内冈册写军农冯冲决况冻净凄准凉减凑凛几凤凫凭凯凶击凿刍划刘则刚创删别刬刭刹刽刾刿剀剂剐剑剥剧劝办务劢动励劲劳势勋勚匀匦匮区医华协单卖占卢卤卧卫却卺厂厅历厉压厌厍厐厕厘厢厣厦厨厩厮县叁参叆叇双发变叙叠台叶号叹叽吁吃后吓吕吗吨听启吴呐呒呓呕呖呗员呙呛呜咏咙咛咝咤咨咸响哑哒哓哔哕哗哙哜哝哟唇唛唝唠唡唢唤啧啬啭啮啯啰啴啸喷喽喾嗫嗳嘘嘤嘱噜嚣团园囱围囵国图圆圣圹场坏块坚坛坜坝坞坟坠垄垅垆垒垦垩垫垭垯垱垲垴埘埙埚堑堕塆墙壮声壳壶壸处备复够头夸夹夺奁奂奋奖奥妆妇妈妩妪妫姗姹娄娅娆娇娈娱娲娴婳婴婵婶媪媭嫒嫔嫱嬷孙学孪宁宝实宠审宪宫宽宾寝对寻导寿将尔尘尝尧尴尸尽层屃屉届属屡屦屿岁岂岖岗岘岚岛岩岭岳岽岿峃峄峡峣峤峥峦峰崂崃崄崭嵘嵚嵝巅巩巯币帅师帏帐帘帜带帧帮帱帻帼幂干并广庄庆床庐庑库应庙庞废庼廪开异弃弑张弥弪弯弹强归当录彟彦彨彻征径徕忆忏忧忾怀态怂怃怄怅怆怜总怼怿恋恒恳恶恸恹恺恻恼恽悦悫悬悭悮悯惊惧惨惩惫惬惭惮惯愠愤愦愿慑慭懑懒懔戆戋戏戗战戬戯户扑执扩扪扫扬扰抚抛抟抠抡抢护报担拟拢拣拥拦拧拨择挂挚挛挜挝挞挟挠挡挢挣挤挥挦捝捞损捡换捣据掳掴掷掸掺掼揽揾揿搀搁搂搄搅携摄摅摆摇摈摊撄撑撵撷撸撺擜擞攒敌敚敛敩数斋斓斗斩断无旧时旷旸昙昵昼昽显晋晒晓晔晕晖暂暅暧术朴机杀杂权杠条来杨杩杰极构枞枢枣枥枧枨枪枫枭柜柠柽栀栅标栈栉栊栋栌栎栏树栖样栾桠桡桢档桤桥桦桧桨桩桪梦梼梾梿检棁棂椁椝椟椠椢椤椫椭椮楼榄榅榇榈榉榝槚槛槟槠横樯樱橥橱橹橼檩欢欤欧歼殁殇残殒殓殚殡殴毁毂毕毙毡毵毶氇气氢氩氲汇汉汤汹沄沟没沣沤沥沦沧沨沩沪泞泪泶泷泸泺泻泼泽泾洁洒洼浃浅浆浇浈浉浊测浍济浏浐浑浒浓浔浕涂涌涚涛涝涞涟涠涡涢涣涤润涧涨涩淀渊渌渍渎渐渑渔渖渗温游湾湿溁溃溅溆溇滗滚滞滟滠满滢滤滥滦滨滩滪潆潇潋潍潜潴澛澜濑濒灏灭灯灵灶灾灿炀炉炖炜炝点炼炽烁烂烃烛烟烦烧烨烩烫烬热焕焖焘煴熏爱爷牍牦牵牺犊状犷犸犹狈狝狞独狭狮狯狰狱狲猃猎猕猡猪猫猬献獭玑玙玚玛玮环现玱玺珐珑珰珲琎琏琐琼瑶瑷瑸璎瓒瓮瓯电画畅畴疖疗疟疠疡疬疭疮疯疱疴痈痉痒痖痨痪痫痴瘅瘆瘗瘘瘪瘫瘾瘿癞癣癫皂皑皱皲盏盐监盖盗盘眍眦眬睁睐睑瞆瞒瞩矫矶矾矿砀码砖砗砚砜砺砻砾础硁硕硖硗硙硚确硵碍碛碜碱礼祃祎祢祯祷祸禀禄禅离秃秆种秘积称秽秾稆税稣稳穑穞穷窃窍窎窑窜窝窥窦窭竖竞笃笋笔笕笺笼笾筑筚筛筜筝筹筼签筿简箓箦箧箨箩箪箫篑篓篮篯篱簖籁籴类籼粜粝粤粪粮粽糁糇糍紧絷緼縆纟纠纡红纣纤纥约级纨纩纪纫纬纭纮纯纰纱纲纳纴纵纶纷纸纹纺纻纼纽纾线绀绁绂练组绅细织终绉绊绋绌绍绎经绐绑绒结绔绕绖绗绘给绚绛络绝绞统绠绡绢绣绤绥绦继绨绩绪绫绬续绮绯绰绱绲绳维绵绶绷绸绹绺绻综绽绾绿缀缁缂缃缄缅缆缇缈缉缊缋缌缍缎缏缐缑缒缓缔缕编缗缘缙缚缛缜缝缞缟缠缡缢缣缤缥缦缧缨缩缪缫缬缭缮缯缰缱缲缳缴缵罂网罗罚罢罴羁羟羡群翘翙翚耢耧耸耻聂聋职聍联聩聪肃肠肤肮肴肾肿胀胁胆胜胧胨胪胫胶脉脍脏脐脑脓脔脚脱脶脸腊腌腘腭腻腼腽腾膑膻臜舆舣舰舱舻艰艳艺节芈芗芜芦苁苇苈苋苌苍苎苏苧苹范茎茏茑茔茕茧荆荐荙荚荛荜荝荞荟荠荡荣荤荥荦荧荨荩荪荫荬荭荮药莅莱莲莳莴莶获莸莹莺莼萚萝萤营萦萧萨葱蒀蒇蒉蒋蒌蒏蓝蓟蓠蓣蓥蓦蔂蔷蔹蔺蔼蕰蕲蕴薮藓藴蘖虏虑虚虫虬虮虱虽虾虿蚀蚁蚂蚃蚕蚝蚬蛊蛎蛏蛮蛰蛱蛲蛳蛴蜕蜗蜡蝇蝈蝉蝎蝼蝾螀螨蟏衅衔补衬衮袄袅袆袜袭袯装裆裈裢裣裤裥褛褴襕见观觃规觅视觇览觉觊觋觌觍觎觏觐觑觞触觯訚詟誉誊讠计订讣认讥讦讧讨让讪讫讬训议讯记讱讲讳讴讵讶讷许讹论讻讼讽设访诀证诂诃评诅识诇诈诉诊诋诌词诎诏诐译诒诓诔试诖诗诘诙诚诛诜话诞诟诠诡询诣诤该详诧诨诩诪诫诬语诮误诰诱诲诳说诵诶请诸诹诺读诼诽课诿谀谁谂调谄谅谆谇谈谉谊谋谌谍谎谏谐谑谒谓谔谕谖谗谘谙谚谛谜谝谞谟谠谡谢谣谤谥谦谧谨谩谪谫谬谭谮谯谰谱谲谳谴谵谶豮贝贞负贠贡财责贤败账货质贩贪贫贬购贮贯贰贱贲贳贴贵贶贷贸费贺贻贼贽贾贿赀赁赂赃资赅赆赇赈赉赊赋赌赍赎赏赐赑赒赓赔赕赖赗赘赙赚赛赜赝赞赟赠赡赢赣赪赵赶趋趱趸跃跄跖跞践跶跷跸跹跻踌踪踬踯蹑蹒蹰蹿躏躜躯輼车轧轨轩轪轫转轭轮软轰轱轲轳轴轵轶轷轸轹轺轻轼载轾轿辀辁辂较辄辅辆辇辈辉辊辋辌辍辎辏辐辑辒输辔辕辖辗辘辙辚辞辟辩辫边辽达迁过迈运还这进远违连迟迩迳迹适选逊递逦逻遗遥邓邝邬邮邹邺邻郁郏郐郑郓郦郧郸酂酝酦酱酽酾酿醖采释里鉴銮錾钅钆钇针钉钊钋钌钍钎钏钐钑钒钓钔钕钖钗钘钙钚钛钜钝钞钟钠钡钢钣钤钥钦钧钨钩钪钫钬钭钮钯钰钱钲钳钴钵钶钷钸钹钺钻钼钽钾钿铀铁铂铃铄铅铆铇铈铉铊铋铌铍铎铏铐铑铒铓铔铕铖铗铘铙铚铛铜铝铞铟铠铡铢铣铤铥铦铧铨铩铪铫铬铭铮铯铰铱铲铳铴铵银铷铸铹铺铻铼铽链铿销锁锂锃锄锅锆锇锈锉锊锋锌锍锎锏锐锑锒锓锔锕锖锗锘错锚锛锜锝锞锟锠锡锢锣锤锥锦锧锨锩锪锫锬锭键锯锰锱锲锳锴锵锶锷锸锹锺锻锼锽锾锿镀镁镂镃镄镅镆镇镈镉镊镋镌镍镎镏镐镑镒镓镔镕镖镗镘镙镚镛镜镝镞镟镠镡镢镣镤镥镦镧镨镩镪镫镬镭镮镯镰镱镲镳镴镵镶长门闩闪闫闬闭问闯闰闱闲闳间闵闶闷闸闹闺闻闼闽闾闿阀阁阂阃阄阅阆阇阈阉阊阋阌阍阎阏阐阑阒阓阔阕阖阗阘阙阚阛队阳阴阵阶际陆陇陈陉陕陦陧陨险随隐隶隽难雇雏雠雳雾霁霉霡霭靓靔静靥鞑鞒鞯鞲韦韧韨韩韪韫韬韵页顶顷顸项顺须顼顽顾顿颀颁颂颃预颅领颇颈颉颊颋颌颍颎颏颐频颒颓颔颕颖颗题颙颚颛颜额颞颟颠颡颢颣颤颥颦颧风飏飐飑飒飓飔飕飖飗飘飙飚飞飨餍饣饤饥饦饧饨饩饪饫饬饭饮饯饰饱饲饳饴饵饶饷饸饹饺饻饼饽饾饿馀馁馂馃馄馅馆馇馈馉馊馋馌馍馎馏馐馑馒馓馔馕马驭驮驯驰驱驲驳驴驵驶驷驸驹驺驻驼驽驾驿骀骁骂骃骄骅骆骇骈骉骊骋验骍骎骏骐骑骒骓骔骕骖骗骘骙骚骛骜骝骞骟骠骡骢骣骤骥骦骧髅髋髌鬓鬶魇魉鱼鱽鱾鱿鲀鲁鲂鲃鲄鲅鲆鲇鲈鲉鲊鲋鲌鲍鲎鲏鲐鲑鲒鲓鲔鲕鲖鲗鲘鲙鲚鲛鲜鲝鲞鲟鲠鲡鲢鲣鲤鲥鲦鲧鲨鲩鲪鲫鲬鲭鲮鲯鲰鲱鲲鲳鲴鲵鲶鲷鲸鲹鲺鲻鲼鲽鲾鲿鳀鳁鳂鳃鳄鳅鳆鳇鳈鳉鳊鳋鳌鳍鳎鳏鳐鳑鳒鳓鳔鳕鳖鳗鳘鳙鳚鳛鳜鳝鳞鳟鳠鳡鳢鳣鳤鸟鸠鸡鸢鸣鸤鸥鸦鸧鸨鸩鸪鸫鸬鸭鸮鸯鸰鸱鸲鸳鸴鸵鸶鸷鸸鸹鸺鸻鸼鸽鸾鸿鹀鹁鹂鹃鹄鹅鹆鹇鹈鹉鹊鹋鹌鹍鹎鹏鹐鹑鹒鹓鹔鹕鹖鹗鹘鹙鹚鹛鹜鹝鹞鹟鹠鹡鹢鹣鹤鹥鹦鹧鹨鹩鹪鹫鹬鹭鹮鹯鹰鹱鹲鹳鹴鹾麦麸麹麺麽黄黉黡黩黪黾鼋鼌鼍鼹齐齑齿龀龁龂龃龄龅龆龇龈龉龊龋龌龙龚龛龟鿎鿏鿒鿔𠀾𠆲𠆿𠇹𠉂𠉗𠋆𠚳𠛅𠛆𠛾𠡠𠮶𠯟𠯠𠰱𠰷𠱞𠲥𠴛𠴢𠵸𠵾𡋀𡋗𡋤𡍣𡒄𡝠𡞋𡞱𡠟𡥧𡭜𡭬𡳃𡳒𡶴𡸃𡺃𡺄𢋈𢗓𢘙𢘝𢘞𢙏𢙐𢙑𢙒𢙓𢛯𢠁𢢐𢧐𢫊𢫞𢫬𢬍𢬦𢭏𢽾𣃁𣆐𣈣𣍨𣍯𣍰𣎑𣏢𣐕𣐤𣑶𣒌𣓿𣔌𣗊𣗋𣗙𣘐𣘓𣘴𣘷𣚚𣞎𣨼𣭤𣯣𣱝𣲗𣲘𣳆𣶩𣶫𣶭𣷷𣸣𣺼𣺽𣽷𤆡𤆢𤇃𤇄𤇭𤇹𤈶𤈷𤊀𤊰𤋏𤎺𤎻𤙯𤝢𤞃𤞤𤠋𤦀𤩽𤳄𤶊𤶧𤻊𤽯𤾀𤿲𥁢𥅘𥅴𥅿𥆧𥇢𥎝𥐟𥐯𥐰𥐻𥞦𥧂𥩟𥩺𥫣𥬀𥬞𥬠𥭉𥮋𥮜𥮾𥱔𥹥𥺅𥺇𦈈𦈉𦈋𦈌𦈎𦈏𦈐𦈑𦈒𦈓𦈔𦈕𦈖𦈗𦈘𦈙𦈚𦈛𦈜𦈝𦈞𦈟𦈠𦈡𦍠𦛨𦝼𦟗𦨩𦰏𦰴𦶟𦶻𦻕𧉐𧉞𧌥𧏖𧏗𧑏𧒭𧜭𧝝𧝧𧮪𧳕𧹑𧹒𧹓𧹔𧹕𧹖𧹗𧿈𨀁𨀱𨁴𨂺𨄄𨅛𨅫𨅬𨉗𨐅𨐆𨐇𨐈𨐉𨐊𨑹𨟳𨠨𨡙𨡺𨤰𨰾𨰿𨱀𨱁𨱂𨱃𨱄𨱅𨱆𨱇𨱈𨱉𨱊𨱋𨱌𨱍𨱎𨱏𨱐𨱑𨱒𨱓𨱔𨱕𨱖𨷿𨸀𨸁𨸂𨸃𨸄𨸅𨸆𨸇𨸉𨸊𨸋𨸌𨸎𨸘𨸟𩏼𩏽𩏾𩏿𩐀𩓋𩖕𩖖𩖗𩙥𩙦𩙧𩙨𩙩𩙪𩙫𩙬𩙭𩙮𩙯𩙰𩟿𩠀𩠁𩠂𩠃𩠅𩠆𩠇𩠈𩠉𩠊𩠋𩠌𩠎𩠏𩠠𩡖𩧦𩧨𩧩𩧪𩧫𩧬𩧭𩧮𩧯𩧰𩧱𩧲𩧳𩧴𩧵𩧶𩧸𩧺𩧻𩧼𩧿𩨀𩨁𩨂𩨃𩨄𩨅𩨆𩨇𩨈𩨉𩨊𩨋𩨌𩨍𩨎𩨏𩨐𩩈𩬣𩬤𩭹𩯒𩰰𩲒𩴌𩽹𩽺𩽻𩽼𩽽𩽾𩽿𩾁𩾂𩾃𩾄𩾅𩾆𩾇𩾈𩾊𩾋𩾌𩾎𪉂𪉃𪉄𪉅𪉆𪉈𪉉𪉊𪉋𪉌𪉍𪉎𪉏𪉐𪉑𪉒𪉔𪉕𪎈𪎉𪎊𪎋𪎌𪑅𪔭𪚏𪚐𪜎𪞝𪟎𪟝𪠀𪠟𪠡𪠳𪠵𪠸𪠺𪠽𪡀𪡃𪡋𪡏𪡛𪡞𪡺𪢌𪢐𪢒𪢕𪢖𪢠𪢮𪢸𪣆𪣒𪣻𪤄𪤚𪥠𪥫𪥰𪥿𪧀𪧘𪨊𪨗𪨧𪨩𪨶𪨷𪨹𪩇𪩎𪩘𪩛𪩷𪩸𪪏𪪑𪪞𪪴𪪼𪫌𪫡𪫷𪫺𪬚𪬯𪭝𪭢𪭧𪭯𪭵𪭾𪮃𪮋𪮖𪮳𪮶𪯋𪰶𪱥𪱷𪲎𪲔𪲛𪲮𪳍𪳗𪴙𪵑𪵣𪵱𪶄𪶒𪶮𪷍𪷽𪸕𪸩𪹀𪹠𪹳𪹹𪺣𪺪𪺭𪺷𪺸𪺻𪺽𪻐𪻨𪻲𪻺𪼋𪼴𪽈𪽝𪽪𪽭𪽮𪽴𪽷𪾔𪾢𪾣𪾦𪾸𪿊𪿞𪿫𪿵𫀌𫀓𫀨𫀬𫀮𫁂𫁟𫁡𫁱𫁲𫁳𫁷𫁺𫂃𫂆𫂈𫂖𫂿𫃗𫄙𫄚𫄛𫄜𫄝𫄞𫄟𫄠𫄡𫄢𫄣𫄤𫄥𫄦𫄧𫄨𫄩𫄪𫄫𫄬𫄭𫄮𫄯𫄰𫄱𫄲𫄳𫄴𫄵𫄶𫄷𫄸𫄹𫅅𫅗𫅥𫅭𫅼𫆏𫆝𫆫𫇘𫇛𫇪𫇭𫇴𫇽𫈉𫈎𫈟𫈵𫉁𫉄𫊪𫊮𫊸𫊹𫊻𫋇𫋌𫋲𫋷𫋹𫋻𫌀𫌇𫌋𫌨𫌪𫌫𫌬𫌭𫌯𫍐𫍙𫍚𫍛𫍜𫍝𫍞𫍟𫍠𫍡𫍢𫍣𫍤𫍥𫍦𫍧𫍨𫍩𫍪𫍫𫍬𫍭𫍮𫍯𫍰𫍱𫍲𫍳𫍴𫍵𫍶𫍷𫍸𫍹𫍺𫍻𫍼𫍽𫍾𫍿𫎆𫎌𫎦𫎧𫎨𫎩𫎪𫎫𫎬𫎭𫎱𫎳𫎸𫎺𫏃𫏆𫏋𫏌𫏐𫏑𫏕𫏞𫏨𫐄𫐅𫐆𫐇𫐈𫐉𫐊𫐋𫐌𫐍𫐎𫐏𫐐𫐑𫐒𫐓𫐔𫐕𫐖𫐗𫐘𫐙𫐷𫑘𫑡𫑷𫓥𫓦𫓧𫓨𫓩𫓪𫓫𫓬𫓭𫓮𫓯𫓰𫓱𫓲𫓳𫓴𫓵𫓶𫓷𫓸𫓹𫓺𫓻𫓼𫓽𫓾𫓿𫔀𫔁𫔂𫔃𫔄𫔅𫔆𫔇𫔈𫔉𫔊𫔋𫔌𫔍𫔎𫔏𫔐𫔑𫔒𫔓𫔔𫔕𫔖𫔭𫔮𫔯𫔰𫔲𫔴𫔵𫔶𫔽𫕚𫕥𫕨𫖃𫖅𫖇𫖑𫖒𫖓𫖔𫖕𫖖𫖪𫖫𫖬𫖭𫖮𫖯𫖰𫖱𫖲𫖳𫖴𫖵𫖶𫖷𫖸𫖹𫖺𫗇𫗈𫗉𫗊𫗋𫗚𫗞𫗟𫗠𫗡𫗢𫗣𫗤𫗥𫗦𫗧𫗨𫗩𫗪𫗫𫗬𫗭𫗮𫗯𫗰𫗱𫗳𫗴𫗵𫘛𫘜𫘝𫘞𫘟𫘠𫘡𫘣𫘤𫘥𫘦𫘧𫘨𫘩𫘪𫘫𫘬𫘭𫘮𫘯𫘰𫘱𫘽𫙂𫚈𫚉𫚊𫚋𫚌𫚍𫚎𫚏𫚐𫚑𫚒𫚓𫚔𫚕𫚖𫚗𫚘𫚙𫚚𫚛𫚜𫚝𫚞𫚟𫚠𫚡𫚢𫚣𫚤𫚥𫚦𫚧𫚨𫚩𫚪𫚫𫚬𫚭𫛚𫛛𫛜𫛝𫛞𫛟𫛠𫛡𫛢𫛣𫛤𫛥𫛦𫛧𫛨𫛩𫛪𫛫𫛬𫛭𫛮𫛯𫛰𫛱𫛲𫛳𫛴𫛵𫛶𫛷𫛸𫛹𫛺𫛻𫛼𫛽𫛾𫜀𫜁𫜂𫜃𫜄𫜅𫜊𫜑𫜒𫜓𫜔𫜕𫜙𫜟𫜨𫜩𫜪𫜫𫜬𫜭𫜮𫜯𫜰𫜲𫜳𫝈𫝋𫝦𫝧𫝨𫝩𫝪𫝫𫝬𫝭𫝮𫝵𫞅𫞗𫞚𫞛𫞝𫞠𫞡𫞢𫞣𫞥𫞦𫞧𫞨𫞩𫞷𫟃𫟄𫟅𫟆𫟇𫟑𫟕𫟞𫟟𫟠𫟡𫟢𫟤𫟥𫟦𫟫𫟬𫟲𫟳𫟴𫟵𫟶𫟷𫟸𫟹𫟺𫟻𫟼𫟽𫟾𫟿𫠀𫠁𫠂𫠅𫠆𫠇𫠈𫠊𫠋𫠌𫠏𫠐𫠑𫠒𫠖𫠜𫢸𫧃𫧮𫫇𫬐𫭟𫭢𫭼𫮃𫰛𫵷𫶇𫷷𫸩𬀩𬀪𬂩𬃊𬇕𬇙𬇹𬉼𬊈𬊤𬍛𬍡𬍤𬒈𬒗𬕂𬘓𬘘𬘡𬘩𬘫𬘬𬘭𬘯𬙂𬙊𬙋𬜬𬜯𬞟𬟁𬟽𬣙𬣞𬣡𬣳𬤇𬤊𬤝𬨂𬨎𬩽𬪩𬬩𬬭𬬮𬬱𬬸𬬹𬬻𬬿𬭁𬭊𬭎𬭚𬭛𬭤𬭩𬭬𬭭𬭯𬭳𬭶𬭸𬭼𬮱𬮿𬯀𬯎𬱖𬱟𬳵𬳶𬳽𬳿𬴂𬴃𬴊𬶋𬶍𬶏𬶐𬶟𬶠𬶨𬶭𬶮𬷕𬸘𬸚𬸣𬸦𬸪𬸯𬹼𬺈𬺓𰬸𰰨𰶎𰻝𰾄𰾭𱊜"
    private static let _stVals = "傌㑶偑㑳倲㑯儸𠗣劏劃劚噚喎㘚㜄媰𡞵𡢃㜏孋𡠹㠏𡾱嵾幓㥮懤慺掆㩳撝擓擽㩜棡椲𣙎樢樫殰殨瀇濧灡澾濄𣾷瀰潚鸂燶煱獱璯𤫩𤪺䁻瞜碽磾稏穇𥢢筴籔䊷紬縳絅䋙䋚綐綵䋻䋹繿繸䍦䎱膞𦪙薵薳藭罃螮𧝞𧜗𧜵䙡襬訢鿁𧩙䜀讌貙𧵳䝼𧶧賰躎𨊰𨊸𨋢釾鏺䥱𨯅𨦫𨧜䥇鐯鐥钁䦛䦟靦𩞯𩣑騧䯀䱽𩶘鮣鰆鰌鰧䱷鳾鵁鴷鶄鶪鷉鸊龑萬與醜專業叢東絲丟兩嚴喪個豐臨爲麗舉麼義烏樂喬習鄉書買亂爭於虧雲亙亞產畝親褻嚲億僅僕從侖倉儀們價衆優夥會傴傘偉傳俥俔傷倀倫傖僞佇體餘傭僉俠侶僥偵側僑儈儕儂儘俁儔儼倆儷倈儉債傾傯僂僨償儎儻儐儲儺兒兌兗黨蘭關興茲養獸囅內岡冊寫軍農馮衝決況凍淨悽準涼減湊凜幾鳳鳧憑凱兇擊鑿芻劃劉則剛創刪別剗剄剎劊㓨劌剴劑剮劍剝劇勸辦務勱動勵勁勞勢勳勩勻匭匱區醫華協單賣佔盧滷臥衛卻巹廠廳歷厲壓厭厙龎廁釐廂厴廈廚廄廝縣叄參靉靆雙發變敘疊臺葉號嘆嘰籲喫後嚇呂嗎噸聽啓吳吶嘸囈嘔嚦唄員咼嗆嗚詠嚨嚀噝吒諮鹹響啞噠嘵嗶噦譁噲嚌噥喲脣嘜嗊嘮啢嗩喚嘖嗇囀齧嘓囉嘽嘯噴嘍嚳囁噯噓嚶囑嚕囂團園囪圍圇國圖圓聖壙場壞塊堅壇壢壩塢墳墜壟壠壚壘墾堊墊埡墶壋塏堖塒壎堝塹墮壪牆壯聲殼壺壼處備復夠頭誇夾奪奩奐奮獎奧妝婦媽嫵嫗嬀姍奼婁婭嬈嬌孌娛媧嫺嫿嬰嬋嬸媼嬃嬡嬪嬙嬤孫學孿寧寶實寵審憲宮寬賓寢對尋導壽將爾塵嘗堯尷屍盡層屓屜屆屬屢屨嶼歲豈嶇崗峴嵐島巖嶺嶽崬巋嶨嶧峽嶢嶠崢巒峯嶗崍嶮嶄嶸嶔嶁巔鞏巰幣帥師幃帳簾幟帶幀幫幬幘幗冪幹並廣莊慶牀廬廡庫應廟龐廢廎廩開異棄弒張彌弳彎彈強歸當錄彠彥彲徹徵徑徠憶懺憂愾懷態慫憮慪悵愴憐總懟懌戀恆懇惡慟懨愷惻惱惲悅愨懸慳悞憫驚懼慘懲憊愜慚憚慣慍憤憒願懾憖懣懶懍戇戔戲戧戰戩戱戶撲執擴捫掃揚擾撫拋摶摳掄搶護報擔擬攏揀擁攔擰撥擇掛摯攣掗撾撻挾撓擋撟掙擠揮撏挩撈損撿換搗據擄摑擲撣摻摜攬搵撳攙擱摟揯攪攜攝攄擺搖擯攤攖撐攆擷擼攛㩵擻攢敵敓斂斆數齋斕鬥斬斷無舊時曠暘曇暱晝曨顯晉曬曉曄暈暉暫𣈶曖術樸機殺雜權槓條來楊榪傑極構樅樞棗櫪梘棖槍楓梟櫃檸檉梔柵標棧櫛櫳棟櫨櫟欄樹棲樣欒椏橈楨檔榿橋樺檜槳樁樳夢檮棶槤檢梲欞槨槼櫝槧槶欏樿橢槮樓欖榲櫬櫚櫸樧檟檻檳櫧橫檣櫻櫫櫥櫓櫞檁歡歟歐殲歿殤殘殞殮殫殯毆毀轂畢斃氈毿𣯶氌氣氫氬氳匯漢湯洶澐溝沒灃漚瀝淪滄渢潙滬濘淚澩瀧瀘濼瀉潑澤涇潔灑窪浹淺漿澆湞溮濁測澮濟瀏滻渾滸濃潯濜塗湧涗濤澇淶漣潿渦溳渙滌潤澗漲澀澱淵淥漬瀆漸澠漁瀋滲溫遊灣溼濚潰濺漵漊潷滾滯灩灄滿瀅濾濫灤濱灘澦瀠瀟瀲濰潛瀦瀂瀾瀨瀕灝滅燈靈竈災燦煬爐燉煒熗點煉熾爍爛烴燭煙煩燒燁燴燙燼熱煥燜燾熅燻愛爺牘犛牽犧犢狀獷獁猶狽獮獰獨狹獅獪猙獄猻獫獵獼玀豬貓蝟獻獺璣璵瑒瑪瑋環現瑲璽琺瓏璫琿璡璉瑣瓊瑤璦璸瓔瓚甕甌電畫暢疇癤療瘧癘瘍癧瘲瘡瘋皰痾癰痙癢瘂癆瘓癇癡癉瘮瘞瘻癟癱癮癭癩癬癲皁皚皺皸盞鹽監蓋盜盤瞘眥矓睜睞瞼瞶瞞矚矯磯礬礦碭碼磚硨硯碸礪礱礫礎硜碩硤磽磑礄確磠礙磧磣鹼禮禡禕禰禎禱禍稟祿禪離禿稈種祕積稱穢穠穭稅穌穩穡穭窮竊竅窵窯竄窩窺竇窶豎競篤筍筆筧箋籠籩築篳篩簹箏籌篔籤篠簡籙簀篋籜籮簞簫簣簍籃籛籬籪籟糴類秈糶糲粵糞糧糉糝餱餈緊縶縕緪糹糾紆紅紂纖紇約級紈纊紀紉緯紜紘純紕紗綱納紝縱綸紛紙紋紡紵紖紐紓線紺紲紱練組紳細織終縐絆紼絀紹繹經紿綁絨結絝繞絰絎繪給絢絳絡絕絞統綆綃絹繡綌綏絛繼綈績緒綾緓續綺緋綽鞝緄繩維綿綬繃綢綯綹綣綜綻綰綠綴緇緙緗緘緬纜緹緲緝縕繢緦綞緞緶線緱縋緩締縷編緡緣縉縛縟縝縫縗縞纏縭縊縑繽縹縵縲纓縮繆繅纈繚繕繒繮繾繰繯繳纘罌網羅罰罷羆羈羥羨羣翹翽翬耮耬聳恥聶聾職聹聯聵聰肅腸膚骯餚腎腫脹脅膽勝朧腖臚脛膠脈膾髒臍腦膿臠腳脫腡臉臘醃膕齶膩靦膃騰臏羶臢輿艤艦艙艫艱豔藝節羋薌蕪蘆蓯葦藶莧萇蒼苧蘇薴蘋範莖蘢蔦塋煢繭荊薦薘莢蕘蓽萴蕎薈薺蕩榮葷滎犖熒蕁藎蓀蔭蕒葒葤藥蒞萊蓮蒔萵薟獲蕕瑩鶯蓴蘀蘿螢營縈蕭薩蔥蒕蕆蕢蔣蔞醟藍薊蘺蕷鎣驀虆薔蘞藺藹薀蘄蘊藪蘚蘊櫱虜慮虛蟲虯蟣蝨雖蝦蠆蝕蟻螞蠁蠶蠔蜆蠱蠣蟶蠻蟄蛺蟯螄蠐蛻蝸蠟蠅蟈蟬蠍螻蠑螿蟎蠨釁銜補襯袞襖嫋褘襪襲襏裝襠褌褳襝褲襉褸襤襴見觀覎規覓視覘覽覺覬覡覿覥覦覯覲覷觴觸觶誾讋譽謄訁計訂訃認譏訐訌討讓訕訖託訓議訊記訒講諱謳詎訝訥許訛論訩訟諷設訪訣證詁訶評詛識詗詐訴診詆謅詞詘詔詖譯詒誆誄試詿詩詰詼誠誅詵話誕詬詮詭詢詣諍該詳詫諢詡譸誡誣語誚誤誥誘誨誑說誦誒請諸諏諾讀諑誹課諉諛誰諗調諂諒諄誶談讅誼謀諶諜謊諫諧謔謁謂諤諭諼讒諮諳諺諦謎諞諝謨讜謖謝謠謗諡謙謐謹謾謫譾謬譚譖譙讕譜譎讞譴譫讖豶貝貞負貟貢財責賢敗賬貨質販貪貧貶購貯貫貳賤賁貰貼貴貺貸貿費賀貽賊贄賈賄貲賃賂贓資賅贐賕賑賚賒賦賭齎贖賞賜贔賙賡賠賧賴賵贅賻賺賽賾贗贊贇贈贍贏贛赬趙趕趨趲躉躍蹌蹠躒踐躂蹺蹕躚躋躊蹤躓躑躡蹣躕躥躪躦軀轀車軋軌軒軑軔轉軛輪軟轟軲軻轤軸軹軼軤軫轢軺輕軾載輊轎輈輇輅較輒輔輛輦輩輝輥輞輬輟輜輳輻輯轀輸轡轅轄輾轆轍轔辭闢辯辮邊遼達遷過邁運還這進遠違連遲邇逕跡適選遜遞邐邏遺遙鄧鄺鄔郵鄒鄴鄰鬱郟鄶鄭鄆酈鄖鄲酇醞醱醬釅釃釀醞採釋裏鑑鑾鏨釒釓釔針釘釗釙釕釷釺釧釤鈒釩釣鍆釹鍚釵鈃鈣鈈鈦鉅鈍鈔鍾鈉鋇鋼鈑鈐鑰欽鈞鎢鉤鈧鈁鈥鈄鈕鈀鈺錢鉦鉗鈷鉢鈳鉕鈽鈸鉞鑽鉬鉭鉀鈿鈾鐵鉑鈴鑠鉛鉚鉋鈰鉉鉈鉍鈮鈹鐸鉶銬銠鉺鋩錏銪鋮鋏鋣鐃銍鐺銅鋁銱銦鎧鍘銖銑鋌銩銛鏵銓鎩鉿銚鉻銘錚銫鉸銥鏟銃鐋銨銀銣鑄鐒鋪鋙錸鋱鏈鏗銷鎖鋰鋥鋤鍋鋯鋨鏽銼鋝鋒鋅鋶鐦鐧銳銻鋃鋟鋦錒錆鍺鍩錯錨錛錡鍀錁錕錩錫錮鑼錘錐錦鑕鍁錈鍃錇錟錠鍵鋸錳錙鍥鍈鍇鏘鍶鍔鍤鍬鍾鍛鎪鍠鍰鎄鍍鎂鏤鎡鐨鎇鏌鎮鎛鎘鑷钂鐫鎳鎿鎦鎬鎊鎰鎵鑌鎔鏢鏜鏝鏍鏰鏞鏡鏑鏃鏇鏐鐔钁鐐鏷鑥鐓鑭鐠鑹鏹鐙鑊鐳鐶鐲鐮鐿鑔鑣鑞鑱鑲長門閂閃閆閈閉問闖閏闈閒閎間閔閌悶閘鬧閨聞闥閩閭闓閥閣閡閫鬮閱閬闍閾閹閶鬩閿閽閻閼闡闌闃闠闊闋闔闐闒闕闞闤隊陽陰陣階際陸隴陳陘陝隯隉隕險隨隱隸雋難僱雛讎靂霧霽黴霢靄靚靝靜靨韃鞽韉韝韋韌韍韓韙韞韜韻頁頂頃頇項順須頊頑顧頓頎頒頌頏預顱領頗頸頡頰頲頜潁熲頦頤頻頮頹頷頴穎顆題顒顎顓顏額顳顢顛顙顥纇顫顬顰顴風颺颭颮颯颶颸颼颻飀飄飆飈飛饗饜飠飣飢飥餳飩餼飪飫飭飯飲餞飾飽飼飿飴餌饒餉餄餎餃餏餅餑餖餓餘餒餕餜餛餡館餷饋餶餿饞饁饃餺餾饈饉饅饊饌饢馬馭馱馴馳驅馹駁驢駔駛駟駙駒騶駐駝駑駕驛駘驍罵駰驕驊駱駭駢驫驪騁驗騂駸駿騏騎騍騅騌驌驂騙騭騤騷騖驁騮騫騸驃騾驄驏驟驥驦驤髏髖髕鬢鬹魘魎魚魛魢魷魨魯魴䰾魺鮁鮃鮎鱸鮋鮓鮒鮊鮑鱟鮍鮐鮭鮚鮳鮪鮞鮦鰂鮜鱠鱭鮫鮮鮺鯗鱘鯁鱺鰱鰹鯉鰣鰷鯀鯊鯇鮶鯽鯒鯖鯪鯕鯫鯡鯤鯧鯝鯢鯰鯛鯨鰺鯴鯔鱝鰈鰏鱨鯷鰮鰃鰓鱷鰍鰒鰉鰁鱂鯿鰠鰲鰭鰨鰥鰩鰟鰜鰳鰾鱈鱉鰻鰵鱅䲁鰼鱖鱔鱗鱒鱯鱤鱧鱣䲘鳥鳩雞鳶鳴鳲鷗鴉鶬鴇鴆鴣鶇鸕鴨鴞鴦鴒鴟鴝鴛鷽鴕鷥鷙鴯鴰鵂鴴鵃鴿鸞鴻鵐鵓鸝鵑鵠鵝鵒鷳鵜鵡鵲鶓鵪鵾鵯鵬鵮鶉鶊鵷鷫鶘鶡鶚鶻鶖鷀鶥鶩鷊鷂鶲鶹鶺鷁鶼鶴鷖鸚鷓鷚鷯鷦鷲鷸鷺䴉鸇鷹鸌鸏鸛鸘鹺麥麩麴麪麼黃黌黶黷黲黽黿鼂鼉鼴齊齏齒齔齕齗齟齡齙齠齜齦齬齪齲齷龍龔龕龜䃮䥑鿓鎶𠁞儣𠌥俓㒓𠏢儭𠠎剾𠞆𪟖勑嗰哯噅㘉嚧囃𡅏𡃕𡄔𡄣㗲𡓾𡑭壗𡔖壈㜷㜗㜢孎孻𡮉𡮣𡳳𦘧嵼𡽗嶈嶘㢝㦛𢤱𢣚𢣭愻憹𢠼憢懀㦎懎𤢻戰𢷮𢶫摋擫𢹿擣斅斸曥𣋋𦢈腪脥臗槫桱欍𣠲楇橯樤樠欓㰙㯤𣞻檭𣝕欘𣠩殢𣯴𣯩氭湋潕㵗澅𣿉𪷓𤅶濆灙𤁣瀃熓㷍爄熌爖熚熉㷿𤒎𤓩熡𤓎𤑳𤛮𤢟獩玁㺏瓕瓛𤳸癐𤸫㿗㿧皟麬䀉𥌃䀹𥊝瞤䁪䂎礒𥖅𥕥碙𥞵𥨐竚𥪂籅䉙籋篘𥵊𥸠䉲篸𥵃𥼽䊭𥽖𥿊緷綇綀繟緍縺緸𦂅䋿縎緰䌈𦃄䌋䌰縬繓䌖繏䌟䌝䌥繻䍽朥膢𦣎𦪽蓧䕳爇𦾟蘟𧕟䗿𧎈蠙蠀蠾𧔥䙱襰𧟀詀𧳟䞈買𧶔賬䝻賟贃𨇁躘𨄣𨅍𨈊𨈌䠱𨇞躝軉軗𨊻𨏠輄𨎮𨏥䢨𨣞𨣧𨢿𨣈𨤻鎷釳𨥛鈠鈋鈲鈯鉁龯銶鋉鍄𨧱錂鏆鎯鍮鎝𨫒鐄鏉鐎鐏𨮂䥩䦳𨳕𨳑閍閐䦘𨴗𨵩𨵸𨶀𨶏𨶲𨶮𨷲𨽏䧢䪏𩏪𩎢䪘䪗顂𩓣顃䫴颰𩗀䬞𩘹𩘀颷颾𩘺𩘝䬘䬝𩙈𩚛𩚥𩚵𩛆𩛩𩟐𩜦䭀䭃𩜇𩜵𩝔餸𩞄𩞦𩠴𩡣𩡺駎𩤊䮾駚𩢡䭿𩢾驋䮝𩥉駧𩢸駩𩢴𩣏𩣫駶𩣵𩣺䮠騔䮞驄騝騪𩤸𩤙䮫騟𩤲騚𩥄𩥑𩥇龭䮳𩧆䯤𩭙𩰀鬖𩯳𩰹𩳤𩴵魥𩵩𩵹鯶𩶱鮟𩶰鯄䲖鮸𩷰𩸃𩸦鯱䱙䱬䱰鱇𩽇䲰鳼𩿪𪀦鴲鴜𪁈鷨𪀾𪁖鵚𪂆𪃏𪃍鷔𪄕𪄆𪇳䴬麲麨䴴麳䵳𪔵𪘀𪘯𠿕凙㔋勣𧷎㓄𠬙唓㖮嚛𠽃噹嘺嘪噞嗹㗿嘳𡃄㘓𡃤𡂡嚽𡅯囒圞墲埬堚塿𡓁壣𧹈孇嬣嬻孾寠㞞屩崙𡸗輋巗𡹬㟺巊巘𡿖幝幩廬㢗廧𢍰彃徿𢤩㦞憸𢣐𢤿𢯷摐擟𢶒掚撊㨻㩋撧𢺳攋㪎曊膹梖櫅欐檵櫠欇𣜬欑毊霼濿溡𤄷𣽏㵾灒熂煇𤑹𤓌爥𤒻𤘀𤜆犞獊𤠮㺜猌瑽瓄瑻璝㻶𤬅畼𤳷痮𤷃㿖𤺔瘱盨睍眝矑矉𥏝𥖲礮𥗇𥜰𥜐䅐䅳𥢷䆉竱鴗𥶽䉑𥯤䉶𥴼簢簂䉬𥴨𥻦𩏷糺䊺紟䋃𥾯䋔絁絙絧絥繷繨纚𦀖綖絺䋦𦅇綟緤緮䋼𦃩縍繬縸縰繂𦅈繈繶纁纗䍤羵𦒀䎙𦔖聻𦟼𦡝𦧺艣𦱌蔿蒭蕽蕳葝蔯蕝薆藷䗅蠦蟜𧒯蟳蟂蟘䙔襗襓襘襀襵𧞫覼覛𧡴𧢄覹䚩𧭹訑訞訜詓諫𧦝𧦧䛄詑譊詷譑誂譨誺誫諣誋䛳誷𧩕誳諴諰諯謏諥謱謸𧩼謉謆謯𧫝譆𧬤譞𧭈譾豵貗贚䝭𧸘賝䞋贉贑䞓䟐䟆𧽯䟃䠆蹳蹻𨂐蹔𨇽𨆪𨇰𨇤軏軕轣軜軷軨軬𨎌軿𨌈輢輖輗輨輷輮𨍰轊轇轐轗轠遱鄟鄳醶釟釨鈇鈛鏦鈆𨥟鉔鉠𨪕銈銊鐈銁𨰋鉾鋠鋗𫒡錽錤鐪錜𨨛錝錥𨨢鍊鐼鍉𨰲鍒鎍䥯鎞鎙𨰃鏥䥗鏾鐇鐍𨬖𨭸𨭖𨮳𨯟鑴𨰥𨲳開閒閗閞𨴹閵䦯闑𨼳𩀨霣𩅙靧䪊鞾𩎖韠𩏂韛韝𩏠𩑔䪴䪾𩒎顗頫䫂䫀䫟頵𩔳𩓥顅𩔑願顣䫶䫻𩗓𩗴䬓飋𩟗飦䬧餦𩚩飵飶𩛌餫餔餗𩛡饠餧餬餪餵餭餱䭔䭑𩝽饘饟馯馼駃駞駊駤駫駻騃騉騊騄騠騜騵騴騱騻䮰驓驙驨鬠𩯁鱮魟鰑鱄魦魵𩶁䱁䱀鮅鮄鮤鮰鰤鮆鮯𩻮鯆鮿鮵䲅𩸄鯬𩸡䱧鯞鰋鯾鰦鰕鰫鰽𩻗𩻬鱊鱢𩼶鱲鳽鳷鴀鴅鴃鸗𩿤鴔鸋鴥鴐鵊鴮𪀖鵧鴳鴽鶰䳜鵟䳤鶭䳢鵫鵰鵩鷤鶌鶒鶦鶗𪃧䳧𪃒䳫鷅𪆷鷐鷩𪅂鷣鷷䴋𪉸麷䴱𪌭䴽𪍠䵴𪓰䶕齧齩𫜦齰齭齴𪙏齾龓䶲㑮𠐊㛝㜐媈嬦𡟫婡嬇孆孄嶹𦠅潣澬㶆灍爧爃𤛱㹽珼璾𤩂璼璊𥢶絍綋綡緟𦆲䖅䕤訨詊譂誴䜖䡐䡩䡵𨞺𨟊釚釲鈖鈗銏鉝鉽鉷䤤銂鐽𨧰𨩰鎈䥄鑉閝韚頍𩖰䫾䮄騼𩦠𩵦魽䱸鱆𩿅齯僤𣍐𪋿噁㘔塸埨𡑍墠娙㠣嵽廞彄暐晛梜櫍澫浿漍熰燖燀瓅璗璕礐𥗽篢紃紞絪綎綄綪綝綧縯纆纕蔄䓣蘋虉蝀訏詝諓詪諲諟譓軝輶鄩醲釴錀鋹釿鉥鉮鑪鉊鉧𨧀鋐錞𨨏鍭鎓鏏鏚䥕𨭎𨭆鏻鐩闉隑隮隤頔頠駓駉駪駼騑騞驎鮈鮀鮠鮡鯻鰊鱀鰶鱚鵏鶠鸑鶱鷟鷭鷿齘齮齼繐菕譅𰻞鋂鑀𪈼"
    private static let _tsKeys = "㑯㑳㑶㓨㗲㘚㜄㜏㜢㠏㠣㥮㩜㩳㩵㺏䁪䁻䃮䊷䋙䋚䋹䋻䍦䎱䓣䙡䜀䝼䡵䥇䥑䥕䥱䦛䦟䧢䮄䯀䰾䱷䱽䲁䲘䴉丟並乾亂亙亞佇佈佔併來侖侶侷俁係俔俠俥俬倀倆倈倉個們倖倫倲偉偑側偵偽傌傑傖傘備傢傭傯傳傴債傷傾僂僅僉僑僕僞僤僥僨僱價儀儁儂億儈儉儎儐儔儕儘償優儲儷儸儺儻儼兇兌兒兗內兩冊冑冪凈凍凜凱別刪剄則剋剎剗剛剝剮剴創剷劃劄劇劉劊劌劍劏劑劚勁動務勛勝勞勢勣勩勱勳勵勸勻匭匯匱區協卹卻卽厙厠厤厭厲厴參叄叢吒吳吶呂咼員唄唸問啓啞啟啢喎喚喪喫喬單喲嗆嗇嗊嗎嗚嗩嗰嗶嘆嘍嘓嘔嘖嘗嘜嘩嘮嘯嘰嘵嘸嘽噁噓噚噝噠噥噦噯噲噴噸噹嚀嚇嚌嚐嚕嚙嚥嚦嚧嚨嚮嚲嚳嚴嚶囀囁囂囅囈囉囌囑囪圇國圍園圓圖團垻埡埨埰執堅堊堖堝堯報場塊塋塏塒塗塚塢塤塵塸塹塿墊墜墠墮墰墳墶墻墾壇壋壎壓壗壘壙壚壜壞壟壠壢壩壪壯壺壼壽夠夢夥夾奐奧奩奪奬奮奼妝姍姦娙娛婁婦婭媧媯媰媼媽嫋嫗嫵嫺嫻嫿嬀嬃嬈嬋嬌嬙嬡嬤嬪嬰嬸孃孋孌孫學孻孿宮寀寢實寧審寫寬寵寶將專尋對導尷屆屍屓屜屢層屨屬岡峯峴島峽崍崑崗崙崢崬嵐嵗嵽嵾嶁嶄嶇嶔嶗嶠嶢嶧嶨嶮嶸嶺嶼嶽巋巒巔巖巘巰巹帥師帳帶幀幃幓幗幘幟幣幫幬幷幹幾庫廁廂廄廈廎廕廚廝廞廟廠廡廢廣廩廬廳弒弔弳張強彄彆彈彌彎彔彙彠彥彫彲彿後徑從徠復徵徹恆恥悅悞悵悶悽惡惱惲惻愛愜愨愴愷愾慄態慍慘慚慟慣慤慪慫慮慳慶慺慼慾憂憊憐憑憒憖憚憤憫憮憲憶懇應懌懍懞懟懣懤懨懲懶懷懸懺懼懾戀戇戔戧戩戰戱戲戶扞拋拚挩挱挾捨捫捱捲掃掄掆掗掙掛採揀揚換揮揯損搖搗搧搵搶摑摜摟摯摳摶摺摻撈撏撐撓撝撟撣撥撫撲撳撻撾撿擁擄擇擊擋擓擔據擠擡擣擬擯擰擱擲擴擷擺擻擼擽擾攄攆攏攔攖攙攛攜攝攢攣攤攪攬敎敓敗敘敵數斂斃斆斕斬斷於旂旣昇時晉晛晝暈暉暐暘暢暫曄曆曇曉曏曖曠曥曨曬書會朥朧朮東枴柵柺査桱桿梔梘梜條梟梲棄棊棖棗棟棡棧棲棶椏椲楊楓楨業極榘榦榪榮榲榿構槍槓槤槧槨槮槳槶槼樁樂樅樑樓標樞樢樣樧樫樳樸樹樺樿橈橋機橢橫橯檁檉檔檜檟檢檣檮檯檳檸檻櫃櫍櫓櫚櫛櫝櫞櫟櫥櫧櫨櫪櫫櫬櫱櫳櫸櫻欄欅權欏欒欓欖欞欽歎歐歟歡歲歷歸歿殘殞殤殨殫殭殮殯殰殲殺殻殼毀毆毿氂氈氌氣氫氬氳氾汎汙決沒沖況泝洩洶浹浿涇涗涼淒淚淥淨淩淪淵淶淺渙減渢渦測渾湊湋湞湧湯溈準溝溫溮溳溼滄滅滌滎滙滬滯滲滷滸滻滾滿漁漊漍漚漢漣漬漲漵漸漿潁潑潔潕潙潚潛潤潯潰潷潿澀澆澇澐澗澠澤澦澩澫澮澱澾濁濃濄濆濕濘濚濛濜濟濤濧濫濰濱濺濼濾瀂瀅瀆瀇瀉瀋瀏瀕瀘瀝瀟瀠瀦瀧瀨瀰瀲瀾灃灄灑灒灕灘灙灝灡灣灤灧灩災為烏烴無煉煒煙煢煥煩煬煱熅熒熗熰熱熲熾燀燁燈燉燒燖燙燜營燦燬燭燴燶燻燼燾爍爐爛爭爲爺爾牀牆牘牴牽犖犛犢犧狀狹狽猙猶猻獁獃獄獅獎獨獪獫獮獰獱獲獵獷獸獺獻獼玀現琱琺琿瑋瑒瑣瑤瑩瑪瑲璉璊璕璗璡璣璦璫璯環璵璸璽璿瓅瓊瓏瓔瓚瓛甌甕產産畝畢畫異畵當疇疊痙痠痾瘂瘋瘍瘓瘞瘡瘧瘮瘲瘺瘻療癆癇癉癒癘癟癡癢癤癥癧癩癬癭癮癰癱癲發皁皚皰皸皺盃盜盞盡監盤盧盪眞眥眾睍睏睜睞瞘瞜瞞瞶瞼矇矓矚矯硃硜硤硨硯碕碩碭碸確碼碽磑磚磠磣磧磯磽磾礄礎礐礙礦礪礫礬礱祕祿禍禎禕禡禦禪禮禰禱禿秈稅稈稏稜稟種稱穀穇穌積穎穠穡穢穩穫穭窩窪窮窯窵窶窺竄竅竇竈竊竪競筆筍筧筴箇箋箏箚節範築篋篔篠篢篤篩篳篸簀簍簑簞簡簣簫簹簽簾籃籅籌籔籙籛籜籟籠籤籩籪籬籮籲粵糉糝糞糧糰糲糴糶糹糾紀紂紃約紅紆紇紈紉紋納紐紓純紕紖紗紘紙級紛紜紝紞紡紬紮細紱紲紳紵紹紺紼紿絀終絃組絅絆絎結絕絛絝絞絡絢給絨絪絰統絲絳絶絹絺綁綃綄綆綈綉綌綎綏綐綑經綖綜綝綞綠綡綢綣綧綪綫綬維綯綰綱網綳綴綵綸綹綺綻綽綾綿緄緇緊緋緑緒緓緔緗緘緙線緝緞締緡緣緦編緩緬緯緱緲練緶緹緻緼縈縉縊縋縐縑縕縗縛縝縞縟縣縧縫縭縮縯縱縲縳縴縵縶縷縹總績繃繅繆繒織繕繚繞繡繢繩繪繫繭繮繯繰繳繶繸繹繻繼繽繾繿纁纆纇纈纊續纍纏纓纔纕纖纘纜缽罃罈罌罎罰罵罷羅羆羈羋羣羥羨義羶習翫翬翹翽耬耮聖聞聯聰聲聳聵聶職聹聽聾肅脅脈脛脣脩脫脹腎腖腡腦腫腳腸膃膕膚膞膠膢膩膽膾膿臉臍臏臘臚臟臠臢臥臨臺與興舉舊舖舘艙艤艦艫艱艷芻苧茲荊莊莖莢莧華菴菸萇萊萬萴萵葉葒葤葦葯葷蒍蒐蒓蒔蒕蒞蒼蓀蓆蓋蓮蓯蓴蓽蔄蔔蔘蔞蔣蔥蔦蔭蔯蔿蕁蕆蕎蕒蕓蕕蕘蕢蕩蕪蕭蕷薀薈薊薌薑薔薘薟薦薩薴薵薹薺藍藎藝藥藪藭藴藶藹藺蘀蘄蘆蘇蘊蘋蘚蘞蘟蘢蘭蘺蘿虆虉處虛虜號虧虯蛺蛻蜆蝀蝕蝟蝦蝨蝸螄螞螢螮螻螿蟄蟈蟎蟣蟬蟯蟲蟳蟶蟻蠁蠅蠆蠍蠐蠑蠔蠟蠣蠨蠱蠶蠻衆衊術衕衚衛衝袞袷裊裏補裝裡製複褌褘褲褳褸褻襀襇襉襏襖襝襠襤襪襬襯襲襴覈見覎規覓視覘覡覥覦親覬覯覲覷覺覽覿觀觴觶觸訁訂訃計訊訌討訏訐訒訓訕訖託記訛訝訟訢訣訥訩訪設許訴訶診註証詀詁詆詎詐詒詔評詖詗詘詛詝詞詠詡詢詣試詩詪詫詬詭詮詰話該詳詵詷詼詿誄誅誆誇誌認誑誒誕誘誚語誠誡誣誤誥誦誨說説誰課誶誹誼誾調諂諄談諉請諍諏諑諒諓論諗諛諜諝諞諟諡諢諤諦諧諫諭諮諱諲諳諴諶諷諸諺諼諾謀謁謂謄謅謊謎謏謐謔謖謗謙謚講謝謠謡謨謫謬謭謳謹謾譁證譎譏譓譖識譙譚譜譞譟譫譭譯議譴護譸譽譾讀讅變讋讌讎讒讓讕讖讚讜讞谿豈豎豐豔豬豶貍貓貙貝貞貟負財貢貧貨販貪貫責貯貰貲貳貴貶買貸貺費貼貽貿賀賁賂賃賄賅資賈賊賑賒賓賕賙賚賜賞賠賡賢賣賤賦賧質賫賬賭賰賴賵賺賻購賽賾贄贅贇贈贊贋贍贏贐贓贔贖贗贛贜赬趕趙趨趲跡踐踰踴蹌蹕蹟蹠蹣蹤蹺躂躉躊躋躍躎躑躒躓躕躚躡躥躦躪軀車軋軌軍軏軑軒軔軛軝軟軤軫軲軸軹軺軻軼軾較輄輅輇輈載輊輋輒輓輔輕輗輛輜輝輞輟輥輦輩輪輬輮輯輳輶輸輻輼輾輿轀轂轄轅轆轉轍轎轔轟轡轢轤辦辭辮辯農迴逕這連週進遊運過達違遙遜遞遠遡適遲遶遷選遺遼邁還邇邊邏邐郟郵鄆鄉鄒鄔鄖鄧鄩鄭鄰鄲鄳鄴鄶鄺酇酈醃醖醜醞醟醣醫醬醱醲釀釁釃釅釋釐釒釓釔釕釗釘釙針釣釤釦釧釩釴釵釷釹釺釾釿鈀鈁鈃鈄鈅鈇鈈鈉鈍鈎鈐鈑鈒鈔鈕鈞鈡鈣鈥鈦鈧鈮鈰鈳鈴鈷鈸鈹鈺鈽鈾鈿鉀鉅鉆鉈鉉鉊鉋鉍鉑鉕鉗鉚鉛鉝鉞鉢鉤鉥鉦鉧鉬鉭鉮鉳鉶鉷鉸鉺鉻鉿銀銃銅銈銍銑銓銖銘銚銛銜銠銣銥銦銨銩銪銫銬銱銳銶銷銹銻銼鋁鋃鋅鋇鋌鋏鋐鋒鋗鋙鋝鋟鋣鋤鋥鋦鋨鋩鋪鋭鋮鋯鋰鋱鋶鋸鋹鋼錀錁錄錆錇錈錏錐錒錕錘錙錚錛錞錟錠錡錢錤錦錨錩錫錮錯録錳錶錸錼鍀鍁鍃鍅鍆鍇鍈鍊鍋鍍鍔鍘鍚鍛鍠鍤鍥鍩鍬鍭鍰鍵鍶鍺鍼鍾鎂鎄鎇鎊鎌鎓鎔鎖鎘鎚鎛鎝鎡鎢鎣鎦鎧鎩鎪鎬鎭鎮鎰鎲鎳鎵鎶鎸鎿鏃鏇鏈鏌鏍鏏鏐鏑鏗鏘鏜鏝鏞鏟鏡鏢鏤鏨鏰鏵鏷鏹鏺鏻鏽鐃鐄鐇鐋鐍鐏鐐鐒鐓鐔鐘鐙鐝鐠鐥鐦鐧鐨鐩鐫鐮鐯鐲鐳鐵鐶鐸鐺鐽鐿鑄鑊鑌鑑鑒鑔鑕鑞鑠鑣鑥鑪鑭鑰鑱鑲鑷鑹鑼鑽鑾鑿钁钂長門閂閃閆閈閉開閌閎閏閑閒間閔閘閡閣閤閥閨閩閫閬閭閱閲閶閹閻閼閽閾閿闃闆闇闈闉闊闋闌闍闐闑闒闓闔闕闖關闞闠闡闢闤闥陘陝陞陣陰陳陸陽隉隊階隑隕際隤隨險隮隯隱隴隸隻雋雖雙雛雜雞離難雲電霑霢霧霽靂靄靆靈靉靚靜靝靦靨鞏鞝鞦鞽韁韃韆韉韋韌韍韓韙韜韝韞韻響頁頂頃項順頇須頊頌頍頎頏預頑頒頓頔頗領頜頠頡頤頦頫頭頮頰頲頴頵頷頸頹頻頽顆題額顎顏顒顓顔顗願顙顛類顢顥顧顫顬顯顰顱顳顴風颭颮颯颱颳颶颸颺颻颼飀飄飆飈飛飠飢飣飥飩飪飫飭飯飱飲飴飼飽飾飿餃餄餅餈餉養餌餎餏餑餒餓餕餖餗餘餚餛餜餞餡館餬餱餳餵餶餷餸餺餼餾餿饁饃饅饈饉饊饋饌饑饒饗饘饜饞饢馬馭馮馱馳馴馹馼駁駃駉駐駑駒駓駔駕駘駙駛駝駟駡駢駪駭駰駱駸駼駿騁騂騄騅騊騌騍騎騏騑騖騙騞騠騤騧騫騭騮騰騱騵騶騷騸騾驀驁驂驃驄驅驊驌驍驎驏驕驗驚驛驟驢驤驥驦驪驫骯髏髒體髕髖髮鬆鬍鬚鬢鬥鬧鬨鬩鬮鬱鬹魎魘魚魛魟魢魨魯魴魷魺鮀鮁鮃鮆鮈鮊鮋鮍鮎鮐鮑鮒鮓鮚鮜鮝鮞鮟鮠鮡鮣鮦鮪鮫鮭鮮鮳鮶鮸鮺鯀鯁鯇鯉鯊鯒鯔鯕鯖鯗鯛鯝鯡鯢鯤鯧鯨鯪鯫鯰鯴鯷鯻鯽鯿鰁鰂鰃鰆鰈鰉鰊鰌鰍鰏鰐鰒鰓鰛鰜鰟鰠鰣鰤鰥鰧鰨鰩鰭鰮鰱鰲鰳鰵鰶鰷鰹鰺鰻鰼鰾鱀鱂鱅鱇鱈鱉鱒鱔鱖鱗鱘鱚鱝鱟鱠鱣鱤鱧鱨鱭鱯鱲鱷鱸鱺鳥鳧鳩鳬鳲鳳鳴鳶鳾鴆鴇鴉鴒鴕鴛鴝鴞鴟鴣鴦鴨鴯鴰鴴鴷鴻鴿鵁鵂鵃鵏鵐鵑鵒鵓鵜鵝鵟鵠鵡鵪鵬鵮鵯鵰鵲鵷鵾鶄鶇鶉鶊鶓鶖鶘鶚鶠鶡鶥鶩鶪鶬鶯鶱鶲鶴鶹鶺鶻鶼鶿鷀鷁鷂鷄鷉鷊鷓鷖鷗鷙鷚鷟鷥鷦鷫鷭鷯鷲鷳鷴鷸鷹鷺鷽鸂鸇鸊鸌鸏鸑鸕鸘鸚鸛鸝鸞鹵鹹鹺鹼鹽麗麥麩麪麫麬麯麳麴麵麼麽黃黌點黨黲黴黶黷黽黿鼂鼉鼕鼴齊齋齎齏齒齔齕齗齘齙齜齟齠齡齣齦齧齪齬齮齯齲齶齷齼龍龎龐龑龔龕龜鿁鿓𠁞𠗣𡃕𡅏𡑍𡑭𡓾𡔖𡞵𡠹𡢃𡮉𡮣𡳳𡻕𡾱𢣚𢶫𢹿𣈶𣙎𣞻𣠩𣠲𣯶𣾷𤁣𤅶𤓩𤪺𤫩𤳸𥊝𥌃𥕥𥖅𥗽𥢢𥸠𥼽𦘧𦣎𦪙𧜗𧜵𧝞𧟀𧩙𧵳𧶧𨊰𨊸𨋢𨤻𨦫𨧀𨧜𨨏𨭆𨭎𨯅𩞯𩠴𩣑𩶘𰻞"
    private static let _tsVals = "㑔㑇㐹刾𠵾㘎㚯㛣𡞱㟆𫵷㤘㨫㧐擜𤠋𥇢䀥鿎䌶䌺䌻䌿䌾䍠䎬𬜯䙌䜧䞍𫟦䦂鿏𬭯䥾䦶䦷𨸟𫠊䯅鲃䲣䲝鳚鳤鹮丢并干乱亘亚伫布占并来仑侣局俣系伣侠伡私伥俩俫仓个们幸伦㑈伟㐽侧侦伪㐷杰伧伞备家佣偬传伛债伤倾偻仅佥侨仆伪𫢸侥偾雇价仪俊侬亿侩俭傤傧俦侪尽偿优储俪㑩傩傥俨凶兑儿兖内两册胄幂净冻凛凯别删刭则克刹刬刚剥剐剀创铲划札剧刘刽刿剑㓥剂㔉劲动务勋胜劳势𪟝勚劢勋励劝匀匦汇匮区协恤却即厍厕历厌厉厣参叁丛咤吴呐吕呙员呗念问启哑启唡㖞唤丧吃乔单哟呛啬唝吗呜唢𠮶哔叹喽啯呕啧尝唛哗唠啸叽哓呒啴恶嘘㖊咝哒哝哕嗳哙喷吨当咛吓哜尝噜啮咽呖𠰷咙向亸喾严嘤啭嗫嚣冁呓啰苏嘱囱囵国围园圆图团坝垭𫭢采执坚垩垴埚尧报场块茔垲埘涂冢坞埙尘𫭟堑𪣻垫坠𫮃堕坛坟垯墙垦坛垱埙压𡋤垒圹垆坛坏垄垅坜坝塆壮壶壸寿够梦伙夹奂奥奁夺奖奋姹妆姗奸𫰛娱娄妇娅娲妫㛀媪妈袅妪妩娴娴婳妫媭娆婵娇嫱嫒嬷嫔婴婶娘㛤娈孙学𡥧孪宫采寝实宁审写宽宠宝将专寻对导尴届尸屃屉屡层屦属冈峰岘岛峡崃昆岗仑峥岽岚岁𫶇㟥嵝崭岖嵚崂峤峣峄峃崄嵘岭屿岳岿峦巅岩𪩘巯卺帅师帐带帧帏㡎帼帻帜币帮帱并干几库厕厢厩厦庼荫厨厮𫷷庙厂庑废广廪庐厅弑吊弪张强𫸩别弹弥弯录汇彟彦雕彨佛后径从徕复征彻恒耻悦悮怅闷凄恶恼恽恻爱惬悫怆恺忾栗态愠惨惭恸惯悫怄怂虑悭庆㥪戚欲忧惫怜凭愦慭惮愤悯怃宪忆恳应怿懔蒙怼懑㤽恹惩懒怀悬忏惧慑恋戆戋戗戬战戯戏户捍抛拼捝挲挟舍扪挨卷扫抡㧏挜挣挂采拣扬换挥搄损摇捣扇揾抢掴掼搂挚抠抟折掺捞挦撑挠㧑挢掸拨抚扑揿挞挝捡拥掳择击挡㧟担据挤抬捣拟摈拧搁掷扩撷摆擞撸㧰扰摅撵拢拦撄搀撺携摄攒挛摊搅揽教敚败叙敌数敛毙敩斓斩断于旗既升时晋𬀪昼晕晖𬀩旸畅暂晔历昙晓向暧旷𣆐昽晒书会𦛨胧术东拐栅拐查𣐕杆栀枧𬂩条枭棁弃棋枨枣栋㭎栈栖梾桠㭏杨枫桢业极矩干杩荣榅桤构枪杠梿椠椁椮桨椢椝桩乐枞梁楼标枢㭤样榝㭴桪朴树桦椫桡桥机椭横𣓿檩柽档桧槚检樯梼台槟柠槛柜𬃊橹榈栉椟橼栎橱槠栌枥橥榇蘖栊榉樱栏榉权椤栾𣗋榄棂钦叹欧欤欢岁历归殁残殒殇㱮殚僵殓殡㱩歼杀壳壳毁殴毵牦毡氇气氢氩氲泛泛污决没冲况溯泄汹浃𬇙泾涚凉凄泪渌净凌沦渊涞浅涣减沨涡测浑凑𣲗浈涌汤沩准沟温浉涢湿沧灭涤荥汇沪滞渗卤浒浐滚满渔溇𬇹沤汉涟渍涨溆渐浆颍泼洁𣲘沩㴋潜润浔溃滗涠涩浇涝沄涧渑泽滪泶𬇕浍淀㳠浊浓㳡𣸣湿泞溁蒙浕济涛㳔滥潍滨溅泺滤澛滢渎㲿泻沈浏濒泸沥潇潆潴泷濑弥潋澜沣滠洒𪷽漓滩𣺼灏㳕湾滦滟滟灾为乌烃无炼炜烟茕焕烦炀㶽煴荧炝𬉼热颎炽𬊤烨灯炖烧𬊈烫焖营灿毁烛烩㶶熏烬焘烁炉烂争为爷尔床墙牍抵牵荦牦犊牺状狭狈狰犹狲犸呆狱狮奖独狯猃狝狞㺍获猎犷兽獭献猕猡现雕珐珲玮玚琐瑶莹玛玱琏𫞩𬍤𬍡琎玑瑷珰㻅环玙瑸玺璇𬍛琼珑璎瓒𤩽瓯瓮产产亩毕画异画当畴叠痉酸疴痖疯疡痪瘗疮疟瘆疭瘘瘘疗痨痫瘅愈疠瘪痴痒疖症疬癞癣瘿瘾痈瘫癫发皂皑疱皲皱杯盗盏尽监盘卢荡真眦众𪾢困睁睐眍䁖瞒瞆睑蒙眬瞩矫朱硁硖砗砚埼硕砀砜确码䂵硙砖硵碜碛矶硗䃅硚础𬒈碍矿砺砾矾砻秘禄祸祯祎祃御禅礼祢祷秃籼税秆䅉棱禀种称谷䅟稣积颖秾穑秽稳获穞窝洼穷窑窎窭窥窜窍窦灶窃竖竞笔笋笕䇲个笺筝札节范筑箧筼筿𬕂笃筛筚𥮾箦篓蓑箪简篑箫筜签帘篮𥫣筹䉤箓篯箨籁笼签笾簖篱箩吁粤粽糁粪粮团粝籴粜纟纠纪纣𬘓约红纡纥纨纫纹纳纽纾纯纰纼纱纮纸级纷纭纴𬘘纺䌷扎细绂绁绅纻绍绀绋绐绌终弦组䌹绊绗结绝绦绔绞络绚给绒𬘡绖统丝绛绝绢𫄨绑绡𬘫绠绨绣绤𬘩绥䌼捆经𫄧综𬘭缍绿𫟅绸绻𬘯𬘬线绶维绹绾纲网绷缀彩纶绺绮绽绰绫绵绲缁紧绯绿绪绬绱缃缄缂线缉缎缔缗缘缌编缓缅纬缑缈练缏缇致缊萦缙缢缒绉缣缊缞缚缜缟缛县绦缝缡缩𬙂纵缧䌸纤缦絷缕缥总绩绷缫缪缯织缮缭绕绣缋绳绘系茧缰缳缲缴𫄷䍁绎𦈡继缤缱䍀𫄸𬙊颣缬纩续累缠缨才𬙋纤缵缆钵䓨坛罂坛罚骂罢罗罴羁芈群羟羡义膻习玩翚翘翙耧耢圣闻联聪声耸聩聂职聍听聋肃胁脉胫唇修脱胀肾胨脶脑肿脚肠腽腘肤䏝胶𦝼腻胆脍脓脸脐膑腊胪脏脔臜卧临台与兴举旧铺馆舱舣舰舻艰艳刍苎兹荆庄茎荚苋华庵烟苌莱万荝莴叶荭荮苇药荤𫇭搜莼莳蒀莅苍荪席盖莲苁莼荜𬜬卜参蒌蒋葱茑荫𫈟𫇭荨蒇荞荬芸莸荛蒉荡芜萧蓣蕰荟蓟芗姜蔷荙莶荐萨苧䓓苔荠蓝荩艺药薮䓖蕴苈蔼蔺萚蕲芦苏蕴苹藓蔹𦻕茏兰蓠萝蔂𬟁处虚虏号亏虬蛱蜕蚬𬟽蚀猬虾虱蜗蛳蚂萤䗖蝼螀蛰蝈螨虮蝉蛲虫𫊻蛏蚁蚃蝇虿蝎蛴蝾蚝蜡蛎蟏蛊蚕蛮众蔑术同胡卫冲衮夹袅里补装里制复裈袆裤裢褛亵𫌀裥裥袯袄裣裆褴袜摆衬袭襕核见觃规觅视觇觋觍觎亲觊觏觐觑觉览觌观觞觯触讠订讣计讯讧讨𬣙讦讱训讪讫托记讹讶讼䜣诀讷讻访设许诉诃诊注证𧮪诂诋讵诈诒诏评诐诇诎诅𬣞词咏诩询诣试诗𬣳诧诟诡诠诘话该详诜𫍣诙诖诔诛诓夸志认诳诶诞诱诮语诚诫诬误诰诵诲说说谁课谇诽谊訚调谄谆谈诿请诤诹诼谅𬣡论谂谀谍谞谝𬤊谥诨谔谛谐谏谕咨讳𬤇谙𫍯谌讽诸谚谖诺谋谒谓誊诌谎谜𫍲谧谑谡谤谦谥讲谢谣谣谟谪谬谫讴谨谩哗证谲讥𬤝谮识谯谭谱𫍽噪谵毁译议谴护诪誉谫读谉变詟䜩雠谗让谰谶赞谠谳溪岂竖丰艳猪豮狸猫䝙贝贞贠负财贡贫货贩贪贯责贮贳赀贰贵贬买贷贶费贴贻贸贺贲赂赁贿赅资贾贼赈赊宾赇赒赉赐赏赔赓贤卖贱赋赕质赍账赌䞐赖赗赚赙购赛赜贽赘赟赠赞赝赡赢赆赃赑赎赝赣赃赪赶赵趋趱迹践逾踊跄跸迹跖蹒踪跷跶趸踌跻跃䟢踯跞踬蹰跹蹑蹿躜躏躯车轧轨军𫐄轪轩轫轭𬨂软轷轸轱轴轵轺轲轶轼较𨐈辂辁辀载轾𪨶辄挽辅轻𫐐辆辎辉辋辍辊辇辈轮辌𫐓辑辏𬨎输辐辒辗舆辒毂辖辕辘转辙轿辚轰辔轹轳办辞辫辩农回径这连周进游运过达违遥逊递远溯适迟绕迁选遗辽迈还迩边逻逦郏邮郓乡邹邬郧邓𬩽郑邻郸𫑡邺郐邝酂郦腌酝丑酝蒏糖医酱酦𬪩酿衅酾酽释厘钅钆钇钌钊钉钋针钓钐扣钏钒𬬩钗钍钕钎䥺𬬱钯钫钘钭钥𫓧钚钠钝钩钤钣钑钞钮钧钟钙钬钛钪铌铈钶铃钴钹铍钰钸铀钿钾巨钻铊铉𬬿铇铋铂钷钳铆铅𫟷钺钵钩𬬸钲𬭁钼钽𬬹锫铏𫟹铰铒铬铪银铳铜𫓯铚铣铨铢铭铫铦衔铑铷铱铟铵铥铕铯铐铞锐𨱇销锈锑锉铝锒锌钡铤铗𬭎锋𫓶铻锊锓铘锄锃锔锇铓铺锐铖锆锂铽锍锯𬬮钢𬬭锞录锖锫锩铔锥锕锟锤锱铮锛𬭚锬锭锜钱𫓹锦锚锠锡锢错录锰表铼镎锝锨锪钫钔锴锳炼锅镀锷铡钖锻锽锸锲锘锹𬭤锾键锶锗针钟镁锿镅镑镰𬭩镕锁镉锤镈𨱏镃钨蓥镏铠铩锼镐镇镇镒镋镍镓鿔镌镎镞旋链镆镙𬭬镠镝铿锵镗镘镛铲镜镖镂錾镚铧镤镪䥽𬭸锈铙𨱑𫔍铴𫔎𨱔镣铹镦镡钟镫镢镨䦅锎锏镄𬭼镌镰䦃镯镭铁镮铎铛𫟼镱铸镬镔鉴鉴镲锧镴铄镳镥𬬻镧钥镵镶镊镩锣钻銮凿镢镋长门闩闪闫闬闭开闶闳闰闲闲间闵闸阂阁合阀闺闽阃阆闾阅阅阊阉阎阏阍阈阌阒板暗闱𬮱阔阕阑阇阗𫔶阘闿阖阙闯关阚阓阐辟阛闼陉陕升阵阴陈陆阳陧队阶𬮿陨际𬯎随险𬯀陦隐陇隶只隽虽双雏杂鸡离难云电沾霡雾霁雳霭叇灵叆靓静靔腼靥巩绱秋鞒缰鞑千鞯韦韧韨韩韪韬鞲韫韵响页顶顷项顺顸须顼颂𫠆颀颃预顽颁顿𬱖颇领颌𬱟颉颐颏𫖯头颒颊颋颕𫖳颔颈颓频颓颗题额颚颜颙颛颜𫖮愿颡颠类颟颢顾颤颥显颦颅颞颧风飐飑飒台刮飓飔飏飖飕飗飘飙飚飞饣饥饤饦饨饪饫饬饭飧饮饴饲饱饰饳饺饸饼糍饷养饵饹饻饽馁饿馂饾𫗧余肴馄馃饯馅馆糊糇饧喂馉馇𩠌馎饩馏馊馌馍馒馐馑馓馈馔饥饶飨𫗴餍馋馕马驭冯驮驰驯驲𫘜驳𫘝𬳶驻驽驹𬳵驵驾骀驸驶驼驷骂骈𬳽骇骃骆骎𬳿骏骋骍𫘧骓𫘦骔骒骑骐𬴂骛骗𬴃𫘨骙䯄骞骘骝腾𫘬𫘪驺骚骟骡蓦骜骖骠骢驱骅骕骁𬴊骣骄验惊驿骤驴骧骥骦骊骉肮髅脏体髌髋发松胡须鬓斗闹哄阋阄郁鬶魉魇鱼鱽𫚉鱾鲀鲁鲂鱿鲄𬶍鲅鲆𫚖𬶋鲌鲉鲏鲇鲐鲍鲋鲊鲒鲘鲞鲕𩽾𬶏𬶐䲟鲖鲔鲛鲑鲜鲓鲪𩾃鲝鲧鲠鲩鲤鲨鲬鲻鲯鲭鲞鲷鲴鲱鲵鲲鲳鲸鲮鲰鲶鲺鳀𬶟鲫鳊鳈鲗鳂䲠鲽鳇𬶠䲡鳅鲾鳄鳆鳃鳁鳒鳑鳋鲥𫚕鳏䲢鳎鳐鳍鳁鲢鳌鳓鳘𬶭鲦鲣鲹鳗鳛鳔𬶨鳉鳙𩾌鳕鳖鳟鳝鳜鳞鲟𬶮鲼鲎鲙鳣鳡鳢鲿鲚鳠𫚭鳄鲈鲡鸟凫鸠凫鸤凤鸣鸢䴓鸩鸨鸦鸰鸵鸳鸲鸮鸱鸪鸯鸭鸸鸹鸻䴕鸿鸽䴔鸺鸼𬷕鹀鹃鹆鹁鹈鹅𫛭鹄鹉鹌鹏鹐鹎雕鹊鹓鹍䴖鸫鹑鹒鹋鹙鹕鹗𬸘鹖鹛鹜䴗鸧莺𬸣鹟鹤鹠鹡鹘鹣鹚鹚鹢鹞鸡䴘鹝鹧鹥鸥鸷鹨𬸦鸶鹪鹔𬸪鹩鹫鹇鹇鹬鹰鹭鸴㶉鹯䴙鹱鹲𬸚鸬鹴鹦鹳鹂鸾卤咸鹾碱盐丽麦麸面面𤿲曲𪎌曲面么么黄黉点党黪霉黡黩黾鼋鼌鼍冬鼹齐斋赍齑齿龀龁龂𬹼龅龇龃龆龄出龈啮龊龉𬺈𫠜龋腭龌𬺓龙厐庞䶮龚龛龟䜤鿒𠀾㓆𠴛𠲥𫭼𡋗𡋀𡍣㛟㛿㛠𡭜𡭬𡳃岁㟜𢘝𢫞𢬦暅㭣𣘓𣞎𣑶毶㳢𣺽𣷷𤊰㻘㻏𤳄𥅿𥅘𥐰𥐯𬒗䅪𥮋𥹥𡳒𦟗䑽䘞䙊䘛𧝧䜥䞌䞎䢀䢁䢂𨤰䦀𬭊䦁𬭛𬭶𬭳䥿䭪𩠠䯃䲞𰻝"

    private static let simpToTrad: [Character: Character] = {
        var d: [Character: Character] = [:]
        d.reserveCapacity(_stKeys.count)
        for (a, b) in zip(_stKeys, _stVals) { d[a] = b }
        return d
    }()

    private static let tradToSimp: [Character: Character] = {
        var d: [Character: Character] = [:]
        d.reserveCapacity(_tsKeys.count)
        for (a, b) in zip(_tsKeys, _tsVals) { d[a] = b }
        return d
    }()

    /// 将文本就地转为目标简/繁。非中文目标或无需转换时原样返回。
    static func convert(_ text: String, to target: AppLanguage) -> String {
        guard target.isChinese, !text.isEmpty else { return text }
        let map: [Character: Character]
        switch target {
        case .zhHans: map = tradToSimp
        case .zhHant: map = simpToTrad
        default: return text
        }
        var out = String()
        out.reserveCapacity(text.count)
        for ch in text {
            out.append(map[ch] ?? ch)
        }
        return out
    }

    // 高频「仅简 / 仅繁」特征字（非穷尽，够用粗判）
    private static let simplifiedOnly: Set<Character> = Set(
        "国东门车马龙过这来时对会发点开关从众专与书买乱争产亲亿们传体优储儿党兰兴养写农冲决况净准凤凯划刚创删剂剑剧劝办务动劳势勋汇汉洁浇浊测济浑浓润涨渔渗滚满滥滨滤灭灯灿烦烧热爱牵牺独现环说语请让认议记许识译证话广庆应厅历压县参双变处备复妇妈孙学宁实审宽宾寻导将尘尽层岛帅师帐带帮干后边达运还进远连迟选护报拥拦拨择挂挡挣挤挥损换据捞摇摊摆摄敌数斩时晋晓术机杀杂权条杨极构柜样档桥楼欢岁残段毕气汇汤沟没浅涂涌涛涝淀游满濑激烂爷猎现画疮疯盐监盘睁确碍矿码砖础种积称稳穷窗竞笼简签类粮纠红纤约级纯纲纳纵纷纸纺练组细织终经结绕绘给络绝统继绩续绳维绿缓编缘缝缠缩网罗罚罢聋职联聪肠肤胆艺节苏药获蓝虽蚁蝇见观视览觉计订训讯讲论设访评词试诗读调谈贝负责败账货质贪购贱贵贷贸费贺贼资赌赏赔赚赞赠赢赵赶跃车轧转轮软轻载轿较辅辆辈辑输辞辩边辽适钉针钟钢钥钦钱铁铃铅铜银锁销锋错键长门闪闭问闲间闹闻阅队阳阴阵阶际陆陈险随隐难雾页顶项顺须顾顿预领频题额颜愿风飞饥饭饮饱饼馆马驱驾验骑骗鱼鲜鸟鸡鸣鸭鸿鹏"
    )

    private static let traditionalOnly: Set<Character> = Set(
        "國東門車馬龍過這來時對會發點開關從眾專與書買亂爭產親億們傳體優儲兒黨蘭興養寫農沖決況淨準鳳凱劃剛創刪劑劍劇勸辦務動勞勢勛匯漢潔澆濁測濟渾濃潤漲漁滲滾滿濫濱濾滅燈燦煩燒熱愛牽犧獨現環說語請讓認議記許識譯證話廣慶應廳歷壓縣參雙變處備複婦媽孫學寧實審寬賓尋導將塵盡層島帥師帳帶幫幹後邊達運還進遠連遲選護報擁攔撥擇掛擋掙擠揮損換據撈搖攤擺攝敵數斬時晉曉術機殺雜權條楊極構櫃樣檔橋樓歡歲殘段畢氣湯溝沒淺塗湧濤澇澱遊瀨激爛爺獵畫瘡瘋鹽監盤睜確礙礦碼磚礎種積稱穩窮窗競籠簡簽類糧糾紅纖約級純綱納縱紛紙紡練組細織終經結繞繪給絡絕統繼績續繩維綠緩編緣縫纏縮網羅罰罷聾職聯聰腸膚膽藝節蘇藥獲藍雖蟻蠅見觀視覽覺計訂訓訊講論設訪評詞試詩讀調談貝負責敗賬貨質貪購賤貴貸貿費賀賊資賭賞賠賺贊贈贏趙趕躍軋轉輪軟輕載轎較輔輛輩輯輸辭辯邊遼適釘針鐘鋼鑰欽錢鐵鈴鉛銅銀鎖銷鋒錯鍵長閃閉問閑間鬧聞閱隊陽陰陣階際陸陳險隨隱難霧頁頂項順須顧頓預領頻題額顏願風飛饑飯飲飽餅館馬驅駕驗騎騙魚鮮鳥雞鳴鴨鴻鵬"
    )
}

private struct ListTranslationJob {
    enum Field { case title, summary }
    let articleID: UUID
    let field: Field
    let text: String
}

// MARK: - Article Row

struct ArticleRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    let article: Article
    let showTranslation: Bool
    /// 收藏页等场景：始终使用未读样式（强调色）
    var preferUnreadStyle: Bool = false

    /// 依赖本篇 generation + 同 feed 快照（不 flatMap 全库）
    private var live: Article {
        let _ = store.articleFlags.generation(of: article.id)
        return store.articleSnapshot(id: article.id, feedID: article.feedID) ?? article
    }

    private var displayTitle: String {
        let raw: String
        if showTranslation, let t = live.translatedTitle, !t.isEmpty { raw = t }
        else { raw = live.title }
        // 列表标题通常已是纯文本；仅在含标签时去标签
        return raw.contains("<") ? HTMLUtils.plainText(raw) : raw
    }

    private var displaySummary: String {
        let raw: String
        if showTranslation, let t = live.translatedSummary, !t.isEmpty { raw = t }
        else { raw = live.summary }
        return raw.contains("<") ? HTMLUtils.plainText(raw) : raw
    }

    var body: some View {
        let item = live
        VStack(alignment: .leading, spacing: 0) {
            // Title → Excerpt → Metadata
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                // Title
                HStack(alignment: .top, spacing: AppSpacing.xs) {
                    Text(displayTitle)
                        .font(AppTypography.font(
                            size: store.listTitleFontSize,
                            weight: (preferUnreadStyle || !item.isRead) ? .semibold : .regular
                        ))
                        .foregroundStyle((preferUnreadStyle || !item.isRead) ? theme.text : theme.muted)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    if item.isFavorite {
                        Image(systemName: "star.fill")
                            .font(AppTypography.font(size: max(11, store.listTitleFontSize - 6), weight: .semibold))
                            .foregroundStyle(.orange)
                            .padding(.top, 3)
                            .accessibilityLabel("已收藏")
                    }
                }
                if showTranslation && store.titleDisplayMode == .bilingual && item.translatedTitle != nil {
                    Text(item.title)
                        .font(AppTypography.listSummary(size: max(12, store.listTitleFontSize - 4)))
                        .foregroundStyle(theme.muted)
                        .lineLimit(2)
                }

                // Excerpt
                if !displaySummary.isEmpty {
                    Text(displaySummary)
                        .font(AppTypography.listSummary(size: store.listSummaryFontSize))
                        .foregroundStyle(theme.muted)
                        .lineLimit(2)
                    if showTranslation && store.titleDisplayMode == .bilingual
                        && item.translatedSummary != nil && !item.summary.isEmpty {
                        Text(item.summary)
                            .font(AppTypography.listSummary(size: max(12, store.listSummaryFontSize - 2)))
                            .foregroundStyle(theme.muted.opacity(0.75))
                            .lineLimit(2)
                    }
                }

                // Metadata — lowest weight
                HStack(spacing: 6) {
                    Text(item.feedTitle)
                        .font(AppTypography.caption())
                        .foregroundStyle(theme.muted)
                    if !item.relativeTime.isEmpty {
                        Text("·")
                            .font(AppTypography.caption())
                            .foregroundStyle(theme.muted.opacity(0.45))
                        Text(item.relativeTime)
                            .font(AppTypography.caption())
                            .foregroundStyle(theme.muted)
                    }
                    if store.smartInterestFilterEnabled, let score = item.interestScore {
                        Text("·")
                            .font(AppTypography.caption())
                            .foregroundStyle(theme.muted.opacity(0.45))
                        Text(String(format: "%.0f%%", score * 100))
                            .font(AppTypography.caption())
                            .foregroundStyle(score < store.lowInterestThreshold ? Color.orange : theme.muted)
                    }
                }

                if store.smartInterestFilterEnabled,
                   let score = item.interestScore,
                   score < store.lowInterestThreshold,
                   let reason = store.interestExplanation(for: item) {
                    Text(reason)
                        .font(AppTypography.caption())
                        .foregroundStyle(.orange.opacity(0.9))
                        .lineLimit(2)
                }
                // 仅对已读且配置了黑名单的条目计算，避免列表滚动时全量扫描
                if item.isRead, !store.articleBlacklistTerms.isEmpty,
                   let bl = store.articleBlacklistReason(for: item) {
                    Text(bl)
                        .font(AppTypography.caption())
                        .foregroundStyle(.red.opacity(0.85))
                        .lineLimit(1)
                }
            }
            .padding(.vertical, AppSpacing.md)
            Divider()
                .opacity(0.4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityRowLabel(item: item))
        .accessibilityHint(item.isRead ? "已读" : "未读")
    }

    private func accessibilityRowLabel(item: Article) -> String {
        var parts = [displayTitle]
        if !displaySummary.isEmpty {
            parts.append(String(displaySummary.prefix(80)))
        }
        parts.append(item.feedTitle)
        if !item.relativeTime.isEmpty { parts.append(item.relativeTime) }
        if item.isFavorite { parts.append("已收藏") }
        return parts.joined(separator: "，")
    }
}


/// 只观察 SessionChrome 上的列表翻译进度，不绑定文章列表数据
private struct ListTranslationChromeProgress: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme

    private var progressText: String { store.chrome.listTranslationProgressText }

    var body: some View {
        HStack(spacing: 4) {
            ProgressView().scaleEffect(0.75)
            if !progressText.isEmpty {
                Text(progressText)
                    .font(AppTypography.caption())
                    .monospacedDigit()
                    .foregroundStyle(theme.muted)
            }
        }
    }
}
