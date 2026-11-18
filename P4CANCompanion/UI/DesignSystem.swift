import SwiftUI

/// 设计系统组件（方案 v1 的 P1 层）：按钮、胶囊、分组标题、指标块。
///
/// 约束：全 App 只允许三种按钮（Primary / Secondary / Destructive），
/// 高度 48pt、圆角 14pt、水平内边距 20pt；强调色只来自 `p4Accent`。
enum DS {

    // MARK: - 分组标题（替代带 emoji 的 section header）

    struct SectionHeader: View {
        let title: String

        var body: some View {
            Text(title)
                .font(.caption2.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(.secondary)
                .textCase(nil)
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

    /// 三块一组的指标：标签 11pt 次要色，数值 26pt 圆体等宽，单位独立 12pt。
    struct Metric: View {
        let label: String
        let value: String
        var unit: String? = nil
        var tone: Color? = nil

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(tone ?? .primary)
                    if let unit {
                        Text(unit)
                            .font(.system(size: 12, weight: .medium))
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

    /// 统一卡片：18pt 圆角 + 1px 描边 + 16pt 内边距。
    struct Card<Content: View>: View {
        var padding: CGFloat = 16
        @ViewBuilder var content: Content

        var body: some View {
            content
                .padding(padding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.p4Card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .strokeBorder(Color.p4Hairline, lineWidth: 0.5)
                }
        }
    }

    // MARK: - 按钮

    struct PrimaryButtonStyle: ButtonStyle {
        var compact = false

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.system(size: compact ? 14 : 16, weight: .semibold))
                .foregroundStyle(Color.p4OnAccent)
                .padding(.horizontal, compact ? 16 : 20)
                .frame(minWidth: compact ? 132 : nil, maxWidth: compact ? nil : .infinity)
                .frame(height: compact ? 40 : 48)
                .background(Color.p4Accent.opacity(configuration.isPressed ? 0.82 : 1),
                            in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                .opacity(configuration.isPressed ? 0.95 : 1)
        }
    }

    struct SecondaryButtonStyle: ButtonStyle {
        var compact = false

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.system(size: compact ? 14 : 16, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, compact ? 16 : 20)
                .frame(minWidth: compact ? 132 : nil, maxWidth: compact ? nil : .infinity)
                .frame(height: compact ? 40 : 48)
                .background(Color.p4Tile.opacity(configuration.isPressed ? 0.75 : 1),
                            in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                        .strokeBorder(Color.p4Hairline, lineWidth: 0.5)
                }
        }
    }

    struct DestructiveButtonStyle: ButtonStyle {
        var compact = false

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.system(size: compact ? 14 : 16, weight: .semibold))
                .foregroundStyle(Color.p4Err)
                .padding(.horizontal, compact ? 16 : 20)
                .frame(minWidth: compact ? 132 : nil, maxWidth: compact ? nil : .infinity)
                .frame(height: compact ? 40 : 48)
                .background(Color.p4Err.opacity(configuration.isPressed ? 0.2 : 0.12),
                            in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                        .strokeBorder(Color.p4Err.opacity(0.24), lineWidth: 0.5)
                }
        }
    }
}

extension ButtonStyle where Self == DS.PrimaryButtonStyle {
    /// 主操作：琥珀实心。
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
