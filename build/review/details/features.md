# 功能与灯光 审查

只读审查，未修改仓库任何文件。证据路径相对于 `P4CAN-Companion/`；固件路径前缀记为 `fw/`（= `build/firmware-build/P4-CAN-Universal-v3.29.3/`）。

**契约核对结论（先说答案）**：`python3 build/tools/check_api_contract.py` → `契约一致：路径与参数全部匹配固件实现。`
逐条人工复核后，**没有发现「发出去必然 400」的控件**（所有 write key 都能在 `fw/web_api.h` 找到对应 `server.hasArg` 分支，取值范围也与固件 clamp 一致）。真正的偏差集中在三类：**读状态读错端点/字段**（`supportKey` 类，见 P2-1）、**固件里存在但 App 未建模的参数**（灯光 `durationMs/stopMode/maxRunMs`，见 P1-1）、**语义错配**（R79 Bit18 in Mode 2、踏板 `targetName` 是会话态）。

---

## 1. 功能现状

### 1.1 模块清单（实际 24 个，不是 22）

`FeatureCatalog.modules` 实际声明 **24** 个模块（`Core/FeatureCatalog.swift:138-1072`）。其中 8 个属 `.lab`（只在「实验室」标签页出现），1 个 `profile` 只在「设置」页出现，因此**功能页列表里是 15 个模块 + `s3xy` + `lab` 两个伪行**（`Features/Features/FeaturesView.swift:48-56`）。任务描述里的「22 个」与实际代码不符，概览按实际 24 个给出。

| 分组 | 模块（id） | 控件与契约结论 |
|---|---|---|
| 灯光 | headlight（前大灯爆闪） | 无 `controls`，独立页；见 1.2 |
| 灯光 | rearFog（后雾灯爆闪） | 无 `controls`，独立页；见 1.3 |
| 驾驶辅助 | nag | toggle×6 / select×6 / number×2 / trigger×1；`enabled/method/tsl9Sequence/tsl9InputMode/tsl9LegacyRoute/torqueRightScroll*/tsl9RightPeriodic*/ignoreApState/pauseAtZeroSpeed/tsl9Window` 全部命中 `fw/web_api.h:3574-3760`；`mode` 走 `/api/nag/mode?m=`（`web_api.h:3523-3528`，`MODE_C=3/MODE_H=7` 与 `fw/can_core.h:807-810` 一致） |
| 驾驶辅助 | vision | toggle `disabled`+select `bus`，`web_api.h:4507-4545` 要求「恰好其一」，App 各发一个 → 合规；状态读 `requestDisabled`（`fw/vehicle_logic.h:3500`）正确 |
| 驾驶辅助 | dms | toggle `enabled` 单参数，`web_api.h:2971-2986` 要求 `args()==1` → 合规 |
| 驾驶辅助 | summon | 只读 |
| 驾驶辅助 | r79 | 8 个控件；`hw3Enabled` 单独提交符合 `web_api.h:4281-4290` 的互斥校验；`bit18Mode` 在 Mode 2 下读值是派生值（见 P3-3） |
| 驾驶辅助 | tlssc | endpointToggle + 2 toggle；字段 `tlssc/tlsscHighwayGateEnabled/tlsscBlockInNoa` 均在 `web_api.h:439-441` |
| 驾驶辅助 | ulc | 5 个控件；`confirm/timing/alcOff/blind/ulcOff` 均命中 `web_api.h:4457-4490`；`alcMode==2` 判据与 `LAB3F8_ALC_FORCE_ON=2`（`fw/vehicle_logic.h:1016`）一致 |
| 车身 | isa | 仅 1 个内联 toggle（不走详情页），`web_api.h:3013-3028` 合规 |
| 车身 | blink | 端点式 enable/disable + `ms` + 双数值 `noaStabilizationSeconds/cancelPauseSeconds` + `mode` + `doorCancel`；参数名/范围全部与 `web_api.h:4748-4810`、`:3195-3213` 一致 |
| 高级 | country | 2 个 select；`countryMode/mapMode` 分别单独提交，`web_api.h:4686-4702` 允许 |
| 高级 | pedal | select `mode`（STOCK/CHILL/SPORT/PERFORMANCE），`web_api.h:14-40` 接受这 4 个词；但读的是 `targetName`（会话态，见 P3-4） |
| 高级 | continuousAP | toggle+select，`web_api.h:3080-3092` 要求「enabled 与 method 恰好各一个」，App 用 `extra` 互相补齐 → 合规，且有 `method==0` 前置拦截（`FeatureDetailView.swift:568-578`） |
| 高级 | apDrive | toggle + select（regen 提交 `20/10/1`），`web_api.h:3215-3246` 接受字符串或数值 → 合规；状态字段在 `pedalmap/stats`（`fw/vehicle_logic.h:1931-1934`）里，`statsPath` 也是它 → 读对了 |
| 高级 | s3xy / lab 伪行 | `/api/features/s3xy`、`/api/features/lab`，`enabled` 单参数（`web_api.h:3166-3191`、`:3307+`） |
| 实验室 | r79ap | 4 参数一次提交（`enabled/mode/delaySeconds/allowManualDriving`），与 `web_api.h:4245-4270` 的「四个都必需」一致；LAB 未开时固件 403，App 也有 `canWrite` 门（`FeatureDetailView.swift:38-42`） |
| 实验室 | r79status / modeh | 只读（modeh 在 Lab 页走 `ModeHView`） |
| 实验室 | heartbeat | toggle 用 `selectedValue:value` 别名提交（`FeatureCatalog.swift:847-864`），命中 `web_api.h:4047-4062` 的 `enabled+value` 双必需 → 这是全仓最正确的一处别名用法 |
| 实验室 | alc | toggle+select，`web_api.h:4511-4530` 允许单个参数 |
| 实验室 | window | 单 trigger；固件成功返回 202，`interpret` 接受 2xx（`Core/P4APIClient.swift:433-436`） |
| 实验室 | research | 4 个 start + mode + 双数值窗口 + reset；`preMs/postMs` 是固件别名（`web_api.h:2403-2404`） |
| 实验室 | dmscapture | 6 个 slot trigger + reset，slot A–F 与 `fw/driver_monitor_capture.h` 一致 |
| 设置 | profile | 只读，仅在 `Features/System/SystemView.swift:236-238` 出现 |

