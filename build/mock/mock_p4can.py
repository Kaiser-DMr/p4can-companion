#!/usr/bin/env python3
"""P4-CAN 固件本地 mock（仅用于 App 联调）。

模拟 web_api.h / s3xy_ble.h 的真实字段结构：
  GET  /api/snapshot?groups=home-fast[&slow=1]
  GET  /api/profile/status  /api/features/status  /api/s3xy/stats  ...
  POST /api/nag/update?enabled=1 等（返回 ok，并维护少量开关状态）
"""
import json
import os
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

LOCK = threading.Lock()

STATE = {
    "nag_enabled": True,
    "nag_mode": 7,
    "nag_method": 0,
    "blink_enabled": True,
    "tlssc": True,
    "lab": True,
    "s3xy_bt": True,
    "can_alive": True,
}


def j(obj):
    return json.dumps(obj, ensure_ascii=False)


def snapshot_fast():
    t = 1.35
    return {
        "nag": {
            "torque": round(t, 2),
            "handsOnState": 2,
            "stoppedGate": False,
            "stopCarrierActive": False,
            "apActive": True,
            "canAState": 1,
        },
        "blink": {
            "enabled": STATE["blink_enabled"],
            "noaActive": True,
            "noaSessionState": 2,
            "noaSessionStateName": "READY",
            "noaStabilizationRemainingMs": 0,
            "noaExitRemainingMs": 0,
            "cancelPaused": False,
            "dasStateValid": True,
            "dasState": 4,
            "displayStateValid": True,
            "displayState": 4,
            "canReinitializing": False,
        },
        "summon": {"canState": 1, "canStateName": "RUNNING"},
        "cantraffic": {
            "canBusCount": 3,
            "can1Name": "BODY",
            "can1State": 1,
            "can1RxCount": 128934,
            "can1TxAccepted": 1203,
            "can1TxRejected": 2,
            "can1BusOffCount": 0,
            "can1TrafficAgeMs": 8,
            "can1Ready": True,
            "can1TrafficSeen": True,
            "can1TrafficOnline": True,
            "can1TxPin": 20,
            "can1RxPin": 21,
            "can2Name": "CHASSIS",
            "can2State": 1,
            "can2RxCount": 88210,
            "can2TxAccepted": 640,
            "can2TxRejected": 0,
            "can2BusOffCount": 1,
            "can2TrafficAgeMs": 15,
            "can2Ready": True,
            "can2TrafficSeen": True,
            "can2TrafficOnline": True,
            "can2TxPin": 22,
            "can2RxPin": 23,
            "can3Name": "PARTY",
            "can3State": 1 if STATE["can_alive"] else 2,
            "can3RxCount": 33210,
            "can3TxAccepted": 88,
            "can3TxRejected": 1,
            "can3BusOffCount": 0,
            "can3TrafficAgeMs": 42,
            "can3Ready": True,
            "can3TrafficSeen": True,
            "can3TrafficOnline": bool(STATE["can_alive"]),
            "can3TxPin": 26,
            "can3RxPin": 27,
        },
        "r79": {
            "txState": "ACTIVE",
            "apWaitRemainingMs": 0,
            "apGateReason": "AP_ACTIVE",
            "txReason": "OK",
            "gearName": "D",
            "dasState": 4,
            "dasStateValid": True,
            "txOk": 532,
            "txFail": 0,
            "lastTxValid": True,
            "lastTxAgeMs": 120,
        },
    }


def snapshot_slow():
    return {
        "blink": {"enabled": STATE["blink_enabled"], "delayMs": 0},
        "summon": {"tlssc": STATE["tlssc"]},
        "s3xy": {
            "bluetoothEnabled": STATE["s3xy_bt"],
            "pairedCount": 2,
            "connectedCount": 1,
        },
        "r79": {"smartMode": 1},
        "lab3f8": {"alcMode": 2},
    }


PROFILE = {
    "ok": True,
    "setupMode": False,
    "nvsError": False,
    "migrationNotice": False,
    "profile": 3,
    "profileName": "Model Y (Juniper)",
    "topology": 2,
    "topologyName": "BODY + CHASSIS + PARTY",
    "canA": "BODY",
    "canB": "CHASSIS",
    "canExtra": "PARTY",
    "routeABus": 1,
    "routeBBus": 2,
    "turn": 1,
    "turnName": "STALK",
    "nagSupported": True,
    "nagTorqueSupported": True,
    "nagTsl9Supported": True,
    "advancedEapSupported": True,
    "pedalMapSupported": True,
    "apDriveProfileSupported": True,
    "apDriveProfile": False,
    "apDriveProfileRegenRaw": 20,
    "apDriveProfileRegenName": "STANDARD",
    "bodyControlsSupported": True,
    "euUnlockSupported": True,
    "tlsscRestoreSupported": True,
    "bannedSupported": True,
}

