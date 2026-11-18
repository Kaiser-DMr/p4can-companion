// 前大灯爆闪 · 0x249 SCCM_highBeamStalkStatus
//
// 集成位置（P4-CAN Universal v3.29.3）：
//   1) vehicle_logic.h：在 sendStalkFrameCanB() 之前声明
//        static volatile bool headlightStrobeActiveFlag = false;
//      并在 sendStalkFrameCanB()/sendStalkFrameCanA() 开头加
//        if (headlightStrobeActiveFlag) return;
//   2) vehicle_logic.h：在 sendStalkFrameCanA() 之后 #include "headlight_strobe.h"
//   3) can_runtime.h：blinkATxTick() 之后调用 headlightStrobeTick();
//   4) web_api.h：注册 /api/headlight-strobe/{config,stats,trigger,stop}
//
// 0x249 位定义（opendbc tesla_model3_party.dbc）：
//   SCCM_highBeamStalkStatus : start bit 12, 2 bits
//   0 = IDLE, 1 = PULL（闪一下）, 2 = PUSH（远光常开）, 3 = SNA
//   位于 byte1 的 bit5:4；byte1 低半字节是 rolling counter，byte2 低半字节是转向。
//
// 设计约束：
// - 只使用已捕获的真实 0x249 模板，不凭空造帧；
// - 爆闪期间独占 0x249：其它注入（转向灯/ALC/一shot）被 sendStalkFrame* 的
//   headlightStrobeActiveFlag 守卫挡住，物理拨杆仍由整车正常工作；
// - 结束/中断时发送触发前的高灯状态（preHighBeam），再释放 0x249。

#pragma once
#include <stdint.h>

enum HeadlightStrobeStateCode : uint8_t {
  HS_STATE_IDLE = 0,
  HS_STATE_ACTIVE = 1,
  HS_STATE_COMPLETE = 2,
  HS_STATE_STOPPED = 3,
  HS_STATE_BLOCKED = 4,
};

enum HeadlightStrobeTriggerSource : uint8_t {
  HS_TRIGGER_APP = 0,
  HS_TRIGGER_S3XY = 1,
  HS_TRIGGER_HOLD = 2,   // 物理拨杆按住（Web 开关控制）
};

enum HeadlightStrobeBeam : uint8_t {
  HS_BEAM_IDLE = 0,
  HS_BEAM_PULL = 1,
  HS_BEAM_PUSH = 2,
};

struct HeadlightStrobeConfig {
  uint16_t count;       // 1..30，一次 on/off 算一次（COUNT 模式）
  uint16_t intervalMs;  // 50..1000，每次 on/off 之间的半周期
  uint8_t trigger;      // 0=APP/网页, 1=S3XY
  uint16_t durationMs;  // 0=按 count 计算；>0 表示固定总时长（100..30000），优先级高于 count
  uint8_t stopMode;     // 0=到时自动停, 1=只能手动停（持续频闪）, 2=到时或手动都可
  uint16_t maxRunMs;    // 安全上限 500..60000，任何模式到点强制停
  uint8_t holdEnabled;  // 1 = 按住远光拨杆持续爆闪（Web 开关）
  uint16_t holdDelayMs; // 按住多久才开始爆闪（0..10000，默认 2500）
};

struct HeadlightStrobeState {
  bool active;
  uint16_t count;
  uint16_t intervalMs;
  uint8_t trigger;
  uint32_t startedAtMs;
  uint32_t lastToggleMs;
  uint32_t epochAtStart;
  uint16_t flashesDone;
  bool onPhase;
  uint8_t preHighBeam;
  uint8_t state;
  const char *blockReason;
  uint32_t txOk;
  uint32_t txFail;
  uint8_t restoreBeam;  // 结束时恢复到哪个高灯状态
  uint32_t totalMs;     // 本次运行的总时长（按模式算出来的）
  uint32_t durationMs;  // 本次生效的 durationMs
  uint8_t stopMode;     // 本次生效的 stopMode
};

static HeadlightStrobeConfig headlightStrobeConfig = {10, 100, HS_TRIGGER_APP, 0, 0, 30000, 0, 2500};

static HeadlightStrobeState headlightStrobeState = {
    false, 10, 100, HS_TRIGGER_APP, 0, 0, 0, 0, false, HS_BEAM_IDLE,
    HS_STATE_IDLE, "", 0, 0, HS_BEAM_IDLE, 0, 0, 0};

static portMUX_TYPE headlightStrobeMux = portMUX_INITIALIZER_UNLOCKED;

static inline uint16_t headlightStrobeClampCount(int value) {
  if (value < 1) return 1;
  if (value > 30) return 30;
  return (uint16_t)value;
}

