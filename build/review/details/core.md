# 核心层与契约 审查

> 审查对象：`/Users/k/WorkBuddy/2026-11-17-19-25-27/P4CAN-Companion`
> 只读审查，未修改任何仓库文件；未运行 xcodebuild。
> 固件基线：`build/firmware-build/P4-CAN-Universal-v3.29.3/web_api.h`

## 1. 现状与基线

### 1.1 契约检查（必须执行项）

```
$ python3 build/tools/check_api_contract.py
契约一致：路径与参数全部匹配固件实现。
EXIT=0
```

输出摘要：0 处不一致，退出码 0。

补充核对（本次审查额外做的静态比对，非脚本能力）：

- `P4Route` 共 95 个路径常量，固件 `server.on(...)` 注册 109 条路由；**App 使用的 95 条全部在固件注册表中存在**，无孤儿路由（python 正则比对，结果为空集）。
- 唯一未被引用的常量是 `P4Route.otaUpload`（仅客户端内部使用），属正常。

脚本覆盖面的局限（不是失败，是"绿灯的边界"）：

- 只比对 **路径存在性** 与 **提交参数名**（`check_api_contract.py:103-129`）。不校验 HTTP 方法（GET/POST）、不校验取值范围、不校验"固件必填但 App 未提交"的缺失参数、不覆盖 `statsPath` / `trigger` / `/update`。
- 参数名正则 `ARG_CALL` / `ARG_NAME`（`check_api_contract.py:22-23`）只能识别 `arg*("x")` / `argName(x) == "x"` 两种固件写法，其他读参风格会被判为"不接受该参数"。

### 1.2 工程基线

| 项 | 值 | 证据 |
|---|---|---|
| 部署目标 / Swift | iOS 17.0 / Swift 6.0 | `project.pbxproj:214,219` |
| 版本号 | MARKETING 3.30 / BUILD 51（App + Widget 四个配置一致） | `project.pbxproj:245-249,265-269,286-290,308-312` |
| Bundle ID | `com.p4can.companion` / `.widget` | `project.pbxproj:250,291` |
| ATS | 仅 `NSAllowsLocalNetworking`，无 `NSAllowsArbitraryLoads` | `Support/Info.plist:30-34` |
| 版本号来源 | Info.plist 用 `$(MARKETING_VERSION)`，无硬编码双份 | `Support/Info.plist:19-22` |
| 仓库规模 | 308 个跟踪文件，`.git` 43 MB，63 张 PNG 入库 | `git ls-files` / `du -sh .git` |
| 自动化测试 | **无测试 target，无 XCTest / Swift Testing** | `project.pbxproj:93-136` 仅 application + app-extension 两个 target；`grep -rn "XCTest\|@Test"` 无结果 |

### 1.3 已有设计亮点（避免误伤）

- 主 session 拒绝所有 3xx（`P4APIClient.swift:469-479`），响应体再兜底判 300-399（`P4APIClient.swift:430-432`）。
- 日志对 `password/psk/token/...` 打码（`P4APIClient.swift:167-169,450-459`）。
- OTA 走独立 uploader + 900 s 资源超时，与 8 s 状态轮询隔离（`P4APIClient.swift:500-543`）。
- 设计系统按钮热区 44/50 pt、按压即时反馈、尊重"减弱动态效果"（`DesignSystem.swift:140-162`）。
- 离线缓存按 host 隔离、只在成功时写、7 天过期（`OfflineCache.swift:36-58`）。

## 2. 问题清单

共 20 条：**P0 × 1、P1 × 4、P2 × 9、P3 × 6**。

### [P0] 1. `interpret` 把「状态里的 ok:false」当成业务错误，导致 OTA 三条流程在真机上不可达

