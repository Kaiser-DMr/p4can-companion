# 设置与维护 审查

审查范围：`P4CANCompanion/Features/System/`（SystemView / FirmwareUpdateView / FirmwareChangelogView / WirelessView / VehicleProfileChangeView / DiagnosticsView / NetworkLogView）、`App/P4Shortcuts.swift`、`App/RootTabBarController.swift`、`App/SceneDelegate.swift`、`Core/AppEnvironment.swift`（设置持久化 / OTA）。
对照固件：`build/firmware-build/P4-CAN-Universal-v3.29.3/web_api.h`、`vehicle_profile.h`、`P4-CAN-Universal-v3.29.3.ino`（`FW_VERSION "v3.29.3"`）。
只读审查，未修改仓库。

---

## 1. 功能现状（按分组）

### 1.1 车型（SystemView.ProfileSection / VehicleProfileChangeView）
- 车型卡片展示 `profileName`、`fwVersion`、拓扑、拨杆、NAG/ADV EAP/EU UNLOCK 能力位，`badge` 缺失时用首字母兜底（`SystemView.swift:204-231`）。字段名与 `p4CanWriteStatus` + `writeProfileCapabilityJson` 一致（`web_api.h:2873-2885`、`2896-2909`）。
- 5 个车型 ID 与固件枚举一致（`vehicle_profile.h:8-12` 对 `VehicleProfileChangeView.swift:21-32`），topology 1=YL / 2=STANDARD 一致（`vehicle_profile.h:16-19`）。
-  Highland 强制选拨杆，其余固定 STALK；`turn` 始终随 query 发送，固件仅对 Highland 读取（`web_api.h:3135-3141`）。
- 保存：`POST /api/profile/select` → 固件持久化成功后 300 ms 重启（`web_api.h:3156-3163`）；App 成功后弹「车型已保存」并提示重连（`VehicleProfileChangeView.swift:177-182`）。
- 失败：设备端先校验再写 NVS，失败仅回 400/409/500/503 且不落盘（`web_api.h:3103-3159`），因此无需回滚；App 捕获 `P4APIError` 直接展示错误（`VehicleProfileChangeView.swift:233-249`）；非 `P4APIError`（回包丢失）时用 20 s 回读 `profile/status` 确认（`:254-263`）。
- 入口在 `isOnline == false` 时禁用（`SystemView.swift:297`）。

### 1.2 系统操作分级（重启 / 两级重置 / 恢复出厂 / 封禁）
- 四级动作均有 `confirmationDialog` + `role: .destructive` + 说明文案（`SystemView.swift:66-83`、`394-418`、`123-138`）；恢复出厂文案含「此操作不可撤销」（`:134-136`），二级重置文案逐条说明保留项，与固件行为一致（`web_api.h:3403-3424`、`3429-3463`、`3468-3481`）。
- 封禁 / TLSSC 恢复为红色 DANGER 分组，开启前二次确认（`SystemView.swift:502-537`、`84-99`、`558-571`），关闭直接发 `enabled=0`（`:565-569`）。
- 危险动作按钮本身不做离线 / `isBusy` 门禁（`:396-418`）；`command()` 在 `isBusy` 时静默返回（`AppEnvironment.swift:672`）。

### 1.3 App 设置（语言 / 外观 / 刷新间隔 / 设备地址 / 实时活动）
- 四项均持久化：`p4can.language` / `p4can.appearance` / `p4can.poll.ms` / `p4can.device.host`（`AppEnvironment.swift:109-111`、`166`、`253-268`、`450-499`）。
- 外观即时同步到 `window.overrideUserInterfaceStyle`（`SceneDelegate.swift:29-31`）；刷新间隔在下一拍生效（`AppEnvironment.swift:163`、`237-246`）；语言切换重建标签栏标题（`RootTabBarController.swift:96-99`）。
- 地址校验：允许 `http(s)://host[:port]` 与 `host[:port]`，拒绝账号/路径/查询/空白（`P4APIClient.swift:206-230`）；非法输入弹失败 toast（`AppEnvironment.swift:256-262`）。
- 实时活动开关在设置页（`SystemView.swift:603-614`）与首页（`DashboardView.swift:874-885`）各有一份。

