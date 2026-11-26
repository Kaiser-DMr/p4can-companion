import SwiftUI

/// Liquid Glass 表面（iOS 26+）。
///
/// 规则来源：SwiftPieces `get_liquid_glass_guide`
/// 1. `#available(iOS 26, *)` 且必须有 Material 回退；
/// 2. 尊重「降低透明度」辅助功能 → 改用不透明卡片；
/// 3. 只用真实 API：`glassEffect(_:in:)`、`Glass.regular`。
struct P4GlassSurface: ViewModifier {
    var cornerRadius: CGFloat

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            content.p4CardSurface(cornerRadius: cornerRadius)
        }
    }
}

extension View {
    /// 把视图放到一块液态玻璃上；系统版本或辅助功能不满足时自动退回卡片样式。
    func p4Glass(cornerRadius: CGFloat) -> some View {
        modifier(P4GlassSurface(cornerRadius: cornerRadius))
    }
}
