import Foundation
import SwiftUI

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
/// 读取名与提交名不一致时用 `"statsKey:submitKey"`（如 `selectedValue:value`），
/// 这类不一致会让固件返回 400，表现为「点了没反应」，可用
/// `build/tools/check_api_contract.py` 批量核对。
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
        /// 读取状态时用来匹配的值（可能是数值，也可能是固件上报的名称）。
        let rawValue: String
        /// 提交给固件的值；与 `rawValue` 不同的场景（如读取 STANDARD、提交 20）在此单独声明。
        let submitValue: String

        init(label: String, rawValue: String, submitValue: String? = nil) {
            self.label = label
            self.rawValue = rawValue
            self.submitValue = submitValue ?? rawValue
        }

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
    /// 读取状态需要等于某个整数才算「开」（如 ULC alcMode==2 表示关闭 ALC）。
    var readEquals: Int? = nil
}

/// 一个功能模块：标题、说明、状态端点与控件集合。
struct FeatureModule: Identifiable, Sendable {
    enum Section: String, CaseIterable, Sendable {
        // 顺序即功能页的分组顺序：灯光放最前（外观类、最常演示），
        // 实验室工具已并入「功能」，不再单独分组。
        case lighting = "灯光"
        case driving = "功能"
        case body = "车身与舒适"
        case advanced = "实验"

        /// 分组色板：决定图标瓦片底色，让「灯光/驾驶辅助/车身」一眼可分。
        var tint: Color {
            switch self {
            case .lighting: return P4Palette.orange
            case .driving: return P4Palette.blue
            case .body: return P4Palette.green
            case .advanced: return P4Palette.indigo
            }
        }

        var englishName: String {
            switch self {
            case .lighting: return "Lighting"
            case .driving: return "Features"
            case .body: return "Body"
            case .advanced: return "Experimental"
            }
        }

        /// 分组头的小图标（与模块图标同一套 emoji 语言）。
        var emoji: String {
            switch self {
            case .lighting: return "💡"
            case .driving: return "🚗"
            case .body: return "🚪"
            case .advanced: return "⚙️"
            }
        }
    }

    let id: String
    let title: String
    let summary: String
    /// 英文标题 / 摘要（采用固件网页的原措辞）
    var titleEN: String = ""
    var summaryEN: String = ""
    let icon: String
    let section: Section
    /// 详情页轮询的状态端点（GET）
    let statsPath: String
    /// 能力位键（features/status 或 profile/status），nil 表示不检查
    let supportKey: String?
    let controls: [FeatureControl]

    @MainActor var localizedTitle: String {
        L10n.t(title, titleEN.isEmpty ? title : titleEN)
    }

    @MainActor var localizedSummary: String {
        L10n.t(summary, summaryEN.isEmpty ? summary : summaryEN)
    }
}

/// 功能目录：严格对应开源固件 web_api.h 的接口与取值域。
enum FeatureCatalog {