### 1.2 前大灯页逐步流程（`Features/Features/HeadlightStrobeView.swift`）

1. 进入：`FeaturesView` 列表行直接 push `HeadlightStrobeView`（`FeaturesView.swift:339-350`），深链 `P4CAN_MODULE=headlight` 也走同一分支（`:132-133`）。
2. 首帧：`poll()` 先 `loadConfig()`（`HeadlightStrobeView.swift:433-434`），GET `/api/headlight-strobe/config` 回填 `count/intervalMs/trigger/holdEnabled/holdDelayMs/supported` 并写入 `saved`（`:445-458`）；失败则 `supported=false` + 顶部错误行（`:461-465`）。
3. 轮询：之后每 800ms 只 GET `/stats`，更新 `active/state/flashesDone/flashesTotal/blockReason/txOk/txFail/supported/stalkVariant`（`:436-441`）。**config 只读一次**。
4. 按住开关：Toggle 立即 POST `holdEnabled=1|0`（只发这一个参数，固件允许局部更新，`fw/web_api.h:5796-5808`）；成功后同步 `saved.hold`，失败回滚开关并给 `errorText`（`:505-523`）。页脚承诺「开关立即写入设备，无需保存」（`:158-160`）。
5. 次数刻度尺：`RulerSlider` 1…30，步进 1，主刻度 5（`:235-244`）；间隔刻度尺 50…500，步进 10（`:246-255`），副标题给出 `总时长 = 次数 × 2 × 间隔`（`:242-243`，与固件 COUNT 模式公式一致，`fw/headlight_strobe.h:213-220`）。
6. 触发入口：segmented Picker `App 按钮 / S3XY 按键`（`:256-262`），**改动只改本地 `triggerSource`，随保存提交**（`:482-487`）。
7. dirty/保存：`dirty = (count, intervalMs, trigger, hold) != saved`（`:47-49`）；`saveDisabled = busy || !dirty || active`（`:75`）；保存成功后 `saved` 更新 + `justSaved` 2.5s（`:477-502`）；撤销 `resetToSaved()`（`:468-475`）。
8. 触发：`CommitButton` 仅在 `canTrigger`（supported && !active && !busy && trigger==0 && !dirty）时可用（`:133-135`），点击先弹确认（`:337-349`），确认后 POST `/trigger` 无参数（`:530`）；失败进 `.error` 相位，完整错误进 `errorText`（`:535-540`）。
9. 停止：`active` 时出现「停止并恢复」，POST `/stop`（`:544-556`）。
10. 状态区：进度 `done/total`、长按延迟、`blockReason` 本地化 + 语义配色（`:353-431`）。

### 1.3 后雾灯页逐步流程（`Features/Features/RearFogStrobeView.swift`）

