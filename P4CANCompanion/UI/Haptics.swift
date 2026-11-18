import UIKit

/// 触觉反馈（危险操作与命令结果），遵循 HIG 的克制使用原则。
@MainActor
enum Haptics {

    // 复用同一个 generator 并提前 prepare：新建 generator 会让首次触发晚 20–100 ms，
    // 与视觉不同帧，触感就「不像是我按下造成的」。
    private static let notification = UINotificationFeedbackGenerator()
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)

    static func success() {
        notification.prepare()
        notification.notificationOccurred(.success)
    }

    static func warning() {
        notification.prepare()
        notification.notificationOccurred(.warning)
    }

    static func error() {
        notification.prepare()
        notification.notificationOccurred(.error)
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        let generator = style == .light ? light : medium
        generator.prepare()
        generator.impactOccurred()
    }
}