    static let modules: [FeatureModule] = [
FeatureModule(
            id: "headlight",
            title: "前大灯爆闪",
            summary: "远光灯按设定次数与间隔快速闪烁，结束后恢复触发前的灯光状态。",
            titleEN: "Headlight Strobe",
            summaryEN: "Flash the high beams a set number of times, then restore the previous light state.",
            icon: "light.beacon.max.fill",
            section: .lighting,
            statsPath: P4Route.headlightStrobeStats,
            supportKey: nil,
            controls: []
        ),
FeatureModule(
            id: "rearFog",
            title: "后雾灯爆闪",
            summary: "注入 0x273 的后雾灯位：开始后连续闪烁，单次最长 30 秒，结束自动恢复。",
            titleEN: "Rear Fog Strobe",
            summaryEN: "Pulse the rear fog lamp via 0x273 for up to 30 seconds, then restore automatically.",
            icon: "cloud.fog.fill",
            section: .lighting,
            statsPath: P4Route.rearFogStrobeStats,
            supportKey: nil,
            controls: []
        ),
FeatureModule(
            id: "nag",
            title: "NAG 抑制（Nag Killer）",
            summary: "扭矩表 / TSL9 两种注入方式，含 Mode A/B/C/H 波形与右手滚轮注入。",
            titleEN: "Nag Killer",
            summaryEN: "Reduce steering-wheel reminders during Autopilot.",
            icon: "steeringwheel",
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
                    id: "nag.pauseLaneChange", title: "变道时暂停", footnote: "AP 自动变道时暂停扭矩注入",
                    kind: .toggle(key: "pauseDuringLaneChange", path: P4Route.nagUpdate, extra: [])
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
                    id: "nag.rightScrollPattern", title: "滚轮波形", footnote: nil,
                    kind: .selectRead(
                        key: "torqueRightScrollPattern",
                        readKey: "torqueRightScrollPattern",
                        options: [
                            .init(label: "+1 → 0 → −1 → 0", rawValue: "0"),
                            .init(label: "+1 → −1", rawValue: "1"),
                        ],
                        path: P4Route.nagUpdate,
                        extra: []
                    )
                ),
                FeatureControl(
                    id: "nag.tsl9Window", title: "整个 AP 会话", footnote: "保持 Hands-On 降级",
                    kind: .toggle(key: "tsl9Window", path: P4Route.nagUpdate, extra: []),
                    readKey: "tsl9Window"
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
            id: "isa",
            title: "ISA 限速提示抑制",
            summary: "抑制智能限速提示音（依当地法规自行决定）。",
            titleEN: "ISA Suppression",
            summaryEN: "Reduce ISA warning chimes during Autopilot.",
            icon: "speedometer",
            section: .driving,
            statsPath: P4Route.isaSuppressionConfig,
            supportKey: nil,
            controls: [
                FeatureControl(
                    id: "isa.enabled", title: "启用抑制", footnote: nil,
                    kind: .toggle(key: "enabled", path: P4Route.isaSuppressionConfig, extra: [])
                ),
            ]
        ),
FeatureModule(
            id: "vision",
            title: "视觉限速控制",
            summary: "禁用视觉限速控制注入，可选择 Chassis 或 Body 总线。",
            titleEN: "Visual Speed Control",
            summaryEN: "Applies during Autopilot · default off.",
            icon: "camera.viewfinder",
            section: .driving,
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
            id: "dms",
            title: "禁用驾驶员监控",
            summary: "AP 期间请求关闭座舱摄像头监控（需要车型支持）。",
            titleEN: "Disable Driver Monitoring",
            summaryEN: "Request cabin-camera monitoring off during Autopilot.",
            icon: "eye.slash",
            section: .driving,
            statsPath: P4Route.dmsConfig,
            supportKey: "dmsNagSupported",
            controls: [
                FeatureControl(
                    id: "dms.enabled", title: "禁用 DMS 提醒", footnote: "需要车型支持",
                    kind: .toggle(key: "enabled", path: P4Route.dmsConfig, extra: [])
                ),
            ]
        ),
FeatureModule(
            id: "blink",
            title: "自动转向灯 (BlinkA)",
            summary: "NOA 变道自动打灯，含稳定期、取消暂停与发送模式。",
            titleEN: "Auto Blinker",
            summaryEN: "Trigger a turn signal for a detected NOA lane change.",
            icon: "arrow.triangle.turn.up.right.diamond.fill",
            section: .driving,
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
                    id: "blink.delay", title: "打灯延迟", footnote: "0–30000 ms（0–30 秒）",
                    kind: .number(
                        key: "ms", range: 0...30_000, step: 50, unit: "ms",
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
                FeatureControl(
                    id: "blink.doorCancel", title: "开门按钮取消变道",
                    footnote: "按下前门开门按钮即取消正在进行的变道",
                    kind: .toggle(key: "enabled", path: P4Route.featuresDoorCancel, extra: []),
                    readKey: "doorCancel",
                    readPath: P4Route.featuresStatus
                ),
            ]
        ),
FeatureModule(
            id: "summon",
            title: "召唤状态",
            summary: "查看召唤会话、确认挡位、信号新鲜度与发送队列（只读）。",
            titleEN: "Summon Status",
            summaryEN: "View the current Summon session and status.",
            icon: "dot.radiowaves.left.and.right",
            section: .driving,
            statsPath: P4Route.summonStats,
            supportKey: nil,
            controls: []
        ),
FeatureModule(
            id: "tlssc",
            title: "TLSSC 交通灯 / 停车标志",
            summary: "AP 期间注入红绿灯与停车标志控制；高速与 NOA 闸门可按需放行。",
            titleEN: "TLSSC",
            summaryEN: "Traffic-light and stop-sign control during AP.",
            icon: "octagon.fill",
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
                    id: "summon.highwayGate", title: "高速闸门", footnote: "确认进入封闭道路后暂停 TLSSC",
                    kind: .toggle(key: "enabled", path: P4Route.summonTLSSCHighwayGate, extra: []),
                    readKey: "tlsscHighwayGateEnabled"
                ),
                FeatureControl(
                    id: "summon.noaBlock", title: "NOA 中阻断 TLSSC", footnote: "NOA 启动后释放覆盖",
                    kind: .toggle(key: "enabled", path: P4Route.summonTLSSCNoABlock, extra: []),
                    readKey: "tlsscBlockInNoa"
                ),
            ]
        ),
