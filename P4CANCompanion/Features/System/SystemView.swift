import SwiftUI
import UniformTypeIdentifiers

/// 「系统」页：连接设置、设备入网、固件 OTA、维护重置、日志导出。
struct SystemView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        NavigationStack {
            List {
                ConnectionSection()
                InterfaceSection()
                WiFiSection()
                OTASection()
                MaintenanceSection()
                DataBrowseSection()
                LogsSection()
                AboutSection()
            }
            .navigationTitle("系统")
            .overlay(alignment: .bottom) { ToastOverlay() }
        }
    }
}

// MARK: - 连接设置

private struct ConnectionSection: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var hostField = ""
    @State private var showsGuide = false

    var body: some View {
        Section {
            HStack {
                Text("设备地址")
                Spacer()
                Text(environment.phase == .online ? "在线" : "离线")
                    .foregroundStyle(environment.phase == .online ? Color.p4OK : Color.p4Err)
                    .accessibilityLabel("设备\(environment.phase == .online ? "在线" : "离线")")
            }
            .font(.subheadline)

            TextField("例如 192.168.4.1", text: $hostField)
                .keyboardType(.decimalPad)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onAppear { hostField = environment.host }
                .accessibilityLabel("设备 IP 地址输入框")

            Button("应用地址并连接") {
                environment.updateHost(hostField)
            }
            .disabled(hostField.trimmingCharacters(in: .whitespaces) == environment.host)

            Button("查看连接引导") { showsGuide = true }
        } header: {
            Label("连接", systemImage: "network")
        } footer: {
            Text("设备热点模式默认网关 192.168.4.1；设备加入家庭网络后请改为其新 IP。")
        }
        .sheet(isPresented: $showsGuide) { ConnectionGuideView() }
    }
}

// MARK: - Wi-Fi 配置（设备入网）

private struct InterfaceSection: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        Section {
            Toggle(isOn: Binding(
                get: { environment.bluetoothTabEnabled },
                set: { environment.setBluetoothTabEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("在标签栏显示「蓝牙」")
                    Text("S3XY 设备配对与动作绑定")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel("在标签栏显示蓝牙页")
            .accessibilityHint("关闭后底部只保留状态、功能、系统三页")
        } header: {
            Label("界面", systemImage: "slider.horizontal.3")
        } footer: {
            Text("蓝牙页平时用不到，默认隐藏；需要配对 S3XY 设备时在这里打开，就会出现在底部标签栏。")
        }
    }
}

private struct WiFiSection: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var ssid = ""
    @State private var password = ""

    var body: some View {
        Section {
            if let wifi = environment.wifiStatus?.objectValue {
                MetricRow(key: "ssid", value: wifi["ssid"] ?? .null)
                MetricRow(key: "networkState", value: wifi["networkState"] ?? .null)
                if let ip = wifi["ip"]?.stringValue, !ip.isEmpty {
                    MetricRow(key: "ip", value: .string(ip))
                }
                if let hosted = wifi["hostedWifiStarted"]?.boolValue {
                    MetricRow(key: "hostedWifiStarted", value: .bool(hosted))
                }
                if wifi["passwordIsDefault"]?.boolValue == true {
                    Label("设备 AP 密码仍为默认值，建议尽快修改", systemImage: "exclamationmark.shield")
                        .font(.footnote)
                        .foregroundStyle(.p4Warn)
                }
            } else {
                Text("暂无 Wi-Fi 状态")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            TextField("热点名称（SSID）", text: $ssid)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityLabel("热点名称输入框")
            SecureField("热点密码（8–63 位）", text: $password)
                .accessibilityLabel("热点密码输入框")

            Button("应用热点配置（/api/wifi/apply）") {
                Task { await environment.applyWiFi(ssid: ssid, password: password) }
            }
            .disabled(ssid.isEmpty || environment.isBusy)
        } header: {
            Label("设备热点（SoftAP）", systemImage: "wifi.router")
        } footer: {
            Text("固件只重建 SoftAP：SSID/密码生效后 IP 仍为 192.168.4.1。留空密码表示保持现有密码。")
        }
    }
}

// MARK: - 固件升级（OTA）

private struct OTASection: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var pickedURL: URL?
    @State private var showsImporter = false

