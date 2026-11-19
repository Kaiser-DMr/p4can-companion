# 状态与数据 审查

审查对象：`/Users/k/WorkBuddy/2026-11-17-19-25-27/P4CAN-Companion`
范围：`Features/Overview/*`、`Core/AppEnvironment.swift`（轮询/合并/缓存/错误态）、`Core/OfflineCache.swift`、`Features/LiveActivity/*`、`P4CANWidget/*`、`UI/Components.swift`。
约束：只读审查，未修改仓库文件；未运行 xcodebuild。已运行 `python3 build/tools/check_api_contract.py`（输出「契约一致」），并用 `build/mock/mock_p4can.py` 在 18080 端口实采响应核对字段类型。

---

## 1. 功能现状（按卡片/子模块，预期用途 vs 实现）

数据主干（`AppEnvironment.refreshOnce` 272-367）：
每拍并行请求 1 个快照 + 8 个慢变端点（283-305），`tick % 2` 带 `slow=1`，`tick % 4` 拉 profile/features/s3xy/ota/wifi/system/das/nagConfig；回来一次性写 `@Published`，再 `rebuildDerived()`（417）重算 `mergedStats` / `canBuses` / 趋势采样 / 实时活动。
`phase` 只有 idle/connecting/online/offline(reason) 四态，**没有「部分陈旧」「单端点失败」的表达**。

| 卡片 | 预期 | 实际实现 | 空值 | 离线 | 单位/精度 |
|---|---|---|---|---|---|
| staleBanner（100-137） | 离线/缓存提示 | 仅 `!isOnline` 时出现；文字分「离线预览（缓存）」/「连接已断开」，时间取 `cachedAt ?? lastUpdated`（112） | 无时间则不显示第二行 | 依赖 `isShowingCachedData`，该标记只在「内存完全无数据」时才置位（397） | 时间 `time: .standard`（无日期） |
| heroCard（139-191） | 车型 + 在线胶囊 + 同步时间 + 间隔 | 车型取 `profileStatus.profileName`；胶囊三态；`updatedText` 取 `lastUpdated` | 车型回退 "P4-CAN"；副标题回退「正在读取设备信息…」 | 离线时仍显示旧车型/旧固件，无降级样式 | 「每 500 ms 自动同步」（218-224）与实际周期不符（见 P1-7） |
| kpiGrid 挡位/AP/NOA（273-293） | 4 个关键指标 | `group("r79").gearName`、`group("nag").apActive`、`group("blink").noaActive` | `boolText(nil)` → "—"；挡位 → "—" | 沿用上一拍值，无「陈旧」标记 | 布尔本地化为「激活/未激活」 |
| kpiGrid 扭矩（294-301、312-315） | 实时方向盘扭矩 | `group("nag").torque` | "—" | 沿用旧值 | `%.2f` + "N·m"（与趋势卡一致） |
| batteryCard（326-369） | 「固件给出才显示」的 SOC | 跨全部端点搜 `batterySoc/soc/batteryLevel/stateOfCharge`，直接当 0–100 用 | 无则整卡不渲染（好） | 缓存里也会被搜到 | `%.0f` +"%"、续航 `%.0f km`；未归一化 0–1 |
| quickStrip（380-433） | NAG/自动转向灯/TLSSC 快捷开关 | 读 `nagConfig.enabled`、`group("blink").enabled`、`group("summon").tlssc`（含 slow 兜底） | `isOn == nil` → 永久「读取中…」（463） | 离线仍可点，仅 toast 报错 | 布尔 |
| canBusCard（473-514） | 三路 CAN 健康度 | `CanBusResolver.resolve(cantraffic, profile)`（Models 55-97） | 空数组时显示一句说明 | 整机离线时仍全绿 | 计数无千分位；状态文本为英文原样 |
| trendCard（633-689） | 「近 3 分钟」扭矩曲线 | `trendSamples` 每次 `rebuildDerived` 追加一点，上限 120（439-445） | <2 点显示等待文案 | 缓存恢复时不采样（414，正确） | `%.2f N·m`，与 KPI 一致 |
| vehicleCard（715-745） | 车型/拓扑/三路角色/能力位 | `profileStatus.canA/canB/canExtra`（730-738）+ `capability()`（823-826） | 能力位 nil 显示 "?"（787） | 沿用旧值 | 布尔三态 |
| bluetoothCard（802-813） | S3XY 蓝牙摘要 | `s3xyStats`（每 4 拍，2–4 s 才更新一次） | "—" | 沿用旧值 | 计数 |
| otaCard（825-851） | 升级中显示进度，失败显示原因 | `otaStatus.inProgress` + `stage/receivedBytes/totalBytes`；失败判断用 `error?.boolValue`（845） | 无数据即「空闲」 | — | 字节走 `P4Format.bytes`（与其它页一致） |
| deviceCard（853-867） | 固件/堆/运行时长 | `systemStats` 优先，`stat()` 兜底 | 缺键直接不显示该行 | 沿用旧值 | `MetricRow` → `P4Format.value`（heap→字节、*ms→时长） |
| liveActivityCard（870-891） | 开启/关闭实时活动 | 只看 `isLiveActivitySupported`（`areActivitiesEnabled`） | — | — | — |
| offlineContent（895-913） | 首次连不上时的空态 | hero + 原因 + 骨架屏 | — | 只在「内存里完全没有数据」时才会出现（34） | — |
| LiveDataView（全 203 行） | 全部 `/api/*` 字段浏览 | 独立 3 s 轮询 30 个端点（194-202、578-626） | 「无可展示的标量字段」 | 未区分「没请求」与「请求失败」（127） | 原始值，按 `P4Format` |
| Live Activity / Widget | 锁屏与灵动岛显示三路总线 + 挡位 + 三个开关 | `activityState()`（519-539）+ `Activity.update`；Widget 只有 ActivityConfiguration | 无总线时不启动（545） | 离线时**不更新也不结束** | 时间 `shortened`；颜色硬编码 green/red |

