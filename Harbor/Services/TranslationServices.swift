import Foundation
import Observation

/// 翻译专用 URLSession：提高同主机并发连接，减少排队
enum TranslationHTTP {
    static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 18
        cfg.timeoutIntervalForResource = 45
        cfg.httpMaximumConnectionsPerHost = 10
        cfg.waitsForConnectivity = true
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: cfg)
    }()
}

enum TranslationError: LocalizedError {
    case noProvider
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .noProvider:
            return "未配置翻译引擎，请在设置中添加AI提供商"
        case .apiError(let msg):
            return msg
        }
    }
}

// MARK: - DeepL

enum DeepLTranslate {
    /// DeepL Free API Key 通常以 ":fx" 结尾，会自动使用对应的免费端点
    static func translate(text: String, apiKey: String, targetLang: String = "ZH") async throws -> String {
        let all = try await translate(texts: [text], apiKey: apiKey, targetLang: targetLang)
        guard let first = all.first, !first.isEmpty else {
            throw TranslationError.apiError("解析 DeepL 响应失败")
        }
        return first
    }

    /// 一次请求翻译多段文本，顺序与输入一致
    static func translate(texts: [String], apiKey: String, targetLang: String = "ZH") async throws -> [String] {
        guard !apiKey.isEmpty else { throw TranslationError.apiError("未配置 DeepL API Key") }
        guard !texts.isEmpty else { return [] }

        let isFreeKey = apiKey.hasSuffix(":fx")
        let baseURL = isFreeKey
            ? "https://api-free.deepl.com/v2/translate"
            : "https://api.deepl.com/v2/translate"

        guard let url = URL(string: baseURL) else {
            throw TranslationError.apiError("无效的 DeepL URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("DeepL-Auth-Key \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "text": texts,
            "target_lang": targetLang
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await TranslationHTTP.session.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TranslationError.apiError("DeepL API 错误 \(http.statusCode): \(msg.prefix(200))")
        }

        struct Translation: Decodable {
            let text: String
            let detected_source_language: String?
        }
        struct Resp: Decodable { let translations: [Translation] }

        guard let resp = try? JSONDecoder().decode(Resp.self, from: data),
              resp.translations.count == texts.count else {
            throw TranslationError.apiError("解析 DeepL 响应失败")
        }

        return resp.translations.map(\.text)
    }
}

// MARK: - Google Translate (free unofficial endpoint)

enum GoogleTranslate {
    /// 与 Readest 一致：全局并发闸，避免 free endpoint 被 429
    private static let maxConcurrent = 4
    private static let gate = RequestGate(limit: maxConcurrent)

    /// 纯免费接口（无 Key）：
    /// GET https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=…&dt=t&q=…
    static func translate(text: String, targetLang: String = "zh-CN") async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let tl: String = {
            switch targetLang.lowercased() {
            case "zh", "zh-hans": return "zh-CN"
            case "zh-hant": return "zh-TW"
            default: return targetLang
            }
        }()
        return try await gate.run {
            if trimmed.utf8.count < 1800 {
                do {
                    return try await request(text: trimmed, targetLang: tl, method: "GET")
                } catch {
                    return try await request(text: trimmed, targetLang: tl, method: "POST")
                }
            }
            return try await request(text: trimmed, targetLang: tl, method: "POST")
        }
    }

    /// 简单异步信号量：跨调用共享，防止列表翻译打爆 Google（Readest 同思路）
    private actor RequestGate {
        private let limit: Int
        private var active = 0
        private var waiters: [CheckedContinuation<Void, Never>] = []
        init(limit: Int) { self.limit = max(1, limit) }
        func run<T: Sendable>(_ work: @Sendable () async throws -> T) async throws -> T {
            await acquire()
            do {
                let value = try await work()
                release()
                return value
            } catch {
                release()
                throw error
            }
        }
        private func acquire() async {
            if active < limit {
                active += 1
                return
            }
            await withCheckedContinuation { cont in
                waiters.append(cont)
            }
            // 被唤醒时槽位已由 release 转交，不再 +1
        }
        private func release() {
            if !waiters.isEmpty {
                let next = waiters.removeFirst()
                next.resume()
            } else {
                active = max(0, active - 1)
            }
        }
    }

    private static func request(text: String, targetLang: String, method: String) async throws -> String {
        if method == "GET" {
            var comps = URLComponents(string: "https://translate.googleapis.com/translate_a/single")!
            comps.queryItems = [
                URLQueryItem(name: "client", value: "gtx"),
                URLQueryItem(name: "sl", value: "auto"),
                URLQueryItem(name: "tl", value: targetLang),
                URLQueryItem(name: "dt", value: "t"),
                URLQueryItem(name: "q", value: text)
            ]
            guard let url = comps.url else { throw TranslationError.apiError("无效的 Google URL") }
            var request = URLRequest(url: url, timeoutInterval: 15)
            request.httpMethod = "GET"
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            return try await parse(request)
        } else {
            guard let url = URL(string: "https://translate.googleapis.com/translate_a/single") else {
                throw TranslationError.apiError("无效的URL")
            }
            var request = URLRequest(url: url, timeoutInterval: 15)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
            var body = URLComponents()
            body.queryItems = [
                URLQueryItem(name: "client", value: "gtx"),
                URLQueryItem(name: "sl", value: "auto"),
                URLQueryItem(name: "tl", value: targetLang),
                URLQueryItem(name: "dt", value: "t"),
                URLQueryItem(name: "q", value: text)
            ]
            request.httpBody = body.percentEncodedQuery?.data(using: .utf8)
            return try await parse(request)
        }
    }

    private static func parse(_ request: URLRequest) async throws -> String {
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            if http.statusCode == 429 {
                throw TranslationError.apiError("Google 限流 (429)，请稍后再试")
            }
            throw TranslationError.apiError("Google 翻译失败 (状态码 \(http.statusCode))")
        }
        if let raw = String(data: data, encoding: .utf8),
           raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("<!") {
            throw TranslationError.apiError("Google 限流 (429)，请稍后再试")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let firstElement = json.first as? [Any] else {
            throw TranslationError.apiError("解析 Google 响应失败")
        }
        let result = firstElement.compactMap { segment -> String? in
            guard let segArray = segment as? [Any],
                  let text = segArray.first as? String else { return nil }
            return text
        }.joined()
        if result.isEmpty {
            throw TranslationError.apiError("Google 返回空译文")
        }
        return result
    }
}


