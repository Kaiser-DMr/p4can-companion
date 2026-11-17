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
    /// 是否在标签栏显示「蓝牙」页（持久化；默认关闭——多数时间用不到，按需在系统页开启）。
    @Published private(set) var bluetoothTabEnabled = false
    /// 根控制器注入：标签显隐变化时重建标签栏（避免 Combine 跨隔离域捕获）。
    var onBluetoothTabVisibilityChange: (@MainActor () -> Void)?

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

    private var onlineInterval: Duration = .milliseconds(1500)
    private var offlineInterval: Duration = .seconds(5)

    private static let hostDefaultsKey = "p4can.device.host"
    private static let liveActivityDefaultsKey = "p4can.liveactivity.enabled"
    private static let bluetoothTabDefaultsKey = "p4can.tab.bluetooth"
    private var pollTask: Task<Void, Never>?
    private var client: P4APIClient
    private var tick = 0
    private var lastLiveActivityAttempt: Date?
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
        self.bluetoothTabEnabled = UserDefaults.standard.bool(forKey: Self.bluetoothTabDefaultsKey)
        #if DEBUG
        // 本地联调：SIMCTL_CHILD_P4CAN_BT_TAB=1 强制显示蓝牙标签
        if let raw = ProcessInfo.processInfo.environment["P4CAN_BT_TAB"] {
            self.bluetoothTabEnabled = (raw == "1")
        }
        #endif
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
        host = trimmed
        UserDefaults.standard.set(trimmed, forKey: Self.hostDefaultsKey)
        client = P4APIClient(host: trimmed)
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

        if snapshot != nil {
            phase = .online
            lastUpdated = Date()
            #if DEBUG
            // 本地联调：SIMCTL_CHILD_P4CAN_LIVEACTIVITY=1 首次联网自动开启实时活动
            if ProcessInfo.processInfo.environment["P4CAN_LIVEACTIVITY"] == "1",
               !liveActivityEnabled {
                setLiveActivity(true)
            }
            #endif
        } else if includeMeta, (profile != nil || features != nil || system != nil) {
            phase = .online
            lastUpdated = Date()
        } else {
            let reason = await Self.probeReason(client: currentClient)
            phase = .offline(reason: reason)
        }
    }

    private func rebuildDerived() {
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
        appendTrendSample()
        refreshLiveActivity()
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

    /// 蓝牙页是否出现在底部标签栏（持久化，默认关闭）。
    func setBluetoothTabEnabled(_ enabled: Bool) {
        guard enabled != bluetoothTabEnabled else { return }
        bluetoothTabEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.bluetoothTabDefaultsKey)
        onBluetoothTabVisibilityChange?()
        Haptics.impact()
        toast = P4Toast(
            message: enabled ? "「蓝牙」已显示在标签栏" : "「蓝牙」已从标签栏隐藏",
            style: .info
        )
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
    var isLabEnabled: Bool { featuresStatus?["lab"]?.boolValue ?? false }
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
