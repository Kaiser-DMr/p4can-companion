import Foundation

/// P4-CAN 固件 API 路由（依据开源固件 web_api.h 的路由注册表）。
enum P4Route {
    // 快照（分组接口，网页主数据源）
    static let snapshot = "/api/snapshot"

    // 系统
    static let systemStats = "/api/system/stats"
    static let systemReboot = "/api/system/reboot"
    static let systemFactoryReset = "/api/system/factory-reset"
    static let systemResetSettings = "/api/system/reset-settings"
    static let systemResetStats = "/api/system/reset-stats"
    static let systemReinitCAN = "/api/system/reinit-can"
    static let systemResetNVSKeepBLE = "/api/system/reset-nvs-keep-ble"
    static let bootCaptureCSV = "/api/system/boot-capture.csv"

    // Wi-Fi / OTA
    static let wifiStatus = "/api/wifi/status"
    static let wifiApply = "/api/wifi/apply"
    static let otaStatus = "/api/ota/status"
    static let otaUpload = "/update"

    // 车型
    static let profileStatus = "/api/profile/status"
    static let profileSelect = "/api/profile/select"

    // 功能闸门
    static let featuresStatus = "/api/features/status"
    static let featuresLab = "/api/features/lab"
    static let featuresS3XY = "/api/features/s3xy"
    static let featuresBanned = "/api/features/banned"
    static let featuresAPDriveProfile = "/api/features/ap-drive-profile"
    static let featuresDoorCancel = "/api/features/door-cancel"
    static let featuresTLSSCRestore = "/api/features/tlssc-restore"

    // NAG
    static let nagConfig = "/api/nag/config"
    static let nagStats = "/api/nag/stats"
    static let nagMode = "/api/nag/mode"
    static let nagUpdate = "/api/nag/update"
    static let nagReset = "/api/nag/reset"
    static let nagHProfileStats = "/api/nag/h-profile/stats"
    static let nagHProfileUpdate = "/api/nag/h-profile/update"
    static let nagHProfileReset = "/api/nag/h-profile/reset"

    // 变道 / 召唤
    static let ulcStats = "/api/ulc/stats"
    static let ulcUpdate = "/api/ulc/update"
    static let alcStats = "/api/lab/auto-lane-change/stats"
    static let alcUpdate = "/api/lab/auto-lane-change/update"
    static let summonStats = "/api/summon/stats"
    static let summonTLSSCEnable = "/api/summon/tlssc-enable"
    static let summonTLSSCDisable = "/api/summon/tlssc-disable"
    static let summonTLSSCHighwayGate = "/api/summon/tlssc-highway-gate"
    static let summonTLSSCNoABlock = "/api/summon/tlssc-noa-block"
    static let summonHeartbeatStats = "/api/lab/summon-heartbeat/stats"
    static let summonHeartbeatUpdate = "/api/lab/summon-heartbeat/update"

    // 驾驶员监控
    static let dmsConfig = "/api/driver-monitoring/config"
    static let dmsStart = "/api/drivermonitor/start"
    static let dmsReset = "/api/drivermonitor/reset"
    static let dmsStats = "/api/drivermonitor/stats"
    static let dasStats = "/api/das/stats"

    // 视觉 / 转向灯 / 车窗
    static let visionControlStats = "/api/vision-control/stats"
    static let visionControlUpdate = "/api/vision-control/update"
    static let blinkAStats = "/api/blinkA/stats"
    static let blinkAEnable = "/api/blinkA/enable"
    static let blinkADisable = "/api/blinkA/disable"
    static let blinkADelay = "/api/blinkA/delay"
    static let blinkATiming = "/api/blinkA/timing"
    static let blinkATxMode = "/api/blinkA/tx-mode"
    static let driverWindowStats = "/api/lab/driver-window/stats"
    static let driverWindowOpen = "/api/lab/driver-window/open"

    // 地区 / ISA
    static let countryStats = "/api/country/stats"
    static let countryUpdate = "/api/country/update"
    static let isaSuppressionConfig = "/api/isa-suppression/config"

    // R79
    static let r79Stats = "/api/r79/stats"
    static let r79Update = "/api/r79/update"
    static let r79APControlStats = "/api/r79/ap-control/stats"
    static let r79APControlUpdate = "/api/r79/ap-control/update"

