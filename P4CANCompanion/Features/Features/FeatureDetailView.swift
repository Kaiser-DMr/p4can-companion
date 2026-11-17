import SwiftUI

/// 功能模块详情页：控件（开关/选择/滑杆/成对数值/按钮）+ 实时状态键值表 + 原始数据。
///
/// 与固件契约：所有写操作是 `POST path?key=value`；部分接口要求同时提交兄弟参数，
/// 由 `FeatureControl.Kind` 的 `extra` 声明，值取自当前 stats。
struct FeatureDetailView: View {
    @EnvironmentObject private var environment: AppEnvironment

    let module: FeatureModule

    @State private var stats: P4JSON?
    /// 控件声明了 readPath 时（如 LAB 的踏板档位在 /api/pedalmap/stats）的附加状态。
    @State private var statsByPath: [String: P4JSON] = [:]
    @State private var loadFailed: String?
    @State private var numberValues: [String: Double] = [:]
    @State private var selectedOptions: [String: String] = [:]
    @State private var pendingTrigger: FeatureControl?
    /// 乐观开关值：点下立即生效，避免「请求未回 → 开关弹回」的错觉。
    @State private var optimisticToggles: [String: Bool] = [:]
    /// 正在拖动的滑杆（拖动期间不回写设备值，避免手指被覆盖）。
    @State private var sliderEditing: Set<String> = []
    @State private var showsRawData = false
    @State private var showsAdvanced = false

    private let pollInterval: Duration = .milliseconds(1200)

    /// 车型能力位是否支持该模块（无声明视为支持）。
    private var capabilitySupported: Bool {
        guard let key = module.supportKey else { return true }
        return environment.capability(key) != false
    }

    /// 允许写入：能力支持 + 非 Setup 模式 + 实验室模块需 LAB 已开。
    private var canWrite: Bool {
        guard capabilitySupported, !environment.isSetupMode else { return false }
        if module.section == .lab, !environment.isLabEnabled { return false }
        return true
    }

