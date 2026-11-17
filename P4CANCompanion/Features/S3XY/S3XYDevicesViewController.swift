import UIKit
// SnapKit 以源码形式内置（Vendor/SnapKit），无需 import
import SwiftUI

/// 「蓝牙」页：S3XY 蓝牙管理（纯 UIKit + SnapKit）。
///
/// 与固件 s3xy_ble.h 的真实契约：
/// - 设备以槽位 `id` 标识（1..N），`address` 为 BLE MAC；
/// - 配对 `pair?address=`；连接/断开/握手/忘记/自动重连 均带 `id`；
/// - 动作绑定 `device/action?id=&gesture=single|double|long&action=<code>`；
/// - 扫描结果来自 stats 的 `scanResults[]`（含 registered 标记）；
/// - 蓝牙总开关为独立端点（v3.29.3 修复点）。
final class S3XYDevicesViewController: UIViewController {

    private let environment: AppEnvironment

    private let headerView = S3XYHeaderView()
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>?

    private var devices: [S3XYDevice] = []
    private var scanResults: [S3XYScanResult] = []
    private var pollTask: Task<Void, Never>?
    private var statusMessage: String?

    private enum Section: Int, CaseIterable {
        case paired
        case discovered

        var title: String {
            switch self {
            case .paired: return "已配对设备"
            case .discovered: return "扫描结果"
            }
        }
    }

    private enum Item: Hashable {
        case device(S3XYDevice)
        case scan(S3XYScanResult)
    }

    // MARK: - 生命周期

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持 storyboard 初始化") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        navigationItem.title = "S3XY 蓝牙"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            style: .plain,
            target: self,
            action: #selector(showGlobalMenu)
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel = "更多蓝牙维护操作"

        setupHeader()
        setupCollectionView()
        applySnapshot()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startPolling()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Header（SnapKit）

