import SwiftUI

struct SettingsView: View {
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

    @State private var showOPMLImport = false
    @State private var showOPMLExport = false
    @State private var opmlExportURL: URL?
    @State private var dataIOMessage: String?

    var body: some View {
        @Bindable var settings = store.settings
        @Bindable var store = store
        NavigationStack {
            Form {
                // MARK: 账号
                Section {
                    Toggle(isOn: Binding(
                        get: { store.iCloudSyncEnabled },
                        set: { store.iCloudSyncEnabled = $0 }
                    )) {
                        Label("云同步", systemImage: "icloud")
                    }
                    if store.iCloudSyncEnabled {
                        HStack {
                            Text("同步状态")
                            Spacer()
                            Text(store.iCloudLastSyncText.isEmpty ? "—" : store.iCloudLastSyncText)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                        Button {
                            store.syncICloudNow()
                        } label: {
                            Label("立即同步", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                } header: {
                    Text("账号")
                } footer: {
                    Text("同步订阅源、分组与设置到同一 Apple ID 的其它设备。正文在换机后刷新即可重新获取。API Key 经 iCloud 钥匙串同步。")
                }

                // MARK: 阅读
                Section {
                    Picker("标题显示", selection: $settings.titleDisplayMode) {
                        ForEach(TitleDisplayMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    NavigationLink(destination: FontSettingsView()) {
                        HStack {
                            Text("字体大小")
                            Spacer()
                            Text("分组 / 列表 / 阅读")
                                .font(.footnote)
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
                    NavigationLink {
                        Form {
                            ThemePalettePicker(selection: $settings.colorTheme)
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
                    Picker("深色模式", selection: $settings.appearanceMode) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .onChange(of: store.appearanceMode) { _, _ in store.persistSettings() }

                    Picker("朗读音色", selection: $settings.ttsVoice) {
                        Text("自动（按语言）").tag("")
                        ForEach(EdgeTTS.popularVoices, id: \.id) { v in
                            Text(v.name).tag(v.id)
                        }
                    }
                    .onChange(of: store.ttsVoice) { _, _ in store.persistSettings() }
                    HStack {
                        Text("默认朗读语速")
                        Spacer()
                        Text(ttsRateLabel)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $settings.ttsRate, in: 0.5...2.0, step: 0.05)
                        .onChange(of: settings.ttsRate) { _, v in
                            // 文章与书籍共用默认语速
                            settings.bookTTSRate = v
                            store.persistSettings()
                        }
                } header: {
                    Text("阅读")
                } footer: {
                    Text("字号随系统「更大字体」缩放。行距随正文字号自动调整。默认语速同时作用于文章与书籍朗读（阅读中仍可临时调节）。Edge 在线语音，无需 API Key。")
                }

                // MARK: 订阅
                Section {
                    Toggle("显示已读文章", isOn: $settings.showReadArticles)
                    Picker("默认排序", selection: $settings.feedSortMode) {
                        ForEach(FeedSortMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .onChange(of: store.feedSortMode) { _, _ in store.persistSettings() }
                } header: {
                    Text("订阅")
                } footer: {
                    Text("源的添加、分组与刷新在「订阅」页。排序影响订阅列表顺序。")
                }

                // MARK: AI
                Section {
                    NavigationLink(destination: AISettingsView()) {
                        HStack {
                            Text("AI 服务")
                            Spacer()
                            Text("\(store.aiProviders.count) 个 Provider")
                                .foregroundStyle(.secondary)
                        }
                    }
                    NavigationLink(destination: TranslationSettingsView()) {
                        HStack {
                            Text("翻译")
                            Spacer()
                            Text(store.targetLanguage.displayName)
                                .foregroundStyle(.secondary)
                        }
                    }
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
                } header: {
                    Text("AI")
                } footer: {
                    Text("自动摘要 / 自动翻译可在各订阅源中单独开关。翻译目标语言与引擎链在「翻译」中配置。")
                }

                // MARK: 数据
                                Section {
                    NavigationLink {
                        BookSettingsView()
                    } label: {
                        Label("书籍阅读与缓存", systemImage: "books.vertical")
                    }
                } header: {
                    Text("书籍")
                }

Section {
                    HStack {
                        Label("缓存占用", systemImage: "internaldrive")
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
                    Button {
                        showOPMLImport = true
                    } label: {
                        Label("导入 OPML", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        prepareOPMLExport()
                    } label: {
                        Label("导出 OPML", systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive) {
                        Task {
                            await store.clearOfflineContentCacheAsync()
                            cacheSizeText = store.cacheSizeDescription()
                        }
                    } label: {
                        Label("清除缓存", systemImage: "trash")
                    }
                    .disabled(store.isClearingCache)
                    Toggle(isOn: $settings.fullContentURLPrefixEnabled) {
                        Label("全文 URL 前缀", systemImage: "link.badge.plus")
                    }
                    .onChange(of: store.fullContentURLPrefixEnabled) { _, _ in
                        store.persistSettings()
                    }
                    if store.fullContentURLPrefixEnabled {
                        TextField("前缀，如 https://archive.is/", text: $settings.fullContentURLPrefix)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .onChange(of: store.fullContentURLPrefix) { _, _ in
                                store.persistSettings()
                            }
                    }
                    if let dataIOMessage {
                        Text(dataIOMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("数据")
                } footer: {
                    Text("清除缓存只删除全文、Feed 快照与图片；订阅与已读保留。开启 URL 前缀后，在订阅列表对源左滑/长按「开启全文 URL 前缀」才会对该源生效；缓存仍按原始链接。")
                }
                .onAppear { cacheSizeText = store.cacheSizeDescription() }

                Section {
                        Stepper(value: $settings.readRetentionDays, in: 0...365) {
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
                        Stepper(value: $settings.fullContentCacheDays, in: 0...365) {
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
                        Toggle("导出设置时包含 API Key", isOn: $exportIncludeSecrets)
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
                    Text("清理与备份")
                } footer: {
                    Text("导出为完整偏好快照（字体/主题/翻译/AI/TTS/书籍阅读等全部已注册设置；日后新增项会自动进入备份）。默认不含 API Key（可勾选包含）。订阅列表请用 OPML；书籍文件与 OPDS 书库不在此备份内。")
                }

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
                } footer: {
                    Text("Harbor · 观澜")
                }

            }
            .appFormChrome()
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.large)
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
            .sheet(isPresented: $showOPMLImport) {
                OPMLDocumentPicker { url in
                    showOPMLImport = false
                    guard let url else { return }
                    importOPML(from: url)
                }
            }
            .sheet(isPresented: $showOPMLExport) {
                if let url = opmlExportURL {
                    SettingsExportPicker(url: url) { showOPMLExport = false }
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

    private func prepareOPMLExport() {
        let content = store.exportOPML()
        guard !content.isEmpty,
              let url = store.writeExportFile(content: content, filename: "Harbor-subscriptions.opml") else {
            dataIOMessage = "无法创建 OPML 文件"
            return
        }
        opmlExportURL = url
        showOPMLExport = true
        dataIOMessage = nil
    }

    private func importOPML(from url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        var data: Data?
        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        coordinator.coordinate(readingItemAt: url, error: &coordError) { coordinated in
            data = try? Data(contentsOf: coordinated)
        }
        if data == nil { data = try? Data(contentsOf: url) }
        guard let data, !data.isEmpty else {
            dataIOMessage = "无法读取该文件"
            return
        }
        let imported = store.importSubscriptions(data: data)
        if imported.added == 0 && imported.skipped == 0 {
            dataIOMessage = "未找到有效订阅地址"
        } else {
            var text = "已导入 \(imported.added) 个订阅"
            if imported.skipped > 0 { text += "，跳过 \(imported.skipped) 个已存在" }
            dataIOMessage = text
            if imported.added > 0 { Task { await store.refreshAll() } }
        }
    }
}

// MARK: - 字号

struct FontSettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme

    var body: some View {
        @Bindable var settings = store.settings
        @Bindable var store = store
        Form {
            Section {
                fontRow("分组标题", value: $settings.feedTitleFontSize, range: 13...24)
                fontRow("列表标题", value: $settings.listTitleFontSize, range: 14...26)
                fontRow("列表摘要", value: $settings.listSummaryFontSize, range: 12...20)
            } header: {
                Text("列表")
            }
            Section {
                fontRow("文章标题", value: $settings.readerTitleFontSize, range: 18...34)
                fontRow("正文字号", value: $settings.fontSize, range: 14...28)
                fontRow("AI 摘要", value: $settings.aiSummaryFontSize, range: 14...28)
            } header: {
                Text("阅读")
            } footer: {
                Text("调整后立即生效，并自动保存。跟随系统「更大字体」时会在基准上再缩放。")
            }
        }
        .appFormChrome()
        .navigationTitle("字体大小")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { store.persistSettings() }
    }

    private func fontRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value.wrappedValue))").foregroundStyle(.secondary).monospacedDigit()
            }
            Slider(value: value, in: range, step: 1)
                .onChange(of: value.wrappedValue) { _, _ in store.persistSettings() }
        }
    }
}
