import SwiftUI

/// 前大灯爆闪：远光灯 PULL/IDLE 交替，结束后恢复触发前的高灯状态。
///
/// 固件契约（`/api/headlight-strobe/*`）：
/// - `config`：count 1–30、intervalMs 50–1000、trigger 0=App / 1=S3XY、
///   `durationMs`（0=按次数，>0 固定总时长 100–30000）、
///   `stopMode`（0=到时自动停 / 1=只能手动停 / 2=两者皆可）、
///   `maxRunMs`（500–60000 安全上限，手动模式的实际运行上限）、holdEnabled 按住拨杆开关；
/// - `trigger`：仅当 trigger 与入口匹配且无转向灯注入时启动；
/// - `stop`：立即中断并恢复；
/// - `stats`：active / state / flashesDone / flashesTotal / elapsedMs / totalMs / mode / blockReason。
struct HeadlightStrobeView: View {
    @EnvironmentObject private var environment: AppEnvironment

    /// 结束方式（App 侧语义，落盘时映射为固件的 `stopMode` + `durationMs`）。
    private enum Ending: Int, CaseIterable, Identifiable {
        case count      // 按次数：跑完 count 次自动停
        case duration   // 按总时长：durationMs 到点自动停
        case manual     // 手动停止：一直闪，直到手动停或到 maxRunMs

        var id: Int { rawValue }
    }

    private struct Config: Equatable {
        var count: Int
        var intervalMs: Int
        var trigger: Int
        var hold: Bool
        var durationMs: Int
        var stopMode: Int
        var maxRunMs: Int
    }

    @State private var count = 10
    @State private var intervalMs = 100
    @State private var triggerSource = 0
    @State private var holdEnabled = false
    @State private var holdDelayMs = 2500
    @State private var ending: Ending = .count
    @State private var durationSec = 5
    @State private var maxRunSec = 30
    @State private var saved = Config(count: 10, intervalMs: 100, trigger: 0, hold: false,
                                      durationMs: 0, stopMode: 0, maxRunMs: 30_000)

    /// 运行状态放在共享端点缓存里：功能列表、本页、诊断包读的是同一份。
    private var stats: P4JSON? { environment.endpointValue(P4Route.headlightStrobeStats) }
    @State private var supported = true
    @State private var stalkVariant = "STALK"
    @State private var busy = false
    /// 保存成功后的短暂「已保存」态：确认出现在手指位置，而不是被标签栏挡住的行里。
    @State private var justSaved = false
    @State private var confirms = false
    /// 触发按钮的相位（SwiftPieces CommitButton）：空闲 / 进行中 / 成功 / 失败 / 不可用。
    @State private var commitPhase: CommitButton.Phase = .idle
    @State private var errorText: String?

    private var active: Bool { stats?["active"]?.boolValue ?? false }
    private var state: String { stats?["state"]?.stringValue ?? "IDLE" }
    private var done: Int { stats?["flashesDone"]?.intValue.map(Int.init) ?? 0 }
    private var total: Int { stats?["flashesTotal"]?.intValue.map(Int.init) ?? count }
    private var blockReason: String? {
        guard let raw = stats?["blockReason"]?.stringValue, !raw.isEmpty else { return nil }
        return raw
    }

    private var effectiveDurationMs: Int {
        ending == .duration ? durationSec * 1000 : 0
    }

    private var effectiveStopMode: Int {
        ending == .manual ? 1 : 0
    }

    private var effectiveMaxRunMs: Int { maxRunSec * 1000 }

    private var drafted: Config {
        Config(count: count, intervalMs: intervalMs, trigger: triggerSource, hold: holdEnabled,
               durationMs: effectiveDurationMs, stopMode: effectiveStopMode, maxRunMs: effectiveMaxRunMs)
    }

    private var dirty: Bool { drafted != saved }