1. 进入：列表行直接 push（`FeaturesView.swift:351-360`）；`FeatureDetailView` 里的同名入口不可达（见 P3-1）。
2. 轮询：每 500ms GET `/stats`（`:177-187`），字段 `active/remainingMs/totalMs/intervalMs/txOk/txFail/stockFogOn/templateValid/setupMode/stopReason`（固件 `fw/web_api.h:5834-5880` 全部存在）。
3. 圆环：`progress = 1 - remaining/total`，未激活时固定显示 `30.0`（`:152`），胶囊状态「运行中 / Setup 模式不可用 / 待机（已收到 0x273）/ 等待 0x273 帧」（`:32-37`）。
4. 开始：`canStart = !active && !busy && templateValid && !setupMode`（`:44-46`），**无确认弹窗**；POST `/start`，失败时按 `templateValid` 猜文案（`:189-207`）。
5. 停止：`:209-221`；成功后固件补发一帧原始 0x273 让灯立刻回原状态（`fw/rear_fog_strobe.h:145-165`）。
6. 30 秒：固件 `REAR_FOG_MAX_MS=30000` 硬上限（`fw/rear_fog_strobe.h:22`），`stopReason=TIMEOUT`；`NO_FRAME`（模板 >2s 过期）也会自动停并落文案（`:48-55`）。

---

## 2. 问题清单

### P1

**P1-1 固件支持三种爆闪模式，App 只建模 COUNT 一种；设备处于 DURATION/MANUAL 时，次数/间隔/总时长全部失真**
现象：页面按「次数 × 2 × 间隔」显示总时长、进度按 `flashesTotal=count` 计算，但固件 `durationMs>0` 时总数按固定时长跑、`stopMode==1` 时按 `maxRunMs` 跑到手动停，`count` 被完全忽略；App 的「保存参数」只提交 `count/intervalMs/trigger/holdEnabled` 四项，永远不会清掉网页端留下的 `durationMs/stopMode`，也从不展示 `mode` 字段。
证据：`fw/headlight_strobe.h:210-220`（runTotal 三模式）、`fw/web_api.h:5764-5787`（durationMs/stopMode/maxRunMs 可写）、`fw/web_api.h:5685-5687`（stats 已返回 `mode`）、`fw/web_api.h:5696-5697`（`flashesTotal` 恒等于 count）；`HeadlightStrobeView.swift:68-71`（总时长公式）、`:242-243`（caption）、`:482-487`（只提交 4 参数）。
影响：用户设 10 次/100ms 以为 2 秒，实际可能闪满 5 秒或一直闪到手动停；进度 0/10 走完后界面停住但灯还在闪。「保存」无法把设备拉回 COUNT 模式，属功能性错误。
建议：`Config` 增加 `durationMs/stopMode/maxRunMs/mode`，UI 显示当前模式（COUNT/DURATION/MANUAL）；保存时按模式提交（选 COUNT 就显式 `durationMs=0`、`stopMode=0`）；进度与总时长按 `stats.totalMs/elapsedMs` 而不是本地公式。

**P1-2 `AppEnvironment.command` 对并发命令静默丢弃，调用方仍按「已提交」继续走后续逻辑**
现象：`guard !isBusy else { return }` 直接返回，既不改 toast 也不抛错；`isBusy` 在命令结束后的 `refreshOnce()` 期间仍为 true（最长 8s 超时），期间任何写操作被吞。
证据：`Core/AppEnvironment.swift:666-684`（672 行 guard，683 行 refresh 仍在 isBusy 内）；`Features/Features/FeaturesView.swift:533-537`（`submitInline` 无返回值判断，接着 `loadConfigToggles()`）；`Features/Features/FeatureDetailView.swift:592-602`（`submitToggle` 用 `environment.toast?.style == .success` 判断是否写入成功，命令被丢弃时读到的是上一条无关 toast）。
影响：开关「点了没反应」且无任何提示；极端情况下把上一条命令的成功 toast 当成自己的，弹出「已提交但设备未回读」的错误结论。
建议：`command` 返回 `Bool`/`Result`；忙时给出「设备正忙，请稍候」的明确失败（或排队）；调用方只在返回成功时做乐观确认。

**P1-3 详情页轮询会覆盖正在输入/正在提交的本地值（Picker 回弹、成对滑杆被打断）**
现象：`poll()` 每 1.2s `load()`→`syncFromDevice()` 无条件重写 `selectedOptions` 与 `numberValues`；只有单个 `.number` 有 `sliderEditing` 保护，`select` 与 `pairNumber` 没有任何保护。于是：选完下拉后写请求在飞行期间（8s 超时内的任意 1.2s 拍）Picker 会跳回旧值；拖动「NOA 等待时间 / 捕获窗口」滑杆时每 1.2 秒被设备值拽回去，根本无法连续调参。
证据：`FeatureDetailView.swift:29`（1200ms）、`:223-246`（poll→load→syncFromDevice）、`:266-281`（`selectedOptions[key] = selectText(...)`、`numberValues[first.key] = ...` 覆盖）、`:269-271`（仅 `.number` 有 sliderEditing）、`:326-336`（select 写入后无本地保护）、`:397-417` 与 `:434-475`（pairNumber 无 sliderEditing）。
影响：blink 的两个时序滑杆、research 的双窗口（虽改成 Picker 预设，但读值仍会被覆盖）操作体验破坏；下拉选择出现「选了又跳回去」，用户会重复点击，放大 P1-2 的丢命令问题。
建议：给 `select`/`pairNumber` 复用 `sliderEditing` 思路（`pendingWrites: Set<String>`，写入返回前不覆盖），或统一「写入成功后再允许轮询覆盖」；pair 滑杆松手才提交并加编辑锁。

