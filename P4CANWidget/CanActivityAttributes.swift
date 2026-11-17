#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit
#endif
import Foundation

/// 三路 CAN 的实时活动数据模型。
///
/// 注意：App 与 Widget Extension 各有一份**完全一致**的定义
/// （跨 target 无法共享源码，ActivityKit 以 JSON 编解码，不要求同一模块）。
struct CanBusActivityState: Codable, Hashable, Identifiable {
    var id: String { name }
    var name: String
    var online: Bool
    var detail: String
}

struct CanActivityAttributes {
    struct ContentState: Codable, Hashable {
        var buses: [CanBusActivityState]
        var nagEnabled: Bool
        var blinkEnabled: Bool
        var tlsscEnabled: Bool
        var gear: String
        var updatedAt: Date
    }

    var deviceName: String
}

#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
extension CanActivityAttributes: ActivityAttributes {}
#endif
