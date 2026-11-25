import SwiftUI
import UIKit

/// 8pt 网格间距与语义色。全部使用系统语义色，自动适配深色模式与高对比度。
enum Theme {
    static let grid: CGFloat = 8

    /// 8pt 网格倍数快捷取值（支持 0.5 半格 = 4pt）。
    static func spacing(_ multiple: CGFloat) -> CGFloat {
        grid * multiple
    }

    /// 圆角规范：卡片 20 / 瓦片 14 / 按钮 14，胶囊由 Capsule 处理，全部连续曲率。
    enum Radius {
        static let card: CGFloat = 20
        static let tile: CGFloat = 14
        static let button: CGFloat = 14
    }

    /// 列表行图标（系统设置页同款实心彩色小方块）。
    enum RowIcon {
        static let size: CGFloat = 29
        static let corner: CGFloat = 7
        static let glyph: CGFloat = 15
    }

    /// 图标规范：全 App 只允许这三种尺寸，避免同一列表里图标大小不一。
    ///
    /// - `tile`：列表行图标底色瓦片边长（38）；
    /// - `smallTile`：详情页内嵌链接、次级行（30）；
    /// - `hero`：详情页顶部主图标（46）。
    /// `glyph` 是 emoji / SF Symbol 的视觉字高，与瓦片保持约 0.58 的比例。
    enum Icon {
        static let tile: CGFloat = 38
        static let smallTile: CGFloat = 30
        static let hero: CGFloat = 46
        /// 图标瓦片圆角（随尺寸等比，基准 38 → 10）。
        static let corner: CGFloat = 10
        /// 图标与文字的间距。
        static let gap: CGFloat = 12
        /// 图标字高基准（38 瓦片 → 21，约占瓦片 56%，与系统设置页图标占比一致）。
        static let glyph: CGFloat = 21

        /// 按瓦片尺寸推导字高，保证 30 / 38 / 46 三种尺寸视觉重量一致。
        static func glyph(for tile: CGFloat) -> CGFloat {
            (tile * glyph / Theme.Icon.tile).rounded()
        }

        /// 按瓦片尺寸推导圆角。
        static func corner(for tile: CGFloat) -> CGFloat {
            max((tile * corner / Theme.Icon.tile).rounded(), 6)
        }
    }

    /// 字号规范：正文与大数字全部走 Dynamic Type 语义字号。
    ///
    /// 大数字用圆体 + `.title2` / `.largeTitle` 语义字号，系统会按用户字号设置缩放，
    /// 不再写死 point size（写死会在辅助功能字号下不放大，属于可访问性缺陷）。
    enum TypeScale {
        /// 卡片标题（次级、字重 600）
        static let section = Font.subheadline.weight(.semibold)
        /// 指标大数字（圆体、半粗）
        static let metric = Font.system(.title2, design: .rounded, weight: .semibold)
        /// 主指标（电池等需要压住版面的大数字）
        static let metricLarge = Font.system(.largeTitle, design: .rounded, weight: .bold)
        /// 等宽数字（计数、毫秒、字节）
        static let mono = Font.system(.caption, design: .monospaced)
    }

    /// 布局规范：宽屏（iPad / Mac 窗口）下内容不再铺满整行，而是居中并限制阅读宽度。
    enum Layout {
        /// 单列内容最大宽度。iPhone 上永远不会触发；iPad 11" 约留 55pt 边距，13" 约留 150pt。
        static let contentMaxWidth: CGFloat = 720
    }
}

/// Apple 风格令牌：全部走系统语义色与系统字体，浅色/深色/高对比度由系统接管。
///
/// 取舍：不使用自定义配色（上一版琥珀方案已废弃）；强调色回到系统蓝，
/// 结果状态才用 systemGreen / systemOrange / systemRed，避免「到处都是颜色」。
extension ShapeStyle where Self == Color {
    /// 分组页背景（浅 #F2F2F7 / 深 #000）。
    static var p4Background: Color { Color(uiColor: .systemGroupedBackground) }
    /// 卡片背景（浅 #FFF / 深 #1C1C1E）。
    static var p4Card: Color { Color(uiColor: .secondarySystemGroupedBackground) }
    /// 次级底（瓦片、槽、浮层）。
    static var p4Tile: Color { Color(uiColor: .tertiarySystemFill) }
    /// 正常/在线。
    static var p4OK: Color { Color(uiColor: .systemGreen) }
    /// 注意。
    static var p4Warn: Color { Color(uiColor: .systemOrange) }
    /// 异常。
    static var p4Err: Color { Color(uiColor: .systemRed) }
    /// 信息。
    static var p4Info: Color { Color(uiColor: .systemBlue) }
    /// 主操作强调色 = 系统蓝（跟随系统强调色语义）。
    static var p4Accent: Color { Color(uiColor: .systemBlue) }
    /// 强调色上的文字。
    static var p4OnAccent: Color { .white }
    /// 分隔线 / 卡片描边（系统分隔色，深浅自动）。
    static var p4Hairline: Color { Color(uiColor: .separator) }
}

/// 分类色板：只用于图标瓦片底色，区分功能类别；状态含义仍由 `P4Tone` 表达。
enum P4Palette {
    static let blue = Color(uiColor: .systemBlue)
    static let indigo = Color(uiColor: .systemIndigo)
    static let purple = Color(uiColor: .systemPurple)
    static let pink = Color(uiColor: .systemPink)
    static let red = Color(uiColor: .systemRed)
    static let orange = Color(uiColor: .systemOrange)
    static let yellow = Color(uiColor: .systemYellow)
    static let green = Color(uiColor: .systemGreen)
    static let mint = Color(uiColor: .systemMint)
    static let teal = Color(uiColor: .systemTeal)
    static let cyan = Color(uiColor: .systemCyan)
    static let gray = Color(uiColor: .systemGray)
}

extension UIImage {
    /// UIKit 页面用的行图标：与 SwiftUI `SettingsIcon` 同尺寸、同圆角的实心彩色方块 + 白色字形。
    static func p4Tile(systemName: String, color: UIColor, size: CGFloat = Theme.RowIcon.size) -> UIImage? {
        let pointSize = size * Theme.RowIcon.glyph / Theme.RowIcon.size
        let configuration = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        guard let symbol = UIImage(systemName: systemName, withConfiguration: configuration)?
            .withTintColor(.white, renderingMode: .alwaysOriginal) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        return UIGraphicsImageRenderer(size: rect.size).image { _ in
            color.setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: size * Theme.RowIcon.corner / Theme.RowIcon.size).fill()
            let glyph = symbol.size
            symbol.draw(in: CGRect(x: (size - glyph.width) / 2, y: (size - glyph.height) / 2,
                                   width: glyph.width, height: glyph.height))
        }
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
        // 固件用 BUS-OFF（连字符），这里统一成空格再匹配。
        let value = state.uppercased().replacingOccurrences(of: "-", with: " ")
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
        let value = state.uppercased().replacingOccurrences(of: "-", with: " ")
        if value.contains("OFFLINE") || value.contains("BUS OFF") || value.contains("STOP") {
            return .p4Err
        }
        if value.contains("RUNNING") || value.contains("ONLINE") || value.contains("READY") || value.contains("OK") {
            return .p4OK
        }
        return .p4Warn
    }
}
