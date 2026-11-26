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

# 固件代次模拟：P4CAN_MOCK_FW=3.35.2 时移除爆闪与封禁/TLSSC 恢复端点，
# 用于验证 App 在官方新版固件上的兼容降级。
FW_VARIANT = os.environ.get("P4CAN_MOCK_FW", "3.29.3")
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


# P4CAN_MOCK_GEAR_CYCLE=<秒>：挡位按 P → D → N → R 循环切换，用于验证状态页车辆视角随挡位变化
GEAR_CYCLE = float(os.environ.get("P4CAN_MOCK_GEAR_CYCLE", "0"))
START_TIME = time.time()


def mock_gear():
    if GEAR_CYCLE <= 0:
        return "D"
    return ["P", "D", "N", "R"][int(time.time() / GEAR_CYCLE) % 4]


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
            # 收帧计数随时间增长（约 1.8k / 1.1k / 0.4k 帧每秒），用于验证实时活动里的帧率
            "can1RxCount": 128934 + int((time.time() - START_TIME) * 1800),
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
            "can2RxCount": 88210 + int((time.time() - START_TIME) * 1100),
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
            "can3RxCount": 33210 + (int((time.time() - START_TIME) * 400) if STATE["can_alive"] else 0),
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
            "gearName": mock_gear(),
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
    "profile": 2,
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

PREHEAT = {
    "supported": True, "enabled": False, "targetC": 40.0, "active": False,
    "batteryWarm": False, "targetReached": False, "packSeen": True,
    "packTempMinC": 18.5, "packTempMaxC": 20.1, "packTempAvgC": 19.3,
    "bmsSeen": True, "bmsPreconditionAllowed": True, "bmsHeatingWorthwhile": True,
    "heatingActive": False, "txOk": 0, "txFail": 0, "tripId": "0x347",
    "evalAgeMs": 120, "autoOffReason": "NONE", "blocked": False,
    # 以下字段与固件 preheatStatsToJson 一致（v3.35.3）
    "bmsKeepWarmRequest": False, "coolantSeen": True, "coolantFlowLpm": 8.4,
    "statorFrontSeen": True, "statorFrontAgeMs": 90, "statorHeatFrontKw": 1.25,
    "statorRearSeen": True, "statorRearAgeMs": 90, "statorHeatRearKw": 2.10, "statorHeatKw": 3.35,
    "ptMaxPackSeen": True, "ptMaxPackAgeMs": 400, "ptMaxPackC": 20.4,
    "ptFlowReqSeen": True, "ptFlowReqAgeMs": 400, "ptFlowReqLpm": 7.5,
    "ptCellTargetSeen": True, "ptCellTargetAgeMs": 400, "ptCellTargetC": 25.0,
    "ptHpPowerSeen": True, "ptHpPowerAgeMs": 400, "ptHpPowerW": 1850,
    "ptAmbientSeen": True, "ptAmbientAgeMs": 900, "ptAmbientC": 2.5,
    "ptHeatLimitSeen": True, "ptHeatLimitAgeMs": 400, "ptHeatLimitKw": 7.00,
    "replyTx": 0, "replyFail": 0, "replyLatLastMs": 0, "replyLatMaxMs": 0,
    "heatDrops": 0, "heatDropsNearCar": 0, "autoOffCount": 1, "lastSkipReason": "DISABLED",
    "thVitalsAgeMs": 120, "thPumpBatRpm": 2100, "thPumpPtRpm": 1800, "thFanRpm": 0,
    "thModeAgeMs": 120, "thValveMode": 0, "thHpReq": 2, "thSysAgeMs": 800, "thHeatPump": True,
    "thInletsAgeMs": 120, "thBatInletC": 21.2, "thPtInletC": 34.6,
    "thFlowsAgeMs": 120, "thFlowBatLpm": 8.4, "thFlowPtLpm": 6.1,
    "thPcsAgeMs": 2000, "thDcdcC": 31.0, "thChargerC": 18.0,
    "thInvFrontAgeMs": 2000, "thInvFrontC": 27.0, "thInvRearAgeMs": 2000, "thInvRearC": 33.0,
    "thApAgeMs": 4000, "thApC": 42.0, "thInfoAgeMs": 4294967295, "thInfoC": 0.0,
}
FSD = {"enabled": False, "suspendDuringAp": True, "values": 0,
       "mux0Fresh": True, "stock1": "0x00", "txOk": 0, "txFail": 0, "apBlocked": False}
