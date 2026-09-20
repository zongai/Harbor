import SwiftUI

struct TranslationSettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var microsoftKeys: [String] = []
    @State private var newMicrosoftKey = ""
    @State private var deeplKeys: [String] = []
    @State private var newDeepLKey = ""
    @State private var testingEngine: TranslationEngine?
    @State private var testMessage: String?
    @State private var testIsError = false
    /// 各引擎 Key 行旁的可用性：index -> true/false
    @State private var microsoftKeyOK: [Int: Bool] = [:]
    @State private var deeplKeyOK: [Int: Bool] = [:]

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                Picker("翻译目标语言", selection: $store.targetLanguage) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                Picker("AI 输出语言", selection: $store.aiOutputLanguage) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
            } header: {
                Text("语言")
            } footer: {
                Text("翻译引擎将内容译为「翻译目标语言」；摘要/解释使用「AI 输出语言」。目标为简体/繁体时，若正文是另一侧中文，会自动做繁简转换（不跳过）。")
            }

            Section {
                ForEach(store.translationEngineChain, id: \.self) { engine in
                    HStack(spacing: 10) {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(engine.rawValue)
                            if !store.isTranslationEngineReady(engine) {
                                Text("未配置 Key，将自动跳过")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                        Spacer()
                        if store.translationEngineChain.count > 1 {
                            Button(role: .destructive) {
                                store.toggleTranslationEngineInChain(engine)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("从列表移除")
                        }
                    }
                }
                .onMove { source, dest in
                    store.moveTranslationEngine(from: source, to: dest)
                }
                Menu {
                    ForEach(TranslationEngine.allCases, id: \.self) { engine in
                        if !store.translationEngineChain.contains(engine) {
                            Button(engine.rawValue) {
                                store.toggleTranslationEngineInChain(engine)
                            }
                        }
                    }
                } label: {
                    Label("添加引擎", systemImage: "plus")
                }
            } header: {
                Text("翻译引擎顺序")
            } footer: {
                Text("按列表从上到下使用。遇限流自动切换下一个；未配置 Key 的引擎会跳过。可拖动排序。")
            }

            Section {
                Picker("并发度", selection: $store.translationConcurrency) {
                    Text("自动（推荐）").tag(0)
                    ForEach(1...8, id: \.self) { n in
                        Text("\(n) 路").tag(n)
                    }
                }
            } header: {
                Text("并发")
            } footer: {
                Text("同时请求数。自动：Google 3、MyMemory 4、AI 4。遇 429 请降到 1～2 或换引擎。")
            }


            // Google
            Section {
                engineHeader("Google 翻译", selected: store.translationEngineChain.first == .google)
                testButton(for: .google)
            } header: { Text("Google（免 Key）") }
            footer: { Text("使用免费接口 client=gtx，无需 API Key。并发固定为串行，降低 429 限流。") }


            // Microsoft
            Section {
                engineHeader("Microsoft 翻译", selected: store.translationEngineChain.first == .microsoft)
                ForEach(Array(microsoftKeys.enumerated()), id: \.offset) { idx, key in
                    HStack {
                        Text(maskSecret(key)).font(.system(.body, design: .monospaced))
                        keyStatusBadge(microsoftKeyOK[idx])
                        Spacer()
                        Button(role: .destructive) {
                            microsoftKeys.remove(at: idx)
                            store.saveMicrosoftKeys(microsoftKeys)
                            microsoftKeyOK.removeValue(forKey: idx)
                        } label: { Image(systemName: "trash") }
                    }
                }
                HStack {
                    TextField("添加 Microsoft API Key", text: $newMicrosoftKey)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button("添加") {
                        let k = newMicrosoftKey.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !k.isEmpty else { return }
                        microsoftKeys.append(k)
                        store.saveMicrosoftKeys(microsoftKeys)
                        newMicrosoftKey = ""
                    }
                }
                TextField("资源区域（如 eastasia / eastus / global）", text: $store.microsoftTranslateRegion)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                testButton(for: .microsoft)
            } header: { Text("Microsoft（多 Key）") }
            footer: { Text("多 Key 自动轮询；无效/限流 Key 自动跳过。区域需与 Azure 资源位置一致。") }

            // DeepL
            Section {
                engineHeader("DeepL", selected: store.translationEngineChain.first == .deepl)
                ForEach(Array(deeplKeys.enumerated()), id: \.offset) { idx, key in
                    HStack {
                        Text(maskSecret(key)).font(.system(.body, design: .monospaced))
                        keyStatusBadge(deeplKeyOK[idx])
                        Spacer()
                        Button(role: .destructive) {
                            deeplKeys.remove(at: idx)
                            store.saveDeepLKeys(deeplKeys)
                            deeplKeyOK.removeValue(forKey: idx)
                        } label: { Image(systemName: "trash") }
                    }
                }
                HStack {
                    TextField("添加 DeepL Key", text: $newDeepLKey)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button("添加") {
                        let k = newDeepLKey.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !k.isEmpty else { return }
                        deeplKeys.append(k)
                        store.saveDeepLKeys(deeplKeys)
                        newDeepLKey = ""
                    }
                }
                testButton(for: .deepl)
            } header: { Text("DeepL（多 Key）") }
            footer: { Text("多 Key 自动轮询；无效 Key 跳过约 1 小时，限流 Key 跳过约 5 分钟；全部失败回退 Google。") }

            // MyMemory
            Section {
                engineHeader("MyMemory（免 Key）", selected: store.translationEngineChain.first == .mymemory)
                testButton(for: .mymemory)
            } header: { Text("MyMemory") }
            footer: { Text("按 IP 有日配额；限流时请换引擎或稍后再试。") }

            // Lingva
            Section {
                engineHeader("Lingva（免 Key）", selected: store.translationEngineChain.first == .lingva)
                TextField("自定义实例 URL（可选）", text: $store.lingvaCustomBase)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                testButton(for: .lingva)
            } header: { Text("Lingva") }
            footer: { Text("公共实例：lingva.ml / plausibility.cloud / lunar.icu / projectsegfau.lt / garudalinux.org。也可填自定义实例。") }


            // AI
            Section {
                engineHeader("AI 翻译", selected: store.translationEngineChain.first == .ai)
                Text("在「AI 设置」中配置 Provider 与 Key，可对单个 Provider 左滑测试。")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                testButton(for: .ai)
            } header: { Text("AI 翻译") }

            if let testMessage {
                Section {
                    Text(testMessage)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(testIsError ? .red : .primary)
                        .textSelection(.enabled)
                } header: { Text("测试结果（含 Key 可用性）") }
            }
        }
        .navigationTitle("翻译设置")
        .navigationBarTitleDisplayMode(.inline)
        .appFormChrome()
        .onDisappear { store.persistSettings() }
        .onChange(of: store.translationConcurrency) { _, _ in store.persistSettings() }
        .environment(\.editMode, .constant(.active))
        .onChange(of: store.microsoftTranslateRegion) { _, _ in store.persistSettings() }
        .onChange(of: store.lingvaCustomBase) { _, _ in store.persistSettings() }
        .onAppear {
            microsoftKeys = store.loadMicrosoftKeys()
            deeplKeys = store.loadDeepLKeys()
        }
        .onChange(of: store.targetLanguage) { _, _ in store.persistSettings() }
        .onChange(of: store.aiOutputLanguage) { _, _ in store.persistSettings() }
    }

    private func maskSecret(_ key: String) -> String {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard k.count > 8 else { return String(repeating: "•", count: max(4, k.count)) }
        return String(k.prefix(3)) + "…" + String(k.suffix(4))
    }

    @ViewBuilder
    private func keyStatusBadge(_ ok: Bool?) -> some View {
        if let ok {
            Text(ok ? "可用" : "不可用")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ok ? Color.green : Color.red)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background((ok ? Color.green : Color.red).opacity(0.12))
                .clipShape(Capsule())
        }
    }

    @ViewBuilder
    private func engineHeader(_ title: String, selected: Bool) -> some View {
        HStack {
            Text(title).font(.system(size: 15, weight: .medium))
            Spacer()
            if selected {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.primary)
            }
        }
    }

    private func testButton(for engine: TranslationEngine) -> some View {
        Button {
            Task { await runTest(engine) }
        } label: {
            HStack {
                if testingEngine == engine {
                    ProgressView().scaleEffect(0.85)
                    Text("测试中…")
                } else {
                    Label("测试此引擎", systemImage: "network")
                }
                Spacer()
            }
        }
        .disabled(testingEngine != nil)
    }

    @MainActor
    private func runTest(_ engine: TranslationEngine) async {
        testingEngine = engine
        testMessage = nil
        testIsError = false
        defer { testingEngine = nil }
        store.saveMicrosoftKeys(microsoftKeys)
        store.saveDeepLKeys(deeplKeys)
        store.persistSettings()

        switch engine {
        case .google:
            do {
                let msg = try await store.testTranslationEngine(.google)
                testMessage = msg
                testIsError = false
            } catch {
                testMessage = error.localizedDescription
                testIsError = true
            }
            return
        case .microsoft:
            microsoftKeyOK = [:]
            guard !microsoftKeys.isEmpty else {
                testMessage = "Microsoft：未配置 API Key"
                testIsError = true
                return
            }
            var okCount = 0
            for (i, key) in microsoftKeys.enumerated() {
                let ok = await store.probeMicrosoftKey(key)
                microsoftKeyOK[i] = ok
                if ok { okCount += 1 }
            }
            testMessage = "Microsoft：\(okCount)/\(microsoftKeys.count) 个 Key 可用"
            testIsError = okCount == 0
            return
        case .deepl:
            deeplKeyOK = [:]
            guard !deeplKeys.isEmpty else {
                testMessage = "DeepL：未配置 API Key"
                testIsError = true
                return
            }
            var okCount = 0
            for (i, key) in deeplKeys.enumerated() {
                let ok = await store.probeDeepLKey(key)
                deeplKeyOK[i] = ok
                if ok { okCount += 1 }
            }
            testMessage = "DeepL：\(okCount)/\(deeplKeys.count) 个 Key 可用"
            testIsError = okCount == 0
            return
        default:
            break
        }

        do {
            let msg = try await store.testTranslationEngine(engine)
            testMessage = msg
            testIsError = false
        } catch {
            testMessage = error.localizedDescription
            testIsError = true
        }
    }
}


