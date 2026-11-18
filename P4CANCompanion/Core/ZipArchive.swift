import Foundation

/// 极简 ZIP 打包（store 模式，不压缩）。
///
/// 为什么自己写：iOS 没有公开的 zip 写入 API，`AppleArchive` 产出的 .aea 在 Windows
/// 和手机上都不好直接打开。诊断包只有几十 KB，不压缩完全够用，换来的是
/// 系统「文件」、微信、邮件附件都能直接解压。
enum ZipArchive {

    /// 生成 zip。`entries` 的 name 用 `/` 分隔目录；同名会覆盖（按最后一次写入）。
    static func make(entries: [(name: String, data: Data)], date: Date = Date()) -> Data {
        var output = Data()
        var central = Data()
        var seen = Set<String>()
        let (time, day) = dosDateTime(date)

        for entry in entries.reversed() where !seen.contains(entry.name) {
            seen.insert(entry.name)
            let nameBytes = Array(entry.name.utf8)
            let crc = crc32(entry.data)
            let offset = UInt32(output.count)

            // 本地文件头
            output.append(uint32: 0x0403_4b50)
            output.append(uint16: 20)            // version needed
            output.append(uint16: 0x0800)        // UTF-8 文件名
            output.append(uint16: 0)             // store
            output.append(uint16: time)
            output.append(uint16: day)
            output.append(uint32: crc)
            output.append(uint32: UInt32(entry.data.count))
            output.append(uint32: UInt32(entry.data.count))
            output.append(uint16: UInt16(nameBytes.count))
            output.append(uint16: 0)             // extra
            output.append(contentsOf: nameBytes)
            output.append(entry.data)

            // 中央目录项
            central.append(uint32: 0x0201_4b50)
            central.append(uint16: 20)           // version made by
            central.append(uint16: 20)           // version needed
            central.append(uint16: 0x0800)
            central.append(uint16: 0)
            central.append(uint16: time)
            central.append(uint16: day)
            central.append(uint32: crc)
            central.append(uint32: UInt32(entry.data.count))
            central.append(uint32: UInt32(entry.data.count))
            central.append(uint16: UInt16(nameBytes.count))
            central.append(uint16: 0)
            central.append(uint16: 0)
            central.append(uint16: 0)            // disk
            central.append(uint16: 0)            // internal attrs
            central.append(uint32: 0)            // external attrs
            central.append(uint32: offset)
            central.append(contentsOf: nameBytes)
        }

        let centralOffset = UInt32(output.count)
        output.append(central)
        let count = UInt16(seen.count)

        // EOCD
        output.append(uint32: 0x0605_4b50)
        output.append(uint16: 0)
        output.append(uint16: 0)
        output.append(uint16: count)
        output.append(uint16: count)
        output.append(uint32: UInt32(central.count))
        output.append(uint32: centralOffset)
        output.append(uint16: 0)
        return output
    }

    // MARK: - CRC32

    private static let crcTable: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = (value & 1) == 1 ? (0xEDB8_8320 ^ (value >> 1)) : (value >> 1)
        }
        return value
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }

    // MARK: - DOS 时间

    private static func dosDateTime(_ date: Date) -> (time: UInt16, day: UInt16) {
        let calendar = Calendar(identifier: .gregorian)
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = max((parts.year ?? 2026) - 1980, 0)
        let month = parts.month ?? 1
        let day = parts.day ?? 1
        let hour = parts.hour ?? 0
        let minute = parts.minute ?? 0
        let second = (parts.second ?? 0) / 2
        let time = UInt16((hour << 11) | (minute << 5) | second)
        let dateValue = UInt16((year << 9) | (month << 5) | day)
        return (time, dateValue)
    }
}

private extension Data {
    mutating func append(uint16 value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func append(uint32 value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}
