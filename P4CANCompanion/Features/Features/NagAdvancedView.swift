import SwiftUI

/// NAG 高级参数（报文级）：对应固件网页 NAG 面板的 Advanced Parameters。
///
/// 契约（web_api.h `httpNagUpdate`，局部更新）：
/// - `targetId` / `apStateId` / `steeringId`：C 风格整数（`0x399` 或十进制），1…0x7FF；
/// - `hoRatePct`：0…100；`burstMs`：50…10000；`pauseMs`：0…10000；
/// - 只提交这 6 个字段即可，扭矩表保持设备当前值。
///
/// 固件对越界 ID 是**静默忽略**，所以这里严格校验，并在写入后回读比对。
struct NagAdvancedView: View {
    @Environment(AppEnvironment.self) private var environment

    private struct Snapshot {
        var targetId: Int
        var apStateId: Int
        var steeringId: Int
        var hoRatePct: Int
        var burstMs: Int
        var pauseMs: Int
    }

    private struct TorqueRow: Identifiable {
        let id: Int
        let b2: Int
        let b3: Int
        let nm: Double
    }

    @State private var targetIdText = ""
    @State private var apStateIdText = ""
    @State private var steeringIdText = ""
    @State private var hoRateText = ""
    @State private var burstText = ""
    @State private var pauseText = ""

    @State private var loaded: Snapshot?
    @State private var torque: [TorqueRow] = []
    @State private var apActive = false
    @State private var stale = false
    @State private var loadError: String?
    @State private var busy = false
    @State private var confirms = false
    @State private var attempt: String?

    private var setupMode: Bool { environment.isSetupMode }
    private var canEdit: Bool { !busy && !setupMode && !apActive && loaded != nil }

    // MARK: - 解析与校验

    private static func parseID(_ text: String) -> Int? {
        var raw = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !raw.isEmpty else { return nil }
        if raw.hasPrefix("0x") { raw.removeFirst(2) }
        guard let value = Int(raw, radix: 16) else { return nil }
        return (1...0x7FF).contains(value) ? value : nil
    }

    private static func parseInt(_ text: String, range: ClosedRange<Int>) -> Int? {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(raw), range.contains(value) else { return nil }
        return value
    }

    private var edited: Snapshot? {
        guard let target = Self.parseID(targetIdText),
              let ap = Self.parseID(apStateIdText),
              let steering = Self.parseID(steeringIdText),
              let ho = Self.parseInt(hoRateText, range: 0...100),
              let burst = Self.parseInt(burstText, range: 50...10_000),
              let pause = Self.parseInt(pauseText, range: 0...10_000) else { return nil }
        return Snapshot(targetId: target, apStateId: ap, steeringId: steering,
                        hoRatePct: ho, burstMs: burst, pauseMs: pause)
    }

    private var fieldErrors: [String] {
        var errors: [String] = []
        if Self.parseID(targetIdText) == nil { errors.append(L10n.t("目标 ID：0x001–0x7FF", "Target ID: 0x001–0x7FF")) }
        if Self.parseID(apStateIdText) == nil { errors.append(L10n.t("AP 状态 ID：0x001–0x7FF", "AP state ID: 0x001–0x7FF")) }
        if Self.parseID(steeringIdText) == nil { errors.append(L10n.t("转向 ID：0x001–0x7FF", "Steering ID: 0x001–0x7FF")) }
        if Self.parseInt(hoRateText, range: 0...100) == nil { errors.append(L10n.t("HO 比例：0–100", "HO rate: 0–100")) }
        if Self.parseInt(burstText, range: 50...10_000) == nil { errors.append(L10n.t("Burst：50–10000 ms", "Burst: 50–10000 ms")) }
        if Self.parseInt(pauseText, range: 0...10_000) == nil { errors.append(L10n.t("Pause：0–10000 ms", "Pause: 0–10000 ms")) }
        return errors
    }

