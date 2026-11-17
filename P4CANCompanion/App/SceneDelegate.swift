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
        window.makeKeyAndVisible()
        self.window = window

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
}
