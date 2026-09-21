import SwiftUI

struct ContentView: View {
    @State private var store = AppStore()
    @State private var bookLibrary = BookLibrary()
    @State private var opdsCatalogs = OPDSCatalogStore()
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let scheme = ReadingTheme.effectiveColorScheme(
            appearance: store.appearanceMode,
            systemScheme: systemColorScheme
        )
        let readingTheme = store.colorTheme
        let tokens = readingTheme.tokens(for: scheme)
        TabView {
            Tab("订阅", systemImage: "newspaper") {
                FeedsListView()
            }
            Tab("搜索", systemImage: "magnifyingglass") {
                SearchView()
            }
            Tab("对话", systemImage: "bubble.left.and.bubble.right") {
                AIChatView()
            }
            Tab("书籍", systemImage: "books.vertical") {
                BookshelfView()
            }
            Tab("设置", systemImage: "gearshape") {
                SettingsView()
            }
        }
        .tint(tokens.accent)
        .environment(store)
        .environment(bookLibrary)
        .environment(opdsCatalogs)
        .environment(\.theme, tokens)
        .environment(\.readingTheme, readingTheme.colors(for: scheme))
        .preferredColorScheme(store.appearanceMode.preferredColorScheme)
        .onChange(of: scenePhase) { _, phase in
            // 进入后台立即刷盘，缩短防抖崩溃窗口
            if phase == .background || phase == .inactive {
                store.flushPendingFeedsPersist()
            }
        }
    }
}