    private var changes: [String] {
        guard let edited, let loaded else { return [] }
        var items: [String] = []
        func hex(_ value: Int) -> String { String(format: "0x%03X", value) }
        if edited.targetId != loaded.targetId {
            items.append("\(L10n.t("目标 ID", "Target ID")) \(hex(loaded.targetId)) → \(hex(edited.targetId))")
        }
        if edited.apStateId != loaded.apStateId {
            items.append("\(L10n.t("AP 状态 ID", "AP state ID")) \(hex(loaded.apStateId)) → \(hex(edited.apStateId))")
        }
        if edited.steeringId != loaded.steeringId {
            items.append("\(L10n.t("转向 ID", "Steering ID")) \(hex(loaded.steeringId)) → \(hex(edited.steeringId))")
        }
        if edited.hoRatePct != loaded.hoRatePct {
            items.append("HO \(loaded.hoRatePct)% → \(edited.hoRatePct)%")
        }
        if edited.burstMs != loaded.burstMs {
            items.append("Burst \(loaded.burstMs) → \(edited.burstMs) ms")
        }
        if edited.pauseMs != loaded.pauseMs {
            items.append("Pause \(loaded.pauseMs) → \(edited.pauseMs) ms")
        }
        return items
    }

    // MARK: - Body

    var body: some View {
        List {
            Section {
                Label {
                    Text(L10n.t("这些是 0x370 接收与 0x399 注入的报文级参数。改错会导致 NAG 完全失效或行为异常；不确定时不要修改。",
                                "These are frame-level parameters for 0x370 RX and 0x399 TX. Wrong values can break NAG entirely. Do not change them unless you understand them."))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.p4Warn)
                }
                .font(.footnote)
            }

            if setupMode {
                statusRow(L10n.t("设备处于 Setup 模式，参数写入已禁用。", "Setup mode: writes are disabled."))
            } else if apActive {
                statusRow(L10n.t("AP 激活中，暂不可修改高级参数；请先退出 AP。",
                                 "AP is active. Exit Autopilot before changing advanced parameters."))
            }

            if stale {
                Section {
                    Label(L10n.t("设备端参数已被网页或其他人修改。请先「重新从设备读取」，否则应用会覆盖这些改动。",
                                 "These parameters changed on the device. Reload before applying, or your write will overwrite them."),
                          systemImage: "arrow.triangle.2.circlepath")
                        .font(.footnote)
                        .foregroundStyle(.p4Warn)
                    Button(L10n.t("重新从设备读取", "Reload from device")) {
                        Task { await load(force: true) }
                    }
                    .font(.footnote)
                }
            }

            Section {
                hexRow(L10n.t("目标 ID", "Target ID"), text: $targetIdText,
                       hint: L10n.t("接收的转向报文 ID，默认 0x370", "Steering frame ID to receive, default 0x370"))
                hexRow(L10n.t("AP 状态 ID", "AP state ID"), text: $apStateIdText,
                       hint: L10n.t("AP 状态报文的源 ID，默认 0x399", "Source ID of the AP state frame, default 0x399"))
                hexRow(L10n.t("转向 ID", "Steering ID"), text: $steeringIdText,
                       hint: L10n.t("转向角报文 ID，默认 0x129", "Steering-angle frame ID, default 0x129"))
            } header: {
                Text(L10n.t("报文 ID", "Frame IDs"))
            } footer: {
                Text(L10n.t("支持 0x001–0x7FF 的十六进制，或同等十进制；下方会显示十进制值。",
                            "Accepts hexadecimal 0x001–0x7FF or the decimal equivalent; the decimal value is shown below."))
            }

            Section {
                decimalRow(L10n.t("HO 比例", "HO rate"), text: $hoRateText, unit: "%",
                           range: "0–100")
                decimalRow(L10n.t("Burst", "Burst"), text: $burstText, unit: "ms",
                           range: "50–10000")
                decimalRow(L10n.t("Pause", "Pause"), text: $pauseText, unit: "ms",
                           range: "0–10000")
            } header: {
                Text(L10n.t("报文节奏", "Frame timing"))
            } footer: {
                Text(L10n.t("Burst 为单次注入的持续时间，Pause 为两次注入之间的间隔。",
                            "Burst is the duration of one injection; Pause is the gap between injections."))
            }

            torqueSection

            if loaded != nil, !fieldErrors.isEmpty {
                Section {
                    ForEach(fieldErrors, id: \.self) { message in
                        Label(message, systemImage: "xmark.circle")
                            .font(.footnote)
                            .foregroundStyle(.p4Err)
                    }
                }
            }

            if let attempt {
                Section {
                    Label(attempt, systemImage: "checkmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.p4OK)
                }
            }

            if let loadError {
                Section {
                    Label(loadError, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.p4Err)
                }
            }

            Section {
                Button {
                    confirms = true
                } label: {
                    Label(busy ? L10n.t("正在写入…", "Writing…")
                               : L10n.t("应用高级参数", "Apply advanced parameters"),
                          systemImage: "checkmark.circle")
                }
                .disabled(!canEdit || edited == nil || changes.isEmpty)

                Button {
                    fillFromLoaded()
                    attempt = nil
                } label: {
                    Label(L10n.t("撤销未保存修改", "Revert unsaved changes"), systemImage: "arrow.uturn.backward")
                }
                .disabled(busy || loaded == nil)

                Button {
                    Task { await load(force: true) }
                } label: {
                    Label(L10n.t("重新从设备读取", "Reload from device"), systemImage: "arrow.clockwise")
                }
                .disabled(busy)
            } footer: {
                Text(L10n.t("只提交这 6 个字段，扭矩表保持设备当前值；写入后会立即回读校验。",
                            "Only these six fields are submitted; the torque table is left untouched. Values are read back and compared after writing."))
            }
        }
        .listStyle(.insetGrouped)
        .p4ListStyle()
        .navigationTitle(L10n.t("高级参数（报文级）", "Advanced parameters"))
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) { ToastOverlay() }
        .task { await poll() }
        .confirmationDialog(
            L10n.t("写入 NAG 高级参数？", "Write NAG advanced parameters?"),
            isPresented: $confirms,
            titleVisibility: .visible
        ) {
            Button(L10n.t("确认写入", "Write"), role: .destructive) {
                Task { await apply() }
            }
            Button(L10n.t("取消", "Cancel"), role: .cancel) {}
        } message: {
            Text(changes.joined(separator: "\n"))
        }
    }

    private func statusRow(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.octagon")
            .font(.footnote)
            .foregroundStyle(.p4Warn)
    }

    private func hexRow(_ title: String, text: Binding<String>, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                Spacer()
                TextField("0x370", text: text)
                    .keyboardType(.asciiCapable)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .p4NumberField(width: 110)
                    .disabled(!canEdit)
                    .accessibilityLabel(title)
            }
            .font(.subheadline)
            HStack {
                Text(hint).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                if let value = Self.parseID(text.wrappedValue) {
                    Text("= \(value)").font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func decimalRow(_ title: String, text: Binding<String>, unit: String, range: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline)
                Text(range).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            TextField("0", text: text)
                .keyboardType(.numberPad)
                .p4NumberField(width: 90)
                .disabled(!canEdit)
                .accessibilityLabel(title)
            Text(unit).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var torqueSection: some View {
        Section {
            if torque.isEmpty {
                Text(L10n.t("设备未上报扭矩表", "No torque table reported"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(torque) { row in
                    HStack {
                        Text("#\(row.id + 1)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .leading)
                        Text(String(format: "0x%02X", row.b2))
                        Text(String(format: "0x%02X", row.b3))
                        Spacer()
                        Text(String(format: "%.2f Nm", row.nm))
                            .monospacedDigit()
                    }
                    .font(.system(.caption, design: .monospaced))
                }
            }
        } header: {
            Text(L10n.t("扭矩表（只读）", "Torque table (read-only)"))
        } footer: {
            Text(L10n.t("扭矩表仍由网页端编辑；App 第一期只展示，不会写入或清空。",
                        "The torque table remains web-editable; this app only displays it and never writes or clears it."))
        }
    }

    // MARK: - 读写

    private func poll() async {
        while !Task.isCancelled {
            if loaded == nil {
                await load(force: false)
            } else {
                await checkFreshness()
            }
            await loadAPState()
            try? await Task.sleep(for: .milliseconds(1500))
        }
    }

    /// 只比较设备基线，不覆盖正在编辑的输入框。
    private func checkFreshness() async {
        guard let loaded,
              let config = try? await environment.api.get(P4Route.nagConfig),
              let device = snapshot(from: config) else { return }
        if signature(device) != signature(loaded) { stale = true }
    }

    private func load(force: Bool) async {
        do {
            let config = try await environment.api.get(P4Route.nagConfig)
            apply(config: config)
            if force { attempt = nil }
            stale = false
            loadError = nil
        } catch {
            loadError = AppEnvironment.friendly(error)
        }
    }

    private func loadAPState() async {
        guard let stats = try? await environment.api.get(P4Route.nagStats),
              let active = stats.objectValue?["apActive"]?.boolValue else { return }
        apActive = active
    }

    private func snapshot(from config: P4JSON) -> Snapshot? {
        guard let object = config.objectValue else { return nil }
        func int(_ key: String) -> Int? { object[key]?.intValue.map(Int.init) }
        guard let target = int("targetId"), let ap = int("apStateId"), let steering = int("steeringId"),
              let ho = int("hoRatePct"), let burst = int("burstMs"), let pause = int("pauseMs") else { return nil }
        return Snapshot(targetId: target, apStateId: ap, steeringId: steering,
                        hoRatePct: ho, burstMs: burst, pauseMs: pause)
    }

    private func signature(_ value: Snapshot) -> String {
        "\(value.targetId)/\(value.apStateId)/\(value.steeringId)/\(value.hoRatePct)/\(value.burstMs)/\(value.pauseMs)"
    }

    private func apply(config: P4JSON) {
        guard let object = config.objectValue, let snapshot = snapshot(from: config) else { return }
        loaded = snapshot
        stale = false
        torque = (object["torque"]?.arrayValue ?? []).enumerated().compactMap { index, value in
            guard let row = value.objectValue,
                  let b2 = row["b2"]?.intValue, let b3 = row["b3"]?.intValue,
                  let nm = row["nm"]?.doubleValue else { return nil }
            return TorqueRow(id: index, b2: Int(b2), b3: Int(b3), nm: nm)
        }
        fillFromLoaded()
    }

    private func fillFromLoaded() {
        guard let loaded else { return }
        targetIdText = String(format: "0x%03X", loaded.targetId)
        apStateIdText = String(format: "0x%03X", loaded.apStateId)
        steeringIdText = String(format: "0x%03X", loaded.steeringId)
        hoRateText = String(loaded.hoRatePct)
        burstText = String(loaded.burstMs)
        pauseText = String(loaded.pauseMs)
    }

    private func apply() async {
        guard let edited, let loaded else { return }
        guard !apActive, !setupMode else { return }
        busy = true
        attempt = nil
        // 若设备基线在打开页面后被改过，拒绝写入，避免把别人的改动覆盖掉。
        if let config = try? await environment.api.get(P4Route.nagConfig),
           let device = snapshot(from: config), signature(device) != signature(loaded) {
            stale = true
            loadError = L10n.t("设备端参数已变化，请先「重新从设备读取」再应用。",
                               "Device parameters changed. Reload before applying.")
            busy = false
            Haptics.error()
            return
        }
        let query = [
            P4Param("targetId", String(format: "0x%03X", edited.targetId)),
            P4Param("apStateId", String(format: "0x%03X", edited.apStateId)),
            P4Param("steeringId", String(format: "0x%03X", edited.steeringId)),
            P4Param("hoRatePct", String(edited.hoRatePct)),
            P4Param("burstMs", String(edited.burstMs)),
            P4Param("pauseMs", String(edited.pauseMs)),
        ]
        do {
            _ = try await environment.api.post(P4Route.nagUpdate, query: query)
            let config = try await environment.api.get(P4Route.nagConfig)
            guard let object = config.objectValue else { throw P4APIError(message: "回读失败") }
            func int(_ key: String) -> Int? { object[key]?.intValue.map(Int.init) }
            let mismatches = [
                int("targetId") == edited.targetId ? nil : "targetId",
                int("apStateId") == edited.apStateId ? nil : "apStateId",
                int("steeringId") == edited.steeringId ? nil : "steeringId",
                int("hoRatePct") == edited.hoRatePct ? nil : "hoRatePct",
                int("burstMs") == edited.burstMs ? nil : "burstMs",
                int("pauseMs") == edited.pauseMs ? nil : "pauseMs",
            ].compactMap { $0 }
            apply(config: config)
            if mismatches.isEmpty {
                attempt = L10n.t("已写入并回读确认", "Written and verified by read-back")
                Haptics.success()
                environment.toast = P4Toast(message: L10n.t("高级参数已生效", "Advanced parameters applied"), style: .success)
            } else {
                attempt = nil
                loadError = L10n.t("设备未接受：\(mismatches.joined(separator: ", "))",
                                   "Device rejected: \(mismatches.joined(separator: ", "))")
                Haptics.error()
            }
        } catch {
            loadError = AppEnvironment.friendly(error)
            Haptics.error()
        }
        busy = false
    }
}
