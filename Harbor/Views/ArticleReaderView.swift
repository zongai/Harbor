import SwiftUI
import SafariServices

struct ArticleReaderView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let article: Article
    var feedID: UUID? = nil
    /// 收藏页进入：左右滑在收藏列表内换篇
    var browseFavorites: Bool = false

    @State private var isTranslating = false
    @State private var isGeneratingSummary = false
    @State private var isFetchingFull = false
    @State private var translatedContent: String?
    @State private var showTranslated = false
    @State private var aiSummary: String?
    @State private var aiSummaryProvider: String?
    @State private var summaryExpanded = true
    @State private var translationError: String?
    @State private var summaryError: String?
    @State private var fullContentError: String?
    @State private var browserItem: BrowserLink?
    @State private var translationProgress: String?
    @State private var fullContentHint: String?
    @State private var showComments = false
    @ObservedObject private var tts = EdgeTTSPlayer.shared
    @State private var showChrome = true
    @State private var currentID: UUID?
    @State private var dragOffset: CGFloat = 0
    /// 阅读进度用引用类型存放，滚动中改值不触发 View 刷新
    @State private var readProgressBox = ReaderScrollMetrics()
    /// 仅用于顶部细进度条 UI（稀疏更新，避免滚动掉帧）
    @State private var displayProgress: Double = 0
    /// 横向滑动表格时为 true，避免误触发左右换篇
    @State private var suppressArticleSwipe = false

    /// 与当前阅读主题一致的状态栏/导航栏配色，保证时间与信号图标清晰可见
    private var readerStatusBarScheme: ColorScheme {
        let resolved = ReadingTheme.resolved(
            selected: store.colorTheme,
            appearance: store.appearanceMode,
            systemScheme: systemColorScheme
        )
        return resolved.isDark ? .dark : .light
    }

    private var activeID: UUID { currentID ?? article.id }

    private var currentArticle: Article {
        store.feeds.flatMap { $0.articles }.first(where: { $0.id == activeID }) ?? article
    }

    private var feedArticles: [Article] {
        if browseFavorites {
            return store.favoriteArticles
                .sorted { ($0.publishedDate ?? .distantPast) > ($1.publishedDate ?? .distantPast) }
        }
        let fid = feedID ?? currentArticle.feedID
        return store.articlesForFeed(fid)
            .sorted { ($0.publishedDate ?? .distantPast) > ($1.publishedDate ?? .distantPast) }
    }

    private var currentIndex: Int? {
        feedArticles.firstIndex(where: { $0.id == activeID })
    }

    private var needsTranslation: Bool {
        // 以正文为准：正文足够长时只看正文；否则才回退标题
        let body = HTMLUtils.plainText(currentArticle.content)
        let sample: String
        if body.count >= 40 {
            sample = body
        } else {
            sample = (currentArticle.title + "\n" + body).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if sample.isEmpty { return false }
        if currentArticle.hasTranslatedBody { return false }
        return !ListLanguageDetect.isMostlyTarget(sample, language: store.targetLanguage)
    }

    /// 工具栏翻译按钮：需译、已在看译文、或已有缓存译文时都显示（便于原文/译文切换）
    private var showTranslationButton: Bool {
        if showTranslated { return true }
        if currentArticle.hasTranslatedBody { return true }
        if let local = translatedContent, !local.isEmpty { return true }
        return needsTranslation
    }

    private var hasUsableTranslation: Bool {
        if let local = translatedContent, !local.isEmpty { return true }
        return currentArticle.hasTranslatedBody
    }


    private var displayTitle: String {
        if showTranslated, let t = currentArticle.translatedTitle, !t.isEmpty { return t }
        return currentArticle.title
    }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Color.clear.frame(height: 0).id("readerTop")

                // MARK: Editorial header — category → title → meta
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    // Category / source (quiet label above the title)
                    Text(currentArticle.feedTitle.uppercased())
                        .font(AppTypography.articleCategory(size: max(11, store.readerTitleFontSize - 14)))
                        .tracking(1.0)
                        .foregroundStyle(theme.muted)

                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text(displayTitle)
                            .font(AppTypography.articleTitle(size: store.readerTitleFontSize))
                            .tracking(AppTypography.displayTracking)
                            .foregroundStyle(theme.text)
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)

                        if showTranslated,
                           let translated = currentArticle.translatedTitle,
                           !translated.isEmpty,
                           store.titleDisplayMode == .bilingual {
                            Text(currentArticle.title)
                                .font(AppTypography.articleSubtitle(size: max(13, store.readerTitleFontSize - 9)))
                                .foregroundStyle(theme.muted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    // Metadata — lowest weight
                    HStack(spacing: AppSpacing.xs) {
                        if !currentArticle.relativeTime.isEmpty {
                            Text(currentArticle.relativeTime)
                                .font(AppTypography.articleMeta(size: max(12, store.readerTitleFontSize - 12)))
                                .foregroundStyle(theme.muted)
                        }
                        if currentArticle.hasFullContent {
                            Text("·")
                                .foregroundStyle(theme.muted.opacity(0.45))
                            Text("全文")
                                .font(AppTypography.articleMeta(size: max(11, store.readerTitleFontSize - 13)))
                                .foregroundStyle(theme.muted)
                        } else if fullContentError != nil {
                            Text("·")
                                .foregroundStyle(theme.muted.opacity(0.45))
                            Text("仅摘要")
                                .font(AppTypography.articleMeta(size: max(11, store.readerTitleFontSize - 13)))
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .padding(.horizontal, AppLayout.readingHorizontalPadding)
                .padding(.top, AppSpacing.xxl)
                .padding(.bottom, AppSpacing.xl)
                .readingColumn()

                readerHighlightsSection()
                    .padding(.horizontal, AppLayout.readingHorizontalPadding)
                    .readingColumn()

                // Soft rule under header
                Divider()
                    .opacity(0.45)
                    .padding(.horizontal, AppLayout.readingHorizontalPadding)
                    .readingColumn()

                if let summary = aiSummary ?? currentArticle.aiSummary {
                    AISummaryCard(summary: summary, expanded: $summaryExpanded, fontSize: store.aiSummaryFontSize, providerName: aiSummaryProvider ?? currentArticle.aiSummaryProvider)
                        .padding(.horizontal, AppLayout.readingHorizontalPadding)
                        .padding(.top, AppSpacing.md)
                        .readingColumn()
                }
                if let err = summaryError {
                    Text(err)
                        .font(AppTypography.caption())
                        .foregroundStyle(.red)
                        .padding(.horizontal, AppLayout.readingHorizontalPadding)
                        .padding(.top, AppSpacing.xs)
                        .readingColumn()
                }
                if let err = translationError {
                    Text(err)
                        .font(AppTypography.caption())
                        .foregroundStyle(.red)
                        .padding(.horizontal, AppLayout.readingHorizontalPadding)
                        .padding(.top, AppSpacing.xs)
                        .readingColumn()
                }
                if let err = tts.errorMessage {
                    Text(err)
                        .font(AppTypography.caption())
                        .foregroundStyle(.red)
                        .padding(.horizontal, AppLayout.readingHorizontalPadding)
                        .padding(.top, AppSpacing.xs)
                        .readingColumn()
                }
                readerFullContentErrorBanner()
                if let progress = translationProgress {
                    Text(progress)
                        .font(AppTypography.caption())
                        .foregroundStyle(theme.muted)
                        .padding(.horizontal, AppLayout.readingHorizontalPadding)
                        .padding(.top, AppSpacing.xs)
                        .readingColumn()
                }
                if showTranslated,
                   let engineName = currentArticle.translationEngineName?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !engineName.isEmpty {
                    Label("译文来源：\(engineName)", systemImage: "translate")
                        .font(AppTypography.caption())
                        .fontWeight(.medium)
                        .foregroundStyle(theme.muted)
                        .padding(.horizontal, AppLayout.readingHorizontalPadding)
                        .padding(.top, AppSpacing.xs)
                        .readingColumn()
                        .accessibilityLabel("译文来源 \(engineName)")
                }
                if let hint = fullContentHint {
                    Text(hint)
                        .font(AppTypography.caption())
                        .foregroundStyle(theme.muted)
                        .padding(.horizontal, AppLayout.readingHorizontalPadding)
                        .padding(.top, AppSpacing.xs)
                        .readingColumn()
                }

                if shouldOfferFullContent && !isFetchingFull {
                    Button { Task { await fetchFullContent() } } label: {
                        HStack(spacing: AppSpacing.xs) {
                            Image(systemName: "arrow.down.doc")
                                .font(.system(size: 14, weight: .medium))
                            Text("RSS 仅为摘要，点击获取全文")
                                .font(AppTypography.label())
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(theme.muted)
                        }
                        .foregroundStyle(theme.text)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.sm + 2)
                        .background(
                            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                                .fill(theme.surface.opacity(0.6))
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, AppLayout.readingHorizontalPadding)
                    .padding(.top, AppSpacing.md)
                    .readingColumn()
                    .accessibilityHint("获取完整文章内容")
                }

                let displayContent = showTranslated
                    ? (translatedContent ?? currentArticle.translatedContent ?? currentArticle.content)
                    : currentArticle.content
                ArticleContentView(
                    html: displayContent,
                    fontSize: store.fontSize,
                    prefersChineseTypography: showTranslated,
                    onHighlight: { store.addHighlight(articleID: currentArticle.id, text: $0) },
                    suppressArticleSwipe: $suppressArticleSwipe
                )
                .padding(.horizontal, AppLayout.readingHorizontalPadding)
                .padding(.top, AppSpacing.xl)
                .padding(.bottom, 72)
                .readingColumn()
            }
            // 整页内容随文章 id 重建，避免沿用上一篇的 contentOffset
            .id(activeID)
        }
        .background(theme.background)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            // 禁止在此闭包写 AppStore，否则会在布局阶段触发观察更新导致闪退
            geometry.contentOffset.y
        } action: { oldY, newY in
            let delta = newY - oldY
            // 更大阈值；showChrome 仍会触发 toolbar，但避免与进度/高度 State 叠加
            if newY > 56, delta > 6 {
                if showChrome { showChrome = false }
            } else if delta < -6 || newY < 16 {
                if !showChrome { showChrome = true }
            }
            // 进度与内容高度写入 class，不触发 body；UI 进度稀疏更新
            let box = readProgressBox
            if abs(newY - box.lastY) > 24 {
                let h = max(box.contentHeight, box.viewportHeight + 1)
                let p = min(1, max(0, Double((newY + box.viewportHeight) / h)))
                if p > box.progress + 0.05 {
                    box.progress = p
                }
                box.lastY = newY
                // 约每 8% 刷新细进度条，兼顾流畅与反馈
                if abs(p - displayProgress) >= 0.08 {
                    displayProgress = p
                }
            }
        }
        .onScrollGeometryChange(for: CGSize.self) { geometry in
            CGSize(width: geometry.containerSize.height, height: max(geometry.contentSize.height, 1))
        } action: { _, newSize in
            let box = readProgressBox
            box.viewportHeight = newSize.width
            // 高度可直接写 box，无需 @State
            if abs(newSize.height - box.contentHeight) > 40 {
                box.contentHeight = newSize.height
            }
        }
        .onAppear {
            let p = currentArticle.readingProgress
            readProgressBox.progress = p
            displayProgress = p
        }
        .onDisappear {
            let p = readProgressBox.progress
            if p > 0.05 {
                store.updateReadingProgress(articleID: currentArticle.id, progress: p, persist: true)
            }
        }
        .navigationTitle("")
        .appScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(showChrome ? .visible : .hidden, for: .navigationBar)
        .toolbar(showChrome ? .visible : .hidden, for: .tabBar)
        // 导航栏背景始终可见色（与阅读主题一致），避免正文滚到状态栏下方时时间/信号「透字」看不清
        .toolbarBackground(theme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(showChrome ? .automatic : .hidden, for: .tabBar)
        .toolbarColorScheme(readerStatusBarScheme, for: .navigationBar)
        .preferredColorScheme(readerStatusBarScheme)
        // 隐藏导航栏时仍在状态栏区域盖一层主题底色；chrome 可见时显示细阅读进度
        .overlay(alignment: .top) {
            VStack(spacing: 0) {
                if !showChrome {
                    theme.background
                        .frame(height: 0)
                        .frame(maxWidth: .infinity)
                        .background(theme.background.ignoresSafeArea(edges: .top))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                // Editorial reading progress — 1pt hairline under chrome
                if showChrome, displayProgress > 0.02 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(theme.track.opacity(0.35))
                            Rectangle()
                                .fill(theme.accent.opacity(0.55))
                                .frame(width: max(0, geo.size.width * displayProgress))
                        }
                    }
                    .frame(height: 2)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .animation(AppMotion.optional(AppMotion.progress, reduceMotion: reduceMotion), value: displayProgress)
                }
            }
        }
        .animation(AppMotion.optional(AppMotion.chrome, reduceMotion: reduceMotion), value: showChrome)
        // 换篇：明显水平滑动；表格横向滚动时 suppressArticleSwipe 为 true 则忽略
        .simultaneousGesture(
            DragGesture(minimumDistance: 80)
                .onEnded { value in
                    guard !suppressArticleSwipe else { return }
                    let dx = value.translation.width
                    let dy = value.translation.height
                    // 更严：水平为主、位移足够大，避免滑表格/选文字时误换篇
                    guard abs(dx) > 140,
                          abs(dy) < 36,
                          abs(dx) > abs(dy) * 3.5 else { return }
                    if dx < 0 {
                        goNextArticle()
                    } else {
                        goPrevArticle()
                    }
                }
        )
        .onAppear {
            if currentID == nil { currentID = article.id }
            store.markAsRead(currentArticle)
        }
        .task(id: currentArticle.id) {
            // 需要抓全文时：先全文，完成前不做自动翻译（避免译到半截摘要）
            if shouldOfferFullContent {
                await fetchFullContent(silent: true)
            } else {
                await autoTranslateBodyIfNeeded()
            }
        }
        .toolbar {
            // Primary: favorite
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    store.toggleFavorite(currentArticle)
                } label: {
                    Label(currentArticle.isFavorite ? "已收藏" : "收藏",
                          systemImage: currentArticle.isFavorite ? "star.fill" : "star")
                }
                .labelStyle(.iconOnly)
            }

            // Primary: translate (when relevant)
            if showTranslationButton {
                ToolbarItem(placement: .topBarTrailing) {
                    if isTranslating {
                        ProgressView().scaleEffect(0.75)
                    } else if hasUsableTranslation {
                        Menu {
                            Button {
                                Task { await retranslate(preferHigherQuality: false) }
                            } label: {
                                Label("重新翻译", systemImage: "arrow.clockwise")
                            }
                            Button {
                                Task { await retranslate(preferHigherQuality: true) }
                            } label: {
                                Label("更高质量重新翻译", systemImage: "sparkles")
                            }
                            let readyEngines = TranslationEngine.allCases.filter { store.isTranslationEngineReady($0) }
                            if !readyEngines.isEmpty {
                                Section("选择翻译源") {
                                    ForEach(readyEngines, id: \.self) { engine in
                                        Button {
                                            Task { await retranslate(using: engine) }
                                        } label: {
                                            Label(engine.rawValue, systemImage: "globe")
                                        }
                                    }
                                }
                            }
                        } label: {
                            Label(showTranslated ? "原文" : "译文",
                                  systemImage: showTranslated ? "doc.plaintext" : "translate")
                        } primaryAction: {
                            Task { await toggleTranslation() }
                        }
                        .labelStyle(.iconOnly)
                        .accessibilityHint("轻点切换原文/译文；长按可重新翻译或选择翻译源")
                    } else {
                        Menu {
                            Button {
                                Task { await toggleTranslation() }
                            } label: {
                                Label("翻译（自动选择）", systemImage: "translate")
                            }
                            let readyEngines = TranslationEngine.allCases.filter { store.isTranslationEngineReady($0) }
                            if !readyEngines.isEmpty {
                                Section("选择翻译源") {
                                    ForEach(readyEngines, id: \.self) { engine in
                                        Button {
                                            Task { await retranslate(using: engine) }
                                        } label: {
                                            Label(engine.rawValue, systemImage: "globe")
                                        }
                                    }
                                }
                            }
                        } label: {
                            Label("翻译", systemImage: "translate")
                        }
                        .labelStyle(.iconOnly)
                        .accessibilityHint("翻译正文，可选择翻译源")
                    }
                }
            }

            // Secondary actions → overflow menu (editorial, less chrome)
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if fullContentAllowed {
                        Button {
                            Task { await fetchFullContent() }
                        } label: {
                            Label(
                                currentArticle.hasFullContent ? "已获取全文" : "获取全文",
                                systemImage: currentArticle.hasFullContent ? "arrow.down.doc" : "arrow.down.doc.fill"
                            )
                        }
                        .disabled(isFetchingFull)
                    }

                    Button {
                        Task { await generateSummary() }
                    } label: {
                        Label("AI 摘要", systemImage: "wand.and.stars")
                    }
                    .disabled(isGeneratingSummary)

                    Button {
                        Task {
                            let html = showTranslated
                                ? (translatedContent ?? currentArticle.translatedContent ?? currentArticle.content)
                                : currentArticle.content
                            let plain = HTMLUtils.stripTags(html)
                            let fallback = currentArticle.summary
                            let body = plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : plain
                            let text = displayTitle + "\n" + body
                            await tts.toggle(text: text, voice: store.ttsVoice.isEmpty ? nil : store.ttsVoice, rate: store.ttsRate)
                        }
                    } label: {
                        Label(tts.isPlaying ? "停止朗读" : "朗读",
                              systemImage: tts.isPlaying ? "stop.fill" : "speaker.wave.2")
                    }

                    if commentsAllowed {
                        Button {
                            showComments = true
                        } label: {
                            Label("评论", systemImage: "bubble.left.and.bubble.right")
                        }
                    }

                    if let url = URL(string: currentArticle.link) {
                        Divider()
                        Button {
                            openCurrentArticleInBrowser()
                        } label: {
                            Label("在浏览器中打开", systemImage: "safari")
                        }
                        ShareLink(item: url) {
                            Label("分享链接", systemImage: "square.and.arrow.up")
                        }
                    }
                } label: {
                    if isFetchingFull || isGeneratingSummary || tts.isLoading {
                        ProgressView().scaleEffect(0.75)
                    } else {
                        Label("更多", systemImage: "ellipsis.circle")
                    }
                }
                .labelStyle(.iconOnly)
                .accessibilityLabel("更多操作")
            }
        }
        // 使用 item 绑定：换篇时更新 URL，内置浏览器会跟着当前文章刷新
        .sheet(item: $browserItem) { item in
            SafariView(url: item.url).ignoresSafeArea()
                .id(item.id)
        }
        .onDisappear { tts.stop() }
        .navigationDestination(isPresented: $showComments) {
            ArticleCommentsView(
                articleTitle: currentArticle.title,
                articleURL: currentArticle.link,
                commentsURL: currentArticle.commentsURL
            )
        }
        .onAppear {
            aiSummary = currentArticle.aiSummary
            aiSummaryProvider = currentArticle.aiSummaryProvider
            if let cached = currentArticle.translatedContent, !cached.isEmpty {
                translatedContent = cached
                showTranslated = true
            } else if let t = currentArticle.translatedTitle, !t.isEmpty {
                showTranslated = true
            }
            // 全文自动抓取与自动翻译统一由 .task(id:) 串行处理，避免抓取过程中翻译摘要
        }
        .onChange(of: activeID) { _, _ in
            // 左滑/右滑换篇后回到文章开头
            translationError = nil
            summaryError = nil
            fullContentError = nil
            fullContentHint = nil
            translationProgress = nil
            readProgressBox.progress = 0
            readProgressBox.lastY = 0
            displayProgress = 0
            // 若内置浏览器正开着，同步到新文章链接
            if browserItem != nil {
                presentBrowser(for: currentArticle.link)
            }
            // 内容布局可能晚于 id 切换：立即一次 + 短延迟重试，避免偶发停在半页
            scrollReaderToTop(proxy)
        }
        } // ScrollViewReader
    }

    private var fullContentAllowed: Bool {
        store.isFullContentEnabled(for: currentArticle)
    }

    private var commentsAllowed: Bool {
        store.isCommentsEnabled(for: currentArticle)
    }

    private var shouldOfferFullContent: Bool {
        fullContentAllowed && currentArticle.needsFullContentFetch
    }


    @ViewBuilder
    private func readerHighlightsSection() -> some View {
        if !currentArticle.highlights.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Label("高亮 \(currentArticle.highlights.count)", systemImage: "highlighter")
                    .font(AppTypography.caption())
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.muted)
                ForEach(currentArticle.highlights.prefix(8)) { h in
                    HStack(alignment: .top, spacing: AppSpacing.xs) {
                        Text(h.text)
                            .font(AppTypography.font(size: max(13, store.fontSize - 2), weight: .regular))
                            .foregroundStyle(theme.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            store.removeHighlight(articleID: currentArticle.id, highlightID: h.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(theme.muted)
                        }
                        .buttonStyle(.plain)
                        .frame(minWidth: AppLayout.minTapTarget, minHeight: AppLayout.minTapTarget)
                        .accessibilityLabel("删除高亮")
                    }
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, AppSpacing.xs)
                    .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                }
            }
            .padding(.bottom, AppSpacing.sm)
        }
    }

    @ViewBuilder
    private func readerFullContentErrorBanner() -> some View {
        if let err = fullContentError {
            let isCF = err.localizedCaseInsensitiveContains("Cloudflare")
                || err.localizedCaseInsensitiveContains("人机验证")
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Label(
                    isCF ? "需要浏览器验证 · 当前仅摘要" : "全文抓取失败 · 当前仅摘要",
                    systemImage: isCF ? "lock.shield.fill" : "exclamationmark.triangle.fill"
                )
                .font(AppTypography.label())
                .foregroundStyle(.orange)
                Text(err)
                    .font(AppTypography.caption())
                    .foregroundStyle(theme.muted)
                HStack(spacing: AppSpacing.sm) {
                    if isCF, URL(string: currentArticle.link) != nil {
                        Button {
                            openCurrentArticleInBrowser()
                        } label: {
                            Label("浏览器打开", systemImage: "safari")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    Button {
                        Task { await fetchFullContent() }
                    } label: {
                        Label("重试", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isFetchingFull || !fullContentAllowed)
                    if store.fullContentURLPrefixEnabled {
                        Button {
                            Task {
                                if let fid = store.feeds.first(where: { $0.id == currentArticle.feedID })?.id {
                                    store.setFeedUseFullContentURLPrefix(fid, enabled: true)
                                }
                                await fetchFullContent()
                            }
                        } label: {
                            Label("用前缀重试", systemImage: "link")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isFetchingFull)
                    }
                }
            }
            .padding(AppSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color.orange.opacity(0.12),
                in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
            )
            .padding(.horizontal, AppLayout.readingHorizontalPadding)
            .padding(.top, AppSpacing.xs)
            .readingColumn()
        }
    }

    private func fetchFullContent(silent: Bool = false) async {
        guard fullContentAllowed else {
            if !silent { fullContentError = "该订阅源已关闭全文获取" }
            return
        }
        if currentArticle.hasFullContent && !silent {
            fullContentHint = "已是全文内容"
            return
        }
        fullContentError = nil
        isFetchingFull = true
        if !silent { fullContentHint = "正在获取全文…" }
        do {
            let updated = try await store.fetchFullContent(for: currentArticle)
            showTranslated = false
            translatedContent = nil
            fullContentHint = silent ? nil : "已获取全文（约 \(HTMLUtils.stripTags(updated.content).count) 字）"
            // 全文完成后再自动翻译（抓取过程中不翻译）
            isFetchingFull = false
            await autoTranslateBodyIfNeeded()
            if !silent {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                if fullContentHint?.contains("已获取全文") == true { fullContentHint = nil }
            }
            return
        } catch {
            if !silent { fullContentError = error.localizedDescription }
            fullContentHint = nil
        }
        isFetchingFull = false
        // 抓取失败时仍可按摘要尝试自动翻译
        if silent {
            await autoTranslateBodyIfNeeded()
        }
    }

    /// 源开启自动翻译时：打开阅读页自动译正文（已有译文则直接显示）。
    /// 不依赖标题是否已译：列表可能已译标题，正文仍需在打开时翻译。
    /// 全文抓取进行中不翻译。
    private func autoTranslateBodyIfNeeded() async {
        guard !isFetchingFull else { return }
        let feed = store.feeds.first(where: { $0.id == currentArticle.feedID })
        guard feed?.autoTranslateEnabled == true else { return }
        guard !isTranslating else { return }

        // 已有正文译文：直接显示（标题是否已译无关）
        if let cached = currentArticle.translatedContent, !cached.isEmpty {
            translatedContent = cached
            showTranslated = true
            return
        }
        if let local = translatedContent, !local.isEmpty {
            showTranslated = true
            return
        }

        let sample = HTMLUtils.plainText(currentArticle.content)
        if sample.count >= 40, ListLanguageDetect.isMostlyTarget(sample, language: store.targetLanguage) {
            // 正文已是目标语言：不请求翻译
            return
        }
        // 内容过短则只译标题（若尚未译）
        if sample.count < 20 {
            if currentArticle.translatedTitle == nil {
                await translateTitleIfNeeded()
            }
            return
        }

        // 正文需要翻译：即使 showTranslated 因标题已译而为 true，也继续译正文
        await translateBodyForAuto()
    }

    /// 自动翻译正文（不切换「已显示译文」时的关闭逻辑；供 autoTranslateBodyIfNeeded 使用）
    private func translateBodyForAuto() async {
        if let cached = currentArticle.translatedContent, !cached.isEmpty {
            translatedContent = cached
            showTranslated = true
            return
        }
        translationError = nil
        isTranslating = true
        let hint = store.effectiveTranslationChain().first(where: { store.isTranslationEngineReady($0) })
        translationProgress = hint.map { "正在翻译…（\($0.rawValue)）" } ?? "正在翻译…"
        do {
            let titleTask = Task { () -> String? in
                if let existing = currentArticle.translatedTitle, !existing.isEmpty { return existing }
                let t = currentArticle.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !t.isEmpty else { return nil }
                return try? await store.translateText(t)
            }
            let media = HTMLUtils.extractMediaForTranslation(currentArticle.content)
            let result = try await store.translateLongText(media.text, maxChunkChars: 1800)
            let restored = HTMLUtils.restoreMediaAfterTranslation(
                result, images: media.images, tables: media.tables
            )
            translatedContent = Self.wrapTranslatedHTML(restored)
            let translatedTitle = await titleTask.value
            var updated = currentArticle
            updated.translatedContent = translatedContent
            updated.translationEngineName = store.lastUsedTranslationEngine?.rawValue
            if let translatedTitle, !translatedTitle.isEmpty {
                updated.translatedTitle = translatedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            store.updateArticle(updated)
            showTranslated = true
            translationProgress = nil
        } catch {
            translationError = error.localizedDescription
            translationProgress = nil
        }
        isTranslating = false
    }

    /// 译文拼回 HTML：表格/图片原样保留，其余包 <p>
    private static func wrapTranslatedHTML(_ restored: String) -> String {
        let htmlResult = restored
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { part -> String in
                let lower = part.lowercased()
                if lower.contains("<table") || lower.contains("<img") { return part }
                if part.hasPrefix("[[TABLE_") || part.hasPrefix("[[IMG_") { return part }
                return "<p>\(part)</p>"
            }
            .joined()
        return htmlResult.isEmpty ? "<p>\(restored)</p>" : htmlResult
    }

    /// 首次：执行翻译；之后：在原文 / 译文之间切换
    private func toggleTranslation() async {
        // 已在看译文 → 回原文
        if showTranslated {
            showTranslated = false
            translationError = nil
            translationProgress = nil
            return
        }
        // 已有译文（内存或持久化）→ 直接显示译文
        if let local = translatedContent, !local.isEmpty {
            showTranslated = true
            return
        }
        if let cached = currentArticle.translatedContent, !cached.isEmpty {
            translatedContent = cached
            showTranslated = true
            if currentArticle.translatedTitle == nil { Task { await translateTitleIfNeeded() } }
            return
        }
        // 尚无译文 → 按引擎链翻译
        await performBodyTranslation(excluding: [], progressLabel: "正在翻译…")
    }

    /// 重新翻译：清空缓存后重跑引擎链；高质量模式跳过免费引擎
    private func retranslate(preferHigherQuality: Bool) async {
        translatedContent = nil
        var cleared = currentArticle
        cleared.translatedContent = nil
        cleared.translatedTitle = nil
        cleared.translationEngineName = nil
        store.updateArticle(cleared)
        showTranslated = false
        let excluding: Set<TranslationEngine> = preferHigherQuality ? [.google, .mymemory, .lingva] : []
        let label = preferHigherQuality ? "正在用更高质量引擎翻译…" : "正在重新翻译…"
        await performBodyTranslation(excluding: excluding, progressLabel: label)
    }

    /// 指定单一翻译源重新翻译（菜单「选择翻译源」）
    private func retranslate(using engine: TranslationEngine) async {
        translatedContent = nil
        var cleared = currentArticle
        cleared.translatedContent = nil
        cleared.translatedTitle = nil
        cleared.translationEngineName = nil
        store.updateArticle(cleared)
        showTranslated = false
        let excluding = Set(TranslationEngine.allCases.filter { $0 != engine })
        await performBodyTranslation(excluding: excluding, progressLabel: "正在用 \(engine.rawValue) 翻译…")
    }

    private func performBodyTranslation(
        excluding: Set<TranslationEngine>,
        progressLabel: String
    ) async {
        translationError = nil
        isTranslating = true
        let hintEngine = store.effectiveTranslationChain()
            .filter { !excluding.contains($0) && store.isTranslationEngineReady($0) }
            .first
        translationProgress = hintEngine.map { "\(progressLabel)（\($0.rawValue)）" } ?? progressLabel
        do {
            let titleTask = Task { () -> String? in
                let t = currentArticle.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !t.isEmpty else { return nil }
                return try? await store.translateText(t, excluding: excluding)
            }
            let media = HTMLUtils.extractMediaForTranslation(currentArticle.content)
            let result = try await store.translateLongText(
                media.text,
                maxChunkChars: 1800,
                excluding: excluding
            )
            let restored = HTMLUtils.restoreMediaAfterTranslation(
                result, images: media.images, tables: media.tables
            )
            translatedContent = Self.wrapTranslatedHTML(restored)
            let translatedTitle = await titleTask.value
            let usedEngine = store.lastUsedTranslationEngine?.rawValue
            var updated = currentArticle
            updated.translatedContent = translatedContent
            updated.translationEngineName = usedEngine
            if let translatedTitle, !translatedTitle.isEmpty {
                updated.translatedTitle = translatedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            store.updateArticle(updated)
            showTranslated = true
            translationProgress = nil
        } catch {
            translationError = error.localizedDescription
            translationProgress = nil
        }
        isTranslating = false
    }

    private func translateTitleIfNeeded() async {
        guard currentArticle.translatedTitle == nil else { return }
        let t = currentArticle.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if let result = try? await store.translateText(t), !result.isEmpty {
            var updated = currentArticle
            updated.translatedTitle = result.trimmingCharacters(in: .whitespacesAndNewlines)
            store.updateArticle(updated)
        }
    }

    private func goNextArticle() {
        guard let idx = currentIndex, idx + 1 < feedArticles.count else { return }
        let next = feedArticles[idx + 1]
        switchToArticle(next)
    }

    private func goPrevArticle() {
        guard let idx = currentIndex, idx > 0 else { return }
        let prev = feedArticles[idx - 1]
        switchToArticle(prev)
    }

    private func openCurrentArticleInBrowser() {
        presentBrowser(for: currentArticle.link)
    }

    /// 打开或切换内置浏览器到指定文章链接（换篇时先关再开，强制刷新）
    private func presentBrowser(for link: String) {
        let raw = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            browserItem = nil
            return
        }
        let next = BrowserLink(url: url)
        if browserItem?.id == next.id {
            return
        }
        if browserItem != nil {
            browserItem = nil
            DispatchQueue.main.async {
                browserItem = next
            }
        } else {
            browserItem = next
        }
    }

    private func scrollReaderToTop(_ proxy: ScrollViewProxy) {
        // 不用动画，减少与 toolbar/内容切换抢主线程导致的 scrollTo 丢弃
        proxy.scrollTo("readerTop", anchor: .top)
        DispatchQueue.main.async {
            proxy.scrollTo("readerTop", anchor: .top)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            proxy.scrollTo("readerTop", anchor: .top)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            proxy.scrollTo("readerTop", anchor: .top)
        }
    }

    private func switchToArticle(_ next: Article) {
        currentID = next.id
        showTranslated = false
        translatedContent = nil
        aiSummary = next.aiSummary
        aiSummaryProvider = next.aiSummaryProvider
        translationError = nil
        summaryError = nil
        fullContentError = nil
        fullContentHint = nil
        translationProgress = nil
        isTranslating = false
        isGeneratingSummary = false
        isFetchingFull = false
        readProgressBox.progress = next.readingProgress
        readProgressBox.lastY = 0
        displayProgress = next.readingProgress
        store.markAsRead(next)
        // 内置浏览器打开时跟随换篇并刷新页面
        if browserItem != nil {
            presentBrowser(for: next.link)
        }
        showChrome = true
        // 滚动到顶部由 onChange(of: activeID) + 内容 .id(activeID) 处理
    }

    private func generateSummary() async {
        if let existing = currentArticle.aiSummary {
            aiSummary = existing
            aiSummaryProvider = currentArticle.aiSummaryProvider
            summaryExpanded = true
            return
        }
        summaryError = nil
        isGeneratingSummary = true
        do {
            let result = try await store.generateSummary(for: currentArticle)
            aiSummary = result.text
            aiSummaryProvider = result.providerName
            summaryExpanded = true
            var updated = currentArticle
            updated.aiSummary = result.text
            updated.aiSummaryProvider = result.providerName
            store.updateArticle(updated)
        } catch {
            summaryError = error.localizedDescription
        }
        isGeneratingSummary = false
    }
}

/// 滚动过程中的进度/尺寸缓存：用 class 避免写入触发 SwiftUI body 刷新
private final class ReaderScrollMetrics {
    var progress: Double = 0
    var contentHeight: CGFloat = 1
    var viewportHeight: CGFloat = 1
    var lastY: CGFloat = 0
}