SERVICE = {"canEnter": True, "chinaRestore": True, "restoreTxOk": 12, "restoreTxFail": 0,
           "restoreForce": False, "restoreIntervalMs": 150,
           "cacheValid": True, "cacheLen": 8, "cacheHex": "1B0A2F0000000000",
           "persisted": True, "replayOk": 42, "replayFail": 0, "replayBusy": 1,
           "replaySkip": 0, "burst": 42, "lastErr": 0, "lastErrName": "OK",
           "windowExpired": True,
           "eapNr": {"enabled": True, "prereq": False, "cacheValid": True,
                     "cacheHex": "1B0000000000", "stockRx": 12, "replayOk": 0,
                     "replayFail": 0, "replayBusy": 0, "burst": 0}}
SMARTSHIFT = {
    "profileSupported": True, "executionEnabled": False, "protocol": "AUTO",
    "state": "IDLE", "target": "NONE", "source": "NONE", "reason": "NONE",
    "config": {"requireSeatbelt": True, "steeringFallback": False,
               "parkSteeringFallback": False, "requireSteering": True,
               "maxSpeedKph": 8, "hardCutSpeedKph": 12, "cooldownMs": 1500,
               "obstacleThresholdCm": 120, "parkConfirmDeg": 90,
               "driveReverseConfirmDeg": 90, "obstacleConfirmDeg": 90, "speedBus": 2},
    "engine": {"sends": 0, "confirmations": 0, "failures": 0},
    "templates": {"v12": {"ready": True}, "v13V14": {"ready": False}},
}
DEVTEST = {"enabled": False, "values": 0, "stock0": 0, "stock1": 1,
           "stock2": 0, "stock3": 1, "stock4": 0, "stock5": 1}
LANGUAGE = {"language": "zh-CN"}
SUMMON_VERSION = {"enabled": False, "value": 1, "stock": 1, "gateAllowed": True}
LIGHTING = {"ok": True, "highBeamStrobe": False, "rearFogStrobe": False,
            "highBeamStrobeRunning": False, "rearFogStrobeRunning": False,
            "apForcedHighBeam": False, "dynamicBrakeMode": 0,
            "running": False, "apActive": False, "stalkSupported": True,
            "txOk": 0, "txFail": 0}
CAN_GPIO = {
    "ok": True, "valid": True,
    "active": [{"tx": 4, "rx": 5}, {"tx": 2, "rx": 3}, {"tx": 26, "rx": 27}],
    "saved": [{"tx": 4, "rx": 5}, {"tx": 2, "rx": 3}, {"tx": 26, "rx": 27}],
    "defaults": [{"tx": 20, "rx": 21}, {"tx": 22, "rx": 23}, {"tx": 26, "rx": 27}],
    "allowedPins": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19,
                    20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36,
                    37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54],
    "rebootRequired": False, "canStopped": False, "error": "",
}
R79_TIMING = {"active": False, "allocationFailed": False, "expired": False,
              "session": None, "count": 0, "capacity": 32768, "dropped": 0,
              "elapsedMs": 0, "exporting": False, "driverErrorLost": 0,
              "driverSnapshotFailures": 0}

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
    "preheatSupported": True,
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
    "fwVersion": f"v{FW_VARIANT} (mock)",
    "canHarness": "X179",
    "canPins": "4/5, 2/3, 26/27",
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
        "gearSourceName": "CHASSIS", "gearName": mock_gear(),
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
        "blockTxInPark": False,
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
        "state": "READY", "captureMode": "SNAPSHOT", "capturing": False, "exporting": False,
        "preMs": 5000, "postMs": 5000, "preWindowMs": 5000, "postWindowMs": 5000,
        "samples": 0, "capacity": 20000, "requests": 0, "dropped": 0,
        "segments": 0, "completedSegments": 0, "maxSegments": 8, "fullReason": "",
        "preSnapshotsReady": 3, "preSnapshotSlots": 3,
        "currentSlot": 0,
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
        "state": "READY", "capturing": False, "exporting": False, "supported": True,
        "segments": 0, "maxSegments": 12, "remainingMs": 0,
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
OTA_DOWN_UNTIL = [0.0]  # 模拟设备重启：这段时间内所有请求直接断开
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
    # 与固件 HeadlightStrobeConfig 对齐：0=按次数；durationMs>0 固定总时长；
    # stopMode=1 只能手动停（实际运行上限 maxRunMs）。
    "durationMs": 0, "stopMode": 0, "maxRunMs": 30000,
    "active": False, "started": 0.0, "state": "IDLE", "blockReason": "",
    "txOk": 0, "txFail": 0,
}

