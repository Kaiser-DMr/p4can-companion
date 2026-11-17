import Foundation

/// 数值控件规格（成对提交时使用）。
struct NumberSpec: Sendable {
    let key: String
    let range: ClosedRange<Double>
    let unit: String
}

/// 功能模块内的一个控件定义。
///
/// 与固件 web_api.h 的真实契约对齐：全部为 query 参数 POST。
/// `extra` 表示该接口要求同时提交的兄弟参数（值从当前 stats 读取），
/// 例如 /api/r79/ap-control/update 必须一次提交 4 个参数。
struct FeatureControl: Identifiable, Sendable {
    enum Kind: Sendable {
        /// POST `path?key=1|0[&extra...]`
        case toggle(key: String, path: String?, extra: [String])
        /// POST `path?key=value[&extra...]`
        case select(key: String, options: [Option], path: String?, extra: [String])
        /// 读取字段与提交字段不同名（如提交 m=7 读取 mode）
        case selectRead(key: String, readKey: String, options: [Option], path: String?, extra: [String])
        /// POST `path?key=number[&extra...]`
        case number(key: String, range: ClosedRange<Double>, step: Double, unit: String, path: String?, extra: [String])
        /// 同时提交两个数值（blink 等待时间 / 研究捕获窗口）
        case pairNumber(first: NumberSpec, second: NumberSpec, path: String)
        /// 走独立 enable/disable 端点
        case endpointToggle(readKey: String, on: String, off: String)
        /// 触发型动作
        case trigger(path: String, query: [P4Param], confirmation: Bool, destructive: Bool)
    }

    struct Option: Identifiable, Sendable {
        let label: String
        let rawValue: String
        var id: String { rawValue }
    }

    let id: String
    let title: String
    let footnote: String?
    let kind: Kind
    /// 读取状态用的键（nil 表示与写入键相同）。
    /// 固件里「写入参数名」与「状态 JSON 字段名」常常不一致，例如
    /// ULC 写 `confirm`、状态里叫 `stalkConfirmEnabled`。
    var readKey: String? = nil
    /// 读取状态用的端点（nil 表示模块的 statsPath）。
    /// 少数开关的状态挂在别的端点上（如 LAB 的 AP 踏板档位在 /api/pedalmap/stats）。
    var readPath: String? = nil
}

/// 一个功能模块：标题、说明、状态端点与控件集合。
struct FeatureModule: Identifiable, Sendable {
    enum Section: String, CaseIterable, Sendable {
        case driving = "驾驶辅助"
        case body = "车身与舒适"
        case lab = "实验室功能"
        case advanced = "高级与兼容"

        var symbol: String {
            switch self {
            case .driving: return "car.side"
            case .body: return "door.left.hand.open"
            case .lab: return "flask"
            case .advanced: return "gearshape.2"
            }
        }
    }

    let id: String
    let title: String
    let summary: String
    let icon: String
    let section: Section
    /// 详情页轮询的状态端点（GET）
    let statsPath: String
    /// 能力位键（features/status 或 profile/status），nil 表示不检查
    let supportKey: String?
    let controls: [FeatureControl]
}

/// 功能目录：严格对应开源固件 web_api.h 的接口与取值域。
enum FeatureCatalog {

