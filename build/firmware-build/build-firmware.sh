#!/bin/bash
# 统一编译入口：显式选择板型/线束，避免再漏 -DP4CAN_BOARD_X179。
# 用法: ./build-firmware.sh [x179|default]
set -euo pipefail

BOARD="${1:-x179}"
case "$BOARD" in
  x179)
    EXTRA="--build-property compiler.cpp.extra_flags=-DP4CAN_BOARD_X179"
    OUT="../out-build-x179"
    EXPECT="X179 (2/3,4/5)"
    ;;
  default)
    EXTRA=""
    OUT="../out-build-default"
    EXPECT="默认 (20-23)"
    ;;
  *)
    echo "usage: $0 [x179|default]" >&2
    exit 2
    ;;
esac

cd "$(dirname "$0")/P4-CAN-Universal-v3.29.3"

arduino-cli compile \
  --fqbn "esp32:esp32:esp32p4:ChipVariant=postv3,FlashSize=32M,PartitionScheme=app5M_fat24M_32MB,PSRAM=enabled,USBMode=hwcdc,CDCOnBoot=cdc,FlashMode=qio" \
  $EXTRA \
  --output-dir "$OUT" \
  .

echo "==> 产物: $OUT/P4-CAN-Universal-v3.29.3.ino.bin"
echo "==> 预期 canHarness: $EXPECT"
