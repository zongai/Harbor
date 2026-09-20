import SwiftUI
import SafariServices

/// 内置浏览器 sheet 的 item；id 随 URL 变化，换篇时可刷新页面
struct BrowserLink: Identifiable, Equatable {
    let url: URL
    var id: String { url.absoluteString }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        makeController(url: url)
    }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {
        // SFSafariViewController 不支持改 URL；由上层 .id(url) 触发整页重建
    }
    private func makeController(url: URL) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        let vc = SFSafariViewController(url: url, configuration: config)
        vc.preferredControlTintColor = .label
        return vc
    }
}

struct AISummaryCard: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let summary: String
    @Binding var expanded: Bool
    var fontSize: Double = 22
    var providerName: String? = nil
    private var points: [String] {
        summary.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if reduceMotion {
                    expanded.toggle()
                } else {
                    withAnimation(AppMotion.expand) { expanded.toggle() }
                }
            } label: {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.accent)
                    Text("AI 摘要")
                        .font(AppTypography.label())
                        .foregroundStyle(theme.text)
                    if let providerName, !providerName.isEmpty {
                        Text(providerName)
                            .font(AppTypography.caption())
                            .foregroundStyle(theme.muted)
                    }
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.muted)
                }
                .padding(.horizontal, AppSpacing.sm)
                .padding(.vertical, AppSpacing.sm)
            }
            .buttonStyle(.plain)
            if expanded {
                Divider().opacity(0.4)
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                        Text(point)
                            .font(AppTypography.font(size: fontSize, weight: .regular))
                            .foregroundStyle(theme.text)
                            .lineSpacing(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, AppSpacing.sm)
                .padding(.vertical, AppSpacing.md)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .fill(theme.surface.opacity(0.55))
        )
    }
}