    private func setupHeader() {
        view.addSubview(headerView)
        headerView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(8)
            make.leading.trailing.equalTo(view.safeAreaLayoutGuide).inset(16)
        }
        headerView.onBluetoothToggled = { [weak self] enabled in
            Task { await self?.setBluetooth(enabled: enabled) }
        }
        headerView.onScanTapped = { [weak self] in
            Task { await self?.scan() }
        }
    }

    private func setupCollectionView() {
        var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        configuration.headerMode = .supplementary
        configuration.backgroundColor = .clear
        let layout = UICollectionViewCompositionalLayout.list(using: configuration)

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.top.equalTo(headerView.snp.bottom).offset(8)
            make.leading.trailing.bottom.equalTo(view.safeAreaLayoutGuide)
        }

        let deviceRegistration = UICollectionView.CellRegistration<S3XYDeviceCell, S3XYDevice> { [weak self] cell, _, device in
            cell.configure(with: device)
            cell.onActionTapped = { [weak self] device in
                self?.showDeviceMenu(for: device)
            }
        }
        let scanRegistration = UICollectionView.CellRegistration<S3XYScanCell, S3XYScanResult> { [weak self] cell, _, result in
            cell.configure(with: result)
            cell.onPair = { [weak self] result in
                Task { await self?.pair(result) }
            }
        }

        dataSource = UICollectionViewDiffableDataSource<Section, Item>(
            collectionView: collectionView
        ) { collectionView, indexPath, item in
            switch item {
            case .device(let device):
                return collectionView.dequeueConfiguredReusableCell(
                    using: deviceRegistration, for: indexPath, item: device
                )
            case .scan(let result):
                return collectionView.dequeueConfiguredReusableCell(
                    using: scanRegistration, for: indexPath, item: result
                )
            }
        }

        let headerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { header, _, indexPath in
            guard let section = Section(rawValue: indexPath.section) else { return }
            var content = UIListContentConfiguration.groupedHeader()
            content.text = section.title
            header.contentConfiguration = content
        }
        dataSource?.supplementaryViewProvider = { collectionView, kind, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(
                using: headerRegistration, for: indexPath
            )
        }
    }

    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.paired, .discovered])
        snapshot.appendItems(devices.map { .device($0) }, toSection: .paired)
        snapshot.appendItems(scanResults.map { .scan($0) }, toSection: .discovered)
        dataSource?.apply(snapshot, animatingDifferences: true)
    }

    // MARK: - 轮询

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func refresh() async {
        do {
            let stats = try await environment.api.get(P4Route.s3xyStats)
            devices = S3XYDevice.devices(from: stats)
            scanResults = S3XYScanResult.results(from: stats)
            headerView.update(with: stats)
            applySnapshot()
            if let message = statusMessage {
                headerView.setStatus(message)
                statusMessage = nil
            }
        } catch {
            headerView.setStatus(AppEnvironment.friendly(error))
        }
    }

    // MARK: - 蓝牙总开关 / 扫描

    private func setBluetooth(enabled: Bool) async {
        let path = enabled ? P4Route.s3xyBluetoothEnable : P4Route.s3xyBluetoothDisable
        statusMessage = enabled ? "正在开启蓝牙…" : "正在关闭蓝牙（BLE 任务停止需要时间）…"
        do {
            _ = try await environment.api.post(path)
            statusMessage = enabled ? "蓝牙已开启。" : "蓝牙已关闭。"
        } catch {
            statusMessage = "蓝牙开关失败：\(AppEnvironment.friendly(error))"
        }
        await refresh()
    }

    private func scan() async {
        statusMessage = "正在扫描附近设备…"
        do {
            _ = try await environment.api.post(P4Route.s3xyScan)
            statusMessage = "扫描已开始，结果会自动刷新。"
        } catch {
            statusMessage = "扫描失败：\(AppEnvironment.friendly(error))"
        }
        await refresh()
    }

    private func pair(_ result: S3XYScanResult) async {
        statusMessage = "正在配对 \(result.name)…"
        do {
            _ = try await environment.api.post(
                P4Route.s3xyPair,
                query: [P4Param("address", result.address)]
            )
            statusMessage = "配对请求已提交。"
        } catch {
            statusMessage = "配对失败：\(AppEnvironment.friendly(error))"
        }
        await refresh()
    }

    // MARK: - 设备菜单

    private func showDeviceMenu(for device: S3XYDevice) {
        let alert = UIAlertController(
            title: device.name,
            message: "槽位 \(device.slot) · \(device.address)\n状态：\(device.state)",
            preferredStyle: .actionSheet
        )
        alert.popoverPresentationController?.sourceView = view

        alert.addAction(UIAlertAction(title: device.connected ? "断开连接" : "连接", style: .default) { [weak self] _ in
            Task {
                await self?.deviceCommand(
                    device.connected ? "断开" : "连接",
                    device.connected ? P4Route.s3xyDeviceDisconnect : P4Route.s3xyDeviceConnect,
                    device
                )
            }
        })
        alert.addAction(UIAlertAction(title: "握手同步", style: .default) { [weak self] _ in
            Task { await self?.deviceCommand("握手", P4Route.s3xyDeviceHandshake, device) }
        })
        alert.addAction(UIAlertAction(title: device.autoConnect ? "关闭自动重连" : "开启自动重连", style: .default) { [weak self] _ in
            Task {
                await self?.deviceCommand(
                    "自动重连",
                    P4Route.s3xyDeviceAuto,
                    device,
                    extra: [P4Param("enabled", device.autoConnect ? "0" : "1")]
                )
            }
        })
        alert.addAction(UIAlertAction(title: "设置单击动作（\(device.singleLabel)）", style: .default) { [weak self] _ in
            self?.showActionPicker(gesture: "single", device: device)
        })
        alert.addAction(UIAlertAction(title: "设置双击动作（\(device.doubleLabel)）", style: .default) { [weak self] _ in
            self?.showActionPicker(gesture: "double", device: device)
        })
        alert.addAction(UIAlertAction(title: "设置长按动作（\(device.longLabel)）", style: .default) { [weak self] _ in
            self?.showActionPicker(gesture: "long", device: device)
        })
        alert.addAction(UIAlertAction(title: "重命名", style: .default) { [weak self] _ in
            self?.showRenameDialog(for: device)
        })
        alert.addAction(UIAlertAction(title: "忘记设备", style: .destructive) { [weak self] _ in
            Task { await self?.deviceCommand("忘记设备", P4Route.s3xyDeviceForget, device) }
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }

    private func showActionPicker(gesture: String, device: S3XYDevice) {
        let gestureName: String
        switch gesture {
        case "single": gestureName = "单击"
        case "double": gestureName = "双击"
        default: gestureName = "长按"
        }
        let sheet = UIAlertController(
            title: "\(gestureName)动作",
            message: "绑定后由设备直接触发（固件按当前车型校验可用性）",
            preferredStyle: .actionSheet
        )
        sheet.popoverPresentationController?.sourceView = view
        let current: String
        switch gesture {
        case "single": current = device.singleAction
        case "double": current = device.doubleAction
        default: current = device.longAction
        }
        for option in S3XYActionCatalog.options {
            let title = option.code == current ? "✓ \(option.label)" : option.label
            sheet.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                Task {
                    await self?.deviceCommand(
                        "绑定\(gestureName)动作",
                        P4Route.s3xyDeviceAction,
                        device,
                        extra: [
                            P4Param("gesture", gesture),
                            P4Param("action", option.code),
                        ]
                    )
                }
            })
        }
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(sheet, animated: true)
    }

    private func showRenameDialog(for device: S3XYDevice) {
        let alert = UIAlertController(title: "重命名设备", message: device.address, preferredStyle: .alert)
        alert.addTextField { field in
            field.text = device.name
            field.accessibilityLabel = "新设备名称"
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak self] _ in
            let name = alert.textFields?.first?.text ?? device.name
            Task {
                await self?.deviceCommand(
                    "重命名", P4Route.s3xyDeviceRename, device,
                    extra: [P4Param("name", name)]
                )
            }
        })
        present(alert, animated: true)
    }

    private func deviceCommand(
        _ label: String,
        _ path: String,
        _ device: S3XYDevice,
        extra: [P4Param] = []
    ) async {
        statusMessage = "正在执行「\(label)」…"
        do {
            _ = try await environment.api.post(
                path,
                query: [P4Param("id", "\(device.slot)")] + extra
            )
            statusMessage = "「\(label)」已提交。"
        } catch {
            statusMessage = "「\(label)」失败：\(AppEnvironment.friendly(error))"
        }
        await refresh()
    }

    // MARK: - 全局维护

    @objc private func showGlobalMenu() {
        let alert = UIAlertController(title: "蓝牙维护", message: nil, preferredStyle: .actionSheet)
        alert.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
        alert.addAction(UIAlertAction(title: "自动重连总开关", style: .default) { [weak self] _ in
            guard let self else { return }
            guard let auto = self.headerView.autoEnabled else {
                self.headerView.setStatus("尚未读取到设备的自动重连状态，请稍后重试")
                return
            }
            Task {
                await self.globalCommand(
                    auto ? "关闭自动重连" : "开启自动重连",
                    auto ? P4Route.s3xyAutoDisable : P4Route.s3xyAutoEnable
                )
            }
        })
        alert.addAction(UIAlertAction(title: "重置全部蓝牙", style: .destructive) { [weak self] _ in
            Task { await self?.globalCommand("重置全部蓝牙", P4Route.s3xyResetAll) }
        })
        alert.addAction(UIAlertAction(title: "清除 S3XY 记录", style: .destructive) { [weak self] _ in
            Task { await self?.globalCommand("清除记录", P4Route.s3xyClear) }
        })
        alert.addAction(UIAlertAction(title: "导出 S3XY 日志", style: .default) { [weak self] _ in
            Task { await self?.exportLog(P4LogFile.s3xyLog) }
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }

    private func globalCommand(_ label: String, _ path: String) async {
        statusMessage = "正在执行「\(label)」…"
        do {
            _ = try await environment.api.post(path)
            statusMessage = "「\(label)」已执行。"
        } catch {
            statusMessage = "「\(label)」失败：\(AppEnvironment.friendly(error))"
        }
        await refresh()
    }

    private func exportLog(_ log: P4LogFile) async {
        do {
            let url = try await environment.exportLogFile(log)
            let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            share.popoverPresentationController?.sourceView = view
            present(share, animated: true)
        } catch {
            statusMessage = "导出失败：\(AppEnvironment.friendly(error))"
            await refresh()
        }
    }
}

// MARK: - 上下文菜单

extension S3XYDevicesViewController: UICollectionViewDelegate {

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let indexPath = indexPaths.first,
              let item = dataSource?.itemIdentifier(for: indexPath) else { return nil }
        switch item {
        case .device(let device):
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
                UIMenu(children: [
                    UIAction(title: "操作菜单…", image: UIImage(systemName: "ellipsis.circle")) { [weak self] _ in
                        self?.showDeviceMenu(for: device)
                    },
                    UIAction(title: device.connected ? "断开" : "连接", image: UIImage(systemName: "link")) { [weak self] _ in
                        Task {
                            await self?.deviceCommand(
                                device.connected ? "断开" : "连接",
                                device.connected ? P4Route.s3xyDeviceDisconnect : P4Route.s3xyDeviceConnect,
                                device
                            )
                        }
                    },
                    UIAction(title: "忘记设备", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                        Task { await self?.deviceCommand("忘记设备", P4Route.s3xyDeviceForget, device) }
                    },
                ])
            }
        case .scan(let result):
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
                UIMenu(children: [
                    UIAction(title: "配对", image: UIImage(systemName: "dot.radiowaves.left.and.right")) { [weak self] _ in
                        Task { await self?.pair(result) }
                    },
                ])
            }
        }
    }
}

