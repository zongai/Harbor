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
        try? FileManager.default.removeItem(at: Self.bookDirectory(id: id))
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
}
