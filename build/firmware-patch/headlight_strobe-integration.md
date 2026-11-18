# 前大灯爆闪 · 固件集成说明（P4-CAN Universal v3.29.3）

> 目标：触发后远光灯 PULL/IDLE 交替 `count` 次，结束或中断时恢复触发前的高灯状态。
> 依赖：车辆必须已经上报过真实 `0x249` 拨杆帧（固件原有的 `stalkFrameSnapshot` 安全约束）。

## 1. 关键文件

| 文件 | 改动 |
|---|---|
| `headlight_strobe.h`（新增） | 状态机、0x249 发送、计数/间隔/恢复、防重入 |
| `vehicle_logic.h` | 在 `sendStalkFrameCanB` 前声明 `headlightStrobeActiveFlag`；两个 send 函数开头加守卫；在 `sendStalkFrameCanA` 后 include 新头 |
| `can_runtime.h` | `blinkATxTick();` 后调用 `headlightStrobeTick();` |
| `p4can_forward.h` | 声明 `static void headlightStrobeTick();`（可选，便于 .ino 自动原型） |
| `web_api.h` | 注册 4 个接口 + NVS 配置 |
| `s3xy_ble.h`（可选） | 新增 S3XY 动作 `S3XY_ACTION_HIGH_BEAM_STROBE = 13` |

## 2. vehicle_logic.h 的三处改动

### 2.1 在 `sendStalkFrameCanB()` 之前

```cpp
// 前大灯爆闪期间独占 0x249，挡住转向灯/ALC/one-shot 注入。
static volatile bool headlightStrobeActiveFlag = false;
```

### 2.2 两个 send 函数开头

```cpp
static void sendStalkFrameCanB(uint8_t turn, uint32_t txEpoch, bool directUser) {
  if (headlightStrobeActiveFlag) return;
  ...
}

static void sendStalkFrameCanA(uint8_t turn, uint32_t txEpoch, bool directUser) {
  if (headlightStrobeActiveFlag) return;
  ...
}
```

物理拨杆仍由整车 SCCM 自己工作；这里挡住的只是固件主动注入的转向帧。

### 2.3 在 `sendStalkFrameCanA()` 之后

```cpp
#include "headlight_strobe.h"
```

必须在 `stalkFrameSnapshot`、`sendStalkFrame...`、`canTx...` 之后，保证头文件里的函数能解析到这些符号。

## 3. can_runtime.h

```cpp
blinkATxTick();
headlightStrobeTick();   // 新增
```

放在同一个 CAN 任务循环里即可；`headlightStrobeTick` 内部用 `millis()` 控制半周期，不阻塞。

## 4. web_api.h：接口与 NVS

### 4.1 接口

| 方法 | 路径 | 参数 | 说明 |
|---|---|---|---|
| GET | `/api/headlight-strobe/config` | — | 返回配置 + 当前状态 |
| POST | `/api/headlight-strobe/config` | `count` 1–30、`intervalMs` 50–1000、`trigger` 0/1 | 保存到 NVS；active 时 409 |
| POST | `/api/headlight-strobe/trigger` | — | 按配置启动；重复触发 409 |
| POST | `/api/headlight-strobe/stop` | — | 中断并恢复 |
| GET | `/api/headlight-strobe/stats` | — | 运行状态 |

返回示例：

```json
{
  "ok": true,
  "count": 10,
  "intervalMs": 200,
  "trigger": 0,
  "triggerName": "APP",
  "supported": true,
  "stalkVariant": "STALK",
  "active": true,
  "state": "ACTIVE",
  "flashesDone": 3,
  "flashesTotal": 10,
  "blockReason": "",
  "txOk": 6,
  "txFail": 0
}
```

`state`: `IDLE / ACTIVE / COMPLETE / STOPPED / BLOCKED`
`blockReason`: `ALREADY_ACTIVE / NO_STOCK_TEMPLATE / STALKLESS_UNSUPPORTED / TURN_SIGNAL_ACTIVE / SOURCE_MISMATCH / SEND_FAILED / USER_STOP / COMPLETE`

### 4.2 NVS 与 JSON（放在 `web_api.h` 路由注册之前）

