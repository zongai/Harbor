import SwiftUI
import UniformTypeIdentifiers

/// 书架（Phase 2：本地导入 + 列表；阅读器 / OPDS 后续 Phase）
struct BookshelfView: View {
    @Environment(BookLibrary.self) private var library
    @Environment(\.theme) private var theme
    @State private var showImporter = false
    @State private var importError: String?

    var body: some View {
        NavigationStack {
            Group {
                if library.books.isEmpty {
                    ContentUnavailableView {
                        Label {
                            Text("暂无书籍")
                                .font(AppTypography.section())
                        } icon: {
                            Image(systemName: "books.vertical")
                                .foregroundStyle(theme.muted)
                        }
                    } description: {
                        Text("导入 EPUB 后显示在书架。OPDS 与阅读器将在后续版本提供。")
                            .font(AppTypography.body())
                            .foregroundStyle(theme.muted)
                    } actions: {
                        Button("导入 EPUB") { showImporter = true }
                            .buttonStyle(.borderedProminent)
                            .tint(theme.accent)
                    }
                } else {
                    List {
                        ForEach(library.books) { book in
                            NavigationLink(value: book.id) {
                                BookRow(book: book)
                            }
                            .listRowInsets(EdgeInsets(
                                top: 8,
                                leading: AppLayout.listHorizontalPadding,
                                bottom: 8,
                                trailing: AppLayout.listHorizontalPadding
                            ))
                            .listRowSeparator(.hidden)
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
                    .listStyle(.plain)
                    .navigationDestination(for: UUID.self) { id in
                        BookReaderView(bookID: id)
                    }
                }
            }
            .appScreenBackground()
            .navigationTitle("书籍")
            .navigationBarTitleDisplayMode(.large)
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
