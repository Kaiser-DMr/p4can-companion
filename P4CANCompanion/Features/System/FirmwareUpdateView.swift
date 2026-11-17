import SwiftUI
import UniformTypeIdentifiers

/// 设置 → 固件升级：对应固件网页 `panelOta`。
///
/// 只接受「应用升级版」`.ino.bin`；`.ino.merged.bin` 是串口全量镜像，不能用于 OTA。
struct FirmwareUpdateView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var pickedURL: URL?
    @State private var showsImporter = false

    private var otaObject: [String: P4JSON]? { environment.otaStatus?.objectValue }

    var body: some View {
        List {
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
                } else {
                    SkeletonRows(count: 3)
                }
            } header: {
                Label(L10n.t("当前升级状态", "Update status"), systemImage: "arrow.down.circle")
            }

            Section {
                if let url = pickedURL {
                    Label(url.lastPathComponent, systemImage: "doc.badge.arrow.up")
                        .font(.footnote)
                        .lineLimit(1)
                        .accessibilityLabel(L10n.t("已选择固件 \(url.lastPathComponent)",
                                                   "Selected firmware \(url.lastPathComponent)"))
                }
                Button {
                    showsImporter = true
                } label: {
                    Label(L10n.t("选择固件文件（.ino.bin）", "Choose firmware (.ino.bin)"),
                          systemImage: "folder.badge.plus")
                }
                Button {
                    upload()
                } label: {
                    if environment.otaUploading {
                        Label(L10n.t("上传中…", "Uploading…"), systemImage: "arrow.up.circle.dotted")
                    } else {
                        Label(L10n.t("上传并刷写", "Upload & Flash"), systemImage: "arrow.up.circle.fill")
                    }
                }
                .disabled(pickedURL == nil || environment.otaUploading)
            } header: {
                Label(L10n.t("应用镜像", "Application image"), systemImage: "doc.badge.arrow.up")
            } footer: {
                Text(L10n.t("上传成功后设备会自动重启。请保持连接，刷写过程中不要断电。",
                            "P4-CAN reboots automatically after a successful flash. Keep the connection alive and do not cut power."))
            }
        }
        .listStyle(.insetGrouped)
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