// MARK: - 文章黑名单（与 AI 黑名单独立）

struct ArticleBlacklistSettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var newTerm = ""
    @State private var appliedCount: Int?

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                if store.articleBlacklistTerms.isEmpty {
                    Text("暂无关键词").foregroundStyle(.secondary)
                } else {
                    ForEach(Array(store.articleBlacklistTerms.enumerated()), id: \.offset) { index, term in
                        HStack {
                            Text(term)
                            Spacer()
                            Button {
                                store.articleBlacklistTerms.remove(at: index)
                                store.persistSettings()
                            } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                HStack {
                    TextField("关键词，如广告、招聘", text: $newTerm)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { addTerm() }
                    Button("添加") { addTerm() }
                        .disabled(newTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } header: {
                Text("关键词")
            } footer: {
                Text("标题或摘要包含任一关键词时，自动标为已读并按未读规则隐藏。与 AI 黑名单互不影响，不区分大小写。")
            }

            if !store.articleBlacklistTerms.isEmpty {
                Section {
                    Button("立即应用到已有文章") {
                        let n = store.applyArticleBlacklist()
                        appliedCount = n
                    }
                    if let appliedCount {
                        Text(appliedCount == 0 ? "没有新的命中条目" : "已将 \(appliedCount) 篇标为已读")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("文章黑名单")
        .navigationBarTitleDisplayMode(.inline)
        .appFormChrome()
    }

    private func addTerm() {
        let term = newTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        let exists = store.articleBlacklistTerms.contains { $0.caseInsensitiveCompare(term) == .orderedSame }
        guard !exists else { newTerm = ""; return }
        store.articleBlacklistTerms.append(term)
        store.persistSettings()
        newTerm = ""
        appliedCount = store.applyArticleBlacklist()
    }
}


import UniformTypeIdentifiers

struct SettingsExportPicker: UIViewControllerRepresentable {
    let url: URL
    var onDismiss: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onDismiss: onDismiss) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onDismiss: () -> Void
        init(onDismiss: @escaping () -> Void) { self.onDismiss = onDismiss }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { onDismiss() }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { onDismiss() }
    }
}

struct SettingsImportPicker: UIViewControllerRepresentable {
    var onPick: (URL?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json, .data], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL?) -> Void
        init(onPick: @escaping (URL?) -> Void) { self.onPick = onPick }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { onPick(nil) }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls.first)
        }
    }
}
