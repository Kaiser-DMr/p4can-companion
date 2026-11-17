# P4管家 v3.0 · 安装说明（iPhone + Mac）

## 一、iPhone / iPad（IPA）

- 产物：`P4CAN-Companion-v3.0-adhoc.ipa`（2.6 MB）
- 结构：`Payload/P4CANCompanion.app` + `PlugIns/P4CANWidgetExtension.appex`
- 平台：arm64，iOS 17.0+，iPhone + iPad（v1.5 起兼容 iPad 布局）
- 签名：**ad-hoc**（App 与 Widget 扩展已分别签名），版本 **3.0 / build 21**
- 备份：`~/Downloads/P4CAN-Companion-v3.0-adhoc.ipa`

### 安装方式（本机无开发者证书，需现场重签）

1. **Sideloadly / AltStore**：导入 IPA，用你的 Apple ID 重签后安装（会自动重签 appex）；
2. **Xcode**：`open P4CANCompanion.xcodeproj` → Signing 选你的 Team → 选真机 Cmd+R；
3. 企业/开发证书用户：解压后对 appex 与 app 逐个 `codesign` 再打包。

> Live Activity 要求主 App 与扩展同一 Team 签名。ad-hoc 包重签后即可正常显示；
> 不重签直接装，锁屏/灵动岛可能不出现（其余功能不受影响）。

### 首次使用

1. 系统设置加入 P4 开头的设备热点 → 回到 App 允许「本地网络」；
2. 状态页显示「已连接」后即可使用四个标签页；
3. 需要锁屏/灵动岛时，打开「锁屏与灵动岛 → 显示实时状态」。

## 二、Mac（原生 .app）

- 产物：`P4CAN-Companion-mac-v3.0.zip`（2.4 MB）
- 解压得到 `P4CAN-Companion.app`：Mac Catalyst 原生应用，universal（arm64 + x86_64），macOS 14.0+
- 运行步骤与差异详见同目录 **`Mac-运行说明.md`**

## 三、v3.0 变更摘要（新增「灯光爆闪」模块）

1. 「车身与舒适」新增模块 **灯光爆闪**：启动开关 + 频率 1–8 Hz + 持续时间 0.5–10 s + 模式（左右交替/仅左/仅右）；
2. 走固件新端点 `/api/lights/strobe`（GET 状态 / POST 控制），控件仍是「设备值驱动」，未打固件补丁时显示「读取中…」；
3. 实时状态补中文字段（运行中 / 被阻断 / 频率 / 剩余时间 / 发送成功…），诊断布尔改为「是/否」，空字符串字段自动隐藏；
4. 同时交付固件参考补丁：`build/firmware-patch/light_strobe.h` + `build/固件补丁-灯光爆闪.md`（含插入位置、handler、验证顺序）；
5. 详见 `build/灯光爆闪-方案.md`，截图 `screenshots/strobe-01.png`。

## 四、v2.9 变更摘要（分类胶囊收紧 + 玻璃表面）

1. FilterRail 胶囊间距 26pt → **18pt**（合并距离 20 → 12，保持"彼此独立、指示球穿过才合并"）；
2. 新增 `P4CANCompanion/UI/GlassSurface.swift`：iOS 26 `glassEffect` + Material 回退 + 尊重「降低透明度」；
3. 功能页搜索框、详情页说明卡改用玻璃表面；详情卡宽度与下方原生分组对齐；
4. 详见 `build/SwiftPieces-接入.md` 4.1 / 4.2 节，截图 `sp-04-tighter-gap.png`、`sp-05-detail-glass.png`。

## 五、v2.8 变更摘要（接入 SwiftPieces，重做「功能」页分类条）

1. 接入 MCP `https://swiftpieces.com/api/mcp`（streamable-http，7 个工具），配置写入 `~/.workbuddy/mcp.json`；
2. 按它返回的 App Design 方法评审后，只替换「分类筛选」一处：改用 **FilterRail**（液态玻璃胶囊 + 计数 + 单选指示球）；
3. 选中项自动居中、左右缘渐隐、点击/拖动皆可、内置触觉反馈；深色模式自适应；
4. 搜索态、分组列表、19 个模块与详情页逻辑全部不变；
5. 新增文件 `P4CANCompanion/SwiftPieces/Inputs/FilterRail.swift`（保留 MIT + Commons Clause 头）；
6. 详见 `build/SwiftPieces-接入.md`，截图 `screenshots/sp-01..03`。