FEATURES = {
    "ok": True,
    "lab": STATE["lab"],
    "doorCancel": False,
    "nagSupported": True,
    "nagTorqueSupported": True,
    "nagTsl9Supported": True,
    "advancedEapSupported": True,
    "pedalMapSupported": True,
    "apDriveProfileSupported": True,
    "apDriveProfile": False,
    "apDriveProfileRegenRaw": 20,
    "apDriveProfileRegenName": "STANDARD",
    "bodyControlsSupported": True,
    "euUnlockSupported": True,
    "banned": False,
    "tlsscRestore": False,
    "tlsscRestoreSupported": True,
    "bannedSupported": True,
    "s3xy": STATE["s3xy_bt"],
}

NAG_CONFIG = {
    "enabled": True,
    "ignoreApState": False,
    "method": 0,
    "methodName": "Torque",
    "tsl9Sequence": 0,
    "tsl9SequenceName": "V8.2",
    "tsl9Window": 1,
    "tsl9WindowName": "WINDOW",
    "tsl9InputMode": 0,
    "torqueRightScrollEnabled": False,
    "torqueRightScrollIntervalSeconds": 12,
    "torqueRightScrollPattern": 0,
    "tsl9RightPeriodicEnabled": False,
    "tsl9RightPeriodicIntervalSeconds": 30,
    "tsl9LegacyRoute": 0,
    "tsl9LegacyRouteSelectable": True,
    "tsl9EffectiveRoute": 0,
    "pauseAtZeroSpeed": False,
    "modeHStopBehavior": 1,
    "modeHStopBehaviorName": "STOCK CARRIER",
    "mode": 7,
    "targetId": 0x399,
    "hoRatePct": 100,
    "burstMs": 200,
    "pauseMs": 800,
    "apStateId": 4,
    "steeringId": 0x399,
    "humanVariant": 4,
    "humanVariantCode": "V4",
    "humanVariantLabel": "V4",
    "humanPreset": 0,
    "humanPeakMinNm": 1.5,
    "humanPeakMaxNm": 1.8,
    "hoPolicy": 2,
    "hoPolicyName": "TIERED",
    "ho1ThresholdNm": 1.2,
    "ho2ThresholdNm": 2.0,
    "visualRescueEnabled": False,
    "visualRescueDelayMs": 0,
    "torque": 1.35,
}

S3XY = {
    "bluetoothEnabled": STATE["s3xy_bt"],
    "bleInitialized": True,
    "cryptoSelfTestChecked": True,
    "cryptoSelfTestOk": True,
    "autoEnabled": True,
    "diagnosticsEnabled": True,
    "scanning": False,
    "scanError": "",
    "maxDevices": 8,
    "pairedCount": 2,
    "connectedCount": 1,
    "devices": [
        {
            "id": 1,
            "name": "S3XY Button · 左",
            "address": "AA:BB:CC:11:22:33",
            "state": "READY",
            "error": "",
            "connected": True,
            "paused": False,
            "autoConnect": True,
            "rssi": -58,
            "singleAction": "none",
            "doubleAction": "tlssc_toggle",
            "longAction": "none",
            "singleLabel": "None",
            "doubleLabel": "TLSSC Toggle",
            "longLabel": "None",
        },
        {
            "id": 2,
            "name": "S3XY Button · 右",
            "address": "AA:BB:CC:44:55:66",
            "state": "IDLE",
            "error": "",
            "connected": False,
            "paused": False,
            "autoConnect": False,
            "rssi": -71,
            "singleAction": "left_blinker",
            "doubleAction": "none",
            "longAction": "none",
            "singleLabel": "Left Blinker",
            "doubleLabel": "None",
            "longLabel": "None",
        },
    ],
    "scanResults": [
        {
            "address": "AA:BB:CC:77:88:99",
            "name": "S3XY Button · 新",
            "rssi": -66,
            "registered": False,
        }
    ],
}