- 现象：`/api/ota/status` 是固件里唯一 `ok` 为动态值的端点（`web_api.h:2117`：`ok = otaSuccess && !otaError`）。设备**开机后未成功刷写过**时恒返回 `{"ok":false,...,"error":"",...}`。客户端 `interpret` 的判定是"有 `error` 键且 `ok == false || ok == nil` 就抛错"（`P4APIClient.swift:424-429`），空字符串也是非 nil，于是每次读 OTA 状态都抛 `P4APIError("")`。
- 证据：
  - 固件：`web_api.h:2114-2127`（otaStatusJson 恒写 `error` 键）、`web_api.h:2117`（ok 随刷写结果变化）
  - 客户端：`P4APIClient.swift:424-429`
  - 消费方 1：`AppEnvironment.swift:296-297,324`（`try?` 吞掉 → `otaStatus` 恒为 nil）→ `FirmwareUpdateView.swift:37-43` 的"当前升级状态"永远停在 `SkeletonRows`
  - 消费方 2：`AppEnvironment.swift:722`（`attemptBefore` 恒为 0）
  - 消费方 3：`AppEnvironment.swift:753-787` 的 `confirmUpload` 每次 GET 都抛错 → 被当成"设备正在重启"
- 影响：刷写成功后设备重启，`ok` 又变回 false，**确认阶段永远读不到 `stage/attempt`**，只能等满 120 s 打一条"没能确认设备重启"；`otaUploadPhase` 到不了 `.done`，`FirmwareUpdateView.swift:165-177` 的 `FirmwarePackageStore.save` 永不触发（"上次刷写"记录永远为空）。OTA 状态卡片在从未刷写过的设备上也永远骨架屏。
- 建议：`interpret` 区分"状态端点"与"命令端点"——状态端点只在 `ok == false` **且** `error` 非空时才抛；或给 `get` 增加 `treatOkFalseAsError: false` 选项；OTA 状态改为按 `stage`/`http status` 判读。

### [P1] 2. `confirmUpload` 的 `sawDisconnect || rebooted` 会在断线一次后立即宣布成功

- 现象：循环内只要**曾经**有一次 GET 失败，`sawDisconnect` 就永久为 true；之后任意一次成功读到的状态（哪怕 `stage == "write"`、`inProgress == true`）都会命中 `if sawDisconnect || rebooted` 直接返回 `.done` 并提示"固件已写入，设备已重启"。
- 证据：`AppEnvironment.swift:754,777-781`（`sawDisconnect` 跨轮次不复位）、`AppEnvironment.swift:783-786`（任何错误都记为"重启中"，包括超时/500）
- 影响：弱网或设备写 flash 期间 HTTP 被阻塞（固件写 flash 会卡住 WebServer）时极易触发，把"还在写"误报成"已写入"。修掉 #1 后这条会立刻成为主路径。
- 建议：`sawDisconnect` 只在**连续 N 次失败后**才算"重启过"；恢复后必须以 `stage == "idle" && attempt 归零` 或 `stage == "complete"` 为准，不允许 `sawDisconnect` 单独成立。

### [P1] 3. 命令与页面级轮询不参与"独占操作"互斥，OTA 期间仍有并发写/大量读

- 现象：`refreshOnce` 有 `guard exclusiveOperationDepth == 0`（`AppEnvironment.swift:273`），但 `command()` 完全不看该闸门（`AppEnvironment.swift:666-684`），页面级轮询也不看。OTA 上传期间 `isBusy` 仍为 false，所有开关按钮仍可点（`FeaturesView.swift:322,334`、`SystemView.swift:574` 都只判 `isBusy`）。
- 证据：
  - `AppEnvironment.swift:708-719`（只加 depth，不置 `isBusy`）
  - `AppEnvironment.swift:666-674`（命令入口只判 `isBusy`）
  - 页面轮询：`HeadlightStrobeView.swift:433-442`（800 ms）、`RearFogStrobeView.swift:17,177-186`（500 ms）、`FeatureDetailView.swift:29,222-227`（1200 ms）、`ModeHView.swift:252-255`（1200 ms）、`NagAdvancedView.swift:339-346`（1500 ms）、`LiveDataView.swift:194-202`（3 s × 30 端点）
