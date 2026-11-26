import SwiftUI

/// 车型侧影：按当前 profile 画出特斯拉对应车型的侧面比例，替代所有车型共用的 `car.side.fill`。
///
/// 画布固定 240 × 96、地面在 y = 88，所有几何按比例缩放，因此同一份路径可以在
/// 首页大卡片和列表小图上复用。车身用主色渐变（浅色模式近黑车漆、深色模式近银车漆），
/// 前后车窗是挖空后直接透出卡片底色，避免额外配色在深浅色下失衡。
///
/// 车型比例参考各车实际尺寸（长 / 高 / 轴距）：
/// - Model 3 4720 / 1441 / 2875
/// - Model Y 4750 / 1624 / 2890
/// - Model Y L 4976 / 1668 / 3040
/// - Model S 5021 / 1445 / 2960
/// - Model X 5057 / 1684 / 2965
struct VehicleSilhouette: View {
    let style: VehicleBodyStyle

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 240, size.height / 96)
            guard scale > 0 else { return }
            context.translateBy(x: (size.width - 240 * scale) / 2,
                                y: (size.height - 96 * scale) / 2)
            context.scaleBy(x: scale, y: scale)

            let spec = style.spec
            drawShadow(in: &context, spec: spec)
            drawBody(in: &context, spec: spec)
            drawDetails(in: &context, spec: spec)
            drawWheels(in: &context, spec: spec)
        }
        .accessibilityHidden(true)
    }

    // MARK: - 车漆

    private var paintTop: Color {
        colorScheme == .dark ? Color(white: 0.93) : Color(white: 0.34)
    }

    private var paintBottom: Color {
        colorScheme == .dark ? Color(white: 0.56) : Color(white: 0.09)
    }

    // MARK: - 绘制

    private func drawShadow(in context: inout GraphicsContext, spec: VehicleSpec) {
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 2.6))
            let rect = CGRect(x: spec.noseX + 2, y: 86,
                              width: spec.tailX - spec.noseX - 4, height: 9)
            layer.fill(Path(ellipseIn: rect),
                       with: .color(.black.opacity(colorScheme == .dark ? 0.45 : 0.13)))
        }
    }

    private func drawBody(in context: inout GraphicsContext, spec: VehicleSpec) {
        let body = bodyOnlyPath(spec)
        var shell = body
        shell.addPath(frontWindowPath(spec))
        shell.addPath(rearWindowPath(spec))
        context.fill(
            shell,
            with: .linearGradient(
                Gradient(colors: [paintTop, paintBottom]),
                startPoint: CGPoint(x: 120, y: 16),
                endPoint: CGPoint(x: 120, y: 84)
            ),
            style: FillStyle(eoFill: true)
        )

        // 下裙黑色饰条：只裁在车身内，轮拱处自然断开。
        context.drawLayer { layer in
            layer.clip(to: body)
            let sill = CGRect(x: spec.noseX - 1, y: spec.rockerY - 3,
                              width: spec.tailX - spec.noseX + 2, height: 5)
            layer.fill(Path(sill),
                       with: .color(.black.opacity(colorScheme == .dark ? 0.22 : 0.38)))
        }

        // 车窗胶条：让挖空边缘更像密封条，而不是硬切的洞。
        context.stroke(frontWindowPath(spec),
                       with: .color(.black.opacity(0.35)), lineWidth: 0.7)
        context.stroke(rearWindowPath(spec),
                       with: .color(.black.opacity(0.35)), lineWidth: 0.7)

        // 车顶高光：让轮廓在纯色卡片上不糊成一块。
        var roofLine = Path()
        roofLine.move(to: CGPoint(x: spec.roofFrontX + 2, y: spec.roofFrontY + 0.7))
        addRoof(&roofLine, spec, inset: true)
        context.stroke(roofLine,
                       with: .color(.white.opacity(colorScheme == .dark ? 0.45 : 0.30)),
                       lineWidth: 1)

        // 腰线：从前翼子板顺势上扬到尾灯上方。
        var shoulder = Path()
        let startX = spec.cowlX + 3
        let endX = spec.deckX - 4
        shoulder.move(to: CGPoint(x: startX, y: beltY(spec, atX: startX) + 1.4))
        shoulder.addQuadCurve(
            to: CGPoint(x: endX, y: beltY(spec, atX: endX) + 1.4),
            control: CGPoint(x: spec.bPillarX, y: beltY(spec, atX: spec.bPillarX) + 0.6)
        )
        context.stroke(shoulder,
                       with: .color(.white.opacity(colorScheme == .dark ? 0.16 : 0.10)),
                       lineWidth: 0.8)
    }

    private func drawDetails(in context: inout GraphicsContext, spec: VehicleSpec) {
        // 门缝：B 柱下方到侧裙。
        let pillarBelt = beltY(spec, atX: spec.bPillarX)
        var seam = Path()
        seam.move(to: CGPoint(x: spec.bPillarX + 1, y: pillarBelt + 4))
        seam.addLine(to: CGPoint(x: spec.bPillarX + 1, y: spec.rockerY - 4))
        context.stroke(seam, with: .color(.white.opacity(0.13)), lineWidth: 0.8)

        // 隐藏式门把手：前后门各一个。
        for offset in [-20.0, 8.0] as [CGFloat] {
            let handle = Path(
                roundedRect: CGRect(x: spec.bPillarX + offset, y: pillarBelt + 6,
                                    width: 10, height: 2.3),
                cornerRadius: 1.15
            )
            context.fill(handle,
                         with: .color(.white.opacity(colorScheme == .dark ? 0.5 : 0.28)))
        }

        // 充电口盖：左后翼子板上的小方口。
        let chargePort = Path(
            roundedRect: CGRect(x: spec.deckX - 13, y: pillarBelt + 9, width: 6, height: 3.6),
            cornerRadius: 1.4
        )
        context.stroke(chargePort, with: .color(.white.opacity(0.22)), lineWidth: 0.7)

        // 后视镜：A 柱根部伸出，侧影里最能说明「这是一辆车」的细节。
        var mirror = Path()
        mirror.move(to: CGPoint(x: spec.cowlX + 7, y: pillarBelt - 2.6))
        mirror.addLine(to: CGPoint(x: spec.cowlX + 15, y: pillarBelt - 4.2))
        mirror.addQuadCurve(
            to: CGPoint(x: spec.cowlX + 16, y: pillarBelt + 1.4),
            control: CGPoint(x: spec.cowlX + 17.2, y: pillarBelt - 2.2)
        )
        mirror.addLine(to: CGPoint(x: spec.cowlX + 8, y: pillarBelt + 2.2))
        mirror.closeSubpath()
        context.fill(mirror, with: .color(paintTop))
        context.stroke(mirror, with: .color(.white.opacity(0.18)), lineWidth: 0.5)

        // 前灯：特斯拉的窄条灯组，斜贴在车头。
        var headlight = Path()
        headlight.move(to: CGPoint(x: spec.noseX + 1, y: spec.bumperTopY + 2.4))
        headlight.addQuadCurve(
            to: CGPoint(x: spec.noseX + 9, y: spec.bumperTopY + 0.6),
            control: CGPoint(x: spec.noseX + 5, y: spec.bumperTopY + 0.4)
        )
        headlight.addLine(to: CGPoint(x: spec.noseX + 9, y: spec.bumperTopY + 2.2))
        headlight.addQuadCurve(
            to: CGPoint(x: spec.noseX + 1, y: spec.bumperTopY + 4),
            control: CGPoint(x: spec.noseX + 5, y: spec.bumperTopY + 3.4)
        )
        headlight.closeSubpath()
        context.fill(headlight, with: .color(.white.opacity(0.88)))

        let taillight = Path(
            roundedRect: CGRect(x: spec.tailX - 9, y: spec.tailY + 2.4, width: 7.5, height: 2.8),
            cornerRadius: 1.3
        )
        context.fill(taillight,
                     with: .color(Color(red: 0.95, green: 0.20, blue: 0.22).opacity(0.95)))
    }

    private func drawWheels(in context: inout GraphicsContext, spec: VehicleSpec) {
        for centerX in [spec.frontWheelX, spec.rearWheelX] {
            let r = spec.wheelRadius
            let tireRect = CGRect(x: centerX - r, y: spec.wheelY - r, width: r * 2, height: r * 2)
            let tire = Path(ellipseIn: tireRect)
            context.fill(tire, with: .color(Color(white: 0.10)))
            context.stroke(tire, with: .color(Color(white: 0.30)), lineWidth: 0.8)

            // 低风阻轮罩：整片浅灰盘 + 五道深色开槽，接近原厂 aero 轮。
            let cover = Path(ellipseIn: tireRect.insetBy(dx: r * 0.28, dy: r * 0.28))
            context.fill(cover, with: .color(Color(white: 0.70)))
            context.stroke(cover, with: .color(Color(white: 0.45)), lineWidth: 0.7)

            for index in 0..<5 {
                let angle = Double(index) * .pi * 2 / 5 - .pi / 2
                let inner = r * 0.34
                let outer = r * 0.64
                let width = r * 0.20
                var slot = Path()
                slot.move(to: CGPoint(x: centerX + CGFloat(cos(angle)) * inner,
                                      y: spec.wheelY + CGFloat(sin(angle)) * inner))
                slot.addLine(to: CGPoint(x: centerX + CGFloat(cos(angle)) * outer,
                                         y: spec.wheelY + CGFloat(sin(angle)) * outer))
                context.stroke(slot, with: .color(Color(white: 0.24)), lineWidth: width)
            }

            let hub = Path(ellipseIn: CGRect(x: centerX - r * 0.15,
                                             y: spec.wheelY - r * 0.15,
                                             width: r * 0.30, height: r * 0.30))
            context.fill(hub, with: .color(Color(white: 0.34)))
        }
    }

    // MARK: - 路径

    private func bodyOnlyPath(_ s: VehicleSpec) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: s.noseX, y: s.rockerY))
        // 前保险杠：低处接近垂直，顶部向后收进机盖。
        path.addLine(to: CGPoint(x: s.noseX, y: s.rockerY - 9))
        path.addCurve(
            to: CGPoint(x: s.noseX + 3.5, y: s.bumperTopY),
            control1: CGPoint(x: s.noseX, y: s.rockerY - 16),
            control2: CGPoint(x: s.noseX, y: s.bumperTopY + 2)
        )
        // 机盖前缘到风挡根部。
        path.addCurve(
            to: CGPoint(x: s.hoodFrontX, y: s.hoodY),
            control1: CGPoint(x: s.noseX + 8, y: s.bumperTopY - 0.5),
            control2: CGPoint(x: s.noseX + 16, y: s.hoodY + 0.5)
        )
        path.addCurve(
            to: CGPoint(x: s.cowlX, y: s.cowlY),
            control1: CGPoint(x: (s.hoodFrontX + s.cowlX) / 2, y: (s.hoodY + s.cowlY) / 2 - 2.2),
            control2: CGPoint(x: s.cowlX - 8, y: s.cowlY + 1.2)
        )
        // 前风挡
        path.addLine(to: CGPoint(x: s.roofFrontX, y: s.roofFrontY))
        // 车顶
        addRoof(&path, s)
        // 后风挡 / 尾门
        path.addCurve(
            to: CGPoint(x: s.deckX, y: s.deckY),
            control1: CGPoint(x: s.roofRearX + (s.deckX - s.roofRearX) * 0.34, y: s.roofRearY + 0.8),
            control2: CGPoint(x: s.roofRearX + (s.deckX - s.roofRearX) * 0.74, y: s.deckY - 3.2)
        )
        // 尾箱盖 / 尾门顶部
        path.addCurve(
            to: CGPoint(x: s.tailX, y: s.tailY + 4),
            control1: CGPoint(x: s.deckX + 6, y: s.deckY - 0.4),
            control2: CGPoint(x: s.tailX - 1, y: s.tailY)
        )
        // 后保险杠
        path.addLine(to: CGPoint(x: s.tailX, y: s.rockerY - 6))
        path.addCurve(
            to: CGPoint(x: s.tailX - 6, y: s.rockerY),
            control1: CGPoint(x: s.tailX, y: s.rockerY - 1.5),
            control2: CGPoint(x: s.tailX - 3, y: s.rockerY)
        )
        addArch(&path, spec: s, centerX: s.rearWheelX)
        addArch(&path, spec: s, centerX: s.frontWheelX)
        path.addLine(to: CGPoint(x: s.noseX, y: s.rockerY))
        path.closeSubpath()
        return path
    }

    /// 车顶：从风挡上沿到后风挡上沿，中间是一段连续弧线。
    private func addRoof(_ path: inout Path, _ s: VehicleSpec, inset: Bool = false) {
        let dx = s.roofRearX - s.roofFrontX
        let drop: CGFloat = inset ? 0 : 0
        path.addCurve(
            to: CGPoint(x: s.roofRearX, y: s.roofRearY + drop),
            control1: CGPoint(x: s.roofFrontX + dx * 0.30, y: s.roofPeakY - 1.4),
            control2: CGPoint(x: s.roofFrontX + dx * 0.72, y: s.roofPeakY - 0.4)
        )
    }

    /// 轮拱：从右向左跨过轮心，用两段三次曲线贴近半圆。
    private func addArch(_ path: inout Path, spec s: VehicleSpec, centerX: CGFloat) {
        let dy = s.rockerY - s.wheelY
        let squared = max(0, s.archRadius * s.archRadius - dy * dy)
        let dx = max(1, squared.squareRoot())
        let kappa: CGFloat = 0.5523
        path.addLine(to: CGPoint(x: centerX + dx, y: s.rockerY))
        path.addCurve(
            to: CGPoint(x: centerX, y: s.wheelY - s.archRadius),
            control1: CGPoint(x: centerX + s.archRadius, y: s.wheelY - s.archRadius * kappa),
            control2: CGPoint(x: centerX + s.archRadius * kappa, y: s.wheelY - s.archRadius)
        )
        path.addCurve(
            to: CGPoint(x: centerX - dx, y: s.rockerY),
            control1: CGPoint(x: centerX - s.archRadius * kappa, y: s.wheelY - s.archRadius),
            control2: CGPoint(x: centerX - s.archRadius, y: s.wheelY - s.archRadius * kappa)
        )
    }

    private func frontWindowPath(_ s: VehicleSpec) -> Path {
        var path = Path()
        let baseX = s.cowlX + 6
        path.move(to: CGPoint(x: baseX, y: s.cowlY - 0.5))
        path.addLine(to: CGPoint(x: s.roofFrontX + 6, y: s.roofFrontY + 3.4))
        path.addLine(to: CGPoint(x: s.bPillarX - 1.5, y: roofTopY(s, atX: s.bPillarX - 1.5) + 3.4))
        let pillarBelt = beltY(s, atX: s.bPillarX - 1.5)
        path.addLine(to: CGPoint(x: s.bPillarX - 1.5, y: pillarBelt))
        path.addLine(to: CGPoint(x: baseX, y: beltY(s, atX: baseX)))
        path.closeSubpath()
        return path
    }

    private func rearWindowPath(_ s: VehicleSpec) -> Path {
        var path = Path()
        let baseX = s.bPillarX + 3.5
        // 后侧窗在 C 柱处向前收尖：上沿比下沿更靠后，避免整块方窗变成 MPV。
        let topRearX = s.roofRearX - 3
        let bottomRearX = s.roofRearX - 8
        path.move(to: CGPoint(x: baseX, y: roofTopY(s, atX: baseX) + 3.4))
        path.addLine(to: CGPoint(x: topRearX, y: roofTopY(s, atX: topRearX) + 3.4))
        path.addLine(to: CGPoint(x: bottomRearX, y: beltY(s, atX: bottomRearX)))
        path.addLine(to: CGPoint(x: baseX, y: beltY(s, atX: baseX)))
        path.closeSubpath()
        return path
    }

    /// 腰线：车头略低、车尾略高，避免侧面像一条水平直线。
    private func beltY(_ s: VehicleSpec, atX x: CGFloat) -> CGFloat {
        let span = max(1, s.deckX - s.cowlX)
        let t = min(max((x - s.cowlX) / span, 0), 1)
        return s.beltFrontY + (s.beltRearY - s.beltFrontY) * t
    }

    /// 车顶三次贝塞尔在给定 x 处的 y，用于让车窗上沿贴合车顶曲线。
    private func roofTopY(_ s: VehicleSpec, atX x: CGFloat) -> CGFloat {
        let p0 = CGPoint(x: s.roofFrontX, y: s.roofFrontY)
        let dx = s.roofRearX - s.roofFrontX
        let p1 = CGPoint(x: s.roofFrontX + dx * 0.30, y: s.roofPeakY - 1.4)
        let p2 = CGPoint(x: s.roofFrontX + dx * 0.72, y: s.roofPeakY - 0.4)
        let p3 = CGPoint(x: s.roofRearX, y: s.roofRearY)

        var low: CGFloat = 0
        var high: CGFloat = 1
        for _ in 0..<20 {
            let t = (low + high) / 2
            let mt = 1 - t
            let bx = mt * mt * mt * p0.x + 3 * mt * mt * t * p1.x + 3 * mt * t * t * p2.x + t * t * t * p3.x
            if bx < x { low = t } else { high = t }
        }
        let t = (low + high) / 2
        let mt = 1 - t
        return mt * mt * mt * p0.y + 3 * mt * mt * t * p1.y + 3 * mt * t * t * p2.y + t * t * t * p3.y
    }
}

