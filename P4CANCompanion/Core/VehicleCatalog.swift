import Foundation

/// 车辆视角：P 挡斜前方，D / N 挡侧面，R 挡斜后方。
enum VehicleAngle: Int, CaseIterable, Sendable {
    case front, side, rear

    static func forGear(_ gear: String?) -> VehicleAngle {
        switch gear {
        case "D", "N": return .side
        case "R": return .rear
        default: return .front
        }
    }
}

/// 车漆或轮毂选项（特斯拉选装代码）。
struct VehicleOption: Identifiable, Hashable, Sendable {
    let code: String
    let zh: String
    let en: String
    /// 车漆色块（sRGB 十六进制），轮毂为 nil
    var swatch: UInt32? = nil
    /// 配置器没有该轮毂的斜后方图，R 挡改用侧面视角
    var rearUsesSide = false
    var id: String { code }
}

/// 一个具体版本（标准续航、长续航、Performance、Plaid 等）及其可选车漆、轮毂。
struct VehicleTrim: Identifiable, Hashable, Sendable {
    let code: String
    let zh: String
    let en: String
    /// 配置器出图需要的内饰代码；旧车型不需要
    let interior: String?
    let paints: [VehicleOption]
    let wheels: [VehicleOption]
    var id: String { code }

    func paint(_ code: String?) -> VehicleOption { paints.first { $0.code == code } ?? paints[0] }
    func wheel(_ code: String?) -> VehicleOption { wheels.first { $0.code == code } ?? wheels[0] }
}

/// 一代车型在特斯拉配置器图片接口中的参数与全部版本。
struct VehicleGeneration: Identifiable, Hashable, Sendable {
    let id: String
    let zh: String
    let en: String
    let model: String
    /// 斜前方、侧面、斜后方三个视角名；没有可用斜后方图的车型第三项与侧面相同
    let views: [String]
    let trims: [VehicleTrim]

    func trim(_ code: String?) -> VehicleTrim { trims.first { $0.code == code } ?? trims[0] }
}

/// 用户在「车辆外观」中的选择（UserDefaults 键）；车型为空字符串表示跟随设备车型。
enum VehicleAppearanceKeys {
    static let generation = "vehicle.generation"
    static let trim = "vehicle.trim"
    static let paint = "vehicle.paint"
    static let wheel = "vehicle.wheel"
}

struct VehicleAppearance: Equatable, Sendable {
    let generation: VehicleGeneration
    let trim: VehicleTrim
    let paint: VehicleOption
    let wheel: VehicleOption
}

enum VehicleCatalog {
    static let host = "static-assets.tesla.cn"
    static let imageSize = 1200

    // MARK: 车漆

    private static func paint(_ code: String, _ zh: String, _ en: String, _ swatch: UInt32) -> VehicleOption {
        VehicleOption(code: code, zh: zh, en: en, swatch: swatch)
    }

    private static let PPSW = paint("PPSW", "珍珠白（多涂层）", "Pearl White Multi-Coat", 0xF2F2F0)
    private static let PBSB = paint("PBSB", "纯黑色", "Solid Black", 0x111214)
    private static let PMBL = paint("PMBL", "黑曜石黑", "Obsidian Black Metallic", 0x1A1A1D)
    private static let PMNG = paint("PMNG", "午夜银", "Midnight Silver Metallic", 0x4A4D52)
    private static let PPSB = paint("PPSB", "深海蓝", "Deep Blue Metallic", 0x1E3A78)
    private static let PPMR = paint("PPMR", "红色多涂层", "Red Multi-Coat", 0xB01219)
    private static let PBCW = paint("PBCW", "纯白色", "Solid White", 0xF4F4F4)
    private static let PMSS = paint("PMSS", "银色", "Silver Metallic", 0xBFC1C3)
    private static let PPTI = paint("PPTI", "钛金色", "Titanium Metallic", 0x8B8170)
    private static let PN00 = paint("PN00", "快银", "Quicksilver", 0xB9BBBE)
    private static let PN01 = paint("PN01", "星空灰", "Stealth Grey", 0x45484D)
    private static let PN03 = paint("PN03", "星光金", "Cosmic Silver", 0xB8B0A2)
    private static let PR01 = paint("PR01", "烈焰红", "Ultra Red", 0xB5121B)
    private static let PX02 = paint("PX02", "星钻黑", "Diamond Black", 0x16171A)
    private static let PB00 = paint("PB00", "霜蓝", "Frost Blue Metallic", 0x8FA9C4)
    private static let PB01 = paint("PB01", "冰河蓝", "Glacier Blue", 0x6F8DA8)
    private static let PB02 = paint("PB02", "海洋蓝", "Marine Blue", 0x1F2F57)

