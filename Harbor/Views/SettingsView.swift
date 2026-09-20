import SwiftUI

struct SettingsView: View {
    @State private var showAdvancedSettings = false
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme

    private var ttsRateLabel: String {
        let r = store.ttsRate
        if abs(r - 1.0) < 0.001 { return "1.0× 正常" }
        return String(format: "%.2f×", r)
    }

    @State private var cacheSizeText: String = "计算中…"
    @State private var settingsExportURL: URL?
    @State private var showSettingsExport = false
    @State private var showSettingsImport = false
    @State private var settingsIOMessage: String?
    @State private var exportIncludeSecrets = false
    @State private var showImportConfirm = false
    @State private var pendingImportData: Data?

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                // MARK: 显示模式
                Section {
                    Toggle(isOn: $showAdvancedSettings) {
                        Label(
                            showAdvancedSettings ? "高级选项：已开启" : "显示高级选项",
                            systemImage: showAdvancedSettings ? "slider.horizontal.3" : "line.3.horizontal.decrease.circle"
                        )
                    }
                } footer: {
                    Text(showAdvancedSettings
                          ? "已显示：文章黑名单、已读保留天数、全文缓存策略、URL 前缀、设置导入导出等。"
                          : "默认只显示常用设置。打开后可管理黑名单、缓存策略与备份。")
                }

