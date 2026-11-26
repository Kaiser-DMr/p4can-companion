import SwiftUI
import Charts

/// 「状态」页：设备总览。
///
/// 数据完全来自固件网页同源接口：
/// `snapshot?groups=home-fast[&slow=1]`（nag / blink / summon / cantraffic / r79）
/// + `profile/status`（车型与三路总线角色）+ `features/status`（能力位）。
///
/// 信息层级（自上而下）：
/// 1. 设备与连接（谁、在线吗、多久前同步）
/// 2. 关键指标（挡位 / AP / NOA / 扭矩）
/// 3. 快捷开关（NAG / 转向灯 / TLSSC）
/// 4. 三路 CAN 健康度（状态、收发、成功率、占比）
/// 5. 扭矩趋势（当前 / 峰值 / 均值 + 曲线）
/// 6. 车型与能力、蓝牙、升级、设备（次要）
///
/// 每张卡片是独立视图，只读取自己展示的数据：轮询更新扭矩时只重绘指标与曲线，
/// 不会让整页（含 Swift Charts）在滚动中重算。
struct DashboardView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var showsGuide = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: Theme.spacing(2)) {
                        // 断了但手上有数据（内存里的上次数值或磁盘缓存）时，仍然展示真实内容，
                        // 只在顶部提示「离线预览」，避免整页变成空白。
                        if environment.isOnline || environment.phase == .connecting || environment.hasRenderableData {
                            content
                        } else {
                            DashboardOfflineContent(onShowGuide: { showsGuide = true })
                        }
                        Color.clear.frame(height: 1).id("p4bottom")
                    }
                    .padding(.horizontal, Theme.spacing(2))
                    .padding(.top, Theme.spacing(1))
                    .padding(.bottom, Theme.spacing(2))
                    // 宽度只由容器决定：iPhone 上等于屏幕宽，iPad / Mac 窗口上封顶到 720 并居中。
                    // 用 containerRelativeFrame 而不是 frame(maxWidth:)，是因为后者允许子视图
                    // 用「理想宽度」把内容撑出屏幕（大字号时曾出现 484 > 393 的横向溢出）。
                    .containerRelativeFrame(.horizontal) { length, _ in
                        min(length, Theme.Layout.contentMaxWidth)
                    }
                }
                .background(Color.p4Background)
                .refreshable { await environment.refreshOnce() }
                #if DEBUG
                // 本地联调：SIMCTL_CHILD_P4CAN_SCROLL=bottom 时自动滚到底部（便于截图核对）
                .task {
                    let anchor = ProcessInfo.processInfo.environment["P4CAN_SCROLL"] ?? ""
                    guard ["bottom", "trend", "can"].contains(anchor) else { return }
                    try? await Task.sleep(for: .seconds(2))
                    switch anchor {
                    case "trend": proxy.scrollTo("p4trend", anchor: .top)
                    case "can": proxy.scrollTo("p4can", anchor: .top)
                    default: proxy.scrollTo("p4bottom", anchor: .bottom)
                    }
                }
                #endif
                .p4RootPage(L10n.t("状态", "Status"))
                .sheet(isPresented: $showsGuide) { ConnectionGuideView() }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        DashboardStaleBanner(onShowGuide: { showsGuide = true })
        DashboardHeroCard()
        DashboardSetupModeBanner()
        DashboardKPIGrid()
        DashboardBatteryCard()
        DashboardQuickStrip()
        DashboardCanBusCard().id("p4can")
        DashboardTrendCard().id("p4trend")
        DashboardVehicleCard()
        DashboardBluetoothCard()
        DashboardOTACard()
        DashboardDeviceCard()
        #if !targetEnvironment(macCatalyst)
        DashboardLiveActivityCard()
        #endif
    }
}

// MARK: - 共用推导

/// 连接阶段对应的色调与文案（主视觉卡与离线态共用）。
private enum DashboardConnection {
    @MainActor
    static func tone(_ environment: AppEnvironment) -> P4Tone {
        if environment.isOnline { return .ok }
        if case .offline = environment.phase { return .err }
        return .warn
    }

    @MainActor
    static func text(_ environment: AppEnvironment) -> String {
        if environment.isOnline { return L10n.t("在线", "Online") }
        if case .offline = environment.phase { return L10n.t("离线", "Offline") }
        return L10n.t("连接中", "Connecting")
    }
}

/// 三路 CAN 在线统计（主视觉胶囊与 CAN 卡共用）。
private enum DashboardBuses {
    static func onlineCount(_ buses: [CanBusSnapshot]) -> Int {
        buses.filter(\.isOnline).count
    }

