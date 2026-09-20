import SwiftUI

struct ContentView: View {
    @State private var store = AppStore()
    @Environment(\.colorScheme) private var systemColorScheme

    var body: some View {
        let resolvedTheme = ReadingTheme.resolved(
            selected: store.colorTheme,
            appearance: store.appearanceMode,
            systemScheme: systemColorScheme
        )
        let tokens = resolvedTheme.tokens
        TabView {
            Tab("订阅", systemImage: "newspaper") {
                FeedsListView()
            }
            Tab("搜索", systemImage: "magnifyingglass") {
                SearchView()
            }
            Tab("收藏", systemImage: "star") {
                FavoritesListView()
            }
            Tab("对话", systemImage: "bubble.left.and.bubble.right") {
                AIChatView()
            }
            Tab("设置", systemImage: "gearshape") {
                SettingsView()
            }
        }
        .tint(tokens.accent)
        .environment(store)
        .environment(\.theme, tokens)
        .environment(\.readingTheme, resolvedTheme.colors)
        .preferredColorScheme(store.appearanceMode.preferredColorScheme)
    }
}
