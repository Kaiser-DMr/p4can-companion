import Foundation

// 本机联调测试：直接编译 App 的 Core 源码（P4JSON / Models / P4APIClient / NetworkLog），
// 对 127.0.0.1:8080 的固件 mock 做真实 HTTP 往返与控制接口验证。

@main
struct CoreSmokeTest {
    static func main() async {
        let client = P4APIClient(host: "127.0.0.1:8080")
        var failures = 0

        func check(_ name: String, _ condition: Bool, _ detail: String = "") {
            print(condition ? "  ✅ \(name) \(detail)" : "  ❌ \(name) \(detail)")
            if !condition { failures += 1 }
        }

        print("== 1. 快照分组（home-fast + slow）==")
        do {
            let snapshot = try await client.get(
                "/api/snapshot",
                query: [P4Param("groups", "home-fast"), P4Param("slow", "1")]
            )
            let fast = snapshot["fast"]?.objectValue ?? [:]
            let slow = snapshot["slow"]?.objectValue ?? [:]
            check("fast 组数量 = 5", fast.count == 5, "实际 \(fast.count): \(fast.keys.sorted())")
            check("slow 组数量 = 5", slow.count == 5, "实际 \(slow.count)")
            let gear = fast["r79"]?["gearName"]?.stringValue
            check("r79.gearName", gear == "D", "值 \(gear ?? "nil")")
            let torque = fast["nag"]?["torque"]?.doubleValue
            check("nag.torque 可解析", abs((torque ?? 0) - 1.35) < 0.001, "值 \(torque ?? -1)")
        } catch {
            check("快照请求", false, "\(error)")
        }

        print("== 2. 车型与三路总线 ==")
        do {
            let profile = try await client.get("/api/profile/status")
            let traffic = try await client.get("/api/snapshot", query: [P4Param("groups", "home-fast")])
            let buses = CanBusResolver.resolve(
                traffic: traffic["fast"]?["cantraffic"]?.objectValue ?? [:],
                profile: profile.objectValue ?? [:]
            )
            check("解析出 3 路总线", buses.count == 3, "\(buses.map(\.displayName))")
            let names = buses.map(\.codeName)
            check("BODY / CHASSIS / PARTY", names == ["BODY", "CHASSIS", "PARTY"], "\(names)")
            check("状态解析为 RUNNING", buses.allSatisfy { $0.stateText == "RUNNING" })
            check("CAN2 Bus-Off 计数 = 1", buses[1].busOff == 1, "值 \(buses[1].busOff ?? -1)")
            check("角色映射 canA=BODY", buses[0].roleName == "BODY", buses[0].displayName)
            check("总线路数 canBusCount=3",
                  traffic["fast"]?["cantraffic"]?["canBusCount"]?.intValue == 3)
            for bus in buses {
                print("     \(bus.displayName) 状态=\(bus.stateText) 收=\(bus.rxCount ?? 0) 发=\(bus.txAccepted ?? 0)")
            }
        } catch {
            check("总线解析", false, "\(error)")
        }

        print("== 3. 能力位与功能配置 ==")
        do {
            let features = try await client.get("/api/features/status")
            check("lab 开启", features["lab"]?.boolValue == true)
            check("nagSupported", features["nagSupported"]?.boolValue == true)
            check("advancedEapSupported", features["advancedEapSupported"]?.boolValue == true)
            let nag = try await client.get("/api/nag/config")
            let mode = nag["mode"]?.intValue ?? -1
            check("NAG mode 合法 (0/1/3/7)", [0, 1, 3, 7].contains(mode), "当前 \(mode)")
            check("NAG 参数可读 method", nag["method"]?.intValue == 0)
        } catch {
            check("功能配置", false, "\(error)")
        }

        print("== 4. S3XY 设备与扫描结果 ==")
        do {
            let stats = try await client.get("/api/s3xy/stats")
            let devices = S3XYDevice.devices(from: stats)
            let scans = S3XYScanResult.results(from: stats)
            check("设备数 = 2", devices.count == 2, "\(devices.map(\.name))")
            check("槽位 id 解析", devices.first?.slot == 1)
            check("双击动作标签", devices.first?.doubleLabel == "TLSSC Toggle")
            check("扫描结果 = 1", scans.count == 1, scans.first?.address ?? "nil")
        } catch {
            check("S3XY", false, "\(error)")
        }

        print("== 5. 写接口（query 参数）==")
        do {
            _ = try await client.post("/api/nag/update", query: [P4Param("enabled", "0")])
            let after = try await client.get("/api/nag/config")
            check("关闭 NAG 生效", after["enabled"]?.boolValue == false)
            _ = try await client.post("/api/nag/update", query: [P4Param("enabled", "1")])
            let restored = try await client.get("/api/nag/config")
            check("恢复 NAG 生效", restored["enabled"]?.boolValue == true)

            _ = try await client.post("/api/nag/mode", query: [P4Param("m", "0")])
            let modeAfter = try await client.get("/api/nag/config")
            check("切换 Mode A 生效", modeAfter["mode"]?.intValue == 0)
            // 恢复 Mode H，保证脚本可重复运行
            _ = try await client.post("/api/nag/mode", query: [P4Param("m", "7")])

            _ = try await client.post("/api/s3xy/device/action", query: [
                P4Param("id", "1"), P4Param("gesture", "single"), P4Param("action", "left_blinker"),
            ])
            _ = try await client.post("/api/s3xy/pair", query: [P4Param("address", "AA:BB:CC:77:88:99")])
            check("S3XY 动作/配对请求返回 ok", true)
        } catch {
            check("写接口", false, "\(error)")
        }

        print("== 5b. 日志导出（CAN 错误 JSON）==")
        do {
            let data = try await client.downloadData("/api/system/can-errors.json")
            let json = try JSONDecoder().decode(P4JSON.self, from: data)
            check("CAN 错误 JSON schemaVersion = 1", json["schemaVersion"]?.intValue == 1,
                  "值 \(json["schemaVersion"]?.intValue.map(String.init) ?? "nil")")
            check("CAN 错误 JSON 含三路总线", json["buses"]?.arrayValue?.count == 3)
        } catch {
            check("CAN 错误 JSON 下载", false, "\(error)")
        }

        print("== 6. 错误处理 ==")
        do {
            let bad = P4APIClient(host: "127.0.0.1:65531")
            _ = try await bad.get("/api/system/stats")
            check("不可达端口应报错", false, "竟然成功了")
        } catch {
            check("不可达端口抛错", true, "→ \(P4APIClientErrorText(error))")
        }

        print("== 7. 内置网络日志 ==")
        let logs = NetworkLog.shared.snapshot()
        check("已记录请求", logs.count >= 8, "\(logs.count) 条")
        if let latest = logs.first {
            check("日志字段完整", !latest.path.isEmpty && latest.durationMs >= 0,
                  "\(latest.method) \(latest.path) \(latest.statusCode ?? -1) \(latest.durationMs)ms \(latest.bytes)B")
        }

        print("")
        print(failures == 0 ? "ALL CHECKS PASSED（\(logs.count) 条请求记录）" : "FAILED: \(failures) 项")
        exit(failures == 0 ? 0 : 1)
    }

    static func P4APIClientErrorText(_ error: Error) -> String {
        if let api = error as? P4APIError { return api.message }
        return (error as NSError).localizedDescription
    }
}