## 六、v2.7 变更摘要（改名 P4管家 + 换成 AO3 标志图标）

1. **应用名改为「P4管家」**：主屏名称、Mac 菜单栏、窗口标题、应用内两处授权提示文案全部同步；
   Bundle ID 保持 `com.p4can.companion`，覆盖安装不会丢设置；
2. **图标换成 `archive-of-our-own.svg`**（AO3 单色字标），采用「深红玻璃底 + 白色字标」：
   白 on 深红对比度 ≈8:1，40px 仍可辨；深红即 AO3 品牌色，只对调底色与图形；
3. 三套外观齐全（默认 / 深色 / 着色），字标占 72% 安全区，投影在带内边距画布上计算；
4. 详细说明见 `build/图标设计.md`，展示图 `screenshots/icon-showcase.png`、主屏实拍 `icon-home.png`。

## 七、v2.6 变更摘要（LocatorJS 标志图标）

1. 按用户提供的 `locatorjs.svg`（四角取景框 + `< / >`）重做 App 图标；
2. 遵循 iOS 27 规范：1024²、无圆角、不透明、标志占 66% 安全区；
3. 三套外观齐全：默认（浅色玻璃）/ 深色 / 着色（Tinted），已确认编入 `Assets.car`；
4. 材质用料：悬浮投影 + 顶部受光 + 菲涅尔亮边 + 淡紫/淡玫瑰品牌渗色底；
5. 体积从 903 KB 变为 2.4 MB（三张 1024 图标进 `Assets.car`，其中已关闭噪点以控制体积）；
6. 设计说明见 `build/图标设计.md`，展示图 `screenshots/icon-showcase.png`、主屏实拍 `icon-home.png`。

## 八、v2.4 变更摘要（补上 App 图标）

1. 之前工程里**没有 AppIcon**，装到桌面是白图标；现已加入 1024×1024 图标（深蓝底 + P4 字标 + CAN 方波），
   资产目录 `P4CANCompanion/Assets.xcassets`，Info.plist 已生成 `CFBundleIcons`（含 iPad 尺寸）；
2. 体积从 846 KB → 903 KB（图标压缩后约 57 KB），`.app` 3.6 MB。

## 九、v2.3 变更摘要（功能页搜索）

1. 功能页顶部新增**常驻搜索框**：按模块名 / 说明 / id / 分类名匹配，中英文均可（如「踏板」「tlscc」「限速」）；
2. 搜索时自动收起分类条，摘要变为「搜索「x」· N 个结果」，列表分组头为「搜索结果」；
3. 无结果时给建议关键词与「清除搜索」按钮；列表下滑自动收键盘；
4. 分类条与列表项完全保留，19 个模块一项没少；
5. 设计说明更新至 `build/设计优化-功能页.md` 3.5 节，截图 `features-search.png` / `features-search-empty.png`。

## 十、v2.2 变更摘要（「功能」页分类导航）

1. **顶部新增固定分类条**：全部 19 / 驾驶辅助 6 / 车身与舒适 3 / 实验室功能 6 / 高级与兼容 4；
2. 点分类立即过滤列表（19 项长列表 → 最多 6 项），分类条不随列表滚动；
3. **选中态**：蓝色实心胶囊 + 白字 + 数量；未选中为卡片底 + 0.5pt 描边；选中项自动滚到条中间；
4. 默认「全部」仍按 4 个分组展示，**19 个模块与详情页全部保留**；
5. 行样式统一：图标加 30×30 圆角底、支持徽章改 `StatusChip`；
6. 修复两个失效 SF Symbol：`window.vertical`、`square.and.line.vertical.square`；
7. 设计说明见 `build/设计优化-功能页.md`，截图 `screenshots/features-all.png` / `features-lab.png` / `features-dark.png`。

## 十一、v2.1 变更摘要

1. **预留电池卡（SOC）**：状态页在 KPI 与快捷开关之间新增「电池」卡（百分比 + 进度条 + 剩余续航）。
   仅当设备任意端点返回 `batterySoc` / `soc` / `batteryLevel` / `stateOfCharge`（以及可选 `rangeKm`）时才出现，
   否则整卡隐藏 —— 固件当前没有这个字段，所以真机上不会显示（不是 bug）。