- 影响：固件是单线程 WebServer 且 OTA 写 flash 时会阻塞；此时任何 500 ms 轮询或 POST 都在抢唯一连接，拖慢甚至中断写入（固件 `web_api.h:2135-2138` 已明确"WebServer resets this client to 5 s"这类敏感性）。
- 建议：把 `exclusiveOperationDepth`/`otaUploading` 提升为唯一的"操作闸门"，`command()` 与所有页面轮询统一走它（或统一由 AppEnvironment 提供 `pollStats(path:)`）；OTA 期间把全局 `isBusy` 置 true。

### [P1] 4. 状态双源：6 个页面各自轮询并各自持有 `stats` 副本，与全局 500 ms 快照并存

- 现象：`AppEnvironment` 明明已经持有 `fastGroups/slowGroups` 与各端点的最新值，但详情页、爆闪页、后雾灯页、Mode H 页、高级参数页、全部数据页都自己再拉一份存在 `@State var stats`，且刷新节奏互不相同。
- 证据：`HeadlightStrobeView.swift:24,433-442`；`RearFogStrobeView.swift:17,177-186`；`FeatureDetailView.swift:29,222-236`；`ModeHView.swift:252-268`；`NagAdvancedView.swift:339-360`；`LiveDataView.swift:32,194-202`（还会反向覆写 `fastGroups/slowGroups`：`AppEnvironment.swift:613-616`）
- 影响：同一字段在两处不同步（例如爆闪页显示 `state=STOPPED`，首页仍显示旧的 `ACTIVE`）；`LiveDataView` 用 3 秒前的旧快照覆盖 500 ms 的新快照；请求量在设备端叠加成 2–5 倍。
- 建议：页面只读 `environment.group(...)` / `environment.stat(...)`，需要更高频就在 AppEnvironment 里加一个"订阅式"按需加速项（例如进入详情页把该端点加入 fast 组），而不是另开一条轮询。

### [P1] 5. 前大灯"间隔"滑杆上限 500 ms，固件接受 50–1000 ms，保存即静默改写用户配置

- 现象：`RulerSlider(range: 50...500)`，而固件 `intervalMs` 校验为 50..1000 并原样落盘（`web_api.h:5747-5751`，`headlight_strobe.h:92-96`）。当设备里存的是 800 ms 时，页面把 `clampedValue` 显示成 500、`position` 也停在 500；用户只要点一次"保存参数"，就会把 800 改成 500 写进 NVS。
- 证据：`HeadlightStrobeView.swift:246-253`（range 50...500）、`HeadlightStrobeView.swift:447-449`（读回 800 → `intervalMs = 800`）、`RulerSlider.swift:43-45,78-88`（越界值被 clamp 显示，但 binding 仍是 800）、`HeadlightStrobeView.swift:482-487`（保存时提交 `intervalMs`）
- 影响：静默改变设备行为（爆闪半周期变短、总时长算错），且用户看不出被改过；`totalDurationText` 也按 500 算，与实际不符。
- 建议：range 改为 `50...1000`；或在 `loadConfig` 时对越界值显式提示"设备当前值超出可调范围"。契约检查脚本应增加取值域比对（见 #14）。

### [P2] 6. `isBusy` 是静默丢弃，不是排队也不是反馈

- 现象：`guard !isBusy else { return }`，无 toast、无日志、按钮也不会因它而禁用（多数页面只 `disabled(environment.isBusy)`，但 800 ms 级轮询与命令竞争时用户仍可能点到）。
- 证据：`AppEnvironment.swift:672-674`
- 影响：用户点按后"什么都没发生"，与固件 400 的表现无法区分，现场排查困难。
- 建议：至少给一条 `toast`（"上一操作尚未完成"）或把命令做成串行队列。

