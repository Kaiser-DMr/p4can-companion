import Foundation

/// 最近一次成功拉取的设备数据（离线预览用）。
struct DeviceCache: Codable, Sendable {
    var host: String
    var savedAt: Date
    var entries: [String: P4JSON]
}

/// 成功拿到数据时落盘，断连/冷启动连不上时再读出来顶上，避免页面空白。
///
/// 设计约束：
/// - 只在**成功**时写，失败不会覆盖已有缓存；
/// - 按设备地址隔离，换了设备不会串数据；
/// - 超过 `maxAge` 的缓存不再展示（太旧反而误导）；
/// - 读写都在后台队列，不阻塞轮询。
enum OfflineCache {
    static let maxAge: TimeInterval = 7 * 24 * 60 * 60

    private static let fileName = "device-cache.json"
    private static let queue = DispatchQueue(label: "com.p4can.offlinecache", qos: .utility)

    private static var fileURL: URL? {
        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return nil }
        let directory = base.appendingPathComponent("P4CANCompanion", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory.appendingPathComponent(fileName)
    }

    /// 写入缓存：与已有内容**合并**，不同调用方各写各的端点，不会互相覆盖。
    static func save(host: String, entries: [String: P4JSON], at date: Date = Date()) {
        guard !entries.isEmpty, let url = fileURL else { return }
        queue.async {
            var merged = entries
            if let data = try? Data(contentsOf: url),
               let existing = try? JSONDecoder().decode(DeviceCache.self, from: data),
               existing.host == host {
                merged = existing.entries.merging(entries) { _, new in new }
            }
            let payload = DeviceCache(host: host, savedAt: date, entries: merged)
            guard let data = try? JSONEncoder().encode(payload) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    /// 读取缓存；地址不匹配、文件损坏或过期都返回 nil（调用方按「无缓存」处理）。
    static func load(host: String, now: Date = Date()) -> DeviceCache? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        guard let payload = try? JSONDecoder().decode(DeviceCache.self, from: data) else { return nil }
        guard payload.host == host, !payload.entries.isEmpty else { return nil }
        guard now.timeIntervalSince(payload.savedAt) <= maxAge else { return nil }
        return payload
    }

    static func clear() {
        guard let url = fileURL else { return }
        queue.async { try? FileManager.default.removeItem(at: url) }
    }
}