    static func tone(_ buses: [CanBusSnapshot]) -> P4Tone {
        guard !buses.isEmpty else { return .neutral }
        let online = onlineCount(buses)
        if online == buses.count { return .ok }
        return online == 0 ? .err : .warn
    }
}

/// S3XY 蓝牙总开关的展示（主视觉胶囊与蓝牙卡共用）。
private enum DashboardBluetooth {
    @MainActor
    static func text(_ s3xy: P4JSON?) -> String {
        guard let on = s3xy?["bluetoothEnabled"]?.boolValue else { return "—" }
        return on ? L10n.t("开", "ON") : L10n.t("关", "OFF")
    }

    static func tone(_ s3xy: P4JSON?) -> P4Tone {
        guard let on = s3xy?["bluetoothEnabled"]?.boolValue else { return .neutral }
        return on ? .ok : .neutral
    }
}

// MARK: - 1. 设备与连接

/// 离线 / 使用缓存时的提示条；在线时不占布局。
private struct DashboardStaleBanner: View {
    @Environment(AppEnvironment.self) private var environment
    let onShowGuide: () -> Void

    var body: some View {
        if !environment.isOnline {
            HStack(alignment: .top, spacing: Theme.spacing(1)) {
                Image(systemName: environment.isShowingCachedData ? "clock.arrow.circlepath" : "wifi.slash")
                    .font(.footnote.weight(.semibold))
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(environment.isShowingCachedData
                         ? "离线预览 · 显示上次缓存的数据"
                         : "连接已断开 · 显示断开前的数据")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.primary)
                    if let date = environment.cachedAt ?? environment.lastUpdated {
                        Text(L10n.t("数据时间 \(date.formatted(date: .abbreviated, time: .standard)) · 恢复连接后自动刷新", "Data from \(date.formatted(date: .abbreviated, time: .standard)) · refreshes when reconnected"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Button(action: onShowGuide) {
                    Text(L10n.t("排查", "Fix"))
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel(L10n.t("打开连接排查", "Open connection troubleshooting"))
            }
            .padding(.horizontal, Theme.spacing(1.5))
            .padding(.vertical, Theme.spacing(1))
            .background(
                Color.p4Warn.opacity(0.12),
                in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
            )
            .accessibilityElement(children: .contain)
        }
    }
}

private struct DashboardHeroCard: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let tone = DashboardConnection.tone(environment)
        VStack(alignment: .leading, spacing: Theme.spacing(1.5)) {
            HStack(alignment: .top, spacing: Theme.spacing(1)) {
                VStack(alignment: .leading, spacing: 4) {
                    connectionChip(tone: tone)
                    Text(environment.profileName ?? environment.deviceName)
                        .font(.system(.title, design: .rounded).weight(.bold))
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                        .minimumScaleFactor(0.7)
                        .padding(.top, 4)
                    Text(heroSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                }
                Spacer(minLength: 0)
                // 连接后车辆图缩小到标题右侧，把版面让给实时数据；未连接时下方展示大图
                if compactVehicle {
                    DashboardVehicleImage()
                        .frame(width: 132, height: 74)
                        .transition(.opacity)
                }
            }

            if !compactVehicle {
                DashboardVehicleImage()
                    .frame(height: dynamicTypeSize.isAccessibilitySize ? 140 : 170)
                    .transition(.opacity)
            }

            DashboardHeroChips()

            Divider().opacity(0.6)

            // 同步时间与刷新间隔：大字号下改为两行，不再挤在一行里被裁切。
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    DashboardSyncTimeLabel()
                    Spacer(minLength: Theme.spacing(1))
                    pollIntervalLabel
                }
                VStack(alignment: .leading, spacing: 2) {
                    DashboardSyncTimeLabel()
                    pollIntervalLabel
                }
            }
            .foregroundStyle(.secondary)
        }
        .padding(Theme.spacing(2.5))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [tone.color.opacity(0.16), tone.color.opacity(0.0)],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            ),
            in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        )
        .p4CardSurface()
        .animation(.easeInOut(duration: 0.4), value: tone)
        .animation(.easeInOut(duration: 0.4), value: compactVehicle)
        .accessibilityElement(children: .combine)
    }

    /// 大字号下标题需要整行宽度，车辆图始终放在下方
    private var compactVehicle: Bool { environment.isOnline && !dynamicTypeSize.isAccessibilitySize }

    private func connectionChip(tone: P4Tone) -> some View {
        let text = DashboardConnection.text(environment)
        return HStack(spacing: 6) {
            LiveDot(color: tone.color, isLive: environment.isOnline)
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tone.color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(tone.color.opacity(0.12), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }

    private var pollIntervalLabel: some View {
        Text(environment.isOnline
             ? L10n.t("每 \(environment.pollIntervalMs) ms 自动同步",
                      "Auto-sync every \(environment.pollIntervalMs) ms")
             : L10n.t("等待设备", "Waiting for device"))
            .font(.caption2)
    }

    private var heroSubtitle: String {
        var parts: [String] = []
        if environment.deviceFamily == .t2can { parts.append("T2CAN") }
        if let topology = environment.topologyName { parts.append(topology) }
        if let fw = environment.systemStats?["fwVersion"]?.stringValue ?? environment.stat("fwVersion")?.stringValue {
            parts.append(L10n.t("固件 \(fw)", "FW \(fw)"))
        }
        if parts.isEmpty, let turn = environment.profileStatus?["turnName"]?.stringValue {
            parts.append(L10n.t("拨杆 \(turn)", "Stalk \(turn)"))
        }
        return parts.isEmpty ? L10n.t("正在读取设备信息…", "Reading device info…") : parts.joined(separator: " · ")
    }
}

/// 主视觉卡的车辆图：按设备车型（或用户在「车辆外观」中指定的车型）显示配置器图片，挡位决定视角。
/// 挡位所在的快照分组每拍都会刷新，这里只把车型外观与视角这两个值交给图片视图，值不变时图片视图不重绘。
private struct DashboardVehicleImage: View {
    @Environment(AppEnvironment.self) private var environment
    @AppStorage(VehicleAppearanceKeys.generation) private var generationID = ""
    @AppStorage(VehicleAppearanceKeys.trim) private var trimCode = ""
    @AppStorage(VehicleAppearanceKeys.paint) private var paintCode = ""
    @AppStorage(VehicleAppearanceKeys.wheel) private var wheelCode = ""

    var body: some View {
        let device = VehicleBodyStyle.resolve(profileID: environment.profileID, name: environment.profileName)
        let appearance = VehicleCatalog.resolve(generationID: generationID, trim: trimCode, paint: paintCode,
                                                wheel: wheelCode, deviceGenerationID: device.generationID)
        let gear = environment.isOnline ? environment.group("r79")["gearName"]?.stringValue : nil
        VehicleHeroImage(appearance: appearance, angle: VehicleAngle.forGear(gear))
            .equatable()
    }
}

/// 主视觉卡的 CAN / 蓝牙胶囊：总线计数每拍都在变，单独成视图，只重绘这两颗胶囊。
private struct DashboardHeroChips: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let buses = environment.canBuses
        // 三颗胶囊按可用宽度自动换行：大字号 / 窄屏下不会把「蓝牙开」压成竖排。
        P4FlowLayout(spacing: Theme.spacing(1), lineSpacing: Theme.spacing(0.75)) {
            StatusChip(text: "CAN \(DashboardBuses.onlineCount(buses))/\(max(buses.count, 1))",
                       systemImage: "cable.connector", tone: DashboardBuses.tone(buses))
            StatusChip(text: "\(L10n.t("蓝牙", "BT")) \(DashboardBluetooth.text(environment.s3xyStats))",
                       systemImage: "dot.radiowaves.left.and.right",
                       tone: DashboardBluetooth.tone(environment.s3xyStats))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 「已同步 · 时间」：每拍都变，单独成视图。
private struct DashboardSyncTimeLabel: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath").font(.caption2)
            Text(updatedText).font(.caption2).monospacedDigit()
        }
    }

    private var updatedText: String {
        guard let date = environment.lastUpdated else { return "尚未同步" }
        let time = date.formatted(date: .omitted, time: .standard)
        return L10n.t("已同步 · \(time)", "Synced · \(time)")
    }
}