---

## 2. 问题清单

### [P0] 切换设备地址后旧设备的全部数据与缓存标记都不清理
- 现象：`updateHost` 只改 `host/client/phase` 并重启轮询；`fastGroups / slowGroups / profileStatus / featuresStatus / systemStats / dasStats / s3xyStats / wifiStatus / otaStatus / nagConfig / mergedStats / canBuses / trendSamples / endpointPayloads / isShowingCachedData / cachedAt / lastUpdated / lastLabVisible / lastS3XYVisible` 全部保留。
- 证据：`P4CANCompanion/Core/AppEnvironment.swift:253-268`（无任何清理）、`:51-54`（`hasRenderableData` 为真）、`:397`（`restoreCacheIfNeeded` 的 `guard !hasRenderableData` 于是永不加载新设备缓存）、`:439-445`（趋势采样不清）。
- 影响：把地址改到另一台设备后，页面继续以新地址的名义显示上一台车的车型、挡位、扭矩、CAN 状态与「缓存时间」；新地址不可达时这种张冠李戴会**无限期持续**（横幅还写着「显示断开前的数据」，用户会以为是同一台设备的旧数据）。扭矩趋势图会永久混入两台车的采样点。
- 建议：`updateHost` 内做一次 `resetDeviceState()`（清分组/端点/趋势/缓存标记/`isShowingCachedData`/`cachedAt`/`lastUpdated`），随后立刻 `OfflineCache.load(newHost)`；给 `TrendSample` 加 `host` 字段或在切换时清空。

### [P1] BUS-OFF / STOPPED 的总线被判为「在线」，出现「绿点 + BUS-OFF」的自相矛盾卡片
- 现象：`isOnline = trafficOnline || ready`，只要 `canXReady == true` 就算在线；`busRow` 用 `bus.isOnline ? .ok : …` 决定色调，顶部统计也用 `isOnline` 计数。
- 证据：`P4CANCompanion/Core/Models.swift:51`；`P4CANCompanion/Features/Overview/DashboardView.swift:516-517`、`:528`、`:601-608`。实测 mock 中 `can3State=2`（BUS-OFF）、`can3Ready=true`、`can3TrafficOnline=false` 时，卡片显示绿点 + "BUS-OFF" + 「3/3 在线」；同时 `P4BusState.symbol` 对 "BUS-OFF"（连字符）不匹配 `"BUS OFF"`，图标又退回三角警告（`UI/Theme.swift:129-139`）。
- 影响：总线故障被吞掉——这是状态页最核心的一条数据，绿点会把 BUS-OFF 伪装成健康。
- 建议：`isOnline` 改为 `state == 1 && trafficOnline`；色调由 `state`（0/1/2/3）统一推导，并让 `P4BusState.symbol` 用 `state` 而不是文本匹配；「在线数」用同一判定。

