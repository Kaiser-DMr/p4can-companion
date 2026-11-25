import SwiftUI

/// 设置 → 诊断 / 恢复：对应固件网页 `panelDiag`。
///
/// 只展示设备真实上报的字段；缺失就显示「—」，不补默认值。
/// 恢复动作与网页一致：重置统计、硬重初始化三路 CAN、导出启动抓包。
struct DiagnosticsView: View {
    @EnvironmentObject private var environment: AppEnvironment

    /// 与首页 / 数据浏览共用同一份 system stats。
    private var stats: P4JSON? { environment.endpointValue(P4Route.systemStats) }
    @State private var busy = false
    @State private var confirmsReinit = false
    @State private var exportURL: URL?
    @State private var exportError: String?

    private var object: [String: P4JSON] { stats?.objectValue ?? [:] }

    private static let systemKeys = [
        "fwVersion", "canHarness", "canPins",
        "uptimeS", "freeHeap", "minFreeHeap", "largestHeapBlock",
        "networkState", "hostedWifiStarted",
    ]

    var body: some View {
        List {
            Section {
                if let stats {
                    ForEach(Self.systemKeys.filter { object[$0] != nil }, id: \.self) { key in
                        MetricRow(key: key, value: object[key] ?? .null)
                    }
                    if Self.systemKeys.allSatisfy({ object[$0] == nil }) {
                        Text(L10n.t("设备未上报系统统计字段", "Device did not report system stats"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    SkeletonRows(count: 5)
                }
            } header: {
                Text(L10n.t("系统", "System"))
            }

            ForEach(busIndexes, id: \.self) { index in
                busSection(index)
            }

            Section {
                Button {
                    Task { await command(L10n.t("重置统计", "Reset stats"), path: P4Route.systemResetStats) }
                } label: {
                    Label(L10n.t("重置运行统计", "Reset Stats"), systemImage: "arrow.counterclockwise")
                }
                Button(role: .destructive) {
                    confirmsReinit = true
                } label: {
                    Label(L10n.t("硬重初始化全部 CAN", "Hard Reinitialize CAN"), systemImage: "bolt.trianglebadge.exclamationmark")
                }
                Button {
                    exportBootCapture()
                } label: {
                    Label(L10n.t("导出启动抓包 CSV", "Boot Capture CSV"), systemImage: "square.and.arrow.up")
                }
                Button {
                    exportSystemStats()
                } label: {
                    Label(L10n.t("导出系统统计 JSON", "System Stats JSON"), systemImage: "curlybraces")
                }
                if let exportError {
                    Label(exportError, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.p4Err)
                }
            } header: {
                Text(L10n.t("恢复动作", "Recovery"))
            } footer: {
                Text(L10n.t("硬重初始化会让全部 CAN 短暂中断；仅在总线持续 BUS OFF 或计数异常时使用。",
                            "Hard reinitialization briefly interrupts all three CAN buses. Use only after persistent BUS OFF or abnormal counters."))
            }

            Section {
                DisclosureGroup(L10n.t("全部系统字段", "All system fields")) {
                    let scalars = (stats?.flatScalars ?? []).filter { entry in
                        if case .object = entry.value { return false }
                        if case .array = entry.value { return false }
                        return true
                    }
                    ForEach(scalars, id: \.key) { entry in
                        MetricRow(key: entry.key, value: entry.value)
                    }
                }
                .font(.footnote)
            }

            Section {
                NavigationLink {
                    LiveDataView()
                } label: {
                    Label(L10n.t("按端点浏览全部数据", "Browse all endpoints"),
                          systemImage: "list.bullet.rectangle")
                }
            }
        }
        .listStyle(.insetGrouped)
        .p4ListStyle()
        .navigationTitle(L10n.t("诊断 / 恢复", "Diagnostics / Recovery"))
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) { ToastOverlay() }
        .refreshable { await load() }
        .task { await load() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                // OTA / 批量扫描期间让出连接，避免抢单线程固件。
                if environment.isPollingPaused { continue }
                await load()
            }
        }
        .confirmationDialog(
            L10n.t("硬重初始化全部 CAN？", "Hard reinitialize all CAN buses?"),
            isPresented: $confirmsReinit,
            titleVisibility: .visible
        ) {
            Button(L10n.t("确认执行", "Confirm"), role: .destructive) {
                Task { await command(L10n.t("硬重初始化 CAN", "Hard reinitialize CAN"), path: P4Route.systemReinitCAN) }
            }
            Button(L10n.t("取消", "Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t("CAN 1 / 2 / 3 会重新初始化，功能注入与接收会短暂中断。",
                        "CAN 1 / 2 / 3 will reinitialize; injection and reception are briefly interrupted."))
        }
        .sheet(item: Binding(
            get: { exportURL.map { DiagnosticsExport(url: $0) } },
            set: { if $0 == nil { exportURL = nil } }
        )) { item in
            DiagnosticsShareSheet(items: [item.url])
        }
    }

    private var busIndexes: [Int] {
        (1...3).filter { object["can\($0)Name"] != nil || object["can\($0)State"] != nil }
    }

    @ViewBuilder
    private func busSection(_ index: Int) -> some View {
        let name = object["can\(index)Name"]?.stringValue ?? "CAN \(index)"
        let keys = [
            "can\(index)State", "can\(index)Ready", "can\(index)TrafficOnline",
            "can\(index)RxCount", "can\(index)TxAccepted", "can\(index)TxRejected",
            "can\(index)BusOffCount", "can\(index)TrafficAgeMs",
        ]
        let present = keys.filter { object[$0] != nil }
        Section {
            if present.isEmpty {
                Text(L10n.t("该总线未上报状态", "No status for this bus"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(present, id: \.self) { key in
                    MetricRow(key: key, value: object[key] ?? .null)
                }
            }
        } header: {
            Text("CAN \(index) · \(name)")
        }
    }

    private func load() async {
        await environment.refreshEndpoint(P4Route.systemStats)
    }

    private func command(_ label: String, path: String) async {
        busy = true
        await environment.command(label, path: path)
        await load()
        busy = false
    }

    private func exportBootCapture() {
        Task {
            do {
                let data = try await environment.api.downloadData(P4Route.bootCaptureCSV)
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("p4can-boot-capture.csv")
                try data.write(to: url, options: .atomic)
                exportURL = url
            } catch {
                exportError = AppEnvironment.friendly(error)
            }
        }
    }

    private func exportSystemStats() {
        Task {
            do {
                let data = try await environment.api.downloadData(P4Route.systemStats)
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("p4can-system-stats.json")
                try data.write(to: url, options: .atomic)
                exportURL = url
            } catch {
                exportError = AppEnvironment.friendly(error)
            }
        }
    }
}

private struct DiagnosticsExport: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct DiagnosticsShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
