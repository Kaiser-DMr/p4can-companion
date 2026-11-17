import Foundation

/// 一条网络请求记录（内置抓包，替代 Pulse 的轻量实现）。
struct NetworkLogEntry: Identifiable, Sendable {
    let id: UUID
    let date: Date
    let method: String
    let path: String
    let query: String
    let statusCode: Int?
    let durationMs: Int
    let bytes: Int
    let error: String?
}

/// 线程安全的环形日志（最多 300 条）。
///
/// 说明：SwiftUI 侧通过定时 `snapshot()` 刷新，避免跨线程发布者；
/// `@unchecked Sendable` 由内部 NSLock 保证。
final class NetworkLog: @unchecked Sendable {

    static let shared = NetworkLog()

    private let lock = NSLock()
    private var storage: [NetworkLogEntry] = []
    private let capacity = 300

    func append(_ entry: NetworkLogEntry) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(entry)
        if storage.count > capacity {
            storage.removeFirst(storage.count - capacity)
        }
    }

    func snapshot() -> [NetworkLogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return storage.reversed()
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll()
    }
}