### [P1] 任一慢变端点成功就把整页标为「在线/已同步」，快照冻结无法察觉
- 现象：`gotSnapshot || gotMeta` 即 `phase = .online; lastUpdated = Date()`；`gotMeta` 只要 profile/features/system 三者之一非 nil。快照本身失败时 `fastGroups` 保持不变，页面继续显示上一拍（或上一天）的挡位/扭矩。
- 证据：`P4CANCompanion/Core/AppEnvironment.swift:343-353`；`DashboardView.swift:22-25`（同步时间只认 `lastUpdated`）。
- 影响：设备忙/单线程 WebServer 丢弃 snapshot 时，UI 显示「已同步 · 12:03:44」「在线」，而核心指标其实是旧的；没有任何 per-endpoint 新鲜度可判断。
- 建议：为快照单独记录 `snapshotUpdatedAt`，hero 的「已同步」用快照时间；`phase` 增加「快照陈旧」维度或在快速连失败 3 拍后降级为 warn。

### [P1] 部分成功会清掉「缓存」标记，但页面仍是缓存数据
- 现象：只要 `gotMeta` 为真，就执行 `isShowingCachedData = false; cachedAt = nil; lastUpdated = Date()`，而 `fastGroups` 仍是 `restoreCacheIfNeeded` 从磁盘读进来的旧值。
- 证据：`AppEnvironment.swift:346-353` 与 `:396-415`。
- 影响：设备重启期间（只回 systemStats、不回 snapshot）页面从「离线预览 · 上次缓存」变成「已同步 · 现在」，KPI 与 CAN 卡片却还是旧数据——比不改更糟。
- 建议：缓存标记按「数据来源」跟踪（每个条目一个 source/time），或至少要求 `gotSnapshot` 才能清除 `isShowingCachedData`。

### [P1] Live Activity 离线后既不更新也不结束，锁屏会长时间显示「3/3 在线」
- 现象：`refreshLiveActivity()` 首行 `guard liveActivityEnabled, isOnline else { return }`；离线、后台、`stop()` 都不会推送离线态或 `end()`。`staleDate` 设为 8 小时。
- 证据：`AppEnvironment.swift:542-552`；`Features/LiveActivity/LiveActivityController.swift:40`、`:73`；`P4CANWidget/CanActivityWidget.swift:51-64`（绿勾）。
- 影响：车已熄火/设备断电，锁屏仍显示三路绿勾、NAG「开」；最长 8 小时内没有任何「过期」提示，用户会以为设备还在线。
- 建议：`phase != .online` 时推一帧 `offline` 状态（或在 30 s 后 `end()`）；`staleDate` 改短（如 2 min）；Widget 侧用 `context.isStale` / `updatedAt` 与当前时间比较渲染「已过期」。

### [P1] 实时活动「已开启」提示与真实结果无关，失败无兜底
- 现象：`setLiveActivity(true)` 立即 `liveActivity.start(...)`（fire-and-forget）并弹成功 toast；`Activity.request` 抛错时只 `store(nil)`，用户已被告知「已开启」。之后每 10 s 重试一次，没有上限、没有错误暴露。
- 证据：`AppEnvironment.swift:505-517`；`LiveActivityController.swift:64-80`（catch 内静默）、`:27-29`（`isSupported` 只检查权限）。
- 影响：系统关闭实时活动、达到活动数量上限、扩展被禁用时，开关显示「开」但锁屏什么都没有；用户无法自查。
- 建议：`start` 改成 `async throws` 并把结果回传（成功才弹 toast，失败给 failure 文案 + 关闭开关）；`lastLiveActivityAttempt` 重试加退避与次数上限。

