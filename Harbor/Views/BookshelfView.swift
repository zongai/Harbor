import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 书架：本地书籍 + OPDS 书库入口
struct BookshelfView: View {
    @Environment(BookLibrary.self) private var library
    @Environment(OPDSCatalogStore.self) private var opdsCatalogs
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme

    @State private var showImporter = false
    @State private var showAddOPDS = false
    @State private var importError: String?
    @State private var batchProgressText: String?
    @State private var batchProgress: Double = 0
    @State private var isBatchWorking = false
    @State private var bookBatchTTS = BookTTSController()
    @State private var batchTask: Task<Void, Never>?
    /// 全书任务：选起始章
    @State private var batchPickerBook: Book?
    @State private var batchPickerKind: BookBatchKind = .translate
    @State private var batchStartChapterIndex: Int = 0
    @State private var batchWorkingBookID: UUID?

    private var recentBooks: [Book] {
        library.books
            .filter { $0.lastReadDate != nil }
            .sorted { ($0.lastReadDate ?? .distantPast) > ($1.lastReadDate ?? .distantPast) }
            .prefix(3)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            List {
                if !recentBooks.isEmpty {
                    Section("最近阅读") {
                        ForEach(recentBooks) { book in
                            NavigationLink(value: book.id) {
                                BookRow(book: book)
                            }
                            .listRowBackground(Color.clear)
                            .contextMenu { bookContextMenu(book) }
                        }
                    }
                }

                Section("本地书籍") {
                    if library.books.isEmpty {
                        Text("尚未导入书籍")
                            .font(AppTypography.body())
                            .foregroundStyle(theme.muted)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(library.books) { book in
                            NavigationLink(value: book.id) {
                                BookRow(book: book)
                            }
                            .listRowBackground(Color.clear)
                            .contextMenu { bookContextMenu(book) }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    library.deleteBook(id: book.id)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                }

                Section("OPDS") {
                    ForEach(opdsCatalogs.catalogs) { cat in
                        NavigationLink {
                            OPDSBrowserView(
                                rootTitle: cat.title,
                                rootURL: cat.url,
                                username: cat.username,
                                password: OPDSCredentialStore.password(catalogID: cat.id)
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(cat.title)
                                        .font(AppTypography.listTitle())
                                    if cat.hasCredentials {
                                        Image(systemName: "lock.fill")
                                            .font(.caption2)
                                            .foregroundStyle(theme.muted)
                                    }
                                }
                                Text(cat.url)
                                    .font(AppTypography.caption())
                                    .foregroundStyle(theme.muted)
                                    .lineLimit(1)
                            }
                        }
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                opdsCatalogs.remove(id: cat.id)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                    if opdsCatalogs.catalogs.isEmpty {
                        Text("点右上角 + 可添加 OPDS 书库或导入 EPUB")
                            .font(AppTypography.caption())
                            .foregroundStyle(theme.muted)
                            .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .appScreenBackground()
            .navigationTitle("书籍")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: UUID.self) { id in
                BookReaderView(bookID: id)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showImporter = true
                        } label: {
                            Label("导入 EPUB", systemImage: "doc.badge.plus")
                        }
                        .disabled(library.isImporting)
                        Button {
                            showAddOPDS = true
                        } label: {
                            Label("添加 OPDS 书库", systemImage: "server.rack")
                        }
                    } label: {
                        Label("添加", systemImage: "plus")
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("添加书籍或 OPDS")
                }
            }
            .overlay {
                if library.isImporting {
                    ProgressView("正在导入…")
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                } else if isBatchWorking {
                    VStack(spacing: 10) {
                        ProgressView(value: batchProgress)
                            .frame(width: 180)
                        Text(batchProgressText ?? "处理中…")
                            .font(AppTypography.caption())
                            .foregroundStyle(theme.muted)
                            .multilineTextAlignment(.center)
                        Button("取消") {
                            batchTask?.cancel()
                            bookBatchTTS.stop()
                            if let id = batchWorkingBookID {
                                if batchPickerKind == .tts || bookBatchTTS.isCaching {
                                    let idx = BookJobProgress.loadTTS(bookID: id) ?? 0
                                    BookJobProgress.markTTSInterrupted(bookID: id, chapterIndex: idx)
                                } else {
                                    let idx = BookJobProgress.loadTranslate(bookID: id) ?? 0
                                    BookJobProgress.markTranslateInterrupted(bookID: id, chapterIndex: idx)
                                }
                            }
                            isBatchWorking = false
                            batchProgressText = "已暂停，可继续"
                        }
                        .font(AppTypography.caption())
                    }
                    .padding(16)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .sheet(isPresented: $showImporter) {
                EPUBDocumentPicker { url in
                    showImporter = false
                    guard let url else { return }
                    Task {
                        do {
                            _ = try await library.importEPUB(from: url)
                        } catch {
                            importError = error.localizedDescription
                        }
                    }
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showAddOPDS) {
                NavigationStack {
                    AddOPDSCatalogView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("关闭") { showAddOPDS = false }
                            }
                        }
                }
            }
            .alert("导入失败", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("好", role: .cancel) { importError = nil }
            } message: {
                Text(importError ?? "")
            }
            .sheet(item: $batchPickerBook) { book in
                BookBatchStartPicker(
                    book: book,
                    kind: batchPickerKind,
                    initialIndex: suggestedStartIndex(for: book, kind: batchPickerKind),
                    onConfirm: { startIdx in
                        batchPickerBook = nil
                        if batchPickerKind == .translate {
                            runWholeBookTranslate(book, from: startIdx)
                        } else {
                            runWholeBookTTSCache(book, from: startIdx)
                        }
                    },
                    onCancel: { batchPickerBook = nil }
                )
            }
        }
    }

    @ViewBuilder
    private func bookContextMenu(_ book: Book) -> some View {
        let canResumeTranslate = BookJobProgress.hasIncompleteTranslate(bookID: book.id)
        let canResumeTTS = BookJobProgress.hasIncompleteTTS(bookID: book.id)
        let resumeTranslateIdx = BookJobProgress.resolveTranslateStart(
            book: book,
            targetLanguage: store.targetLanguage.rawValue
        )
        let resumeTTSIdx = BookJobProgress.resolveTTSStart(book: book)

        if canResumeTranslate {
            Button {
                runWholeBookTranslate(book, from: resumeTranslateIdx)
            } label: {
                Label("继续翻译（第 \(resumeTranslateIdx + 1) 章）", systemImage: "arrow.clockwise")
            }
            .disabled(isBatchWorking)
        }
        Button {
            batchPickerKind = .translate
            batchPickerBook = book
        } label: {
            Label(canResumeTranslate ? "全书翻译（重选起点）…" : "全书翻译…", systemImage: "character.book.closed")
        }
        .disabled(isBatchWorking)

        if canResumeTTS {
            Button {
                runWholeBookTTSCache(book, from: resumeTTSIdx)
            } label: {
                Label("继续 TTS（第 \(resumeTTSIdx + 1) 章）", systemImage: "arrow.clockwise")
            }
            .disabled(isBatchWorking)
        }
        Button {
            batchPickerKind = .tts
            batchPickerBook = book
        } label: {
            Label(canResumeTTS ? "全书 TTS（重选起点）…" : "全书 TTS 缓存…", systemImage: "arrow.down.circle")
        }
        .disabled(isBatchWorking)

        Divider()
        Button(role: .destructive) {
            library.deleteBook(id: book.id)
        } label: {
            Label("删除", systemImage: "trash")
        }
    }

    private func suggestedStartIndex(for book: Book, kind: BookBatchKind) -> Int {
        switch kind {
        case .translate:
            return BookJobProgress.resolveTranslateStart(
                book: book,
                targetLanguage: store.targetLanguage.rawValue
            )
        case .tts:
            return BookJobProgress.resolveTTSStart(book: book)
        }
    }

    private func runWholeBookTranslate(_ book: Book, from startIdx: Int) {
        batchTask?.cancel()
        isBatchWorking = true
        batchWorkingBookID = book.id
        batchPickerKind = .translate
        batchProgress = 0
        batchProgressText = "从第 \(startIdx + 1) 章继续翻译…"
        batchTask = Task {
            do {
                try await BookTranslationService.translateBook(
                    book: book,
                    targetLanguage: store.targetLanguage,
                    store: store,
                    fromChapterIndex: startIdx
                ) { p, msg in
                    Task { @MainActor in
                        batchProgress = p
                        batchProgressText = msg
                    }
                }
                batchProgressText = "全书翻译完成"
            } catch is CancellationError {
                batchProgressText = "已暂停，可继续"
            } catch {
                importError = error.localizedDescription
                batchProgressText = "已中断，可继续"
            }
            isBatchWorking = false
        }
    }

    private func runWholeBookTTSCache(_ book: Book, from startIdx: Int) {
        batchTask?.cancel()
        isBatchWorking = true
        batchWorkingBookID = book.id
        batchPickerKind = .tts
        batchProgress = 0
        batchProgressText = "从第 \(startIdx + 1) 章继续缓存…"
        let voice = store.ttsVoice.isEmpty ? nil : store.ttsVoice
        bookBatchTTS.precacheBook(book: book, voice: voice, fromChapterIndex: startIdx) { p, msg in
            batchProgress = p
            batchProgressText = msg
            if p >= 1 || msg.contains("暂停") {
                isBatchWorking = false
            }
        }
        batchTask = Task {
            while !Task.isCancelled && isBatchWorking && bookBatchTTS.isCaching {
                try? await Task.sleep(nanoseconds: 300_000_000)
                batchProgress = bookBatchTTS.cacheProgress
                if let s = bookBatchTTS.statusText { batchProgressText = s }
            }
            if let err = bookBatchTTS.errorMessage {
                importError = err
            }
            if bookBatchTTS.statusText?.contains("暂停") == true {
                batchProgressText = bookBatchTTS.statusText
            }
            isBatchWorking = false
        }
    }
}

private enum BookBatchKind {
    case translate, tts
}

/// 选择全书任务起始章节
private struct BookBatchStartPicker: View {
    let book: Book
    let kind: BookBatchKind
    let initialIndex: Int
    let onConfirm: (Int) -> Void
    let onCancel: () -> Void

    @State private var selectedIndex: Int = 0

    private var chapters: [BookChapter] {
        book.chapters.sorted { $0.index < $1.index }
    }

    private var hasResume: Bool {
        switch kind {
        case .translate: return BookJobProgress.hasIncompleteTranslate(bookID: book.id)
        case .tts: return BookJobProgress.hasIncompleteTTS(bookID: book.id)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if hasResume {
                    Section {
                        Text("上次停在第 \(initialIndex + 1) 章。可直接继续，或改选其他起点。已完成的章节/段落会自动跳过。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("从断点继续（第 \(initialIndex + 1) 章）") {
                            onConfirm(initialIndex)
                        }
                    }
                }
                Section {
                    Text(kind == .translate
                         ? "从选定章节开始翻译。已译章节会跳过，不会重复请求。"
                         : "从选定章节开始缓存语音。已有音频会命中缓存，不重复合成。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("起始章节") {
                    Picker("章节", selection: $selectedIndex) {
                        ForEach(chapters, id: \.id) { ch in
                            Text(chapterLabel(ch)).tag(ch.index)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.inline)
                }
            }
            .navigationTitle(kind == .translate ? "全书翻译" : "全书 TTS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(hasResume && selectedIndex == initialIndex ? "继续" : "开始") {
                        onConfirm(selectedIndex)
                    }
                }
            }
            .onAppear { selectedIndex = initialIndex }
        }
    }

    private func chapterLabel(_ ch: BookChapter) -> String {
        let t = ch.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty {
            return "\(ch.index + 1). \(t)"
        }
        return "第 \(ch.index + 1) 章"
    }
}

private struct BookRow: View {
    @Environment(BookLibrary.self) private var library
    @Environment(\.theme) private var theme
    let book: Book