    /// 按钮下方的提醒：优先说明为什么点不了，其次说明操作限制。
    private var triggerHintText: String {
        if triggerSource == 1 {
            return L10n.t("触发入口已设为 S3XY 按键，请到「蓝牙」页配置；App 内按钮不可用。",
                          "Trigger source is the S3XY button — configure it in the Bluetooth tab.")
        }
        if dirty {
            return L10n.t("参数有未保存修改，保存后才能触发。", "Save parameter changes before flashing.")
        }
        if ending == .manual {
            return L10n.t("将持续爆闪，最长 \(maxRunSec) s，需要手动停止。",
                          "Flashes continuously for up to \(maxRunSec) s until you stop it.")
        }
        return L10n.t("参数改动需先保存；爆闪期间不能重复触发，可随时停止。",
                      "Save changes first. Re-trigger is blocked while active; you can stop at any time.")
    }

    private var holdDelayText: String {
        String(format: "%.1f s", Double(holdDelayMs) / 1000)
    }

    private var totalDurationText: String {
        switch ending {
        case .count:
            let seconds = Double(count * 2 * intervalMs) / 1000
            return String(format: "%.1f s", seconds)
        case .duration:
            return String(format: "%.1f s", Double(durationSec))
        case .manual:
            return L10n.t("最长 \(maxRunSec) s（需手动停止）", "up to \(maxRunSec) s (manual stop)")
        }
    }

    private var intervalStepText: String { "10" }

    private var saveDisabled: Bool { busy || !dirty || active }

    private var revertDisabled: Bool { busy || !dirty }

    /// 撤销按钮的弹性样式：中性玻璃底 + 主文字色，弱于主操作但仍是可点实体；
    /// 尺寸与保存按钮完全一致（50pt / 12pt 圆角 / 同内边距），保证两行边缘对齐。
    private var revertButtonStyle: ElasticButton.Style {
        ElasticButton.Style(
            fill: Color(uiColor: .secondarySystemFill),
            ink: .primary,
            radius: Theme.Radius.button,
            height: 50,
            padding: 20,
            depth: false
        )
    }

    /// 保存按钮的弹性样式：沿用主操作蓝（白字）、12pt 连续圆角、50pt 高。
    /// 禁用时组件自动改为透明玻璃 + 弱化文字，不必再叠一层 opacity。
    private var saveButtonStyle: ElasticButton.Style {
        ElasticButton.Style(
            fill: Color.p4Accent,
            ink: .white,
            radius: Theme.Radius.button,
            height: 50,
            padding: 20,
            depth: true
        )
    }

    /// CommitButton 的玻璃色板：沿用 App 的系统语义色
    /// （蓝=主操作、绿=完成、红=失败），尺寸与其它紧凑按钮一致（44pt）。
    private var commitStyle: CommitButton.Style {
        CommitButton.Style(
            fill: .p4Accent,
            ink: .white,
            successFill: .p4OK,
            errorFill: .p4Err,
            disabledFill: Color(uiColor: .tertiarySystemFill),
            disabledInk: Color(uiColor: .secondaryLabel),
            height: 50,
            font: .subheadline.weight(.semibold)
        )
    }

    /// 触发条件变化时同步「可用 / 不可用」；
    /// loading 与 success 由动作自己驱动，这里不覆盖。
    private func syncCommitPhase() {
        switch commitPhase {
        case .idle:
            if !canTrigger { commitPhase = .disabled }
        case .disabled, .error:
            if canTrigger { commitPhase = .idle }
        case .loading, .success:
            break
        }
    }

    private var canTrigger: Bool {
        supported && !active && !busy && triggerSource == 0 && !dirty
    }

