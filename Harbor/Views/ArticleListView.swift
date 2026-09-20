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

    /// 列表翻译每批条数（标题 + 预览各算一条任务）
    /// 仅用于进度刷新粒度；实际并发由 AppStore.translateTexts 控制
    private let translationBatchSize = 24

    private var articles: [Article] {
        // 显式依赖 openedArticleID / readingIDs，保证返回后重新过滤
        let _ = openedArticleID
        let _ = readingIDs
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
            // Editorial hierarchy: first article as Featured, rest as regular rows
            ForEach(Array(articles.enumerated()), id: \.element.id) { index, article in
                NavigationLink(value: article) {
                    if index == 0 {
                        FeaturedArticleRow(article: article, showTranslation: showAllTranslations)
                    } else {
                        ArticleRow(article: article, showTranslation: showAllTranslations)
                    }
                }
                // 仅用 id + 已读 + 是否显示译文；译文内容变化由 ArticleRow 读最新 article 字段刷新
                // （避免把整段译文塞进 id 导致行身份频繁失效、List 复用失败）
                .id("\(article.id.uuidString)-\(article.isRead)-\(showAllTranslations)-\(article.translatedTitle == nil ? 0 : 1)-\(article.translatedSummary == nil ? 0 : 1)-\(index == 0 ? "f" : "r")")
                .listRowInsets(EdgeInsets(
                    top: index == 0 ? AppSpacing.sm : (index == 1 ? AppSpacing.xs : 0),
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
                        HStack(spacing: 4) {
                            ProgressView().scaleEffect(0.75)
                            if translationTotal > 0 {
                                Text("\(translationDone)/\(translationTotal)")
                                    .font(AppTypography.caption())
                                    .monospacedDigit()
                                    .foregroundStyle(theme.muted)
                            }
                        }
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
        translationDone = 0
        translationTotal = jobs.count

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
                translationDone += 1
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

// MARK: - Featured Article Row (editorial hierarchy — first item)

/// Larger visual weight for the lead story in a feed list.
struct FeaturedArticleRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    let article: Article
    let showTranslation: Bool

    private var live: Article {
        let list = store.articlesForFeed(article.feedID)
        return list.first(where: { $0.id == article.id }) ?? article
    }

    private var displayTitle: String {
        let raw: String
        if showTranslation, let t = live.translatedTitle, !t.isEmpty { raw = t }
        else { raw = live.title }
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
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                // Category / source
                Text(item.feedTitle.uppercased())
                    .font(AppTypography.articleCategory(size: max(11, store.listTitleFontSize - 6)))
                    .tracking(0.9)
                    .foregroundStyle(theme.muted)

                // Large title
                HStack(alignment: .top, spacing: AppSpacing.xs) {
                    Text(displayTitle)
                        .font(AppTypography.font(
                            size: store.listTitleFontSize + 5,
                            weight: item.isRead ? .medium : .bold
                        ))
                        .tracking(AppTypography.displayTracking * 0.7)
                        .lineSpacing(3)
                        .foregroundStyle(item.isRead ? theme.muted : theme.text)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                    if item.isFavorite {
                        Image(systemName: "star.fill")
                            .font(AppTypography.font(size: max(12, store.listTitleFontSize - 4), weight: .semibold))
                            .foregroundStyle(.orange)
                            .padding(.top, 4)
                            .accessibilityLabel("已收藏")
                    }
                }

                if showTranslation && store.titleDisplayMode == .bilingual && item.translatedTitle != nil {
                    Text(item.title)
                        .font(AppTypography.listSummary(size: max(13, store.listTitleFontSize - 2)))
                        .foregroundStyle(theme.muted)
                        .lineLimit(2)
                }

                // Longer excerpt
                if !displaySummary.isEmpty {
                    Text(displaySummary)
                        .font(AppTypography.listSummary(size: store.listSummaryFontSize + 1))
                        .foregroundStyle(theme.muted)
                        .lineSpacing(3)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Metadata — lowest weight
                HStack(spacing: 6) {
                    if !item.relativeTime.isEmpty {
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
                .padding(.top, AppSpacing.xxs)
            }
            .padding(.top, AppSpacing.lg)
            .padding(.bottom, AppSpacing.xl)
            Divider()
                .opacity(0.4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel({
            var parts = ["头条", displayTitle]
            if !displaySummary.isEmpty { parts.append(String(displaySummary.prefix(100))) }
            if !item.relativeTime.isEmpty { parts.append(item.relativeTime) }
            if item.isFavorite { parts.append("已收藏") }
            return parts.joined(separator: "，")
        }())
        .accessibilityHint(item.isRead ? "已读" : "未读")
    }
}

// MARK: - Article Row

struct ArticleRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    let article: Article
    let showTranslation: Bool
    /// 收藏页等场景：始终使用未读样式（强调色）
    var preferUnreadStyle: Bool = false

    /// 优先用 ForEach 传入的最新 article；仅在同 feed 内轻量回查（避免全库 flatMap）
    private var live: Article {
        let list = store.articlesForFeed(article.feedID)
        return list.first(where: { $0.id == article.id }) ?? article
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
            // Editorial order: Title → Excerpt → Metadata
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
            .padding(.vertical, AppSpacing.md + 2)
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
