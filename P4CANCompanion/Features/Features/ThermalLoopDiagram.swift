import SwiftUI

/// 电池预热页的冷却回路图：固件网页「热管理」面板（车辆服务界面 Thermal 页）的原生重绘。
/// 几何按官方 SVG 的 360×372 坐标原样转写，按宽度等比缩放；数据规则与网页 `renderThermal` 一致。
struct ThermalLoopDiagram: View {
    let state: ThermalLoopState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let animating = !reduceMotion && state.hasMotion
        ZStack {
            Canvas { context, size in
                context.scaleBy(x: size.width / Self.width, y: size.height / Self.height)
                Self.drawBase(&context, state)
            }
            TimelineView(.animation(paused: !animating)) { timeline in
                let time = animating ? timeline.date.timeIntervalSinceReferenceDate : 0
                Canvas { context, size in
                    context.scaleBy(x: size.width / Self.width, y: size.height / Self.height)
                    Self.drawFlow(&context, state, time: time)
                }
            }
            Canvas { context, size in
                context.scaleBy(x: size.width / Self.width, y: size.height / Self.height)
                Self.drawComponents(&context, state)
            }
            TimelineView(.animation(paused: !animating)) { timeline in
                let time = animating ? timeline.date.timeIntervalSinceReferenceDate : 0
                Canvas { context, size in
                    context.scaleBy(x: size.width / Self.width, y: size.height / Self.height)
                    Self.drawRotors(&context, state, time: time)
                }
            }
        }
        .aspectRatio(Self.width / Self.height, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(state.accessibilitySummary)
    }

    static let width: CGFloat = 360
    static let height: CGFloat = 372

    // MARK: 配色（与网页一致）

    private static let panel = Color(rgb: 0x1D1E21)
    private static let frame = Color(rgb: 0x8D9096)
    private static let line = Color(rgb: 0xD8DADF)
    private static let pipeBlue = Color(rgb: 0x2FB6E3).opacity(0.72)
    private static let pipePurple = Color(rgb: 0xA64BF4).opacity(0.85)
    private static let pipePale = Color(rgb: 0xD8B9C8).opacity(0.42)
    private static let flowBlue = Color(rgb: 0xEAFCFF).opacity(0.3)
    private static let flowPurple = Color(rgb: 0xF1DDFF).opacity(0.3)
    private static let dotFresh = Color(rgb: 0x2FD15B)
    private static let dotStale = Color(rgb: 0x9A9DA3)

    // MARK: 管路（官方 SVG 的 16 段，顺序与模式表一致）

    private static let pipes: [Path] = [
        PathPen().m(180, 120).v(64).q(180, 51, 192, 51).q(204, 51, 204, 64).v(120).path,
        PathPen().m(180, 120).v(124).q(180, 132, 192, 132).q(204, 132, 204, 124).v(120).path,
        PathPen().m(110, 344).v(350).q(110, 358, 102, 358).h(94).q(86, 358, 86, 350).v(69)
            .q(86, 61, 94, 61).h(139).q(147, 61, 147, 69).v(92).l(156, 101).v(120).path,
        PathPen().m(200, 159).v(170).q(200, 178, 192, 178).h(137).q(129, 178, 129, 170).v(113)
            .q(129, 104, 119.5, 104).q(110, 104, 110, 113).v(344).path,
        PathPen().m(156, 159).v(197).q(156, 205, 164, 205).h(255).q(263, 205, 263, 213).v(350)
            .q(263, 358, 271, 358).h(279).q(287, 358, 287, 350).v(183).q(287, 175, 279, 175).h(232)
            .q(224, 175, 224, 167).v(159).path,
        PathPen().m(180, 159).v(183).q(180, 191, 188, 191).h(254).q(262, 191, 262, 183).v(151).path,
        PathPen().m(262, 129).v(111).q(262, 101, 252, 101).h(234).q(224, 101, 224, 111).v(120).path,
        PathPen().m(156, 120).v(159).path,
        PathPen().m(180, 120).v(159).path,
        PathPen().m(224, 120).v(159).path,
        PathPen().m(180, 159).v(151).q(180, 141, 190, 141).q(200, 141, 200, 151).v(159).path,
        PathPen().m(224, 159).v(152).q(224, 142, 212, 142).q(200, 142, 200, 152).v(159).path,
        PathPen().m(224, 120).v(124).q(224, 133, 214, 133).q(204, 133, 204, 124).v(120).path,
        PathPen().m(204, 120).v(146).q(204, 152, 200, 156).v(159).path,
        PathPen().m(156, 120).v(124).q(156, 132, 168, 132).q(180, 132, 180, 124).v(120).path,
        PathPen().m(156, 159).v(155).q(156, 146, 168, 146).q(180, 146, 180, 155).v(159).path,
    ]