    // MARK: 轮毂

    private static func wheel(_ code: String, _ zh: String, _ en: String, rearUsesSide: Bool = false) -> VehicleOption {
        VehicleOption(code: code, zh: zh, en: en, rearUsesSide: rearUsesSide)
    }

    private static let WY18P = wheel("WY18P", "18 英寸 Aperture 轮毂", "18\" Aperture Wheels")
    private static let WY19P = wheel("WY19P", "19 英寸交互风暴轮毂", "19\" Crossflow Wheels")
    private static let WY20A = wheel("WY20A", "20 英寸螺旋风暴轮毂（首发版）", "20\" Helix 2.0 Wheels (Launch Series)")
    private static let WY20B = wheel("WY20B", "20 英寸螺旋风暴轮毂", "20\" Helix 2.0 Wheels")
    private static let WY21A = wheel("WY21A", "21 英寸蛛网轮毂 2.0", "21\" Arachnid 2.0 Wheels")
    private static let WY19L = wheel("WY19L", "19 英寸旋动机甲轮毂", "19\" Machina 2.0 Wheels")
    private static let WY20L = wheel("WY20L", "20 英寸 Uberhelix 轮毂", "20\" Uberhelix Wheels")
    private static let WY19B = wheel("WY19B", "19 英寸双子星轮毂", "19\" Gemini Wheels")
    private static let WY19C = wheel("WY19C", "19 英寸双子星轮毂（深色）", "19\" Gemini Dark Wheels")
    private static let WY20P = wheel("WY20P", "20 英寸感应轮毂", "20\" Induction Wheels")
    private static let WY21P = wheel("WY21P", "21 英寸 Überturbine 轮毂", "21\" Überturbine Wheels")
    private static let W38A = wheel("W38A", "18 英寸光子轮毂", "18\" Photon Wheels")
    private static let W38C = wheel("W38C", "18 英寸 Prismata 轮毂", "18\" Prismata Wheels")
    private static let W39D = wheel("W39D", "19 英寸深色新星轮毂", "19\" Dark Nova Wheels")
    private static let W39C = wheel("W39C", "19 英寸曲速轮毂", "19\" Warp Wheels")
    private static let W30P = wheel("W30P", "20 英寸曲速轮毂", "20\" Warp Wheels")
    private static let W38B = wheel("W38B", "18 英寸空气动力轮毂", "18\" Aero Wheels")
    private static let W39B = wheel("W39B", "19 英寸运动轮毂", "19\" Sport Wheels")
    private static let W40B = wheel("W40B", "18 英寸空气动力轮毂（2021 款）", "18\" Aero Wheels (2021)")
    private static let W41B = wheel("W41B", "19 英寸运动轮毂（2021 款）", "19\" Sport Wheels (2021)")
    private static let W33D = wheel("W33D", "20 英寸 Überturbine 轮毂", "20\" Überturbine Wheels")
    private static let WX01 = wheel("WX01", "20 英寸 Cyberstream 轮毂（Plaid 红卡钳）", "20\" Cyberstream Wheels (Plaid)")
    private static let WX21 = wheel("WX21", "22 英寸 Turbine 轮毂（Plaid 红卡钳）", "22\" Turbine Wheels (Plaid)")
    private static let WTAS = wheel("WTAS", "19 英寸银色 Slipstream 轮毂", "19\" Silver Slipstream Wheels")
    private static let WTDS = wheel("WTDS", "19 英寸灰色 Slipstream 轮毂", "19\" Grey Slipstream Wheels")
    private static let WTTC = wheel("WTTC", "21 英寸 Sonic Carbon 双涡轮轮毂", "21\" Sonic Carbon Twin Turbine Wheels")
    private static let WTAB = wheel("WTAB", "21 英寸黑色 Arachnid 轮毂", "21\" Black Arachnid Wheels")
    private static let WT22 = wheel("WT22", "22 英寸银色 Turbine 轮毂", "22\" Silver Turbine Wheels")
    private static let WT20 = wheel("WT20", "20 英寸银色 Slipstream 轮毂", "20\" Silver Slipstream Wheels")
    private static let WTSC = wheel("WTSC", "20 英寸 Sonic Carbon 轮毂", "20\" Sonic Carbon Wheels")
    private static let WTUT = wheel("WTUT", "22 英寸 Onyx 黑色轮毂", "22\" Onyx Black Wheels")
    private static let WTSD = wheel("WTSD", "20 英寸双色 Slipstream 轮毂", "20\" Two-Tone Slipstream Wheels", rearUsesSide: true)
    private static let WS90 = wheel("WS90", "19 英寸 Tempest 轮毂", "19\" Tempest Wheels")
    private static let WS10 = wheel("WS10", "21 英寸 Arachnid 轮毂", "21\" Arachnid Wheels")
    private static let WS12 = wheel("WS12", "21 英寸 Arachnid 轮毂（Plaid 红卡钳）", "21\" Arachnid Wheels (Plaid)")
    private static let WX00 = wheel("WX00", "20 英寸 Cyberstream 轮毂", "20\" Cyberstream Wheels")
    private static let WX20 = wheel("WX20", "22 英寸 Turbine 轮毂", "22\" Turbine Wheels")