// MARK: - Header 视图（SnapKit）

final class S3XYHeaderView: UIView {

    var onBluetoothToggled: ((Bool) -> Void)?
    var onScanTapped: (() -> Void)?
    private(set) var autoEnabled: Bool?

    private let titleLabel = UILabel()
    private let bluetoothSwitch = UISwitch()
    private let bluetoothLabel = UILabel()
    private let scanButton = UIButton(type: .system)
    private let statsLabel = UILabel()
    private let statusLabel = UILabel()
    private let noteLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
        setupConstraints()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持 storyboard 初始化") }

    private func setupViews() {
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous

        titleLabel.text = "S3XY 蓝牙设备"
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true

        bluetoothLabel.text = "蓝牙总开关"
        bluetoothLabel.font = .preferredFont(forTextStyle: .body)
        bluetoothLabel.adjustsFontForContentSizeCategory = true

        bluetoothSwitch.addTarget(self, action: #selector(switchChanged), for: .valueChanged)
        bluetoothSwitch.accessibilityLabel = "蓝牙总开关"
        bluetoothSwitch.accessibilityHint = "切换设备的 BLE 任务，需要数秒生效"

        var configuration = UIButton.Configuration.filled()
        configuration.title = "扫描设备"
        configuration.image = UIImage(systemName: "dot.radiowaves.forward")
        configuration.cornerStyle = .capsule
        scanButton.configuration = configuration
        scanButton.addTarget(self, action: #selector(scanTapped), for: .touchUpInside)
        scanButton.accessibilityLabel = "扫描附近的 S3XY 设备"

        for label in [statsLabel, statusLabel, noteLabel] {
            label.font = .preferredFont(forTextStyle: .footnote)
            label.adjustsFontForContentSizeCategory = true
            label.textColor = .secondaryLabel
            label.numberOfLines = 0
        }
        noteLabel.font = .preferredFont(forTextStyle: .caption2)
        noteLabel.text = "固件 v3.29.3 已修复蓝牙总开关作用域；开关状态以设备上报为准。"

        [titleLabel, bluetoothLabel, bluetoothSwitch, scanButton, statsLabel, statusLabel, noteLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
    }

    private func setupConstraints() {
        titleLabel.snp.makeConstraints { make in
            make.leading.top.equalToSuperview().inset(16)
        }
        bluetoothSwitch.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(16)
            make.centerY.equalTo(titleLabel)
        }
        bluetoothLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(16)
            make.trailing.lessThanOrEqualTo(bluetoothSwitch.snp.leading).offset(-8)
            make.top.equalTo(titleLabel.snp.bottom).offset(12)
        }
        scanButton.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(16)
            make.top.equalTo(bluetoothLabel.snp.bottom).offset(12)
        }
        statsLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(16)
            make.top.equalTo(scanButton.snp.bottom).offset(12)
        }
        statusLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(16)
            make.top.equalTo(statsLabel.snp.bottom).offset(8)
        }
        noteLabel.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview().inset(16)
            make.top.equalTo(statusLabel.snp.bottom).offset(8)
        }
    }

    @objc private func switchChanged() {
        onBluetoothToggled?(bluetoothSwitch.isOn)
    }

    @objc private func scanTapped() {
        onScanTapped?()
    }

    func update(with stats: P4JSON) {
        let object = stats.objectValue ?? [:]
        // 设备没上报就不显示开关状态（禁用而不是假装「关」）
        if let enabled = object["bluetoothEnabled"]?.boolValue {
            bluetoothSwitch.isEnabled = true
            bluetoothSwitch.setOn(enabled, animated: true)
        } else {
            bluetoothSwitch.isEnabled = false
        }
        autoEnabled = object["autoEnabled"]?.boolValue
        var parts: [String] = []
        if let paired = object["pairedCount"]?.intValue { parts.append("已配对 \(paired)") }
        if let connected = object["connectedCount"]?.intValue { parts.append("已连接 \(connected)") }
        if autoEnabled == true { parts.append("自动重连开") }
        if object["scanning"]?.boolValue == true { parts.append("扫描中") }
        if object["cryptoSelfTestOk"]?.boolValue == false { parts.append("加密自检异常") }
        statsLabel.text = parts.isEmpty ? "读取中…" : parts.joined(separator: " · ")
        if let error = object["probeError"]?.stringValue, !error.isEmpty {
            statusLabel.text = "最近探测错误：\(error)"
        }
    }

    func setStatus(_ message: String) {
        statusLabel.text = message
    }
}