    // 踏板 / 常驻热点
    static let pedalMapStats = "/api/pedalmap/stats"
    static let pedalMapSet = "/api/pedalmap/set"
    static let continuousAPConfig = "/api/continuous-ap/config"

    // S3XY
    static let s3xyStats = "/api/s3xy/stats"
    static let s3xyScan = "/api/s3xy/scan"
    static let s3xyPair = "/api/s3xy/pair"
    static let s3xyResetAll = "/api/s3xy/reset-all"
    static let s3xyClear = "/api/s3xy/clear"
    static let s3xyBluetoothEnable = "/api/s3xy/bluetooth-enable"
    static let s3xyBluetoothDisable = "/api/s3xy/bluetooth-disable"
    static let s3xyAutoEnable = "/api/s3xy/auto-enable"
    static let s3xyAutoDisable = "/api/s3xy/auto-disable"
    static let s3xyDeviceConnect = "/api/s3xy/device/connect"
    static let s3xyDeviceDisconnect = "/api/s3xy/device/disconnect"
    static let s3xyDeviceHandshake = "/api/s3xy/device/handshake"
    static let s3xyDeviceAction = "/api/s3xy/device/action"
    static let s3xyDeviceAuto = "/api/s3xy/device/auto"
    static let s3xyDeviceForget = "/api/s3xy/device/forget"
    static let s3xyDeviceRename = "/api/s3xy/device/rename"

    // 研究捕获
    // 前大灯爆闪（固件补丁 headlight_strobe.h）
    static let headlightStrobeConfig = "/api/headlight-strobe/config"
    static let headlightStrobeStats = "/api/headlight-strobe/stats"
    static let headlightStrobeTrigger = "/api/headlight-strobe/trigger"
    static let headlightStrobeStop = "/api/headlight-strobe/stop"
    // 后雾灯爆闪（固件 rear_fog_strobe.h）
    static let rearFogStrobeStats = "/api/rear-fog-strobe/stats"
    static let rearFogStrobeStart = "/api/rear-fog-strobe/start"
    static let rearFogStrobeStop = "/api/rear-fog-strobe/stop"

    static let researchCaptureStats = "/api/researchcapture/stats"
    static let researchCaptureStart = "/api/researchcapture/start"
    static let researchCaptureMode = "/api/researchcapture/mode"
    static let researchCaptureConfig = "/api/researchcapture/config"
    static let researchCaptureLabels = "/api/researchcapture/labels"
    static let researchCaptureReset = "/api/researchcapture/reset"
}

/// 一条查询参数。
struct P4Param: Sendable, Hashable {
    let key: String
    let value: String

    init(_ key: String, _ value: String) {
        self.key = key
        self.value = value
    }
}

/// 服务端返回的业务错误（`{"ok":false,"error":"..."}`）。
struct P4APIError: LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}

/// P4-CAN 设备 HTTP API 客户端。
///
/// 固件全部写接口使用 **query 参数**（`POST /api/...?k=v`），而非 JSON body；
/// 仅 `/update`（OTA）使用 multipart 上传。
///
/// 线程安全：仅持有不可变属性 + URLSession（Sendable）。
final class P4APIClient: Sendable {

    let baseURL: URL
    private let session: URLSession

    /// 单次 JSON 响应上限（防止异常/恶意端点把内存打满）。
    private static let maxJSONBytes = 4 * 1024 * 1024
    /// CSV / 日志下载上限。
    private static let maxDownloadBytes = 32 * 1024 * 1024
    /// OTA 应用镜像上限（ESP32 应用分区远小于此）。
    static let maxFirmwareBytes = 8 * 1024 * 1024
    /// 日志里需要打码的 query 参数。
    private static let sensitiveQueryKeys: Set<String> = [
        "password", "passwd", "pass", "psk", "token", "secret", "api_key", "apikey",
    ]

