import Foundation

/// 订阅源 / 分组 / 已读·收藏链接的轻量持久化（与全量 feeds JSON 分离，缩小崩溃窗口丢数据范围）
enum FeedRepository {
    private static let groupsKey = "feedGroups"
    private static let collapsedKey = "collapsedGroupIDs"
    private static let ungroupedCollapsedKey = "isUngroupedCollapsed"
    private static let readLinksKey = "readArticleLinks"
    private static let favoriteLinksKey = "favoriteArticleLinks"

    // MARK: Feeds

    static func loadFeeds() -> [RSSFeed] {
        OfflineCache.loadFeeds() ?? []
    }

    static func saveFeeds(_ feeds: [RSSFeed]) {
        OfflineCache.saveFeeds(feeds)
    }

    // MARK: Groups

    static func loadGroups() -> [FeedGroup] {
        guard let data = UserDefaults.standard.data(forKey: groupsKey),
              let decoded = try? JSONDecoder().decode([FeedGroup].self, from: data) else {
            return []
        }
        return decoded
    }

    static func saveGroups(_ groups: [FeedGroup]) {
        if let data = try? JSONEncoder().encode(groups) {
            UserDefaults.standard.set(data, forKey: groupsKey)
        }
    }

    // MARK: Collapse UI state

    static func loadCollapsedGroupIDs() -> Set<UUID> {
        guard let arr = UserDefaults.standard.array(forKey: collapsedKey) as? [String] else {
            return []
        }
        return Set(arr.compactMap(UUID.init(uuidString:)))
    }

    static func loadIsUngroupedCollapsed() -> Bool {
        UserDefaults.standard.bool(forKey: ungroupedCollapsedKey)
    }

    static func saveCollapsedState(groupIDs: Set<UUID>, isUngroupedCollapsed: Bool) {
        UserDefaults.standard.set(groupIDs.map(\.uuidString), forKey: collapsedKey)
        UserDefaults.standard.set(isUngroupedCollapsed, forKey: ungroupedCollapsedKey)
    }

    // MARK: Read links（即时写入，不依赖 feeds 防抖）

    static func loadReadLinks() -> Set<String> {
        guard let arr = UserDefaults.standard.array(forKey: readLinksKey) as? [String] else {
            return []
        }
        return Set(arr)
    }

    static func saveReadLinks(_ links: Set<String>) {
        UserDefaults.standard.set(Array(links), forKey: readLinksKey)
    }

    // MARK: Favorite links（即时写入，防抖窗口内杀进程不丢收藏）

    static func loadFavoriteLinks() -> Set<String> {
        guard let arr = UserDefaults.standard.array(forKey: favoriteLinksKey) as? [String] else {
            return []
        }
        return Set(arr)
    }

    static func saveFavoriteLinks(_ links: Set<String>) {
        UserDefaults.standard.set(Array(links), forKey: favoriteLinksKey)
    }
}