    private static func pipeColor(_ kind: Character) -> Color? {
        switch kind {
        case "b": return pipeBlue
        case "p": return pipePurple
        case "g": return pipePale
        default: return nil
        }
    }

    // MARK: 底层：面板、分区框、管路

    private static func drawBase(_ context: inout GraphicsContext, _ state: ThermalLoopState) {
        context.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: width, height: height), cornerRadius: 14), with: .color(panel))
        let dashed = StrokeStyle(lineWidth: 1, dash: [3, 3])
        for rect in [CGRect(x: 6, y: 73, width: 348, height: 150), CGRect(x: 8, y: 229, width: 118, height: 139),
                     CGRect(x: 252, y: 229, width: 102, height: 139)] {
            context.stroke(Path(roundedRect: rect, cornerRadius: 10), with: .color(frame), style: dashed)
        }
        let pipeStyle = StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round)
        for (index, kind) in state.mode.drawing.enumerated() {
            guard let color = pipeColor(kind) else { continue }
            context.stroke(pipes[index], with: .color(color), style: pipeStyle)
        }
    }

    // MARK: 流动层：泵在转的回路上虚线沿管路移动

    private static func drawFlow(_ context: inout GraphicsContext, _ state: ThermalLoopState, time: Double) {
        let phase = -40 * (time.truncatingRemainder(dividingBy: 1.4) / 1.4)
        for (index, kind) in state.mode.drawing.enumerated() {
            let flowing: Bool
            let color: Color
            switch kind {
            case "b": flowing = state.ptLoopFlowing; color = flowBlue
            case "p": flowing = state.batteryLoopFlowing; color = flowPurple
            default: continue
            }
            let style = StrokeStyle(lineWidth: 10, lineCap: .butt, dash: [6, 14], dashPhase: flowing ? phase : 0)
            context.stroke(pipes[index], with: .color(color), style: style)
        }
    }

    // MARK: 旋转件：散热器风扇、两台泵的叶轮

    private static let fanBlade = PathPen().m(0.8, -3).c(4.5, -5.5, 5, -10, 2.4, -14.6).l(0.6, -14.8)
        .c(2, -10.5, 1.2, -6.5, -0.9, -3).z().path
    private static let impellerBlade = PathPen().m(0, -1.6).q(3, -3, 2.4, -6.2).path

    private static func drawRotors(_ context: inout GraphicsContext, _ state: ThermalLoopState, time: Double) {
        let spin = 2 * Double.pi * (time.truncatingRemainder(dividingBy: 1.1) / 1.1)
        let fanSpin = state.fanSpinning ? spin : 0
        for index in 0..<9 {
            let transform = CGAffineTransform(rotationAngle: Double(index) * 40 * .pi / 180 + fanSpin)
                .concatenating(CGAffineTransform(scaleX: 0.78, y: 0.78))
                .concatenating(CGAffineTransform(translationX: 192, y: 51))
            context.fill(fanBlade.applying(transform), with: .color(Color(rgb: 0xC9CCD1)))
        }
        let hub = Path(ellipseIn: CGRect(x: 192 - 2.6, y: 51 - 2.6, width: 5.2, height: 5.2))
        context.fill(hub, with: .color(Color(rgb: 0x3A3C40)))
        context.stroke(hub, with: .color(line), lineWidth: 0.8)

        let bladeStyle = StrokeStyle(lineWidth: 1.2, lineCap: .round)
        for (center, spinning) in [(CGPoint(x: 88.42, y: 140.52), state.ptPumpSpinning),
                                   (CGPoint(x: 259.58, y: 136.52), state.batteryPumpSpinning)] {
            for index in 0..<6 {
                let transform = CGAffineTransform(rotationAngle: Double(index) * 60 * .pi / 180 + (spinning ? spin : 0))
                    .concatenating(CGAffineTransform(translationX: center.x, y: center.y))
                context.stroke(impellerBlade.applying(transform), with: .color(Color(rgb: 0xE5E7EB)), style: bladeStyle)
            }
        }
    }

    // MARK: 部件与标签

    private static func drawComponents(_ context: inout GraphicsContext, _ s: ThermalLoopState) {
        let shell = StrokeStyle(lineWidth: 1.4)
        func box(_ rect: CGRect, radius: CGFloat) {
            context.stroke(Path(roundedRect: rect, cornerRadius: radius), with: .color(line), style: shell)
        }
        func dot(_ x: CGFloat, _ y: CGFloat, _ fresh: Bool, radius: CGFloat = 3.3) {
            context.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                         with: .color(fresh ? dotFresh : dotStale))
        }
        func ring(_ x: CGFloat, _ y: CGFloat) {
            context.stroke(Path(ellipseIn: CGRect(x: x - 7.5, y: y - 7.5, width: 15, height: 15)),
                           with: .color(Color(rgb: 0xE5E7EB)), lineWidth: 1.2)
        }
        func separator(_ x1: CGFloat, _ x2: CGFloat, _ y: CGFloat) {
            var path = Path()
            path.move(to: CGPoint(x: x1, y: y))
            path.addLine(to: CGPoint(x: x2, y: y))
            context.stroke(path, with: .color(frame), style: StrokeStyle(lineWidth: 0.8, dash: [2, 2]))
        }
        func text(_ parts: [TextPart], _ x: CGFloat, _ y: CGFloat, size: CGFloat, anchor: UnitPoint = .leading, halo: CGFloat = 3) {
            drawText(&context, parts, x: x, y: y, size: size, anchor: anchor, halo: halo)
        }
        let name = { (value: String) in [TextPart(value, .semibold, Color(rgb: 0xECEEF2))] }
        let head = { (value: String) in [TextPart(value, .bold, Color(rgb: 0xF2F3F5))] }
        let sub = { (label: String, value: String) in
            [TextPart(label, .regular, Color(rgb: 0xB9BCC2)), TextPart(value, .bold, .white)]
        }
        let number = { (value: String) in [TextPart(value, .semibold, Color(rgb: 0xE9EBEF))] }
        let frameName = { (value: String) in [TextPart(value, .regular, Color(rgb: 0xC3C6CC))] }
        let t = L10n.t

        text(frameName(t("超级歧管", "Supermanifold")), 16, 76, size: 8.4, halo: 4)
        text(frameName(t("动力总成回路", "Powertrain Loop")), 16, 232, size: 8.4, halo: 4)
        text(frameName(t("电池回路", "Battery Loop")), 268, 232, size: 8.4, halo: 4)

        // 环境与散热器
        dot(152, 15, s.ambientFresh)
        text([TextPart(t("环境空气：", "Ambient Air: "), .bold, Color(rgb: 0xF2F3F5)), TextPart(s.ambient, .bold, .white)],
             159, 18.3, size: 8.8)
        box(CGRect(x: 152, y: 31, width: 77, height: 40), radius: 4)
        text(name(t("散热器", "Radiator")), 157, 34.5, size: 8.2, halo: 3.4)
        let shroud = Path(roundedRect: CGRect(x: 177, y: 36, width: 30, height: 30), cornerRadius: 4)
        context.fill(shroud, with: .color(Color(rgb: 0x26282C)))
        context.stroke(shroud, with: .color(Color(rgb: 0xB9BCC2)), lineWidth: 1.2)
        let rim = Path(ellipseIn: CGRect(x: 179, y: 38, width: 26, height: 26))
        context.fill(rim, with: .color(panel))
        context.stroke(rim, with: .color(frame), lineWidth: 1)
        var leaders = Path()
        leaders.move(to: CGPoint(x: 229, y: 40)); leaders.addLine(to: CGPoint(x: 237, y: 24))
        leaders.move(to: CGPoint(x: 207, y: 51)); leaders.addLine(to: CGPoint(x: 237, y: 45))
        context.stroke(leaders, with: .color(line), lineWidth: 1)
        dot(241, 21, false)
        text(head(t("散热器", "Radiator")), 248, 24.3, size: 8.8)
        text(sub(t("状态：", "Health: "), "—"), 250, 34.5, size: 8.4)
        dot(241, 44, s.vitals)
        text(head(t("散热器风扇", "Radiator Fan")), 248, 47.3, size: 8.8)
        text(sub(t("转速：", "RPM: "), s.fan), 250, 57.5, size: 8.4)

        // LCC 与冷却器（制冷剂侧）
        for (rect, title, refrigerant) in [
            (CGRect(x: 93, y: 80, width: 48, height: 35), "LCC", CGRect(x: 95, y: 86, width: 44, height: 8.5)),
            (CGRect(x: 232, y: 80, width: 44, height: 33), t("冷却器", "Chiller"), CGRect(x: 234, y: 86, width: 40, height: 8.5)),
        ] {
            box(rect, radius: 4)
            text(name(title), rect.minX + 5, 83.5, size: 8.2, halo: 3.4)
            context.fill(Path(refrigerant), with: .color(Color(rgb: 0x5B2A5E)))
            text([TextPart(t("制冷剂", "Refrigerant"), .semibold, Color(rgb: 0xC99CCF))],
                 refrigerant.midX, 92.6, size: 6.4, anchor: .center, halo: 0)
        }

        // 冷却液阀（热泵车型为 Octovalve）与回路模式
        let valve = PathPen().m(163, 120).h(144).q(140, 120, 140, 124).v(155).q(140, 159, 144, 159).h(150)
            .m(226, 120).h(235).q(239, 120, 239, 124).v(155).q(239, 159, 235, 159).h(232).path
        context.stroke(valve, with: .color(line), style: shell)
        dot(170, 120.5, s.modeFresh)
        text([TextPart(s.valveName, .semibold, Color(rgb: 0xECEEF2))], 177, 124, size: 10, halo: 3.4)
        text([TextPart(s.modeLabel, .bold, .white)], 149, 166, size: 9, halo: 5)

        // 两台泵的蜗壳
        var ptVolute = Path()
        ptVolute.move(to: CGPoint(x: 78, y: 137))
        ptVolute.addRelativeArc(center: CGPoint(x: 88.42, y: 140.52), radius: 11,
                                startAngle: .degrees(198.66), delta: .degrees(220.82))
        ptVolute.addLine(to: CGPoint(x: 94, y: 157)); ptVolute.addLine(to: CGPoint(x: 78, y: 157)); ptVolute.closeSubpath()
        var batteryVolute = Path()
        batteryVolute.move(to: CGPoint(x: 270, y: 133))
        batteryVolute.addRelativeArc(center: CGPoint(x: 259.58, y: 136.52), radius: 11,
                                     startAngle: .degrees(-18.66), delta: .degrees(-220.82))
        batteryVolute.addLine(to: CGPoint(x: 254, y: 153)); batteryVolute.addLine(to: CGPoint(x: 270, y: 153)); batteryVolute.closeSubpath()
        for (volute, center) in [(ptVolute, CGPoint(x: 88.42, y: 140.52)), (batteryVolute, CGPoint(x: 259.58, y: 136.52))] {
            context.fill(volute, with: .color(panel))
            context.stroke(volute, with: .color(line), lineWidth: 1.2)
            let impellerRim = Path(ellipseIn: CGRect(x: center.x - 6.6, y: center.y - 6.6, width: 13.2, height: 13.2))
            context.fill(impellerRim, with: .color(Color(rgb: 0x3A3C40)))
            context.stroke(impellerRim, with: .color(Color(rgb: 0x9A9DA3)), lineWidth: 1)
        }
        dot(14, 136, s.vitals)
        text(head(t("动力总成泵", "PT Pump")), 21, 139.3, size: 8.8)
        text(sub(t("转速：", "RPM: "), s.ptPump), 23, 150, size: 8.4)
        dot(281, 133, s.vitals)
        text(head(t("电池泵", "Battery Pump")), 288, 136.3, size: 8.8)
        text(sub(t("转速：", "RPM: "), s.batteryPump), 290, 147, size: 8.4)

        // 回路入口与储液罐
        ring(86, 198)
        dot(14, 189, s.inletsFresh)
        text(head(t("动力总成回路入口", "PT Loop Inlet")), 21, 192.3, size: 8.8)
        text(sub(t("温度：", "Temp: "), s.ptInlet), 23, 204, size: 8.4)
        text(sub(t("流量：", "Flow: "), s.ptFlow), 23, 214, size: 8.4)
        let bottle = Path(roundedRect: CGRect(x: 95, y: 189, width: 48, height: 24), cornerRadius: 4)
        context.fill(bottle, with: .color(Color(rgb: 0x2B7F99).opacity(0.6)))
        context.stroke(bottle, with: .color(line), lineWidth: 1.2)
        dot(100, 201, false, radius: 2.4)
        text([TextPart(t("冷却液", "Coolant"), .bold, .white)], 105, 199, size: 7.4, halo: 0)
        text([TextPart(t("储液罐", "Bottle"), .bold, .white)], 105, 208, size: 7.4, halo: 0)
        ring(287, 192)
        dot(299, 167, s.inletsFresh)
        text(head(t("电池", "Battery")), 306, 170.3, size: 8.8)
        text(head(t("回路入口", "Loop Inlet")), 306, 179.5, size: 8.8)
        text(sub(t("温度：", "Temp: "), s.batteryInlet), 299, 196, size: 8.4)
        text(sub(t("流量：", "Flow: "), s.batteryFlow), 299, 206, size: 8.4)

        // 动力总成回路：PCS（DCDC / 充电器）、前后驱逆变器
        box(CGRect(x: 14, y: 238, width: 98, height: 56), radius: 5)
        text(name("PCS"), 19, 247, size: 8.2, halo: 3.4)
        text(name("DCDC"), 107, 247, size: 8.2, anchor: .trailing, halo: 3.4)
        dot(24, 258, s.pcsFresh)
        text(number(s.dcdc), 31, 261.5, size: 9.6)
        separator(18, 108, 268)
        dot(24, 279, s.pcsFresh)
        text(number(s.charger), 31, 282.5, size: 9.6)
        text(name(t("充电器", "Charger")), 107, 290, size: 8.2, anchor: .trailing, halo: 3.4)
        box(CGRect(x: 14, y: 300, width: 98, height: 28), radius: 5)
        text(name(t("前驱逆变器", "Front Drive Inverter")), 19, 309, size: 8.2, halo: 3.4)
        dot(24, 319, s.frontInverterFresh)
        text(number(s.frontInverter), 31, 322.5, size: 9.6)
        box(CGRect(x: 14, y: 334, width: 98, height: 28), radius: 5)
        text(name(t("后驱逆变器", "Rear Drive Inverter")), 19, 343, size: 8.2, halo: 3.4)
        dot(24, 353, s.rearInverterFresh)
        text(number(s.rearInverter), 31, 356.5, size: 9.6)

        // 电池回路：AP / 信息娱乐、高压电池最高 / 最低温度
        box(CGRect(x: 258, y: 238, width: 90, height: 58), radius: 5)
        text(name(t("自动辅助驾驶", "Autopilot")), 263, 247, size: 8.2, halo: 3.4)
        dot(306, 258, s.autopilotFresh)
        text(number(s.autopilot), 313, 261.5, size: 9.6)
        separator(262, 344, 268)
        dot(306, 279, s.infotainmentFresh)
        text(number(s.infotainment), 313, 282.5, size: 9.6)
        text(name(t("车载娱乐系统", "Infotainment")), 343, 292, size: 8.2, anchor: .trailing, halo: 3.4)
        box(CGRect(x: 258, y: 302, width: 90, height: 60), radius: 5)
        text(name(t("高压电池", "HV Battery")), 263, 311, size: 8.2, halo: 3.4)
        text(name(t("最大值", "Max")), 343, 311, size: 8.2, anchor: .trailing, halo: 3.4)
        dot(306, 322, s.packFresh)
        text(number(s.packMax), 313, 325.5, size: 9.6)
        separator(262, 344, 332)
        dot(306, 343, s.packFresh)
        text(number(s.packMin), 313, 346.5, size: 9.6)
        text(name(t("最小值", "Min")), 343, 357, size: 8.2, anchor: .trailing, halo: 3.4)
    }

    private struct TextPart {
        let value: String
        let weight: Font.Weight
        let color: Color
        init(_ value: String, _ weight: Font.Weight, _ color: Color) {
            self.value = value; self.weight = weight; self.color = color
        }
    }

    /// SVG 文字以基线定位；这里换算成垂直居中锚点。halo 对应网页的描边（paint-order: stroke），压在管路上时保持可读。
    private static func drawText(_ context: inout GraphicsContext, _ parts: [TextPart], x: CGFloat, y: CGFloat,
                                 size: CGFloat, anchor: UnitPoint, halo: CGFloat) {
        func compose(_ color: Color?) -> Text {
            parts.reduce(Text(verbatim: "")) { result, part in
                result + Text(verbatim: part.value)
                    .font(.system(size: size, weight: part.weight))
                    .foregroundStyle(color ?? part.color)
            }
        }
        let point = CGPoint(x: x, y: y - size * 0.36)
        let resolvedAnchor = UnitPoint(x: anchor.x, y: 0.5)
        if halo > 0 {
            let outline = context.resolve(compose(panel))
            let radius = halo / 2
            for angle in stride(from: 0.0, to: 360.0, by: 45.0) {
                let offset = CGPoint(x: point.x + radius * cos(angle * .pi / 180), y: point.y + radius * sin(angle * .pi / 180))
                context.draw(outline, at: offset, anchor: resolvedAnchor)
            }
        }
        context.draw(context.resolve(compose(nil)), at: point, anchor: resolvedAnchor)
    }
}

