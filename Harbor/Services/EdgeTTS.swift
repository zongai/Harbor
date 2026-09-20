import Foundation
import CryptoKit
import AVFoundation

/// Microsoft Edge 在线 TTS（协议参考 https://github.com/rany2/edge-tts）
/// 无需 API Key / Edge 浏览器。
enum EdgeTTS {
    private static let trustedToken = "6A5AA1D4EAFF4E9FB37E23D68491D6F4"
    private static let chromiumFull = "143.0.3650.75"
    private static var chromiumMajor: String { chromiumFull.split(separator: ".").first.map(String.init) ?? "143" }
    private static var secMsGecVersion: String { "1-\(chromiumFull)" }
    private static let baseURL = "speech.platform.bing.com/consumer/speech/synthesize/readaloud"
    private static var wssBase: String {
        "wss://\(baseURL)/edge/v1?TrustedClientToken=\(trustedToken)"
    }
    private static let winEpoch: Double = 11_644_473_600
    private static let maxChunkBytes = 3200

    static let defaultChineseVoice = "zh-CN-YunyangNeural"
    static let defaultEnglishVoice = "en-US-EmmaMultilingualNeural"
    static let defaultTurkishVoice = "tr-TR-EmelNeural"

    static let popularVoices: [(id: String, name: String)] = [
        ("zh-CN-YunyangNeural", "云扬（男·普通话）"),
        ("zh-CN-XiaoxiaoNeural", "晓晓（女·普通话）"),
        ("zh-CN-YunxiNeural", "云希（男·普通话）"),
        ("zh-CN-XiaoyiNeural", "晓伊（女·普通话）"),
        ("zh-CN-liaoning-XiaobeiNeural", "晓北（女·东北）"),
        ("zh-TW-HsiaoChenNeural", "曉臻（女·台湾）"),
        ("zh-HK-HiuMaanNeural", "曉曼（女·粤语）"),
        ("en-US-EmmaMultilingualNeural", "Emma（女·美式）"),
        ("en-US-AndrewMultilingualNeural", "Andrew（男·美式）"),
        ("en-GB-SoniaNeural", "Sonia（女·英式）"),
        ("ja-JP-NanamiNeural", "七海（女·日语）"),
        ("ko-KR-SunHiNeural", "SunHi（女·韩语）"),
        ("tr-TR-EmelNeural", "Emel（女·土耳其语）"),
        ("tr-TR-AhmetNeural", "Ahmet（男·土耳其语）"),
    ]

