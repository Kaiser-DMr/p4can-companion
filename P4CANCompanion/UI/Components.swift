import SwiftUI

// MARK: - 卡片容器

/// 分组卡片：标题 + SF Symbol + 内容。全宽 16pt 边距（8pt 网格 ×2）。
struct Card<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(2)) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .padding(Theme.spacing(2))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.p4Card,
            in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        )
    }
}

// MARK: - 键值行

/// 固件状态键值行：左侧本地化键名，右侧格式化值。
/// 无障碍：合并为一行朗读“名称，值”。
struct MetricRow: View {
    let key: String
    let value: P4JSON

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(P4KeyLocalization.label(for: key))
                .foregroundStyle(.secondary)
            Spacer(minLength: Theme.spacing(1))
            Text(P4Format.value(for: key, of: value))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(P4KeyLocalization.label(for: key))，\(P4Format.value(for: key, of: value))")
    }
}

// MARK: - 状态徽章

/// 总线/连接状态徽章：图标 + 文字（颜色仅作辅助）。
struct StateBadge: View {
    let text: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.footnote.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, Theme.spacing(1))
            .padding(.vertical, Theme.spacing(0.5))
            .background(color.opacity(0.12), in: Capsule())
            .accessibilityLabel("\(text)状态")
    }
}

// MARK: - 骨架屏

/// 加载占位（禁止全屏 spinner，使用 redacted 骨架）。
struct SkeletonRows: View {
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(1.5)) {
            ForEach(0..<count, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Theme.spacing(0.5))
                    .fill(Color.p4Card)
                    .frame(height: 18)
                    .redacted(reason: .placeholder)
            }
        }
    }
}

// MARK: - 提示横幅

/// 命令执行结果的浮动提示，自动消失。
///
/// Apple 的材料原则：浮层用 Material + 阴影浮在内容之上，不用实色块；
/// 出现时是「材质化」而不是纯淡入（缩放 + 透明度同时进行）；
/// 打开「降低透明度」时退回实色底，「增强对比度」时补一圈描边保证可读。
struct ToastOverlay: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.spacing(1.5), style: .continuous)
    }

    var body: some View {
        if let toast = environment.toast {
            VStack {
                Spacer()
                HStack(spacing: Theme.spacing(1)) {
                    switch toast.style {
                    case .success:
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.p4OK)
                    case .failure:
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.p4Err)
                    case .info:
                        Image(systemName: "info.circle.fill").foregroundStyle(.tint)
                    }
                    Text(toast.message)
                        .font(.footnote)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Theme.spacing(2))
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    if reduceTransparency {
                        shape.fill(Color(uiColor: .secondarySystemGroupedBackground))
                    } else {
                        shape.fill(.regularMaterial)
                    }
                }
                .overlay {
                    if contrast == .increased {
                        shape.strokeBorder(Color.primary.opacity(0.25), lineWidth: 1)
                    }
                }
                .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
                .padding(.horizontal, Theme.spacing(2))
                .padding(.bottom, Theme.spacing(2))
                .accessibilityElement(children: .combine)
                .transition(reduceMotion ? .opacity : .scale(scale: 0.96).combined(with: .opacity))
            }
            .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 1.0), value: environment.toast?.id)
            .task(id: toast.id) {
                try? await Task.sleep(for: .seconds(4))
                if environment.toast?.id == toast.id {
                    environment.toast = nil
                }
            }
        }
    }
}


// MARK: - 状态胶囊（标签）

/// 状态徽标：系统灰底胶囊 + 语义色圆点（或图标），文字用主色。
///
/// 这是 iOS 自带的状态徽标写法（灰底、彩色小圆点、中性文字），
/// 不再给整颗胶囊上色——彩色底会同时占用「底色」和「文字色」两个层级，
/// 一屏出现多颗时版面会很吵，也弱化了真正需要注意的红色/橙色。
/// 文字单行 + 横向自适应：字号放大时胶囊变宽而不是竖排换行。
struct StatusChip: View {
    let text: String
    var systemImage: String? = nil
    var tone: P4Tone = .neutral