### 1.4 数据浏览 / 日志导出 / 诊断包
- 数据浏览 30 个端点（`AppEnvironment.swift:127-160`），4 并发分批拉取并记录逐端点错误（`:578-626`）。
- 日志导出 6 个文件（`Models.swift:209-243`），固件侧路由均存在（`web_api.h:6004`、`6008`、`6042`、`6012`、`6005-6006`）；导出为下载到临时目录再 `UIActivityViewController` 分享（`AppEnvironment.swift:795-801`、`SystemView.swift:762-773`）。
- 诊断包 zip = `diagnostics.txt` + `network-log.csv` + `snapshot.json`（`AppEnvironment.swift:868-896`），store 模式自写 zip（`ZipArchive.swift:11-60`）。
- 脱敏：query 中 `password/passwd/psk/token/...` 记为 `***`（`P4APIClient.swift:167-169`、`450-459`），网络日志页展示的也是脱敏串。

### 1.5 OTA
- 选包：`fileImporter` + 扩展名 `.bin`、拒绝 `.merged`、≥64 KB、≤8 MB（`FirmwareUpdateView.swift:193-214`、`298-320`）；本地算 SHA-256 展示前 12 位并与上次刷写比对（`:88-96`、`FirmwarePackage.swift:30-32`）。
- 上传：独立 `P4FirmwareUploader`（60 s 请求 / 900 s 资源超时、字节级进度）（`P4APIClient.swift:289-363`、`504-624`）；期间 `exclusiveOperationDepth` 暂停主轮询（`AppEnvironment.swift:177`、`273`、`714-716`）。
- 确认：`stage == "complete"` 或「曾断线 + 读到 idle」或 `attempt` 回落判成功，120 s 上限（`AppEnvironment.swift:753-793`）。
- 上次刷写记录：`otaUploadPhase == .done` 时写入 `UserDefaults`（`FirmwareUpdateView.swift:167-178`）。

### 1.6 快捷指令
- 两个 `AppIntent`（前大灯爆闪 / 后雾灯爆闪），`openAppWhenRun = false` 后台执行，按保存的 host 新建轻量 client（`P4Shortcuts.swift:44-53`、`104-144`）。
- 错误映射覆盖超时/不可达/`NO_FRAME`/`ALREADY_ACTIVE`/`TURN_SIGNAL_ACTIVE`/`SOURCE_MISMATCH` 等（`:56-98`）。
- 注册 `AppShortcutsProvider` + 设置页说明 + `ShortcutsLink()`（`:149-175`、`SystemView.swift:796-828`）。

### 1.7 版本与诊断
- `appVersionText` 取 `CFBundleShortVersionString/CFBundleVersion`（`AppEnvironment.swift:831-835`），工程 `MARKETING_VERSION = 3.30`、`CURRENT_PROJECT_VERSION = 51`（`project.pbxproj:249/245`），Info.plist 用变量引用（`Support/Info.plist:19-22`）→ 显示 3.30 (51)，一致。
- `diagnosticsSummary` 含 App 版本、host、在线状态、固件、车型、拓扑、三路 CAN、蓝牙/LAB、OTA stage/attempt/error（`AppEnvironment.swift:839-865`）。

### 1.8 根导航
- `RootTabBarController` 按 LAB / S3XY 闸门动态增删标签并保持当前选中页（`RootTabBarController.swift:128-166`）；语言切换刷新 UIKit 标题（`:168-179`）。
- `SceneDelegate` 注入外观回调与窗口尺寸限制，`environment.start()` 启动轮询（`SceneDelegate.swift:33-36`）。

---

## 2. 问题清单

### P0

