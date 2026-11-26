import SwiftUI

/// CAN 研究捕获的 A–D 标签：对应网页 `Save Labels`。
///
/// `POST /api/researchcapture/labels?slot=A&label=…`，标签 1–63 UTF-8 字节；
/// 标签只影响 CSV 的 segment 注释，不改变捕获内容。
struct ResearchLabelsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    private let slots = ["A", "B", "C", "D"]

    @State private var labels: [String: String] = ["A": "", "B": "", "C": "", "D": ""]
    @State private var loaded: [String: String] = [:]
    @State private var busy = false
    @State private var errorText: String?

    private var changes: [String] {
        slots.filter { slot in
            let value = labels[slot]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !value.isEmpty && value != loaded[slot]
        }
    }

    private var validationMessage: String? {
        for slot in slots {
            let value = labels[slot]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if value.isEmpty { continue }
            let bytes = value.utf8.count
            if bytes > 63 {
                return L10n.t("标签 \(slot) 超过 63 字节", "Label \(slot) exceeds 63 bytes")
            }
        }
        return nil
    }

    var body: some View {
        List {
            Section {
                ForEach(slots, id: \.self) { slot in
                    HStack {
                        Text(slot)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .leading)
                        TextField(L10n.t("标签 \(slot)", "Label \(slot)"),
                                  text: Binding(
                                    get: { labels[slot] ?? "" },
                                    set: { labels[slot] = $0 }
                                  ))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .disabled(busy)
                    }
                }
            } header: {
                Text(L10n.t("捕获标签", "Capture labels"))
            } footer: {
                Text(L10n.t("留空表示保持设备当前标签；每个标签最多 63 个 UTF-8 字节。",
                            "Leave a field blank to keep the device label; each label is limited to 63 UTF-8 bytes."))
            }

            if let validationMessage {
                Section {
                    Label(validationMessage, systemImage: "xmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.p4Err)
                }
            }

            if let errorText {
                Section {
                    Label(errorText, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.p4Err)
                }
            }

            Section {
                Button {
                    Task { await save() }
                } label: {
                    Label(busy ? L10n.t("正在保存…", "Saving…")
                               : L10n.t("保存标签", "Save labels"),
                          systemImage: "checkmark.circle")
                }
                .disabled(busy || validationMessage != nil || changes.isEmpty)

                Button {
                    Task { await load() }
                } label: {
                    Label(L10n.t("重新从设备读取", "Reload from device"), systemImage: "arrow.clockwise")
                }
                .disabled(busy)
            } footer: {
                Text(L10n.t("标签用于导出 CSV 时的 segment 注释，不会触发或停止捕获。",
                            "Labels annotate segments in the exported CSV; they never start or stop a capture."))
            }
        }
        .listStyle(.insetGrouped)
        .p4ListStyle()
        .navigationTitle(L10n.t("捕获标签", "Capture labels"))
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) { ToastOverlay() }
        .task { await load() }
    }

    private func load() async {
        do {
            let stats = try await environment.api.get(P4Route.researchCaptureStats)
            guard let object = stats.objectValue,
                  let raw = object["labels"]?.objectValue else {
                throw P4APIError(message: L10n.t("设备未上报标签", "Device did not report labels"))
            }
            var next: [String: String] = [:]
            for slot in slots {
                next[slot] = raw[slot]?.stringValue ?? ""
            }
            loaded = next
            labels = next
            errorText = nil
        } catch {
            errorText = AppEnvironment.friendly(error)
        }
    }

    private func save() async {
        busy = true
        errorText = nil
        do {
            for slot in changes {
                let value = labels[slot]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                _ = try await environment.api.post(
                    P4Route.researchCaptureLabels,
                    query: [P4Param("slot", slot), P4Param("label", value)]
                )
            }
            await load()
            environment.toast = P4Toast(message: L10n.t("标签已保存", "Labels saved"), style: .success)
            Haptics.success()
        } catch {
            errorText = AppEnvironment.friendly(error)
            Haptics.error()
        }
        busy = false
    }
}