### [P1] 「全部数据」扫描结束时用整批旧结果覆盖实时状态，且与首页轮询并发打同一台设备
- 现象：`loadAllEndpoints` 串行分块拉 30 个端点（每块 4 个），全部结束后才一次性 `fastGroups = …; profileStatus = …; rebuildDerived()`；整个过程持有 `isScanningEndpoints`，但**不参与** `exclusiveOperationDepth`，首页 500 ms 轮询照跑。LiveDataView 每 3 s 再触发一次。
- 证据：`AppEnvironment.swift:578-626`（覆盖率式写入在 613-625）、`:273`（互斥只认 OTA）；`Features/Overview/LiveDataView.swift:30`、`:194-202`。
- 影响：(a) 扫描可能耗时数秒，期间首页已拿到更新的快照，扫描结束后用更旧的数据覆盖回去；(b) 30 端点 + 500 ms 快照同时压 ESP32 单线程 WebServer，容易触发 8 s 超时，`phase` 在 online/offline 间抖动。
- 建议：扫描结果按端点记录 `fetchedAt`，写回时「新覆盖旧」；扫描开始时把首页轮询降频或复用一个 `exclusiveOperationDepth`；LiveDataView 打开时暂停首页轮询。

### [P1] 扭矩趋势窗口与文案不符（120 点 ≠ 3 分钟）
- 现象：注释与卡片都写「约 3 分钟 / 近 3 分钟」，但采样频率=轮询频率（250/500/1000 ms），120 点分别等于 30 s / 60 s / 120 s；且实际周期是「RTT + 间隔」，比设定值更长。
- 证据：`AppEnvironment.swift:80`、`:439-445`；`DashboardView.swift:634`；轮询循环 `AppEnvironment.swift:237-246`。
- 影响：用户在 500 ms 档看到的其实只有 1 分钟数据，X 轴刻度也会与标题矛盾；排查间歇性抖动时会误判时间范围。
- 建议：按时间窗口裁剪（保留 `now - 180s` 内的点）而不是按点数；或用固定 1.5 s 独立采样定时器与轮询解耦。

### [P1] 轮询没有并发保护，也没有场景/后台暂停
- 现象：`refreshOnce` 无 `isRefreshing` 闸门，下拉刷新（`DashboardView.swift:51`、`FirmwareUpdateView.swift:166`、`WirelessView.swift:216`、`ConnectionGuideView.swift:56`）与 `pollTask` 可同时在飞；`stop()` 从不被调用，`SceneDelegate` 也没有 `scenePhase` / `didEnterBackground` 处理。
- 证据：`AppEnvironment.swift:237-251`（`stop()` 无调用点，`grep` 仅定义处）、`:272-367`；`App/SceneDelegate.swift:37`。
- 影响：后返回的旧快照覆盖新快照；失败的那一路把 `phase` 改成 `.offline`，即使另一路刚成功。App 进入后台仍在 2–4 Hz 请求，回到前台时可能叠加一批挂起请求。
- 建议：所有刷新走同一个 `inFlight` 令牌（旧的直接丢弃结果或取消）；在 `SceneDelegate.sceneDidEnterBackground` 调 `stop()`、`willEnterForeground` 调 `start()` 并立即 `refreshOnce()`。

### [P2] 离线判定抖动：每次重试先显示「连接中」，`probeReason` 再加一次完整往返
- 现象：重试时 `phase != .online` 就先置 `.connecting`，8 s 超时后才置 `.offline`；随后 `probeReason` 再发一次 `system/stats`（又是最多 8 s）。离线重试间隔 5 s。
- 证据：`AppEnvironment.swift:274`、`:362-366`、`:642-661`、`:163-164`。
- 影响：设备离线时，顶部胶囊大约 13 s 里有 8 s 显示「连接中」，只有 5 s 显示「离线」，横幅随之反复出现/消失；用户无法判断到底是「正在重连」还是「压根连不上」。
- 建议：引入「连续失败 N 次才转 offline」+ 保持上次 reason；`probeReason` 与主请求合并（快照失败已有 URLError，可直接映射，无需再打一次）。

