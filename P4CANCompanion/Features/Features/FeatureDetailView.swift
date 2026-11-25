import SwiftUI

/// 功能模块详情页：控件（开关/选择/滑杆/成对数值/按钮）+ 实时状态键值表 + 原始数据。
///
/// 与固件契约：所有写操作是 `POST path?key=value`；部分接口要求同时提交兄弟参数，
/// 由 `FeatureControl.Kind` 的 `extra` 声明，值取自当前 stats。
struct FeatureDetailView: View {
    @EnvironmentObject private var environment: AppEnvironment

    let module: FeatureModule

    /// 端点数据统一放在 `AppEnvironment`：本页只读，不再自己存一份。
    private var stats: P4JSON? { environment.endpointValue(module.statsPath) }
    private var loadFailed: String? { environment.endpointError(module.statsPath) }
    @State private var numberValues: [String: Double] = [:]
    @State private var selectedOptions: [String: String] = [:]
    @State private var pendingTrigger: FeatureControl?
    /// 乐观开关值：点下立即生效，避免「请求未回 → 开关弹回」的错觉。
    @State private var optimisticToggles: [String: Bool] = [:]
    /// 正在拖动的滑杆（拖动期间不回写设备值，避免手指被覆盖）。
    @State private var sliderEditing: Set<String> = []
    /// 已发出写请求、尚未完成回读的控件：1.2 s 轮询不能在这期间把值改回旧值，
    /// 否则会出现「刚拖完又跳回去」或「选择器闪回」。
    @State private var pendingWrites: Set<String> = []
    /// 成对数值改过、但还没点「同时提交」：这期间不能被轮询覆盖，否则拖完就白拖。
    @State private var editedPairs: Set<String> = []
    @State private var showsRawData = false
    @State private var showsAdvanced = false
    @State private var showsResearchLabels = false
    @State private var showsHeadlightStrobe = false
    @State private var showsRearFog = false

    private let pollInterval: Duration = .milliseconds(1200)

    /// 车型能力位是否支持该模块（无声明视为支持）。
    private var capabilitySupported: Bool {
        // vision / window 用通用键 "supported"，但 features/status 没有这个键，
        // 真正的支持位在模块自己的 stats 里；否则缺省会被当成「支持」。
        if module.supportKey == "supported" {
            guard let stats else { return false }
            return stats["supported"]?.boolValue ?? true
        }
        guard let key = module.supportKey else { return true }
        return environment.capability(key) != false
    }

    /// 允许写入：能力支持 + 非 Setup 模式 + 捕获类模块没在录制/导出。
    /// 实验室工具已并入「功能」，不再依赖 LAB Menu 总开关。
    private var canWrite: Bool {
        guard capabilitySupported, !environment.isSetupMode else { return false }
        if captureBusy { return false }
        return true
    }

    // MARK: - 捕获类模块（研究捕获 / DMS 捕获）

    private var isCaptureModule: Bool { module.id == "research" || module.id == "dmscapture" }

    private var captureObject: [String: P4JSON]? {
        isCaptureModule ? stats?.objectValue : nil
    }

    /// 录制或导出进行中：固件对这些接口一律回 409，先在 UI 层拦住。
    private var captureBusy: Bool {
        guard let object = captureObject else { return false }
        return object["capturing"]?.boolValue == true || object["exporting"]?.boolValue == true
    }

    private var captureStateText: String {
        switch captureObject?["state"]?.stringValue {
        case "CAPTURING": return L10n.t("录制中", "Capturing")
        case "PAUSED": return L10n.t("已暂停", "Paused")
        case "FULL": return L10n.t("缓冲区已满", "Buffer full")
        case "ERROR": return L10n.t("初始化失败", "Init failed")
        case "READY": return L10n.t("就绪", "Ready")
        default: return "—"
        }
    }

