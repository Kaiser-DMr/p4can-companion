# P4管家

P4-CAN Universal（ESP32-P4 车载 CAN 控制器）的原生 iOS 控制台。UIKit + SwiftUI + SnapKit 混合实现，不是网页套壳。

![平台](https://img.shields.io/badge/platform-iOS%2017%2B%20%7C%20macOS%2014%2B-blue)
![版本](https://img.shields.io/badge/version-3.0%20(21)-green)

## 功能

| 模块 | 内容 |
|---|---|
| **状态** | 设备在线/固件/内存、三路 CAN（BODY / CHASSIS / PARTY）收发与 Bus-Off、扭矩趋势、电池（固件提供才显示）、锁屏与灵动岛实时活动 |
| **功能** | 19+ 个固件功能模块：NAG、自动变道 ALC、无确认变道 ULC、TLSSC 召唤、R79、DMS、ISA、踏板映射、灯光爆闪等；分类导航 + 全局搜索 |
| **蓝牙** | S3XY 设备扫描/配对/连接、单击-双击-长按动作绑定、自动重连、日志导出 |
| **系统** | 设备地址、Wi-Fi 入网、OTA 上传、6 类重置、CSV 日志、网络抓包、全部原始字段浏览 |

## 架构

```
P4CANCompanion/
├── App/            AppDelegate · SceneDelegate · RootTabBarController（iOS 用 Tab，Mac 用侧边栏）
├── Core/           P4APIClient（async/await）· AppEnvironment（单一状态源）· FeatureCatalog（模块与控件 schema）
├── UI/             Theme（8pt 栅格/语义色）· Components（KpiTile/StatusChip/SlimProgress/RatioBar）· GlassSurface
├── Features/       Overview / Features / S3XY / System / LiveActivity / Connect
├── SwiftPieces/    第三方组件（FilterRail，MIT + Commons Clause，版权头保留）
└── Vendor/         SnapKit 5.7.1 源码（内置，避免 SPM 依赖）
P4CANWidget/        Live Activity / 桌面小组件扩展
Support/            Info.plist
```

关键设计：

- **只显示设备真实状态**：任何控件读不到字段就显示「读取中…」并禁用，不猜默认值；写入后回读校验，未生效会明确提示。
- **契约对齐固件**：所有写接口都是 `POST /api/xxx?k=v`，字段名逐条对照 `web_api.h`。
- **状态单一来源**：`AppEnvironment` 每 1.5s 并行轮询快照，慢变端点每 3 拍刷新。

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