FeatureModule(
            id: "alc",
            title: "自动拨杆变道 (ALC)",
            summary: "拨杆触发变道注入，可选择注入总线（CAN A / CAN B / 双路）。",
            titleEN: "Auto Lane Change",
            summaryEN: "Experimental 0x293 UI_autoLaneChange enable.",
            icon: "road.lanes",
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
            id: "pedal",
            title: "踏板映射 (Pedal Map)",
            summary: "切换踏板/加速曲线档位，需 0x334 路由支持。",
            titleEN: "Pedal Response",
            summaryEN: "Acceleration response mapping.",
            icon: "slider.horizontal.3",
            section: .driving,
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
            id: "apDrive",
            title: "AP 加速 / 回收",
            summary: "AP 期间使用 CHILL 加速与所选能量回收档位；退出 AP 后恢复手动驾驶响应。",
            titleEN: "AP Accel / Regen",
            summaryEN: "Use Chill acceleration and chosen regen during AP.",
            icon: "car.side",
            section: .driving,
            statsPath: P4Route.pedalMapStats,
            supportKey: "apDriveProfileSupported",
            controls: [
                FeatureControl(
                    id: "apDrive.enabled", title: "启用 AP 加速 / 回收",
                    footnote: "需要支持的 0x334 路由",
                    kind: .toggle(key: "enabled", path: P4Route.featuresAPDriveProfile, extra: []),
                    readKey: "apDriveProfileEnabled"
                ),
                FeatureControl(
                    id: "apDrive.regen", title: "能量回收档位",
                    footnote: "随下一帧整车 CAN 生效；手动踏板目标仍保留在内存",
                    kind: .selectRead(
                        key: "regen",
                        readKey: "apDriveProfileRegenName",
                        options: [
                            .init(label: "标准 · 20", rawValue: "STANDARD", submitValue: "20"),
                            .init(label: "减弱 · 10", rawValue: "REDUCED", submitValue: "10"),
                            .init(label: "最小 · 1", rawValue: "MINIMAL", submitValue: "1"),
                        ],
                        path: P4Route.featuresAPDriveProfile,
                        extra: []
                    )
                ),
            ]
        ),
FeatureModule(
            id: "lighting",
            title: "灯光功能",
            summary: "AP 期间强制远光（需拨杆车型）与动态刹车灯（轻踩 / 重踩）。",
            titleEN: "Lighting Features",
            summaryEN: "AP forced high beam (stalk profiles) and dynamic brake lights.",
            icon: "headlight.high.beam.fill",
            section: .driving,
            statsPath: P4Route.lightingStats,
            supportKey: nil,
            controls: []
        ),
FeatureModule(
            id: "preheat",
            title: "电池预热",
            summary: "充电前主动请求 BMS 加热电池，达到目标温度或电池已暖后自动关闭。",
            titleEN: "Battery Preheat",
            summaryEN: "Ask the BMS to heat the pack before charging; stops at the target or when warm.",
            icon: "thermometer.sun.fill",
            section: .driving,
            statsPath: P4Route.preheatStats,
            supportKey: "preheatSupported",
            controls: []
        ),
