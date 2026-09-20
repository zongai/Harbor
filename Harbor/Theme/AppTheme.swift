import SwiftUI
import UIKit

// MARK: - Appearance (follow system / force light / force dark)

enum AppearanceMode: String, CaseIterable, Codable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - Hex helpers

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }

    init(hex string: String) {
        let hex = string.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Reading theme colors

struct ReadingThemeColors {
    let name: String
    let background: Color
    let cardBackground: Color
    let primaryText: Color
    let secondaryText: Color
    let accent: Color
    let accentSoft: Color
    let divider: Color
    let success: Color
}

// MARK: - 6 reading themes

enum ReadingTheme: String, CaseIterable, Codable, Identifiable {
    case classicLight
    case sepiaPaper
    case nightDark
    case midnightBlue
    case forestSage
    case highContrast

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classicLight: return "Classic 经典蓝白"
        case .sepiaPaper: return "Sepia 纸感"
        case .nightDark: return "Night 夜间"
        case .midnightBlue: return "Midnight 午夜蓝"
        case .forestSage: return "Forest 松绿"
        case .highContrast: return "高对比度"
        }
    }

    var subtitle: String {
        switch self {
        case .classicLight: return "清爽蓝白，默认日间"
        case .sepiaPaper: return "类 Kindle 米黄，长时间护眼"
        case .nightDark: return "近黑背景，OLED 友好"
        case .midnightBlue: return "低蓝光深蓝，适合夜读"
        case .forestSage: return "低饱和自然绿，缓解疲劳"
        case .highContrast: return "黑白高对比，无障碍（WCAG AAA）"
        }
    }

    var isDark: Bool {
        switch self {
        case .nightDark, .midnightBlue: return true
        default: return false
        }
    }

    static var preferredDark: ReadingTheme { .nightDark }
    static var preferredLight: ReadingTheme { .classicLight }

    /// 跟随系统外观时解析实际主题
    static func resolved(selected: ReadingTheme, appearance: AppearanceMode, systemScheme: ColorScheme) -> ReadingTheme {
        let effective: ColorScheme
        switch appearance {
        case .system: effective = systemScheme
        case .light: effective = .light
        case .dark: effective = .dark
        }
        if effective == .dark {
            return selected.isDark ? selected : .preferredDark
        } else {
            return selected.isDark ? .preferredLight : selected
        }
    }

    var colors: ReadingThemeColors {
        switch self {
        case .classicLight:
            return ReadingThemeColors(
                name: displayName,
                background: Color(hex: "F5F8FC"),
                cardBackground: Color(hex: "FFFFFF"),
                primaryText: Color(hex: "1A2B4C"),
                secondaryText: Color(hex: "6B7A99"),
                accent: Color(hex: "3B5BDB"),
                accentSoft: Color(hex: "DCE4FA"),
                divider: Color(hex: "E4E9F2"),
                success: Color(hex: "22C55E")
            )
        case .sepiaPaper:
            return ReadingThemeColors(
                name: displayName,
                background: Color(hex: "F7F1E3"),
                cardBackground: Color(hex: "FCF8ED"),
                primaryText: Color(hex: "3A2E1F"),
                secondaryText: Color(hex: "8A7A5C"),
                accent: Color(hex: "B5722F"),
                accentSoft: Color(hex: "EFE0C0"),
                divider: Color(hex: "E6D9B8"),
                success: Color(hex: "6B8E4E")
            )
        case .nightDark:
            return ReadingThemeColors(
                name: displayName,
                background: Color(hex: "0B0B0D"),
                cardBackground: Color(hex: "17171A"),
                primaryText: Color(hex: "EAEAEC"),
                secondaryText: Color(hex: "9A9AA2"),
                accent: Color(hex: "8B95F0"),
                accentSoft: Color(hex: "2A2A3A"),
                divider: Color(hex: "2A2A2E"),
                success: Color(hex: "4ADE80")
            )
        case .midnightBlue:
            return ReadingThemeColors(
                name: displayName,
                background: Color(hex: "0F1A2E"),
                cardBackground: Color(hex: "16233D"),
                primaryText: Color(hex: "DDE6F5"),
                secondaryText: Color(hex: "8595B8"),
                accent: Color(hex: "5B8DEF"),
                accentSoft: Color(hex: "1E2F52"),
                divider: Color(hex: "223252"),
                success: Color(hex: "5FD4A6")
            )
        case .forestSage:
            return ReadingThemeColors(
                name: displayName,
                background: Color(hex: "F1F4EC"),
                cardBackground: Color(hex: "FAFBF7"),
                primaryText: Color(hex: "2E3B2A"),
                secondaryText: Color(hex: "6E7C63"),
                accent: Color(hex: "5B7A52"),
                accentSoft: Color(hex: "DCE6D2"),
                divider: Color(hex: "DCE3D3"),
                success: Color(hex: "4E8E5F")
            )
        case .highContrast:
            return ReadingThemeColors(
                name: displayName,
                background: Color(hex: "FFFFFF"),
                cardBackground: Color(hex: "FFFFFF"),
                primaryText: Color(hex: "000000"),
                secondaryText: Color(hex: "333333"),
                accent: Color(hex: "0047AB"),
                accentSoft: Color(hex: "CFE0FF"),
                divider: Color(hex: "000000"),
                success: Color(hex: "006400")
            )
        }
    }

    var previewColors: [Color] {
        let c = colors
        return [c.accent, c.background, c.cardBackground, c.primaryText]
    }

    /// 兼容原有 ThemeTokens 管线
    var tokens: ThemeTokens {
        let c = colors
        return ThemeTokens(
            text: c.primaryText,
            muted: c.secondaryText,
            strong: c.primaryText,
            accent: c.accent,
            background: c.background,
            card: c.cardBackground,
            surface: c.accentSoft,
            track: c.divider,
            ring: c.accent.opacity(isDark ? 0.22 : 0.14),
            accentSoft: c.accentSoft,
            shadow: (isDark ? Color.black.opacity(0.4) : c.primaryText.opacity(0.08)),
            success: c.success
        )
    }
}

