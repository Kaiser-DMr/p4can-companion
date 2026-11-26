import SwiftUI

/// 设置 → 更改车型：对应固件网页车型卡片的 `Change` 流程。
///
/// 契约（web_api.h `httpProfileSelect`）：
/// `POST /api/profile/select?profile=&topology=&turn=`，成功后设备**立即重启**，
/// 在 CAN 初始化前应用新车型；错误会返回 400/409/503 的具体原因。
struct VehicleProfileChangeView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    /// 固件 `VehicleModel` 枚举（vehicle_profile.h）
    private struct Vehicle: Identifiable {
        let id: Int
        let name: String
        let badge: String
        let topology: Int
        let detail: String
    }

    private static let p4Vehicles: [Vehicle] = [
        Vehicle(id: 1, name: "Model Y L", badge: "YL", topology: 1,
                detail: "CAN A · PARTY / CAN B · VH"),
        Vehicle(id: 2, name: "Model Y Juniper", badge: "YJ", topology: 2,
                detail: "CAN A · BODY / CAN B · CHASSIS / CAN C · PARTY"),
        Vehicle(id: 3, name: "Model Y Legacy", badge: "Y", topology: 2,
                detail: "CAN A · BODY / CAN B · CHASSIS / CAN C · PARTY"),
        Vehicle(id: 4, name: "Model 3 Highland", badge: "3H", topology: 2,
                detail: "CAN A · BODY / CAN B · CHASSIS / CAN C · PARTY"),
        Vehicle(id: 5, name: "Model 3 Legacy", badge: "3", topology: 2,
                detail: "CAN A · BODY / CAN B · CHASSIS / CAN C · PARTY"),
    ]

    /// T2CAN 3.30.x 支持的车型（vehicle_profile.h），只有两路 CAN。
    private static let t2Vehicles: [Vehicle] = [
        Vehicle(id: 1, name: "Model Y L", badge: "YL", topology: 1,
                detail: "CAN A · PARTY / CAN B · VH"),
        Vehicle(id: 6, name: "Model S/X MCU2 HW3", badge: "S/X", topology: 1,
                detail: "CAN A · PARTY / CAN B · VH"),
        Vehicle(id: 2, name: "Model Y Juniper", badge: "YJ", topology: 2,
                detail: "CAN A · BODY / CAN B · CHASSIS"),
        Vehicle(id: 3, name: "Model Y Legacy", badge: "Y", topology: 2,
                detail: "CAN A · BODY / CAN B · CHASSIS"),
        Vehicle(id: 4, name: "Model 3 Highland", badge: "3H", topology: 2,
                detail: "CAN A · BODY / CAN B · CHASSIS"),
        Vehicle(id: 5, name: "Model 3 Legacy", badge: "3", topology: 2,
                detail: "CAN A · BODY / CAN B · CHASSIS"),
    ]

    private var isT2: Bool { environment.deviceFamily == .t2can }
    private var vehicles: [Vehicle] { isT2 ? Self.t2Vehicles : Self.p4Vehicles }

    @State private var selectedID: Int
    @State private var turn: Int
    /// T2CAN 非 YL 车型可在 Body+Chassis / Party+Chassis 之间选。
    @State private var t2Topology: Int = 2
    @State private var confirms = false
    @State private var saving = false
    @State private var confirming = false
    @State private var saved = false
    @State private var errorText: String?

    init() {
        // 由调用方通过 `initialProfile` 覆盖；默认 Model Y Juniper。
        _selectedID = State(initialValue: 2)
        _turn = State(initialValue: 1)
    }

    private var selectedVehicle: Vehicle? {
        vehicles.first { $0.id == selectedID }
    }

    /// 只有 Model 3 Highland 需要选拨杆；其余车型固件固定 STALK。
    private var needsTurnChoice: Bool { selectedID == 4 }

    private var resolvedTurn: Int {
        needsTurnChoice ? turn : 1
    }

    /// P4 的拓扑由车型固定；T2CAN 非 YL 车型允许选 Body/Party + Chassis。
    private var resolvedTopology: Int {
        guard let vehicle = selectedVehicle else { return 2 }
        if isT2, vehicle.topology != 1 { return t2Topology }
        return vehicle.topology
    }

    var body: some View {
        List {
            Section {
                ForEach(vehicles) { vehicle in
                    Button {
                        Haptics.impact()
                        selectedID = vehicle.id
                        if vehicle.id == 4, turn == 0 { turn = 1 }
                    } label: {
                        HStack(spacing: 12) {
                            Text(vehicle.badge)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(selectedID == vehicle.id ? Color.white : Color.secondary)
                                .frame(width: 36, height: 36)
                                .background(selectedID == vehicle.id ? Color.accentColor : Color.p4Tile,
                                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(vehicle.name)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.primary)
                                Text(vehicle.detail)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            if selectedID == vehicle.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                                    .accessibilityHidden(true)
                            }
                        }
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedID == vehicle.id ? .isSelected : [])
                }
            } header: {
                Text(L10n.t("车型", "Vehicle"))
            } footer: {
                if isT2 {
                    Text(L10n.t("T2CAN 只有两路 CAN：Model Y L / Model S X 使用 Party + VH，其余车型默认 Body + Chassis。",
                                "T2CAN has two CAN buses: Model Y L / Model S X use Party + VH; other models default to Body + Chassis."))
                } else {
                    Text(L10n.t("CAN 拓扑由车型决定：Model Y L 使用 Party + VH，其余车型使用 Body + Chassis + Party。",
                                "CAN topology is fixed by model: Model Y L uses Party + VH; other models use Body + Chassis + Party."))
                }
            }

            if needsTurnChoice {
                Section {
                    Picker(L10n.t("拨杆类型", "Turn signal"), selection: $turn) {
                        Text("STALK · 0x249").tag(1)
                        Text("STALKLESS · 0x3C2").tag(2)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text(L10n.t("转向灯传输", "Turn signal transport"))
                } footer: {
                    Text(L10n.t("Model 3 Highland 必须选择与实际车辆一致的拨杆类型，否则转向灯与变道功能会异常。",
                                "Model 3 Highland requires the turn-signal variant that matches the car."))
                }
            }

            if isT2, let vehicle = selectedVehicle, vehicle.topology != 1 {
                Section {
                    Picker(L10n.t("CAN 拓扑", "CAN topology"), selection: $t2Topology) {
                        Text("Body + Chassis").tag(2)
                        Text("Party + Chassis").tag(3)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text(L10n.t("拓扑", "Topology"))
                } footer: {
                    Text(L10n.t("只有不确定原车接线时才改；选错会让 NAG / 转向灯路由失效。",
                                "Change this only if the stock wiring is non-standard; a wrong choice breaks NAG and turn-signal routing."))
                }
            }

            Section {
                HStack {
                    Text(L10n.t("当前车型", "Current profile"))
                    Spacer()
                    Text(environment.profileName ?? "—")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
            } footer: {
                Text(L10n.t("保存后 \(environment.deviceName) 会立即重启，并在 CAN 初始化前应用新车型；正在进行的注入会停止。",
                            "\(environment.deviceName) reboots immediately after saving and applies the profile before CAN initialization. Active injection stops."))
            }

            if let errorText {
                Section {
                    Label(errorText, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.p4Err)
                }
            }

            Section {
                Button {
                    confirms = true
                } label: {
                    if confirming {
                        Label(L10n.t("正在确认设备重启…", "Waiting for the device…"), systemImage: "hourglass")
                    } else if saving {
                        Label(L10n.t("正在保存…", "Saving…"), systemImage: "hourglass")
                    } else {
                        Label(L10n.t("保存车型并重启", "Save Profile & Reboot"), systemImage: "checkmark.circle")
                    }
                }
                .disabled(saving || confirming || selectedVehicle == nil
                          || !environment.isOnline || isAlreadyCurrent)
            }
        }
        .listStyle(.insetGrouped)
        .p4ListStyle()
        .navigationTitle(L10n.t("更改车型", "Change Vehicle"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.t("取消", "Cancel")) { dismiss() }
            }
        }
        .overlay(alignment: .bottom) { ToastOverlay() }
        .onAppear(perform: loadCurrent)
        .confirmationDialog(
            L10n.t("保存并重启 \(environment.deviceName)？", "Save profile and reboot \(environment.deviceName)?"),
            isPresented: $confirms,
            titleVisibility: .visible
        ) {
            Button(L10n.t("保存并重启", "Save & Reboot"), role: .destructive) {
                Task { await save() }
            }
            Button(L10n.t("取消", "Cancel"), role: .cancel) {}
        } message: {
            Text(summary)
        }
        .alert(L10n.t("车型已保存", "Profile saved"), isPresented: $saved) {
            Button(L10n.t("完成", "Done")) { dismiss() }
        } message: {
            Text(L10n.t("设备正在重启并应用新车型。若 Wi-Fi 未开启自动加入，请手动重连 \(environment.deviceName) 热点。",
                        "\(environment.deviceName) is rebooting with the new profile. Reconnect to its hotspot manually if Auto-Join is off."))
        }
    }

    private var summary: String {
        let vehicle = selectedVehicle?.name ?? "—"
        let topology: String
        if resolvedTopology == 1 {
            topology = "Party + VH"
        } else if isT2 {
            topology = resolvedTopology == 3 ? "Party + Chassis" : "Body + Chassis"
        } else {
            topology = "Body + Chassis + Party"
        }
        let turnText = needsTurnChoice
            ? (turn == 2 ? "STALKLESS · 0x3C2" : "STALK · 0x249")
            : "STALK · 0x249"
        return L10n.t("车型：\(vehicle)\n拓扑：\(topology)\n拨杆：\(turnText)\n\n保存后设备立即重启。",
                      "Vehicle: \(vehicle)\nTopology: \(topology)\nTurn: \(turnText)\n\n\(environment.deviceName) reboots immediately after saving.")
    }

    private func loadCurrent() {
        #if DEBUG
        // 本地联调：SIMCTL_CHILD_P4CAN_PROFILE_ID=4 预选车型（验证 Highland 拨杆选项）
        if let raw = ProcessInfo.processInfo.environment["P4CAN_PROFILE_ID"],
           let id = Int(raw), vehicles.contains(where: { $0.id == id }) {
            selectedID = id
            if id == 4 { turn = 1 }
            return
        }
        #endif
        guard let raw = environment.profileStatus?["profile"]?.intValue else { return }
        let id = Int(raw)
        if vehicles.contains(where: { $0.id == id }) {
            selectedID = id
        }
        if let storedTopology = environment.profileStatus?["topology"]?.intValue,
           isT2, storedTopology == 3 {
            t2Topology = 3
        }
        if let storedTurn = environment.profileStatus?["turn"]?.intValue {
            turn = Int(storedTurn) == 2 ? 2 : 1
        }
    }

    /// 选中的就是当前车型：再保存只会触发一次无意义重启。
    private var isAlreadyCurrent: Bool {
        guard let selected = selectedVehicle,
              let current = environment.profileStatus?["profile"]?.intValue else { return false }
        guard selected.id == Int(current) else { return false }
        // T2CAN 同一车型可能切过拓扑，拓扑不同仍要允许保存。
        if isT2, let currentTopology = environment.profileStatus?["topology"]?.intValue {
            return resolvedTopology == Int(currentTopology)
        }
        return true
    }

    private func save() async {
        guard let vehicle = selectedVehicle else { return }
        saving = true
        errorText = nil
        let query = [
            P4Param("profile", String(vehicle.id)),
            P4Param("topology", String(resolvedTopology)),
            P4Param("turn", String(resolvedTurn)),
        ]
        do {
            let result = try await environment.api.post(P4Route.profileSelect, query: query)
            guard result.objectValue?["ok"]?.boolValue != false else {
                throw P4APIError(message: result.objectValue?["error"]?.stringValue ?? "保存失败")
            }
            await environment.refreshProfile()
            Haptics.success()
            saving = false
            saved = true
        } catch {
            // 固件回 200 后会立即重启，连接可能先断：用回读的车型确认是否已生效。
            if !(error is P4APIError) {
                confirming = true
                if await confirmApplied(vehicle.id) {
                    await environment.refreshProfile()
                    confirming = false
                    saving = false
                    Haptics.success()
                    saved = true
                    return
                }
                confirming = false
                saving = false
                // 已提交但没回读到时不要指向网络：设备可能正在应用新车型。
                errorText = L10n.t("已提交，但设备尚未回读新车型（可能正在重启）；请回设置页确认。",
                                   "Submitted, but the new profile has not been read back yet. It may still be rebooting — check Settings.")
                Haptics.warning()
                return
            }
            saving = false
            errorText = AppEnvironment.friendly(error)
            Haptics.error()
        }
    }

    /// 重启期间反复读取 profile/status，直到设备回来并报告目标车型。
    private func confirmApplied(_ profileID: Int) async -> Bool {
        // 设备重启 + CAN 初始化常超过 20 s，窗口太短会把成功判成失败。
        let deadline = Date().addingTimeInterval(45)
        while Date() < deadline {
            try? await Task.sleep(for: .milliseconds(1200))
            guard let status = try? await environment.api.get(P4Route.profileStatus),
                  let raw = status.objectValue?["profile"]?.intValue else { continue }
            if Int(raw) == profileID { return true }
        }
        return false
    }
}
