import SwiftUI
import UIKit

/// v3.35.2 新增功能的操作页：电池预热 / FSD / Service Mode / SmartShift / R79 时序。
///
/// 这些接口在 v3.29.3 上不存在；页面只在模块入口可见时进入（入口由功能目录控制），
/// 所有写操作都走 `refreshEndpoint` / `storeEndpoint` 的共享缓存，和灯光页一致。

// MARK: - 共用

@MainActor
private func fwWrite(_ environment: AppEnvironment,
                     path: String,
                     query: [P4Param],
                     storeTo: String) async -> P4JSON? {
    do {
        let value = try await environment.api.post(path, query: query)
        environment.storeEndpoint(storeTo, value)
        return value
    } catch {
        environment.toast = P4Toast(message: AppEnvironment.friendly(error), style: .failure)
        return nil
    }
}

private struct FWStatusRows: View {
    let rows: [(String, String)]

    var body: some View {
        ForEach(rows, id: \.0) { row in
            LabeledContent(row.0, value: row.1)
                .font(.subheadline)
        }
    }
}

private func fwNumber(_ value: P4JSON?, _ digits: Int = 1) -> String {
    guard let value, let number = value.doubleValue else { return "—" }
    return String(format: "%.\(digits)f", number)
}

// MARK: - 电池预热