private struct DashboardSetupModeBanner: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        if environment.isSetupMode {
            Label(
                L10n.t("设备处于 Setup 模式：CAN 注入已禁用，需在设备网页选择车型并重启。", "Setup mode: CAN injection is disabled. Choose the vehicle profile on the device page and reboot."),
                systemImage: "gear.badge.questionmark"
            )
            .font(.footnote)
            .foregroundStyle(.p4Warn)
            .padding(Theme.spacing(2))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.p4Warn.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        }
    }
}

// MARK: - 2. 关键指标

private struct DashboardKPIGrid: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let r79 = environment.group("r79")
        let nag = environment.group("nag")
        let blink = environment.group("blink")
        LazyVGrid(
            // 自适应列：iPhone 竖屏 2 列，iPad / Mac 窗口自动变 3–4 列，指标不再被拉宽。
            columns: [GridItem(.adaptive(minimum: 158), spacing: Theme.spacing(1.5))],
            spacing: Theme.spacing(1.5)
        ) {
            MetricTile(
                icon: "steeringwheel",
                title: L10n.t("挡位", "Gear"),
                value: r79["gearName"]?.stringValue ?? "—",
                tone: .info,
                footnote: gearFootnote(r79),
                iconTint: P4Palette.indigo
            )
            MetricTile(
                icon: "car.side",
                title: L10n.t("AP 状态", "AP"),
                value: boolText(nag["apActive"]?.boolValue, on: L10n.t("激活", "Active"), off: L10n.t("未激活", "Inactive")),
                tone: nag["apActive"]?.boolValue == true ? .ok : .neutral,
                footnote: L10n.t("自动辅助驾驶", "Autopilot"),
                iconTint: P4Palette.blue
            )
            MetricTile(
                icon: "road.lanes",
                title: "NOA",
                value: boolText(blink["noaActive"]?.boolValue, on: L10n.t("激活", "Active"), off: L10n.t("未激活", "Inactive")),
                tone: blink["noaActive"]?.boolValue == true ? .ok : .neutral,
                footnote: L10n.t("导航辅助驾驶", "Navigate on Autopilot"),
                iconTint: P4Palette.teal
            )
            MetricTile(
                icon: "gauge.with.dots.needle.50percent",
                title: L10n.t("扭矩", "Torque"),
                value: nag["torque"]?.doubleValue.map { String(format: "%.2f", $0) } ?? "—",
                unit: "N·m",
                tone: .info,
                footnote: L10n.t("方向盘实时扭矩", "Live wheel torque"),
                iconTint: P4Palette.orange
            )
        }
    }

    private func gearFootnote(_ r79: [String: P4JSON]) -> String {
        if let source = r79["gearSourceName"]?.stringValue, !source.isEmpty {
            return L10n.t("来源 \(source)", "via \(source)")
        }
        return L10n.t("R79 挡位", "R79 gear")
    }

    private func boolText(_ value: Bool?, on: String, off: String) -> String {
        guard let value else { return "—" }
        return value ? on : off
    }
}