// MARK: - MyMemory (free, no key; daily quota per IP)

enum MyMemoryTranslate {
    static func translate(text: String, targetLang: String = "zh-CN") async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        // MyMemory 单次建议 < 500 字符
        let chunk = String(trimmed.prefix(450))
        var comps = URLComponents(string: "https://api.mymemory.translated.net/get")!
        comps.queryItems = [
            URLQueryItem(name: "q", value: chunk),
            URLQueryItem(name: "langpair", value: "Autodetect|\(targetLang)")
        ]
        guard let url = comps.url else { throw TranslationError.apiError("MyMemory URL 无效") }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw TranslationError.apiError("MyMemory 失败 (\(http.statusCode))")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rd = json["responseData"] as? [String: Any],
              let translated = rd["translatedText"] as? String else {
            throw TranslationError.apiError("MyMemory 解析失败")
        }
        let out = translated.trimmingCharacters(in: .whitespacesAndNewlines)
        if out.isEmpty { throw TranslationError.apiError("MyMemory 返回空译文") }
        // 配额耗尽时接口可能原样返回原文或带 MYMEMORY WARNING
        if out.uppercased().contains("MYMEMORY WARNING") {
            throw TranslationError.apiError("MyMemory 额度可能已用尽")
        }
        return out
    }
}


// MARK: - Lingva (REST v1 GET & POST, no key)

enum LingvaTranslate {
    /// 公共实例；可在设置中指定自定义根地址
    private static let defaultHosts = [
        "https://lingva.ml",
        "https://translate.plausibility.cloud",
        "https://lingva.lunar.icu",
        "https://translate.projectsegfau.lt",
        "https://lingva.garudalinux.org"
    ]

    static func resolveHosts(customBase: String?) -> [String] {
        var list: [String] = []
        if let c = customBase?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty {
            let base = c.hasSuffix("/") ? String(c.dropLast()) : c
            list.append(base)
        }
        list.append(contentsOf: defaultHosts)
        var seen = Set<String>()
        return list.filter { seen.insert($0).inserted }
    }

    static func mapTarget(_ targetLang: String) -> String {
        switch targetLang.lowercased() {
        case "zh-cn", "zh-hans", "zh": return "zh"
        case "zh-tw", "zh-hant": return "zh_HANT"
        default:
            return targetLang.replacingOccurrences(of: "-", with: "_")
        }
    }

    /// REST v1：短文本优先 GET；较长文本用 POST JSON
    static func translate(text: String, targetLang: String = "zh", customBase: String? = nil) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let tl = mapTarget(targetLang)
        var lastError: Error = TranslationError.apiError("Lingva 暂不可用")
        for host in resolveHosts(customBase: customBase) {
            do {
                // 超过 ~300 字符用 POST，避免 URL 过长
                if trimmed.count > 300 {
                    return try await post(host: host, target: tl, query: trimmed)
                }
                do {
                    return try await get(host: host, target: tl, query: trimmed)
                } catch {
                    // GET 失败再试 POST
                    return try await post(host: host, target: tl, query: trimmed)
                }
            } catch {
                lastError = error
                continue
            }
        }
        throw lastError
    }

    /// GET /api/v1/:source/:target/:query
    private static func get(host: String, target: String, query: String) async throws -> String {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? query
        guard let url = URL(string: "\(host)/api/v1/auto/\(target)/\(encoded)") else {
            throw TranslationError.apiError("Lingva GET URL 无效")
        }
        var request = URLRequest(url: url, timeoutInterval: 16)
        request.httpMethod = "GET"
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await parseResponse(request: request, host: host)
    }

    /// POST /api/v1/:source/:target  body: {"query":"..."}
    private static func post(host: String, target: String, query: String) async throws -> String {
        guard let url = URL(string: "\(host)/api/v1/auto/\(target)") else {
            throw TranslationError.apiError("Lingva POST URL 无效")
        }
        var request = URLRequest(url: url, timeoutInterval: 18)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["query": query])
        return try await parseResponse(request: request, host: host)
    }

    private static func parseResponse(request: URLRequest, host: String) async throws -> String {
        let (data, response) = try await TranslationHTTP.session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TranslationError.apiError("Lingva 无响应 (\(host))")
        }
        if !(200..<300).contains(http.statusCode) {
            throw TranslationError.apiError("Lingva HTTP \(http.statusCode) (\(host))")
        }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let translation = json["translation"] as? String, !translation.isEmpty {
                return translation
            }
            if let err = json["error"] as? String {
                throw TranslationError.apiError("Lingva: \(err)")
            }
        }
        throw TranslationError.apiError("Lingva 解析失败 (\(host))")
    }
}

// MARK: - Microsoft Translator

enum MicrosoftTranslate {
    static func translate(text: String, apiKey: String, region: String = "", targetLang: String = "zh-Hans") async throws -> String {
        let all = try await translate(texts: [text], apiKey: apiKey, region: region, targetLang: targetLang)
        guard let first = all.first, !first.isEmpty else {
            throw TranslationError.apiError("Microsoft Translator 返回无效响应")
        }
        return first
    }

    /// 一次请求翻译多段文本，顺序与输入一致
    /// - Parameter region: Azure 资源区域（如 eastasia、eastus、global）。多服务资源 Key 必须带区域，否则常返回 401。
    static func translate(texts: [String], apiKey: String, region: String = "", targetLang: String = "zh-Hans") async throws -> [String] {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw TranslationError.apiError("未配置 Microsoft Translator API Key") }
        guard !texts.isEmpty else { return [] }
        let url = URL(string: "https://api.cognitive.microsofttranslator.com/translate?api-version=3.0&to=\(targetLang)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        let regionTrim = region.trimmingCharacters(in: .whitespacesAndNewlines)
        // 多服务 / 区域资源必须带 Region；未填时默认 global（全球资源）
        request.setValue(regionTrim.isEmpty ? "global" : regionTrim, forHTTPHeaderField: "Ocp-Apim-Subscription-Region")
        request.httpBody = try JSONEncoder().encode(texts.map { ["Text": $0] })
        let (data, response) = try await TranslationHTTP.session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            if http.statusCode == 401 {
                throw TranslationError.apiError("Microsoft 401：Key 无效或区域不匹配。请在设置中填写 Azure 资源区域（如 eastasia / eastus / global），并确认 Key 来自 Translator 或多服务资源。")
            }
            throw TranslationError.apiError("Microsoft Translator 错误 \(http.statusCode): \(msg.prefix(200))")
        }
        struct Response: Decodable {
            struct Translation: Decodable { let text: String; let to: String }
            let translations: [Translation]
        }
        guard let results = try? JSONDecoder().decode([Response].self, from: data),
              results.count == texts.count else {
            throw TranslationError.apiError("Microsoft Translator 返回无效响应")
        }
        return results.map { $0.translations.first?.text ?? "" }
    }
}

