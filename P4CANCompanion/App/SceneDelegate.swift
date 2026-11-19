import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    /// 全局共享的应用状态（连接状态、轮询、命令执行）。
    private let environment = AppEnvironment()

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = RootTabBarController(environment: environment)
        window.overrideUserInterfaceStyle = environment.appearance.userInterfaceStyle
        window.makeKeyAndVisible()
        self.window = window

        // 设置 → 外观：SwiftUI 与 UIKit 页面都跟随窗口样式，避免只改一半。
        environment.onAppearanceChange = { [weak self] in
            self?.window?.overrideUserInterfaceStyle = self?.environment.appearance.userInterfaceStyle ?? .unspecified
        }

        #if targetEnvironment(macCatalyst)
        // Mac 窗口尺寸约束：单列信息流最舒服的宽度区间，避免被拉成超宽横条。
        if let restrictions = windowScene.sizeRestrictions {
            restrictions.minimumSize = CGSize(width: 460, height: 640)
            restrictions.maximumSize = CGSize(width: 1180, height: 1600)
        }
        windowScene.title = "P4管家"
        #endif

        environment.start()
    }

    /// 回前台：立即刷新一次并恢复轮询。
    ///
    /// 以前 `start()` 只在 `willConnectTo` 调一次，`stop()` 全仓没有调用点，
    /// 于是退到后台仍在按 500 ms 打设备（直到系统挂起），回前台也不会立即更新。
    func sceneDidBecomeActive(_ scene: UIScene) {
        environment.start()
    }

    /// 退到后台/被系统遮挡（控制中心、来电横幅）：停掉轮询，省电也避免和设备抢连接。
    func sceneWillResignActive(_ scene: UIScene) {
        environment.stop()
    }
}