struct PreheatView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var busy = false

    private var stats: P4JSON? { environment.endpointValue(P4Route.preheatStats) }
    private var object: [String: P4JSON] { stats?.objectValue ?? [:] }
    private var supported: Bool { object["supported"]?.boolValue ?? false }
    private var enabled: Bool { object["enabled"]?.boolValue ?? false }
    private var targetC: Double { object["targetC"]?.doubleValue ?? 40 }

    private var targetOptions: [Int] {
        var values = Array(stride(from: 20, through: 50, by: 5))
        let current = Int(targetC.rounded())
        if !values.contains(current) { values.append(current); values.sort() }
        return values
    }

    private var statusText: String {
        guard supported else { return L10n.t("不可用", "Unavailable") }
        if object["targetReached"]?.boolValue == true { return L10n.t("已达目标", "Target reached") }
        if object["batteryWarm"]?.boolValue == true { return L10n.t("电池已暖", "Battery warm") }
        guard object["active"]?.boolValue == true else {
            if let reason = object["autoOffReason"]?.stringValue, reason != "NONE" {
                return reason == "TARGET_REACHED" ? L10n.t("已达目标自动关闭", "Auto-off: target reached")
                                                   : L10n.t("自动关闭：\(reason)", "Auto-off: \(reason)")
            }
            return L10n.t("关闭", "Off")
        }
        if (object["evalAgeMs"]?.intValue ?? 0) > 3000 { return L10n.t("无 CAN 数据", "No CAN data") }
        if object["blocked"]?.boolValue == true {
            return L10n.t("等待：\(object["blockedReason"]?.stringValue ?? "—")", "Blocked: \(object["blockedReason"]?.stringValue ?? "—")")
        }
        let txOk = object["txOk"]?.intValue ?? 0
        let txFail = object["txFail"]?.intValue ?? 0
        if txOk == 0 && txFail > 0 { return L10n.t("发送失败", "No TX") }
        return L10n.t("加热中", "Heating")
    }

    private var packText: String {
        guard object["packSeen"]?.boolValue == true else { return "—" }
        let minC = fwNumber(object["packTempMinC"]), maxC = fwNumber(object["packTempMaxC"])
        let avg = fwNumber(object["packTempAvgC"])
        return "\(avg) °C（\(minC)–\(maxC)）"
    }

    private var bmsText: String {
        guard object["bmsSeen"]?.boolValue == true else { return L10n.t("等待 BMS", "Waiting for BMS") }
        if object["heatingActive"]?.boolValue == true { return L10n.t("加热中", "Heating") }
        if object["bmsPreconditionAllowed"]?.boolValue != true { return L10n.t("BMS 拒绝", "Blocked by BMS") }
        if object["bmsHeatingWorthwhile"]?.boolValue == true { return L10n.t("就绪", "Ready") }
        return L10n.t("不需要加热", "Not needed")
    }

    var body: some View {
        List {
            Section {
                Toggle(L10n.t("启用电池预热", "Enable battery preheat"),
                       isOn: Binding(get: { enabled }, set: { value in
                           Task { await setEnabled(value) }
                       }))
                    .disabled(!supported || busy)

                Picker(L10n.t("目标温度", "Target"), selection: Binding(
                    get: { Int(targetC.rounded()) },
                    set: { value in Task { await setTarget(Double(value)) } }
                )) {
                    ForEach(targetOptions, id: \.self) { Text("\($0) °C").tag($0) }
                }
                .disabled(!supported || busy)
            } header: {
                Text(L10n.t("控制", "Controls"))
            } footer: {
                Text(L10n.t("预热会请求 BMS 加热电池，需车辆上电；达到目标或电池已暖后自动关闭。",
                            "Preheat asks the BMS to heat the pack while the car is powered; it stops at the target or when warm."))
            }

            Section(L10n.t("状态", "Status")) {
                FWStatusRows(rows: [
                    (L10n.t("状态", "State"), statusText),
                    (L10n.t("电池温度", "Pack temperature"), packText),
                    (L10n.t("BMS", "BMS"), bmsText),
                    (L10n.t("发送 / 失败", "TX / fail"),
                     "\(object["txOk"]?.intValue ?? 0) / \(object["txFail"]?.intValue ?? 0)"),
                    (L10n.t("目标", "Target"), "\(fwNumber(object["targetC"], 1)) °C"),
                    (L10n.t("车型帧", "Trip frame"), object["tripId"]?.stringValue ?? "—"),
                ])
            }
        }
        .listStyle(.insetGrouped)
        .contentMargins(.bottom, 28, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(Color.p4Background.ignoresSafeArea())
        .navigationTitle(L10n.t("电池预热", "Battery Preheat"))
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) { ToastOverlay() }
        .task { await poll() }
    }

    private func setEnabled(_ value: Bool) async {
        busy = true
        defer { busy = false }
        _ = await fwWrite(environment, path: P4Route.preheatSet,
                          query: [P4Param("enabled", value ? "1" : "0")],
                          storeTo: P4Route.preheatStats)
        Haptics.impact()
    }

    private func setTarget(_ value: Double) async {
        busy = true
        defer { busy = false }
        _ = await fwWrite(environment, path: P4Route.preheatSet,
                          query: [P4Param("targetC", String(format: "%.1f", value))],
                          storeTo: P4Route.preheatStats)
        Haptics.impact()
    }

    private func poll() async {
        await environment.refreshEndpoint(P4Route.preheatStats)
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            await environment.refreshEndpoint(P4Route.preheatStats)
        }
    }
}

// MARK: - FSD 注入

