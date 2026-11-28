// 更新检查逻辑校验：版本解析与比较、Release 列表筛选、联网读取主仓库最新 App 版本。
// 构建：xcrun swiftc -parse-as-library P4CANCompanion/Core/AppUpdate.swift build/mock/AppUpdateCheck.swift -o .derived/app-update-check
import Foundation

@main
struct AppUpdateCheck {
    static var failures = 0

    static func expect(_ condition: Bool, _ message: String) {
        print("\(condition ? "PASS" : "FAIL") \(message)")
        if !condition { failures += 1 }
    }

    static func main() async {
        expect(AppUpdate.version("v3.60") == [3, 60], "v3.60 解析为 [3, 60]")
        expect(AppUpdate.version("3.61.1") == [3, 61, 1], "3.61.1 解析为 [3, 61, 1]")
        expect(AppUpdate.version("fw-3.35.3-strobe1") == nil, "固件标签不算 App 版本")
        expect(AppUpdate.version("v3.60-ui") == nil, "带后缀的标签不算正式版本")
        expect(AppUpdate.version("v+3.60") == nil, "带符号的标签无效")
        expect(AppUpdate.isNewer([3, 61], than: [3, 60]), "3.61 比 3.60 新")
        expect(!AppUpdate.isNewer([3, 60], than: [3, 60]), "相同版本不算新")
        expect(!AppUpdate.isNewer([3, 6], than: [3, 6, 0]), "3.6 与 3.6.0 相同")
        expect(AppUpdate.isNewer([4], than: [3, 99]), "4 比 3.99 新")
        expect(!AppUpdate.isNewer([3, 57], than: [3, 60]), "3.57 不比 3.60 新")

        let sample = """
        [
          {"tag_name":"fw-3.35.3-strobe1","name":"固件","html_url":"https://example.com/fw","draft":false,"prerelease":false},
          {"tag_name":"v3.70","name":"预发布","html_url":"https://example.com/pre","draft":false,"prerelease":true},
          {"tag_name":"v3.65","name":"草稿","html_url":"https://example.com/draft","draft":true,"prerelease":false},
          {"tag_name":"v3.57","name":"旧版","html_url":"https://example.com/357","draft":false,"prerelease":false},
          {"tag_name":"v3.61","name":"新版","html_url":"https://example.com/361","draft":false,"prerelease":false}
        ]
        """
        let picked = try? AppUpdate.latest(fromJSON: Data(sample.utf8))
        expect(picked?.tag == "v3.61", "跳过固件、预发布、草稿后取最高版本 v3.61（实际 \(picked?.tag ?? "nil")）")

        do {
            let live = try await AppUpdate.fetchLatest()
            expect(live != nil, "主仓库最新 App 版本：\(live.map { "\($0.tag) \($0.url)" } ?? "nil")")
        } catch {
            expect(false, "联网读取主仓库 Release 失败：\(error)")
        }

        print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
