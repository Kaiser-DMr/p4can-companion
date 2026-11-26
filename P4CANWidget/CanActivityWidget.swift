import SwiftUI
import WidgetKit

#if !targetEnvironment(macCatalyst)
import ActivityKit

/// 灵动岛 + 锁屏实时活动界面。
///
/// 设计约束（HIG）：
/// - 锁屏卡片高度不超过 160 pt：车型行、四格指标、三路总线、功能开关四行；
/// - 灵动岛紧凑区只放挡位与一项关键数值；展开区受高度限制，放车型、指标与总线，功能开关只在锁屏显示；
/// - 状态同时用图标、文字表达，不单独依赖颜色；深浅色由系统渲染，使用语义色；
/// - 固件没有上报的数据（电量、续航等）不显示占位假值。
struct CanActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CanActivityAttributes.self) { context in
            LockScreenView(state: context.state, deviceName: context.attributes.deviceName, isStale: context.isStale)
                .activitySystemActionForegroundColor(Color.primary)
        } dynamicIsland: { context in
            let state = context.state
            let text = Copy(english: state.english ?? false)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        VehicleArt(name: state.vehicleArtwork)
                            .frame(width: 84, height: 32, alignment: .leading)
                        Text(vehicleTitle(state, fallback: context.attributes.deviceName))
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 3) {
                        GearBadge(gear: state.gear, size: 34)
                        BusSummary(state: state, text: text)
                    }
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        MetricRow(state: state, text: text, compact: true)
                        HStack(spacing: 6) {
                            ForEach(state.buses) { BusPill(bus: $0, text: text) }
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
                }
            } compactLeading: {
                GearBadge(gear: state.gear, size: 22)
            } compactTrailing: {
                CompactValue(state: state)
            } minimal: {
                GearBadge(gear: state.gear, size: 22)
            }
            .keylineTint(gearTint(state.gear))
        }
    }
}

// MARK: - 锁屏

struct LockScreenView: View {
    let state: CanActivityAttributes.ContentState
    let deviceName: String
    let isStale: Bool

    private var text: Copy { Copy(english: state.english ?? false) }

