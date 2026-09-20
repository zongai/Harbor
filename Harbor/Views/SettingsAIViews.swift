import SwiftUI

struct AISettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var showAddProvider = false
    @State private var editingProvider: AIProvider?
    @State private var testingProviderID: UUID?
    @State private var providerTestResults: [UUID: String] = [:]

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                ForEach(store.aiProviders) { provider in
                    Button {
                        editingProvider = provider
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            AIProviderRow(provider: provider)
                            if testingProviderID == provider.id {
                                HStack(spacing: 6) {
                                    ProgressView().scaleEffect(0.75)
                                    Text("测试中…").font(.caption).foregroundStyle(.secondary)
                                }
                            } else if let result = providerTestResults[provider.id] {
                                Text(result)
                                    .font(.caption)
                                    .foregroundStyle(result.hasPrefix("失败") ? .red : .secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("编辑 Provider")
                        .swipeActions(edge: .leading) {
                            Button {
                                Task { await testProvider(provider) }
                            } label: {
                                Label("测试", systemImage: "network")
                            }
                            .tint(.blue)
                            .disabled(testingProviderID != nil)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                store.aiProviders.removeAll(where: { $0.id == provider.id })
                                if store.aiBlacklistFallbackProviderID == provider.id {
                                    store.aiBlacklistFallbackProviderID = nil
                                }
                                if store.defaultExplainProviderID == provider.id {
                                    store.defaultExplainProviderID = nil
                                }
                                if store.defaultSummaryProviderID == provider.id {
                                    store.defaultSummaryProviderID = store.aiProviders.first?.id
                                }
                                if store.defaultTranslationProviderID == provider.id {
                                    store.defaultTranslationProviderID = store.aiProviders.first?.id
                                }
                                store.persistSettings()
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                }
                Button { showAddProvider = true } label: {
                    Label("添加 Provider", systemImage: "plus")
                }
            } header: {
                Text("AI Provider")
            } footer: {
                Text("左滑可测试该 Provider。Gemini、OpenAI、Anthropic 等统一管理；Gemini 走专用接口。")
            }

            Section {
                Picker("默认解释引擎", selection: Binding(
                    get: { store.defaultExplainProviderID },
                    set: { store.defaultExplainProviderID = $0; store.persistSettings() }
                )) {
                    Text("跟随摘要引擎").tag(Optional<UUID>.none)
                    ForEach(store.aiProviders) { p in
                        Text(p.name).tag(Optional(p.id))
                    }
                }
            } header: {
                Text("AI 解释")
            } footer: {
                Text("框选文章文字后的「AI解释」使用此 Provider。选「跟随摘要引擎」时与摘要共用。")
            }

            Section {
                NavigationLink {
                    AIBlacklistSettingsView()
                } label: {
                    HStack {
                        Text("AI 黑名单")
                        Spacer()
                        if !store.aiBlacklistTerms.isEmpty {
                            Text("\(store.aiBlacklistTerms.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                Text("配置翻译 / 摘要 / 解释命中关键词时使用的备用 Provider。")
            }

            Section {
                TextEditor(text: $store.translationPrompt)
                    .font(.system(size: 14, design: .monospaced))
                    .frame(minHeight: 110)
                Button("恢复默认翻译 Prompt") {
                    store.translationPrompt = AppStore.defaultTranslationPrompt
                    store.persistSettings()
                }
            } header: {
                Text("翻译 Prompt")
            } footer: {
                Text("仅「AI 翻译」引擎使用。{{text}} 为待译内容，{{lang}} 为目标语言名称。")
            }

            Section {
                Picker("全局摘要模板", selection: $store.globalSummaryPresetID) {
                    ForEach(store.summaryPromptPresets) { p in
                        Text(p.name).tag(p.id)
                    }
                }
                NavigationLink {
                    SummaryPromptPresetsView()
                } label: {
                    Label("管理 Prompt 预设…", systemImage: "list.bullet.rectangle")
                }
            } header: {
                Text("摘要 Prompt 预设")
            } footer: {
                Text("按类型优化的模板（科技/学术/投资/新闻/评测等），可编辑或添加自定义类型。各订阅源可在长按菜单单独指定。占位符：{{title}} {{content}} {{lang}}。")
            }

            Section {
                TextEditor(text: $store.explainPrompt)
                    .font(.system(size: 14, design: .monospaced))
                    .frame(minHeight: 110)
                Button("恢复默认解释 Prompt") {
                    store.explainPrompt = AppStore.defaultExplainPrompt
                    store.persistSettings()
                }
            } header: {
                Text("解释 Prompt")
            } footer: {
                Text("{{text}} 为选中内容；{{lang}} 为 AI 输出语言。")
            }

            Section {
                Toggle("智能兴趣过滤", isOn: $store.smartInterestFilterEnabled)
                if store.smartInterestFilterEnabled {
                    Toggle("低分自动标已读", isOn: $store.autoMarkLowInterestRead)
                    Toggle("列表按兴趣排序", isOn: $store.sortByInterestScore)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("低分阈值 \(String(format: "%.2f", store.lowInterestThreshold))")
                            .font(.subheadline)
                        Slider(value: $store.lowInterestThreshold, in: 0.1...0.7, step: 0.05)
                    }
                    Button("清空兴趣画像") {
                        store.interestWeights = [:]
                        store.persistSettings()
                    }
                    .foregroundStyle(.red)
                }
            } header: {
                Text("兴趣与过滤")
            } footer: {
                Text("根据收藏与「不感兴趣」学习词权重，给文章打分。低分可沉底或自动已读。无需额外 API 费用。")
            }

            Section {
                Toggle("模型费用路由", isOn: $store.modelRoutingEnabled)
                if store.modelRoutingEnabled {
                    Stepper(value: $store.modelRoutingShortLimit, in: 200...3000, step: 100) {
                        Text("短文本阈值 \(store.modelRoutingShortLimit) 字")
                    }
                }
            } header: {
                Text("费用与模型路由")
            } footer: {
                Text("开启后：短文本用 Provider 的「经济模型」，长文摘要与解释用默认强模型。请在编辑 Provider 中填写经济模型 ID。")
            }
        }
        .navigationTitle("AI 设置")
        .navigationBarTitleDisplayMode(.inline)
        .appFormChrome()
        .onDisappear { store.persistSettings() }
        .onChange(of: store.translationPrompt) { _, _ in store.persistSettings() }
        .onChange(of: store.summaryPrompt) { _, _ in store.persistSettings() }
        .onChange(of: store.explainPrompt) { _, _ in store.persistSettings() }
        .onChange(of: store.globalSummaryPresetID) { _, _ in store.persistSettings() }
        .onChange(of: store.smartInterestFilterEnabled) { _, _ in store.persistSettings() }
        .onChange(of: store.autoMarkLowInterestRead) { _, _ in store.persistSettings() }
        .onChange(of: store.sortByInterestScore) { _, _ in store.persistSettings() }
        .onChange(of: store.lowInterestThreshold) { _, _ in store.persistSettings() }
        .onChange(of: store.modelRoutingEnabled) { _, _ in store.persistSettings() }
        .onChange(of: store.modelRoutingShortLimit) { _, _ in store.persistSettings() }
        .sheet(isPresented: $showAddProvider) { EditProviderView(provider: nil) }
        .sheet(item: $editingProvider) { provider in EditProviderView(provider: provider) }
    }

    private func testProvider(_ provider: AIProvider) async {
        testingProviderID = provider.id
        providerTestResults[provider.id] = nil
        do {
            let result = try await store.testAIProvider(provider.id)
            providerTestResults[provider.id] = result
        } catch {
            providerTestResults[provider.id] = "失败：\(error.localizedDescription)"
        }
        testingProviderID = nil
    }
}

// MARK: - AI 黑名单（三级：设置 → AI 设置 → AI 黑名单）

struct AIBlacklistSettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var newTerm = ""

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                if store.aiBlacklistTerms.isEmpty {
                    Text("暂无关键词").foregroundStyle(.secondary)
                } else {
                    ForEach(Array(store.aiBlacklistTerms.enumerated()), id: \.offset) { index, term in
                        HStack {
                            Text(term).font(.system(size: 15))
                            Spacer()
                            Button {
                                store.aiBlacklistTerms.remove(at: index)
                                store.persistSettings()
                            } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                HStack {
                    TextField("添加关键词，如敏感词", text: $newTerm)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { addTerm() }
                    Button("添加") { addTerm() }
                        .disabled(newTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } header: {
                Text("关键词")
            } footer: {
                Text("当 AI 翻译 / 摘要 / 解释 的原文包含任一关键词时，自动改用下方指定的 Provider。不区分大小写。")
            }

            Section {
                Picker("命中后使用", selection: Binding(
                    get: { store.aiBlacklistFallbackProviderID },
                    set: { store.aiBlacklistFallbackProviderID = $0; store.persistSettings() }
                )) {
                    Text("不切换（保持默认）").tag(Optional<UUID>.none)
                    ForEach(store.aiProviders) { p in
                        Text(p.name).tag(Optional(p.id))
                    }
                }
            } header: {
                Text("备用 Provider")
            }
        }
        .navigationTitle("AI 黑名单")
        .navigationBarTitleDisplayMode(.inline)
        .appFormChrome()
        .onDisappear { store.persistSettings() }
    }

    private func addTerm() {
        let term = newTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        let exists = store.aiBlacklistTerms.contains {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == term.lowercased()
        }
        if !exists {
            store.aiBlacklistTerms.append(term)
            store.persistSettings()
        }
        newTerm = ""
    }
}

struct AIProviderRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    let provider: AIProvider

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            HStack {
                Text(provider.name)
                    .font(AppTypography.label())
                    .foregroundStyle(theme.text)
                Spacer()
                HStack(spacing: AppSpacing.xs) {
                    if provider.isDefaultSummary || store.defaultSummaryProviderID == provider.id {
                        ProviderTag(text: "摘要", color: theme.accent)
                    }
                    if provider.isDefaultTranslation || store.defaultTranslationProviderID == provider.id {
                        ProviderTag(text: "翻译", color: theme.muted)
                    }
                    if store.defaultExplainProviderID == provider.id {
                        ProviderTag(text: "解释", color: .orange)
                    }
                }
            }
            let models = provider.availableModels
            if models.count > 1 {
                Text("默认 \(provider.model) · 共 \(models.count) 个模型")
                    .font(AppTypography.caption())
                    .foregroundStyle(theme.muted)
                    .lineLimit(1)
            } else {
                Text(provider.model)
                    .font(AppTypography.caption())
                    .foregroundStyle(theme.muted)
            }
            Text(provider.baseURL)
                .font(AppTypography.caption())
                .foregroundStyle(theme.muted.opacity(0.75))
                .lineLimit(1)
        }
        .padding(.vertical, AppSpacing.xxs)
    }
}

struct ProviderTag: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(AppTypography.caption())
            .fontWeight(.medium)
            .foregroundStyle(Color(.systemBackground))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color, in: Capsule())
    }
}

