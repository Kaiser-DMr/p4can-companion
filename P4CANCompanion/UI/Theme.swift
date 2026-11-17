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
        static let card: CGFloat = 16
        static let tile: CGFloat = 12
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
}

extension ShapeStyle where Self == Color {
    /// 分组页背景（浅色：浅灰；深色：近黑）。
    static var p4Background: Color { Color(uiColor: .systemGroupedBackground) }
    /// 卡片背景。
    static var p4Card: Color { Color(uiColor: .secondarySystemGroupedBackground) }
    /// 卡片内的次级底（瓦片、进度槽）。
    static var p4Tile: Color { Color(uiColor: .tertiarySystemGroupedBackground) }
    /// 正常/在线（绿）。
    static var p4OK: Color { Color(uiColor: .systemGreen) }
    /// 注意（橙）。
    static var p4Warn: Color { Color(uiColor: .systemOrange) }
    /// 异常（红）。
    static var p4Err: Color { Color(uiColor: .systemRed) }
    /// 信息/强调（蓝）。
    static var p4Info: Color { Color(uiColor: .systemBlue) }
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
