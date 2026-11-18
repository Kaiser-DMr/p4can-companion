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
};

enum HeadlightStrobeBeam : uint8_t {
  HS_BEAM_IDLE = 0,
  HS_BEAM_PULL = 1,
  HS_BEAM_PUSH = 2,
};

struct HeadlightStrobeConfig {
  uint16_t count;       // 1..30，一次 on/off 算一次
  uint16_t intervalMs;  // 50..1000，每次 on/off 之间的半周期
  uint8_t trigger;      // 0=APP, 1=S3XY
};

struct HeadlightStrobeState {
  bool active;
  uint16_t count;
  uint16_t intervalMs;
  uint8_t trigger;
  uint32_t startedAtMs;
  uint32_t lastToggleMs;
  uint16_t flashesDone;
  bool onPhase;
  uint8_t preHighBeam;
  uint8_t state;
  const char *blockReason;
  uint32_t txOk;
  uint32_t txFail;
};

static HeadlightStrobeConfig headlightStrobeConfig = {10, 200, HS_TRIGGER_APP};

static HeadlightStrobeState headlightStrobeState = {
    false, 10, 200, HS_TRIGGER_APP, 0, 0, 0, false, HS_BEAM_IDLE,
    HS_STATE_IDLE, "", 0, 0};

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
  if (source != headlightStrobeConfig.trigger) {
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
  portENTER_CRITICAL(&headlightStrobeMux);
  headlightStrobeState.count = headlightStrobeClampCount(headlightStrobeConfig.count);
  headlightStrobeState.intervalMs =
      headlightStrobeClampInterval(headlightStrobeConfig.intervalMs);
  headlightStrobeState.trigger = headlightStrobeConfig.trigger;
  headlightStrobeState.startedAtMs = now;
  headlightStrobeState.lastToggleMs = now;
  headlightStrobeState.flashesDone = 0;
  headlightStrobeState.onPhase = false;
  headlightStrobeState.preHighBeam = (uint8_t)((stock[1] >> 4) & 0x03u);
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
  const uint8_t pre = headlightStrobeState.preHighBeam;
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

static void headlightStrobeTick() {
  if (!headlightStrobeState.active) return;

  const uint32_t now = (uint32_t)millis();
  const uint32_t half = headlightStrobeState.intervalMs;
  const uint32_t total = (uint32_t)headlightStrobeState.count * 2u * half;

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
  if (turnOn) {
    if (headlightStrobeState.flashesDone < headlightStrobeState.count)
      headlightStrobeState.flashesDone++;
  }
  portEXIT_CRITICAL(&headlightStrobeMux);
}
