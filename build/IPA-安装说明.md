# P4管家 v3.11 · 安装说明（iPhone + Mac）

## 一、iPhone / iPad（IPA）

- 产物：`P4CAN-Companion-v3.10-adhoc.ipa`（3.0 MB）
- 结构：`Payload/P4CANCompanion.app` + `PlugIns/P4CANWidgetExtension.appex`
- 平台：arm64，iOS 17.0+，iPhone + iPad（v1.5 起兼容 iPad 布局）
- 签名：**ad-hoc**（App 与 Widget 扩展已分别签名），版本 **3.11 / build 32**
- 备份：`~/Downloads/P4CAN-Companion-v3.11-adhoc.ipa`

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

- 产物：`P4CAN-Companion-mac-v3.6.zip`（2.9 MB）
- 解压得到 `P4CAN-Companion.app`：Mac Catalyst 原生应用，universal（arm64 + x86_64），macOS 14.0+
- 运行步骤与差异详见同目录 **`Mac-运行说明.md`**

## 三、v3.11 变更摘要（前大灯爆闪）

1. 新增「前大灯爆闪」模块：次数 1–30、间隔 50–1000 ms、触发入口 App/S3XY；
2. 固件基于 `0x249 SCCM_highBeamStalkStatus` 的 PULL/IDLE 交替，结束后恢复触发前高灯状态；
3. 爆闪期间独占 0x249，暂停转向灯/ALC 注入；支持停止、防重入、发送失败自动恢复；
4. 无拨杆（0x249 不可用）车型返回 `STALKLESS_UNSUPPORTED`，不发送任何帧；
5. 固件补丁与集成说明：`build/firmware-patch/headlight_strobe.h`、`headlight_strobe-integration.md`。

## 四、v3.10 变更摘要（应用图标）

1. App 图标改为 GE 标志，保留原图白底与蓝色（#0870D8）；内容居中、无透明通道；
2. 移除旧深色/着色变体，避免暗色模式换图标；
3. 截图：`v40-appicon-home.png`。

## 五、v3.9 变更摘要（彩色 emoji 图标）

1. 全部功能模块图标改为彩色 emoji：🛞 🚫 🙈 👁️ 💡 🕹️ 🔓 🌍 🚦 ↔️ 🦶 ♾️ 🚘 ⚡ 🚧 📡 💓 🛣️ 🪟 🔬 🎥 🎛️；
2. S3XY / LAB 内联行使用 🎮 / 🧪；
3. `ModuleIcon` 支持 `emoji:` 前缀，保留 Assets 与 SF Symbol 回退；
4. 截图：`v38-17-emoji-icons.png`。

## 六、v3.8 变更摘要（TLSSC 图标）

1. TLSSC 模块补上红绿灯图标（🚦），功能列表、搜索结果与实验室列表统一走 `ModuleIcon`；
2. `ModuleIcon` 优先支持 Assets 资源名，未找到时回退 SF Symbol；
3. 截图：`v38-16-tlssc-final.png`。

## 七、v3.7 变更摘要（全功能同步复核 + 灵动岛车型）

1. **灵动岛 / 锁屏**：展开区与锁屏标题显示当前车型，不再出现 `UNKNOWN`；有效挡位仍显示在右侧；
2. **NAG 高级参数**：6 个报文级字段可编辑（十六进制 ID、HO 比例、Burst、Pause），AP 激活时禁止写入，写入后回读校验；
3. **同步修复**：踏板档位、ULC 高速禁用 ALC / AP 前生效、R79 HW3、NAG 模式下拉；
4. **补齐控件**：NAG 滚轮波形 / 整个 AP 会话、研究捕获 A–D 标签、热点密码显示、系统统计 JSON；
5. **数值范围对齐**：打灯延迟 30 s、R79 延迟 1 ms 步进、研究窗口固定档位；
6. **批量编辑防覆盖**：Mode H / NAG 高级参数检测设备端变更，应用前拒绝旧表单覆盖；
7. 截图：`v38-07-nag-mode.png`、`v38-09-modeh-stale.png`、`v38-10-nag-stale.png`。

## 八、v3.6 变更摘要（security-audit 复审后的加固）

按 Cloudflare `security-audit-skill` 做了一次针对本项目边界的审查，确认并修复：

1. **网络日志泄露 Wi-Fi 密码**（中）：`POST /api/wifi/apply?password=…` 会把明文密码写进内置抓包页。
   现对 `password / passwd / psk / token / secret / api_key` 统一打码为 `***`；
