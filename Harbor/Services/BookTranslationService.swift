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

    /// 章内翻译：短段批量 API + 长段受控并发（优先吞吐，失败段可单独补）
    /// - 短段（≤1600）：`translateTexts` 分批（DeepL/MS 真批量，其它引擎有限并发）
    /// - 长段：`translateLongText`，并发上限 2
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

        let total = paras.count
        var results = Array(repeating: Optional<String>.none, count: total)
        var doneCount = 0

        func bump(_ label: String) {
            doneCount += 1
            onProgress?(Double(doneCount) / Double(total), "\(label) \(doneCount)/\(total)")
        }

        // 短段索引与长段索引
        var shortJobs: [(Int, String)] = []
        var longJobs: [(Int, String)] = []
        for (i, p) in paras.enumerated() {
            if p.count > 1600 {
                longJobs.append((i, p))
            } else {
                shortJobs.append((i, p))
            }
        }

        // 1) 短段：按 batchSize 切片，每批一次 translateTexts
        let batchSize = 16
        var shortOffset = 0
        while shortOffset < shortJobs.count {
            if Task.isCancelled { throw CancellationError() }
            let end = min(shortOffset + batchSize, shortJobs.count)
            let slice = Array(shortJobs[shortOffset..<end])
            let texts = slice.map(\.1)
            onProgress?(
                Double(doneCount) / Double(total),
                "批量翻译 \(doneCount + 1)–\(doneCount + texts.count)/\(total)"
            )
            let batch = await store.translateTexts(texts)
            for (j, job) in slice.enumerated() {
                let t = (j < batch.count ? batch[j] : nil)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if t.isEmpty {
                    // 批量缺口：单条补
                    if let one = try? await store.translateText(job.1) {
                        results[job.0] = one
                    } else {
                        results[job.0] = ""
                    }
                } else {
                    results[job.0] = t
                }
                bump("翻译")
            }
            shortOffset = end
        }

        // 2) 长段：有限并发
        let longConcurrency = 2
        if !longJobs.isEmpty {
            await withTaskGroup(of: (Int, String).self) { group in
                var next = 0
                let spawn = min(longConcurrency, longJobs.count)
                func submit(_ job: (Int, String)) {
                    let (idx, text) = job
                    group.addTask {
                        let t = (try? await store.translateLongText(text)) ?? ""
                        return (idx, t)
                    }
                }
                while next < spawn {
                    submit(longJobs[next]); next += 1
                }
                for await (idx, text) in group {
                    results[idx] = text
                    bump("长段")
                    if next < longJobs.count {
                        submit(longJobs[next]); next += 1
                    }
                }
            }
        }

        // 仍有空结果再单条补一次
        for i in results.indices where (results[i] ?? "").isEmpty {
            if Task.isCancelled { throw CancellationError() }
            if let t = try? await store.translateText(paras[i]), !t.isEmpty {
                results[i] = t
            }
        }

        var aligned: [BookChapterTranslation.AlignedParagraph] = []
        aligned.reserveCapacity(total)
        for i in 0..<total {
            aligned.append(.init(original: paras[i], translated: results[i] ?? ""))
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


    /// 全书翻译（按章节，跳过已完成且目标语言相同的缓存）
    /// - Parameter fromChapterIndex: 从第几章开始（`BookChapter.index`，含该章）；nil = 从第一章或断点
    @MainActor
    static func translateBook(
        book: Book,
        targetLanguage: AppLanguage,
        store: AppStore,
        fromChapterIndex: Int? = nil,
        onProgress: ((Double, String) -> Void)? = nil
    ) async throws {
        var chapters = book.chapters.sorted { $0.index < $1.index }
        let startIdx = fromChapterIndex
            ?? BookJobProgress.resolveTranslateStart(book: book, targetLanguage: targetLanguage.rawValue)
        chapters = chapters.filter { $0.index >= startIdx }
        guard !chapters.isEmpty else {
            BookJobProgress.clearTranslate(bookID: book.id)
            onProgress?(1, "全书已全部译完")
            return
        }
        let dir = BookLibrary.bookDirectory(id: book.id)
        var currentChapter = startIdx
        do {
            for (i, ch) in chapters.enumerated() {
                if Task.isCancelled {
                    BookJobProgress.markTranslateInterrupted(bookID: book.id, chapterIndex: ch.index)
                    throw CancellationError()
                }
                currentChapter = ch.index
                BookJobProgress.saveTranslate(bookID: book.id, fromChapterIndex: ch.index, status: "running")
                if let existing = load(bookID: book.id, chapterID: ch.id),
                   existing.status == .done,
                   existing.targetLanguage == targetLanguage.rawValue,
                   !existing.paragraphs.isEmpty {
                    onProgress?(
                        Double(i + 1) / Double(chapters.count),
                        "跳过已译 第\(ch.index + 1) 章（\(i + 1)/\(chapters.count)）"
                    )
                    continue
                }
                let html = EPUBParser.loadChapterHTML(bookDirectory: dir, href: ch.href) ?? ""
                onProgress?(
                    Double(i) / Double(chapters.count),
                    "翻译第 \(ch.index + 1) 章（\(i + 1)/\(chapters.count)）"
                )
                _ = try await translateChapter(
                    bookID: book.id,
                    chapterID: ch.id,
                    html: html,
                    targetLanguage: targetLanguage,
                    store: store,
                    onProgress: nil
                )
                onProgress?(
                    Double(i + 1) / Double(chapters.count),
                    "完成 第\(ch.index + 1) 章（\(i + 1)/\(chapters.count)）"
                )
            }
            BookJobProgress.clearTranslate(bookID: book.id)
            onProgress?(1, "全书翻译完成")
        } catch is CancellationError {
            BookJobProgress.markTranslateInterrupted(bookID: book.id, chapterIndex: currentChapter)
            throw CancellationError()
        } catch {
            BookJobProgress.markTranslateInterrupted(bookID: book.id, chapterIndex: currentChapter)
            throw error
        }
    }

    static func clearBook(bookID: UUID) {
        let dir = rootURL.appendingPathComponent(bookID.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
    }

    static func clearAll() {
        try? FileManager.default.removeItem(at: rootURL)
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    static func totalCacheSize() -> Int64 {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: rootURL, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in en {
            if let n = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(n)
            }
        }
        return total
    }

    static func formattedCacheSize() -> String {
        let b = totalCacheSize()
        if b < 1024 { return "\(b) B" }
        if b < 1024 { return "\(b) B" }
        return String(format: "%.1f MB", Double(b) / (1024 * 1024))
    }
}
