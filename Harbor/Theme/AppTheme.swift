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

    /// 主题本身偏深（选中后不论系统如何都偏暗阅读）
    var prefersDarkChrome: Bool {
        switch self {
        case .nightDark, .midnightBlue: return true
        default: return false
        }
    }

    /// 兼容旧调用：是否按深色阅读表面渲染
    var isDark: Bool { prefersDarkChrome }

    static var preferredDark: ReadingTheme { .nightDark }
    static var preferredLight: ReadingTheme { .classicLight }

    /// 外观模式 → 实际 ColorScheme（不再偷偷替换用户选的阅读主题）
    static func effectiveColorScheme(appearance: AppearanceMode, systemScheme: ColorScheme) -> ColorScheme {
        switch appearance {
        case .system: return systemScheme
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// 解析用于渲染的主题：始终尊重用户选择的阅读主题（Forest 不会再被换成 Night）
    static func resolved(selected: ReadingTheme, appearance: AppearanceMode, systemScheme: ColorScheme) -> ReadingTheme {
        _ = appearance
        _ = systemScheme
        return selected
    }

    /// 该主题在指定 scheme 下的色板（浅色主题在深色模式下使用同系深色变体）
    func colors(for scheme: ColorScheme) -> ReadingThemeColors {
        // 夜间 / 午夜蓝始终深色表面；其余主题随 scheme 切换同系浅/深变体
        let useDark = prefersDarkChrome || scheme == .dark
        switch self {
        case .classicLight:
            return useDark ? Self.classicDarkColors : Self.classicLightColors
        case .sepiaPaper:
            return useDark ? Self.sepiaDarkColors : Self.sepiaLightColors
        case .nightDark:
            return Self.nightColors
        case .midnightBlue:
            return Self.midnightColors
        case .forestSage:
            return useDark ? Self.forestDarkColors : Self.forestLightColors
        case .highContrast:
            return useDark ? Self.highContrastDarkColors : Self.highContrastLightColors
        }
    }

    /// 默认浅色预览 / 兼容旧 API
    var colors: ReadingThemeColors {
        colors(for: prefersDarkChrome ? .dark : .light)
    }

    var previewColors: [Color] {
        let c = colors
        return [c.accent, c.background, c.cardBackground, c.primaryText]
    }

    func tokens(for scheme: ColorScheme) -> ThemeTokens {
        let c = colors(for: scheme)
        let darkSurface = (scheme == .dark) || prefersDarkChrome
        return ThemeTokens(
            text: c.primaryText,
            muted: c.secondaryText,
            strong: c.primaryText,
            accent: c.accent,
            background: c.background,
            card: c.cardBackground,
            surface: c.accentSoft,
            track: c.divider,
            ring: c.accent.opacity(darkSurface ? 0.28 : 0.14),
            accentSoft: c.accentSoft,
            shadow: (darkSurface ? Color.black.opacity(0.45) : c.primaryText.opacity(0.07)),
            success: c.success
        )
    }

    /// 兼容原有 ThemeTokens 管线
    var tokens: ThemeTokens {
        tokens(for: prefersDarkChrome ? .dark : .light)
    }

    // MARK: Refined palettes

    /// 经典蓝白：略暖纸白 + 靛蓝强调，正文对比更稳
    private static let classicLightColors = ReadingThemeColors(
        name: "Classic 经典蓝白",
        background: Color(hex: "F3F6FB"),
        cardBackground: Color(hex: "FFFFFF"),
        primaryText: Color(hex: "15233A"),
        secondaryText: Color(hex: "5C6B86"),
        accent: Color(hex: "3A5FCD"),
        accentSoft: Color(hex: "E4EAFB"),
        divider: Color(hex: "E2E8F2"),
        success: Color(hex: "2F9B5B")
    )

    private static let classicDarkColors = ReadingThemeColors(
        name: "Classic 经典蓝白",
        background: Color(hex: "0E1219"),
        cardBackground: Color(hex: "171C26"),
        primaryText: Color(hex: "E6EBF4"),
        secondaryText: Color(hex: "8B97AD"),
        accent: Color(hex: "7B93F0"),
        accentSoft: Color(hex: "222A3C"),
        divider: Color(hex: "2A3140"),
        success: Color(hex: "4ABA78")
    )

    /// 纸感：偏暖象牙，强调赭石，长时间阅读少刺眼
    private static let sepiaLightColors = ReadingThemeColors(
        name: "Sepia 纸感",
        background: Color(hex: "F6F0E4"),
        cardBackground: Color(hex: "FBF6EB"),
        primaryText: Color(hex: "3D2F1E"),
        secondaryText: Color(hex: "8A7860"),
        accent: Color(hex: "A86B2D"),
        accentSoft: Color(hex: "EFE1C4"),
        divider: Color(hex: "E5D8BC"),
        success: Color(hex: "6A8A4E")
    )

    private static let sepiaDarkColors = ReadingThemeColors(
        name: "Sepia 纸感",
        background: Color(hex: "1A1611"),
        cardBackground: Color(hex: "242018"),
        primaryText: Color(hex: "EDE4D4"),
        secondaryText: Color(hex: "A89880"),
        accent: Color(hex: "D4A05A"),
        accentSoft: Color(hex: "332B20"),
        divider: Color(hex: "3A3228"),
        success: Color(hex: "8BB573")
    )

    /// 夜间：近黑 OLED + 柔和紫蓝强调（降低刺眼饱和）
    private static let nightColors = ReadingThemeColors(
        name: "Night 夜间",
        background: Color(hex: "0A0A0C"),
        cardBackground: Color(hex: "161618"),
        primaryText: Color(hex: "ECECEE"),
        secondaryText: Color(hex: "9898A0"),
        accent: Color(hex: "9AA3F2"),
        accentSoft: Color(hex: "252532"),
        divider: Color(hex: "2C2C32"),
        success: Color(hex: "5BD98A")
    )

    /// 午夜蓝：低蓝光深蓝底，强调略提亮便于点按
    private static let midnightColors = ReadingThemeColors(
        name: "Midnight 午夜蓝",
        background: Color(hex: "0C1526"),
        cardBackground: Color(hex: "141F35"),
        primaryText: Color(hex: "E2EAF8"),
        secondaryText: Color(hex: "8A9BB8"),
        accent: Color(hex: "6B9BF0"),
        accentSoft: Color(hex: "1A2A48"),
        divider: Color(hex: "243552"),
        success: Color(hex: "5FCFB0")
    )

    /// 松绿：低饱和鼠尾草，强调橄榄绿（深色模式保持绿色调，不再变成紫蓝）
    private static let forestLightColors = ReadingThemeColors(
        name: "Forest 松绿",
        background: Color(hex: "F0F3EB"),
        cardBackground: Color(hex: "F8FAF5"),
        primaryText: Color(hex: "243024"),
        secondaryText: Color(hex: "66735E"),
        accent: Color(hex: "4F7348"),
        accentSoft: Color(hex: "DCE8D6"),
        divider: Color(hex: "D7E0D0"),
        success: Color(hex: "458B58")
    )

    private static let forestDarkColors = ReadingThemeColors(
        name: "Forest 松绿",
        background: Color(hex: "0F1410"),
        cardBackground: Color(hex: "181E19"),
        primaryText: Color(hex: "E4EBE2"),
        secondaryText: Color(hex: "95A390"),
        accent: Color(hex: "8FBC8A"),
        accentSoft: Color(hex: "243028"),
        divider: Color(hex: "2C382E"),
        success: Color(hex: "6DBF7E")
    )

    private static let highContrastLightColors = ReadingThemeColors(
        name: "高对比度",
        background: Color(hex: "FFFFFF"),
        cardBackground: Color(hex: "FFFFFF"),
        primaryText: Color(hex: "000000"),
        secondaryText: Color(hex: "2A2A2A"),
        accent: Color(hex: "0033A0"),
        accentSoft: Color(hex: "D6E4FF"),
        divider: Color(hex: "1A1A1A"),
        success: Color(hex: "0B5C0B")
    )

    private static let highContrastDarkColors = ReadingThemeColors(
        name: "高对比度",
        background: Color(hex: "000000"),
        cardBackground: Color(hex: "0A0A0A"),
        primaryText: Color(hex: "FFFFFF"),
        secondaryText: Color(hex: "D0D0D0"),
        accent: Color(hex: "5CA8FF"),
        accentSoft: Color(hex: "1A2740"),
        divider: Color(hex: "E0E0E0"),
        success: Color(hex: "5CFF5C")
    )
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
