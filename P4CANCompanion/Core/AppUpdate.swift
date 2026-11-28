import Foundation

/// 主仓库发布的 App 版本。
struct AppRelease: Equatable, Sendable {
    let tag: String
    let version: [Int]
    let name: String
    let url: URL
}

/// 查询主仓库 GitHub Release 上的最新 App 版本。
enum AppUpdate {
    static let releasesURL = URL(string: "https://api.github.com/repos/Kaiser-DMr/p4can-companion/releases?per_page=30")!

    /// `v3.60` / `3.60` → `[3, 60]`；固件等其他形式的标签返回 nil。
    static func version(_ text: String) -> [Int]? {
        var body = Substring(text)
        if body.first == "v" || body.first == "V" { body = body.dropFirst() }
        var parts: [Int] = []
        for part in body.split(separator: ".", omittingEmptySubsequences: false) {
            guard !part.isEmpty, part.allSatisfy({ ("0"..."9").contains($0) }), let number = Int(part) else { return nil }
            parts.append(number)
        }
        return parts.isEmpty ? nil : parts
    }

    /// 逐段比较，缺少的段按 0 处理（3.6 与 3.6.0 相同）。
    static func isNewer(_ candidate: [Int], than current: [Int]) -> Bool {
        for index in 0..<max(candidate.count, current.count) {
            let lhs = index < candidate.count ? candidate[index] : 0
            let rhs = index < current.count ? current[index] : 0
            if lhs != rhs { return lhs > rhs }
        }
        return false
    }

    private struct ReleaseDTO: Decodable {
        let tag_name: String
        let name: String?
        let html_url: URL
        let draft: Bool
        let prerelease: Bool
    }

    /// 从 Release 列表中取版本号最高的正式 App 版本（跳过草稿、预发布与固件标签）。
    static func latest(fromJSON data: Data) throws -> AppRelease? {
        try JSONDecoder().decode([ReleaseDTO].self, from: data)
            .filter { !$0.draft && !$0.prerelease }
            .compactMap { dto in
                version(dto.tag_name).map {
                    AppRelease(tag: dto.tag_name, version: $0, name: dto.name ?? dto.tag_name, url: dto.html_url)
                }
            }
            .max { isNewer($1.version, than: $0.version) }
    }

    static func fetchLatest(session: URLSession = .shared) async throws -> AppRelease? {
        var request = URLRequest(url: releasesURL, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw URLError(.badServerResponse) }
        return try latest(fromJSON: data)
    }
}
