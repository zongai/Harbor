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
                Picker("翻页方式", selection: Binding(
                    get: { BookLayoutMode(rawValue: settings.bookLayoutMode) ?? .scroll },
                    set: {
                        settings.bookLayoutMode = $0.rawValue
                        store.persistSettings()
                    }
                )) {
                    ForEach(BookLayoutMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            } header: {
                Text("书籍阅读")
            } footer: {
                Text("打开书籍时应用。阅读中也可在工具栏「排版」临时调整。默认语速与音色在「设置 → 阅读 → 朗读」。")
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