### [P2] 离线原因直接把 HTTP/内部错误文案上屏，与命令失败的中文文案体系不一致
- 现象：`probeReason` 返回 `P4APIError.message` 原文（如「请求失败：/api/system/stats（HTTP 500）」）或「未知错误」；命令失败走 `friendly()`（908-926）给的是「连不上设备：检查…」这类可执行文案。
- 证据：`AppEnvironment.swift:642-661`、`:908-926`；展示处 `DashboardView.swift:900-903`、`ConnectionGuideView.swift:60-64`。
- 影响：同一类网络故障在首页横幅、连接引导、toast 里是三套措辞；「未知错误」对车主零信息量。
- 建议：`probeReason` 复用 `friendly(error)`，并区分 `URLError` 与 `P4APIError` 两类；「未知错误」改为「设备已响应但数据异常」。

### [P2] 状态页的 OTA 失败提示永远不会出现（字段类型与固件不一致）
- 现象：`if let error = environment.otaStatus?["error"]?.boolValue, error` —— 固件/mock 失败时 `error` 是**字符串**（`"Update end failed: no space"`），`boolValue` 返回 nil，分支不进入；成功时是 `false`。于是「上次升级失败」永远不显示，卡片一律显示「空闲」。
- 证据：`DashboardView.swift:845-848`；`AppEnvironment.swift:761-766`（同一字段按 `stringValue` 读，说明设计上就是字符串）；`build/mock/mock_p4can.py:465`（`"error": False`）与 `:961`（`"error": "Update end failed: no space"`）。
- 影响：升级失败后回到状态页只看到「空闲」，用户以为没升过或已成功。
- 建议：与 `confirmUpload` 一致用 `stringValue`（非空即失败），并回退到 `updateError`；失败态用 `.failure` 胶囊而不是「空闲」。

### [P2] OTA 期间状态页仍显示「每 500 ms 自动同步」，且上传阶段永不复位
- 现象：`exclusiveOperationDepth > 0` 时 `refreshOnce` 直接 return（连 `lastUpdated` 都不动），但 `phase` 仍是 `.online`，hero 仍显示高频同步文案；`otaUploadPhase` 在 done/failed 后没有回到 `.idle`。
- 证据：`AppEnvironment.swift:273`、`:708-719`；`DashboardView.swift:218-224`；`Features/System/FirmwareUpdateView.swift:54`（`!= .idle` 才显示进度区）。
- 影响：升级 1–2 分钟里首页看起来在实时刷新，其实完全冻结；升级完成后固件升级页永久留着一条「上传进度 100%」。
- 建议：增加 `isPollingPaused` 并在 UI 明示「升级中已暂停同步」；`uploadFirmware` 收尾（或 `refreshOnce` 成功后）把 `otaUploadPhase` 复位。

### [P2] 整页以 2–4 Hz 全量重建，`mergedStats` 每拍整体替换
- 现象：`rebuildDerived` 每拍新建 `mergedStats`（fast+slow+7 个端点合并）、新 `canBuses` 数组并赋值给 `@Published`；`DashboardView` 通过 `@EnvironmentObject` 观察整个 environment，任意一个 `@Published` 变化都会让整个 ScrollView 内容重算（含 120 点 catmullRom Chart、多个 LazyVGrid）。
- 证据：`AppEnvironment.swift:417-436`；`DashboardView.swift:18`、`:646-687`。
- 影响：250 ms 档下每秒 4 次全页 diff + 图表重绘，老机型上滑动掉帧、发热、耗电。
- 建议：`mergedStats` 只在内容变化时赋值（`Equatable` 比较），趋势数据单独放到轻量 `ObservableObject` 或用 `Canvas`/降采样；图表 X 轴不必每拍重绘。

### [P2] 电池 SOC 取值域未校验
- 现象：跨端点搜到 `batterySoc/soc/batteryLevel/stateOfCharge` 后直接 `/100` 并 `%.0f` 展示，`<= 20` 判「电量偏低」；没有 0–1、0–1000（‰）或 >100 的处理。
- 证据：`DashboardView.swift:326-333`、`:346-366`。
- 影响：若某版固件按 0–1 上报（`0.68`），界面显示「1%」+ 红色低电量条；反之 >100 时数值与进度条不一致。
- 建议：按值域归一化（`<=1` 视为比例、`<=100` 视为百分比，其余视为无效并降级为 `—`），并且在 label 上标明来源键名。