2. **HTTP 重定向可把请求带离设备**（中）：URLSession 默认跟随 3xx，伪造热点可 302 到外网并带走 query
   （含密码）。现由 `URLSessionTaskDelegate` 拒绝所有跳转，并把 3xx 当成明确错误；
3. **设备地址输入未校验**（低-中）：现只接受 `http(s)://host[:port]` 或 `host[:port]`，拒绝账号、路径、
   查询串、片段、脚本 scheme 与非法端口；
4. **OTA 文件无上限/无类型校验**（低-中）：现在只接受 `.bin`、拒绝 `.merged` 全量镜像、限制 64 KB–8 MB，
   并在 multipart 里清洗文件名中的引号/换行，避免头部注入；
5. **响应体无上限**（低）：JSON 4 MB、CSV 32 MB 上限，超限拒绝解析；
6. 复核通过：ATS 仅 `NSAllowsLocalNetworking`、无 WebView/深链、无硬编码密钥、Mock 仅绑定 127.0.0.1、
   无第三方统计 SDK。

设备侧仍未解决（固件契约，App 无法单独修复）：API 无鉴权、仅 HTTP。建议修改默认 AP 密码并只在可信网络使用。

## 九、v3.5 变更摘要（S3XY 开关统一控制蓝牙标签）

1. 「功能 → S3XY」现在与网页一致：开关打开后底部出现「蓝牙」标签，关闭立即隐藏（若正停留在蓝牙页会回到状态页）；
2. 删除设置页里重复的「在标签栏显示『蓝牙』」开关，只保留功能页的 S3XY 开关；
3. 蓝牙标签显隐改为由固件 `features/status.s3xy` 决定，网页上改 S3XY 时 App 也会跟随；
4. 标签栏重建时保留当前页；删除的标签不存在时回到状态页；S3XY 开关带乐观态与结果提示；
5. 截图：`v35-01-settings-no-bt-toggle.png`、`v35-02-s3xy-off.png`、`v35-03-s3xy-on.png`。

## 十、v3.4 变更摘要（补齐「更改车型」）

1. 设置页车型卡片下新增 **更改车型**：5 个固件车型（Model Y L / Y Juniper / Y Legacy / 3 Highland /
   3 Legacy），拓扑按固件规则自动绑定（Y L → Party + VH，其余 → Body + Chassis + Party）；
2. Model 3 Highland 额外要求选择 **STALK · 0x249 / STALKLESS · 0x3C2**，与实际拨杆一致；
3. 保存走 `POST /api/profile/select?profile=&topology=&turn=`，带二次确认；设备会立即重启，
   重启期间界面显示「正在确认设备重启…」，并通过回读 `profile/status` 确认车型真正生效；
4. 若响应在重启时断开，不直接报失败，而是等待设备回来后比对车型，避免「其实已生效却提示失败」；
5. 截图：`v34-04-change-profile.png`、`v34-05-change-highland.png`、`v34-07-profile-updated.png`。

## 十一、v3.3 变更摘要（功能入口合并到「功能」标签）

1. **「设置 → 功能」整段移动到「功能」标签**，顺序完全不变：NAG → ISA → 驾驶员监控 → 视觉限速 →
   自动转向灯 → 召唤状态 → R79 → 地区/地图 → TLSSC → 变道 → 踏板 → 常驻 AP → AP 加速/回收 →
   S3XY → LAB Menu；
2. **去掉分类筛选**（不再有「全部 / 驾驶辅助 / 车身与舒适 / 高级」胶囊条），列表改为单层；
3. **保留搜索**，并支持英文名与 S3XY / LAB 关键词；搜索结果同样可内联开关；
4. ISA / DMS / S3XY / LAB Menu 四个快捷开关随行内联，读取值来自设备；LAB 打开后底部立即出现实验室；
5. 设置页精简为：车型卡片 → 系统（固件/无线/外观/刷新间隔/诊断/OTA/重置）→ 封禁车辆 → App；
6. 截图：`v33-02-features-late.png`、`v33-04-search-lab.png`、`v33-05-settings-without-features.png`。

## 十二、v3.2 变更摘要（设置页对齐网页 / 补齐固件功能 / LAB 开关可见）

1. **设置页按网页 Settings 重排**：车型卡片 → 功能（NAG / ISA / DMS / 视觉限速 / 自动转向灯 / 召唤状态 /
   R79 / 地区 / TLSSC / 变道 / 踏板 / 常驻 AP / AP 加速回收 / S3XY / **LAB Menu**）→ 系统（固件 / 无线 /
   外观 / 刷新间隔 / 诊断 / 升级 / 重启 / 两级重置 / 恢复出厂）→ 封禁车辆（封禁车辆 / TLSSC 恢复）→ App；
