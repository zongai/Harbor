import SwiftUI

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme

    @State private var showClearCacheOptions = false
    @State private var confirmClearInterest = false

    private var ttsRateLabel: String {
        let r = store.ttsRate
        if abs(r - 1.0) < 0.001 { return "1.0× 正常" }
        return String(format: "%.2f×", r)
    }

    var body: some View {
        @Bindable var settings = store.settings
        @Bindable var store = store
        NavigationStack {
            Form {
                // MARK: 阅读
                Section {
                    NavigationLink {
                        ReadingAppearanceSettingsView()
                    } label: {
                        Label("外观", systemImage: "paintpalette")
                    }
                    NavigationLink {
                        ReadingTTSSettingsView()
                    } label: {
                        HStack {
                            Label("朗读", systemImage: "speaker.wave.2")
                            Spacer()
                            Text(ttsRateLabel)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    NavigationLink {
                        BookReadingModeSettingsView()
                    } label: {
                        Label("书籍", systemImage: "books.vertical")
                    }
                } header: {
                    Text("阅读")
                } footer: {
                    Text("外观影响列表与阅读页；朗读语速与音色由文章与书籍共用；书籍仅配置默认阅读模式。")
                }

                // MARK: 订阅（与「阅读」同级：入口 → 二级页）
                Section {
                    NavigationLink {
                        SubscriptionListDisplaySettingsView()
                    } label: {
                        Label("列表显示", systemImage: "list.bullet.rectangle")
                    }
                    NavigationLink {
                        SubscriptionFullContentSettingsView()
                    } label: {
                        Label("全文获取", systemImage: "doc.richtext")
                    }
                    NavigationLink {
                        SubscriptionContentFilterSettingsView()
                    } label: {
                        HStack {
                            Label("内容过滤", systemImage: "line.3.horizontal.decrease.circle")
                            Spacer()
                            if !store.articleBlacklistTerms.isEmpty {
                                Text("\(store.articleBlacklistTerms.count)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("订阅")
                } footer: {
                    Text("源的添加、分组与刷新在「订阅」页；此处配置列表展示、全文与内容过滤。")
                }

                // MARK: AI
                Section {
                    NavigationLink(destination: AISettingsView()) {
                        HStack {
                            Label("AI 服务商与功能", systemImage: "wand.and.stars")
                            Spacer()
                            Text(store.aiProviders.isEmpty ? "未配置" : "\(store.aiProviders.count) 个")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("AI")
                } footer: {
                    Text("自动摘要 / 自动翻译可在各订阅源中单独开关。默认引擎、提示词与敏感词回退在此配置。")
                }

                // MARK: 翻译
                Section {
                    NavigationLink(destination: TranslationSettingsView()) {
                        HStack {
                            Label("翻译", systemImage: "globe")
                            Spacer()
                            Text(store.targetLanguage.displayName)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("翻译")
                } footer: {
                    Text("目标语言、引擎顺序与各引擎 Key。AI 翻译依赖「AI 服务商」中的 Provider。")
                }

                // MARK: 同步与数据
                Section {
                    NavigationLink {
                        CloudSyncSettingsView()
                    } label: {
                        Label("云同步", systemImage: "icloud")
                    }
                    NavigationLink {
                        StorageSettingsView()
                    } label: {
                        Label("存储", systemImage: "internaldrive")
                    }
                    NavigationLink {
                        SettingsImportExportView()
                    } label: {
                        Label("导入与导出", systemImage: "square.and.arrow.up.on.square")
                    }
                } header: {
                    Text("同步与数据")
                } footer: {
                    Text("云同步、缓存保留与设置备份。清除缓存在底部「危险操作」。")
                }

                // MARK: 危险操作（页面底部）
                Section {
                    Button(role: .destructive) {
                        showClearCacheOptions = true
                    } label: {
                        Label("清除缓存…", systemImage: "trash")
                    }
                    .disabled(store.isClearingCache)

                    Button(role: .destructive) {
                        confirmClearInterest = true
                    } label: {
                        Label("清空兴趣画像", systemImage: "person.crop.circle.badge.minus")
                    }
                    .disabled(!store.smartInterestFilterEnabled && store.interestWeights.isEmpty)
                } header: {
                    Text("危险操作")
                } footer: {
                    Text("清除缓存不删除订阅与已读状态。清空兴趣画像将删除根据收藏与「不感兴趣」学习到的词权重，无法恢复。")
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
            .confirmationDialog("清除缓存", isPresented: $showClearCacheOptions, titleVisibility: .visible) {
                Button("全部（全文 + 语音 + 译文）", role: .destructive) {
                    Task {
                        await store.clearOfflineContentCacheAsync()
                        BookTTSController.clearAllCaches()
                        BookTranslationService.clearAll()
                    }
                }
                Button("仅文章全文", role: .destructive) {
                    Task { await store.clearOfflineContentCacheAsync() }
                }
                Button("仅离线语音", role: .destructive) {
                    BookTTSController.clearAllCaches()
                }
                Button("仅书籍译文", role: .destructive) {
                    BookTranslationService.clearAll()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("请选择要清除的缓存类型。此操作不可撤销。")
            }
            .confirmationDialog("清空兴趣画像？", isPresented: $confirmClearInterest, titleVisibility: .visible) {
                Button("清空", role: .destructive) {
                    store.interestWeights = [:]
                    store.persistSettings()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("将删除根据收藏与「不感兴趣」学习到的词权重，无法恢复。")
            }
            .onDisappear { store.persistSettings() }
        }
    }
}

// MARK: - 订阅 · 列表显示

struct SubscriptionListDisplaySettingsView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var settings = store.settings
        Form {
            Section {
                Picker("标题显示", selection: $settings.titleDisplayMode) {
                    ForEach(TitleDisplayMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                Toggle("显示已读文章", isOn: $settings.showReadArticles)
                Toggle("显示未读数", isOn: $settings.showUnreadCount)
                Picker("默认排序", selection: $settings.feedSortMode) {
                    ForEach(FeedSortMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .onChange(of: store.feedSortMode) { _, _ in store.persistSettings() }
            } header: {
                Text("列表显示")
            } footer: {
                Text("排序影响订阅列表顺序。源的添加、分组与刷新在「订阅」页。")
            }
        }
        .appFormChrome()
        .navigationTitle("列表显示")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { store.persistSettings() }
        .onChange(of: store.showReadArticles) { _, _ in store.persistSettings() }
        .onChange(of: store.showUnreadCount) { _, _ in store.persistSettings() }
        .onChange(of: store.titleDisplayMode) { _, _ in store.persistSettings() }
    }
}

// MARK: - 订阅 · 全文获取

struct SubscriptionFullContentSettingsView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var settings = store.settings
        Form {
            Section {
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
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            } header: {
                Text("全文获取")
            } footer: {
                Text(store.fullContentURLPrefixEnabled
                     ? "在订阅列表对源左滑/长按「开启全文 URL 前缀」才会对该源生效；缓存仍按原始链接。"
                     : "开启后可填写前缀（如 archive.is），再在订阅列表对指定源启用。")
            }
            .animation(.easeInOut(duration: 0.2), value: store.fullContentURLPrefixEnabled)
        }
        .appFormChrome()
        .navigationTitle("全文获取")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { store.persistSettings() }
    }
}

// MARK: - 订阅 · 内容过滤

struct SubscriptionContentFilterSettingsView: View {
    @Environment(AppStore.self) private var store

    private var hasAIProviders: Bool { !store.aiProviders.isEmpty }

    var body: some View {
        @Bindable var settings = store.settings
        Form {
            Section {
                NavigationLink(destination: ArticleBlacklistSettingsView()) {
                    HStack {
                        Text("关键词黑名单")
                        Spacer()
                        if !store.articleBlacklistTerms.isEmpty {
                            Text("\(store.articleBlacklistTerms.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Group {
                    Toggle("智能兴趣过滤", isOn: $settings.smartInterestFilterEnabled)
                        .disabled(!hasAIProviders)
                    if store.smartInterestFilterEnabled {
                        Toggle("低分自动标已读", isOn: $settings.autoMarkLowInterestRead)
                        Toggle("列表按兴趣排序", isOn: $settings.sortByInterestScore)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("低分阈值 \(String(format: "%.2f", store.lowInterestThreshold))")
                                .font(.subheadline)
                            Slider(value: $settings.lowInterestThreshold, in: 0.1...0.7, step: 0.05)
                                .onChange(of: store.lowInterestThreshold) { _, _ in store.persistSettings() }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .opacity(hasAIProviders ? 1 : 0.45)
                .animation(.easeInOut(duration: 0.2), value: store.smartInterestFilterEnabled)
            } header: {
                Text("内容过滤")
            } footer: {
                if !hasAIProviders {
                    Text("关键词黑名单可独立使用。智能兴趣过滤需先在「AI → AI 服务商」添加至少一个 Provider。")
                } else if store.smartInterestFilterEnabled {
                    Text("根据收藏与「不感兴趣」学习词权重打分。清空画像请到设置底部「危险操作」。")
                } else {
                    Text("关键词命中后自动标已读。开启兴趣过滤后可配置阈值与排序。")
                }
            }
        }
        .appFormChrome()
        .navigationTitle("内容过滤")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { store.persistSettings() }
        .onChange(of: store.smartInterestFilterEnabled) { _, _ in store.persistSettings() }
        .onChange(of: store.autoMarkLowInterestRead) { _, _ in store.persistSettings() }
        .onChange(of: store.sortByInterestScore) { _, _ in store.persistSettings() }
    }
}

// MARK: - 同步与数据 · 云同步

struct CloudSyncSettingsView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Form {
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
                    .transition(.opacity)
                    Button {
                        store.syncICloudNow()
                    } label: {
                        Label("立即同步", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .transition(.opacity)
                }
            } header: {
                Text("云同步")
            } footer: {
                Text(store.iCloudSyncEnabled
                     ? "同步订阅源、分组与设置到同一 Apple ID 的其它设备。正文换机后刷新即可。API Key 经 iCloud 钥匙串同步。"
                     : "开启后可查看同步状态并手动立即同步。正文换机后刷新即可重新获取。")
            }
            .animation(.easeInOut(duration: 0.2), value: store.iCloudSyncEnabled)
        }
        .appFormChrome()
        .navigationTitle("云同步")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { store.persistSettings() }
    }
}

// MARK: - 同步与数据 · 存储

struct StorageSettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var articleCacheText: String = "—"
    @State private var ttsCacheText: String = "—"
    @State private var bookTranslationCacheText: String = "—"
    @State private var cacheSizeText: String = "计算中…"

    var body: some View {
        @Bindable var settings = store.settings
        Form {
            Section {
                HStack {
                    Label("缓存占用", systemImage: "internaldrive")
                    Spacer()
                    Text(cacheSizeText).foregroundStyle(.secondary)
                }
                HStack {
                    Text("文章全文")
                    Spacer()
                    Text(articleCacheText).foregroundStyle(.secondary)
                }
                .font(.footnote)
                HStack {
                    Text("离线语音")
                    Spacer()
                    Text(ttsCacheText).foregroundStyle(.secondary)
                }
                .font(.footnote)
                HStack {
                    Text("书籍译文")
                    Spacer()
                    Text(bookTranslationCacheText).foregroundStyle(.secondary)
                }
                .font(.footnote)

                if store.isClearingCache {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: store.cacheClearProgress)
                        Text(store.cacheClearStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

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
            } header: {
                Text("存储")
            } footer: {
                Text("已读保留与全文缓存天数在启动与刷新时生效。清除缓存请到设置底部「危险操作」。")
            }
        }
        .appFormChrome()
        .navigationTitle("存储")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { refreshCacheSizes() }
        .onDisappear { store.persistSettings() }
    }

    private func refreshCacheSizes() {
        articleCacheText = store.cacheSizeDescription()
        ttsCacheText = BookTTSController.formattedCacheSize()
        bookTranslationCacheText = BookTranslationService.formattedCacheSize()
        cacheSizeText = articleCacheText
    }
}

// MARK: - 同步与数据 · 导入与导出

struct SettingsImportExportView: View {
    @Environment(AppStore.self) private var store
    @State private var settingsExportURL: URL?
    @State private var showSettingsExport = false
    @State private var showSettingsImport = false
    @State private var settingsIOMessage: String?
    @State private var exportIncludeSecrets = false
    @State private var showImportConfirm = false
    @State private var pendingImportData: Data?

    var body: some View {
        Form {
            Section {
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
                Text("导入与导出")
            } footer: {
                Text("导出包含字体/主题/翻译/AI/TTS、书籍阅读偏好（默认模式/语速/双语 Voice）与 OPDS 书库列表；默认不含 API Key 与 OPDS 密码。订阅 OPML 在「订阅」页；本地 EPUB 与译文缓存不导出。勾选「包含 API Key」时一并导出密钥与 OPDS 密码，请妥善保管。")
            }
        }
        .appFormChrome()
        .navigationTitle("导入与导出")
        .navigationBarTitleDisplayMode(.inline)
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
    }
}

// MARK: - 阅读 · 外观

struct ReadingAppearanceSettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme

    var body: some View {
        @Bindable var settings = store.settings
        Form {
            Section {
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
                        Text("字体大小")
                        Spacer()
                        Text("分组 / 列表 / 阅读")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("外观")
            } footer: {
                Text("字号随系统「更大字体」缩放。行距随正文字号自动调整。")
            }
        }
        .appFormChrome()
        .navigationTitle("外观")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { store.persistSettings() }
    }
}

// MARK: - 阅读 · 朗读

struct ReadingTTSSettingsView: View {
    @Environment(AppStore.self) private var store

    private var ttsRateLabel: String {
        let r = store.ttsRate
        if abs(r - 1.0) < 0.001 { return "1.0× 正常" }
        return String(format: "%.2f×", r)
    }

    var body: some View {
        @Bindable var settings = store.settings
        Form {
            Section {
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
                        settings.bookTTSRate = v
                        store.persistSettings()
                    }

                Toggle("双语朗读自动选 Voice", isOn: $settings.bookAutoLanguageVoice)
                    .onChange(of: settings.bookAutoLanguageVoice) { _, _ in
                        store.persistSettings()
                    }
            } header: {
                Text("朗读")
            } footer: {
                Text("文章与书籍共用默认语速与音色。阅读中仍可临时调节。双语朗读按段落语种选 Edge Voice。Edge 在线语音，无需 API Key。")
            }
        }
        .appFormChrome()
        .navigationTitle("朗读")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { store.persistSettings() }
    }
}

// MARK: - 阅读 · 书籍（仅默认模式）

struct BookReadingModeSettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var readingMode: BookReadingMode = .original

    var body: some View {
        @Bindable var settings = store.settings
        Form {
            Section {
                Picker("默认阅读模式", selection: $readingMode) {
                    ForEach(BookReadingMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .onChange(of: readingMode) { _, v in
                    settings.bookDefaultReadingMode = v.rawValue
                    store.persistSettings()
                }
            } header: {
                Text("书籍")
            } footer: {
                Text("打开书籍时应用。朗读语速与双语 Voice 请到「阅读 → 朗读」。缓存清理在「同步与数据 → 存储」或底部「危险操作」。")
            }
        }
        .appFormChrome()
        .navigationTitle("书籍")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            readingMode = BookReadingMode(rawValue: settings.bookDefaultReadingMode) ?? .original
        }
        .onDisappear { store.persistSettings() }
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