                // MARK: 阅读
                Section {
                    Picker("标题显示", selection: $store.titleDisplayMode) {
                        ForEach(TitleDisplayMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    Toggle("显示已读文章", isOn: $store.showReadArticles)
                    Picker("订阅源排序", selection: $store.feedSortMode) {
                        ForEach(FeedSortMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .onChange(of: store.feedSortMode) { _, _ in store.persistSettings() }
                } header: {
                    Text("阅读")
                } footer: {
                    Text("控制列表标题语言、已读是否出现在订阅/文章列表，以及源的排序方式。")
                }

                // MARK: 外观
                Section {
                    Picker("外观", selection: $store.appearanceMode) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: store.appearanceMode) { _, _ in store.persistSettings() }

                    NavigationLink {
                        Form {
                            ThemePalettePicker(selection: $store.colorTheme)
                                .onChange(of: store.colorTheme) { _, _ in store.persistSettings() }
                        }
                        .navigationTitle("阅读主题")
                        .navigationBarTitleDisplayMode(.inline)
                        .appScreenBackground()
                    } label: {
                        HStack {
                            Text("阅读主题")
                            Spacer()
                            Text(store.colorTheme.displayName)
                                .foregroundStyle(.secondary)
                        }
                    }

                    NavigationLink {
                        Form {
                            ForEach(AppFontFamily.allCases) { family in
                                Button {
                                    store.appFontFamily = family
                                    store.persistSettings()
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(family.displayName)
                                                .font(AppTypography.font(size: 16, weight: .medium, family: family))
                                                .foregroundStyle(Color.primary)
                                            Text(family.subtitle)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if store.appFontFamily == family {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(store.colorTheme.tokens.accent)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                        .navigationTitle("字体")
                        .navigationBarTitleDisplayMode(.inline)
                        .appScreenBackground()
                    } label: {
                        HStack {
                            Text("字体")
                            Spacer()
                            Text(store.appFontFamily.displayName)
                                .foregroundStyle(.secondary)
                        }
                    }

                    NavigationLink(destination: FontSettingsView()) {
                        HStack {
                            Text("字号")
                            Spacer()
                            Text("分组 / 列表 / 阅读")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("外观")
                } footer: {
                    Text("外观可跟随系统深色模式；主题与字体影响全局界面与阅读页。")
                }

                // MARK: 翻译与 AI
                Section {
                    NavigationLink(destination: TranslationSettingsView()) {
                        HStack {
                            Text("翻译")
                            Spacer()
                            Text(store.targetLanguage.displayName)
                                .foregroundStyle(.secondary)
                        }
                    }
                    NavigationLink(destination: AISettingsView()) {
                        HStack {
                            Text("AI")
                            Spacer()
                            Text("\(store.aiProviders.count) 个 Provider")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if showAdvancedSettings {
                        NavigationLink(destination: ArticleBlacklistSettingsView()) {
                            HStack {
                                Text("文章黑名单")
                                Spacer()
                                if !store.articleBlacklistTerms.isEmpty {
                                    Text("\(store.articleBlacklistTerms.count)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("翻译与 AI")
                } footer: {
                    Text(showAdvancedSettings
                          ? "翻译目标语言、引擎与 Key 在「翻译」；模型、Prompt、AI 黑名单在「AI」。文章黑名单命中后自动标已读。"
                          : "常用：设置翻译语言与一键翻译引擎。更多 AI / 黑名单请打开上方「显示高级选项」，或点右上角「高级」。")
                }

                // MARK: 朗读
                Section {
                    Picker("默认音色", selection: $store.ttsVoice) {
                        Text("自动（按语言）").tag("")
                        ForEach(EdgeTTS.popularVoices, id: \.id) { v in
                            Text(v.name).tag(v.id)
                        }
                    }
                    .onChange(of: store.ttsVoice) { _, _ in store.persistSettings() }

                    HStack {
                        Text("语速")
                        Spacer()
                        Text(ttsRateLabel)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $store.ttsRate, in: 0.5...2.0, step: 0.05)
                        .onChange(of: store.ttsRate) { _, _ in store.persistSettings() }
                    HStack {
                        Text("0.5×").font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Text("1.0×").font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Text("2.0×").font(.caption2).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("朗读")
                } footer: {
                    Text("使用 Microsoft Edge 在线语音，无需 API Key。语速在合成时生效，切换后需重新点朗读。")
                }


                // MARK: 缓存（始终可见）
                Section {
                    HStack {
                        Label("内容缓存", systemImage: "internaldrive")
                        Spacer()
                        Text(cacheSizeText).foregroundStyle(.secondary)
                    }
                    if store.isClearingCache {
                        VStack(alignment: .leading, spacing: 6) {
                            ProgressView(value: store.cacheClearProgress)
                            Text(store.cacheClearStatus)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button(role: .destructive) {
                        Task {
                            await store.clearOfflineContentCacheAsync()
                            cacheSizeText = store.cacheSizeDescription()
                        }
                    } label: {
                        Label("清除离线缓存", systemImage: "trash")
                    }
                    .disabled(store.isClearingCache)
                } header: {
                    Text("缓存")
                } footer: {
                    Text("只清除全文、Feed 快照与正文图片；订阅与已读状态保留。更多保留天数等选项请打开「显示高级选项」。")
                }
                .onAppear { cacheSizeText = store.cacheSizeDescription() }

                if showAdvancedSettings {
                // MARK: 数据与清理
                Section {
                    Stepper(value: $store.readRetentionDays, in: 0...365) {
                        if store.readRetentionDays == 0 {
                            Text("已读保留：关闭自动清理")
                        } else {
                            Text("已读保留 \(store.readRetentionDays) 天")
                        }
                    }
                    .onChange(of: store.readRetentionDays) { _, _ in
                        store.persistSettings()
                        store.purgeOldReadArticles()
                    }
                    Stepper(value: $store.fullContentCacheDays, in: 0...365) {
                        if store.fullContentCacheDays == 0 {
                            Text("全文缓存：不按时间清理")
                        } else {
                            Text("全文缓存 \(store.fullContentCacheDays) 天")
                        }
                    }
                    .onChange(of: store.fullContentCacheDays) { _, _ in
                        store.persistSettings()
                        store.pruneFullContentCache()
                    }
                    Toggle(isOn: $store.fullContentURLPrefixEnabled) {
                        Label("全文 URL 前缀", systemImage: "link.badge.plus")
                    }
                    .onChange(of: store.fullContentURLPrefixEnabled) { _, _ in
                        store.persistSettings()
                    }
                    if store.fullContentURLPrefixEnabled {
                        TextField("前缀，如 https://archive.is/", text: $store.fullContentURLPrefix)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .onChange(of: store.fullContentURLPrefix) { _, _ in
                                store.persistSettings()
                            }
                    }
                } header: {
                    Text("数据与清理")
                } footer: {
                    Text("已读保留与全文缓存天数、URL 前缀等。清除缓存入口在上方「缓存」分区。")
                }

                // MARK: iCloud
                Section {
                    Toggle(isOn: Binding(
                        get: { store.iCloudSyncEnabled },
                        set: { store.iCloudSyncEnabled = $0 }
                    )) {
                        Label("iCloud 同步", systemImage: "icloud")
                    }
                    if store.iCloudSyncEnabled {
                        if !store.iCloudLastSyncText.isEmpty {
                            Text(store.iCloudLastSyncText)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Button {
                            store.syncICloudNow()
                        } label: {
                            Label("立即同步", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                } header: {
                    Text("iCloud")
                } footer: {
                    Text("同步订阅源、分组与全部设置到同一 Apple ID 的其它设备。文章正文在换机后刷新即可重新获取。API Key 通过 iCloud 钥匙串同步（需在系统设置中登录 iCloud 并开启钥匙串）。")
                }

                // MARK: 备份
                Section {
                    Toggle("导出时包含 API Key", isOn: $exportIncludeSecrets)
                    Button {
                        do {
                            let data = try store.exportSettingsJSON(includeSecrets: exportIncludeSecrets)
                            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Harbor-settings.json")
                            try data.write(to: url, options: .atomic)
                            settingsExportURL = url
                            showSettingsExport = true
                        } catch {
                            settingsIOMessage = "导出失败：\(error.localizedDescription)"
                        }
                    } label: {
                        Label("导出设置", systemImage: "square.and.arrow.up")
                    }
                    Button { showSettingsImport = true } label: {
                        Label("导入设置", systemImage: "square.and.arrow.down")
                    }
                    if let settingsIOMessage {
                        Text(settingsIOMessage).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("备份")
                } footer: {
                    Text("默认不含 API Key。订阅源请用 OPML 单独导出。")
                }
                } // showAdvancedSettings: 数据与备份

                // MARK: 关于
                Section {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text(AppVersion.display).foregroundStyle(.secondary)
                    }
                    if let pid = store.defaultSummaryProviderID,
                       let provider = store.aiProviders.first(where: { $0.id == pid }) {
                        HStack {
                            Text("默认摘要")
                            Spacer()
                            Text(provider.name).foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Text("翻译引擎")
                        Spacer()
                        Text(store.translationEngineChain.map(\.rawValue).joined(separator: " → "))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } header: {
                    Text("关于")
                }
            }
            .appFormChrome()
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAdvancedSettings.toggle()
                    } label: {
                        Text(showAdvancedSettings ? "精简" : "高级")
                            .fontWeight(.medium)
                    }
                    .accessibilityLabel(showAdvancedSettings ? "切换到精简设置" : "显示高级设置")
                }
            }
            .sheet(isPresented: $showSettingsExport) {
                if let url = settingsExportURL {
                    SettingsExportPicker(url: url) { showSettingsExport = false }
                }
            }
            .sheet(isPresented: $showSettingsImport) {
                SettingsImportPicker { url in
                    showSettingsImport = false
                    guard let url else { return }
                    do {
                        pendingImportData = try Data(contentsOf: url)
                        showImportConfirm = true
                    } catch {
                        settingsIOMessage = "读取文件失败：\(error.localizedDescription)"
                    }
                }
            }
            .alert("导入设置？", isPresented: $showImportConfirm) {
                Button("取消", role: .cancel) { pendingImportData = nil }
                Button("导入", role: .destructive) {
                    guard let data = pendingImportData else { return }
                    do {
                        try store.importSettingsJSON(data)
                        settingsIOMessage = "设置已导入"
                    } catch {
                        settingsIOMessage = "导入失败：\(error.localizedDescription)"
                    }
                    pendingImportData = nil
                }
            } message: {
                Text("将覆盖当前字号、主题、翻译与 AI 配置等。若文件含 API Key 也会写入。此操作不可撤销。")
            }
            .onDisappear { store.persistSettings() }
            .onChange(of: store.showReadArticles) { _, _ in store.persistSettings() }
            .onChange(of: store.titleDisplayMode) { _, _ in store.persistSettings() }
        }
    }
}

struct FontSettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                fontStepper(title: "分组名称", value: $store.groupTitleFontSize, range: 11...22)
                fontStepper(title: "订阅列表标题", value: $store.feedTitleFontSize, range: 14...22)
                fontStepper(title: "文章列表标题", value: $store.listTitleFontSize, range: 14...24)
                fontStepper(title: "文章列表摘要", value: $store.listSummaryFontSize, range: 12...20)
            } header: {
                Text("列表")
            }

            Section {
                fontStepper(title: "阅读器标题", value: $store.readerTitleFontSize, range: 18...32)
                fontStepper(title: "阅读器正文", value: $store.fontSize, range: 12...28)
                fontStepper(title: "AI 摘要", value: $store.aiSummaryFontSize, range: 14...28)
            } header: {
                Text("阅读")
            } footer: {
                Text("调整后立即生效，并自动保存。跟随系统「更大字体」时会在基准上再缩放。")
            }
        }
        .appFormChrome()
        .navigationTitle("字号设置")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { store.persistSettings() }
        .onChange(of: store.groupTitleFontSize) { _, _ in store.persistSettings() }
        .onChange(of: store.feedTitleFontSize) { _, _ in store.persistSettings() }
        .onChange(of: store.listTitleFontSize) { _, _ in store.persistSettings() }
        .onChange(of: store.listSummaryFontSize) { _, _ in store.persistSettings() }
        .onChange(of: store.readerTitleFontSize) { _, _ in store.persistSettings() }
        .onChange(of: store.fontSize) { _, _ in store.persistSettings() }
        .onChange(of: store.aiSummaryFontSize) { _, _ in store.persistSettings() }
    }

    @ViewBuilder
    private func fontStepper(title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(Int(value.wrappedValue))").foregroundStyle(.secondary).monospacedDigit()
            Stepper("", value: value, in: range, step: 1).labelsHidden()
        }
    }
}
