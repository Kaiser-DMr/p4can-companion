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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
        FeatureCatalog.modules.filter { module in
            guard module.id != "profile" else { return false }
            guard FeatureSupport.supports(module.id, family: environment.deviceFamily) else { return false }
            // v3.35.2 起官方固件移除了爆闪接口：探测到 404 后不再展示这两个入口。
            if module.id == "headlight" || module.id == "rearFog" {
                return environment.strobeSupported != false
            }
            if module.id == "lighting" {
                // 3.35.2 起先展示入口；3.35.2 上点进去会明确提示需要 3.35.3，
                // 而不是整行消失让人以为 App 没更新。
                return environment.newFeaturesSupported == true
            }
            if ["devTest", "summonVersion"].contains(module.id) {
                return environment.v356Supported == true
            }
            if ["preheat", "fsd", "smartShift", "r79Timing"].contains(module.id) {
                return environment.newFeaturesSupported == true
            }
            return true
        }
    }

    /// 全量行（含已置顶的）：搜索、置顶解析与深链滚动共用。
    private var allEntries: [Entry] {
        modules.map { Entry(id: $0.id, kind: .module($0)) }
            + [Entry(id: "s3xy", kind: .s3xy)]
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
            }
        }
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
                    destination(for: module)
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
        // 用垂直内边距 + 最小高度代替固定高度：大字号下输入框随文字长高。
        .padding(.vertical, Theme.spacing(1))
        .frame(minHeight: 42)
        .background(Capsule().fill(Color(uiColor: .tertiarySystemFill)))
        .overlay(
            Capsule()
                .strokeBorder(Color.accentColor.opacity(searchFocused ? 0.5 : 0), lineWidth: 1)
                .animation(.easeOut(duration: 0.15), value: searchFocused)
        )
        .contentShape(Capsule())
        .onTapGesture { searchFocused = true }
        .padding(.horizontal, Theme.spacing(2))
    }

    // MARK: - 列表

    /// 两列圆角卡片：普通字号每行两张，辅助功能字号退化为单列，避免文字被压扁。
    private var gridColumns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: Theme.spacing(1.5), alignment: .top),
                     count: count)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.spacing(3.5)) {
                    if isSearching {
                        if searchResults.isEmpty {
                            emptySearchCard
                        } else {
                            sectionBlock(
                                title: L10n.t("搜索结果", "Results"),
                                count: searchResults.count,
                                entries: searchResults
                            )
                        }
                    } else {
                        if !pinnedEntries.isEmpty {
                            sectionBlock(
                                title: L10n.t("常用", "Pinned"),
                                count: pinnedEntries.count,
                                entries: pinnedEntries,
                                footer: L10n.t("长按任意卡片可置顶或取消（最多 \(FeaturePinStore.maxPins) 个）。",
                                               "Long-press a card to pin or unpin it (up to \(FeaturePinStore.maxPins)).")
                            )
                        }
                        ForEach(groups) { group in
                            sectionBlock(
                                title: L10n.t(group.section.rawValue, group.section.englishName),
                                count: group.entries.count,
                                entries: group.entries,
                                footer: sectionFooterText(for: group)
                            )
                        }
                    }
                }
                .padding(.horizontal, Theme.spacing(2))
                .padding(.top, Theme.spacing(1))
                // 底部留出浮动标签栏的高度，最后一行卡片不会被挡住。
                .padding(.bottom, Theme.spacing(12))
            }
            .scrollDismissesKeyboard(.immediately)
            .background(Color.p4Background)
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

    /// 一个分组：标题 + 两列卡片 + 可选脚注。
    private func sectionBlock(title: String,
                              count: Int,
                              entries: [Entry],
                              footer: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing(1.25)) {
            sectionHeader(title: title, count: count)
                .padding(.horizontal, Theme.spacing(0.5))

            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: Theme.spacing(1.5)) {
                ForEach(entries) { entry in
                    card(entry)
                        .id(entry.id)
                        .contextMenu { pinMenu(entry) }
                }
            }

            if let footer {
                Text(footer)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.spacing(0.5))
                    .padding(.top, 2)
            }
        }
    }

    /// 单张卡片：可导航的走 NavigationLink，内联开关的直接放 Toggle。
    @ViewBuilder
    private func card(_ entry: Entry) -> some View {
        switch entry.kind {
        case .module(let module):
            if module.id == "isa" {
                FeatureCard(
                    icon: module.icon,
                    title: module.localizedTitle,
                    subtitle: module.localizedSummary,
                    tint: module.section.tint,
                    toggle: $isaEnabled,
                    toggleBusy: busyID == module.id,
                    toggleDisabled: environment.isBusy
                ) { newValue in
                    submitInline(module.id, label: L10n.t("ISA 抑制", "ISA Suppression"),
                                 path: P4Route.isaSuppressionConfig, enabled: newValue)
                }
            } else if module.id == "dms" {
                FeatureCard(
                    icon: module.icon,
                    title: module.localizedTitle,
                    subtitle: module.localizedSummary,
                    tint: module.section.tint,
                    toggle: $dmsEnabled,
                    toggleBusy: busyID == module.id,
                    toggleDisabled: environment.isBusy
                ) { newValue in
                    submitInline(module.id, label: L10n.t("禁用驾驶员监控", "Driver Monitoring"),
                                 path: P4Route.dmsConfig, enabled: newValue)
                }
            } else {
                NavigationLink {
                    destination(for: module)
                } label: {
                    FeatureCard(
                        icon: module.icon,
                        title: module.localizedTitle,
                        subtitle: module.localizedSummary,
                        tint: module.section.tint,
                        badge: badge(for: module),
                        showsDisclosure: true
                    )
                }
                .buttonStyle(CardPressStyle())
            }

        case .s3xy:
            FeatureCard(
                icon: "gamecontroller.fill",
                title: L10n.t("S3XY", "S3XY"),
                subtitle: L10n.t("打开后底部出现「蓝牙」标签；用于 S3XY 配对与按键动作。",
                                 "Turns on S3XY buttons and shows the Bluetooth tab."),
                tint: P4Palette.purple,
                toggle: .constant(s3xyEnabled),
                toggleBusy: busyID == "s3xy",
                toggleDisabled: environment.featuresStatus == nil || environment.isBusy
            ) { newValue in
                setFeaturesGate("s3xy", label: "S3XY", path: P4Route.featuresS3XY, enabled: newValue)
            }
        }
    }

    /// 导航目的地（卡片点击与调试深链共用）：少数模块有专用页面，其余走通用详情页。
    @ViewBuilder
    private func destination(for module: FeatureModule) -> some View {
        switch module.id {
        case "headlight": HeadlightStrobeView()
        case "rearFog": RearFogStrobeView()
        case "preheat": PreheatView()
        case "fsd":
            if environment.deviceFamily == .t2can { T2FSDView() } else { FSDInjectionView() }
        case "smartShift": SmartShiftView()
        case "r79Timing": R79TimingView()
        case "lighting": LightingFeaturesView()
        case "devTest": DeveloperTestView()
        case "summonVersion": SummonVersionView()
        case "modeh": ModeHView()
        default: FeatureDetailView(module: module)
        }
    }

    /// 卡片右上角只显示需要提醒的状态：爆闪中 / 当前车型不支持。
    private func badge(for module: FeatureModule) -> FeatureCard.Badge? {
        if strobeActive[module.id] == true {
            return .init(text: L10n.t("爆闪中", "Strobing"),
                         systemImage: "light.beacon.max.fill",
                         tone: .ok)
        }
        if let key = module.supportKey,
           let value = environment.featuresStatus?[key]?.boolValue,
           value == false {
            return .init(text: L10n.t("不支持", "Unsupported"),
                         systemImage: "minus",
                         tone: .warn)
        }
        return nil
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
    private func sectionFooterText(for group: Group) -> String? {
        if group.section == .lighting {
            return L10n.t("灯光类功能会实际控制车辆灯光，请只在安全环境使用；爆闪期间可随时停止。",
                          "Lighting features drive the real lamps. Use them only in a safe environment; you can stop a strobe at any time.")
        }
        if group.id == groups.last?.id {
            return L10n.t("开关状态全部读取自设备；实验室工具已并入「功能」分组。长按卡片可置顶。",
                          "All switch states come from the device. Lab tools now sit in the Features group. Long-press a card to pin.")
        }
        return nil
    }

    /// 列表分组头：emoji + 标题 + 数量胶囊，和卡片左边缘对齐。
    /// 分组标题：系统分组列表的观感——纯文字、次要色、不加色点或胶囊徽标。
    private func sectionHeader(title: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
            Text("\(count)")
                .font(.subheadline.weight(.medium))
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

    private var emptySearchCard: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(1)) {
            Label(L10n.t("没有匹配的功能", "No matching features"), systemImage: "magnifyingglass")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text(L10n.t("试试更短的关键词，例如「灯光」「NAG」「踏板」「R79」。",
                        "Try a shorter keyword such as light, NAG, pedal or R79."))
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button(L10n.t("清除搜索", "Clear search")) {
                Haptics.impact()
                query = ""
            }
            .font(.footnote.weight(.medium))
        }
        .padding(Theme.spacing(2))
        .frame(maxWidth: .infinity, alignment: .leading)
        .p4CardSurface()
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
        guard environment.strobeSupported != false else {
            strobeActive = [:]
            return
        }
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

// MARK: - 功能卡片

/// 两列网格里的功能卡片：圆角底、图标 + 标题 + 说明，尾部放开关或状态徽标。
///
/// 与旧的整行列表相比，卡片把「图标 / 标题 / 说明 / 状态」压成纵向三层，
/// 在 2 列宽度下仍能放下两行标题与三行说明；辅助功能字号会自动退化为单列。
private struct FeatureCard: View {
    struct Badge {
        let text: String
        let systemImage: String
        let tone: P4Tone
    }

    let icon: String
    let title: String
    let subtitle: String
    var tint: Color? = nil
    var badge: Badge? = nil
    /// 非 nil 时右上角显示开关（ISA / DMS / S3XY）；nil 表示这是可导航卡片。
    var toggle: Binding<Bool?>? = nil
    var toggleBusy = false
    var toggleDisabled = false
    var showsDisclosure = false
    var onToggle: ((Bool) -> Void)? = nil

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.card - 2, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: Theme.spacing(0.75)) {
                ModuleIconTile(name: icon, size: Theme.Icon.tile, tint: tint)
                Spacer(minLength: 0)
                trailing
            }

            Spacer(minLength: Theme.spacing(1.5))

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if showsDisclosure {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.top, 3)
        }
        .padding(Theme.spacing(1.75))
        .frame(maxWidth: .infinity, minHeight: 138, alignment: .topLeading)
        .p4CardSurface(cornerRadius: Theme.Radius.card - 2)
        .contentShape(shape)
    }

    @ViewBuilder
    private var trailing: some View {
        if let toggle {
            if toggleBusy || toggle.wrappedValue == nil {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(L10n.t("正在与设备同步", "Syncing with device"))
            } else {
                Toggle("", isOn: Binding(
                    get: { toggle.wrappedValue ?? false },
                    set: { onToggle?($0) }
                ))
                .labelsHidden()
                .controlSize(.mini)
                .disabled(toggleDisabled)
                .accessibilityLabel(title)
            }
        } else if let badge {
            StatusChip(text: badge.text, systemImage: badge.systemImage, tone: badge.tone)
        }
    }
}

/// 卡片按压缩放：比系统默认的链接高亮更贴合圆角卡片。
private struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