// MARK: - Unified AI Translation / Summary

enum AITranslate {
    static func translate(text: String, provider: AIProvider, apiKey: String) async throws -> String {
        try await translate(
            text: text,
            provider: provider,
            apiKey: apiKey,
            promptTemplate: AppStore.defaultTranslationPrompt
        )
    }

    static func translate(text: String, provider: AIProvider, apiKey: String, promptTemplate: String) async throws -> String {
        guard !apiKey.isEmpty else { throw TranslationError.apiError("未配置 API Key") }
        let template = promptTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? AppStore.defaultTranslationPrompt
            : promptTemplate
        var prompt = template.replacingOccurrences(of: "{{text}}", with: text)
        if !template.contains("{{text}}") {
            prompt += "\n\n" + text
        }
        return try await callAI(prompt: prompt, provider: provider, apiKey: apiKey, maxTokens: 2048)
    }
}

enum AISummary {
    static func summarize(article: Article, provider: AIProvider, apiKey: String) async throws -> String {
        try await summarize(
            article: article,
            provider: provider,
            apiKey: apiKey,
            promptTemplate: AppStore.defaultSummaryPrompt
        )
    }

    static func summarize(article: Article, provider: AIProvider, apiKey: String, promptTemplate: String) async throws -> String {
        guard !apiKey.isEmpty else { throw TranslationError.apiError("未配置 API Key") }
        let content = String(HTMLUtils.stripTags(article.content).prefix(2500))
        let template = promptTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? AppStore.defaultSummaryPrompt
            : promptTemplate
        var prompt = template
            .replacingOccurrences(of: "{{title}}", with: article.title)
            .replacingOccurrences(of: "{{content}}", with: content)
        if !template.contains("{{title}}") && !template.contains("{{content}}") {
            prompt += "\n\n标题：\(article.title)\n\n内容：\(content)"
        }
        return try await callAI(prompt: prompt, provider: provider, apiKey: apiKey, maxTokens: 600)
    }
}

/// 框选文字 AI 解释
enum AIExplain {
    static let defaultPrompt = """
    请用简洁的中文解释下面这段文字（词义、专有名词、语境或背景）。只输出解释，不要标题，不要复述整段原文：

    {{text}}
    """

    static func explain(text: String, provider: AIProvider, apiKey: String, promptTemplate: String? = nil) async throws -> String {
        guard !apiKey.isEmpty else { throw TranslationError.apiError("未配置 API Key") }
        let clipped = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(800))
        guard !clipped.isEmpty else { throw TranslationError.apiError("未选中有效文字") }
        let template = (promptTemplate ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? defaultPrompt
            : promptTemplate!
        var prompt = template.replacingOccurrences(of: "{{text}}", with: clipped)
        if !template.contains("{{text}}") {
            prompt += "\n\n\(clipped)"
        }
        return try await callAI(prompt: prompt, provider: provider, apiKey: apiKey, maxTokens: 500)
    }
}

/// 统一入口：根据 provider.kind 走 Gemini 或 OpenAI 兼容接口
func callAI(prompt: String, provider: AIProvider, apiKey: String, maxTokens: Int = 500, modelOverride: String? = nil) async throws -> String {
    var p = provider
    if let m = modelOverride?.trimmingCharacters(in: .whitespacesAndNewlines), !m.isEmpty {
        p.model = m
    }
    if p.kind == "gemini" || p.name.lowercased().contains("gemini") {
        return try await callGemini(prompt: prompt, provider: p, apiKey: apiKey)
    }
    return try await callOpenAICompatible(prompt: prompt, provider: p, apiKey: apiKey, maxTokens: maxTokens)
}

/// 多轮对话：messages 为 user/assistant/system 序列（按时间顺序）
func callAIChat(
    messages: [(role: ChatRole, content: String)],
    provider: AIProvider,
    apiKey: String,
    maxTokens: Int = 2048
) async throws -> String {
    if provider.kind == "gemini" || provider.name.lowercased().contains("gemini") {
        return try await callGeminiChat(messages: messages, provider: provider, apiKey: apiKey, maxTokens: maxTokens)
    }
    return try await callOpenAICompatibleChat(messages: messages, provider: provider, apiKey: apiKey, maxTokens: maxTokens)
}

func callOpenAICompatibleChat(
    messages: [(role: ChatRole, content: String)],
    provider: AIProvider,
    apiKey: String,
    maxTokens: Int = 2048
) async throws -> String {
    let baseURL = provider.baseURL.hasSuffix("/") ? String(provider.baseURL.dropLast()) : provider.baseURL
    guard let url = URL(string: "\(baseURL)/chat/completions") else {
        throw TranslationError.apiError("无效的 Base URL")
    }
    var request = URLRequest(url: url, timeoutInterval: 90)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

    let mapped: [[String: String]] = messages.compactMap { item in
        let text = item.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let role: String
        switch item.role {
        case .user: role = "user"
        case .assistant: role = "assistant"
        case .system: role = "system"
        }
        return ["role": role, "content": text]
    }
    guard !mapped.isEmpty else { throw TranslationError.apiError("消息为空") }

    let body: [String: Any] = [
        "model": provider.model,
        "messages": mapped,
        "max_tokens": max(maxTokens, 800)
    ]
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)
    let (data, response) = try await URLSession.shared.data(for: request)
    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
        let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
        throw TranslationError.apiError("API 错误 \(http.statusCode): \(msg.prefix(200))")
    }
    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let choices = json["choices"] as? [[String: Any]],
       let message = choices.first?["message"] as? [String: Any] {
        let content = (message["content"] as? String) ?? ""
        let cleaned = AIResponseSanitizer.stripThinking(content)
        if !cleaned.isEmpty { return cleaned }
    }
    throw TranslationError.apiError("解析 AI 响应失败")
}