// MARK: - 2.1 电池（固件提供才显示）

/// 固件目前没有解码 SOC；一旦某个版本在任意端点里给出
/// `batterySoc / soc / batteryLevel`（+ 可选 `rangeKm`），这里会自动出现，不会伪造数据。
private struct DashboardBatteryCard: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        if let soc = batterySoc {
            let fraction = min(max(soc / 100, 0), 1)
            Card(title: L10n.t("电池", "Battery"), systemImage: "battery.75percent", tint: P4Palette.green) {
                HStack(spacing: Theme.spacing(2.5)) {
                    RingGauge(value: fraction, tint: socTone(fraction), lineWidth: 10) {
                        HStack(alignment: .firstTextBaseline, spacing: 1) {
                            Text(String(format: "%.0f", soc))
                                .font(.system(.title, design: .rounded).weight(.bold))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                            Text("%").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 104, height: 104)
                    .accessibilityLabel(L10n.t("剩余电量", "Battery level"))

                    VStack(alignment: .leading, spacing: Theme.spacing(1.5)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(soc <= 20 ? L10n.t("电量偏低", "Low") : L10n.t("剩余电量", "Remaining"))
                                .font(.caption)
                                .foregroundStyle(soc <= 20 ? Color.p4Err : .secondary)
                            Text(String(format: "%.0f%%", soc))
                                .font(.system(.headline, design: .rounded))
                                .monospacedDigit()
                        }
                        if let range = batteryRangeKm {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.t("预估续航", "Est. range"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.0f km", range))
                                    .font(.system(.headline, design: .rounded))
                                    .monospacedDigit()
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var batterySoc: Double? {
        for key in ["batterySoc", "soc", "batteryLevel", "stateOfCharge"] {
            if let value = environment.stat(key)?.doubleValue { return value }
        }
        return nil
    }

    private var batteryRangeKm: Double? {
        for key in ["rangeKm", "batteryRangeKm", "ratedRangeKm", "idealRangeKm"] {
            if let value = environment.stat(key)?.doubleValue { return value }
        }
        return nil
    }

    private func socTone(_ fraction: Double) -> Color {
        if fraction <= 0.15 { return .p4Err }
        if fraction <= 0.30 { return .p4Warn }
        return .p4OK
    }
}

// MARK: - 3. 快捷开关

/// 首页快捷开关（对应网页 homeQuickStrip：NAG / 自动转向灯 / TLSSC）。
private struct DashboardQuickStrip: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        Card(title: L10n.t("快捷开关", "Quick toggles"), systemImage: "switch.2", tint: P4Palette.purple) {
            VStack(spacing: Theme.spacing(1)) {
                quickRow(
                    title: L10n.t("NAG 抑制", "NAG suppression"),
                    subtitle: L10n.t("方向盘扭矩注入", "Torque injection"),
                    systemImage: "hands.and.sparkles",
                    tint: P4Palette.blue,
                    isOn: environment.nagConfig?["enabled"]?.boolValue,
                    supported: environment.capability("nagSupported") != false,
                    action: { value in
                        Task {
                            await environment.command(
                                "NAG 开关", path: P4Route.nagUpdate,
                                query: [P4Param("enabled", value ? "1" : "0")]
                            )
                        }
                    }
                )
                Divider().padding(.leading, 44)
                quickRow(
                    title: L10n.t("自动转向灯", "Auto blinker"),
                    subtitle: L10n.t("拨杆触发自动打灯", "Stalk-triggered blinker"),
                    systemImage: "arrow.triangle.turn.up.right.diamond.fill",
                    tint: P4Palette.orange,
                    isOn: environment.group("blink")["enabled"]?.boolValue,
                    supported: environment.capability("advancedEapSupported") != false,
                    action: { value in
                        Task {
                            await environment.command(
                                "自动转向灯",
                                path: value ? P4Route.blinkAEnable : P4Route.blinkADisable
                            )
                        }
                    }
                )
                Divider().padding(.leading, 44)
                quickRow(
                    title: L10n.t("TLSSC 注入", "TLSSC injection"),
                    subtitle: L10n.t("交通灯与停止标志控制", "Traffic light & stop sign control"),
                    systemImage: "car.top.radiowaves.rear.right",
                    tint: P4Palette.green,
                    isOn: environment.group("summon")["tlssc"]?.boolValue
                        ?? environment.slowGroups["summon"]?["tlssc"]?.boolValue,
                    supported: true,
                    action: { value in
                        Task {
                            await environment.command(
                                "TLSSC",
                                path: value ? P4Route.summonTLSSCEnable : P4Route.summonTLSSCDisable
                            )
                        }
                    }
                )
            }
        }
    }

    private func quickRow(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        isOn: Bool?,
        supported: Bool,
        action: @escaping (Bool) -> Void
    ) -> some View {
        HStack(spacing: Theme.spacing(1.5)) {
            SettingsIcon(systemImage: systemImage, tint: tint, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.medium))
                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: Theme.spacing(1))
            if !supported {
                StatusChip(text: "不支持", tone: .neutral)
            }
            if let isOn {
                Toggle("", isOn: Binding(get: { isOn }, set: { action($0) }))
                    .labelsHidden()
                    .disabled(!supported || environment.isBusy || environment.isSetupMode)
                    .accessibilityLabel(L10n.t("\(title)开关", "\(title) switch"))
            } else {
                Text("读取中…")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 4. 三路 CAN

/// 三路 CAN（CAN 1 BODY / CAN 2 CHASSIS / CAN 3 PARTY）。
private struct DashboardCanBusCard: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let buses = environment.canBuses
        Card(title: L10n.t("CAN 总线", "CAN buses"), systemImage: "cable.connector", tint: P4Palette.teal) {
            if buses.isEmpty {
                Text(L10n.t("快照 cantraffic 组尚未返回，请在「全部数据」查看 /api/snapshot。", "The cantraffic group has not returned yet; check /api/snapshot under All data."))
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                let tone = DashboardBuses.tone(buses)
                let online = DashboardBuses.onlineCount(buses)
                VStack(alignment: .leading, spacing: Theme.spacing(1.5)) {
                    HStack {
                        StatusChip(
                            text: L10n.t("\(online)/\(buses.count) 在线", "\(online)/\(buses.count) online"),
                            systemImage: tone.symbol,
                            tone: tone
                        )
                        Spacer(minLength: Theme.spacing(1))
                        Text(environment.topologyName ?? "")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(Array(buses.enumerated()), id: \.element.id) { index, bus in
                        if index > 0 { Divider().opacity(0.6) }
                        busRow(bus)
                    }

                    if totalRxCount(buses) > 0 {
                        Divider().opacity(0.6)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("接收帧占比").font(.caption2).foregroundStyle(.secondary)
                            RatioBar(segments: rxSegments(buses))
                        }
                    }

                    NavigationLink {
                        LiveDataView()
                    } label: {
                        Label(L10n.t("查看全部总线字段", "All bus fields"), systemImage: "list.bullet.rectangle")
                            .font(.footnote.weight(.medium))
                    }
                }
            }
        }
    }

    private func busRow(_ bus: CanBusSnapshot) -> some View {
        let tone = bus.isOnline ? P4Tone.ok : (bus.state == 0 ? .neutral : .err)
        return VStack(alignment: .leading, spacing: Theme.spacing(1)) {
            HStack(alignment: .center, spacing: Theme.spacing(0.5)) {
                Circle()
                    .fill(tone.color)
                    .frame(width: 8, height: 8)
                Text(bus.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: Theme.spacing(1))
                StatusChip(text: bus.stateText, systemImage: P4BusState.symbol(for: bus.stateText), tone: tone)
            }

            // 三个计数保持固定组距（不再各占 1/3 宽度），宽屏下不会散落到卡片两端。
            HStack(alignment: .firstTextBaseline, spacing: Theme.spacing(2.5)) {
                counter("收", bus.rxCount)
                counter("发", bus.txAccepted)
                counter("拒", bus.txRejected ?? 0, tone: (bus.txRejected ?? 0) > 0 ? .warn : .neutral)
                Spacer(minLength: Theme.spacing(1))
                if let busOff = bus.busOff, busOff > 0 {
                    StatusChip(text: "Bus-Off \(P4Format.number(busOff))", tone: .err)
                } else if let age = bus.trafficAgeMs, age >= 0 {
                    Text(L10n.t("\(P4Format.milliseconds(age))前", "\(P4Format.milliseconds(age)) ago"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if let rate = successRate(bus) {
                HStack(spacing: Theme.spacing(1)) {
                    SlimProgress(value: rate, tint: tone.color)
                    Text("\(Int(rate * 100))%")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.t("\(bus.displayName) 发送成功率 \(Int(rate * 100))%", "\(bus.displayName) TX success rate \(Int(rate * 100))%"))
            }
        }
    }

    private func counter(_ label: String, _ value: Int64?, tone: P4Tone = .neutral) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value.map { P4Format.number($0) } ?? "—")
                .font(.system(.caption, design: .monospaced).weight(.medium))
                .foregroundStyle(value == nil ? .secondary : (tone == .neutral ? Color.primary : tone.color))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value.map { P4Format.number($0) } ?? L10n.t("无数据", "no data"))")
    }

    /// 发送成功率 = 接受 / (接受 + 拒绝)；无数据返回 nil（不显示假的 100%）。
    private func successRate(_ bus: CanBusSnapshot) -> Double? {
        guard let accepted = bus.txAccepted else { return nil }
        let rejected = bus.txRejected ?? 0
        let total = Double(accepted) + Double(rejected)
        guard total > 0 else { return nil }
        return Double(accepted) / total
    }

    private func totalRxCount(_ buses: [CanBusSnapshot]) -> Int64 {
        buses.reduce(Int64(0)) { $0 + max($1.rxCount ?? 0, 0) }
    }

    private func rxSegments(_ buses: [CanBusSnapshot]) -> [RatioBar.Segment] {
        let palette: [Color] = [.p4Info, .teal, .indigo]
        return buses.enumerated().compactMap { index, bus in
            guard let rx = bus.rxCount, rx > 0 else { return nil }
            return RatioBar.Segment(
                id: "\(bus.id)",
                label: "CAN \(bus.index)",
                value: Double(rx),
                color: palette[min(index, palette.count - 1)]
            )
        }
    }
}

// MARK: - 5. 扭矩趋势

/// 只依赖 `trendSamples`（最多 1 s 一点），快照其它字段变化不会让曲线重算。
private struct DashboardTrendCard: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let samples = environment.trendSamples
        Card(title: L10n.t("扭矩趋势 · 近 3 分钟", "Torque trend · last 3 min"), systemImage: "chart.xyaxis.line", tint: P4Palette.orange) {
            if samples.count < 2 {
                Text(L10n.t("等待 NAG 扭矩数据（需车辆唤醒）…", "Waiting for NAG torque (wake the car)…"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                let values = samples.map(\.torqueNm)
                let average = values.reduce(0, +) / Double(values.count)
                HStack(spacing: Theme.spacing(2)) {
                    trendStat("当前", value: values.last, tone: .info)
                    trendStat("峰值", value: values.max(), tone: .warn)
                    trendStat("均值", value: average, tone: .neutral)
                }

                Chart {
                    ForEach(samples) { sample in
                        AreaMark(
                            x: .value("时间", sample.date),
                            y: .value("扭矩", sample.torqueNm)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            .linearGradient(
                                colors: [Color.p4Info.opacity(0.26), Color.p4Info.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        LineMark(
                            x: .value("时间", sample.date),
                            y: .value("扭矩", sample.torqueNm)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Color.p4Info)
                    }
                    RuleMark(y: .value("均值", average))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(Color.secondary.opacity(0.5))
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine().foregroundStyle(Color.secondary.opacity(0.15))
                        AxisValueLabel().font(.caption2)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) {
                        AxisValueLabel(format: .dateTime.minute().second())
                            .font(.caption2)
                    }
                }
                .frame(height: 140)
                .accessibilityLabel("近三分钟方向盘扭矩趋势图")
            }
        }
    }

    private func trendStat(_ title: String, value: Double?, tone: P4Tone) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value.map { String(format: "%.2f", $0) } ?? "—")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                Text("N·m").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.t("\(title) \(value.map { String(format: "%.2f", $0) } ?? "无数据") 牛米",
                                    "\(title) \(value.map { String(format: "%.2f", $0) } ?? "no data") N·m"))
    }
}

// MARK: - 6. 车型与能力

private struct DashboardVehicleCard: View {
    @Environment(AppEnvironment.self) private var environment

    private struct CapabilityChip: Identifiable {
        let id: String
        let icon: String
        let supported: Bool?
    }

    var body: some View {
        Card(title: L10n.t("车型与能力", "Vehicle & capabilities"), systemImage: "car.side.fill", tint: P4Palette.indigo) {
            VStack(alignment: .leading, spacing: Theme.spacing(1.5)) {
                if let profileName = environment.profileName {
                    HStack(spacing: Theme.spacing(1)) {
                        Text(profileName)
                            .font(.headline)
                        if let topology = environment.topologyName {
                            StatusChip(text: topology, tone: .info)
                        }
                        Spacer(minLength: 0)
                    }
                }

                HStack(spacing: Theme.spacing(1.5)) {
                    if let canA = environment.profileStatus?["canA"]?.stringValue {
                        roleChip("CAN A", canA)
                    }
                    if let canB = environment.profileStatus?["canB"]?.stringValue {
                        roleChip("CAN B", canB)
                    }
                    if let extra = environment.profileStatus?["canExtra"]?.stringValue {
                        roleChip("PARTY", extra)
                    }
                }

                Divider().opacity(0.6)
                capabilityGrid
            }
        }
    }

    private func roleChip(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.weight(.medium)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, Theme.spacing(1))
        .padding(.vertical, 6)
        .background(Color.p4Tile, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.t("\(title) 角色 \(value)", "\(title) role \(value)"))
    }

    private var capabilityGrid: some View {
        let items: [CapabilityChip] = [
            .init(id: "NAG", icon: "hands.and.sparkles", supported: environment.capability("nagSupported")),
            .init(id: "ADV EAP", icon: "arrow.triangle.branch", supported: environment.capability("advancedEapSupported")),
            .init(id: "EU UNLOCK", icon: "lock.open", supported: environment.capability("euUnlockSupported")),
            .init(id: "PEDAL MAP", icon: "slider.horizontal.3", supported: environment.capability("pedalMapSupported")),
            .init(id: "BODY CTRL", icon: "car.side.front.open", supported: environment.capability("bodyControlsSupported")),
        ]
        return LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 148), spacing: Theme.spacing(1))],
            alignment: .leading,
            spacing: Theme.spacing(1)
        ) {
            ForEach(items) { item in
                let tone: P4Tone = item.supported == true ? .ok : .neutral
                HStack(spacing: 5) {
                    Image(systemName: item.icon).font(.caption2.weight(.semibold))
                    Text(item.id)
                        .font(.caption2.weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Spacer(minLength: 0)
                    Image(systemName: item.supported == true ? "checkmark" : (item.supported == false ? "minus" : "questionmark"))
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(tone.color)
                .padding(.horizontal, Theme.spacing(1))
                .padding(.vertical, 7)
                .background(tone.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(item.id) \(item.supported == true ? L10n.t("支持", "supported") : item.supported == false ? L10n.t("不支持", "unsupported") : L10n.t("未知", "unknown"))")
            }
        }
    }
}

// MARK: - 7. 次要信息

private struct DashboardBluetoothCard: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let s3xy = environment.s3xyStats
        Card(title: L10n.t("蓝牙（S3XY）", "Bluetooth (S3XY)"), systemImage: "dot.radiowaves.left.and.right", tint: P4Palette.blue) {
            HStack(spacing: Theme.spacing(2)) {
                bluetoothStat(title: L10n.t("总开关", "Enabled"), value: DashboardBluetooth.text(s3xy), tone: DashboardBluetooth.tone(s3xy))
                bluetoothStat(title: L10n.t("已配对", "Paired"), value: s3xy?["pairedCount"]?.intValue.map(String.init) ?? "—")
                bluetoothStat(title: L10n.t("已连接", "Connected"), value: s3xy?["connectedCount"]?.intValue.map(String.init) ?? "—")
                Spacer(minLength: 0)
            }
            Text("在「蓝牙」标签页完成扫描、配对与动作绑定")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func bluetoothStat(title: String, value: String, tone: P4Tone = .neutral) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.system(.subheadline, design: .rounded).weight(.semibold)).monospacedDigit()
                .foregroundStyle(tone == .neutral ? Color.primary : tone.color)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value)")
    }
}

