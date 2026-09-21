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
    /// 0...1
    var readingProgress: Double
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
        self.totalChapters = totalChapters
        self.opfPath = opfPath
        self.chapters = chapters
    }

    var progressPercentText: String {
        let p = max(0, min(1, readingProgress))
        if p <= 0 { return "未读" }
        return "阅读 \(Int((p * 100).rounded()))%"
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