    var body: some View {
        List {
            Section {
                Text(module.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(Theme.spacing(2))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .p4Glass(cornerRadius: Theme.Radius.card)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            if !capabilitySupported {
                Section {
                    Label("当前车型/拓扑不支持该功能（固件能力位为否）。", systemImage: "nosign")
                        .font(.footnote)
                        .foregroundStyle(.p4Warn)
                }
            } else if environment.isSetupMode {
                Section {
                    Label("设备处于 Setup 模式，CAN 注入与功能写入已禁用。", systemImage: "gear.badge.questionmark")
                        .font(.footnote)
                        .foregroundStyle(.p4Warn)
                }
            } else if module.section == .lab, !environment.isLabEnabled {
                Section {
                    Label("需要先在「实验室功能总开关」中启用 LAB。", systemImage: "flask")
                        .font(.footnote)
                        .foregroundStyle(.p4Warn)
                }
            }

            if !module.controls.isEmpty {
                Section(L10n.t("控制", "Controls")) {
                    ForEach(module.controls) { control in
                        controlRow(control)
                    }
                }
            }

            if module.id == "nag", capabilitySupported, !environment.isSetupMode {
                Section {
                    NavigationLink {
                        NagAdvancedView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "slider.horizontal.3")
                                .foregroundStyle(.tint)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.t("高级参数（报文级）", "Advanced parameters"))
                                    .font(.body)
                                Text(L10n.t("目标 ID / 报文节奏 / 扭矩表（只读）",
                                            "Frame IDs / timing / torque table (read-only)"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
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
        .navigationDestination(isPresented: $showsAdvanced) { NagAdvancedView() }
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
            #endif
        }
        .confirmationDialog(
            "确认执行「\(pendingTrigger?.title ?? "")」？",
            isPresented: Binding(
                get: { pendingTrigger != nil },
                set: { if !$0 { pendingTrigger = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("确认执行", role: .destructive) {
                Haptics.warning()
                if let control = pendingTrigger {
                    Task { await fire(control) }
                }
                pendingTrigger = nil
            }
            Button("取消", role: .cancel) { pendingTrigger = nil }
        } message: {
            Text("将向设备提交：\(module.title) / \(pendingTrigger?.title ?? "")")
        }
    }

    // MARK: - 轮询

    private func poll() async {
        while !Task.isCancelled {
            await load()
            try? await Task.sleep(for: pollInterval)
        }
    }

    private func load() async {
        do {
            let main = try await environment.api.get(module.statsPath)
            var byPath = [module.statsPath: main]
            for path in Set(module.controls.compactMap(\.readPath)) where path != module.statsPath {
                if let value = try? await environment.api.get(path) {
                    byPath[path] = value
                }
            }
            stats = main
            statsByPath = byPath
            loadFailed = nil
            syncFromDevice()
        } catch {
            loadFailed = AppEnvironment.friendly(error)
        }
    }

    // MARK: - 读取映射

    /// 控件状态所在的对象（可能是模块主端点，也可能是 readPath 指向的端点）。
    private func statsObject(for control: FeatureControl) -> [String: P4JSON]? {
        let path = control.readPath ?? module.statsPath
        if path == module.statsPath { return stats?.objectValue }
        return statsByPath[path]?.objectValue
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
            switch control.kind {
            case .number(let key, _, _, _, _, _):
                if sliderEditing.contains(control.id) { continue }
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
                        Task {
                            await submitToggle(control, key: key, newValue: newValue)
                            optimisticToggles[control.id] = nil
                        }
                    }
                )) {
                    controlLabel(control)
                }
                .disabled(!canWrite || environment.isBusy)
            } else {
                pendingRow(control)
            }

        case .endpointToggle(let readKey, _, _):
            if let current = boolState(control, writeKey: readKey) {
                Toggle(isOn: Binding(
                    get: { optimisticToggles[control.id] ?? current },
                    set: { newValue in
                        optimisticToggles[control.id] = newValue
                        Task {
                            await submitEndpoint(control, newValue: newValue)
                            optimisticToggles[control.id] = nil
                        }
                    }
                )) {
                    controlLabel(control)
                }
                .disabled(!canWrite || environment.isBusy)
            } else {
                pendingRow(control)
            }

        case .select(let key, let options, _, _), .selectRead(let key, _, let options, _, _):
            if let current = selectedOptions[key], options.contains(where: { $0.rawValue == current }) {
                Picker(control.title, selection: Binding(
                    get: { current },
                    set: { newValue in
                        selectedOptions[key] = newValue
                        // 读取值（如 STANDARD）与提交值（如 20）可能不同名，按 Option.submitValue 提交。
                        let submit = options.first { $0.rawValue == newValue }?.submitValue ?? newValue
                        Task { await submitSelect(control, key: key, rawValue: submit) }
                    }
                )) {
                    ForEach(options) { option in
                        Text(option.label).tag(option.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .disabled(!canWrite || environment.isBusy)
                .accessibilityLabel("\(control.title)选择器")
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
                        Text(control.title)
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
                                Task { await submitNumber(control, key: key, value: value) }
                            }
                        }
                    }
                    .disabled(!canWrite || environment.isBusy)
                    .accessibilityLabel("\(control.title)，单位\(unit)")
                    if let footnote = control.footnote {
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
                    Text(control.title).font(.subheadline)
                    pairSlider(first)
                    pairSlider(second)
                    if let footnote = control.footnote {
                        Text(footnote).font(.caption2).foregroundStyle(.secondary)
                    }
                    Button {
                        Task { await submitPair(control, first: first, second: second) }
                    } label: {
                        Label("同时提交", systemImage: "arrow.up.circle")
                            .font(.footnote.weight(.medium))
                    }
                    .disabled(!canWrite || environment.isBusy)
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
            .disabled(!canWrite || environment.isBusy)
        }
    }

    private func pairSlider(_ spec: NumberSpec) -> some View {
        HStack {
            Text(spec.key == "noaStabilizationSeconds" ? "NOA 稳定期" :
                 spec.key == "cancelPauseSeconds" ? "取消暂停" :
                 spec.key == "preMs" ? "前置窗口" : "后置窗口")
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(
                value: Binding(
                    get: { min(max(numberValues[spec.key] ?? spec.range.lowerBound, spec.range.lowerBound), spec.range.upperBound) },
                    set: { numberValues[spec.key] = $0 }
                ),
                in: spec.range,
                step: spec.range.upperBound > 100 ? 1000 : 1
            )
            .accessibilityLabel("\(spec.key)，单位\(spec.unit)")
            Text("\(Int(numberValues[spec.key] ?? spec.range.lowerBound)) \(spec.unit)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 54, alignment: .trailing)
        }
    }

    private func controlLabel(_ control: FeatureControl) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(control.title).font(.subheadline)
            if let footnote = control.footnote {
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
        if let number = value.intValue { return number == 255 ? "stock" : String(number) }
        return nil
    }

    /// 设备没有上报该控件状态时的占位行（绝不显示默认开关/默认数值）。
    private func pendingRow(_ control: FeatureControl) -> some View {
        HStack(alignment: .firstTextBaseline) {
            controlLabel(control)
            Spacer(minLength: Theme.spacing(1))
            Text(loadFailed == nil ? "读取中…" : "未获取")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(control.title)，设备未提供状态")
    }

    // MARK: - 提交

    /// 校验 extra 声明的兄弟参数是否都在设备状态里；缺了就明确报错，避免发出必然 400 的请求。
    private func missingSiblings(_ keys: [String]) -> [String] {
        keys.filter { stats?[$0] == nil }
    }

    private func siblingParams(_ keys: [String]) -> [P4Param] {
        keys.compactMap { key in
            guard let value = stats?[key] else { return nil }
            switch value {
            case .bool(let flag): return P4Param(key, flag ? "1" : "0")
            case .int(let number): return P4Param(key, "\(number)")
            case .double(let number): return P4Param(key, "\(Int(number))")
            case .string(let text): return P4Param(key, text)
            default: return nil
            }
        }
    }

    private func submitToggle(_ control: FeatureControl, key: String, newValue: Bool) async {
        guard case .toggle(_, let path, let extra) = control.kind else { return }

        // 常驻 AP：固件要求 enabled + method 两个参数同时提交，且 method 不能是「未选择」。
        if path == P4Route.continuousAPConfig, newValue {
            guard let method = stats?["method"]?.intValue else {
                environment.toast = P4Toast(message: "设备尚未上报「触发手势」，暂不能开启常驻 AP", style: .failure)
                return
            }
            if method == 0 {
                environment.toast = P4Toast(message: "请先选择「触发手势」，再开启常驻 AP", style: .failure)
                return
            }
        }

        let missing = missingSiblings(extra)
        if !missing.isEmpty {
            environment.toast = P4Toast(
                message: "设备尚未上报「\(control.title)」所需的参数（\(missing.joined(separator: "、"))），请稍后重试",
                style: .failure
            )
            return
        }

        let before = boolState(control, writeKey: key)
        var query = [P4Param(key, newValue ? "1" : "0")]
        query.append(contentsOf: siblingParams(extra))
        await environment.command("\(module.title) · \(control.title)", path: path ?? module.statsPath, query: query)
        await load()

        // 写成功但回读没变：说明固件没有回读该位或被闸门丢弃，明确告诉用户，避免「点了没反应」。
        let after = boolState(control, writeKey: key)
        if environment.toast?.style == .success, after != newValue, after == before {
            environment.toast = P4Toast(
                message: "已提交「\(control.title)」，但设备未回读该状态（固件未暴露或未生效）",
                style: .info
            )
        }
    }

    private func submitEndpoint(_ control: FeatureControl, newValue: Bool) async {
        guard case .endpointToggle(_, let on, let off) = control.kind else { return }
        await environment.command(
            "\(module.title) · \(control.title)",
            path: newValue ? on : off
        )
        await load()
    }

    private func submitSelect(_ control: FeatureControl, key: String, rawValue: String) async {
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
                message: "设备尚未上报「\(control.title)」所需的参数（\(missing.joined(separator: "、"))），请稍后重试",
                style: .failure
            )
            return
        }
        var query = [P4Param(key, rawValue)]
        query.append(contentsOf: siblingParams(extra))
        await environment.command("\(module.title) · \(control.title)", path: path ?? module.statsPath, query: query)
        await load()
    }

    private func submitNumber(_ control: FeatureControl, key: String, value: Double) async {
        guard case .number(_, _, _, _, let path, let extra) = control.kind else { return }
        let missing = missingSiblings(extra)
        if !missing.isEmpty {
            environment.toast = P4Toast(
                message: "设备尚未上报「\(control.title)」所需的参数（\(missing.joined(separator: "、"))），请稍后重试",
                style: .failure
            )
            return
        }
        var query = [P4Param(key, "\(Int(value))")]
        query.append(contentsOf: siblingParams(extra))
        await environment.command("\(module.title) · \(control.title)", path: path ?? module.statsPath, query: query)
        await load()
    }

    private func submitPair(_ control: FeatureControl, first: NumberSpec, second: NumberSpec) async {
        guard case .pairNumber(_, _, let path) = control.kind else { return }
        let query = [
            P4Param(first.key, "\(Int(numberValues[first.key] ?? first.range.lowerBound))"),
            P4Param(second.key, "\(Int(numberValues[second.key] ?? second.range.lowerBound))"),
        ]
        await environment.command("\(module.title) · \(control.title)", path: path, query: query)
        await load()
    }

    private func fire(_ control: FeatureControl) async {
        guard case .trigger(let path, let query, _, _) = control.kind else { return }
        await environment.command("\(module.title) · \(control.title)", path: path, query: query)
        await load()
    }

    // MARK: - 状态展示

    @ViewBuilder
    private var statsSection: some View {
        Section(L10n.t("实时状态", "Live status")) {
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
                    Text("该端点未返回可展示字段")
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
                    DisclosureGroup("原始数据", isExpanded: $showsRawData) {
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
        }
    }
}
