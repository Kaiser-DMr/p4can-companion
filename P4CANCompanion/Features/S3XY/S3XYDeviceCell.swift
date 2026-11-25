import UIKit
// SnapKit 以源码形式内置（Vendor/SnapKit），无需 import

/// S3XY 已配对设备行。
///
/// 使用 `UICollectionViewListCell` + `UIListContentConfiguration`，
/// 由系统负责自适应宽度/高度与 Dynamic Type；操作按钮通过 `UICellAccessory.customView` 挂载，
/// 避免自定义子视图在列表布局下被压缩成窄列。
final class S3XYDeviceCell: UICollectionViewListCell {

    static let reuseIdentifier = "S3XYDeviceCell"

    private let actionButton = UIButton(type: .system)
    private var device: S3XYDevice?
    var onActionTapped: ((S3XYDevice) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        var configuration = UIButton.Configuration.bordered()
        configuration.title = "操作"
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
        actionButton.configuration = configuration
        actionButton.accessibilityLabel = "打开设备操作菜单"
        actionButton.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)

        accessories = [
            .customView(configuration: .init(
                customView: actionButton,
                placement: .trailing(),
                reservedLayoutWidth: .custom(64)
            )),
        ]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持 storyboard 初始化") }

    @objc private func actionTapped() {
        guard let device else { return }
        onActionTapped?(device)
    }

    func configure(with device: S3XYDevice) {
        self.device = device

        var content = UIListContentConfiguration.subtitleCell()
        content.text = device.name
        content.textProperties.font = .preferredFont(forTextStyle: .headline)
        content.textProperties.numberOfLines = 2

        var lines: [String] = []
        lines.append("状态：\(device.state)\(device.connected ? " · 已连接" : "")\(device.paused ? " · 已暂停" : "")")
        lines.append("地址：\(device.address)")
        if let rssi = device.rssi { lines.append("RSSI \(rssi) dBm") }
        lines.append("单击 \(device.singleLabel) · 双击 \(device.doubleLabel) · 长按 \(device.longLabel)")
        if let error = device.error, !error.isEmpty { lines.append("错误：\(error)") }
        content.secondaryText = lines.joined(separator: "\n")
        content.secondaryTextProperties.font = .preferredFont(forTextStyle: .subheadline)
        content.secondaryTextProperties.color = .secondaryLabel
        content.secondaryTextProperties.numberOfLines = 0
        content.image = UIImage.p4Tile(systemName: "dot.radiowaves.left.and.right",
                                       color: device.connected ? .systemGreen : .systemBlue)
        content.imageToTextPadding = Theme.Icon.gap

        contentConfiguration = content
        accessibilityLabel = "\(device.name)，状态\(device.state)"
        accessibilityHint = "操作按钮可连接、重命名或忘记设备"
    }
}

/// 扫描结果行。
final class S3XYScanCell: UICollectionViewListCell {

    static let reuseIdentifier = "S3XYScanCell"

    private let pairButton = UIButton(type: .system)
    private var result: S3XYScanResult?
    var onPair: ((S3XYScanResult) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        var configuration = UIButton.Configuration.filled()
        configuration.title = "配对"
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
        pairButton.configuration = configuration
        pairButton.accessibilityLabel = "配对该设备"
        pairButton.addTarget(self, action: #selector(pairTapped), for: .touchUpInside)

        accessories = [
            .customView(configuration: .init(
                customView: pairButton,
                placement: .trailing(),
                reservedLayoutWidth: .custom(64)
            )),
        ]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持 storyboard 初始化") }

    @objc private func pairTapped() {
        guard let result else { return }
        onPair?(result)
    }

    func configure(with result: S3XYScanResult) {
        self.result = result

        var content = UIListContentConfiguration.subtitleCell()
        content.text = result.name
        var parts = [result.address]
        if let rssi = result.rssi { parts.append("RSSI \(rssi) dBm") }
        if result.registered { parts.append("已注册") }
        content.secondaryText = parts.joined(separator: " · ")
        content.image = UIImage.p4Tile(systemName: "dot.radiowaves.forward", color: .systemTeal)
        content.imageToTextPadding = Theme.Icon.gap
        contentConfiguration = content
        accessibilityLabel = "\(result.name)，\(result.address)"
    }
}
