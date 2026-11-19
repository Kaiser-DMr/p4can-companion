# 实验室与蓝牙 审查

只读审查，未修改仓库、未运行 xcodebuild。代码基准：`P4CAN-Companion`（iOS 17+），固件接口基准 `build/firmware-build/P4-CAN-Universal-v3.29.3/`。

关键前提（影响多条结论）：App 侧 **没有任何 CoreBluetooth 代码**，也**没有声明蓝牙权限**；所谓「S3XY 蓝牙」是设备端 BLE，手机只通过 HTTP over Wi-Fi 代理操作。因此不存在「申请手机蓝牙权限」的时机问题，但 UI 命名会让人误以为要配手机蓝牙（见 3.4）。

---

## 1. 功能现状（逐入口）

| 入口 | 路由（写） | UI 显示的开启条件 | 实际写入闸门 | 进度/结果反馈 |
|---|---|---|---|---|
| 实验室标签页 | — | 仅 `featuresStatus.lab` 为 true 时才出现在标签栏（`AppEnvironment.swift:811-817`、`RootTabBarController.swift:116`）；列表里**不显示**任何车型/总线徽标 | — | 无（仅一条风险脚注 `LabView.swift:24-27`） |
| R79 AP 控制 | `/api/r79/ap-control/update` | 页面无横幅；`FeatureDetailView` 会因 `section == .lab` 显示「先启用 LAB」 | 4 参数缺一即 400；LAB 关闭 403 `lab-disabled`（`web_api.h:4249-4257`） | 每个控件一次 POST，成功后 toast + 回读一次；无回读比对 |
| R79 状态 | 只读 | 同上 | — | 键值表 |
| 召唤心跳覆盖 | `/api/lab/summon-heartbeat/update` | 同上；**不看** stats 里的 `supported/state` | LAB 关闭 409、车型不符 409 `Invalid vehicle topology`（`web_api.h:4066-4075`） | toast；`state`（UNSUPPORTED / WAIT_STOCK / ACTIVE）只在原始表底部 |
| 自动拨杆变道 ALC | `/api/lab/auto-lane-change/update` | 「需实验室功能开启」仅在英文摘要里；运行前提 AP 激活未说明 | LAB 关闭 409（`web_api.h:4566-4567`）；bus 仅收 1/2/3 | toast；无 gate 状态提示 |
| 主驾车窗一键开 | `/api/lab/driver-window/open` | **实际不判定**：`supportKey: "supported"` 在 features/profile 里不存在（`FeatureCatalog.swift:910`），恒为「支持」 | 仅 Model YL + TRIPLE_YL（`driver_window_lab_pure.h:14-18`）；非 P 档/信号过期/占用 → 202/409（`web_api.h:3984-3989`） | 只有「已执行」toast；`availability`/`lastResult` 不解释 |
| CAN 研究捕获 | `/api/researchcapture/start`、`/config`、`/mode`、`/labels`、`/reset` | 同上；A–D 四个按钮无前置就绪检查 | LAB 关闭 409；前置未就绪/正在捕获/正在导出 → 409（`can_research_capture.h:1091-1113`） | 无进度、无剩余时间、无停止入口；失败只剩 HTTP 409 |
| 捕获标签（子页） | `/api/researchcapture/labels` | 与父页一致（无独立判定） | slot+label 必填，1–63 字节；空值被拒（`can_research_capture.h:311-315`） | 逐槽串行保存，部分失败不回滚 |
| 驾驶员监控捕获 | `/api/drivermonitor/start`、`/reset` | 无 | LAB 关闭 409（`web_api.h:2803`） | 同研究捕获 |
| Mode H 调参（独立页） | `/api/nag/h-profile/update` + `/api/nag/update?modeHStopBehavior` | 无横幅（不查 LAB / 车型 / setupMode） | 13 参数一次提交；`ho1<=ho2` 等跨字段校验（`web_api.h:4209-4213`） | 2.4s 轮询实时引擎；应用分两步提交，无回读校验 |
| S3XY 蓝牙页 | `/api/s3xy/*` | 标签可见性 = BLE 总开关（`AppEnvironment.swift:91`） | BLE 关闭 409 `bluetooth disabled`（`web_api.h:1811-1815`） | 2s 轮询；结果靠页眉一行 status；无确认、无重试 |
| 连接引导 | — | 首页离线横幅「排查」/ 设置页入口（`DashboardView.swift:119-127`、`SystemView.swift:636`） | — | 三步说明 + 就地测连 |

