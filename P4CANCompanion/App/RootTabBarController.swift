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
    private var s3xyController: UIViewController!
    private var systemController: UIViewController!

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持 storyboard 初始化") }

    override func viewDidLoad() {
        super.viewDidLoad()

        overviewController = makeHosting(
            DashboardView(),
            title: "状态",
            // 注意：SF Symbols 里没有 gauge.with.dots.needle.bottom.50.percent，
            // 用错名字会得到空白占位图标（之前状态页图标消失的原因）。
            image: "gauge.with.dots.needle.50percent",
            accessibilityLabel: "设备状态总览",
            tag: 0
        )
        featuresController = makeHosting(
            FeaturesView(),
            title: "功能",
            image: "switch.programmable",
            accessibilityLabel: "功能开关列表",
            tag: 1
        )
        systemController = makeHosting(
            SystemView(),
            title: "系统",
            image: "gearshape",
            accessibilityLabel: "系统设置与维护",
            tag: 3
        )

        let s3xy = S3XYDevicesViewController(environment: environment)
        let s3xyItem = UITabBarItem(
            title: "蓝牙",
            image: UIImage(systemName: "dot.radiowaves.left.and.right"),
            tag: 2
        )
        s3xyItem.accessibilityLabel = "S3XY 蓝牙设备管理"
        s3xy.tabBarItem = s3xyItem
        s3xyController = s3xy

        // 蓝牙页默认隐藏，由「系统 → 界面」控制
        environment.onBluetoothTabVisibilityChange = { [weak self] in
            self?.applyTabSet()
        }
        applyTabSet()

        #if targetEnvironment(macCatalyst)
        // Mac 上改用系统侧边栏（与访达/邮件一致的导航形态），比顶部标签条更符合 macOS 习惯。
        if #available(macCatalyst 18.0, *) {
            mode = .tabSidebar
        }
        #endif

        // 本地联调：环境变量 P4CAN_TAB 或偏好 p4can.debugTab 指定初始标签页
        #if DEBUG
        let requestedTab = ProcessInfo.processInfo.environment["P4CAN_TAB"]
            ?? UserDefaults.standard.string(forKey: "p4can.debugTab")
        if let raw = requestedTab,
           let index = Int(raw),
           (0..<(viewControllers?.count ?? 0)).contains(index) {
            selectedIndex = index
        }
        #endif
    }

    // MARK: - 标签集合

    /// 依据「是否显示蓝牙」重建标签栏，并尽量保持当前选中页不变。
    private func applyTabSet() {
        let target: [UIViewController] = environment.bluetoothTabEnabled
            ? [overviewController, featuresController, s3xyController, systemController]
            : [overviewController, featuresController, systemController]

        guard viewControllers?.count != target.count else { return }

        let current = selectedViewController
        viewControllers = target

        if let current, target.contains(where: { $0 === current }) {
            selectedViewController = current
        } else {
            // 当前页被移除（正在看蓝牙时关掉开关）→ 回到状态页
            selectedIndex = 0
        }
    }

    private func makeHosting<Content: View>(
        _ rootView: Content,
        title: String,
        image: String,
        accessibilityLabel: String,
        tag: Int
    ) -> UIViewController {
        let controller = UIHostingController(rootView: rootView.environmentObject(environment))
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