    static let modules: [FeatureModule] = [

        // MARK: 驾驶辅助

        FeatureModule(
            id: "nag",
            title: "NAG 抑制（Nag Killer）",
            summary: "扭矩表 / TSL9 两种注入方式，含 Mode A/B/C/H 波形与右手滚轮注入。",
            icon: "hands.and.sparkles",
            section: .driving,
            statsPath: P4Route.nagConfig,
            supportKey: "nagSupported",
            controls: [
                FeatureControl(
                    id: "nag.enabled", title: "启用 NAG", footnote: "关闭即恢复原厂提示",
                    kind: .toggle(key: "enabled", path: P4Route.nagUpdate, extra: [])
                ),
                FeatureControl(
                    id: "nag.mode", title: "注入模式", footnote: "Mode H 为人体化波形（Mode C 已并入 H）",
                    kind: .selectRead(
                        key: "m",
                        readKey: "mode",
                        options: [
                            .init(label: "Mode A · 经典扭矩表", rawValue: "0"),
                            .init(label: "Mode B", rawValue: "1"),
                            .init(label: "Mode C", rawValue: "3"),
                            .init(label: "Mode H · 人体化", rawValue: "7"),
                        ],
                        path: P4Route.nagMode,
                        extra: []
                    )
                ),
                FeatureControl(
                    id: "nag.method", title: "注入方式", footnote: "TSL9 需要对应车型支持",
                    kind: .select(
                        key: "method",
                        options: [
                            .init(label: "扭矩 · 既有方式", rawValue: "0"),
                            .init(label: "TSL9", rawValue: "1"),
                        ],
                        path: P4Route.nagUpdate,
                        extra: []
                    )
                ),
                FeatureControl(
                    id: "nag.ignoreApState", title: "忽略 AP 状态", footnote: "AP 未激活时也允许注入",
                    kind: .toggle(key: "ignoreApState", path: P4Route.nagUpdate, extra: [])
                ),
                FeatureControl(
                    id: "nag.pauseAtZero", title: "零速暂停", footnote: "停车时停止注入",
                    kind: .toggle(key: "pauseAtZeroSpeed", path: P4Route.nagUpdate, extra: [])
                ),
                FeatureControl(
                    id: "nag.tsl9Sequence", title: "TSL9 时序", footnote: nil,
                    kind: .select(
                        key: "tsl9Sequence",
                        options: [
                            .init(label: "V8.2 原始 · 4→1", rawValue: "0"),
                            .init(label: "扩展 · 2/3/4→1", rawValue: "1"),
                        ],
                        path: P4Route.nagUpdate,
                        extra: []
                    )
                ),
                FeatureControl(
                    id: "nag.tsl9InputMode", title: "TSL9 输入模式", footnote: nil,
                    kind: .select(
                        key: "tsl9InputMode",
                        options: [
                            .init(label: "左侧音量键", rawValue: "0"),
                            .init(label: "右侧车速键", rawValue: "1"),
                        ],
                        path: P4Route.nagUpdate,
                        extra: []
                    )
                ),
                FeatureControl(
                    id: "nag.tsl9LegacyRoute", title: "TSL9 路由", footnote: nil,
                    kind: .select(
                        key: "tsl9LegacyRoute",
                        options: [
                            .init(label: "Body 0x39B", rawValue: "0"),
                            .init(label: "Chassis 0x399", rawValue: "1"),
                        ],
                        path: P4Route.nagUpdate,
                        extra: []
                    )
                ),
                FeatureControl(
                    id: "nag.rightScroll", title: "右手滚轮注入", footnote: "仅扭矩方式",
                    kind: .toggle(key: "torqueRightScrollEnabled", path: P4Route.nagUpdate, extra: [])
                ),
                FeatureControl(
                    id: "nag.rightScrollInterval", title: "滚轮注入间隔", footnote: "1–600 秒",
                    kind: .number(
                        key: "torqueRightScrollIntervalSeconds", range: 1...600, step: 1, unit: "秒",
                        path: P4Route.nagUpdate, extra: []
                    )
                ),
                FeatureControl(
                    id: "nag.tsl9Periodic", title: "TSL9 周期注入", footnote: nil,
                    kind: .toggle(key: "tsl9RightPeriodicEnabled", path: P4Route.nagUpdate, extra: [])
                ),
                FeatureControl(
                    id: "nag.tsl9PeriodicInterval", title: "TSL9 周期间隔", footnote: "1–600 秒",
                    kind: .number(
                        key: "tsl9RightPeriodicIntervalSeconds", range: 1...600, step: 1, unit: "秒",
                        path: P4Route.nagUpdate, extra: []
                    )
                ),
                FeatureControl(
                    id: "nag.reset", title: "恢复默认参数", footnote: nil,
                    kind: .trigger(path: P4Route.nagReset, query: [], confirmation: true, destructive: false)
                ),
            ]
        ),

        FeatureModule(
            id: "alc",
            title: "自动拨杆变道 (ALC)",
            summary: "拨杆触发变道注入，可选择注入总线（CAN A / CAN B / 双路）。",
            icon: "arrow.triangle.turn.up.right.diamond",
            section: .driving,
            statsPath: P4Route.alcStats,
            supportKey: nil,
            controls: [
                FeatureControl(
                    id: "alc.enabled", title: "启用自动变道", footnote: nil,
                    kind: .toggle(key: "enabled", path: P4Route.alcUpdate, extra: []),
                    readKey: "autoLaneChangeEnabled"
                ),
                FeatureControl(
                    id: "alc.bus", title: "注入总线", footnote: "BOTH 会同时在两路发送",
                    kind: .selectRead(
                        key: "bus",
                        readKey: "autoLaneChangeTargetBus",
                        options: [
                            .init(label: "CAN A", rawValue: "1"),
                            .init(label: "CAN B", rawValue: "2"),
                            .init(label: "BOTH", rawValue: "3"),
                        ],
                        path: P4Route.alcUpdate,
                        extra: []
                    )
                ),
            ]
        ),

        FeatureModule(
            id: "ulc",
            title: "无确认变道 (ULC)",
            summary: "变道确认、高速禁用与盲区策略（blind: 标准 / 激进 / 极激进）。",
            icon: "arrow.triangle.swap",
            section: .driving,
            statsPath: P4Route.ulcStats,
            supportKey: nil,
            controls: [
                FeatureControl(
                    id: "ulc.confirm", title: "无确认变道", footnote: "部分车型不支持（Confirm-Free unsupported）",
                    kind: .toggle(key: "confirm", path: P4Route.ulcUpdate, extra: []),
                    readKey: "stalkConfirmEnabled"
                ),
                FeatureControl(
                    id: "ulc.alcOff", title: "高速禁用 ALC", footnote: nil,
                    kind: .toggle(key: "alcOff", path: P4Route.ulcUpdate, extra: []),
                    readKey: "alcMode"
                ),
                FeatureControl(
                    id: "ulc.blind", title: "盲区策略", footnote: nil,
                    kind: .selectRead(
                        key: "blind",
                        readKey: "ulcBlindMode",
                        options: [
                            .init(label: "原厂", rawValue: "stock"),
                            .init(label: "标准", rawValue: "0"),
                            .init(label: "激进", rawValue: "1"),
                            .init(label: "极激进 (MAD MAX)", rawValue: "2"),
                        ],
                        path: P4Route.ulcUpdate,
                        extra: []
                    )
                ),
                FeatureControl(
                    id: "ulc.offHighway", title: "非高速 ULC 策略", footnote: nil,
                    kind: .selectRead(
                        key: "ulcOff",
                        readKey: "ulcOffHighwayMode",
                        options: [
                            .init(label: "原厂", rawValue: "stock"),
                            .init(label: "关闭", rawValue: "0"),
                            .init(label: "开启", rawValue: "1"),
                        ],
                        path: P4Route.ulcUpdate,
                        extra: []
                    )
                ),
                FeatureControl(
                    id: "ulc.timing", title: "变道时序优化", footnote: nil,
                    kind: .toggle(key: "timing", path: P4Route.ulcUpdate, extra: []),
                    readKey: "stalkConfirmTimingMode"
                ),
            ]
        ),

        FeatureModule(
            id: "summon",
            title: "召唤与交通灯 (TLSSC)",
            summary: "TLSSC 注入开关、高速闸门与 NOA 阻断策略。",
            icon: "car.top.radiowaves.rear.right.badge.exclamationmark",
            section: .driving,
            statsPath: P4Route.summonStats,
            supportKey: nil,
            controls: [
                FeatureControl(
                    id: "summon.tlssc", title: "启用 TLSSC 注入", footnote: "独立 enable / disable 端点",
                    kind: .endpointToggle(
                        readKey: "tlssc",
                        on: P4Route.summonTLSSCEnable,
                        off: P4Route.summonTLSSCDisable
                    )
                ),
                FeatureControl(
                    id: "summon.highwayGate", title: "高速闸门", footnote: nil,
                    kind: .toggle(key: "enabled", path: P4Route.summonTLSSCHighwayGate, extra: []),
                    readKey: "tlsscHighwayGateEnabled"
                ),
                FeatureControl(
                    id: "summon.noaBlock", title: "NOA 中阻断 TLSSC", footnote: nil,
                    kind: .toggle(key: "enabled", path: P4Route.summonTLSSCNoABlock, extra: []),
                    readKey: "tlsscBlockInNoa"
                ),
            ]
        ),

        FeatureModule(
            id: "dms",
            title: "驾驶员监控 (DMS)",
            summary: "禁用座舱摄像头提醒，并可抓取一次带标签的 DMS 报文（A–F 槽位）。",
            icon: "eye.square",
            section: .driving,
            statsPath: P4Route.dmsConfig,
            supportKey: "dmsNagSupported",
            controls: [
                FeatureControl(
                    id: "dms.enabled", title: "禁用 DMS 提醒", footnote: "需要车型支持",
                    kind: .toggle(key: "enabled", path: P4Route.dmsConfig, extra: [])
                ),
                FeatureControl(
                    id: "dms.start", title: "捕获一段 DMS 数据", footnote: "槽位 A，日志可在系统页导出",
                    kind: .trigger(
                        path: P4Route.dmsStart,
                        query: [P4Param("slot", "A")],
                        confirmation: false,
                        destructive: false
                    )
                ),
                FeatureControl(
                    id: "dms.reset", title: "重置捕获数据", footnote: nil,
                    kind: .trigger(path: P4Route.dmsReset, query: [], confirmation: true, destructive: false)
                ),
            ]
        ),

        FeatureModule(
            id: "r79",
            title: "R79 / EU 解锁",
            summary: "Mode 1/2 波形、Bit18 策略与 HW3 兼容（HW3 必须单独提交）。",
            icon: "waveform.path.ecg",
            section: .driving,
            statsPath: P4Route.r79Stats,
            supportKey: nil,
            controls: [
                FeatureControl(
                    id: "r79.mode", title: "R79 模式", footnote: nil,
                    kind: .select(
                        key: "mode",
                        options: [
                            .init(label: "Mode 1", rawValue: "1"),
                            .init(label: "Mode 2", rawValue: "2"),
                        ],
                        path: P4Route.r79Update,
                        extra: []
                    )
                ),
                FeatureControl(
                    id: "r79.mode1Wait", title: "Mode 1 发送等待", footnote: nil,
                    kind: .select(
                        key: "mode1TxWaitMode",
                        options: [
                            .init(label: "快速回显 · 0 ms", rawValue: "0"),
                            .init(label: "等待 2 ms", rawValue: "1"),
                        ],
                        path: P4Route.r79Update,
                        extra: []
                    )
                ),
                FeatureControl(
                    id: "r79.mode1Reinject", title: "Mode 1 重注入", footnote: nil,
                    kind: .toggle(key: "mode1Reinject", path: P4Route.r79Update, extra: []),
                    readKey: "mode1ReinjectEnabled"
                ),
                FeatureControl(
                    id: "r79.mode1Delay", title: "Mode 1 延迟", footnote: "0–340 ms",
                    kind: .number(
                        key: "mode1DelayMs", range: 0...340, step: 10, unit: "ms",
                        path: P4Route.r79Update, extra: []
                    )
                ),
                FeatureControl(
                    id: "r79.mode2Reinject", title: "Mode 2 重注入", footnote: nil,
                    kind: .toggle(key: "mode2Reinject", path: P4Route.r79Update, extra: []),
                    readKey: "mode2ReinjectEnabled"
                ),
                FeatureControl(
                    id: "r79.mode2Delay", title: "Mode 2 延迟", footnote: "0–2000 ms",
                    kind: .number(
                        key: "mode2DelayMs", range: 0...2000, step: 50, unit: "ms",
                        path: P4Route.r79Update, extra: []
                    )
                ),
                FeatureControl(
                    id: "r79.bit18", title: "Bit18 策略", footnote: nil,
                    kind: .select(
                        key: "bit18Mode",
                        options: [
                            .init(label: "原厂", rawValue: "0"),
                            .init(label: "强制 0", rawValue: "1"),
                        ],
                        path: P4Route.r79Update,
                        extra: []
                    )
                ),
                FeatureControl(
                    id: "r79.hw3", title: "HW3 兼容", footnote: "此开关必须单独提交",
                    kind: .select(
                        key: "hw3Enabled",
                        options: [
                            .init(label: "关闭", rawValue: "0"),
                            .init(label: "开启", rawValue: "1"),
                        ],
                        path: P4Route.r79Update,
                        extra: []
                    )
                ),
            ]
        ),

        FeatureModule(
            id: "r79ap",
            title: "R79 AP 控制",
            summary: "AP 期间阻断或延迟 R79 注入（需实验室功能开启）。",
            icon: "road.lanes",
            section: .lab,
            statsPath: P4Route.r79APControlStats,
            supportKey: nil,
            controls: [
                FeatureControl(
                    id: "r79ap.enabled", title: "启用 AP 控制", footnote: "四个参数需一次提交",
                    kind: .toggle(
                        key: "enabled", path: P4Route.r79APControlUpdate,
                        extra: ["mode", "delaySeconds", "allowManualDriving"]
                    )
                ),
                FeatureControl(
                    id: "r79ap.mode", title: "AP 策略", footnote: nil,
                    kind: .select(
                        key: "mode",
                        options: [
                            .init(label: "AP 期间阻断", rawValue: "0"),
                            .init(label: "AP 之后延迟", rawValue: "1"),
                        ],
                        path: P4Route.r79APControlUpdate,
                        extra: ["enabled", "delaySeconds", "allowManualDriving"]
                    )
                ),
                FeatureControl(
                    id: "r79ap.delay", title: "延迟秒数", footnote: "2–10 秒",
                    kind: .number(
                        key: "delaySeconds", range: 2...10, step: 1, unit: "秒",
                        path: P4Route.r79APControlUpdate,
                        extra: ["enabled", "mode", "allowManualDriving"]
                    )
                ),
                FeatureControl(
                    id: "r79ap.manual", title: "允许人工介入", footnote: nil,
                    kind: .toggle(
                        key: "allowManualDriving", path: P4Route.r79APControlUpdate,
                        extra: ["enabled", "mode", "delaySeconds"]
                    )
                ),
            ]
        ),

        // MARK: 车身与舒适

        FeatureModule(
            id: "blink",
            title: "自动转向灯 (BlinkA)",
            summary: "NOA 变道自动打灯，含稳定期、取消暂停与发送模式。",
            icon: "arrow.triangle.turn.up.right.diamond",
            section: .body,
            statsPath: P4Route.blinkAStats,
            supportKey: "advancedEapSupported",
            controls: [
                FeatureControl(
                    id: "blink.enabled", title: "启用自动转向灯", footnote: "需 Advanced EAP 支持",
                    kind: .endpointToggle(
                        readKey: "enabled",
                        on: P4Route.blinkAEnable,
                        off: P4Route.blinkADisable
                    )
                ),
                FeatureControl(
                    id: "blink.delay", title: "打灯延迟", footnote: "0–2000 ms",
                    kind: .number(
                        key: "ms", range: 0...2000, step: 50, unit: "ms",
                        path: P4Route.blinkADelay, extra: []
                    ),
                    readKey: "delayMs"
                ),
                FeatureControl(
                    id: "blink.timing", title: "NOA 等待时间", footnote: "稳定期 1–20 秒 / 取消暂停 10–100 秒，同时提交",
                    kind: .pairNumber(
                        first: NumberSpec(key: "noaStabilizationSeconds", range: 1...20, unit: "秒"),
                        second: NumberSpec(key: "cancelPauseSeconds", range: 10...100, unit: "秒"),
                        path: P4Route.blinkATiming
                    )
                ),
                FeatureControl(
                    id: "blink.txMode", title: "发送模式", footnote: nil,
                    kind: .selectRead(
                        key: "mode",
                        readKey: "txMode",
                        options: [
                            .init(label: "发送一次", rawValue: "0"),
                            .init(label: "350 ms 连发", rawValue: "1"),
                        ],
                        path: P4Route.blinkATxMode,
                        extra: []
                    )
                ),
            ]
        ),
        FeatureModule(
            id: "light.strobe",
            title: "灯光爆闪",
            summary: "按设定频率快速切换转向灯，仅用于封闭场地展演；需要固件提供 /api/lights/strobe。",
            icon: "light.beacon.max",
            section: .body,
            statsPath: P4Route.lightStrobe,
            supportKey: nil,
            controls: [
                FeatureControl(
                    id: "strobe.enabled", title: "启动爆闪",
                    footnote: "运行中按频率切换转向灯；关闭即停止",
                    kind: .toggle(
                        key: "enabled",
                        path: P4Route.lightStrobe,
                        extra: ["hz", "durationMs", "pattern"]
                    ),
                    readKey: "active"
                ),
                FeatureControl(
                    id: "strobe.hz", title: "频率",
                    footnote: "1–8 Hz，越高对灯光驱动压力越大",
                    kind: .number(
                        key: "hz", range: 1...8, step: 1, unit: "Hz",
                        path: P4Route.lightStrobe, extra: []
                    )
                ),
                FeatureControl(
                    id: "strobe.duration", title: "持续时间",
                    footnote: "到达时间后自动停止（上限 10 秒）",
                    kind: .number(
                        key: "durationMs", range: 500...10000, step: 500, unit: "ms",
                        path: P4Route.lightStrobe, extra: []
                    )
                ),
                FeatureControl(
                    id: "strobe.pattern", title: "模式", footnote: nil,
                    kind: .select(
                        key: "pattern",
                        options: [
                            .init(label: "左右交替", rawValue: "alternate"),
                            .init(label: "仅左转灯", rawValue: "left"),
                            .init(label: "仅右转灯", rawValue: "right"),
                        ],
                        path: P4Route.lightStrobe,
                        extra: []
                    )
                ),
            ]
        ),

        FeatureModule(
            id: "door",
            title: "开门自动取消",
            summary: "开门时取消充电/空调等动作，需要车身 CAN（BODY）支持。",
            icon: "door.left.hand.open",
            section: .body,
            statsPath: P4Route.featuresStatus,
            supportKey: "bodyControlsSupported",
            controls: [
                FeatureControl(
                    id: "door.enabled", title: "启用开门取消", footnote: nil,
                    kind: .toggle(key: "enabled", path: P4Route.featuresDoorCancel, extra: []),
                    readKey: "doorCancel"
                ),
            ]
        ),

        FeatureModule(
            id: "isa",
            title: "ISA 限速提示抑制",
            summary: "抑制智能限速提示音（依当地法规自行决定）。",
            icon: "speedometer",
            section: .body,
            statsPath: P4Route.isaSuppressionConfig,
            supportKey: nil,
            controls: [
                FeatureControl(
                    id: "isa.enabled", title: "启用抑制", footnote: nil,
                    kind: .toggle(key: "enabled", path: P4Route.isaSuppressionConfig, extra: [])
                ),
            ]
        ),

        // MARK: 实验室功能

        FeatureModule(
            id: "lab",
            title: "实验室功能总开关",
            summary: "开启后才能使用实验区（LAB）全部功能；同时控制 S3XY 诊断与封禁车型方案。",
            icon: "flask",
            section: .lab,
            statsPath: P4Route.featuresStatus,
            supportKey: nil,
            controls: [
                FeatureControl(
                    id: "lab.enabled", title: "启用实验室功能", footnote: "关闭会暂停研究捕获与 DMS 捕获",
                    kind: .toggle(key: "enabled", path: P4Route.featuresLab, extra: []),
                    readKey: "lab"
                ),
                FeatureControl(
                    id: "lab.s3xy", title: "S3XY 诊断", footnote: nil,
                    kind: .toggle(key: "enabled", path: P4Route.featuresS3XY, extra: []),
                    readKey: "s3xy"
                ),
                FeatureControl(
                    id: "lab.banned", title: "封禁车型方案", footnote: "仅支持车型可用",
                    kind: .toggle(key: "enabled", path: P4Route.featuresBanned, extra: []),
                    readKey: "banned"
                ),
                FeatureControl(
                    id: "lab.tlsscRestore", title: "TLSSC 恢复", footnote: nil,
                    kind: .toggle(key: "enabled", path: P4Route.featuresTLSSCRestore, extra: []),
                    readKey: "tlsscRestore"
                ),
                FeatureControl(
                    id: "lab.apDrive", title: "AP 踏板配置", footnote: "需要支持的 0x334 路由",
                    kind: .toggle(key: "enabled", path: P4Route.featuresAPDriveProfile, extra: []),
                    readKey: "apDriveProfileEnabled", readPath: P4Route.pedalMapStats
                ),
                FeatureControl(
                    id: "lab.apRegen", title: "AP 能量回收档位", footnote: nil,
                    kind: .selectRead(
                        key: "regen",
                        readKey: "apDriveProfileRegenName",
                        options: [
                            .init(label: "标准 · 20", rawValue: "STANDARD"),
                            .init(label: "减弱 · 10", rawValue: "REDUCED"),
                            .init(label: "最小 · 1", rawValue: "MINIMAL"),
                        ],
                        path: P4Route.featuresAPDriveProfile,
                        extra: []
                    )
                ),
            ]
        ),

        FeatureModule(
            id: "vision",
            title: "视觉限速控制",
            summary: "禁用视觉限速控制注入，可选择 Chassis 或 Body 总线。",
            icon: "visionpro",
            section: .lab,
            statsPath: P4Route.visionControlStats,
            supportKey: "supported",
            controls: [
                FeatureControl(
                    id: "vision.disabled", title: "禁用视觉限速控制", footnote: "注意语义：开启 = 禁用",
                    kind: .toggle(key: "disabled", path: P4Route.visionControlUpdate, extra: []),
                    readKey: "requestDisabled"
                ),
                FeatureControl(
                    id: "vision.bus", title: "注入总线", footnote: nil,
                    kind: .select(
                        key: "bus",
                        options: [
                            .init(label: "Chassis", rawValue: "0"),
                            .init(label: "Body", rawValue: "1"),
                        ],
                        path: P4Route.visionControlUpdate,
                        extra: []
                    )
                ),
            ]
        ),

        FeatureModule(
            id: "heartbeat",
            title: "召唤心跳覆盖",
            summary: "维持召唤会话心跳（本次会话有效，重启后关闭）。",
            icon: "heart.text.square",
            section: .lab,
            statsPath: P4Route.summonHeartbeatStats,
            supportKey: nil,
            controls: [
                FeatureControl(
                    id: "hb.enabled", title: "启用心跳覆盖", footnote: "需同时提交原始值",
                    kind: .toggle(
                        key: "enabled", path: P4Route.summonHeartbeatUpdate,
                        extra: ["selectedValue"]
                    )
                ),
                FeatureControl(
                    id: "hb.value", title: "心跳原始值", footnote: "0–3",
                    kind: .selectRead(
                        key: "value",
                        readKey: "selectedValue",
                        options: (0...3).map { .init(label: "\($0)", rawValue: "\($0)") },
                        path: P4Route.summonHeartbeatUpdate,
                        extra: ["enabled"]
                    )
                ),
            ]
        ),

        FeatureModule(
            id: "window",
            title: "主驾车窗一键开",
            summary: "仅 Model 3 配置可用，抓取并复用原厂车窗指令。",
            icon: "car.side.front.open",
            section: .lab,
            statsPath: P4Route.driverWindowStats,
            supportKey: "supported",
            controls: [
                FeatureControl(
                    id: "window.open", title: "打开主驾车窗", footnote: "需车辆静止且信号就绪",
                    kind: .trigger(
                        path: P4Route.driverWindowOpen,
                        query: [],
                        confirmation: true,
                        destructive: false
                    )
                ),
            ]
        ),

        FeatureModule(
            id: "research",
            title: "CAN 研究捕获",
            summary: "按槽位打标签捕获 CAN 报文，用于离线分析（A–D 槽位）。",
            icon: "waveform",
            section: .lab,
            statsPath: P4Route.researchCaptureStats,
            supportKey: nil,
            controls: [
                FeatureControl(
                    id: "research.start", title: "开始捕获（槽位 A）", footnote: nil,
                    kind: .trigger(
                        path: P4Route.researchCaptureStart,
                        query: [P4Param("slot", "A")],
                        confirmation: false,
                        destructive: false
                    )
                ),
                FeatureControl(
                    id: "research.mode", title: "捕获模式", footnote: nil,
                    kind: .selectRead(
                        key: "mode",
                        readKey: "captureMode",
                        options: [
                            .init(label: "快照 SNAPSHOT", rawValue: "SNAPSHOT"),
                            .init(label: "原始跳变 RAW_TRANSITION", rawValue: "RAW_TRANSITION"),
                        ],
                        path: P4Route.researchCaptureMode,
                        extra: []
                    )
                ),
                FeatureControl(
                    id: "research.window", title: "捕获窗口", footnote: "前置 2–15 秒 / 后置 2–10 秒，同时提交",
                    kind: .pairNumber(
                        first: NumberSpec(key: "preMs", range: 2000...15000, unit: "ms"),
                        second: NumberSpec(key: "postMs", range: 2000...10000, unit: "ms"),
                        path: P4Route.researchCaptureConfig
                    )
                ),
                FeatureControl(
                    id: "research.reset", title: "重置捕获数据", footnote: nil,
                    kind: .trigger(
                        path: P4Route.researchCaptureReset,
                        query: [],
                        confirmation: true,
                        destructive: true
                    )
                ),
            ]
        ),

        // MARK: 高级与兼容

        FeatureModule(
            id: "country",
            title: "地区 / 地图区服",
            summary: "切换国家与地图区服（STOCK / US / KOREA / NEW ZEALAND）。",
            icon: "globe.asia.australia",
            section: .advanced,
            statsPath: P4Route.countryStats,
            supportKey: "countrySupported",
            controls: [
                FeatureControl(
                    id: "country.mode", title: "国家覆盖", footnote: nil,
                    kind: .select(
                        key: "countryMode",
                        options: [
                            .init(label: "原厂", rawValue: "0"),
                            .init(label: "US", rawValue: "1"),
                            .init(label: "KOREA", rawValue: "2"),
                            .init(label: "NEW ZEALAND", rawValue: "3"),
                        ],
                        path: P4Route.countryUpdate,
                        extra: []
                    )
                ),
                FeatureControl(
                    id: "country.map", title: "地图区服", footnote: nil,
                    kind: .select(
                        key: "mapMode",
                        options: [
                            .init(label: "原厂", rawValue: "0"),
                            .init(label: "US · 0", rawValue: "1"),
                            .init(label: "KOREA · 7", rawValue: "2"),
                        ],
                        path: P4Route.countryUpdate,
                        extra: []
                    )
                ),
            ]
        ),

        FeatureModule(
            id: "pedal",
            title: "踏板映射 (Pedal Map)",
            summary: "切换踏板/加速曲线档位，需 0x334 路由支持。",
            icon: "slider.horizontal.3",
            section: .advanced,
            statsPath: P4Route.pedalMapStats,
            supportKey: "pedalMapSupported",
            controls: [
                FeatureControl(
                    id: "pedal.mode", title: "踏板档位", footnote: nil,
                    kind: .select(
                        key: "mode",
                        options: [
                            .init(label: "原厂", rawValue: "STOCK"),
                            .init(label: "CHILL", rawValue: "CHILL"),
                            .init(label: "SPORT", rawValue: "SPORT"),
                            .init(label: "PERFORMANCE", rawValue: "PERFORMANCE"),
                        ],
                        path: P4Route.pedalMapSet,
                        extra: []
                    ),
                    readKey: "targetName"
                ),
            ]
        ),

        FeatureModule(
            id: "continuousAP",
            title: "常驻 AP（实验）",
            summary: "通过手势保持 AP 会话；方法与开关必须同时提交。",
            icon: "wifi.router",
            section: .advanced,
            statsPath: P4Route.continuousAPConfig,
            supportKey: "supported",
            controls: [
                FeatureControl(
                    id: "cap.enabled", title: "启用常驻 AP", footnote: nil,
                    kind: .toggle(
                        key: "enabled", path: P4Route.continuousAPConfig,
                        extra: ["method"]
                    )
                ),
                FeatureControl(
                    id: "cap.method", title: "触发手势", footnote: nil,
                    kind: .select(
                        key: "method",
                        options: [
                            .init(label: "未选择", rawValue: "0"),
                            .init(label: "拨杆下压", rawValue: "1"),
                            .init(label: "滚轮单击", rawValue: "2"),
                            .init(label: "滚轮双击", rawValue: "3"),
                        ],
                        path: P4Route.continuousAPConfig,
                        extra: ["enabled"]
                    )
                ),
            ]
        ),

        FeatureModule(
            id: "profile",
            title: "车型配置",
            summary: "只读查看当前车型/拓扑与三路总线角色。首次配置请在设备网页 Setup 流程完成（需重启）。",
            icon: "car.2",
            section: .advanced,
            statsPath: P4Route.profileStatus,
            supportKey: nil,
            controls: []
        ),
    ]

    static func modules(in section: FeatureModule.Section) -> [FeatureModule] {
        modules.filter { $0.section == section }
    }
}