```cpp
static Preferences headlightStrobePrefs;
static bool headlightStrobePrefsLoaded = false;

static void headlightStrobeLoadPrefs() {
  if (headlightStrobePrefsLoaded) return;
  headlightStrobePrefsLoaded = true;
  headlightStrobePrefs.begin("hstrobe", false);
  headlightStrobeConfig.count =
      headlightStrobeClampCount(headlightStrobePrefs.getUShort("count", 10));
  headlightStrobeConfig.intervalMs =
      headlightStrobeClampInterval(headlightStrobePrefs.getUShort("intervalMs", 200));
  const uint8_t trigger = headlightStrobePrefs.getUChar("trigger", 0);
  headlightStrobeConfig.trigger = trigger == 1 ? 1 : 0;
}

static void headlightStrobeSavePrefs() {
  headlightStrobePrefs.putUShort("count", headlightStrobeConfig.count);
  headlightStrobePrefs.putUShort("intervalMs", headlightStrobeConfig.intervalMs);
  headlightStrobePrefs.putUChar("trigger", headlightStrobeConfig.trigger);
}

static String headlightStrobeJson() {
  headlightStrobeLoadPrefs();
  const bool active = headlightStrobeState.active;
  const char *stateName = active ? "ACTIVE" :
      headlightStrobeState.state == HS_STATE_COMPLETE ? "COMPLETE" :
      headlightStrobeState.state == HS_STATE_STOPPED ? "STOPPED" :
      headlightStrobeState.state == HS_STATE_BLOCKED ? "BLOCKED" : "IDLE";
  String json;
  JsonWriterArduino jw(json);
  jw.boolean("ok", true);
  jw.u32("count", headlightStrobeConfig.count);
  jw.u32("intervalMs", headlightStrobeConfig.intervalMs);
  jw.u32("trigger", headlightStrobeConfig.trigger);
  jw.string("triggerName", headlightStrobeConfig.trigger == 1 ? "S3XY" : "APP");
  jw.boolean("supported", activeTurnSignalVariant == TURN_SIGNAL_STALK);
  jw.string("stalkVariant", activeTurnSignalVariant == TURN_SIGNAL_STALK ? "STALK" : "STALKLESS");
  jw.boolean("active", active);
  jw.string("state", stateName);
  jw.u32("flashesDone", headlightStrobeState.flashesDone);
  jw.u32("flashesTotal", headlightStrobeConfig.count);
  jw.string("blockReason", headlightStrobeState.blockReason ? headlightStrobeState.blockReason : "");
  jw.u32("txOk", headlightStrobeState.txOk);
  jw.u32("txFail", headlightStrobeState.txFail);
  jw.finish();
  return json;
}
```

### 4.3 四个 handler

```cpp
static void httpHeadlightStrobeConfig() {
  headlightStrobeLoadPrefs();
  if (headlightStrobeState.active) {
    server.send(409, "application/json", "{\"ok\":false,\"error\":\"ALREADY_ACTIVE\"}");
    return;
  }
  if (server.hasArg("count")) {
    const int value = server.arg("count").toInt();
    if (value < 1 || value > 30) {
      server.send(400, "application/json", "{\"ok\":false,\"error\":\"count must be 1..30\"}");
      return;
    }
    headlightStrobeConfig.count = (uint16_t)value;
  }
  if (server.hasArg("intervalMs")) {
    const int value = server.arg("intervalMs").toInt();
    if (value < 50 || value > 1000) {
      server.send(400, "application/json", "{\"ok\":false,\"error\":\"intervalMs must be 50..1000\"}");
      return;
    }
    headlightStrobeConfig.intervalMs = (uint16_t)value;
  }
  if (server.hasArg("trigger")) {
    const int value = server.arg("trigger").toInt();
    if (value != 0 && value != 1) {
      server.send(400, "application/json", "{\"ok\":false,\"error\":\"trigger must be 0 or 1\"}");
      return;
    }
    headlightStrobeConfig.trigger = (uint8_t)value;
  }
  headlightStrobeSavePrefs();
  server.send(200, "application/json", headlightStrobeJson());
}

static void httpHeadlightStrobeTrigger() {
  headlightStrobeLoadPrefs();
  if (!headlightStrobeBegin(HS_TRIGGER_APP)) {
    server.send(409, "application/json",
                String("{\"ok\":false,\"error\":\"") +
                    (headlightStrobeState.blockReason ? headlightStrobeState.blockReason : "BLOCKED") + "\"}");
    return;
  }
  server.send(200, "application/json", headlightStrobeJson());
}

static void httpHeadlightStrobeStop() {
  headlightStrobeStop("USER_STOP", true);
  server.send(200, "application/json", headlightStrobeJson());
}
```

注册：