### [P2] 三路 CAN 的角色名按固定顺序绑定，拓扑切换后会错标
- 现象：`roleNames = [canA, canB, canExtra]` 直接按 index 1/2/3 绑定，忽略固件同时给出的 `routeABus/routeBBus`；`displayName` 在 `roleName != codeName` 时追加括号。
- 证据：`Core/Models.swift:61-65`、`:32-38`；`build/mock/mock_p4can.py:141-142`（`routeABus:1`、`routeBBus:2`）、`:851-852`（拓扑 1 时 `canA="PARTY"`、`canB="VH"`）。
- 影响：拓扑 1（Party + VH）下首屏出现「CAN 1 · BODY（PARTY）」「CAN 2 · CHASSIS（VH）」这种自相矛盾的总线名，排查时极易误判。
- 建议：用 `routeABus/routeBBus` 定位总线号，`canExtra` 单独匹配 codeName；roleName 与 codeName 冲突时只显示其中一个。

### [P2] 三个快捷开关把「未知」当「支持」，且离线时仍可点
- 现象：`supported: environment.capability("nagSupported") != false` —— nil（尚未拉到 features/profile、或缓存缺字段）视为支持；Toggle 的 `disabled` 只包含 `!supported || isBusy || isSetupMode`，不含 `!isOnline`。
- 证据：`DashboardView.swift:387-388`、`:403-404`、`:419-421`、`:457-466`。
- 影响：冷启动/离线时用户点开关只会得到一条失败 toast；能力位未知时也看不到「不支持」提示，与 `capabilityGrid` 的「?」表达不一致。
- 建议：`supported == true` 才允许交互；未知时显示「—/未知」并禁用；离线时禁用并给出「设备离线」说明。

### [P2] 同一屏里「在线/离线/未知/缓存」有四五套表达
- 现象：顶部用中文胶囊「在线/离线/连接中」+ 橙色 warn 图标；CAN 行用英文原样 `RUNNING/BUS-OFF/STOPPED`；能力位用 "?/checkmark/minus"；开关行用「读取中…」；离线横幅用 `clock.arrow.circlepath` vs `wifi.slash`。且离线时 CAN 仍是绿点、开关仍是可点的正常样式。
- 证据：`DashboardView.swift:226-236`、`:516-528`、`:787`、`:455`、`:457-466`、`:601-609`；`Models.swift:40-49`。
- 影响：用户无法用「一套视觉语汇」判断「这个值现在是可信的、未知的、还是过期的」。
- 建议：定义 `DataFreshness { live, cached, stale, unknown }` 一个枚举，卡片头/数值统一据此降低不透明度 + 统一徽标；CAN 状态文本本地化并在离线时统一置灰。

### [P2] 网络日志容量相对轮询频率过小，诊断包基本没有历史
- 现象：环形缓冲 300 条；正常每一拍 2–9 个请求、2–4 Hz，300 条只覆盖约 15–60 s。
- 证据：`Core/NetworkLog.swift:26`；`AppEnvironment.swift:283-305`。
- 影响：现场排查「刚才为什么断」时，导出 `network-log.csv` 往往已经被刷掉。
- 建议：提高容量（如 5000 条）或按时间窗（30 min）保留，并对高频 GET 做采样。

### [P3] LiveDataView 默认展开项与实际路径不匹配
- 现象：`expandedEndpoints` 初始化为 `[P4Route.snapshot, P4Route.systemStats]`，但列表项第一个是 `/api/snapshot?groups=home-fast&slow=1`，与 `/api/snapshot` 不相等，快照分组默认是收起的。
- 证据：`Features/Overview/LiveDataView.swift:15` 与 `:81`、`:128`。
- 影响：注释里「默认展开」的预期没生效，用户要多点一次才能看到核心字段。
- 建议：用 `AppEnvironment.browseEndpoints` 的前两项做默认展开键。

### [P3] LiveData 的「最近同步」在全部失败时也会刷新
- 现象：`endpointsUpdatedAt = Date()` 无条件写在扫描末尾。
- 证据：`AppEnvironment.swift:609-611`；`LiveDataView.swift:61-67`。
- 影响：`0 成功 / 30 失败` 时仍显示刚同步过，时间戳不可信。
- 建议：仅在有成功项时更新，或同时显示成功/失败计数（已有）与「最近成功」。

