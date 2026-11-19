import Foundation
import Combine

/// 全局应用状态：设备连接、分组快照轮询、命令执行与结果提示。
///
/// 数据策略（与固件网页完全同源）：
/// - 主数据源 `GET /api/snapshot?groups=home-fast[&slow=1]`，返回 `{fast:{nag,blink,summon,cantraffic,r79}, slow:{...}}`；
/// - 车型能力 `GET /api/profile/status`、功能闸门 `GET /api/features/status` 每 4 拍刷新；
/// - S3XY / OTA / Wi-Fi / 系统统计同频慢刷；
/// - 全部写操作用 query 参数 POST（与网页 `post(url?k=v)` 一致）；
/// - 客户端禁用 HTTP 缓存并发送 no-cache。
@MainActor
final class AppEnvironment: ObservableObject {

    enum Phase: Equatable {
        case idle
        case connecting
        case online
        case offline(reason: String)
    }

    // MARK: - 连接状态

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var host: String
    @Published private(set) var isBusy = false
    @Published private(set) var otaUploading = false
    /// OTA 上传阶段：上传 → 等待设备重启确认 → 完成 / 失败。
    enum OTAUploadPhase: Equatable {
        case idle
        case uploading
        case verifying
        case done
        case failed
    }
    @Published private(set) var otaUploadPhase: OTAUploadPhase = .idle
    /// 已发送 / 总字节（UI 进度条）。
    @Published private(set) var otaUploadSent = 0
    @Published private(set) var otaUploadTotal = 0
    @Published var toast: P4Toast?

    // MARK: - 离线缓存

    /// 当前展示的是否为磁盘缓存（连不上设备时读上一次成功的数据）。
    @Published private(set) var isShowingCachedData = false
    /// 缓存写入时间（用于界面上的「数据时间」）。
    @Published private(set) var cachedAt: Date?

    /// 是否有任何可渲染的数据（实时或缓存），用于决定首页显示真实内容还是「等待设备」。
    var hasRenderableData: Bool {
        !fastGroups.isEmpty || !slowGroups.isEmpty
            || profileStatus != nil || !mergedStats.isEmpty
    }


    // MARK: - 快照分组（网页同源）

    /// `snapshot?groups=home-fast` 的 `fast` 对象
    @Published private(set) var fastGroups: [String: P4JSON] = [:]
    /// 附带 `&slow=1` 时的 `slow` 对象
    @Published private(set) var slowGroups: [String: P4JSON] = [:]

    // MARK: - 慢变端点

    @Published private(set) var profileStatus: P4JSON?
    @Published private(set) var featuresStatus: P4JSON?
    @Published private(set) var wifiStatus: P4JSON?
    @Published private(set) var otaStatus: P4JSON?
    @Published private(set) var systemStats: P4JSON?
    @Published private(set) var s3xyStats: P4JSON?
    @Published private(set) var dasStats: P4JSON?
    /// 完整 NAG 配置（含 enabled / method / mode），用于首页快捷开关。
    @Published private(set) var nagConfig: P4JSON?
    /// 固件是否提供前后爆闪接口（v3.35.2 官方固件已移除这两个端点）。
    /// nil = 尚未探测或离线不确定；false 时功能列表隐藏两个灯光入口。
    @Published private(set) var strobeSupported: Bool?
    /// 固件是否带 v3.35.2 新功能（预热 / FSD / Service Mode / SmartShift / R79 时序）。
    /// nil = 尚未探测；只有确认存在时才展示这些入口，避免在 v3.29.3 上留下死模块。
    @Published private(set) var newFeaturesSupported: Bool?
    /// 上次探测爆闪接口的时间：为 false 时每分钟复探一次，方便重新刷回带爆闪的固件后自动恢复入口。
    private var lastStrobeProbe: Date?
    private var lastNewFeaturesProbe: Date?

    /// 三路 CAN 总线（CAN 1 BODY / CAN 2 CHASSIS / CAN 3 PARTY）。
    @Published private(set) var canBuses: [CanBusSnapshot] = []
    /// 全部字段扁平合并（供通用键值展示与搜索）。
    @Published private(set) var mergedStats: [String: P4JSON] = [:]
    /// 扭矩趋势采样（Swift Charts 使用，约保留 120 个点 ≈ 3 分钟）。
    @Published private(set) var trendSamples: [TrendSample] = []
    /// 是否开启锁屏 / 灵动岛实时活动（持久化）。
    @Published private(set) var liveActivityEnabled = false
    /// 蓝牙标签是否显示：与网页一致，由固件 S3XY 功能闸门决定（功能页的 S3XY 开关）。
    /// 「蓝牙」标签是否显示：与 BLE 总开关解耦。
    /// 开关关闭只影响连接，不应把唯一的重开入口一起删掉。
    @Published private(set) var showsS3XYTab = UserDefaults.standard.bool(forKey: "p4can.tab.s3xy")

    var isS3XYEnabled: Bool {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["P4CAN_BT_TAB"] {
            return raw == "1"
        }
        #endif
        return featuresStatus?["s3xy"]?.boolValue ?? false
    }
    /// 根控制器注入：标签显隐变化时重建标签栏（避免 Combine 跨隔离域捕获）。
    var onBluetoothTabVisibilityChange: (@MainActor () -> Void)?
    /// 实验室（LAB）开关变化时重建标签栏：LAB 开启才显示「实验室」页。
    var onLabVisibilityChange: (@MainActor () -> Void)?
    /// 语言变化时刷新标签栏标题等 VC 级文案。
    var onLanguageChange: (@MainActor () -> Void)?
    /// 语言（持久化；system = 跟随系统）
    @Published private(set) var language: AppLanguage = .system
    /// 界面外观（持久化；与网页 Settings → Appearance 一致）
    @Published private(set) var appearance: AppAppearance = .system
    /// 主页刷新间隔（毫秒，250 / 500 / 1000；与网页 Settings → Data Refresh Interval 一致）
    @Published private(set) var pollIntervalMs: Int = 500
    /// 根窗口注入：外观变化时同步 overrideUserInterfaceStyle（含 UIKit 侧页面）。
    var onAppearanceChange: (@MainActor () -> Void)?
    private var lastLabVisible = false
    private var lastS3XYVisible = false
    private static let languageDefaultsKey = "p4can.language"
    private static let appearanceDefaultsKey = "p4can.appearance"
    private static let pollIntervalDefaultsKey = "p4can.poll.ms"
    static let pollIntervalOptions = [250, 500, 1000]

    struct TrendSample: Identifiable, Sendable {
        let id = UUID()
        let date: Date
        let torqueNm: Double
    }

    // MARK: - 数据浏览

