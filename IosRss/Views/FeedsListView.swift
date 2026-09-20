import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct FeedsListView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showAddFeed = false
    @State private var showOPMLMenu = false
    @State private var showOPMLImport = false
    @State private var showGroupManager = false
    @State private var editMode: EditMode = .inactive
    @State private var exportFileURL: URL?
    @State private var showExportPicker = false
    @State private var importMessage: String?
    @State private var moveFeedTarget: RSSFeed?
    @State private var newGroupName = ""
    @State private var showNewGroupAlert = false
    @State private var confirmDeleteAll = false
    @State private var renameFeedTarget: RSSFeed?
    @State private var renameFeedText = ""

    private static let allowedImportExtensions: Set<String> = ["opml", "xml", "rss", "atom", "txt"]

    private var refreshProgressLabel: String {
        let cur = store.refreshProgressCurrent
        let tot = store.refreshProgressTotal
        let name = store.refreshProgressTitle
        if tot <= 0 { return "正在刷新…" }
        if name.isEmpty { return "正在刷新 \(cur)/\(tot)" }
        return "正在刷新 \(cur)/\(tot) · \(name)"
    }

    var body: some View {
        NavigationStack {
            List {
                if store.feeds.isEmpty {
                    emptyState
                } else {
                    let sections = visibleFeedSections
                    if sections.isEmpty {
                        noUnreadState
                    } else {
                    // 用稳定 sectionID，避免刷新重排后 ForEach 把折叠状态“串”到别的分组
                    ForEach(sections, id: \.sectionID) { section in
                        let groupID = section.group?.id
                        let collapsed = store.isGroupCollapsed(groupID)
                        let unreadSum = section.feeds.reduce(0) { $0 + $1.unreadCount }
                        Section {
                            if !collapsed {
                                ForEach(section.feeds) { feed in
                                    NavigationLink(value: feed) {
                                        FeedRow(feed: feed)
                                    }
                                    .id(feed.id)
                                    .listRowInsets(EdgeInsets(
                                        top: 0,
                                        leading: AppLayout.listHorizontalPadding,
                                        bottom: 0,
                                        trailing: AppLayout.listHorizontalPadding
                                    ))
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            if let idx = store.feeds.firstIndex(where: { $0.id == feed.id }) {
                                                store.deleteFeed(at: IndexSet([idx]))
                                            }
                                        } label: { Label("删除", systemImage: "trash") }
                                        Button { Task { await store.refreshFeed(feed.id) } } label: {
                                            Label("刷新", systemImage: "arrow.clockwise")
                                        }.tint(.blue)
                                    }
                                    .swipeActions(edge: .leading) {
                                        Button {
                                            UIPasteboard.general.string = feed.url
                                        } label: {
                                            Label("复制链接", systemImage: "link")
                                        }.tint(.indigo)
                                        Button { moveFeedTarget = feed } label: {
                                            Label("分组", systemImage: "folder")
                                        }.tint(.orange)
                                    }
                                    .contextMenu {
                                        Button {
                                            UIPasteboard.general.string = feed.url
                                        } label: {
                                            Label("复制源链接", systemImage: "link")
                                        }
                                        Button {
                                            renameFeedTarget = feed
                                            renameFeedText = feed.title
                                        } label: {
                                            Label("重命名", systemImage: "pencil")
                                        }
                                        let fullOn = store.feeds.first(where: { $0.id == feed.id })?.fetchFullContentEnabled ?? true
                                        Button {
                                            store.setFeedFetchFullContent(feed.id, enabled: !fullOn)
                                        } label: {
                                            Label(fullOn ? "关闭全文获取" : "开启全文获取",
                                                  systemImage: fullOn ? "doc.badge.ellipsis" : "doc.richtext")
                                        }
                                        let commentsOn = store.feeds.first(where: { $0.id == feed.id })?.fetchCommentsEnabled ?? false
                                        Button {
                                            store.setFeedFetchComments(feed.id, enabled: !commentsOn)
                                        } label: {
                                            Label(commentsOn ? "关闭评论获取" : "开启评论获取",
                                                  systemImage: commentsOn ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
                                        }
                                        let autoOn = store.feeds.first(where: { $0.id == feed.id })?.autoTranslateEnabled ?? true
                                        Button {
                                            store.setFeedAutoTranslate(feed.id, enabled: !autoOn)
                                        } label: {
                                            Label(autoOn ? "关闭自动翻译" : "开启自动翻译",
                                                  systemImage: autoOn ? "translate" : "character.textbox")
                                        }
                                        if store.fullContentURLPrefixEnabled {
                                            let prefixOn = store.feeds.first(where: { $0.id == feed.id })?.useFullContentURLPrefix ?? false
                                            Button {
                                                store.setFeedUseFullContentURLPrefix(feed.id, enabled: !prefixOn)
                                            } label: {
                                                Label(prefixOn ? "关闭全文 URL 前缀" : "开启全文 URL 前缀",
                                                      systemImage: prefixOn ? "link.badge.plus" : "link")
                                            }
                                        }
                                        Menu {
                                            let currentID = store.feeds.first(where: { $0.id == feed.id })?.summaryPromptPresetID
                                                ?? SummaryPromptPreset.globalID
                                            Button {
                                                store.setFeedSummaryPreset(feed.id, presetID: SummaryPromptPreset.globalID)
                                            } label: {
                                                if currentID == SummaryPromptPreset.globalID {
                                                    Label(SummaryPromptPreset.globalName, systemImage: "checkmark")
                                                } else {
                                                    Text(SummaryPromptPreset.globalName)
                                                }
                                            }
                                            ForEach(store.summaryPromptPresets) { preset in
                                                Button {
                                                    store.setFeedSummaryPreset(feed.id, presetID: preset.id)
                                                } label: {
                                                    if currentID == preset.id {
                                                        Label(preset.name, systemImage: "checkmark")
                                                    } else {
                                                        Text(preset.name)
                                                    }
                                                }
                                            }
                                        } label: {
                                            Label("摘要模板…", systemImage: "text.badge.star")
                                        }
                                        Button { moveFeedTarget = feed } label: {
                                            Label("移动到分组…", systemImage: "folder")
                                        }
                                        if feed.groupID != nil {
                                            Button { store.moveFeed(feed.id, toGroup: nil) } label: {
                                                Label("移出分组", systemImage: "folder.badge.minus")
                                            }
                                        }
                                    }
                                }
                                .onMove { source, dest in
                                    store.reorderFeeds(groupID: groupID, from: source, to: dest)
                                }
                            }
                        } header: {
                            GroupSectionHeader(
                                title: section.group?.name ?? "未分组",
                                feedCount: section.feeds.count,
                                unreadCount: unreadSum,
                                isCollapsed: collapsed
                            ) {
                                if reduceMotion {
                                    store.toggleGroupCollapsed(groupID)
                                } else {
                                    withAnimation(AppMotion.list) {
                                        store.toggleGroupCollapsed(groupID)
                                    }
                                }
                            }
                        }
                    }
                    } // sections not empty
                }
            }
            .listStyle(.plain)
            .appScreenBackground()
            .environment(\.editMode, $editMode)
            .navigationTitle("订阅")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: RSSFeed.self) { feed in
                ArticleListView(feed: feed)
            }
            .toolbar {
                // While sorting, surface "Done" as primary chrome
                if editMode == .active {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("完成", systemImage: "checkmark") {
                            withAnimation { editMode = .inactive }
                        }
                        .labelStyle(.iconOnly)
                        .accessibilityLabel("完成排序")
                    }
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("添加订阅", systemImage: "plus") {
                            showAddFeed = true
                        }
                        .labelStyle(.iconOnly)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            if store.feedSortMode == .manual {
                                Button {
                                    withAnimation { editMode = .active }
                                } label: {
                                    Label("手动排序", systemImage: "arrow.up.arrow.down")
                                }
                            }
                            Button {
                                showGroupManager = true
                            } label: {
                                Label("管理分组", systemImage: "folder.badge.gearshape")
                            }
                            Divider()
                            Button {
                                showOPMLMenu = true
                            } label: {
                                Label("导入 / 导出", systemImage: "square.and.arrow.down.on.square")
                            }
                        } label: {
                            Label("更多", systemImage: "ellipsis.circle")
                        }
                        .labelStyle(.iconOnly)
                        .accessibilityLabel("更多操作")
                    }
                }
            }
            // 立即结束系统下拉刷新（避免顶部转圈与下方进度条叠两层），实际进度只走 safeAreaInset 线性条
            .refreshable {
                guard !store.isRefreshingAll else { return }
                Task { await store.refreshAll() }
            }
            .safeAreaInset(edge: .top) {
                if store.isRefreshingAll || (store.isLoading && store.refreshProgressTotal > 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(
                            value: Double(store.refreshProgressCurrent),
                            total: Double(max(1, store.refreshProgressTotal))
                        )
                        .progressViewStyle(.linear)
                        .tint(theme.accent)
                        .animation(.easeInOut(duration: 0.32), value: store.refreshProgressCurrent)
                        .animation(.easeInOut(duration: 0.32), value: store.refreshProgressTotal)

                        HStack(spacing: 10) {
                            Text(refreshProgressLabel)
                                .font(AppTypography.caption())
                                .foregroundStyle(theme.muted)
                                .lineLimit(1)
                                .contentTransition(.numericText())
                                .animation(.easeInOut(duration: 0.25), value: store.refreshProgressCurrent)
                                .animation(.easeInOut(duration: 0.25), value: store.refreshProgressTitle)
                            Spacer(minLength: 8)
                            if store.isRefreshingAll {
                                Button("取消") {
                                    store.cancelRefreshAll()
                                }
                                .font(AppTypography.caption().weight(.semibold))
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                    .padding(.horizontal, AppLayout.listHorizontalPadding)
                    .padding(.vertical, AppSpacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            // 仅动画进度条显隐，不带动列表分区折叠/展开
            .animation(.easeInOut(duration: 0.35), value: store.isRefreshingAll)
            .animation(.easeInOut(duration: 0.35), value: store.isLoading)
            .safeAreaInset(edge: .bottom) {
                if let msg = store.errorMessage, !msg.isEmpty {
                    Button {
                        store.errorMessage = nil
                    } label: {
                        Text(msg)
                            .font(AppTypography.caption())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .background(Color.red.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭错误提示")
                    .accessibilityHint(msg)
                }
            }

        }
        .sheet(isPresented: $showAddFeed) { AddFeedView() }
        .sheet(isPresented: $showGroupManager) { GroupManagerView() }
        .confirmationDialog("导入/导出", isPresented: $showOPMLMenu) {
            Button("导入 OPML / XML / TXT") { showOPMLImport = true }
            Button("导出为 OPML") { prepareExport(kind: .opml) }
            Button("删除全部订阅", role: .destructive) { confirmDeleteAll = true }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("确定删除全部订阅源？此操作不可恢复。", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("删除全部", role: .destructive) { store.deleteAllFeeds() }
            Button("取消", role: .cancel) {}
        }
        .sheet(isPresented: $showOPMLImport) {
            OPMLDocumentPicker { url in
                showOPMLImport = false
                if let url { importFile(from: url) }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showExportPicker) {
            if let exportFileURL {
                DocumentExportPicker(fileURL: exportFileURL) {
                    showExportPicker = false
                    self.exportFileURL = nil
                }
                .ignoresSafeArea()
            }
        }
        .confirmationDialog(
            "移动到分组",
            isPresented: Binding(
                get: { moveFeedTarget != nil },
                set: { if !$0 { moveFeedTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("未分组") {
                if let feed = moveFeedTarget { store.moveFeed(feed.id, toGroup: nil) }
                moveFeedTarget = nil
            }
            ForEach(store.groups.sorted(by: { $0.sortOrder < $1.sortOrder })) { group in
                Button(group.name) {
                    if let feed = moveFeedTarget { store.moveFeed(feed.id, toGroup: group.id) }
                    moveFeedTarget = nil
                }
            }
            Button("新建分组…") { showNewGroupAlert = true }
            Button("取消", role: .cancel) { moveFeedTarget = nil }
        }
        .alert("新建分组", isPresented: $showNewGroupAlert) {
            TextField("分组名称", text: $newGroupName)
            Button("创建") {
                let name = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
                store.addGroup(name: name)
                if let feed = moveFeedTarget,
                   let g = store.groups.first(where: { $0.name == name }) {
                    store.moveFeed(feed.id, toGroup: g.id)
                }
                newGroupName = ""
                moveFeedTarget = nil
            }
            Button("取消", role: .cancel) {
                newGroupName = ""
                moveFeedTarget = nil
            }
        } message: {
            Text("输入新分组名称")
        }
        .alert("重命名订阅源", isPresented: Binding(
            get: { renameFeedTarget != nil },
            set: { if !$0 { renameFeedTarget = nil } }
        )) {
            TextField("源名称", text: $renameFeedText)
            Button("保存") {
                if let feed = renameFeedTarget {
                    store.renameFeed(feed.id, to: renameFeedText)
                }
                renameFeedTarget = nil
            }
            Button("取消", role: .cancel) { renameFeedTarget = nil }
        } message: {
            Text("修改后将显示在订阅列表与文章中")
        }
        .alert("导入结果", isPresented: Binding(
            get: { importMessage != nil },
            set: { if !$0 { importMessage = nil } }
        )) {
            Button("好", role: .cancel) { importMessage = nil }
        } message: {
            Text(importMessage ?? "")
        }
    }

    private enum ExportKind { case opml }

    private func prepareExport(kind: ExportKind) {
        let content: String
        let filename: String
        switch kind {
        case .opml:
            content = store.exportOPML()
            filename = "Harbor-subscriptions.opml"
        }
        guard !content.isEmpty,
              let url = store.writeExportFile(content: content, filename: filename) else {
            importMessage = "无法创建导出文件"
            return
        }
        if kind == .opml, url.pathExtension.lowercased() != "opml" {
            importMessage = "导出文件扩展名异常，请重试"
            return
        }
        exportFileURL = url
        showExportPicker = true
    }

    private func importFile(from url: URL) {
        let ext = url.pathExtension.lowercased()
        if !ext.isEmpty, !Self.allowedImportExtensions.contains(ext) {
            importMessage = "仅支持 .opml / .xml / .rss / .atom / .txt 文件（当前：.\(ext)）"
            return
        }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        var data: Data?
        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        coordinator.coordinate(readingItemAt: url, error: &coordError) { coordinated in
            data = try? Data(contentsOf: coordinated)
        }
        if data == nil { data = try? Data(contentsOf: url) }
        if data == nil, let copied = try? Data(contentsOf: URL(fileURLWithPath: url.path)) {
            data = copied
        }
        guard let data, !data.isEmpty else {
            importMessage = "无法读取该文件（\(url.lastPathComponent)）"
            return
        }
        if ext == "txt" {
            importMessage = importTXT(data: data)
            return
        }
        if ext.isEmpty {
            let head = String(data: data.prefix(200), encoding: .utf8)?.lowercased() ?? ""
            let looksOK = head.contains("opml") || head.contains("outline")
                || head.contains("<rss") || head.contains("<feed")
                || head.contains("http://") || head.contains("https://")
            if !looksOK {
                importMessage = "仅支持 OPML / XML / RSS / Atom / TXT 订阅文件"
                return
            }
        }
        let imported = store.importSubscriptions(data: data)
        if imported.added == 0 && imported.skipped == 0 {
            let head = String(data: data.prefix(400), encoding: .utf8) ?? ""
            if head.localizedCaseInsensitiveContains("opml")
                || head.localizedCaseInsensitiveContains("outline")
                || head.localizedCaseInsensitiveContains("xmlUrl") {
                importMessage = "已识别为 OPML，但未找到有效的 xmlUrl 订阅地址"
            } else if head.localizedCaseInsensitiveContains("<rss")
                        || head.localizedCaseInsensitiveContains("<feed") {
                importMessage = "已识别为 RSS/Atom，但未找到可用的源地址"
            } else {
                importMessage = "未能识别为 OPML、RSS 或 Atom（\(url.lastPathComponent)）"
            }
        } else {
            let kind = imported.kind == "rss" ? "RSS/Atom" : "OPML"
            var text = "已从 \(kind) 导入 \(imported.added) 个订阅"
            if imported.skipped > 0 { text += "，跳过 \(imported.skipped) 个已存在的源" }
            importMessage = text
            if imported.added > 0 { Task { await store.refreshAll() } }
        }
    }

    private func importTXT(data: Data) -> String {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
            return "无法解析 TXT 文件"
        }
        var currentGroup: String? = nil
        var pendingTitle: String? = nil
        var added = 0
        var skipped = 0
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            if line.hasPrefix("#") {
                let name = line.dropFirst().trimmingCharacters(in: .whitespaces)
                currentGroup = name.isEmpty || name == "未分组" ? nil : String(name)
                pendingTitle = nil
                continue
            }
            let lower = line.lowercased()
            if lower.hasPrefix("http://") || lower.hasPrefix("https://")
                || lower.hasPrefix("feed://") || lower.hasPrefix("rsshub://") || lower.hasPrefix("rsshub:/") {
                let url = FeedURL.canonical(line)
                if store.feeds.contains(where: { FeedURL.canonical($0.url) == url }) {
                    skipped += 1
                    pendingTitle = nil
                    continue
                }
                var groupID: UUID?
                if let gName = currentGroup {
                    if let existing = store.groups.first(where: { $0.name == gName }) {
                        groupID = existing.id
                    } else {
                        store.addGroup(name: gName)
                        groupID = store.groups.first(where: { $0.name == gName })?.id
                    }
                }
                let title = FeedNaming.resolveTitle(parsed: pendingTitle, url: url)
                store.addFeed(RSSFeed(
                    title: title, url: url,
                    faviconURL: FeedParser.siteFaviconURL(for: url),
                    groupID: groupID
                ))
                added += 1
                pendingTitle = nil
            } else {
                pendingTitle = line
            }
        }
        if added == 0 && skipped == 0 { return "TXT 中未找到有效的订阅地址" }
        var msg = "已从 TXT 导入 \(added) 个订阅"
        if skipped > 0 { msg += "，跳过 \(skipped) 个已存在的源" }
        if added > 0 { Task { await store.refreshAll() } }
        return msg
    }

    
    /// 源列表展示用：默认只显示有未读的源；开启「显示已读文章」时显示全部
    private var visibleFeedSections: [(sectionID: String, group: FeedGroup?, feeds: [RSSFeed])] {
        store.feedsByGroup.compactMap { section in
            let feeds = store.showReadArticles
                ? section.feeds
                : section.feeds.filter { $0.unreadCount > 0 }
            guard !feeds.isEmpty else { return nil }
            let sid = section.group?.id.uuidString ?? "__ungrouped__"
            return (sid, section.group, feeds)
        }
    }

    var noUnreadState: some View {
        ContentUnavailableView {
            Label {
                Text("暂无未读")
                    .font(AppTypography.section())
            } icon: {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(theme.muted)
            }
        } description: {
            Text("所有订阅源都没有未读文章。")
                .font(AppTypography.body())
                .foregroundStyle(theme.muted)
        } actions: {
            Button("显示全部订阅源") {
                store.showReadArticles = true
                store.persistSettings()
            }
            .buttonStyle(.bordered)
            .tint(theme.accent)
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(.init(top: 80, leading: AppLayout.listHorizontalPadding, bottom: 40, trailing: AppLayout.listHorizontalPadding))
    }

    var emptyState: some View {
        ContentUnavailableView {
            Label {
                Text("暂无订阅")
                    .font(AppTypography.section())
            } icon: {
                Image(systemName: "newspaper")
                    .foregroundStyle(theme.muted)
            }
        } description: {
            Text("添加你的第一个 RSS 订阅源，开始安静阅读。")
                .font(AppTypography.body())
                .foregroundStyle(theme.muted)
        } actions: {
            Button("添加订阅") { showAddFeed = true }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(.init(top: 80, leading: AppLayout.listHorizontalPadding, bottom: 40, trailing: AppLayout.listHorizontalPadding))
    }
}

struct GroupSectionHeader: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    let title: String
    let feedCount: Int
    let unreadCount: Int
    let isCollapsed: Bool
    let onToggle: () -> Void

    private var titleSize: Double { store.groupTitleFontSize }
    private var metaSize: Double { max(10, titleSize - 2) }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(AppTypography.font(size: max(9, titleSize - 2), weight: .semibold))
                    .foregroundStyle(theme.muted)
                    .frame(width: max(12, titleSize - 1), alignment: .center)
                Text(title)
                    .font(AppTypography.font(size: titleSize, weight: .semibold))
                    .tracking(AppTypography.sectionTracking * 0.5)
                    .foregroundStyle(theme.text)
                    .textCase(nil)
                if isCollapsed {
                    Text("\(feedCount)")
                        .font(AppTypography.font(size: metaSize, weight: .medium))
                        .foregroundStyle(theme.muted)
                        .monospacedDigit()
                    if unreadCount > 0 {
                        Text("\(unreadCount)")
                            .font(AppTypography.font(size: max(10, titleSize - 3), weight: .bold))
                            .foregroundStyle(Color(.systemBackground))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(theme.accent, in: Capsule())
                            .monospacedDigit()
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .padding(.vertical, AppSpacing.xxs)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)，\(isCollapsed ? "已折叠" : "已展开")")
        .accessibilityHint("点按以\(isCollapsed ? "展开" : "折叠")")
    }
}

struct GroupManagerView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    @State private var renameTarget: FeedGroup?
    @State private var renameText = ""
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.groups.sorted(by: { $0.sortOrder < $1.sortOrder })) { group in
                        Button {
                            renameTarget = group
                            renameText = group.name
                        } label: {
                            HStack(spacing: AppSpacing.sm) {
                                Image(systemName: "folder")
                                    .foregroundStyle(theme.muted)
                                Text(group.name)
                                    .font(AppTypography.font(size: store.groupTitleFontSize, weight: .medium))
                                    .foregroundStyle(theme.text)
                                Spacer()
                                Text("\(store.feeds.filter { $0.groupID == group.id }.count)")
                                    .font(AppTypography.caption())
                                    .foregroundStyle(theme.muted)
                                    .monospacedDigit()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("重命名分组")
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { store.deleteGroup(group.id) } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                } header: { Text("已有分组") }
                footer: { Text("点分组可重命名；删除分组后源会回到「未分组」。点组标题可折叠/展开。") }
                Section("新建分组") {
                    HStack {
                        TextField("分组名称", text: $newName)
                        Button("添加") { store.addGroup(name: newName); newName = "" }
                            .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .appFormChrome()
            .navigationTitle("管理分组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .alert("重命名分组", isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            )) {
                TextField("名称", text: $renameText)
                Button("保存") {
                    if let g = renameTarget { store.renameGroup(g.id, to: renameText) }
                    renameTarget = nil
                }
                Button("取消", role: .cancel) { renameTarget = nil }
            }
        }
    }
}

struct FeedRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    let feed: RSSFeed
    private var live: RSSFeed { store.feeds.first(where: { $0.id == feed.id }) ?? feed }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: AppSpacing.sm) {
                FeedIcon(feed: live, size: 36)
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text(live.title)
                        .font(AppTypography.font(size: store.feedTitleFontSize, weight: .semibold))
                        .tracking(AppTypography.titleTracking * 0.4)
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        if CommentFetcher.isSubstackLike(feed: live) {
                            Label("Substack", systemImage: "newspaper")
                                .labelStyle(.titleAndIcon)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color(.systemBackground))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.9), in: Capsule())
                                .accessibilityLabel("Substack 源")
                        }
                        if let last = live.lastFetched {
                            Text(Self.relativeString(last))
                                .font(AppTypography.caption())
                                .foregroundStyle(theme.muted)
                        }
                        if !live.fetchFullContentEnabled {
                            Text("全文关")
                                .font(AppTypography.caption())
                                .foregroundStyle(theme.muted)
                        }
                        if store.fullContentURLPrefixEnabled && live.useFullContentURLPrefix {
                            Text("前缀")
                                .font(AppTypography.caption())
                                .foregroundStyle(theme.muted)
                        }
                        if live.autoTranslateEnabled {
                            Text("自动译")
                                .font(AppTypography.caption())
                                .foregroundStyle(theme.muted.opacity(0.85))
                        }
                    }
                    // 刷新失败原因：直接显示在源标题下方，便于对照
                    if let err = live.lastRefreshError, !err.isEmpty {
                        Text(err)
                            .font(AppTypography.caption())
                            .foregroundStyle(.orange)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel("刷新失败：\(err)")
                    }
                }
                Spacer(minLength: AppSpacing.xs)
                if live.unreadCount > 0 {
                    Text("\(live.unreadCount)")
                        .font(AppTypography.label())
                        .monospacedDigit()
                        .foregroundStyle(theme.accent)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(theme.accentSoft, in: Capsule())
                }
            }
            .padding(.vertical, AppSpacing.sm)
            Divider()
                .opacity(0.35)
        }
        .id("\(live.id.uuidString)-\(live.lastRefreshError ?? "")-\(live.unreadCount)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel({
            var parts = [live.title]
            if live.unreadCount > 0 { parts.append("\(live.unreadCount) 未读") }
            if let last = live.lastFetched { parts.append(Self.relativeString(last)) }
            if let err = live.lastRefreshError, !err.isEmpty { parts.append("刷新失败") }
            return parts.joined(separator: "，")
        }())
        .accessibilityHint("打开文章列表")
    }
}