FeatureModule(
            id: "r79ap",
            title: "R79 AP 控制",
            summary: "AP 期间阻断或延迟 R79 注入；3.35.8 起可让驻车 / 召唤时暂停其他功能。",
            titleEN: "R79 AP Control",
            summaryEN: "Set R79 behavior during AP and manual driving.",
            icon: "car.circle",
            section: .driving,
            statsPath: P4Route.r79APControlStats,
            supportKey: nil,
            controls: [
                FeatureControl(
                    id: "r79ap.enabled", title: "启用 AP 控制", footnote: "一次提交全部参数（旧固件 4 个，3.35.8 起 5 个）",
                    kind: .toggle(
                        key: "enabled", path: P4Route.r79APControlUpdate,
                        extra: ["mode", "delaySeconds", "allowManualDriving", "blockTxInPark?"]
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
                        extra: ["enabled", "delaySeconds", "allowManualDriving", "blockTxInPark?"]
                    )
                ),
                FeatureControl(
                    id: "r79ap.delay", title: "延迟秒数", footnote: "2–10 秒",
                    kind: .number(
                        key: "delaySeconds", range: 2...10, step: 1, unit: "秒",
                        path: P4Route.r79APControlUpdate,
                        extra: ["enabled", "mode", "allowManualDriving", "blockTxInPark?"]
                    )
                ),
                FeatureControl(
                    id: "r79ap.manual", title: "允许人工介入", footnote: nil,
                    kind: .toggle(
                        key: "allowManualDriving", path: P4Route.r79APControlUpdate,
                        extra: ["enabled", "mode", "delaySeconds", "blockTxInPark?"]
                    )
                ),
                FeatureControl(
                    id: "r79ap.blockPark", title: "驻车 / 召唤时暂停其他功能",
                    footnote: "3.35.8 新增；P 档或召唤时暂停额外功能，避免互相干扰",
                    kind: .toggle(
                        key: "blockTxInPark", path: P4Route.r79APControlUpdate,
                        extra: ["enabled", "mode", "delaySeconds", "allowManualDriving"]
                    )
                ),
            ]
        ),
FeatureModule(
            id: "r79status",
            title: "R79 状态",
            summary: "只读查看当前 R79 发送器的策略、MUX1 收发计数与静默状态。",
            titleEN: "R79 Status",
            summaryEN: "Read-only status of the selected R79 transmitter.",
            icon: "antenna.radiowaves.left.and.right",
            section: .driving,
            statsPath: P4Route.r79Stats,
            supportKey: nil,
            controls: []
        ),
