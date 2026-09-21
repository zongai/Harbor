import SwiftUI
import UIKit

/// EPUB 阅读器（Phase 3）：章节切换、目录、位置记忆、复用正文选区 / AI 解释
struct BookReaderView: View {
    @Environment(BookLibrary.self) private var library
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.scenePhase) private var scenePhase

    let bookID: UUID

    @State private var book: Book?
    @State private var chapterIndex: Int = 0
    @State private var chapterHTML: String = ""
    @State private var isLoadingChapter = false
    /// 换章时若已有缓存则不闪 Progress，仅在无缓存时轻提示
    @State private var showChapterLoadingHint = false
    @State private var loadError: String?
    /// 章节 HTML 内存缓存（换章 / 预取）
    @State private var chapterHTMLCache: [UUID: String] = [:]
    /// 忽略过期的异步加载结果
    @State private var chapterLoadGeneration = 0
    @State private var scrollToTopToken = 0
    /// 章末自动翻到下一章并继续朗读
    @State private var continuousTTS = true
    @State private var pendingContinueTTS = false
    @State private var showTOC = false
    @State private var showChrome = true
    @State private var bookTTS = BookTTSController()
    @State private var ttsRate: Double = 1.0
    @State private var readingMode: BookReadingMode = .original
    @State private var chapterTranslation: BookChapterTranslation?
    @State private var isTranslatingChapter = false
    @State private var translationProgressText: String?
    /// 预生成三种阅读 HTML，切换模式时只换引用、避免重复拼串
    @State private var cachedHTMLOriginal: String = ""
    @State private var cachedHTMLTranslation: String = ""
    @State private var cachedHTMLBilingual: String = ""
    /// 左右滑翻章：累计水平位移，避免与垂直滚动冲突
    @State private var chapterSwipeX: CGFloat = 0
    /// 当前章内滚动比例 0...1
    @State private var scrollProgress: Double = 0
    /// 打开后恢复一次滚动位置
    @State private var pendingScrollRestore: Double?
    @State private var didRestoreScroll = false
    @State private var restoreToken = 0
    @State private var restoreProgress: Double = 0

    private var chapters: [BookChapter] {
        book?.chapters.sorted(by: { $0.index < $1.index }) ?? []
    }

    private var currentChapter: BookChapter? {
        let list = chapters
        guard list.indices.contains(chapterIndex) else { return list.first }
        return list[chapterIndex]
    }

    private var readerStatusBarScheme: ColorScheme {
        let scheme = ReadingTheme.effectiveColorScheme(
            appearance: store.appearanceMode,
            systemScheme: systemColorScheme
        )
        if store.colorTheme.prefersDarkChrome { return .dark }
        return scheme
    }

    var body: some View {
        Group {
            if let book {
                readerBody(book)
            } else {
                ProgressView("打开书籍…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .appScreenBackground()
            }
        }
        .onAppear(perform: bootstrap)
        .onDisappear {
            persistPosition()
            bookTTS.stop()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background || phase == .inactive {
                persistPosition()
            }
        }
    }

    @ViewBuilder
    private func readerBody(_ book: Book) -> some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Color.clear.frame(height: 0).id("chapter-top")
                if let ch = currentChapter {
                    Text(ch.title)
                        .font(AppTypography.articleTitle(size: CGFloat(store.readerTitleFontSize)))
                        .foregroundStyle(theme.text)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("\(chapterIndex + 1) / \(max(chapters.count, 1)) · \(book.title)")
                        .font(AppTypography.articleMeta())
                        .foregroundStyle(theme.muted)
                }

                if let loadError {
                    Text(loadError)
                        .font(AppTypography.body())
                        .foregroundStyle(.red)
                } else if displayHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if isLoadingChapter || showChapterLoadingHint {
                        ProgressView("加载章节…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    } else {
                        Text(emptyContentHint)
                            .font(AppTypography.body())
                            .foregroundStyle(theme.muted)
                            .padding(.vertical, 24)
                    }
                } else {
                    if showChapterLoadingHint {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("加载章节…")
                                .font(AppTypography.caption())
                                .foregroundStyle(theme.muted)
                        }
                        .padding(.vertical, 4)
                    }
                    if isTranslatingChapter {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(translationProgressText ?? "翻译中…")
                                .font(AppTypography.caption())
                                .foregroundStyle(theme.muted)
                        }
                        .padding(.vertical, 8)
                    }
                    BookReaderBodyContent(
                        bookTTS: bookTTS,
                        displayHTML: displayHTML,
                        fontSize: store.fontSize,
                        prefersChinese: prefersChineseForDisplay(book),
                        articleTitle: currentChapter?.title ?? "",
                        contentID: contentViewID
                    )
                    .transaction { $0.animation = nil }
                }
                Color.clear.frame(height: 1).id("chapter-bottom")
            }
            .padding(.horizontal, AppLayout.readingHorizontalPadding)
            .padding(.vertical, AppSpacing.lg)
            .padding(.bottom, 48)
            .background {
                GeometryReader { geo in
                    Color.clear.preference(
                        key: BookScrollHeightKey.self,
                        value: geo.size.height
                    )
                }
            }
        }
        .coordinateSpace(name: "bookReaderScroll")
        .onScrollGeometryChange(for: Double.self) { geo in
            let range = max(geo.contentSize.height - geo.containerSize.height, 1)
            return min(1, max(0, Double(geo.contentOffset.y / range)))
        } action: { _, newValue in
            if pendingScrollRestore == nil {
                scrollProgress = newValue
            }
        }
        .background {
            BookScrollOffsetRestorer(progress: restoreProgress, token: restoreToken)
        }
        .onPreferenceChange(BookScrollHeightKey.self) { _ in
            tryRestoreScroll(proxy: proxy)
        }
        .onChange(of: chapterHTML) { _, _ in
            if pendingScrollRestore != nil {
                didRestoreScroll = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    tryRestoreScroll(proxy: proxy)
                }
            }
        }
        .onChange(of: scrollToTopToken) { _, _ in
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                proxy.scrollTo("chapter-top", anchor: .top)
            }
        }
        .appScreenBackground()

        .simultaneousGesture(
            DragGesture(minimumDistance: 40, coordinateSpace: .local)
                .onEnded { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    // 水平为主才翻章，避免干扰上下滚动
                    guard abs(dx) > 80, abs(dx) > abs(dy) * 1.4 else { return }
                    if dx < 0 {
                        // 左滑 → 下一章
                        if chapterIndex + 1 < chapters.count {
                            selectChapter(chapterIndex + 1)
                        }
                    } else {
                        // 右滑 → 上一章
                        if chapterIndex > 0 {
                            selectChapter(chapterIndex - 1)
                        }
                    }
                }
        )
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    ForEach(BookReadingMode.allCases) { mode in
                        Button {
                            // 无动画切换，减少布局动画卡顿
                            var t = Transaction()
                            t.disablesAnimations = true
                            withTransaction(t) {
                                readingMode = mode
                            }
                        } label: {
                            HStack {
                                Text(mode.title)
                                if readingMode == mode {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .disabled(mode != .original && cachedHTMLTranslation.isEmpty && chapterTranslation?.status != .done)
                    }
                    Divider()
                    Button {
                        Task { await translateCurrentChapter() }
                    } label: {
                        Label(
                            chapterTranslation?.status == .done ? "重新翻译本章" : "翻译本章",
                            systemImage: "character.book.closed"
                        )
                    }
                    .disabled(chapterHTML.isEmpty || isTranslatingChapter)
                } label: {
                    Label("阅读模式", systemImage: "text.book.closed")
                }
                .labelStyle(.iconOnly)

                Menu {
                    ForEach([0.75, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { r in
                        Button {
                            ttsRate = r
                            bookTTS.playbackRate = r
                        } label: {
                            HStack {
                                Text(String(format: "%.2gx", r))
                                if abs(ttsRate - r) < 0.01 {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                    Divider()
                    Button {
                        guard let ch = currentChapter else { return }
                        bookTTS.precacheChapter(
                            bookID: bookID,
                            chapterID: ch.id,
                            html: chapterHTML,
                            voice: store.ttsVoice.isEmpty ? nil : store.ttsVoice
                        )
                    } label: {
                        Label("缓存本章语音", systemImage: "arrow.down.circle")
                    }
                    .disabled(chapterHTML.isEmpty || bookTTS.isCaching)
                    Divider()
                    Button {
                        continuousTTS.toggle()
                        bookTTS.continuousChapterPlay = continuousTTS
                    } label: {
                        Label(
                            continuousTTS ? "自动换章朗读：开" : "自动换章朗读：关",
                            systemImage: continuousTTS ? "checkmark.circle.fill" : "circle"
                        )
                    }
                    Button {
                        startTTSPlayback(forceFromStart: true)
                    } label: {
                        Label("从头朗读本章", systemImage: "backward.end")
                    }
                    .disabled(chapterHTML.isEmpty || bookTTS.isPlaying || bookTTS.isLoading)
                } label: {
                    Label("语速", systemImage: "gauge.with.dots.needle.33percent")
                }
                .labelStyle(.iconOnly)

                Button {
                    startOrStopTTS()
                } label: {
                    Label(
                        bookTTS.isPlaying || bookTTS.isLoading ? "停止" : "朗读",
                        systemImage: bookTTS.isPlaying || bookTTS.isLoading ? "stop.fill" : "speaker.wave.2"
                    )
                }
                .labelStyle(.iconOnly)
                .disabled(chapterHTML.isEmpty && !bookTTS.isPlaying)

                Button {
                    showTOC = true
                } label: {
                    Label("目录", systemImage: "list.bullet")
                }
                .labelStyle(.iconOnly)
                .accessibilityLabel("章节目录")
            }
        }
        .onChange(of: bookTTS.segmentIndex) { _, idx in
            guard bookTTS.isPlaying || bookTTS.isLoading else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo("tts-seg-\(idx)", anchor: .center)
            }
            // 朗读推进时同步阅读进度，关闭再开仍在附近
            if bookTTS.segmentCount > 0 {
                scrollProgress = Double(idx) / Double(max(bookTTS.segmentCount, 1))
            }
        }
        .onChange(of: bookTTS.chapterFinishedToken) { _, _ in
            handleChapterTTSFinished()
        }
        .onChange(of: isLoadingChapter) { _, loading in
            // 自动续读：下一章 HTML 就绪后从章首启动
            if !loading, pendingContinueTTS, !chapterHTML.isEmpty {
                pendingContinueTTS = false
                startTTSPlayback(forceFromStart: true)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if showChrome {
                chapterChrome
            }
        }
        .sheet(isPresented: $showTOC) {
            NavigationStack {
                List {
                    ForEach(Array(chapters.enumerated()), id: \.element.id) { idx, ch in
                        Button {
                            selectChapter(idx)
                            showTOC = false
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ch.title)
                                        .font(AppTypography.listTitle())
                                        .foregroundStyle(theme.text)
                                        .multilineTextAlignment(.leading)
                                    Text("第 " + String(idx + 1) + " 章")
                                        .font(AppTypography.caption())
                                        .foregroundStyle(theme.muted)
                                }
                                Spacer()
                                if idx == chapterIndex {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(theme.accent)
                                }
                            }
                        }
                    }
                }
                .navigationTitle("目录")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("完成") { showTOC = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        } // ScrollViewReader
        .preferredColorScheme(readerStatusBarScheme)
        .onChange(of: chapterIndex) { _, _ in
            Task { await loadCurrentChapter() }
        }
    }

    private var chapterChrome: some View {
        HStack(spacing: 16) {
            Button {
                guard chapterIndex > 0 else { return }
                selectChapter(chapterIndex - 1)
            } label: {
                Label("上一章", systemImage: "chevron.left")
            }
            .disabled(chapterIndex <= 0)
            .labelStyle(.iconOnly)

            VStack(spacing: 4) {
                ProgressView(value: chapterProgress)
                    .tint(theme.accent)
                if let s = bookTTS.statusText, bookTTS.isPlaying || bookTTS.isLoading || bookTTS.isCaching {
                    Text(s)
                        .font(AppTypography.caption())
                        .foregroundStyle(theme.accent)
                        .lineLimit(1)
                } else {
                    Text(currentChapter?.title ?? "")
                        .font(AppTypography.caption())
                        .foregroundStyle(theme.muted)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)

            Button {
                guard chapterIndex + 1 < chapters.count else { return }
                selectChapter(chapterIndex + 1)
            } label: {
                Label("下一章", systemImage: "chevron.right")
            }
            .disabled(chapterIndex + 1 >= chapters.count)
            .labelStyle(.iconOnly)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var chapterProgress: Double {
        let n = max(chapters.count, 1)
        return Double(chapterIndex + 1) / Double(n)
    }


    /// 仅章节变化时重置视图身份；模式切换不 destroy ArticleContentView
    private var contentViewID: String {
        currentChapter?.id.uuidString ?? bookID.uuidString
    }

    private var displayHTML: String {
        switch readingMode {
        case .original:
            return cachedHTMLOriginal.isEmpty ? chapterHTML : cachedHTMLOriginal
        case .translation:
            return cachedHTMLTranslation
        case .bilingual:
            return cachedHTMLBilingual.isEmpty ? cachedHTMLOriginal : cachedHTMLBilingual
        }
    }

    /// 章节 HTML / 译文变更时重建三种缓存（后台拼双语串，避免主线程卡一下）
    private func rebuildHTMLCaches() {
        let original = chapterHTML
        cachedHTMLOriginal = original
        guard let tr = chapterTranslation, tr.status == .done, !tr.paragraphs.isEmpty else {
            cachedHTMLTranslation = ""
            cachedHTMLBilingual = ""
            return
        }
        // 短章同步；长章后台生成，生成前先占位避免空切
        if tr.paragraphs.count < 40 {
            cachedHTMLTranslation = tr.translationHTML
            cachedHTMLBilingual = tr.bilingualHTML
            return
        }
        cachedHTMLTranslation = tr.translationHTML
        let snapshot = tr
        Task.detached(priority: .userInitiated) {
            let bi = snapshot.bilingualHTML
            await MainActor.run {
                // 仍是同一章译文再写入
                if chapterTranslation?.chapterID == snapshot.chapterID,
                   chapterTranslation?.updatedAt == snapshot.updatedAt {
                    cachedHTMLBilingual = bi
                }
            }
        }
    }

    private var emptyContentHint: String {
        switch readingMode {
        case .original:
            return "本章无文本内容"
        case .translation:
            return chapterTranslation == nil ? "尚未翻译本章，请在「阅读模式」中选择翻译本章" : "译文为空"
        case .bilingual:
            return "本章无文本内容"
        }
    }

    private func prefersChineseForDisplay(_ book: Book) -> Bool {
        if readingMode == .translation { return true }
        if readingMode == .bilingual { return true }
        return prefersChinese(book)
    }

    private func loadTranslationIfNeeded() {
        guard let ch = currentChapter else {
            chapterTranslation = nil
            rebuildHTMLCaches()
            return
        }
        chapterTranslation = BookTranslationService.load(bookID: bookID, chapterID: ch.id)
        rebuildHTMLCaches()
    }

    private func translateCurrentChapter() async {
        guard let ch = currentChapter, !chapterHTML.isEmpty else { return }
        isTranslatingChapter = true
        translationProgressText = "准备翻译…"
        loadError = nil
        do {
            let result = try await BookTranslationService.translateChapter(
                bookID: bookID,
                chapterID: ch.id,
                html: chapterHTML,
                targetLanguage: store.targetLanguage,
                store: store
            ) { p, msg in
                Task { @MainActor in
                    translationProgressText = msg
                }
            }
            chapterTranslation = result
            rebuildHTMLCaches()
            if readingMode == .original {
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) {
                    readingMode = .bilingual
                }
            }
        } catch {
            loadError = error.localizedDescription
        }
        isTranslatingChapter = false
        translationProgressText = nil
    }

    private func prefersChinese(_ book: Book) -> Bool {
        let lang = (book.language ?? "").lowercased()
        return lang.contains("zh") || lang.contains("chinese") || lang.hasPrefix("cn")
    }

    private func startOrStopTTS() {
        if bookTTS.isPlaying || bookTTS.isLoading {
            pendingContinueTTS = false
            bookTTS.stop()
            syncReadingPositionFromTTS()
            return
        }
        startTTSPlayback(forceFromStart: false)
    }

    private func startTTSPlayback(forceFromStart: Bool = false) {
        guard let ch = currentChapter, !chapterHTML.isEmpty else { return }
        bookTTS.continuousChapterPlay = continuousTTS
        bookTTS.playbackRate = ttsRate
        // 自动换章续读从章首；用户点朗读则恢复断点
        let resume = !forceFromStart
        bookTTS.toggleContent(
            bookID: bookID,
            chapterID: ch.id,
            mode: readingMode,
            html: chapterHTML,
            translation: chapterTranslation,
            voice: store.ttsVoice.isEmpty ? nil : store.ttsVoice,
            rate: ttsRate,
            resumeFromSaved: resume,
            forceFromStart: forceFromStart
        )
    }

    private func syncReadingPositionFromTTS() {
        guard bookTTS.segmentCount > 0 else { return }
        let frac = Double(bookTTS.segmentIndex) / Double(max(bookTTS.segmentCount, 1))
        scrollProgress = min(1, max(0, frac))
        persistPosition()
    }

    private func handleChapterTTSFinished() {
        guard continuousTTS else { return }
        guard chapterIndex + 1 < chapters.count else {
            bookTTS.statusText = "全书朗读完成"
            return
        }
        pendingContinueTTS = true
        bookTTS.statusText = "进入第 \(chapterIndex + 2) 章…"
        selectChapter(chapterIndex + 1)
        // 章节加载完成后由 applyChapterHTML / isLoadingChapter 钩子启动朗读
    }

    private func bootstrap() {
        // 应用设置中的默认模式 / 语速（与文章共用 ttsRate）
        if let mode = BookReadingMode(rawValue: store.settings.bookDefaultReadingMode) {
            readingMode = mode
        }
        ttsRate = store.ttsRate
        bookTTS.playbackRate = ttsRate
        bookTTS.continuousChapterPlay = continuousTTS

        guard let b = library.books.first(where: { $0.id == bookID }) else {
            library.load()
            book = library.books.first(where: { $0.id == bookID })
            return
        }
        book = b
        // 恢复上次章节
        if let lastID = b.lastChapterID,
           let idx = b.chapters.sorted(by: { $0.index < $1.index }).firstIndex(where: { $0.id == lastID }) {
            chapterIndex = idx
        } else {
            chapterIndex = 0
        }
        // 恢复章内滚动（内容加载后再滚）
        let savedScroll = min(1, max(0, b.lastScrollProgress))
        pendingScrollRestore = savedScroll > 0.02 ? savedScroll : nil
        didRestoreScroll = pendingScrollRestore == nil
        scrollProgress = savedScroll
        Task { await loadCurrentChapter() }
        touchLastRead()
    }

    private func selectChapter(_ idx: Int) {
        guard chapters.indices.contains(idx), idx != chapterIndex else { return }
        // 换章前保存当前章位置
        persistPosition()
        chapterIndex = idx
        scrollProgress = 0
        pendingScrollRestore = nil
        didRestoreScroll = true
        // 立即滚回章首，避免沿用上一章滚动位置
        scrollToTopToken &+= 1
        // load 由 onChange(chapterIndex) 触发
    }

    private func tryRestoreScroll(proxy: ScrollViewProxy) {
        guard !didRestoreScroll, let target = pendingScrollRestore, target > 0.02 else { return }
        guard !isLoadingChapter, !chapterHTML.isEmpty else { return }
        didRestoreScroll = true
        let progress = target
        pendingScrollRestore = nil
        // 先滚到顶部再由 UIKit 按比例定位（比 anchor 估算更准）
        proxy.scrollTo("chapter-top", anchor: .top)
        scrollProgress = progress
        // 触发 UIView 查找 UIScrollView 设置 offset
        restoreToken += 1
        restoreProgress = progress
    }

    private func loadCurrentChapter() async {
        guard let book, let ch = currentChapter else {
            chapterHTML = ""
            cachedHTMLOriginal = ""
            return
        }
        loadError = nil
        chapterLoadGeneration &+= 1
        let gen = chapterLoadGeneration
        let chapterID = ch.id
        let href = ch.href
        let bookDir = BookLibrary.bookDirectory(id: book.id)

        // 1) 内存命中：瞬间切换，无闪白
        if let cached = chapterHTMLCache[chapterID], !cached.isEmpty {
            applyChapterHTML(cached, chapterID: chapterID, generation: gen)
            prefetchAdjacentChapters(around: chapterIndex, book: book)
            return
        }

        // 2) 无缓存：后台读盘，主线程不卡；有旧正文时不整页 Progress
        let hadContent = !chapterHTML.isEmpty
        isLoadingChapter = !hadContent
        showChapterLoadingHint = hadContent
        let loaded: String? = await Task.detached(priority: .userInitiated) {
            EPUBParser.loadChapterHTML(bookDirectory: bookDir, href: href)
        }.value

        guard gen == chapterLoadGeneration else { return }
        if let loaded, !loaded.isEmpty {
            chapterHTMLCache[chapterID] = loaded
            applyChapterHTML(loaded, chapterID: chapterID, generation: gen)
            prefetchAdjacentChapters(around: chapterIndex, book: book)
        } else {
            chapterHTML = ""
            cachedHTMLOriginal = ""
            cachedHTMLTranslation = ""
            cachedHTMLBilingual = ""
            loadError = "无法加载本章内容（\(href)）"
            isLoadingChapter = false
            showChapterLoadingHint = false
        }
    }

    private func applyChapterHTML(_ html: String, chapterID: UUID, generation: Int) {
        guard generation == chapterLoadGeneration else { return }
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            chapterHTML = html
            isLoadingChapter = false
            showChapterLoadingHint = false
            loadTranslationIfNeeded()
        }
        // 限制缓存规模，避免大书占内存
        if chapterHTMLCache.count > 24 {
            let keep = Set(adjacentChapterIDs(around: chapterIndex) + [chapterID])
            chapterHTMLCache = chapterHTMLCache.filter { keep.contains($0.key) }
        }
        // 自动换章朗读：新章内容就绪后从章首继续
        if pendingContinueTTS {
            pendingContinueTTS = false
            DispatchQueue.main.async {
                self.startTTSPlayback(forceFromStart: true)
            }
        }
    }

    private func adjacentChapterIDs(around index: Int) -> [UUID] {
        var ids: [UUID] = []
        let list = chapters
        for i in [index - 1, index, index + 1] where list.indices.contains(i) {
            ids.append(list[i].id)
        }
        return ids
    }

    /// 预取上一章 / 下一章 HTML，使连续翻章接近即时
    private func prefetchAdjacentChapters(around index: Int, book: Book) {
        let list = chapters
        let dir = BookLibrary.bookDirectory(id: book.id)
        let targets = [index - 1, index + 1].compactMap { i -> BookChapter? in
            guard list.indices.contains(i) else { return nil }
            let ch = list[i]
            if chapterHTMLCache[ch.id] != nil { return nil }
            return ch
        }
        guard !targets.isEmpty else { return }
        Task.detached(priority: .utility) {
            var loaded: [(UUID, String)] = []
            for ch in targets {
                if let html = EPUBParser.loadChapterHTML(bookDirectory: dir, href: ch.href), !html.isEmpty {
                    loaded.append((ch.id, html))
                }
            }
            guard !loaded.isEmpty else { return }
            await MainActor.run {
                for (id, html) in loaded {
                    if chapterHTMLCache[id] == nil {
                        chapterHTMLCache[id] = html
                    }
                }
            }
        }
    }

    private func touchLastRead() {
        guard var b = book else { return }
        b.lastReadDate = Date()
        book = b
        library.updateBook(b)
    }

    private func persistPosition() {
        guard var b = book, let ch = currentChapter else { return }
        b.lastChapterID = ch.id
        b.lastReadDate = Date()
        b.lastScrollProgress = min(1, max(0, scrollProgress))
        let n = max(b.chapters.count, 1)
        // 全书进度：章节进度 + 章内滚动
        let chapterFrac = Double(chapterIndex) / Double(n)
        let within = b.lastScrollProgress / Double(n)
        b.readingProgress = min(1, chapterFrac + within + (1.0 / Double(n)) * 0.01)
        if let i = b.chapters.firstIndex(where: { $0.id == ch.id }) {
            b.chapters[i].readingProgress = b.lastScrollProgress
        }
        book = b
        library.updateBook(b)
    }
}

/// 用于观测章节内容高度，触发滚动恢复
private struct BookScrollHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// 在 UIScrollView 上按比例恢复 contentOffset（SwiftUI ScrollView 底层）
private struct BookScrollOffsetRestorer: UIViewRepresentable {
    var progress: Double
    var token: Int

    func makeUIView(context: Context) -> UIView {
        let v = UIView(frame: .zero)
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard token > 0, progress > 0.02 else { return }
        let p = progress
        // 等布局完成再设 offset
        DispatchQueue.main.async {
            guard let scroll = Self.findScrollView(from: uiView) else { return }
            let maxY = max(scroll.contentSize.height - scroll.bounds.height, 0)
            guard maxY > 1 else {
                // 内容高度尚未就绪，稍后再试
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    guard let scroll = Self.findScrollView(from: uiView) else { return }
                    let maxY = max(scroll.contentSize.height - scroll.bounds.height, 0)
                    scroll.setContentOffset(CGPoint(x: 0, y: maxY * p), animated: false)
                }
                return
            }
            scroll.setContentOffset(CGPoint(x: 0, y: maxY * p), animated: false)
        }
    }

    private static func findScrollView(from view: UIView) -> UIScrollView? {
        var v: UIView? = view
        while let cur = v {
            if let s = cur as? UIScrollView { return s }
            v = cur.superview
        }
        // 向上找不到则向下搜兄弟树
        var root: UIView? = view
        while let s = root?.superview { root = s }
        return findScrollViewDFS(root)
    }

    private static func findScrollViewDFS(_ root: UIView?) -> UIScrollView? {
        guard let root else { return nil }
        if let s = root as? UIScrollView, s.contentSize.height > s.bounds.height + 10 {
            return s
        }
        for child in root.subviews {
            if let found = findScrollViewDFS(child) { return found }
        }
        return nil
    }
}

/// 拆出正文区域，降低 BookReaderView body 类型检查负担
private struct BookReaderBodyContent: View {
    var bookTTS: BookTTSController
    let displayHTML: String
    let fontSize: Double
    let prefersChinese: Bool
    let articleTitle: String
    let contentID: String
    @Environment(\.theme) private var theme

    var body: some View {
        if (bookTTS.isPlaying || bookTTS.isLoading) && !bookTTS.activeSegments.isEmpty {
            ttsList
        } else {
            ArticleContentView(
                html: displayHTML,
                fontSize: fontSize,
                prefersChineseTypography: prefersChinese,
                articleTitle: articleTitle
            )
            // 仅按章节稳定身份；模式切换走 html/parseKey，避免整树销毁重建
            .id(contentID)
            .transaction { $0.animation = nil }
        }
    }

    @ViewBuilder
    private var ttsList: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            ForEach(Array(bookTTS.activeSegments.enumerated()), id: \.offset) { item in
                TTSSegLine(
                    text: item.element.text,
                    highlighted: item.offset == bookTTS.segmentIndex,
                    fontSize: fontSize,
                    index: item.offset
                )
            }
        }
    }
}

private struct TTSSegLine: View {
    let text: String
    let highlighted: Bool
    let fontSize: Double
    let index: Int
    @Environment(\.theme) private var theme

    var body: some View {
        Text(text)
            .font(.system(size: fontSize))
            .foregroundStyle(theme.text)
            .lineSpacing(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(highlighted ? theme.accent.opacity(0.18) : Color.clear)
            )
            .id("tts-seg-" + String(index))
    }
}