    private static func trim(_ code: String, _ zh: String, _ en: String, interior: String? = nil,
                             paints: [VehicleOption], wheels: [VehicleOption]) -> VehicleTrim {
        VehicleTrim(code: code, zh: zh, en: en, interior: interior, paints: paints, wheels: wheels)
    }

    // MARK: 车型与版本
    // 新款 Model Y / Model 3、Model Y L 的版本、车漆、轮毂与内饰取自特斯拉中国与北美官网配置器数据；
    // 旧款车型与 Model S / X 由 build/mock/VehicleCatalogCheck.swift 逐项校验出图。

    private static let cnYPaints = [PN01, PPSW, PB01, PX02, PR01, PN00]
    private static let na3Paints = [PN01, PN00, PX02, PB02, PPSW, PR01]
    private static let cn3Paints = [PN01, PPSW, PB02, PX02, PR01, PN00]
    private static let legacyYEarly = [PPSW, PBSB, PMNG, PPSB, PPMR]
    private static let legacyYLate = [PPSW, PBSB, PPSB, PN01, PR01, PN00]
    private static let legacy3Paints = [PPSW, PBSB, PMNG, PPSB, PPMR, PMSS]
    private static let legacy3SR2021 = [PPSW, PMNG, PPSB, PPMR]
    private static let legacy3Late = [PPSW, PBSB, PMNG, PPSB, PPMR]
    private static let legacy3Wheels2021 = [W38B, W39B, W40B, W41B]
    private static let refreshSPaintsLate = [PPSW, PBSB, PMNG, PPSB, PPMR, PN01, PR01]
    private static let refreshXPaintsLate = [PPSW, PBSB, PMNG, PPSB, PN01, PR01]
    private static let legacySPaints = [PPSW, PBSB, PMBL, PMNG, PPSB, PPMR]
    private static let legacyXPaints = [PPSW, PBSB, PMNG, PPSB, PPMR]
    private static let refreshSXPaints = [PPSW, PBSB, PMNG, PPSB, PPMR]

