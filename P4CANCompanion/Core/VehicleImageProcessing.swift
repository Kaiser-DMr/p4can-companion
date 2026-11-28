import CoreGraphics
import Foundation
import ImageIO

enum VehicleImageError: Error {
    case http(Int)
    case notImage
    case emptyImage
}

/// 配置器车图后处理：按透明度找出车身范围后裁剪，边距内渐隐。
/// App 下载车图与生成实时活动内置车图共用这一套规则，不同视角、不同来源的图按同样方式对齐。
enum VehicleImageProcessing {
    static func cropToBody(_ data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw VehicleImageError.notImage }
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
        return fadeEdges(cropped, band: pad)
    }

    /// 边距内的透明度从车身向外渐隐到 0：官方图自带的地面阴影在裁剪边缘不会留下硬边。
    private static func fadeEdges(_ image: CGImage, band: Double) -> CGImage {
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