struct FSDInjectionView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var busy = false

    private var stats: P4JSON? { environment.endpointValue(P4Route.fsdStats) }
    private var object: [String: P4JSON] { stats?.objectValue ?? [:] }
    private var enabled: Bool { object["enabled"]?.boolValue ?? false }
    private var suspendAP: Bool { object["suspendDuringAp"]?.boolValue ?? false }
    private var visualisation: Bool { ((object["values"]?.intValue ?? 0) & 2) != 0 }

    var body: some View {
        List {
            Section {
                Toggle(L10n.t("启用 FSD 注入", "Enable FSD injection"),
                       isOn: Binding(get: { enabled }, set: { value in Task { await update(enabled: value) } }))
                    .disabled(busy)
                Toggle(L10n.t("FSD 可视化", "FSD visualisation"),
                       isOn: Binding(get: { visualisation }, set: { value in Task { await update(visualisation: value) } }))
                    .disabled(busy || !enabled)
                Toggle(L10n.t("AP 激活时暂停", "Suspend during AP"),
                       isOn: Binding(get: { suspendAP }, set: { value in Task { await update(suspend: value) } }))
                    .disabled(busy || !enabled)
            } header: {
                Text(L10n.t("控制", "Controls"))
            } footer: {
                Text(L10n.t("在 CHASSIS 上注入 FSD 可视化标志；AP 激活且开启暂停时自动让出。",
                            "Injects the FSD visualisation flag on CHASSIS and yields while AP is active if suspend is on."))
            }

            Section(L10n.t("状态", "Status")) {
                FWStatusRows(rows: [
                    (L10n.t("状态", "State"), statusText),
                    (L10n.t("CHASSIS 原始值", "CHASSIS stock"),
                     object["mux0Fresh"]?.boolValue == true ? (object["stock1"]?.stringValue ?? "—") : "—"),
                    (L10n.t("发送 / 失败", "TX / fail"),
                     "\(object["txOk"]?.intValue ?? 0) / \(object["txFail"]?.intValue ?? 0)"),
                ])
            }
        }
        .listStyle(.insetGrouped)
        .contentMargins(.bottom, 28, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(Color.p4Background.ignoresSafeArea())
        .navigationTitle(L10n.t("FSD 注入", "FSD Injection"))
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) { ToastOverlay() }
        .task { await poll() }
    }

    private var statusText: String {
        guard !enabled else {
            if suspendAP && object["apBlocked"]?.boolValue == true { return L10n.t("已暂停（AP）", "Suspended (AP)") }
            return L10n.t("生效中", "Echo enabled")
        }
        return L10n.t("关闭", "Echo disabled")
    }

    private func update(enabled newEnabled: Bool? = nil,
                        visualisation newVisualisation: Bool? = nil,
                        suspend newSuspend: Bool? = nil) async {
        busy = true
        defer { busy = false }
        let e = newEnabled ?? enabled
        let v = newVisualisation ?? visualisation
        let s = newSuspend ?? suspendAP
        _ = await fwWrite(environment, path: P4Route.fsdUpdate, query: [
            P4Param("enabled", e ? "1" : "0"),
            P4Param("values", v ? "2" : "0"),
            P4Param("suspendDuringAp", s ? "1" : "0"),
        ], storeTo: P4Route.fsdStats)
        Haptics.impact()
    }

    private func poll() async {
        await environment.refreshEndpoint(P4Route.fsdStats)
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            await environment.refreshEndpoint(P4Route.fsdStats)
        }
    }
}

// MARK: - Service Mode