### P2

**P2-1 `supportKey: "supported"` / `"countrySupported"` 解析不到 → 能力门与「支持/不支持」徽章全部失效**
现象：`capability()` 只在 `featuresStatus` 与 `profileStatus` 里找键，但 `vision`、`continuousAP`、`window` 的 `supported` 只出现在各自 stats 端点，`country` 的 `countrySupported` 只出现在 `country/stats`。结果 `capabilitySupported` 恒为 `true`，列表也不显示徽章；用户在不支持的车型上可以点，最后吃 409。
证据：`FeatureCatalog.swift:322`（vision）、`:536`（country）、`:699`（continuousAP）、`:910`（window）；`Core/AppEnvironment.swift:823-826`（只查两份 status）；`fw/vehicle_logic.h:3500-3501`（`supported` 在 vision stats）、`fw/web_api.h:4637`（`countrySupported` 在 country stats）、`:3960`（window stats）、`:3050`（continuousAP config）。
影响：不支持车型上控件可点、无预警，只能靠英文 409 兜底；功能页缺少能力提示。
建议：给 `FeatureModule` 增加「能力位来源端点」，或让 `capability()` 在 module stats 里查；至少把三处 `supported` 改成 `bodyControlsSupported/...` 这类确实在 profile capability 里的键（`fw/web_api.h:2873-2885`）。

**P2-2 前大灯间隔 UI 上限 500ms，固件上限 1000ms；超范围设备值被「显示夹住但不写回」**
现象：刻度尺 `range: 50...500`，固件 `50..1000`。若网页端设成 800，页面显示 500 但内部 `intervalMs` 仍是 800：`dirty` 为 false（`saved` 也是 800）→ 保存按钮禁用，撤销也禁用，用户只能先拖到别的值再拖回来才能改，期间显示的 500 是假的。
证据：`HeadlightStrobeView.swift:246-255`（50...500）与 `:6` 注释（50–1000）、`:477-478`（保存只校验到 1000）；`fw/web_api.h:5746-5751`（50..1000）；`UI/RulerSlider.swift:43-45`（`clampedValue` 只夹显示）、`:79-88`（`onChange(offset:)` 不回写 `value`）。
影响：间隔无法设到 500–1000（固件允许且后雾灯也复用该值）；设备值越界时 UI 与设备状态不一致，且「保存」语义失效。
建议：范围改 50...1000（或与固件常量共用一份定义）；`RulerSlider` 在 `onChange(of: value)` 发现越界时把 `value` 夹回并标记 dirty，避免“显示值与真实值分叉”。

**P2-3 前大灯失败文案直接暴露固件错误码，未本地化、无处置建议**
现象：触发失败走 `AppEnvironment.friendly(error)`，而 `P4APIError.message` 就是固件 `error` 字段原文（`SOURCE_MISMATCH`、`NO_STOCK_TEMPLATE`、`ALREADY_ACTIVE`…）。`reasonText()` 只服务 stats 的 `blockReason`，错误路径完全没用到，于是同一句原因在状态区是中文、在错误行是英文枚举。
证据：`HeadlightStrobeView.swift:535-540`（`errorText = AppEnvironment.friendly(error)`）、`:404-417`（`reasonText` 映射表只被 `statusSection` 使用）；`fw/web_api.h:5813-5818`（409 body 就是 `blockReason` 原文）；`Core/P4APIClient.swift:424-429`（直接透传 `error`）。
影响：最常见的「配置是 S3XY / 没有 0x249 模板 / 转向灯占用」三种拦截，用户只看到英文码，不知道下一步做什么。
建议：错误行与状态区共用 `reasonText(_:)` + 兜底原文；对 409 的三种原因补一句可执行建议（去蓝牙页配 S3XY / 先打一次转向灯 / 等转向结束）。

**P2-4 后雾灯 409 只按 `templateValid` 猜原因，整段错误体被丢弃；Setup 模式下会给出完全错误的解释**
现象：`start()` 的 catch 不读 `error` 字段，只用本地 `templateValid` 二分。固件在 Setup 模式直接返回 false 且 `active=false` → 报 `NO_FRAME`（`fw/web_api.h:5892`），而模板往往是有效的，App 于是显示「上一次爆闪还没结束，请先停止」——与事实相反。
证据：`RearFogStrobeView.swift:199-203`；`fw/web_api.h:5887-5895`（409 = ALREADY_ACTIVE 或 NO_FRAME）；`fw/rear_fog_strobe.h:174-176`（setupMode 直接 return false → 落到 NO_FRAME）；`Core/P4APIClient.swift:424-429`（error 已解析出来却被调用方忽略）。
影响：用户按提示去点「停止」（按钮此时是禁用的），排障方向被带偏。
建议：解析 `P4APIError.message`，按 `ALREADY_ACTIVE` / `NO_FRAME` 分别给文案；Setup 模式在 UI 上先显示独立提示（`setupMode` 字段已具备，`:25`）。