/// 兼容旧存储键名 AppColorTheme
typealias AppColorTheme = ReadingTheme

struct ThemeTokens {
    var text: Color
    var muted: Color
    var strong: Color
    var accent: Color
    var background: Color
    var card: Color
    var surface: Color
    var track: Color
    var ring: Color
    var accentSoft: Color
    var shadow: Color
    var success: Color
}

// MARK: - Environment

private struct ThemeTokensKey: EnvironmentKey {
    static let defaultValue = ReadingTheme.classicLight.tokens
}

private struct ReadingThemeColorsKey: EnvironmentKey {
    static let defaultValue = ReadingTheme.classicLight.colors
}

extension EnvironmentValues {
    var theme: ThemeTokens {
        get { self[ThemeTokensKey.self] }
        set { self[ThemeTokensKey.self] = newValue }
    }

    var readingTheme: ReadingThemeColors {
        get { self[ReadingThemeColorsKey.self] }
        set { self[ReadingThemeColorsKey.self] = newValue }
    }
}

// MARK: - Design Tokens (Editorial)

/// Spacing scale — prefer these over magic numbers.
enum AppSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    /// Between major sections (list groups, reader blocks)
    static let section: CGFloat = 28
    /// Comfortable paragraph gap in article body
    static let paragraph: CGFloat = 14
    /// Extra breathing room above/below hero / featured
    static let hero: CGFloat = 20
}

/// Corner radii — keep restrained; prefer continuous curves.
enum AppRadius {
    static let none: CGFloat = 0
    static let sm: CGFloat = 6
    static let md: CGFloat = 10
    static let lg: CGFloat = 14
    /// Default for soft surfaces (chips, small cards)
    static let continuous: CGFloat = 12
}

/// Layout constraints for reading & lists.
enum AppLayout {
    /// Max comfortable reading column width. Wider screens center content.
    static let readingMaxWidth: CGFloat = 680
    /// Horizontal padding for article body on phone
    static let readingHorizontalPadding: CGFloat = 22
    /// List / feed row horizontal inset
    static let listHorizontalPadding: CGFloat = 16
    /// General page margin
    static let pageMargin: CGFloat = 20
    /// Minimum touch target
    static let minTapTarget: CGFloat = 44
}

// MARK: - Motion (Phase 6 — restrained, accessibility-aware)

/// Shared animation tokens. Prefer these over ad-hoc springs.
enum AppMotion {
    /// Chrome show/hide, toolbar
    static let chrome: Animation = .easeInOut(duration: 0.2)
    /// List insert/remove, group collapse
    static let list: Animation = .snappy(duration: 0.22)
    /// Expand/collapse cards (AI summary)
    static let expand: Animation = .easeInOut(duration: 0.22)
    /// Progress bar / numeric labels
    static let progress: Animation = .easeOut(duration: 0.28)
    /// Button press feedback
    static let press: Animation = .easeOut(duration: 0.15)

