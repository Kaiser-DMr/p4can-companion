#pragma once
// 后雾灯爆闪
//
// 控制路径（参照 Tesla Model 3/Y 车身 DBC）：
//   0x273  UI_vehicleControl   —— byte2 bit7 = UI_rearFogSwitch（1=请求后雾灯开）
//   0x3E3  VCRIGHT_lightStatus —— byte1 bit1:0 = VCRIGHT_rearFogLightStatus（整车回读）
//
// 做法：收到整车自己的 0x273 后，立刻回发一份「只翻转后雾灯位」的副本（与固件里
// 0x293 变道注入相同的时序策略，避免与整车同 ID 报文抢占）。停止注入后，整车下一帧
// 就会把灯带回它自己的状态，因此不需要额外「恢复」帧也能自然恢复；stop 时仍会补发
// 一帧带原始状态的副本，让恢复更即时。
//
// 单次最长 30 秒；间隔沿用「前大灯爆闪」的 intervalMs（默认 100 ms）。

static constexpr uint16_t REAR_FOG_FRAME_ID = 0x273;
static constexpr uint8_t REAR_FOG_BIT_BYTE = 2;
static constexpr uint8_t REAR_FOG_BIT_MASK = 0x80;
static constexpr uint32_t REAR_FOG_MAX_MS = 30000;
static constexpr uint32_t REAR_FOG_TEMPLATE_TTL_MS = 2000;

enum RearFogStopReason : uint8_t {
  REAR_FOG_STOP_NONE = 0,
  REAR_FOG_STOP_USER = 1,
  REAR_FOG_STOP_TIMEOUT = 2,
  REAR_FOG_STOP_NO_FRAME = 3,
};

struct RearFogStrobeState {
  bool active;
  bool templateValid;
  uint8_t bus;              // 0 = CAN A（Body/Vehicle），1 = CAN B
  uint8_t templateData[8];
  uint8_t templateDlc;
  uint32_t templateMs;
  uint32_t startedAtMs;
  uint32_t lastToggleMs;
  bool phaseOn;
  uint32_t pulses;
  uint32_t txOk;
  uint32_t txFail;
  bool stockFogOn;          // 整车自己的后雾灯状态（出发前）
  uint8_t stopReason;
};

static portMUX_TYPE rearFogStrobeMux = portMUX_INITIALIZER_UNLOCKED;
static RearFogStrobeState rearFogStrobeState = {
    false, false, 1, {0, 0, 0, 0, 0, 0, 0, 0}, 8, 0, 0, 0, false, 0, 0, 0, false,
    REAR_FOG_STOP_NONE};

static inline bool rearFogBitOn(const uint8_t *data) {
  return (data[REAR_FOG_BIT_BYTE] & REAR_FOG_BIT_MASK) != 0;
}

static inline void rearFogWriteBit(uint8_t *data, bool on) {
  if (on) {
    data[REAR_FOG_BIT_BYTE] |= REAR_FOG_BIT_MASK;
  } else {
    data[REAR_FOG_BIT_BYTE] &= (uint8_t)~REAR_FOG_BIT_MASK;
  }
}

static inline uint16_t rearFogStrobeHalfPeriodMs() {
  return headlightStrobeClampInterval(headlightStrobeConfig.intervalMs);
}

static bool rearFogStrobeIsActive() {
  bool active;
  portENTER_CRITICAL(&rearFogStrobeMux);
  active = rearFogStrobeState.active;
  portEXIT_CRITICAL(&rearFogStrobeMux);
  return active;
}

static uint32_t rearFogStrobeRemainingMs() {
  uint32_t remaining = 0;
  portENTER_CRITICAL(&rearFogStrobeMux);
  if (rearFogStrobeState.active) {
    const uint32_t elapsed = (uint32_t)millis() - rearFogStrobeState.startedAtMs;
    remaining = elapsed >= REAR_FOG_MAX_MS ? 0 : (REAR_FOG_MAX_MS - elapsed);
  }
  portEXIT_CRITICAL(&rearFogStrobeMux);
  return remaining;
}

// 在对应总线上发送一帧：镜像 src，把后雾灯位改成 on。
static void rearFogStrobeSend(uint8_t bus, const uint8_t *src, uint8_t dlc, bool on) {
  if (dlc < 8) return;
  uint8_t out[8];
  memcpy(out, src, 8);
  rearFogWriteBit(out, on);
  const uint32_t txEpoch = canTxEpochSnapshot();
  bool ok = false;
  if (bus == 0) {
    struct CanFrame frame = {};
    frame.can_id = REAR_FOG_FRAME_ID;
    frame.can_dlc = 8;
    memcpy(frame.data, out, 8);
    esp_err_t err = ESP_FAIL;
    const bool attempted = canTxNativeASend(&frame, txEpoch, err, nullptr);
    ok = attempted && err == ESP_OK;
  } else {
    twai_message_t msg = {};
    msg.identifier = REAR_FOG_FRAME_ID;
    msg.data_length_code = 8;
    memcpy(msg.data, out, 8);
    ok = canTxTwaiTransmit(&msg, txEpoch) == ESP_OK;
    researchCaptureObserveTxVh(REAR_FOG_FRAME_ID, 8, out, ok);
  }
  portENTER_CRITICAL(&rearFogStrobeMux);
  if (ok) {
    rearFogStrobeState.txOk++;
  } else {
    rearFogStrobeState.txFail++;
  }
  portEXIT_CRITICAL(&rearFogStrobeMux);
}

