import Foundation

enum BookReadingMode: String, CaseIterable, Identifiable, Sendable {
    case original
    case translation
    case bilingual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: return "原文"
        case .translation: return "译文"
        case .bilingual: return "双语"
        }
    }
}

struct BookChapterTranslation: Codable, Sendable {
    var bookID: UUID
    var chapterID: UUID
    var targetLanguage: String
    var paragraphs: [AlignedParagraph]
    var updatedAt: Date
    var status: Status

    enum Status: String, Codable, Sendable {
        case idle, translating, done, failed
    }

    struct AlignedParagraph: Codable, Sendable {
        var original: String
        var translated: String
    }

    /// 译文 HTML（段落）
    var translationHTML: String {
        paragraphs
            .map { "<p>\(Self.escape($0.translated))</p>" }
            .joined(separator: "\n")
    }

    /// 双语 HTML：原文段 + 译文段
    var bilingualHTML: String {
        paragraphs.map { p in
            let o = p.original.trimmingCharacters(in: .whitespacesAndNewlines)
            let t = p.translated.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !o.isEmpty else { return "" }
            if t.isEmpty {
                return "<p>\(Self.escape(o))</p>"
            }
            return "<p>\(Self.escape(o))</p>\n<p><em>\(Self.escape(t))</em></p>"
        }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

/// 章节翻译缓存 + 按段对齐（复用 AppStore.translateLongText / translateText）
enum BookTranslationService {
    private static var rootURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let url = base.appendingPathComponent("Harbor/BookTranslations", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func fileURL(bookID: UUID, chapterID: UUID) -> URL {
        let dir = rootURL.appendingPathComponent(bookID.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(chapterID.uuidString).json")
    }

    static func load(bookID: UUID, chapterID: UUID) -> BookChapterTranslation? {
        let url = fileURL(bookID: bookID, chapterID: chapterID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(BookChapterTranslation.self, from: data)
    }

    static func save(_ payload: BookChapterTranslation) {
        let url = fileURL(bookID: bookID(payload), chapterID: payload.chapterID)
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: url, options: [.atomic])
        }
    }

    private static func bookID(_ p: BookChapterTranslation) -> UUID { p.bookID }

    /// 从 HTML 抽出段落纯文本（用于对齐翻译）
    static func plainParagraphs(fromHTML html: String) -> [String] {
        // 先按块级标签切开
        var text = html
        let blockTags = ["p", "div", "h1", "h2", "h3", "h4", "li", "tr", "section", "article"]
        for tag in blockTags {
            text = text.replacingOccurrences(
                of: "</\(tag)>",
                with: "</\(tag)>\n\n",
                options: [.caseInsensitive]
            )
        }
        let plain = HTMLUtils.stripTags(text)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return plain
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// 翻译本章：按段调用 AppStore.translateLongText，结果落盘
    @MainActor
    static func translateChapter(
        bookID: UUID,
        chapterID: UUID,
        html: String,
        targetLanguage: AppLanguage,
        store: AppStore,
        onProgress: ((Double, String) -> Void)? = nil
    ) async throws -> BookChapterTranslation {
        let paras = plainParagraphs(fromHTML: html)
        guard !paras.isEmpty else {
            throw TranslationError.apiError("本章没有可翻译的文本")
        }

        var aligned: [BookChapterTranslation.AlignedParagraph] = []
        aligned.reserveCapacity(paras.count)

        for (i, original) in paras.enumerated() {
            onProgress?(Double(i) / Double(paras.count), "翻译 \(i + 1)/\(paras.count)")
            // 单段过长仍走 long text chunk
            let translated: String
            if original.count > 1600 {
                translated = try await store.translateLongText(original)
            } else {
                translated = try await store.translateText(original)
            }
            aligned.append(.init(original: original, translated: translated))
        }
        onProgress?(1, "翻译完成")

        let payload = BookChapterTranslation(
            bookID: bookID,
            chapterID: chapterID,
            targetLanguage: targetLanguage.rawValue,
            paragraphs: aligned,
            updatedAt: Date(),
            status: .done
        )
        save(payload)
        return payload
    }

    static func clearBook(bookID: UUID) {
        let dir = rootURL.appendingPathComponent(bookID.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
    }
}
