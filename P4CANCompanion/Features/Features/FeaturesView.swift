import SwiftUI

/// 「功能」页：固件功能总入口（原「设置 → 功能」整段迁移到这里）。
///
/// 列表按 `FeatureModule.Section` 分组，顺序由枚举声明顺序决定：
/// 灯光 → 驾驶辅助 → 车身与舒适 → 高级与兼容（实验室模块归「实验室」标签页）。
/// 每个分组头显示 emoji + 名称 + 数量，搜索时退化为单一「搜索结果」分组。
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
    /// 灯光类模块的运行态（爆闪中）。读不到该端点时不显示，不伪造。
    @State private var strobeActive: [String: Bool] = [:]
    /// 置顶到「常用」的 entry id（顺序即展示顺序，最多 6 个）。
    @State private var pinnedIDs: [String] = FeaturePinStore.load()

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

    /// 一个分类分组：分类枚举 + 该分类下的行。
    private struct Group: Identifiable {
        let section: FeatureModule.Section
        let entries: [Entry]

        var id: String { section.rawValue }
    }

    /// 功能模块（不含车型卡片与实验室专属工具）
    private var modules: [FeatureModule] {
        FeatureCatalog.modules.filter { $0.section != .lab && $0.id != "profile" }
    }

    /// 全量行（含已置顶的）：搜索、置顶解析与深链滚动共用。
    private var allEntries: [Entry] {
        modules.map { Entry(id: $0.id, kind: .module($0)) }
            + [Entry(id: "s3xy", kind: .s3xy), Entry(id: "lab", kind: .lab)]
    }

    /// 搜索与调试锚点使用的扁平行列表。
    private var entries: [Entry] { allEntries }

    private func isPinned(_ id: String) -> Bool { pinnedIDs.contains(id) }

    /// 置顶行（按置顶顺序）。失效的 id（模块被重命名/删除）自动跳过。
    private var pinnedEntries: [Entry] {
        pinnedIDs.compactMap { id in allEntries.first { $0.id == id } }
    }

    /// 按分类分组；空分类不显示。已置顶的行从原分组移出，避免同一功能出现两次。
    private var groups: [Group] {
        FeatureModule.Section.allCases.compactMap { section in
            var items = modules
                .filter { $0.section == section && !isPinned($0.id) }
                .map { Entry(id: $0.id, kind: .module($0)) }
            if section == .advanced {
                if !isPinned("s3xy") { items.append(Entry(id: "s3xy", kind: .s3xy)) }
                if !isPinned("lab") { items.append(Entry(id: "lab", kind: .lab)) }
            }
            guard !items.isEmpty else { return nil }
            return Group(section: section, entries: items)
        }
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
                // 灯光两路直接进操作页；其余模块仍是通用详情页。
                if moduleID == "headlight" {
                    HeadlightStrobeView()
                } else if moduleID == "rearFog" {
                    RearFogStrobeView()
                } else if let module = FeatureCatalog.modules.first(where: { $0.id == moduleID }) {
                    FeatureDetailView(module: module)
                }
            }
            .overlay(alignment: .bottom) { ToastOverlay() }
        }
        .task {
            await loadConfigToggles()
            await loadStrobeStates()
        }
        .task {
            // ISA / DMS 的状态不在 snapshot 里，灯光运行态同理，单独慢轮询。
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                await loadConfigToggles()
                await loadStrobeStates()
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
        HStack(spacing: Theme.spacing(0.75)) {
            Image(systemName: "magnifyingglass")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(
                L10n.t("搜索功能（如 灯光 / 踏板 / TLSSC）", "Search features (e.g. light / pedal / TLSSC)"),
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
        // 用垂直内边距 + 最小高度代替固定 38pt：大字号下输入框会随文字长高，图标不再溢出圆角。
        .padding(.vertical, Theme.spacing(1))
        .frame(minHeight: 40)
        // 用「轻微着色的底 + 细描边」代替玻璃白底：既贴合页面底色，也不会在顶部形成一条白条。
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                // 聚焦态：描边换成强调色并加粗到 1pt，和胶囊的"选中=有边界"语言一致。
                .strokeBorder(
                    searchFocused ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.06),
                    lineWidth: searchFocused ? 1 : 0.5
                )
                .animation(.easeOut(duration: 0.15), value: searchFocused)
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
                                .contextMenu { pinMenu(entry) }
                        }
                    } header: {
                        sectionHeader(
                            title: L10n.t("搜索结果", "Results"),
                            count: searchResults.count
                        )
                    }
                }
            } else {
                if !pinnedEntries.isEmpty {
                    Section {
                        ForEach(pinnedEntries) { entry in
                            row(entry)
                                .id(entry.id)
                                .contextMenu { pinMenu(entry) }
                        }
                    } header: {
                        sectionHeader(
                            title: L10n.t("常用", "Pinned"),
                            count: pinnedEntries.count
                        )
                    } footer: {
                        Text(L10n.t("长按任意功能可置顶或取消（最多 \(FeaturePinStore.maxPins) 个）。",
                                    "Long-press a feature to pin or unpin it (up to \(FeaturePinStore.maxPins))."))
                    }
                }
                ForEach(groups) { group in
                    Section {
                        ForEach(group.entries) { entry in
                            row(entry)
                                .id(entry.id)
                                .contextMenu { pinMenu(entry) }
                        }
                    } header: {
                        sectionHeader(
                            title: L10n.t(group.section.rawValue, group.section.englishName),
                            count: group.entries.count
                        )
                    } footer: {
                        sectionFooter(for: group)
                    }
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
            } else if module.id == "headlight" {
                // 灯光两路直接进可操作页（状态 + 触发在前，参数在后），
                // 不再经过通用详情页里的「爆闪设置与触发」二级入口。
                NavigationLink {
                    HeadlightStrobeView()
                } label: {
                    FeatureRow(
                        module: module,
                        features: environment.featuresStatus,
                        strobeActive: strobeActive[module.id]
                    )
                }
            } else if module.id == "rearFog" {
                NavigationLink {
                    RearFogStrobeView()
                } label: {
                    FeatureRow(
                        module: module,
                        features: environment.featuresStatus,
                        strobeActive: strobeActive[module.id]
                    )
                }
            } else {
                NavigationLink {
                    FeatureDetailView(module: module)
                } label: {
                    FeatureRow(
                        module: module,
                        features: environment.featuresStatus,
                        strobeActive: strobeActive[module.id]
                    )
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

    /// 长按菜单：置顶 / 取消置顶。
    @ViewBuilder
    private func pinMenu(_ entry: Entry) -> some View {
        let pinned = isPinned(entry.id)
        Button {
            togglePin(entry.id)
        } label: {
            Label(pinned ? L10n.t("取消置顶", "Unpin") : L10n.t("置顶到常用", "Pin to top"),
                  systemImage: pinned ? "pin.slash" : "pin")
        }
    }

    private func togglePin(_ id: String) {
        Haptics.impact()
        if let index = pinnedIDs.firstIndex(of: id) {
            pinnedIDs.remove(at: index)
        } else {
            guard pinnedIDs.count < FeaturePinStore.maxPins else {
                environment.toast = P4Toast(
                    message: L10n.t("最多置顶 \(FeaturePinStore.maxPins) 个功能", "Up to \(FeaturePinStore.maxPins) pinned features"),
                    style: .info
                )
                return
            }
            pinnedIDs.append(id)
        }
        FeaturePinStore.save(pinnedIDs)
    }

    /// 分组脚注：灯光组提示真实灯光风险，最后一组说明状态来源。
    @ViewBuilder
    private func sectionFooter(for group: Group) -> some View {
        if group.section == .lighting {
            Text(L10n.t("灯光类功能会实际控制车辆灯光，请只在安全环境使用；爆闪期间可随时停止。",
                        "Lighting features drive the real lamps. Use them only in a safe environment; you can stop a strobe at any time."))
        } else if group.id == groups.last?.id {
            Text(L10n.t("开关状态全部读取自设备；LAB Menu 打开后底部才出现「实验室」标签。长按功能可置顶。",
                        "All switch states come from the device. The Lab tab appears only after LAB Menu is on. Long-press to pin."))
        }
    }

    /// 列表分组头：emoji + 标题 + 数量胶囊，和卡片左边缘对齐。
    /// 分组标题：系统分组列表的观感——纯文字、次要色、不加色点或胶囊徽标。
    private func sectionHeader(title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
            if environment.isShowingCachedData {
                Text(L10n.t("缓存", "Cached"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
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
                Text(L10n.t("试试更短的关键词，例如「灯光」「NAG」「踏板」「LAB」。",
                            "Try a shorter keyword such as light, NAG, pedal or LAB."))
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

    /// ISA / DMS 的状态不在 snapshot 里，单独拉；成功即写入离线缓存，失败时回退到上次的值。
    private func loadConfigToggles() async {
        var fresh: [String: P4JSON] = [:]
        if let isa = try? await environment.api.get(P4Route.isaSuppressionConfig),
           let value = isa.objectValue?["enabled"]?.boolValue {
            isaEnabled = value
            fresh["isa"] = isa
        }
        if let dms = try? await environment.api.get(P4Route.dmsConfig),
           let value = dms.objectValue?["enabled"]?.boolValue {
            dmsEnabled = value
            fresh["dms"] = dms
        }
        if !fresh.isEmpty {
            OfflineCache.save(host: environment.host, entries: fresh)
            return
        }
        // 两个都没拿到（离线）：只补缺失的那一项，避免把已有状态清空。
        guard isaEnabled == nil || dmsEnabled == nil,
              let cache = OfflineCache.load(host: environment.host)?.entries else { return }
        if isaEnabled == nil, let value = cache["isa"]?.objectValue?["enabled"]?.boolValue {
            isaEnabled = value
        }
        if dmsEnabled == nil, let value = cache["dms"]?.objectValue?["enabled"]?.boolValue {
            dmsEnabled = value
        }
    }

    /// 灯光类模块的运行态：只读，失败即视为「未知」，不显示徽章。
    /// 走共享端点缓存：灯光页在 800/500 ms 轮询时，这里直接复用，不再重复打设备。
    private func loadStrobeStates() async {
        var fresh: [String: Bool] = [:]
        if let json = await environment.refreshEndpoint(P4Route.headlightStrobeStats, maxAge: 3),
           let active = json.objectValue?["active"]?.boolValue {
            fresh["headlight"] = active
        }
        if let json = await environment.refreshEndpoint(P4Route.rearFogStrobeStats, maxAge: 3),
           let active = json.objectValue?["active"]?.boolValue {
            fresh["rearFog"] = active
        }
        strobeActive = fresh
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
            let ok = await environment.command(label, path: path, query: [P4Param("enabled", enabled ? "1" : "0")])
            await environment.refreshFeatures()
            gateOverrides[id] = nil
            busyID = nil
            // 失败时保留 command 的失败 toast，不能再覆盖成「已开启」。
            guard ok else { return }
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

// MARK: - 行骨架

/// 功能行的统一骨架：36pt 图标瓦片 + 标题 / 说明 + 尾部区域。
///
/// 功能页的普通行与内联开关行都走这里，保证图标尺寸、内边距、字重与行高完全一致；
/// 以后新增行样式（带徽章、带进度）只需要换尾部内容。
private struct FeatureRowShell<Trailing: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    var tint: Color? = nil
    /// 内联开关行要保留 Toggle 的可交互性，不能把子元素合并成一个无障碍元素。
    let combinesAccessibility: Bool
    private let trailing: Trailing

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        icon: String,
        title: String,
        subtitle: String,
        tint: Color? = nil,
        combinesAccessibility: Bool = true,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.tint = tint
        self.combinesAccessibility = combinesAccessibility
        self.trailing = trailing()
    }

    var body: some View {
        // 辅助功能字号下图标改为顶部对齐，和标题首行齐平（否则图标会漂在高文本块中间）。
        HStack(alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center,
               spacing: Theme.Icon.gap) {
            ModuleIconTile(name: icon, tint: tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                    // 常规字号保持单行；辅助功能字号不限制行数，避免标题被截。
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    // 常规字号两行；辅助功能字号完整展示说明。
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .multilineTextAlignment(.leading)
            }
            // 分隔线与文字左边缘对齐（而不是贴着图标瓦片），列表看起来更整齐。
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            Spacer(minLength: Theme.spacing(1))
            trailing
                .layoutPriority(1)
        }
        .padding(.vertical, Theme.spacing(0.5))
        .modifier(CombineAccessibilityIfNeeded(enabled: combinesAccessibility))
    }
}

/// 条件式无障碍合并，避免在 ViewBuilder 里写 if 造成类型分叉。
private struct CombineAccessibilityIfNeeded: ViewModifier {
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.accessibilityElement(children: .combine)
        } else {
            content
        }
    }
}

// MARK: - 普通功能行

private struct FeatureRow: View {
    let module: FeatureModule
    let features: P4JSON?
    /// 灯光类模块是否正在爆闪（nil = 设备未提供该状态）。
    var strobeActive: Bool? = nil

    private var supportState: (text: String, ok: Bool)? {
        guard let key = module.supportKey, let value = features?[key]?.boolValue else { return nil }
        return (value ? L10n.t("支持", "Supported") : L10n.t("不支持", "Unsupported"), value)
    }

    var body: some View {
        FeatureRowShell(icon: module.icon,
                        title: module.localizedTitle,
                        subtitle: module.localizedSummary,
                        tint: module.section.tint) {
            if strobeActive == true {
                StatusChip(text: L10n.t("爆闪中", "Strobing"),
                           systemImage: "light.beacon.max.fill",
                           tone: .ok)
            } else if let support = supportState {
                StatusChip(
                    text: support.text,
                    systemImage: support.ok ? "checkmark" : "minus",
                    tone: support.ok ? .ok : .warn
                )
            }
        }
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
        FeatureRowShell(icon: icon,
                        title: title,
                        subtitle: subtitle,
                        combinesAccessibility: false) {
            if busy || isOn == nil {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(L10n.t("正在与设备同步", "Syncing with device"))
            } else {
                Toggle("", isOn: binding)
                    .labelsHidden()
                    .disabled(disabled)
                    .accessibilityLabel(title)
            }
        }
    }
}
