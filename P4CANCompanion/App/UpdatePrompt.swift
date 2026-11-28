import UIKit

/// 回到前台时静默检查主仓库是否有新版本，有则弹窗：前往更新 / 下次再说 / 不再提示。
/// 成功检查后 6 小时内不重复请求；网络失败不提示，下次回到前台再试。
@MainActor
enum UpdatePrompt {
    private static let lastCheckKey = "update.lastCheck"
    /// 选择「不再提示」的版本标签：只有出现更高的版本才会再次提示
    private static let skippedTagKey = "update.skippedTag"
    private static let interval: TimeInterval = 6 * 3600
    private static var checking = false

    static func checkIfDue(from window: UIWindow?) {
        let defaults = UserDefaults.standard
        let bundleVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        #if DEBUG
        // 本地联调：SIMCTL_CHILD_P4CAN_UPDATE_FORCE=1 忽略 6 小时间隔；P4CAN_APP_VERSION 模拟旧版本号
        let environment = ProcessInfo.processInfo.environment
        let force = environment["P4CAN_UPDATE_FORCE"] == "1"
        let current = environment["P4CAN_APP_VERSION"] ?? bundleVersion
        #else
        let force = false
        let current = bundleVersion
        #endif
        guard !checking else { return }
        if !force, let last = defaults.object(forKey: lastCheckKey) as? Date, Date().timeIntervalSince(last) < interval { return }
        guard let currentVersion = AppUpdate.version(current) else { return }
        checking = true
        Task {
            defer { checking = false }
            guard let release = try? await AppUpdate.fetchLatest() else { return }
            defaults.set(Date(), forKey: lastCheckKey)
            guard AppUpdate.isNewer(release.version, than: currentVersion),
                  defaults.string(forKey: skippedTagKey) != release.tag else { return }
            present(release, current: current, from: window)
        }
    }

    private static func present(_ release: AppRelease, current: String, from window: UIWindow?) {
        guard var top = window?.rootViewController else { return }
        while let presented = top.presentedViewController { top = presented }
        // 正在显示其他弹窗时不打断，下次检查再提示
        guard !(top is UIAlertController) else { return }
        let alert = UIAlertController(
            title: L10n.t("发现新版本 \(release.tag)", "Update available: \(release.tag)"),
            message: L10n.t("\(release.name)\n当前版本 \(current)", "\(release.name)\nCurrent version \(current)"),
            preferredStyle: .alert
        )
        let open = UIAlertAction(title: L10n.t("前往更新", "Update"), style: .default) { _ in
            UIApplication.shared.open(release.url)
        }
        alert.addAction(open)
        alert.addAction(UIAlertAction(title: L10n.t("下次再说", "Later"), style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.t("不再提示", "Don't Remind Me"), style: .default) { _ in
            UserDefaults.standard.set(release.tag, forKey: skippedTagKey)
        })
        alert.preferredAction = open
        top.present(alert, animated: true)
    }
}