**P2-5 LAB / S3XY 总开关写入失败时仍弹出「已开启」成功提示，且覆盖掉失败 toast**
现象：`setFeaturesGate` 不检查 `command` 结果，`refreshFeatures()` 之后无条件 toast「实验室已开启，底部出现「实验室」标签」。若 POST 返回 500（固件 `Settings could not be saved`），`command` 先写失败 toast，随即被这句成功文案覆盖；开关本身又被 `gateOverrides` 清空回滚，界面于是「开关是关的 + 提示已开启」。
证据：`FeaturesView.swift:540-564`（546 清 override、548-562 无条件 toast）；`Core/AppEnvironment.swift:675-682`（失败只写 toast，不抛错）；`fw/web_api.h:3176-3179`（lab 保存失败 500）。
影响：全局闸门状态被误报，用户会去找「为什么底部没有实验室标签」。
建议：`command` 返回结果，成功再发这条 toast；失败保持 `command` 的失败 toast。

**P2-6 ISA / DMS 内联行在设备不提供该端点时永久转圈，无法判定也无法操作**
现象：`InlineFeatureRow` 在 `isOn == nil` 时只显示 `ProgressView`；`loadConfigToggles` 失败后既不写入 `nil` 的「未获取」态，也没有错误变量，老固件/离线时这一行永远转圈。
证据：`FeaturesView.swift:696-710`（`if busy || isOn == nil { ProgressView() }`）、`:488-513`（无失败状态字段，离线时只尝试缓存）；对比 `FeatureDetailView.swift:523-533`（有「读取中…/未获取」两种态）。
影响：功能页首屏出现两个永久 spinner；用户以为设备在忙。
建议：给两行加三态（nil=未获取 + 重试按钮），或直接改成走详情页/`FeatureRow` 骨架。

**P2-7 功能页 4 秒轮询会覆盖 ISA/DMS 的乐观值，点击后出现「弹回再弹过去」**
现象：`submitInline` 先本地置值再发命令并 `refreshOnce()`（8s 级），期间独立的 4s 轮询照样 `loadConfigToggles()` 读设备旧值写回 `isaEnabled/dmsEnabled`。
证据：`FeaturesView.swift:142-153`（4s `.task`）、`:529-538`（乐观置值）、`:488-513`（无条件覆盖）。
影响：网络慢时开关视觉来回跳，用户重复点 → 撞上 P1-2 的丢命令。
建议：轮询在 `busyID != nil` 或存在 pending 写入时跳过该项。

**P2-8 NAG 高级参数页宣称支持十进制 ID，代码实际只按十六进制解析**
现象：`parseID` 去掉 `0x` 后一律 `Int(raw, radix: 16)`；输入十进制 `880`（期望 0x370）会被解释成 0x880=2176 → 超出 0x7FF → 直接判非法。页脚与提示都写着「或同等十进制」。
证据：`NagAdvancedView.swift:51-57`（radix 16 固定）、`:156-158`（footer 文案）、`:277-279`（`= \(value)` 换算展示同理）。
影响：按文档输入十进制会得到「目标 ID：0x001–0x7FF」的红字，且无法提交；反过来输入 `370` 会被当十六进制（这恰是想要的），文案与行为互相矛盾。
建议：二选一——要么去掉「十进制」承诺，要么 `hasPrefix("0x")` 才按 16 进制、否则按 10 进制并做 0x7FF 上限校验。

**P2-9 「按住拨杆爆闪」开关在爆闪进行中必然 409，与页脚「开关立即写入设备」矛盾**
现象：开启后进入 HOLD 爆闪，此时用户关开关 → POST `/config?holdEnabled=0`，但处理函数在解析参数之前就因 `headlightStrobeState.active` 直接 409 `ALREADY_ACTIVE`。固件自己在 `holdEnabled==0` 分支写了「运行中关闭：立即停止并恢复」，永远走不到。
证据：`fw/web_api.h:5734-5737`（active 时任何 POST 都 409）对比 `:5802-5806`（本意支持运行中关闭）；`HeadlightStrobeView.swift:141-147`（开关无 `disabled`，立即提交）、`:505-523`（失败回滚 + errorText）、`:158-160`（页脚承诺）。
影响：开关看起来「点了自己弹回去」，且错误只落在页面最底部一行，用户难以关联。
建议：App 侧在 `active` 时禁用该开关并配一句「爆闪中不可改，请先停止」；同时向固件提 bug（把 holdEnabled 分支移到 active 判断之前），双边都改才彻底。