SYSTEM = {
    # 固件当前不支持 SOC；这里仅用于演示 App 的"有字段就显示"能力
    "batterySoc": 68,
    "rangeKm": 312,
    "fwVersion": "v3.29.3 (mock)",
    "freeHeap": 184320,
    "minFreeHeap": 151200,
    "largestHeapBlock": 98304,
    "uptimeS": 5321,
    "canBusCount": 3,
    "can1Name": "BODY",
    "can1State": 1,
    "can1Ready": True,
    "can1TrafficOnline": True,
    "can1RxCount": 128934,
    "can1TxAccepted": 1203,
    "can1TxRejected": 2,
    "can1BusOffCount": 0,
    "can1TrafficAgeMs": 8,
    "can2Name": "CHASSIS",
    "can2State": 1,
    "can2Ready": True,
    "can2TrafficOnline": True,
    "can2RxCount": 88210,
    "can2TxAccepted": 640,
    "can2TxRejected": 0,
    "can2BusOffCount": 1,
    "can2TrafficAgeMs": 15,
    "can3Name": "PARTY",
    "can3State": 1,
    "can3Ready": True,
    "can3TrafficOnline": True,
    "can3RxCount": 33210,
    "can3TxAccepted": 88,
    "can3TxRejected": 1,
    "can3BusOffCount": 0,
    "can3TrafficAgeMs": 42,
}