2. **LAB Menu 开关回到设置页**：打开后底部立即出现「实验室」标签，关闭立即隐藏；S3XY 开关同页可读可写；
3. **补齐固件原生功能**：新增召唤状态（只读）、TLSSC 独立模块、R79 状态（只读）、AP 加速 / 回收、
   驾驶员监控捕获（A–F 六槽）、**Mode H 调参**（13 个参数一次提交 + 实时引擎监视）；
4. **移除灯光爆闪**：按需求先只保留固件原生功能，`/api/lights/strobe` 与固件补丁不随 v3.2 发布；
5. **外观与刷新间隔**：跟随手机 / 浅色 / 深色（窗口级生效，含 UIKit 页），250 / 500 / 1000 ms（默认 500）；
6. **无线与诊断**：蓝牙总开关、S3XY 自动重连、热点设置、已注册按钮数、清除蓝牙数据；诊断页含系统统计、
   三路 CAN 计数器、重置统计、硬重初始化、导出启动抓包；
7. **修复**：`.selectRead` 读取键一直显示「读取中…」（NAG 注入模式、AP 回收档位等）；支持徽章在中文下
   误显示为「— 支持」；状态页同步间隔文案固定为 1.5 秒；
8. 截图：`v32-08-settings-top-zh.png`、`v32-14-settings-lab-en.png`、`v32-09-lab.png`、`v32-10-modeh.png`、
   `v32-11-wireless.png`、`v32-12-diagnostics.png`、`v32-20-apdrive-fixed.png`。

## 十三、v3.1 变更摘要（排序对齐网页 / 实验室独立标签 / 中英切换）

1. **功能排序按固件网页的设置列表**：NAG → ISA → DMS → 视觉限速 → 自动转向灯 → 灯光爆闪 → 开门取消 →
   召唤/TLSSC → R79 → 地区 → 无确认变道 → 踏板 → 常驻 AP → 车型配置（单层列表，不再按四个分区打散）；
2. **实验室独立成标签**：LAB 总开关启用后才出现在底部（顺序同网页 LAB 分区：LAB → R79 AP → 心跳 →
   自动变道 → 主驾车窗 → CAN 捕获）；关闭时自动隐藏并回到状态页；
3. **语言切换**：系统 → 界面 → 语言（跟随系统 / 简体中文 / English），立即生效、持久化；
   英文采用固件网页原措辞（Nag Killer / Auto Blinker / Lane Change …）；
4. 新增 `Core/L10n.swift`，`FeatureModule` 增加 `titleEN/summaryEN`；标签栏、分类条、模块列表、
   详情页标题与分区、系统页主要分区已双语；控件行内的说明仍为中文（下一版补齐）；
5. 截图：`v31-01-features-en.png`、`v31-02-lab-en.png`、`v31-03-settings-en.png`。

## 十四、v3.0 变更摘要（新增「灯光爆闪」模块）

1. 「车身与舒适」新增模块 **灯光爆闪**：启动开关 + 频率 1–8 Hz + 持续时间 0.5–10 s + 模式（左右交替/仅左/仅右）；
2. 走固件新端点 `/api/lights/strobe`（GET 状态 / POST 控制），控件仍是「设备值驱动」，未打固件补丁时显示「读取中…」；
3. 实时状态补中文字段（运行中 / 被阻断 / 频率 / 剩余时间 / 发送成功…），诊断布尔改为「是/否」，空字符串字段自动隐藏；
4. 同时交付固件参考补丁：`build/firmware-patch/light_strobe.h` + `build/固件补丁-灯光爆闪.md`（含插入位置、handler、验证顺序）；
5. 详见 `build/灯光爆闪-方案.md`，截图 `screenshots/strobe-01.png`。

## 十五、v2.9 变更摘要（分类胶囊收紧 + 玻璃表面）

1. FilterRail 胶囊间距 26pt → **18pt**（合并距离 20 → 12，保持"彼此独立、指示球穿过才合并"）；
2. 新增 `P4CANCompanion/UI/GlassSurface.swift`：iOS 26 `glassEffect` + Material 回退 + 尊重「降低透明度」；
3. 功能页搜索框、详情页说明卡改用玻璃表面；详情卡宽度与下方原生分组对齐；
4. 详见 `build/SwiftPieces-接入.md` 4.1 / 4.2 节，截图 `sp-04-tighter-gap.png`、`sp-05-detail-glass.png`。

## 十六、v2.8 变更摘要（接入 SwiftPieces，重做「功能」页分类条）