    var body: some View {
        List {
            Section {
                heroHeader
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            if !capabilitySupported {
                Section {
                    Label(L10n.t("当前车型/拓扑不支持该功能（固件能力位为否）。",
                             "This vehicle or topology does not support the feature (capability bit is off)."),
                          systemImage: "nosign")
                        .font(.footnote)
                        .foregroundStyle(.p4Warn)
                }
            } else if environment.isSetupMode {
                Section {
                    Label(L10n.t("设备处于 Setup 模式，CAN 注入与功能写入已禁用。",
                             "The device is in setup mode; CAN injection and writes are disabled."),
                          systemImage: "gear.badge.questionmark")
                        .font(.footnote)
                        .foregroundStyle(.p4Warn)
                }
            }

            if !module.controls.isEmpty {
                Section(L10n.t("控制", "Controls")) {
                    ForEach(module.controls.filter(isControlAvailable)) { control in
                        controlRow(control)
                    }
                }
            }

            captureSection

            if module.id == "headlight" {
                Section {
                    NavigationLink {
                        HeadlightStrobeView()
                    } label: {
                        NavRow(icon: "slider.horizontal.3",
                               title: L10n.t("爆闪设置与触发", "Strobe settings and trigger"),
                               subtitle: L10n.t("次数 / 时长 / 手动停止 / 触发入口",
                                                "Count / duration / manual stop / trigger"),
                               tint: P4Palette.orange)
                    }
                } footer: {
                    Text(L10n.t("爆闪会实际控制远光灯；请只在安全环境使用，并确认周围没有对向车辆。",
                                "The strobe actually controls the high beams. Use it only in a safe environment."))
                }
            }

            if module.id == "rearFog" {
                Section {
                    NavigationLink {
                        RearFogStrobeView()
                    } label: {
                        NavRow(icon: "timer",
                               title: L10n.t("开始 / 停止爆闪", "Start / stop strobe"),
                               subtitle: L10n.t("单次最长 30 秒 · 显示剩余时间", "Up to 30 s · live countdown"),
                               tint: P4Palette.red)
                    }
                } footer: {
                    Text(L10n.t("通过 0x273 的后雾灯位实现；需要车辆上电且能收到整车 0x273。",
                                "Driven by the rear-fog bit in 0x273; the car must be powered and sending 0x273."))
                }
            }

            if module.id == "research" {
                Section {
                    NavigationLink {
                        ResearchLabelsView()
                    } label: {
                        NavRow(icon: "tag.fill",
                               title: L10n.t("捕获标签（A–D）", "Capture labels (A–D)"),
                               subtitle: L10n.t("给导出的 CSV segment 加注释",
                                                "Annotate segments in the exported CSV"),
                               tint: P4Palette.purple)
                    }
                }
            }

            if module.id == "nag", capabilitySupported, !environment.isSetupMode {
                Section {
                    NavigationLink {
                        NagAdvancedView()
                    } label: {
                        NavRow(icon: "dial.medium.fill",
                               title: L10n.t("高级参数（报文级）", "Advanced parameters"),
                               subtitle: L10n.t("目标 ID / 报文节奏 / 扭矩表（只读）",
                                                "Frame IDs / timing / torque table (read-only)"),
                               tint: P4Palette.indigo)
                    }
                } footer: {
                    Text(L10n.t("修改 0x370 / 0x399 的报文级参数前，请确认你清楚每一字段的含义；AP 激活时禁止写入。",
                                "Make sure you understand each frame-level field before changing 0x370 / 0x399 parameters. Writes are blocked while AP is active."))
                }
            }

            statsSection
        }
        .navigationTitle(module.localizedTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.p4Background, for: .navigationBar)
        .labelStyle(.p4Row)
        .scrollContentBackground(.hidden)
        .background(Color.p4Background.ignoresSafeArea())
        .contentMargins(.top, Theme.spacing(0.5), for: .scrollContent)
        .navigationDestination(isPresented: $showsAdvanced) { NagAdvancedView() }
        .navigationDestination(isPresented: $showsResearchLabels) { ResearchLabelsView() }
        .navigationDestination(isPresented: $showsHeadlightStrobe) { HeadlightStrobeView() }
        .navigationDestination(isPresented: $showsRearFog) { RearFogStrobeView() }
        .overlay(alignment: .bottom) { ToastOverlay() }
        .refreshable { await load() }
        .task { await poll() }
        .task {
            #if DEBUG
            // 本地联调：SIMCTL_CHILD_P4CAN_NAG_ADVANCED=1 直接进入高级参数
            if module.id == "nag",
               ProcessInfo.processInfo.environment["P4CAN_NAG_ADVANCED"] == "1" {
                try? await Task.sleep(for: .milliseconds(500))
                showsAdvanced = true
            }
            if module.id == "research",
               ProcessInfo.processInfo.environment["P4CAN_RESEARCH_LABELS"] == "1" {
                try? await Task.sleep(for: .milliseconds(500))
                showsResearchLabels = true
            }
            if module.id == "headlight",
               ProcessInfo.processInfo.environment["P4CAN_HEADLIGHT_STROBE"] == "1" {
                try? await Task.sleep(for: .milliseconds(500))
                showsHeadlightStrobe = true
            }
            if module.id == "rearFog",
               ProcessInfo.processInfo.environment["P4CAN_REAR_FOG"] == "1" {
                try? await Task.sleep(for: .milliseconds(500))
                showsRearFog = true
            }
            #endif
        }
        .confirmationDialog(
            L10n.t("确认执行「\(pendingTrigger?.localizedTitle ?? "")」？",
                    "Run “\(pendingTrigger?.localizedTitle ?? "")”?"),
            isPresented: Binding(
                get: { pendingTrigger != nil },
                set: { if !$0 { pendingTrigger = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(L10n.t("确认执行", "Confirm"), role: .destructive) {
                Haptics.warning()
                if let control = pendingTrigger {
                    Task { await fire(control) }
                }
                pendingTrigger = nil
            }
            Button(L10n.t("取消", "Cancel"), role: .cancel) { pendingTrigger = nil }
        } message: {
            Text(L10n.t("将向设备提交：\(module.localizedTitle) / \(pendingTrigger?.localizedTitle ?? "")",
                        "Sends to the device: \(module.localizedTitle) / \(pendingTrigger?.localizedTitle ?? "")"))
        }
    }

    // MARK: - 顶部信息

    /// 模块信息卡：图标瓦片 + 说明。
    ///
    /// 标题由导航栏承担，卡片里不再重复写一遍模块名；图标尺寸与列表行同源
    /// （`Theme.Icon` / `ModuleIconTile`），从列表点进来不会有"换了一套图标"的割裂感。
    private var heroHeader: some View {
        HStack(alignment: .center, spacing: Theme.Icon.gap) {
            ModuleIconTile(name: module.icon, size: Theme.Icon.hero, tint: module.section.tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.t(module.section.rawValue, module.section.englishName))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(module.section.tint)
                Text(module.localizedSummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Theme.spacing(2))
        .frame(maxWidth: .infinity, alignment: .leading)
        .p4Glass(cornerRadius: Theme.Radius.card)
        .accessibilityElement(children: .combine)
    }

    // MARK: - 轮询

    private func poll() async {
        while !Task.isCancelled {
            await load()
            try? await Task.sleep(for: pollInterval)
        }
    }

    /// 只在部分固件版本存在的控件：设备没有上报对应字段时整行隐藏，
    /// 而不是留一个永远「读取中」、提交还会被固件拒绝的占位行。
    private static let firmwareOptionalKeys: [String: String] = [
        "r79ap.blockPark": "blockTxInPark",
        "nag.pauseLaneChange": "pauseDuringLaneChange",
    ]

    private func isControlAvailable(_ control: FeatureControl) -> Bool {
        guard let key = Self.firmwareOptionalKeys[control.id] else { return true }
        return statsObject(for: control)?[key] != nil
    }

    private func load() async {
        // 主端点失败时保留上一次成功的数据（共享缓存不清空），
        // 由 `loadFailed` 提示「数据可能过期」。
        await environment.refreshEndpoint(module.statsPath)
        for path in Set(module.controls.compactMap(\.readPath)) where path != module.statsPath {
            await environment.refreshEndpoint(path)
        }
        syncFromDevice()
    }

    // MARK: - 读取映射

    /// 控件状态所在的对象（可能是模块主端点，也可能是 readPath 指向的端点）。
    private func statsObject(for control: FeatureControl) -> [String: P4JSON]? {
        environment.endpointValue(control.readPath ?? module.statsPath)?.objectValue
    }

    /// 读取用键：固件里写入参数名与状态字段名常不一致（如 confirm → stalkConfirmEnabled）。
    private func readKey(for control: FeatureControl, writeKey: String) -> String {
        control.readKey ?? writeKey
    }

    /// 每次轮询都把控件值同步为**设备当前值**（不再"猜默认值"）：
    /// - 读不到 → 清空，UI 显示「读取中 / 未获取」，不显示任何默认值；
    /// - 读到 → 直接覆盖本地值，因此网页上改了设置，App 这边会跟着变；
    /// - 正在拖动的滑杆跳过，避免手抖。
    private func syncFromDevice() {
        for control in module.controls {
            // 本控件正在拖动或刚提交、还没回读：保留手指/请求带来的本地值。
            if sliderEditing.contains(control.id) || pendingWrites.contains(control.id)
                || editedPairs.contains(control.id) { continue }
            switch control.kind {
            case .number(let key, _, _, _, _, _):
                numberValues[key] = numberState(control, writeKey: key)
            case .pairNumber(let first, let second, _):
                numberValues[first.key] = numberState(control, writeKey: first.key)
                numberValues[second.key] = numberState(control, writeKey: second.key)
            case .select(let key, _, _, _), .selectRead(let key, _, _, _, _):
                selectedOptions[key] = selectText(control, writeKey: key)
            default:
                break
            }
        }
    }

    // MARK: - 控件

    @ViewBuilder
    private func controlRow(_ control: FeatureControl) -> some View {
        switch control.kind {
        case .toggle(let key, _, _):
            if let current = boolState(control, writeKey: key) {
                Toggle(isOn: Binding(
                    get: { optimisticToggles[control.id] ?? current },
                    set: { newValue in
                        optimisticToggles[control.id] = newValue
                        pendingWrites.insert(control.id)
                        Task {
                            await submitToggle(control, key: key, newValue: newValue)
                            optimisticToggles[control.id] = nil
                        }
                    }
                )) {
                    controlLabel(control)
                }
                .disabled(!canWrite || environment.isBusy || pendingWrites.contains(control.id))
            } else {
                pendingRow(control)
            }

        case .endpointToggle(let readKey, _, _):
            if let current = boolState(control, writeKey: readKey) {
                Toggle(isOn: Binding(
                    get: { optimisticToggles[control.id] ?? current },
                    set: { newValue in
                        optimisticToggles[control.id] = newValue
                        pendingWrites.insert(control.id)
                        Task {
                            await submitEndpoint(control, newValue: newValue)
                            optimisticToggles[control.id] = nil
                        }
                    }
                )) {
                    controlLabel(control)
                }
                .disabled(!canWrite || environment.isBusy || pendingWrites.contains(control.id))
            } else {
                pendingRow(control)
            }

        case .select(let key, let options, _, _), .selectRead(let key, _, let options, _, _):
            if let current = selectedOptions[key], options.contains(where: { $0.rawValue == current }) {
                Picker(control.localizedTitle, selection: Binding(
                    get: { current },
                    set: { newValue in
                        selectedOptions[key] = newValue
                        pendingWrites.insert(control.id)
                        // 读取值（如 STANDARD）与提交值（如 20）可能不同名，按 Option.submitValue 提交。
                        let submit = options.first { $0.rawValue == newValue }?.submitValue ?? newValue
                        Task { await submitSelect(control, key: key, rawValue: submit) }
                    }
                )) {
                    ForEach(options) { option in
                        Text(option.localizedLabel).tag(option.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .disabled(!canWrite || environment.isBusy || pendingWrites.contains(control.id))
                .accessibilityLabel(L10n.t("\(control.localizedTitle)选择器", "\(control.localizedTitle) picker"))
            } else if let current = selectedOptions[key] {
                // 设备返回了值，但不在 App 的选项域内（固件新增枚举等）→ 原样只读展示
                HStack {
                    controlLabel(control)
                    Spacer(minLength: Theme.spacing(1))
                    Text(current)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            } else {
                pendingRow(control)
            }

        case .number(let key, let range, let step, let unit, _, _):
            if let value = numberValues[key] {
                VStack(alignment: .leading, spacing: Theme.spacing(1)) {
                    HStack {
                        Text(control.localizedTitle)
                        Spacer()
                        Text("\(Int(value)) \(unit)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .font(.subheadline)
                    Slider(
                        value: Binding(
                            get: { min(max(value, range.lowerBound), range.upperBound) },
                            set: { numberValues[key] = $0 }
                        ),
                        in: range,
                        step: step
                    ) { editing in
                        if editing {
                            sliderEditing.insert(control.id)
                        } else {
                            sliderEditing.remove(control.id)
                            if let value = numberValues[key] {
                                // 松手到 Task 真正开始之间还有一帧，先占锁再提交。
                                pendingWrites.insert(control.id)
                                Task { await submitNumber(control, key: key, value: value) }
                            }
                        }
                    }
                    .disabled(!canWrite || environment.isBusy || pendingWrites.contains(control.id))
                    .accessibilityLabel(L10n.t("\(control.localizedTitle)，单位\(unit)", "\(control.localizedTitle), unit \(unit)"))
                    if let footnote = control.localizedFootnote {
                        Text(footnote).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            } else {
                pendingRow(control)
            }

        case .pairNumber(let first, let second, _):
            if numberValues[first.key] != nil, numberValues[second.key] != nil {
                VStack(alignment: .leading, spacing: Theme.spacing(1.5)) {
                    Text(control.localizedTitle).font(.subheadline)
                    pairSlider(first, controlID: control.id)
                    pairSlider(second, controlID: control.id)
                    if let footnote = control.localizedFootnote {
                        Text(footnote).font(.caption2).foregroundStyle(.secondary)
                    }
                    Button {
                        Task { await submitPair(control, first: first, second: second) }
                    } label: {
                        Label(L10n.t("同时提交", "Submit both"), systemImage: "arrow.up.circle")
                            .font(.footnote.weight(.medium))
                            .labelStyle(.titleAndIcon)
                    }
                    .disabled(!canWrite || environment.isBusy || pendingWrites.contains(control.id))
                }
                .padding(.vertical, 2)
            } else {
                pendingRow(control)
            }

        case .trigger(_, _, let confirmation, let destructive):
            Button {
                if confirmation {
                    pendingTrigger = control
                } else {
                    Task { await fire(control) }
                }
            } label: {
                controlLabel(control)
                    .foregroundStyle(destructive ? Color.p4Err : Color.accentColor)
            }
            .disabled(!canWrite || environment.isBusy || pendingWrites.contains(control.id))
        }
    }

    private func pairSlider(_ spec: NumberSpec, controlID: String) -> some View {
        HStack {
            Text(spec.key == "noaStabilizationSeconds" ? L10n.t("NOA 稳定期", "NOA settle") :
                 spec.key == "cancelPauseSeconds" ? L10n.t("取消暂停", "Cancel pause") :
                 spec.key == "preMs" ? L10n.t("前置窗口", "Pre window") : L10n.t("后置窗口", "Post window"))
                .font(.caption)
                .foregroundStyle(.secondary)
            if spec.key == "preMs" || spec.key == "postMs" {
                // 固件只接受固定档位，不能给任意毫秒值。
                let presets = spec.key == "preMs" ? [2000, 5000, 10000, 15000] : [2000, 5000, 10000]
                Picker(spec.key, selection: Binding(
                    get: {
                        let current = Int(numberValues[spec.key] ?? Double(presets[0]))
                        return presets.min(by: { abs($0 - current) < abs($1 - current) }) ?? presets[0]
                    },
                    set: { numberValues[spec.key] = Double($0) }
                )) {
                    ForEach(presets, id: \.self) { value in
                        Text("\(value / 1000) s").tag(value)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .accessibilityLabel(L10n.t("\(spec.key)，单位秒", "\(spec.key), seconds"))
            } else {
                Slider(
                    value: Binding(
                        get: { min(max(numberValues[spec.key] ?? spec.range.lowerBound, spec.range.lowerBound), spec.range.upperBound) },
                        set: {
                            numberValues[spec.key] = $0
                            editedPairs.insert(controlID)
                        }
                    ),
                    in: spec.range,
                    step: 1
                ) { editing in
                    // 成对参数只在「同时提交」时写入，但拖动期间同样不能被轮询覆盖。
                    if editing {
                        sliderEditing.insert(controlID)
                    } else {
                        sliderEditing.remove(controlID)
                    }
                }
                .accessibilityLabel(L10n.t("\(spec.key)，单位\(spec.unit)", "\(spec.key), unit \(spec.unit)"))
                Text("\(Int(numberValues[spec.key] ?? spec.range.lowerBound)) \(spec.unit)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 54, alignment: .trailing)
            }
        }
    }

    private func controlLabel(_ control: FeatureControl) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(control.localizedTitle).font(.subheadline)
            if let footnote = control.localizedFootnote {
                Text(footnote).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// 设备返回的开关值；nil = 设备没有这个字段（不当作 false）。
    private func boolState(_ control: FeatureControl, writeKey: String) -> Bool? {
        guard let object = statsObject(for: control) else { return nil }
        let key = readKey(for: control, writeKey: writeKey)
        guard let value = object[key] else { return nil }
        if let target = control.readEquals {
            guard let number = value.intValue else { return nil }
            return number == target
        }
        if let flag = value.boolValue { return flag }
        if let number = value.intValue { return number != 0 }
        return nil
    }

    /// 设备返回的数值；nil = 设备没有这个字段（不当作 0）。
    private func numberState(_ control: FeatureControl, writeKey: String) -> Double? {
        statsObject(for: control)?[readKey(for: control, writeKey: writeKey)]?.doubleValue
    }

    /// 设备返回的选择值（255 视为「原厂」）。
    ///
    /// `.selectRead` 把读取键写在枚举里（写入 m、读取 mode），优先级：
    /// 控件级 readKey → 枚举内 readKey → 写入键。
    private func selectText(_ control: FeatureControl, writeKey: String) -> String? {
        var key = readKey(for: control, writeKey: writeKey)
        if case .selectRead(_, let caseReadKey, _, _, _) = control.kind, control.readKey == nil {
            key = caseReadKey
        }
        guard let value = statsObject(for: control)?[key] else { return nil }
        if let text = value.stringValue { return text }
        if case .bool(let flag) = value { return flag ? "1" : "0" }
        if let number = value.intValue { return number == 255 ? "stock" : String(number) }
        return nil
    }

    /// 设备没有上报该控件状态时的占位行（绝不显示默认开关/默认数值）。
    private func pendingRow(_ control: FeatureControl) -> some View {
        HStack(alignment: .firstTextBaseline) {
            controlLabel(control)
            Spacer(minLength: Theme.spacing(1))
            Text(loadFailed == nil ? L10n.t("读取中…", "Reading…") : L10n.t("未获取", "Unavailable"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.t("\(control.localizedTitle)，设备未提供状态", "\(control.localizedTitle), no state from device"))
    }

    // MARK: - 提交

    /// 拆分 `extra` 声明："statsKey"、"statsKey:submitKey"，尾部加 `?` 表示可选。
    ///
    /// 可选参数用于跨固件版本兼容：例如 R79 AP 控制在 3.35.8 新增 blockTxInPark，
    /// 旧固件没有该字段，就不提交它，而不是整条命令发不出去。
    private func splitExtra(_ key: String) -> (read: String, write: String, optional: Bool) {
        var body = key
        var optional = false
        if body.hasSuffix("?") {
            optional = true
            body.removeLast()
        }
        let parts = body.split(separator: ":", maxSplits: 1).map(String.init)
        return (parts[0], parts.count > 1 ? parts[1] : parts[0], optional)
    }

    /// 校验 extra 声明的兄弟参数是否都在设备状态里；缺了就明确报错，避免发出必然 400 的请求。
    private func missingSiblings(_ keys: [String]) -> [String] {
        keys.compactMap { key in
            let item = splitExtra(key)
            if item.optional { return nil }
            return stats?[item.read] == nil ? item.read : nil
        }
    }

    private func siblingParams(_ keys: [String]) -> [P4Param] {
        keys.compactMap { key in
            let (read, write, _) = splitExtra(key)
            guard let value = stats?[read] else { return nil }
            switch value {
            case .bool(let flag): return P4Param(write, flag ? "1" : "0")
            case .int(let number): return P4Param(write, "\(number)")
            case .double(let number): return P4Param(write, "\(Int(number))")
            case .string(let text): return P4Param(write, text)
            default: return nil
            }
        }
    }

    private func submitToggle(_ control: FeatureControl, key: String, newValue: Bool) async {
        guard case .toggle(_, let path, let extra) = control.kind else { return }
        // 入口即加锁并用 defer 兜底：早退分支（缺兄弟参数、常驻 AP 未选手势）
        // 若不加锁会留下一个永远 disabled 的控件。
        pendingWrites.insert(control.id)
        defer { pendingWrites.remove(control.id) }

        // 常驻 AP：固件要求 enabled + method 两个参数同时提交，且 method 不能是「未选择」。
        if path == P4Route.continuousAPConfig, newValue {
            guard let method = stats?["method"]?.intValue else {
                environment.toast = P4Toast(message: L10n.t("设备尚未上报「触发手势」，暂不能开启常驻 AP",
                                     "The device has not reported a trigger gesture; continuous AP cannot be enabled yet"), style: .failure)
                return
            }
            if method == 0 {
                environment.toast = P4Toast(message: L10n.t("请先选择「触发手势」，再开启常驻 AP",
                                     "Choose a trigger gesture before enabling continuous AP"), style: .failure)
                return
            }
        }

        let missing = missingSiblings(extra)
        if !missing.isEmpty {
            environment.toast = P4Toast(
                message: L10n.t("设备尚未上报「\(control.localizedTitle)」所需的参数（\(missing.joined(separator: "、"))），请稍后重试",
                                 "The device has not reported the parameters for “\(control.localizedTitle)” (\(missing.joined(separator: ", "))); try again shortly"),
                style: .failure
            )
            return
        }

        let before = boolState(control, writeKey: key)
        var query = [P4Param(key, newValue ? "1" : "0")]
        query.append(contentsOf: siblingParams(extra))
        await environment.command("\(module.localizedTitle) · \(control.localizedTitle)", path: path ?? module.statsPath, query: query)
        await load()

        // 写成功但回读没变：说明固件没有回读该位或被闸门丢弃，明确告诉用户，避免「点了没反应」。
        let after = boolState(control, writeKey: key)
        if environment.toast?.style == .success, after != newValue, after == before {
            environment.toast = P4Toast(
                message: L10n.t("已提交「\(control.localizedTitle)」，但设备未回读该状态（固件未暴露或未生效）",
                                 "Sent “\(control.localizedTitle)”, but the device did not report the new state (not exposed or not applied)"),
                style: .info
            )
        }
    }

    private func submitEndpoint(_ control: FeatureControl, newValue: Bool) async {
        guard case .endpointToggle(_, let on, let off) = control.kind else { return }
        pendingWrites.insert(control.id)
        defer { pendingWrites.remove(control.id) }
        await environment.command(
            "\(module.localizedTitle) · \(control.localizedTitle)",
            path: newValue ? on : off
        )
        await load()
    }

    private func submitSelect(_ control: FeatureControl, key: String, rawValue: String) async {
        pendingWrites.insert(control.id)
        defer { pendingWrites.remove(control.id) }
        let path: String?
        let extra: [String]
        switch control.kind {
        case .select(_, _, let p, let e):
            path = p; extra = e
        case .selectRead(_, _, _, let p, let e):
            path = p; extra = e
        default:
            return
        }
        let missing = missingSiblings(extra)
        if !missing.isEmpty {
            environment.toast = P4Toast(
                message: L10n.t("设备尚未上报「\(control.localizedTitle)」所需的参数（\(missing.joined(separator: "、"))），请稍后重试",
                                 "The device has not reported the parameters for “\(control.localizedTitle)” (\(missing.joined(separator: ", "))); try again shortly"),
                style: .failure
            )
            return
        }
        var query = [P4Param(key, rawValue)]
        query.append(contentsOf: siblingParams(extra))
        await environment.command("\(module.localizedTitle) · \(control.localizedTitle)", path: path ?? module.statsPath, query: query)
        await load()
    }

    private func submitNumber(_ control: FeatureControl, key: String, value: Double) async {
        guard case .number(_, _, _, _, let path, let extra) = control.kind else { return }
        pendingWrites.insert(control.id)
        defer { pendingWrites.remove(control.id) }
        let missing = missingSiblings(extra)
        if !missing.isEmpty {
            environment.toast = P4Toast(
                message: L10n.t("设备尚未上报「\(control.localizedTitle)」所需的参数（\(missing.joined(separator: "、"))），请稍后重试",
                                 "The device has not reported the parameters for “\(control.localizedTitle)” (\(missing.joined(separator: ", "))); try again shortly"),
                style: .failure
            )
            return
        }
        var query = [P4Param(key, "\(Int(value))")]
        query.append(contentsOf: siblingParams(extra))
        await environment.command("\(module.localizedTitle) · \(control.localizedTitle)", path: path ?? module.statsPath, query: query)
        await load()
    }

    private func submitPair(_ control: FeatureControl, first: NumberSpec, second: NumberSpec) async {
        guard case .pairNumber(_, _, let path) = control.kind else { return }
        pendingWrites.insert(control.id)
        defer {
            pendingWrites.remove(control.id)
            editedPairs.remove(control.id)
        }
        let query = [
            P4Param(first.key, "\(Int(numberValues[first.key] ?? first.range.lowerBound))"),
            P4Param(second.key, "\(Int(numberValues[second.key] ?? second.range.lowerBound))"),
        ]
        await environment.command("\(module.localizedTitle) · \(control.localizedTitle)", path: path, query: query)
        await load()
    }

    private func fire(_ control: FeatureControl) async {
        guard case .trigger(let path, let query, _, _) = control.kind else { return }
        await environment.command("\(module.localizedTitle) · \(control.localizedTitle)", path: path, query: query)
        await load()
    }

    // MARK: - 状态展示

    /// 捕获类模块的运行状态：进度、容量、前置条件。
    ///
    /// 这两个模块以前只有一排触发按钮：开始后不知道录到哪、为什么被 409 拒绝、
    /// 什么时候能导出。状态字段固件都给了，这里直接呈现，不再让用户去原始表里找。
    @ViewBuilder
    private var captureSection: some View {
        if let object = captureObject {
            Section {
                HStack {
                    Text(L10n.t("状态", "State"))
                    Spacer()
                    Text(captureStateText)
                        .foregroundStyle(captureBusy ? Color.p4Warn : Color.secondary)
                }
                .font(.subheadline)

                if let maxSegments = object["maxSegments"]?.intValue, maxSegments > 0 {
                    let done = Int(object["completedSegments"]?.intValue
                                   ?? object["segments"]?.intValue ?? 0)
                    LabeledContent(L10n.t("已捕获段数", "Segments"),
                                   value: "\(done) / \(maxSegments)")
                        .font(.subheadline)
                }

                if let samples = object["samples"]?.intValue,
                   let capacity = object["capacity"]?.intValue, capacity > 0 {
                    LabeledContent(L10n.t("样本", "Samples"), value: "\(samples) / \(capacity)")
                        .font(.subheadline)
                }

                if object["exporting"]?.boolValue != true,
                   let remaining = object["remainingMs"]?.intValue, remaining > 0 {
                    LabeledContent(L10n.t("剩余", "Remaining"),
                                   value: "\(Int(remaining / 1000)) s")
                        .font(.subheadline)
                }

                if module.id == "research",
                   let ready = object["preSnapshotsReady"]?.intValue,
                   let slots = object["preSnapshotSlots"]?.intValue, slots > 0 {
                    LabeledContent(L10n.t("前置快照", "Pre-snapshots"), value: "\(ready) / \(slots)")
                        .font(.subheadline)
                        .foregroundStyle(ready < slots ? Color.p4Warn : Color.primary)
                }

                if let reason = object["fullReason"]?.stringValue, !reason.isEmpty {
                    Text(captureReasonText(reason))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(L10n.t("捕获状态", "Capture status"))
            } footer: {
                Text(captureFooterText(object))
            }
        }
    }

    private func captureReasonText(_ raw: String) -> String {
        switch raw {
        case "SAMPLES": return L10n.t("样本数已达上限，需要重置后才能继续。", "Sample buffer is full; reset before capturing again.")
        case "SEGMENTS": return L10n.t("段数已达上限，需要重置后才能继续。", "Segment limit reached; reset before capturing again.")
        case "ARCHIVE": return L10n.t("原始归档已满，需要重置后才能继续。", "Raw archive is full; reset before capturing again.")
        default: return raw
        }
    }

    private func captureFooterText(_ object: [String: P4JSON]) -> String {
        if object["exporting"]?.boolValue == true {
            return L10n.t("正在导出 CSV：导出完成前不能开始新的捕获。",
                          "Exporting CSV; new captures are blocked until it finishes.")
        }
        if object["capturing"]?.boolValue == true {
            return L10n.t("录制进行中：固件不支持中途停止，结束后才能开始下一次；完成后再导出或重置。",
                          "Capturing: the firmware cannot stop mid-run; wait for it to finish before starting again.")
        }
        if module.id == "research",
           let ready = object["preSnapshotsReady"]?.intValue,
           let slots = object["preSnapshotSlots"]?.intValue, ready < slots {
            return L10n.t("前置快照未就绪（\(ready)/\(slots)）：先让车辆上电、相关总线在线，否则开始会被拒绝。",
                          "Pre-snapshots not ready (\(ready)/\(slots)); power the car and bring the bus online first.")
        }
        if object["state"]?.stringValue == "FULL" {
            return L10n.t("缓冲区已满：先导出 CSV 或重置，再开始新的捕获。",
                          "Buffer full: export the CSV or reset before capturing.")
        }
        return L10n.t("录制会持续到固件预置的时长结束；开始前请确认槽位标签。",
                      "Recording runs for the firmware-defined window; check the slot label before starting.")
    }

    @ViewBuilder
    private var statsSection: some View {
        Section {
            if let failed = loadFailed {
                Label(failed, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.p4Err)
            }
            if let stats {
                let scalars = stats.flatScalars.filter { entry in
                    guard let text = entry.value.stringValue else { return true }
                    return !text.trimmingCharacters(in: .whitespaces).isEmpty
                }
                if scalars.isEmpty {
                    Text(L10n.t("该端点未返回可展示字段", "This endpoint returned no displayable fields"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(scalars, id: \.key) { entry in
                        MetricRow(key: entry.key, value: entry.value)
                    }
                }
                if stats.objectValue?.contains(where: { entry in
                    switch entry.value {
                    case .array, .object: return true
                    default: return false
                    }
                }) == true {
                    DisclosureGroup(L10n.t("原始数据", "Raw data"), isExpanded: $showsRawData) {
                        Text(stats.prettyText())
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .font(.footnote)
                }
            } else if loadFailed == nil {
                SkeletonRows(count: 5)
            }
        } header: {
            Text(L10n.t("实时状态", "Live status"))
        } footer: {
            // 新鲜度：端点级时间戳，读失败时明确「这是旧数据」，
            // 不再出现「在线但数据不动」却看不出问题的状态。
            if let age = environment.endpointAge(module.statsPath) {
                Text(freshnessText(age))
            } else if loadFailed != nil {
                Text(L10n.t("显示的是上一次成功读取的数据。", "Showing the last successful reading."))
            }
        }
    }

    private func freshnessText(_ age: TimeInterval) -> String {
        if age < 2 {
            return L10n.t("刚刚更新", "Updated just now")
        }
        if age < 60 {
            return L10n.t("\(Int(age)) s 前更新", "Updated \(Int(age)) s ago")
        }
        return L10n.t("\(Int(age / 60)) 分钟前更新", "Updated \(Int(age / 60)) min ago")
    }
}
