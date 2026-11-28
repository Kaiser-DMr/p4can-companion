import SwiftUI

/// 配置器车辆图：按视角切换时侧滑加淡入淡出，车漆、轮毂、车型变化时淡入淡出。
/// 不同视角的图都已裁到车身范围，等比缩放后底边落在同一条地面线上。
struct VehicleHeroImage: View, Equatable {
    let appearance: VehicleAppearance
    let angle: VehicleAngle

    nonisolated static func == (lhs: VehicleHeroImage, rhs: VehicleHeroImage) -> Bool {
        lhs.appearance == rhs.appearance && lhs.angle == rhs.angle
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Layer?
    @State private var direction: CGFloat = 1
    @State private var failed = false

    /// 已缓存的车图在首帧直接显示，不经过空白再淡入
    init(appearance: VehicleAppearance, angle: VehicleAngle) {
        self.appearance = appearance
        self.angle = angle
        let url = VehicleCatalog.imageURL(appearance, angle: angle)
        _shown = State(initialValue: VehicleImageStore.shared.cached(url).map {
            Layer(url: url, appearance: appearance, angle: VehicleCatalog.effectiveAngle(appearance, angle), image: $0)
        })
    }

    private struct Layer: Identifiable, Equatable {
        let url: URL
        let appearance: VehicleAppearance
        let angle: VehicleAngle
        let image: VehicleImage
        var id: URL { url }
        static func == (lhs: Layer, rhs: Layer) -> Bool { lhs.url == rhs.url }
    }

    private var url: URL { VehicleCatalog.imageURL(appearance, angle: angle) }

    var body: some View {
        ZStack {
            if let shown {
                car(shown)
                    .id(shown.id)
                    .transition(transition)
            } else if failed {
                // 联网车图不可用（无网络、被限流）时显示内置的同车型侧视图
                Image(VehicleBodyStyle(generationID: appearance.generation.id).assetName)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .task(id: url) { await load(url) }
        .accessibilityElement()
        .accessibilityLabel(L10n.t(
            "\(appearance.generation.zh) \(appearance.trim.zh)，\(appearance.paint.zh)，\(appearance.wheel.zh)",
            "\(appearance.generation.en) \(appearance.trim.en), \(appearance.paint.en), \(appearance.wheel.en)"))
    }

    private var transition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .offset(x: 36 * direction).combined(with: .opacity),
            removal: .offset(x: -36 * direction).combined(with: .opacity)
        )
    }

    /// 图片已裁到车身范围：按容器等比缩放，水平居中、底边贴住容器底部。
    private func car(_ layer: Layer) -> some View {
        Image(uiImage: layer.image.image)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private func load(_ target: URL) async {
        if let hit = VehicleImageStore.shared.cached(target) {
            show(target, hit)
            return
        }
        do {
            let image = try await VehicleImageStore.shared.image(for: target)
            guard !Task.isCancelled else { return }
            show(target, image)
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled else { return }
            failed = true
            // 只有视角加载失败时保留当前车图；车型、车漆或轮毂已变时不能继续显示旧外观
            if shown?.appearance != appearance { shown = nil }
        }
    }

    private func show(_ target: URL, _ image: VehicleImage) {
        guard shown?.url != target else { return }
        let effective = VehicleCatalog.effectiveAngle(appearance, angle)
        let next = Layer(url: target, appearance: appearance, angle: effective, image: image)
        let turns = shown.map { $0.angle != effective } ?? false
        if let current = shown, turns {
            direction = effective.rawValue > current.angle.rawValue ? 1 : -1
        }
        failed = false
        if shown == nil {
            shown = next
        } else {
            // 先让旧图以新方向渲染一次，移出动画才会朝正确方向滑动
            Task { @MainActor in
                withAnimation(.easeInOut(duration: turns ? 0.55 : 0.4)) { shown = next }
            }
        }
    }
}
