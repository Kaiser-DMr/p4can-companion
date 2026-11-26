import SwiftUI

/// 首页车型图像：按当前 profile 显示真实车款渲染图（透明底），
/// 不再使用通用的 `car.side.fill`，也不再手绘近似轮廓。
///
/// profile 编号：1 Model Y L、2 Model Y Juniper、3 Model Y（旧款）、
/// 4 Model 3 Highland、5 Model 3、6 Model S/X。
enum VehicleBodyStyle {
    case model3
    case modelY
    case modelYJuniper
    case modelYL
    case modelS
    case modelX

    /// profile 优先，其次按名称兜底（离线缓存或旧固件没有 profile id 时）。
    static func resolve(profileID: Int?, name: String?) -> VehicleBodyStyle {
        #if DEBUG
        // 本地联调：SIMCTL_CHILD_P4CAN_CAR_STYLE=y|yj|yl|3|s|x 可强制某种车身，便于逐车型截图核对。
        if let forced = ProcessInfo.processInfo.environment["P4CAN_CAR_STYLE"]?.lowercased() {
            switch forced {
            case "3", "model3": return .model3
            case "y", "modely": return .modelY
            case "yj", "juniper", "modelyjuniper": return .modelYJuniper
            case "yl", "modelyl": return .modelYL
            case "s", "models": return .modelS
            case "x", "modelx": return .modelX
            default: break
            }
        }
        #endif

        switch profileID {
        case 1: return .modelYL
        case 2: return .modelYJuniper
        case 3: return .modelY
        case 4, 5: return .model3
        case 6: return .modelS
        default: break
        }

        let text = (name ?? "").lowercased()
        if text.contains("model y l") || text.contains(" yl") { return .modelYL }
        if text.contains("juniper") { return .modelYJuniper }
        if text.contains("model y") { return .modelY }
        if text.contains("model 3") { return .model3 }
        if text.contains("model x") { return .modelX }
        if text.contains("model s") || text.contains("s/x") { return .modelS }
        return .model3
    }

    /// 资源名。每种车款都有独立素材。
    var assetName: String {
        switch self {
        case .model3: return "VehicleModel3"
        case .modelY: return "VehicleModelY"
        case .modelYJuniper: return "VehicleModelYJuniper"
        case .modelYL: return "VehicleModelYL"
        case .modelS: return "VehicleModelS"
        case .modelX: return "VehicleModelX"
        }
    }
}
