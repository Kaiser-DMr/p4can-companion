import SwiftUI

// MARK: - 卡片表面

/// 卡片底：浅色模式靠极轻阴影从灰底上浮起，深色模式阴影不可见，改用 0.5pt 发丝描边分层。
struct CardSurface: ViewModifier {
    var cornerRadius: CGFloat = Theme.Radius.card

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(shape.fill(Color.p4Card))
            .overlay(
                shape.strokeBorder(
                    Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.04),
                    lineWidth: 0.5
                )
            )
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0 : 0.045),
                radius: 10, x: 0, y: 3
            )
    }
}

extension View {
    func p4CardSurface(cornerRadius: CGFloat = Theme.Radius.card) -> some View {
        modifier(CardSurface(cornerRadius: cornerRadius))
    }
}

// MARK: - 卡片容器

/// 分组卡片：彩色小图标 + 标题 + 可选尾部附件 + 内容。
struct Card<Content: View, Accessory: View>: View {
    let title: String
    let systemImage: String
    var tint: Color = .p4Accent
    @ViewBuilder let accessory: Accessory
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(1.75)) {
            HStack(spacing: Theme.spacing(1)) {
                SettingsIcon(systemImage: systemImage, tint: tint, size: 24)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: Theme.spacing(1))
                accessory
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            content
        }
        .padding(Theme.spacing(2))
        .frame(maxWidth: .infinity, alignment: .leading)
        .p4CardSurface()
    }
}

extension Card where Accessory == EmptyView {
    init(title: String,
         systemImage: String,
         tint: Color = .p4Accent,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.accessory = EmptyView()
        self.content = content()
    }
}

// MARK: - 列表行图标

/// 系统设置页同款行图标：实心彩色圆角方块 + 白色字形，顶部带一层很淡的高光渐变。
struct SettingsIcon: View {
    let systemImage: String
    var tint: Color = .p4Accent
    var size: CGFloat = Theme.RowIcon.size

    private var corner: CGFloat { (size * Theme.RowIcon.corner / Theme.RowIcon.size).rounded() }
    private var glyph: CGFloat { (size * Theme.RowIcon.glyph / Theme.RowIcon.size).rounded() }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(tint.gradient)
            Image(systemName: systemImage)
                .font(.system(size: glyph, weight: .semibold))
                .foregroundStyle(.white)
                .symbolRenderingMode(.monochrome)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// 列表行：彩色图标 + 标题 + 可选说明。放在 `NavigationLink` / `Button` 的 label 里使用。
struct IconRow: View {
    let title: String
    var subtitle: String? = nil
    let systemImage: String
    var tint: Color = .p4Accent
    var titleColor: Color = .primary

    var body: some View {
        HStack(spacing: Theme.Icon.gap) {
            SettingsIcon(systemImage: systemImage, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(titleColor)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, subtitle == nil ? 0 : 1)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 列表行 Label 样式

private struct P4RowTintKey: EnvironmentKey {
    static let defaultValue: Color = .p4Accent
}

extension EnvironmentValues {
    /// 列表行图标瓦片的底色，由 `.p4RowTint(_:)` 设置，向下传递。
    var p4RowTint: Color {
        get { self[P4RowTintKey.self] }
        set { self[P4RowTintKey.self] = newValue }
    }
}

/// 列表行 Label：SF Symbol 放进实心彩色圆角方块（系统设置页观感），标题保持原样。
/// 对 `List` 整体设置后，所有行内 `Label` 自动统一；分组标题使用纯文字，不受影响。
/// 显式设置了小字号的 Label（脚注提示、错误说明）保持行内小图标，不放大成方块。
/// 只认小字号：`LabeledContent` 等系统容器会给标签设置自己的字体，不能当成提示文字。
struct P4RowLabelStyle: LabelStyle {
    @Environment(\.p4RowTint) private var tint
    @Environment(\.font) private var font

    private static let inlineFonts: [Font] = [.footnote, .caption, .caption2]

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if let font, Self.inlineFonts.contains(font) {
            Label(configuration).labelStyle(.titleAndIcon)
        } else {
            HStack(spacing: Theme.Icon.gap) {
                configuration.icon
                    .font(.system(size: Theme.RowIcon.glyph, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.monochrome)
                    .frame(width: Theme.RowIcon.size, height: Theme.RowIcon.size)
                    .background(
                        tint.gradient,
                        in: RoundedRectangle(cornerRadius: Theme.RowIcon.corner, style: .continuous)
                    )
                    .accessibilityHidden(true)
                configuration.title
            }
        }
    }
}

extension LabelStyle where Self == P4RowLabelStyle {
    static var p4Row: P4RowLabelStyle { .init() }
}

extension View {
    /// 设置本视图内列表行图标的底色。
    func p4RowTint(_ color: Color) -> some View {
        environment(\.p4RowTint, color)
    }

    /// 分组列表的统一外观：行内 Label 换成彩色图标，页面底色与其他标签页一致。
    func p4ListStyle() -> some View {
        self
            .labelStyle(.p4Row)
            .scrollContentBackground(.hidden)
            .background(Color.p4Background)
    }
}

// MARK: - 数值输入框

/// 列表行尾的数值输入：右对齐、等宽数字、浅灰圆角底，一眼能看出可编辑，又不像系统描边框那样突兀。
struct P4NumberFieldStyle: ViewModifier {
    var width: CGFloat = 96

    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(width: width)
            .background(
                Color(uiColor: .tertiarySystemFill),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
    }
}

extension View {
    func p4NumberField(width: CGFloat = 96) -> some View {
        modifier(P4NumberFieldStyle(width: width))
    }
}

// MARK: - 圆环仪表

/// 圆环进度：电量、写入进度等 0…1 数值，中心放主数字。
struct RingGauge<Center: View>: View {
    let value: Double
    var tint: Color = .p4OK
    var lineWidth: CGFloat = 10
    @ViewBuilder var center: Center

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clamped: Double { min(max(value, 0), 1) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.p4Tile, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(
                    AngularGradient(
                        colors: [tint.opacity(0.65), tint],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360 * clamped)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .smooth(duration: 0.6), value: clamped)
            center
        }
        .accessibilityElement(children: .ignore)
        .accessibilityValue("\(Int(clamped * 100))%")
    }
}

// MARK: - 实时指示点

/// 在线时缓慢呼吸的状态点；减弱动态效果时保持静止。
struct LiveDot: View {
    var color: Color = .p4OK
    var isLive = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        ZStack {
            if isLive && !reduceMotion {
                Circle()
                    .fill(color.opacity(0.35))
                    .scaleEffect(pulse ? 2.2 : 1)
                    .opacity(pulse ? 0 : 1)
                    .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false), value: pulse)
            }
            Circle().fill(color)
        }
        .frame(width: 8, height: 8)
        .onAppear { pulse = true }
        .accessibilityHidden(true)
    }
}