    private var otaObject: [String: P4JSON]? { environment.otaStatus?.objectValue }

    var body: some View {
        Section {
            if let ota = otaObject {
                MetricRow(key: "stage", value: ota["stage"] ?? .null)
                MetricRow(key: "inProgress", value: ota["inProgress"] ?? .null)
                MetricRow(key: "receivedBytes", value: ota["receivedBytes"] ?? .null)
                MetricRow(key: "totalBytes", value: ota["totalBytes"] ?? .null)
                MetricRow(key: "attempt", value: ota["attempt"] ?? .null)
                if let error = ota["updateError"]?.stringValue, !error.isEmpty {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.p4Err)
                }
            }

            if let url = pickedURL {
                Label(url.lastPathComponent, systemImage: "doc.badge.arrow.up")
                    .font(.footnote)
                    .lineLimit(1)
                    .accessibilityLabel("已选择固件文件 \(url.lastPathComponent)")
            }

            Button {
                showsImporter = true
            } label: {
                Label("选择固件文件（.ino.bin）", systemImage: "folder.badge.plus")
            }
            .accessibilityHint("从文件 App 选择增量升级镜像")

            Button {
                upload()
            } label: {
                if environment.otaUploading {
                    Label("上传中…", systemImage: "arrow.up.circle.dotted")
                } else {
                    Label("开始上传", systemImage: "arrow.up.circle.fill")
                }
            }
            .disabled(pickedURL == nil || environment.otaUploading)
            .accessibilityHint("上传固件到设备网页升级入口，期间请保持连接且勿断电")

        } header: {
            Label("固件升级（OTA）", systemImage: "arrow.down.circle")
        } footer: {
            Text("只上传“应用升级版” .ino.bin（如 P4-CAN-Universal-v3.29.3-C6.ino.bin）。.ino.merged.bin 为 32MB 串口全量镜像，不可用于网页/App OTA。")
        }
        .fileImporter(
            isPresented: $showsImporter,
            allowedContentTypes: [.data],
            onCompletion: { result in
                if case .success(let url) = result {
                    pickedURL = url
                } else if case .failure(let error) = result {
                    environment.toast = P4Toast(message: "选择文件失败：\(error.localizedDescription)", style: .failure)
                }
            }
        )
    }

    private func upload() {
        guard let url = pickedURL else { return }
        Task {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                await environment.uploadFirmware(named: url.lastPathComponent, data: data)
                if environment.toast?.style == .success { pickedURL = nil }
            } catch {
                environment.toast = P4Toast(message: "读取文件失败：\(error.localizedDescription)", style: .failure)
            }
        }
    }
}

// MARK: - 维护与重置