### [P2] 7. 响应大小限制是"收完再检查"，没有流式截断

- 现象：`checkSize` 在 `session.data(for:)` 返回**之后**才执行（`P4APIClient.swift:253-255,264-266,273-278`），此时整段 body 已在内存；`P4FirmwareUploader` 的 `buffer.append` 也无上限（`P4APIClient.swift:574-582`）。
- 证据：`P4APIClient.swift:461-465`、`P4APIClient.swift:254,265,277`
- 影响：4 MB / 32 MB 的"上限"只挡住了 JSON 解析，不挡内存峰值；异常端点仍可把 App 撑到 OOM。恶意/错配的 AP 更容易打崩。
- 建议：用 `URLSessionDataDelegate` 在 `didReceive data` 里累计并 `cancel()`，或改用 `bytes(for:)` 逐块读取。

### [P2] 8. OTA 上传 session 没有重定向拦截，与主 session 策略不一致

- 现象：主 session 用 `P4RedirectBlocker` 拒跳转（`P4APIClient.swift:199-203`），`P4FirmwareUploader` 自建 session 的 delegate 是 `self`，**未实现** `willPerformHTTPRedirection`，因此跟随 3xx。
- 证据：`P4APIClient.swift:531-541`（新建 session）、`P4APIClient.swift:558-624`（delegate 扩展里无重定向回调）
- 影响：伪造热点可把一次 OTA 请求 302 到别处（body 已发但会继续握手），至少造成"上传后状态不可解释"；安全策略出现例外路径。
- 建议：uploader 也实现 `willPerformHTTPRedirection` 返回 `nil`，并在 `didReceive response` 里对 3xx 直接 `cancel()`。

### [P2] 9. 未限制每主机连接数，9 路并发请求打到"一次只服务一个客户端"的固件

- 现象：`URLSessionConfiguration.default` 的 `httpMaximumConnectionsPerHost` 保持默认 6；`refreshOnce` 一拍内并发 9 个请求（`AppEnvironment.swift:283-305`），`loadAllEndpoints` 每批再并发 4 个（`AppEnvironment.swift:588-601`）。
- 证据：`P4APIClient.swift:190-204`（未设置该属性）、`AppEnvironment.swift:283-305`
- 影响：排队请求各自计 8 s 超时（`P4APIClient.swift:191`），设备稍慢就会出现"随机几条超时"的假故障；日志里表现为同一拍部分 200 部分超时。
- 建议：`configuration.httpMaximumConnectionsPerHost = 1`（或 2），并把 meta 端点错峰到不同 tick。

### [P2] 10. 错误映射三套并存且都不完整

- 现象：`AppEnvironment.friendly`（`AppEnvironment.swift:908-926`）、`probeReason`（`AppEnvironment.swift:642-661`）、`P4ShortcutRunner.message`（`P4Shortcuts.swift:56-98`）各写一套 URLError switch，覆盖面互不相同。三套都没覆盖 `.badServerResponse`、`.secureConnectionFailed`、`.serverCertificateUntrusted`、`.cannotLoadFromNetwork`、`.resourceUnavailable`、`.httpTooManyRedirects`、`.userAuthenticationRequired`。
- 证据：同上；三套的 case 集合对比：friendly 有 7 个、probeReason 3 个、intent 2 个
- 影响：同一故障在 App 内、离线横幅、快捷指令里给出三种说法；证书/ATS 类问题会直接掉到 `localizedDescription`（英文系统文案）。
- 建议：收敛成一个 `P4ErrorText.message(for:)`，三处复用；补齐上述 case。

### [P2] 11. 英文界面下大面积中文残留（含"全部数据""状态"这些核心页）