    static let generations: [VehicleGeneration] = [
        VehicleGeneration(
            id: "my-juniper", zh: "Model Y（新款）", en: "Model Y (Juniper)", model: "my",
            views: ["FRONT34", "SIDE", "REAR34"],
            trims: [
                trim("MTY79", "后轮驱动版", "Rear-Wheel Drive", interior: "IPB15", paints: cnYPaints, wheels: [WY19P, WY20B]),
                trim("MTY81", "长续航后轮驱动版", "Long Range Rear-Wheel Drive", interior: "IPB15", paints: cnYPaints, wheels: [WY19P, WY20B]),
                trim("MTY80", "长续航全轮驱动版", "Long Range All-Wheel Drive", interior: "IPB16", paints: cnYPaints, wheels: [WY19P, WY20B]),
                trim("MTY88", "Performance 高性能全轮驱动版", "Performance All-Wheel Drive", interior: "IPB14", paints: cnYPaints, wheels: [WY21A]),
                trim("MTY97", "标准版后轮驱动（北美）", "Standard Rear-Wheel Drive (NA)", interior: "IBB6", paints: [PN01, PPSW, PX02], wheels: [WY18P, WY19P]),
                trim("MTY98", "标准版全轮驱动（北美）", "Standard All-Wheel Drive (NA)", interior: "IBB6", paints: [PN01, PPSW, PX02], wheels: [WY18P, WY19P]),
                trim("MTY94", "Premium 长续航后轮驱动（北美）", "Premium Rear-Wheel Drive (NA)", interior: "IPB12",
                     paints: [PN01, PN00, PPSW, PR01, PX02, PB02], wheels: [WY19P, WY20B]),
                trim("MTY96", "Premium 长续航全轮驱动（北美）", "Premium All-Wheel Drive (NA)", interior: "IPB12",
                     paints: [PN01, PN00, PPSW, PR01, PX02, PB02], wheels: [WY19P, WY20B]),
                trim("MTY42", "长续航全轮驱动首发版", "Long Range AWD Launch Series", interior: "IPB6",
                     paints: [PN01, PN00, PPSW, PR01], wheels: [WY19P, WY20A]),
                trim("MTY70", "Performance 高性能全轮驱动（北美）", "Performance All-Wheel Drive (NA)", interior: "IPB14",
                     paints: [PN00, PN01, PPSW, PR01, PX02, PB00], wheels: [WY21A]),
            ]
        ),
        VehicleGeneration(
            id: "my-l", zh: "Model Y L", en: "Model Y L", model: "my",
            views: ["FRONT34", "SIDE", "REAR34"],
            trims: [
                trim("MTY87", "Model Y L 长续航全轮驱动", "Model Y L Long Range AWD", interior: "IPB9",
                     paints: [PN01, PPSW, PB01, PX02, PR01, PN03], wheels: [WY19L]),
                trim("MTY83", "Model Y L Premium 全轮驱动（北美）", "Model Y L Premium AWD (NA)", interior: "IPB17",
                     paints: [PPSW, PN01, PN03, PB02, PR01, PX02], wheels: [WY19L, WY20L]),
            ]
        ),
        VehicleGeneration(
            id: "my-legacy", zh: "Model Y（2020–2025 旧款）", en: "Model Y (2020–2025)", model: "my",
            views: ["FRONT34", "SIDE", "REAR34"],
            trims: [
                trim("MTY01", "标准续航后轮驱动", "Standard Range RWD", interior: "INPB1", paints: legacyYEarly, wheels: [WY19B, WY20P]),
                trim("MTY13", "后轮驱动", "Rear-Wheel Drive", interior: "INPB0",
                     paints: [PPSW, PBSB, PMNG, PPSB, PPMR, PN00, PN01, PR01], wheels: [WY19B, WY19C, WY20P]),
                trim("MTY02", "长续航后轮驱动（2020–2022）", "Long Range RWD (2020–2022)", interior: "INPB1", paints: legacyYEarly, wheels: [WY19B, WY20P]),
                trim("MTY35", "长续航后轮驱动（2023 起）", "Long Range RWD (2023+)", interior: "INPB0", paints: legacyYLate, wheels: [WY19B, WY19C, WY20P]),
                trim("MTY14", "全轮驱动", "All-Wheel Drive", interior: "INPB0", paints: legacyYEarly, wheels: [WY19B, WY20P]),
                trim("MTY03", "长续航全轮驱动（2020–2022）", "Long Range AWD (2020–2022)", interior: "INPB1", paints: legacyYEarly, wheels: [WY19B, WY20P]),
                trim("MTY37", "长续航全轮驱动（2023 起）", "Long Range AWD (2023+)", interior: "INPB0", paints: legacyYLate, wheels: [WY19B, WY19C, WY20P]),
                trim("MTY05", "Performance 高性能全轮驱动（2020–2022）", "Performance AWD (2020–2022)", interior: "INPB1", paints: legacyYEarly, wheels: [WY21P]),
                trim("MTY38", "Performance 高性能全轮驱动（2023 起）", "Performance AWD (2023+)", interior: "INPB0", paints: legacyYLate, wheels: [WY21P]),
            ]
        ),
        VehicleGeneration(
            id: "m3-highland", zh: "Model 3（新款）", en: "Model 3 (Highland)", model: "m3",
            views: ["STUD_FRONT34", "SIDE", "REAR34"],
            trims: [
                trim("MT382", "后轮驱动版", "Rear-Wheel Drive", interior: "IPB11", paints: cn3Paints, wheels: [W38A, W39D]),
                trim("MT383", "长续航后轮驱动版", "Long Range Rear-Wheel Drive", interior: "IPB11", paints: cn3Paints, wheels: [W38A, W39D]),
                trim("MT384", "长续航全轮驱动版", "Long Range All-Wheel Drive", interior: "IPB12", paints: cn3Paints, wheels: [W38A, W39D]),
                trim("MT380", "Performance 高性能全轮驱动版", "Performance All-Wheel Drive", interior: "IPB14", paints: cn3Paints, wheels: [W39C]),
                trim("MT367", "标准版后轮驱动（北美）", "Standard Rear-Wheel Drive (NA)", interior: "IBB8", paints: [PN01, PX02, PPSW], wheels: [W38C, W39D]),
                trim("MT369", "Premium 长续航后轮驱动（北美）", "Premium Rear-Wheel Drive (NA)", interior: "IPB13", paints: na3Paints, wheels: [W38A, W39D]),
                trim("MT385", "Premium 长续航全轮驱动（北美）", "Premium All-Wheel Drive (NA)", interior: "IPB19", paints: na3Paints, wheels: [W38A, W39D]),
                trim("MT379", "Performance 高性能全轮驱动（北美）", "Performance All-Wheel Drive (NA)", interior: "IPB14",
                     paints: [PN01, PN00, PX02, PB00, PPSW, PR01], wheels: [W30P]),
            ]
        ),
        VehicleGeneration(
            // 旧款 Model 3 的 STUD_REAR 是尾灯特写，没有整车斜后方图，R 挡显示侧面
            id: "m3-legacy", zh: "Model 3（2017–2023 旧款）", en: "Model 3 (2017–2023)", model: "m3",
            // MT307、MT309 与 MT305、MT308 同名，不重复列出
            views: ["STUD_3QTR", "STUD_SIDE", "STUD_SIDE"],
            trims: [
                trim("MT300", "标准续航后轮驱动", "Standard Range RWD", paints: legacy3Paints, wheels: [W38B, W39B]),
                trim("MT301", "标准续航升级版后轮驱动", "Standard Range Plus RWD", paints: legacy3Paints, wheels: [W38B, W39B]),
                trim("MT308", "标准续航升级版后轮驱动（2019 改款）", "Standard Range Plus RWD (2019)", paints: legacy3Paints, wheels: [W38B, W39B]),
                trim("MT336", "标准续航升级版后轮驱动（2020 改款）", "Standard Range Plus RWD (2020)", paints: legacy3Paints, wheels: [W38B, W39B]),
                trim("MT305", "中续航后轮驱动", "Mid Range RWD", paints: legacy3Paints, wheels: [W38B, W39B]),
                trim("MT302", "长续航后轮驱动", "Long Range RWD", paints: legacy3Paints, wheels: [W38B, W39B]),
                trim("MT303", "长续航全轮驱动", "Long Range AWD", paints: legacy3Paints, wheels: [W38B, W39B]),
                trim("MT310", "长续航全轮驱动（2019 改款）", "Long Range AWD (2019)", paints: legacy3Paints, wheels: [W38B, W39B]),
                trim("MT304", "长续航全轮驱动 Performance", "Long Range AWD Performance", paints: legacy3Paints, wheels: [W38B, W39B]),
                trim("MT311", "长续航全轮驱动 Performance（2019 改款）", "Long Range AWD Performance (2019)", paints: legacy3Paints, wheels: [W38B, W39B]),
                trim("MT331", "标准续航升级版（2020，MT331）", "Standard Range Plus (2020, MT331)", interior: "IBB1", paints: legacy3Paints, wheels: [W38B, W39B]),
                trim("MT332", "标准续航升级版（2020，MT332）", "Standard Range Plus (2020, MT332)", interior: "IBB1", paints: legacy3Paints, wheels: [W38B, W39B]),
                trim("MT333", "标准续航升级版（2020，MT333）", "Standard Range Plus (2020, MT333)", interior: "IBB1", paints: legacy3Paints, wheels: [W38B, W39B]),
                trim("MT334", "长续航后轮驱动（2020）", "Long Range RWD (2020)", interior: "IBB1", paints: legacy3Paints, wheels: [W38B, W39B]),
                trim("MT314", "标准续航升级版（2021，MT314）", "Standard Range Plus (2021, MT314)", interior: "IBB1", paints: legacy3SR2021, wheels: legacy3Wheels2021),
                trim("MT320", "标准续航升级版（2021，MT320）", "Standard Range Plus (2021, MT320)", interior: "IBB1", paints: legacy3SR2021, wheels: legacy3Wheels2021),
                trim("MT322", "标准续航升级版（2021，MT322）", "Standard Range Plus (2021, MT322)", interior: "IBB1", paints: legacy3SR2021, wheels: [W39B, W40B, W41B]),
                trim("MT337", "标准续航升级版（2021，MT337）", "Standard Range Plus (2021, MT337)", interior: "IBB1", paints: legacy3SR2021, wheels: legacy3Wheels2021),
                trim("MT315", "长续航全轮驱动（2021，MT315）", "Long Range AWD (2021, MT315)", interior: "IBB1", paints: legacy3Late, wheels: legacy3Wheels2021),
                trim("MT316", "长续航全轮驱动（2021，MT316）", "Long Range AWD (2021, MT316)", interior: "IBB1", paints: legacy3Late, wheels: legacy3Wheels2021),
                trim("MT321", "长续航全轮驱动（2021，MT321）", "Long Range AWD (2021, MT321)", interior: "IBB1", paints: legacy3Late, wheels: legacy3Wheels2021),
                trim("MT323", "长续航全轮驱动（2021，MT323）", "Long Range AWD (2021, MT323)", interior: "IBB1", paints: legacy3Late, wheels: legacy3Wheels2021),
                trim("MT324", "长续航全轮驱动（2021，MT324）", "Long Range AWD (2021, MT324)", interior: "IBB1", paints: legacy3Late, wheels: legacy3Wheels2021),
                trim("MT328", "长续航全轮驱动（2022）", "Long Range AWD (2022)", interior: "IBB1", paints: legacy3Late, wheels: legacy3Wheels2021),
                trim("MT317", "Performance（2021）", "Performance (2021)", interior: "IPB1", paints: legacy3Late, wheels: [W33D]),
                trim("MT325", "Performance（2022，MT325）", "Performance (2022, MT325)", interior: "IPB1", paints: legacy3Late, wheels: [W33D]),
                trim("MT340", "Performance（2022，MT340）", "Performance (2022, MT340)", interior: "IPB1", paints: legacy3Late, wheels: [W33D]),
            ]
        ),
        VehicleGeneration(
            // 改款前 Model S 的 STUD_REAR 透明图车窗与尾灯缺失，R 挡显示侧面
            id: "ms-legacy", zh: "Model S（2016–2021）", en: "Model S (2016–2021)", model: "ms",
            views: ["STUD_3QTR_V2", "STUD_SIDE_V2", "STUD_SIDE_V2"],
            trims: [
                trim("MTS03", "长续航（MTS03）", "Long Range (MTS03)", paints: legacySPaints, wheels: [WTAS, WTDS, WTTC]),
                trim("MTS05", "长续航（MTS05）", "Long Range (MTS05)", paints: legacySPaints, wheels: [WTAS, WTDS, WTTC]),
                trim("MTS07", "长续航升级版", "Long Range Plus", paints: legacySPaints, wheels: [WTAS, WTDS, WTTC]),
                trim("MTS04", "Performance 高性能版（MTS04）", "Performance (MTS04)", paints: legacySPaints,
                     wheels: [WTAS, WTDS, WTTC, WTAB]),
                trim("MTS06", "Performance 高性能版（MTS06）", "Performance (MTS06)", paints: legacySPaints,
                     wheels: [WTAS, WTDS, WTTC, WTAB]),
                trim("MTS08", "Performance 高性能版（MTS08）", "Performance (MTS08)", paints: legacySPaints,
                     wheels: [WTAS, WTDS, WTTC, WTAB]),
            ]
        ),
        VehicleGeneration(
            id: "mx-legacy", zh: "Model X（2016–2021）", en: "Model X (2016–2021)", model: "mx",
            views: ["STUD_3QTR_V2", "STUD_SIDE_V2", "STUD_REAR"],
            trims: [
                trim("MTX03", "长续航", "Long Range", paints: legacyXPaints, wheels: [WT20, WTSC, WTUT, WTSD]),
                trim("MTX05", "长续航升级版（MTX05）", "Long Range Plus (MTX05)", paints: legacyXPaints, wheels: [WT20, WTSC, WTUT, WTSD]),
                trim("MTX07", "长续航升级版（MTX07）", "Long Range Plus (MTX07)", paints: legacyXPaints, wheels: [WT20, WTSC, WTUT, WTSD]),
                trim("MTX04", "Performance 高性能版（MTX04）", "Performance (MTX04)", paints: legacyXPaints,
                     wheels: [WT20, WTSC, WTUT, WT22, WTSD]),
                trim("MTX06", "Performance 高性能版（MTX06）", "Performance (MTX06)", paints: legacyXPaints,
                     wheels: [WT20, WTSC, WTUT, WT22, WTSD]),
                trim("MTX08", "Performance 高性能版（MTX08）", "Performance (MTX08)", paints: legacyXPaints,
                     wheels: [WT20, WTSC, WTUT, WT22, WTSD]),
            ]
        ),
        VehicleGeneration(
            id: "ms-refresh", zh: "Model S（2021 起）", en: "Model S (2021+)", model: "ms",
            views: ["FRONT34", "SIDE", "REAR34"],
            // MTS18–MTS20 为 2023 年后的新代码，公开资料没有对应名称，按代码列出
            trims: [
                trim("MTS17", "标准续航（2023）", "Standard Range (2023)", interior: "IBC00", paints: refreshSPaintsLate.filter { $0 != PR01 }, wheels: [WS90, WS10]),
                trim("MTS10", "长续航（2021）", "Long Range (2021)", interior: "IBC00", paints: refreshSXPaints, wheels: [WS90, WS10, WS12]),
                trim("MTS13", "双电机全轮驱动（2022）", "Dual Motor AWD (2022)", interior: "IBC00", paints: refreshSPaintsLate, wheels: [WS90, WS10]),
                trim("MTS18", "MTS18（2023 年后版本）", "MTS18 (2023+)", interior: "IBC00", paints: refreshSPaintsLate, wheels: [WS90, WS10]),
                trim("MTS19", "MTS19（2023 年后版本）", "MTS19 (2023+)", interior: "IBC00", paints: refreshSPaintsLate, wheels: [WS90, WS10]),
                trim("MTS20", "MTS20（2023 年后版本）", "MTS20 (2023+)", interior: "IBC00", paints: refreshSPaintsLate, wheels: [WS90, WS10]),
                trim("MTS11", "Plaid（2021）", "Plaid (2021)", interior: "IBC00", paints: refreshSXPaints, wheels: [WS90, WS10, WS12]),
                trim("MTS12", "Plaid（2022）", "Plaid (2022)", interior: "IBC00", paints: refreshSXPaints, wheels: [WS90, WS10, WS12]),
                trim("MTS14", "Plaid 三电机全轮驱动（2022）", "Plaid Tri Motor AWD (2022)", interior: "IBC00", paints: refreshSXPaints, wheels: [WS90, WS10, WS12]),
            ]
        ),
        VehicleGeneration(
            id: "mx-refresh", zh: "Model X（2021 起）", en: "Model X (2021+)", model: "mx",
            views: ["FRONT34", "SIDE", "REAR34"],
            // MTX15、MTX16、MTX18–MTX20 为 2023 年后的新代码，公开资料没有对应名称，按代码列出
            trims: [
                trim("MTX17", "标准续航（2023）", "Standard Range (2023)", interior: "IBC00", paints: refreshXPaintsLate, wheels: [WX00, WX20]),
                trim("MTX10", "长续航（2021）", "Long Range (2021)", interior: "IBC00", paints: refreshSXPaints, wheels: [WX00, WX01, WX20, WX21]),
                trim("MTX15", "MTX15（2023 年后版本）", "MTX15 (2023+)", interior: "IBC00", paints: refreshXPaintsLate, wheels: [WX00, WX20]),
                trim("MTX16", "MTX16（2023 年后版本）", "MTX16 (2023+)", interior: "IBC00", paints: refreshXPaintsLate, wheels: [WX00, WX20]),
                trim("MTX18", "MTX18（2023 年后版本）", "MTX18 (2023+)", interior: "IBC00", paints: refreshXPaintsLate, wheels: [WX00, WX20]),
                trim("MTX19", "MTX19（2023 年后版本）", "MTX19 (2023+)", interior: "IBC00", paints: refreshXPaintsLate, wheels: [WX00, WX20]),
                trim("MTX20", "MTX20（2023 年后版本）", "MTX20 (2023+)", interior: "IBC00", paints: refreshXPaintsLate, wheels: [WX00, WX20]),
                trim("MTX11", "Plaid（MTX11）", "Plaid (MTX11)", interior: "IBC00", paints: refreshSXPaints, wheels: [WX00, WX01, WX20, WX21]),
                trim("MTX12", "Plaid（MTX12）", "Plaid (MTX12)", interior: "IBC00", paints: refreshSXPaints, wheels: [WX00, WX01, WX20, WX21]),
                trim("MTX13", "Plaid（MTX13）", "Plaid (MTX13)", interior: "IBC00", paints: refreshSXPaints + [PR01], wheels: [WX00, WX20]),
                trim("MTX14", "Plaid 三电机全轮驱动（2022）", "Plaid Tri Motor AWD (2022)", interior: "IBC00", paints: refreshSXPaints, wheels: [WX00, WX01, WX20, WX21]),
            ]
        ),
    ]

