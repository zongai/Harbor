import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 书架：本地书籍 + OPDS 书库入口
struct BookshelfView: View {
    @Environment(BookLibrary.self) private var library
    @Environment(OPDSCatalogStore.self) private var opdsCatalogs
    @Environment(\.theme) private var theme
    @State private var showImporter = false
    @State private var showAddOPDS = false
    @State private var importError: String?
    @State private var batchProgressText: String?
    @State private var batchProgress: Double = 0
    @State private var isBatchWorking = false
    @State private var bookBatchTTS = BookTTSController()
    @Environment(AppStore.self) private var store

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
                            .contextMenu {
                                Button {
                                    startWholeBookTranslate(book)
                                } label: {
                                    Label("全书翻译", systemImage: "character.book.closed")
                                }
                                .disabled(isBatchWorking)
                                Button {
                                    startWholeBookTTSCache(book)
                                } label: {
                                    Label("全书 TTS 缓存", systemImage: "arrow.down.circle")
                                }
                                .disabled(isBatchWorking)
                            }
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
                            .contextMenu {
                                Button {
                                    startWholeBookTranslate(book)
                                } label: {
                                    Label("全书翻译", systemImage: "character.book.closed")
                                }
                                .disabled(isBatchWorking)
                                Button {
                                    startWholeBookTTSCache(book)
                                } label: {
                                    Label("全书 TTS 缓存", systemImage: "arrow.down.circle")
                                }
                                .disabled(isBatchWorking)
                                Divider()
                                Button(role: .destructive) {
                                    library.deleteBook(id: book.id)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
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
                            bookBatchTTS.stop()
                            isBatchWorking = false
                            batchProgressText = nil
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
        }
    }
}

    private func startWholeBookTranslate(_ book: Book) {
        isBatchWorking = true
        batchProgress = 0
        batchProgressText = "准备全书翻译…"
        Task {
            do {
                try await BookTranslationService.translateBook(
                    book: book,
                    targetLanguage: store.targetLanguage,
                    store: store
                ) { p, msg in
                    Task { @MainActor in
                        batchProgress = p
                        batchProgressText = msg
                    }
                }
                batchProgressText = "全书翻译完成"
            } catch is CancellationError {
                batchProgressText = "已取消"
            } catch {
                importError = error.localizedDescription
            }
            isBatchWorking = false
        }
    }

    private func startWholeBookTTSCache(_ book: Book) {
        isBatchWorking = true
        batchProgress = 0
        batchProgressText = "准备全书语音缓存…"
        let voice = store.ttsVoice.isEmpty ? nil : store.ttsVoice
        bookBatchTTS.precacheBook(book: book, voice: voice) { p, msg in
            batchProgress = p
            batchProgressText = msg
            if p >= 1 {
                isBatchWorking = false
            }
        }
        // 若立即失败
        Task {
            while isBatchWorking && bookBatchTTS.isCaching {
                try? await Task.sleep(nanoseconds: 300_000_000)
                batchProgress = bookBatchTTS.cacheProgress
                if let s = bookBatchTTS.statusText { batchProgressText = s }
            }
            if bookBatchTTS.errorMessage != nil {
                importError = bookBatchTTS.errorMessage
            }
            isBatchWorking = false
        }
    }

private struct BookRow: View {
    @Environment(BookLibrary.self) private var library
    @Environment(\.theme) private var theme
    let book: Book

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
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
                HStack(spacing: 8) {
                    Text(book.progressPercentText)
                    Text("·")
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
        // IDPF / EPUB 常用 UTI
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
