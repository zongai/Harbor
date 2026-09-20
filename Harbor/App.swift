import SwiftUI

@main
struct HarborApp: App {
    init() {
        // Cloud 后端未启用（stub），不在此初始化以免误导
        // 扩大 URL 磁盘缓存，配合 OfflineCache 支持离线读正文/图片
        OfflineCache.configureURLCache()
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