### P3

**P3-1 前大灯/后雾灯的通用详情页入口是死代码，形成「两个入口只有一个能用」的错觉**
现象：`FeatureDetailView` 为 `headlight`/`rearFog` 各写了一段 NavigationLink（含 footer 提示）以及两个 `navigationDestination(isPresented:)`，但 `FeaturesView` 对这两个 id 一律直接 push 专用页，永远不会构造 `FeatureDetailView(module: headlight/rearFog)`；全仓也没有第三个入口（`SystemView` 只开 `profile`，`LabView` 只开 `.lab`）。
证据：`FeatureDetailView.swift:80-108`（两段入口）、`:147-150`（两个 destination）、`:26-27`（`showsHeadlightStrobe/showsRearFog`）、`:167-176`（DEBUG 直跳）；`FeaturesView.swift:130-139` 与 `:339-360`（唯一真实路由）。
影响：~30 行不可达代码 + 两套「爆闪设置与触发」文案，后续改动容易只改一处；工具链的覆盖率/死代码分析会噪音。
建议：删除 `FeatureDetailView` 里这两段（连 `showsHeadlightStrobe/showsRearFog`），灯光入口只保留列表直达。

**P3-2 搜索不覆盖 8 个实验室模块与「车型配置」，但深链又能进入 → 搜索/置顶/深链三者行为不一致**
现象：`allEntries` 只由「非 lab 且非 profile」的模块 + `s3xy` + `lab` 组成，所以搜「心跳」「R79 AP」「研究捕获」「车型」都无结果；同时 `P4CAN_MODULE` 深链只要 id 存在于完整 catalog 就会 push，`modeh` 还会进到一个 `controls` 为空的 `FeatureDetailView`（而 Lab 页对 `modeh` 是 `ModeHView`）。
证据：`FeaturesView.swift:48-56`（过滤）、`:89-106`（搜索域）、`:154-167`（深链用 `FeatureCatalog.modules` 全集）；`LabView.swift:32-38`（modeh→ModeHView 的分支）；`FeatureCatalog.swift:1057-1068`（modeh controls 为空）。
影响：用户搜不到实验室功能（只能靠底部标签）；调试深链会看到与正常路径不同的页面。
建议：搜索域与置顶域保持一致（要么都含 lab，要么深链也按可见集合校验）；`modeh` 在 features 侧要么路由到 `ModeHView`，要么不参与深链。

**P3-3 R79「Bit18 策略」在 Mode 2 下是假控件（读值恒为原厂，写入被忽略）**
现象：固件在 Mode 2 时把 `bit18Mode` 强制上报为 `R79_BIT18_STOCK_PURE`，真实 `bit18Policy` 被隐藏；App 读到 0 → 命中选项 → Picker 可用 → 用户选「强制 0」提交 `bit18Mode=1`，固件接受但不生效（下次读回仍是 0）。
证据：`fw/web_api.h:1006-1011`（Mode 2 下输出 STOCK）、`:4339-4345`（写入无 Mode 2 校验）；`FeatureCatalog.swift:500-511`（控件无 `readEquals`/禁用条件）；`FeatureDetailView.swift:326-343`（只要读值在选项域内就启用）。
影响：用户会以为改成功（toast 是「已执行」），实际无效。
建议：读 `mode`，Mode 2 时禁用该 Picker 并注明「Mode 2 由固件固定为原厂」。

**P3-4 踏板档位读的是 `targetName`（会话态），override 一结束 Picker 就自动跳回 STOCK**
现象：`targetName` 在 `overrideActive==false` 时恒为 `"STOCK"`；踏板映射是运行期会话（固件明确不写 NVS，`fw/web_api.h:35-36`），驻车/换挡后会话清理，页面显示回到「原厂」，用户会以为设置丢了。
证据：`fw/vehicle_logic.h:1921`（`active ? pedalMapName(target) : "STOCK"`）、`fw/web_api.h:35-38`（runtime-only、可被 live state 拒绝）；`FeatureCatalog.swift:671-687`（`readKey: "targetName"`）。
影响：状态显示与「保存过」的直觉冲突；也会让「设置被拒绝（409 blocked by live vehicle state）」看起来像「设置没生效」。
建议：同时显示 `targetRaw/targetName` 与「会话中/已结束」，或在 footnote 里点明这是运行期会话。

**P3-5 切换 NAG 注入模式会用模式默认值整包重写配置，扭矩表被重置，App 无任何提示**
现象：`/api/nag/mode` 的实现是「按 m 取整套默认值 → 保留 enabled/ignoreApState/pauseAtZero/method/tsl9*」再保存，扭矩表与波形细节全部回到默认。App 的控件标题只写「注入模式」。
证据：`fw/web_api.h:3548-3567`（`nagCfgDefaultsModeX(nc)` 后 `nagCfgSaveCandidate`）；`FeatureCatalog.swift:157-171`（footnote 只提 Mode C 并入 H）。
影响：用户在高级参数页（或网页）精调过的波形，一切换模式就静默丢失。
建议：footnote 补一句「切换模式会恢复该模式默认波形与扭矩表」；或在切换前弹确认。