**[P0] OTA 写入成功后「确认重启」阶段必然失败，最终停在「未完成」** — 现象：上传 100% → 「已发送，等待设备重启确认」→ 120 s 后变红「未完成」，且「上次刷写」记录不写入；用户会以为刷写失败而重复刷写。— 证据：设备重启后 `otaSuccess` 复位为 false，`/api/ota/status` 返回 `ok:false` 且 `error:""`（`web_api.h:2117-2119`，全局复位见 `vehicle_logic.h:5508-5510`）；`get()` 见到 `ok:false` 且 `error` 非 nil（空串）即抛 `P4APIError`（`P4APIClient.swift:424-429`）；`confirmUpload` 只把「HTTP/URLSession 失败」当断线，`P4APIError` 也落进同一 `catch` 置 `sawDisconnect`（`AppEnvironment.swift:758-786`），而 `if sawDisconnect || rebooted` 只在 `do` 成功路径里求值，因此读不到 `stage=="idle"` 与 `attempt` 回落，循环空转 120 s 后置 `.failed`（`:788-792`）。— 影响：核心维护功能给出错误结论；`FirmwarePackageStore` 记录（`FirmwareUpdateView.swift:167-178`）永不触发。— 建议：`confirmUpload` 内改用「裸 HTTP 读取 + 不抛 ok:false」的状态解析（或在 `P4APIClient` 增加 `getStatus` 宽容入口）；显式判定 `stage == "idle" && attempt < attemptBefore` 即成功；`P4APIError` 不应置 `sawDisconnect`。

### P1

**[P1] Wi-Fi 只改密码（SSID 留空）必定失败，并清空已输入内容** — 现象：只填新密码点「应用热点设置」→ 设备 400 `missing ssid`，toast 报失败；随后 SSID/密码输入框被清空，需重输。— 证据：`WirelessView.swift:208-212` 在 `ssid` 为空时不发 `ssid`；固件强制要求 `ssid`（`web_api.h:1760-1762`），空密码才表示「保持不变」（`:1766-1774`）；失败后仍执行清空（`WirelessView.swift:214-215`）。— 影响：常见需求（只换密码）不可用；失败即丢输入。— 建议：未填 SSID 时用 `wifiStatus.ssid` 回填后一起提交；仅在命令成功后清空；客户端先校验 8–63 位。

**[P1] 「TLSSC 恢复」开关的前置条件与文案都和固件相反** — 现象：单独打开「TLSSC 恢复」必失败（设备 409），且弹窗写「开启后可能导致车辆被封禁」，而固件语义是「车辆已被封禁后的恢复覆盖」。— 证据：`SystemView.swift:168-171`（文案）、`:512-519`（独立开关）；固件要求 `bannedCar == true` 才允许开启（`web_api.h:3294-3296`）；TLSSC 关闭时 `banned` 也被强制关（`:3276`）。— 影响：危险功能在错误前提下可点，失败只得到英文原文；文案误导用户对风险方向的理解。— 建议：`banned == false` 时禁用并提示「请先开启『封禁车辆』」；修正英文/中文文案；开启 TLSSC 时若未开 banned，先联动开启再二次确认。

**[P1] 「封禁车辆」在数据缺失时默认「支持」，离线也能操作** — 现象：冷启动/离线（`featuresStatus == nil`）时两个危险开关仍是可点的 ON/OFF 样式。— 证据：`supported` 缺省为 `true`（`SystemView.swift:497-500`）、只按 `!supported || isBusy` 禁用（`:574`）。— 影响：离线误点无反馈失败；危险开关在未知能力状态下向用户暴露。— 建议：`featuresStatus == nil` 时改为不可用 + 「未知机型能力」；与「更改车型」一致，用 `isOnline` 门禁。

**[P1] 一次瞬时超时会被判成「固件已写入，设备已重启」** — 现象：确认阶段只要出现过一次 GET 失败（例如 8 s 超时），随后任意一次读到的状态（哪怕 `stage=="write"`、`inProgress=true`）都会命中 `sawDisconnect` 分支并立即报成功。— 证据：`AppEnvironment.swift:777-780`（`if sawDisconnect || rebooted` 未校验 stage 是否为终态）。— 影响：刷写失败/未完成时误报成功，用户不会补刷。— 建议：仅当「断线 + 重连后 `stage=="idle"`」或「`attempt` 较上传前回落」判成功；`sawDisconnect` 单独不足以判定。

