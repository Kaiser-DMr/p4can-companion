import SwiftUI

/// 设计系统组件：按钮、胶囊、分组标题、指标块、卡片。
///
/// 遵循 Apple HIG 与本项目的 apple-design 规范：
/// - 字号全部走 Dynamic Type 语义字号或 `@ScaledMetric`，放大字号时布局跟着长；
/// - 只有三种按钮（Primary / Secondary / Destructive），最小热区 44pt，主按钮 50pt；
/// - 按下即反馈（不等抬手），用临界阻尼弹簧（response 0.18 / damping 1.0），不过冲；
/// - 尊重「减弱动态效果」：关闭缩放与弹簧，只保留颜色/透明度变化；
/// - 禁用态必须有可见反馈（降到 35–40% 不透明度），不能只靠点不动。
enum DS {

    // MARK: - 分组标题

    /// 分组标题：对齐系统分组列表的 header —— .footnote、半粗、次要色，不做字距拉伸。
    struct SectionHeader: View {
        let title: String

        var body: some View {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(nil)
                .accessibilityAddTraits(.isHeader)
        }
    }

    // MARK: - 状态胶囊

    struct Pill: View {
        let text: String
        var tone: P4Tone = .neutral
        var showsDot: Bool = true

        var body: some View {
            HStack(spacing: 5) {
                if showsDot {
                    Circle()
                        .fill(tone.color)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
                Text(text)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(tone.color)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(tone.color.opacity(0.12), in: Capsule())
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(text)
        }
    }

    // MARK: - 指标块

    /// 指标：标签用 .caption2，数值随动态字体缩放（基准 26pt），单位独立降级。
    ///
    /// 大字号数字加负字距（字号越大字距越紧），这是 Apple 的排版规则；
    /// 等宽数字保证轮询刷新时数值不左右跳动。
    struct Metric: View {
        let label: String
        let value: String
        var unit: String? = nil
        var tone: Color? = nil

        @ScaledMetric(relativeTo: .title2) private var valueSize: CGFloat = 26

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.system(size: valueSize, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .tracking(-valueSize * 0.015)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(tone ?? .primary)
                    if let unit {
                        Text(unit)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(label) \(value)\(unit ?? "")")
        }
    }

    // MARK: - 卡片容器

    /// 卡片：只用系统卡片底色与圆角分层，不加描边（系统分组列表也不给卡片描边）。
    struct Card<Content: View>: View {
        var padding: CGFloat = 16
        @ViewBuilder var content: Content

        var body: some View {
            content
                .padding(padding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color.p4Card,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                )
        }
    }

    // MARK: - 按钮

    /// 按钮的共用行为：语义字号、HIG 热区、按下即反馈、禁用可见、尊重减弱动效。
    private struct ButtonSurface: ViewModifier {
        /// 常态填充；`pressedFill` 非空时按下切换到它（系统次按钮的观感）。
        let fill: AnyShapeStyle
        var pressedFill: AnyShapeStyle? = nil
        let foreground: Color
        let compact: Bool
        let isPressed: Bool

        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        private var shape: RoundedRectangle {
            RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
        }

        /// 禁用时不再保留强调色：系统按钮禁用后是灰底 + 次要文字，
        /// 只把彩色按钮降透明度会让人误以为「还能点，只是暗一点」。
        private var disabledFill: AnyShapeStyle {
            AnyShapeStyle(Color(uiColor: .tertiarySystemFill))
        }

        func body(content: Content) -> some View {
            content
                .font(compact ? .subheadline.weight(.semibold) : .body.weight(.semibold))
                .foregroundStyle(isEnabled ? foreground : Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .padding(.horizontal, compact ? 16 : 20)
                // 44pt 是 HIG 的最小点击热区；主按钮用系统 50pt 的观感。
                .frame(minWidth: compact ? 88 : nil, maxWidth: compact ? nil : .infinity)
                .frame(minHeight: compact ? 44 : 50)
                .background(
                    isEnabled ? ((isPressed ? pressedFill : nil) ?? fill) : disabledFill,
                    in: shape
                )
                .opacity(isPressed ? 0.85 : 1)
                .scaleEffect(isPressed && !reduceMotion ? 0.98 : 1)
                .animation(
                    reduceMotion ? nil : .spring(response: 0.18, dampingFraction: 1.0),
                    value: isPressed
                )
                .contentShape(shape)
        }
    }

    struct PrimaryButtonStyle: ButtonStyle {
        var compact = false

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .modifier(ButtonSurface(
                    fill: AnyShapeStyle(Color.p4Accent),
                    foreground: .p4OnAccent,
                    compact: compact,
                    isPressed: configuration.isPressed
                ))
        }
    }

    /// 次按钮：系统填充色，不加描边；按下用更浅的填充表示。
    struct SecondaryButtonStyle: ButtonStyle {
        var compact = false

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .modifier(ButtonSurface(
                    fill: AnyShapeStyle(Color(uiColor: .secondarySystemFill)),
                    pressedFill: AnyShapeStyle(Color(uiColor: .tertiarySystemFill)),
                    foreground: .primary,
                    compact: compact,
                    isPressed: configuration.isPressed
                ))
        }
    }

    /// 危险操作：红字 + 系统填充底（与系统 destructive 按钮一致），不额外加红色块。
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

extension ButtonStyle where Self == DS.PrimaryButtonStyle {
    /// 主操作：系统强调色实心。
    static var dsPrimary: DS.PrimaryButtonStyle { .init() }
    static func dsPrimary(compact: Bool) -> DS.PrimaryButtonStyle { .init(compact: compact) }
}

extension ButtonStyle where Self == DS.SecondaryButtonStyle {
    static var dsSecondary: DS.SecondaryButtonStyle { .init() }
    static func dsSecondary(compact: Bool) -> DS.SecondaryButtonStyle { .init(compact: compact) }
}

extension ButtonStyle where Self == DS.DestructiveButtonStyle {
    static var dsDestructive: DS.DestructiveButtonStyle { .init() }
    static func dsDestructive(compact: Bool) -> DS.DestructiveButtonStyle { .init(compact: compact) }
}