STATS = {
    "/api/ulc/stats": {
        "anyOverride": True, "gateOpen": True, "gateRule": "AP_ACTIVE",
        "dasState": 4, "dasStateValid": True, "dasAgeMs": 90,
        "alcMode": 2, "ulcBlindMode": 1, "ulcOffHighwayMode": 255,
        "stockAlcOffHighway": True, "stockUlcOffHighway": True, "stockUlcBlindSpot": 2,
        "policyGateOpen": True,
        "stalkConfirmSupported": True, "stalkConfirmEnabled": False,
        "stalkConfirmTimingMode": 0, "stalkConfirmGateOpen": True,
        "stalkConfirmRoute": "CAN B / Chassis", "stalkConfirmCanBName": "CHASSIS",
        "autoLaneChangeEnabled": True, "autoLaneChangeTargetBus": 1,
        "autoLaneChangeGateOpen": True,
        "autoLaneChangeTxAOk": 21, "autoLaneChangeTxAFail": 0,
        "autoLaneChangeTxBOk": 0, "autoLaneChangeTxBFail": 0,
        "txOk": 21, "txFail": 0,
    },
    "/api/summon/stats": {
        "monitoring": True, "tlssc": True, "tlsscHighwayGateEnabled": True,
        "tlsscBlockInNoa": False, "tlsscInjectedActive": True, "tlsscClearPending": False,
        "roadContextValid": True, "roadClass": 2, "navRouteActive": True,
        "controlledAccess": True, "summonRouteValid": True,
        "gearSourceName": "CHASSIS", "gearName": "D",
        "txOk": 88, "txFail": 0, "canState": 1, "canStateName": "RUNNING", "uptimeS": 5321,
    },
    "/api/blinkA/stats": {
        "enabled": STATE["blink_enabled"], "apActive": True, "noaActive": True,
        "noaStabilizationSeconds": 8, "noaStabilized": True,
        "noaSessionState": 2, "noaSessionStateName": "READY",
        "cancelPauseSeconds": 30, "cancelPaused": False,
        "dasStateValid": True, "dasState": 4, "alcState": 2,
        "delayMs": 0, "txMode": 1, "txModeName": "BURST",
        "txOk": 12, "txFail": 0, "txRequests": 12, "uptimeS": 5321,
    },
    "/api/driver-monitoring/config": {"enabled": False, "supported": True, "active": False},
    "/api/isa-suppression/config": {
        "enabled": False, "supported": True, "active": False,
        "route": "BODY", "modified": False, "txOk": 0, "txFail": 0,
    },
    "/api/vision-control/stats": {
        "requestDisabled": False, "bus": 0, "supported": True, "busSupported": True,
        "bodySupported": True, "labEnabled": True, "busSelectorVisible": True,
        "apActive": True, "apFresh": True, "stockValid": True, "stockBit": 1,
        "rxAgeMs": 80, "rxCount": 1200, "gateOpen": False, "txOk": 0, "txFail": 0,
        "state": "OFF",
    },
    "/api/r79/stats": {
        "fixedPolicy": False, "mode": 1, "modeName": "MODE 1", "transport": "CAN",
        "periodic": True, "mode1TxWaitMode": 0,
        "mode1ReinjectEnabled": True, "mode1DelayMs": 120,
        "mode2ReinjectEnabled": False, "mode2DelayMs": 200,
        "bit18Mode": 1, "bit18ModeName": "OVERRIDE", "bit19": 0,
        "hw3Enabled": 0, "hw3Supported": True, "hw3Active": False,
        "dmsNagSupported": True, "dmsNagEnabled": False, "dmsNagActive": False,
        "runtimeState": "RUNNING", "txOk": 320, "txFail": 1,
    },
    "/api/r79/ap-control/stats": {
        "enabled": True, "allowManualDriving": False, "mode": 1, "delaySeconds": 5,
        "apActive": True, "gateAllowed": True, "gateReason": "AP_ACTIVE", "remainingMs": 0,
    },
    "/api/pedalmap/stats": {
        "valid": True, "stockRaw": 0, "stockName": "STOCK", "ageMs": 40,
        "overrideActive": True, "targetRaw": 1, "targetName": "CHILL",
        "originRaw": 0, "txOk": 12, "txFail": 0, "blocked": False, "stockAccepted": True,
        "apDriveProfileEnabled": False, "apDriveProfileActive": False,
        "apDriveProfileRegenRaw": 20, "apDriveProfileRegenName": "STANDARD",
    },
    "/api/lab/summon-heartbeat/stats": {
        "ok": True, "supported": True, "labEnabled": True,
        "enabled": False, "selectedValue": 0, "gateOpen": True,
        "stockValid": True, "stockFresh": True, "stockValue": 0, "stockAgeMs": 120,
        "appliedCount": 0, "txFail": 0, "blocked": False, "state": "IDLE",
    },
    "/api/researchcapture/stats": {
        "state": "IDLE", "captureMode": "SNAPSHOT", "capturing": False, "exporting": False,
        "preMs": 5000, "postMs": 5000, "preWindowMs": 5000, "postWindowMs": 5000,
        "samples": 0, "capacity": 20000, "requests": 0, "dropped": 0,
        "currentSlot": 0, "completedSegments": 0,
        "labels": {"A": "baseline", "B": "glance", "C": "side", "D": "down"},
    },
    "/api/country/stats": {
        "countrySupported": True, "countryMode": 0, "countryModeName": "STOCK",
        "mode": 0, "modeName": "STOCK", "mapMode": 0, "mapModeName": "STOCK",
        "gateAllowed": True, "countryActive": False, "mapActive": False,
        "countryCanAName": "BODY", "countryCanBName": "CHASSIS",
        "countryRx238": 12, "countryTxOk": 4, "countryTxFail": 0,
    },
    "/api/continuous-ap/config": {
        "enabled": False, "method": 1, "effectiveEnabled": False, "supported": True,
        "stalkSupported": True, "scrollSingleSupported": True, "scrollDoubleSupported": True,
        "route": "CAN B", "state": "IDLE", "attempts": 0, "txOk": 0, "txFail": 0,
    },
    "/api/lab/driver-window/stats": {
        "ok": True, "supported": True, "available": True, "pending": False,
        "framesSent": 0, "requests": 0, "completed": 0, "txOk": 0, "txFail": 0,
        "blocked": False, "lastResult": "NONE",
    },
    "/api/das/stats": {
        "steeringAngleDeg": 1.2, "handsOnLevel": 0, "apState": 4, "gear": "D",
        "dasStateName": "AP_ACTIVE",
    },
    "/api/nag/stats": {
        "torque": 1.35,
        "apActive": os.environ.get("P4CAN_MOCK_AP_ACTIVE", "1") == "1",
        "handsOnState": 2, "injections": 1203,
    },
    # Mode H 调参（对应 web /api/nag/h-profile/stats）
    "/api/nag/h-profile/stats": {
        "phase": "IDLE", "eventType": "NONE", "activeEventPeakNm": 0.0,
        "outputNm": 0.0, "carrierSampleNm": 0.0, "carrierApplied": False,
        "stopCarrierActive": False,
        "peakMinNm": 1.50, "peakMaxNm": 1.80,
        "waitMinMs": 800, "waitMaxMs": 2000,
        "refractoryMinMs": 500, "refractoryMaxMs": 1500,
        "carrierMinNm": 0.10, "carrierMaxNm": 0.60,
        "hoPolicy": 2, "ho1ThresholdNm": 1.20, "ho2ThresholdNm": 2.00,
        "visualRescueEnabled": False, "visualRescueDelayMs": 0,
    },
    # DMS 捕获（对应 web /api/drivermonitor/stats）
    "/api/drivermonitor/stats": {
        "state": "READY", "segments": 0, "maxSegments": 12,
        "samples": 0, "capacity": 1024, "remainingPostMs": 0,
        "preBuffer": "WARMUP", "lastInteraction": "—",
        "requests": 0, "ignored": 0, "dropped": 0,
        "driverInteraction": "FRONT · NORMAL",
    },
}

# 灯光爆闪（模拟）：契约见 build/灯光补丁说明
LIGHT_STROBE = {
    "supported": True, "active": False, "pattern": "alternate",
    "hz": 4, "durationMs": 5000, "remainingMs": 0,
    "txOk": 0, "txFail": 0, "blocked": False, "blockReason": "",
}
STATS["/api/lights/strobe"] = LIGHT_STROBE

