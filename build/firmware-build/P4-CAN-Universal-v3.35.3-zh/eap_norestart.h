// ─────────────────────────────────────────────────────────────
// EAP / TLSSC 免重启补发（最小化移植自 baicyber/P4can-No-Reboot）
//
// 目标固件：P4-CAN Universal v3.35.3 中文版
//
// 原有逻辑（service_settings.h: chinaRestoreEcho）：
//   车发 0x331 → 我们改 byte0 低 6 位为 0x1B → 补发一帧。
//   车机只在启动时读一次 DAS 配置；如果那一刻总线上没有改过的 0x331，
//   就会锁存“封禁”，必须人工重启车机。
//
// 本补丁：
//   1) 缓存最近一次补丁后的 0x331（NVS，每个上电周期最多写一次）
//   2) 上电后 CAN CHASSIS 就绪即开 60 s 窗口，10 Hz 补发缓存帧
//   3) 车自己开始发 0x331（2 s 内新鲜）立即让位
//   4) 600 帧或窗口到期停止
//
// 与参考实现的差异：
//   · v3.35.3 没有 bannedCar 变量，条件改为 chinaRestoreEnabled
//   · 直接按 P4_CHASSIS 发送（兼容 YL：CHASSIS 是 extra 总线）
//   · 发送走 canTxBarrierMutex + p4CanSendFrame，和 chinaRestoreEcho 同一套门控
// ─────────────────────────────────────────────────────────────
#pragma once

#define EAP_NR_NS          "eapnr"
#define EAP_NR_KEY_ON      "on"
#define EAP_NR_KEY_FRAME   "frame"

#define EAP_NR_WINDOW_MS      60000u
#define EAP_NR_PERIOD_MS        100u
#define EAP_NR_MAX_FRAMES       600u
#define EAP_NR_STOCK_FRESH_MS  2000u

static volatile bool eapNrEnabled = true;
static uint8_t eapNrFrame[8] = {};
static volatile uint8_t eapNrFrameLen = 0;
static volatile bool eapNrFrameValid = false;
static volatile bool eapNrPersisted = false;
static volatile uint32_t eapNrStockRx = 0;
static volatile uint32_t eapNrStockMs = 0;
static volatile uint32_t eapNrReplayOk = 0;
static volatile uint32_t eapNrReplayFail = 0;
static volatile uint32_t eapNrReplayBusy = 0;
static volatile uint32_t eapNrReplaySkip = 0;
static volatile uint32_t eapNrLastReplayMs = 0;
static volatile int16_t eapNrLastErr = 0;
static volatile uint32_t eapNrArmedMs = 0;
static volatile uint16_t eapNrBurst = 0;

static bool eapNrPrereq() {
  return chinaRestoreEnabled;
}

// ── NVS ───────────────────────────────────────────────────────
static void eapNrLoad() {
  Preferences p;
  if (!p.begin(EAP_NR_NS, true)) return;
  eapNrEnabled = p.getBool(EAP_NR_KEY_ON, true);
  String hex = p.getString(EAP_NR_KEY_FRAME, "");
  p.end();

  if (hex.length() == 16) {
    bool ok = true;
    for (uint8_t i = 0; i < 8; i++) {
      auto nib = [](char c) -> int8_t {
        if (c >= '0' && c <= '9') return (int8_t)(c - '0');
        if (c >= 'a' && c <= 'f') return (int8_t)(c - 'a' + 10);
        if (c >= 'A' && c <= 'F') return (int8_t)(c - 'A' + 10);
        return -1;
      };
      const int8_t a = nib(hex[i * 2]), b = nib(hex[i * 2 + 1]);
      if (a < 0 || b < 0) { ok = false; break; }
      eapNrFrame[i] = (uint8_t)((a << 4) | b);
    }
    if (ok) {
      eapNrFrameLen = 8;
      eapNrFrameValid = true;
    }
  }
  eapNrPersisted = eapNrFrameValid;
}

static void eapNrPersistFrame() {
  if (eapNrPersisted || !eapNrFrameValid) return;
  char hex[17];
  for (uint8_t i = 0; i < 8; i++) snprintf(hex + i * 2, 3, "%02X", eapNrFrame[i]);
  hex[16] = '\0';
  Preferences p;
  if (!p.begin(EAP_NR_NS, false)) return;
  const size_t n = p.putString(EAP_NR_KEY_FRAME, hex);
  p.end();
  if (n > 0) eapNrPersisted = true;
}

static bool eapNrSetEnabled(bool on, const char *&note) {
  note = "applied";
  Preferences p;
  if (!p.begin(EAP_NR_NS, false)) { note = "nvs-open-failed"; return false; }
  const size_t n = p.putBool(EAP_NR_KEY_ON, on);
  p.end();
  if (n == 0) { note = "nvs-write-failed"; return false; }
  eapNrEnabled = on;
  if (on && eapNrFrameValid && !eapNrPersisted) eapNrPersistFrame();
  // 重新开窗：用户在车上点开时立即补发，而不是等下一轮上电。
  eapNrArmedMs = 0;
  eapNrBurst = 0;
  eapNrStockMs = 0;
  return true;
}

// ── 观察车端 0x331，缓存补丁后的载荷 ─────────────────────────
static void eapNrCache331(uint8_t dlc, const uint8_t *data);

static void eapNrObserve331(const twai_message_t &f) {
  if (f.extd || f.rtr || f.data_length_code < 1) return;
  eapNrCache331(f.data_length_code, f.data);
}