2. 调研与探测工具：
   - `build/电量SOC-调研.md`：为什么现在拿不到、固件要改哪几处、怎么先用 RAW 捕获确认；
   - `build/tools/soc_probe.py`：扫描 `researchcapture/log.csv`，按"像 SOC 的程度"排出候选 (总线, CAN ID, 字节)。
3. 演示截图 `screenshots/soc-demo.png`（mock 注入 `batterySoc=68, rangeKm=312`）。

## 十二、v2.0 变更摘要

1. **移除「状态」页顶部三个工具图标**（全部数据 / 立即同步 / 连接引导），导航栏只保留「设备状态」标题；
   这些能力仍可从别处进入：
   - 全部数据：系统 → 数据浏览，或 CAN 卡片底部「查看全部总线字段」；
   - 立即同步：下拉刷新（也与 1.5 秒自动轮询等效）；
   - 连接引导：系统 → 连接 → 「查看连接引导」，离线时首屏也有入口。

## 十三、v1.9 变更摘要（状态页设计优化 v2.0）

状态页按设计稿重排信息层级，数据口径不变，只改呈现：

1. **Hero 卡合并**「设备身份 + 连接态 + 三路健康 + 同步时间」；
2. 原「车辆实时」7 行键值 → **2×2 KPI 四宫格**（挡位 / AP / NOA / 扭矩，26pt 圆体等宽数字）；
3. **CAN 总线**改为每路"状态胶囊 + 收/发/拒 + 发送成功率进度条 + 帧龄"，新增**接收帧占比条**；
4. **扭矩趋势**增加当前 / 峰值 / 均值三指标 + 均值虚线，坐标轴改为左侧 3 刻度；
5. 新增通用组件 `MetricTile` / `StatusChip` / `SlimProgress` / `RatioBar`，功能列表支持徽章同步换成 `StatusChip`；
6. 颜色/字号/圆角/间距收敛为 token，输出 `build/design-tokens.json`（可导入 Figma Variables）；
7. 完整设计说明见 **`build/设计优化-状态页.md`**，截图 `screenshots/design-01-hero.png`、`design-02-can.png`、`design-03-dark.png`。

## 十四、v1.8 变更摘要（界面只显示板子的真实状态，不再有默认值）

原则：**App 不猜、不填默认**。连接后看到的就是设备当前值；设备没上报的字段，App 显示「读取中…」并禁用操作。

| 场景 | 之前 | 现在 |
|---|---|---|
| 设备没上报某开关 | 显示「关」 | 显示「读取中…」，开关不可点 |
| 设备没上报某数值 | 滑杆停在最小值，显示 0 | 显示「读取中…」，不显示滑杆 |
| 设备没上报某下拉项 | 直接选中第一个选项 | 显示「读取中…」 |
| 设备返回的枚举不在 App 选项里 | 强行显示为第一项 | 原样只读显示（例如 `0` / `STOCK`） |
| 网页上改了设置 | App 只在打开页面时读一次，之后拿本地缓存 | 每 1.2 秒以设备值为准覆盖（拖滑杆时暂停），网页改了 App 跟着变 |
| 数值超出自定义范围 | 按范围夹取后显示 | 显示设备原值，只把滑杆位置夹在范围内 |
| 写入需要伴随参数但设备没上报 | 发一个残缺请求 → 设备回 400 | 不发请求，直接提示缺哪个字段 |

改动位置：
- `FeatureDetailView`：`boolState / numberState / selectText` 全部返回可选值；`syncFromDevice()` 每轮把控件同步成设备值；
  `pendingRow()` 统一渲染「读取中…」；滑块拖动期间用 `sliderEditing` 保护。
- `DashboardView.quickRow`：`isOn: Bool?`，未知时显示「读取中…」。
- `S3XYDevicesViewController`：蓝牙总开关未知时禁用并显示「读取中…」；自动重连状态未知时不猜方向。

**验证**：另外起了一个「只返回 `{"ok":true}`」的空设备做反向测试 —— ULC 五个控件、首页三个快捷开关全部显示「读取中…」，
没有任何默认开关/默认数值；切回带完整字段的设备后，所有值立刻变成设备真实值。

## 十五、v1.7 变更摘要（修「开关打开没反应」）

**根因**：写入用的 query 参数名 与 状态 JSON 的字段名 在固件里经常不一致，而 App 用同一个键既写又读，
于是写成功了却回读到旧值 → 开关弹回，看起来「点了没反应」。

修正的回读映射（写入键 → 正确读取键）：