    /// Returns nil when Reduce Motion is on.
    static func optional(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

// MARK: - Metrics & Soft chrome (compat + softened)

enum AppMetrics {
    static let pageMargin: CGFloat = AppLayout.pageMargin
    static let cardGroupSpacing: CGFloat = AppSpacing.lg
    static let innerSpacing: CGFloat = AppSpacing.sm
    /// Softened: was 20 — less “card stack” feel
    static let cardRadius: CGFloat = AppRadius.lg
    static let chipRadius: CGFloat = AppRadius.continuous
    static let rowRadius: CGFloat = AppRadius.lg
    static let iconButtonSize: CGFloat = 42
}

struct SoftCardBackground: ViewModifier {
    @Environment(\.theme) private var theme
    var radius: CGFloat = AppMetrics.cardRadius
    /// When false, no drop shadow (preferred for editorial surfaces)
    var elevated: Bool = false
    func body(content: Content) -> some View {
        content.background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(theme.card)
                .shadow(color: elevated ? theme.shadow : .clear, radius: elevated ? 8 : 0, x: 0, y: elevated ? 3 : 0)
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(theme.ring, lineWidth: 1)
                )
        )
    }
}

struct SoftIconButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var size: CGFloat = AppMetrics.iconButtonSize
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(minWidth: max(size, AppLayout.minTapTarget), minHeight: max(size, AppLayout.minTapTarget))
            .frame(width: size, height: size)
            .contentShape(Rectangle())
            .background(
                Circle().fill(theme.surface)
                    .shadow(color: theme.shadow, radius: configuration.isPressed ? 2 : 4, x: 0, y: configuration.isPressed ? 1 : 2)
                    .overlay(Circle().stroke(theme.ring, lineWidth: 1))
            )
            .scaleEffect((!reduceMotion && configuration.isPressed) ? 0.96 : 1)
            .animation(AppMotion.optional(AppMotion.press, reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

extension View {
    func softCard(radius: CGFloat = AppMetrics.cardRadius, elevated: Bool = false) -> some View {
        modifier(SoftCardBackground(radius: radius, elevated: elevated))
    }

    func appTitleStyle() -> some View {
        font(AppTypography.title()).tracking(AppTypography.titleTracking).lineSpacing(6)
    }

    func appSectionStyle() -> some View {
        font(AppTypography.section()).tracking(AppTypography.sectionTracking)
    }

    func appBodyStyle() -> some View {
        font(AppTypography.body()).tracking(AppTypography.bodyTracking).lineSpacing(3.5)
    }

    func appCaptionStyle() -> some View {
        font(AppTypography.caption()).tracking(0.2)
    }

    func appScreenBackground() -> some View {
        modifier(AppScreenBackground())
    }

    /// Form / settings chrome: hide default list background, use reading theme.
    func appFormChrome() -> some View {
        modifier(AppFormChrome())
    }

    /// Constrain content to a comfortable reading column and center on wide screens.
    func readingColumn(maxWidth: CGFloat = AppLayout.readingMaxWidth) -> some View {
        frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }
}

private struct AppFormChrome: ViewModifier {
    @Environment(\.theme) private var theme
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(theme.background.ignoresSafeArea())
    }
}

private struct AppScreenBackground: ViewModifier {
    @Environment(\.theme) private var theme
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(theme.background.ignoresSafeArea())
    }
}

// MARK: - Theme picker

