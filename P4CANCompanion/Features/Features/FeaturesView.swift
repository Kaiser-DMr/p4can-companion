import SwiftUI

/// 「功能」页：固件功能总入口（原「设置 → 功能」整段迁移到这里）。
///
/// 顺序严格保持固件网页 Settings → Features：
/// NAG → ISA → DMS → 视觉限速 → 自动转向灯 → 召唤状态 → R79 → 地区 → TLSSC →
/// 变道 → 踏板 → 常驻 AP → AP 加速 / 回收 → S3XY → LAB Menu。
/// 分类筛选已移除，保留搜索；四个快捷开关（ISA / DMS / S3XY / LAB Menu）直接内联。
struct FeaturesView: View {
    @EnvironmentObject private var environment: AppEnvironment

    /// 详情页导航栈（DEBUG 下可由 P4CAN_MODULE 直接深链到某个模块）。
    @State private var path: [String] = []
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    @State private var isaEnabled: Bool?
    @State private var dmsEnabled: Bool?
    @State private var busyID: String?
    /// 内联开关的乐观值：点下立即变化，设备回读后清除。
    @State private var gateOverrides: [String: Bool] = [:]

    // MARK: - 行模型

    private struct Entry: Identifiable {
        enum Kind {
            case module(FeatureModule)
            case s3xy
            case lab
        }

        let id: String
        let kind: Kind
    }

    /// 功能模块（不含车型卡片与实验室专属工具）
    private var modules: [FeatureModule] {
        FeatureCatalog.modules.filter { $0.section != .lab && $0.id != "profile" }
    }