    private var markColor: Color {
        tone == .neutral ? Color.secondary : tone.color
    }

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(markColor)
                    .accessibilityHidden(true)
            } else {
                Circle()
                    .fill(markColor)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}

// MARK: - 流式布局

/// 按行排列、放不下自动换行的布局（状态胶囊组专用）。
///
/// 系统 `HStack` 在窄屏或大字号下会把胶囊压扁、文字竖排；这里让每个子视图保持自身
/// 理想尺寸，超出可用宽度就整颗换到下一行，行内垂直居中。
struct P4FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    private struct Line {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func lines(maxWidth: CGFloat, subviews: Subviews) -> [Line] {
        var result: [Line] = []
        var current = Line()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let additional = current.indices.isEmpty ? size.width : spacing + size.width
            if !current.indices.isEmpty, current.width + additional > maxWidth {
                result.append(current)
                current = Line(indices: [index], width: size.width, height: size.height)
            } else {
                current.indices.append(index)
                current.width += additional
                current.height = max(current.height, size.height)
            }
        }
        if !current.indices.isEmpty { result.append(current) }
        return result
    }

    /// 计算换行时使用的可用宽度。
    ///
    /// 父容器有时会用「无宽度」的 proposal 来测理想尺寸（VStack 的 ideal pass），
    /// 这时如果按无穷宽算，所有胶囊会排成一行，理想宽度变成三颗胶囊之和，
    /// 反过来把父容器撑得比屏幕还宽。这里退化到一个保守宽度，真正的布局阶段
    /// 父容器一定会给出确定宽度，换行仍然准确。
    private func availableWidth(_ proposal: ProposedViewSize) -> CGFloat {
        proposal.width ?? 320
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = availableWidth(proposal)
        let rows = lines(maxWidth: maxWidth, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(rows.count - 1, 0))
        let width = min(rows.map(\.width).max() ?? 0, maxWidth)
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in lines(maxWidth: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }
}


// MARK: - 模块图标

/// 模块图标：优先按 Assets 资源名查找（如 TLSSC 的红绿灯），否则回退 SF Symbol。
///
/// `glyphSize` 统一由 `Theme.Icon` 推导，保证同一列表里的 emoji / 位图 / 符号三种来源
/// 视觉大小一致（emoji 自带留白，需要比 SF Symbol 略大一号）。
struct ModuleIcon: View {
    let name: String
    var glyphSize: CGFloat = Theme.Icon.glyph

    private static let emojiPrefix = "emoji:"

    var body: some View {
        if name.hasPrefix(Self.emojiPrefix) {
            Text(String(name.dropFirst(Self.emojiPrefix.count)))
                .font(.system(size: glyphSize))
                .frame(width: glyphSize * 1.2, height: glyphSize * 1.2)
        } else if UIImage(named: name) != nil {
            Image(name)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: glyphSize, height: glyphSize)
        } else {
            Image(systemName: name)
                .font(.system(size: glyphSize * 0.92, weight: .medium))
                .frame(width: glyphSize, height: glyphSize)
        }
    }
}

/// 带底色瓦片的模块图标：功能列表、详情页链接、实验室列表统一使用。
///
/// 三层结构固定为「瓦片底 + 0.5pt 描边 + 居中字形」，这样不同底色（卡片 / 玻璃）上
/// 图标块的视觉重量一致；emoji 本身有颜色，不使用强调色，SF Symbol 才着色。
struct ModuleIconTile: View {
    let name: String
    var size: CGFloat = Theme.Icon.tile
    /// nil 表示中性瓦片（emoji 场景）；传入强调色时瓦片底色跟随淡化。
    var tint: Color? = nil