// extra 总线路径用的是 CanFrame（无 extd/rtr 成员），单独重载。
static void eapNrObserve331(const CanFrame &f) {
  if ((f.can_id & 0xC0000000UL) != 0 || f.can_dlc < 1) return;
  eapNrCache331(f.can_dlc, f.data);
}

static void eapNrCache331(uint8_t dlc, const uint8_t *data) {
  eapNrStockRx++;
  eapNrStockMs = (uint32_t)millis();

  uint8_t patched[8] = {};
  const uint8_t n = dlc > 8 ? 8 : dlc;
  for (uint8_t i = 0; i < n; i++) patched[i] = data[i];
  patched[0] = (uint8_t)((patched[0] & 0xC0U) | 0x1BU);

  bool changed = (eapNrFrameLen != n) || !eapNrFrameValid;
  for (uint8_t i = 0; i < n && !changed; i++)
    if (eapNrFrame[i] != patched[i]) changed = true;
  if (changed) {
    for (uint8_t i = 0; i < n; i++) eapNrFrame[i] = patched[i];
    eapNrFrameLen = n;
    eapNrFrameValid = true;
    if (eapNrEnabled) eapNrPersistFrame();
  }
}

// ── 周期补发 ─────────────────────────────────────────────────
static void eapNrTick() {
  if (!eapNrEnabled) return;
  if (!eapNrPrereq()) {
    // TLSSC 恢复关掉后重新开窗，下次打开立即补发。
    eapNrArmedMs = 0;
    eapNrBurst = 0;
    return;
  }
  if (!p4CanOnline[P4_CHASSIS] || !p4CanHandles[P4_CHASSIS]) return;
  if (!twaiReady || canTxAdministrativeHold || canUsbPassive()) return;

  const uint32_t now = (uint32_t)millis();
  if (eapNrArmedMs == 0) eapNrArmedMs = now ? now : 1u;
  if ((uint32_t)(now - eapNrArmedMs) > EAP_NR_WINDOW_MS) return;
  if (eapNrBurst >= EAP_NR_MAX_FRAMES) return;
  if (!eapNrFrameValid) { eapNrReplaySkip++; return; }

  // 车自己在发 0x331 就让位，回到 chinaRestoreEcho 的读-改-重发。
  if (eapNrStockMs && (uint32_t)(now - eapNrStockMs) < EAP_NR_STOCK_FRESH_MS) return;
  if (eapNrLastReplayMs && (uint32_t)(now - eapNrLastReplayMs) < EAP_NR_PERIOD_MS) return;

  if (!canTxBarrierMutex || xSemaphoreTake(canTxBarrierMutex, 0) != pdTRUE) {
    eapNrReplayBusy++;
    return;
  }

  esp_err_t err = ESP_ERR_INVALID_STATE;
  const uint32_t epoch = canTxEpochSnapshot();
  if (!canTxAdministrativeHold && !canUsbPassive() && p4CanAllRunning() &&
      epoch != 0u && epoch == canTxBarrierState.epoch &&
      (P4_CHASSIS != p4CanBusB() || twaiNonSummonAdmissionOpen())) {
    CanFrame out = {};
    out.bus = P4_CHASSIS;
    out.can_id = 0x331u;
    out.can_dlc = eapNrFrameLen;
    for (uint8_t i = 0; i < eapNrFrameLen; i++) out.data[i] = eapNrFrame[i];
    err = p4CanSendFrame(&out);
  }
  xSemaphoreGive(canTxBarrierMutex);

  eapNrLastErr = (int16_t)err;
  if (err == ESP_ERR_TIMEOUT) {
    // TX 屏障被爆闪/AP/维护等短暂占用：让位，下个周期重试，不算失败。
    eapNrReplayBusy++;
    return;
  }
  eapNrLastReplayMs = now ? now : 1u;
  eapNrBurst++;
  if (err == ESP_OK) eapNrReplayOk++;
  else eapNrReplayFail++;
}

static String eapNrStatsJson() {
  String j = "{";
  j += "\"enabled\":"; j += eapNrEnabled ? "true" : "false";
  j += ",\"prereq\":"; j += eapNrPrereq() ? "true" : "false";
  j += ",\"cacheValid\":"; j += eapNrFrameValid ? "true" : "false";
  j += ",\"cacheLen\":"; j += String((unsigned)eapNrFrameLen);
  j += ",\"cacheHex\":\"";
  if (eapNrFrameValid) {
    for (uint8_t i = 0; i < eapNrFrameLen; i++) {
      char b[3]; snprintf(b, sizeof(b), "%02X", eapNrFrame[i]); j += b;
    }
  }
  j += "\",\"stockRx\":"; j += String((unsigned long)eapNrStockRx);
  j += ",\"stockMs\":"; j += String((unsigned long)eapNrStockMs);
  j += ",\"replayOk\":"; j += String((unsigned long)eapNrReplayOk);
  j += ",\"replayFail\":"; j += String((unsigned long)eapNrReplayFail);
  j += ",\"replayBusy\":"; j += String((unsigned long)eapNrReplayBusy);
  j += ",\"replaySkip\":"; j += String((unsigned long)eapNrReplaySkip);
  j += ",\"burst\":"; j += String((unsigned)eapNrBurst);
  j += ",\"lastMs\":"; j += String((unsigned long)eapNrLastReplayMs);
  j += ",\"lastErr\":"; j += String((int)eapNrLastErr);
  j += "}";
  return j;
}
