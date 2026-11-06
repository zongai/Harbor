import Foundation
import Observation
import UIKit
import UniformTypeIdentifiers

/// 本地书库：元数据索引 + 每本书独立目录（与 AppStore / RSS 隔离）
@Observable
@MainActor
final class BookLibrary {
    private(set) var books: [Book] = []
    var isImporting = false
    var lastError: String?

    private static let indexFileName = "library_index.json"

    private static var rootURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let url = base.appendingPathComponent("Harbor/Books", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static var indexURL: URL {
        rootURL.appendingPathComponent(indexFileName)
    }

    static func bookDirectory(id: UUID) -> URL {
        rootURL.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    init() {
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: Self.indexURL),
              let list = try? JSONDecoder().decode([Book].self, from: data) else {
            books = []
            return
        }
        books = list.sorted {
            ($0.lastReadDate ?? $0.importDate) > ($1.lastReadDate ?? $1.importDate)
        }
    }

    private func saveIndex() {
        do {
            let data = try JSONEncoder().encode(books)
            try data.write(to: Self.indexURL, options: [.atomic])
        } catch {
            lastError = "书架索引写入失败：\(error.localizedDescription)"
        }
    }

    /// 导入本地 EPUB（后台解析，主线程更新索引）
    @discardableResult
    func importEPUB(from sourceURL: URL) async throws -> Book {
        isImporting = true
        lastError = nil
        defer { isImporting = false }

        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }

        let ext = sourceURL.pathExtension.lowercased()
        if !ext.isEmpty, ext != "epub", ext != "zip" {
            throw BookImportError.io("请选择 .epub 文件（当前：.\(ext)）")
        }

        let bookID = UUID()
        let dir = Self.bookDirectory(id: bookID)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let destEPUB = dir.appendingPathComponent("book.epub")
        if FileManager.default.fileExists(atPath: destEPUB.path) {
            try FileManager.default.removeItem(at: destEPUB)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destEPUB)

        let parseResult = try await Task.detached(priority: .userInitiated) {
            try EPUBParser.parse(epubURL: destEPUB, bookID: bookID)
        }.value

        let extractDir = dir.appendingPathComponent("extracted", isDirectory: true)
        let entries = try await Task.detached(priority: .userInitiated) {
            try MinimalZip.entries(from: destEPUB)
        }.value
        try MinimalZip.extract(entries: entries, to: extractDir)

        var book = parseResult.book
        if let cover = parseResult.coverData, let name = book.coverFileName {
            try? cover.write(to: dir.appendingPathComponent(name), options: [.atomic])
        }

        let metaURL = dir.appendingPathComponent("metadata.json")
        if let data = try? JSONEncoder().encode(book) {
            try? data.write(to: metaURL, options: [.atomic])
        }

        books.insert(book, at: 0)
        saveIndex()
        return book
    }

    func deleteBook(id: UUID) {
        books.removeAll { $0.id == id }
        saveIndex()
        // 书文件：EPUB / 解压 HTML / 封面 / metadata
        try? FileManager.default.removeItem(at: Self.bookDirectory(id: id))
        // 语音缓存、译文缓存、全书任务断点
        BookTTSController.clearBookCache(bookID: id)
        BookTranslationService.clearBook(bookID: id)
        BookJobProgress.clearTTS(bookID: id)
        BookJobProgress.clearTranslate(bookID: id)
        BookTTSPositionStore.clear(bookID: id)
    }

    func updateBook(_ book: Book) {
        guard let i = books.firstIndex(where: { $0.id == book.id }) else { return }
        books[i] = book
        saveIndex()
        let metaURL = Self.bookDirectory(id: book.id).appendingPathComponent("metadata.json")
        if let data = try? JSONEncoder().encode(book) {
            try? data.write(to: metaURL, options: [.atomic])
        }
    }

    func coverImage(for book: Book) -> UIImage? {
        guard let name = book.coverFileName else { return nil }
        let url = Self.bookDirectory(id: book.id).appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    func chapterHTML(book: Book, chapter: BookChapter) -> String? {
        EPUBParser.loadChapterHTML(
            bookDirectory: Self.bookDirectory(id: book.id),
            href: chapter.href
        )
    }

    /// 导出书架元数据索引（不含 EPUB 文件本体）
    func exportIndex() -> [Book] {
        books
    }

    /// 从备份恢复阅读进度与索引：仅当本地仍有 book.epub 时写入；按 id 优先，其次标题+作者
    @discardableResult
    func importIndex(_ imported: [Book]) -> (updated: Int, skipped: Int) {
        var updated = 0
        var skipped = 0
        for b in imported {
            let epubPath = Self.bookDirectory(id: b.id).appendingPathComponent("book.epub").path
            if FileManager.default.fileExists(atPath: epubPath) {
                if let i = books.firstIndex(where: { $0.id == b.id }) {
                    books[i] = b
                } else {
                    books.append(b)
                }
                let metaURL = Self.bookDirectory(id: b.id).appendingPathComponent("metadata.json")
                if let data = try? JSONEncoder().encode(b) {
                    try? data.write(to: metaURL, options: [.atomic])
                }
                updated += 1
                continue
            }
            // 同书重新导入后 id 可能不同：按标题+作者合并进度
            if let i = books.firstIndex(where: {
                Self.normalizeTitle($0.title) == Self.normalizeTitle(b.title)
                    && Self.normalizeAuthor($0.author) == Self.normalizeAuthor(b.author)
            }) {
                books[i].lastReadDate = b.lastReadDate ?? books[i].lastReadDate
                books[i].lastChapterID = b.lastChapterID ?? books[i].lastChapterID
                books[i].readingProgress = max(books[i].readingProgress, b.readingProgress)
                books[i].lastScrollProgress = b.lastScrollProgress
                let metaURL = Self.bookDirectory(id: books[i].id).appendingPathComponent("metadata.json")
                if let data = try? JSONEncoder().encode(books[i]) {
                    try? data.write(to: metaURL, options: [.atomic])
                }
                updated += 1
            } else {
                skipped += 1
            }
        }
        books.sort {
            ($0.lastReadDate ?? $0.importDate) > ($1.lastReadDate ?? $1.importDate)
        }
        saveIndex()
        return (updated, skipped)
    }

    private static func normalizeTitle(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func normalizeAuthor(_ s: String?) -> String {
        (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

extension Notification.Name {
    /// 设置备份导入了书架 / OPDS 后，通知界面刷新内存中的 BookLibrary / OPDSCatalogStore
    static let harborBookDataDidImport = Notification.Name("harborBookDataDidImport")
}

