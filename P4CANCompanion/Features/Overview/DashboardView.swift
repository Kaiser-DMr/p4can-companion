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
struct DashboardView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var showsGuide = false

    private var updatedText: String {
        guard let date = environment.lastUpdated else { return "尚未同步" }
        return "已同步 · \(date.formatted(date: .omitted, time: .standard))"
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: Theme.spacing(2)) {
                        if environment.isOnline || environment.phase == .connecting {
                            content
                        } else {
                            offlineContent
                        }
                        Color.clear.frame(height: 1).id("p4bottom")
                    }
                    .padding(.horizontal, Theme.spacing(2))
                    .padding(.vertical, Theme.spacing(2))
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
                .overlay(alignment: .bottom) { ToastOverlay() }
                .navigationTitle("设备状态")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Color.p4Background, for: .navigationBar)
                .sheet(isPresented: $showsGuide) { ConnectionGuideView() }
            }
        }
    }

    // MARK: - 内容

    @ViewBuilder
    private var content: some View {
        heroCard
        setupModeBanner
        kpiGrid
        batteryCard
        quickStrip
        canBusCard.id("p4can")
        trendCard.id("p4trend")
        vehicleCard
        bluetoothCard
        otaCard
        deviceCard
        #if !targetEnvironment(macCatalyst)
        liveActivityCard
        #endif
    }

    // MARK: - 1. 设备与连接

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(1.5)) {
            HStack(alignment: .top, spacing: Theme.spacing(1)) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(connectionTone.color)
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(environment.profileName ?? "P4-CAN")
                        .font(.title2.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(heroSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: Theme.spacing(1))
                StatusChip(text: connectionText, systemImage: connectionTone.symbol, tone: connectionTone)
            }

            HStack(spacing: Theme.spacing(1)) {
                StatusChip(text: "CAN \(onlineBusCount)/\(max(environment.canBuses.count, 1))", systemImage: "cable.connector", tone: busTone)
                StatusChip(text: "\(L10n.t("蓝牙", "BT")) \(bluetoothText)",
                           systemImage: "dot.radiowaves.left.and.right", tone: bluetoothTone)
                StatusChip(text: "LAB \(labText)", systemImage: "flask", tone: labTone)
                Spacer(minLength: 0)
            }

            Divider().opacity(0.6)

            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath").font(.caption2)
                Text(updatedText).font(.caption2)
                Spacer(minLength: Theme.spacing(1))
                Text(environment.isOnline
                     ? L10n.t("每 \(environment.pollIntervalMs) ms 自动同步",
                              "Auto-sync every \(environment.pollIntervalMs) ms")
                     : L10n.t("等待设备", "Waiting for device"))
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
        }
        .padding(Theme.spacing(2))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.p4Card, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .accessibilityElement(children: .combine)
    }

    private var connectionTone: P4Tone {
        if environment.isOnline { return .ok }
        if case .offline = environment.phase { return .err }
        return .warn
    }

    private var connectionText: String {
        if environment.isOnline { return "在线" }
        if case .offline = environment.phase { return "离线" }
        return "连接中"
    }

    private var heroSubtitle: String {
        var parts: [String] = []
        if let topology = environment.topologyName { parts.append(topology) }
        if let fw = environment.systemStats?["fwVersion"]?.stringValue ?? environment.stat("fwVersion")?.stringValue {
            parts.append("固件 \(fw)")
        }
        if parts.isEmpty, let turn = environment.profileStatus?["turnName"]?.stringValue {
            parts.append("拨杆 \(turn)")
        }
        return parts.isEmpty ? "正在读取设备信息…" : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var setupModeBanner: some View {
        if environment.isSetupMode {
            Label(
                "设备处于 Setup 模式：CAN 注入已禁用，需在设备网页选择车型并重启。",
                systemImage: "gear.badge.questionmark"
            )
            .font(.footnote)
            .foregroundStyle(.p4Warn)
            .padding(Theme.spacing(2))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.p4Warn.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        }
    }

    // MARK: - 2. 关键指标

    private var kpiGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: Theme.spacing(1)), GridItem(.flexible(), spacing: Theme.spacing(1))],
            spacing: Theme.spacing(1)
        ) {
            MetricTile(
                icon: "steeringwheel",
                title: "挡位",
                value: environment.group("r79")["gearName"]?.stringValue ?? "—",
                tone: .info,
                footnote: gearFootnote
            )
            MetricTile(
                icon: "car.side",
                title: "AP 状态",
                value: boolText(environment.group("nag")["apActive"]?.boolValue, on: "激活", off: "未激活"),
                tone: environment.group("nag")["apActive"]?.boolValue == true ? .ok : .neutral,
                footnote: "自动辅助驾驶"
            )
            MetricTile(
                icon: "road.lanes",
                title: "NOA",
                value: boolText(environment.group("blink")["noaActive"]?.boolValue, on: "激活", off: "未激活"),
                tone: environment.group("blink")["noaActive"]?.boolValue == true ? .ok : .neutral,
                footnote: "导航辅助驾驶"
            )
            MetricTile(
                icon: "gauge.with.dots.needle.50percent",
                title: "扭矩",
                value: torqueText,
                unit: "N·m",
                tone: .info,
                footnote: "方向盘实时扭矩"
            )
        }
    }

    private var gearFootnote: String {
        if let source = environment.group("r79")["gearSourceName"]?.stringValue, !source.isEmpty {
            return "来源 \(source)"
        }
        return "R79 挡位"
    }

    private var torqueText: String {
        guard let torque = environment.group("nag")["torque"]?.doubleValue else { return "—" }
        return String(format: "%.2f", torque)
    }

    private func boolText(_ value: Bool?, on: String, off: String) -> String {
        guard let value else { return "—" }
        return value ? on : off
    }

    // MARK: - 2.1 电池（固件提供才显示）

    /// 固件目前没有解码 SOC；一旦某个版本在任意端点里给出
    /// `batterySoc / soc / batteryLevel`（+ 可选 `rangeKm`），这里会自动出现，不会伪造数据。
    private var batterySoc: (key: String, value: Double)? {
        for key in ["batterySoc", "soc", "batteryLevel", "stateOfCharge"] {
            if let value = environment.stat(key)?.doubleValue {
                return (key, value)
            }
        }
        return nil
    }

    private var batteryRangeKm: Double? {
        for key in ["rangeKm", "batteryRangeKm", "ratedRangeKm", "idealRangeKm"] {
            if let value = environment.stat(key)?.doubleValue {
                return value
            }
        }
        return nil
    }

    @ViewBuilder
    private var batteryCard: some View {
        if let soc = batterySoc {
            let fraction = min(max(soc.value / 100, 0), 1)
            Card(title: "电池", systemImage: "battery.75percent") {
                HStack(alignment: .firstTextBaseline, spacing: Theme.spacing(1)) {
                    Text(String(format: "%.0f", soc.value))
                        .font(Theme.TypeScale.metric(30))
                        .monospacedDigit()
                    Text("%").font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: Theme.spacing(1))
                    if let range = batteryRangeKm {
                        Label(String(format: "%.0f km", range), systemImage: "road.lanes")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                SlimProgress(
                    value: fraction,
                    tint: socTone(fraction),
                    height: 8,
                    label: soc.value <= 20 ? "电量偏低" : "剩余电量"
                )
            }
        }
    }

    private func socTone(_ fraction: Double) -> Color {
        if fraction <= 0.15 { return .p4Err }
        if fraction <= 0.30 { return .p4Warn }
        return .p4OK
    }

    // MARK: - 3. 快捷开关

    /// 首页快捷开关（对应网页 homeQuickStrip：NAG / 自动转向灯 / TLSSC）。
    private var quickStrip: some View {
        Card(title: "快捷开关", systemImage: "switch.2") {
            VStack(spacing: Theme.spacing(1)) {
                quickRow(
                    title: "NAG 抑制",
                    subtitle: "方向盘扭矩注入",
                    systemImage: "hands.and.sparkles",
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
                Divider()
                quickRow(
                    title: "自动转向灯",
                    subtitle: "拨杆触发自动打灯",
                    systemImage: "arrow.triangle.turn.up.right.diamond",
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
                Divider()
                quickRow(
                    title: "TLSSC 注入",
                    subtitle: "交通灯与停止标志控制",
                    systemImage: "car.top.radiowaves.rear.right",
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
        isOn: Bool?,
        supported: Bool,
        action: @escaping (Bool) -> Void
    ) -> some View {
        HStack(spacing: Theme.spacing(1.5)) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 30, height: 30)
                .background(Color.p4Tile, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
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
                    .accessibilityLabel("\(title)开关")
            } else {
                Text("读取中…")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 4. 三路 CAN

    /// 三路 CAN（CAN 1 BODY / CAN 2 CHASSIS / CAN 3 PARTY）。
    private var canBusCard: some View {
        Card(title: "CAN 总线", systemImage: "cable.connector") {
            if environment.canBuses.isEmpty {
                Text("快照 cantraffic 组尚未返回，请在「全部数据」查看 /api/snapshot。")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: Theme.spacing(1.5)) {
                    HStack {
                        StatusChip(
                            text: "\(onlineBusCount)/\(environment.canBuses.count) 在线",
                            systemImage: busTone.symbol,
                            tone: busTone
                        )
                        Spacer(minLength: Theme.spacing(1))
                        Text("canBusCount = \(environment.stat("canBusCount")?.displayText ?? "—")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(Array(environment.canBuses.enumerated()), id: \.element.id) { index, bus in
                        if index > 0 { Divider().opacity(0.6) }
                        busRow(bus, colorIndex: index)
                    }

                    if totalRxCount > 0 {
                        Divider().opacity(0.6)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("接收帧占比").font(.caption2).foregroundStyle(.secondary)
                            RatioBar(segments: rxSegments)
                        }
                    }

                    NavigationLink {
                        LiveDataView()
                    } label: {
                        Label("查看全部总线字段", systemImage: "chevron.right")
                            .font(.footnote.weight(.medium))
                    }
                }
            }
        }
    }

    private func busRow(_ bus: CanBusSnapshot, colorIndex: Int) -> some View {
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

            HStack(alignment: .firstTextBaseline, spacing: 0) {
                counter("收", bus.rxCount)
                    .frame(maxWidth: .infinity, alignment: .leading)
                counter("发", bus.txAccepted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                counter("拒", bus.txRejected ?? 0, tone: (bus.txRejected ?? 0) > 0 ? .warn : .neutral)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let busOff = bus.busOff, busOff > 0 {
                    StatusChip(text: "Bus-Off \(P4Format.number(busOff))", tone: .err)
                } else if let age = bus.trafficAgeMs, age >= 0 {
                    Text("\(P4Format.milliseconds(age))前")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
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
                .accessibilityLabel("\(bus.displayName) 发送成功率 \(Int(rate * 100))%")
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
        .accessibilityLabel("\(label) \(value.map { P4Format.number($0) } ?? "无数据")")
    }

    /// 发送成功率 = 接受 / (接受 + 拒绝)；无数据返回 nil（不显示假的 100%）。
    private func successRate(_ bus: CanBusSnapshot) -> Double? {
        guard let accepted = bus.txAccepted else { return nil }
        let rejected = bus.txRejected ?? 0
        let total = Double(accepted) + Double(rejected)
        guard total > 0 else { return nil }
        return Double(accepted) / total
    }

    private var totalRxCount: Int64 {
        environment.canBuses.reduce(Int64(0)) { $0 + max($1.rxCount ?? 0, 0) }
    }

    private var rxSegments: [RatioBar.Segment] {
        let palette: [Color] = [.p4Info, .teal, .indigo]
        return environment.canBuses.enumerated().compactMap { index, bus in
            guard let rx = bus.rxCount, rx > 0 else { return nil }
            return RatioBar.Segment(
                id: "\(bus.id)",
                label: "CAN \(bus.index)",
                value: Double(rx),
                color: palette[min(index, palette.count - 1)]
            )
        }
    }

    private var onlineBusCount: Int {
        environment.canBuses.filter(\.isOnline).count
    }

    private var busTone: P4Tone {
        guard !environment.canBuses.isEmpty else { return .neutral }
        if onlineBusCount == environment.canBuses.count { return .ok }
        return onlineBusCount == 0 ? .err : .warn
    }

    private var bluetoothText: String {
        guard let on = environment.s3xyStats?["bluetoothEnabled"]?.boolValue else { return "—" }
        return on ? L10n.t("开", "ON") : L10n.t("关", "OFF")
    }

    private var bluetoothTone: P4Tone {
        guard let on = environment.s3xyStats?["bluetoothEnabled"]?.boolValue else { return .neutral }
        return on ? .ok : .neutral
    }

    private var labText: String {
        guard let on = environment.featuresStatus?["lab"]?.boolValue else { return "—" }
        return on ? L10n.t("开", "ON") : L10n.t("关", "OFF")
    }

    private var labTone: P4Tone {
        guard let on = environment.featuresStatus?["lab"]?.boolValue else { return .neutral }
        return on ? .info : .neutral
    }

    // MARK: - 5. 扭矩趋势

    private var trendCard: some View {
        Card(title: "扭矩趋势 · 近 3 分钟", systemImage: "chart.xyaxis.line") {
            if environment.trendSamples.count < 2 {
                Text("等待 NAG 扭矩数据（需车辆唤醒）…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: Theme.spacing(2)) {
                    trendStat("当前", value: environment.trendSamples.last?.torqueNm, tone: .info)
                    trendStat("峰值", value: environment.trendSamples.map(\.torqueNm).max(), tone: .warn)
                    trendStat("均值", value: averageTorque, tone: .neutral)
                }

                Chart {
                    ForEach(environment.trendSamples) { sample in
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
                    if let average = averageTorque {
                        RuleMark(y: .value("均值", average))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(Color.secondary.opacity(0.5))
                    }
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

    private var averageTorque: Double? {
        let values = environment.trendSamples.map(\.torqueNm)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
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
        .accessibilityLabel("\(title) \(value.map { String(format: "%.2f", $0) } ?? "无数据") 牛米")
    }

    // MARK: - 6. 车型与能力

    private var vehicleCard: some View {
        Card(title: "车型与能力", systemImage: "car.side") {
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
        .accessibilityLabel("\(title) 角色 \(value)")
    }

    private struct CapabilityChip: Identifiable {
        let id: String
        let icon: String
        let supported: Bool?
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
            columns: [GridItem(.flexible(), spacing: Theme.spacing(1)), GridItem(.flexible(), spacing: Theme.spacing(1))],
            alignment: .leading,
            spacing: Theme.spacing(1)
        ) {
            ForEach(items) { item in
                let tone: P4Tone = item.supported == true ? .ok : (item.supported == false ? .neutral : .neutral)
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
                .accessibilityLabel("\(item.id) \(item.supported == true ? "支持" : item.supported == false ? "不支持" : "未知")")
            }
        }
    }

    // MARK: - 7. 次要信息

    private var bluetoothCard: some View {
        Card(title: "蓝牙（S3XY）", systemImage: "dot.radiowaves.left.and.right") {
            HStack(spacing: Theme.spacing(2)) {
                bluetoothStat(title: "总开关", value: bluetoothText, tone: bluetoothTone)
                bluetoothStat(title: "已配对", value: environment.s3xyStats?["pairedCount"]?.intValue.map(String.init) ?? "—")
                bluetoothStat(title: "已连接", value: environment.s3xyStats?["connectedCount"]?.intValue.map(String.init) ?? "—")
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

    private var otaCard: some View {
        Card(title: "固件升级", systemImage: "arrow.down.circle") {
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
                    StatusChip(text: "空闲", systemImage: "checkmark.circle", tone: .neutral)
                    Spacer()
                    Text("在「系统」页上传 .ino.bin").font(.caption).foregroundStyle(.secondary)
                }
                if let error = environment.otaStatus?["error"]?.boolValue, error {
                    Label(environment.otaStatus?["updateError"]?.stringValue ?? "上次升级失败", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.p4Err)
                }
            }
        }
    }

    private var deviceCard: some View {
        Card(title: "设备", systemImage: "memorychip") {
            VStack(spacing: Theme.spacing(1)) {
                ForEach(deviceKeys, id: \.self) { key in
                    if let value = environment.systemStats?[key] ?? environment.stat(key) {
                        MetricRow(key: key, value: value)
                    }
                }
            }
        }
    }

    private var deviceKeys: [String] {
        ["fwVersion", "freeHeap", "minFreeHeap", "largestHeapBlock", "uptimeS"]
    }

    /// 锁屏 / 灵动岛实时活动开关。
    private var liveActivityCard: some View {
        Card(title: "锁屏与灵动岛", systemImage: "platter.filled.top.and.arrow.up.iphone") {
            Toggle(isOn: Binding(
                get: { environment.liveActivityEnabled },
                set: { environment.setLiveActivity($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("显示实时状态").font(.subheadline)
                    Text("三路总线在线情况 + 挡位 + NAG / Blink / TLSSC")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!environment.isLiveActivitySupported)
            .accessibilityLabel("锁屏与灵动岛实时状态开关")
            if !environment.isLiveActivitySupported {
                Text("系统已关闭实时活动权限，可在 设置 → P4管家 中开启。")
                    .font(.caption2)
                    .foregroundStyle(.p4Warn)
            }
        }
    }

    // MARK: - 离线态

    private var offlineContent: some View {
        VStack(spacing: Theme.spacing(2)) {
            heroCard
            Card(title: "等待设备", systemImage: "antenna.radiowaves.left.and.right") {
                VStack(alignment: .leading, spacing: Theme.spacing(1.5)) {
                    if case .offline(let reason) = environment.phase {
                        Label(reason, systemImage: "wifi.exclamationmark")
                            .font(.subheadline)
                            .foregroundStyle(.p4Err)
                    } else {
                        Text("正在连接设备…").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Button("查看连接引导") { showsGuide = true }
                        .font(.subheadline.weight(.medium))
                }
                SkeletonRows(count: 4)
            }
        }
    }
}
