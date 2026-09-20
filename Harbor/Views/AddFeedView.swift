import SwiftUI

struct AddFeedView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    @State private var urlText = ""
    @State private var isSearching = false
    @State private var discoveredFeeds: [DiscoveredFeed] = []
    @State private var errorMessage: String?
    @State private var phase: Phase = .input
    @FocusState private var isURLFocused: Bool
    /// 新源加入的分组键：`"none"` = 未分组（不要塞进任何分组）
    @State private var selectedGroupKey: String = "none"
    @State private var showNewGroupAlert = false
    @State private var newGroupName = ""

    enum Phase { case input, discovering, select, adding }

    private var sortedGroups: [FeedGroup] {
        store.groups.sorted {
            $0.sortOrder < $1.sortOrder || ($0.sortOrder == $1.sortOrder && $0.name < $1.name)
        }
    }

    /// 仅当用户明确选中某个仍存在的分组时才返回 id
    private var resolvedGroupID: UUID? {
        guard selectedGroupKey != "none",
              let id = UUID(uuidString: selectedGroupKey),
              store.groups.contains(where: { $0.id == id }) else {
            return nil
        }
        return id
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // URL Input Area
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("粘贴网站或 Feed 地址")
                        .font(AppTypography.caption())
                        .foregroundStyle(theme.muted)
                        .padding(.horizontal, AppLayout.pageMargin)
                        .padding(.top, AppSpacing.xl)

                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "link")
                            .foregroundStyle(theme.muted)
                        TextField("https://", text: $urlText)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .focused($isURLFocused)
                            .submitLabel(.search)
                            .onSubmit { Task { await discover() } }
                    }
                    .padding(AppSpacing.sm + 2)
                    .background(
                        RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                            .fill(theme.surface.opacity(0.55))
                    )
                    .padding(.horizontal, AppLayout.pageMargin)

                    // 指定分组（默认「未分组」= groupID 为 nil，不放进任何分组）
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "folder")
                            .foregroundStyle(theme.muted)
                            .frame(width: 18)
                        Picker("加入分组", selection: $selectedGroupKey) {
                            Text("未分组").tag("none")
                            ForEach(sortedGroups) { group in
                                Text(group.name).tag(group.id.uuidString)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        Spacer(minLength: 0)
                        Button {
                            newGroupName = ""
                            showNewGroupAlert = true
                        } label: {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(theme.accent)
                        }
                        .accessibilityLabel("新建分组")
                        .frame(minWidth: AppLayout.minTapTarget, minHeight: AppLayout.minTapTarget)
                    }
                    .padding(.horizontal, AppSpacing.sm + 2)
                    .padding(.vertical, AppSpacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                            .fill(theme.surface.opacity(0.55))
                    )
                    .padding(.horizontal, AppLayout.pageMargin)
                    .padding(.top, AppSpacing.xxs)
                }

                if let error = errorMessage {
                    Text(error)
                        .font(AppTypography.caption())
                        .foregroundStyle(.red)
                        .padding(.horizontal, AppLayout.pageMargin)
                        .padding(.top, AppSpacing.xs)
                }

                if phase == .discovering {
                    HStack(spacing: AppSpacing.sm) {
                        ProgressView()
                            .tint(theme.accent)
                        Text("正在查找 Feed…")
                            .font(AppTypography.body())
                            .foregroundStyle(theme.muted)
                    }
                    .padding(.top, AppSpacing.xl)
                }

                if !discoveredFeeds.isEmpty && phase == .select {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("发现以下 Feed，请选择：")
                            .font(AppTypography.caption())
                            .foregroundStyle(theme.muted)
                            .padding(.horizontal, AppLayout.pageMargin)
                            .padding(.top, AppSpacing.xl)
                            .padding(.bottom, AppSpacing.xs)

                        ForEach(discoveredFeeds) { feed in
                            Button {
                                Task { await addFeed(feed) }
                            } label: {
                                HStack(spacing: AppSpacing.sm) {
                                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                                        Text(feed.title)
                                            .font(AppTypography.label())
                                            .foregroundStyle(theme.text)
                                        Text(feed.url)
                                            .font(AppTypography.caption())
                                            .foregroundStyle(theme.muted)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle")
                                        .foregroundStyle(theme.accent)
                                }
                                .padding(.vertical, AppSpacing.sm)
                                .padding(.horizontal, AppLayout.pageMargin)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider()
                                .opacity(0.4)
                                .padding(.leading, AppLayout.pageMargin)
                        }
                    }
                }

                Spacer()

                Button {
                    Task { await discover() }
                } label: {
                    HStack {
                        if phase == .adding {
                            ProgressView().tint(Color(.systemBackground))
                        } else {
                            Text(phase == .select ? "返回搜索" : "查找 Feed")
                                .font(AppTypography.font(size: 16, weight: .semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: AppLayout.minTapTarget + 6)
                    .background(theme.text, in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                    .foregroundStyle(Color(.systemBackground))
                    .padding(.horizontal, AppLayout.pageMargin)
                    .padding(.bottom, AppSpacing.xl)
                }
                .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty || phase == .discovering || phase == .adding)
            }
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("添加订阅")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .alert("新建分组", isPresented: $showNewGroupAlert) {
                TextField("分组名称", text: $newGroupName)
                Button("创建") {
                    let name = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    store.addGroup(name: name)
                    if let g = store.groups.first(where: { $0.name == name }) {
                        selectedGroupKey = g.id.uuidString
                    }
                    newGroupName = ""
                }
                Button("取消", role: .cancel) { newGroupName = "" }
            } message: {
                Text("创建后将自动选中该分组")
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            isURLFocused = true
            // 打开添加页时默认未分组；无效残留选择也回退
            if selectedGroupKey != "none",
               UUID(uuidString: selectedGroupKey).map({ id in store.groups.contains(where: { $0.id == id }) }) != true {
                selectedGroupKey = "none"
            }
        }
    }

    private func discover() async {
        let raw = urlText.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return }
        errorMessage = nil
        discoveredFeeds = []
        phase = .discovering

        // rsshub://zaobao/realtime → https://rsshub.app/zaobao/realtime
        var urlStr = FeedURL.expandCustomSchemes(raw)
        if urlStr != raw {
            urlText = urlStr // 输入框同步为展开后的 https 地址
        }
        let lower = urlStr.lowercased()
        if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") {
            urlStr = "https://\(urlStr)"
        }
        guard let url = URL(string: urlStr) else {
            errorMessage = "无效的 URL"
            phase = .input
            return
        }

        do {
            let feeds = try await FeedDiscovery.discoverFeeds(from: url)
            if feeds.isEmpty {
                errorMessage = "未找到 Feed，请检查地址是否正确"
                phase = .input
            } else if feeds.count == 1 {
                await addFeed(feeds[0])
            } else {
                discoveredFeeds = feeds
                phase = .select
            }
        } catch {
            // Try parsing directly as feed
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let articles = FeedParser.parse(data: data, feedID: UUID(), feedTitle: "")
                if !articles.isEmpty {
                    let title = FeedNaming.resolveTitle(
                        parsed: FeedParser.extractFeedTitle(from: data),
                        url: urlStr
                    )
                    await addFeed(DiscoveredFeed(title: title, url: urlStr))
                } else {
                    errorMessage = "无法解析该地址的 Feed：\(error.localizedDescription)"
                    phase = .input
                }
            } catch {
                errorMessage = "网络错误：\(error.localizedDescription)"
                phase = .input
            }
        }
    }

    private func failAdd(_ message: String) {
        errorMessage = message
        // 有候选列表时回到选择，否则回输入
        phase = discoveredFeeds.isEmpty ? .input : .select
    }

    private func addFeed(_ discovered: DiscoveredFeed) async {
        phase = .adding
        errorMessage = nil
        guard let url = URL(string: discovered.url) else {
            failAdd("无效的 Feed URL")
            return
        }
        // 已存在则直接提示，不重复添加
        let canonical = FeedURL.canonical(discovered.url)
        if store.feeds.contains(where: { FeedURL.canonical($0.url) == canonical }) {
            failAdd("该订阅源已存在")
            return
        }
        do {
            let data: Data
            if RSSHubSupport.isRSSHubURL(url) {
                // RSSHub 官方站常被 Cloudflare 拦截：自动尝试公共镜像（订阅地址仍保留用户输入）
                do {
                    (data, _) = try await FeedDiscovery.fetchRSSHubFeed(from: url)
                } catch {
                    let ns = error as NSError
                    if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorNoPermissionsToReadFile {
                        failAdd("RSSHub 返回了验证页（Cloudflare），已尝试公共镜像仍失败，请稍后重试或更换实例")
                    } else {
                        failAdd("无法获取 RSSHub 源信息：\(error.localizedDescription)")
                    }
                    return
                }
            } else {
                var request = URLRequest(url: url, timeoutInterval: 20)
                request.setValue(
                    "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15",
                    forHTTPHeaderField: "User-Agent"
                )
                request.setValue(
                    "application/rss+xml, application/atom+xml, application/xml, text/xml, */*;q=0.8",
                    forHTTPHeaderField: "Accept"
                )
                let (body, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    failAdd("无法获取源信息（HTTP \(http.statusCode)）")
                    return
                }
                data = body
            }
            guard !data.isEmpty else {
                failAdd("无法获取源信息：返回内容为空")
                return
            }
            if RSSHubSupport.looksLikeCloudflareOrHTMLGate(data) {
                failAdd("源站返回了验证页，无法读取 Feed")
                return
            }

            let feedID = UUID()
            let fromXML = FeedParser.extractFeedTitle(from: data)
            let fallbackName = (discovered.title != discovered.url
                                && discovered.title != FeedNaming.domainName(from: discovered.url))
                ? discovered.title : nil
            let resolvedTitle = FeedNaming.resolveTitle(
                parsed: fromXML ?? fallbackName,
                url: discovered.url
            )
            let articles = FeedParser.parse(data: data, feedID: feedID, feedTitle: resolvedTitle)

            // 既无频道标题、又解析不出任何条目 → 视为获取失败，不添加
            let hasTitle = fromXML.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false
            let looksLikeFeed = Self.dataLooksLikeFeed(data) || RSSHubSupport.looksLikeFeedXML(data)
            if articles.isEmpty && !hasTitle {
                failAdd(looksLikeFeed
                        ? "该源暂无文章，且缺少标题信息，已取消添加"
                        : "无法解析为有效的 RSS/Atom 源，已取消添加")
                return
            }
            if articles.isEmpty && !looksLikeFeed {
                failAdd("无法解析为有效的 RSS/Atom 源，已取消添加")
                return
            }

            OfflineCache.saveFeedXML(url: discovered.url, data: data)
            let favicon = FeedParser.resolveFaviconURL(from: data, feedURL: discovered.url)
            let groupID = resolvedGroupID
            let sampleLinks = articles.prefix(8).map(\.link)
            let enableComments = CommentFetcher.shouldAutoEnableComments(
                feedURL: discovered.url,
                sampleArticleLinks: Array(sampleLinks)
            )
            let feed = RSSFeed(
                id: feedID,
                title: resolvedTitle,
                url: discovered.url,
                faviconURL: favicon,
                unreadCount: articles.count,
                articles: articles,
                lastFetched: Date(),
                groupID: groupID,
                fetchCommentsEnabled: enableComments,
                faviconFetchDone: false
            )
            store.addFeed(feed)
            dismiss()
        } catch {
            failAdd("无法获取源信息：\(error.localizedDescription)")
        }
    }

    /// 粗检：内容是否像 RSS / Atom
    private static func dataLooksLikeFeed(_ data: Data) -> Bool {
        guard let raw = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else { return false }
        let head = raw.prefix(4096).lowercased()
        if head.contains("<rss") || head.contains("<feed") || head.contains("<rdf:rdf") { return true }
        if head.contains("<channel") && (head.contains("<item") || head.contains("<title")) { return true }
        return false
    }
}
