import Foundation

/// 动态 JSON 值。
///
/// 固件各 `/api/*` 端点的统计字段集合会随版本演进（v3.29.3 就含数百个键），
/// 因此统一以宽容方式解析：未知字段原样保留并展示，解析失败不影响其他字段。
enum P4JSON: Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([P4JSON])
    case object([String: P4JSON])
}

// MARK: - Decodable / Encodable

extension P4JSON: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([P4JSON].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: P4JSON].self) {
            self = .object(value)
        } else {
            let context = DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "无法识别的 JSON 值"
            )
            throw DecodingError.dataCorrupted(context)
        }
    }
}

extension P4JSON: Encodable {
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

// MARK: - 访问器

extension P4JSON {
    var objectValue: [String: P4JSON]? {
        if case .object(let value) = self { return value }
        return nil
    }

    var arrayValue: [P4JSON]? {
        if case .array(let value) = self { return value }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        if case .int(let value) = self { return value != 0 }
        return nil
    }

    var intValue: Int64? {
        if case .int(let value) = self { return value }
        if case .double(let value) = self { return Int64(value) }
        return nil
    }

    var doubleValue: Double? {
        if case .double(let value) = self { return value }
        if case .int(let value) = self { return Double(value) }
        return nil
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    subscript(key: String) -> P4JSON? {
        objectValue?[key]
    }

    /// 顶层标量字段（用于键值列表展示），按键名排序。
    var flatScalars: [(key: String, value: P4JSON)] {
        guard let object = objectValue else { return [] }
        return object
            .filter { entry in
                switch entry.value {
                case .bool, .int, .double, .string: return true
                default: return false
                }
            }
            .sorted { $0.key < $1.key }
            .map { (key: $0.key, value: $0.value) }
    }
}

// MARK: - 展示格式化

extension P4JSON {

    /// 单个值的可读文本（布尔本地化、字节量/时长按语义格式化）。
    @MainActor
    var displayText: String {
        switch self {
        case .null:
            return "—"
        case .bool(let value):
            return L10n.t(value ? "开启" : "关闭", value ? "On" : "Off")
        case .int(let value):
            return P4Format.number(value)
        case .double(let value):
            return P4Format.number(value)
        case .string(let value):
            return value
        case .array(let value):
            return L10n.t("[\(value.count) 项]", "[\(value.count) items]")
        case .object(let value):
            return "{\(value.count) 个字段}"
        }
    }

    /// 紧凑 JSON 文本（用于“原始数据”折叠区）。
    func prettyText() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self),
              let text = String(data: data, encoding: .utf8) else {
            return "（无法序列化）"
        }
        return text
    }
}

/// 数值与单位格式化。
enum P4Format {

    static func number(_ value: Int64) -> String {
        "\(value)"
    }

    static func number(_ value: Double) -> String {
        if value.rounded() == value { return "\(Int64(value))" }
        return String(format: "%.2f", value)
    }

    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    @MainActor
    static func milliseconds(_ value: Int64) -> String {
        if value < 1000 { return L10n.t("\(value) 毫秒", "\(value) ms") }
        let seconds = Double(value) / 1000.0
        if seconds < 60 { return L10n.t(String(format: "%.1f 秒", seconds), String(format: "%.1f s", seconds)) }
        let minutes = Int(seconds / 60)
        if minutes < 60 {
            return L10n.t("\(minutes) 分 \(Int(seconds) % 60) 秒", "\(minutes) min \(Int(seconds) % 60) s")
        }
        return L10n.t("\(minutes / 60) 小时 \(minutes % 60) 分", "\(minutes / 60) h \(minutes % 60) min")
    }

    /// 依据键名语义选择格式化方式。
    @MainActor
    static func value(for key: String, of json: P4JSON) -> String {
        let lower = key.lowercased()
        switch json {
        case .bool:
            // 诊断类布尔用「是/否」，开关类仍用「开启/关闭」
            if ["blocked", "supported", "valid", "ok"].contains(lower) {
                return json.boolValue == true ? L10n.t("是", "Yes") : L10n.t("否", "No")
            }
            return json.displayText
        case .int(let value):
            if lower.contains("byte") || lower.contains("heap") {
                return bytes(value)
            }
            if lower.hasSuffix("ms") || lower.contains("ms") {
                return milliseconds(value)
            }
            return number(value)
        case .double(let value):
            if lower.hasSuffix("ms") || lower.contains("ms") {
                return milliseconds(Int64(value.rounded()))
            }
            return number(value)
        default:
            return json.displayText
        }
    }
}