    init(host: String) {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        var components = URLComponents()
        components.scheme = "http"

        if let url = URL(string: trimmed), let scheme = url.scheme, !scheme.isEmpty {
            // 支持完整 URL（含端口/路径）：http://127.0.0.1:8080
            components = URLComponents(url: url, resolvingAgainstBaseURL: false) ?? components
        } else {
            // 支持 host:port（本地 mock 调试用）
            let parts = trimmed.split(separator: ":", maxSplits: 1)
            components.host = parts.first.map(String.init) ?? "192.168.4.1"
            if parts.count == 2, let port = Int(parts[1]) {
                components.port = port
            }
        }
        if components.host?.isEmpty != false { components.host = "192.168.4.1" }
        self.baseURL = components.url ?? URL(string: "http://192.168.4.1")!

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 60
        configuration.allowsCellularAccess = false
        configuration.waitsForConnectivity = false
        // 状态接口必须实时：禁用 URL 缓存，避免读到旧快照（与网页不同步）。
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        // 设备只应是被配置的那台 P4-CAN：拒绝任何 3xx 跳转，避免被热点/ARP 欺骗带到外网。
        self.session = URLSession(
            configuration: configuration,
            delegate: P4RedirectBlocker(),
            delegateQueue: nil
        )
    }

    /// 校验用户输入：只允许 http(s)://host[:port] 或 host[:port]，
    /// 不允许账号、路径、查询串、片段与空白字符。
    static func validatedHost(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 255,
              !trimmed.contains(where: \.isWhitespace) else { return nil }
        if trimmed.contains("://") {
            guard let components = URLComponents(string: trimmed),
                  let scheme = components.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  let host = components.host, !host.isEmpty,
                  components.user == nil, components.password == nil,
                  components.path.isEmpty || components.path == "/",
                  components.query == nil, components.fragment == nil else { return nil }
            return trimmed
        }
        guard !trimmed.contains("/"), !trimmed.contains("?"),
              !trimmed.contains("#"), !trimmed.contains("@") else { return nil }
        let parts = trimmed.split(separator: ":", maxSplits: 1)
        guard let host = parts.first, !host.isEmpty else { return nil }
        if parts.count == 2 {
            guard let port = Int(parts[1]), (1...65535).contains(port) else { return nil }
        }
        return trimmed
    }

    // MARK: - URL

    func url(for path: String, query: [P4Param] = []) -> URL {
        guard var components = URLComponents(
            url: URL(string: path, relativeTo: baseURL)?.absoluteURL ?? baseURL,
            resolvingAgainstBaseURL: false
        ) else { return baseURL }
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return components.url ?? baseURL
    }

    // MARK: - 请求

    /// GET 并解析为动态 JSON（强制回源，禁用缓存）。
    func get(_ path: String, query: [P4Param] = []) async throws -> P4JSON {
        var request = URLRequest(url: url(for: path, query: query))
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        let (data, response) = try await execute(request, path: path, query: query)
        try Self.checkSize(data, limit: Self.maxJSONBytes, label: "响应")
        return try Self.interpret(data: data, response: response, path: path)
    }

    /// POST（query 参数），与固件网页完全一致的调用方式。
    @discardableResult
    func post(_ path: String, query: [P4Param] = []) async throws -> P4JSON {
        var request = URLRequest(url: url(for: path, query: query))
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await execute(request, path: path, query: query)
        try Self.checkSize(data, limit: Self.maxJSONBytes, label: "响应")
        return try Self.interpret(data: data, response: response, path: path)
    }