### [P3] 搜索匹配大小写不一致 + 结果静默截断
- 现象：`needle` 走了 `lowercased()`，但 `label.contains(query)` 用的是原始输入；结果 `prefix(300)` 截断且无提示；每个条目重复计算 `flatScalars`。
- 证据：`LiveDataView.swift:170-184`、`:99`。
- 影响：英文界面输入 "State" 能匹配键名但匹配不到中文标签；字段多时用户不知道还有更多结果。
- 建议：统一 `lowercased()`；截断时显示「仅显示前 300 条」；一次扫描缓存 `flatScalars`。

### [P3] 离线缓存实际是「单槽」，与注释承诺的「按设备地址隔离」不符
- 现象：固定文件名 `device-cache.json`，`save` 只在 `existing.host == host` 时合并，换 host 直接整体覆盖；`entries` 合并后旧键永不淘汰。
- 证据：`Core/OfflineCache.swift:20`、`:36-49`、`:10-18`（注释声称隔离）、`:52-58`。
- 影响：两台设备交替连接时互相顶掉缓存；固件改版删掉的组会永远留在缓存里被当成有效数据。
- 建议：文件名带 host 哈希；`maxAge` 从 7 天降到小时级（状态页数据「一周前」没有展示价值）。

### [P3] 缓存时间最多可落后 20 s，冷启动早退可能不落盘
- 现象：`persistCacheIfDue` 在条目数未增长且距上次写 <20 s 时直接 return。
- 证据：`AppEnvironment.swift:373-393`。
- 影响：状态页「数据时间」与真实最新数据差最多 20 s；刚连上就被杀进程时这次会话可能没有缓存。
- 建议：写入节流改为「合并延迟写 + 退后台强制 force 写一次」。

### [P3] iOS 端没有桌面/锁屏 Widget，只有 Live Activity
- 现象：WidgetBundle 在非 Catalyst 分支只注册 `CanActivityWidget()`（ActivityConfiguration），没有 `StaticConfiguration/TimelineProvider`；Catalyst 分支的静态 Widget 在 iOS 上不存在。
- 证据：`P4CANWidget/P4CANWidgetBundle.swift:6-12`；`P4CANWidget/CanActivityWidget.swift:171-211`。
- 影响：「Widget 更新链路」实际上不存在——用户只能靠实时活动，而实时活动必须 App 在前台才会被更新（见 P1-5）。
- 建议：要么明确不提供桌面 Widget（并去掉相关文档描述），要么加 Timeline Widget + App Group 共享最近一次快照。

### [P3] Widget 文案与配色未接入应用的设计令牌与语言
- 现象：胶囊写死 `"开"/"关"`，在线/离线写死 `Color.green/Color.red`；App 侧是 `L10n` + `P4Tone`。
- 证据：`P4CANWidget/CanActivityWidget.swift:93-100`、`:152-168`。
- 影响：英文界面下锁屏仍是中文；深色/高对比度下自选绿色与系统语义色不一致。
- 建议：把状态文案放进 `ContentState`（App 侧已按语言生成），颜色在 Widget 侧用语义色 + `accessibilityDifferentiateWithoutColor` 的图标区分（当前图标已具备）。

### [P3] 响应大小上限是在整包读入内存后才检查
- 现象：`session.data(for:)` 先把 body 全部缓冲，`checkSize` 在之后才判断 4 MB。
- 证据：`Core/P4APIClient.swift:253-255`、`:461-465`。
- 影响：上限只能防「解析」，不能防「内存峰值」；异常端点仍会瞬时占用与响应等量的内存。
- 建议：用 `URLSession.bytes(for:)` 增量读并在超限时取消，或改用 `downloadTask` + `expectedContentLength` 预检。

### [P3] 其它一致性/冗余
- `P4BusState.color(for:)` 实现完整但无人调用，色调逻辑在 `DashboardView:517` 重复实现（`UI/Theme.swift:141-151`）。
- 状态页把原始键名直接展示给用户：`canBusCount = 3`（`DashboardView.swift:487`），与其它已本地化文案不一致。
- `group()` 已做 fast→slow 兜底，`DashboardView.swift:419-420` 又写了一遍 `?? environment.slowGroups[...]`，属重复路径。
- `phase == .connecting` 在 `DashboardView.swift:34` 的分支里被 `hasRenderableData` 完全覆盖，第一次成功之后 `offlineContent` 成为不可达代码。
- 计数类（rx/tx 帧数）没有千分位（`P4Format.number` 直出），六位数在窄屏靠 `minimumScaleFactor` 硬缩（`Components.swift:562-570`）。
- `P4Format.number(Double)` 对整数值会丢小数（1.00 → "1"），与扭矩卡固定 `%.2f` 的精度不一致（`Core/P4JSON.swift:159-162`）。

