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

    /// 三路 CAN 总线（CAN 1 BODY / CAN 2 CHASSIS / CAN 3 PARTY）。
    @Published private(set) var canBuses: [CanBusSnapshot] = []
    /// 全部字段扁平合并（供通用键值展示与搜索）。
    @Published private(set) var mergedStats: [String: P4JSON] = [:]
    /// 扭矩趋势采样（Swift Charts 使用，约保留 120 个点 ≈ 3 分钟）。
    @Published private(set) var trendSamples: [TrendSample] = []
    /// 是否开启锁屏 / 灵动岛实时活动（持久化）。
    @Published private(set) var liveActivityEnabled = false
    /// 蓝牙标签是否显示：与网页一致，由固件 S3XY 功能闸门决定（功能页的 S3XY 开关）。
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
    ]

    /// 离线时放慢重试；在线间隔由用户设置（默认 500 ms，与网页一致）。
    private var onlineInterval: Duration { .milliseconds(pollIntervalMs) }
    private var offlineInterval: Duration = .seconds(5)

    private static let hostDefaultsKey = "p4can.device.host"
    private static let liveActivityDefaultsKey = "p4can.liveactivity.enabled"
    private var pollTask: Task<Void, Never>?
    private var client: P4APIClient
    private var tick = 0
    private var lastLiveActivityAttempt: Date?
    /// 上次写缓存的时间（节流用）。
    private var lastCacheWriteAt: Date?
    /// 上次写入包含的端点数量（新端点出现时立刻补写）。
    private var lastCachedEntryCount = 0

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
        L10n.selection = self.language
        let savedAppearance = UserDefaults.standard.string(forKey: Self.appearanceDefaultsKey) ?? "system"
        self.appearance = AppAppearance(rawValue: savedAppearance) ?? .system
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

    func updateHost(_ newHost: String) {
        let trimmed = newHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != host else { return }
        guard let normalized = P4APIClient.validatedHost(trimmed) else {
            toast = P4Toast(
                message: "地址格式无效：只支持 http(s)://主机[:端口] 或 主机[:端口]，不要带账号、路径或查询参数",
                style: .failure
            )
            return
        }
        host = normalized
        UserDefaults.standard.set(normalized, forKey: Self.hostDefaultsKey)
        client = P4APIClient(host: normalized)
        phase = .idle
        start()
    }

    // MARK: - 刷新

    func refreshOnce() async {
        if phase != .online { phase = .connecting }
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
        if let s3xy { s3xyStats = s3xy }
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
            lastUpdated = Date()
            if isShowingCachedData {
                isShowingCachedData = false
                cachedAt = nil
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

    /// 追加扭矩采样（最多 120 点）。
    private func appendTrendSample() {
        guard let torque = fastGroups["nag"]?["torque"]?.doubleValue else { return }
        trendSamples.append(TrendSample(date: Date(), torqueNm: torque))
        if trendSamples.count > 120 {
            trendSamples.removeFirst(trendSamples.count - 120)
        }
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
            liveActivity.start(deviceName: host, state: activityState())
            lastLiveActivityAttempt = Date()
            toast = P4Toast(message: "已开启锁屏 / 灵动岛实时状态", style: .success)
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
        guard liveActivityEnabled, isOnline else { return }
        let state = activityState()
        guard !state.buses.isEmpty else { return }
        if liveActivity.isActive {
            liveActivity.update(state: state)
        } else if lastLiveActivityAttempt.map({ Date().timeIntervalSince($0) > 10 }) ?? true {
            lastLiveActivityAttempt = Date()
            liveActivity.start(deviceName: host, state: state)
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
        defer { isScanningEndpoints = false }

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
    func command(
        _ label: String,
        path: String,
        query: [P4Param] = [],
        refresh: Bool = true
    ) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await client.post(path, query: query)
            toast = P4Toast(message: "已执行「\(label)」", style: .success)
            Haptics.success()
        } catch {
            toast = P4Toast(message: "「\(label)」失败：\(Self.friendly(error))", style: .failure)
            Haptics.error()
        }
        if refresh { await refreshOnce() }
    }

    func applyWiFi(ssid: String, password: String) async {
        guard !ssid.isEmpty else {
            toast = P4Toast(message: "请填写 Wi-Fi 名称", style: .failure)
            return
        }
        var query = [P4Param("ssid", ssid)]
        if !password.isEmpty { query.append(P4Param("password", password)) }
        await command("Wi-Fi 配置", path: P4Route.wifiApply, query: query, refresh: false)
        toast = P4Toast(
            message: "已提交：设备 SoftAP 将以新 SSID 重启（IP 仍为 192.168.4.1）。请重新加入该热点。",
            style: .info
        )
        await refreshOnce()
    }

    func uploadFirmware(named name: String, data: Data) async {
        guard !otaUploading else { return }
        otaUploading = true
        defer { otaUploading = false }
        do {
            _ = try await client.uploadFirmware(fileName: name, data: data)
            toast = P4Toast(message: "固件已上传，设备正在写入并重启，请勿断电", style: .success)
        } catch {
            toast = P4Toast(message: "固件上传失败：\(Self.friendly(error))", style: .failure)
        }
        await refreshOnce()
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

    static func friendly(_ error: Error) -> String {
        if let apiError = error as? P4APIError { return apiError.message }
        return error.localizedDescription
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0, !isEmpty else { return [] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