func callGeminiChat(
    messages: [(role: ChatRole, content: String)],
    provider: AIProvider,
    apiKey: String,
    maxTokens: Int = 2048
) async throws -> String {
    let model = provider.model.isEmpty ? "gemini-2.0-flash" : provider.model
    let urlStr = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"
    guard let url = URL(string: urlStr) else {
        throw TranslationError.apiError("无效的 Gemini URL")
    }
    var request = URLRequest(url: url, timeoutInterval: 90)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    var systemText = ""
    var contents: [[String: Any]] = []
    for item in messages {
        let text = item.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { continue }
        switch item.role {
        case .system:
            if systemText.isEmpty { systemText = text }
            else { systemText += "\n" + text }
        case .user:
            contents.append(["role": "user", "parts": [["text": text]]])
        case .assistant:
            contents.append(["role": "model", "parts": [["text": text]]])
        }
    }
    guard !contents.isEmpty else { throw TranslationError.apiError("消息为空") }

    var body: [String: Any] = [
        "contents": contents,
        "generationConfig": ["maxOutputTokens": max(maxTokens, 1024)]
    ]
    if !systemText.isEmpty {
        body["systemInstruction"] = ["parts": [["text": systemText]]]
    }
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)

    let (data, response) = try await URLSession.shared.data(for: request)
    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
        let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
        throw TranslationError.apiError("Gemini API 错误 \(http.statusCode): \(msg.prefix(200))")
    }
    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let candidates = json["candidates"] as? [[String: Any]],
       let content = candidates.first?["content"] as? [String: Any],
       let parts = content["parts"] as? [[String: Any]] {
        var texts: [String] = []
        for part in parts {
            if let thought = part["thought"] as? Bool, thought { continue }
            if let text = part["text"] as? String, !text.isEmpty {
                texts.append(text)
            }
        }
        let cleaned = AIResponseSanitizer.stripThinking(texts.joined())
        if !cleaned.isEmpty { return cleaned }
    }
    let raw = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
    throw TranslationError.apiError("解析 Gemini 响应失败: \(raw)")
}

func callOpenAICompatible(prompt: String, provider: AIProvider, apiKey: String, maxTokens: Int = 500) async throws -> String {
    let baseURL = provider.baseURL.hasSuffix("/") ? String(provider.baseURL.dropLast()) : provider.baseURL
    guard let url = URL(string: "\(baseURL)/chat/completions") else {
        throw TranslationError.apiError("无效的 Base URL")
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    // 思考模型可能占用较多 completion token；略提高上限，最终只展示正文
    let body: [String: Any] = [
        "model": provider.model,
        "messages": [["role": "user", "content": prompt]],
        "max_tokens": max(maxTokens, 800)
    ]
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)
    let (data, response) = try await URLSession.shared.data(for: request)
    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
        let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
        throw TranslationError.apiError("API 错误 \(http.statusCode): \(msg.prefix(200))")
    }
    // 兼容：content / reasoning_content / reasoning；只取最终回答
    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let choices = json["choices"] as? [[String: Any]],
       let message = choices.first?["message"] as? [String: Any] {
        let content = (message["content"] as? String) ?? ""
        // 忽略 reasoning_content / reasoning / reasoning_text 等思考字段
        let cleaned = AIResponseSanitizer.stripThinking(content)
        if !cleaned.isEmpty {
            return cleaned
        }
        // 少数接口把最终答案放在其它字段
        for key in ["output_text", "result", "answer"] {
            if let alt = message[key] as? String {
                let c = AIResponseSanitizer.stripThinking(alt)
                if !c.isEmpty { return c }
            }
        }
    }
    throw TranslationError.apiError("解析 AI 响应失败")
}

func callGemini(prompt: String, provider: AIProvider, apiKey: String) async throws -> String {
    let model = provider.model.isEmpty ? "gemini-2.0-flash" : provider.model
    let urlStr = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"
    guard let url = URL(string: urlStr) else {
        throw TranslationError.apiError("无效的 Gemini URL")
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    // thought 类模型：请求不把思考过程混进可见文本（若接口支持）
    var body: [String: Any] = [
        "contents": [
            ["parts": [["text": prompt]]]
        ]
    ]
    // Gemini 2.5 thinking：generationConfig 可选
    body["generationConfig"] = [
        "maxOutputTokens": 2048
    ]
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)

    let (data, response) = try await URLSession.shared.data(for: request)

    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
        let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
        throw TranslationError.apiError("Gemini API 错误 \(http.statusCode): \(msg.prefix(200))")
    }

    // 解析 parts：跳过 thought / 仅拼接可见 text
    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let candidates = json["candidates"] as? [[String: Any]],
       let content = candidates.first?["content"] as? [String: Any],
       let parts = content["parts"] as? [[String: Any]] {
        var texts: [String] = []
        for part in parts {
            // thought: true 的 part 为思考过程，跳过
            if let thought = part["thought"] as? Bool, thought { continue }
            if let text = part["text"] as? String, !text.isEmpty {
                texts.append(text)
            }
        }
        let joined = texts.joined()
        let cleaned = AIResponseSanitizer.stripThinking(joined)
        if !cleaned.isEmpty {
            return cleaned
        }
    }
    let raw = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
    throw TranslationError.apiError("解析 Gemini 响应失败: \(raw)")
}

/// 过滤思考模型输出中的推理过程，只保留最终回答
enum AIResponseSanitizer {
    static func stripThinking(_ text: String) -> String {
        var result = text

        // 常见标签块：<think> <thinking> <reasoning> <reflection> <thought>
        let tagPatterns = [
            #"<think>[\s\S]*?</think>"#,
            #"<thinking>[\s\S]*?</thinking>"#,
            #"<reasoning>[\s\S]*?</reasoning>"#,
            #"<reflection>[\s\S]*?</reflection>"#,
            #"<thought>[\s\S]*?</thought>"#,
            #"<redacted_reasoning>[\s\S]*?</redacted_reasoning>"#,
        ]
        for pattern in tagPatterns {
            if let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(result.startIndex..., in: result)
                result = re.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
            }
        }

