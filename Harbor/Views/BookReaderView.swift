import SwiftUI

/// EPUB 阅读器（Phase 3）：章节切换、目录、位置记忆、复用正文选区 / AI 解释
struct BookReaderView: View {
    @Environment(BookLibrary.self) private var library
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var systemColorScheme

    let bookID: UUID

    @State private var book: Book?
    @State private var chapterIndex: Int = 0
    @State private var chapterHTML: String = ""
    @State private var isLoadingChapter = false
    @State private var loadError: String?
    @State private var showTOC = false
    @State private var showChrome = true
    @State private var bookTTS = BookTTSController()
    @State private var ttsRate: Double = 1.0
    @State private var readingMode: BookReadingMode = .original
    @State private var chapterTranslation: BookChapterTranslation?
    @State private var isTranslatingChapter = false
    @State private var translationProgressText: String?

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
    }

    @ViewBuilder
    private func readerBody(_ book: Book) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                if let ch = currentChapter {
                    Text(ch.title)
                        .font(AppTypography.articleTitle(size: CGFloat(store.readerTitleFontSize)))
                        .foregroundStyle(theme.text)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("\(chapterIndex + 1) / \(max(chapters.count, 1)) · \(book.title)")
                        .font(AppTypography.articleMeta())
                        .foregroundStyle(theme.muted)
                }

                if isLoadingChapter {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else if let loadError {
                    Text(loadError)
                        .font(AppTypography.body())
                        .foregroundStyle(.red)
                } else if displayHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(emptyContentHint)
                        .font(AppTypography.body())
                        .foregroundStyle(theme.muted)
                        .padding(.vertical, 24)
                } else {
                    if isTranslatingChapter {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(translationProgressText ?? "翻译中…")
                                .font(AppTypography.caption())
                                .foregroundStyle(theme.muted)
                        }
                        .padding(.vertical, 8)
                    }
                    // 复用 RSS 正文组件：选区 + AI 解释
                    ArticleContentView(
                        html: displayHTML,
                        fontSize: store.fontSize,
                        prefersChineseTypography: prefersChineseForDisplay(book),
                        articleTitle: currentChapter?.title ?? ""
                    )
                    .id("\(readingMode.rawValue)-\(currentChapter?.id.uuidString ?? "")-\(chapterTranslation?.updatedAt.timeIntervalSince1970 ?? 0)")
                }
            }
            .padding(.horizontal, AppLayout.readingHorizontalPadding)
            .padding(.vertical, AppSpacing.lg)
            .padding(.bottom, 48)
        }
        .appScreenBackground()
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    ForEach(BookReadingMode.allCases) { mode in
                        Button {
                            readingMode = mode
                        } label: {
                            HStack {
                                Text(mode.title)
                                if readingMode == mode {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
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
                } label: {
                    Label("语速", systemImage: "gauge.with.dots.needle.33percent")
                }
                .labelStyle(.iconOnly)

                Button {
                    guard let ch = currentChapter else { return }
                    bookTTS.playbackRate = ttsRate
                    bookTTS.toggleChapter(
                        bookID: bookID,
                        chapterID: ch.id,
                        html: chapterHTML,
                        voice: store.ttsVoice.isEmpty ? nil : store.ttsVoice,
                        rate: ttsRate
                    )
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
                                    Text("第 \(idx + 1) 章")
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


    private var displayHTML: String {
        switch readingMode {
        case .original:
            return chapterHTML
        case .translation:
            return chapterTranslation?.translationHTML ?? ""
        case .bilingual:
            return chapterTranslation?.bilingualHTML ?? chapterHTML
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
            return
        }
        chapterTranslation = BookTranslationService.load(bookID: bookID, chapterID: ch.id)
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
            if readingMode == .original {
                readingMode = .bilingual
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

    private func bootstrap() {
        guard let b = library.books.first(where: { $0.id == bookID }) else {
            // 尝试从磁盘 metadata 恢复
            library.load()
            book = library.books.first(where: { $0.id == bookID })
            return
        }
        book = b
        if let lastID = b.lastChapterID,
           let idx = b.chapters.sorted(by: { $0.index < $1.index }).firstIndex(where: { $0.id == lastID }) {
            chapterIndex = idx
        } else {
            chapterIndex = 0
        }
        Task { await loadCurrentChapter() }
        touchLastRead()
    }

    private func selectChapter(_ idx: Int) {
        guard chapters.indices.contains(idx) else { return }
        chapterIndex = idx
        persistPosition()
    }

    private func loadCurrentChapter() async {
        guard let book, let ch = currentChapter else {
            chapterHTML = ""
            return
        }
        isLoadingChapter = true
        loadError = nil
        let html = library.chapterHTML(book: book, chapter: ch)
        await MainActor.run {
            if let html, !html.isEmpty {
                chapterHTML = html
            } else {
                chapterHTML = ""
                loadError = "无法加载本章内容（\(ch.href)）"
            }
            isLoadingChapter = false
            loadTranslationIfNeeded()
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
        let n = max(b.chapters.count, 1)
        b.readingProgress = Double(chapterIndex + 1) / Double(n)
        // 同步章节进度标记
        if let i = b.chapters.firstIndex(where: { $0.id == ch.id }) {
            b.chapters[i].readingProgress = 1
        }
        book = b
        library.updateBook(b)
    }
}