- 现象：全仓含中文字面量 1200 处，其中 664 处未包 `L10n.t`。主要分布（未本地化数 / 该文件中文串总数）：
  - `Core/P4JSON.swift` 243 / 243 —— `P4KeyLocalization.table` 是中文-only 字典（`P4JSON.swift:208-212`），英文界面下每个字段名仍是中文
  - `Core/FeatureCatalog.swift` 196 / 196 —— 模块有 `titleEN/summaryEN`（`FeatureCatalog.swift:117-124`，24 个模块齐全），但 `FeatureControl.title`、`option.label`、`footnote` 无英文列
  - `Features/S3XY/S3XYDevicesViewController.swift` 66 / 66 —— UIKit 页整页中文，不随语言切换
  - `Core/AppEnvironment.swift` 25 / 25 —— 所有 toast 与诊断摘要（`AppEnvironment.swift:258,511,514,677,688,695,734,748,764,774,779,790`）
  - `Core/Models.swift` 21 / 21 —— S3XY 动作名（`Models.swift:174-180`）
- 证据：上述行号 + `P4JSON.swift:126,171,184`（P4Format 的"开启/关闭/秒/是/否"）
- 影响：选了 English 后，功能页控件标题、全部数据页字段名、蓝牙页整页仍是中文，属于"半汉化"，比全中文更容易误导。
- 建议：`P4KeyLocalization` 改双列（zh/en）并走 `L10n`；`FeatureControl`/`Option` 增加 `titleEN`/`labelEN`，缺省回退英文键名而不是中文；S3XY UIKit 页统一改 `L10n.t`。

### [P2] 12. 可访问性：Toast 不播报、若干部件 a11y 文案写死中文

- 现象与证据：
  - `ToastOverlay` 只有视觉呈现，没有 `AccessibilityNotification.Announcement`（`Components.swift:140-157`）→ 命令成功/失败对 VoiceOver 用户完全不可感知
  - `RatioBar` 的 label 前缀固定中文（`Components.swift:522`）、`StateBadge` 拼 `"\(text)状态"`（`Components.swift:66`）、`SlimProgress` 兜底 `"进度"`（`Components.swift:471`）、`MetricTile` 用中文逗号拼读（`Components.swift:442`）
  - 这些部件同时被英文界面复用，VoiceOver 会中英混读
- 影响：核心结果反馈对无障碍用户不可达；本地化在朗读层再次漏掉。
- 建议：toast 出现时 `UIAccessibility.post(notification: .announcement, argument: message)`；a11y 文案全部走 `L10n.t` 并用 `", "` 连接。

### [P2] 13. mock 与固件在关键端点上差异过大，恰好掩盖了 #1/#2

- 关键差异（左侧 mock，右侧固件）：
  1. `OTA["ok"]` 恒 `True` 且 `error` 是 **Bool**（`mock_p4can.py:465,955-967`）→ 固件是 `ok=false`（未刷写过）+ `error` 字符串（`web_api.h:2114-2127`）。**mock 永远复现不出 #1**。
  2. `/api/headlight-strobe/stats` 缺 `durationMs/stopMode/maxRunMs/mode/totalMs/elapsedMs/raw249Hex/beamState/cksumSelfTest/rx249/holdArmed/holdPullMaxMs/holdPullTotal/lastBeam`（`mock_p4can.py:534-548` vs `web_api.h:5666-5725`）。
  3. `/api/headlight-strobe/config` 的 POST 只接受 `count/intervalMs/trigger/holdEnabled`，对 `durationMs/stopMode/maxRunMs/holdDelayMs` 静默忽略（`mock_p4can.py:789-809`）→ 固件全部支持并校验（`web_api.h:5763-5801`）。App 若少传参，mock 不会报错。
  4. 固件"运行中写配置"回 **409**（`web_api.h:5733-5736`），mock 回 **400**（`mock_p4can.py:984-985`）。
  5. 固件 `supported = (variant == STALK)`（`web_api.h:5692`），mock 恒 `True`（`mock_p4can.py:540`）→ 无拨杆车型分支测不到。
  6. `/update` 固件校验镜像、按块 `Update.write` 并可能 `begin/write/end` 失败（`web_api.h:2133-2225`），mock 收任意字节（含 0 字节）直接 `stage=complete`（`mock_p4can.py:948-981`）。
  7. `?groups=lab` / `?groups=settings` 固件返回**扁平**对象（`web_api.h:5945-5955`），mock 返回 `{fast,slow}`（`mock_p4can.py:907-914`）。
  8. 前大灯 trigger 固件会因 `NO_STOCK_TEMPLATE/TURN_SIGNAL_ACTIVE/STALKLESS_UNSUPPORTED` 拒绝（`web_api.h:5815-5822`），mock 只校验 trigger 源（`mock_p4can.py:811-818`）→ App 的 `reasonText` 映射有大半测不到（`HeadlightStrobeView.swift:404-414`）。