        // 未闭合的 <think>… 直接截到标签前
        if let re = try? NSRegularExpression(pattern: #"<think>[\s\S]*"#, options: [.caseInsensitive]) {
            let range = NSRange(result.startIndex..., in: result)
            result = re.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }

        // 中文标记
        let cnPatterns = [
            #"【思考】[\s\S]*?【/思考】"#,
            #"【推理】[\s\S]*?【/推理】"#,
            #"（思考过程：[\s\S]*?）"#,
        ]
        for pattern in cnPatterns {
            if let re = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(result.startIndex..., in: result)
                result = re.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
            }
        }

        // 去掉开头的 “Thinking / 思考过程” 段落（到空行或文末）
        if let re = try? NSRegularExpression(
            pattern: #"(?im)^#{1,3}\s*(thinking|reasoning|thought process|思考过程|推理过程)\s*$[\s\S]*?(?=^#{1,3}\s|\Z)"#,
            options: []
        ) {
            let range = NSRange(result.startIndex..., in: result)
            result = re.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - HTML Utilities (entities + strip)

enum HTMLUtils {
    /// 解码常见 HTML 实体（含数字实体如 &#8216;）
    /// 解码正文中残留的百分号编码片段（如 %e8%ae%ae → 议）
    static func decodePercentEncodings(_ text: String) -> String {
        var result = text
        // 连续 %XX 序列
        if let regex = try? NSRegularExpression(pattern: #"(?:%[0-9A-Fa-f]{2}){2,}"#, options: []) {
            let ns = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: ns.length)).reversed()
            for match in matches {
                guard let range = Range(match.range, in: result) else { continue }
                let encoded = String(result[range])
                if let decoded = encoded.removingPercentEncoding, decoded != encoded {
                    result.replaceSubrange(range, with: decoded)
                }
            }
        }
        // 单个 %XX 若为可打印字符也尝试
        if let regex = try? NSRegularExpression(pattern: #"%[0-9A-Fa-f]{2}"#, options: []) {
            let ns = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: ns.length)).reversed()
            for match in matches {
                guard let range = Range(match.range, in: result) else { continue }
                let encoded = String(result[range])
                if let decoded = encoded.removingPercentEncoding, decoded != encoded,
                   decoded.unicodeScalars.allSatisfy({ !$0.properties.isNoncharacterCodePoint }) {
                    result.replaceSubrange(range, with: decoded)
                }
            }
        }
        return result
    }

    static func decodeEntities(_ html: String) -> String {
        var result = html
        // 命名实体
        // 用拼接避免源文件中出现完整 HTML 实体字面量（部分同步路径会错误解码）
        let named: [(String, String)] = [
            ("&" + "amp;", "&"),
            ("&" + "lt;", "<"),
            ("&" + "gt;", ">"),
            ("&" + "quot;", "\""),
            ("&" + "apos;", "'"),
            ("&" + "#39;", "'"),
            ("&" + "nbsp;", " "),
            ("&" + "ldquo;", "\u{201C}"),
            ("&" + "rdquo;", "\u{201D}"),
            ("&" + "lsquo;", "\u{2018}"),
            ("&" + "rsquo;", "\u{2019}"),
            ("&" + "mdash;", "\u{2014}"),
            ("&" + "ndash;", "\u{2013}"),
            ("&" + "hellip;", "\u{2026}"),
            ("&" + "copy;", "©"),
            ("&" + "reg;", "®"),
            ("&" + "trade;", "™"),
        ]
        for (entity, char) in named {
            result = result.replacingOccurrences(of: entity, with: char)
        }
        // 十进制数字实体 &#8216;
        if let regex = try? NSRegularExpression(pattern: "&#(\\d+);", options: []) {
            let ns = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: ns.length)).reversed()
            for match in matches {
                let numRange = match.range(at: 1)
                if let range = Range(numRange, in: result),
                   let code = Int(result[range]),
                   let scalar = Unicode.Scalar(code) {
                    let fullRange = Range(match.range, in: result)!
                    result.replaceSubrange(fullRange, with: String(Character(scalar)))
                }
            }
        }
        // 十六进制 &#x2018;
        if let regex = try? NSRegularExpression(pattern: "&#x([0-9a-fA-F]+);", options: []) {
            let ns = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: ns.length)).reversed()
            for match in matches {
                let numRange = match.range(at: 1)
                if let range = Range(numRange, in: result),
                   let code = Int(result[range], radix: 16),
                   let scalar = Unicode.Scalar(code) {
                    let fullRange = Range(match.range, in: result)!
                    result.replaceSubrange(fullRange, with: String(Character(scalar)))
                }
            }
        }
        return decodePercentEncodings(result)
    }

    static func stripTags(_ html: String) -> String {
        var result = html
        result = result.replacingOccurrences(of: "<![CDATA[", with: "")
        result = result.replacingOccurrences(of: "]]>", with: "")
        if let re = try? NSRegularExpression(pattern: "<!--([\\s\\S]*?)-->", options: []) {
            result = re.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }
        if let re = try? NSRegularExpression(pattern: "<script[\\s\\S]*?</script>", options: .caseInsensitive) {
            result = re.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }
        if let re = try? NSRegularExpression(pattern: "<style[\\s\\S]*?</style>", options: .caseInsensitive) {
            result = re.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }
        result = result.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: .regularExpression)
        result = result.replacingOccurrences(of: #"</p>|</div>|</li>|</tr>|</h[1-6]>"#, with: "\n", options: .regularExpression)
        if let re = try? NSRegularExpression(pattern: "<[^>]+>", options: [.dotMatchesLineSeparators]) {
            result = re.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }
        // 半截未闭合标签（如裸露的 <div class=）
        if let re = try? NSRegularExpression(pattern: "</?[A-Za-z][^<>\\n]{0,80}", options: []) {
            result = re.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }
        result = decodeEntities(result)
        result = result.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 列表/标题用：去标签并压缩空白
    static func plainText(_ html: String) -> String {
        stripTags(html)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// 翻译前抽出表格与图片：表格整块原样保留（不送译），避免结构被破坏
    static func extractImagesForTranslation(_ html: String) -> (text: String, images: [String]) {
        let extracted = extractMediaForTranslation(html)
        return (extracted.text, extracted.images)
    }

    /// 抽出 table / img，用占位符替换后送译；表格跳过翻译以保留样式
    static func extractMediaForTranslation(_ html: String) -> (text: String, images: [String], tables: [String]) {
        var working = html
        var tables: [String] = []
        var images: [String] = []

        // 1) 整表抽出（从后往前）
        if let tableRe = try? NSRegularExpression(
            pattern: #"<table\b[\s\S]*?</table>"#,
            options: [.caseInsensitive]
        ) {
            let ns = working as NSString
            let matches = tableRe.matches(in: working, range: NSRange(location: 0, length: ns.length)).reversed()
            for match in matches {
                guard let fullRange = Range(match.range, in: working) else { continue }
                let tableHTML = String(working[fullRange])
                tables.insert(tableHTML, at: 0)
                let placeholder = "\n\n[[TABLE_\(tables.count - 1)]]\n\n"
                working.replaceSubrange(fullRange, with: placeholder)
            }
        }

        // 2) 图片
        if let imgRe = try? NSRegularExpression(pattern: #"<img\b[^>]*>"#, options: .caseInsensitive) {
            let ns = working as NSString
            let matches = imgRe.matches(in: working, range: NSRange(location: 0, length: ns.length)).reversed()
            for match in matches {
                guard let fullRange = Range(match.range, in: working) else { continue }
                let tag = String(working[fullRange])
                images.insert(tag, at: 0)
                let placeholder = "\n\n[[IMG_\(images.count - 1)]]\n\n"
                working.replaceSubrange(fullRange, with: placeholder)
            }
        }

        // 去掉其余标签，保留占位符与段落结构
        working = working.replacingOccurrences(of: "<![CDATA[", with: "")
        working = working.replacingOccurrences(of: "]]>", with: "")
        working = working.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: .regularExpression)
        working = working.replacingOccurrences(of: #"</p>|</div>|</li>|</h[1-6]>"#, with: "\n\n", options: .regularExpression)
        working = working.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        working = decodeEntities(working)
        return (
            working.trimmingCharacters(in: .whitespacesAndNewlines),
            images,
            tables
        )
    }

    /// 将翻译结果中的 [[IMG_n]] / [[TABLE_n]] 还原为原始标签
    static func restoreImagesAfterTranslation(_ text: String, images: [String]) -> String {
        restoreMediaAfterTranslation(text, images: images, tables: [])
    }

    static func restoreMediaAfterTranslation(_ text: String, images: [String], tables: [String]) -> String {
        var result = text
        for (i, tag) in tables.enumerated() {
            let patterns = [
                "[[TABLE_\(i)]]",
                "【TABLE_\(i)】",
                "[TABLE_\(i)]",
                "TABLE_\(i)"
            ]
            for p in patterns {
                if result.contains(p) {
                    result = result.replacingOccurrences(of: p, with: "\n\n\(tag)\n\n")
                    break
                }
            }
        }
        for (i, tag) in images.enumerated() {
            let patterns = [
                "[[IMG_\(i)]]",
                "【IMG_\(i)】",
                "[IMG_\(i)]",
                "IMG_\(i)"
            ]
            for p in patterns {
                if result.contains(p) {
                    result = result.replacingOccurrences(of: p, with: "\n\n\(tag)\n\n")
                    break
                }
            }
        }
        return result
    }
}


// MARK: - 译文润色（参考 Readest polish）

enum TranslationPolish {
    /// 按目标语言做轻量标点/空白整理，不改语义
    static func polish(_ text: String, targetLang: AppLanguage) -> String {
        var s = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // 标点前多余空格
        s = s.replacingOccurrences(of: #"\s+([.,!?;:])"#, with: "$1", options: .regularExpression)
        switch targetLang {
        case .zhHans, .zhHant:
            s = s.replacingOccurrences(of: "--", with: "⸺")
            s = s.replacingOccurrences(of: #"\s+([。、！？；：，])"#, with: "$1", options: .regularExpression)
            s = s.replacingOccurrences(of: #"([。、！？；：，])\s+"#, with: "$1", options: .regularExpression)
        case .ja:
            s = s.replacingOccurrences(of: #"\s+([。、！？])"#, with: "$1", options: .regularExpression)
            s = s.replacingOccurrences(of: #"([。、！？])\s+"#, with: "$1", options: .regularExpression)
        case .fr:
            s = s.replacingOccurrences(of: #"\s+([!?:;])"#, with: " $1", options: .regularExpression)
        default:
            break
        }
        return s
    }
}

// MARK: - 翻译结果缓存（参考 Readest：provider + 语言 + 原文）

enum TranslationCache {
    private static let memory = NSCache<NSString, NSString>()
    private static let fileName = "translation_cache_v1.json"
    private static var disk: [String: String] = loadDisk()
    private static let lock = NSLock()
    private static let maxDiskEntries = 4000

    private static func key(text: String, target: String, provider: String) -> String {
        // 原文过长只取指纹，避免 key 爆炸
        let body: String
        if text.count <= 240 {
            body = text
        } else {
            body = "\(text.count):\(text.prefix(80))…\(text.suffix(40))"
        }
        return "\(provider)|\(target)|\(body)"
    }

    static func get(text: String, targetLang: AppLanguage, provider: String) -> String? {
        let k = key(text: text, target: targetLang.rawValue, provider: provider)
        if let m = memory.object(forKey: k as NSString) as String? {
            return m
        }
        lock.lock()
        let v = disk[k]
        lock.unlock()
        if let v {
            memory.setObject(v as NSString, forKey: k as NSString)
        }
        return v
    }

    static func set(_ translation: String, text: String, targetLang: AppLanguage, provider: String) {
        let trimmed = translation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !trimmed.isEmpty else { return }
        let k = key(text: text, target: targetLang.rawValue, provider: provider)
        memory.setObject(trimmed as NSString, forKey: k as NSString)
        lock.lock()
        disk[k] = trimmed
        if disk.count > maxDiskEntries {
            // 粗暴裁半：JSON 无序，足够用
            let drop = disk.count - maxDiskEntries / 2
            for key in disk.keys.prefix(drop) {
                disk.removeValue(forKey: key)
            }
        }
        let snapshot = disk
        lock.unlock()
        saveDisk(snapshot)
    }

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return dir.appendingPathComponent(fileName)
    }

    private static func loadDisk() -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL),
              let obj = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return obj
    }

    private static func saveDisk(_ map: [String: String]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func clear() {
        memory.removeAllObjects()
        lock.lock()
        disk.removeAll()
        lock.unlock()
        try? FileManager.default.removeItem(at: fileURL)
    }
}

// MARK: - Yandex（免 Key，网页 API，参考 Readest）

enum YandexTranslate {
    private static let sessionURL = URL(string: "https://translate.yandex.ru/props/api/v1.0/sessions")!
    private static let translateURL = URL(string: "https://translate.yandex.net/api/v1/tr.json/translate")!
    private static let origin = "https://translate.yandex.ru"
    private static let ua =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
    private static let maxChars = 600
    private static let gate = AsyncGate(limit: 3)

    private static var sid: String?
    private static var sidExpires: Date = .distantPast
    private static let lock = NSLock()

    static func translate(text: String, targetLang: String = "zh") async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let tl = normalizeLang(targetLang)
        let chunks = chunk(trimmed, max: maxChars)
        var parts: [String] = []
        parts.reserveCapacity(chunks.count)
        for c in chunks {
            let p = try await gate.run {
                try await translateChunk(c, targetLang: tl, retry: true)
            }
            parts.append(p)
        }
        return parts.joined()
    }

    private static func normalizeLang(_ lang: String) -> String {
        let l = lang.lowercased()
        if l.hasPrefix("zh") { return "zh" }
        if l.hasPrefix("en") { return "en" }
        if l.hasPrefix("ja") { return "ja" }
        if l.hasPrefix("ko") { return "ko" }
        if l.hasPrefix("fr") { return "fr" }
        if l.hasPrefix("de") { return "de" }
        if l.hasPrefix("es") { return "es" }
        return String(l.prefix(2))
    }

    private static func chunk(_ text: String, max: Int) -> [String] {
        guard text.count > max else { return [text] }
        var out: [String] = []
        var start = text.startIndex
        while start < text.endIndex {
            let end = text.index(start, offsetBy: max, limitedBy: text.endIndex) ?? text.endIndex
            out.append(String(text[start..<end]))
            start = end
        }
        return out
    }

    private static func translateChunk(_ text: String, targetLang: String, retry: Bool) async throws -> String {
        let sid = try await getSID()
        var comps = URLComponents(url: translateURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "srv", value: "tr-text"),
            URLQueryItem(name: "sid", value: "\(sid)-5-0"),
            URLQueryItem(name: "target_lang", value: targetLang),
            URLQueryItem(name: "reason", value: "paste"),
            URLQueryItem(name: "format", value: "text"),
            URLQueryItem(name: "strategy", value: "0"),
            URLQueryItem(name: "disable_cache", value: "false"),
            URLQueryItem(name: "ajax", value: "1"),
        ]
        guard let url = comps.url else { throw TranslationError.apiError("Yandex URL 无效") }
        var req = URLRequest(url: url, timeoutInterval: 18)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        req.setValue(origin, forHTTPHeaderField: "Origin")
        req.setValue(origin + "/", forHTTPHeaderField: "Referer")
        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "options", value: "0"),
            URLQueryItem(name: "text", value: text),
        ]
        req.httpBody = body.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await TranslationHTTP.session.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            if (http.statusCode == 401 || http.statusCode == 403), retry {
                invalidateSID()
                return try await translateChunk(text, targetLang: targetLang, retry: false)
            }
            throw TranslationError.apiError("Yandex 错误 \(http.statusCode)")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TranslationError.apiError("Yandex 响应无效")
        }
        let code = json["code"] as? Int
        if code == 401 || code == 403, retry {
            invalidateSID()
            return try await translateChunk(text, targetLang: targetLang, retry: false)
        }
        if let arr = json["text"] as? [String] {
            return arr.joined()
        }
        throw TranslationError.apiError("Yandex 无译文")
    }

    private static func getSID() async throws -> String {
        lock.lock()
        if let sid, sidExpires > Date() {
            lock.unlock()
            return sid
        }
        lock.unlock()

        var comps = URLComponents(url: sessionURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "srv", value: "tr-text"),
            URLQueryItem(name: "yu", value: String(Int.random(in: 1_000_000_000_000...9_999_999_999_999_999))),
            URLQueryItem(name: "yum", value: String(Int(Date().timeIntervalSince1970 * 1_000_000))),
        ]
        guard let url = comps.url else { throw TranslationError.apiError("Yandex session URL 无效") }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        req.setValue(origin, forHTTPHeaderField: "Origin")
        req.setValue(origin + "/", forHTTPHeaderField: "Referer")

        let (data, response) = try await TranslationHTTP.session.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw TranslationError.apiError("Yandex session \(http.statusCode)")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let session = json["session"] as? [String: Any],
              let id = session["id"] as? String, !id.isEmpty else {
            throw TranslationError.apiError("Yandex session 解析失败")
        }
        let created = (session["creationTimestamp"] as? Double) ?? Date().timeIntervalSince1970
        let maxAge = (session["maxAge"] as? Double) ?? 3600
        lock.lock()
        sid = id
        sidExpires = Date(timeIntervalSince1970: created + maxAge - 60)
        lock.unlock()
        return id
    }

    private static func invalidateSID() {
        lock.lock()
        sid = nil
        sidExpires = .distantPast
        lock.unlock()
    }
}

