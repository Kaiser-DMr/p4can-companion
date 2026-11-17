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
                Toggle("暂停刷新", isOn: $paused)
                LabeledContent("记录条数", value: "\(entries.count)")
                Button("清空日志") {
                    NetworkLog.shared.clear()
                    entries = []
                }
                .foregroundStyle(.p4Err)
            } footer: {
                Text("记录保存在内存中（最多 300 条），退出 App 后清空。")
            }

            Section("请求") {
                let filtered = filteredEntries
                if filtered.isEmpty {
                    Text("暂无记录")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(filtered) { entry in
                    row(entry)
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = fullURL(entry)
                            } label: {
                                Label("复制 URL", systemImage: "doc.on.doc")
                            }
                        }
                }
            }
        }
        .navigationTitle("网络日志")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "搜索路径或 query")
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