---

## 3. 缺失 / 重复 / 逻辑不合理

**缺失**
1. 没有任何「数据新鲜度」模型：只有设备整体 online/offline，没有 per-endpoint 时间戳，因此「在线但数据不动」永远不可见（P1-2、P1-3）。
2. 没有后台/前台场景切换处理（`stop()` 从未被调用），也没有「回到前台立即刷新」。
3. 没有重启/断电识别：`uptimeS` 骤降、rx/tx 计数归零都不触发任何状态复位，趋势图跨重启直接连线。
4. 没有离线退避策略：固定 5 s 重试，连续失败 100 次与第 1 次表现完全相同。
5. Live Activity 无「过期」表达；Widget 无 iOS 桌面形态。
6. 没有对「快照缺失 fast/slow 键」的校验：`snapshot != nil` 即认为成功（`AppEnvironment.swift:317-320`、`:343`）。设备回 `{"ok":true}` 也会被静默当成在线。

**重复**
1. 双轮询：`pollTask`（全局）+ `LiveDataView.poll()`（3 s、30 端点），无互斥（P1-7）。
2. 缓存/离线判定两套：`hasRenderableData`（内存优先）与 `isShowingCachedData`（只在内存空时才可能为真），二者组合导致「缓存标记」与「实际展示内容」脱钩（P1-3）。
3. 色调逻辑三份：`P4Tone`、`P4BusState.color`、`DashboardView.busTone/busRow`，互不一致（P1-1）。
4. `group()` 兜底与调用处 `?? slowGroups` 重复。

**逻辑不合理**
1. `if phase != .online { phase = .connecting }` 写在每次请求**之前**，把「重试」表达成「正在连接」，导致离线态被自己覆盖（P2）。
2. `restoreCacheIfNeeded` 的前置条件让缓存只在「内存全空」时才生效，而 `persistCacheIfDue` 是「按条目数增长 + 20 s 节流」，两者对「什么算有数据」的定义不同。
3. `gotMeta` 的判定（profile/features/system 任一非 nil）与「状态页依赖 fast 快照」的实际依赖不对等。
4. `addTrendSample` 由 `rebuildDerived` 驱动，而 `refreshProfile()` / `refreshFeatures()` 也会调它——这两处会插入与轮询无关的额外采样点，让时间轴密度不均（`AppEnvironment.swift:468-489`）。
5. 刷新间隔文案 `"每 \(pollIntervalMs) ms 自动同步"` 把「sleep 间隔」当成「同步周期」，忽略了每拍 1 个快照 + 最多 8 个端点的往返时间。

---

## 4. 优先修复顺序（最多 5 条）

1. **切设备/切网络后必须清状态**：`updateHost` 加 `resetDeviceState()`（含 `trendSamples`、`endpointPayloads`、`isShowingCachedData/cachedAt/lastUpdated`），并按新 host 立即读缓存。→ P0
2. **修 CAN 在线判定**：`isOnline` 改为 `state == 1 && trafficOnline`，色调/计数/图标全部由 `state` 单点推导，删除 Dashboard 里的重复实现。→ P1-1
3. **给「数据来源」建模**：为快照与各慢端点各记一个 `fetchedAt/source`，`已同步` 只说快照，`cached` 标记与内容来源绑定；移除「任一 meta 成功即 online」的粗糙判定。→ P1-2、P1-3
4. **实时活动生命周期**：离线推送一帧离线态（或超时 end）、`staleDate` 缩短、`start` 返回结果并回写开关/toast、重试加退避上限。→ P1-5、P1-6
5. **轮询调度收敛**：单一 `inFlight` 令牌 + 场景暂停 + `loadAllEndpoints` 与首页轮询互斥（并禁止其用旧结果覆盖新快照）；顺带把趋势改成按 180 s 时间窗裁剪以匹配文案。→ P1-7、P1-8、P1-9
