import SwiftUI

/// 设置 → 更改车型：对应固件网页车型卡片的 `Change` 流程。
///
/// 契约（web_api.h `httpProfileSelect`）：
/// `POST /api/profile/select?profile=&topology=&turn=`，成功后设备**立即重启**，
/// 在 CAN 初始化前应用新车型；错误会返回 400/409/503 的具体原因。
struct VehicleProfileChangeView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    /// 固件 `VehicleModel` 枚举（vehicle_profile.h）
    private struct Vehicle: Identifiable {
        let id: Int
        let name: String
        let badge: String
        let topology: Int
        let detail: String
    }

    private static let vehicles: [Vehicle] = [
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

    @State private var selectedID: Int
    @State private var turn: Int
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
        Self.vehicles.first { $0.id == selectedID }
    }

    /// 只有 Model 3 Highland 需要选拨杆；其余车型固件固定 STALK。
    private var needsTurnChoice: Bool { selectedID == 4 }

    private var resolvedTurn: Int {
        needsTurnChoice ? turn : 1
    }

    var body: some View {
        List {
            Section {
                ForEach(Self.vehicles) { vehicle in
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
                Text(L10n.t("CAN 拓扑由车型决定：Model Y L 使用 Party + VH，其余车型使用 Body + Chassis + Party。",
                            "CAN topology is fixed by model: Model Y L uses Party + VH; other models use Body + Chassis + Party."))
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

            Section {
                HStack {
                    Text(L10n.t("当前车型", "Current profile"))
                    Spacer()
                    Text(environment.profileName ?? "—")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
            } footer: {
                Text(L10n.t("保存后 P4-CAN 会立即重启，并在 CAN 初始化前应用新车型；正在进行的注入会停止。",
                            "P4-CAN reboots immediately after saving and applies the profile before CAN initialization. Active injection stops."))
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
                .disabled(saving || confirming || selectedVehicle == nil)
            }
        }
        .listStyle(.insetGrouped)
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
            L10n.t("保存并重启 P4-CAN？", "Save profile and reboot P4-CAN?"),
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
            Text(L10n.t("设备正在重启并应用新车型。若 Wi-Fi 未开启自动加入，请手动重连 P4-CAN 热点。",
                        "P4-CAN is rebooting with the new profile. Reconnect to its hotspot manually if Auto-Join is off."))
        }
    }

    private var summary: String {
        let vehicle = selectedVehicle?.name ?? "—"
        let topology = selectedVehicle?.topology == 1 ? "Party + VH" : "Body + Chassis + Party"
        let turnText = needsTurnChoice
            ? (turn == 2 ? "STALKLESS · 0x3C2" : "STALK · 0x249")
            : "STALK · 0x249"
        return L10n.t("车型：\(vehicle)\n拓扑：\(topology)\n拨杆：\(turnText)\n\n保存后设备立即重启。",
                      "Vehicle: \(vehicle)\nTopology: \(topology)\nTurn: \(turnText)\n\nP4-CAN reboots immediately after saving.")
    }

    private func loadCurrent() {
        #if DEBUG
        // 本地联调：SIMCTL_CHILD_P4CAN_PROFILE_ID=4 预选车型（验证 Highland 拨杆选项）
        if let raw = ProcessInfo.processInfo.environment["P4CAN_PROFILE_ID"],
           let id = Int(raw), Self.vehicles.contains(where: { $0.id == id }) {
            selectedID = id
            if id == 4 { turn = 1 }
            return
        }
        #endif
        guard let raw = environment.profileStatus?["profile"]?.intValue else { return }
        let id = Int(raw)
        if Self.vehicles.contains(where: { $0.id == id }) {
            selectedID = id
        }
        if let storedTurn = environment.profileStatus?["turn"]?.intValue {
            turn = Int(storedTurn) == 2 ? 2 : 1
        }
    }

    private func save() async {
        guard let vehicle = selectedVehicle else { return }
        saving = true
        errorText = nil
        let query = [
            P4Param("profile", String(vehicle.id)),
            P4Param("topology", String(vehicle.topology)),
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
            }
            saving = false
            errorText = AppEnvironment.friendly(error)
            Haptics.error()
        }
    }

    /// 重启期间反复读取 profile/status，直到设备回来并报告目标车型。
    private func confirmApplied(_ profileID: Int) async -> Bool {
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            try? await Task.sleep(for: .milliseconds(1200))
            guard let status = try? await environment.api.get(P4Route.profileStatus),
                  let raw = status.objectValue?["profile"]?.intValue else { continue }
            if Int(raw) == profileID { return true }
        }
        return false
    }
}
