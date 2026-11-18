import SwiftUI

/// 前大灯爆闪：远光灯 PULL/IDLE 交替 `count` 次，结束后恢复触发前的高灯状态。
///
/// 固件契约（`/api/headlight-strobe/*`）：
/// - `config`：count 1–30、intervalMs 50–1000、trigger 0=App / 1=S3XY；
/// - `trigger`：仅当 trigger 与入口匹配且无转向灯注入时启动；
/// - `stop`：立即中断并恢复；
/// - `stats`：active / state / flashesDone / flashesTotal / blockReason。
struct HeadlightStrobeView: View {
    @EnvironmentObject private var environment: AppEnvironment

    private struct Config: Equatable {
        var count: Int
        var intervalMs: Int
        var trigger: Int
    }

    @State private var count = 10
    @State private var intervalMs = 200
    @State private var triggerSource = 0
    @State private var saved = Config(count: 10, intervalMs: 200, trigger: 0)

    @State private var stats: P4JSON?
    @State private var supported = true
    @State private var stalkVariant = "STALK"
    @State private var busy = false
    @State private var confirms = false
    @State private var errorText: String?

    private var active: Bool { stats?["active"]?.boolValue ?? false }
    private var state: String { stats?["state"]?.stringValue ?? "IDLE" }
    private var done: Int { stats?["flashesDone"]?.intValue.map(Int.init) ?? 0 }
    private var total: Int { stats?["flashesTotal"]?.intValue.map(Int.init) ?? count }
    private var blockReason: String? {
        guard let raw = stats?["blockReason"]?.stringValue, !raw.isEmpty else { return nil }
        return raw
    }

    private var dirty: Bool {
        Config(count: count, intervalMs: intervalMs, trigger: triggerSource) != saved
    }

    private var canTrigger: Bool {
        supported && !active && !busy && triggerSource == 0 && !dirty
    }