    @Published private(set) var endpointPayloads: [String: P4JSON] = [:]
    @Published private(set) var endpointErrors: [String: String] = [:]
    @Published private(set) var endpointsUpdatedAt: Date?
    @Published private(set) var isScanningEndpoints = false

    // MARK: - 端点级共享快照

    /// 页面共用的端点数据：同一路径只保留最新一次成功回包与时间戳。
    ///
    /// 以前详情页、灯光两页、功能列表各自持有 `stats` 并各自轮询同一端点，
    /// 同一份数据有多个真相源：A 页写入成功后 B 页要等下一拍，离线时各页新旧不一。
    /// 现在统一走这里，页面只读，不再自己存。
    @Published private(set) var endpointValues: [String: P4JSON] = [:]
    @Published private(set) var endpointFetchedAt: [String: Date] = [:]
    /// 同一路径正在请求中：并发调用复用这次请求，避免多页同时挂载时重复打设备。
    private var endpointInFlight: Set<String> = []

    /// 端点最新一次成功回包（nil = 从未成功）。
    func endpointValue(_ path: String) -> P4JSON? { endpointValues[path] }

    /// 端点最近一次成功时间（用于新鲜度提示）。
    func endpointUpdatedAt(_ path: String) -> Date? { endpointFetchedAt[path] }

    /// 端点数据年龄（秒）；nil 表示从未成功。
    func endpointAge(_ path: String) -> TimeInterval? {
        guard let at = endpointFetchedAt[path] else { return nil }
        return Date().timeIntervalSince(at)
    }

    /// 端点最近一次失败原因（成功后清除）。
    func endpointError(_ path: String) -> String? { endpointErrors[path] }

    /// 写入共享缓存（写接口的回包本身就是最新状态，直接落进来，
    /// 其它页面下一拍就能看到，不必等各自轮询）。
    func storeEndpoint(_ path: String, _ value: P4JSON) {
        endpointValues[path] = value
        endpointFetchedAt[path] = Date()
        endpointErrors[path] = nil
    }

    /// 读取一个端点；`maxAge` 内的缓存直接复用。
    ///
    /// - `maxAge > 0`：节流（如功能列表 4 s 慢轮询，灯光页 800 ms 高频轮询共用一份数据）；
    /// - 同一路径已有请求在飞：不重复发，直接返回当前缓存，等下一拍再取。
    @discardableResult
    func refreshEndpoint(_ path: String, maxAge: TimeInterval = 0) async -> P4JSON? {
        if maxAge > 0, let at = endpointFetchedAt[path],
           Date().timeIntervalSince(at) <= maxAge {
            return endpointValues[path]
        }
        guard !endpointInFlight.contains(path) else { return endpointValues[path] }
        endpointInFlight.insert(path)
        defer { endpointInFlight.remove(path) }
        do {
            let value = try await api.get(path)
            storeEndpoint(path, value)
            return value
        } catch {
            endpointErrors[path] = AppEnvironment.friendly(error)
            return nil
        }
    }

    /// 是否处于独占操作（OTA / 批量扫描）——页面级轮询应据此暂停。
    var isPollingPaused: Bool { exclusiveOperationDepth > 0 }

    static let browseEndpoints: [String] = [
        "/api/snapshot?groups=home-fast&slow=1",
        "/api/snapshot?groups=lab",
        "/api/snapshot?groups=settings",
        P4Route.systemStats,
        P4Route.profileStatus,
        P4Route.featuresStatus,
        P4Route.dasStats,
        P4Route.nagConfig,
        P4Route.nagStats,
        P4Route.nagHProfileStats,
        P4Route.ulcStats,
        P4Route.alcStats,
        P4Route.summonStats,
        P4Route.summonHeartbeatStats,
        P4Route.dmsStats,
        P4Route.dmsConfig,
        P4Route.s3xyStats,
        P4Route.blinkAStats,
        P4Route.visionControlStats,
        P4Route.countryStats,
        P4Route.isaSuppressionConfig,
        P4Route.r79Stats,
        P4Route.r79APControlStats,
        P4Route.pedalMapStats,
        P4Route.continuousAPConfig,
        P4Route.researchCaptureStats,
        P4Route.driverWindowStats,
        P4Route.wifiStatus,
        P4Route.otaStatus,
        // 灯光爆闪：这两条原先没进浏览清单，现场排查时搜不到 beam/held 等字段
        P4Route.headlightStrobeStats,
        P4Route.rearFogStrobeStats,
    ]

    /// 离线时放慢重试；在线间隔由用户设置（默认 500 ms，与网页一致）。
    private var onlineInterval: Duration { .milliseconds(pollIntervalMs) }
    private var offlineInterval: Duration = .seconds(5)

    private static let hostDefaultsKey = "p4can.device.host"
    private static let liveActivityDefaultsKey = "p4can.liveactivity.enabled"
    private var pollTask: Task<Void, Never>?
    private var client: P4APIClient
    private var tick = 0
    private var isRefreshing = false
    private var lastLiveActivityAttempt: Date?
    /// 连续离线起点：超过 1 分钟就结束实时活动，避免锁屏长期显示旧状态。
    private var liveActivityOfflineSince: Date?
    /// 上次写缓存的时间（节流用）。
    private var lastCacheWriteAt: Date?
    /// 上次写入包含的端点数量（新端点出现时立刻补写）。
    private var lastCachedEntryCount = 0
    /// >0 时暂停后台轮询（OTA 上传/等待重启期间），避免和单线程的固件 WebServer 抢连接。
    private var exclusiveOperationDepth = 0

    /// 当前可缓存的端点数量。
    private var cacheEntryCount: Int {
        var count = 0
        if !fastGroups.isEmpty { count += 1 }
        if !slowGroups.isEmpty { count += 1 }
        if profileStatus != nil { count += 1 }
        if featuresStatus != nil { count += 1 }
        if systemStats != nil { count += 1 }
        if dasStats != nil { count += 1 }
        if s3xyStats != nil { count += 1 }
        if wifiStatus != nil { count += 1 }
        if otaStatus != nil { count += 1 }
        if nagConfig != nil { count += 1 }
        return count
    }
    private let liveActivity = LiveActivityController.shared

