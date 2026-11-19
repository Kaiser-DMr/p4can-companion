#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit
#endif
import Foundation

#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)

/// 管理「灵动岛 / 锁屏」实时活动生命周期（iOS / iPadOS）。
///
/// 并发策略：ActivityKit 的 `Activity` 句柄不是 Sendable，
/// 因此控制器用 NSLock 保护句柄、所有 ActivityKit 调用都在创建它的 Task 内完成，
/// 句柄不跨隔离域传递（`@unchecked Sendable` 由锁保证）。
final class LiveActivityController: @unchecked Sendable {

    static let shared = LiveActivityController()

    private let lock = NSLock()
    private var current: Activity<CanActivityAttributes>?
    private var activeFlag = false

    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return activeFlag
    }

    var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// - Returns: 是否真的创建了活动（系统关闭实时活动、达到上限时会失败）。
    @discardableResult
    func start(deviceName: String, state: CanActivityAttributes.ContentState) async -> Bool {
        await startInternal(deviceName: deviceName, state: state)
    }

    func update(state: CanActivityAttributes.ContentState) {
        Task {
            let activity = self.takeCurrent()
            guard let activity else { return }
            await activity.update(
                ActivityContent(state: state, staleDate: Date().addingTimeInterval(5 * 60), relevanceScore: 100)
            )
        }
    }

    func end() {
        Task { await self.endInternal() }
    }

    // MARK: - 内部

    private func takeCurrent() -> Activity<CanActivityAttributes>? {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    private func store(_ activity: Activity<CanActivityAttributes>?) {
        lock.lock()
        defer { lock.unlock() }
        current = activity
        activeFlag = (activity != nil)
    }

    private func startInternal(
        deviceName: String,
        state: CanActivityAttributes.ContentState
    ) async -> Bool {
        await endInternal()
        guard isSupported else { return false }
        do {
            let activity = try Activity.request(
                attributes: CanActivityAttributes(deviceName: deviceName),
                // 数据每 0.25–1 s 刷新一次，8 小时才过期等于永不提示陈旧。
                content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(5 * 60), relevanceScore: 100),
                pushType: nil
            )
            store(activity)
            return true
        } catch {
            store(nil)
            return false
        }
    }

    private func endInternal() async {
        let activity = takeCurrent()
        store(nil)
        if let activity {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}

#else

/// Mac Catalyst 版：ActivityKit 不可用（Mac 没有灵动岛/锁屏实时活动），
/// 保留完全相同的 API 以便上层代码无需分支，`isSupported` 恒为 false，
/// 设置页会自动隐藏「锁屏与灵动岛」开关。
final class LiveActivityController: @unchecked Sendable {

    static let shared = LiveActivityController()

    var isActive: Bool { false }
    var isSupported: Bool { false }

    func start(deviceName: String, state: CanActivityAttributes.ContentState) {}
    func update(state: CanActivityAttributes.ContentState) {}
    func end() {}
}

#endif