    /// 下载原始数据（CSV 日志等）。
    func downloadData(_ path: String) async throws -> Data {
        var request = URLRequest(url: url(for: path))
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await execute(request, path: path, query: [])
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw P4APIError(message: "下载失败（HTTP \(http.statusCode)）")
        }
        try Self.checkSize(data, limit: Self.maxDownloadBytes, label: "下载")
        return data
    }

    /// OTA：multipart/form-data 上传应用镜像到 `/update`。
    ///
    /// 固件只接受“应用升级版” `.ino.bin`；`.ino.merged.bin` 为串口全量镜像，不可 OTA。
    ///
    /// 与普通请求的区别：
    /// - 走独立的 `P4FirmwareUploader`（长超时：弱网下一颗 1.4 MB 镜像可能要一两分钟）；
    /// - 提供字节级进度，UI 能显示“已发送 x / y”；
    /// - 丢包/设备重启导致的“响应丢失”抛 `P4UploadInterrupted`，由调用方按“可能已写入”处理。
    @discardableResult
    func uploadFirmware(
        fileName: String,
        data: Data,
        onProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> P4JSON {
        guard !data.isEmpty, data.count <= Self.maxFirmwareBytes else {
            throw P4APIError(message: "固件大小无效：需小于 8 MB")
        }
        // 文件名来自文件 App，可能包含引号/换行，直接拼接会破坏 multipart 头。
        let safeName = String(
            fileName
                .replacingOccurrences(of: "\\", with: "_")
                .replacingOccurrences(of: "\"", with: "_")
                .replacingOccurrences(of: "\r", with: "_")
                .replacingOccurrences(of: "\n", with: "_")
                .prefix(120)
        )
        let boundary = "P4CAN-" + UUID().uuidString
        var request = URLRequest(url: url(for: P4Route.otaUpload))
        request.httpMethod = "POST"
        request.timeoutInterval = 900
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        // ESP32 WebServer 不支持分块传输：显式给出长度，避免中间设备改写为 chunked。
        request.setValue("close", forHTTPHeaderField: "Connection")

        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data(
            "Content-Disposition: form-data; name=\"firmware\"; filename=\"\(safeName)\"\r\n".utf8
        ))
        body.append(Data("Content-Type: application/octet-stream\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body

        let started = Date()
        do {
            let uploader = P4FirmwareUploader()
            let (responseData, response) = try await uploader.upload(
                request: request,
                body: body,
                onProgress: onProgress
            )
            NetworkLog.shared.append(
                NetworkLogEntry(
                    id: UUID(),
                    date: Date(),
                    method: "POST",
                    path: P4Route.otaUpload,
                    query: "firmware=\(body.count)B",
                    statusCode: (response as? HTTPURLResponse)?.statusCode,
                    durationMs: Int(Date().timeIntervalSince(started) * 1000),
                    bytes: responseData.count,
                    error: nil
                )
            )
            return try Self.interpret(data: responseData, response: response, path: P4Route.otaUpload)
        } catch {
            NetworkLog.shared.append(
                NetworkLogEntry(
                    id: UUID(),
                    date: Date(),
                    method: "POST",
                    path: P4Route.otaUpload,
                    query: "firmware=\(body.count)B",
                    statusCode: nil,
                    durationMs: Int(Date().timeIntervalSince(started) * 1000),
                    bytes: 0,
                    error: (error as? P4UploadInterrupted)?.description ?? Self.friendlyText(error)
                )
            )
            throw error
        }
    }

    private static func friendlyText(_ error: Error) -> String {
        if let apiError = error as? P4APIError { return apiError.message }
        return error.localizedDescription
    }

    // MARK: - 执行与抓包

    /// 统一执行请求并写入内置网络日志（路径、耗时、状态码、字节数、错误）。
    private func execute(
        _ request: URLRequest,
        path: String,
        query: [P4Param]
    ) async throws -> (Data, URLResponse) {
        let started = Date()
        let method = request.httpMethod ?? "GET"
        let queryText = Self.redactedQuery(query)
        do {
            let (data, response) = try await session.data(for: request)
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            NetworkLog.shared.append(
                NetworkLogEntry(
                    id: UUID(),
                    date: Date(),
                    method: method,
                    path: path,
                    query: queryText,
                    statusCode: (response as? HTTPURLResponse)?.statusCode,
                    durationMs: ms,
                    bytes: data.count,
                    error: nil
                )
            )
            return (data, response)
        } catch {
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            NetworkLog.shared.append(
                NetworkLogEntry(
                    id: UUID(),
                    date: Date(),
                    method: method,
                    path: path,
                    query: queryText,
                    statusCode: nil,
                    durationMs: ms,
                    bytes: 0,
                    error: (error as? P4APIError)?.message ?? error.localizedDescription
                )
            )
            throw error
        }
    }

    // MARK: - 响应解释

    private struct ErrorBody: Decodable {
        let ok: Bool?
        let error: String?
    }

    private static func interpret(data: Data, response: URLResponse, path: String) throws -> P4JSON {
        if let body = Self.tryDecode(ErrorBody.self, from: data),
           let message = body.error,
           body.ok == false || body.ok == nil {
            throw P4APIError(message: message)
        }
        if let http = response as? HTTPURLResponse, (300...399).contains(http.statusCode) {
            throw P4APIError(message: "已阻止设备返回的重定向（HTTP \(http.statusCode)），请确认连接的仍是 P4-CAN")
        }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw P4APIError(message: "请求失败：\(path)（HTTP \(http.statusCode)）")
        }
        if data.isEmpty { return .null }
        do {
            return try JSONDecoder().decode(P4JSON.self, from: data)
        } catch {
            throw P4APIError(message: "响应解析失败：\(path)")
        }
    }

    private static func tryDecode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        guard !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// 日志脱敏：Wi-Fi 密码等只保留键名。
    private static func redactedQuery(_ query: [P4Param]) -> String {
        query.map { param in
            let key = param.key.lowercased()
            if sensitiveQueryKeys.contains(key) || key.contains("password") || key.contains("secret") {
                return "\(param.key)=***"
            }
            return "\(param.key)=\(param.value)"
        }
        .joined(separator: "&")
    }

    private static func checkSize(_ data: Data, limit: Int, label: String) throws {
        guard data.count <= limit else {
            throw P4APIError(message: "\(label)过大（\(data.count) 字节），已拒绝解析")
        }
    }
}