struct ServiceModeView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var busy = false
    @State private var confirmEnter = false

    private var stats: P4JSON? { environment.endpointValue(P4Route.serviceModeStats) }
    private var object: [String: P4JSON] { stats?.objectValue ?? [:] }
    private var canEnter: Bool { object["canEnter"]?.boolValue ?? false }
    private var chinaRestore: Bool { object["chinaRestore"]?.boolValue ?? false }

    var body: some View {
        List {
            Section {
                Button {
                    confirmEnter = true
                } label: {
                    Label(L10n.t("进入 Service Mode", "Enter Service Mode"), systemImage: "wrench.and.screwdriver.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.p4Warn)
                .disabled(!canEnter || busy)

                Toggle(L10n.t("中国市场恢复帧", "China restore frames"),
                       isOn: Binding(get: { chinaRestore }, set: { value in Task { await setRestore(value) } }))
                    .disabled(busy)
            } header: {
                Text(L10n.t("控制", "Controls"))
            } footer: {
                Text(L10n.t("进入后需要在车机屏幕上确认；固件只发一次请求，不会自动重试。",
                            "Confirm Service Mode on the vehicle screen. The request is sent once and is not retried automatically."))
            }

            Section(L10n.t("状态", "Status")) {
                FWStatusRows(rows: [
                    (L10n.t("可进入", "Can enter"), canEnter ? L10n.t("是", "Yes") : L10n.t("否", "No")),
                    (L10n.t("恢复帧", "Restore frames"), chinaRestore ? L10n.t("开", "On") : L10n.t("关", "Off")),
                    (L10n.t("恢复发送 / 失败", "Restore TX / fail"),
                     "\(object["restoreTxOk"]?.intValue ?? 0) / \(object["restoreTxFail"]?.intValue ?? 0)"),
                ])
            }
        }
        .listStyle(.insetGrouped)
        .contentMargins(.bottom, 28, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(Color.p4Background.ignoresSafeArea())
        .navigationTitle(L10n.t("Service Mode", "Service Mode"))
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) { ToastOverlay() }
        .confirmationDialog(L10n.t("确认进入 Service Mode？", "Enter Service Mode?"),
                            isPresented: $confirmEnter, titleVisibility: .visible) {
            Button(L10n.t("进入", "Enter"), role: .destructive) { Task { await enter() } }
            Button(L10n.t("取消", "Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t("车辆需在驻车状态，进入后还要在车机屏幕上确认。", "Park the car first; you still confirm on the vehicle screen."))
        }
        .task { await poll() }
    }

    private func enter() async {
        busy = true
        defer { busy = false }
        _ = await fwWrite(environment, path: P4Route.serviceModeEnter, query: [], storeTo: P4Route.serviceModeStats)
        Haptics.success()
    }

    private func setRestore(_ value: Bool) async {
        busy = true
        defer { busy = false }
        _ = await fwWrite(environment, path: P4Route.serviceModeRestore,
                          query: [P4Param("enabled", value ? "1" : "0")],
                          storeTo: P4Route.serviceModeStats)
        Haptics.impact()
    }

    private func poll() async {
        await environment.refreshEndpoint(P4Route.serviceModeStats)
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            await environment.refreshEndpoint(P4Route.serviceModeStats)
        }
    }
}

// MARK: - SmartShift

struct SmartShiftView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var busy = false
    @State private var numbers: [String: String] = [:]
    @State private var draftsLoaded = false

    private struct NumberSpec: Identifiable {
        let key: String
        let label: String
        let range: ClosedRange<Int>
        var id: String { key }
    }

    private let numberSpecs: [NumberSpec] = [
        NumberSpec(key: "maxSpeedKph", label: "最高换挡车速 (km/h)", range: 0...8),
        NumberSpec(key: "hardCutSpeedKph", label: "硬切断车速 (km/h)", range: 1...30),
        NumberSpec(key: "cooldownMs", label: "冷却时间 (ms)", range: 0...10000),
        NumberSpec(key: "obstacleThresholdCm", label: "障碍物阈值 (cm)", range: 1...499),
        NumberSpec(key: "parkConfirmDeg", label: "P 挡确认角度 (°)", range: 1...720),
        NumberSpec(key: "driveReverseConfirmDeg", label: "D/R 确认角度 (°)", range: 1...720),
        NumberSpec(key: "obstacleConfirmDeg", label: "障碍物确认角度 (°)", range: 1...720),
    ]

    private var stats: P4JSON? { environment.endpointValue(P4Route.smartShiftStats) }
    private var object: [String: P4JSON] { stats?.objectValue ?? [:] }
    private var config: [String: P4JSON] { object["config"]?.objectValue ?? [:] }
    private var supported: Bool { object["profileSupported"]?.boolValue ?? false }

    private func flag(_ key: String) -> Bool {
        key == "enabled" ? (object["executionEnabled"]?.boolValue ?? false)
                         : (config[key]?.boolValue ?? false)
    }

    var body: some View {
        List {
            Section {
                ForEach([("enabled", "启用自动换挡", "Automatic shifting"),
                         ("requireSeatbelt", "要求安全带", "Require seat belt"),
                         ("steeringFallback", "D/R 转向确认", "D/R steering confirmation"),
                         ("parkSteeringFallback", "P 挡转向选择", "Park steering selection"),
                         ("requireSteering", "障碍物转向确认", "Obstacle steering confirmation")],
                        id: \.0) { item in
                    Toggle(L10n.t(item.1, item.2), isOn: Binding(
                        get: { flag(item.0) },
                        set: { value in Task { await updateFlag(item.0, value) } }
                    ))
                    .disabled(!supported || busy)
                }

                Picker(L10n.t("协议", "Protocol"), selection: Binding(
                    get: { object["protocol"]?.stringValue ?? "AUTO" },
                    set: { value in Task { await updateValue("protocol", value) } }
                )) {
                    Text("AUTO").tag("AUTO")
                    Text("V12 · 0x229").tag("V12")
                    Text("V13/V14 · 0x678").tag("V13V14")
                }
                .disabled(!supported || busy)

                Picker(L10n.t("车速来源", "Speed source"), selection: Binding(
                    get: { String(config["speedBus"]?.intValue ?? 2) },
                    set: { value in Task { await updateValue("speedBus", value) } }
                )) {
                    Text("BODY").tag("0")
                    Text("CHASSIS").tag("1")
                    Text("PARTY").tag("2")
                }
                .disabled(!supported || busy)
            } header: {
                Text(L10n.t("控制", "Controls"))
            } footer: {
                Text(L10n.t("实验性功能：刹车确认后才会发出挡位请求；不满足车速、安全带或障碍物条件时不动作。",
                            "Experimental: gear requests are sent only after brake confirmation and the speed, belt and obstacle gates pass."))
            }

            Section {
                ForEach(numberSpecs) { spec in
                    HStack {
                        Text(L10n.t(spec.label, spec.key))
                            .font(.subheadline)
                        Spacer()
                        TextField("—", text: Binding(
                            get: { numbers[spec.key] ?? "" },
                            set: { numbers[spec.key] = $0 }
                        ))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 96)
                        .textFieldStyle(.roundedBorder)
                    }
                }
                Button(L10n.t("保存数值参数", "Save numeric settings")) {
                    Task { await saveNumbers() }
                }
                .disabled(!supported || busy)
            } header: {
                Text(L10n.t("数值参数", "Numeric settings"))
            }

            Section(L10n.t("状态", "Status")) {
                FWStatusRows(rows: [
                    (L10n.t("状态", "State"), object["state"]?.stringValue ?? "—"),
                    (L10n.t("候选 / 来源", "Candidate / source"),
                     "\(object["prearm"]?.objectValue?["candidate"]?.stringValue ?? object["target"]?.stringValue ?? "NONE") / \(object["prearm"]?.objectValue?["source"]?.stringValue ?? object["source"]?.stringValue ?? "NONE")"),
                    (L10n.t("原因", "Reason"), object["reason"]?.stringValue ?? "—"),
                    (L10n.t("发送 / 确认 / 失败", "Sends / confirm / fail"),
                     "\(object["engine"]?.objectValue?["sends"]?.intValue ?? 0) / \(object["engine"]?.objectValue?["confirmations"]?.intValue ?? 0) / \(object["engine"]?.objectValue?["failures"]?.intValue ?? 0)"),
                    (L10n.t("模板", "Templates"),
                     "V12 \((object["templates"]?.objectValue?["v12"]?.objectValue?["ready"]?.boolValue ?? false) ? "READY" : "WAIT") · V13/14 \((object["templates"]?.objectValue?["v13V14"]?.objectValue?["ready"]?.boolValue ?? false) ? "READY" : "WAIT")"),
                    (L10n.t("车型支持", "Profile"), supported ? L10n.t("是", "Yes") : L10n.t("否", "No")),
                ])
            }
        }
        .listStyle(.insetGrouped)
        .contentMargins(.bottom, 28, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(Color.p4Background.ignoresSafeArea())
        .navigationTitle(L10n.t("SmartShift 自动换挡", "SmartShift"))
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) { ToastOverlay() }
        .task { await poll() }
    }

    private func updateFlag(_ key: String, _ value: Bool) async {
        busy = true
        defer { busy = false }
        _ = await fwWrite(environment, path: P4Route.smartShiftUpdate,
                          query: [P4Param(key, value ? "1" : "0")],
                          storeTo: P4Route.smartShiftStats)
        Haptics.impact()
    }

    private func updateValue(_ key: String, _ value: String) async {
        busy = true
        defer { busy = false }
        _ = await fwWrite(environment, path: P4Route.smartShiftUpdate,
                          query: [P4Param(key, value)],
                          storeTo: P4Route.smartShiftStats)
        Haptics.impact()
    }

    private func saveNumbers() async {
        busy = true
        defer { busy = false }
        for spec in numberSpecs {
            guard let raw = numbers[spec.key], let value = Int(raw), spec.range.contains(value) else { continue }
            _ = await fwWrite(environment, path: P4Route.smartShiftUpdate,
                              query: [P4Param(spec.key, String(value))],
                              storeTo: P4Route.smartShiftStats)
        }
        Haptics.success()
    }

    private func syncDrafts() {
        guard !draftsLoaded, !config.isEmpty else { return }
        for spec in numberSpecs {
            if let value = config[spec.key]?.intValue { numbers[spec.key] = String(value) }
        }
        draftsLoaded = true
    }

    private func poll() async {
        await environment.refreshEndpoint(P4Route.smartShiftStats)
        syncDrafts()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            await environment.refreshEndpoint(P4Route.smartShiftStats)
            syncDrafts()
        }
    }
}

