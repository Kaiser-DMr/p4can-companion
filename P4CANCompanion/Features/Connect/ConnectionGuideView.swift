import SwiftUI
import UIKit

/// 首次连接引导：分步说明加入设备热点与本地网络权限。
struct ConnectionGuideView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: Theme.spacing(2)) {
                        Label("第 1 步 · 加入设备热点", systemImage: "wifi")
                            .font(.headline)
                        Text(
                            "P4-CAN 设备会广播自己的 Wi-Fi 热点。请前往系统设置，加入设备热点网络（名称以 P4 开头，密码见设备标签或说明书）。"
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        Button("打开无线局域网设置") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .accessibilityHint("跳转到系统设置的应用无线网络页面")
                    }
                    .padding(.vertical, Theme.spacing(1))
                }

                Section {
                    VStack(alignment: .leading, spacing: Theme.spacing(2)) {
                        Label("第 2 步 · 允许本地网络访问", systemImage: "network.badge.shield.half.filled")
                            .font(.headline)
                        Text(
                            "回到 App 后，首次访问设备会弹出“允许 P4管家查找并连接到本地网络设备”，请点允许。App 不会连接互联网。"
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: Theme.spacing(2)) {
                        Label("第 3 步 · 验证连接", systemImage: "checkmark.seal")
                            .font(.headline)
                        HStack {
                            Text("设备地址")
                            Spacer()
                            Text(environment.host)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        .font(.subheadline)
                        Button {
                            Task { await environment.refreshOnce() }
                        } label: {
                            Label("立即测试连接", systemImage: "bolt.horizontal")
                        }
                        if case .offline(let reason) = environment.phase {
                            Label(reason, systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                                .foregroundStyle(.p4Err)
                        }
                        if environment.isOnline {
                            Label("设备已连接", systemImage: "checkmark.circle")
                                .font(.footnote)
                                .foregroundStyle(.p4OK)
                        }
                    }
                }

                Section("设备已加入家庭 Wi-Fi？") {
                    Text(
                        "若设备已通过“系统 → Wi-Fi 配置”加入家庭网络，请在该页把设备地址改为设备在新网络中的 IP。"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("连接引导")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                        .accessibilityLabel("关闭连接引导")
                }
            }
        }
    }
}