/// 拒绝所有 HTTP 重定向：控制请求不允许离开用户配置的设备地址。
private final class P4RedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

// MARK: - 固件上传

/// 上传在「请求体已全部发出」之后才失败（设备重启、AP 断链、读超时）。
///
/// 固件 `httpOtaFinish()` 在回 200 之后约 700 ms 就 `restartP4CanSafely()`，
/// 手机侧此时常常收不到完整响应；但**设备只有在写入成功时才会重启**，
/// 所以这种情况不能直接判失败，要交给上层去确认设备是否重启。
struct P4UploadInterrupted: Error, CustomStringConvertible {
    let bytesSent: Int
    let totalBytes: Int
    let bodyFullySent: Bool
    let underlying: Error

    var description: String {
        let pct = totalBytes > 0 ? Int(Double(bytesSent) / Double(totalBytes) * 100) : 0
        return "上传中断（已发送 \(bytesSent)/\(totalBytes) B，\(pct)%）：\(underlying.localizedDescription)"
    }
}

/// 固件上传器：`URLSession.uploadTask` + delegate，拿到字节进度与「是否已发完」。
///
/// 单独一条 session 的原因：上传镜像需要 15 分钟级超时，而状态轮询要求 8 秒级超时，
/// 混用会让弱网下的上传被状态请求的超时策略拖死。
final class P4FirmwareUploader: NSObject, @unchecked Sendable {
    private let lock = NSLock()
    private var session: URLSession?
    private var continuation: CheckedContinuation<(Data, URLResponse), Error>?
    private var buffer = Data()
    private var response: URLResponse?
    private var sentBytes = 0
    private var totalBytes = 0
    private var progressHandler: (@Sendable (Int, Int) -> Void)?
    private var finished = false

    func upload(
        request: URLRequest,
        body: Data,
        onProgress: (@Sendable (Int, Int) -> Void)?
    ) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            self.continuation = continuation
            self.progressHandler = onProgress
            self.buffer = Data()
            self.response = nil
            self.sentBytes = 0
            self.totalBytes = body.count
            self.finished = false
            lock.unlock()

            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 60
            configuration.timeoutIntervalForResource = 900
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.allowsCellularAccess = false
            configuration.waitsForConnectivity = false
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            lock.lock()
            self.session = session
            lock.unlock()
            session.uploadTask(with: request, from: body).resume()
        }
    }

    private func finish(_ result: Result<(Data, URLResponse), Error>) {
        lock.lock()
        guard !finished, let continuation else { lock.unlock(); return }
        finished = true
        self.continuation = nil
        let session = self.session
        self.session = nil
        lock.unlock()
        session?.finishTasksAndInvalidate()
        continuation.resume(with: result)
    }
}

extension P4FirmwareUploader: URLSessionDataDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        lock.lock()
        sentBytes = Int(totalBytesSent)
        let total = totalBytesExpectedToSend > 0 ? Int(totalBytesExpectedToSend) : totalBytes
        let handler = progressHandler
        lock.unlock()
        handler?(Int(totalBytesSent), total)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        lock.lock()
        buffer.append(data)
        lock.unlock()
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        lock.lock()
        self.response = response
        lock.unlock()
        completionHandler(.allow)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        lock.lock()
        let sent = sentBytes
        let total = totalBytes
        let body = buffer
        let httpResponse = response
        lock.unlock()

        if let error {
            let fullySent = total > 0 && sent >= total
            finish(.failure(P4UploadInterrupted(
                bytesSent: sent,
                totalBytes: total,
                bodyFullySent: fullySent,
                underlying: error
            )))
            return
        }
        guard let httpResponse else {
            finish(.failure(URLError(.badServerResponse)))
            return
        }
        finish(.success((body, httpResponse)))
    }
}
