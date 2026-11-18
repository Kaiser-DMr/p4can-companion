import SwiftUI

// MARK: - 卡片容器

/// 分组卡片：标题 + SF Symbol + 内容。全宽 16pt 边距（8pt 网格 ×2）。
struct Card<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(2)) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .padding(Theme.spacing(2))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.p4Card, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }
}

// MARK: - 键值行

/// 固件状态键值行：左侧本地化键名，右侧格式化值。
/// 无障碍：合并为一行朗读“名称，值”。
struct MetricRow: View {
    let key: String
    let value: P4JSON

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(P4KeyLocalization.label(for: key))
                .foregroundStyle(.secondary)
            Spacer(minLength: Theme.spacing(1))
            Text(P4Format.value(for: key, of: value))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(P4KeyLocalization.label(for: key))，\(P4Format.value(for: key, of: value))")
    }
}

// MARK: - 状态徽章

/// 总线/连接状态徽章：图标 + 文字（颜色仅作辅助）。
struct StateBadge: View {
    let text: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.footnote.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, Theme.spacing(1))
            .padding(.vertical, Theme.spacing(0.5))
            .background(color.opacity(0.12), in: Capsule())
            .accessibilityLabel("\(text)状态")
    }
}

// MARK: - 骨架屏

/// 加载占位（禁止全屏 spinner，使用 redacted 骨架）。
struct SkeletonRows: View {
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(1.5)) {
            ForEach(0..<count, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Theme.spacing(0.5))
                    .fill(Color.p4Card)
                    .frame(height: 18)
                    .redacted(reason: .placeholder)
            }
        }
    }
}

// MARK: - 提示横幅

/// 命令执行结果的浮动提示，自动消失。
struct ToastOverlay: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        if let toast = environment.toast {
            VStack {
                Spacer()
                HStack(spacing: Theme.spacing(1)) {
                    switch toast.style {
                    case .success:
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.p4OK)
                    case .failure:
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.p4Err)
                    case .info:
                        Image(systemName: "info.circle.fill").foregroundStyle(.tint)
                    }
                    Text(toast.message)
                        .font(.footnote)
                        .multilineTextAlignment(.leading)
                }
                .padding(Theme.spacing(2))
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.spacing(1.5)))
                .padding(.horizontal, Theme.spacing(2))
                .padding(.bottom, Theme.spacing(2))
                .accessibilityElement(children: .combine)
            }
            .task(id: toast.id) {
                try? await Task.sleep(for: .seconds(4))
                if environment.toast?.id == toast.id {
                    environment.toast = nil
                }
            }
        }
    }
}


// MARK: - 状态胶囊（标签）

/// 状态标签：图标 + 文字 + 语义色，颜色只作辅助，文字本身可读。
struct StatusChip: View {
    let text: String
    var systemImage: String? = nil
    var tone: P4Tone = .neutral

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage).font(.caption2.weight(.semibold))
            }
            Text(text).font(.caption.weight(.medium))
        }
        .foregroundStyle(tone.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tone.color.opacity(0.12), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}


// MARK: - 模块图标

/// 模块图标：优先按 Assets 资源名查找（如 TLSSC 的红绿灯），否则回退 SF Symbol。
struct ModuleIcon: View {
    let name: String

    var body: some View {
        if name == "trafficlight" {
            Text("🚦").font(.system(size: 17))
        } else if UIImage(named: name) != nil {
            Image(name)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
        } else {
            Image(systemName: name)
        }
    }
}

// MARK: - KPI 瓦片

/// 关键指标瓦片：图标 + 名称 + 大数字（+ 单位）+ 备注。
/// 设备未上报时传 "—"，不伪造数值。
struct MetricTile: View {
    let icon: String
    let title: String
    let value: String
    var unit: String? = nil
    var tone: P4Tone = .info
    var footnote: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tone.color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(Theme.TypeScale.metric())
                    .monospacedDigit()
                    .foregroundStyle(value == "—" ? Color.secondary : Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let unit {
                    Text(unit).font(.caption2).foregroundStyle(.secondary)
                }
            }
            if let footnote {
                Text(footnote).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(Theme.spacing(1.5))
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
        .background(Color.p4Card, in: RoundedRectangle(cornerRadius: Theme.Radius.tile))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.tile)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)，\(value)\(unit ?? "")")
    }
}

// MARK: - 细进度条

/// 细进度条：用于发送成功率、固件写入进度等。数值 0…1。
struct SlimProgress: View {
    let value: Double
    var tint: Color = .p4Info
    var height: CGFloat = 6
    var label: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.p4Tile)
                    Capsule()
                        .fill(tint)
                        .frame(width: max(0, min(1, value)) * geo.size.width)
                }
            }
            .frame(height: height)
            if let label {
                Text(label).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label ?? "进度")
        .accessibilityValue("\(Int((min(max(value, 0), 1)) * 100))%")
    }
}

// MARK: - 占比条

/// 横向占比条 + 图例：展示三路总线的接收帧占比。
struct RatioBar: View {
    struct Segment: Identifiable {
        let id: String
        let label: String
        let value: Double
        let color: Color
    }

    let segments: [Segment]

    private var total: Double {
        max(segments.reduce(0) { $0 + max($1.value, 0) }, 0.0001)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                let gap: CGFloat = 3
                let available = max(geo.size.width - gap * CGFloat(max(segments.count - 1, 0)), 1)
                HStack(spacing: gap) {
                    ForEach(segments) { segment in
                        Capsule()
                            .fill(segment.color)
                            .frame(width: max(3, available * CGFloat(max(segment.value, 0) / total)))
                    }
                }
            }
            .frame(height: 10)

            HStack(spacing: Theme.spacing(1.5)) {
                ForEach(segments) { segment in
                    HStack(spacing: 4) {
                        Circle().fill(segment.color).frame(width: 6, height: 6)
                        Text(segment.label).font(.caption2).foregroundStyle(.secondary)
                        Text("\(Int((max(segment.value, 0) / total) * 100))%")
                            .font(.caption2.weight(.medium))
                            .monospacedDigit()
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("接收帧占比：" + segments.map { "\($0.label) \(Int((max($0.value, 0) / total) * 100))%" }.joined(separator: "，"))
    }
}