    var body: some View {
        VStack(spacing: 7) {
            HStack(alignment: .center, spacing: 10) {
                VehicleArt(name: state.vehicleArtwork)
                    .frame(width: 92, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(vehicleTitle(state, fallback: deviceName))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    HStack(spacing: 4) {
                        if isStale {
                            Image(systemName: "clock.badge.exclamationmark")
                            Text(text.stale)
                        } else {
                            BusSummary(state: state, text: text)
                            Text("· \(state.updatedAt.formatted(date: .omitted, time: .shortened))")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                GearBadge(gear: state.gear, size: 38)
            }

            MetricRow(state: state, text: text, compact: false)

            HStack(spacing: 6) {
                ForEach(state.buses) { BusPill(bus: $0, text: text) }
            }

            FeatureRow(state: state, text: text)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .opacity(isStale ? 0.6 : 1)
    }
}

// MARK: - 组件

/// 中英文案：Widget 扩展拿不到 App 的语言设置，由 App 随状态传入。
struct Copy {
    let english: Bool
    func t(_ zh: String, _ en: String) -> String { english ? en : zh }

    var stale: String { t("数据已过期，打开 App 刷新", "Stale. Open the app to refresh") }
    var battery: String { t("电量", "Battery") }
    var range: String { t("续航", "Range") }
    var torque: String { t("扭矩", "Torque") }
    var active: String { t("激活", "On") }
    var inactive: String { t("未激活", "Off") }
    var blink: String { t("爆闪", "Strobe") }
    func buses(_ online: Int, _ total: Int) -> String { t("总线 \(online)/\(total)", "Bus \(online)/\(total)") }
}

/// 挡位徽章：P 灰、R 橙、N 蓝、D 绿；没有挡位信号时显示短横。
struct GearBadge: View {
    let gear: String
    let size: CGFloat

    var body: some View {
        let value = validGear(gear)
        Text(value ?? "–")
            .font(.system(size: size * 0.52, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(gearTint(gear).gradient, in: Circle())
            .accessibilityLabel(value.map { "挡位 \($0)" } ?? "挡位未知")
    }
}

struct VehicleArt: View {
    let name: String?

    var body: some View {
        if let name {
            Image(name)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .accessibilityHidden(true)
        } else {
            Image(systemName: "car.side.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}

/// 四格指标：电量、续航、AP、扭矩；固件没有电量时用 NOA 补位。
struct MetricRow: View {
    let state: CanActivityAttributes.ContentState
    let text: Copy
    let compact: Bool

    var body: some View {
        HStack(spacing: 6) {
            ForEach(items, id: \.title) { item in
                VStack(alignment: .leading, spacing: 1) {
                    Label(item.title, systemImage: item.icon)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(item.tint)
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text(item.value)
                            .font(.system(size: compact ? 14 : 15, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if let unit = item.unit {
                            Text(unit)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
        }
    }

    private struct Item {
        let title: String
        let icon: String
        let value: String
        let unit: String?
        let tint: Color
    }

    private var items: [Item] {
        var result: [Item] = []
        if let soc = state.batterySoc {
            result.append(Item(title: text.battery, icon: batteryIcon(soc), value: String(format: "%.0f", soc), unit: "%",
                               tint: soc <= 20 ? .red : (soc <= 30 ? .orange : .green)))
            result.append(Item(title: text.range, icon: "road.lanes", value: state.rangeKm.map { String(format: "%.0f", $0) } ?? "–",
                               unit: state.rangeKm == nil ? nil : "km", tint: .teal))
        } else {
            result.append(Item(title: "NOA", icon: "point.topleft.down.to.point.bottomright.curvepath",
                               value: onOff(state.noaActive), unit: nil, tint: .teal))
        }
        result.append(Item(title: "AP", icon: "steeringwheel", value: onOff(state.apActive), unit: nil, tint: .blue))
        result.append(Item(title: text.torque, icon: "gauge.with.dots.needle.50percent",
                           value: state.torque.map { String(format: "%.1f", $0) } ?? "–",
                           unit: state.torque == nil ? nil : "N·m", tint: .orange))
        return result
    }

    private func onOff(_ value: Bool?) -> String {
        guard let value else { return "–" }
        return value ? text.active : text.inactive
    }

    private func batteryIcon(_ soc: Double) -> String {
        switch soc {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

/// 单路总线：在线点 + 总线名 + 每秒收帧数。
struct BusPill: View {
    let bus: CanBusActivityState
    let text: Copy

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: bus.online ? "circle.fill" : "xmark.circle.fill")
                .font(.system(size: bus.online ? 6 : 9))
                .foregroundStyle(bus.online ? Color.green : Color.red)
            Text(bus.shortName ?? bus.name)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .layoutPriority(1)
            Spacer(minLength: 2)
            Text(rateText)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background((bus.online ? Color.green : Color.red).opacity(0.12), in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private var rateText: String {
        guard bus.online else { return text.t("离线", "Off") }
        guard let rate = bus.rxPerSecond else { return "" }
        return rate >= 1000 ? String(format: "%.1fk/s", Double(rate) / 1000) : "\(rate)/s"
    }
}

/// NAG / 爆闪 / TLSSC 三个功能开关。
struct FeatureRow: View {
    let state: CanActivityAttributes.ContentState
    let text: Copy

    var body: some View {
        HStack(spacing: 6) {
            chip("NAG", icon: "hand.raised.fill", on: state.nagEnabled)
            chip(text.blink, icon: "light.beacon.max.fill", on: state.blinkEnabled)
            chip("TLSSC", icon: "car.rear.waves.up.fill", on: state.tlsscEnabled)
            Spacer(minLength: 0)
        }
    }

    private func chip(_ title: String, icon: String, on: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
            Text(title)
        }
        .font(.system(size: 10, weight: .semibold))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .foregroundStyle(on ? Color.accentColor : Color.secondary)
        .background((on ? Color.accentColor : Color.secondary).opacity(on ? 0.16 : 0.1), in: Capsule())
        .accessibilityLabel("\(title) \(on ? text.t("开", "on") : text.t("关", "off"))")
    }
}

/// 在线总线数（带状态点）。
struct BusSummary: View {
    let state: CanActivityAttributes.ContentState
    let text: Copy

    var body: some View {
        let online = state.buses.filter(\.online).count
        let total = state.buses.count
        HStack(spacing: 3) {
            Circle()
                .fill(total > 0 && online == total ? Color.green : (online > 0 ? Color.orange : Color.red))
                .frame(width: 6, height: 6)
            Text(text.buses(online, total))
                .monospacedDigit()
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}

/// 灵动岛紧凑区右侧：有电量显示电量，否则显示在线总线数。
struct CompactValue: View {
    let state: CanActivityAttributes.ContentState

    var body: some View {
        if let soc = state.batterySoc {
            Text(String(format: "%.0f%%", soc))
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(soc <= 20 ? Color.red : Color.green)
        } else {
            let online = state.buses.filter(\.online).count
            Text("\(online)/\(state.buses.count)")
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(online == state.buses.count ? Color.green : Color.orange)
        }
    }
}

/// 固件在无挡位信号时上报 UNKNOWN；此时不显示挡位字母。
private func validGear(_ gear: String) -> String? {
    let value = gear.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    guard ["P", "R", "N", "D"].contains(value) else { return nil }
    return value
}

private func gearTint(_ gear: String) -> Color {
    switch validGear(gear) {
    case "D": return .green
    case "R": return .orange
    case "N": return .blue
    case "P": return Color(.systemGray)
    default: return Color(.systemGray3)
    }
}

private func vehicleTitle(_ state: CanActivityAttributes.ContentState, fallback: String) -> String {
    if let model = state.vehicleModel, !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return model
    }
    return fallback
}

#else

// MARK: - Mac Catalyst 回退

/// Mac 上没有灵动岛与锁屏实时活动（ActivityKit 不可用），
/// 扩展仍保留一个静态状态组件，用于「通知中心 / 桌面」查看连接说明。
struct CatalystStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "P4CANStatusWidget", provider: CatalystStatusProvider()) { _ in
            VStack(alignment: .leading, spacing: 4) {
                Label("P4-CAN", systemImage: "cable.connector")
                    .font(.caption.weight(.semibold))
                Text("控制台在 Mac 窗口中运行")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
        }
        .configurationDisplayName("P4-CAN 状态")
        .description("在 Mac 上快速打开 P4-CAN 控制台。")
        .supportedFamilies([.systemSmall])
    }
}

private struct CatalystStatusEntry: TimelineEntry {
    let date: Date
}

private struct CatalystStatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> CatalystStatusEntry {
        CatalystStatusEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (CatalystStatusEntry) -> Void) {
        completion(CatalystStatusEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CatalystStatusEntry>) -> Void) {
        completion(Timeline(entries: [CatalystStatusEntry(date: Date())], policy: .never))
    }
}

#endif
