#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit
#endif
import Foundation

/// 与 Widget Extension 中的定义保持完全一致（ActivityKit 以 JSON 编解码）。
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

/// 实时活动属性。
///
/// `ActivityAttributes` 协议在 Mac Catalyst 上不可用（ActivityKit 未提供 Mac 实现），
/// 因此这里把「数据模型」与「协议适配」拆开：模型在所有平台一致，
/// 只在 iOS / iPadOS 上追加协议一致性，Mac 版走控制器桩实现，UI 自动隐藏该开关。
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
        /// 本机「车辆外观」对应的 Widget 内置侧视图资源名（车型 × 车漆 × 轮毂）；缺少时用 `vehicleArtwork`
        var vehicleVariant: String?
    }

    var deviceName: String
}

#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
extension CanActivityAttributes: ActivityAttributes {}
#endif
