# 本地联调（Mock 设备）

固件不在手边时，用 mock 服务模拟 P4-CAN 的真实接口，验证 App 的数据层与 UI。

## 1. 启动 mock

```bash
cd P4CAN-Companion/build/mock
python3 mock_p4can.py          # http://127.0.0.1:8080
```

已实现接口（字段与开源固件 `web_api.h` 一致）：
- `GET /api/snapshot?groups=home-fast[&slow=1]`（nag / blink / summon / cantraffic / r79 + slow）
- `GET /api/profile/status`、`/api/features/status`、`/api/nag/config`、`/api/s3xy/stats`
- `GET /api/wifi/status`、`/api/ota/status`、`/api/system/stats`、`/api/ulc/stats`、`/api/summon/stats`、
  `/api/blinkA/stats`、`/api/r79/stats`、`/api/r79/ap-control/stats`、`/api/country/stats`、
  `/api/pedalmap/stats`、`/api/continuous-ap/config`、`/api/driver-monitoring/config`、
  `/api/isa-suppression/config`、`/api/vision-control/stats`、`/api/researchcapture/stats`、`/api/das/stats` 等
- `POST /api/nag/update?enabled=0|1`、`/api/nag/mode?m=0|1|3|7`、`/api/blinkA/enable|disable`、
  `/api/summon/tlssc-enable|disable`、`/api/features/lab?enabled=` 等（会更新状态，GET 可见）

## 2. 指向 mock 运行

App 支持两种覆盖方式（无需改代码）：

| 方式 | 用法 |
|---|---|
| 启动环境变量 | `SIMCTL_CHILD_P4CAN_HOST=127.0.0.1:8080`（模拟器） |
| 界面输入 | 系统 → 连接 → 设备地址填 `127.0.0.1:8080` |

同时支持 `SIMCTL_CHILD_P4CAN_TAB=0..3` 指定启动标签页（0 状态 / 1 功能 / 2 蓝牙 / 3 系统）。

## 3. 一键脚本

```bash
cd P4CAN-Companion/build/mock
chmod +x run_on_simulator.sh
./run_on_simulator.sh 0     # 状态页
./run_on_simulator.sh 2     # 蓝牙页
```

脚本会：起 mock → 启动模拟器 → 安装 Debug 构建 → 以 mock 地址启动 → 截图到 `/tmp`。

> 前提：Xcode 已安装 iOS 模拟器运行时（Xcode → Settings → Components，或
> `sudo xcodebuild -downloadPlatform iOS`）。本机当前未安装运行时，故未能在此环境截图。

## 4. 数据层回归（无需模拟器）

```bash
cd P4CAN-Companion
xcrun swiftc -O \
  P4CANCompanion/Core/P4JSON.swift \
  P4CANCompanion/Core/Models.swift \
  P4CANCompanion/Core/P4APIClient.swift \
  P4CANCompanion/Core/NetworkLog.swift \
  build/mock/CoreSmokeTest.swift -o /tmp/p4coretest
/tmp/p4coretest
```

覆盖：分组快照解析、三路总线（BODY/CHASSIS/PARTY）、能力位、S3XY 设备/扫描、写接口
（NAG 开关与模式、S3XY 动作/配对）、不可达主机错误、内置网络日志。
