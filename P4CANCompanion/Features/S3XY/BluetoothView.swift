import SwiftUI

/// 「蓝牙」页：S3XY 按键的扫描、配对、连接与动作绑定。
///
/// 与固件 s3xy_ble.h 的契约：
/// - 设备以槽位 `id` 标识，`address` 为 BLE MAC；
/// - 配对 `pair?address=`；连接 / 断开 / 握手 / 忘记 / 自动重连 均带 `id`；
/// - 动作绑定 `device/action?id=&gesture=single|double|long&action=<code>`；
/// - 扫描结果来自 stats 的 `scanResults[]`（含 registered 标记）；
/// - 蓝牙总开关为独立端点。
struct BluetoothView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var renaming: S3XYDevice?
    @State private var renameText = ""
    @State private var forgetting: S3XYDevice?
    @State private var pendingGlobal: GlobalAction?
    @State private var shareURL: URL?
    /// 总开关的乐观值：点下立即变化，设备回读后清除。
    @State private var pendingBluetooth: Bool?

    private enum GlobalAction: String, Identifiable {
        case resetAll
        case clear

        var id: String { rawValue }
    }

    private enum Gesture: String, CaseIterable {
        case single, double, long

        @MainActor var title: String {
            switch self {
            case .single: return L10n.t("单击", "Single press")
            case .double: return L10n.t("双击", "Double press")
            case .long: return L10n.t("长按", "Long press")
            }
        }

        func current(_ device: S3XYDevice) -> String {
            switch self {
            case .single: return device.singleAction
            case .double: return device.doubleAction
            case .long: return device.longAction
            }
        }

        func label(_ device: S3XYDevice) -> String {
            switch self {
            case .single: return device.singleLabel
            case .double: return device.doubleLabel
            case .long: return device.longLabel
            }
        }
    }

    // MARK: 数据

    private var stats: P4JSON? {
        environment.endpointValue(P4Route.s3xyStats) ?? environment.s3xyStats
    }
    private var object: [String: P4JSON] { stats?.objectValue ?? [:] }
    private var devices: [S3XYDevice] { S3XYDevice.devices(from: stats) }
    private var scanResults: [S3XYScanResult] { S3XYScanResult.results(from: stats) }
    private var bluetoothOn: Bool? { object["bluetoothEnabled"]?.boolValue }
    private var autoEnabled: Bool? { object["autoEnabled"]?.boolValue }
    private var scanning: Bool { object["scanning"]?.boolValue == true }
    /// 离线时页面显示的是上次读到的数据，所有写操作都会失败，因此一并禁用。
    private var online: Bool { environment.isOnline }
    private var canWrite: Bool { online && !environment.isBusy }

    // MARK: 视图

    var body: some View {
        NavigationStack {
            List {
                Section {
                    heroCard
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section {
                    if devices.isEmpty {
                        emptyRow(L10n.t("还没有配对的按键。打开蓝牙后点「扫描设备」，在扫描结果里配对。",
                                        "No paired buttons yet. Turn Bluetooth on, scan, then pair from the results."))
                    }
                    ForEach(devices) { device in
                        deviceRow(device)
                            .contextMenu {
                                if online { deviceMenu(device) }
                            }
                    }
                } header: {
                    Text(L10n.t("已配对设备", "Paired buttons"))
                }

                Section {
                    if scanResults.isEmpty {
                        emptyRow(scanning ? L10n.t("正在扫描…", "Scanning…")
                                          : L10n.t("暂无扫描结果。", "No scan results."))
                    }
                    ForEach(scanResults) { result in
                        scanRow(result)
                    }
                } header: {
                    Text(L10n.t("扫描结果", "Scan results"))
                } footer: {
                    Text(L10n.t("开关状态以设备上报为准；动作由设备直接执行，固件按当前车型校验可用性。",
                                "States come from the device; actions run on the device and are validated for the current vehicle."))
                }
            }
            .listStyle(.insetGrouped)
            .p4ListStyle()
            .contentMargins(.top, Theme.spacing(0.5), for: .scrollContent)
            .p4RootPage(L10n.t("蓝牙", "Bluetooth"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { globalMenu }
            }
            .refreshable { await refresh() }
            .task { await poll() }
            .alert(L10n.t("重命名设备", "Rename button"), isPresented: Binding(
                get: { renaming != nil },
                set: { if !$0 { renaming = nil } }
            )) {
                TextField(L10n.t("设备名称", "Name"), text: $renameText)
                Button(L10n.t("取消", "Cancel"), role: .cancel) { renaming = nil }
                Button(L10n.t("确定", "Save")) {
                    if let device = renaming {
                        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                        Task { await deviceCommand(L10n.t("重命名", "Rename"), P4Route.s3xyDeviceRename, device,
                                                   extra: [P4Param("name", name.isEmpty ? device.name : name)]) }
                    }
                    renaming = nil
                }
            } message: {
                Text(renaming?.address ?? "")
            }
            .confirmationDialog(
                L10n.t("忘记「\(forgetting?.name ?? "")」？", "Forget “\(forgetting?.name ?? "")”?"),
                isPresented: Binding(get: { forgetting != nil }, set: { if !$0 { forgetting = nil } }),
                titleVisibility: .visible
            ) {
                Button(L10n.t("忘记设备", "Forget"), role: .destructive) {
                    if let device = forgetting {
                        Task { await deviceCommand(L10n.t("忘记设备", "Forget"), P4Route.s3xyDeviceForget, device) }
                    }
                    forgetting = nil
                }
                Button(L10n.t("取消", "Cancel"), role: .cancel) { forgetting = nil }
            } message: {
                Text(L10n.t("配对信息与按键动作会从设备上删除，需要重新配对。",
                            "The pairing and button actions are removed from the device; you will need to pair again."))
            }
            .confirmationDialog(
                pendingGlobal == .resetAll ? L10n.t("重置全部蓝牙？", "Reset all Bluetooth?")
                                           : L10n.t("清除 S3XY 记录？", "Clear S3XY records?"),
                isPresented: Binding(get: { pendingGlobal != nil }, set: { if !$0 { pendingGlobal = nil } }),
                titleVisibility: .visible
            ) {
                Button(L10n.t("确认执行", "Confirm"), role: .destructive) {
                    if let action = pendingGlobal {
                        Task {
                            if action == .resetAll {
                                await globalCommand(L10n.t("重置全部蓝牙", "Reset all Bluetooth"), P4Route.s3xyResetAll)
                            } else {
                                await globalCommand(L10n.t("清除 S3XY 记录", "Clear S3XY records"), P4Route.s3xyClear)
                            }
                        }
                    }
                    pendingGlobal = nil
                }
                Button(L10n.t("取消", "Cancel"), role: .cancel) { pendingGlobal = nil }
            } message: {
                Text(pendingGlobal == .resetAll
                     ? L10n.t("清除所有配对、按键动作与蓝牙设置，设备上的 BLE 任务会重新启动。",
                              "Removes all pairings, button actions and Bluetooth settings; the device restarts its BLE task.")
                     : L10n.t("清除设备上记录的 S3XY 日志与统计。", "Clears the S3XY log and counters stored on the device."))
            }
            .sheet(item: Binding(
                get: { shareURL.map { ShareItem(url: $0) } },
                set: { if $0 == nil { shareURL = nil } }
            )) { item in
                P4ShareSheet(items: [item.url])
            }
        }
    }

    // MARK: 顶部主卡

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(1.5)) {
            // 辅助功能字号下标题、说明与开关挤在一行会被拆成单字竖排，改为上下排。
            if dynamicTypeSize.isAccessibilitySize {
                HStack {
                    SettingsIcon(systemImage: "dot.radiowaves.left.and.right", tint: P4Palette.blue, size: 40)
                    Spacer(minLength: Theme.spacing(1))
                    bluetoothToggle
                }
                heroTitle
            } else {
                HStack(spacing: Theme.Icon.gap) {
                    SettingsIcon(systemImage: "dot.radiowaves.left.and.right", tint: P4Palette.blue, size: 40)
                    heroTitle
                    Spacer(minLength: Theme.spacing(1))
                    bluetoothToggle
                }
            }

            if !online {
                Label(offlineText, systemImage: "wifi.slash")
                    .font(.caption)
                    .foregroundStyle(.p4Warn)
                    .labelStyle(.titleAndIcon)
                    .fixedSize(horizontal: false, vertical: true)
            }

            P4FlowLayout(spacing: Theme.spacing(1), lineSpacing: Theme.spacing(0.75)) {
                StatusChip(text: L10n.t("已配对 \(object["pairedCount"]?.intValue ?? Int64(devices.count))",
                                        "Paired \(object["pairedCount"]?.intValue ?? Int64(devices.count))"),
                           systemImage: "link", tone: .neutral)
                StatusChip(text: L10n.t("已连接 \(object["connectedCount"]?.intValue ?? 0)",
                                        "Connected \(object["connectedCount"]?.intValue ?? 0)"),
                           systemImage: "checkmark.circle",
                           tone: (object["connectedCount"]?.intValue ?? 0) > 0 ? .ok : .neutral)
                if let autoEnabled {
                    StatusChip(text: autoEnabled ? L10n.t("自动重连 开", "Auto-reconnect on")
                                                 : L10n.t("自动重连 关", "Auto-reconnect off"),
                               systemImage: "arrow.triangle.2.circlepath",
                               tone: autoEnabled ? .ok : .neutral)
                }
                if object["cryptoSelfTestOk"]?.boolValue == false {
                    StatusChip(text: L10n.t("加密自检异常", "Crypto self-test failed"),
                               systemImage: P4Tone.err.symbol, tone: .err)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                Task { await scan() }
            } label: {
                HStack(spacing: Theme.spacing(1)) {
                    if scanning {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(systemName: "dot.radiowaves.forward")
                    }
                    Text(scanning ? L10n.t("扫描中…", "Scanning…") : L10n.t("扫描设备", "Scan for buttons"))
                }
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: Theme.Radius.button))
            .disabled(bluetoothOn != true || scanning || !canWrite)

            if let error = object["probeError"]?.stringValue, !error.isEmpty {
                Label(L10n.t("最近探测错误：\(error)", "Last probe error: \(error)"),
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.p4Warn)
                    .labelStyle(.titleAndIcon)
            }
        }
        .padding(Theme.spacing(2))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [P4Palette.blue.opacity(bluetoothOn == true && online ? 0.14 : 0.05), .clear],
                           startPoint: .topTrailing, endPoint: .bottomLeading),
            in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        )
        .p4CardSurface()
    }

    private var heroTitle: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L10n.t("蓝牙总开关", "Bluetooth"))
                .font(.headline)
            Text(bluetoothSubtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var bluetoothToggle: some View {
        Toggle("", isOn: Binding(
            get: { pendingBluetooth ?? bluetoothOn ?? false },
            set: { value in
                pendingBluetooth = value
                Task {
                    await setBluetooth(value)
                    pendingBluetooth = nil
                }
            }
        ))
        .labelsHidden()
        .disabled(bluetoothOn == nil || !canWrite)
        .accessibilityLabel(L10n.t("蓝牙总开关", "Bluetooth"))
    }

    private var bluetoothSubtitle: String {
        guard let bluetoothOn else {
            return online ? L10n.t("读取中…", "Loading…") : L10n.t("未读取到蓝牙状态", "Bluetooth state unavailable")
        }
        if !online { return bluetoothOn ? L10n.t("上次状态：已开启", "Last known: on") : L10n.t("上次状态：已关闭", "Last known: off") }
        return bluetoothOn ? L10n.t("已开启 · 可连接 S3XY 按键", "On · S3XY buttons can connect") : L10n.t("已关闭", "Off")
    }

    private var offlineText: String {
        let reason = environment.endpointError(P4Route.s3xyStats)
        let base = L10n.t("设备未连接，下方为上次读到的数据，操作已暂停", "Device offline. Showing the last known data; actions are paused")
        guard let reason, !reason.isEmpty else { return base }
        return "\(base)（\(reason)）"
    }

    // MARK: 行

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)
    }

    private func deviceRow(_ device: S3XYDevice) -> some View {
        HStack(alignment: .top, spacing: Theme.Icon.gap) {
            SettingsIcon(systemImage: "dot.radiowaves.left.and.right",
                         tint: device.connected ? P4Palette.green : P4Palette.gray)
            VStack(alignment: .leading, spacing: 3) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        Text(device.name).font(.body.weight(.semibold)).lineLimit(1)
                        deviceStateChip(device)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(device.name).font(.body.weight(.semibold))
                        deviceStateChip(device)
                    }
                }
                Text(deviceDetail(device))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(Gesture.allCases.map { "\($0.title) \($0.label(device))" }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let error = device.error, !error.isEmpty {
                    Text(L10n.t("错误：\(error)", "Error: \(error)"))
                        .font(.caption)
                        .foregroundStyle(.p4Err)
                }
            }
            Spacer(minLength: 0)
            Menu {
                deviceMenu(device)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(!online)
            .accessibilityLabel(L10n.t("\(device.name) 操作", "\(device.name) actions"))
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func deviceStateChip(_ device: S3XYDevice) -> some View {
        if device.connected {
            StatusChip(text: L10n.t("已连接", "Connected"), tone: .ok)
        } else if device.paused {
            StatusChip(text: L10n.t("已暂停", "Paused"), tone: .warn)
        }
    }

    private func deviceDetail(_ device: S3XYDevice) -> String {
        var parts = [device.state, device.address]
        if let rssi = device.rssi { parts.append("RSSI \(rssi) dBm") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func deviceMenu(_ device: S3XYDevice) -> some View {
        Button {
            Task {
                await deviceCommand(device.connected ? L10n.t("断开", "Disconnect") : L10n.t("连接", "Connect"),
                                    device.connected ? P4Route.s3xyDeviceDisconnect : P4Route.s3xyDeviceConnect,
                                    device)
            }
        } label: {
            Label(device.connected ? L10n.t("断开连接", "Disconnect") : L10n.t("连接", "Connect"),
                  systemImage: device.connected ? "xmark.circle" : "link")
        }
        Button {
            Task { await deviceCommand(L10n.t("握手同步", "Handshake"), P4Route.s3xyDeviceHandshake, device) }
        } label: {
            Label(L10n.t("握手同步", "Handshake"), systemImage: "hand.wave")
        }
        Button {
            Task {
                await deviceCommand(L10n.t("自动重连", "Auto-reconnect"), P4Route.s3xyDeviceAuto, device,
                                    extra: [P4Param("enabled", device.autoConnect ? "0" : "1")])
            }
        } label: {
            Label(device.autoConnect ? L10n.t("关闭自动重连", "Turn off auto-reconnect")
                                     : L10n.t("开启自动重连", "Turn on auto-reconnect"),
                  systemImage: "arrow.triangle.2.circlepath")
        }

        Section(L10n.t("按键动作", "Button actions")) {
            ForEach(Gesture.allCases, id: \.self) { gesture in
                Menu {
                    ForEach(S3XYActionCatalog.options, id: \.code) { option in
                        Button {
                            Task {
                                await deviceCommand(L10n.t("绑定\(gesture.title)动作", "Bind \(gesture.title)"),
                                                    P4Route.s3xyDeviceAction, device,
                                                    extra: [P4Param("gesture", gesture.rawValue),
                                                            P4Param("action", option.code)])
                            }
                        } label: {
                            if option.code == gesture.current(device) {
                                Label(option.label, systemImage: "checkmark")
                            } else {
                                Text(option.label)
                            }
                        }
                    }
                } label: {
                    Label("\(gesture.title)：\(gesture.label(device))", systemImage: "hand.tap")
                }
            }
        }

        Button {
            renameText = device.name
            renaming = device
        } label: {
            Label(L10n.t("重命名", "Rename"), systemImage: "pencil")
        }
        Button(role: .destructive) {
            forgetting = device
        } label: {
            Label(L10n.t("忘记设备", "Forget"), systemImage: "trash")
        }
    }

    private func scanRow(_ result: S3XYScanResult) -> some View {
        HStack(spacing: Theme.Icon.gap) {
            SettingsIcon(systemImage: "dot.radiowaves.forward", tint: P4Palette.teal)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.name).font(.body).lineLimit(1)
                Text(scanDetail(result))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: Theme.spacing(1))
            Button(L10n.t("配对", "Pair")) {
                Task { await pair(result) }
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .disabled(!canWrite)
            .accessibilityLabel(L10n.t("配对 \(result.name)", "Pair \(result.name)"))
        }
    }

    private func scanDetail(_ result: S3XYScanResult) -> String {
        var parts = [result.address]
        if let rssi = result.rssi { parts.append("RSSI \(rssi) dBm") }
        if result.registered { parts.append(L10n.t("已注册", "Registered")) }
        return parts.joined(separator: " · ")
    }

    private var globalMenu: some View {
        Menu {
            Button {
                guard let autoEnabled else {
                    environment.toast = P4Toast(message: L10n.t("尚未读取到自动重连状态，请稍后重试",
                                                                "Auto-reconnect state not loaded yet"),
                                                style: .info)
                    return
                }
                Task {
                    await globalCommand(autoEnabled ? L10n.t("关闭自动重连", "Turn off auto-reconnect")
                                                    : L10n.t("开启自动重连", "Turn on auto-reconnect"),
                                        autoEnabled ? P4Route.s3xyAutoDisable : P4Route.s3xyAutoEnable)
                }
            } label: {
                Label(autoEnabled == true ? L10n.t("关闭自动重连（全部）", "Turn off auto-reconnect (all)")
                                          : L10n.t("开启自动重连（全部）", "Turn on auto-reconnect (all)"),
                      systemImage: "arrow.triangle.2.circlepath")
            }
            Button {
                Task { await exportLog() }
            } label: {
                Label(L10n.t("导出 S3XY 日志", "Export S3XY log"), systemImage: "square.and.arrow.up")
            }
            Divider()
            Button(role: .destructive) {
                pendingGlobal = .clear
            } label: {
                Label(L10n.t("清除 S3XY 记录", "Clear S3XY records"), systemImage: "eraser")
            }
            Button(role: .destructive) {
                pendingGlobal = .resetAll
            } label: {
                Label(L10n.t("重置全部蓝牙", "Reset all Bluetooth"), systemImage: "arrow.counterclockwise")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .disabled(!online)
        .accessibilityLabel(L10n.t("蓝牙维护", "Bluetooth maintenance"))
    }

    // MARK: 读写

    private func refresh() async {
        await environment.refreshEndpoint(P4Route.s3xyStats)
    }

    private func poll() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private func setBluetooth(_ enabled: Bool) async {
        await environment.command(
            enabled ? L10n.t("开启蓝牙", "Turn on Bluetooth") : L10n.t("关闭蓝牙", "Turn off Bluetooth"),
            path: enabled ? P4Route.s3xyBluetoothEnable : P4Route.s3xyBluetoothDisable
        )
        await refresh()
    }

    private func scan() async {
        await environment.command(L10n.t("扫描设备", "Scan"), path: P4Route.s3xyScan)
        await refresh()
    }

    private func pair(_ result: S3XYScanResult) async {
        await environment.command(L10n.t("配对 \(result.name)", "Pair \(result.name)"),
                                  path: P4Route.s3xyPair,
                                  query: [P4Param("address", result.address)])
        await refresh()
    }

    private func deviceCommand(_ label: String, _ path: String, _ device: S3XYDevice,
                               extra: [P4Param] = []) async {
        await environment.command(label, path: path, query: [P4Param("id", "\(device.slot)")] + extra)
        await refresh()
    }

    private func globalCommand(_ label: String, _ path: String) async {
        await environment.command(label, path: path)
        await refresh()
    }

    private func exportLog() async {
        do {
            shareURL = try await environment.exportLogFile(P4LogFile.s3xyLog)
        } catch {
            environment.toast = P4Toast(message: AppEnvironment.friendly(error), style: .failure)
        }
    }
}

private struct ShareItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
