# P4管家

P4-CAN Universal（ESP32-P4 车载 CAN 控制器）的原生 iOS 控制台。UIKit + SwiftUI + SnapKit 混合实现，不是网页套壳。

![平台](https://img.shields.io/badge/platform-iOS%2017%2B%20%7C%20macOS%2014%2B-blue)
![版本](https://img.shields.io/badge/version-3.16%20(37)-green)

**下载：** [Releases](https://github.com/Kaiser-DMr/p4can-companion/releases) —— `P4CAN-Companion-v3.20-adhoc.ipa`（iPhone，需自签）/ `P4CAN-Companion-mac-v3.20.zip`（Mac 解压即用）

## 功能

| 模块 | 内容 |
|---|---|
| **状态** | 设备在线/固件/内存、三路 CAN（BODY / CHASSIS / PARTY）收发与 Bus-Off、扭矩趋势、电池（固件提供才显示）、锁屏与灵动岛实时活动 |
| **功能** | 固件功能总入口，按分类分组：**灯光**（前大灯爆闪 / 后雾灯爆闪，点进去即是操作页：状态 + 触发在上，参数在下）→ 驾驶辅助 → 车身与舒适 → 高级与兼容（含 S3XY、LAB Menu）；支持搜索、长按置顶（顶部「常用」，最多 6 个），灯光组行尾显示「爆闪中」实时状态 |
| **蓝牙** | 由「功能 → S3XY」开关控制标签显隐；S3XY 设备扫描/配对/连接、单击-双击-长按动作绑定、自动重连、日志导出 |
| **设置** | 车型卡片与**更改车型**（保存后设备重启）、无线、外观、刷新间隔、诊断/恢复、**OTA（选包→SHA-256 校验→确认→字节进度→重启确认→记录上次刷写）**、三级重置、封禁车辆、App 语言与设备地址、一键复制诊断信息 / 导出诊断包（zip：摘要 + 网络日志 + 快照）、固件变更记录 |
| **实验室** | LAB Menu 打开后出现：R79 AP 控制 / R79 状态 / 召唤心跳 / ALC / 主驾车窗 / CAN 研究捕获 / 驾驶员监控捕获 / Mode H 调参（含实时引擎） |

## 架构

```
P4CANCompanion/
├── App/            AppDelegate · SceneDelegate · RootTabBarController（iOS 用 Tab，Mac 用侧边栏）
├── Core/           P4APIClient（async/await）· AppEnvironment（单一状态源）· FeatureCatalog（模块与控件 schema）
├── UI/             Theme（8pt 栅格/语义色/图标尺寸）· Components（ModuleIconTile/NavRow/KpiTile/StatusChip）· GlassSurface
├── Features/       Overview / Features / S3XY / System / Lab / LiveActivity / Connect
├── SwiftPieces/    第三方组件（FilterRail，MIT + Commons Clause，版权头保留）
└── Vendor/         SnapKit 5.7.1 源码（内置，避免 SPM 依赖）
P4CANWidget/        Live Activity / 桌面小组件扩展
Support/            Info.plist
```

关键设计：

- **只显示设备真实状态**：任何控件读不到字段就显示「读取中…」并禁用，不猜默认值；写入后回读校验，未生效会明确提示。
- **契约对齐固件**：所有写接口都是 `POST /api/xxx?k=v`，字段名逐条对照 `web_api.h`。
- **状态单一来源**：`AppEnvironment` 按设置里的 250 / 500 / 1000 ms 并行轮询快照，慢变端点每 4 拍刷新。
- **LAB 显隐跟网页一致**：设置 → 功能 → LAB Menu 打开后，底部才出现「实验室」标签；关闭即隐藏。

## 安全边界

- 只与用户配置的 P4-CAN 地址通信：ATS 仅开 `NSAllowsLocalNetworking`，并**拒绝所有 HTTP 3xx 跳转**，防止被伪造热点带离设备；
- 设备地址只接受 `http(s)://host[:port]` 或 `host[:port]`，拒绝账号、路径、查询串与脚本 scheme；
- 网络日志对 `password` / `secret` 等参数打码；日志只存在内存（最多 300 条），不上传；
- OTA 只接受应用升级版 `.bin`、拒绝 `.merged.bin` 与超过 8 MB 的文件，multipart 文件名做注入清洗；
- JSON 响应限制 4 MB、日志下载限制 32 MB；
- 无第三方统计 / 广告 SDK，不收集任何遥测数据。

> 设备侧限制：固件 API 无鉴权、仅 HTTP。请修改默认 AP 密码，并只在可信网络下操作；这是当前固件契约，App 无法单独修复。

## 构建

```bash
# iOS（模拟器）
xcodebuild -scheme P4CANCompanion \
  -destination 'generic/platform=iOS Simulator' -configuration Debug build

# iOS（真机，需在 Xcode 里选自己的 Team）
xcodebuild -scheme P4CANCompanion -destination 'generic/platform=iOS' -configuration Release build

# Mac（Catalyst）
xcodebuild -scheme P4CANCompanion -destination 'platform=macOS,variant=Mac Catalyst' -configuration Release build
```

> 若在沙箱环境中命令行编译，Swift 宏插件服务器会被拦截，需追加 `OTHER_SWIFT_FLAGS='-Xfrontend -disable-sandbox'`。
> 在 Xcode GUI 里直接 Cmd+R 不受影响。

## 本地联调

```bash
cd build/mock && P4CAN_MOCK_PORT=8099 python3 mock_p4can.py
# 启动 App 时指向 mock：
SIMCTL_CHILD_P4CAN_HOST=127.0.0.1:8099 xcrun simctl launch booted com.p4can.companion
```

`build/mock/mock_p4can.py` 按固件真实字段实现了 20+ 个端点，写接口会真实改变状态，可用于回归。

## 文档

| 文件 | 内容 |
|---|---|
| `实现方案.md` | 架构、数据层、页面结构与版本演进 |
| `build/IPA-安装说明.md` | 每个版本的变更与 IPA 安装方式 |
| `build/图标设计.md` | App 图标设计（三套外观、Liquid Glass 材质） |
| `build/SwiftPieces-接入.md` | MCP 接入、组件选型与改造记录 |
| `build/灯光爆闪-方案.md` | 爆闪可行性、接口契约与风险 |
| `build/固件补丁-灯光爆闪.md` | 固件参考补丁与接入步骤 |

## 相关

- 固件源码：<https://github.com/06066060606060/P4can-universal-unlock>
- 组件库：SwiftPieces（`https://swiftpieces.com`，`FilterRail` 采用 MIT + Commons Clause，允许随 App 分发，不得单独转售组件）

## 免责声明

本项目用于个人车辆的诊断与配置。所有 CAN 写入都可能影响车辆行为：请在封闭场地测试，遵守当地法规，因使用造成的后果由使用者自行承担。
