import SwiftUI
import UniformTypeIdentifiers

/// 设置 → 固件升级：对应固件网页 `panelOta`。
///
/// 只接受「应用升级版」`.ino.bin`；`.ino.merged.bin` 是串口全量镜像，不能用于 OTA。
struct FirmwareUpdateView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var pickedURL: URL?
    @State private var showsImporter = false
    @State private var confirmsUpload = false
    /// 选中包的指纹（大小 + SHA-256），用于展示与“和上次是否同一个包”的比对。
    @State private var pickedSize = 0
    @State private var pickedSHA = ""
    @State private var lastPackage: FirmwarePackage? = FirmwarePackageStore.load()

    private var otaObject: [String: P4JSON]? { environment.otaStatus?.objectValue }

    var body: some View {
        List {
            Section {
                LabeledContent(L10n.t("当前固件", "Firmware"), value: firmwareText)
                LabeledContent(L10n.t("连接", "Connection"),
                               value: environment.isOnline ? L10n.t("在线", "Online") : L10n.t("离线", "Offline"))
                NavigationLink {
                    FirmwareChangelogView()
                } label: {
                    Label(L10n.t("固件变更记录", "Firmware changelog"),
                          systemImage: "list.bullet.rectangle")
                }
            } header: {
                Label(L10n.t("设备", "Device"), systemImage: "cpu")
            }

            Section {
                if let ota = otaObject {
                    MetricRow(key: "stage", value: ota["stage"] ?? .null)
                    MetricRow(key: "inProgress", value: ota["inProgress"] ?? .null)
                    MetricRow(key: "receivedBytes", value: ota["receivedBytes"] ?? .null)
                    MetricRow(key: "totalBytes", value: ota["totalBytes"] ?? .null)
                    MetricRow(key: "attempt", value: ota["attempt"] ?? .null)
                    // 固件把文案放在 `error`（字符串），`updateError` 是数字错误码。
                    if let error = ota["error"]?.stringValue, !error.isEmpty {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.p4Err)
                    }
                } else {
                    SkeletonRows(count: 3)
                }
            } header: {
                Label(L10n.t("当前升级状态", "Update status"), systemImage: "arrow.down.circle")
            }

            if environment.otaUploadPhase != .idle {
                Section {
                    VStack(alignment: .leading, spacing: Theme.spacing(1)) {
                        HStack(spacing: Theme.spacing(1)) {
                            Text(phaseText)
                                .font(.subheadline.weight(.medium))
                            Spacer(minLength: Theme.spacing(1))
                            Text("\(Int(uploadProgress * 100))%")
                                .font(.subheadline.weight(.medium))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        SlimProgress(value: uploadProgress, tint: phaseTint)
                        Text(byteText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(phaseText)，\(byteText)")
                } header: {
                    Label(L10n.t("上传进度", "Upload progress"), systemImage: "arrow.up.circle")
                }
            }

            Section {
                if let url = pickedURL {
                    Label(url.lastPathComponent, systemImage: "doc.badge.arrow.up")
                        .font(.footnote)
                        .lineLimit(1)
                        .accessibilityLabel(L10n.t("已选择固件 \(url.lastPathComponent)",
                                                   "Selected firmware \(url.lastPathComponent)"))
                    LabeledContent(L10n.t("大小", "Size"), value: sizeText)
                    LabeledContent(L10n.t("SHA-256", "SHA-256")) {
                        Text(pickedSHA.isEmpty ? "—" : String(pickedSHA.prefix(12)))
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    if let last = lastPackage, last.sha256 == pickedSHA {
                        StatusChip(text: L10n.t("与上次刷写相同", "Same as last flash"), tone: .info)
                    }
                }
                Button {
                    showsImporter = true
                } label: {
                    Label(L10n.t("选择固件文件（.ino.bin）", "Choose firmware (.ino.bin)"),
                          systemImage: "folder.badge.plus")
                }
                .disabled(environment.otaUploading)
                Button {
                    confirmsUpload = true
                } label: {
                    if environment.otaUploading {
                        Label(environment.otaUploadPhase == .verifying
                              ? L10n.t("等待设备重启…", "Waiting for reboot…")
                              : L10n.t("上传中…", "Uploading…"),
                              systemImage: "arrow.up.circle.dotted")
                    } else {
                        Label(L10n.t("上传并刷写", "Upload & Flash"), systemImage: "arrow.up.circle.fill")
                    }
                }
                .disabled(pickedURL == nil || environment.otaUploading || !environment.isOnline)
            } header: {
                Label(L10n.t("应用镜像", "Application image"), systemImage: "doc.badge.arrow.up")
            } footer: {
                Text(L10n.t("上传成功后设备会自动重启，连接会短暂中断（属正常）。刷写过程中不要断电。",
                            "P4-CAN reboots after a successful flash, so the connection drops briefly — that is expected. Do not cut power."))
            }

            if let last = lastPackage {
                Section {
                    LabeledContent(L10n.t("文件", "File"), value: last.name)
                    LabeledContent(L10n.t("SHA-256", "SHA-256")) {
                        Text(last.shortSHA)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent(L10n.t("大小", "Size"), value: last.sizeText)
                    LabeledContent(L10n.t("刷写时间", "Flashed at"),
                                   value: last.flashedAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent(L10n.t("当时固件", "Firmware then"), value: last.deviceFirmware)
                } header: {
                    Label(L10n.t("上次刷写", "Last flash"), systemImage: "clock.arrow.circlepath")
                } footer: {
                    Text(L10n.t("刷写前先核对 SHA-256 前 12 位，能避免刷错包（同版本不同改动时尤其有用）。",
                                "Compare the first 12 hex chars before flashing to avoid picking the wrong build."))
                }
            }
        }
        .listStyle(.insetGrouped)
        .task {
            #if DEBUG
            // 本地联调：SIMCTL_CHILD_P4CAN_OTA_FILE=/path/app.ino.bin 启动后自动选择并上传，
            // 用于在没有真机的情况下跑通 OTA 全链路（mock 的 /update 会回同样的状态 JSON）。
            guard let path = ProcessInfo.processInfo.environment["P4CAN_OTA_FILE"] else { return }
            try? await Task.sleep(for: .seconds(1))
            let url = URL(fileURLWithPath: path)
            if let problem = validate(url) {
                environment.toast = P4Toast(message: problem, style: .failure)
                return
            }
            inspect(url)
            pickedURL = url
            if ProcessInfo.processInfo.environment["P4CAN_OTA_CONFIRM"] == "1" {
                confirmsUpload = true
            } else {
                upload()
            }
            #endif
        }
        .refreshable { await environment.refreshOnce() }
        .onChange(of: environment.otaUploadPhase) { _, phase in
            guard phase == .done, let url = pickedURL, !pickedSHA.isEmpty else { return }
            let record = FirmwarePackage(
                name: url.lastPathComponent,
                size: pickedSize,
                sha256: pickedSHA,
                flashedAt: Date(),
                deviceFirmware: firmwareText
            )
            FirmwarePackageStore.save(record)
            lastPackage = record
        }
        // 用 alert 而不是 confirmationDialog：iOS 26 的紧凑样式会把「取消」收成隐式手势，
        // 刷写这类不可逆操作必须两个按钮都明确可见。
        .alert(
            L10n.t("确认刷写固件？", "Flash firmware?"),
            isPresented: $confirmsUpload
        ) {
            Button(L10n.t("取消", "Cancel"), role: .cancel) {}
            Button(L10n.t("开始刷写", "Start flashing"), role: .destructive) { upload() }
        } message: {
            Text(confirmMessage)
        }
        .onAppear { environment.clearFinishedOTAProgress() }
        .navigationTitle(L10n.t("固件升级", "Firmware Update"))
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) { ToastOverlay() }
        .fileImporter(
            isPresented: $showsImporter,
            allowedContentTypes: [.data],
            onCompletion: { result in
                switch result {
                case .success(let url):
                    if let problem = validate(url) {
                        pickedURL = nil
                        environment.toast = P4Toast(message: problem, style: .failure)
                    } else {
                        inspect(url)
                        pickedURL = url
                    }
                case .failure(let error):
                    environment.toast = P4Toast(
                        message: L10n.t("选择文件失败：\(error.localizedDescription)",
                                        "Could not pick file: \(error.localizedDescription)"),
                        style: .failure
                    )
                }
            }
        )
    }

    private var sizeText: String {
        pickedSize > 0
            ? ByteCountFormatter.string(fromByteCount: Int64(pickedSize), countStyle: .file)
            : "—"
    }

    /// 读取大小并算 SHA-256；失败时清空指纹（不阻塞选包流程）。
    private func inspect(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            pickedSize = 0
            pickedSHA = ""
            return
        }
        pickedSize = data.count
        pickedSHA = FirmwarePackageStore.sha256Hex(of: data)
    }

    private var firmwareText: String {
        environment.systemStats?["fwVersion"]?.stringValue
            ?? environment.profileStatus?["fwVersion"]?.stringValue
            ?? "—"
    }

    private var confirmMessage: String {
        let name = pickedURL?.lastPathComponent ?? "—"
        let size = pickedURL
            .flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }
            .map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? "—"
        return L10n.t(
            "文件：\(name)（\(size)）\n当前固件：\(firmwareText)\n刷写过程中请勿断电；完成后设备会自动重启，连接会短暂中断。",
            "File: \(name) (\(size))\nCurrent firmware: \(firmwareText)\nDo not cut power while flashing. The device reboots afterwards and the link drops briefly."
        )
    }

    // MARK: - 上传状态

    private var uploadProgress: Double {
        switch environment.otaUploadPhase {
        case .idle: return 0
        case .uploading:
            guard environment.otaUploadTotal > 0 else { return 0 }
            return min(max(Double(environment.otaUploadSent) / Double(environment.otaUploadTotal), 0), 1)
        case .verifying, .done: return 1
        case .failed:
            // 失败时保留"发到哪一步"的比例，红色进度条比重置为 0 更有信息量。
            guard environment.otaUploadTotal > 0 else { return 0 }
            return min(max(Double(environment.otaUploadSent) / Double(environment.otaUploadTotal), 0), 1)
        }
    }

    private var phaseText: String {
        switch environment.otaUploadPhase {
        case .idle: return L10n.t("待机", "Idle")
        case .uploading: return L10n.t("正在上传固件", "Uploading firmware")
        case .verifying: return L10n.t("已发送，等待设备重启确认", "Sent — waiting for the device to reboot")
        case .done: return L10n.t("写入完成", "Written")
        case .failed: return L10n.t("未完成", "Not completed")
        }
    }

    private var phaseTint: Color {
        switch environment.otaUploadPhase {
        case .done: return .p4OK
        case .failed: return .p4Err
        case .verifying: return .p4Warn
        default: return .p4Info
        }
    }

    private var byteText: String {
        let sent = environment.otaUploadSent
        let total = environment.otaUploadTotal
        guard total > 0 else { return L10n.t("等待开始", "Waiting to start") }
        return L10n.t(
            "已发送 \(ByteCountFormatter.string(fromByteCount: Int64(sent), countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file))",
            "\(ByteCountFormatter.string(fromByteCount: Int64(sent), countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file)) sent"
        )
    }

    /// 只接受应用升级版 `.ino.bin`：拒绝 merged 全量镜像、非 bin 与超大文件。
    private func validate(_ url: URL) -> String? {
        let name = url.lastPathComponent.lowercased()
        guard name.hasSuffix(".bin") else {
            return L10n.t("只支持 .bin 固件文件", "Only .bin firmware files are supported")
        }
        guard !name.contains(".merged") else {
            return L10n.t("这是串口全量镜像（.merged.bin），不能用于 App 内 OTA；请选择应用升级版 .ino.bin",
                          "This is a full merged image (.merged.bin); choose the application .ino.bin instead")
        }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            return L10n.t("无法读取文件大小", "Could not read the file size")
        }
        guard size >= 64 * 1024 else {
            return L10n.t("固件文件过小，可能不是有效的应用镜像", "The file is too small to be a valid firmware image")
        }
        // ESP32 应用镜像以 0xE9 开头；不校验会把改名的图片/别的板子的镜像送进刷写。
        if let handle = try? FileHandle(forReadingFrom: url) {
            let magic = try? handle.read(upToCount: 1)
            try? handle.close()
            guard magic?.first == 0xE9 else {
                return L10n.t("这不是 ESP32 应用镜像（缺少 0xE9 标识），请选择 .ino.bin",
                              "Not an ESP32 application image (missing 0xE9 magic); choose the .ino.bin")
            }
        }
        guard size <= P4APIClient.maxFirmwareBytes else {
            return L10n.t("固件超过 8 MB，已拒绝", "Firmware exceeds 8 MB and was rejected")
        }
        return nil
    }

    private func upload() {
        guard let url = pickedURL else { return }
        if let problem = validate(url) {
            environment.toast = P4Toast(message: problem, style: .failure)
            pickedURL = nil
            return
        }
        Task {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                await environment.uploadFirmware(named: url.lastPathComponent, data: data)
                if environment.toast?.style == .success { pickedURL = nil }
            } catch {
                environment.toast = P4Toast(
                    message: L10n.t("读取文件失败：\(error.localizedDescription)",
                                    "Could not read file: \(error.localizedDescription)"),
                    style: .failure
                )
            }
        }
    }
}