// MARK: - R79 时序捕获

struct R79TimingView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var busy = false
    @State private var shareURL: URL?
    @State private var showShare = false

    private var stats: P4JSON? { environment.endpointValue(P4Route.r79TimingStatus) }
    private var object: [String: P4JSON] { stats?.objectValue ?? [:] }
    private var active: Bool { object["active"]?.boolValue ?? false }
    private var ready: Bool { stats != nil }
    private var exporting: Bool { object["exporting"]?.boolValue ?? false }

    private var hasSession: Bool {
        guard let value = object["session"] else { return false }
        if case .null = value { return false }
        return true
    }

    private var stateText: String {
        guard ready else { return L10n.t("读取中…", "Loading…") }
        if object["allocationFailed"]?.boolValue == true { return L10n.t("PSRAM 不可用", "PSRAM unavailable") }
        if active { return L10n.t("录制中", "Recording") }
        if object["expired"]?.boolValue == true { return L10n.t("10 分钟捕获已结束", "10-minute capture finished") }
        if hasSession { return L10n.t("已停止 · CSV 可导出", "Stopped · CSV ready") }
        return L10n.t("就绪", "Ready")
    }

    private var warnings: [String] {
        var items: [String] = []
        if let dropped = object["dropped"]?.intValue, dropped > 0 { items.append(L10n.t("丢弃 \(dropped) 条", "\(dropped) dropped")) }
        if let lost = object["driverErrorLost"]?.intValue, lost > 0 { items.append(L10n.t("CAN 2 错误丢失 \(lost)", "\(lost) CAN 2 errors lost")) }
        if let failures = object["driverSnapshotFailures"]?.intValue, failures > 0 { items.append(L10n.t("驱动快照失败 \(failures)", "\(failures) snapshot failures")) }
        if object["driverSequenceSaturated"]?.boolValue == true { items.append(L10n.t("CAN 2 错误序号饱和", "CAN 2 error sequence saturated")) }
        if object["driverImportPending"]?.boolValue == true { items.append(L10n.t("CAN 2 错误导入中", "CAN 2 error import pending")) }
        return items
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Button(L10n.t("开始录制", "Start")) { Task { await action("start") } }
                        .buttonStyle(.borderedProminent)
                        .disabled(busy || active || !ready || exporting)
                    Spacer()
                    Button(L10n.t("停止", "Stop")) { Task { await action("stop") } }
                        .buttonStyle(.bordered)
                        .disabled(busy || !active || exporting)
                }

                Button {
                    Task { await exportCSV() }
                } label: {
                    Label(L10n.t("导出 CSV", "Export CSV"), systemImage: "square.and.arrow.up")
                }
                .disabled(busy || active || exporting || !hasSession)
            } header: {
                Text(L10n.t("捕获", "Capture"))
            } footer: {
                Text(L10n.t("单次最长 10 分钟；录制中不能导出，停止后 CSV 才可用。",
                            "Up to 10 minutes per capture. Export is available after stopping."))
            }

            Section(L10n.t("状态", "Status")) {
                FWStatusRows(rows: [
                    (L10n.t("状态", "State"), stateText),
                    (L10n.t("记录 / 容量", "Records / capacity"),
                     "\(object["count"]?.intValue ?? 0) / \(object["capacity"]?.intValue ?? 32768)"),
                    (L10n.t("丢弃", "Dropped"), "\(object["dropped"]?.intValue ?? 0)"),
                    (L10n.t("已用时间", "Elapsed"),
                     String(format: "%.1f s", Double(object["elapsedMs"]?.intValue ?? 0) / 1000)),
                ])
                if !warnings.isEmpty {
                    Text(warnings.joined(separator: " · "))
                        .font(.footnote)
                        .foregroundStyle(.p4Warn)
                }
            }
        }
        .listStyle(.insetGrouped)
        .contentMargins(.bottom, 28, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(Color.p4Background.ignoresSafeArea())
        .navigationTitle(L10n.t("R79 时序捕获", "R79 Timing Capture"))
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) { ToastOverlay() }
        .sheet(isPresented: $showShare) {
            if let shareURL { FWActivityView(items: [shareURL]) }
        }
        .task { await poll() }
    }

    private func action(_ name: String) async {
        busy = true
        defer { busy = false }
        let path = name == "start" ? P4Route.r79TimingStart : P4Route.r79TimingStop
        _ = await fwWrite(environment, path: path, query: [], storeTo: P4Route.r79TimingStatus)
        Haptics.impact()
    }

    private func exportCSV() async {
        busy = true
        defer { busy = false }
        do {
            let data = try await environment.api.downloadData(P4Route.r79TimingCSV)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("P4_R79_Timing.csv")
            try data.write(to: url, options: .atomic)
            shareURL = url
            showShare = true
        } catch {
            environment.toast = P4Toast(message: AppEnvironment.friendly(error), style: .failure)
        }
    }

    private func poll() async {
        await environment.refreshEndpoint(P4Route.r79TimingStatus)
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            await environment.refreshEndpoint(P4Route.r79TimingStatus)
        }
    }
}