**[P1] 设备端 OTA 错误原文从不显示（字段类型读错）** — 现象：「当前升级状态」里的错误行永远不出现，即使设备已记录 `Update begin failed / write failed`。— 证据：`FirmwareUpdateView.swift:42` 用 `ota["updateError"]?.stringValue`，但固件把 `updateError` 写成 `u32` 错误码（`web_api.h:2121`），字符串在 `error` 字段（`:2119`）；`P4JSON.stringValue` 仅对 `.string` 返回（`P4JSON.swift:92-95`）。— 影响：排障信息丢失，用户只看到「未完成」。— 建议：改读 `ota["error"]`，并保留 `updateError` 数字作为次要信息。

**[P1] 选包只校验扩展名与大小，无镜像头/板型校验** — 现象：任意 ≥64 KB 的 `.bin`（改名的图片、别的板子的镜像、`.merged` 漏改名之外的全量包）都能进入刷写流程，设备 `Update.write` 也不会拒。— 证据：`FirmwareUpdateView.swift:298-320` 仅 `hasSuffix(".bin")`、`!contains(".merged")`、大小区间；`P4APIClient.uploadFirmware` 只判空与 8 MB（`P4APIClient.swift:295-297`）。— 影响：刷入非应用镜像可能导致设备无法启动（需串口救砖）。— 建议：校验 ESP32 镜像魔数 `0xE9`、image header 的 chip id 与 app 分区大小；不匹配直接拒绝并说明原因。

**[P1] 设备地址输入框无法输入端口/scheme，应用后无反馈且输入框不同步** — 现象：键盘是 `.decimalPad`，只能打数字和「.」，无法输入 `http://` 或 `:8080`（而校验逻辑声称支持）；点「应用地址并连接」成功后输入框仍是旧文本、按钮仍可用，也没有成功提示或「测试连接」。— 证据：`SystemView.swift:624-634`；`hostField` 只在 `onAppear` 同步一次（`:628`）；`updateHost` 成功后不改 `hostField`、只有失败 toast（`AppEnvironment.swift:253-268`）。— 影响：与 mock/自定义网段联调不可用；用户无法确认地址是否已生效。— 建议：`.URL` 键盘或 `.asciiCapable`；成功后回写 `hostField = environment.host` 并给成功 toast；增加「恢复默认 192.168.4.1」和连通性探测。

**[P1] 语言切换只覆盖了一部分界面，大量字符串硬编码中文** — 现象：英文模式下仍有中文：命令结果 toast、地址错误提示、实时活动提示、离线原因、整个网络日志页、日志文件标题、数据浏览页标题/footer、布尔值展示、诊断摘要。— 证据：`AppEnvironment.swift:258`、`677`、`680`、`511`、`514`、`645-660`；`NetworkLogView.swift:15-24`、`45`、`47`；`Models.swift:216-237`；`LiveDataView.swift:27`、`42`、`64`、`69`、`74`；`P4JSON.swift:128-129`；`AppEnvironment.swift:842-864`。— 影响：设置页文案承诺「语言切换立即生效」，实际中英混杂。— 建议：把这些串统一走 `L10n.t`；`P4JSON.displayText` 改成注入本地化函数。

**[P1] 诊断页 / 无线页自建轮询绕过 OTA 的「暂停轮询」** — 现象：三处仍用自己的 `environment.api` 直连：诊断页每 2 s、无线页每 3 s，不受 `exclusiveOperationDepth` 影响；失败时静默保留旧值。— 证据：`DiagnosticsView.swift:109-114`、`164-168`；`WirelessView.swift:76-81`、`168-175`；`AppEnvironment.swift:177`、`272-273`（只拦 `refreshOnce`）。— 影响：固件是单线程 WebServer，后台仍有请求抢连接；诊断页在离线时看不出数据已过期。— 建议：统一走 `environment.refreshOnce`/增加共享 gate；`load()` 失败时记录 `lastError` 并在页面标注「数据时间」。