extension FeedRow {
    static func relativeString(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }
}

struct FeedIcon: View {
    @Environment(AppStore.self) private var store
    let feed: RSSFeed
    let size: CGFloat
    @State private var image: UIImage?
    @State private var loading = false
    @State private var useLetter = false
    /// 本会话对失败缓存的重试（兼容旧版误标 fetchDone / 空缓存）
    @State private var didSessionRetry = false
    private var cacheKey: String { "feed-icon:\(feed.id.uuidString)" }
    private var live: RSSFeed { store.feeds.first(where: { $0.id == feed.id }) ?? feed }
    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .accessibilityLabel("\(feed.title) 图标")
            } else if loading {
                ProgressView()
                    .frame(width: size, height: size)
                    .accessibilityLabel("正在加载图标")
            } else { letterFallback }
        }
        .task(id: "\(feed.id.uuidString)-\(live.faviconURL ?? "")-\(live.faviconFetchDone)") {
            // URL / 完成标记变化时重新尝试（兼容旧数据误标 fetchDone）
            if image == nil {
                useLetter = false
                await loadIcon()
            }
        }
    }
    private var letterFallback: some View {
        ZStack {
            Circle().fill(Color.primary).frame(width: size, height: size)
            Text(String(feed.title.prefix(1)).uppercased())
                .font(.system(size: size * 0.45, weight: .bold))
                .foregroundStyle(Color(.systemBackground))
        }
        .accessibilityLabel("\(feed.title) 图标占位")
    }
    private func loadIcon() async {
        if image != nil { return }
        if let cached = FaviconCache.shared.image(for: cacheKey) {
            image = cached
            useLetter = false
            return
        }
        if let data = OfflineCache.loadFavicon(key: cacheKey) {
            // 非空且能解码 → 成功缓存；空数据表示曾经失败
            if !data.isEmpty, let ui = UIImage(data: data), ui.size.width > 1 {
                FaviconCache.shared.store(ui, for: cacheKey)
                image = ui
                useLetter = false
                return
            }
            // 失败空缓存：本会话允许重试一次（旧版可能未真正拉取就标记完成）
            if data.isEmpty && live.faviconFetchDone && didSessionRetry {
                useLetter = true
                return
            }
            if data.isEmpty && !didSessionRetry {
                didSessionRetry = true
                // 清掉失败占位，重新走候选下载
                OfflineCache.saveFavicon(key: cacheKey, data: Data()) // keep key; will overwrite on success
            }
        } else if let legacy = OfflineCache.loadImage(url: cacheKey) {
            OfflineCache.saveFavicon(key: cacheKey, data: legacy)
            if !legacy.isEmpty, let ui = UIImage(data: legacy), ui.size.width > 1 {
                FaviconCache.shared.store(ui, for: cacheKey)
                image = ui
                useLetter = false
                return
            }
        }
        // 兼容旧 bug：fetchDone=true 但磁盘无缓存 → 再试
        if live.faviconFetchDone, OfflineCache.loadFavicon(key: cacheKey) != nil, didSessionRetry {
            useLetter = true
            return
        }
        if !didSessionRetry { didSessionRetry = true }

        loading = true
        defer { loading = false }
        var candidates: [String] = []
        if let preferred = live.faviconURL, !preferred.isEmpty { candidates.append(preferred) }
        candidates.append(contentsOf: FeedParser.faviconCandidates(for: live.url))
        var seen = Set<String>()
        var found: UIImage?
        var foundData: Data?
        for raw in candidates {
            guard !raw.isEmpty, seen.insert(raw).inserted, let url = URL(string: raw) else { continue }
            do {
                var request = URLRequest(url: url, timeoutInterval: 12)
                request.setValue(
                    "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15",
                    forHTTPHeaderField: "User-Agent"
                )
                request.setValue("image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { continue }
                guard data.count >= 32 else { continue }
                guard let ui = UIImage(data: data), ui.size.width > 1 else { continue }
                found = ui
                foundData = data
                break
            } catch { continue }
        }
        if let found, let foundData {
            FaviconCache.shared.store(found, for: cacheKey)
            OfflineCache.saveFavicon(key: cacheKey, data: foundData)
            image = found
            useLetter = false
        } else {
            useLetter = true
            OfflineCache.saveFavicon(key: cacheKey, data: Data())
        }
        store.markFaviconFetchDone(live.id)
    }
}

enum FaviconCache {
    static let shared = Cache()
    final class Cache {
        private let cache = NSCache<NSString, UIImage>()
        func image(for key: String) -> UIImage? { cache.object(forKey: key as NSString) }
        func store(_ image: UIImage, for key: String) { cache.setObject(image, forKey: key as NSString) }
    }
}

struct OPMLDocumentPicker: UIViewControllerRepresentable {
    var onPick: (URL?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [.item]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL?) -> Void
        init(onPick: @escaping (URL?) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls.first)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { onPick(nil) }
    }
}

struct DocumentExportPicker: UIViewControllerRepresentable {
    let fileURL: URL
    var onFinish: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [fileURL], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { onFinish() }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { onFinish() }
    }
}
