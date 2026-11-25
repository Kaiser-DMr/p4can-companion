#!/usr/bin/env bash
# 3.35.8 免重启补发自检
#
# 用法：
#   ./verify-3358-antirestart.sh [host] [--watch N]
#
# 默认 host=192.168.4.1；--watch N 表示每 2 秒采样一次，共 N 次。
# 退出码：0 正常 / 1 补发失败 / 2 连不上 / 3 固件无字段 / 4 无缓存 / 5 窗口进行中

set -u

HOST="192.168.4.1"
WATCH=1
while [ $# -gt 0 ]; do
  case "$1" in
    --watch) WATCH="${2:-1}"; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) HOST="$1"; shift ;;
  esac
done

URL="http://${HOST}/api/service-mode/stats"

sample() {
  local raw
  raw="$(curl -sS --max-time 5 "$URL" 2>/dev/null)" || return 2
  [ -n "$raw" ] || return 2
  printf '%s' "$raw" | python3 -c '
import json, sys

raw = sys.stdin.read()
try:
    d = json.loads(raw)
except Exception:
    print("返回不是 JSON：")
    print(raw[:400])
    sys.exit(2)

need = ["cacheValid", "cacheHex", "replayOk", "burst"]
if not any(k in d for k in need):
    print("该固件没有内置补发状态字段（cacheValid/replayOk/burst）。")
    print("可能不是带修复的 3.35.8 构建，或接口路径不同。")
    sys.exit(3)

def num(k):
    v = d.get(k)
    return int(v) if isinstance(v, (int, float)) else 0

cache_valid = bool(d.get("cacheValid"))
cache_hex = d.get("cacheHex") or "—"
persisted = d.get("persisted")
ok, fail, busy, skip = num("replayOk"), num("replayFail"), num("replayBusy"), num("replaySkip")
burst = num("burst")
expired = d.get("windowExpired")
err = d.get("lastErrName") or "—"

print(f"缓存有效      : {cache_valid}")
print(f"缓存帧         : {cache_hex}")
if persisted is not None:
    print(f"已写入 NVS     : {bool(persisted)}")
print(f"补发 成功/失败/让位/跳过 : {ok} / {fail} / {busy} / {skip}")
print(f"补发帧数       : {burst}")
if expired is not None:
    window_text = "已结束" if expired else "进行中"
    print(f"60 秒窗口      : {window_text}")
print(f"最后错误       : {err}")

if not cache_valid:
    print("结论: NO-CACHE — 还没捕获到补丁后的 0x331。确认 TLSSC 恢复已开、车端发过 0x331。")
    sys.exit(4)
if fail > 0 and ok == 0:
    print("结论: TX-BLOCKED — 有缓存但补发一直失败，检查 CAN 总线/挡位/收发器。")
    sys.exit(1)
if ok > 0:
    print("结论: OK — 缓存已落盘且补发成功。")
    sys.exit(0)
if expired is False:
    print("结论: WAIT — 窗口仍在进行，稍后再查。")
    sys.exit(5)
print("结论: NO-REPLAY — 窗口内没有成功补发，检查 lastErrName 与 CAN 状态。")
sys.exit(1)
'
}

if [ "$WATCH" -le 1 ]; then
  sample
  exit $?
fi

for i in $(seq 1 "$WATCH"); do
  echo "── 采样 $i/$WATCH · $(date '+%H:%M:%S') ──"
  sample
  code=$?
  echo
  [ "$i" -lt "$WATCH" ] && sleep 2
done
exit "$code"
