import Foundation
import UIKit

/// 应用内语言。`system` 跟随系统语言（中文环境用中文，其余用英文）。
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case zh
    case en

    var id: String { rawValue }

    /// 语言选择器里的名称（用各自语言书写，切换时不会看不懂）。
    @MainActor var displayName: String {
        switch self {
        case .system: return L10n.t("跟随系统", "System")
        case .zh: return "简体中文"
        case .en: return "English"
        }
    }
}

/// 界面外观（对齐固件网页 Settings → Appearance：跟随手机 / 浅色 / 深色）。
enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    @MainActor var displayName: String {
        switch self {
        case .system: return L10n.t("跟随手机", "Follow phone")
        case .light: return L10n.t("浅色", "Light")
        case .dark: return L10n.t("深色", "Dark")
        }
    }

    /// 网页原始的三段文案（全大写短标签）。
    @MainActor var shortName: String {
        switch self {
        case .system: return L10n.t("跟随", "AUTO")
        case .light: return L10n.t("浅色", "LIGHT")
        case .dark: return L10n.t("深色", "DARK")
        }
    }

    var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// 运行时文案切换。
///
/// - 中文为默认；英文优先采用固件网页（dashboard_source.html）里的原始英文措辞
///   （Nag Killer / Auto Blinker / TLSSC / Lane Change …），避免二次翻译走样。
/// - 所有调用都发生在主线程的 View body 中，因此用 `@MainActor` 的静态状态即可。
@MainActor
enum L10n {
    /// 用户选择（持久化在 AppEnvironment 里，这里只做缓存）
    static var selection: AppLanguage = .system

    /// 实际生效的语言
    static var resolved: AppLanguage {
        if selection != .system { return selection }
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "zh"
        return preferred.hasPrefix("zh") ? .zh : .en
    }

    static var isEnglish: Bool { resolved == .en }

    /// 中英二选一。英文串请尽量使用固件网页的原文。
    static func t(_ zh: String, _ en: String) -> String {
        isEnglish ? en : zh
    }
}