struct EditProviderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store
    let provider: AIProvider?

    @State private var isTesting = false
    @State private var testResult: String?
    @State private var keyOK: [Int: Bool] = [:]
    @State private var name = ""
    @State private var baseURL = ""
    @State private var model = ""
    /// 每行一个模型名
    @State private var modelsText = ""
    @State private var economyModel = ""
    @State private var apiKeys: [String] = []
    @State private var newAPIKey = ""
    @State private var kind = "openai"
    @State private var isDefaultSummary = false
    @State private var isDefaultTranslation = false
    @State private var isDefaultExplain = false

    private var isNew: Bool { provider == nil }

    private var parsedModels: [String] {
        var seen = Set<String>()
        var list: [String] = []
        for line in modelsText.components(separatedBy: .newlines) {
            let m = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !m.isEmpty, !seen.contains(m) else { continue }
            seen.insert(m)
            list.append(m)
        }
        let primary = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !primary.isEmpty && !seen.contains(primary) {
            list.insert(primary, at: 0)
        }
        return list
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Provider 模板") {
                    Button("OpenAI") { applyTemplate(.openAITemplate) }.foregroundStyle(Color.primary)
                    Button("Anthropic") { applyTemplate(.anthropicTemplate) }.foregroundStyle(Color.primary)
                    Button("Gemini") { applyTemplate(.geminiTemplate) }.foregroundStyle(Color.primary)
                }
                Section {
                    TextField("名称", text: $name)
                    TextField("Base URL", text: $baseURL)
                        .keyboardType(.URL).autocorrectionDisabled().textInputAutocapitalization(.never)
                    Picker("接口类型", selection: $kind) {
                        Text("OpenAI 兼容").tag("openai")
                        Text("Gemini").tag("gemini")
                    }
                } header: {
                    Text("基本信息")
                }
                Section {
                    TextEditor(text: $modelsText)
                        .font(.system(size: 14, design: .monospaced))
                        .frame(minHeight: 88)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    if !parsedModels.isEmpty {
                        Picker("默认模型", selection: $model) {
                            ForEach(parsedModels, id: \.self) { m in
                                Text(m).tag(m)
                            }
                        }
                    } else {
                        TextField("默认模型名", text: $model)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                } header: {
                    Text("模型（可多个）")
                } footer: {
                    Text("每行一个模型 ID。默认模型用于摘要/翻译/解释；对话页可在列表中切换同一 Provider 下的其它模型。")
                }
                Section {
                    TextField("经济模型（可选）", text: $economyModel)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    if !parsedModels.isEmpty {
                        Button("使用列表中的轻量模型") {
                            // 优先选含 mini / flash / haiku 的
                            if let lite = parsedModels.first(where: {
                                let l = $0.lowercased()
                                return l.contains("mini") || l.contains("flash") || l.contains("haiku") || l.contains("lite")
                            }) {
                                economyModel = lite
                            } else if parsedModels.count > 1 {
                                economyModel = parsedModels.last ?? ""
                            }
                        }
                    }
                } header: {
                    Text("费用路由")
                } footer: {
                    Text("开启「模型费用路由」后，短文本将使用此模型；留空则始终用默认模型。")
                }
                Section {
                    if apiKeys.isEmpty {
                        Text("尚未添加 Key").foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(apiKeys.enumerated()), id: \.offset) { index, key in
                            HStack {
                                Text(maskKey(key))
                                    .font(.system(size: 13, design: .monospaced))
                                if let ok = keyOK[index] {
                                    Text(ok ? "可用" : "不可用")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(ok ? Color.green : Color.red)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background((ok ? Color.green : Color.red).opacity(0.12))
                                        .clipShape(Capsule())
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    apiKeys.remove(at: index)
                                    keyOK.removeValue(forKey: index)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    HStack {
                        SecureField("添加 API Key", text: $newAPIKey)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        Button("添加") {
                            let k = newAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !k.isEmpty else { return }
                            if !apiKeys.contains(k) { apiKeys.append(k) }
                            newAPIKey = ""
                        }
                        .disabled(newAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } header: {
                    Text("API Key（可多个）")
                } footer: {
                    Text("可添加多个 Key：自动轮询；无效 Key 跳过约 1 小时，限流约 5 分钟。存于钥匙串。")
                }
                Section {
                    Button {
                        Task { await testCurrent() }
                    } label: {
                        HStack {
                            Label("测试此 Provider", systemImage: "network")
                            Spacer()
                            if isTesting { ProgressView() }
                        }
                    }
                    .disabled(isTesting || baseURL.isEmpty || (model.isEmpty && parsedModels.isEmpty))
                    if let testResult {
                        Text(testResult)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(testResult.contains("不可用") && !testResult.contains("可用") ? Color.red : Color.primary)
                            .textSelection(.enabled)
                    }
                } footer: {
                    Text("使用当前表单中的配置（需先保存 Key 后对新 Provider 更准确；已有 Provider 直接测已存 Key）。")
                }

                Section("默认设置") {
                    Toggle("设为默认摘要引擎", isOn: $isDefaultSummary)
                    Toggle("设为默认 AI 翻译引擎", isOn: $isDefaultTranslation)
                    Toggle("设为默认 AI 解释引擎", isOn: $isDefaultExplain)
                }
            }
            .navigationTitle(isNew ? "添加 Provider" : "编辑 Provider")
            .navigationBarTitleDisplayMode(.inline)
            .appFormChrome()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(name.isEmpty || baseURL.isEmpty || (model.isEmpty && parsedModels.isEmpty))
                }
            }
        }
        .onAppear { loadProvider() }
    }

    private func loadProvider() {
        guard let p = provider else { return }
        name = p.name
        baseURL = p.baseURL
        model = p.model
        modelsText = p.availableModels.joined(separator: "\n")
        economyModel = p.economyModel
        kind = p.kind.isEmpty ? (p.name.lowercased().contains("gemini") ? "gemini" : "openai") : p.kind
        apiKeys = store.loadAIKeys(for: p.id)
        isDefaultSummary = store.defaultSummaryProviderID == p.id
        isDefaultTranslation = store.defaultTranslationProviderID == p.id
        isDefaultExplain = store.defaultExplainProviderID == p.id
    }

    private func applyTemplate(_ template: AIProvider) {
        name = template.name
        baseURL = template.baseURL
        model = template.model
        modelsText = template.availableModels.joined(separator: "\n")
        economyModel = template.economyModel
        kind = template.kind
    }

    private func testCurrent() async {
        let id = provider?.id ?? UUID()
        store.saveAIKeys(for: id, keys: apiKeys)
        let models = parsedModels
        let active = model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (models.first ?? "")
            : model.trimmingCharacters(in: .whitespacesAndNewlines)
        let temp = AIProvider(
            id: id, name: name.isEmpty ? "Test" : name,
            baseURL: baseURL, model: active, models: models,
            economyModel: economyModel.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: kind
        )
        isTesting = true
        testResult = nil
        keyOK = [:]
        defer { isTesting = false }

        let insertedTemporarily: Bool
        if store.aiProviders.contains(where: { $0.id == id }) {
            if let idx = store.aiProviders.firstIndex(where: { $0.id == id }) {
                store.aiProviders[idx] = temp
            }
            insertedTemporarily = false
        } else {
            store.aiProviders.append(temp)
            insertedTemporarily = true
        }

        guard !apiKeys.isEmpty else {
            testResult = "未配置 API Key"
            if insertedTemporarily { store.aiProviders.removeAll { $0.id == id } }
            return
        }

        var okCount = 0
        for (i, key) in apiKeys.enumerated() {
            let ok = await store.probeAIKey(provider: temp, key: key)
            keyOK[i] = ok
            if ok { okCount += 1 }
        }
        testResult = "\(temp.name)：\(okCount)/\(apiKeys.count) 个 Key 可用"
        if insertedTemporarily {
            store.aiProviders.removeAll { $0.id == id }
        } else if let prev = provider, let idx = store.aiProviders.firstIndex(where: { $0.id == id }) {
            // 恢复原先 provider 对象（测试中可能覆盖了名称等未保存改动以外的引用）
            store.aiProviders[idx] = prev
            // 但保留用户当前表单中的 key 已 saveAIKeys
        }
    }

    private func maskKey(_ key: String) -> String {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard k.count > 8 else { return String(repeating: "•", count: max(4, k.count)) }
        return String(k.prefix(4)) + "…" + String(k.suffix(4))
    }

    private func save() {
        let id = provider?.id ?? UUID()
        let models = parsedModels
        var active = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if active.isEmpty { active = models.first ?? "" }
        let updated = AIProvider(
            id: id, name: name, baseURL: baseURL, model: active, models: models,
            economyModel: economyModel.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: kind,
            isDefaultSummary: isDefaultSummary, isDefaultTranslation: isDefaultTranslation
        )
        store.saveAIKeys(for: id, keys: apiKeys)
        if isDefaultSummary { store.defaultSummaryProviderID = id }
        if isDefaultTranslation { store.defaultTranslationProviderID = id }
        if isDefaultExplain {
            store.defaultExplainProviderID = id
        } else if store.defaultExplainProviderID == id {
            store.defaultExplainProviderID = nil
        }
        if let idx = store.aiProviders.firstIndex(where: { $0.id == id }) {
            store.aiProviders[idx] = updated
        } else {
            store.aiProviders.append(updated)
        }
        store.persistSettings()
        dismiss()
    }
}