1. 接入 MCP `https://swiftpieces.com/api/mcp`（streamable-http，7 个工具），配置写入 `~/.workbuddy/mcp.json`；
2. 按它返回的 App Design 方法评审后，只替换「分类筛选」一处：改用 **FilterRail**（液态玻璃胶囊 + 计数 + 单选指示球）；
3. 选中项自动居中、左右缘渐隐、点击/拖动皆可、内置触觉反馈；深色模式自适应；
4. 搜索态、分组列表、19 个模块与详情页逻辑全部不变；
5. 新增文件 `P4CANCompanion/SwiftPieces/Inputs/FilterRail.swift`（保留 MIT + Commons Clause 头）；
6. 详见 `build/SwiftPieces-接入.md`，截图 `screenshots/sp-01..03`。

## 十七、v2.7 变更摘要（改名 P4管家 + 换成 AO3 标志图标）

1. **应用名改为「P4管家」**：主屏名称、Mac 菜单栏、窗口标题、应用内两处授权提示文案全部同步；
   Bundle ID 保持 `com.p4can.companion`，覆盖安装不会丢设置；
2. **图标换成 `archive-of-our-own.svg`**（AO3 单色字标），采用「深红玻璃底 + 白色字标」：
   白 on 深红对比度 ≈8:1，40px 仍可辨；深红即 AO3 品牌色，只对调底色与图形；
3. 三套外观齐全（默认 / 深色 / 着色），字标占 72% 安全区，投影在带内边距画布上计算；
4. 详细说明见 `build/图标设计.md`，展示图 `screenshots/icon-showcase.png`、主屏实拍 `icon-home.png`。

## 十八、v2.6 变更摘要（LocatorJS 标志图标）

1. 按用户提供的 `locatorjs.svg`（四角取景框 + `< / >`）重做 App 图标；
2. 遵循 iOS 27 规范：1024²、无圆角、不透明、标志占 66% 安全区；
3. 三套外观齐全：默认（浅色玻璃）/ 深色 / 着色（Tinted），已确认编入 `Assets.car`；
4. 材质用料：悬浮投影 + 顶部受光 + 菲涅尔亮边 + 淡紫/淡玫瑰品牌渗色底；
5. 体积从 903 KB 变为 2.4 MB（三张 1024 图标进 `Assets.car`，其中已关闭噪点以控制体积）；
6. 设计说明见 `build/图标设计.md`，展示图 `screenshots/icon-showcase.png`、主屏实拍 `icon-home.png`。

## 十九、v2.4 变更摘要（补上 App 图标）

1. 之前工程里**没有 AppIcon**，装到桌面是白图标；现已加入 1024×1024 图标（深蓝底 + P4 字标 + CAN 方波），
   资产目录 `P4CANCompanion/Assets.xcassets`，Info.plist 已生成 `CFBundleIcons`（含 iPad 尺寸）；
2. 体积从 846 KB → 903 KB（图标压缩后约 57 KB），`.app` 3.6 MB。

## 二十、v2.3 变更摘要（功能页搜索）

1. 功能页顶部新增**常驻搜索框**：按模块名 / 说明 / id / 分类名匹配，中英文均可（如「踏板」「tlscc」「限速」）；
2. 搜索时自动收起分类条，摘要变为「搜索「x」· N 个结果」，列表分组头为「搜索结果」；
3. 无结果时给建议关键词与「清除搜索」按钮；列表下滑自动收键盘；
4. 分类条与列表项完全保留，19 个模块一项没少；
5. 设计说明更新至 `build/设计优化-功能页.md` 3.5 节，截图 `features-search.png` / `features-search-empty.png`。

## 二十一、v2.2 变更摘要（「功能」页分类导航）

1. **顶部新增固定分类条**：全部 19 / 驾驶辅助 6 / 车身与舒适 3 / 实验室功能 6 / 高级与兼容 4；
2. 点分类立即过滤列表（19 项长列表 → 最多 6 项），分类条不随列表滚动；
3. **选中态**：蓝色实心胶囊 + 白字 + 数量；未选中为卡片底 + 0.5pt 描边；选中项自动滚到条中间；
4. 默认「全部」仍按 4 个分组展示，**19 个模块与详情页全部保留**；
5. 行样式统一：图标加 30×30 圆角底、支持徽章改 `StatusChip`；
6. 修复两个失效 SF Symbol：`window.vertical`、`square.and.line.vertical.square`；
7. 设计说明见 `build/设计优化-功能页.md`，截图 `screenshots/features-all.png` / `features-lab.png` / `features-dark.png`。

## 二十二、v2.1 变更摘要

