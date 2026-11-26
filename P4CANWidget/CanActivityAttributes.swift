#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit
#endif
import Foundation

/// 三路 CAN 的实时活动数据模型。
///
/// 注意：App 与 Widget Extension 各有一份**完全一致**的定义
/// （跨 target 无法共享源码，ActivityKit 以 JSON 编解码，不要求同一模块）。
/// 新增字段一律可选：系统里遗留的旧版本活动解码时这些字段为 nil。
struct CanBusActivityState: Codable, Hashable, Identifiable {
    var id: String { name }
    var name: String
    var online: Bool
    var detail: String
    /// 固件总线名（BODY / CHASSIS / PARTY）
    var shortName: String?
    /// 每秒收帧数（取整），未知时为 nil
    var rxPerSecond: Int?
}

struct CanActivityAttributes {
    struct ContentState: Codable, Hashable {
        var buses: [CanBusActivityState]
        var nagEnabled: Bool
        var blinkEnabled: Bool
        var tlsscEnabled: Bool
        var gear: String
        /// 当前选择的车型（profileName）
        var vehicleModel: String?
        var updatedAt: Date
        /// Widget 资源中的车型侧视图名（VehicleModel3 等）
        var vehicleArtwork: String?
        var apActive: Bool?
        var noaActive: Bool?
        /// 方向盘扭矩（N·m）
        var torque: Double?
        /// 电量百分比与续航，固件上报时才有
        var batterySoc: Double?
        var rangeKm: Double?
        /// 界面语言跟随 App 设置
        var english: Bool?
    }

    var deviceName: String
}

#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
extension CanActivityAttributes: ActivityAttributes {}
#endif
