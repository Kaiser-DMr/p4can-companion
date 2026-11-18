import UIKit
import SwiftUI

/// 根控制器：UIKit UITabBarController 承载主标签。
/// - 状态 / 功能 / 系统：SwiftUI 视图通过 UIHostingController 挂载
/// - 蓝牙（S3XY）：纯 UIKit + SnapKit + UICollectionView(CompositionalLayout + Diffable)
///   —— 默认不出现在标签栏，可在「系统 → 界面」开启后显示（多数时间用不到，避免占位）
///
/// 说明：不使用 hamburger 菜单，遵循 HIG 的 Tab 导航；
/// 不覆盖系统返回手势；Modal 均提供取消路径。
final class RootTabBarController: UITabBarController {

    private let environment: AppEnvironment

    private var overviewController: UIViewController!
    private var featuresController: UIViewController!
    private var labController: UIViewController!
    private var s3xyController: UIViewController!
    private var systemController: UIViewController!
    #if DEBUG
    private var debugTabApplied = false
    #endif

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持 storyboard 初始化") }

    override func viewDidLoad() {
        super.viewDidLoad()

        // 全 App 唯一强调色：琥珀（浅色下压深）。UIKit 壳层（标签栏、返回键）也要同步，
        // 否则 SwiftUI 用 p4Accent、系统控件还是默认蓝，会出现两种强调色。
        let accent = UIColor(Color.p4Accent)
        view.tintColor = accent
        tabBar.tintColor = accent
        tabBar.unselectedItemTintColor = UIColor.secondaryLabel
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance

        overviewController = makeHosting(
            DashboardView(),
            title: L10n.t("状态", "Status"),
            // 注意：SF Symbols 里没有 gauge.with.dots.needle.bottom.50.percent，
            // 用错名字会得到空白占位图标（之前状态页图标消失的原因）。
            image: "gauge.with.dots.needle.50percent",
            accessibilityLabel: L10n.t("设备状态总览", "Device status"),
            tag: 0
        )
        featuresController = makeHosting(
            FeaturesView(),
            title: L10n.t("功能", "Features"),
            image: "switch.programmable",
            accessibilityLabel: L10n.t("功能开关列表", "Feature list"),
            tag: 1
        )
        labController = makeHosting(
            LabView(),
            title: L10n.t("实验室", "Lab"),
            image: "flask",
            accessibilityLabel: L10n.t("实验室功能", "Lab features"),
            tag: 4
        )
        systemController = makeHosting(
            SystemView(),
            title: L10n.t("系统", "Settings"),
            image: "gearshape",
            accessibilityLabel: L10n.t("系统设置与维护", "Settings and maintenance"),
            tag: 3
        )

        let s3xy = S3XYDevicesViewController(environment: environment)
        let s3xyItem = UITabBarItem(
            title: L10n.t("蓝牙", "Bluetooth"),
            image: UIImage(systemName: "dot.radiowaves.left.and.right"),
            tag: 2
        )
        s3xyItem.accessibilityLabel = L10n.t("S3XY 蓝牙设备管理", "S3XY Bluetooth devices")
        s3xy.tabBarItem = s3xyItem
        s3xyController = s3xy

        // 蓝牙页默认隐藏，由「系统 → 界面」控制
        environment.onBluetoothTabVisibilityChange = { [weak self] in
            self?.applyTabSet()
        }
        environment.onLabVisibilityChange = { [weak self] in
            self?.applyTabSet()
        }
        environment.onLanguageChange = { [weak self] in
            self?.refreshTitles()
            self?.applyTabSet()
        }
        applyTabSet()

        #if targetEnvironment(macCatalyst)
        // Mac 上改用系统侧边栏（与访达/邮件一致的导航形态），比顶部标签条更符合 macOS 习惯。
        if #available(macCatalyst 18.0, *) {
            mode = .tabSidebar
        }
        #endif

    }

    // MARK: - 标签集合

    /// 依据「蓝牙开关」与「LAB 是否启用」重建标签栏，并尽量保持当前选中页不变。
    private func applyTabSet() {
        var target: [UIViewController] = [overviewController, featuresController]
        if environment.isLabEnabled { target.append(labController) }
        if environment.isS3XYEnabled { target.append(s3xyController) }
        target.append(systemController)

        let current = selectedViewController
        let changed = viewControllers?.count != target.count
            || zip(viewControllers ?? [], target).contains { $0 !== $1 }
        if changed { viewControllers = target }

        #if DEBUG
        // 本地联调：离线截图时强制初始标签（不等 featuresStatus）。
        if !debugTabApplied,
           let raw = ProcessInfo.processInfo.environment["P4CAN_TAB_FORCE"],
           let index = Int(raw), target.indices.contains(index) {
            debugTabApplied = true
            selectedIndex = index
            return
        }
        // 本地联调：标签页要等 LAB 闸门读取后才齐，这里在首次达到目标数量时应用初始标签。
        if !debugTabApplied, environment.featuresStatus != nil {
            let requested = ProcessInfo.processInfo.environment["P4CAN_TAB"]
                ?? UserDefaults.standard.string(forKey: "p4can.debugTab")
            if let raw = requested, let index = Int(raw), target.indices.contains(index) {
                debugTabApplied = true
                selectedIndex = index
                return
            }
        }
        #endif

        if let current, target.contains(where: { $0 === current }) {
            selectedViewController = current
        } else {
            selectedIndex = 0
        }
    }

    /// 语言切换后刷新 UIKit 侧文案（标签标题与可访问性标签）。
    private func refreshTitles() {
        overviewController?.tabBarItem.title = L10n.t("状态", "Status")
        overviewController?.tabBarItem.accessibilityLabel = L10n.t("设备状态总览", "Device status")
        featuresController?.tabBarItem.title = L10n.t("功能", "Features")
        featuresController?.tabBarItem.accessibilityLabel = L10n.t("功能开关列表", "Feature list")
        labController?.tabBarItem.title = L10n.t("实验室", "Lab")
        labController?.tabBarItem.accessibilityLabel = L10n.t("实验室功能", "Lab features")
        s3xyController?.tabBarItem.title = L10n.t("蓝牙", "Bluetooth")
        s3xyController?.tabBarItem.accessibilityLabel = L10n.t("S3XY 蓝牙设备管理", "S3XY Bluetooth devices")
        systemController?.tabBarItem.title = L10n.t("系统", "Settings")
        systemController?.tabBarItem.accessibilityLabel = L10n.t("系统设置与维护", "Settings and maintenance")
    }

    private func makeHosting<Content: View>(
        _ rootView: Content,
        title: String,
        image: String,
        accessibilityLabel: String,
        tag: Int
    ) -> UIViewController {
        let controller = UIHostingController(rootView: rootView.environmentObject(environment))
        // 宿主默认背景是纯白；页面底色铺不满时（转场、安全区、键盘收起）会从顶部漏出白条。
        controller.view.backgroundColor = .systemGroupedBackground
        let item = UITabBarItem(
            title: title,
            image: UIImage(systemName: image),
            tag: tag
        )
        item.accessibilityLabel = accessibilityLabel
        controller.tabBarItem = item
        return controller
    }
}