// MARK: - Azure/Bing（免 Key，Bing Translator 网页接口，参考 Readest）

enum AzureBingTranslate {
    private static let pageURL = URL(string: "https://www.bing.com/translator")!
    private static let translatePath = "/ttranslatev3"
    private static let ua =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
    private static let maxChars = 1000
    private static let gate = AsyncGate(limit: 6)

    private struct Auth {
        var ig: String
        var iid: String
        var key: String
        var token: String
        var expiresAt: Date
        var host: String
    }

    private static var cached: Auth?
    private static let lock = NSLock()

    static func translate(text: String, targetLang: String = "zh-Hans") async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let tl = normalizeLang(targetLang)
        let chunks = chunk(trimmed, max: maxChars)
        var parts: [String] = []
        for c in chunks {
            let p = try await gate.run {
                try await translateChunk(c, to: tl, retry: true)
            }
            parts.append(p)
        }
        return parts.joined()
    }

    private static func normalizeLang(_ lang: String) -> String {
        let l = lang.trimmingCharacters(in: .whitespacesAndNewlines)
        switch l.lowercased() {
        case "zh", "zh-cn", "zh-hans": return "zh-Hans"
        case "zh-tw", "zh-hk", "zh-hant": return "zh-Hant"
        case "en", "en-us", "en-gb": return "en"
        case "ja", "ja-jp": return "ja"
        case "ko", "ko-kr": return "ko"
        case "fr", "fr-fr": return "fr"
        case "de", "de-de": return "de"
        case "es", "es-es": return "es"
        default:
            // Bing 拒 en-US 这类 culture，尽量取主语言
            if let dash = l.firstIndex(of: "-") {
                return String(l[..<dash])
            }
            return l
        }
    }

    private static func chunk(_ text: String, max: Int) -> [String] {
        guard text.count > max else { return [text] }
        var out: [String] = []
        var start = text.startIndex
        while start < text.endIndex {
            let end = text.index(start, offsetBy: max, limitedBy: text.endIndex) ?? text.endIndex
            out.append(String(text[start..<end]))
            start = end
        }
        return out
    }

    private static func translateChunk(_ text: String, to: String, retry: Bool) async throws -> String {
        let auth = try await getAuth()
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = auth.host
        comps.path = translatePath
        comps.queryItems = [
            URLQueryItem(name: "isVertical", value: "1"),
            URLQueryItem(name: "IG", value: auth.ig),
            URLQueryItem(name: "IID", value: auth.iid),
        ]
        guard let url = comps.url else { throw TranslationError.apiError("Bing URL 无效") }
        var req = URLRequest(url: url, timeoutInterval: 18)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        req.setValue("https://www.bing.com/translator", forHTTPHeaderField: "Referer")
        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "fromLang", value: "auto-detect"),
            URLQueryItem(name: "text", value: text),
            URLQueryItem(name: "to", value: to),
            URLQueryItem(name: "token", value: auth.token),
            URLQueryItem(name: "key", value: auth.key),
        ]
        req.httpBody = body.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await TranslationHTTP.session.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            if retry {
                invalidateAuth()
                return try await translateChunk(text, to: to, retry: false)
            }
            throw TranslationError.apiError("Bing 错误 \(http.statusCode)")
        }
        // statusCode 可能嵌在 JSON 里（如 205 过期）
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let code = obj["statusCode"] as? Int, code != 200 {
            if code == 205, retry {
                invalidateAuth()
                return try await translateChunk(text, to: to, retry: false)
            }
            throw TranslationError.apiError("Bing status \(code)")
        }
        if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
           let first = arr.first,
           let translations = first["translations"] as? [[String: Any]],
           let t = translations.first?["text"] as? String {
            return t
        }
        throw TranslationError.apiError("Bing 响应无效")
    }

    private static func getAuth() async throws -> Auth {
        lock.lock()
        if let cached, cached.expiresAt > Date() {
            lock.unlock()
            return cached
        }
        lock.unlock()

        var req = URLRequest(url: pageURL, timeoutInterval: 20)
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        req.setValue("text/html", forHTTPHeaderField: "Accept")
        let (data, response) = try await TranslationHTTP.session.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw TranslationError.apiError("Bing 页面 \(http.statusCode)")
        }
        let html = String(data: data, encoding: .utf8) ?? ""
        let ns = html as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard let abuseRe = try? NSRegularExpression(
                pattern: #"params_AbusePreventionHelper\s*=\s*\[\s*(\d+)\s*,\s*"([^"]+)"\s*,\s*(\d+)\s*\]"#
             ),
             let abuse = abuseRe.firstMatch(in: html, range: full),
             abuse.numberOfRanges >= 4,
             let igRe = try? NSRegularExpression(pattern: #"IG\s*:\s*"([A-Fa-f0-9]+)""#),
             let igM = igRe.firstMatch(in: html, range: full),
             igM.numberOfRanges >= 2,
             let iidRe = try? NSRegularExpression(pattern: #"data-iid\s*=\s*"([^"]+)""#),
             let iidM = iidRe.firstMatch(in: html, range: full),
             iidM.numberOfRanges >= 2
        else {
            throw TranslationError.apiError("Bing 鉴权解析失败")
        }
        let key = ns.substring(with: abuse.range(at: 1))
        let token = ns.substring(with: abuse.range(at: 2))
        let ttlMs = Double(ns.substring(with: abuse.range(at: 3))) ?? 3_600_000
        let ig = ns.substring(with: igM.range(at: 1))
        let iid = ns.substring(with: iidM.range(at: 1))
        var host = "www.bing.com"
        if let http = response as? HTTPURLResponse,
           let final = http.url?.host,
           final.hasSuffix("bing.com") {
            host = final
        }
        let auth = Auth(
            ig: ig,
            iid: iid,
            key: key,
            token: token,
            expiresAt: Date().addingTimeInterval(max(ttlMs - 60_000, 0) / 1000.0),
            host: host
        )
        lock.lock()
        cached = auth
        lock.unlock()
        return auth
    }

    private static func invalidateAuth() {
        lock.lock()
        cached = nil
        lock.unlock()
    }
}

/// 跨引擎共享的简单并发闸
actor AsyncGate {
    private let limit: Int
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    init(limit: Int) { self.limit = max(1, limit) }
    func run<T: Sendable>(_ work: @Sendable () async throws -> T) async throws -> T {
        await acquire()
        do {
            let v = try await work()
            release()
            return v
        } catch {
            release()
            throw error
        }
    }
    private func acquire() async {
        if active < limit {
            active += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }
    private func release() {
        if !waiters.isEmpty {
            waiters.removeFirst().resume()
        } else {
            active = max(0, active - 1)
        }
    }
}