**P3-6 `loadStrobeStates` 用整体替换：任一灯光端点失败会抹掉另一条的「爆闪中」徽章**
现象：`fresh` 字典只装成功的项，最后 `strobeActive = fresh` 全量覆盖。
证据：`FeaturesView.swift:516-527`（526 行整体赋值）。
影响：网络抖动时列表徽章闪没，用户以为爆闪停了。
建议：按 key 合并（失败保留旧值），或失败时不动该 key。

**P3-7 前大灯保存后不回读配置，无法发现「固件没接受」的情况**
现象：`saveConfig` 直接把本地值写进 `saved`，请求返回的 JSON（含 `count/intervalMs/trigger/holdEnabled/mode/durationMs`）只赋给 `stats` 不参与校验；对比 `NagAdvancedView.apply` 有逐字段回读比对。
证据：`HeadlightStrobeView.swift:482-496`；`NagAdvancedView.swift:436-458`（回读比对范例）；`fw/web_api.h:5810`（POST 直接回 `headlightStrobeJson()`，具备回读条件）。
影响：若固件 clamp 或丢弃某参数，UI 仍显示「已保存」，dirty 变 false 后用户无法察觉。
建议：保存后用响应里的四个字段回填 `count/intervalMs/triggerSource/holdEnabled` 再更新 `saved`（顺带解决 P1-1 的模式回读）。

**P3-8 后雾灯页若干细节与固件/前大灯页不一致**
现象：①空闲时圆环固定显示 `30.0`，不看 `totalMs`；②固件已上报 `pulses/phaseOn/frameAgeMs/bus`，页面一个都没用；③开始爆闪无确认弹窗（前大灯有），而两者都会实际驱动车灯；④间隔来自前大灯配置（`rearFogStrobeHalfPeriodMs()` 直接复用 `headlightStrobeConfig.intervalMs`），后雾灯页只读展示且没有说明这个耦合。
证据：`RearFogStrobeView.swift:152`（硬编码 30.0）、`:99-112`（状态区只列 4 项）、`:66-79`（无确认）；`fw/web_api.h:5849-5870`（字段齐全）；`fw/rear_fog_strobe.h:58-60`（复用前大灯 intervalMs）。
影响：演示时两页操作语言不一致；用户不知道改后雾灯频率要去前大灯页。
建议：空闲值用 `totalMs`；补 `pulses/bus` 只读行；给 start 加与 headlight 同款确认；在参数区注明「间隔由前大灯爆闪参数决定」。

**P3-9 前大灯「按住拨杆」开关在车型不支持（STALKLESS）时仍可写**
现象：`supported=false` 只用来拦触发与显示提示条，hold 开关没有 `disabled`。
证据：`HeadlightStrobeView.swift:140-171`（Toggle 无 `disabled`，`:163-171` 只是提示条）；`fw/headlight_strobe.h:175-178`（begin 时一律拒绝 STALKLESS）。
影响：用户打开一个永远不会生效的开关，也写进 NVS。
建议：`!supported` 时禁用 hold 开关。

**P3-10 ISA / DMS 内联行绕开了能力位与支持徽章**
现象：`isa`/`dms` 在列表里走 `InlineFeatureRow`，既没有 `FeatureRow` 的「支持/不支持」胶囊，也没有 `capabilitySupported` 式拦截；不支持时只能靠 409（固件 `driver monitoring control unavailable for current profile` / `ISA suppression unavailable`）。
证据：`FeaturesView.swift:315-338`（内联分支）；`FeatureDetailView.swift:32-42`（详情页才有门）；`fw/web_api.h:2977-2980`、`:3019-3022`（409 文案）。
影响：与同组的其他模块 UI 语义不一致。
建议：给内联行加能力位胶囊（`dmsNagSupported` 已在 profile capability 中）。

**P3-11 `FeaturesView` 混用 `NavigationStack(path:)` 与 `NavigationLink(destination:)`，`path` 永远为空**
现象：列表行用 destination 式链接，只有 DEBUG 深链会写 `path`；因此「深链进入 → 返回」与「点进去 → 返回」走两套机制，`path` 无法反映真实栈（也影响以后的还原/分享链接）。
证据：`FeaturesView.swift:12`（`@State path`）、`:130-139`（destination(for:)）、`:154-167`（唯一写 path 的地方）、`:342-370`（destination 式 NavigationLink）。
影响：当前功能可用，但深链/状态恢复容易出问题（例如深链到 `modeh` 会显示空详情页，见 P3-2）。
建议：统一成 value 式 `NavigationLink(value: id)`，把「灯光直达/lab 分支」放进同一个 `navigationDestination`。

