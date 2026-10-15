import SwiftUI

/// Clipa 设计体系 —— 对应 doc/design_reference.md 的 Design System strip。
/// 颜色优先映射 macOS 系统语义色（深浅自适应），强调色用系统 accent。
enum Theme {

    // MARK: - Spacing（8pt 网格）
    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let xxxl: CGFloat = 40
    }

    // MARK: - Radii
    enum Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let card: CGFloat = 16
        static let large: CGFloat = 20
    }

    // MARK: - Colors（语义命名，深浅自适应）
    enum Color {
        static let accent = SwiftUI.Color.accentColor
        static let text = SwiftUI.Color(nsColor: .labelColor)
        static let secondary = SwiftUI.Color(nsColor: .secondaryLabelColor)
        static let tertiary = SwiftUI.Color(nsColor: .tertiaryLabelColor)
        static let border = SwiftUI.Color(nsColor: .separatorColor)
        static let card = SwiftUI.Color(nsColor: .controlBackgroundColor)
        static let surface = SwiftUI.Color(nsColor: .windowBackgroundColor)
        static let success = SwiftUI.Color(nsColor: .systemGreen)
        static let warning = SwiftUI.Color(nsColor: .systemOrange)
        static let danger = SwiftUI.Color(nsColor: .systemRed)
    }

    // MARK: - Typography（SF Pro）
    enum Font {
        static let title = SwiftUI.Font.system(size: 17, weight: .semibold)
        static let headline = SwiftUI.Font.system(size: 15, weight: .semibold)
        static let body = SwiftUI.Font.system(size: 13, weight: .regular)
        static let callout = SwiftUI.Font.system(size: 13, weight: .regular)
        static let caption = SwiftUI.Font.system(size: 11, weight: .regular)
        static let footnote = SwiftUI.Font.system(size: 10, weight: .regular)
        static let mono = SwiftUI.Font.system(size: 12, weight: .regular, design: .monospaced)
    }

    // MARK: - Card 尺寸（卡片条）
    enum Card {
        static let width: CGFloat = 200
        static let height: CGFloat = 262
        static let spacing: CGFloat = 14
        static let radius: CGFloat = 14
    }

    /// 浮层尺寸
    enum Bar {
        static let topBarHeight: CGFloat = 48
        static var panelHeight: CGFloat { topBarHeight + Card.height + Space.md * 2 + 1 }
    }

}

extension View {
    /// 卡片柔和阴影（Card Shadow ≈ 0 6 30 rgba(0,0,0,0.08)）
    func clipaCardShadow() -> some View {
        shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
    }

    /// 浮层 / popover 阴影（≈ 0 12 40 rgba(0,0,0,0.16)）
    func clipaPopoverShadow() -> some View {
        shadow(color: .black.opacity(0.16), radius: 20, x: 0, y: 6)
    }
}

// MARK: - Figma 还原配色（1:1，见 doc/design_reference）

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

/// 动态浅/深色。
func dyn(_ light: Color, _ dark: Color) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return NSColor(isDark ? dark : light)
    })
}

enum ClipaColor {
    static let accent = Color(hex: 0x4F46E5)                 // indigo 品牌色
    // 更通透的浮层底色：降低不透明度让毛玻璃/液态玻璃透出背景。
    static let barBG = dyn(Color(hex: 0xE9E5FC, alpha: 0.60), Color(hex: 0x1C1C1E, alpha: 0.62))
    /// 液态玻璃（macOS 26）之上的极淡品牌染色，保持 Clipa 的紫调而不挡背景。
    static let barGlassTint = dyn(Color(hex: 0xE9E5FC, alpha: 0.12), Color(hex: 0x1C1C1E, alpha: 0.16))
    static let cardBG = dyn(Color(hex: 0xFFFFFF, alpha: 0.92), Color(hex: 0x2C2C2E, alpha: 0.92))
    static let cardBorder = dyn(Color(hex: 0x000000, alpha: 0.08), Color(hex: 0xFFFFFF, alpha: 0.09))
    static let topBorder = dyn(Color(hex: 0x000000, alpha: 0.07), Color(hex: 0xFFFFFF, alpha: 0.08))
    static let searchBG = dyn(Color(hex: 0xFFFFFF, alpha: 0.72), Color(hex: 0x000000, alpha: 0.22))
    static let segTrack = dyn(Color(hex: 0x000000, alpha: 0.05), Color(hex: 0xFFFFFF, alpha: 0.08))
    static let segSelected = dyn(Color(hex: 0xFFFFFF, alpha: 0.95), Color(hex: 0x636366, alpha: 0.9))
    static let textPrimary = dyn(Color(hex: 0x1C1C1E), Color(hex: 0xF2F2F7))
    static let textSecondary = dyn(Color(hex: 0x6E6E73), Color(hex: 0xAEAEB2))
    static let textTertiary = dyn(Color(hex: 0x8E8E93), Color(hex: 0x8E8E93))
    static let keyCapBG = dyn(Color(hex: 0x000000, alpha: 0.05), Color(hex: 0xFFFFFF, alpha: 0.08))
    static let imageBG = dyn(Color(hex: 0xF2F2F5), Color(hex: 0x1A1A1C))   // 非透明图片的容器底色

    /// 类型 → 强调色（药丸文字色；底色用其 ~0.12 透明）。
    static func type(_ kind: ClipKind) -> Color {
        switch kind {
        case .text: return dyn(Color(hex: 0x6E6E73), Color(hex: 0xAEAEB2))
        case .rtf:  return Color(hex: 0x5856D6)
        case .link: return Color(hex: 0x2563EB)
        case .image: return Color(hex: 0x7C3AED)
        case .file: return Color(hex: 0xD97706)
        case .code: return Color(hex: 0x059669)
        case .color: return Color(hex: 0xDB2777)
        }
    }
}

/// 相对时间："just now" / "3 min ago" / "2 h ago" / "1 d ago"
enum RelativeTime {
    static func string(_ date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        if s < 10 { return String(localized: "just now") }
        if s < 60 { return String(localized: "\(s)s ago") }
        let m = s / 60
        if m < 60 { return String(localized: "\(m) min ago") }
        let h = m / 60
        if h < 24 { return String(localized: "\(h)h ago") }
        return String(localized: "\(h / 24)d ago")
    }
}
