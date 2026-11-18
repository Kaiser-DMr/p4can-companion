import CryptoKit
import Foundation

/// 一个选中/刷写过的固件包：名称、大小、SHA-256 与刷写时间。
///
/// 用途是“别再刷错包”：刷之前能看到这次的包和上次刷的是不是同一个，
/// 刷完留一条记录，出问题时也能对上号。
struct FirmwarePackage: Codable, Equatable, Sendable {
    let name: String
    let size: Int
    /// 完整 SHA-256（小写 hex）；展示时只取前 12 位。
    let sha256: String
    let flashedAt: Date
    /// 刷写时设备自报的固件版本（刷完后设备会重启，这个值来自刷前）。
    let deviceFirmware: String

    /// 展示用的短 SHA：12 位足够人工核对，又不至于撑爆一行。
    var shortSHA: String { String(sha256.prefix(12)) }

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}

/// 固件包指纹与「上次刷写」记录的本地存储。
enum FirmwarePackageStore {
    private static let key = "p4can.ota.lastFirmware"

    /// 计算 SHA-256（小写 hex）。
    static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func load() -> FirmwarePackage? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(FirmwarePackage.self, from: data)
    }

    static func save(_ package: FirmwarePackage) {
        guard let data = try? JSONEncoder().encode(package) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
