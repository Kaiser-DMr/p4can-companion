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
    static let lightStrobe = "/api/lights/strobe"
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
        self.session = URLSession(configuration: configuration)
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
        return try Self.interpret(data: data, response: response, path: path)
    }

    /// POST（query 参数），与固件网页完全一致的调用方式。
    @discardableResult
    func post(_ path: String, query: [P4Param] = []) async throws -> P4JSON {
        var request = URLRequest(url: url(for: path, query: query))
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await execute(request, path: path, query: query)
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
        return data
    }

    /// OTA：multipart/form-data 上传应用镜像到 `/update`。
    ///
    /// 固件只接受“应用升级版” `.ino.bin`；`.ino.merged.bin` 为串口全量镜像，不可 OTA。
    @discardableResult
    func uploadFirmware(fileName: String, data: Data) async throws -> P4JSON {
        let boundary = "P4CAN-" + UUID().uuidString
        var request = URLRequest(url: url(for: P4Route.otaUpload))
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data(
            "Content-Disposition: form-data; name=\"firmware\"; filename=\"\(fileName)\"\r\n".utf8
        ))
        body.append(Data("Content-Type: application/octet-stream\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body

        let (responseData, response) = try await execute(request, path: P4Route.otaUpload, query: [])
        return try Self.interpret(data: responseData, response: response, path: P4Route.otaUpload)
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
        let queryText = query.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
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
}
