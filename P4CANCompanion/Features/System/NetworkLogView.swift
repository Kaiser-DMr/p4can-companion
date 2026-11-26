import SwiftUI

/// 内置网络抓包日志（轻量替代 Pulse）。
///
/// 记录每个 /api/* 请求的方法、路径、query、状态码、耗时、响应字节数与错误，
/// 每秒刷新一次快照，支持搜索与复制，便于对照固件源码排障。
struct NetworkLogView: View {
    @State private var entries: [NetworkLogEntry] = []
    @State private var query = ""
    @State private var paused = false

    var body: some View {
        List {
            Section {
                Toggle(L10n.t("暂停刷新", "Pause refresh"), isOn: $paused)
                LabeledContent(L10n.t("记录条数", "Entries"), value: "\(entries.count)")
                Button(L10n.t("清空日志", "Clear log")) {
                    NetworkLog.shared.clear()
                    entries = []
                }
                .foregroundStyle(.p4Err)
            } footer: {
                Text(L10n.t("记录保存在内存中（最多 300 条），退出 App 后清空。",
                            "Kept in memory (up to 300 entries) and cleared when the app quits."))
            }

            Section(L10n.t("请求", "Requests")) {
                let filtered = filteredEntries
                if filtered.isEmpty {
                    Text(L10n.t("暂无记录", "No entries"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(filtered) { entry in
                    row(entry)
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = fullURL(entry)
                            } label: {
                                Label(L10n.t("复制 URL", "Copy URL"), systemImage: "doc.on.doc")
                            }
                        }
                }
            }
        }
        .p4ListStyle()
        .navigationTitle(L10n.t("网络日志", "Network log"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: L10n.t("搜索路径或 query", "Search path or query"))
        .task { await poll() }
    }

    private var filteredEntries: [NetworkLogEntry] {
        guard !query.isEmpty else { return entries }
        let needle = query.lowercased()
        return entries.filter {
            $0.path.lowercased().contains(needle) || $0.query.lowercased().contains(needle)
        }
    }

    private func row(_ entry: NetworkLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(entry.method)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(entry.method == "POST" ? Color.p4Warn.opacity(0.18) : Color.secondary.opacity(0.14), in: Capsule())
                Text(entry.path)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let status = entry.statusCode {
                    Text("\(status)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(status >= 400 ? Color.p4Err : Color.p4OK)
                } else {
                    Text("ERR")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.p4Err)
                }
            }
            if !entry.query.isEmpty {
                Text(entry.query)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack(spacing: 8) {
                Text("\(entry.durationMs) ms")
                Text(ByteCountFormatter.string(fromByteCount: Int64(entry.bytes), countStyle: .file))
                Text(entry.date.formatted(date: .omitted, time: .standard))
                if let error = entry.error {
                    Text(error).foregroundStyle(.p4Err).lineLimit(1)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func fullURL(_ entry: NetworkLogEntry) -> String {
        var text = "\(entry.method) \(entry.path)"
        if !entry.query.isEmpty { text += "?\(entry.query)" }
        return text
    }

    private func poll() async {
        while !Task.isCancelled {
            if !paused {
                entries = NetworkLog.shared.snapshot()
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }
}
