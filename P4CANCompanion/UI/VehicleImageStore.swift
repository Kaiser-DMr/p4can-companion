import CryptoKit
import UIKit

/// 已裁到车身范围（含渐隐边距）的配置器车辆图。
struct VehicleImage {
    let image: UIImage
}

/// 下载并缓存特斯拉配置器车辆图片：内存缓存 + Caches 目录磁盘缓存，同一 URL 并发请求只下载一次。
/// 磁盘只保存裁剪、渐隐后的成品图，之后启动直接读取，不再重复下载和裁剪。
@MainActor
final class VehicleImageStore {
    static let shared = VehicleImageStore()

    /// 解码后的车图每张约 2 MB；在「车辆外观」里连续切换车漆、轮毂时限制常驻数量。
    private let memory: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 24
        return cache
    }()
    private var inFlight: [URL: Task<VehicleImage, Error>] = [:]
    private let directory: URL
    private let session: URLSession

    private init() {
        directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VehicleImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config)
        let directory = directory
        // 旧版本缓存的是未裁剪原图，已不再读取
        Task.detached(priority: .utility) {
            let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for file in files where !file.lastPathComponent.hasSuffix(Self.fileSuffix) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    /// 内存或磁盘里已有的成品车图。读文件只建立延迟解码的 `UIImage`，可以在主线程同步调用。
    func cached(_ url: URL) -> VehicleImage? {
        if let hit = memory.object(forKey: url as NSURL) { return VehicleImage(image: hit) }
        guard let image = UIImage(contentsOfFile: file(for: url).path) else { return nil }
        memory.setObject(image, forKey: url as NSURL)
        return VehicleImage(image: image)
    }

    func image(for url: URL) async throws -> VehicleImage {
        if let hit = cached(url) { return hit }
        return try await download(url).value
    }

    /// 后台预取同一外观的其余视角，挡位切换时不必等待下载。
    func prefetch(_ urls: [URL]) {
        for url in Set(urls) where cached(url) == nil {
            _ = download(url)
        }
    }

    /// 同一 URL 只建立一个下载任务；完成后写入内存缓存。
    private func download(_ url: URL) -> Task<VehicleImage, Error> {
        if let task = inFlight[url] { return task }
        let file = file(for: url)
        let session = session
        let task = Task.detached(priority: .userInitiated) { () throws -> VehicleImage in
            var request = URLRequest(url: url)
            request.setValue("image/png,image/*", forHTTPHeaderField: "Accept")
            let (body, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { throw VehicleImageError.http(status) }
            guard (response.mimeType ?? "").hasPrefix("image/") else { throw VehicleImageError.notImage }
            let image = UIImage(cgImage: try VehicleImageProcessing.cropToBody(body))
            try? image.pngData()?.write(to: file, options: .atomic)
            return VehicleImage(image: image)
        }
        inFlight[url] = task
        Task { @MainActor in
            if let result = try? await task.value {
                memory.setObject(result.image, forKey: url as NSURL)
            }
            inFlight[url] = nil
        }
        return task
    }

    private nonisolated static let fileSuffix = ".v2.png"

    private func file(for url: URL) -> URL {
        directory.appendingPathComponent(Self.fileName(url))
    }

    private nonisolated static func fileName(_ url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + fileSuffix
    }
}