关于问题 4（长时任务）：Mode H 是设备端常驻引擎，退出页面继续运行，页面只是 1.2 s 轮询（`ModeHView.swift:177,251-256`），重进会重新读取；研究捕获/DMS 捕获也是设备端进行，**没有 stop 语义**（固件只提供 reset 丢弃），App 既没有说明这一点，也没有用已上报的 `capturing/remainingMs/segment` 做任何恢复展示。

---

## 2. 问题清单

### P1

[P1] 关闭蓝牙总开关会当场删掉「蓝牙」标签页 — 在蓝牙页把总开关关掉后，`featuresStatus.s3xy`（等于 BLE 总开关，`web_api.h:2927`）变 false，`applyTabSet` 移除该标签并把用户弹回状态页；页面上再也点不到「开」 — `S3XYDevicesViewController.swift:193-203`、`AppEnvironment.swift:91`、`RootTabBarController.swift:116-123` — 功能自我删除，用户必须猜到去「功能 → S3XY」才能恢复；首页卡片还写着「在『蓝牙』标签页完成扫描、配对与动作绑定」（`DashboardView.swift:810`），而此时该标签不存在 — 标签可见性改用与 BLE 开关解耦的界面偏好，或关掉后保留标签并就地提示「已关闭，可在此重新开启」。

[P1] LAB/S3XY 总开关写入失败仍提示「已开启」 — `setFeaturesGate` 在 `command` 之后无条件把自己的提示覆盖到 `environment.toast`（成功与失败都覆盖），于是 403/超时也会显示「实验室已开启，底部出现『实验室』标签」 — `FeaturesView.swift:540-563`、`AppEnvironment.swift:676-683` — 用户以为已开启，标签却没出现，无法判断是没开还是失败 — 只在成功分支写提示；失败时保留 `command` 的错误 toast（必要时附「设备未确认」）。

[P1] 车窗入口的能力判定引用不存在的字段 — `supportKey: "supported"`，而 `features/status`/`profile/status` 的能力位里没有 `supported` 这个键（`web_api.h:2873-2885`），`capability()` 返回 nil 被当作「支持」 — `FeatureCatalog.swift:909-911`、`FeatureDetailView.swift:32-35` — 非 Model YL 车型上按钮可点，结果只有 HTTP 409；用户无从知道要 Model YL — 改读模块 stats 的 `supported`（`web_api.h:3960`），并补充「仅 Model YL（Triple YL）」前置说明。

[P1] 实验室命令失败只回裸 HTTP 码或固件英文串，且已有原因字段未使用 — `interpret` 对无 `error` 键的非 2xx 一律抛「请求失败：path（HTTP 409）」，对有 `error` 的直接抛英文 `lab-disabled` / `busy` / `Invalid vehicle topology` — `P4APIClient.swift:424-435`；对照固件已上报 `availability/lastResult`（`web_api.h:3960-3972`）、`state`（`web_api.h:4013-4038`）、`capturing/fullReason`（`web_api.h:2374-2380`）— 车窗属安全相关动作，用户不知道是「未 P 档」「信号过期」还是「车型不支持」，只能反复点 — 建立 409/403 的语义映射（至少车窗 arm 结果、心跳 state、捕获 state），并按读数显示原因。