/// 回路图需要的数值与状态，规则与固件网页 `renderThermal` 一致：
/// 10 Hz 帧 5 s 内、慢帧 15 s 内视为新鲜；过期的温度显示 --°C，状态点变灰。
@MainActor
struct ThermalLoopState {
    enum Mode: Equatable {
        case off, bypass, ambient, series, parallel

        /// 每段管路一个字符：b 动力总成泵回路（或单回路）蓝色，p 独立的电池泵回路紫色，g 灰色，- 不画
        var drawing: [Character] {
            switch self {
            case .bypass: return Array("ggbbbbbb-bb-----")
            case .ambient: return Array("p-bbbppbp--bp---")
            case .series: return Array("b-bbbbbbbb---b--")
            case .parallel: return Array("b-bbppp--p---bbp")
            case .off: return Array("gggggggg-gg-----")
            }
        }
    }

    let mode: Mode
    let modeFresh: Bool
    let vitals: Bool
    let ptLoopFlowing: Bool
    let batteryLoopFlowing: Bool
    let ptPumpSpinning: Bool
    let batteryPumpSpinning: Bool
    let fanSpinning: Bool
    let valveName: String
    let fan: String
    let ptPump: String
    let batteryPump: String
    let inletsFresh: Bool
    let ptInlet: String
    let batteryInlet: String
    let ptFlow: String
    let batteryFlow: String
    let pcsFresh: Bool
    let dcdc: String
    let charger: String
    let frontInverterFresh: Bool
    let frontInverter: String
    let rearInverterFresh: Bool
    let rearInverter: String
    let autopilotFresh: Bool
    let autopilot: String
    let infotainmentFresh: Bool
    let infotainment: String
    let packFresh: Bool
    let packMax: String
    let packMin: String
    let ambientFresh: Bool
    let ambient: String

