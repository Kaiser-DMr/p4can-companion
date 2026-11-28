import CryptoKit
import UIKit

/// 已裁到车身范围（含渐隐边距）的配置器车辆图。
struct VehicleImage {
    let image: UIImage
}

enum VehicleImageError: Error {
    case http(Int)
    case notImage
    case emptyImage
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
            let image = try Self.decode(body)
            try? image.image.pngData()?.write(to: file, options: .atomic)
            return image
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

    /// 实时活动用的车图：缩到 360 px 宽写入 App Group 共享目录，返回文件名（不含扩展名）。
    /// 共享目录只保留当前这一张；没有 App Group 或下载失败时返回 nil。
    func exportSharedThumbnail(for url: URL) async -> String? {
        let key = String(Self.fileName(url).dropLast(Self.fileSuffix.count))
        guard let directory = SharedVehicleImage.directory, let target = SharedVehicleImage.file(key) else { return nil }
        if FileManager.default.fileExists(atPath: target.path) { return key }
        guard let source = try? await image(for: url) else { return nil }
        let image = source.image
        let written = await Task.detached(priority: .utility) { () -> Bool in
            let width = min(360, image.size.width)
            let size = CGSize(width: width, height: (image.size.height * width / image.size.width).rounded())
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let thumbnail = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }
            guard let data = thumbnail.pngData() else { return false }
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            guard (try? data.write(to: target, options: .atomic)) != nil else { return false }
            let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.lastPathComponent != target.lastPathComponent {
                try? FileManager.default.removeItem(at: file)
            }
            return true
        }.value
        return written ? key : nil
    }

    private nonisolated static let fileSuffix = ".v2.png"

    private func file(for url: URL) -> URL {
        directory.appendingPathComponent(Self.fileName(url))
    }

    private nonisolated static func fileName(_ url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + fileSuffix
    }

    /// 解码图片并按透明度找出车身范围后裁剪，不同视角因此能按同一规则对齐和缩放。
    private nonisolated static func decode(_ data: Data) throws -> VehicleImage {
        guard let image = UIImage(data: data), let cg = image.cgImage else { throw VehicleImageError.notImage }
        let sampleW = 480
        let sampleH = max(1, Int(Double(cg.height) * Double(sampleW) / Double(cg.width)))
        guard let ctx = CGContext(data: nil, width: sampleW, height: sampleH, bitsPerComponent: 8,
                                  bytesPerRow: sampleW * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let raw = ctx.data else { throw VehicleImageError.notImage }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: sampleW, height: sampleH))
        let pixels = raw.bindMemory(to: UInt8.self, capacity: sampleW * sampleH * 4)
        var minX = sampleW, maxX = -1, minRow = sampleH, maxRow = -1
        for row in 0..<sampleH {
            // 阈值高于官方图自带的半透明地面阴影，只统计车身
            for x in 0..<sampleW where pixels[(row * sampleW + x) * 4 + 3] > 160 {
                minX = min(minX, x); maxX = max(maxX, x)
                minRow = min(minRow, row); maxRow = max(maxRow, row)
            }
        }
        guard maxX >= minX, maxRow >= minRow else { throw VehicleImageError.emptyImage }
        // 位图内存第 0 行对应图片顶部；换算回原图像素，四周留少量边距
        let scale = Double(cg.width) / Double(sampleW)
        let body = CGRect(x: Double(minX) * scale, y: Double(minRow) * scale,
                          width: Double(maxX - minX + 1) * scale, height: Double(maxRow - minRow + 1) * scale)
        let pad = body.width * 0.025
        let crop = body.insetBy(dx: -pad, dy: -pad)
            .intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height)).integral
        guard let cropped = cg.cropping(to: crop) else { throw VehicleImageError.emptyImage }
        return VehicleImage(image: UIImage(cgImage: fadeEdges(cropped, band: pad)))
    }

    /// 边距内的透明度从车身向外渐隐到 0：官方图自带的地面阴影在裁剪边缘不会留下硬边。
    private nonisolated static func fadeEdges(_ image: CGImage, band: Double) -> CGImage {
        let w = image.width, h = image.height
        guard band >= 1,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setBlendMode(.destinationOut)
        let colors = [CGColor(gray: 0, alpha: 1), CGColor(gray: 0, alpha: 0)] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(), colors: colors, locations: [0, 1]) else { return image }
        let edges: [(CGPoint, CGPoint)] = [
            (CGPoint(x: 0, y: 0), CGPoint(x: band, y: 0)),
            (CGPoint(x: Double(w), y: 0), CGPoint(x: Double(w) - band, y: 0)),
            (CGPoint(x: 0, y: 0), CGPoint(x: 0, y: band)),
            (CGPoint(x: 0, y: Double(h)), CGPoint(x: 0, y: Double(h) - band)),
        ]
        for (start, end) in edges {
            ctx.saveGState()
            let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                              width: start.x == end.x ? Double(w) : band, height: start.y == end.y ? Double(h) : band)
            ctx.clip(to: rect)
            ctx.drawLinearGradient(gradient, start: start, end: end, options: [])
            ctx.restoreGState()
        }
        return ctx.makeImage() ?? image
    }
}
