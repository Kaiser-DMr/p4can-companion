// 下载指定车型 × 轮毂三个视角的配置器图，叠在亮绿底上保存，用于人工检查轮毂是否缺失。
// 构建：xcrun swiftc -parse-as-library P4CANCompanion/Core/VehicleCatalog.swift P4CANCompanion/Core/VehicleImageProcessing.swift build/mock/WheelViewProbe.swift -o .derived/wheel-view-probe
// 运行：./.derived/wheel-view-probe <车型 id> <轮毂代码> [输出目录]
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

@main
struct WheelViewProbe {
    static func main() async {
        let args = CommandLine.arguments
        guard args.count >= 3, let generation = VehicleCatalog.generation(id: args[1]),
              let trim = generation.trims.first(where: { $0.wheels.contains { $0.code == args[2] } }),
              let wheel = trim.wheels.first(where: { $0.code == args[2] }) else {
            print("{\"status\":\"error\",\"message\":\"unknown generation or wheel\"}")
            exit(2)
        }
        let out = URL(fileURLWithPath: args.count > 3 ? args[3] : ".derived/shots", isDirectory: true)
        let appearance = VehicleAppearance(generation: generation, trim: trim, paint: trim.paints[0], wheel: wheel)
        for angle in VehicleAngle.allCases {
            let url = VehicleCatalog.imageURL(appearance, angle: angle)
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard status == 200 else { throw VehicleImageError.http(status) }
                let image = try VehicleImageProcessing.cropToBody(data)
                let file = out.appendingPathComponent("probe-\(args[1])-\(args[2])-\(angle).png")
                guard let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil) else { continue }
                CGImageDestinationAddImage(destination, image, nil)
                CGImageDestinationFinalize(destination)
                print("\(angle) \(VehicleCatalog.view(appearance, angle: angle)) \(file.path)")
            } catch {
                print("\(angle) error \(error)")
            }
        }
    }
}
