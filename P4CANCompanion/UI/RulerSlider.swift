import SwiftUI

/// 横向刻度尺（参考时钟/闹钟的时间调节）：拖动中间刻度过数，按步进吸附，带触感反馈。
///
/// 设计取向（对齐 HIG）：
/// - 数值是主角：大号圆体 + 等宽数字，单位单独降级为次要色，避免读成数值的一部分；
/// - 交互只做一件事：左右拖动选值，点击刻度也能直接跳过去；
/// - 可访问性：整体作为一个 `.adjustable` 元素，VoiceOver 上下滑动即可增减，
///   并读出「当前值 + 单位」，不依赖视觉刻度；
/// - 动态字体：刻度标签用 `.caption2`（随系统缩放），数值用 `.title2`，
///   并允许在极小宽度下按 0.8 缩放而不是截断。
struct RulerSlider: View {
    let title: String
    let unit: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    /// 每隔多少步显示一个数字刻度（其余只画短线）。
    var majorEvery: Int = 5
    /// 副标题（例如换算公式），可选。
    var caption: String? = nil

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var position: Int?

    /// 刻度间距随动态字体放大：辅助功能字号下数字会变宽，
    /// 维持 14pt 会让「50 / 100 / 150」挤成一串。
    private var tickWidth: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 26 : (dynamicTypeSize >= .xxLarge ? 18 : 14)
    }

    private var rulerHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 76 : 58
    }

    private var values: [Int] {
        Array(stride(from: range.lowerBound, through: range.upperBound, by: step))
    }

    private var clampedValue: Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ruler
            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text("\(clampedValue) \(unit)"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                setValue(clampedValue + step, animated: true)
            case .decrement:
                setValue(clampedValue - step, animated: true)
            @unknown default:
                break
            }
        }
        .onAppear { position = clampedValue }
        .onChange(of: position) { _, newValue in
            guard let newValue, newValue != clampedValue else { return }
            value = min(max(newValue, range.lowerBound), range.upperBound)
        }
        .onChange(of: value) { _, newValue in
            // 外部（设备回读 / 撤销）改变数值时，把刻度尺同步过去。
            let target = min(max(newValue, range.lowerBound), range.upperBound)
            guard position != target else { return }
            withAnimation(.snappy(duration: 0.18)) { position = target }
        }
        .sensoryFeedback(.selection, trigger: clampedValue)
    }

    // MARK: - 数值标题

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .layoutPriority(1)
            Spacer(minLength: 8)
            Text("\(clampedValue)")
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .contentTransition(.numericText(value: Double(clampedValue)))
            Text(unit)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityHidden(true)
    }

    // MARK: - 刻度尺

    private var ruler: some View {
        GeometryReader { proxy in
            // 让首尾刻度也能停在正中：左右各留半个容器宽的边距。
            let inset = max(proxy.size.width / 2 - tickWidth / 2, 0)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(values, id: \.self) { item in
                        tick(item)
                            .id(item)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, inset, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $position, anchor: .center)
            .overlay(alignment: .center) { centerMarker }
        }
        .frame(height: rulerHeight)
        .background(Color.p4Tile.opacity(0.55), in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        }
    }

    private func tick(_ item: Int) -> some View {
        let isMajor = (item - range.lowerBound) % (step * majorEvery) == 0
        let isSelected = item == clampedValue
        return VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(isSelected ? Color.accentColor : Color.secondary.opacity(isMajor ? 0.55 : 0.28))
                .frame(width: isMajor ? 1.6 : 1, height: isMajor ? 20 : 11)
                .frame(height: 22, alignment: .bottom)
            if isMajor {
                Text("\(item)")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .fixedSize()
            }
        }
        .frame(width: tickWidth, alignment: .center)
        .contentShape(Rectangle())
        .onTapGesture {
            setValue(item, animated: true)
        }
    }

    private var centerMarker: some View {
        VStack(spacing: 0) {
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(Color.accentColor)
                .offset(y: -1)
            Spacer(minLength: 0)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - 写入

    private func setValue(_ target: Int, animated: Bool) {
        let clamped = min(max(target, range.lowerBound), range.upperBound)
        if animated {
            withAnimation(.snappy(duration: 0.18)) { position = clamped }
        } else {
            position = clamped
        }
        value = clamped
        Haptics.impact()
    }
}