**[P1] `AppEnvironment.applyWiFi` 是重复且会「失败当成功」的死代码** — 现象：内部先 `command(... refresh: false)`，随后无条件写入 info toast「已提交：设备 SoftAP 将以新 SSID 重启」，会覆盖 `command` 刚写入的失败 toast。— 证据：`AppEnvironment.swift:686-699`；全仓无调用点（`WirelessView.swift:205-218` 已另写一份）。— 影响：误用即产生假成功；两份实现行为不一致（一份带 `ssid` 校验、一份不带）。— 建议：删除 `AppEnvironment.applyWiFi`，把 SSID 校验/结果判断收敛到无线页一处。

**[P1] 车型保存不校验在线状态，也不拦截「保存当前同一车型」** — 现象：进入更改车型后断网仍可点「保存车型并重启」；选择与当前完全相同的车型也会触发一次重启（中断正在进行的注入）。— 证据：保存按钮只判 `saving/confirming/selectedVehicle`（`VehicleProfileChangeView.swift:152`），query 无条件发送（`:219-223`）；固件成功即 `restartP4CanSafely()`（`web_api.h:3161-3163`）。— 影响：无意义重启；注入中断。— 建议：保存前校验 `environment.isOnline`；当 `selectedID == profileStatus.profile && resolvedTurn == 当前 turn` 时按钮置灰并提示「已是当前车型」。

**[P1] 20 s 回读窗口偏短，且失败后错误文案会指向网络** — 现象：POST 回包丢失后 `confirmApplied` 最多等 20 s；设备重启 + CAN 初始化常超过该窗口，超时后展示的是 `friendly(URLError)`「连不上设备」，不是「已保存但未确认」。— 证据：`VehicleProfileChangeView.swift:254-263`、`:246-249`。— 影响：用户误判为保存失败，重复保存（再次重启）。— 建议：延长到 45–60 s；超时文案改为「已提交，设备可能正在应用新车型，请回设置页确认」。

### P2

**[P2] 四个系统动作共用「确认执行」按钮，且无 busy/离线门禁** — 现象：确认弹窗按钮不重述动作；动作执行中/离线时四个按钮都可再点，第二次点击被 `command()` 的 `guard !isBusy` 静默丢弃（无任何提示）。— 证据：`SystemView.swift:74`、`396-418`；`AppEnvironment.swift:672`。— 影响：误触后无反馈；恢复出厂这类不可逆操作缺少「明确指向动作」的二次确认。— 建议：按钮文案改为动作名（「恢复出厂并重启」）；动作期间禁用整组并给运行中状态。

**[P2] 固件英文错误原文直接透传进中文界面** — 现象：409/500 时 toast/错误行显示 `not available in setup mode`、`restore not allowed for current state/profile`、`CAN stop not confirmed; retry reboot`。— 证据：`P4APIClient.swift:425-429`、`433-435`；`web_api.h:3295`、`3431`、`3435`。— 影响：中文用户看不懂，也不知道下一步做什么。— 建议：建立设备错误码/前缀映射（`NO_FRAME`、`SOURCE_MISMATCH` 已在快捷指令里做过，可复用）并保留原文折叠。

**[P2] 诊断包内容偏薄且未声明隐私范围** — 现象：只有摘要 + 网络日志 + `mergedStats`；缺 `system/stats` 全量、`profile/status`、`features/status`、`s3xy/stats`、启动抓包、App 设置（语言/外观/刷新间隔）。而 `mergedStats` 合并了 `wifiStatus`（含 SSID / IP）。— 证据：`AppEnvironment.swift:868-896`、`424-428`；`Web_api.h` 未返回密码（`web_api.h:1767`）故密码不泄漏。— 影响：排障信息不足；分享 zip 时用户不知道其中含 SSID/IP。— 建议：补入上述端点与设置快照；页脚明确「包含设备 SSID 与内网 IP，不含 Wi-Fi 密码」。

**[P2] 「上次刷写」记录因 [P0] 几乎永不写入，且无法清除** — 现象：记录依赖 `otaUploadPhase == .done`；同时 `FirmwarePackageStore.clear()` 无调用点，也没有「清除记录」入口。— 证据：`FirmwareUpdateView.swift:167-178`；`FirmwarePackage.swift:44-46`。— 影响：SHA 比对功能形同虚设；换包后仍显示旧记录。— 建议：与 [P0] 一起修；增加「清除上次刷写记录」并加入 confirm。