private struct DashboardOTACard: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        Card(title: L10n.t("固件升级", "Firmware update"), systemImage: "arrow.down.circle.fill", tint: P4Palette.cyan) {
            if let ota = environment.otaStatus?.objectValue,
               ota["inProgress"]?.boolValue == true {
                let received = ota["receivedBytes"]?.doubleValue ?? 0
                let total = ota["totalBytes"]?.doubleValue ?? 0
                VStack(alignment: .leading, spacing: Theme.spacing(1)) {
                    SlimProgress(
                        value: total > 0 ? received / total : 0,
                        tint: .p4Info,
                        height: 8,
                        label: "\(ota["stage"]?.stringValue ?? "写入") · \(P4Format.bytes(Int64(received))) / \(P4Format.bytes(Int64(total)))"
                    )
                }
            } else {
                HStack {
                    StatusChip(text: L10n.t("空闲", "Idle"), systemImage: "checkmark.circle", tone: .neutral)
                    Spacer()
                    Text("在「系统」页上传 .ino.bin").font(.caption).foregroundStyle(.secondary)
                }
                // `error` 是字符串（失败原因），不是布尔；按非空判断，否则失败态永远不显示。
                if let message = environment.otaStatus?["error"]?.stringValue, !message.isEmpty {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.p4Err)
                }
            }
        }
    }
}

