import Foundation
import AVFoundation
import Observation

/// 书籍 TTS：Edge 合成 + 段落级磁盘缓存 + 播放队列（语速用 player.rate，不重合成）
@MainActor
@Observable
final class BookTTSController {
    var isPlaying = false
    var isLoading = false
    var isCaching = false
    var cacheProgress: Double = 0
    var segmentIndex = 0
    var segmentCount = 0
    var statusText: String?
    var errorMessage: String?
    /// 当前正在朗读的段落文本（供阅读页高亮）
    var currentSegmentText: String = ""
    /// 当前队列只读快照（朗读时用于分段跟随）
    var activeSegments: [Segment] = []

    /// 0.5 ... 3.0，仅影响 AVAudioPlayer.rate
    var playbackRate: Double = 1.0 {
        didSet {
            player?.rate = Float(max(0.5, min(3.0, playbackRate)))
            player?.enableRate = true
        }
    }

    private var player: AVAudioPlayer?
    private var queue: [Segment] = []
    private var session = 0
    private var playTask: Task<Void, Never>?
    private var cacheTask: Task<Void, Never>?

    struct Segment: Identifiable {
        let id: String
        let text: String
        /// 缓存与语种键：en / zh / ja / ko / tr / auto
        let languageTag: String
        /// 双语时强制按文本选 Voice，忽略用户单一默认 Voice
        let autoVoice: Bool
    }

    // MARK: - Cache paths

