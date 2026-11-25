import Foundation

/// 单路 CAN 总线（固件 p4CanWriteStatus：can1*/can2*/can3*）。
///
/// 固件固定三路：CAN 1 BODY（TWAI0）、CAN 2 CHASSIS（TWAI1）、CAN 3 PARTY（TWAI2）。
struct CanBusSnapshot: Identifiable, Sendable {
    struct Field: Identifiable, Sendable {
        let key: String
        let value: P4JSON
        var id: String { key }
    }

    /// 1..3
    let index: Int
    /// 固件内置名称：BODY / CHASSIS / PARTY
    let codeName: String
    /// 当前车型拓扑下的角色名（profile/status 的 canA / canB / canExtra）
    let roleName: String?
    /// twai_state_t：0 STOPPED / 1 RUNNING / 2 BUS_OFF / 3 RECOVERING
    let state: Int?
    let ready: Bool
    let trafficOnline: Bool
    let rxCount: Int64?
    let txAccepted: Int64?
    let txRejected: Int64?
    let busOff: Int64?
    let trafficAgeMs: Int64?
    let fields: [Field]

    var id: Int { index }

    var displayName: String {
        var text = "CAN \(index) · \(codeName)"
        if let roleName, !roleName.isEmpty, roleName != codeName {
            text += "（\(roleName)）"
        }
        return text
    }

    var stateText: String {
        guard let state else { return trafficOnline ? "ONLINE" : "—" }
        switch state {
        case 0: return "STOPPED"
        case 1: return "RUNNING"
        case 2: return "BUS-OFF"
        case 3: return "RECOVERING"
        default: return "STATE \(state)"
        }
    }

    /// 只有「RUNNING + 有流量」才算在线。
    /// 之前用 `trafficOnline || ready`，BUS-OFF 时 ready 仍为 true，
    /// 状态页会出现「绿点 + BUS-OFF + 3/3 在线」的矛盾。
    var isOnline: Bool {
        guard let state else { return trafficOnline }
        return state == 1 && trafficOnline
    }
}

/// 从 cantraffic 组（p4CanWriteStatus）解析三路总线。
enum CanBusResolver {

    static func resolve(
        traffic: [String: P4JSON],
        profile: [String: P4JSON],
        system: [String: P4JSON] = [:]
    ) -> [CanBusSnapshot] {
        // T2CAN：MCP2515（CAN A）+ TWAI（CAN B），状态字段是 mcp*/twai*。
        if system["mcpReady"] != nil || system["mcpState"] != nil
            || traffic["mcpTrafficOnline"] != nil {
            return resolveT2(traffic: traffic, profile: profile, system: system)
        }

        let roleNames: [String?] = [
            profile["canA"]?.stringValue,
            profile["canB"]?.stringValue,
            profile["canExtra"]?.stringValue,
        ]

        var buses: [CanBusSnapshot] = []
        for index in 1...3 {
            let prefix = "can\(index)"
            guard traffic.keys.contains(where: { $0.hasPrefix(prefix) }) else { continue }
            let fields: [CanBusSnapshot.Field] = traffic
                .filter { key, value in
                    key.hasPrefix(prefix) && value.objectValue == nil
                }
                .sorted { $0.key < $1.key }
                .map { CanBusSnapshot.Field(key: $0.key, value: $0.value) }

            buses.append(
                CanBusSnapshot(
                    index: index,
                    codeName: traffic["\(prefix)Name"]?.stringValue ?? "CAN \(index)",
                    roleName: roleNames[index - 1],
                    state: traffic["\(prefix)State"]?.intValue.map { Int($0) },
                    ready: traffic["\(prefix)Ready"]?.boolValue ?? false,
                    trafficOnline: traffic["\(prefix)TrafficOnline"]?.boolValue ?? false,
                    rxCount: traffic["\(prefix)RxCount"]?.intValue,
                    txAccepted: traffic["\(prefix)TxAccepted"]?.intValue,
                    txRejected: traffic["\(prefix)TxRejected"]?.intValue,
                    busOff: traffic["\(prefix)BusOffCount"]?.intValue,
                    trafficAgeMs: traffic["\(prefix)TrafficAgeMs"]?.intValue,
                    fields: fields
                )
            )
        }
        return buses
    }