    var body: some View {
        ScrollViewReader { proxy in
        List {
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
                // 固件在爆闪进行中对任何 config POST 都回 409，开关此时必然写失败：
                // 先禁用并说明，避免「点了开关又被弹回去」。
                .disabled(active || busy)
            } footer: {
                Text(active
                     ? L10n.t("爆闪进行中，先点「停止并恢复」才能改这个开关。",
                              "Stop the strobe before changing this switch.")
                     : L10n.t("开关立即写入设备，无需保存。",
                              "The switch is written to the device immediately; no save needed."))
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
                // 第一屏就是可操作区：状态一行 + 触发按钮 + 按钮下方的提醒。
                HStack(spacing: Theme.spacing(1)) {
                    Text(L10n.t("状态", "State"))
                        .font(.subheadline)
                    Spacer(minLength: Theme.spacing(1))
                    Text(stateText)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(active ? Color.p4Warn : Color.secondary)
                }

                VStack(spacing: 8) {
                    // 触发按钮用 SwiftPieces 的 CommitButton：同一颗按钮承载
                    // 空闲 / 加载 / 成功 / 失败（可重试）四态，失败时胶囊变红并带重试气泡。
                    CommitButton(
                        active ? L10n.t("爆闪进行中…", "Strobe active…")
                               : L10n.t("立即爆闪", "Flash now"),
                        phase: $commitPhase,
                        successTitle: L10n.t("已开始", "Started"),
                        style: commitStyle
                    ) {
                        confirms = true
                    }
                    // 与下方「保存参数」同宽同高（整行、50pt），两处主操作对齐。
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
                                }
                                Text(L10n.t("停止并恢复", "Stop and restore"))
                            }
                        }
                        .buttonStyle(.dsDestructive)
                        .disabled(busy)
                        .accessibilityLabel(L10n.t("停止爆闪并恢复灯光", "Stop the strobe and restore lights"))
                    }