    var body: some View {
        List {
            Section {
                Label {
                    Text(L10n.t("爆闪会实际控制远光灯。请只在安全环境使用，并确认周围没有对向车辆或行人。",
                                "The strobe actually controls the high beams. Use it only in a safe environment."))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.p4Warn)
                }
                .font(.footnote)
            }

            if !supported {
                Section {
                    Label(L10n.t("当前车型不支持 0x249 拨杆注入（无拨杆版本暂不支持）。",
                                 "This vehicle does not support 0x249 stalk injection."),
                          systemImage: "nosign")
                        .font(.footnote)
                        .foregroundStyle(.p4Warn)
                }
            }

            Section {
                Stepper(value: $count, in: 1...30) {
                    HStack {
                        Text(L10n.t("闪烁次数", "Flashes"))
                        Spacer()
                        Text("\(count)").monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                Stepper(value: $intervalMs, in: 50...1000, step: 10) {
                    HStack {
                        Text(L10n.t("间隔", "Interval"))
                        Spacer()
                        Text("\(intervalMs) ms").monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                Picker(selection: $triggerSource) {
                    Text(L10n.t("App 按钮", "App button")).tag(0)
                    Text(L10n.t("S3XY 按键", "S3XY button")).tag(1)
                } label: {
                    Text(L10n.t("触发入口", "Trigger source"))
                }

                Button {
                    Task { await saveConfig() }
                } label: {
                    Label(L10n.t("保存参数", "Save settings"), systemImage: "checkmark.circle")
                }
                .disabled(busy || !dirty || active)

                Button {
                    resetToSaved()
                } label: {
                    Label(L10n.t("撤销未保存修改", "Revert unsaved changes"), systemImage: "arrow.uturn.backward")
                }
                .disabled(busy || !dirty)
            } header: {
                Label(L10n.t("参数", "Parameters"), systemImage: "slider.horizontal.3")
            } footer: {
                Text(L10n.t("间隔是每一次开/关之间的半周期；总时长 = 次数 × 2 × 间隔。触发入口选 S3XY 后，App 按钮会禁用。",
                            "Interval is the half-period between on/off toggles. Total = count × 2 × interval. The App button is disabled when S3XY is selected."))
            }

            Section {
                Button {
                    confirms = true
                } label: {
                    Label(active ? L10n.t("爆闪进行中…", "Strobe active…")
                                 : L10n.t("立即爆闪", "Flash now"),
                          systemImage: "light.beacon.max.fill")
                }
                .disabled(!canTrigger)

                if active {
                    Button(role: .destructive) {
                        Task { await stop() }
                    } label: {
                        Label(L10n.t("停止并恢复", "Stop and restore"), systemImage: "stop.circle")
                    }
                    .disabled(busy)
                }
            } header: {
                Label(L10n.t("触发", "Trigger"), systemImage: "bolt.fill")
            } footer: {
                if triggerSource == 1 {
                    Text(L10n.t("已选择 S3XY 入口：请到「蓝牙」页把某个按键动作设为「前大灯爆闪」，App 内按钮不可用。",
                                "S3XY is selected. Assign the “Headlight Strobe” action to a button in the Bluetooth tab."))
                } else {
                    Text(L10n.t("触发前需保存参数；爆闪期间不能重复触发，可随时停止。",
                                "Save settings before triggering. Re-trigger is blocked while active; you can stop at any time."))
                }
            }

            statusSection

            if let errorText {
                Section {
                    Label(errorText, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.p4Err)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L10n.t("前大灯爆闪", "Headlight Strobe"))
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) { ToastOverlay() }
        .task { await poll() }
        .confirmationDialog(
            L10n.t("开始远光灯爆闪？", "Start high-beam strobe?"),
            isPresented: $confirms,
            titleVisibility: .visible
        ) {
            Button(L10n.t("开始爆闪", "Start"), role: .destructive) {
                Task { await trigger() }
            }
            Button(L10n.t("取消", "Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t("将闪烁 \(count) 次，间隔 \(intervalMs) ms，结束后恢复触发前的灯光状态。",
                        "\(count) flashes at \(intervalMs) ms, then restore the previous light state."))
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        Section {
            HStack {
                Text(L10n.t("状态", "State"))
                Spacer()
                Text(stateText).foregroundStyle(active ? Color.p4Warn : Color.secondary)
            }
            .font(.subheadline)

            HStack {
                Text(L10n.t("进度", "Progress"))
                Spacer()
                Text("\(done) / \(total)").monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.subheadline)

            if let blockReason {
                Text(reasonText(blockReason))
                    .font(.footnote)
                    .foregroundStyle(.p4Warn)
            }

            if let tx = stats?["txOk"]?.intValue, let fail = stats?["txFail"]?.intValue {
                HStack {
                    Text(L10n.t("发送 / 失败", "TX / fail"))
                    Spacer()
                    Text("\(tx) / \(fail)").monospacedDigit().foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        } header: {
            Label(L10n.t("运行状态", "Runtime"), systemImage: "gauge.with.dots.needle.33percent")
        } footer: {
            Text(L10n.t("0x249 高灯 PULL/IDLE；爆闪期间暂停其他 0x249 注入，结束后自动解除。",
                        "0x249 high-beam PULL/IDLE. Other 0x249 injections are paused while active."))
        }
    }

    private var stateText: String {
        switch state {
        case "ACTIVE": return L10n.t("爆闪中", "Active")
        case "COMPLETE": return L10n.t("已完成", "Complete")
        case "STOPPED": return L10n.t("已停止", "Stopped")
        case "BLOCKED": return L10n.t("已拦截", "Blocked")
        default: return L10n.t("就绪", "Ready")
        }
    }

    private func reasonText(_ raw: String) -> String {
        switch raw {
        case "ALREADY_ACTIVE": return L10n.t("正在爆闪，不能重复触发", "Already active")
        case "NO_STOCK_TEMPLATE": return L10n.t("尚未捕获 0x249 原始帧，请先让车辆上报一次拨杆状态", "No stock 0x249 template captured yet")
        case "STALKLESS_UNSUPPORTED": return L10n.t("当前车型为无拨杆版本，暂不支持", "Stalkless variant is not supported")
        case "TURN_SIGNAL_ACTIVE": return L10n.t("转向灯注入进行中，请稍后再试", "Turn-signal injection is active")
        case "SOURCE_MISMATCH": return L10n.t("触发入口与配置不一致", "Trigger source mismatch")
        case "SEND_FAILED": return L10n.t("CAN 发送失败，已停止并恢复", "CAN send failed; stopped and restored")
        case "USER_STOP": return L10n.t("已手动停止", "Stopped by user")
        case "COMPLETE": return L10n.t("已完成并恢复", "Completed and restored")
        default: return raw
        }
    }

    private func poll() async {
        await loadConfig()
        while !Task.isCancelled {
            if let value = try? await environment.api.get(P4Route.headlightStrobeStats) {
                stats = value
                supported = value.objectValue?["supported"]?.boolValue ?? supported
                stalkVariant = value.objectValue?["stalkVariant"]?.stringValue ?? stalkVariant
            }
            try? await Task.sleep(for: .milliseconds(800))
        }
    }

    private func loadConfig() async {
        guard let value = try? await environment.api.get(P4Route.headlightStrobeConfig),
              let object = value.objectValue else { return }
        if let c = object["count"]?.intValue { count = Int(c) }
        if let i = object["intervalMs"]?.intValue { intervalMs = Int(i) }
        if let t = object["trigger"]?.intValue { triggerSource = Int(t) }
        supported = object["supported"]?.boolValue ?? true
        stalkVariant = object["stalkVariant"]?.stringValue ?? stalkVariant
        saved = Config(count: count, intervalMs: intervalMs, trigger: triggerSource)
        stats = value
    }

    private func resetToSaved() {
        count = saved.count
        intervalMs = saved.intervalMs
        triggerSource = saved.trigger
    }

    private func saveConfig() async {
        guard (1...30).contains(count), (50...1000).contains(intervalMs) else { return }
        busy = true
        errorText = nil
        do {
            let value = try await environment.api.post(P4Route.headlightStrobeConfig, query: [
                P4Param("count", String(count)),
                P4Param("intervalMs", String(intervalMs)),
                P4Param("trigger", String(triggerSource)),
            ])
            stats = value
            saved = Config(count: count, intervalMs: intervalMs, trigger: triggerSource)
            Haptics.success()
            environment.toast = P4Toast(message: L10n.t("爆闪参数已保存", "Strobe settings saved"), style: .success)
        } catch {
            errorText = AppEnvironment.friendly(error)
            Haptics.error()
        }
        busy = false
    }

    private func trigger() async {
        busy = true
        errorText = nil
        do {
            let value = try await environment.api.post(P4Route.headlightStrobeTrigger)
            stats = value
            Haptics.success()
            environment.toast = P4Toast(message: L10n.t("爆闪已开始", "Strobe started"), style: .success)
        } catch {
            errorText = AppEnvironment.friendly(error)
            Haptics.error()
        }
        busy = false
    }

    private func stop() async {
        busy = true
        errorText = nil
        do {
            let value = try await environment.api.post(P4Route.headlightStrobeStop)
            stats = value
            environment.toast = P4Toast(message: L10n.t("已停止并恢复", "Stopped and restored"), style: .info)
        } catch {
            errorText = AppEnvironment.friendly(error)
            Haptics.error()
        }
        busy = false
    }
}
