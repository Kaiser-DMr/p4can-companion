import SwiftUI

/// 「功能」页：搜索 + 分类导航 + 模块列表。
///
/// 设计目标（v2.3）：
/// - 19 个模块不再是一条长列表：顶部「分类条」一屏内切换，列表最多 6 项；
/// - 顶部搜索框：按名称/说明/关键词全局搜索，边输边过滤；
/// - 搜索时隐藏分类条，避免两套筛选逻辑打架；清空即回到原分类；
/// - 「全部」保留分组标题，单分类只显示该组；19 个模块与详情页完全不变。
struct FeaturesView: View {
    @EnvironmentObject private var environment: AppEnvironment

    /// 详情页导航栈（DEBUG 下可由 P4CAN_MODULE 直接深链到某个模块）。
    @State private var path: [String] = []
    /// nil = 全部
    @State private var selectedSection: FeatureModule.Section?
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var totalCount: Int { FeatureCatalog.modules.count }

    private func count(in section: FeatureModule.Section) -> Int {
        FeatureCatalog.modules(in: section).count
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool { !trimmedQuery.isEmpty }

    /// 搜索范围：名称 / 摘要 / 模块 id / 分类名，全部小写匹配（中英文都可用）。
    private var searchResults: [FeatureModule] {
        let needle = trimmedQuery.lowercased()
        guard !needle.isEmpty else { return [] }
        return FeatureCatalog.modules.filter { module in
            module.title.lowercased().contains(needle)
                || module.summary.lowercased().contains(needle)
                || module.id.lowercased().contains(needle)
                || module.section.rawValue.lowercased().contains(needle)
        }
    }

    private var summaryText: String {
        if isSearching {
            return "搜索「\(trimmedQuery)」· \(searchResults.count) 个结果"
        }
        if let section = selectedSection {
            return "\(section.rawValue) · \(count(in: section)) 个模块"
        }
        return "全部 · \(totalCount) 个模块"
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                header
                Divider().opacity(0.5)
                moduleList
            }
            .background(Color.p4Background)
            .navigationTitle("功能")
            .navigationDestination(for: String.self) { moduleID in
                if let module = FeatureCatalog.modules.first(where: { $0.id == moduleID }) {
                    FeatureDetailView(module: module)
                }
            }
            .overlay(alignment: .bottom) { ToastOverlay() }
        }
        .task {
            #if DEBUG
            // 本地联调：SIMCTL_CHILD_P4CAN_MODULE=ulc 启动即进入该模块详情
            if path.isEmpty,
               let moduleID = ProcessInfo.processInfo.environment["P4CAN_MODULE"],
               FeatureCatalog.modules.contains(where: { $0.id == moduleID }) {
                path = [moduleID]
            }
            // 本地联调：SIMCTL_CHILD_P4CAN_CATEGORY=实验室功能 预选分类
            if let raw = ProcessInfo.processInfo.environment["P4CAN_CATEGORY"],
               let section = FeatureModule.Section.allCases.first(where: { $0.rawValue == raw }) {
                selectedSection = section
            }
            // 本地联调：SIMCTL_CHILD_P4CAN_SEARCH=限速 预填搜索
            if let raw = ProcessInfo.processInfo.environment["P4CAN_SEARCH"] {
                query = raw
            }
            #endif
        }
    }

    // MARK: - 顶部：搜索 + 分类

    private var header: some View {
        VStack(spacing: Theme.spacing(1)) {
            searchField
            if !isSearching {
                categoryRail
                    .transition(.opacity)
            }
            Text(summaryText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.spacing(2))
                .accessibilityLabel(summaryText)
        }
        .padding(.top, Theme.spacing(1))
        .padding(.bottom, Theme.spacing(1))
        .background(Color.p4Background)
        .animation(.snappy(duration: 0.2), value: isSearching)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
            TextField("搜索模块（如 踏板 / TLSSC / 限速）", text: $query)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit { searchFocused = false }
                .accessibilityLabel("搜索功能模块")
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
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, Theme.spacing(1.5))
        .padding(.vertical, 9)
        .p4Glass(cornerRadius: Theme.Radius.tile)
        .padding(.horizontal, Theme.spacing(2))
    }

    /// 分类筛选条：SwiftPieces 的 FilterRail（液态玻璃胶囊 + 滑动指示 + 计数）。
    private var categoryRail: some View {
        FilterRail(
            options: ["全部"] + FeatureModule.Section.allCases.map(\.rawValue),
            selection: Binding(
                get: { selectedSection.map { [$0.rawValue] } ?? ["全部"] },
                set: { newValue in
                    if let raw = newValue.first,
                       let section = FeatureModule.Section(rawValue: raw) {
                        guard selectedSection != section else { return }
                        Haptics.impact()
                        withAnimation(.snappy(duration: 0.22)) { selectedSection = section }
                    } else if selectedSection != nil {
                        Haptics.impact()
                        withAnimation(.snappy(duration: 0.22)) { selectedSection = nil }
                    }
                }
            ),
            counts: categoryCounts,
            style: FilterRail.Style(indicator: .p4Info, onIndicator: .white, chipHeight: 36)
        )
        .accessibilityLabel("功能分类")
    }

    private var categoryCounts: [String: Int] {
        var counts: [String: Int] = ["全部": totalCount]
        for section in FeatureModule.Section.allCases {
            counts[section.rawValue] = count(in: section)
        }
        return counts
    }

    // MARK: - 列表

    private var moduleList: some View {
        List {
            if !environment.isOnline {
                Section {
                    Label("设备未连接，以下状态为最近一次数据", systemImage: "wifi.slash")
                        .font(.footnote)
                        .foregroundStyle(.p4Err)
                }
            }

            if isSearching {
                if searchResults.isEmpty {
                    emptySearchSection
                } else {
                    Section {
                        ForEach(searchResults) { module in
                            moduleRow(module)
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Label("搜索结果", systemImage: "magnifyingglass")
                                .font(.subheadline.weight(.semibold))
                            Text("\(searchResults.count)")
                                .font(.caption2.weight(.semibold))
                                .monospacedDigit()
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Color.primary.opacity(0.08), in: Capsule())
                            Spacer()
                        }
                    }
                }
            } else if let section = selectedSection {
                Section {
                    ForEach(FeatureCatalog.modules(in: section)) { module in
                        moduleRow(module)
                    }
                } header: {
                    sectionHeader(section)
                }
            } else {
                ForEach(FeatureModule.Section.allCases, id: \.rawValue) { section in
                    Section {
                        ForEach(FeatureCatalog.modules(in: section)) { module in
                            moduleRow(module)
                        }
                    } header: {
                        sectionHeader(section)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
    }

    private var emptySearchSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.spacing(1)) {
                Label("没有匹配的模块", systemImage: "magnifyingglass")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Text("试试更短的关键词，例如「NAG」「踏板」「TLSSC」「限速」。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("清除搜索") {
                    Haptics.impact()
                    query = ""
                }
                .font(.footnote.weight(.medium))
            }
            .padding(.vertical, Theme.spacing(1))
        }
    }

    private func sectionHeader(_ section: FeatureModule.Section) -> some View {
        HStack(spacing: 6) {
            Label(section.rawValue, systemImage: section.symbol)
                .font(.subheadline.weight(.semibold))
            Text("\(count(in: section))")
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Color.primary.opacity(0.08), in: Capsule())
            Spacer()
        }
    }

    private func moduleRow(_ module: FeatureModule) -> some View {
        NavigationLink(value: module.id) {
            FeatureRow(module: module, features: environment.featuresStatus)
        }
    }
}

private struct FeatureRow: View {
    let module: FeatureModule
    let features: P4JSON?

    private var supportLabel: String? {
        guard let key = module.supportKey, let value = features?[key]?.boolValue else { return nil }
        return value ? "支持" : "当前车型不支持"
    }

    var body: some View {
        HStack(spacing: Theme.spacing(1.5)) {
            Image(systemName: module.icon)
                .foregroundStyle(.tint)
                .frame(width: 30, height: 30)
                .background(Color.p4Tile, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(module.title)
                    .font(.body.weight(.medium))
                Text(module.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: Theme.spacing(1))
            if let support = supportLabel {
                StatusChip(
                    text: support == "支持" ? "支持" : "不支持",
                    systemImage: support == "支持" ? "checkmark" : "minus",
                    tone: support == "支持" ? .ok : .warn
                )
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