---

## 3. 缺失 / 重复 / 逻辑不合理

**缺失**
- 前大灯：`durationMs / stopMode / maxRunMs / mode` 四个固件参数完全未建模（P1-1）；`holdDelayMs` 只读不可改；`txOk/txFail` 有展示但 `elapsedMs/totalMs` 没有（进度本可更准）。
- 后雾灯：`pulses / phaseOn / frameAgeMs / bus / templateHex` 未展示；没有「30 秒上限受前大灯 intervalMs 影响」的说明。
- 功能页：没有「只看已开启 / 只看不支持」的筛选；ISA/DMS 无失败态与重试（P2-6）；搜索不覆盖 lab（P3-2）。
- 通用详情页：`.pairNumber` 没有编辑锁与去抖（P1-3）；写入没有「进行中」禁用（`canWrite` 只看能力位/Setup/LAB，不看本控件是否有请求在飞）。

**重复 / 不可达**
- `FeatureDetailView` 里 headlight/rearFog 的两段入口 + 两个 `isPresented` destination 不可达（P3-1）。
- headlight/rearFog 在「灯光」分组里同时存在「直达页」和（理论上的）「通用详情页」两条路径，实际只有前者可用。
- DEBUG 深链可把 lab 模块推进「功能」标签页，与「实验室」标签页形成同一模块双入口（P3-2）。

**逻辑不合理**
- 灯光页「参数随保存提交」与「dirty 才允许触发」是自洽的，但 `triggerSource=1` 的提示语在未保存时就已经宣称「App 内按钮不可用」（`HeadlightStrobeView.swift:52-56` 只判断本地值，不判断 `dirty`），而设备侧仍是 APP 入口——提示与设备状态短暂不一致。
- `saveDisabled` 包含 `active`，但固件其实允许运行中改 `intervalMs` 并即时生效（`fw/web_api.h:5752-5755`）；现在的 UI 把这个能力藏了，同时又因为整个 config POST 在 active 时 409 而无法实现（P2-9），属于双边设计冲突。
- 状态文案「已提交但设备未回读」（`FeatureDetailView.swift:595-602`）依赖全局 toast 的 style 判断本次写入是否成功，跨命令会误判（见 P1-2）。
- 后雾灯的失败文案与固件错误码脱钩（P2-4），前大灯的失败文案与本地映射表脱钩（P2-3）：两个页面在「同一类错误」上采用了相反策略。

**契约偏差汇总（参数名/范围/错误码）**
- 参数名：未发现错名。`selectedValue:value`（heartbeat）、`m`（nag mode）、`txMode`（blink）这些读写不同名的场景处理正确。
- 范围：前端比固件窄 1 处（headlight interval 500 vs 1000，P2-2）；其余（count 1..30、blink 0..30000、r79 0..340/0..2000、research 2000..15000/2000..10000、r79ap 2..10）与固件一致。
- 错误码：固件有 400/403/409/410/500/503 六类语义（`unsupported-profile`、`Confirm-Free unsupported`、`ALREADY_ACTIVE`、`NO_FRAME`、`lab-disabled`、`mixed-hw3-settings`…），App 只区分「业务 error 文本」与「HTTP 状态」，没有统一映射表；灯光两页各自又写了一套（P2-3/P2-4）。

---

## 4. 优先修复顺序（最多 5 条）

1. **P1-1 灯光模式建模**：把 `durationMs/stopMode/maxRunMs/mode` 纳入 headlight 的 Config，保存时按模式显式下发并在 UI 显示当前模式；进度/总时长改读 `totalMs/elapsedMs`。这是唯一会让「次数/间隔」在真实设备上完全失真的问题。
2. **P1-2 `command` 返回值化**：忙时明确失败或排队，禁止静默丢弃；顺带修掉 P2-5（假成功提示）与 `submitToggle` 里基于 toast 的成功判定。
3. **P1-3 写保护**：详情页为 `select/pairNumber` 增加 pending 写锁 + pair 滑杆去抖；轮询在 pending 期间不覆盖。与 P2-7 一并处理（列表内联行的 4s 轮询同样跳过 pending）。
4. **P2-1 能力位来源**：让 `capability()` 能查到模块自身 stats 的 `supported/countrySupported`（或改键），恢复「不支持」徽章与写入门；同步补 P3-10 的 ISA/DMS 徽章。
5. **P2-2 + P2-3/P2-4 灯光契约与文案**：间隔范围对齐 50..1000 并修 `RulerSlider` 越界不回写；两页失败文案统一走 `reasonText` 映射（含 409 的 ALREADY_ACTIVE / NO_FRAME / SOURCE_MISMATCH），后雾灯改为解析 `P4APIError.message`。