    private var corner: CGFloat { Theme.Icon.corner(for: size) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(tint.map { $0.opacity(0.14) } ?? Color.p4Tile)
            ModuleIcon(name: name, glyphSize: Theme.Icon.glyph(for: size))
                .foregroundStyle(tint ?? Color.accentColor)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - 详情页跳转行

/// 详情页里的二级入口行：图标瓦片 + 标题 + 说明。
///
/// 放在 `NavigationLink` 的 label 里使用，系统会自动补 chevron 与按压高亮，
/// 因此不额外加箭头，避免出现双箭头。
struct NavRow: View {
    let icon: String
    let title: String
    let subtitle: String
    var tint: Color? = nil

    var body: some View {
        HStack(spacing: Theme.Icon.gap) {
            ModuleIconTile(name: icon, size: Theme.Icon.smallTile, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Theme.spacing(0.5))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(subtitle)")
    }
}

// MARK: - 交互状态约定
//
// 功能区的可交互元素统一按下面三态呈现，避免同一页出现两套反馈：
// - 按压：交给系统（List 行高亮、Toggle / Picker / Stepper 自带）；
// - 忙：按钮内联 `ProgressView().controlSize(.small)`，同时 `.disabled(true)`；
// - 生效：行尾用 `StatusChip`（如「爆闪中」「支持 / 不支持」），文字优先、颜色辅助。

// MARK: - KPI 瓦片

/// 关键指标瓦片：图标 + 名称 + 大数字（+ 单位）+ 备注。
/// 设备未上报时传 "—"，不伪造数值。
///
/// 三层结构与 ShipSwift `SWKPICard` 一致：标题行（图标 + caption）→ 主数值 → 脚注。
/// 数值使用 `numericText` 过渡，轮询刷新时数字是滚动变化而不是硬跳；
/// 标题允许折到两行、脚注在大字号下允许两行，避免 Dynamic Type 放大后被截成 "AP …"。
struct MetricTile: View {
    let icon: String
    let title: String
    let value: String
    var unit: String? = nil
    var tone: P4Tone = .info
    var footnote: String? = nil

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 只有警告/错误才给数值上色；正常状态用主文字色，保持版面安静。
    private var valueColor: Color {
        switch tone {
        case .warn: return .p4Warn
        case .err: return .p4Err
        default: return value == "—" ? .secondary : .primary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                // 图标保持次要色：色彩只留给「需要注意」的数值，避免一排彩色小图标抢走层级。
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(Theme.TypeScale.metric)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let unit {
                    Text(unit).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 1.0), value: value)
            if let footnote {
                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            }
        }
        .padding(Theme.spacing(1.5))
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
        .background(
            Color.p4Card,
            in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)，\(value)\(unit ?? "")")
    }
}

// MARK: - 细进度条

/// 细进度条：用于发送成功率、固件写入进度等。数值 0…1。
struct SlimProgress: View {
    let value: Double
    var tint: Color = .p4Info
    var height: CGFloat = 6
    var label: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.p4Tile)
                    Capsule()
                        .fill(tint)
                        .frame(width: max(0, min(1, value)) * geo.size.width)
                }
            }
            .frame(height: height)
            if let label {
                Text(label).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label ?? "进度")
        .accessibilityValue("\(Int((min(max(value, 0), 1)) * 100))%")
    }
}

// MARK: - 占比条

/// 横向占比条 + 图例：展示三路总线的接收帧占比。
struct RatioBar: View {
    struct Segment: Identifiable {
        let id: String
        let label: String
        let value: Double
        let color: Color
    }

    let segments: [Segment]

    private var total: Double {
        max(segments.reduce(0) { $0 + max($1.value, 0) }, 0.0001)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                let gap: CGFloat = 3
                let available = max(geo.size.width - gap * CGFloat(max(segments.count - 1, 0)), 1)
                HStack(spacing: gap) {
                    ForEach(segments) { segment in
                        Capsule()
                            .fill(segment.color)
                            .frame(width: max(3, available * CGFloat(max(segment.value, 0) / total)))
                    }
                }
            }
            .frame(height: 10)

            HStack(spacing: Theme.spacing(1.5)) {
                ForEach(segments) { segment in
                    HStack(spacing: 4) {
                        Circle().fill(segment.color).frame(width: 6, height: 6)
                        Text(segment.label).font(.caption2).foregroundStyle(.secondary)
                        Text("\(Int((max(segment.value, 0) / total) * 100))%")
                            .font(.caption2.weight(.medium))
                            .monospacedDigit()
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("接收帧占比：" + segments.map { "\($0.label) \(Int((max($0.value, 0) / total) * 100))%" }.joined(separator: "，"))
    }
}