    // MARK: - 生命周期

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.hostDefaultsKey)
        // 本地联调：可用 SIMCTL_CHILD_P4CAN_HOST=127.0.0.1:8080 覆盖设备地址
        let override = ProcessInfo.processInfo.environment["P4CAN_HOST"]
        let resolved: String
        if let override, !override.isEmpty {
            resolved = override
        } else {
            resolved = (saved?.isEmpty == false) ? saved! : "192.168.4.1"
        }
        self.host = resolved
        self.client = P4APIClient(host: resolved)
        self.liveActivityEnabled = UserDefaults.standard.bool(forKey: Self.liveActivityDefaultsKey)
        let savedLanguage = UserDefaults.standard.string(forKey: Self.languageDefaultsKey) ?? "system"
        self.language = AppLanguage(rawValue: savedLanguage) ?? .system
        #if DEBUG
        // 本地联调：SIMCTL_CHILD_P4CAN_LANGUAGE=en 强制语言（不写回偏好）
        if let raw = ProcessInfo.processInfo.environment["P4CAN_LANGUAGE"],
           let forced = AppLanguage(rawValue: raw) {
            self.language = forced
        }
        #endif
        L10n.selection = self.language
        let savedAppearance = UserDefaults.standard.string(forKey: Self.appearanceDefaultsKey) ?? "system"
        self.appearance = AppAppearance(rawValue: savedAppearance) ?? .system
        #if DEBUG
        // 本地联调：SIMCTL_CHILD_P4CAN_APPEARANCE=dark 强制外观（不写回偏好）。
        // 必须放在读取偏好之后，否则会被上面的赋值覆盖。
        if let raw = ProcessInfo.processInfo.environment["P4CAN_APPEARANCE"],
           let forced = AppAppearance(rawValue: raw) {
            self.appearance = forced
        }
        #endif
        let savedPoll = UserDefaults.standard.integer(forKey: Self.pollIntervalDefaultsKey)
        self.pollIntervalMs = Self.pollIntervalOptions.contains(savedPoll) ? savedPoll : 500
    }

    var api: P4APIClient { client }

    func start() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.refreshOnce()
                let interval = (self.phase == .online) ? self.onlineInterval : self.offlineInterval
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    @discardableResult
    func updateHost(_ newHost: String) -> Bool {
        let trimmed = newHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != host else { return false }
        guard let normalized = P4APIClient.validatedHost(trimmed) else {
            toast = P4Toast(
                message: "地址格式无效：只支持 http(s)://主机[:端口] 或 主机[:端口]，不要带账号、路径或查询参数",
                style: .failure
            )
            return false
        }
        host = normalized
        UserDefaults.standard.set(normalized, forKey: Self.hostDefaultsKey)
        client = P4APIClient(host: normalized)
        // 换设备必须清状态：否则会继续以新地址的名义显示上一台车的车型/挡位/扭矩，
        // 且 hasRenderableData 为真会让新设备的缓存永不加载。
        resetDeviceState()
        phase = .idle
        start()
        restoreCacheIfNeeded()
        toast = P4Toast(
            message: L10n.t("已切换到 \(normalized)", "Now using \(normalized)"),
            style: .info
        )
        return true
    }

    /// 清空与「某台设备」绑定的全部展示状态（切换设备地址时调用）。
    private func resetDeviceState() {
        fastGroups = [:]
        slowGroups = [:]
        profileStatus = nil
        featuresStatus = nil
        wifiStatus = nil
        otaStatus = nil
        systemStats = nil
        s3xyStats = nil
        dasStats = nil
        nagConfig = nil
        strobeSupported = nil
        newFeaturesSupported = nil
        mergedStats = [:]
        canBuses = []
        trendSamples = []
        endpointPayloads = [:]
        endpointErrors = [:]
        endpointValues = [:]
        endpointFetchedAt = [:]
        endpointInFlight = []
        endpointsUpdatedAt = nil
        isShowingCachedData = false
        cachedAt = nil
        lastUpdated = nil
        lastLabVisible = false
        lastS3XYVisible = false
    }

    // MARK: - 刷新

    func refreshOnce() async {
        guard exclusiveOperationDepth == 0 else { return }
        // 下拉刷新与轮询可能同时触发：旧响应会覆盖新响应，必须串行化。
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        // 只有首次连接才显示「连接中」；离线重试不再每 5 s 闪一次。
        if phase == .idle { phase = .connecting }
        let currentClient = client
        tick += 1
        let includeSlow = tick % 2 == 0
        let includeMeta = tick % 4 == 0

        var snapshotQuery: [P4Param] = [P4Param("groups", "home-fast")]
        if includeSlow { snapshotQuery.append(P4Param("slow", "1")) }

        async let snapshotTask: P4JSON? = try? await currentClient.get(
            P4Route.snapshot, query: snapshotQuery
        )
        async let profileTask: P4JSON? = includeMeta
            ? try? await currentClient.get(
                P4Route.profileStatus,
                query: [P4Param("probe", "\(Int(Date().timeIntervalSince1970 * 1000))")]
            )
            : nil
        async let featuresTask: P4JSON? = includeMeta
            ? try? await currentClient.get(P4Route.featuresStatus) : nil
        async let s3xyTask: P4JSON? = includeMeta
            ? try? await currentClient.get(P4Route.s3xyStats) : nil
        async let otaTask: P4JSON? = includeMeta
            ? try? await currentClient.get(P4Route.otaStatus) : nil
        async let wifiTask: P4JSON? = includeMeta
            ? try? await currentClient.get(P4Route.wifiStatus) : nil
        async let systemTask: P4JSON? = includeMeta
            ? try? await currentClient.get(P4Route.systemStats) : nil
        async let dasTask: P4JSON? = includeMeta
            ? try? await currentClient.get(P4Route.dasStats) : nil
        async let nagConfigTask: P4JSON? = includeMeta
            ? try? await currentClient.get(P4Route.nagConfig) : nil

        let snapshot = await snapshotTask
        let profile = await profileTask
        let features = await featuresTask
        let s3xy = await s3xyTask
        let ota = await otaTask
        let wifi = await wifiTask
        let system = await systemTask
        let das = await dasTask
        let nagCfg = await nagConfigTask

        if let snapshot {
            if let fast = snapshot["fast"]?.objectValue { fastGroups = fast }
            if let slow = snapshot["slow"]?.objectValue { slowGroups = slow }
        }
        if let profile { profileStatus = profile }
        if let features { featuresStatus = features }
        // v3.35.2 起官方固件移除了爆闪接口：探测一次 404 就把两个入口隐藏，
        // 避免列表里留着点进去只有报错的模块。网络错误不判定为“不支持”。
        if includeMeta, strobeSupported != true, features != nil {
            let due = lastStrobeProbe.map { Date().timeIntervalSince($0) > 60 } ?? true
            if due { await probeStrobeSupport(using: currentClient) }
        }
        if includeMeta, newFeaturesSupported != true, features != nil {
            let due = lastNewFeaturesProbe.map { Date().timeIntervalSince($0) > 60 } ?? true
            if due { await probeNewFeatures(using: currentClient) }
        }
        if let s3xy { s3xyStats = s3xy }
        if isS3XYEnabled && !showsS3XYTab {
            showsS3XYTab = true
            UserDefaults.standard.set(true, forKey: "p4can.tab.s3xy")
        }
        if let ota { otaStatus = ota }
        if let wifi { wifiStatus = wifi }
        if let system { systemStats = system }
        if let das { dasStats = das }
        if let nagCfg { nagConfig = nagCfg }

        rebuildDerived()

        let labVisible = isLabEnabled
        if labVisible != lastLabVisible {
            lastLabVisible = labVisible
            onLabVisibilityChange?()
        }
        let s3xyVisible = isS3XYEnabled
        if s3xyVisible != lastS3XYVisible {
            lastS3XYVisible = s3xyVisible
            onBluetoothTabVisibilityChange?()
        }

        let gotSnapshot = snapshot != nil
        let gotMeta = includeMeta && (profile != nil || features != nil || system != nil)

        if gotSnapshot || gotMeta {
            phase = .online
            // 「已同步」只认快照：任一慢端点成功不代表挡位/扭矩是新的。
            // 缓存标记也只在快照成功时清除，否则会出现「已同步 + 缓存数据」。
            if gotSnapshot {
                lastUpdated = Date()
                if isShowingCachedData {
                    isShowingCachedData = false
                    cachedAt = nil
                }
            }
            persistCacheIfDue()
            #if DEBUG
            // 本地联调：SIMCTL_CHILD_P4CAN_LIVEACTIVITY=1 首次联网自动开启实时活动
            if gotSnapshot,
               ProcessInfo.processInfo.environment["P4CAN_LIVEACTIVITY"] == "1",
               !liveActivityEnabled {
                setLiveActivity(true)
            }
            #endif
        } else {
            let reason = await Self.probeReason(client: currentClient)
            phase = .offline(reason: reason)
            restoreCacheIfNeeded()
        }
    }

    // MARK: - 离线缓存

    /// 节流写入：轮询间隔 250–1000 ms，没必要每拍都落盘；
    /// 但一旦拿到新的端点（profile/features 等是每 4 拍才拉），要立刻补写。
    private func persistCacheIfDue(force: Bool = false) {
        let now = Date()
        let entryCount = cacheEntryCount
        let gainedEntries = entryCount > lastCachedEntryCount
        if !force, !gainedEntries, let last = lastCacheWriteAt, now.timeIntervalSince(last) < 20 { return }
        var entries: [String: P4JSON] = [:]
        if !fastGroups.isEmpty { entries["fast"] = .object(fastGroups) }
        if !slowGroups.isEmpty { entries["slow"] = .object(slowGroups) }
        if let profileStatus { entries["profile"] = profileStatus }
        if let featuresStatus { entries["features"] = featuresStatus }
        if let systemStats { entries["system"] = systemStats }
        if let dasStats { entries["das"] = dasStats }
        if let s3xyStats { entries["s3xy"] = s3xyStats }
        if let wifiStatus { entries["wifi"] = wifiStatus }
        if let otaStatus { entries["ota"] = otaStatus }
        if let nagConfig { entries["nag"] = nagConfig }
        guard !entries.isEmpty else { return }
        lastCacheWriteAt = now
        lastCachedEntryCount = entries.count
        OfflineCache.save(host: host, entries: entries, at: now)
    }

    /// 连不上且手上没有任何数据时，用上次成功的缓存顶上（不会覆盖实时数据）。
    private func restoreCacheIfNeeded() {
        guard !hasRenderableData, !isShowingCachedData else { return }
        guard let cache = OfflineCache.load(host: host) else { return }
        if let fast = cache.entries["fast"]?.objectValue { fastGroups = fast }
        if let slow = cache.entries["slow"]?.objectValue { slowGroups = slow }
        if let profile = cache.entries["profile"] { profileStatus = profile }
        if let features = cache.entries["features"] { featuresStatus = features }
        if let system = cache.entries["system"] { systemStats = system }
        if let das = cache.entries["das"] { dasStats = das }
        if let s3xy = cache.entries["s3xy"] { s3xyStats = s3xy }
        if let wifi = cache.entries["wifi"] { wifiStatus = wifi }
        if let ota = cache.entries["ota"] { otaStatus = ota }
        if let nag = cache.entries["nag"] { nagConfig = nag }
        guard hasRenderableData else { return }
        isShowingCachedData = true
        cachedAt = cache.savedAt
        lastUpdated = cache.savedAt
        // 缓存数据不写趋势采样，也避免冷启动时拉起实时活动。
        rebuildDerived(appendSample: false, pushLiveActivity: false)
    }

    private func rebuildDerived(appendSample: Bool = true, pushLiveActivity: Bool = true) {
        var merged: [String: P4JSON] = [:]
        for group in Array(fastGroups.values) + Array(slowGroups.values) {
            if let object = group.objectValue {
                merged.merge(object) { _, new in new }
            }
        }
        for source in [profileStatus, featuresStatus, wifiStatus, otaStatus, s3xyStats, dasStats, systemStats] {
            if let object = source?.objectValue {
                merged.merge(object) { _, new in new }
            }
        }
        mergedStats = merged
        canBuses = CanBusResolver.resolve(
            traffic: fastGroups["cantraffic"]?.objectValue ?? [:],
            profile: profileStatus?.objectValue ?? [:]
        )
        if appendSample { appendTrendSample() }
        if pushLiveActivity { refreshLiveActivity() }
    }

    /// 追加扭矩采样：按 180 s 时间窗（与「近 3 分钟」文案一致），最多 1 s 一点。
    /// 原来按 120 点裁剪，500 ms 档实际只有 1 分钟；250 ms 档点数又会翻倍。
    private func appendTrendSample() {
        guard let torque = fastGroups["nag"]?["torque"]?.doubleValue else { return }
        let now = Date()
        if let last = trendSamples.last, now.timeIntervalSince(last.date) < 0.9 { return }
        trendSamples.append(TrendSample(date: now, torqueNm: torque))
        let cutoff = now.addingTimeInterval(-180)
        let firstFresh = trendSamples.firstIndex { $0.date >= cutoff } ?? trendSamples.count
        if firstFresh > 0 { trendSamples.removeFirst(firstFresh) }
    }

    // MARK: - 界面

    /// 切换外观：持久化并通知根窗口同步（SwiftUI 与 UIKit 页面一起变化）。
    func setAppearance(_ appearance: AppAppearance) {
        guard appearance != self.appearance else { return }
        self.appearance = appearance
        UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceDefaultsKey)
        onAppearanceChange?()
        Haptics.impact()
    }

    /// 切换主页刷新间隔（250 / 500 / 1000 ms）；下一拍轮询即生效。
    func setPollInterval(_ milliseconds: Int) {
        let value = Self.pollIntervalOptions.contains(milliseconds) ? milliseconds : 500
        guard value != pollIntervalMs else { return }
        pollIntervalMs = value
        UserDefaults.standard.set(value, forKey: Self.pollIntervalDefaultsKey)
        Haptics.impact()
    }

    /// 单独拉取车型状态（更改车型、从后台返回时使用）。
    func refreshProfile() async {
        guard let profile = try? await client.get(P4Route.profileStatus) else { return }
        profileStatus = profile
        rebuildDerived()
    }

    /// 探测固件是否提供前后爆闪接口。
    private func probeStrobeSupport(using client: P4APIClient) async {
        lastStrobeProbe = Date()
        do {
            _ = try await client.get(P4Route.headlightStrobeStats)
            strobeSupported = true
        } catch let error as P4APIError {
            if error.status == 404 { strobeSupported = false }
        } catch {
            // 离线/超时：保持未知，下一轮再试；不能把“没连上”当成“不支持”。
        }
    }

    /// 探测固件是否带 v3.35.2 新功能。用预热接口做代表：200 即新版，404 即旧版。
    private func probeNewFeatures(using client: P4APIClient) async {
        lastNewFeaturesProbe = Date()
        do {
            _ = try await client.get(P4Route.preheatStats)
            newFeaturesSupported = true
        } catch let error as P4APIError {
            if error.status == 404 { newFeaturesSupported = false }
        } catch {
            // 离线/超时：保持未知，下一轮再试。
        }
    }

    /// 单独拉取功能闸门（LAB Menu / S3XY / 封禁方案），用于开关后立即刷新标签栏。
    func refreshFeatures() async {
        guard let features = try? await client.get(P4Route.featuresStatus) else { return }
        featuresStatus = features
        rebuildDerived()
        let visible = isLabEnabled
        if visible != lastLabVisible {
            lastLabVisible = visible
            onLabVisibilityChange?()
        }
        let s3xyVisible = isS3XYEnabled
        if s3xyVisible != lastS3XYVisible {
            lastS3XYVisible = s3xyVisible
            onBluetoothTabVisibilityChange?()
        }
    }

    /// 切换语言：持久化并刷新标签栏文案。
    func setLanguage(_ language: AppLanguage) {
        guard language != self.language else { return }
        self.language = language
        UserDefaults.standard.set(language.rawValue, forKey: Self.languageDefaultsKey)
        L10n.selection = language
        onLanguageChange?()
        Haptics.impact()
    }

    // MARK: - 锁屏 / 灵动岛

    var isLiveActivitySupported: Bool { liveActivity.isSupported }

    func setLiveActivity(_ enabled: Bool) {
        liveActivityEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.liveActivityDefaultsKey)
        if enabled {
            lastLiveActivityAttempt = Date()
            // 创建结果要回读：系统关闭实时活动时开关不能显示「已开启」。
            Task {
                let ok = await liveActivity.start(deviceName: host, state: activityState())
                if ok {
                    toast = P4Toast(message: L10n.t("已开启锁屏 / 灵动岛实时状态", "Live Activity enabled"), style: .success)
                } else {
                    liveActivityEnabled = false
                    UserDefaults.standard.set(false, forKey: Self.liveActivityDefaultsKey)
                    toast = P4Toast(
                        message: L10n.t("系统未允许实时活动：请在 设置 → P4管家 中开启「实时活动」",
                                        "Live Activities are off. Enable them in Settings → P4管家."),
                        style: .failure
                    )
                }
            }
        } else {
            liveActivity.end()
            toast = P4Toast(message: "已关闭实时状态", style: .info)
        }
        Haptics.impact()
    }

    private func activityState() -> CanActivityAttributes.ContentState {
        let buses = canBuses.map { bus in
            CanBusActivityState(
                name: bus.displayName,
                online: bus.isOnline,
                detail: bus.rxCount.map { "收 \($0) 帧" } ?? bus.stateText
            )
        }
        let gear = group("r79")["gearName"]?.stringValue ?? "—"
        return CanActivityAttributes.ContentState(
            buses: buses,
            nagEnabled: nagConfig?["enabled"]?.boolValue ?? false,
            blinkEnabled: group("blink")["enabled"]?.boolValue ?? false,
            tlsscEnabled: group("summon")["tlssc"]?.boolValue
                ?? slowGroups["summon"]?["tlssc"]?.boolValue
                ?? false,
            gear: gear,
            vehicleModel: profileName,
            updatedAt: Date()
        )
    }

    /// 已开启时同步内容；首次联网时自动拉起活动（带 10s 冷却避免失败重试风暴）。
    private func refreshLiveActivity() {
        guard liveActivityEnabled else { return }
        // 离线：不要继续显示离线前的绿勾。持续 1 分钟后结束活动，恢复在线会自动重建。
        if !isOnline {
            if liveActivityOfflineSince == nil { liveActivityOfflineSince = Date() }
            if let since = liveActivityOfflineSince,
               Date().timeIntervalSince(since) > 60,
               liveActivity.isActive {
                liveActivity.end()
            }
            return
        }
        liveActivityOfflineSince = nil
        let state = activityState()
        guard !state.buses.isEmpty else { return }
        if liveActivity.isActive {
            liveActivity.update(state: state)
        } else if lastLiveActivityAttempt.map({ Date().timeIntervalSince($0) > 10 }) ?? true {
            lastLiveActivityAttempt = Date()
            Task { await liveActivity.start(deviceName: host, state: state) }
        }
    }

    /// 读取快照小组（nag / blink / summon / cantraffic / r79 / s3xy / lab3f8 …）。
    func group(_ name: String) -> [String: P4JSON] {
        if let value = fastGroups[name]?.objectValue { return value }
        if let value = slowGroups[name]?.objectValue { return value }
        return [:]
    }

    /// 读取组内字段。
    func field(_ group: String, _ key: String) -> P4JSON? {
        self.group(group)[key]
    }

    /// 全字段兜底查找。
    func stat(_ key: String) -> P4JSON? {
        if let value = mergedStats[key] { return value }
        for group in fastGroups.values {
            if let value = group[key] { return value }
        }
        for group in slowGroups.values {
            if let value = group[key] { return value }
        }
        return nil
    }

    func loadAllEndpoints() async {
        guard !isScanningEndpoints else { return }
        isScanningEndpoints = true
        // 30 个端点扫描期间必须让全局轮询停手：固件是单线程 WebServer，
        // 并发读会把 8 s 超时打穿，扫描结果也会和快照互相覆盖。
        exclusiveOperationDepth += 1
        defer {
            isScanningEndpoints = false
            exclusiveOperationDepth = max(0, exclusiveOperationDepth - 1)
        }

        let currentClient = client
        var payloads: [String: P4JSON] = [:]
        var errors: [String: String] = [:]

        for chunk in Self.browseEndpoints.chunked(into: 4) {
            let results = await withTaskGroup(of: (String, P4JSON?, String?).self) { group in
                for full in chunk {
                    group.addTask {
                        do {
                            return (full, try await Self.fetchRaw(currentClient, full), nil)
                        } catch {
                            let message = (error as? P4APIError)?.message ?? error.localizedDescription
                            return (full, nil, message)
                        }
                    }
                }
                var collected: [(String, P4JSON?, String?)] = []
                for await item in group { collected.append(item) }
                return collected
            }
            for (path, value, error) in results {
                if let value { payloads[path] = value }
                if let error { errors[path] = error }
            }
        }

        endpointPayloads = payloads
        endpointErrors = errors
        endpointsUpdatedAt = Date()
        // 扫描结果也是「刚读到的真相」：同步进共享缓存，页面切过去不用再等一轮。
        let scannedAt = Date()
        for (path, value) in payloads {
            endpointValues[path] = value
            endpointFetchedAt[path] = scannedAt
        }

        if let snapshot = payloads["/api/snapshot?groups=home-fast&slow=1"] {
            if let fast = snapshot["fast"]?.objectValue { fastGroups = fast }
            if let slow = snapshot["slow"]?.objectValue { slowGroups = slow }
        }
        if let value = payloads[P4Route.systemStats] { systemStats = value }
        if let value = payloads[P4Route.profileStatus] { profileStatus = value }
        if let value = payloads[P4Route.featuresStatus] { featuresStatus = value }
        if let value = payloads[P4Route.nagConfig] { nagConfig = value }
        if let value = payloads[P4Route.wifiStatus] { wifiStatus = value }
        if let value = payloads[P4Route.otaStatus] { otaStatus = value }
        if let value = payloads[P4Route.s3xyStats] { s3xyStats = value }
        if let value = payloads[P4Route.dasStats] { dasStats = value }
        rebuildDerived()
    }

    /// 支持 `/api/snapshot?groups=...` 这类带查询串的浏览项。
    nonisolated private static func fetchRaw(_ client: P4APIClient, _ full: String) async throws -> P4JSON {
        if let questionMark = full.firstIndex(of: "?") {
            let path = String(full[..<questionMark])
            let queryString = String(full[full.index(after: questionMark)...])
            let params = queryString.split(separator: "&").map { pair -> P4Param in
                let parts = pair.split(separator: "=", maxSplits: 1)
                return P4Param(String(parts[0]), parts.count > 1 ? String(parts[1]) : "")
            }
            return try await client.get(path, query: params)
        }
        return try await client.get(full)
    }

    private static func probeReason(client: P4APIClient) async -> String {
        do {
            _ = try await client.get(P4Route.systemStats)
            return "未知错误"
        } catch let error as P4APIError {
            return error.message
        } catch {
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain {
                switch ns.code {
                case NSURLErrorTimedOut: return "连接超时，请确认已加入设备热点"
                case NSURLErrorCannotFindHost,
                     NSURLErrorCannotConnectToHost: return "无法连接设备，请确认网络"
                case NSURLErrorNotConnectedToInternet: return "未连接网络"
                default: break
                }
            }
            return error.localizedDescription
        }
    }

    // MARK: - 命令

    /// 执行固件写接口：POST + query 参数，然后刷新。
    /// 执行固件写接口：POST + query 参数，然后刷新。
    /// - Returns: 是否真的把命令发出去了。忙时返回 false（调用方不要当成已提交）。
    @discardableResult
    func command(
        _ label: String,
        path: String,
        query: [P4Param] = [],
        refresh: Bool = true
    ) async -> Bool {
        guard !isBusy else {
            // 以前这里直接 return，调用方与用户都以为点成功了。
            toast = P4Toast(message: L10n.t("设备忙，请稍候再试", "Device busy — try again in a moment"), style: .info)
            return false
        }
        isBusy = true
        defer { isBusy = false }
        var succeeded = false
        do {
            _ = try await client.post(path, query: query)
            toast = P4Toast(message: "已执行「\(label)」", style: .success)
            Haptics.success()
            succeeded = true
        } catch {
            toast = P4Toast(message: "「\(label)」失败：\(Self.friendly(error))", style: .failure)
            Haptics.error()
        }
        if refresh { await refreshOnce() }
        return succeeded
    }



    /// OTA 上传入口。
    ///
    /// 固件的行为决定了不能只看 HTTP 结果：`httpOtaFinish()` 回 200 之后约 700 ms 就重启，
    /// 手机侧经常收不到回包（-1005 连接中断）。因此：
    /// 1. 上传期间暂停所有状态轮询（固件是单线程 WebServer，抢连接会让写入变慢甚至中断）；
    /// 2. 请求体发完却拿不到回包 → 不判失败，进入“确认”阶段；
    /// 3. 确认阶段以设备是否重启为准（重启 = 写入成功，因为只有 `Update.end(true)` 成功才重启）。
    func uploadFirmware(named name: String, data: Data) async {
        guard !otaUploading else { return }
        otaUploading = true
        otaUploadPhase = .uploading
        otaUploadSent = 0
        otaUploadTotal = data.count
        exclusiveOperationDepth += 1
        await performUpload(named: name, data: data)
        exclusiveOperationDepth = max(0, exclusiveOperationDepth - 1)
        otaUploading = false
        await refreshOnce()
    }

    /// 清掉已结束的 OTA 进度（进入升级页时调用；上传中不生效）。
    func clearFinishedOTAProgress() {
        guard !otaUploading else { return }
        otaUploadPhase = .idle
        otaUploadSent = 0
        otaUploadTotal = 0
    }

    private func performUpload(named name: String, data: Data) async {
        let attemptBefore = otaStatus?["attempt"]?.intValue ?? 0
        do {
            let json = try await client.uploadFirmware(fileName: name, data: data) { @Sendable sent, total in
                Task { @MainActor [weak self] in
                    self?.otaUploadSent = sent
                    self?.otaUploadTotal = max(total, 1)
                }
            }
            otaUploadSent = otaUploadTotal
            if json["ok"]?.boolValue == false {
                let message = json["error"]?.stringValue ?? ""
                otaUploadPhase = .failed
                toast = P4Toast(
                    message: message.isEmpty ? "设备拒绝写入固件" : "固件写入失败：\(message)",
                    style: .failure
                )
                return
            }
            otaUploadPhase = .verifying
            await confirmUpload(attemptBefore: attemptBefore)
        } catch let interrupted as P4UploadInterrupted where interrupted.bodyFullySent {
            // 请求体已全部发出：设备极可能已写入并重启，转到确认阶段而不是直接报失败。
            otaUploadPhase = .verifying
            await confirmUpload(attemptBefore: attemptBefore)
        } catch {
            otaUploadPhase = .failed
            toast = P4Toast(message: "固件上传失败：\(Self.friendly(error))", style: .failure)
        }
    }

    /// 上传后确认：等设备重启（重启 = 写入成功），或读到设备的失败原因。
    private func confirmUpload(attemptBefore: Int64) async {
        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline {
            try? await Task.sleep(for: .milliseconds(1200))
            do {
                let status = try await client.get(P4Route.otaStatus)
                let object = status.objectValue ?? [:]
                let error = object["error"]?.stringValue ?? ""
                if !error.isEmpty {
                    otaUploadPhase = .failed
                    toast = P4Toast(message: "固件写入失败：\(error)", style: .failure)
                    return
                }
                let attempt = object["attempt"]?.intValue ?? 0
                let stage = object["stage"]?.stringValue ?? ""
                // 设备自报 complete = 明确写入成功；stage 回到 idle 且 attempt 归零 = 已重启过。
                let rebooted = stage == "idle" && attempt < max(attemptBefore, 1)
                if stage == "complete" {
                    // 设备自报完成，但重启还没发生（固件回包后约 0.7 s 才 restart）。
                    otaUploadPhase = .done
                    toast = P4Toast(message: "固件写入完成，设备即将重启", style: .success)
                    return
                }
                // 断线本身不能当成功依据：只有「重启后回到 idle 且 attempt 回落」才算数。
                if rebooted {
                    otaUploadPhase = .done
                    toast = P4Toast(message: "固件已写入，设备已重启", style: .success)
                    return
                }
                if object["inProgress"]?.boolValue == true { continue }
            } catch {
                // 连不上：设备可能正在重启，继续等它回来；不据此判成功。
            }
        }
        otaUploadPhase = .failed
        toast = P4Toast(
            message: "固件已发送，但没能确认设备重启；请到「状态」页看是否已恢复在线",
            style: .info
        )
    }

    func exportLogFile(_ log: P4LogFile) async throws -> URL {
        let data = try await client.downloadData(log.path)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(log.fileName)
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - 便捷读取

    var isOnline: Bool { phase == .online }

    var s3xyDevices: [S3XYDevice] { S3XYDevice.devices(from: s3xyStats) }
    var s3xyScanResults: [S3XYScanResult] { S3XYScanResult.results(from: s3xyStats) }

    var isBluetoothEnabled: Bool { s3xyStats?["bluetoothEnabled"]?.boolValue ?? false }
    var isLabEnabled: Bool {
        #if DEBUG
        // 本地联调：SIMCTL_CHILD_P4CAN_LAB=1 强制显示实验室标签
        if ProcessInfo.processInfo.environment["P4CAN_LAB"] == "1" { return true }
        #endif
        return featuresStatus?["lab"]?.boolValue ?? false
    }
    var isSetupMode: Bool { profileStatus?["setupMode"]?.boolValue ?? false }
    var profileName: String? { profileStatus?["profileName"]?.stringValue }
    var topologyName: String? { profileStatus?["topologyName"]?.stringValue }

    /// 车型能力位（profile/status 与 features/status 共用命名）。
    func capability(_ key: String) -> Bool? {
        if let value = featuresStatus?[key]?.boolValue { return value }
        return profileStatus?[key]?.boolValue
    }

    // MARK: - 诊断

    /// App 版本 + build，来自 Info.plist。
    var appVersionText: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    /// 一眼能看懂的诊断摘要：版本、连接、固件、拓扑、总线、OTA。
    /// 「复制诊断信息」和诊断包里的 diagnostics.txt 用的是同一份内容。
    var diagnosticsSummary: String {
        let buses = canBuses
        let online = buses.filter(\.isOnline).count
        var lines: [String] = [
            "P4 管家 \(appVersionText)",
            "设备 \(host) · \(isOnline ? "在线" : "离线")",
            "固件 \(systemStats?["fwVersion"]?.stringValue ?? "—") · \(profileName ?? "—")",
            "拓扑 \(topologyName ?? "—")",
            "CAN \(online)/\(max(buses.count, 1)) 在线 · 蓝牙 \(isBluetoothEnabled ? "开" : "关") · LAB \(isLabEnabled ? "开" : "关")",
        ]
        if let date = lastUpdated {
            lines.append("最后更新 \(date.formatted(date: .abbreviated, time: .standard))")
        }
        if isShowingCachedData, let cachedAt {
            lines.append("当前显示缓存 · \(cachedAt.formatted(date: .abbreviated, time: .standard))")
        }
        for bus in buses {
            lines.append("· \(bus.displayName) \(bus.stateText) rx=\(bus.rxCount) tx=\(bus.txAccepted)")
        }
        if let ota = otaStatus?.objectValue {
            let stage = ota["stage"]?.stringValue ?? "-"
            let attempt = ota["attempt"]?.displayText ?? "-"
            let error = ota["error"]?.stringValue ?? ""
            lines.append("OTA stage=\(stage) attempt=\(attempt) error=\(error.isEmpty ? "-" : error)")
        }
        return lines.joined(separator: "\n")
    }

    /// 生成诊断包 zip：摘要 + 网络日志 CSV + 最近一次快照 JSON。
    func makeDiagnosticsArchive() throws -> URL {
        let stamp = Self.diagnosticsStamp.string(from: Date())
        let log = NetworkLog.shared.snapshot()
        let iso = ISO8601DateFormatter()
        var csv = "time,method,path,query,status,durationMs,bytes,error\n"
        for entry in log {
            let fields = [
                iso.string(from: entry.date),
                entry.method,
                entry.path,
                entry.query.replacingOccurrences(of: ",", with: ";"),
                entry.statusCode.map(String.init) ?? "",
                String(entry.durationMs),
                String(entry.bytes),
                (entry.error ?? "").replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: ",", with: ";"),
            ]
            csv += fields.joined(separator: ",") + "\n"
        }
        let snapshot = (try? JSONEncoder().encode(mergedStats)) ?? Data("{}".utf8)
        let archive = ZipArchive.make(entries: [
            ("diagnostics.txt", Data(diagnosticsSummary.utf8)),
            ("network-log.csv", Data(csv.utf8)),
            ("snapshot.json", snapshot),
        ])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("P4CAN-diagnostics-\(stamp).zip")
        try archive.write(to: url, options: .atomic)
        return url
    }

    private static let diagnosticsStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    /// 把系统网络错误翻成“能照做”的中文提示。
    ///
    /// URLSession 的本地化错误对车主没意义（"The request timed out."），
    /// 这里按失败类型给出下一步动作，避免用户只能反复重试。
    static func friendly(_ error: Error) -> String {
        if let apiError = error as? P4APIError { return deviceMessage(apiError) }
        if let upload = error as? P4UploadInterrupted { return upload.description }
        guard let urlError = error as? URLError else { return error.localizedDescription }
        switch urlError.code {
        case .timedOut:
            return "设备响应超时：确认手机仍连在 P4-CAN 的热点上，或稍后重试"
        case .cannotFindHost, .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet:
            return "连不上设备：检查「设置 → 设备地址」是否为设备当前 IP，并确认已连上它的 Wi-Fi"
        case .dnsLookupFailed:
            return "地址解析失败：设备地址应为 IP，例如 192.168.4.1"
        case .appTransportSecurityRequiresSecureConnection:
            return "系统拦截了明文连接：设备地址需以 http:// 开头"
        case .cancelled:
            return "请求已取消"
        default:
            return urlError.localizedDescription
        }
    }

    /// 固件错误码 → 可执行的中文提示。
    ///
    /// 固件把「为什么不允许」直接写在 `error` 里（多为英文常量），App 以前原样透传，
    /// 用户只看到 `lab-disabled` / `ALREADY_ACTIVE` 这类字符串。这里按语义翻译，
    /// 保留原文的接口留给诊断（网络日志里仍记录原始 error）。
    private static func deviceMessage(_ error: P4APIError) -> String {
        guard let raw = error.deviceError else { return error.message }
        if let mapped = deviceErrorText[raw] { return mapped }

        // 前缀类：`<Action> unavailable for current profile/topology`、
        // `<xxx> requires ...`、`... must be ...` 等带参数的文案。
        if raw.hasPrefix("driver monitoring control unavailable") {
            return "当前车型不支持驾驶员监控控制（DMS）"
        }
        if raw.hasPrefix("ISA suppression unavailable") {
            return "当前车型不支持 ISA 抑制"
        }
        if raw.hasPrefix("NAG unavailable") || raw.hasPrefix("NAG method unavailable") {
            return "当前车型/拓扑不支持该 NAG 方式"
        }
        if raw.hasPrefix("Confirm-Free unsupported") {
            return "当前车型不支持「免确认」"
        }
        if raw.hasPrefix("Advanced EAP unavailable") {
            return "当前拓扑不支持高级 EAP"
        }
        if raw.hasPrefix("AP Pedal / Regen Profile requires") {
            return "该踏板/回充档位需要车型支持 0x334 报文"
        }
        if raw.hasPrefix("Legacy TSL9 route selector unavailable") {
            return "当前车型不支持旧版 TSL9 通道选择"
        }
        if raw.hasPrefix("banned car not supported") {
            return "当前车型不支持「封禁车辆」"
        }
        if raw.hasPrefix("invalid topology") || raw == "Invalid vehicle topology" || raw == "missing topology" {
            return "车型拓扑与当前车辆不匹配，请先在「设置 → 车型」确认识别结果"
        }
        if raw.hasPrefix("mixed-hw3-settings") || raw.hasPrefix("hw3-unsupported-profile") {
            return "HW3 相关设置与当前车型不匹配"
        }
        if raw.contains("must be") || raw.hasPrefix("invalid ") || raw.hasPrefix("missing ") {
            return "参数未通过设备校验：\(raw)"
        }
        if raw.contains("still active") || raw == "CSV export active" || raw == "capture busy or NVS write failed" {
            return "捕获或导出仍在进行，请等它结束再操作"
        }
        if raw.contains("still in progress") {
            return "上一步还没结束，请稍后重试"
        }
        if raw.contains("requires") {
            return "设备要求满足前置条件：\(raw)"
        }

        switch error.status {
        case 403:
            return "设备拒绝了该操作（HTTP 403）：\(raw)"
        case 409:
            return "设备当前状态不允许该操作（HTTP 409）：\(raw)"
        case 410:
            return "该功能在当前固件中已不可用（HTTP 410）：\(raw)"
        case 503:
            return "设备忙或正在重启（HTTP 503）：\(raw)"
        default:
            return error.message
        }
    }

    /// 高频固件错误常量的中文释义（与 `web_api.h` 的 `send(4xx, ...)` 对齐）。
    private static let deviceErrorText: [String: String] = [
        "ALREADY_ACTIVE": "上一次操作还没结束，请先停止或等它完成",
        "NO_FRAME": "还没收到整车对应报文：车辆需上电，相关总线在线",
        "SOURCE_MISMATCH": "触发入口与配置不一致：请到「蓝牙」页确认 S3XY 按键设置",
        "TURN_SIGNAL_ACTIVE": "转向灯注入进行中，请等转向结束再试",
        "SEND_FAILED": "CAN 发送失败，已停止并恢复",
        "CAN_EPOCH_CHANGED": "CAN 总线重启过，操作已停止；请重新触发",
        "STALKLESS_UNSUPPORTED": "当前车型为无拨杆版本，不支持拨杆注入",
        "NO_STOCK_TEMPLATE": "还没捕获到整车原始帧：先让车辆上报一次拨杆状态",
        "HOLD_DISABLED": "「按住拨杆爆闪」已关闭",
        "USER_STOP": "已手动停止",
        "COMPLETE": "已完成并恢复",
        "LAB disabled": "实验室功能未开启：请先在「实验室」页打开总开关",
        "lab-disabled": "实验室功能未开启：请先在「实验室」页打开总开关",
        "bluetooth disabled": "蓝牙已关闭：请先在「蓝牙」页打开总开关",
        "BLE shutdown still in progress": "蓝牙正在关闭，请稍后再开",
        "not available in setup mode": "设备处于 Setup 模式，该操作被禁用；请先完成配网",
        "CAN stopped for maintenance; reboot required": "CAN 已因维护停止，需要重启设备",
        "capture or CSV export still active": "捕获或 CSV 导出仍在进行，请等它结束",
        "CSV export active": "CSV 导出仍在进行，请等它结束",
        "capture busy or NVS write failed": "捕获正忙，或参数写入失败；请稍后重试",
        "confirm free unsupported": "当前车型不支持免确认",
        "empty name": "名称不能为空",
        "missing ssid": "请填写 Wi-Fi 名称",
        "already registered": "该设备已注册",
        "device not found": "设备未找到",
        "invalid action": "动作无效，请重新选择",
        "invalid confirm": "确认参数无效",
        "invalid gesture": "手势参数无效",
        "invalid mode": "模式参数无效",
        "invalid profile": "车型配置无效",
        "invalid timing": "时序参数无效",
        "invalid bus": "总线参数无效",
        "invalid enabled": "开关参数无效",
        "settings not supplied": "没有提交任何设置",
        "no setting supplied": "没有提交任何设置",
        "restore not allowed for current state/profile": "当前状态/车型不允许恢复",
        "CAN stop not confirmed; retry reboot": "CAN 停止未确认，请重试重启",
        "Mode H profiles retired; Mode H uses one engine": "Mode H 已改为单一引擎，旧的档位配置不再生效",
    ]
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0, !isEmpty else { return [] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