    /// T2CAN 两路总线：MCP2515（CAN A）与 TWAI（CAN B）。
    ///
    /// T2 的 `system/stats` 没有 `can1*` 字段，只有 `mcp*` / `twai*`；
    /// MCP 的 `mcpState` 是驱动错误码而非 TWAI 状态，所以不映射成 STOPPED/RUNNING，
    /// 在线判断交给 trafficOnline，避免把 ERROR_OK(0) 误显示为 STOPPED。
    private static func resolveT2(
        traffic: [String: P4JSON],
        profile: [String: P4JSON],
        system: [String: P4JSON]
    ) -> [CanBusSnapshot] {
        func scalarFields(prefix: String) -> [CanBusSnapshot.Field] {
            system
                .filter { key, value in
                    key.hasPrefix(prefix) && value.objectValue == nil
                }
                .sorted { $0.key < $1.key }
                .map { CanBusSnapshot.Field(key: $0.key, value: $0.value) }
        }

        func value(_ key: String) -> P4JSON? { system[key] }

        let busA = CanBusSnapshot(
            index: 1,
            codeName: "MCP2515",
            roleName: profile["canA"]?.stringValue,
            state: nil,
            ready: value("mcpReady")?.boolValue ?? false,
            trafficOnline: traffic["mcpTrafficOnline"]?.boolValue
                ?? value("mcpTrafficOnline")?.boolValue ?? false,
            rxCount: value("canARxFramesProcessed")?.intValue,
            txAccepted: value("mcpTxOk")?.intValue,
            txRejected: value("mcpTxFail")?.intValue,
            busOff: value("mcpBusOffCount")?.intValue,
            trafficAgeMs: traffic["mcpTrafficAgeMs"]?.intValue
                ?? value("mcpTrafficAgeMs")?.intValue,
            fields: scalarFields(prefix: "mcp")
        )

        let busB = CanBusSnapshot(
            index: 2,
            codeName: "TWAI",
            roleName: profile["canB"]?.stringValue,
            state: value("twaiState")?.intValue.map { Int($0) },
            ready: value("twaiReady")?.boolValue ?? false,
            trafficOnline: traffic["twaiTrafficOnline"]?.boolValue
                ?? value("twaiTrafficOnline")?.boolValue ?? false,
            rxCount: nil,
            txAccepted: nil,
            txRejected: value("twaiTxFailedCount")?.intValue,
            busOff: value("twaiBusOffCount")?.intValue,
            trafficAgeMs: traffic["twaiTrafficAgeMs"]?.intValue
                ?? value("twaiTrafficAgeMs")?.intValue,
            fields: scalarFields(prefix: "twai")
        )

        return [busA, busB]
    }
}

// MARK: - S3XY 蓝牙设备（s3xy_ble.h 真实结构）

/// 已配对设备。固件以槽位 `id`（1..N）标识设备，`address` 为 BLE MAC。
struct S3XYDevice: Identifiable, Hashable, Sendable {
    let slot: Int
    let name: String
    let address: String
    let state: String
    let connected: Bool
    let paused: Bool
    let autoConnect: Bool
    let rssi: Int?
    let singleLabel: String
    let doubleLabel: String
    let longLabel: String
    let singleAction: String
    let doubleAction: String
    let longAction: String
    let error: String?

    var id: Int { slot }

    init?(json: P4JSON) {
        guard let object = json.objectValue,
              let slot = object["id"]?.intValue.map({ Int($0) }) else { return nil }
        self.slot = slot
        self.name = object["name"]?.stringValue ?? "S3XY"
        self.address = object["address"]?.stringValue ?? ""
        self.state = object["state"]?.stringValue ?? "UNKNOWN"
        self.connected = object["connected"]?.boolValue ?? false
        self.paused = object["paused"]?.boolValue ?? false
        self.autoConnect = object["autoConnect"]?.boolValue ?? false
        self.rssi = object["rssi"]?.intValue.map { Int($0) }
        self.singleLabel = object["singleLabel"]?.stringValue ?? "None"
        self.doubleLabel = object["doubleLabel"]?.stringValue ?? "None"
        self.longLabel = object["longLabel"]?.stringValue ?? "None"
        self.singleAction = object["singleAction"]?.stringValue ?? "none"
        self.doubleAction = object["doubleAction"]?.stringValue ?? "none"
        self.longAction = object["longAction"]?.stringValue ?? "none"
        self.error = object["error"]?.stringValue
    }

