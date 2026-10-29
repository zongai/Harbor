import SwiftUI
import UIKit

/// OPDS 书库浏览：瀑布流海报封面
struct OPDSBrowserView: View {
    @Environment(BookLibrary.self) private var library
    @Environment(\.theme) private var theme

    let rootTitle: String
    let rootURL: String
    var username: String? = nil
    var password: String? = nil

    @State private var feed: OPDSFeed?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var path: [String] = []
    @State private var downloadingID: String?
    @State private var downloadProgress: Double = 0
    @State private var statusMessage: String?
    @State private var downloadTask: Task<Void, Never>?
    /// 默认只显示尚未加入本地书架的书（按标题粗匹配）
    @State private var showOnlyNotInLibrary: Bool = true

    private var navigationEntries: [OPDSEntry] {
        (feed?.entries ?? []).filter(\.isNavigation)
    }

    private var allPublications: [OPDSEntry] {
        (feed?.entries ?? []).filter { !$0.isNavigation }
    }

    private var libraryTitleKeys: Set<String> {
        Set(library.books.map { Self.normalizeTitle($0.title) })
    }

    private var publicationEntries: [OPDSEntry] {
        let all = allPublications
        guard showOnlyNotInLibrary else { return all }
        return all.filter { !libraryTitleKeys.contains(Self.normalizeTitle($0.title)) }
    }

    private static func normalizeTitle(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\s+", with: " ", options: .regularExpression)
    }

