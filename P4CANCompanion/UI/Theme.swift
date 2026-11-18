import SwiftUI
import UIKit

/// 8pt 网格间距与语义色。全部使用系统语义色，自动适配深色模式与高对比度。
enum Theme {
    static let grid: CGFloat = 8

    /// 8pt 网格倍数快捷取值（支持 0.5 半格 = 4pt）。
    static func spacing(_ multiple: CGFloat) -> CGFloat {
        grid * multiple
    }

    /// 圆角规范：卡片 16 / 瓦片 12 / 胶囊由 Capsule 处理。
    enum Radius {
        static let card: CGFloat = 18
        static let tile: CGFloat = 11
        static let button: CGFloat = 14
    }

    /// 图标规范：全 App 只允许这三种尺寸，避免同一列表里图标大小不一。
    ///
    /// - `tile`：列表行图标底色瓦片边长（36）；
    /// - `smallTile`：详情页内嵌链接、次级行（30）；
    /// - `hero`：详情页顶部主图标（46）。
    /// `glyph` 是 emoji / SF Symbol 的视觉字高，与瓦片保持约 0.58 的比例。
    enum Icon {
        static let tile: CGFloat = 38
        static let smallTile: CGFloat = 30
        static let hero: CGFloat = 46
        /// 图标瓦片圆角（随尺寸等比，基准 36 → 10）。
        static let corner: CGFloat = 10
        /// 图标与文字的间距。
        static let gap: CGFloat = 12
        /// 图标字高基准（36 瓦片 → 21，约占瓦片 58%，与系统设置页图标占比一致）。
        static let glyph: CGFloat = 21

        /// 按瓦片尺寸推导字高，保证 30 / 36 / 46 三种尺寸视觉重量一致。
        static func glyph(for tile: CGFloat) -> CGFloat {
            (tile * glyph / Theme.Icon.tile).rounded()
        }

        /// 按瓦片尺寸推导圆角。
        static func corner(for tile: CGFloat) -> CGFloat {
            max((tile * corner / Theme.Icon.tile).rounded(), 6)
        }
    }

    /// 字号规范（正文走 Dynamic Type 语义字号，仅"大数字"用固定字号 + 圆体）。
    enum TypeScale {
        /// 卡片标题（次级、字重 600）
        static let section = Font.subheadline.weight(.semibold)
        /// 指标大数字
        static func metric(_ size: CGFloat = 26) -> Font {
            .system(size: size, weight: .semibold, design: .rounded)
        }
        /// 等宽数字（计数、毫秒、字节）
        static let mono = Font.system(.caption, design: .monospaced)
    }

    /// 布局规范：宽屏（iPad / Mac 窗口）下内容不再铺满整行，而是居中并限制阅读宽度。
    enum Layout {
        /// 单列内容最大宽度。iPhone 上永远不会触发；iPad 11" 约留 55pt 边距，13" 约留 150pt。
        static let contentMaxWidth: CGFloat = 720
    }
}

/// 双主题令牌：浅色是同一套层级的映射，不是第二套设计。
///
/// 深色（驾驶舱）：画布 #0B0D10 / 卡片 #14181F / 浮层 #1B2029；
/// 浅色：画布 #F6F7F9 / 卡片 #FFFFFF / 浮层 #F1F3F5。
/// 强调色在浅色下压深到 #B26A00，保证白底对比度 ≥ 4.5:1。
extension ShapeStyle where Self == Color {
    /// 分组页背景。
    static var p4Background: Color { p4Dynamic(light: 0xF6F7F9, dark: 0x0B0D10) }
    /// 卡片背景。
    static var p4Card: Color { p4Dynamic(light: 0xFFFFFF, dark: 0x14181F) }
    /// 卡片内的次级底（瓦片、进度槽、浮层）。
    static var p4Tile: Color { p4Dynamic(light: 0xF1F3F5, dark: 0x1B2029) }
    /// 正常/在线（绿）。
    static var p4OK: Color { p4Dynamic(light: 0x0E7A5F, dark: 0x3DDC97) }
    /// 注意（橙）。
    static var p4Warn: Color { p4Dynamic(light: 0xB45309, dark: 0xFFB020) }
    /// 异常（红）。
    static var p4Err: Color { p4Dynamic(light: 0xB3261E, dark: 0xFF6B6B) }
    /// 信息（蓝）。
    static var p4Info: Color { p4Dynamic(light: 0x1D5FD0, dark: 0x5AA9FF) }
    /// 主操作强调色（全 App 唯一强调色）。
    static var p4Accent: Color { p4Dynamic(light: 0xB26A00, dark: 0xFFB020) }
    /// 强调色上的文字。
    static var p4OnAccent: Color { p4Dynamic(light: 0xFFFFFF, dark: 0x1A1200) }
    /// 1px 分隔线 / 卡片描边。
    static var p4Hairline: Color { p4Dynamic(light: 0xE5E7EB, dark: 0x232A34) }
}

/// 十六进制 → 动态色。内部用，避免散落的 `Color(red:)`。
private func p4Dynamic(light: UInt32, dark: UInt32) -> Color {
    Color(uiColor: UIColor { trait in
        UIColor(hex: trait.userInterfaceStyle == .dark ? dark : light)
    })
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// 语义色调：颜色与默认图标一处定义，保证全 App 一致。
enum P4Tone {
    case ok
    case warn
    case err
    case info
    case neutral

    var color: Color {
        switch self {
        case .ok: return .p4OK
        case .warn: return .p4Warn
        case .err: return .p4Err
        case .info: return .p4Info
        case .neutral: return .secondary
        }
    }

    var symbol: String {
        switch self {
        case .ok: return "checkmark.circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .err: return "xmark.octagon.fill"
        case .info: return "info.circle.fill"
        case .neutral: return "circle.dashed"
        }
    }
}

/// CAN 总线状态的图标/颜色判断（不单独依赖颜色，同时提供 SF Symbol 与文字）。
enum P4BusState {
    static func symbol(for state: String?) -> String {
        guard let state else { return "questionmark.circle" }
        let value = state.uppercased()
        if value.contains("OFFLINE") || value.contains("BUS OFF") || value.contains("STOP") {
            return "xmark.octagon"
        }
        if value.contains("RUNNING") || value.contains("ONLINE") || value.contains("READY") || value.contains("OK") {
            return "checkmark.circle"
        }
        return "exclamationmark.triangle"
    }

    static func color(for state: String?) -> Color {
        guard let state else { return .secondary }
        let value = state.uppercased()
        if value.contains("OFFLINE") || value.contains("BUS OFF") || value.contains("STOP") {
            return .p4Err
        }
        if value.contains("RUNNING") || value.contains("ONLINE") || value.contains("READY") || value.contains("OK") {
            return .p4OK
        }
        return .p4Warn
    }
}
