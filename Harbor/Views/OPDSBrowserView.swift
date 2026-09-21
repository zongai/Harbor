import SwiftUI

/// OPDS 书库浏览与 EPUB 下载入架
struct OPDSBrowserView: View {
    @Environment(BookLibrary.self) private var library
    @Environment(\.theme) private var theme

    let rootTitle: String
    let rootURL: String

    @State private var path: [String] = []
    @State private var feed: OPDSFeed?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var downloadProgress: Double?
    @State private var downloadingID: String?
    @State private var statusMessage: String?
    @State private var downloadTask: Task<Void, Never>?

    private var currentURL: String {
        path.last ?? rootURL
    }

    var body: some View {
        Group {
            if isLoading && feed == nil {
                ProgressView("加载书库…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, feed == nil {
                ContentUnavailableView {
                    Label("加载失败", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("重试") { Task { await load(url: currentURL) } }
                }
            } else {
                List {
                    if let statusMessage {
                        Text(statusMessage)
                            .font(AppTypography.caption())
                            .foregroundStyle(theme.muted)
                            .listRowBackground(Color.clear)
                    }
                    if let downloadProgress {
                        ProgressView(value: downloadProgress)
                            .listRowBackground(Color.clear)
                    }
                    ForEach(feed?.entries ?? []) { entry in
                        entryRow(entry)
                    }
                    if let next = feed?.nextURL {
                        Button("加载更多") {
                            Task { await load(url: next, append: true) }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .appScreenBackground()
        .navigationTitle(feed?.title ?? rootTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load(url: rootURL) }
        .onDisappear {
            downloadTask?.cancel()
        }
    }

    @ViewBuilder
    private func entryRow(_ entry: OPDSEntry) -> some View {
        if entry.isNavigation, let nav = entry.navigationURL {
            NavigationLink(entry.title) {
                OPDSBrowserView(rootTitle: entry.title, rootURL: nav)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.title)
                    .font(AppTypography.listTitle())
                    .foregroundStyle(theme.text)
                if !entry.authors.isEmpty {
                    Text(entry.authors.joined(separator: " · "))
                        .font(AppTypography.caption())
                        .foregroundStyle(theme.muted)
                }
                if let summary = entry.summary, !summary.isEmpty {
                    Text(summary)
                        .font(AppTypography.caption())
                        .foregroundStyle(theme.muted)
                        .lineLimit(3)
                }
                HStack {
                    if entry.preferredEPUBURL != nil {
                        Button {
                            startDownload(entry)
                        } label: {
                            if downloadingID == entry.id {
                                Label("下载中…", systemImage: "arrow.down.circle")
                            } else {
                                Label("下载 EPUB", systemImage: "arrow.down.circle")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(downloadingID != nil)
                    }
                    if let lang = entry.language {
                        Text(lang)
                            .font(AppTypography.caption())
                            .foregroundStyle(theme.muted)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func load(url: String, append: Bool = false) async {
        isLoading = true
        errorMessage = nil
        do {
            let f = try await OPDSClient.fetchFeed(from: url)
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
        // 避免重复：同名已在书架
        if library.books.contains(where: { $0.title == entry.title }) {
            statusMessage = "书架中可能已有「\(entry.title)」，继续将再导入一本"
        }
        downloadingID = entry.id
        downloadProgress = 0
        statusMessage = "正在下载…"
        downloadTask?.cancel()
        downloadTask = Task {
            do {
                let file = try await OPDSClient.downloadEPUB(from: href, progress: { p in
                    Task { @MainActor in
                        downloadProgress = p
                    }
                }, isCancelled: { Task.isCancelled })
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
            downloadProgress = nil
        }
    }
}

/// 添加 OPDS 书库
struct AddOPDSCatalogView: View {
    @Environment(OPDSCatalogStore.self) private var catalogs
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    @State private var title = ""
    @State private var url = ""
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
                Text("示例：公开 OPDS 书库的 Atom 目录地址。")
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
        do {
            let feed = try await OPDSClient.fetchFeed(from: u)
            let name = title.isEmpty ? feed.title : title
            catalogs.add(title: name, url: u)
            testMessage = "已添加：\(feed.title)（\(feed.entries.count) 条）"
            dismiss()
        } catch {
            testMessage = error.localizedDescription
        }
        testing = false
    }
}