    static let freshMs: Int64 = 5_000
    static let slowMs: Int64 = 15_000

    init(_ stats: [String: P4JSON]) {
        func fresh(_ key: String, _ window: Int64 = Self.freshMs) -> Bool {
            guard let age = stats[key]?.intValue else { return false }
            return age <= window
        }
        func int(_ key: String) -> Int64 { stats[key]?.intValue ?? 0 }
        func celsius(_ key: String, _ ok: Bool) -> String {
            ok ? "\(Int((stats[key]?.doubleValue ?? 0).rounded())) °C" : "--°C"
        }
        func lpm(_ key: String, _ ok: Bool) -> String {
            ok ? "\(Int((stats[key]?.doubleValue ?? 0).rounded())) LPM" : "—"
        }

        vitals = fresh("thVitalsAgeMs")
        modeFresh = fresh("thModeAgeMs")
        let pumpBattery = int("thPumpBatRpm"), pumpPt = int("thPumpPtRpm"), fanRpm = int("thFanRpm")
        let valve = int("thValveMode") & 3
        var mode: Mode
        if !modeFresh {
            mode = .off
        } else if valve == 3 {
            mode = .ambient
        } else if valve == 1 {
            mode = .parallel
        } else {
            mode = int("thHpReq") == 2 ? .bypass : .series
        }
        if vitals && pumpBattery == 0 && pumpPt == 0 { mode = .off }
        self.mode = mode

        // 串联类模式只有一个回路：任一台泵在转，整条回路都在流动
        let singleLoop = mode == .bypass || mode == .series
        ptLoopFlowing = vitals && (pumpPt > 0 || (singleLoop && pumpBattery > 0))
        batteryLoopFlowing = vitals && pumpBattery > 0
        ptPumpSpinning = vitals && pumpPt > 0
        batteryPumpSpinning = vitals && pumpBattery > 0
        fanSpinning = vitals && fanRpm > 0
        valveName = fresh("thSysAgeMs") && stats["thHeatPump"]?.boolValue == true
            ? "Octovalve" : L10n.t("冷却液阀", "Coolant valve")
        fan = vitals ? String(fanRpm) : "—"
        ptPump = vitals ? String(pumpPt) : "—"
        batteryPump = vitals ? String(pumpBattery) : "—"

        inletsFresh = fresh("thInletsAgeMs", Self.slowMs)
        let flows = fresh("thFlowsAgeMs")
        ptInlet = celsius("thPtInletC", inletsFresh)
        batteryInlet = celsius("thBatInletC", inletsFresh)
        ptFlow = lpm("thFlowPtLpm", flows)
        batteryFlow = lpm("thFlowBatLpm", flows)
        pcsFresh = fresh("thPcsAgeMs", Self.slowMs)
        dcdc = celsius("thDcdcC", pcsFresh)
        charger = celsius("thChargerC", pcsFresh)
        frontInverterFresh = fresh("thInvFrontAgeMs", Self.slowMs)
        frontInverter = celsius("thInvFrontC", frontInverterFresh)
        rearInverterFresh = fresh("thInvRearAgeMs", Self.slowMs)
        rearInverter = celsius("thInvRearC", rearInverterFresh)
        autopilotFresh = fresh("thApAgeMs", Self.slowMs)
        autopilot = celsius("thApC", autopilotFresh)
        infotainmentFresh = fresh("thInfoAgeMs", Self.slowMs)
        infotainment = celsius("thInfoC", infotainmentFresh)
        packFresh = stats["packSeen"]?.boolValue == true
        packMax = celsius("packTempMaxC", packFresh)
        packMin = celsius("packTempMinC", packFresh)
        ambientFresh = stats["ptAmbientSeen"]?.boolValue == true && fresh("ptAmbientAgeMs", Self.slowMs)
        ambient = ambientFresh ? celsius("ptAmbientC", true) : "—"
    }