1. **预留电池卡（SOC）**：状态页在 KPI 与快捷开关之间新增「电池」卡（百分比 + 进度条 + 剩余续航）。
   仅当设备任意端点返回 `batterySoc` / `soc` / `batteryLevel` / `stateOfCharge`（以及可选 `rangeKm`）时才出现，
   否则整卡隐藏 —— 固件当前没有这个字段，所以真机上不会显示（不是 bug）。
2. 调研与探测工具：
   - `build/电量SOC-调研.md`：为什么现在拿不到、固件要改哪几处、怎么先用 RAW 捕获确认；
   - `build/tools/soc_probe.py`：扫描 `researchcapture/log.csv`，按"像 SOC 的程度"排出候选 (总线, CAN ID, 字节)。
3. 演示截图 `screenshots/soc-demo.png`（mock 注入 `batterySoc=68, rangeKm=312`）。

## 二十三、v2.0 变更摘要

1. **移除「状态」页顶部三个工具图标**（全部数据 / 立即同步 / 连接引导），导航栏只保留「设备状态」标题；
   这些能力仍可从别处进入：
   - 全部数据：系统 → 数据浏览，或 CAN 卡片底部「查看全部总线字段」；
   - 立即同步：下拉刷新（也与 1.5 秒自动轮询等效）；
   - 连接引导：系统 → 连接 → 「查看连接引导」，离线时首屏也有入口。

## 二十四、v1.9 变更摘要（状态页设计优化 v2.0）

状态页按设计稿重排信息层级，数据口径不变，只改呈现：

1. **Hero 卡合并**「设备身份 + 连接态 + 三路健康 + 同步时间」；
2. 原「车辆实时」7 行键值 → **2×2 KPI 四宫格**（挡位 / AP / NOA / 扭矩，26pt 圆体等宽数字）；
3. **CAN 总线**改为每路"状态胶囊 + 收/发/拒 + 发送成功率进度条 + 帧龄"，新增**接收帧占比条**；
4. **扭矩趋势**增加当前 / 峰值 / 均值三指标 + 均值虚线，坐标轴改为左侧 3 刻度；
5. 新增通用组件 `MetricTile` / `StatusChip` / `SlimProgress` / `RatioBar`，功能列表支持徽章同步换成 `StatusChip`；
6. 颜色/字号/圆角/间距收敛为 token，输出 `build/design-tokens.json`（可导入 Figma Variables）；
7. 完整设计说明见 **`build/设计优化-状态页.md`**，截图 `screenshots/design-01-hero.png`、`design-02-can.png`、`design-03-dark.png`。

## 二十五、v1.8 变更摘要（界面只显示板子的真实状态，不再有默认值）

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

## 二十六、v1.7 变更摘要（修「开关打开没反应」）

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

## 二十七、v1.6 变更摘要

1. **修复「状态」标签图标空白**：`gauge.with.dots.needle.bottom.50.percent` 不是合法 SF Symbol，改为 `gauge.with.dots.needle.50percent`（并全量校验了工程内 54 个符号名，仅此一处有误）；
2. **「蓝牙」标签改为可隐藏**：系统 → 界面 → 「在标签栏显示「蓝牙」」，默认关闭（底部只有 状态/功能/系统）；
   开关切换时标签栏实时重建并保持当前页；正在看蓝牙时关闭会回到状态页；
3. 清理编译警告（S3XY 分组头注册多余 `[weak self]`）。

## 二十八、v1.5 变更摘要

1. **新增 Mac 原生版**（Mac Catalyst）：侧边栏导航、可缩放窗口、全部功能与 iPhone 版一致；
2. ActivityKit 在 Mac 不可用 → 属性模型与控制器做跨平台拆分，Mac 自动隐藏实时活动开关；
3. `CFBundleName` 改为「P4-CAN 工具箱」（Mac 菜单栏不再显示工程名）；
4. 设备族扩到 iPhone + iPad（`TARGETED_DEVICE_FAMILY = 1,2`）；
5. 补本地化：`apDisplayState` / `r79TxState` / `r79TxCount` 等；
6. 本地联调钩子：`P4CAN_TAB` 环境变量或 `p4can.debugTab` 偏好可指定启动标签页（DEBUG）。

## 二十九、仍旧有效的历史变更

- v1.2：按开源固件源码重做接口契约（query 参数）、三路 `can1..can3`、S3XY 槽位与动作绑定、写入门禁；
- v1.3：灵动岛/锁屏实时活动、Swift Charts 扭矩趋势、内置网络抓包、触觉反馈；
- v1.4：模拟器实测修复 `#if DEBUG` 失效、蓝牙页布局塌陷、非法 SF Symbol、字段本地化。