static inline uint16_t headlightStrobeClampInterval(int value) {
  if (value < 50) return 50;
  if (value > 1000) return 1000;
  return (uint16_t)value;
}

static inline uint16_t headlightStrobeClampDuration(int value) {
  if (value <= 0) return 0;
  if (value < 100) return 100;
  if (value > 30000) return 30000;
  return (uint16_t)value;
}

static inline uint16_t headlightStrobeClampMaxRun(int value) {
  if (value < 500) return 500;
  if (value > 60000) return 60000;
  return (uint16_t)value;
}

static inline uint16_t headlightStrobeClampHoldDelay(int value) {
  if (value <= 0) return 0;
  if (value > 10000) return 10000;
  return (uint16_t)value;
}

static inline uint8_t headlightStrobeClampStopMode(int value) {
  if (value < 0 || value > 2) return 0;
  return (uint8_t)value;
}

static inline bool headlightStrobeIsActive() {
  return headlightStrobeState.active;
}

static inline void headlightStrobeSetBlocked(const char *reason) {
  portENTER_CRITICAL(&headlightStrobeMux);
  headlightStrobeState.active = false;
  headlightStrobeState.state = HS_STATE_BLOCKED;
  headlightStrobeState.blockReason = reason ? reason : "";
  portEXIT_CRITICAL(&headlightStrobeMux);
}

// 用最新真实 0x249 模板发一帧；高灯 nibble 单独覆盖，转向/其它位保持模板值。
static bool headlightStrobeSend(uint8_t beam) {
  uint8_t counter = 0;
  uint8_t stock[4] = {0};
  if (!stalkFrameSnapshot(counter, stock)) return false;

  stock[1] = (uint8_t)((stock[1] & 0xCFu) | ((beam & 0x03u) << 4));
  const uint8_t turn = (uint8_t)(stock[2] & 0x0Fu);
  const uint32_t epoch = canTxEpochSnapshot();
  const uint8_t traceSource = CAN_TX_TRACE_SOURCE_S3XY_BUTTON;

  if (activeProfileIsYl()) {
    twai_message_t out = {};
    out.identifier = LEFTSTALK_ID;
    out.data_length_code = 4;
    if (!stalkFramePreparePure(stock, 4, counter, turn, out.data)) return false;
    if (!twaiNonSummonAdmissionOpen()) return false;
    return canTxTwaiTransmitTagged(&out, epoch, traceSource) == ESP_OK;
  }
  if (activeCanAIsBody()) {
    struct CanFrame out = {};
    out.can_id = LEFTSTALK_ID;
    out.can_dlc = 4;
    if (!stalkFramePreparePure(stock, 4, counter, turn, out.data)) return false;
    esp_err_t err = ESP_FAIL;
    const bool attempted =
        canTxNativeASendTagged(&out, epoch, traceSource, err, nullptr);
    return attempted && err == ESP_OK;
  }
  return false;
}