    private static var rootURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let url = base.appendingPathComponent("Harbor/TTSAudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func cacheURL(bookID: UUID, chapterID: UUID, segmentID: String, voice: String) -> URL {
        let safeVoice = voice.replacingOccurrences(of: "/", with: "_")
        let dir = rootURL
            .appendingPathComponent(bookID.uuidString, isDirectory: true)
            .appendingPathComponent(chapterID.uuidString, isDirectory: true)
            .appendingPathComponent(safeVoice, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(segmentID).mp3")
    }

    static func chapterCacheStatus(bookID: UUID, chapterID: UUID, voice: String, segmentIDs: [String]) -> (done: Int, total: Int) {
        let total = segmentIDs.count
        guard total > 0 else { return (0, 0) }
        var done = 0
        for id in segmentIDs {
            let url = cacheURL(bookID: bookID, chapterID: chapterID, segmentID: id, voice: voice)
            if FileManager.default.fileExists(atPath: url.path) { done += 1 }
        }
        return (done, total)
    }

    // MARK: - Text split

    static func segments(fromHTML html: String, chapterID: UUID) -> [Segment] {
        let plain = HTMLUtils.stripTags(html)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var parts = plain.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if parts.count <= 1 {
            // 再按单换行 / 句号粗分，避免整章一块过大
            let byLine = plain.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if byLine.count > 1 { parts = byLine }
        }
        // 合并过短段，拆分过长段
        var merged: [String] = []
        var buf = ""
        for p in parts {
            if buf.isEmpty {
                buf = p
            } else if buf.count + p.count < 80 {
                buf += " " + p
            } else {
                merged.append(buf)
                buf = p
            }
        }
        if !buf.isEmpty { merged.append(buf) }

        var result: [Segment] = []
        var idx = 0
        for text in merged {
            for chunk in chunkText(text, maxChars: 450) {
                idx += 1
                let id = String(format: "%04d", idx)
                result.append(Segment(
                    id: id,
                    text: chunk,
                    languageTag: BookLanguageDetect.tag(for: chunk),
                    autoVoice: false
                ))
            }
        }
        return result
    }

    private static func chunkText(_ text: String, maxChars: Int) -> [String] {
        guard text.count > maxChars else { return [text] }
        var out: [String] = []
        var start = text.startIndex
        while start < text.endIndex {
            let end = text.index(start, offsetBy: maxChars, limitedBy: text.endIndex) ?? text.endIndex
            var cut = end
            if end < text.endIndex {
                let window = text[start..<end]
                if let r = window.lastIndex(where: { ".!?。！？；;".contains($0) }) {
                    cut = text.index(after: r)
                }
            }
            let piece = String(text[start..<cut]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty { out.append(piece) }
            start = cut
        }
        return out.isEmpty ? [text] : out
    }

    // MARK: - Playback

    func stop() {
        session += 1
        playTask?.cancel()
        playTask = nil
        cacheTask?.cancel()
        player?.stop()
        player = nil
        isPlaying = false
        isLoading = false
        isCaching = false
        statusText = nil
        currentSegmentText = ""
        activeSegments = []
    }

    func toggleChapter(
        bookID: UUID,
        chapterID: UUID,
        html: String,
        voice: String?,
        rate: Double
    ) {
        toggleContent(
            bookID: bookID,
            chapterID: chapterID,
            mode: .original,
            html: html,
            translation: nil,
            voice: voice,
            rate: rate
        )
    }

    /// 按阅读模式组队列：双语则原文段 + 译文段交替，并按语种选 Voice
    func toggleContent(
        bookID: UUID,
        chapterID: UUID,
        mode: BookReadingMode,
        html: String,
        translation: BookChapterTranslation?,
        voice: String?,
        rate: Double
    ) {
        if isPlaying || isLoading {
            stop()
            return
        }
        playbackRate = rate
        let segs = Self.buildSegments(
            mode: mode,
            html: html,
            translation: translation,
            chapterID: chapterID
        )
        guard !segs.isEmpty else {
            errorMessage = mode == .translation && translation == nil
                ? "请先翻译本章再朗读译文"
                : "没有可朗读的文本"
            return
        }
        queue = segs
        activeSegments = segs
        segmentCount = segs.count
        segmentIndex = 0
        currentSegmentText = segs.first?.text ?? ""
        playTask = Task { await runQueue(bookID: bookID, chapterID: chapterID, voice: voice) }
    }

    static func buildSegments(
        mode: BookReadingMode,
        html: String,
        translation: BookChapterTranslation?,
        chapterID: UUID
    ) -> [Segment] {
        switch mode {
        case .original:
            return segments(fromHTML: html, chapterID: chapterID)
        case .translation:
            guard let tr = translation, !tr.paragraphs.isEmpty else { return [] }
            var out: [Segment] = []
            for (i, p) in tr.paragraphs.enumerated() {
                let text = p.translated.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                for (j, chunk) in chunkText(text, maxChars: 450).enumerated() {
                    out.append(Segment(
                        id: String(format: "t-%03d-%02d", i + 1, j + 1),
                        text: chunk,
                        languageTag: BookLanguageDetect.tag(for: chunk),
                        autoVoice: true
                    ))
                }
            }
            return out
        case .bilingual:
            if let tr = translation, !tr.paragraphs.isEmpty {
                var out: [Segment] = []
                for (i, p) in tr.paragraphs.enumerated() {
                    let o = p.original.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trn = p.translated.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !o.isEmpty {
                        for (j, chunk) in chunkText(o, maxChars: 450).enumerated() {
                            out.append(Segment(
                                id: String(format: "b-%03d-o%02d", i + 1, j + 1),
                                text: chunk,
                                languageTag: BookLanguageDetect.tag(for: chunk),
                                autoVoice: true
                            ))
                        }
                    }
                    if !trn.isEmpty {
                        for (j, chunk) in chunkText(trn, maxChars: 450).enumerated() {
                            out.append(Segment(
                                id: String(format: "b-%03d-t%02d", i + 1, j + 1),
                                text: chunk,
                                languageTag: BookLanguageDetect.tag(for: chunk),
                                autoVoice: true
                            ))
                        }
                    }
                }
                return out
            }
            return segments(fromHTML: html, chapterID: chapterID)
        }
    }

    private func runQueue(bookID: UUID, chapterID: UUID, voice: String?) async {
        let my = session
        isLoading = true
        errorMessage = nil
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return
        }

        for (i, seg) in queue.enumerated() {
            if Task.isCancelled || my != session { return }
            segmentIndex = i
            currentSegmentText = seg.text
            statusText = "朗读 \(i + 1)/\(queue.count)"
            isLoading = true
            do {
                let data = try await audioData(
                    bookID: bookID,
                    chapterID: chapterID,
                    segment: seg,
                    voice: voice,
                    session: my
                )
                if my != session { return }
                let p = try AVAudioPlayer(data: data)
                p.enableRate = true
                p.rate = Float(max(0.5, min(3.0, playbackRate)))
                p.prepareToPlay()
                player = p
                isLoading = false
                isPlaying = true
                p.play()
                while p.isPlaying {
                    if my != session || Task.isCancelled {
                        p.stop()
                        return
                    }
                    // 允许中途改速
                    p.rate = Float(max(0.5, min(3.0, playbackRate)))
                    try await Task.sleep(nanoseconds: 150_000_000)
                }
            } catch {
                if my != session { return }
                if let e = error as? EdgeTTS.TTSError, case .cancelled = e {
                    isPlaying = false
                    isLoading = false
                    return
                }
                errorMessage = error.localizedDescription
                isPlaying = false
                isLoading = false
                return
            }
        }
        if my == session {
            isPlaying = false
            isLoading = false
            statusText = "本章朗读完成"
            player = nil
        }
    }

    private func audioData(
        bookID: UUID,
        chapterID: UUID,
        segment: Segment,
        voice: String?,
        session: Int
    ) async throws -> Data {
        let configured = segment.autoVoice ? nil : voice
        let resolved = EdgeTTS.preferredVoice(for: segment.text, configured: configured)
        // 缓存键含语种，避免中英共用同一文件
        let cacheKey = "\(segment.id)-\(segment.languageTag)"
        let url = Self.cacheURL(bookID: bookID, chapterID: chapterID, segmentID: cacheKey, voice: resolved)
        if let cached = try? Data(contentsOf: url), !cached.isEmpty {
            return cached
        }
        // 离线且无缓存：不调用 Edge，给出明确提示
        if !NetworkReachability.shared.isOnline {
            throw EdgeTTS.TTSError.network("当前无网络，且本章段语音未缓存。请联网后朗读或先「缓存本章语音」。")
        }
        // 缓存固定用 +0% 合成，播放时用 player.rate
        let data = try await EdgeTTS.synthesize(
            text: segment.text,
            voice: resolved,
            rate: "+0%"
        ) {
            session != self.session
        }
        try? data.write(to: url, options: [.atomic])
        return data
    }

    /// 预缓存当前章节全部段落（Edge）
    func precacheChapter(
        bookID: UUID,
        chapterID: UUID,
        html: String,
        voice: String?
    ) {
        cacheTask?.cancel()
        let segs = Self.segments(fromHTML: html, chapterID: chapterID)
        guard !segs.isEmpty else {
            errorMessage = "本章没有可缓存的文本"
            return
        }
        isCaching = true
        cacheProgress = 0
        statusText = "缓存语音 0/\(segs.count)"
        cacheTask = Task {
            let my = session
            for (i, seg) in segs.enumerated() {
                if Task.isCancelled || my != session { break }
                do {
                    _ = try await audioData(
                        bookID: bookID,
                        chapterID: chapterID,
                        segment: seg,
                        voice: voice,
                        session: my
                    )
                } catch {
                    if my == session {
                        errorMessage = error.localizedDescription
                    }
                    break
                }
                cacheProgress = Double(i + 1) / Double(segs.count)
                statusText = "缓存语音 \(i + 1)/\(segs.count)"
            }
            if my == session {
                isCaching = false
                statusText = "本章语音已缓存"
            }
        }
    }

    static func clearBookCache(bookID: UUID) {
        let dir = rootURL.appendingPathComponent(bookID.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
    }

    static func clearAllCaches() {
        try? FileManager.default.removeItem(at: rootURL)
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    static func totalCacheSize() -> Int64 {
        directorySize(rootURL)
    }

    static func formattedCacheSize() -> String {
        let b = totalCacheSize()
        if b < 1024 { return "\(b) B" }
        if b < 1024 * 1024 { return String(format: "%.1f KB", Double(b) / 1024) }
        return String(format: "%.1f MB", Double(b) / (1024 * 1024))
    }

    private static func directorySize(_ url: URL) -> Int64 {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in en {
            if let n = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(n)
            }
        }
        return total
    }
}


/// 书籍段落语种粗检（用于 TTS Voice；与 ListLanguageDetect 互补）
enum BookLanguageDetect {
    static func tag(for text: String) -> String {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return "auto" }
        if ListLanguageDetect.isMostlyChinese(s) { return "zh" }
        // 日文假名
        if s.unicodeScalars.contains(where: { (0x3040...0x30FF).contains($0.value) }) { return "ja" }
        // 韩文
        if s.unicodeScalars.contains(where: { (0xAC00...0xD7AF).contains($0.value) }) { return "ko" }
        // 土耳其特征
        let tr: Set<Character> = Set("ğüşıöçĞÜŞİÖÇ")
        if s.filter({ tr.contains($0) }).count >= 2 { return "tr" }
        return "en"
    }
}
