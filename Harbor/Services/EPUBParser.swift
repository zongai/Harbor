import Foundation
import UIKit

/// 首次导入时解析 EPUB：解压一次，建立元数据与章节索引；之后按章节按需读 HTML
enum EPUBParser {
    struct ParseResult: Sendable {
        let book: Book
        let coverData: Data?
        /// 解压目录中的相对路径 → 用于后续读章节
        let extractRootRelative: String
    }

    /// 从本地 .epub 解析；`bookID` 可预先指定以便路径稳定
    static func parse(epubURL: URL, bookID: UUID = UUID()) throws -> ParseResult {
        let values = try epubURL.resourceValues(forKeys: [.fileSizeKey])
        let fileSize = Int64(values.fileSize ?? 0)

        let entries = try MinimalZip.entries(from: epubURL)
        var map: [String: Data] = [:]
        map.reserveCapacity(entries.count)
        for e in entries {
            let key = normalizePath(e.name)
            map[key] = e.data
            // 也存一份末段名为键，方便查找
            if let last = key.split(separator: "/").last {
                map[String(last)] = e.data
            }
        }

        guard let containerData = map["meta-inf/container.xml"] ?? map["META-INF/container.xml"]
            ?? map.first(where: { $0.key.lowercased().hasSuffix("container.xml") })?.value else {
            throw BookImportError.missingContainer
        }
        let containerXML = string(from: containerData)
        guard let opfPathRaw = firstMatch(
            #"full-path\s*=\s*"([^"]+)""#,
            in: containerXML
        ) ?? firstMatch(#"full-path\s*=\s*'([^']+)'"#, in: containerXML) else {
            throw BookImportError.missingOPF
        }
        let opfPath = normalizePath(opfPathRaw)
        guard let opfData = map[opfPath] ?? map[opfPathRaw] else {
            throw BookImportError.missingOPF
        }
        let opf = string(from: opfData)
        let opfDir = opfPath.contains("/")
            ? String(opfPath[..<opfPath.lastIndex(of: "/")!])
            : ""

        let title = metaContent("title", in: opf)
            ?? metaDC("title", in: opf)
            ?? epubURL.deletingPathExtension().lastPathComponent
        let creator = metaContent("creator", in: opf) ?? metaDC("creator", in: opf)
        let publisher = metaContent("publisher", in: opf) ?? metaDC("publisher", in: opf)
        let language = metaContent("language", in: opf) ?? metaDC("language", in: opf)
        let subtitle = metaContent("subtitle", in: opf)

        // manifest: id → href
        var manifest: [String: String] = [:]
        var manifestMedia: [String: String] = [:]
        let itemPattern = #"<item\b[^>]*>"#
        for itemTag in matches(itemPattern, in: opf) {
            guard let id = attr("id", in: itemTag), let href = attr("href", in: itemTag) else { continue }
            manifest[id] = href
            if let media = attr("media-type", in: itemTag) {
                manifestMedia[id] = media
            }
        }

        // spine
        var spineIDs: [String] = []
        if let spineBlock = firstBlock("spine", in: opf) {
            for ref in matches(#"<itemref\b[^>]*>"#, in: spineBlock) {
                if let idref = attr("idref", in: ref) {
                    spineIDs.append(idref)
                }
            }
        }
        if spineIDs.isEmpty { throw BookImportError.emptySpine }

        // TOC titles from nav or ncx
        var tocTitles: [String: String] = [:]
        if let navHref = manifest.first(where: { manifestMedia[$0.key]?.contains("nav+xml") == true })?.value
            ?? manifest.first(where: { $0.value.lowercased().contains("nav") && $0.value.hasSuffix(".xhtml") })?.value {
            let navPath = join(opfDir, navHref)
            if let navData = map[normalizePath(navPath)] {
                tocTitles.merge(parseNavTitles(string(from: navData)), uniquingKeysWith: { a, _ in a })
            }
        }
        if tocTitles.isEmpty, let ncxHref = manifest.first(where: { $0.value.lowercased().hasSuffix(".ncx") })?.value {
            let ncxPath = join(opfDir, ncxHref)
            if let ncxData = map[normalizePath(ncxPath)] {
                tocTitles.merge(parseNCXTitles(string(from: ncxData)), uniquingKeysWith: { a, _ in a })
            }
        }

        var chapters: [BookChapter] = []
        chapters.reserveCapacity(spineIDs.count)
        for (idx, idref) in spineIDs.enumerated() {
            guard let href = manifest[idref] else { continue }
            let media = manifestMedia[idref] ?? ""
            if media.contains("image") { continue }
            let fullHref = join(opfDir, href)
            let titleGuess = tocTitles[normalizePath(fullHref)]
                ?? tocTitles[href]
                ?? tocTitles[href.split(separator: "/").last.map(String.init) ?? ""]
                ?? "第 \(idx + 1) 章"
            chapters.append(BookChapter(
                bookID: bookID,
                index: idx,
                title: stripXML(titleGuess),
                href: normalizePath(fullHref),
                language: language
            ))
        }
        if chapters.isEmpty { throw BookImportError.emptySpine }

        // cover
        var coverData: Data?
        var coverFileName: String?
        if let coverID = attr("content", in: firstMatch(#"<meta[^>]*name\s*=\s*"cover"[^>]*>"#, in: opf) ?? "")
            ?? firstMatch(#"name\s*=\s*"cover"[^>]*content\s*=\s*"([^"]+)""#, in: opf) {
            if let href = manifest[coverID] {
                let path = normalizePath(join(opfDir, href))
                if let d = map[path] {
                    coverData = d
                    coverFileName = "cover" + (URL(fileURLWithPath: href).pathExtension.isEmpty ? ".jpg" : ".\(URL(fileURLWithPath: href).pathExtension)")
                }
            }
        }
        if coverData == nil {
            // properties="cover-image"
            for itemTag in matches(#"<item\b[^>]*>"#, in: opf) {
                if itemTag.contains("cover-image"), let href = attr("href", in: itemTag) {
                    let path = normalizePath(join(opfDir, href))
                    if let d = map[path] {
                        coverData = d
                        let ext = URL(fileURLWithPath: href).pathExtension
                        coverFileName = "cover." + (ext.isEmpty ? "jpg" : ext)
                        break
                    }
                }
            }
        }

        let book = Book(
            id: bookID,
            title: stripXML(title).isEmpty ? "未命名书籍" : stripXML(title),
            subtitle: subtitle.map { stripXML($0) },
            author: creator.map { stripXML($0) },
            publisher: publisher.map { stripXML($0) },
            language: language.map { stripXML($0) },
            coverFileName: coverFileName,
            fileSize: fileSize,
            importDate: Date(),
            totalChapters: chapters.count,
            opfPath: opfPath,
            chapters: chapters
        )
        return ParseResult(book: book, coverData: coverData, extractRootRelative: "")
    }

    /// 按章节 href 从已解压目录读取 HTML
    static func loadChapterHTML(bookDirectory: URL, href: String) -> String? {
        let path = bookDirectory.appendingPathComponent("extracted").appendingPathComponent(href)
        if let data = try? Data(contentsOf: path) {
            return string(from: data)
        }
        // try map basename
        let base = (href as NSString).lastPathComponent
        let dir = bookDirectory.appendingPathComponent("extracted")
        if let en = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) {
            for case let file as URL in en where file.lastPathComponent == base {
                if let data = try? Data(contentsOf: file) {
                    return string(from: data)
                }
            }
        }
        return nil
    }

    // MARK: - Helpers

    private static func normalizePath(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("./") { s = String(s.dropFirst(2)) }
        while s.hasPrefix("/") { s = String(s.dropFirst()) }
        // decode %20
        s = s.removingPercentEncoding ?? s
        return s.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    private static func join(_ dir: String, _ href: String) -> String {
        let h = href.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("/") { return String(h.dropFirst()) }
        if dir.isEmpty { return h }
        // resolve ..
        var parts = dir.split(separator: "/").map(String.init)
        for p in h.split(separator: "/") {
            if p == ".." { if !parts.isEmpty { parts.removeLast() } }
            else if p != "." { parts.append(String(p)) }
        }
        return parts.joined(separator: "/")
    }

    private static func string(from data: Data) -> String {
        if let s = String(data: data, encoding: .utf8) { return s }
        if let s = String(data: data, encoding: .isoLatin1) { return s }
        return String(decoding: data, as: UTF8.self)
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, options: [], range: range), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return re.matches(in: text, options: [], range: range).compactMap { m in
            guard let r = Range(m.range, in: text) else { return nil }
            return String(text[r])
        }
    }

    private static func attr(_ name: String, in tag: String) -> String? {
        firstMatch(#"\#(name)\s*=\s*"([^"]+)""#, in: tag)
            ?? firstMatch(#"\#(name)\s*=\s*'([^']+)'"#, in: tag)
    }

    private static func firstBlock(_ tag: String, in text: String) -> String? {
        firstMatch(#"<\#(tag)\b[^>]*>([\s\S]*?)</\#(tag)>"#, in: text)
    }

    private static func metaDC(_ name: String, in opf: String) -> String? {
        firstMatch(#"<dc:\#(name)[^>]*>([^<]+)</dc:\#(name)>"#, in: opf)
            ?? firstMatch(#"<\#(name)[^>]*xmlns[^>]*>([^<]+)</\#(name)>"#, in: opf)
    }

    private static func metaContent(_ name: String, in opf: String) -> String? {
        metaDC(name, in: opf)
    }

    private static func stripXML(_ s: String) -> String {
        var t = s
        if let re = try? NSRegularExpression(pattern: #"<[^>]+>"#) {
            t = re.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: "")
        }
        return t
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseNavTitles(_ nav: String) -> [String: String] {
        var result: [String: String] = [:]
        // <a href="...">title</a>
        let pattern = #"<a\b[^>]*href\s*=\s*"([^"]+)"[^>]*>([\s\S]*?)</a>"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return result }
        let range = NSRange(nav.startIndex..., in: nav)
        for m in re.matches(in: nav, options: [], range: range) {
            guard m.numberOfRanges >= 3,
                  let hr = Range(m.range(at: 1), in: nav),
                  let tr = Range(m.range(at: 2), in: nav) else { continue }
            let href = String(nav[hr]).components(separatedBy: "#").first ?? String(nav[hr])
            let title = stripXML(String(nav[tr]))
            if !title.isEmpty {
                result[normalizePath(href)] = title
            }
        }
        return result
    }

    private static func parseNCXTitles(_ ncx: String) -> [String: String] {
        var result: [String: String] = [:]
        let pattern = #"<navPoint[\s\S]*?<text>([^<]*)</text>[\s\S]*?<content[^>]*src\s*=\s*"([^"]+)""#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return result }
        let range = NSRange(ncx.startIndex..., in: ncx)
        for m in re.matches(in: ncx, options: [], range: range) {
            guard m.numberOfRanges >= 3,
                  let tr = Range(m.range(at: 1), in: ncx),
                  let hr = Range(m.range(at: 2), in: ncx) else { continue }
            let href = String(ncx[hr]).components(separatedBy: "#").first ?? String(ncx[hr])
            result[normalizePath(href)] = stripXML(String(ncx[tr]))
        }
        return result
    }
}