    static func devices(from stats: P4JSON?) -> [S3XYDevice] {
        guard let array = stats?["devices"]?.arrayValue else { return [] }
        return array.compactMap(S3XYDevice.init(json:))
    }
}

/// 扫描发现的设备（scanResults）。
struct S3XYScanResult: Identifiable, Hashable, Sendable {
    let address: String
    let name: String
    let rssi: Int?
    let registered: Bool

    var id: String { address }

    init?(json: P4JSON) {
        guard let object = json.objectValue,
              let address = object["address"]?.stringValue, !address.isEmpty else { return nil }
        self.address = address
        self.name = object["name"]?.stringValue ?? "未知设备"
        self.rssi = object["rssi"]?.intValue.map { Int($0) }
        self.registered = object["registered"]?.boolValue ?? false
    }

    static func results(from stats: P4JSON?) -> [S3XYScanResult] {
        guard let array = stats?["scanResults"]?.arrayValue else { return [] }
        return array.compactMap(S3XYScanResult.init(json:))
    }
}

/// S3XY 设备动作绑定可选项（固件 s3xyActionCode 列表）。
enum S3XYActionCatalog {
    static let options: [(code: String, label: String)] = [
        ("none", "无动作"),
        ("noa_cancel", "取消 NOA 变道"),
        ("left_blinker", "左转向灯"),
        ("right_blinker", "右转向灯"),
        ("accel_mode_toggle", "加速模式切换"),
        ("performance_mode", "性能模式"),
        ("tlssc_toggle", "TLSSC 开关"),
        ("auto_blinker_toggle", "自动转向灯开关"),
        ("high_beam_strobe", "前大灯爆闪"),
        ("ap_left_lane_change", "AP 左变道"),
        ("ap_right_lane_change", "AP 右变道"),
        ("fsd_visualisation", "FSD 可视化"),
        ("research_capture_a", "研究捕获 A"),
        ("research_capture_b", "研究捕获 B"),
        ("research_capture_c", "研究捕获 C"),
        ("research_capture_d", "研究捕获 D"),
        ("research_capture_reset", "研究捕获重置"),
    ]
}

/// 设备执行的可回显结果提示。
struct P4Toast: Equatable, Sendable {
    enum Style: Sendable { case success, failure, info }

    let id: UUID
    let message: String
    let style: Style

    init(message: String, style: Style) {
        self.id = UUID()
        self.message = message
        self.style = style
    }

    static func == (lhs: P4Toast, rhs: P4Toast) -> Bool { lhs.id == rhs.id }
}

/// 可导出的 CSV 日志（固件 Content-Disposition 文件名）。
struct P4LogFile: Identifiable, Sendable {
    let id: String
    let title: String
    let path: String
    let fileName: String

    static let bootCapture = P4LogFile(
        id: "boot", title: "启动诊断记录", path: "/api/system/boot-capture.csv",
        fileName: "P4-CAN_boot_capture.csv"
    )
    static let canATrace = P4LogFile(
        id: "cana", title: "CAN A 发送跟踪", path: "/api/system/cana-tx.csv",
        fileName: "P4-CAN_CANA_TX_TRACE.csv"
    )
    static let canBTrace = P4LogFile(
        id: "canb", title: "CAN B 发送跟踪", path: "/api/system/canb-tx.csv",
        fileName: "P4-CAN_CANB_TX_TRACE.csv"
    )
    static let s3xyLog = P4LogFile(
        id: "s3xy", title: "S3XY 蓝牙日志", path: "/api/s3xy/log.csv",
        fileName: "P4-CAN_S3XY_log.csv"
    )
    static let driverMonitorLog = P4LogFile(
        id: "dms", title: "驾驶员监控捕获", path: "/api/drivermonitor/log.csv",
        fileName: "Driver_Monitoring_Capture.csv"
    )
    static let researchCaptureLog = P4LogFile(
        id: "research", title: "CAN 研究捕获", path: "/api/researchcapture/log.csv",
        fileName: "CAN_Research_Capture.csv"
    )

    static let all: [P4LogFile] = [
        .bootCapture, .canATrace, .canBTrace, .s3xyLog, .driverMonitorLog, .researchCaptureLog,
    ]
}
