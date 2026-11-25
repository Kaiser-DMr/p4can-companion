import AppIntents
import Foundation

// MARK: - 语言

/// App Intents 可能在 App 未启动时运行，不能依赖 `L10n.selection` 的内存缓存，
/// 因此这里直接读持久化的语言设置，再回落到系统语言。
private enum P4IntentLanguage {
    static var isEnglish: Bool {
        let raw = UserDefaults.standard.string(forKey: "p4can.language") ?? "system"
        switch raw {
        case "en": return true
        case "zh": return false
        default:
            let preferred = Locale.preferredLanguages.first?.lowercased() ?? "zh"
            return !preferred.hasPrefix("zh")
        }
    }
}

private enum P4IntentText {
    static func t(_ zh: String, _ en: String) -> String {
        P4IntentLanguage.isEnglish ? en : zh
    }
}

// MARK: - 失败反馈

/// 快捷指令运行失败时用系统对话框说明原因（而不是只留一个红色感叹号）。
struct P4IntentFailure: LocalizedError, CustomLocalizedStringResourceConvertible {
    let message: String

    var errorDescription: String? { message }

    var localizedStringResource: LocalizedStringResource {
        LocalizedStringResource(stringLiteral: message)
    }
}

// MARK: - 调用

/// 快捷指令的运行环境没有 AppEnvironment，这里按保存的设备地址新建一个轻量客户端，
/// 复用与 App 内完全相同的接口与错误语义。
enum P4ShortcutRunner {
    static func trigger(_ path: String) async throws {
        let host = UserDefaults.standard.string(forKey: "p4can.device.host") ?? "192.168.4.1"
        let client = P4APIClient(host: host)
        do {
            _ = try await client.post(path)
        } catch {
            throw P4IntentFailure(message: message(for: error))
        }
    }

    /// 把网络错误与固件错误码翻成「能照做」的一句话。
    private static func message(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return P4IntentText.t(
                    "设备响应超时：确认这台 iPhone 仍连在设备的热点上",
                    "Timed out. Make sure this iPhone is still on the device hotspot."
                )
            case .cannotFindHost, .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet:
                return P4IntentText.t(
                    "连不上设备：请先加入设备的 Wi-Fi 再运行",
                    "Cannot reach the device. Join the device Wi-Fi first."
                )
            default:
                break
            }
        }

        let raw = (error as? P4APIError)?.message ?? error.localizedDescription
        if raw.contains("NO_FRAME") {
            return P4IntentText.t("还没收到整车 0x273：先给车辆上电（踩刹车）再试",
                                  "No 0x273 frame yet. Power on the car and try again.")
        }
        if raw.contains("ALREADY_ACTIVE") {
            return P4IntentText.t("正在爆闪中，请稍后再试", "Already flashing. Try again in a moment.")
        }
        if raw.contains("TURN_SIGNAL_ACTIVE") {
            return P4IntentText.t("转向灯正在工作，等它结束后再试",
                                  "Turn signal is active. Try again once it finishes.")
        }
        if raw.contains("NO_STOCK_TEMPLATE") {
            return P4IntentText.t("还没收到 0x249 模板：先拨一下拨杆再试",
                                  "No 0x249 template yet. Move the stalk once and try again.")
        }
        if raw.contains("SOURCE_MISMATCH") {
            return P4IntentText.t("App 触发已关闭：设置里的触发入口当前是 S3XY 按键",
                                  "App trigger is off. The trigger source is set to the S3XY button.")
        }
        if raw.contains("STALKLESS_UNSUPPORTED") {
            return P4IntentText.t("当前车型不支持 0x249 拨杆注入", "This vehicle does not support stalk injection.")
        }
        return P4IntentText.t("触发失败：\(raw)", "Failed: \(raw)")
    }
}

// MARK: - 前大灯爆闪

/// 动作：执行「立即爆闪」。参数（次数 / 间隔）沿用 App 内已保存的设置。
struct HeadlightStrobeIntent: AppIntent {
    // 说明：App Intents 的元数据在编译期提取，title / description / shortTitle
    // 必须用字面量，不能用运行时语言函数。中文为主语言；英文用户仍可用英文短语触发。
    static var title: LocalizedStringResource { "前大灯爆闪" }

    static var description: IntentDescription {
        IntentDescription("按已保存的次数与间隔立即触发前大灯爆闪，结束后自动恢复原灯光状态。")
    }

    /// 后台执行，不把 App 拉到前台。
    static var openAppWhenRun: Bool { false }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await P4ShortcutRunner.trigger(P4Route.headlightStrobeTrigger)
        return .result(dialog: IntentDialog(stringLiteral: P4IntentText.t(
            "前大灯已开始爆闪",
            "Headlight strobe started"
        )))
    }
}

// MARK: - 后雾灯爆闪

/// 动作：执行「开始爆闪」。单次最长 30 秒，到时自动停止并恢复。
struct RearFogStrobeIntent: AppIntent {
    static var title: LocalizedStringResource { "后雾灯爆闪" }

    static var description: IntentDescription {
        IntentDescription("开始后雾灯爆闪，最长 30 秒后自动停止，整车下一帧即恢复原状态。")
    }

    static var openAppWhenRun: Bool { false }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await P4ShortcutRunner.trigger(P4Route.rearFogStrobeStart)
        return .result(dialog: IntentDialog(stringLiteral: P4IntentText.t(
            "后雾灯已开始爆闪",
            "Rear fog strobe started"
        )))
    }
}

// MARK: - 系统「快捷指令」收录

/// 注册到系统快捷指令：装好 App 后无需手动配置即可在「快捷指令」与 Spotlight 中搜到。
struct P4AppShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor { .blue }

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: HeadlightStrobeIntent(),
            phrases: [
                "用\(.applicationName)闪前大灯",
                "用\(.applicationName)触发前大灯爆闪",
                "Flash the headlights with \(.applicationName)",
            ],
            shortTitle: "前大灯爆闪",
            systemImageName: "light.beacon.max.fill"
        )

        AppShortcut(
            intent: RearFogStrobeIntent(),
            phrases: [
                "用\(.applicationName)开后雾灯爆闪",
                "用\(.applicationName)开始后雾灯爆闪",
                "Start the rear fog strobe with \(.applicationName)",
            ],
            shortTitle: "后雾灯爆闪",
            systemImageName: "cloud.fog.fill"
        )
    }
}