[P1] 连接引导的「已加入家庭 Wi-Fi」段落对 v3.29.3 不成立 — 引导让用户「把设备地址改为设备在新网络中的 IP」，但固件只有 SoftAP（`p4_network.h:55`），`/api/wifi/apply` 仅换 SSID/密码并重启热点，注释明确「Only the SoftAP is recycled」（`web_api.h:1792-1796`）；这与本 App 无线页「IP 仍为 192.168.4.1」（`WirelessView.swift:159-161`）直接矛盾 — `ConnectionGuideView.swift:73-79` — 按引导操作的用户会把地址改成不存在的 IP，彻底失联，且引导里的「系统 → Wi-Fi 配置」入口名也不存在（实际是 设置 → 无线，`WirelessView.swift:72`） — 删除该段，改为「改热点名后需重新加入新 SSID，地址仍为 192.168.4.1」。

[P1] 研究捕获/DMS 捕获无进度、无停止、无失败原因 — A–D 与 A–F 按钮 `confirmation:false`、无就绪检查（`FeatureCatalog.swift:936-974,1019-1048`），`fire()` 只发一条 POST 再 `load()`（`FeatureDetailView.swift:665-669`）；固件在「正在捕获/前置未就绪/正在导出」时返回 409 且 body 无 error（`can_research_capture.h:1091-1113`、`web_api.h:2478-2487`）— 长时任务不可控；同一 App 的后雾灯爆闪却做了专用页（进度条 + 剩余时间 + 停止，`RearFogStrobeView.swift:21-29,152`），同类能力两套标准 — 为捕获增加状态条（`capturing`/`remainingMs`/`segment`）、开始按钮按 `preSnapshotsReady==preSnapshotSlots` 禁用，并明确「捕获无法停止，只能完成后导出或重置」。

### P2

[P2] Mode H 缺 `HO1 <= HO2` 交叉校验 — 客户端只校验四组 min<=max（`ModeHView.swift:325-341`），固件要求 `ho1ThresholdRaw <= ho2ThresholdRaw`（`mode_h_pure.h:538-540`）并回一长串英文范围说明（`web_api.h:4209-4213`）— 用户把 HO1 调到 2.0、HO2 保持 1.0 时提交必失败，错误串很长且是英文 — 提交前补 HO1<=HO2（以及 rescue delay 等同样的区间检查）并给出中文原因。

[P2] Mode H「停车行为」默认值会在读取失败时静默覆盖设备设置 — `stopBehavior` 初值 1（STOCK CARRIER），仅在首次加载时用 `try?` 从 `/api/nag/config` 取一次，失败静默；而 `apply()` 无条件写回该值 — `ModeHView.swift:24,265-269,376-378` — 设备原本是 HARD PAUSE 时，一次「应用调参」会顺带把它改成 STOCK CARRIER，用户没有被告知 — 改用 stats 里已存在的 `stopBehavior`（`web_api.h:4128`），取不到就禁用该次写入（不提交该参数）。

[P2] Mode H 分两步提交，无回滚、无回读校验 — 先 `h-profile/update` 再 `nag/update?modeHStopBehavior`，两步各自 toast，第二步失败会覆盖第一步的成功提示（`ModeHView.swift:373-382`）；随后 `loadForm(force:true)` 用回读值刷新，但没有比对是否与请求一致 — 部分生效时用户看到的是「第二步失败」，实际参数已改一半 — 合并为一次 UI 事务：任一步失败即标注「参数已写入/停车行为未写入」，并对比回读值给出差异。

[P2] Mode H 页缺条件横幅，且首包会覆盖用户正在编辑的值 — 该页不查 `isLabEnabled` / `isSetupMode` / 车型能力，与 `FeatureDetailView` 的三条横幅（`FeatureDetailView.swift:52-70`）不一致；滑杆在 `formLoaded` 之前可拖动，`loadForm(force:false)` 到位后直接覆盖 — `ModeHView.swift:61-159,263-269` — setup 模式下仍可点「应用」；弱网下用户调好的数值被静默改写 — 复用详情页的横幅判定，并在 `formLoaded` 前禁用滑杆或提示「读取中」。