    static func generation(id: String) -> VehicleGeneration? { generations.first { $0.id == id } }

    /// `generationID` 为空表示跟随设备车型（`deviceGenerationID`）；版本、车漆、轮毂代码不在当前选择中时取第一项。
    static func resolve(generationID: String, trim: String, paint: String, wheel: String,
                        deviceGenerationID: String) -> VehicleAppearance {
        let generation = generation(id: generationID) ?? generation(id: deviceGenerationID) ?? generations[0]
        let trim = generation.trim(trim)
        return VehicleAppearance(generation: generation, trim: trim, paint: trim.paint(paint), wheel: trim.wheel(wheel))
    }

    static func options(_ appearance: VehicleAppearance) -> [String] {
        ["MDL\(appearance.generation.model.dropFirst().uppercased())", appearance.trim.code]
            + (appearance.trim.interior.map { [$0] } ?? [])
            + [appearance.paint.code, appearance.wheel.code]
    }

    /// 实际显示的视角：车型或轮毂没有斜后方图时 R 挡显示侧面。
    static func effectiveAngle(_ appearance: VehicleAppearance, _ angle: VehicleAngle) -> VehicleAngle {
        guard angle == .rear else { return angle }
        let views = appearance.generation.views
        return appearance.wheel.rearUsesSide || views[2] == views[1] ? .side : .rear
    }

    static func view(_ appearance: VehicleAppearance, angle: VehicleAngle) -> String {
        appearance.generation.views[effectiveAngle(appearance, angle).rawValue]
    }

    static func imageURL(_ appearance: VehicleAppearance, angle: VehicleAngle) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/configurator/compositor"
        components.queryItems = [
            URLQueryItem(name: "context", value: "design_studio_2"),
            URLQueryItem(name: "options", value: options(appearance).map { "$" + $0 }.joined(separator: ",")),
            URLQueryItem(name: "view", value: view(appearance, angle: angle)),
            URLQueryItem(name: "model", value: appearance.generation.model),
            URLQueryItem(name: "size", value: String(imageSize)),
            URLQueryItem(name: "bkba_opt", value: "1"),
            URLQueryItem(name: "crop", value: "0,0,0,0"),
            URLQueryItem(name: "overlay", value: "0"),
        ]
        return components.url!
    }
}