- 影响：本地联调全绿，真机首刷即踩 #1；参数增删在 mock 侧无感。
- 建议：把 mock 的 `OTA` 初始值改成 `ok=False, error=""`，字段对齐 `otaStatusJson`；补齐 headlight 的 14 个字段与 4 个可写参数、409 状态码、`supported` 可变；`/update` 至少校验长度下限与 `0xE9` 魔数。

### [P2] 14. 契约脚本的"绿灯"小于实际契约面

- 现象：`check_api_contract.py` 只做两件事：catalog 里 `path:` 是否注册、`FeatureControl` 提交的参数名是否在固件 `arg("...")` 集合里。
- 证据：`check_api_contract.py:102-107`（只查路径存在）、`110-129`（只查参数名）、无 method / range / 必填 / statsPath / trigger / `/update` 检查
- 影响：`intervalMs` 上限不一致（#5）、固件必填但 App 不传、GET/POST 挂错、`statsPath` 拼错（`FeatureCatalog.swift` 里 24 个 `statsPath` 完全没被检查）都不会被拦。
- 建议：增加 (a) `server.on` 的 HTTP 方法比对；(b) 从固件 `if (value < X || value > Y)` 抽范围与 catalog `range:` 比对；(c) 覆盖 `statsPath`、`P4Param(`、"无查询串的 POST"。

### [P3] 15. RulerSlider 刻度点击热区 14 pt、状态胶囊彩色小字对比度不足

- 现象：每个刻度宽 `tickWidth`（14/18/26 pt）且用 `onTapGesture` 命中（`RulerSlider.swift:31-33,171-175`），横向命中宽度远小于 HIG 44 pt；`DS.Pill` 用 `tone.color` 作前景压在 `tone.color.opacity(0.12)` 上（`DesignSystem.swift:47-50`），`systemGreen/systemOrange` 的 caption 文字在浅色下对比度约 2–3:1。
- 影响：手指/辅助点选容易点错刻度；低视力用户读不清状态色文案。颜色本身有 SF Symbol 兜底（`Theme.swift:128-152`），文字对比度是主要缺口。
- 建议：刻度命中区域至少 44 pt（透明 `contentShape` 加宽）；Pill 文字改 `.primary`，只让圆点着色（`StatusChip` 已是这个做法，见 `Components.swift:191-198`）。

### [P3] 16. 调试用环境变量覆盖不在 DEBUG 分支

- 现象：`P4CAN_HOST` 在 `init()` 里无条件读取并覆盖设备地址（`AppEnvironment.swift:201-207`），其余 11 个 `P4CAN_*` 变量都在 `#if DEBUG` 内。
- 影响：Release 包保留了一条"用环境变量改设备地址"的路径（正常 App Store 分发拿不到环境变量，风险低，但不符合"调试开关仅 DEBUG"的自我约束）。
- 建议：把这段包进 `#if DEBUG`，或至少要求 release 构建忽略。

### [P3] 17. 死代码与组件重复