struct ThemePalettePicker: View {
    @Binding var selection: ReadingTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(ReadingTheme.allCases) { theme in
                Button {
                    selection = theme
                } label: {
                    HStack(spacing: 14) {
                        HStack(spacing: 4) {
                            ForEach(0..<theme.previewColors.count, id: \.self) { i in
                                Circle()
                                    .fill(theme.previewColors[i])
                                    .frame(width: 16, height: 16)
                                    .overlay(Circle().stroke(Color.black.opacity(0.06), lineWidth: 0.5))
                            }
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(theme.displayName)
                                .font(AppTypography.label())
                            Text(theme.subtitle)
                                .font(AppTypography.caption())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selection == theme {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(theme.colors.accent)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: AppMetrics.rowRadius, style: .continuous)
                            .fill(selection == theme ? theme.colors.accentSoft : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}


// MARK: - Font family

enum AppFontFamily: String, CaseIterable, Codable, Identifiable {
    case system
    case pingFangSC
    case songti
    case heiti

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "系统默认"
        case .pingFangSC: return "苹方"
        case .songti: return "宋体"
        case .heiti: return "黑体"
        }
    }

    var subtitle: String {
        switch self {
        case .system: return "跟随 iOS 系统字体（SF Pro）"
        case .pingFangSC: return "系统中文字体 PingFang SC"
        case .songti: return "宋体，偏印刷感"
        case .heiti: return "黑体，端庄醒目"
        }
    }
}

// MARK: - Typography (Source Han Sans / system families)

enum AppTypography {
    // —— Semantic sizes (editorial hierarchy) ——
    static func greeting() -> Font { font(size: 26, weight: .semibold) }
    static func title() -> Font { font(size: 22, weight: .semibold) }
    static func section() -> Font { font(size: 19, weight: .semibold) }
    static func body() -> Font { font(size: 14.5, weight: .regular) }
    static func bodyLarge() -> Font { font(size: 16, weight: .regular) }
    static func caption() -> Font { font(size: 12.5, weight: .regular) }
    static func label() -> Font { font(size: 13, weight: .medium) }

    // —— Article reader hierarchy (prefer these in Phase 2+) ——
    /// Large article title in reader
    static func articleTitle(size: CGFloat = 26) -> Font { font(size: size, weight: .bold) }
    /// Subtitle / dek under title
    static func articleSubtitle(size: CGFloat = 16) -> Font { font(size: size, weight: .regular) }
    /// Author · date · reading time
    static func articleMeta(size: CGFloat = 13) -> Font { font(size: size, weight: .medium) }
    /// Body paragraph
    static func articleBody(size: CGFloat = 17) -> Font { font(size: size, weight: .regular) }
    /// Category / section label above title
    static func articleCategory(size: CGFloat = 12) -> Font { font(size: size, weight: .semibold) }
    /// List row title
    static func listTitle(size: CGFloat = 17) -> Font { font(size: size, weight: .semibold) }
    /// List row summary
    static func listSummary(size: CGFloat = 14) -> Font { font(size: size, weight: .regular) }

    /// 当前选用的字体家族（由设置写入 UserDefaults）
    static var family: AppFontFamily {
        if let raw = UserDefaults.standard.string(forKey: "appFontFamily"),
           let f = AppFontFamily(rawValue: raw) {
            return f
        }
        return .system
    }

    /// Scale a design size with Dynamic Type (body metrics by default).
    static func scaled(_ size: CGFloat, textStyle: UIFont.TextStyle = .body) -> CGFloat {
        UIFontMetrics(forTextStyle: textStyle).scaledValue(for: size)
    }

    static func font(size: CGFloat, weight: Font.Weight, textStyle: UIFont.TextStyle = .body) -> Font {
        font(size: scaled(size, textStyle: textStyle), weight: weight, family: family)
    }

    static func font(size: CGFloat, weight: Font.Weight, family: AppFontFamily, textStyle: UIFont.TextStyle = .body) -> Font {
        let resolved = scaled(size, textStyle: textStyle)
        switch family {
        case .system:
            return .system(size: resolved, weight: weight)
        case .pingFangSC:
            let name: String
            switch weight {
            case .bold, .heavy, .black, .semibold: name = "PingFangSC-Semibold"
            case .medium: name = "PingFangSC-Medium"
            default: name = "PingFangSC-Regular"
            }
            return UIFont(name: name, size: resolved) != nil ? .custom(name, size: resolved) : .system(size: resolved, weight: weight)
        case .songti:
            let name = "STSongti-SC-Regular"
            return UIFont(name: name, size: resolved) != nil ? .custom(name, size: resolved) : .system(size: resolved, weight: weight, design: .serif)
        case .heiti:
            let name: String
            switch weight {
            case .bold, .heavy, .black, .semibold: name = "STHeitiSC-Medium"
            default: name = "STHeitiSC-Light"
            }
            return UIFont(name: name, size: resolved) != nil ? .custom(name, size: resolved) : .system(size: resolved, weight: weight)
        }
    }

    static let titleTracking: CGFloat = -0.8
    static let sectionTracking: CGFloat = 0.6
    static let bodyTracking: CGFloat = 0.3
    /// Tighter tracking for large display titles
    static let displayTracking: CGFloat = -1.1
}
