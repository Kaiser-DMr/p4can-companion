#!/bin/bash
# 本地模拟器启动脚本（需已安装 iOS 模拟器运行时）
# 用法： ./run_on_simulator.sh [0|1|2|3]
#   0 状态  1 功能  2 蓝牙  3 系统
set -euo pipefail

TAB="${1:-0}"
BUNDLE_ID="com.p4can.companion"
APP_PATH="$(ls -d "$HOME"/Library/Developer/Xcode/DerivedData/P4CANCompanion-*/Build/Products/Debug-iphonesimulator/P4CANCompanion.app 2>/dev/null | head -1)"
MOCK="$(cd "$(dirname "$0")" && pwd)/mock_p4can.py"
SHOT="/tmp/p4can_tab${TAB}_$(date +%H%M%S).png"

if [[ -z "${APP_PATH}" ]]; then
  echo "未找到模拟器构建产物，请先执行："
  echo "  xcodebuild -scheme P4CANCompanion -destination 'generic/platform=iOS Simulator' OTHER_SWIFT_FLAGS='-Xfrontend -disable-sandbox' build"
  exit 1
fi

echo "1) 启动 mock 设备 (127.0.0.1:8080)…"
if ! curl -s --max-time 1 http://127.0.0.1:8080/api/profile/status >/dev/null; then
  python3 "${MOCK}" >/tmp/p4can_mock.log 2>&1 &
  sleep 1
fi

echo "2) 准备模拟器…"
UDID="$(xcrun simctl list devices available | grep -m1 -oE '[0-9A-F-]{36}' || true)"
if [[ -z "${UDID}" ]]; then
  echo "没有可用模拟器设备，请先在 Xcode → Settings → Components 安装 iOS 运行时"
  exit 1
fi
xcrun simctl boot "${UDID}" 2>/dev/null || true
xcrun simctl bootstatus "${UDID}" -b >/dev/null 2>&1 || true

echo "3) 安装并启动（host=127.0.0.1:8080, tab=${TAB}）…"
xcrun simctl install "${UDID}" "${APP_PATH}"
SIMCTL_CHILD_P4CAN_HOST=127.0.0.1:8080 \
SIMCTL_CHILD_P4CAN_TAB="${TAB}" \
xcrun simctl launch --terminate-running-process "${UDID}" "${BUNDLE_ID}"

sleep 3
echo "4) 截图：${SHOT}"
xcrun simctl io "${UDID}" screenshot --type=png "${SHOT}"
open "${SHOT}" 2>/dev/null || true