    /// 回路模式文字；没有阀门帧时为「—」
    var modeLabel: String {
        guard modeFresh else { return "—" }
        switch mode {
        case .off: return L10n.t("停止", "Off")
        case .bypass: return L10n.t("串联散热器旁通", "Series Radiator Bypass")
        case .ambient: return L10n.t("环境热源", "Ambient Source")
        case .series: return L10n.t("串联", "Series")
        case .parallel: return L10n.t("并联", "Parallel")
        }
    }

    var hasMotion: Bool { ptLoopFlowing || batteryLoopFlowing || fanSpinning }

    var accessibilitySummary: String {
        L10n.t("冷却回路，模式 \(modeLabel)，动力总成泵 \(ptPump) 转，电池泵 \(batteryPump) 转，风扇 \(fan) 转，电池回路入口 \(batteryInlet)，动力总成回路入口 \(ptInlet)，高压电池 \(packMin) 至 \(packMax)",
               "Coolant loops, mode \(modeLabel), PT pump \(ptPump) RPM, battery pump \(batteryPump) RPM, fan \(fan) RPM, battery inlet \(batteryInlet), PT inlet \(ptInlet), HV battery \(packMin) to \(packMax)")
    }
}

/// 把官方 SVG 路径命令逐条转写为 SwiftUI Path（M / V / H / L / Q / C / Z，绝对坐标）。
private struct PathPen {
    private(set) var path = Path()
    private var point = CGPoint.zero

