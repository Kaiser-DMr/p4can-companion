import CryptoKit
import Foundation
import ImageIO

// 联网校验车型目录：每个车型 × 车漆 × 轮毂 × 视角都必须返回非空的透明 PNG；
// 同一车型同一视角下，不同车漆、不同轮毂的图片必须互不相同（否则说明代码未被识别）。
// 编译：xcrun swiftc -parse-as-library P4CANCompanion/Core/VehicleCatalog.swift build/mock/VehicleCatalogCheck.swift -o .derived/vehicle-catalog-check
// 运行：.derived/vehicle-catalog-check [版本代码 ...]，不带参数校验全部版本；全量约 5000 次请求，
// 并发过高会被特斯拉图片服务限流（HTTP 403），因此每批 4 个请求。

struct Result: Sendable {
    let label: String
    let hash: String?
    let error: String?
}

@main
struct VehicleCatalogCheck {
    static func fetch(_ url: URL, label: String) async -> Result {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = components.queryItems?.map { $0.name == "size" ? URLQueryItem(name: "size", value: "300") : $0 }
        do {
            let (data, response) = try await URLSession.shared.data(from: components.url!)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { return Result(label: label, hash: nil, error: "HTTP \(status)") }
            guard response.mimeType == "image/png" else { return Result(label: label, hash: nil, error: "类型 \(response.mimeType ?? "-")") }
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                return Result(label: label, hash: nil, error: "无法解码")
            }
            let coverage = opaqueCoverage(image)
            guard coverage > 0.03 else { return Result(label: label, hash: nil, error: String(format: "车身像素占比 %.3f", coverage)) }
            let hash = SHA256.hash(data: data).prefix(6).map { String(format: "%02x", $0) }.joined()
            return Result(label: label, hash: hash, error: nil)
        } catch {
            return Result(label: label, hash: nil, error: error.localizedDescription)
        }
    }

    static func opaqueCoverage(_ image: CGImage) -> Double {
        let w = image.width, h = image.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let p = ctx.data!.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var opaque = 0
        for i in 0..<(w * h) where p[i * 4 + 3] > 40 { opaque += 1 }
        return Double(opaque) / Double(w * h)
    }

    static func main() async {
        let only = Set(CommandLine.arguments.dropFirst())
        // 每张图另配一张「无效轮毂代码」的基准图：两者相同说明该轮毂在此视角没有素材（车轮缺失）
        var jobs: [(label: String, url: URL, baseline: String)] = []
        var baselines: [String: URL] = [:]
        for g in VehicleCatalog.generations {
            for t in g.trims where only.isEmpty || only.contains(t.code) {
                for paint in t.paints {
                    for wheel in t.wheels {
                        let appearance = VehicleAppearance(generation: g, trim: t, paint: paint, wheel: wheel)
                        let missing = VehicleOption(code: "W000", zh: "", en: "", rearUsesSide: wheel.rearUsesSide)
                        let empty = VehicleAppearance(generation: g, trim: t, paint: paint, wheel: missing)
                        for angle in VehicleAngle.allCases {
                            let view = VehicleCatalog.view(appearance, angle: angle)
                            let label = "\(t.code) \(paint.code) \(wheel.code) \(view)"
                            let baseLabel = "\(t.code) \(paint.code) W000 \(view)"
                            baselines[baseLabel] = VehicleCatalog.imageURL(empty, angle: angle)
                            jobs.append((label, VehicleCatalog.imageURL(appearance, angle: angle), baseLabel))
                        }
                    }
                }
            }
        }
        let fetches = jobs.map { ($0.label, $0.url) } + baselines.map { ($0.key, $0.value) }
        print("共 \(jobs.count) 张图片，\(baselines.count) 张基准图")
        var results: [String: Result] = [:]
        var index = 0
        while index < fetches.count {
            let batch = fetches[index..<min(index + 4, fetches.count)]
            await withTaskGroup(of: Result.self) { group in
                for job in batch { group.addTask { await fetch(job.1, label: job.0) } }
                for await r in group { results[r.label] = r }
            }
            index += batch.count
        }

        var failures = 0
        var reported = Set<String>()
        for job in jobs where reported.insert(job.label).inserted {
            if let error = results[job.label]?.error {
                print("❌ \(job.label)：\(error)")
                failures += 1
            } else if let hash = results[job.label]?.hash, hash == results[job.baseline]?.hash {
                print("❌ \(job.label)：与无轮毂基准图相同（该视角缺少轮毂素材）")
                failures += 1
            }
        }
        // 同车型同视角同轮毂：车漆之间互不相同；同车漆：轮毂之间互不相同
        for g in VehicleCatalog.generations {
            for t in g.trims where only.isEmpty || only.contains(t.code) {
                for angle in VehicleAngle.allCases {
                    let view = g.views[angle.rawValue]
                    for wheel in t.wheels {
                        let groups = Dictionary(grouping: t.paints, by: { results["\(t.code) \($0.code) \(wheel.code) \(view)"]?.hash ?? "-" })
                        for (hash, same) in groups where hash != "-" && same.count > 1 {
                            print("❌ \(t.code) \(wheel.code) \(view)：车漆 \(same.map(\.code).joined(separator: "/")) 图片相同"); failures += 1
                        }
                    }
                    for paint in t.paints {
                        let groups = Dictionary(grouping: t.wheels, by: { results["\(t.code) \(paint.code) \($0.code) \(view)"]?.hash ?? "-" })
                        for (hash, same) in groups where hash != "-" && same.count > 1 {
                            print("❌ \(t.code) \(paint.code) \(view)：轮毂 \(same.map(\.code).joined(separator: "/")) 图片相同"); failures += 1
                        }
                    }
                }
            }
        }
        print(failures == 0 ? "✅ 全部 \(jobs.count) 张图片通过" : "共 \(failures) 项失败")
        exit(failures == 0 ? 0 : 1)
    }
}