    private var entries: [Entry] {
        modules.map { Entry(id: $0.id, kind: .module($0)) }
            + [Entry(id: "s3xy", kind: .s3xy), Entry(id: "lab", kind: .lab)]
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool { !trimmedQuery.isEmpty }

    private var searchResults: [Entry] {
        let needle = trimmedQuery.lowercased()
        guard !needle.isEmpty else { return [] }
        return entries.filter { entry in
            switch entry.kind {
            case .module(let module):
                return module.title.lowercased().contains(needle)
                    || module.summary.lowercased().contains(needle)
                    || module.titleEN.lowercased().contains(needle)
                    || module.summaryEN.lowercased().contains(needle)
                    || module.id.lowercased().contains(needle)
            case .s3xy:
                return ["s3xy", "button", "按键", "蓝牙", "bluetooth"].contains { $0.contains(needle) }
            case .lab:
                return ["lab", "menu", "实验", "实验室"].contains { $0.contains(needle) }
            }
        }
    }

    private var labEnabled: Bool {
        gateOverrides["lab"] ?? environment.featuresStatus?["lab"]?.boolValue ?? false
    }

    private var s3xyEnabled: Bool {
        gateOverrides["s3xy"] ?? environment.featuresStatus?["s3xy"]?.boolValue ?? false
    }

    // MARK: - Body

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                header
                list
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // 页面底色铺到状态栏 / 导航栏下方，避免系统默认的白色背景从上边缘透出来。
            .background(Color.p4Background.ignoresSafeArea())
            .navigationTitle(L10n.t("功能", "Features"))
            // 导航栏不再使用系统默认（浅色模式下为纯白）材质，与页面底色保持一致。
            .toolbarBackground(Color.p4Background, for: .navigationBar)
            .navigationDestination(for: String.self) { moduleID in
                if let module = FeatureCatalog.modules.first(where: { $0.id == moduleID }) {
                    FeatureDetailView(module: module)
                }
            }
            .overlay(alignment: .bottom) { ToastOverlay() }
        }
        .task { await loadConfigToggles() }
        .task {
            // ISA / DMS 的状态不在 snapshot 里，单独慢轮询。
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                await loadConfigToggles()
            }
        }
        .task {
            #if DEBUG
            // 本地联调：SIMCTL_CHILD_P4CAN_MODULE=ulc 启动即进入该模块详情
            if path.isEmpty,
               let moduleID = ProcessInfo.processInfo.environment["P4CAN_MODULE"],
               FeatureCatalog.modules.contains(where: { $0.id == moduleID }) {
                path = [moduleID]
            }
            // 本地联调：SIMCTL_CHILD_P4CAN_SEARCH=限速 预填搜索
            if let raw = ProcessInfo.processInfo.environment["P4CAN_SEARCH"] {
                query = raw
            }
            #endif
        }
    }

    // MARK: - 顶部：搜索

    private var header: some View {
        searchField
            .padding(.top, Theme.spacing(0.5))
            .padding(.bottom, Theme.spacing(1.5))
            .background(Color.p4Background)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
            TextField(
                L10n.t("搜索功能（如 踏板 / TLSSC / LAB）", "Search features (e.g. pedal / TLSSC / LAB)"),
                text: $query
            )
            .textFieldStyle(.plain)
            .font(.subheadline)
            .focused($searchFocused)
            .submitLabel(.search)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .onSubmit { searchFocused = false }
            .accessibilityLabel(L10n.t("搜索功能", "Search features"))
            if isSearching {
                Button {
                    Haptics.impact()
                    query = ""
                    searchFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("清除搜索", "Clear search"))
            }
        }
        .padding(.horizontal, Theme.spacing(1.5))
        .frame(height: 38)
        // 用「轻微着色的底 + 细描边」代替玻璃白底：既贴合页面底色，也不会在顶部形成一条白条。
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
        .onTapGesture { searchFocused = true }
        .padding(.horizontal, Theme.spacing(2))
    }

    // MARK: - 列表

    private var list: some View {
        ScrollViewReader { proxy in
            listRows
                .listStyle(.insetGrouped)
                .contentMargins(.top, Theme.spacing(0.5), for: .scrollContent)
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.immediately)
                #if DEBUG
                // 本地联调：SIMCTL_CHILD_P4CAN_FEATURES_SCROLL=bottom 启动后滚到底部（核对滚动后的顶栏配色）
                .task {
                    guard ProcessInfo.processInfo.environment["P4CAN_FEATURES_SCROLL"] == "bottom",
                          let last = entries.last?.id else { return }
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(last, anchor: .bottom) }
                }
                #endif
        }
    }

    private var listRows: some View {
        List {
            if isSearching {
                if searchResults.isEmpty {
                    emptySearchSection
                } else {
                    Section {
                        ForEach(searchResults) { entry in
                            row(entry)
                        }
                    } header: {
                        sectionHeader(
                            title: L10n.t("搜索结果", "Results"),
                            count: searchResults.count
                        )
                    }
                }
            } else {
                Section {
                    ForEach(entries) { entry in
                        row(entry).id(entry.id)
                    }
                } header: {
                    sectionHeader(
                        title: L10n.t("全部功能", "All features"),
                        count: entries.count
                    )
                } footer: {
                    Text(L10n.t("开关状态全部读取自设备；LAB Menu 打开后底部才出现「实验室」标签。",
                                "All switch states come from the device. The Lab tab appears only after LAB Menu is turned on."))
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ entry: Entry) -> some View {
        switch entry.kind {
        case .module(let module):
            if module.id == "isa" {
                InlineFeatureRow(
                    icon: module.icon,
                    title: module.localizedTitle,
                    subtitle: module.localizedSummary,
                    isOn: $isaEnabled,
                    busy: busyID == module.id,
                    disabled: environment.isBusy
                ) { newValue in
                    submitInline(module.id, label: L10n.t("ISA 抑制", "ISA Suppression"),
                                 path: P4Route.isaSuppressionConfig, enabled: newValue)
                }
            } else if module.id == "dms" {
                InlineFeatureRow(
                    icon: module.icon,
                    title: module.localizedTitle,
                    subtitle: module.localizedSummary,
                    isOn: $dmsEnabled,
                    busy: busyID == module.id,
                    disabled: environment.isBusy
                ) { newValue in
                    submitInline(module.id, label: L10n.t("禁用驾驶员监控", "Driver Monitoring"),
                                 path: P4Route.dmsConfig, enabled: newValue)
                }
            } else {
                NavigationLink {
                    FeatureDetailView(module: module)
                } label: {
                    FeatureRow(module: module, features: environment.featuresStatus)
                }
            }

        case .s3xy:
            InlineFeatureRow(
                icon: "emoji:🎮",
                title: L10n.t("S3XY", "S3XY"),
                subtitle: L10n.t("打开后底部出现「蓝牙」标签；用于 S3XY 配对与按键动作。",
                                 "Turns on S3XY buttons and shows the Bluetooth tab."),
                isOn: .constant(s3xyEnabled as Bool?),
                busy: busyID == "s3xy",
                disabled: environment.featuresStatus == nil || environment.isBusy
            ) { newValue in
                setFeaturesGate("s3xy", label: "S3XY", path: P4Route.featuresS3XY, enabled: newValue)
            }

        case .lab:
            InlineFeatureRow(
                icon: "emoji:🧪",
                title: L10n.t("实验室菜单 (LAB Menu)", "LAB Menu"),
                subtitle: L10n.t("显示实验性控制与捕获工具；打开后底部出现「实验室」标签。",
                                 "Show experimental controls and capture tools."),
                isOn: .constant(labEnabled as Bool?),
                busy: busyID == "lab",
                disabled: environment.featuresStatus == nil || environment.isBusy
            ) { newValue in
                setFeaturesGate("lab", label: "LAB Menu", path: P4Route.featuresLab, enabled: newValue)
            }
        }
    }

    /// 列表分组头：标题 + 数量胶囊，和卡片左边缘对齐，信息与原来的「全部 · N 项」一致。
    private func sectionHeader(title: String, count: Int) -> some View {
        HStack(spacing: Theme.spacing(1)) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Color.primary.opacity(0.07), in: Capsule())
            Spacer(minLength: 0)
        }
        .textCase(nil)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.t("\(title)，共 \(count) 项", "\(title), \(count) items"))
    }

    private var emptySearchSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.spacing(1)) {
                Label(L10n.t("没有匹配的功能", "No matching features"), systemImage: "magnifyingglass")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(L10n.t("试试更短的关键词，例如「NAG」「踏板」「TLSSC」「LAB」。",
                            "Try a shorter keyword such as NAG, pedal, TLSSC or LAB."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button(L10n.t("清除搜索", "Clear search")) {
                    Haptics.impact()
                    query = ""
                }
                .font(.footnote.weight(.medium))
            }
            .padding(.vertical, Theme.spacing(1))
        }
    }

    // MARK: - 读写

    private func loadConfigToggles() async {
        if let isa = try? await environment.api.get(P4Route.isaSuppressionConfig),
           let value = isa.objectValue?["enabled"]?.boolValue {
            isaEnabled = value
        }
        if let dms = try? await environment.api.get(P4Route.dmsConfig),
           let value = dms.objectValue?["enabled"]?.boolValue {
            dmsEnabled = value
        }
    }

    private func submitInline(_ id: String, label: String, path: String, enabled: Bool) {
        busyID = id
        if id == "isa" { isaEnabled = enabled }
        if id == "dms" { dmsEnabled = enabled }
        Task {
            await environment.command(label, path: path, query: [P4Param("enabled", enabled ? "1" : "0")])
            await loadConfigToggles()
            busyID = nil
        }
    }

    private func setFeaturesGate(_ id: String, label: String, path: String, enabled: Bool) {
        busyID = id
        gateOverrides[id] = enabled
        Task {
            await environment.command(label, path: path, query: [P4Param("enabled", enabled ? "1" : "0")])
            await environment.refreshFeatures()
            gateOverrides[id] = nil
            busyID = nil
            if id == "lab" {
                environment.toast = P4Toast(
                    message: enabled
                        ? L10n.t("实验室已开启，底部出现「实验室」标签", "LAB enabled — the Lab tab is now shown")
                        : L10n.t("实验室已关闭，底部标签已隐藏", "LAB disabled — the Lab tab is hidden"),
                    style: .info
                )
            } else if id == "s3xy" {
                environment.toast = P4Toast(
                    message: enabled
                        ? L10n.t("S3XY 已开启，底部出现「蓝牙」标签", "S3XY enabled — the Bluetooth tab is now shown")
                        : L10n.t("S3XY 已关闭，蓝牙标签已隐藏", "S3XY disabled — the Bluetooth tab is hidden"),
                    style: .info
                )
            }
        }
    }
}