[P2] 心跳覆盖不看 `supported`/`state`，UNSUPPORTED 与 WAIT_STOCK 无法区分 — 模块 `supportKey: nil`（`FeatureCatalog.swift:836-866`），stats 已给出 `supported` 与 `state`（`web_api.h:4013-4038`），但只在原始键值表里出现；开关照常可点，车型不符才在提交时回 409 英文 — `FeatureCatalog.swift:847-865`、`web_api.h:4071-4075` — 「打开了但一直没生效」的典型困惑（WAIT_STOCK 是在等原厂帧）— 用 `state` 在控制区顶部显示一行状态并据此禁用开关。

[P2] S3XY 破坏性操作没有二次确认 — 「忘记设备」「重置全部蓝牙」「清除 S3XY 记录」点击即发（`S3XYDevicesViewController.swift:274-276,376-381`），无确认弹窗、无撤销 — 与 Lab 里重置捕获需要 `confirmationDialog` 的做法不一致 — 误触会清掉全部 BLE 注册，需重新扫描配对 — 三个动作统一加 destructive 确认，并说明后果（是否重启）。

[P2] S3XY 无连接状态机与超时反馈，开关会被轮询拉回 — 所有动作都是 POST 后立刻 `refresh()`（`S3XYDevicesViewController.swift:193-203,339-356`），但固件是排队异步执行（202，`web_api.h:1817-1869`）；`refresh()` 每 2 s 用设备值重设 `UISwitch`（`S3XYDevicesViewController.swift:561-569`） — 关闭可能返回 202 `stopping:true`，界面先显示「已关闭」，下一次轮询又弹回开；连接/握手同理，看不到「连接中→失败原因」 — 提交后进入本地 pending 态并延迟轮询（或按 `stopping` 继续追），超时明确报「未在 N 秒内确认」。

[P2] BLE 总开关在两处重复实现 — 「功能 → S3XY」走 `/api/features/s3xy`（内部转调 `httpS3xyBluetoothEnable/Disable`，`web_api.h:3313-3315`），蓝牙页页眉走 `/api/s3xy/bluetooth-enable|disable`，两者改同一位（`web_api.h:2927`）— `FeaturesView.swift:373-384`、`S3XYDevicesViewController.swift:193-203` — 同一状态两条路径、两种文案、一套会隐藏另一套 UI；排障时无法判断是谁关的 — 收敛为一个入口（建议蓝牙页只读显示总开关，关闭动作跳功能页），或至少统一文案并互相跳转。

[P2] 捕获标签无法清除，且部分失败不回滚 — `changes` 只收集非空且变更的槽（`ResearchLabelsView.swift:18-23`），空值等于「保持不变」；固件也拒绝空标签（`can_research_capture.h:311-315`）；多槽保存中途抛错时不刷新 `loaded`、不提示哪些已写入（`ResearchLabelsView.swift:126-145`）— 标签一旦写入永久存在，只能改写；部分成功状态与 UI 不一致 — 明确写「标签不可清空，只能改写」，并按槽回报成功/失败（或先快照再汇总）。

[P2] 连接引导的步骤顺序与真实权限时机不符，且被拒后无恢复路径 — App 在 `scene(willConnectTo:)` 就 `environment.start()`（`SceneDelegate.swift:37`），首个 `/api/snapshot` 在启动瞬间发出，本地网络弹窗因此出现在「第 1 步加入热点」之前（甚至用户还没加入热点）；引导只写「回到 App 后会弹出…请点允许」（`ConnectionGuideView.swift:31-41`），没有「已拒绝怎么办」，且「打开无线局域网设置」实际用 `UIApplication.openSettingsURLString` 打开的是本 App 的设置页（`ConnectionGuideView.swift:21-26`）— 用户在启动时误点「不允许」后再也看不到该弹窗，引导帮不上 — 改为「若已拒绝：设置 → 隐私与安全性 → 本地网络 → 打开 P4管家」，按钮改名为「打开 App 设置」；步骤 1/2 顺序按真实时序重写。

