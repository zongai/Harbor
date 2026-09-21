import Foundation

/// 本地书架书籍元数据（正文按章节文件按需加载，不进列表内存）
struct Book: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var subtitle: String?
    var author: String?
    var publisher: String?
    var language: String?
    /// 相对 Books/{id}/ 的封面文件名，如 cover.jpg
    var coverFileName: String?
    var fileSize: Int64
    var importDate: Date
    var lastReadDate: Date?
    var lastChapterID: UUID?
    /// 全书进度 0...1（按章节序号）
    var readingProgress: Double
    /// 上次退出时，当前章内滚动比例 0...1（0=章首，1=章末）
    var lastScrollProgress: Double
    var totalChapters: Int
    /// 源 EPUB 内 OPF 路径（相对解压根）
    var opfPath: String?
    /// 章节清单（仅元数据；HTML 在 chapters/{id}.html）
    var chapters: [BookChapter]

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String? = nil,
        author: String? = nil,
        publisher: String? = nil,
        language: String? = nil,
        coverFileName: String? = nil,
        fileSize: Int64 = 0,
        importDate: Date = Date(),
        lastReadDate: Date? = nil,
        lastChapterID: UUID? = nil,
        readingProgress: Double = 0,
        lastScrollProgress: Double = 0,
        totalChapters: Int = 0,
        opfPath: String? = nil,
        chapters: [BookChapter] = []
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.author = author
        self.publisher = publisher
        self.language = language
        self.coverFileName = coverFileName
        self.fileSize = fileSize
        self.importDate = importDate
        self.lastReadDate = lastReadDate
        self.lastChapterID = lastChapterID
        self.readingProgress = readingProgress
        self.lastScrollProgress = min(1, max(0, lastScrollProgress))
        self.totalChapters = totalChapters
        self.opfPath = opfPath
        self.chapters = chapters
    }

    var progressPercentText: String {
        let p = max(0, min(1, readingProgress))
        if p <= 0 { return "未读" }
        return "阅读 \(Int((p * 100).rounded()))%"
    }

    /// 兼容旧 metadata（无 lastScrollProgress）
    enum CodingKeys: String, CodingKey {
        case id, title, subtitle, author, publisher, language, coverFileName
        case fileSize, importDate, lastReadDate, lastChapterID, readingProgress
        case lastScrollProgress, totalChapters, opfPath, chapters
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle)
        author = try c.decodeIfPresent(String.self, forKey: .author)
        publisher = try c.decodeIfPresent(String.self, forKey: .publisher)
        language = try c.decodeIfPresent(String.self, forKey: .language)
        coverFileName = try c.decodeIfPresent(String.self, forKey: .coverFileName)
        fileSize = try c.decodeIfPresent(Int64.self, forKey: .fileSize) ?? 0
        importDate = try c.decodeIfPresent(Date.self, forKey: .importDate) ?? Date()
        lastReadDate = try c.decodeIfPresent(Date.self, forKey: .lastReadDate)
        lastChapterID = try c.decodeIfPresent(UUID.self, forKey: .lastChapterID)
        readingProgress = try c.decodeIfPresent(Double.self, forKey: .readingProgress) ?? 0
        lastScrollProgress = min(1, max(0, try c.decodeIfPresent(Double.self, forKey: .lastScrollProgress) ?? 0))
        totalChapters = try c.decodeIfPresent(Int.self, forKey: .totalChapters) ?? 0
        opfPath = try c.decodeIfPresent(String.self, forKey: .opfPath)
        chapters = try c.decodeIfPresent([BookChapter].self, forKey: .chapters) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(subtitle, forKey: .subtitle)
        try c.encodeIfPresent(author, forKey: .author)
        try c.encodeIfPresent(publisher, forKey: .publisher)
        try c.encodeIfPresent(language, forKey: .language)
        try c.encodeIfPresent(coverFileName, forKey: .coverFileName)
        try c.encode(fileSize, forKey: .fileSize)
        try c.encode(importDate, forKey: .importDate)
        try c.encodeIfPresent(lastReadDate, forKey: .lastReadDate)
        try c.encodeIfPresent(lastChapterID, forKey: .lastChapterID)
        try c.encode(readingProgress, forKey: .readingProgress)
        try c.encode(lastScrollProgress, forKey: .lastScrollProgress)
        try c.encode(totalChapters, forKey: .totalChapters)
        try c.encodeIfPresent(opfPath, forKey: .opfPath)
        try c.encode(chapters, forKey: .chapters)
    }
}

struct BookChapter: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var bookID: UUID
    var index: Int
    var title: String
    /// EPUB 内相对 OPF 的 href
    var href: String
    /// 本地已抽出的章节 HTML 相对路径（相对书目录）；nil 表示尚未物化
    var localHTMLFileName: String?
    var language: String?
    var readingProgress: Double

    init(
        id: UUID = UUID(),
        bookID: UUID,
        index: Int,
        title: String,
        href: String,
        localHTMLFileName: String? = nil,
        language: String? = nil,
        readingProgress: Double = 0
    ) {
        self.id = id
        self.bookID = bookID
        self.index = index
        self.title = title
        self.href = href
        self.localHTMLFileName = localHTMLFileName
        self.language = language
        self.readingProgress = readingProgress
    }
}

enum BookImportError: LocalizedError {
    case invalidEPUB
    case missingContainer
    case missingOPF
    case emptySpine
    case unzipFailed(String)
    case io(String)

    var errorDescription: String? {
        switch self {
        case .invalidEPUB: return "不是有效的 EPUB 文件"
        case .missingContainer: return "缺少 META-INF/container.xml"
        case .missingOPF: return "无法定位内容清单（OPF）"
        case .emptySpine: return "书籍没有可读章节"
        case .unzipFailed(let s): return "解压失败：\(s)"
        case .io(let s): return s
        }
    }
}
