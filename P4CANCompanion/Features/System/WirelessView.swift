import SwiftUI

/// 设置 → 无线：对应固件网页 `panelWireless`。
///
/// - 蓝牙总开关（即时生效，配对保留）
/// - S3XY 自动重连总开关
/// - 设备热点（SoftAP）SSID / 密码
/// - 清除全部蓝牙数据（危险，会重启设备）
struct WirelessView: View {
    @EnvironmentObject private var environment: AppEnvironment

    @State private var bluetoothOn: Bool?
    @State private var autoConnect: Bool?
    @State private var pairedCount: Int?
    @State private var connectedCount: Int?
    @State private var ssid = ""
    @State private var password = ""
    @State private var busy = false
    @State private var confirmsReset = false
    @State private var revealsPassword = false

    var body: some View {
        List {
            Section {
                toggleRow(
                    title: L10n.t("蓝牙总开关", "Bluetooth Master"),
                    subtitle: L10n.t("即时开关 · 配对信息保留", "Instant on/off · pairings saved"),
                    isOn: $bluetoothOn,
                    disabled: busy
                ) { newValue in
                    setBluetooth(newValue)
                }

                toggleRow(
                    title: L10n.t("S3XY 自动重连", "S3XY Auto Connect"),
                    subtitle: L10n.t("开机或断链后自动重连已保存的按钮",
                                     "Reconnects saved buttons after boot or link loss"),
                    isOn: $autoConnect,
                    disabled: busy || bluetoothOn == false
                ) { newValue in
                    setAutoConnect(newValue)
                }
            } header: {
                Label(L10n.t("蓝牙", "Bluetooth"), systemImage: "dot.radiowaves.left.and.right")
            } footer: {
                Text(L10n.t("关闭蓝牙总开关会停用 S3XY 按钮与 BLE 日志，但不会删除配对；再次打开即恢复。",
                            "Turning Bluetooth off stops S3XY buttons and BLE logs without deleting pairings."))
            }

            Section {
                LabeledContent(L10n.t("已注册按钮", "Registered buttons"),
                               value: pairedCount.map(String.init) ?? "—")
                LabeledContent(L10n.t("当前连接", "Connected"),
                               value: connectedCount.map(String.init) ?? "—")
                Button {
                    confirmsReset = true
                } label: {
                    Label(L10n.t("清除全部蓝牙数据", "Reset Bluetooth Data"), systemImage: "trash")
                        .foregroundStyle(.p4Err)
                }
                .disabled(busy || bluetoothOn != true)
            } header: {
                Label(L10n.t("S3XY 按钮", "S3XY buttons"), systemImage: "button.programmable")
            } footer: {
                Text(L10n.t("清除会移除注册按钮、按键映射、BLE 绑定与发现缓存，并重启 P4-CAN；蓝牙总开关与自动重连设置保留。",
                            "Removes registered buttons, action mappings, BLE bonds and discovery cache, then reboots P4-CAN. Bluetooth Master and Auto Connect are kept."))
            }

            wifiSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L10n.t("无线", "Wireless"))
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) { ToastOverlay() }
        .task { await load() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                if environment.isPollingPaused { continue }
                await load()
            }
        }
        .confirmationDialog(
            L10n.t("清除全部蓝牙数据？", "Reset all Bluetooth data?"),
            isPresented: $confirmsReset,
            titleVisibility: .visible
        ) {
            Button(L10n.t("清除并重启", "Reset and reboot"), role: .destructive) {
                busy = true
                Task {
                    await environment.command(L10n.t("清除蓝牙数据", "Reset Bluetooth data"),
                                              path: P4Route.s3xyResetAll)
                    busy = false
                    await load()
                }
            }
            Button(L10n.t("取消", "Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t("将移除 \(pairedCount ?? 0) 个已注册按钮及其绑定。此操作不可撤销。",
                        "This removes \(pairedCount ?? 0) registered button(s) and their bonds. It cannot be undone."))
        }
    }

    // MARK: - Wi-Fi

    private var wifiSection: some View {
        Section {
            if let wifi = environment.wifiStatus?.objectValue {
                if let ssidValue = wifi["ssid"]?.stringValue, !ssidValue.isEmpty {
                    LabeledContent(L10n.t("热点名称", "SSID"), value: ssidValue)
                }
                if let state = wifi["networkState"]?.stringValue, !state.isEmpty {
                    LabeledContent(L10n.t("网络状态", "Network"), value: state)
                }
                if let ip = wifi["ip"]?.stringValue, !ip.isEmpty {
                    LabeledContent("IP", value: ip)
                }
                if wifi["passwordIsDefault"]?.boolValue == true {
                    Label("设备热点仍为默认密码，建议尽快修改",
                          systemImage: "exclamationmark.shield")
                        .font(.footnote)
                        .foregroundStyle(.p4Warn)
                }
            } else {
                Text(L10n.t("暂无 Wi-Fi 状态", "No Wi-Fi status"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            TextField(L10n.t("新热点名称（留空保持不变）", "New SSID (leave blank to keep)"), text: $ssid)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityLabel(L10n.t("热点名称", "SSID"))
            HStack(spacing: 8) {
                if revealsPassword {
                    TextField(L10n.t("新密码（留空保持不变）", "New password (leave blank to keep)"), text: $password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    SecureField(L10n.t("新密码（留空保持不变）", "New password (leave blank to keep)"), text: $password)
                }
                Button {
                    revealsPassword.toggle()
                } label: {
                    Image(systemName: revealsPassword ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("显示或隐藏密码", "Show or hide password"))
            }
            .accessibilityElement(children: .contain)

            Button {
                applyWiFi()
            } label: {
                Label(L10n.t("应用热点设置", "Apply Wi-Fi settings"), systemImage: "wifi.router")
            }
            .disabled(busy || (ssid.isEmpty && password.isEmpty))
        } header: {
            Label(L10n.t("设备热点（SoftAP）", "Device hotspot (SoftAP)"), systemImage: "wifi.router")
        } footer: {
            Text(L10n.t("设置保存在 NVS，「重置功能设置」不会清除。应用后只重启热点，不影响 CAN 与蓝牙；IP 仍为 192.168.4.1。密码通过局域网 HTTP 发送（固件接口仅支持 query 参数），请只在可信网络下修改；App 的网络日志会对其打码。",
                        "Settings are stored in NVS and preserved by Reset Feature Settings. Only the access point restarts; CAN and Bluetooth keep running. The password is sent over local HTTP (the firmware only accepts query parameters); change it only on a trusted network. The in-app network log masks it."))
        }
    }

    // MARK: - 读写

    private func load() async {
        guard let stats = try? await environment.api.get(P4Route.s3xyStats) else { return }
        guard let object = stats.objectValue else { return }
        if let value = object["bluetoothEnabled"]?.boolValue { bluetoothOn = value }
        if let value = object["autoEnabled"]?.boolValue { autoConnect = value }
        if let value = object["pairedCount"]?.intValue { pairedCount = Int(value) }
        if let value = object["connectedCount"]?.intValue { connectedCount = Int(value) }
    }

    private func setBluetooth(_ enabled: Bool) {
        bluetoothOn = enabled
        busy = true
        Task {
            await environment.command(
                enabled ? L10n.t("打开蓝牙", "Enable Bluetooth") : L10n.t("关闭蓝牙", "Disable Bluetooth"),
                path: enabled ? P4Route.s3xyBluetoothEnable : P4Route.s3xyBluetoothDisable,
                refresh: false
            )
            busy = false
            await load()
        }
    }

    private func setAutoConnect(_ enabled: Bool) {
        autoConnect = enabled
        busy = true
        Task {
            await environment.command(
                enabled ? L10n.t("开启自动重连", "Enable Auto Connect") : L10n.t("关闭自动重连", "Disable Auto Connect"),
                path: enabled ? P4Route.s3xyAutoEnable : P4Route.s3xyAutoDisable,
                refresh: false
            )
            busy = false
            await load()
        }
    }

    private func applyWiFi() {
        // 固件强制要求 ssid：只改密码时必须把当前 SSID 一起提交，否则必回 400。
        let effectiveSSID = ssid.isEmpty
            ? (environment.wifiStatus?["ssid"]?.stringValue ?? "")
            : ssid
        guard !effectiveSSID.isEmpty else {
            environment.toast = P4Toast(
                message: L10n.t("先填写新的热点名称（当前热点名还没读到）",
                                "Enter a new SSID first — the current one has not been read yet"),
                style: .failure
            )
            return
        }
        busy = true
        Task {
            var query: [P4Param] = [P4Param("ssid", effectiveSSID)]
            if !password.isEmpty { query.append(P4Param("password", password)) }
            let ok = await environment.command(L10n.t("热点设置", "Wi-Fi settings"),
                                               path: P4Route.wifiApply, query: query, refresh: false)
            busy = false
            // 失败时保留输入，避免用户重输。
            if ok {
                ssid = ""
                password = ""
            }
            await environment.refreshOnce()
        }
    }

    @ViewBuilder
    private func toggleRow(
        title: String,
        subtitle: String,
        isOn: Binding<Bool?>,
        disabled: Bool,
        onChange: @escaping (Bool) -> Void
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let value = isOn.wrappedValue {
                Toggle("", isOn: Binding(
                    get: { value },
                    set: { newValue in
                        Haptics.impact()
                        onChange(newValue)
                    }
                ))
                .labelsHidden()
                .disabled(disabled)
                .accessibilityLabel(title)
            } else {
                ProgressView()
                    .accessibilityLabel(L10n.t("正在读取", "Loading"))
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