// MARK: - 车型

enum VehicleBodyStyle {
    case model3
    case modelY
    case modelYL
    case modelS
    case modelX

    /// profile 优先，其次按名称兜底（离线缓存或旧固件没有 profile id 时）。
    static func resolve(profileID: Int?, name: String?) -> VehicleBodyStyle {
        switch profileID {
        case 1: return .modelYL
        case 2, 3: return .modelY
        case 4, 5: return .model3
        case 6: return .modelS
        default: break
        }

        let text = (name ?? "").lowercased()
        if text.contains("model y l") || text.contains(" yl") { return .modelYL }
        if text.contains("model y") { return .modelY }
        if text.contains("model 3") { return .model3 }
        if text.contains("model x") { return .modelX }
        if text.contains("model s") || text.contains("s/x") { return .modelS }
        return .model3
    }

    fileprivate var spec: VehicleSpec {
        switch self {
        case .model3: return VehicleSpec.model3
        case .modelY: return VehicleSpec.modelY
        case .modelYL: return VehicleSpec.modelYL
        case .modelS: return VehicleSpec.modelS
        case .modelX: return VehicleSpec.modelX
        }
    }
}

/// 一组车身控制点（画布 240 × 96，地面 y = 88）。
fileprivate struct VehicleSpec {
    let noseX: CGFloat
    let tailX: CGFloat
    let rockerY: CGFloat
    let bumperTopY: CGFloat
    let hoodFrontX: CGFloat
    let hoodY: CGFloat
    let cowlX: CGFloat
    let cowlY: CGFloat
    let roofFrontX: CGFloat
    let roofFrontY: CGFloat
    let roofPeakX: CGFloat
    let roofPeakY: CGFloat
    let roofRearX: CGFloat
    let roofRearY: CGFloat
    let deckX: CGFloat
    let deckY: CGFloat
    let tailY: CGFloat
    let beltFrontY: CGFloat
    let beltRearY: CGFloat
    let bPillarX: CGFloat
    let wheelY: CGFloat
    let wheelRadius: CGFloat
    let archRadius: CGFloat
    let frontWheelX: CGFloat
    let rearWheelX: CGFloat

    /// Model 3：低矮轿车，轴距 2875 / 车长 4720，短前悬、长后悬、fastback。
    static let model3 = VehicleSpec(
        noseX: 15, tailX: 221, rockerY: 79, bumperTopY: 53,
        hoodFrontX: 30, hoodY: 51, cowlX: 76, cowlY: 41.5,
        roofFrontX: 96, roofFrontY: 25.5, roofPeakX: 127, roofPeakY: 24.5,
        roofRearX: 153, roofRearY: 30.5, deckX: 198, deckY: 42.5, tailY: 45,
        beltFrontY: 46.5, beltRearY: 42.5, bPillarX: 122,
        wheelY: 73.4, wheelRadius: 14.7, archRadius: 17.2,
        frontWheelX: 52, rearWheelX: 177.5
    )

    /// Model Y：紧凑 SUV，车顶比 3 高 183 mm，尾门更立、后窗更长。
    static let modelY = VehicleSpec(
        noseX: 15, tailX: 221, rockerY: 75, bumperTopY: 51,
        hoodFrontX: 30, hoodY: 49, cowlX: 75, cowlY: 39.5,
        roofFrontX: 93, roofFrontY: 20.5, roofPeakX: 130, roofPeakY: 17.5,
        roofRearX: 178, roofRearY: 26, deckX: 206, deckY: 38.5, tailY: 41,
        beltFrontY: 42, beltRearY: 38.5, bPillarX: 123,
        wheelY: 72.8, wheelRadius: 15.2, archRadius: 19.6,
        frontWheelX: 53, rearWheelX: 178
    )

    /// Model Y L：长轴距 6 座版，车长 +226 mm、轴距 +150 mm，后门和后排明显加长。
    static let modelYL = VehicleSpec(
        noseX: 11, tailX: 228, rockerY: 75, bumperTopY: 51,
        hoodFrontX: 26, hoodY: 49, cowlX: 71, cowlY: 39.5,
        roofFrontX: 89, roofFrontY: 19.5, roofPeakX: 134, roofPeakY: 15.3,
        roofRearX: 188, roofRearY: 24.5, deckX: 214, deckY: 37.5, tailY: 40,
        beltFrontY: 42, beltRearY: 38.5, bPillarX: 124,
        wheelY: 72, wheelRadius: 16, archRadius: 20.4,
        frontWheelX: 50, rearWheelX: 182.5
    )

    /// Model S：大型掀背轿车，更长更低，车顶弧线最平缓。
    static let modelS = VehicleSpec(
        noseX: 12, tailX: 225, rockerY: 79, bumperTopY: 54,
        hoodFrontX: 28, hoodY: 52, cowlX: 78, cowlY: 41.5,
        roofFrontX: 98, roofFrontY: 27.5, roofPeakX: 132, roofPeakY: 26,
        roofRearX: 166, roofRearY: 33, deckX: 208, deckY: 43, tailY: 46,
        beltFrontY: 46.5, beltRearY: 42, bPillarX: 126,
        wheelY: 73.1, wheelRadius: 14.9, archRadius: 17.4,
        frontWheelX: 52, rearWheelX: 177.5
    )

    /// Model X：大型 SUV，车身高、尾门近乎垂直、轮圈更大。
    static let modelX = VehicleSpec(
        noseX: 12, tailX: 228, rockerY: 74, bumperTopY: 50,
        hoodFrontX: 27, hoodY: 48, cowlX: 74, cowlY: 37.5,
        roofFrontX: 93, roofFrontY: 19, roofPeakX: 144, roofPeakY: 16,
        roofRearX: 195, roofRearY: 25, deckX: 216, deckY: 36.5, tailY: 39,
        beltFrontY: 40.5, beltRearY: 36.5, bPillarX: 128,
        wheelY: 72.2, wheelRadius: 15.8, archRadius: 21.2,
        frontWheelX: 52, rearWheelX: 178.6
    )
}