private struct FWActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - CAN GPIO 设置

struct CanGpioView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var draft: [Int] = [20, 21, 22, 23, 26, 27]
    @State private var loaded = false
    @State private var busy = false
    @State private var confirmSave = false

    private let keys = ["tx1", "rx1", "tx2", "rx2", "tx3", "rx3"]
    private let labels = [
        ("CAN 1 BODY", "TX"), ("CAN 1 BODY", "RX"),
        ("CAN 2 CHASSIS", "TX"), ("CAN 2 CHASSIS", "RX"),
        ("CAN 3 PARTY", "TX"), ("CAN 3 PARTY", "RX"),
    ]

    private var stats: P4JSON? { environment.endpointValue(P4Route.systemCanGpio) }
    private var object: [String: P4JSON] { stats?.objectValue ?? [:] }
    private var allowedPins: [Int] {
        (object["allowedPins"]?.arrayValue ?? []).compactMap { Int($0.intValue ?? -1) }
    }

    private func map(_ key: String) -> [[String: P4JSON]] {
        (object[key]?.arrayValue ?? []).compactMap { $0.objectValue }
    }

    private func pinText(_ key: String, _ index: Int) -> String {
        let rows = map(key)
        guard rows.indices.contains(index) else { return "—" }
        let tx = rows[index]["tx"]?.intValue ?? 0
        let rx = rows[index]["rx"]?.intValue ?? 0
        return "TX \(tx) / RX \(rx)"
    }

    var body: some View {
        List {
            Section(L10n.t("当前生效", "Active")) {
                FWStatusRows(rows: [
                    ("CAN 1 BODY", pinText("active", 0)),
                    ("CAN 2 CHASSIS", pinText("active", 1)),
                    ("CAN 3 PARTY", pinText("active", 2)),
                ])
            }

            Section {
                ForEach(0..<6, id: \.self) { index in
                    Picker("\(labels[index].0) \(labels[index].1)", selection: Binding(
                        get: { draft.indices.contains(index) ? draft[index] : 0 },
                        set: { value in
                            if draft.indices.contains(index) { draft[index] = value }
                        }
                    )) {
                        ForEach(allowedPins, id: \.self) { pin in
                            Text("GPIO \(pin)").tag(pin)
                        }
                    }
                    .disabled(busy)
                }
            } header: {
                Text(L10n.t("引脚", "Pins"))
            } footer: {
                Text(L10n.t("X179 线束：CHASSIS 2/3、BODY 4/5、PARTY 26/27；标准接线：20/21、22/23、26/27。保存会停止 CAN 并重启设备。",
                            "X179 harness: CHASSIS 2/3, BODY 4/5, PARTY 26/27. Standard: 20/21, 22/23, 26/27. Saving stops CAN and reboots."))
            }

            Section {
                Button(L10n.t("恢复默认引脚", "Restore defaults")) {
                    loadDefaults()
                }
                .disabled(busy)

                Button(role: .destructive) {
                    confirmSave = true
                } label: {
                    Label(L10n.t("保存并重启", "Save and reboot"), systemImage: "externaldrive.badge.checkmark")
                        .frame(maxWidth: .infinity)
                }
                .disabled(busy || allowedPins.isEmpty)
            }

            Section(L10n.t("状态", "Status")) {
                FWStatusRows(rows: [
                    (L10n.t("映射有效", "Mapping valid"), object["valid"]?.boolValue == true ? L10n.t("是", "Yes") : L10n.t("否", "No")),
                    (L10n.t("需要重启", "Reboot required"), object["rebootRequired"]?.boolValue == true ? L10n.t("是", "Yes") : L10n.t("否", "No")),
                    (L10n.t("CAN 已停止", "CAN stopped"), object["canStopped"]?.boolValue == true ? L10n.t("是", "Yes") : L10n.t("否", "No")),
                    (L10n.t("错误", "Error"), object["error"]?.stringValue ?? ""),
                ])
            }
        }
        .listStyle(.insetGrouped)
        .contentMargins(.bottom, 28, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(Color.p4Background.ignoresSafeArea())
        .navigationTitle(L10n.t("CAN GPIO 设置", "CAN GPIO"))
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) { ToastOverlay() }
        .confirmationDialog(L10n.t("保存 GPIO 并重启？", "Save GPIO and reboot?"),
                            isPresented: $confirmSave, titleVisibility: .visible) {
            Button(L10n.t("保存并重启", "Save and reboot"), role: .destructive) { Task { await save() } }
            Button(L10n.t("取消", "Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t("设备会停止 CAN、写入引脚并重启；重启后请确认三路总线都有数据。",
                        "The device stops CAN, writes the pins and reboots. Verify all three buses afterwards."))
        }
        .task { await poll() }
        .onChange(of: stats) { _, _ in loadDraftsIfNeeded() }
    }

    private func loadDraftsIfNeeded() {
        guard !loaded else { return }
        let rows = map("saved").isEmpty ? map("active") : map("saved")
        guard rows.count == 3 else { return }
        var values: [Int] = []
        for row in rows {
            values.append(Int(row["tx"]?.intValue ?? 0))
            values.append(Int(row["rx"]?.intValue ?? 0))
        }
        draft = values
        loaded = true
    }

    private func loadDefaults() {
        let rows = map("defaults")
        guard rows.count == 3 else { return }
        var values: [Int] = []
        for row in rows {
            values.append(Int(row["tx"]?.intValue ?? 20))
            values.append(Int(row["rx"]?.intValue ?? 21))
        }
        draft = values
        Haptics.impact()
    }

    private func save() async {
        busy = true
        defer { busy = false }
        let query = zip(keys, draft).map { P4Param($0.0, String($0.1)) }
        _ = await fwWrite(environment, path: P4Route.systemCanGpio, query: query, storeTo: P4Route.systemCanGpio)
        environment.toast = P4Toast(message: L10n.t("GPIO 已保存，设备重启中…", "GPIO saved; device rebooting…"), style: .success)
        Haptics.success()
    }

    private func poll() async {
        await environment.refreshEndpoint(P4Route.systemCanGpio)
        loadDraftsIfNeeded()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(2))
            await environment.refreshEndpoint(P4Route.systemCanGpio)
            loadDraftsIfNeeded()
        }
    }
}