| 模块 | 控件 | 写入 | 之前读 | 现在读 |
|---|---|---|---|---|
| 自动变道 ALC | 启用 | `enabled` | `enabled` ❌ | `autoLaneChangeEnabled` |
| 无确认变道 ULC | 无确认变道 | `confirm` | `confirm` ❌ | `stalkConfirmEnabled` |
| ULC | 高速禁用 ALC | `alcOff` | `alcOff` ❌ | `alcMode`（2=开） |
| ULC | 变道时序优化 | `timing` | `timing` ❌ | `stalkConfirmTimingMode` |
| 召唤 TLSSC | 高速闸门 | `enabled` | `enabled` ❌ | `tlsscHighwayGateEnabled` |
| 召唤 TLSSC | NOA 阻断 | `enabled` | `enabled` ❌ | `tlsscBlockInNoa` |
| R79 | Mode 1/2 重注入 | `modeNReinject` | 同名 ❌ | `modeNReinjectEnabled` |
| 开门取消 | 启用 | `enabled` | `enabled` ❌ | `doorCancel` |
| 实验室 | LAB / S3XY / 封禁 / TLSSC 恢复 | `enabled` | `enabled` ❌ | `lab` / `s3xy` / `banned` / `tlsscRestore` |
| 实验室 | AP 踏板配置 | `enabled` | `enabled` ❌ | `/api/pedalmap/stats` 的 `apDriveProfileEnabled` |
| 视觉限速 | 抑制 | `disabled` | `disabled` ❌ | `requestDisabled` |
| 踏板映射 | 档位 | `mode` | `mode` ❌ | `targetName`（STOCK/CHILL/SPORT/PERFORMANCE） |

其他写入修正：
- **打灯延迟**：固件参数是 `ms`，原来发 `delayMs`（被当成未提供 → 永远落默认值），已改；
- **常驻 AP**：固件要求 `enabled` + `method` 同时提交且 `method` 不能为「未选择」，已在开启前拦截并提示；
- **踏板档位**：改用固件接受的 `STOCK/CHILL/SPORT/PERFORMANCE`。

体验修正：
- 开关改为**乐观状态**：点下立即保持，不再出现「一按就弹回」；
- 写成功但回读没变时，明确提示「已提交，但设备未回读该状态」，不再让人以为没反应；
- 补齐 `advancedEapSupported` / `apDriveProfile` / `stalkConfirmEnabled` 等中文标签，并修掉一处
  本地化表重复键导致的启动崩溃。

## 十六、v1.6 变更摘要

1. **修复「状态」标签图标空白**：`gauge.with.dots.needle.bottom.50.percent` 不是合法 SF Symbol，改为 `gauge.with.dots.needle.50percent`（并全量校验了工程内 54 个符号名，仅此一处有误）；
2. **「蓝牙」标签改为可隐藏**：系统 → 界面 → 「在标签栏显示「蓝牙」」，默认关闭（底部只有 状态/功能/系统）；
   开关切换时标签栏实时重建并保持当前页；正在看蓝牙时关闭会回到状态页；
3. 清理编译警告（S3XY 分组头注册多余 `[weak self]`）。

## 十七、v1.5 变更摘要

1. **新增 Mac 原生版**（Mac Catalyst）：侧边栏导航、可缩放窗口、全部功能与 iPhone 版一致；
2. ActivityKit 在 Mac 不可用 → 属性模型与控制器做跨平台拆分，Mac 自动隐藏实时活动开关；
3. `CFBundleName` 改为「P4-CAN 工具箱」（Mac 菜单栏不再显示工程名）；
4. 设备族扩到 iPhone + iPad（`TARGETED_DEVICE_FAMILY = 1,2`）；
5. 补本地化：`apDisplayState` / `r79TxState` / `r79TxCount` 等；
6. 本地联调钩子：`P4CAN_TAB` 环境变量或 `p4can.debugTab` 偏好可指定启动标签页（DEBUG）。

## 十八、仍旧有效的历史变更

- v1.2：按开源固件源码重做接口契约（query 参数）、三路 `can1..can3`、S3XY 槽位与动作绑定、写入门禁；
- v1.3：灵动岛/锁屏实时活动、Swift Charts 扭矩趋势、内置网络抓包、触觉反馈；
- v1.4：模拟器实测修复 `#if DEBUG` 失效、蓝牙页布局塌陷、非法 SF Symbol、字段本地化。