[P2] ALC 的运行前提未在界面说明，且 LAB 关闭时页面直接变空表 — 摘要只说「需实验室功能开启」（英文），实际注入还要求 AP 激活（`auto_lane_change_enable_pure.h:34-38`）；`/api/lab/auto-lane-change/stats` 本身受 LAB 门控（`web_api.h:4522-4525`），LAB 一旦被关，轮询 409，控件全部回落「未获取」 — `FeatureCatalog.swift:868-899`、`FeatureDetailView.swift:523-533` — 用户看到「读取中/未获取」，以为是网络问题 — 在控制区显示「AP 未激活 / LAB 已关闭」两态，并把 gate 原因接到现有 `autoLaneChangeGateOpen`。

[P2] S3XY 动作绑定列表不过滤当前车型，失败只回英文 — 14 个动作全部列出（`S3XYDevicesViewController.swift:300-315`），固件按车型校验后 409 并回 `"<动作名> unavailable for current CAN topology"`（`web_api.h:1981-1986`）— 研究捕获类动作在 LAB 关闭时也不会生效，界面无任何提示 — 用户选完以为绑定成功（其实那一次是 409，只闪在页眉一行小字）— 按 `featuresStatus` / 当前拓扑过滤或标记不可用项，并给出中文原因。

[P2] 两个近名入口「禁用驾驶员监控」与「驾驶员监控捕获」共存且无对照 — 前者在驾驶辅助（`FeatureCatalog.swift:295-311`），后者在 Lab（`FeatureCatalog.swift:1008-1018`），名称仅差两字，摘要都提 DMS — 用户容易在错误入口找「关闭监控」，而 Lab 那个只是录制 — 至少在两处互相加一行「本页只录制，不改变监控行为」。

### P3

[P3] Lab 列表不显示任何能力徽标 — `LabRow` 只渲染标题+摘要（`LabView.swift:53-77`），而功能页同类行会显示「支持/不支持」chip（`FeaturesView.swift:650-671`，且同样因 `supported` 键缺失而不显示）— 用户在进入前无法判断哪些实验室功能在自己车上可用 — Lab 行也接一份 `featuresStatus` 并显示 chip。

[P3] `LabView` 头部注释与真实目录不一致 — 注释声称顺序为「LAB 总开关 → R79 AP → 召唤心跳 → ALC → 主驾车窗 → 研究捕获」（`LabView.swift:5-6`），实际目录还含 R79 状态、驾驶员监控捕获、Mode H，且页面里没有「LAB 总开关」这一项 — 后续维护者按注释会漏掉新增入口 — 更新注释或去掉枚举式描述。

[P3] 蓝牙页页眉把固件变更记录当用户文案 — 「固件 v3.29.3 已修复蓝牙总开关作用域；开关状态以设备上报为准。」（`S3XYDevicesViewController.swift:514`）— 面向用户的界面出现内部修复说明，且「作用域」对车主无意义 — 换成「开关状态以设备为准，切换后需数秒生效」。

[P3] `command` 在 `isBusy` 时静默丢弃点击 — `guard !isBusy else { return }` 无 toast、无队列（`AppEnvironment.swift:672`），而按钮的 `.disabled(!canWrite || environment.isBusy)` 只覆盖了渲染周期内的忙碌（`FeatureDetailView.swift:430`）— 连点两个 Lab 触发按钮时第二次完全无反应，用户以为卡死 — 至少回一条 info toast「上一个命令执行中」。

[P3] 连接引导页多处硬编码中文，未走 L10n — 「连接引导」「打开无线局域网设置」「设备地址」「完成」（`ConnectionGuideView.swift:21,48,81,85`），而正文都有中英双语 — 英文界面下中英混杂 — 统一走 `L10n.t`。

[P3] 设备地址输入的键盘与校验格式不一致，空输入无反馈 — `keyboardType(.decimalPad)` 只能输数字和点（`SystemView.swift:624-626`），但 `validatedHost` 明确支持 `http(s)://host[:port]` 与主机名（`P4APIClient.swift:208-230`）；输入为空时 `updateHost` 直接 `guard` 返回、无任何提示（`AppEnvironment.swift:253-262`）— 想改端口或写 `http://` 的用户被键盘挡住，空提交像「点了没反应」— 改 `.URL` 键盘，空输入给出错误提示。

