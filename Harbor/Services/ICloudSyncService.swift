import Foundation

/// iCloud Key-Value 同步：订阅源元数据、分组、设置、已读链接、收藏链接。
/// 正文与缓存仍仅存本机；换机后刷新即可重新拉取文章。
enum ICloudSyncService {
    private static let store = NSUbiquitousKeyValueStore.default
    private static let snapshotKey = "harbor.sync.snapshot.v1"
    private static let localUpdatedKey = "harbor.sync.localUpdatedAt"
    private static let enabledKey = "iCloudSyncEnabled"
    private static let maxReadLinks = 8000
    private static let maxFavoriteLinks = 2000

    /// 默认开启；用户可在设置中关闭
    static var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: enabledKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: enabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var lastLocalPushAt: Date? {
        get { UserDefaults.standard.object(forKey: localUpdatedKey) as? Date }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: localUpdatedKey)
            } else {
                UserDefaults.standard.removeObject(forKey: localUpdatedKey)
            }
        }
    }

    // MARK: - Snapshot model

    struct FeedRecord: Codable, Hashable {
        var id: UUID
        var title: String
        var url: String
        var faviconURL: String?
        var groupID: UUID?
        var fetchFullContentEnabled: Bool
        var fetchCommentsEnabled: Bool
        var faviconFetchDone: Bool
        var autoTranslateEnabled: Bool
        var useFullContentURLPrefix: Bool
        var summaryPromptPresetID: String
        var sortOrder: Int

        init(from feed: RSSFeed) {
            id = feed.id
            title = feed.title
            url = feed.url
            faviconURL = feed.faviconURL
            groupID = feed.groupID
            fetchFullContentEnabled = feed.fetchFullContentEnabled
            fetchCommentsEnabled = feed.fetchCommentsEnabled
            faviconFetchDone = feed.faviconFetchDone
            autoTranslateEnabled = feed.autoTranslateEnabled
            useFullContentURLPrefix = feed.useFullContentURLPrefix
            summaryPromptPresetID = feed.summaryPromptPresetID
            sortOrder = feed.sortOrder
        }

        func makeFeed() -> RSSFeed {
            RSSFeed(
                id: id,
                title: title,
                url: url,
                faviconURL: faviconURL,
                groupID: groupID,
                fetchFullContentEnabled: fetchFullContentEnabled,
                fetchCommentsEnabled: fetchCommentsEnabled,
                faviconFetchDone: faviconFetchDone,
                autoTranslateEnabled: autoTranslateEnabled,
                useFullContentURLPrefix: useFullContentURLPrefix,
                summaryPromptPresetID: summaryPromptPresetID,
                sortOrder: sortOrder
            )
        }

        func applyMetadata(to feed: inout RSSFeed) {
            feed.title = title
            feed.faviconURL = faviconURL
            feed.groupID = groupID
            feed.fetchFullContentEnabled = fetchFullContentEnabled
            feed.fetchCommentsEnabled = fetchCommentsEnabled
            feed.faviconFetchDone = faviconFetchDone
            feed.autoTranslateEnabled = autoTranslateEnabled
            feed.useFullContentURLPrefix = useFullContentURLPrefix
            feed.summaryPromptPresetID = summaryPromptPresetID
            feed.sortOrder = sortOrder
            // 保持 id 与文章列表：以本机为准，仅同步元数据
        }
    }

    struct Snapshot: Codable {
        var version: Int
        var updatedAt: Date
        var feeds: [FeedRecord]
        var groups: [FeedGroup]
        var settingsData: Data?
        var readLinks: [String]
        var favoriteLinks: [String]
        var collapsedGroupIDs: [UUID]
        var isUngroupedCollapsed: Bool
    }

    // MARK: - Push / Pull

    static func push(
        feeds: [RSSFeed],
        groups: [FeedGroup],
        settingsData: Data?,
        readLinks: Set<String>,
        favoriteLinks: [String],
        collapsedGroupIDs: Set<UUID>,
        isUngroupedCollapsed: Bool
    ) {
        guard isEnabled else { return }
        let now = Date()
        let snap = Snapshot(
            version: 1,
            updatedAt: now,
            feeds: feeds.map { FeedRecord(from: $0) },
            groups: groups,
            settingsData: settingsData,
            readLinks: Array(readLinks.prefix(maxReadLinks)),
            favoriteLinks: Array(favoriteLinks.prefix(maxFavoriteLinks)),
            collapsedGroupIDs: Array(collapsedGroupIDs),
            isUngroupedCollapsed: isUngroupedCollapsed
        )
        guard let data = try? JSONEncoder().encode(snap) else { return }
        // KVS 总量约 1MB；超限则缩小已读集合再试
        if data.count > 900_000 {
            var slim = snap
            slim.readLinks = Array(slim.readLinks.prefix(2000))
            slim.favoriteLinks = Array(slim.favoriteLinks.prefix(500))
            guard let slimData = try? JSONEncoder().encode(slim) else { return }
            store.set(slimData, forKey: snapshotKey)
        } else {
            store.set(data, forKey: snapshotKey)
        }
        lastLocalPushAt = now
        store.synchronize()
    }

    /// 若云端更新，返回快照；否则 nil
    static func pullIfNewer() -> Snapshot? {
        guard isEnabled else { return nil }
        store.synchronize()
        guard let data = store.data(forKey: snapshotKey),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return nil
        }
        if let local = lastLocalPushAt, snap.updatedAt <= local {
            return nil
        }
        return snap
    }

    static func forcePull() -> Snapshot? {
        guard isEnabled else { return nil }
        store.synchronize()
        guard let data = store.data(forKey: snapshotKey),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return nil
        }
        return snap
    }

    static var cloudUpdatedAt: Date? {
        guard let data = store.data(forKey: snapshotKey),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return nil
        }
        return snap.updatedAt
    }

    static func startObserving(_ handler: @escaping () -> Void) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { _ in
            handler()
        }
    }
}