                    // 提醒紧跟按钮，不再作为整段 footer 漂在卡片外。
                    Text(triggerHintText)
                        .font(.caption)
                        .foregroundStyle(dirty ? Color.p4Warn : Color.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }
                .frame(maxWidth: .infinity)
            } header: {
                Label(L10n.t("触发", "Trigger"), systemImage: "bolt.fill")
            }

            statusSection

            Section {
                Picker(selection: $ending) {
                    Text(L10n.t("按次数", "By count")).tag(Ending.count)
                    Text(L10n.t("按总时长", "By duration")).tag(Ending.duration)
                    Text(L10n.t("手动停止", "Until stopped")).tag(Ending.manual)
                } label: {
                    Label(L10n.t("结束方式", "Ending"), systemImage: "timer")
                }
                .pickerStyle(.segmented)

                switch ending {
                case .count:
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
                case .duration:
                    RulerSlider(
                        title: L10n.t("总时长", "Duration"),
                        unit: "s",
                        value: $durationSec,
                        range: 1...30,
                        step: 1,
                        majorEvery: 5,
                        caption: L10n.t("到点自动停止；次数按间隔自动排满这段时间。",
                                         "Stops automatically; the flashes fill this window.")
                    )
                case .manual:
                    RulerSlider(
                        title: L10n.t("安全上限", "Max run"),
                        unit: "s",
                        value: $maxRunSec,
                        range: 5...60,
                        step: 5,
                        majorEvery: 4,
                        caption: L10n.t("一直闪到手动停止；到达上限也会强制停止并恢复。",
                                         "Runs until stopped; the cap force-stops and restores.")
                    )
                }

                RulerSlider(
                    title: L10n.t("间隔", "Interval"),
                    unit: "ms",
                    value: $intervalMs,
                    range: 50...1000,
                    step: 10,
                    majorEvery: 5,
                    caption: L10n.t("开/关之间的半周期，随「保存参数」一起写入设备。",
                                     "Half-period between on/off, written with Save settings.")
                )
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
                Text(ending == .count
                     ? L10n.t("刻度按 \(intervalStepText) ms 吸附；参数改动需保存后才会用于下一次触发。",
                              "The ruler snaps every \(intervalStepText) ms. Save changes before the next run.")
                     : L10n.t("时长按 1 s、安全上限按 5 s 吸附；参数改动需保存后才会用于下一次触发。",
                              "Snaps to 1 s for duration and 5 s for the cap. Save before the next run."))
            }
            .id("params")

            Section {
                // 每个按钮独占一行：List 行内放多个按钮时，行级手势会吞掉点击
                // （表现为「按下去没有动画、也没有反应」）。分行的同时保持同宽同高，
                // 用 listRowSeparator(.hidden) 去掉中间那条分隔线。
                Button {
                    Task { await saveConfig() }
                } label: {
                    HStack(spacing: 8) {
                        if busy {
                            ProgressView().controlSize(.small).tint(.white)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                        }
                        Text(justSaved ? L10n.t("已保存", "Saved")
                                       : L10n.t("保存参数", "Save settings"))
                    }
                    .frame(maxWidth: .infinity)
                }
                // SwiftPieces ElasticButton：按下向触点挤压缩放、拖拽有橡皮筋阻力，
                // 抬起带一点回弹；表面是同款液体玻璃，与上方触发按钮同一套材质语言。
                .buttonStyle(.elastic(saveButtonStyle))
                .disabled(saveDisabled)
                .listRowSeparator(.hidden)
                // 玻璃材质会把底衬冲淡（实测红色只剩约 1/4），所以禁用感靠整体降低不透明度，
                // 不再垫灰底。启用时是实心蓝玻璃，两种状态区分依然明显。
                .opacity(saveDisabled ? 0.7 : 1)
                .accessibilityHint(L10n.t("保存闪烁次数、间隔与触发入口",
                                          "Saves flashes, interval and trigger source"))

                Button {
                    resetToSaved()
                } label: {
                    Text(L10n.t("撤销未保存修改", "Revert unsaved changes"))
                        .frame(maxWidth: .infinity)
                }
                // 同为 ElasticButton，中性玻璃底，尺寸与保存按钮完全一致。
                .buttonStyle(.elastic(revertButtonStyle))
                .disabled(revertDisabled)
                .opacity(revertDisabled ? 0.7 : 1)

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
        .onAppear { syncCommitPhase() }
        .onChange(of: canTrigger) { _, _ in syncCommitPhase() }
        .onChange(of: commitPhase) { _, _ in syncCommitPhase() }
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
            Text(confirmMessage)
        }
        }
    }

    private var confirmMessage: String {
        switch ending {
        case .count:
            return L10n.t("将闪烁 \(count) 次，间隔 \(intervalMs) ms，结束后恢复触发前的灯光状态。",
                          "\(count) flashes at \(intervalMs) ms, then restore the previous light state.")
        case .duration:
            return L10n.t("将在 \(durationSec) s 内按 \(intervalMs) ms 间隔闪烁，到点自动停止并恢复。",
                          "Flashes for \(durationSec) s at \(intervalMs) ms, then stops and restores.")
        case .manual:
            return L10n.t("将持续闪烁，最长 \(maxRunSec) s；需要手动点「停止并恢复」。",
                          "Flashes until you stop it, capped at \(maxRunSec) s.")
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        Section {
            HStack {
                Text(L10n.t("结束方式", "Ending"))
                Spacer()
                Text(runModeText).foregroundStyle(.secondary)
            }
            .font(.subheadline)

            HStack {
                Text(L10n.t("进度", "Progress"))
                Spacer()
                Text(progressText).monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.subheadline)

            if let age = environment.endpointAge(P4Route.headlightStrobeStats) {
                HStack {
                    Text(L10n.t("数据", "Data"))
                    Spacer()
                    Text(freshnessText(age))
                        .monospacedDigit()
                        .foregroundStyle(age > 5 ? Color.p4Warn : Color.secondary)
                }
                .font(.caption)
            }

            HStack {
                Text(L10n.t("长按触发", "Hold delay"))
                Spacer()
                Text(String(format: "%.1f s", Double(holdDelayMs) / 1000))
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.subheadline)

            if let blockReason {
                // 颜色只表语义：完成=绿、手动停止=次要、可继续的拦截=橙、真失败=红。
                Text(reasonText(blockReason))
                    .font(.footnote)
                    .foregroundStyle(reasonTone(blockReason))
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

    private var runModeText: String {
        switch stats?["mode"]?.stringValue {
        case "MANUAL": return L10n.t("手动停止", "Until stopped")
        case "DURATION": return L10n.t("按总时长", "By duration")
        case "COUNT": return L10n.t("按次数", "By count")
        default: return "—"
        }
    }

    /// COUNT 模式看「第几次」，其余模式看「已运行 / 总时长」。
    private var progressText: String {
        guard stats?["mode"]?.stringValue != "COUNT" else { return "\(done) / \(total)" }
        let totalMs = Int(stats?["totalMs"]?.intValue ?? 0)
        guard totalMs > 0 else { return "\(done) / \(total)" }
        let elapsed = Int(stats?["elapsedMs"]?.intValue ?? 0)
        return String(format: "%.1f / %.1f s", Double(elapsed) / 1000, Double(totalMs) / 1000)
    }

    private func freshnessText(_ age: TimeInterval) -> String {
        if age < 2 { return L10n.t("刚刚", "now") }
        if age < 60 { return L10n.t("\(Int(age)) s 前", "\(Int(age)) s ago") }
        return L10n.t("\(Int(age / 60)) 分钟前", "\(Int(age / 60)) min ago")
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

    private func reasonTone(_ raw: String) -> Color {
        switch raw {
        case "COMPLETE": return .p4OK
        case "USER_STOP": return .secondary
        case "ALREADY_ACTIVE", "TURN_SIGNAL_ACTIVE", "NO_STOCK_TEMPLATE",
             "STALKLESS_UNSUPPORTED", "SOURCE_MISMATCH":
            return .p4Warn
        case "SEND_FAILED", "CAN_EPOCH_CHANGED":
            return .p4Err
        default:
            return .secondary
        }
    }

    private func poll() async {
        await loadConfig()
        while !Task.isCancelled {
            if let value = await environment.refreshEndpoint(P4Route.headlightStrobeStats) {
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
            // 结束方式由固件的 stopMode + durationMs 共同决定（mode 字段是二者的合成结果）。
            let stopMode = Int(object["stopMode"]?.intValue ?? 0)
            let durationMs = Int(object["durationMs"]?.intValue ?? 0)
            let maxRunMs = Int(object["maxRunMs"]?.intValue ?? 30_000)
            ending = stopMode == 1 ? .manual : (durationMs > 0 ? .duration : .count)
            durationSec = min(max(Int((Double(durationMs) / 1000).rounded()), 1), 30)
            maxRunSec = min(max(Int((Double(maxRunMs) / 1000).rounded()), 5), 60)
            supported = object["supported"]?.boolValue ?? true
            stalkVariant = object["stalkVariant"]?.stringValue ?? stalkVariant
            // 存盘值按 UI 粒度归一：设备里可能有 1500 ms 这类非整秒值，
            // 若原样当基线，一进页面就会显示「有未保存修改」。
            saved = Config(count: count, intervalMs: intervalMs, trigger: triggerSource,
                           hold: holdEnabled,
                           durationMs: ending == .duration ? durationSec * 1000 : 0,
                           stopMode: stopMode == 1 ? 1 : 0,
                           maxRunMs: maxRunSec * 1000)
            environment.storeEndpoint(P4Route.headlightStrobeStats, value)
            errorText = nil
        } catch {
            // 有缓存就先用缓存渲染：一次 config 读失败不等于「车型不支持」。
            if let cached = stats?.objectValue {
                supported = cached["supported"]?.boolValue ?? supported
                stalkVariant = cached["stalkVariant"]?.stringValue ?? stalkVariant
                errorText = L10n.t("参数读取失败，显示上一次的值：\(AppEnvironment.friendly(error))",
                                   "Could not read settings; showing the last values: \(AppEnvironment.friendly(error))")
            } else {
                supported = false
                errorText = L10n.t("固件没有提供爆闪接口（需集成 headlight_strobe 补丁）：\(AppEnvironment.friendly(error))",
                                   "Firmware does not expose the strobe API (headlight_strobe patch required): \(AppEnvironment.friendly(error))")
            }
        }
    }

    private func resetToSaved() {
        guard dirty else { return }
        count = saved.count
        intervalMs = saved.intervalMs
        triggerSource = saved.trigger
        holdEnabled = saved.hold
        ending = saved.stopMode == 1 ? .manual : (saved.durationMs > 0 ? .duration : .count)
        durationSec = min(max(saved.durationMs / 1000, 1), 30)
        maxRunSec = min(max(saved.maxRunMs / 1000, 5), 60)
        Haptics.impact()
    }

    private func saveConfig() async {
        guard (1...30).contains(count), (50...1000).contains(intervalMs),
              (1...30).contains(durationSec), (5...60).contains(maxRunSec) else { return }
        busy = true
        errorText = nil
        do {
            let value = try await environment.api.post(P4Route.headlightStrobeConfig, query: [
                P4Param("count", String(count)),
                P4Param("intervalMs", String(intervalMs)),
                P4Param("trigger", String(triggerSource)),
                P4Param("holdEnabled", holdEnabled ? "1" : "0"),
                P4Param("durationMs", String(effectiveDurationMs)),
                P4Param("stopMode", String(effectiveStopMode)),
                P4Param("maxRunMs", String(effectiveMaxRunMs)),
            ])
            environment.storeEndpoint(P4Route.headlightStrobeStats, value)
            saved = drafted
            Haptics.success()
            withAnimation(.spring(response: 0.28, dampingFraction: 1.0)) { justSaved = true }
            Task {
                try? await Task.sleep(for: .milliseconds(2500))
                withAnimation(.easeOut(duration: 0.2)) { justSaved = false }
            }
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
            environment.storeEndpoint(P4Route.headlightStrobeStats, value)
            saved = Config(count: saved.count, intervalMs: saved.intervalMs,
                           trigger: saved.trigger, hold: on,
                           durationMs: saved.durationMs, stopMode: saved.stopMode,
                           maxRunMs: saved.maxRunMs)
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

    private func trigger() async {
        busy = true
        errorText = nil
        commitPhase = .loading
        do {
            let value = try await environment.api.post(P4Route.headlightStrobeTrigger)
            environment.storeEndpoint(P4Route.headlightStrobeStats, value)
            // 成功/失败的触感由 CommitButton 自己播放，这里不再重复触发。
            commitPhase = .success
            environment.toast = P4Toast(message: L10n.t("爆闪已开始", "Strobe started"), style: .success)
        } catch {
            let message = AppEnvironment.friendly(error)
            errorText = message
            // 409 是「设备当前状态不允许」，立刻重试只会再撞一次；引导稍后再试。
            let retryable = (error as? P4APIError)?.status != 409
            commitPhase = .error(retryable
                                 ? L10n.t("失败 · 点按重试", "Failed · tap to retry")
                                 : L10n.t("未开始 · 稍后重试", "Not started · retry later"))
        }
        busy = false
    }

    private func stop() async {
        busy = true
        errorText = nil
        do {
            let value = try await environment.api.post(P4Route.headlightStrobeStop)
            environment.storeEndpoint(P4Route.headlightStrobeStats, value)
            environment.toast = P4Toast(message: L10n.t("已停止并恢复", "Stopped and restored"), style: .info)
        } catch {
            errorText = AppEnvironment.friendly(error)
            Haptics.error()
        }
        busy = false
    }
}