[P3] LAB 被外部关闭时标签页突然消失并把用户弹回状态页 — `applyTabSet` 在 `isLabEnabled` 变化时重建标签集合，当前控制器不在新集合里就 `selectedIndex = 0`（`RootTabBarController.swift:114-150`）— 用户正在 Mode H 调参，另一台设备/网页关掉 LAB，页面被无提示替换 — 关闭时保留页面并显示只读横幅，或先提示再切换。

---

## 3. 缺失 / 重复 / 逻辑不合理

1. **缺失：写入失败的可解释性。** 固件在 lab/s3xy 接口里已经把「为什么不允许」写进 stats（`availability`、`state`、`gateOpen`、`capturing`、`fullReason`），App 只用它们做原始键值展示，从不参与决策和文案。
2. **缺失：捕获类任务的会话视图。** 研究捕获与 DMS 捕获没有「进行中 / 剩余 / 已完成段数 / 导出中」的呈现，也没有「开始前检查前置窗口」。后雾灯爆闪有完整会话页，说明能力不缺，只是没做。
3. **缺失：LAB 关闭后的引导。** Lab 标签消失后，App 内没有任何「LAB 在哪开」的指路；`FeatureDetailView` 的「需要先启用 LAB」横幅（`FeatureDetailView.swift:64-69`）在实践中不可达（Lab 标签不存在就进不了 lab 模块）。
4. **重复：BLE 总开关两套实现。** 功能页 `features/s3xy` 与蓝牙页 `s3xy/bluetooth-enable|disable` 同一状态位（`web_api.h:2927,3313-3315`），一套会隐藏另一套的入口。
5. **重复：同类触发在两处。** 研究捕获 A–D 既在 Lab 的模块按钮，又作为 S3XY 按键动作（`Models.swift:183-187`），两处的能力/前置条件提示完全不同（一处什么都没有，一处只回 409 英文）。
6. **逻辑不合理：可见性耦合状态。** 「蓝牙标签是否显示」用 BLE 总开关决定，等于把导航结构绑在一个用户可随时关闭的功能状态上；同理 LAB 标签也绑 `featuresStatus.lab`，导致关闭即失去重开入口（只能绕到功能页）。
7. **逻辑不合理：能力位命名。** `FeatureCatalog` 用 `supportKey: "supported"`（window、vision），但 `features/status` 的能力位命名空间里没有这个键（`web_api.h:2873-2885`），这类「通用词」键必然解析失败且静默当作支持。
8. **文案矛盾。** 车窗模块中文「仅 Model 3 配置可用」、英文「Model YL only · PARK required.」（`FeatureCatalog.swift:904-907`），固件是 YL + TRIPLE_YL（`driver_window_lab_pure.h:14-18`）；连接引导的「家庭 Wi-Fi / 新 IP」与无线页「IP 仍为 192.168.4.1」矛盾（见 P1）。

---

## 4. 优先修复顺序（最多 5 条）

1. **断开「蓝牙标签可见性 = BLE 总开关」的耦合**（P1#1）：否则用户按一次关就在 App 里永远回不去，属于自锁。
2. **修 `supportKey: "supported"` 与车窗/心跳的能力与原因呈现**（P1#3、P1#4）：涉及安全相关动作（车窗），必须让用户看到「为什么不能开」。
3. **修 `setFeaturesGate` 的假成功 toast**（P1#2）：开关类操作是所有实验室功能的总闸，误报会让后续所有排障失真。
4. **重写连接引导的三步顺序与「家庭 Wi-Fi」段落，补本地网络被拒的恢复路径**（P1#5、P2#16）：直接影响首次可用性，且当前文案会把用户引导到失联状态。
5. **给研究捕获/DMS 捕获加状态与就绪检查，并把 409 映射成可读原因**（P1#6、P2#11）：长时任务目前完全不可控，且失败信息为零。

（Mode H 的 `ho1<=ho2` 与 `stopBehavior` 静默默认值紧随其后，属 P2 但改动量小、风险收益比高。）
