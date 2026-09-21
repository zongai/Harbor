import SwiftUI

/// 书籍相关设置与缓存管理（Phase 8）
struct BookSettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    @State private var readingMode: BookReadingMode = .original
    @State private var ttsRate: Double = 1.0
    @State private var ttsCacheSize = "—"
    @State private var translationCacheSize = "—"
    @State private var confirmClearTTS = false
    @State private var confirmClearTranslation = false

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

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("默认朗读语速")
                        Spacer()
                        Text(String(format: "%.2gx", ttsRate))
                            .foregroundStyle(theme.muted)
                    }
                    Slider(value: $ttsRate, in: 0.75...2.0, step: 0.25) {
                        Text("语速")
                    }
                    .onChange(of: ttsRate) { _, v in
                        settings.bookTTSRate = v
                        store.persistSettings()
                    }
                }

                Toggle("双语朗读自动选 Voice", isOn: $settings.bookAutoLanguageVoice)
                    .onChange(of: settings.bookAutoLanguageVoice) { _, _ in
                        store.persistSettings()
                    }
            } header: {
                Text("书籍阅读")
            } footer: {
                Text("阅读器首次打开一本书时应用默认模式与语速；双语朗读会按段落语种选择 Edge Voice。")
            }

            Section {
                LabeledContent("离线语音缓存", value: ttsCacheSize)
                LabeledContent("书籍译文缓存", value: translationCacheSize)
                Button("刷新占用") { refreshSizes() }
                Button("清除全部离线语音", role: .destructive) {
                    confirmClearTTS = true
                }
                Button("清除全部书籍译文", role: .destructive) {
                    confirmClearTranslation = true
                }
            } header: {
                Text("书籍缓存")
            } footer: {
                Text("离线时可播放已缓存语音；未缓存段落在无网络时会提示，不会错误调用在线 TTS。删除书架书籍时会同步清理该书缓存。")
            }
        }
        .navigationTitle("书籍")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            readingMode = BookReadingMode(rawValue: settings.bookDefaultReadingMode) ?? .original
            ttsRate = settings.bookTTSRate
            refreshSizes()
        }
        .confirmationDialog("清除全部离线语音？", isPresented: $confirmClearTTS, titleVisibility: .visible) {
            Button("清除", role: .destructive) {
                BookTTSController.clearAllCaches()
                refreshSizes()
            }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("清除全部书籍译文？", isPresented: $confirmClearTranslation, titleVisibility: .visible) {
            Button("清除", role: .destructive) {
                BookTranslationService.clearAll()
                refreshSizes()
            }
            Button("取消", role: .cancel) {}
        }
    }

    private func refreshSizes() {
        ttsCacheSize = BookTTSController.formattedCacheSize()
        translationCacheSize = BookTranslationService.formattedCacheSize()
    }
}