FeatureModule(
            id: "heartbeat",
            title: "召唤心跳覆盖",
            summary: "维持召唤会话心跳（本次会话有效，重启后关闭）。",
            titleEN: "Summon Heartbeat Override",
            summaryEN: "0x3F8 UI_driverAssistControl override.",
            icon: "heart.text.square",
            section: .driving,
            statsPath: P4Route.summonHeartbeatStats,
            supportKey: nil,
            controls: [
                FeatureControl(
                    id: "hb.enabled", title: "启用心跳覆盖", footnote: "需同时提交原始值",
                    kind: .toggle(
                        key: "enabled", path: P4Route.summonHeartbeatUpdate,
                        // 固件读 value，stats 里叫 selectedValue → 用 "read:write" 别名提交
                        extra: ["selectedValue:value"]
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
            summary: "仅 Model YL（三电机）配置可用，需车辆静止；抓取并复用原厂车窗指令。",
            titleEN: "Driver Window Test",
            summaryEN: "Model YL (Triple YL) only · PARK required.",
            icon: "rectangle.split.3x1",
            section: .driving,
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
            titleEN: "CAN Research Capture",
            summaryEN: "BODY + CHASSIS + PARTY research recording.",
            icon: "record.circle",
            section: .driving,
            statsPath: P4Route.researchCaptureStats,
            supportKey: nil,
            controls: [
                FeatureControl(
                    id: "research.start.a", title: "捕获 A · 立即可用",
                    footnote: "前置窗口已就绪时按此开始",
                    kind: .trigger(
                        path: P4Route.researchCaptureStart,
                        query: [P4Param("slot", "A")],
                        confirmation: false,
                        destructive: false
                    )
                ),
                FeatureControl(
                    id: "research.start.b", title: "捕获 B",
                    footnote: nil,
                    kind: .trigger(
                        path: P4Route.researchCaptureStart,
                        query: [P4Param("slot", "B")],
                        confirmation: false,
                        destructive: false
                    )
                ),
                FeatureControl(
                    id: "research.start.c", title: "捕获 C",
                    footnote: nil,
                    kind: .trigger(
                        path: P4Route.researchCaptureStart,
                        query: [P4Param("slot", "C")],
                        confirmation: false,
                        destructive: false
                    )
                ),
                FeatureControl(
                    id: "research.start.d", title: "捕获 D",
                    footnote: nil,
                    kind: .trigger(
                        path: P4Route.researchCaptureStart,
                        query: [P4Param("slot", "D")],
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
FeatureModule(
            id: "dmscapture",
            title: "驾驶员监控捕获",
            summary: "只读录制 0x389 / 0x5D9 / 0x247 / 0x399 / 0x370 的交互与手扶状态；固定前置 2 秒 + 后置 5 秒，A–F 六种测试条件。",
            titleEN: "Driver Monitoring Capture",
            summaryEN: "Record driver-monitoring signals.",
            icon: "video",
            section: .driving,
            statsPath: P4Route.dmsStats,
            supportKey: nil,
            controls: [
                FeatureControl(
                    id: "dmscap.a", title: "A · 正常前视", footnote: "按下后立即保持正常前视",
                    kind: .trigger(path: P4Route.dmsStart, query: [P4Param("slot", "A")],
                                   confirmation: false, destructive: false)
                ),
                FeatureControl(
                    id: "dmscap.b", title: "B · 短暂扫视屏幕", footnote: nil,
                    kind: .trigger(path: P4Route.dmsStart, query: [P4Param("slot", "B")],
                                   confirmation: false, destructive: false)
                ),
                FeatureControl(
                    id: "dmscap.c", title: "C · 持续侧看", footnote: nil,
                    kind: .trigger(path: P4Route.dmsStart, query: [P4Param("slot", "C")],
                                   confirmation: false, destructive: false)
                ),
                FeatureControl(
                    id: "dmscap.d", title: "D · 低头", footnote: nil,
                    kind: .trigger(path: P4Route.dmsStart, query: [P4Param("slot", "D")],
                                   confirmation: false, destructive: false)
                ),
                FeatureControl(
                    id: "dmscap.e", title: "E · 转向扭矩 + 移开视线", footnote: nil,
                    kind: .trigger(path: P4Route.dmsStart, query: [P4Param("slot", "E")],
                                   confirmation: false, destructive: false)
                ),
                FeatureControl(
                    id: "dmscap.f", title: "F · 前视，无主动扭矩", footnote: nil,
                    kind: .trigger(path: P4Route.dmsStart, query: [P4Param("slot", "F")],
                                   confirmation: false, destructive: false)
                ),
                FeatureControl(
                    id: "dmscap.reset", title: "重置捕获数据", footnote: "CSV 可在「系统 → 日志」导出",
                    kind: .trigger(path: P4Route.dmsReset, query: [],
                                   confirmation: true, destructive: true)
                ),
            ]
        ),
FeatureModule(
            id: "modeh",
            title: "Mode H 调参",
            summary: "Mode H 波形的主峰值、等待、不应期、反向载波与 Hands-On 策略；含实时引擎监视。",
            titleEN: "Mode H Tuning",
            summaryEN: "Mode H profile tuning and live engine monitor.",
            icon: "dial.medium",
            section: .driving,
            statsPath: P4Route.nagHProfileStats,
            supportKey: "nagSupported",
            controls: []
        ),
FeatureModule(
            id: "r79Timing",
            title: "R79 时序捕获",
            summary: "记录 R79 请求与控制器完成时序，导出 CSV 分析延迟与失败原因。",
            titleEN: "R79 Timing Capture",
            summaryEN: "Capture R79 request/completion timing and export a CSV.",
            icon: "timer",
            section: .driving,
            statsPath: P4Route.r79TimingStatus,
            supportKey: nil,
            controls: []
        ),
FeatureModule(
            id: "r79",
            title: "R79 / EU 解锁",
            summary: "Mode 1/2 波形、Bit18 策略与 HW3 兼容（HW3 必须单独提交）。",
            titleEN: "R79 / EU Unlock",
            summaryEN: "R79 mode, bit18 / bit19 and HW3 legacy policy.",
            icon: "gearshape.2",
            section: .advanced,
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
                        key: "mode1DelayMs", range: 0...340, step: 1, unit: "ms",
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
                        key: "mode2DelayMs", range: 0...2000, step: 1, unit: "ms",
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
            id: "smartShift",
            title: "SmartShift 自动换挡",
            summary: "实验性自动换挡：刹车确认后由 BODY 发出挡位请求，含车速与障碍物门槛。",
            titleEN: "SmartShift",
            summaryEN: "Experimental automatic shifting with brake confirmation, speed and obstacle gates.",
            icon: "gearshift.layout.sixspeed",
            section: .advanced,
            statsPath: P4Route.smartShiftStats,
            supportKey: nil,
            controls: []
        ),
FeatureModule(
            id: "country",
            title: "地区 / 地图区服",
            summary: "切换国家与地图区服（STOCK / US / KOREA / NEW ZEALAND）。",
            titleEN: "Country / Map",
            summaryEN: "Country and map presets for every valid CAN profile.",
            icon: "globe",
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
            id: "ulc",
            title: "无确认变道 (ULC)",
            summary: "变道确认、高速禁用与盲区策略（blind: 标准 / 激进 / 极激进）。",
            titleEN: "Lane Change",
            summaryEN: "Confirmation, off-highway flag and blind-spot policy.",
            icon: "arrow.left.arrow.right",
            section: .advanced,
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
                    readKey: "alcMode",
                    readEquals: 2
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
                    id: "ulc.timing", title: "AP 开始前即生效",
                    footnote: "关闭 = 仅 AP 激活后生效（原厂行为）",
                    kind: .toggle(key: "timing", path: P4Route.ulcUpdate, extra: []),
                    readKey: "stalkConfirmTimingMode",
                    readEquals: 1
                ),
            ]
        ),
FeatureModule(
            id: "continuousAP",
            title: "常驻 AP（实验）",
            summary: "通过手势保持 AP 会话；方法与开关必须同时提交。",
            titleEN: "Continuous AP",
            summaryEN: "Re-engage AP after a signaled lane change.",
            icon: "location.north.line",
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
            id: "fsd",
            title: "Developer Test · FSD 可视化",
            summary: "3.35.8 把 Developer Test 合并到这里：注入 FSD 可视化标志，可设 AP 激活时暂停。打开后会阻断 AP。",
            titleEN: "Developer Test · FSD Visualisation",
            summaryEN: "3.35.8 folds Developer Test into this page: inject the FSD visualisation flag, optionally suspended during AP. Enabling it blocks AP.",
            icon: "wand.and.stars",
            section: .advanced,
            statsPath: P4Route.fsdStats,
            supportKey: nil,
            controls: []
        ),
FeatureModule(
            id: "devTest",
            title: "Developer Test",
            summary: "覆盖 CHASSIS 0x3FD 的六路 UI 信号，仅用于测试。",
            titleEN: "Developer Test",
            summaryEN: "Override six UI signals on CHASSIS 0x3FD for testing.",
            icon: "wrench.adjustable.fill",
            section: .advanced,
            statsPath: P4Route.developerTestStats,
            supportKey: nil,
            controls: []
        ),
FeatureModule(
            id: "summonVersion",
            title: "召唤版本标识",
            summary: "覆盖 0x259 的 APP_summonVersionIdentifier，仅在 P 档或召唤时注入。",
            titleEN: "Summon Version",
            summaryEN: "Override APP_summonVersionIdentifier on 0x259 while parked or summoning.",
            icon: "car.side.arrowtriangle.up",
            section: .advanced,
            statsPath: P4Route.summonVersionStats,
            supportKey: nil,
            controls: []
        ),
FeatureModule(
            id: "profile",
            title: "车型配置",
            summary: "只读查看当前车型/拓扑与三路总线角色；要切换车型请回设置页点「更改车型」（保存后设备重启）。",
            titleEN: "Vehicle Profile",
            summaryEN: "Model, topology and stalk selection. Change it from Settings — the device reboots after saving.",
            icon: "car.side.fill",
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
