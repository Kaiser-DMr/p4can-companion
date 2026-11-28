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
        /// 本机「车辆外观」车图在 App Group 共享目录中的文件名；读不到时用 `vehicleArtwork`
        var vehicleImageKey: String?
    }

    var deviceName: String
}

/// App 与 Widget 共享的车图缩略图目录（App Group）。
enum SharedVehicleImage {
    static let appGroup = "group.com.p4can.companion"

    /// 重签工具没有保留 App Group 时为 nil
    static var directory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("VehicleThumbs", isDirectory: true)
    }

    static func file(_ key: String) -> URL? {
        directory?.appendingPathComponent(key + ".png")
    }
}

#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
extension CanActivityAttributes: ActivityAttributes {}
#endif
