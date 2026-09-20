import SwiftUI

struct ArticleCommentsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let articleTitle: String
    let articleURL: String
    var commentsURL: String? = nil

    @State private var comments: [WebComment] = []
    @State private var isLoading = true
    @State private var errorText: String?
    @State private var showTranslated = false
    @State private var isTranslating = false

    private var commentCountLabel: String {
        let n = comments.count
        if n == 0 { return "暂无评论" }
        return "\(n) 条评论"
    }

    var body: some View {
        Group {
            if isLoading {
                loadingState
            } else if let errorText {
                errorState(errorText)
            } else if comments.isEmpty {
                emptyState
            } else {
                commentsList
            }
        }
        .background(theme.background)
        .navigationTitle("评论")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !comments.isEmpty {
                    Button {
                        Task { await toggleTranslation() }
                    } label: {
                        if isTranslating {
                            ProgressView()
                        } else {
                            Label(showTranslated ? "原文" : "翻译", systemImage: "translate")
                        }
                    }
                    .labelStyle(.iconOnly)
                    .disabled(isTranslating)
                    .accessibilityLabel(showTranslated ? "显示原文" : "翻译评论")
                }
                Button {
                    Task { await load(force: true) }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .labelStyle(.iconOnly)
                .disabled(isLoading)
                .accessibilityLabel("刷新评论")
            }
        }
        .task { await load(force: false) }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: AppSpacing.md) {
            ProgressView()
            Text("正在加载评论…")
                .font(AppTypography.caption())
                .foregroundStyle(theme.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background.opacity(0.92))
    }

    private func errorState(_ message: String) -> some View {
        ContentUnavailableView {
            Label("无法加载评论", systemImage: "bubble.left.and.bubble.right")
        } description: {
            Text(message)
                .font(AppTypography.body())
                .foregroundStyle(theme.muted)
        } actions: {
            Button("重试") {
                Task { await load(force: true) }
            }
            .buttonStyle(.bordered)
            .tint(theme.accent)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("暂无评论", systemImage: "bubble.left")
        } description: {
            Text("原文页面尚未有公开评论")
                .font(AppTypography.body())
                .foregroundStyle(theme.muted)
        } actions: {
            Button("刷新") {
                Task { await load(force: true) }
            }
            .buttonStyle(.bordered)
            .tint(theme.accent)
        }
    }

    // MARK: - List

    private var commentsList: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(articleTitle)
                        .font(AppTypography.label())
                        .foregroundStyle(theme.text)
                        .lineLimit(2)
                    Text(commentCountLabel)
                        .font(AppTypography.caption())
                        .foregroundStyle(theme.muted)
                }
                .padding(.vertical, AppSpacing.xxs)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(
                    top: AppSpacing.md,
                    leading: AppLayout.listHorizontalPadding,
                    bottom: AppSpacing.sm,
                    trailing: AppLayout.listHorizontalPadding
                ))
            }

            Section {
                ForEach(Array(comments.enumerated()), id: \.element.id) { index, c in
                    commentRow(c)
                        .listRowInsets(EdgeInsets(
                            top: AppSpacing.sm,
                            leading: AppLayout.listHorizontalPadding,
                            bottom: AppSpacing.sm,
                            trailing: AppLayout.listHorizontalPadding
                        ))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .overlay(alignment: .bottom) {
                            if index < comments.count - 1 {
                                Divider()
                                    .opacity(0.35)
                                    .padding(.leading, CGFloat(min(c.depth, 6)) * AppSpacing.sm)
                            }
                        }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(theme.background)
    }

    private func commentRow(_ c: WebComment) -> some View {
        let depth = min(c.depth, 6)
        return HStack(alignment: .top, spacing: 0) {
            if depth > 0 {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(theme.accent.opacity(0.22))
                    .frame(width: 2)
                    .padding(.trailing, AppSpacing.sm)
                    .padding(.vertical, 2)
            }

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
                    Text(c.author)
                        .font(AppTypography.label())
                        .fontWeight(.semibold)
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                    if let d = c.date {
                        Text("·")
                            .foregroundStyle(theme.muted.opacity(0.45))
                        Text(Self.relativeDate(d))
                            .font(AppTypography.caption())
                            .foregroundStyle(theme.muted)
                    }
                    Spacer(minLength: 0)
                }

                Text(displayBody(c))
                    .font(AppTypography.bodyLarge())
                    .foregroundStyle(theme.text)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.leading, CGFloat(depth) * AppSpacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: c))
    }

    private func accessibilityLabel(for c: WebComment) -> String {
        var parts = [c.author]
        if let d = c.date {
            parts.append(Self.relativeDate(d))
        }
        parts.append(displayBody(c))
        return parts.joined(separator: "，")
    }

    // MARK: - Data

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
            withAnimation(AppMotion.optional(.easeInOut(duration: 0.2), reduceMotion: reduceMotion)) {
                showTranslated = false
            }
            return
        }
        let needIdx = comments.indices.filter {
            let t = comments[$0].translatedBody?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return t.isEmpty
        }
        if needIdx.isEmpty {
            withAnimation(AppMotion.optional(.easeInOut(duration: 0.2), reduceMotion: reduceMotion)) {
                showTranslated = true
            }
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
        withAnimation(AppMotion.optional(.easeInOut(duration: 0.2), reduceMotion: reduceMotion)) {
            showTranslated = true
        }
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
