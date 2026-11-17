# P4-CAN 工具箱 · Mac 版运行说明（v1.8 / build 9）

## 产物

- `P4CAN-Companion-mac-v1.8.zip`（约 1.4 MB）
- 解压即得 `P4CAN-Companion.app`：**macOS 原生应用**（Mac Catalyst）
- 架构：universal（Apple Silicon arm64 + Intel x86_64）
- 系统要求：macOS 14.0 或更高
- 签名：ad-hoc（本地运行无需开发者账号）

## 三步跑起来

1. 双击 zip 解压，把 `P4CAN-Companion.app` 拖进「应用程序」（或任意目录）。
2. 首次打开：若提示「无法验证开发者」，右键 App → **打开** → 再点「打开」即可（只需一次）。
3. 连设备：Mac 连上 P4 开头的设备热点，或在「系统 → 设备地址」里改成设备当前 IP（默认 `192.168.4.1`）。

> 首次联网 macOS 会弹「本地网络」授权，必须允许，否则读不到设备。

## 与 iPhone 版的差异

| 项目 | Mac 版 |
|---|---|
| 导航 | 系统**侧边栏**（状态 / 功能 / 蓝牙 / 系统），不是底部 Tab |
| 窗口 | 460×640 ~ 1180×1600 可自由缩放，单列信息流不会被拉宽 |
| 灵动岛 / 锁屏实时活动 | ❌ Mac 无此能力（ActivityKit 未提供 Mac 实现），该开关自动隐藏 |
| 其余功能 | 与 iPhone 版**完全一致**：三路 CAN、17 个固件功能模块、S3XY 蓝牙、OTA、Wi-Fi/热点、日志导出、扭矩趋势、网络日志 |

## 用本地 mock 试跑（不接硬件）

```bash
# 1) 起 mock 设备（仓库内已带，返回固件真实字段结构）
cd ~/WorkBuddy/2026-11-17-19-25-27/P4CAN-Companion/build/mock
python3 mock_p4can.py        # 监听 127.0.0.1:8080

# 2) 把 App 的设备地址指向 mock（写入偏好后重启 App）
defaults write com.p4can.companion "p4can.device.host" -string "127.0.0.1:8080"
open -n ~/Applications/P4CAN-Companion.app

# 3) 想回到真机地址
defaults write com.p4can.companion "p4can.device.host" -string "192.168.4.1"
```

DEBUG 构建还支持 `defaults write com.p4can.companion p4can.debugTab -string 2` 指定启动时停在第几个标签（0..3）。

## 从源码构建

```bash
cd ~/WorkBuddy/2026-11-17-19-25-27/P4CAN-Companion
xcodebuild -scheme P4CANCompanion \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -configuration Release build
# 产物：~/Library/Developer/Xcode/DerivedData/P4CANCompanion-*/Build/Products/Release-maccatalyst/P4CANCompanion.app
```

或直接在 Xcode 里把运行目标选成 **My Mac (Mac Catalyst)**，Cmd+R。

## 实测记录（2026-11-17，macOS 27.2 / arm64）

- Release 构建 ✅ BUILD SUCCEEDED，产物 5.8 MB，`codesign -v` 通过
- 解压后启动 ✅ 正常显示「已连接 · 在线」，四页全部可用
- 截图见 `build/screenshots/mac-01-status.png` ~ `mac-05-canbus.png`
