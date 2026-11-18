import SwiftUI

/// 前大灯爆闪：远光灯 PULL/IDLE 交替 `count` 次，结束后恢复触发前的高灯状态。
///
/// 固件契约（`/api/headlight-strobe/*`）：
/// - `config`：count 1–30、intervalMs 50–1000、trigger 0=App / 1=S3XY、holdEnabled 按住拨杆开关；
/// - `trigger`：仅当 trigger 与入口匹配且无转向灯注入时启动；
/// - `stop`：立即中断并恢复；
/// - `stats`：active / state / flashesDone / flashesTotal / blockReason。
struct HeadlightStrobeView: View {
    @EnvironmentObject private var environment: AppEnvironment

    private struct Config: Equatable {
        var count: Int
        var intervalMs: Int
        var trigger: Int
        var hold: Bool
    }

    @State private var count = 10
    @State private var intervalMs = 100
    @State private var triggerSource = 0
    @State private var holdEnabled = false
    @State private var holdDelayMs = 2500
    @State private var saved = Config(count: 10, intervalMs: 100, trigger: 0, hold: false)

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
        Config(count: count, intervalMs: intervalMs, trigger: triggerSource, hold: holdEnabled) != saved
    }

    private var holdDelayText: String {
        String(format: "%.1f s", Double(holdDelayMs) / 1000)
    }

    private var totalDurationText: String {
        let seconds = Double(count * 2 * intervalMs) / 1000
        return String(format: "%.1f s", seconds)
    }

    private var intervalStepText: String { "10" }

    private var canTrigger: Bool {
        supported && !active && !busy && triggerSource == 0 && !dirty
    }

    var body: some View {
        ScrollViewReader { proxy in
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
                // 第一屏就是可操作区：状态一行 + 触发按钮，参数统一挪到下方。
                HStack(spacing: Theme.spacing(1)) {
                    Text(L10n.t("状态", "State"))
                        .font(.subheadline)
                    Spacer(minLength: Theme.spacing(1))
                    Text(stateText)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(active ? Color.p4Warn : Color.secondary)
                }
                if dirty {
                    Label(L10n.t("参数有未保存修改，保存后才能触发",
                                 "Unsaved parameter changes — save before flashing"),
                          systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.p4Warn)
                }

                Button {
                    confirms = true
                } label: {
                    HStack(spacing: 8) {
                        if busy {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        } else {
                            Image(systemName: "light.beacon.max.fill")
                                .font(.body.weight(.semibold))
                        }
                        Text(active ? L10n.t("爆闪进行中…", "Strobe active…")
                                    : L10n.t("立即爆闪", "Flash now"))
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(active ? Color.p4Warn : Color.accentColor)
                .disabled(!canTrigger)
                .accessibilityLabel(L10n.t("立即开始前大灯爆闪", "Start headlight strobe now"))
                .accessibilityHint(L10n.t("会实际控制远光灯，需确认后执行",
                                          "Controls the real high beams; asks for confirmation"))

                if active {
                    Button(role: .destructive) {
                        Task { await stop() }
                    } label: {
                        HStack(spacing: 8) {
                            if busy {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "stop.circle.fill")
                                    .font(.body.weight(.semibold))
                            }
                            Text(L10n.t("停止并恢复", "Stop and restore"))
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.p4Err)
                    .disabled(busy)
                    .accessibilityLabel(L10n.t("停止爆闪并恢复灯光", "Stop the strobe and restore lights"))
                }
            } header: {
                Label(L10n.t("触发", "Trigger"), systemImage: "bolt.fill")
            } footer: {
                if triggerSource == 1 {
                    Text(L10n.t("已选择 S3XY 入口：请到「蓝牙」页把某个按键动作设为「前大灯爆闪」，App 内按钮不可用。",
                                "S3XY is selected. Assign the “Headlight Strobe” action to a button in the Bluetooth tab."))
                } else {
                    Text(L10n.t("参数改动需先保存；爆闪期间不能重复触发，可随时停止。参数在下方。",
                                "Save parameter changes first. Re-trigger is blocked while active; parameters are below."))
                }
            }

            statusSection

            Section {
                Toggle(isOn: Binding(
                    get: { holdEnabled },
                    set: { on in
                        holdEnabled = on
                        Haptics.impact()
                        Task { await applyHold(on) }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("按住拨杆爆闪", "Hold-stalk strobe"))
                        Text(L10n.t("拉住远光拨杆 \(holdDelayText) 后开始爆闪，松开即停",
                                    "Hold the stalk for \(holdDelayText) to start; release to stop"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.accentColor)
            } header: {
                Label(L10n.t("按住拨杆", "Hold to strobe"), systemImage: "hand.point.up.left")
            } footer: {
                Text(L10n.t("开关立即写入设备，无需保存。",
                            "The switch is written to the device immediately; no save needed."))
            }

            Section {
                RulerSlider(
                    title: L10n.t("闪烁次数", "Flashes"),
                    unit: L10n.t("次", "×"),
                    value: $count,
                    range: 1...30,
                    step: 1,
                    majorEvery: 5,
                    caption: L10n.t("总时长 = 次数 × 2 × 间隔 = \(totalDurationText)",
                                     "Duration = count × 2 × interval = \(totalDurationText)")
                )

                RulerSlider(
                    title: L10n.t("间隔", "Interval"),
                    unit: "ms",
                    value: $intervalMs,
                    range: 50...500,
                    step: 10,
                    majorEvery: 5,
                    caption: L10n.t("开/关之间的半周期，立即写入设备，同时作用于按住拨杆触发。",
                                     "Half-period between on/off. Applied immediately and shared with hold-to-strobe.")
                )
                .onChange(of: intervalMs) { _, newValue in
                    Task { await applyInterval(newValue) }
                }

                Picker(selection: $triggerSource) {
                    Text(L10n.t("App 按钮", "App button")).tag(0)
                    Text(L10n.t("S3XY 按键", "S3XY button")).tag(1)
                } label: {
                    Label(L10n.t("触发入口", "Trigger source"), systemImage: "switch.2")
                }
                .pickerStyle(.segmented)
            } header: {
                Label(L10n.t("参数", "Parameters"), systemImage: "slider.horizontal.3")
            } footer: {
                Text(L10n.t("刻度按 \(intervalStepText) ms 吸附；参数改动需保存后才会用于下一次触发。",
                            "The ruler snaps every \(intervalStepText) ms. Save changes before the next run."))
            }
            .id("params")

            Section {
                Button {
                    Task { await saveConfig() }
                } label: {
                    HStack(spacing: 8) {
                        if busy {
                            ProgressView().controlSize(.small).tint(.white)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.body.weight(.semibold))
                        }
                        Text(L10n.t("保存参数", "Save settings"))
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy || !dirty || active)
                .accessibilityHint(L10n.t("保存次数与触发入口；间隔会即时生效",
                                          "Saves count and trigger source; interval applies immediately"))

                Button {
                    resetToSaved()
                } label: {
                    Text(L10n.t("撤销未保存修改", "Revert unsaved changes"))
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(busy || !dirty)
            }

            if let errorText {
                Section {
                    Label(errorText, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.p4Err)
                }
            }
        }
        .listStyle(.insetGrouped)
        #if DEBUG
        // 本地联调：SIMCTL_CHILD_P4CAN_SCROLL_TO=params 启动后直接滚到参数区
        .task {
            guard ProcessInfo.processInfo.environment["P4CAN_SCROLL_TO"] == "params" else { return }
            try? await Task.sleep(for: .milliseconds(600))
            withAnimation { proxy.scrollTo("params", anchor: .top) }
        }
        #endif
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
    }

    @ViewBuilder
    private var statusSection: some View {
        Section {
            HStack {
                Text(L10n.t("进度", "Progress"))
                Spacer()
                Text("\(done) / \(total)").monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.subheadline)

            HStack {
                Text(L10n.t("长按触发", "Hold delay"))
                Spacer()
                Text(String(format: "%.1f s", Double(holdDelayMs) / 1000))
                    .monospacedDigit().foregroundStyle(.secondary)
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
        case "CAN_EPOCH_CHANGED": return L10n.t("CAN 总线已恢复/重启，爆闪已停止", "CAN bus epoch changed; strobe stopped")
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
        do {
            let value = try await environment.api.get(P4Route.headlightStrobeConfig)
            guard let object = value.objectValue else {
                throw P4APIError(message: L10n.t("固件返回了无效配置", "Invalid config response"))
            }
            if let c = object["count"]?.intValue { count = Int(c) }
            if let i = object["intervalMs"]?.intValue { intervalMs = Int(i) }
            if let t = object["trigger"]?.intValue { triggerSource = Int(t) }
            holdEnabled = object["holdEnabled"]?.boolValue ?? false
            if let d = object["holdDelayMs"]?.intValue { holdDelayMs = Int(d) }
            supported = object["supported"]?.boolValue ?? true
            stalkVariant = object["stalkVariant"]?.stringValue ?? stalkVariant
            saved = Config(count: count, intervalMs: intervalMs, trigger: triggerSource, hold: holdEnabled)
            stats = value
            errorText = nil
        } catch {
            supported = false
            errorText = L10n.t("固件没有提供爆闪接口（需集成 headlight_strobe 补丁）：\(AppEnvironment.friendly(error))",
                               "Firmware does not expose the strobe API (headlight_strobe patch required): \(AppEnvironment.friendly(error))")
        }
    }

    private func resetToSaved() {
        count = saved.count
        intervalMs = saved.intervalMs
        triggerSource = saved.trigger
        holdEnabled = saved.hold
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
                P4Param("holdEnabled", holdEnabled ? "1" : "0"),
            ])
            stats = value
            saved = Config(count: count, intervalMs: intervalMs, trigger: triggerSource, hold: holdEnabled)
            Haptics.success()
            environment.toast = P4Toast(message: L10n.t("爆闪参数已保存", "Strobe settings saved"), style: .success)
        } catch {
            errorText = AppEnvironment.friendly(error)
            Haptics.error()
        }
        busy = false
    }

    /// 开关即时写入：失败则回滚 UI 状态。
    private func applyHold(_ on: Bool) async {
        do {
            let value = try await environment.api.post(P4Route.headlightStrobeConfig, query: [
                P4Param("holdEnabled", on ? "1" : "0"),
            ])
            stats = value
            saved = Config(count: saved.count, intervalMs: saved.intervalMs,
                           trigger: saved.trigger, hold: on)
            environment.toast = P4Toast(
                message: on ? L10n.t("按住拨杆爆闪已开启", "Hold-stalk strobe on")
                            : L10n.t("按住拨杆爆闪已关闭", "Hold-stalk strobe off"),
                style: .info
            )
        } catch {
            holdEnabled = !on
            errorText = AppEnvironment.friendly(error)
            Haptics.error()
        }
    }

    /// 间隔即时写入：连续拖动时只提交最后一次。
    private func applyInterval(_ value: Int) async {
        let clamped = min(max(value, 50), 500)
        try? await Task.sleep(for: .milliseconds(350))
        guard clamped == intervalMs else { return }
        do {
            let json = try await environment.api.post(P4Route.headlightStrobeConfig, query: [
                P4Param("intervalMs", String(clamped)),
            ])
            stats = json
            saved = Config(count: saved.count, intervalMs: clamped,
                           trigger: saved.trigger, hold: saved.hold)
        } catch {
            errorText = AppEnvironment.friendly(error)
        }
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