// MARK: - 键值行

/// 固件状态键值行：左侧本地化键名，右侧格式化值。
/// 与系统 `LabeledContent` 一致：键名主色、值次要色，字号跟随所在容器。
/// 无障碍：合并为一行朗读“名称，值”。
struct MetricRow: View {
    let key: String
    let value: P4JSON

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(P4KeyLocalization.label(for: key))
                .foregroundStyle(.primary)
            Spacer(minLength: Theme.spacing(1))
            Text(P4Format.value(for: key, of: value))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("\(P4KeyLocalization.label(for: key))，\(P4Format.value(for: key, of: value))",
                                   "\(P4KeyLocalization.label(for: key)), \(P4Format.value(for: key, of: value))"))
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
                // 进入「材质化」（缩放 + 淡入），离场只淡出且更快：
                // 离场是系统在响应，不该和进入一样慢。
                .transition(reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .scale(scale: 0.96).combined(with: .opacity),
                                removal: .opacity))
            }
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1.0), value: environment.toast?.id)
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

/// 模块图标：优先按 Assets 资源名查找，否则回退 SF Symbol。
/// 注意：SF Symbol 名写错时 `Image(systemName:)` 会静默返回空图，
/// 新增图标后需对照 CoreGlyphs 的 name_availability 校验一次。
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
/// 传入分类色时是实心渐变底 + 白色字形（与列表行 `SettingsIcon` 同一语言）；
/// emoji 自带颜色，固定使用中性底。
struct ModuleIconTile: View {
    let name: String
    var size: CGFloat = Theme.Icon.tile
    /// nil 表示中性瓦片（emoji 场景或未分类）。
    var tint: Color? = nil

    private var corner: CGFloat { Theme.Icon.corner(for: size) }
    private var isEmoji: Bool { name.hasPrefix("emoji:") }

    var body: some View {
        ZStack {
            if let tint, !isEmoji {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(tint.gradient)
                ModuleIcon(name: name, glyphSize: Theme.Icon.glyph(for: size))
                    .foregroundStyle(.white)
            } else {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(Color.p4Tile)
                ModuleIcon(name: name, glyphSize: Theme.Icon.glyph(for: size))
                    .foregroundStyle(Color.accentColor)
            }
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
    /// 标题行图标的分类色。
    var iconTint: Color = .p4Accent

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// 只有警告/错误才给数值上色；正常状态用主文字色，保持版面安静。
    private var valueColor: Color {
        switch tone {
        case .warn: return .p4Warn
        case .err: return .p4Err
        default: return value == "—" ? .secondary : .primary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(iconTint)
                    .frame(width: 24, height: 24)
                    .background(iconTint.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.caption.weight(.medium))
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
            // 设备每 500ms 刷新一次，逐值动画等于让数字一直处于运动中（高频交互不动画）。
            // 等宽数字已经保证不抖动，这里只保留内容过渡给「模式切换」这类低频变化用。
            if let footnote {
                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            }
        }
        .padding(Theme.spacing(1.75))
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .p4CardSurface(cornerRadius: Theme.Radius.card - 2)
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