// RX 钩子：记录模板；若正在爆闪，立刻回发一帧带当前相位的副本。
static void rearFogStrobeObserve(uint8_t bus, const uint8_t *data, uint8_t dlc) {
  if (dlc < 8) return;
  const uint32_t now = (uint32_t)millis();
  bool active;
  bool phaseOn;
  portENTER_CRITICAL(&rearFogStrobeMux);
  rearFogStrobeState.stockFogOn = rearFogBitOn(data);
  memcpy(rearFogStrobeState.templateData, data, 8);
  rearFogStrobeState.templateDlc = dlc;
  rearFogStrobeState.bus = bus;
  rearFogStrobeState.templateMs = now;
  rearFogStrobeState.templateValid = true;
  active = rearFogStrobeState.active;
  phaseOn = rearFogStrobeState.phaseOn;
  portEXIT_CRITICAL(&rearFogStrobeMux);
  if (!active) return;
  rearFogStrobeSend(bus, data, dlc, phaseOn);
}

static void rearFogStrobeStop(uint8_t reason) {
  uint8_t bus = 1;
  uint8_t dlc = 8;
  uint8_t snapshot[8];
  bool stockOn = false;
  bool wasActive = false;
  portENTER_CRITICAL(&rearFogStrobeMux);
  wasActive = rearFogStrobeState.active;
  rearFogStrobeState.active = false;
  rearFogStrobeState.phaseOn = false;
  if (wasActive) rearFogStrobeState.stopReason = reason;
  bus = rearFogStrobeState.bus;
  dlc = rearFogStrobeState.templateDlc;
  memcpy(snapshot, rearFogStrobeState.templateData, 8);
  stockOn = rearFogStrobeState.stockFogOn;
  const bool templateFresh =
      rearFogStrobeState.templateValid &&
      (uint32_t)((uint32_t)millis() - rearFogStrobeState.templateMs) <= REAR_FOG_TEMPLATE_TTL_MS;
  portEXIT_CRITICAL(&rearFogStrobeMux);
  if (!wasActive || !templateFresh) return;
  // 补发一帧「整车原始状态」，让灯立刻回到触发前，而不是等下一帧。
  rearFogStrobeSend(bus, snapshot, dlc, stockOn);
}

static bool rearFogStrobeStart() {
  if (vehicleProfileSetupMode) return false;
  const uint32_t now = (uint32_t)millis();
  portENTER_CRITICAL(&rearFogStrobeMux);
  const bool busy = rearFogStrobeState.active;
  const bool fresh =
      rearFogStrobeState.templateValid &&
      (uint32_t)(now - rearFogStrobeState.templateMs) <= REAR_FOG_TEMPLATE_TTL_MS;
  if (!busy && fresh) {
    rearFogStrobeState.active = true;
    rearFogStrobeState.startedAtMs = now;
    rearFogStrobeState.lastToggleMs = now;
    rearFogStrobeState.phaseOn = true;
    rearFogStrobeState.pulses = 1;
    rearFogStrobeState.txOk = 0;
    rearFogStrobeState.txFail = 0;
    rearFogStrobeState.stopReason = REAR_FOG_STOP_NONE;
  }
  portEXIT_CRITICAL(&rearFogStrobeMux);
  return !busy && fresh;
}

// 周期任务：30 秒封顶、按 intervalMs 翻相位、整车帧断了就停。
static void rearFogStrobeTick() {
  bool active;
  uint32_t startedAt;
  uint32_t lastToggle;
  uint32_t templateMs;
  bool templateValid;
  portENTER_CRITICAL(&rearFogStrobeMux);
  active = rearFogStrobeState.active;
  startedAt = rearFogStrobeState.startedAtMs;
  lastToggle = rearFogStrobeState.lastToggleMs;
  templateMs = rearFogStrobeState.templateMs;
  templateValid = rearFogStrobeState.templateValid;
  portEXIT_CRITICAL(&rearFogStrobeMux);
  if (!active) return;

  const uint32_t now = (uint32_t)millis();
  if (!templateValid || (uint32_t)(now - templateMs) > 500) {
    rearFogStrobeStop(REAR_FOG_STOP_NO_FRAME);
    return;
  }
  if ((uint32_t)(now - startedAt) >= REAR_FOG_MAX_MS) {
    rearFogStrobeStop(REAR_FOG_STOP_TIMEOUT);
    return;
  }
  const uint16_t half = rearFogStrobeHalfPeriodMs();
  if ((uint32_t)(now - lastToggle) < half) return;
  portENTER_CRITICAL(&rearFogStrobeMux);
  rearFogStrobeState.phaseOn = !rearFogStrobeState.phaseOn;
  rearFogStrobeState.lastToggleMs = now;
  if (rearFogStrobeState.phaseOn) rearFogStrobeState.pulses++;
  portEXIT_CRITICAL(&rearFogStrobeMux);
}