    var body: some View {
        HStack(spacing: 12) {
            cover
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(AppTypography.listTitle())
                    .foregroundStyle(theme.text)
                    .lineLimit(2)
                if let author = book.author, !author.isEmpty {
                    Text(author)
                        .font(AppTypography.caption())
                        .foregroundStyle(theme.muted)
                        .lineLimit(1)
                }
                HStack(spacing: 4) {
                    Text("\(book.totalChapters) 章")
                    if let lang = book.language, !lang.isEmpty {
                        Text("·")
                        Text(lang)
                    }
                }
                .font(AppTypography.caption())
                .foregroundStyle(theme.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var cover: some View {
        let img = library.coverImage(for: book)
        Group {
            if let img {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    theme.card
                    Image(systemName: "book.closed")
                        .foregroundStyle(theme.muted)
                }
            }
        }
        .frame(width: 52, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// 使用 UIDocumentPicker，类型放宽到 item/data/zip/epub，避免 .epub 在文件 App 中不可选
struct EPUBDocumentPicker: UIViewControllerRepresentable {
    var onPick: (URL?) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        var types: [UTType] = [.item, .data, .content]
        if let epub = UTType(filenameExtension: "epub") {
            types.insert(epub, at: 0)
        }
        if let zip = UTType(filenameExtension: "zip") {
            types.insert(zip, at: 0)
        }
        if let idpf = UTType("org.idpf.epub-container") {
            types.insert(idpf, at: 0)
        }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL?) -> Void
        init(onPick: @escaping (URL?) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls.first)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onPick(nil)
        }
    }
}