**[P2] 固件变更记录里的「当前」标记对补丁条目恒为 false** — 现象：`matchesCurrent` 对非 base 条目直接 `return false`，标题注释却写「能对上就打勾」。— 证据：`FirmwareChangelogView.swift:81-85` 对 `:6` 的注释承诺。— 影响：用户无法判断当前固件包含哪个补丁（补丁版本串同为 v3.29.3）。— 建议：用 `systemStats` 中可区分字段（如 `canHarness`、爆闪 stats 是否存在）判定，或明确标注「无法从版本号区分」。

**[P2] 实时活动开关在设置页不判 `isLiveActivitySupported`，且与首页重复** — 现象：不支持实时活动的设备在设置页仍可打开，开关「成功」但无活动；首页同功能开关是禁用的。— 证据：`SystemView.swift:603-614` 无 `.disabled`；`DashboardView.swift:883` 有；`AppEnvironment.swift:503` 提供该判定却未被使用。— 影响：两处行为不一致。— 建议：设置页复用同一判定，删除首页或设置页其一。

**[P2] 切换设备地址后不清空上一台设备的数据** — 现象：`updateHost` 只换 client 与 phase，`fastGroups/profileStatus/...` 与 `isShowingCachedData` 保留；首次轮询成功前界面仍显示旧设备数据。— 证据：`AppEnvironment.swift:263-268`（未清空），`:396-415`（缓存按 host 分桶，但内存数据未重置）。— 影响：两台设备（如 mock 与真机）切换时误读。— 建议：切 host 时重置所有 `@Published` 数据与 `lastUpdated`，并给「已切换设备，等待数据」状态。

**[P2] 危险开关行把交互控件合并进无障碍元素** — 现象：`.accessibilityElement(children: .combine)` 用在了包含 `Toggle` 的行上，VoiceOver 可能把开关吞并成静态文本，只剩标签。— 证据：`SystemView.swift:578`；`WirelessView.swift:253`（同类写法）。— 影响：辅助功能用户无法操作封禁/TLSSC/蓝牙开关。— 建议：改为 `.contain`，或给 Toggle 单独的 `accessibilityLabel/Value`。

**[P2] OTA 上传/等待阶段无法取消，离开页面后也无全局提示** — 现象：开始刷写后按钮全部禁用，进度条只在固件升级页可见；最长 120 s 的确认阶段没有任何中止路径。— 证据：`FirmwareUpdateView.swift:104-117`（`otaUploading` 时禁用选包/上传）、`:54-78`（仅本页展示）；`AppEnvironment.swift:708-719` 无 cancel 接口。— 影响：误选大包或设备无响应时只能杀 App（会中断上传）。— 建议：加「中止等待」（只停确认轮询，不打断已在发送的 body）并在其他页显示全局进度。

**[P2] 诊断摘要中 CAN 计数在无数据时显示 `0/1`** — 现象：`max(buses.count, 1)` 让「0 路」显示成「CAN 0/1 在线」。— 证据：`AppEnvironment.swift:847`。— 影响：诊断信息不准确，易被误读为「有一路总线」。— 建议：`buses.isEmpty` 时输出「CAN 未上报」。

**[P2] 网络日志「暂停刷新」不暂停采集，页脚未说明** — 现象：开关只冻结列表，`NetworkLog` 仍在记录，恢复后一次性跳变。— 证据：`NetworkLogView.swift:15`、`107-113`。— 影响：用户以为停止抓包，实际仍在写（也仍会被诊断包带走）。— 建议：改文案为「暂停滚动/冻结列表」，或真正停止 append。

### P3

**[P3] 「关于」页固件名与连接方式硬编码** — 现象：显示 `P4-CAN Universal Unlock v3.29.3`，固件实际 `FW_VERSION "v3.29.3"` 且无「Unlock」字样；「连接方式」固定写 `192.168.4.1`，用户改地址后不成立。— 证据：`SystemView.swift:839-841`；`P4-CAN-Universal-v3.29.3.ino:70`。— 影响：信息不准确。— 建议：固件名去掉「Unlock」，连接方式用 `environment.host`。