/// 固件字段名的中文对照（依据 v3.29.3 固件内嵌字符串还原）。
/// 未收录的字段回退为原始键名，保证不丢信息。
enum P4KeyLocalization {

    static let table: [String: String] = [
        // 系统
        "fwVersion": "固件版本",
        "freeHeap": "可用堆内存",
        "minFreeHeap": "历史最低堆内存",
        "largestHeapBlock": "最大连续堆块",
        "psramFreeBytes": "PSRAM 可用",
        "psramTotalBytes": "PSRAM 总量",
        "rtcBootCount": "累计启动次数",
        "uptimeMs": "运行时长",
        "uptimeS": "运行时长（秒）",
        "runtimeStatsResetCount": "统计重置次数",
        "hostedC6Version": "C6 从机固件版本",
        "hostedHostVersion": "Hosted 主机版本",
        "hostedWifiStarted": "Hosted Wi-Fi 已启动",
        "passwordIsDefault": "AP 密码仍为默认",
        "setupMode": "设置模式",
        "networkState": "网络状态",
        "ssid": "Wi-Fi 名称",
        "ip": "IP 地址",
        "channel": "信道",
        "state": "状态",
        // 车辆与拓扑
        "profile.canA": "CAN A 角色",
        "profile.canB": "CAN B 角色",
        "profile.canExtra": "Party 角色",
        "topology": "CAN 拓扑",
        "topologyName": "CAN 拓扑",
        "profile": "车型配置",
        "profileName": "车型配置",
        "hw3Enabled": "HW3 兼容启用",
        "hw3Active": "HW3 兼容生效",
        "hw3Supported": "支持 HW3",
        "banned": "banned 车型方案",
        "bannedSupported": "支持 banned 车型",
        "labEnabled": "实验室功能",
        "s3xyDiagnosticsEnabled": "S3XY 诊断",
        "apDriveProfileEnabled": "AP 踏板配置",
        "apDriveProfileActive": "AP 踏板配置生效",
        "apDriveProfileSupported": "支持 AP 踏板配置",
        "apDriveProfileRegenName": "能量回收档位",
        "apDriveProfileTxOk": "踏板配置发送成功",
        "apDriveProfileTxFail": "踏板配置发送失败",
        "tlsscRestore": "TLSSC 恢复",
        "tlsscRestoreSupported": "支持 TLSSC 恢复",
        "bodySupported": "车身 CAN 支持",
        "bodyControlsSupported": "车身控制支持",
        "pedalMapSupported": "支持踏板映射",
        "ulcSupported": "支持无确认变道",
        "nagSupported": "支持 NAG",
        "nagTorqueSupported": "支持扭矩 NAG",
        "nagTsl9Supported": "支持 TSL9 NAG",
        // CAN 总线
        "canAName": "CAN A 名称",
        "canBName": "CAN B 名称",
        "canExtraName": "Party CAN 名称",
        "canAState": "CAN A 状态",
        "canBState": "CAN B 状态",
        "canExtraState": "Party CAN 状态",
        "canAStateName": "CAN A 状态",
        "canBStateName": "CAN B 状态",
        "canAPhysical": "CAN A 物理在线",
        "canBPhysical": "CAN B 物理在线",
        "canExtraPhysical": "Party CAN 物理在线",
        "canARxFramesProcessed": "CAN A 接收帧数",
        "canBRxFramesProcessed": "CAN B 接收帧数",
        "canExtraRxFramesProcessed": "Party 接收帧数",
        "canATxTraceCount": "CAN A 发送跟踪条数",
        "canBTxTraceCount": "CAN B 发送跟踪条数",
        "canExtraTxTraceCount": "Party 发送跟踪条数",
        "canABusOffRecord": "CAN A Bus-Off 记录",
        "canBBusOffRecord": "CAN B Bus-Off 记录",
        "canBusCount": "总线数量",
        "canExtra": "Party CAN",
        "canExtraDetail": "Party CAN 详情",
        "canA": "CAN A",
        "canB": "CAN B",
        "canState": "CAN 状态",
        "canStateName": "CAN 状态",
        // canN* 后缀（配合 label(for:) 前缀映射）
        "Name": "名称",
        "State": "状态",
        "Ready": "就绪",
        "TrafficOnline": "流量在线",
        "TrafficSeen": "检测到流量",
        "TrafficAgeMs": "最近帧龄",
        "RxCount": "接收帧数",
        "TxAccepted": "发送接受",
        "TxRejected": "发送被拒",
        "BusOffCount": "Bus-Off 次数",
        "RxMissed": "接收丢弃",
        "RxOverrun": "接收溢出",
        "TxPin": "发送引脚",
        "RxPin": "接收引脚",
        "Mode": "模式",
        "twaiState": "TWAI 状态",
        "twaiReady": "TWAI 就绪",
        "twaiTrafficAgeMs": "TWAI 帧龄",
        "mcpReady": "MCP2515 就绪",
        "mcpState": "MCP2515 状态",
        "mcpTrafficSeen": "MCP2515 有流量",
        "mcpTrafficOnline": "MCP2515 在线",
        "mcpTrafficAgeMs": "MCP2515 帧龄",
        "mcpTxOk": "MCP2515 发送成功",
        "mcpTxFail": "MCP2515 发送失败",
        "mcpBusOffCount": "MCP2515 BUS-OFF",
        "twaiStateName": "TWAI 状态",
        "twaiTxFailedCount": "发送失败计数",
        "twaiRxMissedCount": "接收丢失计数",
        "twaiBusOffCount": "Bus-Off 计数",
        "twaiBusErrorCount": "总线错误计数",
        "twaiArbLostCount": "仲裁丢失计数",
        "twaiRxErrorCounter": "接收错误计数器",
        "twaiTxErrorCounter": "发送错误计数器",
        "twaiTrafficOnline": "总线流量在线",
        "twaiTrafficSeen": "检测到总线流量",
        "twaiQueueNow": "当前队列长度",
        "canAName-": "CAN A",
        // NAG / DMS
        "enabled": "启用",
        "dmsNag": "DMS 提醒干预",
        "dmsNagEnabled": "DMS 提醒干预",
        "dmsNagActive": "DMS 干预生效中",
        "dmsNagSupported": "支持 DMS 干预",
        "ho1ThresholdNm": "提示阈值 1 (N·m)",
        "ho2ThresholdNm": "提示阈值 2 (N·m)",
        "hoPolicy": "握手策略",
        "hoPolicyName": "握手策略",
        "hoRatePct": "提示频率 (%)",
        "method": "方式",
        "methodName": "方式",
        "ignoreApState": "忽略 AP 状态",
        // 变道 / 召唤 / 视觉
        "autoLaneChangeEnabled": "自动变道启用",
        "autoLaneChangeGateOpen": "自动变道闸门开放",
        "autoLaneChangeTargetBus": "自动变道目标总线",
        "ulcOffHighwayMode": "高速禁用模式",
        "ulcBlindSpotConfig": "盲区配置",
        "summonSessionActive": "召唤会话激活",
        "summonRouteValid": "召唤路由有效",
        "tlsscInjectedActive": "TLSSC 注入激活",
        "tlsscHighwayGateEnabled": "高速闸门启用",
        "tlsscBlockInNoa": "NOA 中阻断",
        "tlsscClearPending": "清除待处理",
        "noaActive": "NOA 激活",
        "apActive": "AP 激活",
        "torque": "扭矩 (N·m)",
        "displayState": "AP 显示状态",
        "noaSessionStateName": "NOA 会话状态",
        "noaStabilizationSeconds": "NOA 稳定期 (秒)",
        // 驾驶状态（网页顶部实时区同源字段）
        "dasState": "自动驾驶状态",
        "dasStateName": "自动驾驶状态",
        "dasAgeMs": "DAS 数据时延",
        "dasBusName": "DAS 来源总线",
        "dasHandsOnRaw": "方向盘在位原始值",
        "gearName": "挡位",
        "gearRaw": "挡位原始值",
        "gearBusName": "挡位来源总线",
        "gearSourceName": "挡位来源",
        "gearAgeMs": "挡位时延",
        "speedKph": "车速 (km/h)",
        "vehicleSpeedKph": "车速 (km/h)",
        "speed": "车速",
        "active": "运行中",
        "blocked": "被阻断",
        "blockReason": "阻断原因",
        "hz": "频率 (Hz)",
        "durationMs": "持续时间 (ms)",
        "remainingMs": "剩余时间",
        "allowManualDriving": "允许人工介入",
        "blockTxInPark": "驻车 / 召唤时暂停",
        "pattern": "模式",
        "batterySoc": "电池电量 (%)",
        "soc": "电池电量 (%)",
        "batteryLevel": "电池电量 (%)",
        "stateOfCharge": "电池电量 (%)",
        "rangeKm": "剩余续航 (km)",
        "batteryRangeKm": "剩余续航 (km)",
        "ratedRangeKm": "额定续航 (km)",
        "advancedEapSupported": "高级 EAP 支持",
        "apDriveProfile": "AP 踏板配置",
        "apDriveProfileRegenRaw": "AP 回收档位原始值",
        "alcMode": "ALC 覆盖模式",
        "alcOffHighwayEnabled": "非高速 ALC 覆盖",
        "anyOverride": "存在 ULC 覆盖",
        "stalkConfirmEnabled": "变道免确认",
        "stalkConfirmTimingMode": "变道免确认时序",
        "requestDisabled": "限速识别抑制",
        "mode1ReinjectEnabled": "Mode 1 重注入",
        "mode2ReinjectEnabled": "Mode 2 重注入",
        "s3xy": "S3XY 诊断",
        "targetName": "目标档位",
        "selectedValue": "心跳值",
        "handsOnState": "方向盘状态",
        "apDisplayState": "AP 显示状态",
        "r79TxState": "R79 发送状态",
        "r79TxCount": "R79 发送计数",
        "epasTorqueNm": "转向扭矩 (N·m)",
        "steeringDeg": "转向角 (°)",
        "parked": "驻车",
        "navRouteActive": "导航路由激活",
        "roadClass": "道路类型",
        "controlledAccess": "封闭道路",
        // 车身
        "doorCancel": "开门取消",
        "cancelPauseSeconds": "取消暂停秒数",
        "delayMs": "延迟 (毫秒)",
        "blinkTx": "转向灯发送计数",
        "autoEnabled": "自动模式",
        "autoConnect": "自动连接",
        // S3XY / 蓝牙
        "bluetoothEnabled": "蓝牙总开关",
        "scanning": "扫描中",
        "pairedCount": "已配对数量",
        "connectedCount": "已连接数量",
        "maxDevices": "设备数上限",
        "lastPairingRc": "最近配对结果",
        "lastDisconnectRc": "最近断开原因",
        "scanError": "扫描错误",
        "bleInitialized": "BLE 已初始化",
        "bleStartupAllowed": "允许 BLE 启动",
        "s3xyLogCapacity": "S3XY 日志容量",
        // OTA
        "otaInProgress": "升级进行中",
        "inProgress": "升级进行中",
        "stage": "升级阶段",
        "receivedBytes": "已接收字节",
        "totalBytes": "总字节",
        "attempt": "升级尝试次数",
        "updateError": "升级错误",
        "error": "错误",
        "ok": "结果",
        // 研究捕获
        "capturing": "捕获中",
        "captureMode": "捕获模式",
        "rawRingCapacity": "环形缓冲容量",
        "rawArchiveUsagePct": "归档使用率 (%)",
        "currentLabel": "当前标签",
        // 灯光爆闪（headlight-strobe / rear-fog-strobe）
        // 注意：*Ms 字段的值会自动带「毫秒 / 秒」，标签里不再重复写单位。
        "flashesDone": "已完成闪烁",
        "flashesTotal": "总闪烁次数",
        "intervalMs": "间隔",
        "holdEnabled": "按住拨杆爆闪",
        "holdDelayMs": "长按触发时间",
        "trigger": "触发入口",
        "triggerName": "触发入口",
        "stalkVariant": "拨杆类型",
        "totalMs": "总时长",
        "pulses": "脉冲计数",
        "phaseOn": "当前相位",
        "templateValid": "已捕获原始帧",
        "stockFogOn": "触发前后雾灯",
        "stopReason": "结束原因",
        "frameAgeMs": "帧龄",
        // 其他常用
        "supported": "支持",
        "available": "可用",
        "reason": "原因",
        "timestamp": "时间戳",
        "count": "计数",
        "txOk": "发送成功",
        "txFail": "发送失败",
        "txMode": "发送模式",
        "txModeName": "发送模式",
        "unknown": "未知",
    ]

    @MainActor
    static func label(for key: String) -> String {
        // 英文模式不套中文表：直接显示固件字段名，比半中半英更好读，
        // 也避免为 200+ 个键维护第二张翻译表。
        if L10n.isEnglish { return key }
        if let mapped = table[key] { return mapped }
        // can1*/can2*/can3* 统一映射
        for index in 1...3 {
            let prefix = "can\(index)"
            if key.hasPrefix(prefix),
               let suffix = table[String(key.dropFirst(prefix.count))] {
                return "CAN \(index) \(suffix)"
            }
        }
        return key
    }
}
