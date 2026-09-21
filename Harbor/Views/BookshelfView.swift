import SwiftUI
import UniformTypeIdentifiers

/// 书架：本地书籍 + OPDS 书库入口
struct BookshelfView: View {
    @Environment(BookLibrary.self) private var library
    @Environment(OPDSCatalogStore.self) private var opdsCatalogs
    @Environment(\.theme) private var theme
    @State private var showImporter = false
    @State private var showAddOPDS = false
    @State private var importError: String?

    private var recentBooks: [Book] {
        library.books
            .filter { $0.lastReadDate != nil }
            .sorted { ($0.lastReadDate ?? .distantPast) > ($1.lastReadDate ?? .distantPast) }
            .prefix(8)
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
                    Button {
                        showAddOPDS = true
                    } label: {
                        Label("添加 OPDS 书库", systemImage: "plus.circle")
                    }
                    .listRowBackground(Color.clear)
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
                    Button {
                        showImporter = true
                    } label: {
                        Label("导入 EPUB", systemImage: "plus")
                    }
                    .labelStyle(.iconOnly)
                    .disabled(library.isImporting)
                }
            }
            .overlay {
                if library.isImporting {
                    ProgressView("正在导入…")
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [
                    UTType(filenameExtension: "epub") ?? .data,
                    .data
                ],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    Task {
                        do {
                            _ = try await library.importEPUB(from: url)
                        } catch {
                            importError = error.localizedDescription
                        }
                    }
                case .failure(let error):
                    importError = error.localizedDescription
                }
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