**[P3] 地址校验不检查 IPv4 段范围，scheme 形式不检查端口区间** — 现象：`192.168.4.999`、`1`、`http://host:0` 均通过。— 证据：`P4APIClient.swift:212-229`（scheme 分支未判 `components.port`，非 scheme 分支未校验各段 ≤255）。— 影响：可保存不可达/无意义地址，只能靠超时发现。— 建议：按 IPv4 逐段校验或要求可解析主机名；端口范围 1–65535 两分支都校验。

**[P3] 选包时在主线程同步读 8 MB 并算 SHA-256** — 现象：大包选中瞬间列表卡顿。— 证据：`FirmwareUpdateView.swift:203`、`224-233`（`Data(contentsOf:)` + `SHA256.hash` 均在 View 上下文同步执行）。— 影响：交互掉帧，iOS 26 上可能触发 hang 检测。— 建议：移到 `Task.detached(.utility)`，先显示「计算中」。

**[P3] 生产视图里散落大量 DEBUG 环境变量分支** — 现象：`P4CAN_SETTINGS_ANCHOR/PAGE`、`P4CAN_PROFILE_CHANGE`、`P4CAN_OTA_FILE/CONFIRM`、`P4CAN_PROFILE_ID` 等直接写在视图 `.task` 中，`P4CAN_OTA_CONFIRM` 还会自动弹出刷写确认框。— 证据：`SystemView.swift:42-55`、`305-311`；`FirmwareUpdateView.swift:146-165`；`VehicleProfileChangeView.swift:196-204`。— 影响：编译期隔离（`#if DEBUG`）尚可，但视图逻辑被调试路径污染，且有「启动即刷写」的误触发面。— 建议：统一收到 `DebugOverrides` 类型，由一处读取。

**[P3] 未使用 / 重复的符号** — `AppEnvironment.isLiveActivitySupported`（`AppEnvironment.swift:503`）、`FirmwarePackageStore.clear`（`FirmwarePackage.swift:44-46`）、`AppEnvironment.applyWiFi`（`:686-699`）；`ActivityShareSheet`（`SystemView.swift:782-790`）与 `DiagnosticsShareSheet`（`DiagnosticsView.swift:211-219`）实现完全重复。

**[P3] 「快捷指令」分组只描述功能，不展示 Intent 实际名称与首次使用前提** — 现象：用户照着「前大灯爆闪」去快捷指令 App 搜不到同名动作（Intent title 是「前大灯爆闪」但分组里写的是「前大灯爆闪 · 立即爆闪」等描述性文字），也没提「首次需打开 App 授权本地网络」。— 证据：`SystemView.swift:796-828`；`P4Shortcuts.swift:107`、`129`、`149-175`。— 影响：配置失败率偏高。— 建议：列出真实 `shortTitle`，并加一条「首次请先在 App 内连上设备」的说明。

---

## 3. 缺失 / 重复 / 逻辑不合理

**缺失**
1. 没有「设备重启中」状态：重启 / 重置 / 改车型 / OTA 后只有一句 toast（`SystemView.swift:76`），随后 `phase` 直接变 `offline`（`AppEnvironment.swift:362-366`），用户看不出「正在重启」还是「连不上」。
2. OTA 无取消、无「重新确认」按钮；120 s 超时后只给一句 info（`AppEnvironment.swift:788-792`）。
3. 快捷指令只有「触发/开始」，没有「停止」：固件已有 `/api/headlight-strobe/stop`、`/api/rear-fog-strobe/stop`（`P4APIClient.swift:118`、`122`），App 未暴露；后雾灯只能等 30 s 自动结束（`FirmwareChangelogView.swift:33-34`）。
4. 设备地址缺「测试连接」「恢复默认」「当前是否在设备热点上」的判定；地址错误时用户只能看到离线原因文本（`AppEnvironment.swift:642-661`）。
5. 诊断包缺设备端完整端点快照与 App 设置项，也缺「本次操作时间线」（用户什么时候点了恢复出厂/刷写）。
6. 「上次刷写」无清除入口（见 P2）。
7. 设置页没有「固件版本 vs App 适配版本」不一致提示：`AboutSection` 写死 3.29.3（`SystemView.swift:839`），设备实报值在 `SystemSection`（`:343-347`），两者冲突时无提示。