- 未使用：`DS.Card`（`DesignSystem.swift:101`）、`DS.Pill`（`:30`）、`DS.Metric`（`:63`）、`DS.SectionHeader`（`:16`）、`ButtonStyle.dsPrimary/dsSecondary`（`:212-221`）、`StateBadge`（`Components.swift:54`）、`Theme.TypeScale.mono`、`Theme.p4Hairline`（`Theme.swift:61,95`）——全部引用数为 0/1（脚本统计）。
- 重复：两套 `Card`（`Components.swift:6` 在用 vs `DesignSystem.swift:101` 未用）；三套状态徽章（`DS.Pill` / `StatusChip` 在用 / `StateBadge` 未用）；两套命令通道（`environment.command` vs 各页直接 `environment.api.post`，后者绕过 `isBusy`，见 #3）。
- 建议：删掉未用组件，或让它们成为唯一实现（避免下次有人用错一套）。

### [P3] 18. 文档版本与工程版本漂移

- 现象：`pbxproj` 是 3.30 (51)，README 徽章写 `3.16 (37)`、下载链接写 `v3.20`（`README.md:6,8`）。
- 影响：发版核对成本，issue 里报的版本对不上。
- 建议：README 版本改成从 `project.pbxproj` 抄，或加一条发版清单。

### [P3] 19. 离线/取消路径的小问题（合并）

- `OfflineCache.load` 在主线程同步 `Data(contentsOf:)` + JSON 解码（`OfflineCache.swift:52-58`），由 `restoreCacheIfNeeded`（`AppEnvironment.swift:396-415`）在 MainActor 上调用；缓存大时首屏会顿一下。
- 无 `scenePhase` 处理：`environment.start()` 只在 `scene:willConnectTo` 调一次（`SceneDelegate.swift:38`），`stop()` 全仓无调用点 → 后台仍按 500 ms 轮询直到系统挂起；回前台也没有立即刷新。
- 离线重试无退避/抖动：固定 5 s（`AppEnvironment.swift:164`）；每次失败后还额外发一条 `probeReason` 请求（`AppEnvironment.swift:363`），离线时等于每 5 s 多一次 8 s 超时。
- `probeReason` 在探测**成功**时返回"未知错误"（`AppEnvironment.swift:642-645`），语义误导。
- 建议：缓存读取挪到后台队列；接 `scenePhase`；失败退避 5→10→20 s 并加抖动；探测成功时改用"部分接口失败"文案。

### [P3] 20. `performUpload` 里"设备拒绝写入"分支不可达

- 现象：`uploadFirmware` 内部走 `interpret`，`ok:false` 会先抛 `P4APIError`（`P4APIClient.swift:346`），所以 `if json["ok"]?.boolValue == false`（`AppEnvironment.swift:731-739`）永远进不去，落进下面的通用 catch（`:746-749`）。
- 影响：少见但有意义的"设备明确拒绝"与"网络失败"被合并成一条笼统提示。
- 建议：修 #1 后自然会走到；或改为在 catch 里识别 `P4APIError` 给专门文案。

## 3. 缺失 / 重复 / 逻辑不合理

**缺失**

- 固件已有的 4 个可写参数 App 未暴露：`durationMs`（0 或 100–30000）、`stopMode`（0–2）、`maxRunMs`（500–60000）、`holdDelayMs`（0–10000）（`web_api.h:5763-5801`）。`holdDelayMs` 只被读来显示（`HeadlightStrobeView.swift:448`），改不了。
- 后雾灯无 config 端点（固件也只有 start/stop/stats），App 侧一致，但页面上没有"剩余时长"之外的窗口说明，属信息缺失。
- 无测试 target、无 CI：`build/mock/CoreSmokeTest.swift` 是一个手工编译的 `@main` 程序（需先起 mock），不在工程内、不进构建、不进 CI。
- 无请求取消入口：OTA 上传没有"取消"按钮，`Task` 也未随页面消失取消（`FirmwareUpdateView.swift:335-346`）。一次 900 s 超时的上传会锁住 `otaUploading` 直到超时。
- 无 `retry-after`/退避策略，也没有把"设备忙（503 reboot/409）"与"网络失败"区分开的统一处理。