// source: 0=APP, 1=S3XY。返回 false 时 blockReason 说明原因。
static bool headlightStrobeBegin(uint8_t source) {
  if (headlightStrobeState.active) {
    headlightStrobeSetBlocked("ALREADY_ACTIVE");
    return false;
  }
  if (activeTurnSignalVariant != TURN_SIGNAL_STALK) {
    headlightStrobeSetBlocked("STALKLESS_UNSUPPORTED");
    return false;
  }
  // HOLD（物理拨杆）不受 trigger 选择影响；APP/S3XY 必须与配置一致。
  if (source != HS_TRIGGER_HOLD && source != headlightStrobeConfig.trigger) {
    headlightStrobeSetBlocked("SOURCE_MISMATCH");
    return false;
  }

  uint8_t counter = 0;
  uint8_t stock[4] = {0};
  if (!stalkFrameSnapshot(counter, stock)) {
    headlightStrobeSetBlocked("NO_STOCK_TEMPLATE");
    return false;
  }

  bool turnBusy = false;
  portENTER_CRITICAL(&blinkAMux);
  turnBusy = activeTurn != STALK_IDLE || oneShotTurn != STALK_IDLE || autoArmed;
  portEXIT_CRITICAL(&blinkAMux);
  if (turnBusy) {
    headlightStrobeSetBlocked("TURN_SIGNAL_ACTIVE");
    return false;
  }

  const uint32_t now = (uint32_t)millis();
  const uint16_t cfgCount = headlightStrobeClampCount(headlightStrobeConfig.count);
  const uint16_t cfgInterval =
      headlightStrobeClampInterval(headlightStrobeConfig.intervalMs);
  const uint16_t cfgDuration =
      headlightStrobeClampDuration(headlightStrobeConfig.durationMs);
  const uint8_t cfgStopMode =
      headlightStrobeClampStopMode(headlightStrobeConfig.stopMode);
  const uint16_t cfgMaxRun = headlightStrobeClampMaxRun(headlightStrobeConfig.maxRunMs);
  // 三种模式：
  //   MANUAL   —— 只受 stop 控制，跑满 maxRunMs 强制停
  //   DURATION —— 固定总时长 durationMs
  //   COUNT    —— count × 2 × intervalMs
  const uint32_t runTotal = (source == HS_TRIGGER_HOLD)
      ? (uint32_t)cfgMaxRun   // 按住期间持续，最长 maxRunMs 兜底
      : (cfgStopMode == 1
             ? (uint32_t)cfgMaxRun
             : (cfgDuration > 0
                    ? (uint32_t)cfgDuration
                    : (uint32_t)cfgCount * 2u * (uint32_t)cfgInterval));

  portENTER_CRITICAL(&headlightStrobeMux);
  headlightStrobeState.count = cfgCount;
  headlightStrobeState.intervalMs = cfgInterval;
  headlightStrobeState.trigger = headlightStrobeConfig.trigger;
  headlightStrobeState.totalMs = runTotal;
  headlightStrobeState.durationMs = cfgDuration;
  headlightStrobeState.stopMode = cfgStopMode;
  headlightStrobeState.startedAtMs = now;
  headlightStrobeState.lastToggleMs = now;
  headlightStrobeState.epochAtStart = canTxEpochSnapshot();
  headlightStrobeState.flashesDone = 0;
  headlightStrobeState.onPhase = false;
  headlightStrobeState.preHighBeam = (uint8_t)((stock[1] >> 4) & 0x03u);
  // 按住拨杆结束时，物理拨杆已经松开 -> 恢复到 IDLE，而不是触发前的 PULL。
  headlightStrobeState.restoreBeam = (source == HS_TRIGGER_HOLD)
      ? (uint8_t)HS_BEAM_IDLE
      : headlightStrobeState.preHighBeam;
  headlightStrobeState.txOk = 0;
  headlightStrobeState.txFail = 0;
  headlightStrobeState.state = HS_STATE_ACTIVE;
  headlightStrobeState.blockReason = "";
  headlightStrobeState.active = true;
  headlightStrobeActiveFlag = true;
  portEXIT_CRITICAL(&headlightStrobeMux);
  return true;
}

// 结束并恢复触发前高灯状态；reason 为 nullptr 表示完成。
static void headlightStrobeStop(const char *reason, bool restore) {
  portENTER_CRITICAL(&headlightStrobeMux);
  const bool wasActive = headlightStrobeState.active;
  const uint8_t pre = headlightStrobeState.restoreBeam;
  headlightStrobeState.active = false;
  headlightStrobeState.onPhase = false;
  headlightStrobeState.state = reason ? HS_STATE_STOPPED : HS_STATE_COMPLETE;
  headlightStrobeState.blockReason = reason ? reason : "COMPLETE";
  portEXIT_CRITICAL(&headlightStrobeMux);

  if (wasActive && restore) {
    // 先恢复高灯，再释放 0x249 独占。
    (void)headlightStrobeSend(pre);
  }
  headlightStrobeActiveFlag = false;
}

// 按住拨杆检测：读最新真实 0x249（整车 SCCM 发来的，不含本机注入）的高灯状态。
static void headlightStrobeHoldTick(uint32_t now);

static void headlightStrobeTick() {
  const uint32_t tickNow = (uint32_t)millis();
  headlightStrobeHoldTick(tickNow);
  if (!headlightStrobeState.active) return;

  if (canTxEpochSnapshot() != headlightStrobeState.epochAtStart) {
    headlightStrobeStop("CAN_EPOCH_CHANGED", true);
    return;
  }

  const uint32_t now = (uint32_t)millis();
  const uint32_t half = headlightStrobeState.intervalMs;
  const uint32_t total = headlightStrobeState.totalMs;

  if ((uint32_t)(now - headlightStrobeState.startedAtMs) >= total) {
    headlightStrobeStop(nullptr, true);
    return;
  }
  if ((uint32_t)(now - headlightStrobeState.lastToggleMs) < half) return;

  const bool turnOn = !headlightStrobeState.onPhase;
  if (!headlightStrobeSend(turnOn ? HS_BEAM_PULL : HS_BEAM_IDLE)) {
    portENTER_CRITICAL(&headlightStrobeMux);
    headlightStrobeState.txFail++;
    const bool tooMany = headlightStrobeState.txFail >= 5;
    portEXIT_CRITICAL(&headlightStrobeMux);
    if (tooMany) headlightStrobeStop("SEND_FAILED", true);
    return;
  }

  portENTER_CRITICAL(&headlightStrobeMux);
  headlightStrobeState.lastToggleMs = now;
  headlightStrobeState.onPhase = turnOn;
  headlightStrobeState.txOk++;
  if (turnOn && headlightStrobeState.flashesDone < 0xFFFFu) {
    headlightStrobeState.flashesDone++;
  }
  portEXIT_CRITICAL(&headlightStrobeMux);
}