// MARK: - 普通功能行

private struct FeatureRow: View {
    let module: FeatureModule
    let features: P4JSON?

    private var supportState: (text: String, ok: Bool)? {
        guard let key = module.supportKey, let value = features?[key]?.boolValue else { return nil }
        return (value ? L10n.t("支持", "Supported") : L10n.t("不支持", "Unsupported"), value)
    }

    var body: some View {
        HStack(alignment: .center, spacing: Theme.spacing(1.5)) {
            ModuleIcon(name: module.icon)
                .foregroundStyle(.tint)
                .frame(width: 32, height: 32)
                .background(Color.p4Tile, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(module.localizedTitle)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(module.localizedSummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: Theme.spacing(1))
            if let support = supportState {
                StatusChip(
                    text: support.text,
                    systemImage: support.ok ? "checkmark" : "minus",
                    tone: support.ok ? .ok : .warn
                )
                .layoutPriority(1)
            }
        }
        .padding(.vertical, Theme.spacing(0.5))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 内联开关行

private struct InlineFeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool?
    let busy: Bool
    let disabled: Bool
    let onChange: (Bool) -> Void

    private var binding: Binding<Bool> {
        Binding(
            get: { isOn ?? false },
            set: { newValue in
                Haptics.impact()
                onChange(newValue)
            }
        )
    }

    var body: some View {
        HStack(alignment: .center, spacing: Theme.spacing(1.5)) {
            ModuleIcon(name: icon)
                .font(.body)
                .foregroundStyle(.tint)
                .frame(width: 32, height: 32)
                .background(Color.p4Tile, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: Theme.spacing(1))
            if busy || isOn == nil {
                ProgressView()
                    .accessibilityLabel(L10n.t("正在与设备同步", "Syncing with device"))
            } else {
                Toggle("", isOn: binding)
                    .labelsHidden()
                    .disabled(disabled)
                    .accessibilityLabel(title)
            }
        }
        .padding(.vertical, Theme.spacing(0.5))
        .accessibilityElement(children: .combine)
    }
}