WIFI = {
    "ok": True, "ssid": "P4-CAN-2F9A", "passwordIsDefault": True,
    "ip": "192.168.4.1", "networkState": "AP_READY",
    "hostedWifiStarted": True, "bleStartupAllowed": True,
}
OTA = {"ok": True, "inProgress": False, "error": False, "stage": "idle",
       "updateError": "", "attempt": 0, "receivedBytes": 0, "totalBytes": 0}



# ---------- 写入模拟（键名与 web_api.h 的 arg() 完全一致） ----------

ULC = STATS["/api/ulc/stats"]
R79 = STATS["/api/r79/stats"]
R79AP = STATS["/api/r79/ap-control/stats"]
BLINK = STATS["/api/blinkA/stats"]
SUMMON = STATS["/api/summon/stats"]
VISION = STATS["/api/vision-control/stats"]
PEDAL = STATS["/api/pedalmap/stats"]
HB = STATS["/api/lab/summon-heartbeat/stats"]
RESEARCH = STATS["/api/researchcapture/stats"]
COUNTRY = STATS["/api/country/stats"]
CAP = STATS["/api/continuous-ap/config"]
DMS = STATS["/api/driver-monitoring/config"]
ISA = STATS["/api/isa-suppression/config"]

HEADLIGHT = {
    "count": 10, "intervalMs": 100, "trigger": 0, "holdEnabled": True, "holdDelayMs": 2500,
    "active": False, "started": 0.0, "state": "IDLE", "blockReason": "",
    "txOk": 0, "txFail": 0,
}

def headlight_json():
    hl = HEADLIGHT
    if hl["active"]:
        half = max(0.05, hl["intervalMs"] / 1000.0)
        total_s = hl["count"] * 2 * half
        elapsed = max(0.0, time.time() - hl["started"])
        if elapsed >= total_s:
            hl["active"] = False
            hl["state"] = "COMPLETE"
            hl["blockReason"] = "COMPLETE"
        else:
            hl["state"] = "ACTIVE"
    done = hl["count"] if hl["state"] == "COMPLETE" else (
        min(hl["count"], int(max(0.0, time.time() - hl["started"]) / (2 * max(0.05, hl["intervalMs"] / 1000.0))))
        if hl["active"] else 0
    )
    return {
        "ok": True, "count": hl["count"], "intervalMs": hl["intervalMs"],
        "trigger": hl["trigger"], "triggerName": "S3XY" if hl["trigger"] == 1 else "APP",
        "holdEnabled": bool(hl.get("holdEnabled", True)),
        "holdDelayMs": int(hl.get("holdDelayMs", 2500)),
        "supported": True, "stalkVariant": "STALK",
        "active": hl["active"], "state": hl["state"],
        "flashesDone": done, "flashesTotal": hl["count"],
        "blockReason": hl["blockReason"], "txOk": hl["txOk"], "txFail": hl["txFail"],
    }


def _bool(raw):
    return raw in ("1", "true", "True")