REAR_FOG = {"active": False, "started": 0.0, "templateValid": True, "stockFogOn": False,
            "txOk": 0, "txFail": 0, "pulses": 0, "stopReason": "NONE"}

def rear_fog_json():
    rf = REAR_FOG
    now = time.time()
    if rf["active"]:
        elapsed_ms = int((now - rf["started"]) * 1000)
        if elapsed_ms >= 30000:
            rf["active"] = False
            rf["stopReason"] = "TIMEOUT"
        else:
            rf["pulses"] = max(1, elapsed_ms // 100)
            rf["txOk"] = rf["pulses"] * 2
    remaining = 0
    if rf["active"]:
        remaining = max(0, 30000 - int((now - rf["started"]) * 1000))
    return {
        "ok": True, "active": rf["active"], "remainingMs": remaining, "totalMs": 30000,
        "intervalMs": HEADLIGHT["intervalMs"], "phaseOn": bool(rf["pulses"] % 2),
        "pulses": rf["pulses"], "txOk": rf["txOk"], "txFail": rf["txFail"],
        "stockFogOn": rf["stockFogOn"], "templateValid": rf["templateValid"],
        "frameAgeMs": 12, "setupMode": False, "stopReason": rf["stopReason"],
    }

def hl_mode(hl):
    if hl["stopMode"] == 1:
        return "MANUAL"
    return "DURATION" if hl["durationMs"] > 0 else "COUNT"


def hl_total_s(hl):
    if hl["stopMode"] == 1:
        return max(0.5, hl["maxRunMs"] / 1000.0)
    if hl["durationMs"] > 0:
        return hl["durationMs"] / 1000.0
    return hl["count"] * 2 * max(0.05, hl["intervalMs"] / 1000.0)


def headlight_json():
    hl = HEADLIGHT
    total_s = hl_total_s(hl)
    elapsed = 0.0
    if hl["active"]:
        elapsed = max(0.0, time.time() - hl["started"])
        if elapsed >= total_s:
            hl["active"] = False
            hl["state"] = "COMPLETE"
            hl["blockReason"] = "COMPLETE"
        else:
            hl["state"] = "ACTIVE"
    half = max(0.05, hl["intervalMs"] / 1000.0)
    done = hl["count"] if hl["state"] == "COMPLETE" else (
        min(hl["count"], int(elapsed / (2 * half))) if hl["active"] else 0
    )
    return {
        "ok": True, "count": hl["count"], "intervalMs": hl["intervalMs"],
        "trigger": hl["trigger"], "triggerName": "S3XY" if hl["trigger"] == 1 else "APP",
        "durationMs": hl["durationMs"], "stopMode": hl["stopMode"],
        "maxRunMs": hl["maxRunMs"], "mode": hl_mode(hl),
        "totalMs": int(total_s * 1000),
        "elapsedMs": int(elapsed * 1000) if hl["active"] else 0,
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

    if path == "/api/developer-test/update":
        if has("enabled"):
            DEVTEST["enabled"] = _bool(val("enabled"))
        if has("values"):
            DEVTEST["values"] = int(val("values"))
        return None
    if path == "/api/dashboard/language":
        if has("language"):
            LANGUAGE["language"] = val("language")
        return None
    if path == "/api/summon-version/update":
        if has("enabled"):
            SUMMON_VERSION["enabled"] = _bool(val("enabled"))
        if has("value"):
            SUMMON_VERSION["value"] = int(val("value"))
        return None
    if path == "/api/service-mode/eapnr":
        if has("enabled"):
            SERVICE["eapNr"]["enabled"] = _bool(val("enabled"))
        return None
    if path == "/api/service-mode/force":
        if has("enabled"):
            SERVICE["restoreForce"] = _bool(val("enabled"))
        if has("intervalMs"):
            SERVICE["restoreIntervalMs"] = int(val("intervalMs"))
        return None
    if path == "/api/lighting/update":
        if has("apForcedHighBeam"):
            LIGHTING["apForcedHighBeam"] = _bool(val("apForcedHighBeam"))
        if has("dynamicBrakeMode"):
            LIGHTING["dynamicBrakeMode"] = int(val("dynamicBrakeMode"))
        return None
    if path == "/api/system/can-gpio":
        rows = []
        for i in range(3):
            tx = int(val(f"tx{i+1}")); rx = int(val(f"rx{i+1}"))
            rows.append({"tx": tx, "rx": rx})
        CAN_GPIO["saved"] = rows
        return None
    if path == "/api/preheat/set":
        if has("enabled"):
            PREHEAT["enabled"] = _bool(val("enabled"))
        if has("targetC"):
            PREHEAT["targetC"] = float(val("targetC"))
        return None
    if path == "/api/fsd/update":
        if has("enabled"):
            FSD["enabled"] = _bool(val("enabled"))
        if has("values"):
            FSD["values"] = int(val("values"))
        if has("suspendDuringAp"):
            FSD["suspendDuringAp"] = _bool(val("suspendDuringAp"))
        return None
    if path == "/api/service-mode/enter":
        return None
    if path == "/api/service-mode/restore":
        if has("enabled"):
            SERVICE["chinaRestore"] = _bool(val("enabled"))
        return None
    if path == "/api/smartshift/update":
        for key in ("enabled", "requireSeatbelt", "steeringFallback",
                    "parkSteeringFallback", "requireSteering"):
            if has(key):
                if key == "enabled":
                    SMARTSHIFT["executionEnabled"] = _bool(val(key))
                else:
                    SMARTSHIFT["config"][key] = _bool(val(key))
        if has("protocol"):
            SMARTSHIFT["protocol"] = val("protocol")
        if has("speedBus"):
            SMARTSHIFT["config"]["speedBus"] = int(val("speedBus"))
        for key in ("maxSpeedKph", "hardCutSpeedKph", "cooldownMs",
                    "obstacleThresholdCm", "parkConfirmDeg",
                    "driveReverseConfirmDeg", "obstacleConfirmDeg"):
            if has(key):
                SMARTSHIFT["config"][key] = int(val(key))
        return None
    if path == "/api/r79/timing/start":
        R79_TIMING.update(active=True, expired=False, count=0, elapsedMs=0,
                          session={"id": 1})
        return None
    if path == "/api/r79/timing/stop":
        R79_TIMING.update(active=False, session={"id": 1})
        return None
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
        if has("blockTxInPark"):
            R79AP["blockTxInPark"] = _bool(val("blockTxInPark"))
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

    if path == "/api/nag/mode":
        # 固件 httpNagSetMode 读取参数 m（0 / 1 / 3 / 7）
        NAG_CONFIG["mode"] = int(val("m"))
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
            duration = int(val("durationMs")) if has("durationMs") else HEADLIGHT["durationMs"]
            stop_mode = int(val("stopMode")) if has("stopMode") else HEADLIGHT["stopMode"]
            max_run = int(val("maxRunMs")) if has("maxRunMs") else HEADLIGHT["maxRunMs"]
        except ValueError:
            return "invalid number"
        if not (1 <= count <= 30):
            return "count must be 1..30"
        if not (50 <= interval <= 1000):
            return "intervalMs must be 50..1000"
        if trigger not in (0, 1):
            return "trigger must be 0 or 1"
        if duration != 0 and not (100 <= duration <= 30000):
            return "durationMs must be 0 or 100..30000"
        if stop_mode not in (0, 1, 2):
            return "stopMode must be 0..2"
        if not (500 <= max_run <= 60000):
            return "maxRunMs must be 500..60000"
        hold = HEADLIGHT.get("holdEnabled", True)
        if has("holdEnabled"):
            hold = val("holdEnabled") == "1"
        HEADLIGHT.update(count=count, intervalMs=interval, trigger=trigger,
                         durationMs=duration, stopMode=stop_mode, maxRunMs=max_run,
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

    if path == "/api/rear-fog-strobe/start":
        if REAR_FOG["active"]:
            return "ALREADY_ACTIVE"
        if not REAR_FOG["templateValid"]:
            return "NO_FRAME"
        REAR_FOG.update(active=True, started=time.time(), pulses=1, txOk=0, txFail=0,
                        stopReason="NONE", stockFogOn=False)
        return None

    if path == "/api/rear-fog-strobe/stop":
        if REAR_FOG["active"]:
            REAR_FOG.update(active=False, stopReason="USER_STOP")
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


# ── T2CAN 模式：P4CAN_DEVICE=t2can ─────────────────────────────
# T2CAN 只有两路 CAN（MCP2515 + TWAI），状态字段前缀与 P4 不同；
# FSD / Service Mode 在 /api/lab/* 下。
T2_DEVICE = os.environ.get("P4CAN_DEVICE", "p4can") == "t2can"


def t2_cantraffic():
    return {
        "mcpTrafficSeen": True,
        "mcpTrafficOnline": True,
        "mcpTrafficAgeMs": 11,
        "twaiTrafficSeen": True,
        "twaiTrafficOnline": True,
        "twaiTrafficAgeMs": 7,
    }


if T2_DEVICE:
    for _key in [k for k in SYSTEM if k.startswith("can")]:
        SYSTEM.pop(_key, None)
    for _key in ("chipModel", "canHarness", "canPins", "hostedHostVersion",
                 "hostedPinsReady", "canBusCount"):
        SYSTEM.pop(_key, None)
    SYSTEM.update({
        "fwVersion": "v3.30.3 (mock)",
        "mcpReady": True, "mcpState": 0,
        "mcpTrafficSeen": True, "mcpTrafficOnline": True, "mcpTrafficAgeMs": 11,
        "mcpTxOk": 320, "mcpTxFail": 2, "mcpBusOffCount": 0,
        "canARxFramesProcessed": 98211, "mcpRxOverflowCount": 0,
        "mcpErrorFlags": 0, "mcpTxFailConsecutive": 0,
        "twaiReady": True, "twaiState": 1, "twaiStateName": "RUNNING",
        "twaiTrafficSeen": True, "twaiTrafficOnline": True, "twaiTrafficAgeMs": 7,
        "twaiTxFailedCount": 4, "twaiBusOffCount": 0,
        "twaiRxMissedCount": 0, "twaiRxOverrunCount": 0,
        "twaiTxErrorCounter": 0, "twaiRxErrorCounter": 0,
    })
    PROFILE.update({
        "profile": 2,
        "profileName": "Model Y Juniper (T2)",
        "topology": 2,
        "topologyName": "BODY + CHASSIS",
        "canA": "BODY",
        "canB": "CHASSIS",
    })
    PROFILE.pop("canExtra", None)

    STATS["/api/lab/fsd/stats"] = {
        "ok": True, "supported": True, "labEnabled": True,
        "pauseOnAp": False, "apBlocked": False,
        "enableEcho": False, "enableValue": 0, "enableOriginal": 0,
        "enableAgeMs": 120, "enableRx": 18, "enableTxOk": 0, "enableTxFail": 0,
        "profileEcho": False, "profileValue": 0, "profileOriginal": 0,
        "profileAgeMs": 120, "profileRx": 9, "profileTxOk": 0, "profileTxFail": 0,
    }
    STATS["/api/lab/service-mode/stats"] = {
        "ok": True, "supported": True, "available": True, "bus": "CAN B",
    }


# ── 车型档案覆盖：P4CAN_PROFILE=yl|yj|y|3h|3|sx ─────────────────
# 用真实档案编号联调首页车型图，避免出现「图是 3、标题还是 Y」的假象。
PROFILE_PRESETS = {
    "yl": (1, "Model Y L", 1),
    "yj": (2, "Model Y (Juniper)", 2),
    "y": (3, "Model Y (Legacy)", 2),
    "3h": (4, "Model 3 Highland", 2),
    "3": (5, "Model 3 (Legacy)", 2),
    "sx": (6, "Model S/X MCU2 HW3", 1),
}
_profile_override = os.environ.get("P4CAN_PROFILE", "").lower()
if _profile_override in PROFILE_PRESETS and not T2_DEVICE:
    _pid, _pname, _ptopo = PROFILE_PRESETS[_profile_override]
    PROFILE.update({
        "profile": _pid,
        "profileName": _pname,
        "topology": _ptopo,
        "topologyName": "PARTY + VH" if _ptopo == 1 else "BODY + CHASSIS + PARTY",
        "canA": "PARTY" if _ptopo == 1 else "BODY",
        "canB": "VH" if _ptopo == 1 else "CHASSIS",
    })
    if _ptopo == 1:
        PROFILE.pop("canExtra", None)
    else:
        PROFILE["canExtra"] = "PARTY"

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

    def _rebooting(self):
        if time.time() < OTA_DOWN_UNTIL[0]:
            self.send_json({"ok": False, "error": "rebooting"}, status=503)
            return True
        return False

    def do_GET(self):
        parsed = urlparse(self.path)
        path, qs = parsed.path, parse_qs(parsed.query)
        if self._rebooting():
            return

        if FW_VARIANT.startswith("3.35"):
            if path.startswith(("/api/headlight-strobe/", "/api/rear-fog-strobe/",
                                "/api/features/banned", "/api/features/tlssc-restore")):
                return self.send_json({"ok": False, "error": "not found"}, status=404)
            if FW_VARIANT.startswith(("3.35.7", "3.35.8")):
                if path.startswith(("/api/developer-test/", "/api/summon-version/",
                                    "/api/service-mode/force")):
                    return self.send_json({"ok": False, "error": "not found"}, status=404)
            if path == "/api/features/status":
                return self.send_json({k: v for k, v in FEATURES.items()
                                       if k not in ("banned", "bannedSupported",
                                                    "tlsscRestore", "tlsscRestoreSupported")})

        if path == "/api/preheat/stats":
            return self.send_json(PREHEAT)
        if path == "/api/fsd/stats":
            return self.send_json(FSD)
        if path == "/api/service-mode/stats":
            if FW_VARIANT.startswith(("3.35.7", "3.35.8")):
                return self.send_json({k: v for k, v in SERVICE.items()
                                       if k not in ("restoreForce", "restoreIntervalMs", "eapNr")})
            return self.send_json({k: v for k, v in SERVICE.items()
                                   if k not in ("cacheValid", "cacheLen", "cacheHex", "persisted",
                                                "replayOk", "replayFail", "replayBusy", "replaySkip",
                                                "burst", "lastErr", "lastErrName", "windowExpired")})
        if path == "/api/smartshift/stats":
            return self.send_json(SMARTSHIFT)
        if path == "/api/developer-test/stats":
            return self.send_json(DEVTEST)
        if path == "/api/dashboard/language":
            return self.send_json(LANGUAGE)
        if path == "/api/summon-version/stats":
            return self.send_json(SUMMON_VERSION)
        if path == "/api/lighting/stats":
            if FW_VARIANT.startswith("3.35.2") and not FW_VARIANT.startswith("3.35.3"):
                return self.send_json({"ok": False, "error": "not found"}, status=404)
            return self.send_json(LIGHTING)
        if path == "/api/system/can-gpio":
            return self.send_json(CAN_GPIO)
        if path == "/api/r79/timing/status":
            return self.send_json(R79_TIMING)
        if path == "/api/r79/timing/csv":
            body = b"seq,relative_ms,result\n"
            self.send_response(200)
            self.send_header("Content-Type", "text/csv")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if path == "/api/system/can-errors.json":
            # 与固件 canDiagJsonSerialize 相同的顶层结构（内容精简）
            return self.send_json({
                "schemaVersion": 1, "firmware": SYSTEM.get("fwVersion", "mock"), "bootId": 1,
                "captureBeginUs": "0", "capturedUs": "1000000", "consistent": True,
                "buses": [{"bus": i, "busErrors": 0, "controllerEpoch": 1} for i in range(3)],
                "driverErrorCapture": {"count": 0}, "reinitializations": [],
            })
        if path in ("/api/headlight-strobe/config", "/api/headlight-strobe/stats"):
            return self.send_json(headlight_json())
        if path == "/api/rear-fog-strobe/stats":
            return self.send_json(rear_fog_json())

        if path == "/api/snapshot":
            groups = qs.get("groups", ["home"])[0]
            if groups == "home-fast":
                payload = {"fast": snapshot_fast()}
                if qs.get("slow", ["0"])[0] == "1":
                    payload["slow"] = snapshot_slow()
                if T2_DEVICE:
                    payload["fast"]["cantraffic"] = t2_cantraffic()
                    payload["fast"].pop("lab3f8", None)
                return self.send_json(payload)
            payload = {"fast": snapshot_fast(), "slow": snapshot_slow()}
            if T2_DEVICE:
                payload["fast"]["cantraffic"] = t2_cantraffic()
                payload["fast"].pop("lab3f8", None)
            return self.send_json(payload)

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
            if path == "/api/r79/ap-control/stats" and not FW_VARIANT.startswith("3.35.8"):
                return self.send_json({k: v for k, v in STATS[path].items()
                                       if k != "blockTxInPark"})
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
        if self._rebooting():
            return
        if FW_VARIANT.startswith("3.35") and path.startswith(
                ("/api/headlight-strobe/", "/api/rear-fog-strobe/",
                 "/api/features/banned", "/api/features/tlssc-restore")):
            return self.send_json({"ok": False, "error": "not found"}, status=404)
        # OTA 上传（与固件 server.on("/update", HTTP_POST, ...) 对齐）：
        # 按 Content-Length 读满 multipart，取 part 头之后的净载荷长度当写入量。
        if T2_DEVICE and path == "/api/lab/fsd/update":
            field = (qs.get("field") or [""])[0]
            enabled = (qs.get("enabled") or ["0"])[0] in ("1", "true", "True")
            fsd = STATS["/api/lab/fsd/stats"]
            if field == "enable":
                fsd["enableEcho"] = enabled
                fsd["enableTxOk"] = fsd.get("enableTxOk", 0) + (1 if enabled else 0)
            elif field == "profile":
                fsd["profileEcho"] = enabled
                fsd["profileValue"] = 2 if enabled else 0
                fsd["profileTxOk"] = fsd.get("profileTxOk", 0) + (1 if enabled else 0)
            elif field == "pauseOnAp":
                fsd["pauseOnAp"] = enabled
            return self.send_json(fsd)
        if T2_DEVICE and path == "/api/lab/service-mode/send":
            return self.send_json({"ok": True, "sent": True})
        if path == "/update":
            length = int(self.headers.get("Content-Length", 0) or 0)
            body = self.rfile.read(length) if length else b""
            payload = b""
            if b"\r\n\r\n" in body:
                payload = body.split(b"\r\n\r\n", 1)[1].rsplit(b"\r\n--", 1)[0]
            with LOCK:
                OTA.update(ok=True, inProgress=False, error=False, stage="complete",
                           attempt=OTA["attempt"] + 1,
                           receivedBytes=len(payload), totalBytes=len(payload))
                print(f"[OTA] received {len(payload)} bytes (content-length {length})")
            mode = os.environ.get("P4CAN_MOCK_OTA_MODE", "")
            if mode == "fail":
                OTA.update(ok=False, inProgress=False, error="Update end failed: no space",
                           stage="end", updateError="No space left", attempt=OTA["attempt"] + 1)
                return self.send_json(OTA)
            if mode == "reboot":
                # 模拟真机：写入成功后 0.7 s 重启，客户端拿不到回包，AP 断链若干秒。
                OTA_DOWN_UNTIL[0] = time.time() + 8
                OTA.update(ok=True, stage="idle", attempt=0, error=False, inProgress=False)
                self.connection.close()
                self.close_connection = True
                print("[OTA] simulated reboot (no response, 8 s gap)")
                return
            self.send_json(OTA)
            # 模拟固件 httpOtaFinish()：回包后 700 ms 就 restart，客户端可能读不到完整响应。
            if os.environ.get("P4CAN_MOCK_OTA_RST") == "1":
                import socket as _socket
                import struct as _struct
                self.connection.setsockopt(
                    _socket.SOL_SOCKET, _socket.SO_LINGER, _struct.pack("ii", 1, 0))
                self.connection.close()
                self.close_connection = True
            return
        with LOCK:
            error = apply_post(path, qs)
        if error:
            return self.send_json({"ok": False, "error": error}, status=400)
        if path.startswith("/api/headlight-strobe/"):
            return self.send_json(headlight_json())
        if path.startswith("/api/rear-fog-strobe/"):
            return self.send_json(rear_fog_json())
        return self.send_json({"ok": True})


if __name__ == "__main__":
    import os
    import sys
    port = int(os.environ.get("P4CAN_MOCK_PORT", sys.argv[1] if len(sys.argv) > 1 else 8080))
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print(f"P4-CAN mock listening on http://127.0.0.1:{port}")
    server.serve_forever()
