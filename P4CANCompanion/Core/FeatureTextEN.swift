import Foundation

/// 功能控件文案的英文表（键 = 中文原文）。
///
/// 控件在 `FeatureCatalog` 里有 70 处构造点，给每个 `FeatureControl` 加英文字段
/// 会让目录噪音翻倍；这里按中文原文查表，漏翻的条目自动回落到中文，
/// 不会出现空标题。新增控件时只需补一条（可选）。
@MainActor
enum FeatureTextEN {

    static func title(_ zh: String) -> String {
        L10n.t(zh, titles[zh] ?? zh)
    }

    static func footnote(_ zh: String) -> String {
        L10n.t(zh, footnotes[zh] ?? zh)
    }

    static func option(_ zh: String) -> String {
        L10n.t(zh, options[zh] ?? zh)
    }

    private static let titles: [String: String] = [
        "注入模式": "Injection mode",
        "右手滚轮注入": "Right scroll wheel injection",
        "无确认变道": "Confirm-free lane change",
        "启用自动转向灯": "Auto turn signal",
        "禁用视觉限速控制": "Disable vision speed control",
        "禁用 DMS 提醒": "Disable DMS alerts",
        "启用 NAG": "Enable NAG",
        "启用 TLSSC 注入": "Enable TLSSC injection",
        "非高速 ULC 策略": "Non-highway ULC",
        "高速禁用 ALC": "Disable ALC on highway",
        "启用常驻 AP": "Continuous AP",
        "忽略 AP 状态": "Ignore AP state",
        "启用 AP 加速 / 回收": "Enable AP accel / regen",
        "AP 策略": "AP strategy",
        "AP 开始前即生效": "Active before AP engages",
        "Bit18 策略": "Bit18 strategy",
        "HW3 兼容": "HW3 compatibility",
        "NOA 中阻断 TLSSC": "Block TLSSC in NOA",
        "NOA 等待时间": "NOA settle time",
        "R79 模式": "R79 mode",
        "TSL9 时序": "TSL9 timing",
        "TSL9 输入模式": "TSL9 input mode",
        "Mode 1 延迟": "Mode 1 delay",
        "Mode 1 重注入": "Mode 1 reinjection",
        "Mode 1 发送等待": "Mode 1 TX wait",
        "Mode 2 延迟": "Mode 2 delay",
        "Mode 2 重注入": "Mode 2 reinjection",
        "捕获 A · 立即可用": "Capture A · ready now",
        "捕获 B": "Capture B",
        "捕获 C": "Capture C",
        "捕获 D": "Capture D",
        "A · 正常前视": "A · normal forward gaze",
        "B · 短暂扫视屏幕": "B · brief glance at screen",
        "C · 持续侧看": "C · sustained side glance",
        "D · 低头": "D · head down",
        "E · 转向扭矩 + 移开视线": "E · steering torque + look away",
        "F · 前视，无主动扭矩": "F · forward gaze, no torque",

        "TSL9 周期注入": "TSL9 periodic injection",
        "TSL9 周期间隔": "TSL9 periodic interval",
        "TSL9 路由": "TSL9 route",
        "允许人工介入": "Allow manual override",
        "发送模式": "Send mode",
        "启用 AP 控制": "Enable AP control",
        "启用心跳覆盖": "Enable heartbeat override",
        "启用抑制": "Enable suppression",
        "启用自动变道": "Enable auto lane change",
        "国家覆盖": "Country override",
        "地图区服": "Map region",
        "延迟秒数": "Delay (seconds)",
        "开门按钮取消变道": "Door-button lane-change cancel",
        "心跳原始值": "Heartbeat raw value",
        "恢复默认参数": "Restore defaults",
        "打开主驾车窗": "Open driver window",
        "打灯延迟": "Turn-signal delay",
        "捕获模式": "Capture mode",
        "捕获窗口": "Capture window",
        "整个 AP 会话": "Entire AP session",
        "注入总线": "Injection bus",
        "注入方式": "Injection method",
        "滚轮波形": "Scroll wheel waveform",
        "滚轮注入间隔": "Wheel injection interval",
        "盲区策略": "Blind-spot strategy",
        "能量回收档位": "Regen level",
        "触发手势": "Trigger gesture",
        "踏板档位": "Pedal profile",
        "重置捕获数据": "Reset capture data",
        "零速暂停": "Pause at zero speed",
        "高速闸门": "Highway gate",
    ]