private struct MaintenanceSection: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var destructiveAction: DestructiveAction?

    private enum DestructiveAction: String, Identifiable {
        case reboot = "重启设备"
        case reinitCAN = "重新初始化 CAN"
        case resetStats = "重置运行统计"
        case resetSettings = "重置设置（保留配对）"
        case factoryReset = "恢复出厂设置"
        case resetNVSKeepBLE = "重置 NVS（保留蓝牙）"
        var id: String { rawValue }

        var path: String {
            switch self {
            case .reboot: return P4Route.systemReboot
            case .reinitCAN: return P4Route.systemReinitCAN
            case .resetStats: return P4Route.systemResetStats
            case .resetSettings: return P4Route.systemResetSettings
            case .factoryReset: return P4Route.systemFactoryReset
            case .resetNVSKeepBLE: return P4Route.systemResetNVSKeepBLE
            }
        }

        var warning: String {
            switch self {
            case .reboot: return "设备将重启，连接会短暂中断。"
            case .reinitCAN: return "CAN 总线将重新初始化，期间功能短暂不可用。"
            case .resetStats: return "运行统计与计数器将清零，不可恢复。"
            case .resetSettings: return "功能设置将恢复默认，蓝牙配对保留。"
            case .factoryReset: return "⚠️ 全部设置、配对与统计数据将被清除，恢复出厂状态！"
            case .resetNVSKeepBLE: return "NVS 将重建，仅保留蓝牙配对数据，其余全部丢失！"
            }
        }
    }

    var body: some View {
        Section {
            Button("重启设备") { destructiveAction = .reboot }
            Button("重新初始化 CAN") { destructiveAction = .reinitCAN }
            Button("重置运行统计") { destructiveAction = .resetStats }
            Button("重置设置（保留配对）") { destructiveAction = .resetSettings }
            Button("恢复出厂设置") { destructiveAction = .factoryReset }
                .foregroundStyle(.p4Err)
            Button("重置 NVS（保留蓝牙）") { destructiveAction = .resetNVSKeepBLE }
                .foregroundStyle(.p4Err)
        } header: {
            Label("维护与重置", systemImage: "wrench.and.screwdriver")
        }
        .confirmationDialog(
            destructiveAction?.rawValue ?? "",
            isPresented: Binding(
                get: { destructiveAction != nil },
                set: { if !$0 { destructiveAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("确认执行", role: .destructive) {
                if let action = destructiveAction {
                    Task { await environment.command(action.rawValue, path: action.path) }
                }
                destructiveAction = nil
            }
            Button("取消", role: .cancel) { destructiveAction = nil }
        } message: {
            Text(destructiveAction?.warning ?? "")
        }
    }
}

// MARK: - 数据浏览

private struct DataBrowseSection: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        Section {
            NavigationLink {
                LiveDataView()
            } label: {
                HStack {
                    Label("全部数据（原始字段）", systemImage: "list.bullet.rectangle")
                    Spacer()
                    Text("\(AppEnvironment.browseEndpoints.count) 个端点")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            NavigationLink {
                NetworkLogView()
            } label: {
                Label("网络日志（抓包调试）", systemImage: "waveform.path.ecg.rectangle")
            }
        } header: {
            Label("数据浏览", systemImage: "magnifyingglass")
        } footer: {
            Text("按端点查看固件 /api/* 的全部字段，支持搜索（can1 / can2 / can3 / gear / das 等）。")
        }
    }
}

// MARK: - 日志导出

private struct LogsSection: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var exportingLog: P4LogFile?
    @State private var exportedURL: URL?
    @State private var exportFailed: String?

    var body: some View {
        Section {
            ForEach(P4LogFile.all) { log in
                Button {
                    export(log)
                } label: {
                    HStack {
                        Label(log.title, systemImage: "doc.text.magnifyingglass")
                            .foregroundStyle(.primary)
                        Spacer()
                        if exportingLog?.id == log.id {
                            ProgressView()
                                .accessibilityLabel("正在导出\(log.title)")
                        } else {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(.tint)
                                .accessibilityLabel("导出并分享")
                        }
                    }
                }
                .disabled(exportingLog != nil)
            }
            if let failed = exportFailed {
                Label(failed, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.p4Err)
            }
        } header: {
            Label("日志与跟踪导出", systemImage: "list.bullet.rectangle")
        } footer: {
            Text("下载设备端 CSV（启动诊断、CAN A/B 发送跟踪、S3XY、DMS、研究捕获），完成后可分享或存储到文件 App。")
        }
        .sheet(item: Binding(
            get: { exportedURL.map { ShareURLWrapper(url: $0) } },
            set: { if $0 == nil { exportedURL = nil } }
        )) { wrapper in
            ActivityShareSheet(items: [wrapper.url])
        }
    }

    private func export(_ log: P4LogFile) {
        exportingLog = log
        exportFailed = nil
        Task {
            do {
                exportedURL = try await environment.exportLogFile(log)
            } catch {
                exportFailed = AppEnvironment.friendly(error)
            }
            exportingLog = nil
        }
    }
}

private struct ShareURLWrapper: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// UIActivityViewController 的 SwiftUI 包装（Modal 提供系统滑动关闭路径）。
private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - 关于

private struct AboutSection: View {
    var body: some View {
        Section {
            LabeledContent("App 版本", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.2")
            LabeledContent("适配固件", value: "P4-CAN Universal Unlock v3.29.3")
            LabeledContent("接口契约", value: "web_api.h（query 参数）")
            LabeledContent("连接方式", value: "本地 HTTP（192.168.4.1）")
        } header: {
            Label("关于", systemImage: "info.circle")
        } footer: {
            Text("功能列表依据固件 v3.29.3 内嵌 API 路由与状态字段还原；个别参数含义以固件实际行为为准。")
        }
    }
}