// MARK: - Prompt 预设管理

struct SummaryPromptPresetsView: View {
    @Environment(AppStore.self) private var store
    @State private var editing: SummaryPromptPreset?
    @State private var showAdd = false

    var body: some View {
        List {
            Section {
                ForEach(store.summaryPromptPresets) { preset in
                    Button {
                        editing = preset
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(preset.name)
                                    .foregroundStyle(.primary)
                                Text(preset.isBuiltIn ? "内置" : "自定义")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if store.globalSummaryPresetID == preset.id {
                                Text("全局")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.accentColor.opacity(0.15), in: Capsule())
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if !preset.isBuiltIn {
                            Button(role: .destructive) {
                                store.deleteSummaryPreset(id: preset.id)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                        Button {
                            store.globalSummaryPresetID = preset.id
                            store.persistSettings()
                        } label: {
                            Label("设为全局", systemImage: "star")
                        }
                        .tint(.orange)
                    }
                }
            } footer: {
                Text("左滑可设为全局默认；自定义类型可删除。内置类型可改模板，也可恢复默认文案。")
            }
        }
        .navigationTitle("Prompt 预设")
        .navigationBarTitleDisplayMode(.inline)
        .appFormChrome()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("添加", systemImage: "plus") { showAdd = true }
            }
        }
        .sheet(item: $editing) { preset in
            EditSummaryPromptPresetView(preset: preset)
        }
        .sheet(isPresented: $showAdd) {
            EditSummaryPromptPresetView(preset: nil)
        }
        .onAppear { store.ensureSummaryPromptPresets() }
    }
}