private struct DashboardDeviceCard: View {
    @Environment(AppEnvironment.self) private var environment

    private static let deviceKeys = ["fwVersion", "freeHeap", "minFreeHeap", "largestHeapBlock", "uptimeS"]

    var body: some View {
        Card(title: L10n.t("设备", "Device"), systemImage: "memorychip", tint: P4Palette.gray) {
            VStack(spacing: Theme.spacing(1)) {
                ForEach(Self.deviceKeys, id: \.self) { key in
                    if let value = environment.systemStats?[key] ?? environment.stat(key) {
                        MetricRow(key: key, value: value)
                    }
                }
            }
            .font(.subheadline)
        }
    }
}

/// 锁屏 / 灵动岛实时活动开关。
private struct DashboardLiveActivityCard: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        Card(title: L10n.t("锁屏与灵动岛", "Lock screen & Dynamic Island"), systemImage: "platter.filled.top.and.arrow.up.iphone", tint: P4Palette.pink) {
            Toggle(isOn: Binding(
                get: { environment.liveActivityEnabled },
                set: { environment.setLiveActivity($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("显示实时状态").font(.subheadline)
                    Text(L10n.t("总线在线情况 + 挡位 + NAG / Blink / TLSSC", "Bus status + gear + NAG / Blink / TLSSC"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!environment.isLiveActivitySupported)
            .accessibilityLabel("锁屏与灵动岛实时状态开关")
            if !environment.isLiveActivitySupported {
                Text(L10n.t("系统已关闭实时活动权限，可在 设置 → P4管家 中开启。", "Live Activities are off. Enable them in Settings → P4管家."))
                    .font(.caption2)
                    .foregroundStyle(.p4Warn)
            }
        }
    }
}

// MARK: - 离线态

private struct DashboardOfflineContent: View {
    @Environment(AppEnvironment.self) private var environment
    let onShowGuide: () -> Void

    var body: some View {
        VStack(spacing: Theme.spacing(2)) {
            DashboardHeroCard()
            Card(title: L10n.t("等待设备", "Waiting for device"), systemImage: "antenna.radiowaves.left.and.right", tint: P4Palette.orange) {
                VStack(alignment: .leading, spacing: Theme.spacing(1.5)) {
                    if case .offline(let reason) = environment.phase {
                        Label(reason, systemImage: "wifi.exclamationmark")
                            .font(.subheadline)
                            .foregroundStyle(.p4Err)
                    } else {
                        Text("正在连接设备…").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Button("查看连接引导", action: onShowGuide)
                        .font(.subheadline.weight(.medium))
                }
                SkeletonRows(count: 4)
            }
        }
    }
}
