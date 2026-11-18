import SwiftUI

/// 「全部数据」页：直接浏览固件每个 /api/* 端点返回的全部字段。
///
/// 目的：设备网页上能看到的信息，App 里必须一条不少。
/// - 按端点分组展示全部标量字段（未知键名原样显示）；
/// - 嵌套对象/数组折叠为可展开的原始 JSON；
/// - 支持关键字搜索（如 canA、state、tx）；
/// - 可开启 3 秒自动刷新，手动下拉亦可刷新。
struct LiveDataView: View {
    @EnvironmentObject private var environment: AppEnvironment

    @State private var query = ""
    @State private var autoRefresh = true
    @State private var expandedEndpoints: Set<String> = [P4Route.snapshot, P4Route.systemStats]

    var body: some View {
        List {
            controlsSection
            if query.isEmpty {
                groupedContent
            } else {
                searchContent
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("全部数据")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: L10n.t("搜索字段，如 can1 / gear / das / state", "Search fields, e.g. can1 / gear / das / state"))
        .refreshable { await environment.loadAllEndpoints() }
        .overlay(alignment: .bottom) { ToastOverlay() }
        .task { await poll() }
    }

    // MARK: - 顶部控制区

    private var controlsSection: some View {
        Section {
            Toggle(isOn: $autoRefresh) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("自动刷新（3 秒）", "Auto refresh (3 s)"))
                    Text("与设备网页使用同一批状态接口")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Button {
                Task { await environment.loadAllEndpoints() }
            } label: {
                HStack {
                    Label(L10n.t("立即刷新全部端点", "Refresh all endpoints"), systemImage: "arrow.clockwise")
                    Spacer()
                    if environment.isScanningEndpoints {
                        ProgressView()
                            .accessibilityLabel("正在刷新")
                    }
                }
            }
            .disabled(environment.isScanningEndpoints)

            if let updated = environment.endpointsUpdatedAt {
                LabeledContent(
                    "最近同步",
                    value: updated.formatted(date: .omitted, time: .standard)
                )
                .font(.footnote)
            }
            LabeledContent(
                "端点数据",
                value: L10n.t("\(environment.endpointPayloads.count) 成功 / \(environment.endpointErrors.count) 失败", "\(environment.endpointPayloads.count) ok / \(environment.endpointErrors.count) failed")
            )
            .font(.footnote)
        } footer: {
            Text("这些原始字段来自固件 /api/*，与设备网页同源；搜索可快速定位字段。")
        }
    }

    // MARK: - 分组内容

    private var groupedContent: some View {
        ForEach(AppEnvironment.browseEndpoints, id: \.self) { path in
            Section {
                if let payload = environment.endpointPayloads[path] {
                    let scalars = payload.flatScalars
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { expandedEndpoints.contains(path) },
                            set: { isOn in
                                if isOn { expandedEndpoints.insert(path) }
                                else { expandedEndpoints.remove(path) }
                            }
                        )
                    ) {
                        if scalars.isEmpty {
                            Text("无可展示的标量字段")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(scalars, id: \.key) { entry in
                                MetricRow(key: entry.key, value: entry.value)
                            }
                        }
                        if hasNested(payload) {
                            DisclosureGroup(L10n.t("原始 JSON", "Raw JSON")) {
                                Text(payload.prettyText())
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            .font(.footnote)
                        }
                    } label: {
                        HStack {
                            Text(path)
                                .font(.system(.footnote, design: .monospaced))
                            Spacer()
                            Text(L10n.t("\(scalars.count) 字段", "\(scalars.count) fields"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    HStack {
                        Text(path)
                            .font(.system(.footnote, design: .monospaced))
                        Spacer()
                        Text(environment.endpointErrors[path] ?? "未请求")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        }
    }

    // MARK: - 搜索结果

    private var searchContent: some View {
        let matches = searchMatches
        return Group {
            if matches.isEmpty {
                Section {
                    Text(L10n.t("没有匹配「\(query)」的字段", "No field matches “\(query)”"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section(L10n.t("匹配 \(matches.count) 个字段", "\(matches.count) matching fields")) {
                    ForEach(matches, id: \.id) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            MetricRow(key: item.key, value: item.value)
                            Text(item.path)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    private struct Match: Identifiable {
        let path: String
        let key: String
        let value: P4JSON
        var id: String { path + "#" + key }
    }

    private var searchMatches: [Match] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return [] }
        var results: [Match] = []
        for path in AppEnvironment.browseEndpoints {
            guard let payload = environment.endpointPayloads[path] else { continue }
            for entry in payload.flatScalars {
                let label = P4KeyLocalization.label(for: entry.key)
                if entry.key.lowercased().contains(needle) || label.contains(query) {
                    results.append(Match(path: path, key: entry.key, value: entry.value))
                }
            }
        }
        return Array(results.prefix(300))
    }

    private func hasNested(_ payload: P4JSON) -> Bool {
        payload.objectValue?.contains { _, value in
            value.objectValue != nil || value.arrayValue != nil
        } ?? false
    }

    // MARK: - 轮询

    private func poll() async {
        await environment.loadAllEndpoints()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3))
            if autoRefresh {
                await environment.loadAllEndpoints()
            }
        }
    }
}