    func m(_ x: CGFloat, _ y: CGFloat) -> PathPen {
        var pen = self
        pen.point = CGPoint(x: x, y: y)
        pen.path.move(to: pen.point)
        return pen
    }

    func l(_ x: CGFloat, _ y: CGFloat) -> PathPen {
        var pen = self
        pen.point = CGPoint(x: x, y: y)
        pen.path.addLine(to: pen.point)
        return pen
    }

    func v(_ y: CGFloat) -> PathPen { l(point.x, y) }
    func h(_ x: CGFloat) -> PathPen { l(x, point.y) }

    func q(_ cx: CGFloat, _ cy: CGFloat, _ x: CGFloat, _ y: CGFloat) -> PathPen {
        var pen = self
        pen.point = CGPoint(x: x, y: y)
        pen.path.addQuadCurve(to: pen.point, control: CGPoint(x: cx, y: cy))
        return pen
    }

    func c(_ c1x: CGFloat, _ c1y: CGFloat, _ c2x: CGFloat, _ c2y: CGFloat, _ x: CGFloat, _ y: CGFloat) -> PathPen {
        var pen = self
        pen.point = CGPoint(x: x, y: y)
        pen.path.addCurve(to: pen.point, control1: CGPoint(x: c1x, y: c1y), control2: CGPoint(x: c2x, y: c2y))
        return pen
    }

    func z() -> PathPen {
        var pen = self
        pen.path.closeSubpath()
        return pen
    }
}

private extension Color {
    init(rgb: UInt32) {
        self.init(.sRGB,
                  red: Double((rgb >> 16) & 0xFF) / 255,
                  green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255)
    }
}
