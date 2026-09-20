import SwiftUI

struct ArticleCommentsView: View {
    @Environment(AppStore.self) private var store
    let articleTitle: String
    let articleURL: String
    var commentsURL: String? = nil

    @State private var comments: [WebComment] = []
    @State private var isLoading = true
    @State private var errorText: String?
    @State private var showTranslated = false
    @State private var isTranslating = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView("正在加载评论…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorText {
                ContentUnavailableView(
                    "无法加载评论",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text(errorText)
                )
            } else if comments.isEmpty {
                ContentUnavailableView(
                    "暂无评论",
                    systemImage: "bubble.left",
                    description: Text("原文页面尚未有公开评论")
                )
            } else {
                List {
                    ForEach(comments) { c in
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            HStack(spacing: AppSpacing.xs) {
                                Text(c.author)
                                    .font(AppTypography.label())
                                    .foregroundStyle(Color.primary)
                                if let d = c.date {
                                    Text(Self.relativeDate(d))
                                        .font(AppTypography.caption())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            Text(displayBody(c))
                                .font(AppTypography.bodyLarge())
                                .foregroundStyle(Color.primary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.leading, CGFloat(min(c.depth, 6)) * AppSpacing.sm)
                        .listRowInsets(EdgeInsets(
                            top: AppSpacing.sm,
                            leading: AppLayout.listHorizontalPadding,
                            bottom: AppSpacing.sm,
                            trailing: AppLayout.listHorizontalPadding
                        ))
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .appScreenBackground()
            }
        }
        .navigationTitle("评论")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !comments.isEmpty {
                    Button {
                        Task { await toggleTranslation() }
                    } label: {
                        if isTranslating {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Label(showTranslated ? "原文" : "翻译", systemImage: "translate")
                        }
                    }
                    .labelStyle(.iconOnly)
                    .disabled(isTranslating)
                }
                Button {
                    Task { await load(force: true) }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .labelStyle(.iconOnly)
                .disabled(isLoading)
            }
        }
        .task { await load(force: false) }
    }

    private func displayBody(_ c: WebComment) -> String {
        if showTranslated, let t = c.translatedBody, !t.isEmpty { return t }
        return c.body
    }

    private func load(force: Bool) async {
        if !force, !comments.isEmpty { return }
        isLoading = true
        errorText = nil
        showTranslated = false
        defer { isLoading = false }
        do {
            comments = try await CommentFetcher.fetchComments(from: articleURL, commentsURL: commentsURL)
        } catch {
            comments = []
            errorText = error.localizedDescription
        }
    }

    private func toggleTranslation() async {
        if showTranslated {
            showTranslated = false
            return
        }
        let needIdx = comments.indices.filter {
            let t = comments[$0].translatedBody?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return t.isEmpty
        }
        if needIdx.isEmpty {
            showTranslated = true
            return
        }
        isTranslating = true
        defer { isTranslating = false }
        let texts = needIdx.map { comments[$0].body }
        let results = await store.translateTexts(texts, concurrency: 3)
        for (i, idx) in needIdx.enumerated() where i < results.count {
            if let r = results[i], !r.isEmpty {
                comments[idx].translatedBody = r
            }
        }
        showTranslated = true
    }

    private static func relativeDate(_ date: Date) -> String {
        let diff = Date().timeIntervalSince(date)
        if diff < 60 { return "刚刚" }
        if diff < 3600 { return "\(Int(diff / 60)) 分钟前" }
        if diff < 86400 { return "\(Int(diff / 3600)) 小时前" }
        if diff < 86400 * 7 { return "\(Int(diff / 86400)) 天前" }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }
}
