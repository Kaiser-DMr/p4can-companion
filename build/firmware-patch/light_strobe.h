// 灯光爆闪 · 转向灯 0x249 状态机（P4-CAN Universal 固件补丁）
//
// 放置位置：vehicle_logic.h，紧跟 blinkATxTick() 之后（该处可直接访问
//           sendStalkFrameCanB / stalkFrameSnapshot / canTxEpochSnapshot / STALK_*）。
//
// 依赖：0x249 拨杆帧的模板必须已在总线上被捕获过（stalkFrameSnapshot 返回 true），
//       否则拒绝注入——这是固件原有的安全设计，本补丁沿用。

#ifndef LIGHT_STROBE_H
#define LIGHT_STROBE_H

enum LightStrobePattern : uint8_t {
  LS_PATTERN_ALTERNATE = 0,
  LS_PATTERN_LEFT = 1,
  LS_PATTERN_RIGHT = 2,
};

struct LightStrobeState {
  bool active;
  uint8_t pattern;
  uint8_t hz;
  uint32_t durationMs;
  uint32_t startedAtMs;
  uint32_t lastToggleMs;
  bool onPhase;          // true = 灯亮相位（已发送 turn），false = 已回 IDLE
  bool phaseLeft;
  uint32_t txOk;
  uint32_t txFail;
  bool blocked;
  const char *blockReason;
};

static LightStrobeState lightStrobeState = {
  false, LS_PATTERN_ALTERNATE, 4, 5000, 0, 0, false, true, 0, 0, false, ""
};
static portMUX_TYPE lightStrobeMux = portMUX_INITIALIZER_UNLOCKED;

static inline uint8_t lightStrobeClampHz(int v) {
  if (v < 1) return 1;
  if (v > 8) return 8;
  return (uint8_t)v;
}

static inline uint32_t lightStrobeHalfPeriodMs(uint8_t hz) {
  // hz = 每秒完整闪几次 → 半周期 = 1000 / (2 * hz)，下限 60ms 保护灯光驱动
  uint32_t half = 1000u / (2u * (uint32_t)hz);
  return half < 60u ? 60u : half;
}

static inline uint8_t lightStrobeTurnForPhase(const LightStrobeState &s) {
  switch (s.pattern) {
    case LS_PATTERN_LEFT:  return STALK_DOWN_1;   // 下拨 = 左转（上车请确认）
    case LS_PATTERN_RIGHT: return STALK_UP_1;     // 上拨 = 右转
    default:               return s.phaseLeft ? STALK_DOWN_1 : STALK_UP_1;
  }
}

// 启动：enabled=1 时调用。返回 false 表示被拒绝，原因写进 blockReason。
static bool lightStrobeBegin(uint8_t hz, uint32_t durationMs, uint8_t pattern) {
  if (pattern > LS_PATTERN_RIGHT) pattern = LS_PATTERN_ALTERNATE;
  if (durationMs < 200) durationMs = 200;
  if (durationMs > 30000) durationMs = 30000;

  uint8_t probeCnt = 0;
  uint8_t probe[4] = {0};
  if (!stalkFrameSnapshot(probeCnt, probe)) {
    portENTER_CRITICAL(&lightStrobeMux);
    lightStrobeState.blocked = true;
    lightStrobeState.blockReason = "NO_STOCK_TEMPLATE";
    lightStrobeState.active = false;
    portEXIT_CRITICAL(&lightStrobeMux);
    return false;
  }

  const uint32_t now = (uint32_t)millis();
  portENTER_CRITICAL(&lightStrobeMux);
  lightStrobeState.hz = lightStrobeClampHz(hz);
  lightStrobeState.durationMs = durationMs;
  lightStrobeState.pattern = pattern;
  lightStrobeState.startedAtMs = now;
  lightStrobeState.lastToggleMs = now;
  lightStrobeState.onPhase = false;      // 下一个 tick 立即点亮第一下
  lightStrobeState.phaseLeft = true;
  lightStrobeState.txOk = 0;
  lightStrobeState.txFail = 0;
  lightStrobeState.blocked = false;
  lightStrobeState.blockReason = "";
  lightStrobeState.active = true;
  portEXIT_CRITICAL(&lightStrobeMux);
  return true;
}

static void lightStrobeStop(const char *reason) {
  portENTER_CRITICAL(&lightStrobeMux);
  const bool wasActive = lightStrobeState.active;
  lightStrobeState.active = false;
  if (reason && reason[0]) {
    lightStrobeState.blocked = true;
    lightStrobeState.blockReason = reason;
  }
  portEXIT_CRITICAL(&lightStrobeMux);
  if (wasActive) {
    // 收尾：把拨杆回到 IDLE，避免灯停在亮着的状态
    const uint32_t epoch = canTxEpochSnapshot();
    sendStalkFrameCanB(STALK_IDLE, epoch, true);
  }
}

// 周期调用（放在 can_runtime.h 里 blinkATxTick() 同一处）
static void lightStrobeTick() {
  if (!lightStrobeState.active) return;

  const uint32_t now = (uint32_t)millis();
  if ((uint32_t)(now - lightStrobeState.startedAtMs) >= lightStrobeState.durationMs) {
    lightStrobeStop(nullptr);           // 到时自动停，不记为故障
    return;
  }

  const uint32_t half = lightStrobeHalfPeriodMs(lightStrobeState.hz);
  if ((uint32_t)(now - lightStrobeState.lastToggleMs) < half) return;

  const uint32_t epoch = canTxEpochSnapshot();
  const bool turnOn = !lightStrobeState.onPhase;
  const uint8_t turn = turnOn ? lightStrobeTurnForPhase(lightStrobeState) : STALK_IDLE;

  sendStalkFrameCanB(turn, epoch, true);   // directUser=true：绕过 ULC 免确认抑制

  portENTER_CRITICAL(&lightStrobeMux);
  lightStrobeState.lastToggleMs = now;
  lightStrobeState.onPhase = turnOn;
  if (turnOn) {
    lightStrobeState.txOk++;
    if (lightStrobeState.pattern == LS_PATTERN_ALTERNATE) {
      lightStrobeState.phaseLeft = !lightStrobeState.phaseLeft;
    }
  }
  portEXIT_CRITICAL(&lightStrobeMux);
}

#endif  // LIGHT_STROBE_H
