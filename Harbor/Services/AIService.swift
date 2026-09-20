import Foundation

/// AI 摘要 / 解释相关纯逻辑与多步流程编排（网络经 AIRuntime 注入）
enum AIService {
    protocol Runtime: AnyObject {
        var aiOutputLanguage: AppLanguage { get }
        var defaultSummaryProviderID: UUID? { get }
        var defaultExplainProviderID: UUID? { get }
        var modelRoutingShortLimit: Int { get }
        func resolvedSummaryPrompt(for article: Article) -> String
        func callAIWithFailover(
            preferredID: UUID?,
            probeText: String,
            maxTokens: Int,
            preferStrongModel: Bool,
            buildPrompt: () -> String
        ) async throws -> (text: String, provider: AIProvider)
    }

    static func cleanSummaryText(_ text: String) -> String {
        let patterns = [
            #"^(\d+[\.\)、:：]|[(（]\d+[)）])\s*"#,
            #"^[-•●▪◦]\s+"#
        ]
        let regexes = patterns.compactMap { try? NSRegularExpression(pattern: $0) }
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { line -> String in
                var s = line.trimmingCharacters(in: .whitespacesAndNewlines)
                for re in regexes {
                    s = re.stringByReplacingMatches(
                        in: s,
                        range: NSRange(s.startIndex..., in: s),
                        withTemplate: ""
                    )
                }
                return s.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
        return lines.joined(separator: "\n")
    }

    static func generateSummary(article: Article, runtime: Runtime) async throws -> (text: String, providerName: String) {
        let content = String(HTMLUtils.stripTags(article.content.isEmpty ? article.summary : article.content).prefix(2500))
        let probe = [article.title, article.summary, article.content]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        let template = runtime.resolvedSummaryPrompt(for: article)
        var prompt = template
            .replacingOccurrences(of: "{{lang}}", with: runtime.aiOutputLanguage.promptLabel)
            .replacingOccurrences(of: "{{title}}", with: article.title)
            .replacingOccurrences(of: "{{content}}", with: content)
        if !template.contains("{{title}}") && !template.contains("{{content}}") {
            prompt += "\n\n标题：\(article.title)\n\n内容：\(content)"
        }
        let strong = content.count > runtime.modelRoutingShortLimit
        let (raw, provider) = try await runtime.callAIWithFailover(
            preferredID: runtime.defaultSummaryProviderID,
            probeText: probe,
            maxTokens: 600,
            preferStrongModel: strong,
            buildPrompt: { prompt }
        )
        return (cleanSummaryText(raw), provider.name)
    }

    static func explainText(_ text: String, promptTemplate: String, runtime: Runtime) async throws -> String {
        let prompt = promptTemplate
            .replacingOccurrences(of: "{{lang}}", with: runtime.aiOutputLanguage.promptLabel)
            .replacingOccurrences(of: "{{text}}", with: text)
        let (raw, _) = try await runtime.callAIWithFailover(
            preferredID: runtime.defaultExplainProviderID ?? runtime.defaultSummaryProviderID,
            probeText: text,
            maxTokens: 500,
            preferStrongModel: true,
            buildPrompt: { prompt }
        )
        return cleanSummaryText(raw)
    }
}