// ── 按住拨杆 → 持续爆闪（Web 开关 holdEnabled 控制）────────────────
// 说明：本机 TX 不会被自己接收，rx249 只随整车 SCCM 的 0x249 递增，
// 所以 realRaw249[1] 的 bit5:4 就是物理拨杆的真实状态。
static uint32_t hsHoldSeenRx = 0;
static uint32_t hsHoldPullSinceMs = 0;   // 本轮连续 PULL 的起点
static uint32_t hsHoldLastRxMs = 0;
static uint8_t hsHoldPullFrames = 0;
static uint8_t hsHoldFreeFrames = 0;
// 现场诊断：最长一次「连续 PULL」持续了多久、见过几帧 PULL、最近一次起爆被谁拦住。
static uint32_t hsHoldPullMaxMs = 0;
static uint32_t hsHoldPullTotal = 0;
static uint8_t hsHoldLastBeam = 0;

static void headlightStrobeHoldTick(uint32_t now) {
  const bool holdOn = headlightStrobeConfig.holdEnabled != 0;
  const bool holdActive =
      headlightStrobeState.active && headlightStrobeState.trigger == HS_TRIGGER_HOLD;

  // 开关关掉：正在爆闪就立刻停，并清掉按压计数。
  if (!holdOn) {
    if (holdActive) headlightStrobeStop("HOLD_DISABLED", true);
    hsHoldPullFrames = 0;
    hsHoldFreeFrames = 0;
    return;
  }

  uint32_t rx = 0;
  uint8_t beam = HS_BEAM_IDLE;
  bool ckOk = false;
  portENTER_CRITICAL(&blinkAMux);
  rx = rx249;
  beam = (uint8_t)((realRaw249[1] >> 4) & 0x03u);
  ckOk = cksumSelfTest;
  portEXIT_CRITICAL(&blinkAMux);
  (void)ckOk;   // 自检只用于展示：判定不再依赖它

  const bool newFrame = (rx != hsHoldSeenRx);
  if (newFrame) {
    hsHoldSeenRx = rx;
    hsHoldLastRxMs = now;
    hsHoldLastBeam = beam;
    if (beam == HS_BEAM_PULL) {
      if (hsHoldPullFrames < 0xFF) hsHoldPullFrames++;
      hsHoldPullTotal++;
      hsHoldFreeFrames = 0;
      if (hsHoldPullSinceMs == 0) hsHoldPullSinceMs = now;
      const uint32_t held = (uint32_t)(now - hsHoldPullSinceMs);
      if (held > hsHoldPullMaxMs) hsHoldPullMaxMs = held;
    } else {
      if (hsHoldFreeFrames < 0xFF) hsHoldFreeFrames++;
      hsHoldPullFrames = 0;
      hsHoldPullSinceMs = 0;
    }
  }
  // 注意：这里不再因为「一段时间没有新帧」就把按住计时清零。
  // 有些车型的 0x249 是事件型报文——按住期间根本不发新帧，
  // 旧逻辑会在 500 ms 后清掉计时，导致「2.5 秒」永远攒不够。

  if (holdActive) {
    // 松开判定：连续 2 帧明确不是 PULL 才停（≈40 ms），保住「松手即停」体感。
    // 不再用「无帧 500 ms」停 —— 事件型 SCCM 在按住期间同样没有新帧。
    const bool longEnough =
        (uint32_t)(now - headlightStrobeState.startedAtMs) >= 150u;
    if (newFrame && hsHoldFreeFrames >= 2u && longEnough)
      headlightStrobeStop("HOLD_RELEASE", true);
    return;
  }

  // 必须持续 holdDelayMs（默认 2500 ms）才起爆，避免误触。
  const uint32_t needMs = headlightStrobeClampHoldDelay(headlightStrobeConfig.holdDelayMs);
  const bool heldLongEnough =
      hsHoldPullSinceMs != 0 && (uint32_t)(now - hsHoldPullSinceMs) >= needMs;
  // 允许按住期间完全没有新帧：只要最近一次收到的仍是 PULL 且在 4 s 内。
  const bool stillPulled =
      hsHoldPullFrames >= 1u && (uint32_t)(now - hsHoldLastRxMs) <= 4000u;
  if (heldLongEnough && stillPulled) {
    if (!headlightStrobeBegin(HS_TRIGGER_HOLD)) {
      hsHoldPullFrames = 0;   // 被拦（无模板/转向中）时不要每帧重试
    }
  }
}
