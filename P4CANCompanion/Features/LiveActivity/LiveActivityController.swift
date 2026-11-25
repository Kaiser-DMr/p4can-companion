#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit
#endif
import Foundation

#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)

/// 管理「灵动岛 / 锁屏」实时活动生命周期（iOS / iPadOS）。
///
/// 实时活动的生命周期长于 App 进程：App 被系统回收、手动划掉或覆盖安装后，
/// 上一个进程创建的活动仍留在锁屏。因此启动时先接管 `Activity.activities` 里已有的活动，
/// 多余的全部结束，保证同一时间只有一个；关闭时同样结束全部，而不只是本进程创建的那个。
///
/// 并发策略：ActivityKit 的 `Activity` 句柄不是 Sendable，控制器用 NSLock 保护句柄与启动标记，
/// 句柄不跨隔离域传递（`@unchecked Sendable` 由锁保证）。
final class LiveActivityController: @unchecked Sendable {

    static let shared = LiveActivityController()

    private let lock = NSLock()
    private var current: Activity<CanActivityAttributes>?
    /// 正在启动：并发的两次启动会各自请求一个活动，后到的直接返回。
    private var starting = false
    /// 每次 `end()` 加一：启动过程中被关闭时，启动完成后要把刚建好的活动结束掉。
    private var endGeneration = 0

    /// 以系统状态为准：用户在锁屏划掉或系统结束后，句柄还在但已不再显示。
    var isActive: Bool {
        takeCurrent()?.activityState == .active
    }

    var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// - Returns: 是否有活动在显示（接管已有的或新建成功；系统关闭实时活动、达到上限时为 false）。
    @discardableResult
    func start(deviceName: String, state: CanActivityAttributes.ContentState) async -> Bool {
        guard let generation = beginStarting() else { return isActive }
        defer { finishStarting() }
        let shown = await startInternal(deviceName: deviceName, state: state)
        guard generation == currentGeneration() else {
            await endAll()
            return false
        }
        return shown
    }

    func update(state: CanActivityAttributes.ContentState) {
        Task {
            guard let activity = self.takeCurrent(), activity.activityState == .active else { return }
            await activity.update(Self.content(state))
        }
    }

    func end() {
        lock.lock()
        endGeneration += 1
        lock.unlock()
        Task { await self.endAll() }
    }

    // MARK: - 内部

    private static func content(_ state: CanActivityAttributes.ContentState) -> ActivityContent<CanActivityAttributes.ContentState> {
        // 5 分钟没有新数据就提示陈旧（数据每 0.25–1 s 刷新一次）。
        ActivityContent(state: state, staleDate: Date().addingTimeInterval(5 * 60), relevanceScore: 100)
    }

    /// - Returns: 开始启动时的关闭代数；已有启动在进行时为 nil。
    private func beginStarting() -> Int? {
        lock.lock()
        defer { lock.unlock() }
        guard !starting else { return nil }
        starting = true
        return endGeneration
    }

    private func currentGeneration() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return endGeneration
    }

    private func finishStarting() {
        lock.lock()
        defer { lock.unlock() }
        starting = false
    }

    private func takeCurrent() -> Activity<CanActivityAttributes>? {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    private func store(_ activity: Activity<CanActivityAttributes>?) {
        lock.lock()
        defer { lock.unlock() }
        current = activity
    }

    private func startInternal(
        deviceName: String,
        state: CanActivityAttributes.ContentState
    ) async -> Bool {
        guard isSupported else {
            await endAll()
            return false
        }
        let existing = Activity<CanActivityAttributes>.activities
        // 优先沿用本进程的句柄，其次接管上一个进程留下的同一设备活动。
        let reusable = ([takeCurrent()].compactMap { $0 } + existing).first { activity in
            activity.activityState == .active && activity.attributes.deviceName == deviceName
        }
        #if DEBUG
        FileHandle.standardError.write(Data(
            "[LiveActivity] start: existing=\(existing.count) reuse=\(reusable != nil)\n".utf8
        ))
        #endif
        for activity in existing where activity.id != reusable?.id {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        if let reusable {
            store(reusable)
            await reusable.update(Self.content(state))
            return true
        }
        do {
            let activity = try Activity.request(
                attributes: CanActivityAttributes(deviceName: deviceName),
                content: Self.content(state),
                pushType: nil
            )
            store(activity)
            return true
        } catch {
            store(nil)
            return false
        }
    }

    /// 结束本 App 的全部实时活动（包括之前进程遗留的）。
    private func endAll() async {
        store(nil)
        for activity in Activity<CanActivityAttributes>.activities {
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

    @discardableResult
    func start(deviceName: String, state: CanActivityAttributes.ContentState) async -> Bool { false }
    func update(state: CanActivityAttributes.ContentState) {}
    func end() {}
}

#endif