```cpp
server.on("/api/headlight-strobe/config", HTTP_GET, httpHeadlightStrobeConfig);
server.on("/api/headlight-strobe/config", HTTP_POST, httpHeadlightStrobeConfig);
server.on("/api/headlight-strobe/trigger", HTTP_POST, httpHeadlightStrobeTrigger);
server.on("/api/headlight-strobe/stop", HTTP_POST, httpHeadlightStrobeStop);
server.on("/api/headlight-strobe/stats", HTTP_GET, []() {
  server.send(200, "application/json", headlightStrobeJson());
});
```

## 5. S3XY 触发入口（可选）

`s3xy_ble.h`：

```cpp
enum : uint8_t { S3XY_ACTION_HIGH_BEAM_STROBE = 13 };
```

并补 `s3xyActionCode/Label/ParseKnown`、`s3xyActionSupportedForCurrentProfile`、
`pending` 计数器与 `s3xyLoop` 的分发：

```cpp
if (action == S3XY_ACTION_HIGH_BEAM_STROBE) s3xyHighBeamActionPending++;
...
if (runHighBeam) {
  headlightStrobeBegin(HS_TRIGGER_S3XY);
}
```

App 的 S3XY 动作下拉里新增 `high_beam_strobe` / `High Beam Strobe`。

## 6. 冲突与边界

1. **0x249 独占**：爆闪 active 时 `sendStalkFrameCanB/A` 直接返回，转向灯/ALC/one-shot 的注入暂停；`headlightStrobe` 自己的帧保留模板里的转向 nibble，物理拨杆不受影响。
2. **启动前置条件**：必须已有真实 0x249 模板；当前不是 STALK 变体（无拨杆）直接拒绝；转向灯注入正在进行时拒绝。
3. **防重入**：`active` 时再次 trigger 返回 409 `ALREADY_ACTIVE`；App 按钮同时禁用。
4. **中断**：stop 立即发触发前高灯状态并释放 0x249；发送失败累计 5 次自动停止并恢复。
5. **恢复语义**：触发前 PUSH（远光常开）会恢复 PUSH；触发前 IDLE 恢复 IDLE；爆闪期间驾驶员改高灯不会被记录为“触发前状态”。

## 7. 验证方式

### 7.1 编译

- `arduino-cli compile` / 原工程构建通过，无新增 warning；
- `headlight_strobe.h` 与 `vehicle_logic.h` 的 include 顺序正确（必须在 `sendStalkFrameCanA` 之后）。

### 7.2 台架（CAN 分析仪，不接车）

1. 让设备先收到真实 0x249（或注入一帧合法模板），确认 `stalkFrameSnapshot` 有值；
2. 触发一次 10 次 / 200 ms：
   - 抓 `0x249`，byte1 bit5:4 应为 `1,0,1,0…` 共 20 次跳变；
   - byte1 低半字节 counter 递增，byte0 CRC 与 `leftStalkChecksumPure` 一致；
   - 总时长 ≈ 4.0 s，结束后 byte1 bit5:4 回到触发前值；
3. 触发中调用 `/stop`：应在下一 tick 停止，并立即发一帧恢复帧；
4. 触发中再次 `/trigger`：409 `ALREADY_ACTIVE`；
5. 把 trigger 设为 1（S3XY）后用 App trigger：409 `SOURCE_MISMATCH`。

### 7.3 实车（驻车、无人、远离对向车辆）

1. 车辆上电，确认 App 显示 `STALK` 且没有 `NO_STOCK_TEMPLATE`；
2. 近光灯/远光关闭状态触发 10 次：目视 10 次远近切换，结束后回到近光；
3. 远光常开（PUSH）状态触发：结束后回到远光常开；
4. 触发中打转向灯：物理转向正常，爆闪结束后转向继续；
5. 触发中按“停止并恢复”：灯立即回到触发前状态；
6. 无拨杆（Highland stalkless）车型：应返回 `STALKLESS_UNSUPPORTED`，不发送任何 0x249。

> 安全：远光灯爆闪可能造成眩目；只在封闭场地/驻车环境验证，遵守当地法规。

## 8. 已知限制

- 只支持 `0x249` 拨杆车型；`0x3C2` 无拨杆版本暂不支持（需要额外的 VCLEFT 高灯位定义）。
- 爆闪期间注入式转向灯/ALC 会暂停约 `count × 2 × interval`，物理拨杆不受影响。
- 需要重新编译并烧录固件；App 单独无法控制灯光。
