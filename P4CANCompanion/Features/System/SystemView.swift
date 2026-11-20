import AppIntents
import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// 「设置」页：严格对照固件网页 Settings 的分组与顺序。
///
/// 网页结构（v3.29.3）：
/// 车型卡片 → Features（NAG / ISA / DMS / 视觉限速 / 自动转向灯 / 召唤状态 / R79 /
/// 地区 / TLSSC / 变道 / 踏板 / 常驻 AP / AP 加速回收 / S3XY / LAB Menu）→
/// System（固件 / 无线 / 外观 / 刷新间隔 / 诊断 / 升级 / 重启 / 两级重置 / 恢复出厂）→
/// Banned Car（封禁车辆 / TLSSC 恢复）。
///
/// 「LAB Menu」在这里，打开后底部才会出现实验室标签。
struct SystemView: View {
    @EnvironmentObject private var environment: AppEnvironment

    @State private var destructiveAction: ResetAction?
    @State private var dangerToggle: DangerToggle?
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
                List {
                    ProfileSection()
                    SystemSection(destructiveAction: $destructiveAction)
                        .id("system")
                    // v3.35.2 起官方固件移除了 /api/features/banned 与 tlssc-restore，
                    // 能力位也随之消失；没有这两个键时整段隐藏，避免点进去 404。
                    if environment.featuresStatus?["bannedSupported"] != nil {
                        BannedSection(pending: $dangerToggle)
                            .id("banned")
                    }
                    AppSection()
                    DataBrowseSection()
                    LogsSection()
                    ShortcutsSection()
                    AboutSection().id("about")
                }
                .listStyle(.insetGrouped)
                .navigationTitle(L10n.t("设置", "Settings"))
                .overlay(alignment: .bottom) { ToastOverlay() }
                .onAppear { AppEnvironmentActions.shared.environment = environment }
                .task {
                    #if DEBUG
                    // 本地联调：SIMCTL_CHILD_P4CAN_SETTINGS_ANCHOR=lab|system|banned 启动即滚到对应分组
                    if let anchor = ProcessInfo.processInfo.environment["P4CAN_SETTINGS_ANCHOR"] {
                        try? await Task.sleep(for: .milliseconds(700))
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo(anchor, anchor: .top)
                        }
                    }
                    // 本地联调：SIMCTL_CHILD_P4CAN_SETTINGS_PAGE=wireless|diagnostics|ota 直接进入子页
                    if let page = ProcessInfo.processInfo.environment["P4CAN_SETTINGS_PAGE"] {
                        try? await Task.sleep(for: .milliseconds(400))
                        path = [page]
                    }
                    #endif
                }
                .navigationDestination(for: String.self) { page in
                    switch page {
                    case "wireless": WirelessView()
                    case "diagnostics": DiagnosticsView()
                    case "ota": FirmwareUpdateView()
                    case "changelog": FirmwareChangelogView()
                    default: EmptyView()
                    }
                }
            .confirmationDialog(
                destructiveAction?.title ?? "",
                isPresented: Binding(
                    get: { destructiveAction != nil },
                    set: { if !$0 { destructiveAction = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button(L10n.t("确认执行", "Confirm"), role: .destructive) {
                    if let action = destructiveAction {
                        Task { await environment.command(action.title, path: action.path) }
                    }
                    destructiveAction = nil
                }
                Button(L10n.t("取消", "Cancel"), role: .cancel) { destructiveAction = nil }
            } message: {
                Text(destructiveAction?.message ?? "")
            }
            .confirmationDialog(
                dangerToggle?.title ?? "",
                isPresented: Binding(
                    get: { dangerToggle != nil },
                    set: { if !$0 { dangerToggle = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button(L10n.t("我已知晓，仍然开启", "I understand — enable"), role: .destructive) {
                    if let toggle = dangerToggle { Task { await toggle.enable() } }
                    dangerToggle = nil
                }
                Button(L10n.t("取消", "Cancel"), role: .cancel) { dangerToggle = nil }
            } message: {
                Text(dangerToggle?.message ?? "")
            }
            }
        }
    }

    // MARK: - 重置动作（文案对齐网页确认弹窗）

    enum ResetAction: String, Identifiable {
        case reboot
        case resetSettings
        case resetNVSKeepBLE
        case factoryReset

        var id: String { rawValue }

        @MainActor var title: String {
            switch self {
            case .reboot: return L10n.t("重启 P4-CAN", "Reboot P4-CAN")
            case .resetSettings: return L10n.t("重置功能设置", "Reset Feature Settings")
            case .resetNVSKeepBLE: return L10n.t("重置设置 · 保留 S3XY", "Reset Setup · Keep S3XY")
            case .factoryReset: return L10n.t("恢复出厂设置", "Factory Reset")
            }
        }

        @MainActor var message: String {
            switch self {
            case .reboot:
                return L10n.t("设备将重启，连接会短暂中断；Wi-Fi 未开启自动加入时需手动重连。",
                              "P4-CAN will reboot. Reconnect to Wi-Fi manually if Auto-Join is off.")
            case .resetSettings:
                return L10n.t("功能设置恢复默认；车型、Wi-Fi、S3XY 配对与 BUS OFF 证据保留。LAB Menu 与封禁开关会回到关闭。",
                              "Feature settings return to defaults. Vehicle, Wi-Fi, S3XY pairings and BUS OFF evidence are preserved. LAB Menu and banned switches return to OFF.")
            case .resetNVSKeepBLE:
                return L10n.t("回到车型选择；车型、Wi-Fi、功能、LAB 与诊断标记清除，S3XY 注册表、按键映射、蓝牙开关与配对保留。",
                              "Returns to profile setup. Vehicle, Wi-Fi, features, LAB and diagnostics are cleared; S3XY registry, mappings, Bluetooth settings and bonds are kept.")
            case .factoryReset:
                return L10n.t("清除全部设置、Wi-Fi 与 S3XY 配对，设备回到首次开箱的车型选择。此操作不可撤销。",
                              "Erase all settings, Wi-Fi and paired buttons. P4-CAN returns to first-boot profile setup. This cannot be undone.")
            }
        }

        var path: String {
            switch self {
            case .reboot: return P4Route.systemReboot
            case .resetSettings: return P4Route.systemResetSettings
            case .resetNVSKeepBLE: return P4Route.systemResetNVSKeepBLE
            case .factoryReset: return P4Route.systemFactoryReset
            }
        }
    }

    enum DangerToggle: String, Identifiable {
        case banned
        case tlsscRestore

        var id: String { rawValue }

        @MainActor var title: String {
            switch self {
            case .banned: return L10n.t("开启「封禁车辆」？", "Enable Banned Car?")
            case .tlsscRestore: return L10n.t("开启 TLSSC 恢复？", "Enable TLSSC Restore?")
            }
        }

        @MainActor var message: String {
            switch self {
            case .banned:
                return L10n.t("仅当车辆已被 Tesla 封禁或限制时开启。开启本身不会发送 TLSSC 恢复报文。",
                              "Enable only if this vehicle is already banned or restricted by Tesla. Enabling alone does not transmit TLSSC restore frames.")
            case .tlsscRestore:
                return L10n.t("仅在车辆已被封禁后使用：开启会发送 TLSSC 恢复覆盖。需先开启「封禁车辆」。",
                              "Use only after the vehicle is already banned: this sends the TLSSC restore override. Enable Banned Car first.")
            }
        }

        @MainActor func enable() async {
            let path = self == .banned ? P4Route.featuresBanned : P4Route.featuresTLSSCRestore
            let label = self == .banned
                ? L10n.t("开启封禁车辆", "Enable Banned Car")
                : L10n.t("开启 TLSSC 恢复", "Enable TLSSC Restore")
            await AppEnvironmentActions.shared.enableDanger(path: path, label: label)
        }
    }
}

/// 让确认弹窗里的动作能拿到 environment（SwiftUI 的 enum 无法持有 EnvironmentObject）。
@MainActor
final class AppEnvironmentActions {
    static let shared = AppEnvironmentActions()
    weak var environment: AppEnvironment?

    func enableDanger(path: String, label: String) async {
        guard let environment else { return }
        await environment.command(label, path: path, query: [P4Param("enabled", "1")])
        await environment.refreshFeatures()
    }
}

// MARK: - 车型卡片

private struct ProfileSection: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var showsChange = false

    private var profile: [String: P4JSON] { environment.profileStatus?.objectValue ?? [:] }
    private var model: String { profile["profileName"]?.stringValue ?? L10n.t("未选择车型", "No profile") }
    private var firmware: String {
        environment.systemStats?["fwVersion"]?.stringValue
            ?? profile["fwVersion"]?.stringValue
            ?? "—"
    }
    private var badge: String {
        if let raw = profile["badge"]?.stringValue, !raw.isEmpty { return raw }
        let initials = model.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        return initials.isEmpty ? "P4" : initials.uppercased()
    }
    private var topologyText: String? {
        guard let topology = environment.topologyName, !topology.isEmpty else { return nil }
        return topology
    }

    private var turnText: String? {
        guard let turn = profile["turnName"]?.stringValue, !turn.isEmpty else { return nil }
        return "\(turn) · 0x249"
    }

    private var capsText: String {
        [
            environment.profileStatus?["nagSupported"]?.boolValue == true ? "✓ NAG" : "— NAG",
            environment.profileStatus?["advancedEapSupported"]?.boolValue == true ? "✓ ADV EAP" : "— ADV EAP",
            environment.profileStatus?["euUnlockSupported"]?.boolValue == true ? "✓ EU UNLOCK" : "— EU UNLOCK",
        ].joined(separator: " · ")
    }

    var body: some View {
        Section {
            if let module = FeatureCatalog.modules.first(where: { $0.id == "profile" }) {
                NavigationLink {
                    FeatureDetailView(module: module)
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Text(badge)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Color.p4OK)
                                // 44pt 徽标固定尺寸（与 App 图标网格一致），大字号下缩小字重而不是截成 "…"。
                                .lineLimit(1)
                                .minimumScaleFactor(0.45)
                                .frame(width: 44, height: 44)
                                .background(Color.p4OK.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(L10n.t("车型配置 · 开机锁定", "Vehicle profile · locked at boot"))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(model)
                                    .font(.headline)
                                Text("P4-CAN · \(firmware)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            Spacer(minLength: 0)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                if let topologyText {
                                    chipView(topologyText, scaling: 0.85)
                                }
                                if let turnText {
                                    chipView(turnText)
                                }
                                Spacer(minLength: 0)
                            }
                            chipView(capsText, scaling: 0.8)
                        }
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(L10n.t("车型 \(model)，点击查看配置详情",
                                               "Vehicle \(model), open profile details"))
                }
            } else {
                progressRow
            }

            Button {
                showsChange = true
            } label: {
                HStack {
                    Label(L10n.t("更改车型", "Change vehicle profile"),
                          systemImage: "arrow.triangle.2.circlepath")
                    Spacer()
                    Text(environment.profileName ?? "—")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(environment.isOnline == false)
            .sheet(isPresented: $showsChange) {
                NavigationStack {
                    VehicleProfileChangeView()
                        .environmentObject(environment)
                }
            }
            .task {
                #if DEBUG
                // 本地联调：SIMCTL_CHILD_P4CAN_PROFILE_CHANGE=1 启动即打开更改车型
                if ProcessInfo.processInfo.environment["P4CAN_PROFILE_CHANGE"] == "1" {
                    try? await Task.sleep(for: .milliseconds(600))
                    showsChange = true
                }
                #endif
            }
        }
    }

    private func chipView(_ text: String, scaling: CGFloat = 1) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(scaling)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.p4Tile, in: Capsule())
    }

    private var progressRow: some View {
        HStack {
            ProgressView()
            Text(L10n.t("正在读取车型配置…", "Loading vehicle profile…"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 系统

private struct SystemSection: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Binding var destructiveAction: SystemView.ResetAction?

    private var firmware: String {
        environment.systemStats?["fwVersion"]?.stringValue
            ?? environment.profileStatus?["fwVersion"]?.stringValue
            ?? "—"
    }

    var body: some View {
        Section {
            LabeledContent {
                Text(firmware)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } label: {
                Text(L10n.t("固件", "Firmware"))
            }

            NavigationLink {
                WirelessView()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("无线", "Wireless"))
                    Text(wirelessSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            appearanceRow
            refreshRow

            if environment.newFeaturesSupported == true {
                NavigationLink {
                    CanGpioView()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("CAN GPIO 设置", "CAN GPIO"))
                        Text(L10n.t("配置 TX / RX 引脚 · 重启生效",
                                    "Configure TX / RX pins · reboot to apply"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            NavigationLink {
                DiagnosticsView()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("诊断 / 恢复", "Diagnostics / Recovery"))
                    Text(L10n.t("计数器、启动抓包与系统日志", "Counters, boot capture and system logs"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if environment.newFeaturesSupported == true {
                NavigationLink {
                    ServiceModeView()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("Service Mode", "Service Mode"))
                        Text(L10n.t("进入 Service Mode · 中国市场恢复帧",
                                    "Service Mode entry and China restore frames"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            NavigationLink {
                FirmwareUpdateView()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("固件升级", "Firmware Update"))
                    Text(L10n.t("上传应用 .bin 文件", "Install an application .bin file"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                destructiveAction = .reboot
            } label: {
                Label(L10n.t("重启 P4-CAN", "Reboot P4-CAN"), systemImage: "arrow.clockwise")
            }

            Button {
                destructiveAction = .resetSettings
            } label: {
                Label(L10n.t("重置功能设置", "Reset Feature Settings"), systemImage: "arrow.counterclockwise")
            }

            Button {
                destructiveAction = .resetNVSKeepBLE
            } label: {
                Label(L10n.t("重置设置 · 保留 S3XY", "Reset Setup · Keep S3XY"), systemImage: "externaldrive.badge.minus")
            }

            Button(role: .destructive) {
                destructiveAction = .factoryReset
            } label: {
                Label(L10n.t("恢复出厂设置", "Factory Reset"), systemImage: "trash")
            }
        } header: {
            HStack {
                Text(L10n.t("系统", "System"))
                Spacer()
                Text("P4-CAN")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text(L10n.t("重置与恢复出厂会断开连接，请确认已知晓影响后再执行。",
                        "Resets disconnect the device. Make sure you understand the impact before continuing."))
        }
    }

    private var wirelessSummary: String {
        let bt = environment.isBluetoothEnabled ? "ON" : "OFF"
        let auto = environment.s3xyStats?["autoEnabled"]?.boolValue
        let autoText = auto == nil ? "—" : (auto == true ? "ON" : "OFF")
        let wifi = environment.wifiStatus?["ssid"]?.stringValue ?? "—"
        return L10n.t("蓝牙 \(bt) · 自动连接 \(autoText) · \(wifi)",
                      "Bluetooth \(bt) · Auto Connect \(autoText) · \(wifi)")
    }

    private var appearanceRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.t("外观", "Appearance"))
                Spacer()
                Text(environment.appearance == .system
                     ? L10n.t("跟随手机设置", "Follows phone setting")
                     : environment.appearance.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Picker(L10n.t("外观", "Appearance"), selection: Binding(
                get: { environment.appearance },
                set: { environment.setAppearance($0) }
            )) {
                ForEach(AppAppearance.allCases) { appearance in
                    Text(appearance.shortName).tag(appearance)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel(L10n.t("界面外观", "Appearance"))
        }
        .padding(.vertical, 2)
    }

    private var refreshRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.t("数据刷新间隔", "Data Refresh Interval"))
                Spacer()
                Text(L10n.t("主页更新 · 默认 500 ms", "Home updates · default 500 ms"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Picker(L10n.t("刷新间隔", "Refresh interval"), selection: Binding(
                get: { environment.pollIntervalMs },
                set: { environment.setPollInterval($0) }
            )) {
                ForEach(AppEnvironment.pollIntervalOptions, id: \.self) { value in
                    Text("\(value) ms").tag(value)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel(L10n.t("数据刷新间隔", "Data refresh interval"))
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 封禁车辆（危险）

private struct BannedSection: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Binding var pending: SystemView.DangerToggle?

    private var banned: Bool { environment.featuresStatus?["banned"]?.boolValue ?? false }
    private var restore: Bool { environment.featuresStatus?["tlsscRestore"]?.boolValue ?? false }
    // 能力位缺失（冷启动/离线）时不能默认「支持」——危险开关不应在未知状态下可点。
    private var bannedSupported: Bool {
        environment.featuresStatus?["bannedSupported"]?.boolValue ?? false
    }
    /// 固件要求车辆已被封禁才允许开启 TLSSC 恢复，否则必回 409。
    private var restoreSupported: Bool {
        let capable = environment.featuresStatus?["tlsscRestoreSupported"]?.boolValue ?? false
        return capable && banned
    }

    var body: some View {
        Section {
            dangerRow(
                title: L10n.t("封禁车辆", "Banned Car"),
                subtitle: L10n.t("为已被封禁的车辆显示恢复控制。",
                                 "Show restore controls for already-banned vehicles."),
                isOn: banned,
                supported: bannedSupported,
                id: .banned
            )
            dangerRow(
                title: L10n.t("TLSSC 恢复", "TLSSC Restore"),
                subtitle: L10n.t("对被封禁车辆尝试 TLSSC 恢复覆盖（需先开启上方开关）。",
                                 "Try the TLSSC restore override on a banned vehicle (requires Banned Car above)."),
                isOn: restore,
                supported: restoreSupported,
                id: .tlsscRestore
            )
        } header: {
            HStack {
                Text(L10n.t("封禁车辆", "Banned Car"))
                Text("DANGER")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.p4Err)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.p4Err.opacity(0.12), in: Capsule())
                Spacer()
                Text(L10n.t("仅限已被封禁的车辆", "Already-banned vehicles only"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text(L10n.t("仅当车辆已被 Tesla 封禁或限制时开启；错误使用可能导致车辆被封禁。",
                        "Enable only when the vehicle is already banned or restricted. Misuse may cause a ban."))
        }
    }

    private func dangerRow(
        title: String,
        subtitle: String,
        isOn: Bool,
        supported: Bool,
        id: SystemView.DangerToggle
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.p4Err)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(
                get: { isOn },
                set: { newValue in
                    Haptics.warning()
                    if newValue {
                        pending = id
                    } else {
                        let path = id == .banned ? P4Route.featuresBanned : P4Route.featuresTLSSCRestore
                        Task {
                            await environment.command(id.title, path: path, query: [P4Param("enabled", "0")])
                            await environment.refreshFeatures()
                        }
                    }
                }
            ))
            .labelsHidden()
            .disabled(!supported || environment.isBusy || !environment.isOnline)
            .accessibilityLabel(title)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - App 自身设置

private struct AppSection: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var hostField = ""
    @State private var showsGuide = false

    var body: some View {
        Section {
            Picker(selection: Binding(
                get: { environment.language },
                set: { environment.setLanguage($0) }
            )) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            } label: {
                Label(L10n.t("语言", "Language"), systemImage: "globe")
            }
            .accessibilityLabel(L10n.t("界面语言", "Interface language"))

            Toggle(isOn: Binding(
                get: { environment.liveActivityEnabled },
                set: { environment.setLiveActivity($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("锁屏 / 灵动岛实时状态", "Live Activity"))
                    Text(L10n.t("锁屏与灵动岛显示三路总线状态",
                                "Show CAN bus status on the Lock Screen and Dynamic Island"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Text(L10n.t("设备地址", "Device address"))
                Spacer()
                Text(environment.phase == .online ? L10n.t("在线", "Online") : L10n.t("离线", "Offline"))
                    .foregroundStyle(environment.phase == .online ? Color.p4OK : Color.p4Err)
            }
            .font(.subheadline)

            TextField(L10n.t("例如 192.168.4.1", "e.g. 192.168.4.1"), text: $hostField)
                // 支持 host:port 与 http:// 前缀，decimalPad 打不出冒号与斜杠。
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onAppear { hostField = environment.host }
                .accessibilityLabel(L10n.t("设备 IP 地址", "Device IP address"))

            Button(L10n.t("应用地址并连接", "Apply and connect")) {
                if environment.updateHost(hostField) {
                    hostField = environment.host
                }
            }
            .disabled(hostField.trimmingCharacters(in: .whitespaces) == environment.host)

            Button(L10n.t("查看连接引导", "Connection guide")) { showsGuide = true }
        } header: {
            Label(L10n.t("App", "App"), systemImage: "app.badge")
        } footer: {
            Text(L10n.t("语言切换立即生效，英文采用固件网页的原始措辞。蓝牙标签由「功能 → S3XY」开关控制：打开即显示，关闭即隐藏。",
                        "Language changes apply immediately. The Bluetooth tab follows the S3XY switch in Features: on shows it, off hides it."))
        }
        .sheet(isPresented: $showsGuide) { ConnectionGuideView() }
    }
}

// MARK: - 数据浏览

private struct DataBrowseSection: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        Section {
            NavigationLink {
                LiveDataView()
            } label: {
                HStack {
                    Label(L10n.t("全部数据（原始字段）", "All data (raw fields)"), systemImage: "list.bullet.rectangle")
                    Spacer()
                    Text(L10n.t("\(AppEnvironment.browseEndpoints.count) 个端点",
                                "\(AppEnvironment.browseEndpoints.count) endpoints"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            NavigationLink {
                NetworkLogView()
            } label: {
                Label(L10n.t("网络日志（抓包调试）", "Network log (debug)"), systemImage: "waveform.path.ecg.rectangle")
            }
        } header: {
            Label(L10n.t("数据浏览", "Data browser"), systemImage: "magnifyingglass")
        } footer: {
            Text(L10n.t("按端点查看固件 /api/* 的全部字段，支持搜索（can1 / can2 / can3 / gear / das 等）。",
                        "Browse every field of the firmware /api/* endpoints; search for can1 / can2 / can3 / gear / das."))
        }
    }
}

// MARK: - 日志导出

private struct LogsSection: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var exportingLog: P4LogFile?
    @State private var exportingBundle = false
    @State private var exportedURL: URL?
    @State private var exportFailed: String?

    private var isExporting: Bool { exportingLog != nil || exportingBundle }

    var body: some View {
        Section {
            Button {
                exportBundle()
            } label: {
                HStack {
                    Label(L10n.t("诊断包（zip）", "Diagnostics bundle (zip)"), systemImage: "shippingbox")
                        .foregroundStyle(.primary)
                    Spacer()
                    if exportingBundle {
                        ProgressView()
                    } else {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(.tint)
                    }
                }
            }
            .disabled(isExporting)

            ForEach(P4LogFile.all) { log in
                Button {
                    export(log)
                } label: {
                    HStack {
                        Label(log.title, systemImage: "doc.text.magnifyingglass")
                            .foregroundStyle(.primary)
                        Spacer()
                        if exportingLog?.id == log.id {
                            ProgressView()
                                .accessibilityLabel(L10n.t("正在导出\(log.title)", "Exporting \(log.title)"))
                        } else {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(.tint)
                                .accessibilityLabel(L10n.t("导出并分享", "Export and share"))
                        }
                    }
                }
                .disabled(isExporting)
            }
            if let failed = exportFailed {
                Label(failed, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.p4Err)
            }
        } header: {
            Label(L10n.t("日志与跟踪导出", "Logs & traces"), systemImage: "list.bullet.rectangle")
        } footer: {
            Text(L10n.t("诊断包内含：本机状态摘要、内置网络日志 CSV、最近一次快照 JSON。可直接分享给开发者排查。",
                        "The bundle contains a status summary, the in-app network log CSV and the latest snapshot JSON."))
        }
        .sheet(item: Binding(
            get: { exportedURL.map { ShareURLWrapper(url: $0) } },
            set: { if $0 == nil { exportedURL = nil } }
        )) { wrapper in
            ActivityShareSheet(items: [wrapper.url])
        }
    }

    private func exportBundle() {
        exportingBundle = true
        exportFailed = nil
        Task {
            do {
                exportedURL = try environment.makeDiagnosticsArchive()
            } catch {
                exportFailed = AppEnvironment.friendly(error)
            }
            exportingBundle = false
        }
    }

    private func export(_ log: P4LogFile) {
        exportingLog = log
        exportFailed = nil
        Task {
            do {
                exportedURL = try await environment.exportLogFile(log)
            } catch {
                exportFailed = AppEnvironment.friendly(error)
            }
            exportingLog = nil
        }
    }
}

private struct ShareURLWrapper: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// UIActivityViewController 的 SwiftUI 包装（Modal 提供系统滑动关闭路径）。
private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - 关于

/// 快捷指令：两个动作由 App Intent 提供，系统「快捷指令」会自动收录；
/// 这里给出动作说明与系统自带的添加入口，避免用户去猜名称。
private struct ShortcutsSection: View {
    var body: some View {
        Section {
            LabeledContent {
                Text(L10n.t("立即爆闪", "Flash now"))
                    .foregroundStyle(.secondary)
            } label: {
                Label(L10n.t("前大灯爆闪", "Headlight strobe"),
                      systemImage: "light.beacon.max.fill")
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(L10n.t("前大灯爆闪，立即爆闪", "Headlight strobe, flash now"))

            LabeledContent {
                Text(L10n.t("开始爆闪", "Start"))
                    .foregroundStyle(.secondary)
            } label: {
                Label(L10n.t("后雾灯爆闪", "Rear fog strobe"),
                      systemImage: "cloud.fog.fill")
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(L10n.t("后雾灯爆闪，开始爆闪", "Rear fog strobe, start"))

            // 系统提供的「添加到快捷指令」按钮，点击进入本 App 的动作列表。
            ShortcutsLink()
        } header: {
            Label(L10n.t("快捷指令", "Shortcuts"), systemImage: "square.stack.3d.up.fill")
        } footer: {
            Text(L10n.t(
                "动作在后台执行，使用 App 内已保存的次数与间隔；运行前请确认手机已连上 P4-CAN 的 Wi-Fi。",
                "Actions run in the background with the settings saved in the app. Make sure this iPhone is on the P4-CAN Wi-Fi first."
            ))
        }
    }
}

private struct AboutSection: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var copied = false

    var body: some View {
        Section {
            LabeledContent(L10n.t("App 版本", "App version"), value: environment.appVersionText)
            LabeledContent(L10n.t("适配固件", "Firmware"), value: "P4-CAN Universal Unlock v3.29.3")
            LabeledContent(L10n.t("接口契约", "API contract"), value: "web_api.h（query 参数）")
            LabeledContent(L10n.t("连接方式", "Transport"), value: L10n.t("本地 HTTP（192.168.4.1）", "Local HTTP (192.168.4.1)"))

            Button {
                UIPasteboard.general.string = environment.diagnosticsSummary
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    copied = false
                }
            } label: {
                Label(copied ? L10n.t("已复制诊断信息", "Diagnostics copied")
                             : L10n.t("复制诊断信息", "Copy diagnostics"),
                      systemImage: copied ? "checkmark.circle.fill" : "doc.on.doc")
                    .foregroundStyle(copied ? Color.p4OK : Color.accentColor)
            }
        } header: {
            Label(L10n.t("关于", "About"), systemImage: "info.circle")
        } footer: {
            Text(L10n.t("功能列表依据固件 v3.29.3 内嵌 API 路由与状态字段还原；个别参数含义以固件实际行为为准。",
                        "Feature list is derived from the API routes and status fields embedded in firmware v3.29.3."))
        }
    }
}