struct EditSummaryPromptPresetView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let preset: SummaryPromptPreset?

    @State private var name = ""
    @State private var template = ""

    private var isNew: Bool { preset == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名称", text: $name)
                        .disabled(preset?.isBuiltIn == true)
                } header: {
                    Text("类型名称")
                } footer: {
                    if preset?.isBuiltIn == true {
                        Text("内置类型名称固定，可修改下方模板。")
                    }
                }
                Section {
                    TextEditor(text: $template)
                        .font(.system(size: 14, design: .monospaced))
                        .frame(minHeight: 220)
                } header: {
                    Text("Prompt 模板")
                } footer: {
                    Text("可用 {{title}}、{{content}}、{{lang}}。")
                }
                if let p = preset, p.isBuiltIn {
                    Section {
                        Button("恢复该类型默认模板") {
                            if let built = SummaryPromptPreset.builtInDefaults.first(where: { $0.id == p.id }) {
                                template = built.template
                            }
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "添加类型" : "编辑类型")
            .navigationBarTitleDisplayMode(.inline)
            .appFormChrome()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if let p = preset {
                    name = p.name
                    template = p.template
                } else {
                    name = ""
                    template = """
用{{lang}}总结以下内容：

标题：{{title}}

内容：{{content}}
"""
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTemplate = template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedTemplate.isEmpty else { return }
        if let p = preset {
            var updated = p
            if !p.isBuiltIn { updated.name = trimmedName }
            updated.template = trimmedTemplate
            store.upsertSummaryPreset(updated)
        } else {
            let custom = SummaryPromptPreset(
                id: UUID().uuidString,
                name: trimmedName,
                isBuiltIn: false,
                template: trimmedTemplate
            )
            store.upsertSummaryPreset(custom)
        }
        dismiss()
    }
}