    private static let footnotes: [String: String] = [
        "关闭 = 仅 AP 激活后生效（原厂行为）": "Off = only while AP is active (stock behavior)",
        "注意语义：开启 = 禁用": "Note: On means disabled",
        "需要支持的 0x334 路由": "Requires a supported 0x334 route",
        "稳定期 1–20 秒 / 取消暂停 10–100 秒，同时提交": "Settle 1–20 s / cancel pause 10–100 s, submitted together",
        "前置 2–15 秒 / 后置 2–10 秒，同时提交": "Pre 2–15 s / post 2–10 s, submitted together",
        "需 Advanced EAP 支持": "Requires Advanced EAP",
        "随下一帧整车 CAN 生效；手动踏板目标仍保留在内存": "Applies on the next vehicle CAN frame; manual pedal targets stay in memory",
        "独立 enable / disable 端点": "Separate enable / disable endpoints",
        "保持 Hands-On 降级": "Keeps the hands-on fallback",
        "确认进入封闭道路后暂停 TLSSC": "Pauses TLSSC once a closed road is confirmed",
        "仅扭矩方式": "Torque-based only",
        "需要车型支持": "Requires vehicle support",
        "停车时停止注入": "Stops injection while parked",
        "需同时提交原始值": "Submit the raw value together",
        "关闭即恢复原厂提示": "Off restores the stock chime",
        "需车辆静止且信号就绪": "Vehicle must be stationary with signals ready",
        "按下后立即保持正常前视": "Keeps a normal forward gaze after pressing",
        "前置窗口已就绪时按此开始": "Start here once the pre-window is ready",
        "按下前门开门按钮即取消正在进行的变道": "Pressing the front-door button cancels an active lane change",
        "AP 未激活时也允许注入": "Inject even when AP is inactive",
        "BOTH 会同时在两路发送": "BOTH sends on both buses",
        "部分车型不支持（Confirm-Free unsupported）": "Some vehicles do not support it (Confirm-Free unsupported)",
        "CSV 可在「系统 → 日志」导出": "Export the CSV from System → Logs",
        "Mode H 为人体化波形（Mode C 已并入 H）": "Mode H is the humanized waveform (Mode C is folded into H)",
        "NOA 启动后释放覆盖": "Releases the override after NOA starts",
        "TSL9 需要对应车型支持": "TSL9 requires vehicle support",
        "0–30000 ms（0–30 秒）": "0–30000 ms (0–30 s)",
        "1–600 秒": "1–600 s",
        "2–10 秒": "2–10 s",
        "0–2000 ms": "0–2000 ms",
        "0–340 ms": "0–340 ms",
        "0–3": "0–3",
        "四个参数需一次提交": "All four parameters must be submitted together",
        "此开关必须单独提交": "This switch must be submitted on its own",
    ]

    private static let options: [String: String] = [
        "原厂": "Stock",
        "未选择": "Not selected",
        "发送一次": "Send once",
        "左侧音量键": "Left scroll wheel",
        "扭矩 · 既有方式": "Torque · existing",
        "快速回显 · 0 ms": "Fast echo · 0 ms",
        "最小 · 1": "Min · 1",
        "减弱 · 10": "Reduced · 10",
        "扩展 · 2/3/4→1": "Expanded · 2/3/4→1",
        "标准 · 20": "Standard · 20",
        "极激进 (MAD MAX)": "Extreme (MAD MAX)",
        "强制 0": "Force 0",
        "等待 2 ms": "Wait 2 ms",
        "原始跳变 RAW_TRANSITION": "Raw transition",
        "快照 SNAPSHOT": "Snapshot",
        "350 ms 连发": "350 ms burst",
        "AP 期间阻断": "Block during AP",
        "Mode A · 经典扭矩表": "Mode A · classic torque table",
        "Mode H · 人体化": "Mode H · humanized",
        "V8.2 原始 · 4→1": "V8.2 raw · 4→1",
        "AP 之后延迟": "Delay after AP",
        "关闭": "Off",
        "开启": "On",
        "右侧车速键": "Right scroll wheel",
        "拨杆下压": "Stalk press",
        "标准": "Standard",
        "滚轮单击": "Single click",
        "滚轮双击": "Double click",
        "激进": "Aggressive",
    ]
}

extension FeatureControl {
    /// 控件标题（英文模式查表，缺条目回落中文）。
    @MainActor var localizedTitle: String { FeatureTextEN.title(title) }
    @MainActor var localizedFootnote: String? { footnote.map { FeatureTextEN.footnote($0) } }
}

extension FeatureControl.Option {
    @MainActor var localizedLabel: String { FeatureTextEN.option(label) }
}