    enum TTSError: LocalizedError {
        case emptyText
        case badURL
        case noAudio
        case network(String)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .emptyText: return "没有可朗读的文本"
            case .badURL: return "TTS 地址无效"
            case .noAudio: return "未收到音频数据，请稍后重试"
            case .network(let s): return s
            case .cancelled: return "已取消"
            }
        }
    }

    // MARK: - Public

    /// 将文本合成为 MP3 数据（自动分块后拼接）
    static func synthesize(
        text: String,
        voice: String,
        rate: String = "+0%",
        pitch: String = "+0Hz",
        volume: String = "+0%",
        isCancelled: (() -> Bool)? = nil
    ) async throws -> Data {
        let cleaned = sanitize(text)
        guard !cleaned.isEmpty else { throw TTSError.emptyText }
        let chunks = splitText(cleaned, maxBytes: maxChunkBytes)
        var audio = Data()
        for chunk in chunks {
            if isCancelled?() == true { throw TTSError.cancelled }
            let part = try await synthesizeChunk(
                text: chunk,
                voice: voice,
                rate: rate,
                pitch: pitch,
                volume: volume
            )
            audio.append(part)
        }
        guard !audio.isEmpty else { throw TTSError.noAudio }
        return audio
    }

    static func preferredVoice(for text: String, configured: String?) -> String {
        if let configured, !configured.isEmpty { return configured }
        if ListLanguageDetect.isMostlyChinese(text) { return defaultChineseVoice }
        if isMostlyTurkish(text) { return defaultTurkishVoice }
        return defaultEnglishVoice
    }

    /// 粗判土耳其语：拉丁字母为主且含 ğüşıöç 等特征字母
    private static func isMostlyTurkish(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let special: Set<Character> = Set("ğüşıöçĞÜŞİÖÇ")
        var letters = 0
        var latin = 0
        var trMark = 0
        for ch in trimmed {
            if ch.isNewline || ch.isWhitespace || ch.isPunctuation || ch.isSymbol || ch.isNumber { continue }
            letters += 1
            if special.contains(ch) {
                trMark += 1
                latin += 1
            } else if ch.isLetter {
                // 排除明显 CJK / 假名 / 谚文
                if let v = ch.unicodeScalars.first?.value {
                    if (0x3040...0x30FF).contains(v) || (0x4E00...0x9FFF).contains(v)
                        || (0xAC00...0xD7AF).contains(v) {
                        continue
                    }
                }
                latin += 1
            }
        }
        guard letters > 0, Double(latin) / Double(letters) >= 0.55 else { return false }
        // 特征字母足够，或短句里至少出现 2 个土耳其特有字母
        if trMark >= 3 { return true }
        if letters <= 40, trMark >= 2 { return true }
        return trMark >= 2 && Double(trMark) / Double(max(1, latin)) >= 0.04
    }

    /// 倍速 0.5～2.0 → SSML rate（如 +20% / -15%）
    static func rateString(from multiplier: Double) -> String {
        let clamped = min(2.0, max(0.5, multiplier))
        let pct = Int(((clamped - 1.0) * 100.0).rounded())
        if pct >= 0 { return "+\(pct)%" }
        return "\(pct)%"
    }

    // MARK: - Chunk synthesis via WebSocket

    private static func synthesizeChunk(
        text: String,
        voice: String,
        rate: String,
        pitch: String,
        volume: String
    ) async throws -> Data {
        let connectionId = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let gec = generateSecMsGec()
        let urlStr =
            "\(wssBase)&ConnectionId=\(connectionId)&Sec-MS-GEC=\(gec)&Sec-MS-GEC-Version=\(secMsGecVersion)"
        guard let url = URL(string: urlStr) else { throw TTSError.badURL }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold", forHTTPHeaderField: "Origin")
        request.setValue("muid=\(randomMUID());", forHTTPHeaderField: "Cookie")
        request.timeoutInterval = 60

        let session = URLSession(configuration: .ephemeral)
        let task = session.webSocketTask(with: request)
        task.resume()

        defer {
            task.cancel(with: .goingAway, reason: nil)
            session.invalidateAndCancel()
        }

        // speech.config
        let configMsg =
            "X-Timestamp:\(jsDateString())\r\n" +
            "Content-Type:application/json; charset=utf-8\r\n" +
            "Path:speech.config\r\n\r\n" +
            "{\"context\":{\"synthesis\":{\"audio\":{\"metadataoptions\":{" +
            "\"sentenceBoundaryEnabled\":\"false\",\"wordBoundaryEnabled\":\"true\"" +
            "},\"outputFormat\":\"audio-24khz-48kbitrate-mono-mp3\"}}}}\r\n"
        try await task.send(.string(configMsg))

        // SSML
        let ssml = makeSSML(text: text, voice: voice, rate: rate, pitch: pitch, volume: volume)
        let reqId = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let ssmlMsg =
            "X-RequestId:\(reqId)\r\n" +
            "Content-Type:application/ssml+xml\r\n" +
            "X-Timestamp:\(jsDateString())Z\r\n" +
            "Path:ssml\r\n\r\n" +
            ssml
        try await task.send(.string(ssmlMsg))

        var audio = Data()
        var gotAudio = false
        var finished = false
        let deadline = Date().addingTimeInterval(90)

        while !finished && Date() < deadline {
            let message: URLSessionWebSocketTask.Message
            do {
                message = try await task.receive()
            } catch {
                if gotAudio { break }
                throw TTSError.network(error.localizedDescription)
            }

            switch message {
            case .string(let textMsg):
                if textMsg.contains("Path:turn.end") {
                    finished = true
                }
            case .data(let data):
                guard data.count >= 2 else { continue }
                let headerLen = Int(data[0]) << 8 | Int(data[1])
                guard headerLen + 2 <= data.count else { continue }
                let headerData = data.subdata(in: 2..<(2 + headerLen))
                let body = data.subdata(in: (2 + headerLen)..<data.count)
                let headerStr = String(data: headerData, encoding: .utf8) ?? ""
                guard headerStr.contains("Path:audio") else { continue }
                if body.isEmpty { continue }
                if headerStr.contains("Content-Type:audio/mpeg") || headerStr.lowercased().contains("audio") {
                    audio.append(body)
                    gotAudio = true
                }
            @unknown default:
                continue
            }
        }

        guard gotAudio, !audio.isEmpty else { throw TTSError.noAudio }
        return audio
    }

    // MARK: - Helpers

    private static var userAgent: String {
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
            + "(KHTML, like Gecko) Chrome/\(chromiumMajor).0.0.0 Safari/537.36 "
            + "Edg/\(chromiumMajor).0.0.0"
    }

    private static func generateSecMsGec() -> String {
        var ticks = Date().timeIntervalSince1970 + winEpoch
        ticks -= ticks.truncatingRemainder(dividingBy: 300)
        ticks *= 1e9 / 100
        let str = String(format: "%.0f", ticks) + trustedToken
        let digest = SHA256.hash(data: Data(str.utf8))
        return digest.map { String(format: "%02X", $0) }.joined()
    }

    private static func randomMUID() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02X", $0) }.joined()
    }

    private static func jsDateString() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "EEE MMM dd yyyy HH:mm:ss 'GMT+0000 (Coordinated Universal Time)'"
        return f.string(from: Date())
    }

    private static func sanitize(_ text: String) -> String {
        let stripped = HTMLUtils.stripTags(text)
        return String(stripped.unicodeScalars.map { s -> Character in
            let v = s.value
            if (0...8).contains(v) || (11...12).contains(v) || (14...31).contains(v) {
                return " "
            }
            return Character(s)
        }).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static func makeSSML(text: String, voice: String, rate: String, pitch: String, volume: String) -> String {
        let body = xmlEscape(text)
        return """
        <speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='en-US'>\
        <voice name='\(voice)'>\
        <prosody pitch='\(pitch)' rate='\(rate)' volume='\(volume)'>\
        \(body)\
        </prosody></voice></speak>
        """
    }

    private static func splitText(_ text: String, maxBytes: Int) -> [String] {
        let data = Data(text.utf8)
        if data.count <= maxBytes { return [text] }
        var result: [String] = []
        var start = text.startIndex
        while start < text.endIndex {
            var end = start
            var bytes = 0
            var lastBreak = start
            while end < text.endIndex {
                let ch = text[end]
                let bl = String(ch).utf8.count
                if bytes + bl > maxBytes { break }
                bytes += bl
                let next = text.index(after: end)
                if ch == "\n" || ch == "。" || ch == "！" || ch == "？" || ch == "." || ch == "!" || ch == "?" || ch == " " {
                    lastBreak = next
                }
                end = next
            }
            if lastBreak > start && end < text.endIndex {
                end = lastBreak
            }
            if end == start { end = text.index(after: start) }
            let piece = String(text[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty { result.append(piece) }
            start = end
        }
        return result.isEmpty ? [text] : result
    }
}

// MARK: - Player

@MainActor
final class EdgeTTSPlayer: ObservableObject {
    static let shared = EdgeTTSPlayer()

    @Published var isPlaying = false
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var player: AVAudioPlayer?
    private var session = 0

    func stop() {
        session += 1
        player?.stop()
        player = nil
        isPlaying = false
        isLoading = false
    }

    func toggle(text: String, voice: String?, rate: Double = 1.0) async {
        if isPlaying || isLoading {
            stop()
            return
        }
        await play(text: text, voice: voice, rate: rate)
    }

    func play(text: String, voice: String?, rate: Double = 1.0) async {
        stop()
        let mySession = session
        isLoading = true
        errorMessage = nil
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            let resolved = EdgeTTS.preferredVoice(for: text, configured: voice)
            let rateStr = EdgeTTS.rateString(from: rate)
            let data = try await EdgeTTS.synthesize(text: text, voice: resolved, rate: rateStr) {
                mySession != self.session
            }
            guard mySession == session else { return }
            let p = try AVAudioPlayer(data: data)
            p.prepareToPlay()
            player = p
            isLoading = false
            isPlaying = true
            p.play()
            // Poll until finished
            while p.isPlaying {
                if mySession != session { return }
                try await Task.sleep(nanoseconds: 200_000_000)
            }
            if mySession == session {
                isPlaying = false
                player = nil
            }
        } catch {
            if mySession == session {
                isLoading = false
                isPlaying = false
                if let e = error as? EdgeTTS.TTSError, case .cancelled = e {
                    errorMessage = nil
                } else {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
