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
    /// 本章队列正常播完（非取消）时递增，供阅读页自动翻章续读
    var chapterFinishedToken: Int = 0
    /// 是否在章末自动请求续读（由阅读页决定是否翻章）
    var continuousChapterPlay: Bool = true

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

        // 预取：播放当前段时后台合成下 1～2 段，缩短段间等待
        var prefetchTasks: [Int: Task<Data?, Never>] = [:]

        for (i, seg) in queue.enumerated() {
            if Task.isCancelled || my != session { return }
            segmentIndex = i
            currentSegmentText = seg.text
            statusText = "朗读 \(i + 1)/\(queue.count)"
            isLoading = true

            // 启动后续段预取（最多 3 段，压低段间等待）
            for lookAhead in 1...3 {
                let next = i + lookAhead
                guard next < queue.count, prefetchTasks[next] == nil else { continue }
                let nextSeg = queue[next]
                prefetchTasks[next] = Task {
                    try? await audioData(
                        bookID: bookID,
                        chapterID: chapterID,
                        segment: nextSeg,
                        voice: voice,
                        session: my
                    )
                }
            }

            do {
                let data: Data
                if let pref = prefetchTasks[i] {
                    if let d = await pref.value {
                        data = d
                    } else {
                        data = try await audioData(
                            bookID: bookID,
                            chapterID: chapterID,
                            segment: seg,
                            voice: voice,
                            session: my
                        )
                    }
                    prefetchTasks[i] = nil
                } else {
                    data = try await audioData(
                        bookID: bookID,
                        chapterID: chapterID,
                        segment: seg,
                        voice: voice,
                        session: my
                    )
                }
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
            player = nil
            if continuousChapterPlay {
                statusText = "本章完成，准备下一章…"
                chapterFinishedToken &+= 1
            } else {
                statusText = "本章朗读完成"
            }
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
        let cacheKey = "\(segment.id)-\(segment.languageTag)"
        let url = Self.cacheURL(bookID: bookID, chapterID: chapterID, segmentID: cacheKey, voice: resolved)
        if let cached = try? Data(contentsOf: url), !cached.isEmpty {
            return cached
        }
        if !NetworkReachability.shared.isOnline {
            throw EdgeTTS.TTSError.network("当前无网络，且本章段语音未缓存。请联网后朗读或先「缓存本章语音」。")
        }
        // 同 cacheKey 只允许一路 in-flight 合成（预取与播放共享）
        let dedupeKey = "\(bookID.uuidString)|\(chapterID.uuidString)|\(cacheKey)|\(resolved)"
        let text = segment.text
        let outURL = url
        let data = try await TTSInFlight.shared.run(key: dedupeKey) {
            if let cached = try? Data(contentsOf: outURL), !cached.isEmpty {
                return cached
            }
            // 取消：依赖 Task 取消（stop() 会 cancel play/cache Task）；避免捕获 MainActor self
            let data = try await EdgeTTS.synthesize(
                text: text,
                voice: resolved,
                rate: "+0%"
            ) {
                Task.isCancelled
            }
            try? data.write(to: outURL, options: [.atomic])
            return data
        }
        if session != self.session { throw EdgeTTS.TTSError.cancelled }
        return data
    }

    /// 预缓存当前章节全部段落（Edge）— 有限并发，失败不中断整章
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
            let total = segs.count
            let concurrency = Self.ttsCacheConcurrency
            var completed = 0
            var firstError: String?
            await withTaskGroup(of: (Int, String?).self) { group in
                var next = 0
                let spawn = min(concurrency, total)
                func submit(_ index: Int) {
                    let seg = segs[index]
                    group.addTask {
                        do {
                            _ = try await self.audioData(
                                bookID: bookID,
                                chapterID: chapterID,
                                segment: seg,
                                voice: voice,
                                session: my
                            )
                            return (index, nil)
                        } catch {
                            return (index, error.localizedDescription)
                        }
                    }
                }
                while next < spawn {
                    submit(next); next += 1
                }
                for await (_, err) in group {
                    if Task.isCancelled || my != session { break }
                    completed += 1
                    if let err, firstError == nil { firstError = err }
                    cacheProgress = Double(completed) / Double(total)
                    statusText = "缓存语音 \(completed)/\(total)"
                    if next < total {
                        submit(next); next += 1
                    }
                }
            }
            if my == session {
                isCaching = false
                if let firstError, completed < total {
                    errorMessage = firstError
                    statusText = "缓存部分完成 \(completed)/\(total)"
                } else {
                    statusText = "本章语音已缓存"
                }
            }
        }
    }


    /// 全书语音预缓存（按章节顺序，可取消）
    /// - Parameter fromChapterIndex: 从第几章开始（`BookChapter.index`，含该章）；nil = 从第一章
    func precacheBook(
        book: Book,
        voice: String?,
        fromChapterIndex: Int? = nil,
        onProgress: (@MainActor (Double, String) -> Void)? = nil
    ) {
        cacheTask?.cancel()
        var chapters = book.chapters.sorted { $0.index < $1.index }
        let startIdx = fromChapterIndex ?? BookJobProgress.resolveTTSStart(book: book)
        chapters = chapters.filter { $0.index >= startIdx }
        guard !chapters.isEmpty else {
            BookJobProgress.clearTTS(bookID: book.id)
            statusText = "全书语音已全部缓存"
            cacheProgress = 1
            onProgress?(1, "全书语音已全部缓存")
            return
        }
        BookJobProgress.saveTTS(bookID: book.id, fromChapterIndex: startIdx, status: "running")
        isCaching = true
        cacheProgress = 0
        statusText = "从第 \(startIdx + 1) 章继续缓存…"
        cacheTask = Task {
            let my = session
            let dir = BookLibrary.bookDirectory(id: book.id)
            let concurrency = Self.ttsCacheConcurrency
            var lastChapter = startIdx
            for (ci, ch) in chapters.enumerated() {
                if Task.isCancelled || my != session {
                    BookJobProgress.markTTSInterrupted(bookID: book.id, chapterIndex: lastChapter)
                    break
                }
                lastChapter = ch.index
                BookJobProgress.saveTTS(bookID: book.id, fromChapterIndex: ch.index, status: "running")
                let html = EPUBParser.loadChapterHTML(bookDirectory: dir, href: ch.href) ?? ""
                let segs = Self.segments(fromHTML: html, chapterID: ch.id)
                guard !segs.isEmpty else {
                    let frac = Double(ci + 1) / Double(max(chapters.count, 1))
                    cacheProgress = frac
                    onProgress?(frac, "跳过空章 第\(ch.index + 1)")
                    continue
                }
                var segDone = 0
                let segTotal = segs.count
                await withTaskGroup(of: Bool.self) { group in
                    var next = 0
                    let spawn = min(concurrency, segTotal)
                    func submit(_ index: Int) {
                        let seg = segs[index]
                        group.addTask {
                            do {
                                _ = try await self.audioData(
                                    bookID: book.id,
                                    chapterID: ch.id,
                                    segment: seg,
                                    voice: voice,
                                    session: my
                                )
                                return true
                            } catch {
                                return false
                            }
                        }
                    }
                    while next < spawn {
                        submit(next); next += 1
                    }
                    for await ok in group {
                        if Task.isCancelled || my != session { break }
                        segDone += 1
                        _ = ok
                        let frac = (Double(ci) + Double(segDone) / Double(segTotal)) / Double(max(chapters.count, 1))
                        cacheProgress = frac
                        let msg = "全书语音 第\(ch.index + 1) 章 \(segDone)/\(segTotal)（\(ci + 1)/\(chapters.count)）"
                        statusText = msg
                        onProgress?(frac, msg)
                        if next < segTotal {
                            submit(next); next += 1
                        }
                    }
                }
                if Task.isCancelled || my != session {
                    BookJobProgress.markTTSInterrupted(bookID: book.id, chapterIndex: ch.index)
                    break
                }
            }
            if my == session {
                isCaching = false
                if Task.isCancelled {
                    BookJobProgress.markTTSInterrupted(bookID: book.id, chapterIndex: lastChapter)
                    statusText = "已暂停，可继续"
                    onProgress?(cacheProgress, "已暂停，可从第 \(lastChapter + 1) 章继续")
                } else {
                    statusText = "全书语音已缓存"
                    cacheProgress = 1
                    BookJobProgress.clearTTS(bookID: book.id)
                    onProgress?(1, "全书语音已缓存")
                }
            }
        }
    }

    /// 全书/本章缓存默认并发（Edge 侧过高易 429）
    private static let ttsCacheConcurrency = 4

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

