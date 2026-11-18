import Foundation

/// 功能页「常用」置顶的持久化。
///
/// 只存 entry id（模块 id 或 `s3xy` / `lab`），顺序即展示顺序；上限 6 个，
/// 再多就不叫「常用」了，反而要在长列表里找。
enum FeaturePinStore {
    private static let key = "p4can.features.pinned"
    static let maxPins = 6

    static func load() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func save(_ ids: [String]) {
        UserDefaults.standard.set(Array(ids.prefix(maxPins)), forKey: key)
    }
}
