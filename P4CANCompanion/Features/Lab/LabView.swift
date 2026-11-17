import SwiftUI

/// 「实验室」页：仅在 LAB 总开关启用后出现在标签栏。
///
/// 排序与固件网页的 LAB 分区一致：
/// LAB 总开关 → R79 AP 控制 → 召唤心跳 → 自动变道 (ALC) → 主驾车窗 → CAN 研究捕获。
struct LabView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var path: [String] = []

    private var modules: [FeatureModule] {
        FeatureCatalog.modules(in: .lab)
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    ForEach(modules) { module in
                        NavigationLink(value: module.id) {
                            LabRow(module: module)
                        }
                    }
                } footer: {
                    Text(L10n.t("实验室功能会直接改写 CAN 报文，仅在理解风险后使用；车辆需处于驻车或封闭场地。",
                                "Lab features rewrite CAN frames directly. Use only when you understand the risk, parked or on closed roads."))
                        .font(.footnote)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L10n.t("实验室", "Lab"))
            .navigationDestination(for: String.self) { moduleID in
                if moduleID == "modeh" {
                    ModeHView()
                } else if let module = modules.first(where: { $0.id == moduleID }) {
                    FeatureDetailView(module: module)
                }
            }
            .overlay(alignment: .bottom) { ToastOverlay() }
        }
        .task {
            #if DEBUG
            if path.isEmpty,
               let moduleID = ProcessInfo.processInfo.environment["P4CAN_MODULE"],
               modules.contains(where: { $0.id == moduleID }) {
                path = [moduleID]
            }
            #endif
        }
    }
}

private struct LabRow: View {
    let module: FeatureModule

    var body: some View {
        HStack(spacing: Theme.spacing(1.5)) {
            Image(systemName: module.icon)
                .foregroundStyle(.tint)
                .frame(width: 30, height: 30)
                .background(Color.p4Tile, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(module.localizedTitle)
                    .font(.body.weight(.medium))
                Text(module.localizedSummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: Theme.spacing(1))
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