**重复**
1. 实时活动开关两处（`SystemView.swift:603-614`、`DashboardView.swift:874-885`），判定逻辑不一致。
2. Wi-Fi 应用两处（`WirelessView.swift:205-218`、`AppEnvironment.swift:686-699`），行为不一致（前者无 ssid 校验、后者假成功）。
3. `UIActivityViewController` 包装两份（`SystemView.swift:782-790`、`DiagnosticsView.swift:211-219`）。
4. 「诊断/恢复」页与设置页都能进 `LiveDataView`（`DiagnosticsView.swift:94-101`、`SystemView.swift:654-665`），入口重复但无害。

**逻辑不合理**
1. `confirmUpload` 用「任何一次读失败」当作重启证据（`AppEnvironment.swift:777-780`），同时把设备明确报错（`ok:false`）当断线（配合 `P4APIClient.swift:425-429`）——两个方向的误判都存在。
2. `command()` 在 `isBusy` 时静默 `return`（`AppEnvironment.swift:672`），调用方（设置页四个危险按钮、诊断页、无线页）都各自维护 `busy`，两套忙闲状态互不感知。
3. `DangerToggle.enable()` 失败后仍 `refreshFeatures()`（`SystemView.swift:190-194`），开关回弹但没有任何「为什么没开」的说明（除通用失败 toast）。
4. `VehicleProfileChangeView.init` 默认选中 Model Y Juniper（`VehicleProfileChangeView.swift:42-46`），若 `profileStatus` 缺失（离线/首帧），UI 会先展示一个与设备无关的默认值；依赖 `loadCurrent()` 在 `onAppear` 纠正。
5. `SystemView` 的「更改车型」用 `isOnline == false` 判离线（`SystemView.swift:297`），`connecting` 阶段仍可点；而 `VehicleProfileChangeView` 完全没有门禁——两层保护不一致。
6. `P4JSON.displayText` 里的布尔值固定中文「开启/关闭」（`P4JSON.swift:128-129`），被首页/诊断/数据浏览共用，语言切换后仍是中文。

---

## 4. 优先修复顺序（最多 5 条）

1. **OTA 确认阶段（P0）**：`confirmUpload` 改为不抛 `ok:false` 的宽容状态读取；`P4APIError` 不计入 `sawDisconnect`；仅以 `stage=="idle" + attempt 回落` 判成功；同时把 120 s 缩短到 45–60 s 并提供「去状态页确认」出口。（`AppEnvironment.swift:753-793`、`P4APIClient.swift:424-429`）
2. **OTA 错误可见性（P1）**：改读 `ota["error"]`，保留 `updateError` 数字；刷写失败时把设备原文与 `stage` 一起展示。（`FirmwareUpdateView.swift:36-46`）
3. **Wi-Fi 设置正确性（P1）**：SSID 留空时回填当前 SSID 再提交；仅成功后清空输入；客户端校验 8–63 位密码；删除 `AppEnvironment.applyWiFi`。（`WirelessView.swift:205-218`、`web_api.h:1760-1774`）
4. **危险开关前置条件与文案（P1）**：TLSSC 恢复与「封禁车辆」联动 + 修正「可能导致封禁」的错误文案；`featuresStatus` 缺失时禁用两个开关；四个系统动作改为动作名按钮并加 `isBusy`/离线门禁。（`SystemView.swift:163-181`、`497-500`、`574`、`74`、`396-418`、`web_api.h:3294-3296`）
5. **设置项一致性与本地化（P1）**：设备地址换 `.URL` 键盘、成功后回写输入框并给成功提示、加「恢复默认」；把命令 toast / 网络日志页 / 日志标题 / 数据浏览标题 / `P4JSON.displayText` 纳入 `L10n`。（`SystemView.swift:624-634`、`AppEnvironment.swift:253-268`、`677-681`、`NetworkLogView.swift:15-47`、`Models.swift:216-237`）
