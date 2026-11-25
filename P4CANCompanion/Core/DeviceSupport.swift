import Foundation

/// 设备家族：P4-CAN（三路 TWAI）与 T2CAN（MCP2515 + TWAI）。
///
/// 两套固件共用大部分 `/api/*` 路由，差异集中在：
/// - T2CAN 只有两路 CAN，状态字段前缀是 `mcp*` / `twai*`；
/// - FSD 与服务模式在 T2CAN 上位于 `/api/lab/...`；
/// - T2CAN 没有灯光、GPIO、SmartShift、R79 时序等 P4 专属功能。
enum DeviceFamily: String, Sendable {
    case p4can
    case t2can
    case unknown

    var displayName: String {
        switch self {
        case .p4can: return "P4-CAN"
        case .t2can: return "T2CAN"
        case .unknown: return "P4-CAN"
        }
    }

    var isT2CAN: Bool { self == .t2can }

    /// 固件实际 CAN 路数；unknown 时按 P4 处理，等 `system/stats` 到达后纠正。
    var busCount: Int { self == .t2can ? 2 : 3 }

    /// 依据 `/api/system/stats` 判断；T2CAN 会返回 `mcpReady/mcpState`，P4 返回 `chipModel/canBusCount`。
    static func detect(system: [String: P4JSON]) -> DeviceFamily {
        if let chip = system["chipModel"]?.stringValue,
           chip.localizedCaseInsensitiveContains("P4") {
            return .p4can
        }
        if system["mcpReady"] != nil || system["mcpState"] != nil {
            return .t2can
        }
        if system["canBusCount"] != nil {
            return .p4can
        }
        return .unknown
    }
}

/// 路由别名：视图仍然使用 P4 的路径，客户端在发送前按设备家族改写。
///
/// 只改写确实不同、且语义一致的接口；T2CAN 不存在的接口由功能开关隐藏，
/// 不做“404 回退”，避免把写操作发到错误端点。
enum DeviceRoute {
    nonisolated(unsafe) static var family: DeviceFamily = .unknown

    static func resolve(_ path: String) -> String {
        guard family == .t2can else { return path }
        switch path {
        case "/api/fsd/stats": return "/api/lab/fsd/stats"
        case "/api/fsd/update": return "/api/lab/fsd/update"
        case "/api/service-mode/stats": return "/api/lab/service-mode/stats"
        case "/api/service-mode/enter": return "/api/lab/service-mode/send"
        default: return path
        }
    }
}

/// 功能可用性：按设备家族隐藏 P4 专属模块。
enum FeatureSupport {
    /// T2CAN 3.30.x 没有这些端点；不是“暂时 404”，而是硬件/固件不提供。
    static let t2Unsupported: Set<String> = [
        "headlight", "rearFog", "lighting", "canGpio",
        "smartShift", "r79Timing", "heartbeat",
        "devTest", "summonVersion",
    ]

    static func supports(_ moduleID: String, family: DeviceFamily) -> Bool {
        guard family == .t2can else { return true }
        return !t2Unsupported.contains(moduleID)
    }
}