// MARK: - TTS in-flight dedupe（同 cacheKey 只合成一次）

private actor TTSInFlight {
    static let shared = TTSInFlight()
    private var tasks: [String: Task<Data, Error>] = [:]

    func run(key: String, operation: @escaping @Sendable () async throws -> Data) async throws -> Data {
        if let existing = tasks[key] {
            return try await existing.value
        }
        let task = Task {
            try await operation()
        }
        tasks[key] = task
        defer { tasks[key] = nil }
        return try await task.value
    }
}

// MARK: - 全书任务断点（可从上次停止处继续）

enum BookJobProgress {
    private static var dir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let url = base.appendingPathComponent("Harbor/BookJobs", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func url(bookID: UUID, kind: String) -> URL {
        dir.appendingPathComponent("\(bookID.uuidString)-\(kind).json")
    }

    struct Snapshot: Codable {
        var fromChapterIndex: Int
        var updatedAt: Date
        /// running = 进行中/被中断；completed = 全书完成（文件通常会被删）
        var status: String
        var message: String?

        init(fromChapterIndex: Int, updatedAt: Date = Date(), status: String = "running", message: String? = nil) {
            self.fromChapterIndex = fromChapterIndex
            self.updatedAt = updatedAt
            self.status = status
            self.message = message
        }
    }

    // MARK: TTS

    static func saveTTS(bookID: UUID, fromChapterIndex: Int, status: String = "running", message: String? = nil) {
        let s = Snapshot(fromChapterIndex: fromChapterIndex, status: status, message: message)
        if let data = try? JSONEncoder().encode(s) {
            try? data.write(to: url(bookID: bookID, kind: "tts"), options: [.atomic])
        }
    }

    static func loadTTSSnapshot(bookID: UUID) -> Snapshot? {
        guard let data = try? Data(contentsOf: url(bookID: bookID, kind: "tts")),
              let s = try? JSONDecoder().decode(Snapshot.self, from: data) else { return nil }
        return s
    }

    static func loadTTS(bookID: UUID) -> Int? {
        loadTTSSnapshot(bookID: bookID)?.fromChapterIndex
    }

    static func hasIncompleteTTS(bookID: UUID) -> Bool {
        guard let s = loadTTSSnapshot(bookID: bookID) else { return false }
        return s.status == "running" || s.status == "interrupted"
    }

    static func clearTTS(bookID: UUID) {
        try? FileManager.default.removeItem(at: url(bookID: bookID, kind: "tts"))
    }

    static func markTTSInterrupted(bookID: UUID, chapterIndex: Int) {
        saveTTS(bookID: bookID, fromChapterIndex: chapterIndex, status: "interrupted", message: "已暂停，可继续")
    }

    // MARK: Translate

    static func saveTranslate(bookID: UUID, fromChapterIndex: Int, status: String = "running", message: String? = nil) {
        let s = Snapshot(fromChapterIndex: fromChapterIndex, status: status, message: message)
        if let data = try? JSONEncoder().encode(s) {
            try? data.write(to: url(bookID: bookID, kind: "translate"), options: [.atomic])
        }
    }

    static func loadTranslateSnapshot(bookID: UUID) -> Snapshot? {
        guard let data = try? Data(contentsOf: url(bookID: bookID, kind: "translate")),
              let s = try? JSONDecoder().decode(Snapshot.self, from: data) else { return nil }
        return s
    }

    static func loadTranslate(bookID: UUID) -> Int? {
        loadTranslateSnapshot(bookID: bookID)?.fromChapterIndex
    }

    static func hasIncompleteTranslate(bookID: UUID) -> Bool {
        guard let s = loadTranslateSnapshot(bookID: bookID) else { return false }
        return s.status == "running" || s.status == "interrupted"
    }

    static func clearTranslate(bookID: UUID) {
        try? FileManager.default.removeItem(at: url(bookID: bookID, kind: "translate"))
    }

    static func markTranslateInterrupted(bookID: UUID, chapterIndex: Int) {
        saveTranslate(bookID: bookID, fromChapterIndex: chapterIndex, status: "interrupted", message: "已暂停，可继续")
    }

    /// 智能续跑起点：优先断点文件；否则扫描首个未完成章
    static func resolveTranslateStart(book: Book, targetLanguage: String) -> Int {
        if let snap = loadTranslateSnapshot(bookID: book.id),
           snap.status == "running" || snap.status == "interrupted" {
            return snap.fromChapterIndex
        }
        let chapters = book.chapters.sorted { $0.index < $1.index }
        for ch in chapters {
            if let existing = BookTranslationService.load(bookID: book.id, chapterID: ch.id),
               existing.status == .done,
               existing.targetLanguage == targetLanguage,
               !existing.paragraphs.isEmpty {
                continue
            }
            return ch.index
        }
        return chapters.first?.index ?? 0
    }

    /// TTS 续跑：断点文件，或首个仍有未缓存段的章（粗检：目录是否为空）
    static func resolveTTSStart(book: Book) -> Int {
        if let snap = loadTTSSnapshot(bookID: book.id),
           snap.status == "running" || snap.status == "interrupted" {
            return snap.fromChapterIndex
        }
        let chapters = book.chapters.sorted { $0.index < $1.index }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let ttsRoot = base.appendingPathComponent("Harbor/TTSAudio/\(book.id.uuidString)", isDirectory: true)
        for ch in chapters {
            let chDir = ttsRoot.appendingPathComponent(ch.id.uuidString, isDirectory: true)
            // 无目录或空 → 视为未完成
            if let files = try? FileManager.default.contentsOfDirectory(atPath: chDir.path), !files.isEmpty {
                continue
            }
            return ch.index
        }
        return chapters.first?.index ?? 0
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