**重复**

- 页面级轮询 6 处（见 #4），每个都自己 `while !Task.isCancelled { get; sleep }`。
- 三套 URLError → 文案映射（见 #10）。
- 两套 Card、三套状态徽章、两套命令通道（见 #17）。
- 两套语言判定：`L10n.resolved`（`L10n.swift:67-71`）与 `P4IntentLanguage.isEnglish`（`P4Shortcuts.swift:9-18`）。**结论是一致的**（都读 `p4can.language`，`system` 都按 `Locale.preferredLanguages` 前缀 zh 判定），但逻辑复制意味着以后改一处会漂移。

**逻辑不合理**

- `interpret` 先判 `error` 键、后判 HTTP 状态码（`P4APIClient.swift:425-435`）：任何"带 error 键但其实是状态"的端点都会被误判（#1 的根因）。
- 注释说"每 4 拍刷新 meta"（`AppEnvironment.swift:8`），实际 `tick % 4` 在 500 ms 节拍下是每 2 秒，而 slow 每 1 秒（`AppEnvironment.swift:277-278`）。注释与行为不一致（行为本身没错，注释错）。
- `refreshOnce` 在 `phase != .online` 时才置 `.connecting`（`AppEnvironment.swift:274`），所以在线期间不会闪；但 `updateHost` 后 `phase = .idle` + `start()` 会立刻重建 Task，旧 Task 的取消若不及时，可能有一拍重复轮询（`AppEnvironment.swift:253-268`）。
- `LiveDataView` 的 `autoRefresh` 关闭后循环仍每 3 s 醒来（`LiveDataView.swift:196-201`），只是不发请求——无害但不必要。
- `RulerSlider` 的 `onAppear position = clampedValue` 与 `onChange(of: value)` 组合，会在"外部值越界"时把显示与 binding 分叉（#5 的技术根因）。
- `P4FirmwareUploader` 完成后不清 `buffer`/`progressHandler`（`P4APIClient.swift:545-555`），单次上传后残留一份响应副本。

## 4. 优先修复顺序（最多 5 条）

1. **#1 `interpret` 误判 `ok:false`**（P0）—— 一处改动同时修好 OTA 状态卡片、`attemptBefore`、`confirmUpload` 与刷写记录；修完立刻把 mock 的 `OTA.ok` 初始值改成 `False`，否则回归测试仍然是假绿。
2. **#2 `sawDisconnect ||` 误判成功**（P1）—— 紧跟 #1，否则 #1 修好后"OTA 成功"会变成假阳性，比原来更危险。
3. **#5 `intervalMs` 范围 50–500 → 50–1000**（P1）—— 一行改动，避免"打开页面点保存就静默改设备"；顺手补 #14 的取值域检查，防止再犯。
4. **#3 + #4 统一轮询与互斥**（P1）—— 把页面级轮询收敛进 `AppEnvironment`，`command()` 与轮询共用 `exclusiveOperationDepth`/`otaUploading` 闸门；这是设备端"抢连接"和"状态双源"的共同根因。
5. **补测试基线（第 3 节"缺失"项）**（P1）—— 建一个 XCTest target：`interpret` 的 ok/error 矩阵、`confirmUpload` 状态机（可注入桩客户端）、`ZipArchive` 往返、`P4APIClient.validatedHost` 边界。当前最高风险模块正是这四处：`P4APIClient`（网络 + OTA 状态机）、`AppEnvironment.confirmUpload`、`FeatureCatalog`（95 个路由 + 全部参数名/范围）、`OfflineCache`（编码兼容）。