    var body: some View {
        Group {
            if isLoading && feed == nil {
                ProgressView("加载中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, feed == nil {
                ContentUnavailableView {
                    Label("加载失败", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("重试") {
                        Task { await load(url: rootURL) }
                    }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        if let statusMessage {
                            Text(statusMessage)
                                .font(AppTypography.caption())
                                .foregroundStyle(theme.muted)
                                .padding(.horizontal, AppSpacing.md)
                        }

                        if downloadingID != nil {
                            ProgressView(value: downloadProgress)
                                .padding(.horizontal, AppSpacing.md)
                        }

                        if !navigationEntries.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(navigationEntries) { entry in
                                        if let nav = entry.navigationURL {
                                            NavigationLink {
                                                OPDSBrowserView(
                                                    rootTitle: entry.title,
                                                    rootURL: nav,
                                                    username: username,
                                                    password: password
                                                )
                                            } label: {
                                                Text(entry.title)
                                                    .font(AppTypography.caption())
                                                    .foregroundStyle(theme.text)
                                                    .padding(.horizontal, 12)
                                                    .padding(.vertical, 8)
                                                    .background(theme.card, in: Capsule())
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                                .padding(.horizontal, AppSpacing.md)
                            }
                        }

                        if allPublications.isEmpty && navigationEntries.isEmpty && feed != nil {
                            Text("此目录暂无条目")
                                .font(AppTypography.body())
                                .foregroundStyle(theme.muted)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        } else if publicationEntries.isEmpty && !allPublications.isEmpty {
                            VStack(spacing: 10) {
                                Text(showOnlyNotInLibrary ? "没有未入库的书籍" : "暂无条目")
                                    .font(AppTypography.body())
                                    .foregroundStyle(theme.muted)
                                if showOnlyNotInLibrary {
                                    Button("显示全部书籍") { showOnlyNotInLibrary = false }
                                        .font(AppTypography.caption())
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                        } else if !publicationEntries.isEmpty {
                            WaterfallGrid(items: publicationEntries, columns: 2, spacing: 10) { entry in
                                OPDSPosterCard(
                                    entry: entry,
                                    username: username,
                                    password: password,
                                    isDownloading: downloadingID == entry.id,
                                    downloadProgress: downloadingID == entry.id ? downloadProgress : nil,
                                    alreadyInLibrary: libraryTitleKeys.contains(Self.normalizeTitle(entry.title)),
                                    onDownload: { startDownload(entry) }
                                )
                            }
                            .padding(.horizontal, AppSpacing.md)
                        }

                        if let next = feed?.nextURL {
                            Button {
                                Task { await load(url: next, append: true) }
                            } label: {
                                if isLoading {
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                } else {
                                    Text("加载更多")
                                        .font(AppTypography.body())
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                }
                            }
                            .buttonStyle(.bordered)
                            .padding(.horizontal, AppSpacing.md)
                            .padding(.bottom, AppSpacing.lg)
                            .disabled(isLoading)
                        }
                    }
                    .padding(.vertical, AppSpacing.sm)
                }
            }
        }
        .appScreenBackground()
        .navigationTitle(feed?.title ?? rootTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showOnlyNotInLibrary.toggle()
                } label: {
                    Text(showOnlyNotInLibrary ? "未入库" : "全部")
                        .font(AppTypography.caption())
                }
                .accessibilityLabel(showOnlyNotInLibrary ? "当前仅显示未入库，点按显示全部" : "当前显示全部，点按仅未入库")
            }
        }
        .task { await load(url: rootURL) }
        .onDisappear { downloadTask?.cancel() }
    }

    private func load(url: String, append: Bool = false) async {
        isLoading = true
        errorMessage = nil
        do {
            let f = try await OPDSClient.fetchFeed(
                from: url,
                username: username,
                password: password
            )
            if append, var existing = feed {
                existing.entries.append(contentsOf: f.entries)
                existing.nextURL = f.nextURL
                feed = existing
            } else {
                feed = f
            }
            if !append {
                if path.last != url, url != rootURL {
                    path.append(url)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func startDownload(_ entry: OPDSEntry) {
        guard let href = entry.preferredEPUBURL else {
            statusMessage = OPDSError.noEPUB.localizedDescription
            return
        }
        if library.books.contains(where: { $0.title == entry.title }) {
            statusMessage = "书架中可能已有「\(entry.title)」，继续将再导入一本"
        }
        downloadingID = entry.id
        downloadProgress = 0
        statusMessage = "正在下载…"
        downloadTask?.cancel()
        downloadTask = Task {
            do {
                let file = try await OPDSClient.downloadEPUB(
                    from: href,
                    username: username,
                    password: password,
                    progress: { p in
                        Task { @MainActor in
                            downloadProgress = p
                        }
                    },
                    isCancelled: { Task.isCancelled }
                )
                statusMessage = "正在导入书架…"
                _ = try await library.importEPUB(from: file)
                try? FileManager.default.removeItem(at: file)
                statusMessage = "已加入书架：\(entry.title)"
            } catch is CancellationError {
                statusMessage = "已取消"
            } catch {
                statusMessage = error.localizedDescription
            }
            downloadingID = nil
            downloadProgress = 0
        }
    }
}

// MARK: - Waterfall

private struct WaterfallGrid<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let columns: Int
    let spacing: CGFloat
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(0..<columns, id: \.self) { col in
                LazyVStack(spacing: spacing) {
                    ForEach(itemsForColumn(col)) { item in
                        content(item)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    private func itemsForColumn(_ col: Int) -> [Item] {
        items.enumerated().compactMap { $0.offset % columns == col ? $0.element : nil }
    }
}

// MARK: - Poster card

private struct OPDSPosterCard: View {
    @Environment(\.theme) private var theme
    let entry: OPDSEntry
    var username: String?
    var password: String?
    var isDownloading: Bool
    var downloadProgress: Double?
    var alreadyInLibrary: Bool = false
    var onDownload: () -> Void

    var body: some View {
        Button(action: onDownload) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .bottom) {
                    OPDSCoverImage(
                        urlString: entry.coverURL,
                        username: username,
                        password: password
                    )
                    .aspectRatio(2 / 3, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipped()

                    LinearGradient(
                        colors: [.clear, .black.opacity(0.75)],
                        startPoint: .center,
                        endPoint: .bottom
                    )

                    if alreadyInLibrary {
                        Text("已入库")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.55), in: Capsule())
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(8)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title)
                            .font(AppTypography.font(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        if !entry.authors.isEmpty {
                            Text(entry.authors.joined(separator: " · "))
                                .font(AppTypography.caption())
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1)
                        }
                        if isDownloading, let downloadProgress {
                            ProgressView(value: min(1, max(0, downloadProgress)))
                                .tint(.white)
                                .scaleEffect(x: 1, y: 0.7, anchor: .center)
                                .padding(.top, 2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                }
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 6, y: 3)

                if let summary = entry.summary, !summary.isEmpty {
                    Text(summary)
                        .font(AppTypography.caption())
                        .foregroundStyle(theme.muted)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }

                if entry.preferredEPUBURL != nil {
                    Label(isDownloading ? "下载中…" : "获取 EPUB", systemImage: "arrow.down.circle")
                        .font(AppTypography.caption())
                        .foregroundStyle(theme.accent)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isDownloading)
        .accessibilityLabel(entry.title)
        .accessibilityHint(entry.preferredEPUBURL != nil ? "下载并导入书架" : "无 EPUB")
    }

}

/// 支持可选 Basic 认证的封面图
private struct OPDSCoverImage: View {
    @Environment(\.theme) private var theme
    let urlString: String?
    var username: String?
    var password: String?

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if failed || urlString == nil {
                ZStack {
                    LinearGradient(
                        colors: [theme.card, theme.card.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    VStack(spacing: 6) {
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(theme.muted)
                        Text("暂无封面")
                            .font(AppTypography.caption())
                            .foregroundStyle(theme.muted)
                    }
                }
            } else {
                ZStack {
                    theme.card
                    ProgressView()
                }
            }
        }
        .task(id: urlString) {
            await load()
        }
    }

    private func load() async {
        guard let urlString, let url = URL(string: urlString) else {
            failed = true
            return
        }
        failed = false
        image = nil
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        if let username, !username.isEmpty {
            let userPass = "\(username):\(password ?? "")"
            if let data = userPass.data(using: .utf8) {
                request.setValue("Basic \(data.base64EncodedString())", forHTTPHeaderField: "Authorization")
            }
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                failed = true
                return
            }
            if let ui = UIImage(data: data) {
                image = ui
            } else {
                failed = true
            }
        } catch {
            failed = true
        }
    }
}

struct AddOPDSCatalogView: View {
    @Environment(OPDSCatalogStore.self) private var catalogs
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    @State private var title = ""
    @State private var url = ""
    @State private var username = ""
    @State private var password = ""
    @State private var testing = false
    @State private var testMessage: String?

    var body: some View {
        Form {
            Section {
                TextField("名称（可选）", text: $title)
                TextField("OPDS URL", text: $url)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            } footer: {
                Text("支持 http:// 与 https://。示例：http://192.168.1.10:8080/opds 或 https://example.com/opds")
            }
            Section {
                TextField("用户名（可选）", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("密码（可选）", text: $password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } footer: {
                Text("使用 HTTP Basic 认证。密码保存在系统钥匙串，不会写入书库列表文件。")
            }
            if let testMessage {
                Section {
                    Text(testMessage)
                        .font(AppTypography.caption())
                        .foregroundStyle(theme.muted)
                }
            }
            Section {
                Button {
                    Task { await testAndSave() }
                } label: {
                    if testing {
                        ProgressView()
                    } else {
                        Text("验证并添加")
                    }
                }
                .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || testing)
            }
        }
        .navigationTitle("添加 OPDS")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func testAndSave() async {
        testing = true
        testMessage = nil
        let u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let pass = password
        do {
            let feed = try await OPDSClient.fetchFeed(
                from: u,
                username: user.isEmpty ? nil : user,
                password: user.isEmpty ? nil : pass
            )
            let name = title.isEmpty ? feed.title : title
            if let err = catalogs.add(
                title: name,
                url: u,
                username: user.isEmpty ? nil : user,
                password: user.isEmpty ? nil : pass
            ) {
                testMessage = err
            } else {
                testMessage = "已添加：\(feed.title)（\(feed.entries.count) 条）"
                dismiss()
            }
        } catch {
            testMessage = error.localizedDescription
        }
        testing = false
    }
}
