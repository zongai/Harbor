import SwiftUI

/// 书籍相关设置入口（朗读与缓存已并入「阅读 → 朗读」与「同步与数据 → 存储」）
struct BookSettingsView: View {
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
                Text("书籍阅读")
            } footer: {
                Text("打开书籍时应用。默认语速、音色与双语 Voice 在「设置 → 阅读 → 朗读」；离线语音与译文缓存清理在「设置 → 同步与数据 → 存储」。")
            }
        }
        .navigationTitle("书籍")
        .navigationBarTitleDisplayMode(.inline)
        .appFormChrome()
        .onAppear {
            readingMode = BookReadingMode(rawValue: settings.bookDefaultReadingMode) ?? .original
        }
        .onDisappear { store.persistSettings() }
    }
}
