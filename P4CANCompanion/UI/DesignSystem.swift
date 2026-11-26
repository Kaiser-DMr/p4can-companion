import SwiftUI

/// 设计系统按钮。
///
/// 遵循 Apple HIG：
/// - 字号走 Dynamic Type 语义字号，最小热区 44pt，常规按钮 50pt；
/// - 按下即反馈（不等抬手），用临界阻尼弹簧，不过冲；
/// - 尊重「减弱动态效果」：关闭缩放与弹簧，只保留颜色/透明度变化；
/// - 禁用态必须有可见反馈：灰底 + 次要文字。
enum DS {

    /// 按钮的共用行为：语义字号、HIG 热区、按下即反馈、禁用可见、尊重减弱动效。
    private struct ButtonSurface: ViewModifier {
        let fill: AnyShapeStyle
        let pressedFill: AnyShapeStyle
        let foreground: Color
        let compact: Bool
        let isPressed: Bool

        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        private var shape: RoundedRectangle {
            RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
        }

        func body(content: Content) -> some View {
            content
                .font(compact ? .subheadline.weight(.semibold) : .body.weight(.semibold))
                .foregroundStyle(isEnabled ? foreground : Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .padding(.horizontal, compact ? 16 : 20)
                .frame(minWidth: compact ? 88 : nil, maxWidth: compact ? nil : .infinity)
                .frame(minHeight: compact ? 44 : 50)
                .background(
                    isEnabled
                        ? (isPressed ? pressedFill : fill)
                        : AnyShapeStyle(Color(uiColor: .tertiarySystemFill)),
                    in: shape
                )
                .opacity(isPressed ? 0.9 : 1)
                .scaleEffect(isPressed && !reduceMotion ? 0.97 : 1)
                .animation(
                    reduceMotion ? nil : .spring(response: 0.15, dampingFraction: 1.0),
                    value: isPressed
                )
                .contentShape(shape)
        }
    }

    /// 危险操作：红字 + 系统填充底（与系统 destructive 按钮一致）。
    struct DestructiveButtonStyle: ButtonStyle {
        var compact = false

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .modifier(ButtonSurface(
                    fill: AnyShapeStyle(Color(uiColor: .secondarySystemFill)),
                    pressedFill: AnyShapeStyle(Color(uiColor: .tertiarySystemFill)),
                    foreground: .p4Err,
                    compact: compact,
                    isPressed: configuration.isPressed
                ))
        }
    }
}

extension ButtonStyle where Self == DS.DestructiveButtonStyle {
    static var dsDestructive: DS.DestructiveButtonStyle { .init() }
    static func dsDestructive(compact: Bool) -> DS.DestructiveButtonStyle { .init(compact: compact) }
}
