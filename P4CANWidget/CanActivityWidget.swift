import SwiftUI
import WidgetKit

#if !targetEnvironment(macCatalyst)
import ActivityKit

/// 灵动岛 + 锁屏实时活动界面。
///
/// 设计约束（HIG）：
/// - 灵动岛紧凑区只放最关键信息（在线总线数 + 挡位），避免拥挤；
/// - 展开区呈现三路总线与三个功能开关状态；
/// - 状态同时用图标与文字表达，不单独依赖颜色；
/// - 深色/浅色由系统渲染，使用语义色。
struct CanActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CanActivityAttributes.self) { context in
            LockScreenView(state: context.state, deviceName: context.attributes.deviceName)
                .activityBackgroundTint(Color(uiColor: .secondarySystemBackground))
                .activitySystemActionForegroundColor(Color.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(
                        vehicleTitle(
                            model: context.state.vehicleModel,
                            gear: context.state.gear,
                            fallback: context.attributes.deviceName
                        ),
                        systemImage: "car.side"
                    )
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(context.state.updatedAt.formatted(date: .omitted, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if let gear = validGear(context.state.gear) {
                            Text(gear)
                                .font(.caption2.weight(.semibold))
                                .monospacedDigit()
                        }
                    }
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        ForEach(context.state.buses) { bus in
                            HStack(spacing: 6) {
                                Image(systemName: bus.online ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                    .foregroundStyle(bus.online ? Color.green : Color.red)
                                    .font(.caption)
                                Text(bus.name)
                                    .font(.caption2.weight(.medium))
                                Spacer(minLength: 4)
                                Text(bus.detail)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        HStack(spacing: 8) {
                            chip("NAG", on: context.state.nagEnabled)
                            chip("Blink", on: context.state.blinkEnabled)
                            chip("TLSSC", on: context.state.tlsscEnabled)
                        }
                        .padding(.top, 2)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: "cable.connector")
                    .foregroundStyle(.tint)
            } compactTrailing: {
                Text("\(onlineCount(context.state))/\(max(context.state.buses.count, 3))")
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
            } minimal: {
                Image(systemName: "cable.connector")
                    .foregroundStyle(.tint)
            }
            .keylineTint(.accentColor)
        }
    }

    private func onlineCount(_ state: CanActivityAttributes.ContentState) -> Int {
        state.buses.filter(\.online).count
    }

    private func chip(_ title: String, on: Bool) -> some View {
        Text("\(title) \(on ? "开" : "关")")
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background((on ? Color.green : Color.secondary).opacity(0.18), in: Capsule())
            .foregroundStyle(on ? Color.green : Color.secondary)
    }
}

/// 固件在无挡位信号时上报 UNKNOWN；此时优先展示车型。
private func validGear(_ gear: String) -> String? {
    let value = gear.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty, value != "UNKNOWN", value != "—" else { return nil }
    return value
}

private func vehicleTitle(model: String?, gear: String, fallback: String) -> String {
    if let model, !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return model
    }
    return validGear(gear) ?? fallback
}

/// 锁屏卡片。
struct LockScreenView: View {
    let state: CanActivityAttributes.ContentState
    let deviceName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(
                    vehicleTitle(model: state.vehicleModel, gear: state.gear, fallback: deviceName),
                    systemImage: "car.side"
                )
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                Spacer()
                if let gear = validGear(state.gear) {
                    Text(gear)
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                }
                Text(state.updatedAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ForEach(state.buses) { bus in
                HStack(spacing: 6) {
                    Image(systemName: bus.online ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .font(.caption2)
                        .foregroundStyle(bus.online ? Color.green : Color.red)
                    Text(bus.name).font(.caption2.weight(.medium))
                    Spacer(minLength: 4)
                    Text(bus.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            HStack(spacing: 8) {
                chip("NAG", on: state.nagEnabled)
                chip("Blink", on: state.blinkEnabled)
                chip("TLSSC", on: state.tlsscEnabled)
            }
        }
        .padding(12)
    }

    private func chip(_ title: String, on: Bool) -> some View {
        Text("\(title) \(on ? "开" : "关")")
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background((on ? Color.green : Color.secondary).opacity(0.18), in: Capsule())
            .foregroundStyle(on ? Color.green : Color.secondary)
    }
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
