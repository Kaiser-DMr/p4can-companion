// 生成实时活动内置车图：每个车型 × 车漆 × 轮毂下载一张配置器侧视图，裁到车身、缩到 240 px 宽，
// 写入 P4CANWidget/Assets.xcassets/ActivityVehicles（有损压缩），已存在的跳过，可中断后续跑。
// 构建：xcrun swiftc -parse-as-library P4CANCompanion/Core/VehicleCatalog.swift P4CANCompanion/Core/VehicleImageProcessing.swift build/tools/make_activity_vehicles.swift -o .derived/make-activity-vehicles
// 运行（在仓库根目录）：./.derived/make-activity-vehicles
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

@main
struct MakeActivityVehicles {
    static let width = 240
    static let folder = URL(fileURLWithPath: "P4CANWidget/Assets.xcassets/ActivityVehicles", isDirectory: true)

    /// 每个车型 × 车漆 × 轮毂取第一个同时提供该车漆与轮毂的版本出图
    static func variants() -> [VehicleAppearance] {
        var seen = Set<String>()
        var result: [VehicleAppearance] = []
        for generation in VehicleCatalog.generations {
            for trim in generation.trims {
                for paint in trim.paints {
                    for wheel in trim.wheels {
                        let appearance = VehicleAppearance(generation: generation, trim: trim, paint: paint, wheel: wheel)
                        if seen.insert(VehicleCatalog.activityAssetName(appearance)).inserted { result.append(appearance) }
                    }
                }
            }
        }
        return result
    }

    static func resize(_ image: CGImage) throws -> CGImage {
        let height = max(1, Int((Double(image.height) * Double(width) / Double(image.width)).rounded()))
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw VehicleImageError.notImage }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let result = ctx.makeImage() else { throw VehicleImageError.notImage }
        return result
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw VehicleImageError.notImage
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw VehicleImageError.notImage }
    }

    static func make(_ appearance: VehicleAppearance) async throws -> Bool {
        let name = VehicleCatalog.activityAssetName(appearance)
        let set = folder.appendingPathComponent(name + ".imageset", isDirectory: true)
        let png = set.appendingPathComponent(name + ".png")
        if FileManager.default.fileExists(atPath: png.path) { return false }
        let url = VehicleCatalog.imageURL(appearance, angle: .side)
        let (data, response) = try await URLSession.shared.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw VehicleImageError.http(status) }
        let image = try resize(VehicleImageProcessing.cropToBody(data))
        try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
        try writePNG(image, to: png)
        let contents = """
        {
          "images" : [
            {
              "filename" : "\(name).png",
              "idiom" : "universal"
            }
          ],
          "info" : {
            "author" : "xcode",
            "version" : 1
          },
          "properties" : {
            "compression-type" : "lossy"
          }
        }

        """
        try contents.write(to: set.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
        return true
    }

    static func main() async {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let folderContents = folder.appendingPathComponent("Contents.json")
        if !FileManager.default.fileExists(atPath: folderContents.path) {
            try? "{\n  \"info\" : {\n    \"author\" : \"xcode\",\n    \"version\" : 1\n  }\n}\n"
                .write(to: folderContents, atomically: true, encoding: .utf8)
        }
        let all = variants()
        var made = 0, skipped = 0, failed: [String] = []
        // 每批 4 个：并发过高会被配置器接口限流（HTTP 403）
        for start in stride(from: 0, to: all.count, by: 4) {
            let batch = Array(all[start..<min(start + 4, all.count)])
            await withTaskGroup(of: (String, Result<Bool, Error>).self) { group in
                for appearance in batch {
                    group.addTask {
                        let name = VehicleCatalog.activityAssetName(appearance)
                        do { return (name, .success(try await make(appearance))) } catch { return (name, .failure(error)) }
                    }
                }
                for await (name, result) in group {
                    switch result {
                    case .success(true): made += 1
                    case .success(false): skipped += 1
                    case .failure(let error): failed.append("\(name): \(error)")
                    }
                }
            }
        }
        print("{\"total\":\(all.count),\"made\":\(made),\"skipped\":\(skipped),\"failed\":\(failed.count)}")
        failed.forEach { print("FAIL \($0)") }
        exit(failed.isEmpty ? 0 : 1)
    }
}