def apply_post(path, qs):
    """返回 None=成功；返回字符串=按固件风格回 400 + error。"""
    def has(k):
        return k in qs

    def val(k):
        return qs[k][0]

    if path == "/api/ulc/update":
        if has("confirm"):
            ULC["stalkConfirmEnabled"] = _bool(val("confirm"))
        if has("timing"):
            ULC["stalkConfirmTimingMode"] = int(val("timing"))
        if has("alcOff"):
            ULC["alcMode"] = 2 if _bool(val("alcOff")) else 0
        if has("blind"):
            raw = val("blind")
            ULC["ulcBlindMode"] = 255 if raw == "stock" else int(raw)
        if has("ulcOff"):
            raw = val("ulcOff")
            ULC["ulcOffHighwayMode"] = 255 if raw == "stock" else int(raw)
        return None

    if path == "/api/lab/auto-lane-change/update":
        if has("enabled"):
            ULC["autoLaneChangeEnabled"] = _bool(val("enabled"))
        if has("bus"):
            ULC["autoLaneChangeTargetBus"] = int(val("bus"))
        return None

    if path == "/api/r79/update":
        for arg, key in (("mode", "mode"), ("mode1TxWaitMode", "mode1TxWaitMode"),
                         ("mode1Reinject", "mode1ReinjectEnabled"),
                         ("mode2Reinject", "mode2ReinjectEnabled"),
                         ("mode1DelayMs", "mode1DelayMs"), ("mode2DelayMs", "mode2DelayMs"),
                         ("bit18Mode", "bit18Mode"), ("hw3Enabled", "hw3Enabled")):
            if has(arg):
                R79[key] = _bool(val(arg)) if arg.endswith("Reinject") else int(val(arg))
        return None

    if path == "/api/r79/ap-control/update":
        for k in ("enabled", "mode", "delaySeconds", "allowManualDriving"):
            if not has(k):
                return "missing-ap-control-setting"
        R79AP["enabled"] = _bool(val("enabled"))
        R79AP["mode"] = int(val("mode"))
        R79AP["delaySeconds"] = int(val("delaySeconds"))
        R79AP["allowManualDriving"] = _bool(val("allowManualDriving"))
        return None

    if path == "/api/blinkA/delay":
        BLINK["delayMs"] = int(val("ms")) if has("ms") else 0
        return None

    if path == "/api/blinkA/timing":
        if has("noaStabilizationSeconds"):
            BLINK["noaStabilizationSeconds"] = int(val("noaStabilizationSeconds"))
        if has("cancelPauseSeconds"):
            BLINK["cancelPauseSeconds"] = int(val("cancelPauseSeconds"))
        return None

    if path == "/api/blinkA/tx-mode":
        BLINK["txMode"] = int(val("mode"))
        return None

    if path == "/api/summon/tlssc-highway-gate":
        SUMMON["tlsscHighwayGateEnabled"] = _bool(val("enabled"))
        return None

    if path == "/api/summon/tlssc-noa-block":
        SUMMON["tlsscBlockInNoa"] = _bool(val("enabled"))
        return None

    if path == "/api/features/lab":
        FEATURES["lab"] = _bool(val("enabled"))
        return None

    if path == "/api/features/door-cancel":
        FEATURES["doorCancel"] = _bool(val("enabled"))
        return None

    if path == "/api/features/s3xy":
        FEATURES["s3xy"] = _bool(val("enabled"))
        return None

    if path == "/api/features/banned":
        FEATURES["banned"] = _bool(val("enabled"))
        return None

    if path == "/api/features/tlssc-restore":
        FEATURES["tlsscRestore"] = _bool(val("enabled"))
        return None

    if path == "/api/features/ap-drive-profile":
        if has("enabled"):
            FEATURES["apDriveProfile"] = _bool(val("enabled"))
            PEDAL["apDriveProfileEnabled"] = _bool(val("enabled"))
        if has("regen"):
            raw = val("regen").upper()
            PEDAL["apDriveProfileRegenName"] = raw
            PEDAL["apDriveProfileRegenRaw"] = {"STANDARD": 20, "REDUCED": 10, "MINIMAL": 1}.get(raw, 20)
        return None

    if path == "/api/vision-control/update":
        if has("disabled"):
            VISION["requestDisabled"] = _bool(val("disabled"))
        if has("bus"):
            VISION["bus"] = int(val("bus"))
        return None

    if path == "/api/continuous-ap/config":
        if not (has("enabled") and has("method")):
            return "invalid enabled or method"
        CAP["enabled"] = _bool(val("enabled"))
        CAP["method"] = int(val("method"))
        CAP["effectiveEnabled"] = CAP["enabled"]
        return None

    if path == "/api/pedalmap/set":
        name = val("mode").upper()
        if name not in ("STOCK", "CHILL", "SPORT", "PERFORMANCE"):
            return "invalid mode"
        PEDAL["targetName"] = name
        PEDAL["overrideActive"] = name != "STOCK"
        return None

    if path == "/api/lab/summon-heartbeat/update":
        if not (has("enabled") and has("value")):
            return "enabled and value required"
        HB["enabled"] = _bool(val("enabled"))
        HB["selectedValue"] = int(val("value"))
        return None

    if path == "/api/researchcapture/mode":
        RESEARCH["captureMode"] = val("mode")
        return None

    if path == "/api/researchcapture/config":
        if not (has("preMs") and has("postMs")):
            return "preMs and postMs are required"
        RESEARCH["preMs"] = int(val("preMs"))
        RESEARCH["postMs"] = int(val("postMs"))
        return None

    if path == "/api/country/update":
        if has("countryMode"):
            COUNTRY["countryMode"] = int(val("countryMode"))
        if has("mapMode"):
            COUNTRY["mapMode"] = int(val("mapMode"))
        return None

    if path == "/api/driver-monitoring/config":
        if len(qs) != 1 or not has("enabled"):
            return "invalid enabled"
        DMS["enabled"] = _bool(val("enabled"))
        DMS["active"] = DMS["enabled"]
        return None

    if path == "/api/isa-suppression/config":
        if len(qs) != 1 or not has("enabled"):
            return "invalid enabled"
        ISA["enabled"] = _bool(val("enabled"))
        ISA["active"] = ISA["enabled"]
        return None

    if path == "/api/lights/strobe":
        if has("hz"):
            LIGHT_STROBE["hz"] = max(1, min(8, int(val("hz"))))
        if has("durationMs"):
            LIGHT_STROBE["durationMs"] = max(500, min(10000, int(val("durationMs"))))
        if has("pattern"):
            LIGHT_STROBE["pattern"] = val("pattern")
        if has("enabled"):
            on = _bool(val("enabled"))
            LIGHT_STROBE["active"] = on
            LIGHT_STROBE["remainingMs"] = LIGHT_STROBE["durationMs"] if on else 0
            if on:
                LIGHT_STROBE["txOk"] += LIGHT_STROBE["hz"] * 2
        return None

    if path == "/api/nag/update":
        for k in ("enabled", "ignoreApState", "pauseAtZeroSpeed", "torqueRightScrollEnabled",
                  "tsl9RightPeriodicEnabled"):
            if has(k):
                NAG_CONFIG[k] = _bool(val(k))
        for k in ("method", "tsl9Sequence", "tsl9InputMode", "tsl9LegacyRoute",
                  "torqueRightScrollIntervalSeconds", "tsl9RightPeriodicIntervalSeconds",
                  "modeHStopBehavior"):
            if has(k):
                NAG_CONFIG[k] = int(val(k))
        if has("modeHStopBehavior"):
            NAG_CONFIG["modeHStopBehaviorName"] = (
                "STOCK CARRIER" if int(val("modeHStopBehavior")) == 1 else "HARD PAUSE")
        for k in ("hoRatePct", "burstMs", "pauseMs"):
            if has(k):
                NAG_CONFIG[k] = int(val(k))
        for k in ("targetId", "apStateId", "steeringId"):
            if has(k):
                NAG_CONFIG[k] = int(val(k), 0)
        return None

    if path == "/api/nag/h-profile/update":
        hp = STATS["/api/nag/h-profile/stats"]
        for k in ("peakMinNm", "peakMaxNm", "carrierMinNm", "carrierMaxNm",
                  "ho1ThresholdNm", "ho2ThresholdNm"):
            if has(k):
                hp[k] = float(val(k))
        for k in ("waitMinMs", "waitMaxMs", "refractoryMinMs", "refractoryMaxMs",
                  "visualRescueDelayMs", "hoPolicy"):
            if has(k):
                hp[k] = int(val(k))
        if has("visualRescueEnabled"):
            hp["visualRescueEnabled"] = _bool(val("visualRescueEnabled"))
        NAG_CONFIG["humanPeakMinNm"] = hp["peakMinNm"]
        NAG_CONFIG["humanPeakMaxNm"] = hp["peakMaxNm"]
        NAG_CONFIG["hoPolicy"] = hp["hoPolicy"]
        return None

    if path == "/api/nag/h-profile/reset":
        hp = STATS["/api/nag/h-profile/stats"]
        hp.update({
            "peakMinNm": 1.50, "peakMaxNm": 1.80,
            "waitMinMs": 800, "waitMaxMs": 2000,
            "refractoryMinMs": 500, "refractoryMaxMs": 1500,
            "carrierMinNm": 0.10, "carrierMaxNm": 0.60,
            "hoPolicy": 2, "ho1ThresholdNm": 1.20, "ho2ThresholdNm": 2.00,
            "visualRescueEnabled": False, "visualRescueDelayMs": 0,
        })
        return None

    if path == "/api/researchcapture/labels":
        if not has("slot") or not has("label"):
            return "slot and label are required"
        slot = val("slot").upper()
        label = val("label")
        if slot not in ("A", "B", "C", "D") or not (1 <= len(label.encode("utf-8")) <= 63):
            return "label must be 1-63 UTF-8 bytes"
        RESEARCH["labels"][slot] = label
        return None

    if path == "/api/headlight-strobe/config":
        if HEADLIGHT["active"]:
            return "ALREADY_ACTIVE"
        try:
            count = int(val("count")) if has("count") else HEADLIGHT["count"]
            interval = int(val("intervalMs")) if has("intervalMs") else HEADLIGHT["intervalMs"]
            trigger = int(val("trigger")) if has("trigger") else HEADLIGHT["trigger"]
        except ValueError:
            return "invalid number"
        if not (1 <= count <= 30):
            return "count must be 1..30"
        if not (50 <= interval <= 1000):
            return "intervalMs must be 50..1000"
        if trigger not in (0, 1):
            return "trigger must be 0 or 1"
        hold = HEADLIGHT.get("holdEnabled", True)
        if has("holdEnabled"):
            hold = val("holdEnabled") == "1"
        HEADLIGHT.update(count=count, intervalMs=interval, trigger=trigger,
                         holdEnabled=hold, state="IDLE", blockReason="", txOk=0, txFail=0)
        return None

    if path == "/api/headlight-strobe/trigger":
        if HEADLIGHT["active"]:
            return "ALREADY_ACTIVE"
        if HEADLIGHT["trigger"] != 0:
            return "SOURCE_MISMATCH"
        HEADLIGHT.update(active=True, started=time.time(), state="ACTIVE",
                         blockReason="", txOk=0, txFail=0)
        return None

    if path == "/api/headlight-strobe/stop":
        if HEADLIGHT["active"]:
            HEADLIGHT.update(active=False, state="STOPPED", blockReason="USER_STOP")
        return None

    if path == "/api/profile/select":
        names = {1: "Model Y L", 2: "Model Y Juniper", 3: "Model Y Legacy",
                 4: "Model 3 Highland", 5: "Model 3 Legacy"}
        pid = int(val("profile")) if has("profile") else 0
        if pid not in names:
            return "invalid profile"
        topo = int(val("topology")) if has("topology") else (1 if pid == 1 else 2)
        turn = int(val("turn")) if has("turn") else 1
        PROFILE["profile"] = pid
        PROFILE["profileName"] = names[pid]
        PROFILE["topology"] = topo
        PROFILE["topologyName"] = "Party + VH" if topo == 1 else "BODY + CHASSIS + PARTY"
        PROFILE["canA"] = "PARTY" if topo == 1 else "BODY"
        PROFILE["canB"] = "VH" if topo == 1 else "CHASSIS"
        PROFILE["turn"] = turn
        PROFILE["turnName"] = "STALKLESS" if turn == 2 else "STALK"
        return None

    if path == "/api/drivermonitor/start":
        dm = STATS["/api/drivermonitor/stats"]
        slot = val("slot") if has("slot") else "A"
        dm["state"] = "CAPTURING"
        dm["segments"] = min(dm["maxSegments"], dm["segments"] + 1)
        dm["requests"] = dm["requests"] + 1
        dm["driverInteraction"] = f"SLOT {slot} · CAPTURING"
        return None

    if path == "/api/drivermonitor/reset":
        dm = STATS["/api/drivermonitor/stats"]
        dm.update({"state": "READY", "segments": 0, "samples": 0,
                   "requests": 0, "driverInteraction": "FRONT · NORMAL"})
        return None

    return None


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        print(f"[{self.command}] {self.path}", flush=True)

    def send_json(self, obj, status=200):
        body = j(obj).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        parsed = urlparse(self.path)
        path, qs = parsed.path, parse_qs(parsed.query)

        if path in ("/api/headlight-strobe/config", "/api/headlight-strobe/stats"):
            return self.send_json(headlight_json())

        if path == "/api/snapshot":
            groups = qs.get("groups", ["home"])[0]
            if groups == "home-fast":
                payload = {"fast": snapshot_fast()}
                if qs.get("slow", ["0"])[0] == "1":
                    payload["slow"] = snapshot_slow()
                return self.send_json(payload)
            return self.send_json({"fast": snapshot_fast(), "slow": snapshot_slow()})

        table = {
            "/api/profile/status": PROFILE,
            "/api/features/status": FEATURES,
            "/api/nag/config": NAG_CONFIG,
            "/api/s3xy/stats": S3XY,
            "/api/system/stats": SYSTEM,
            "/api/wifi/status": WIFI,
            "/api/ota/status": OTA,
        }
        if path in table:
            return self.send_json(table[path])
        if path == "/api/lab/auto-lane-change/stats":
            return self.send_json(STATS["/api/ulc/stats"])
        if path in STATS:
            return self.send_json(STATS[path])
        if path.endswith(".csv"):
            body = b"segment,label\n1,A\n"
            self.send_response(200)
            self.send_header("Content-Type", "text/csv")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        return self.send_json({"ok": True})

    def do_POST(self):
        parsed = urlparse(self.path)
        path, qs = parsed.path, parse_qs(parsed.query)
        with LOCK:
            error = apply_post(path, qs)
        if error:
            return self.send_json({"ok": False, "error": error}, status=400)
        if path.startswith("/api/headlight-strobe/"):
            return self.send_json(headlight_json())
        return self.send_json({"ok": True})


if __name__ == "__main__":
    import os
    import sys
    port = int(os.environ.get("P4CAN_MOCK_PORT", sys.argv[1] if len(sys.argv) > 1 else 8080))
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print(f"P4-CAN mock listening on http://127.0.0.1:{port}")
    server.serve_forever()
