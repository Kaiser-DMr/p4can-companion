#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit
#endif
import Foundation

/// 与 Widget Extension 中的定义保持完全一致（ActivityKit 以 JSON 编解码）。
struct CanBusActivityState: Codable, Hashable, Identifiable {
    var id: String { name }
    var name: String
    var online: Bool
    var detail: String
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
        /// 当前选择的车型（profileName）；老版本活动解码时为 nil。
        var vehicleModel: String?
        var updatedAt: Date
    }

    var deviceName: String
}

#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
extension CanActivityAttributes: ActivityAttributes {}
#endif
