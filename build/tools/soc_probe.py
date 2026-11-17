#!/usr/bin/env python3
"""SOC（电量）候选探测器 —— 针对 P4-CAN 固件的 RAW 研究捕获 CSV。

背景：P4-CAN 固件本身**不解析**电池 SOC，但它的「CAN 研究捕获」可以在
BODY / CHASSIS / PARTY 三路总线上录制原始帧，并导出 CSV：
    GET /api/researchcapture/log.csv

用法：
    # 1. 先让车处于上电/充电状态，打开网页 实验室 → CAN 研究捕获 → 模式选 RAW_TRANSITION（RAW 类）
    # 2. 开始捕获 20–60 秒，结束后导出 CSV（网页按钮或上面的 API）
    # 3. 用本脚本扫描候选字段
    python3 soc_probe.py CAN_Research_Capture.csv
    python3 soc_probe.py capture.csv --bus VEHICLE --top 40

输出：按"像 SOC 的程度"排序的 (总线, CAN ID, 字节序号) 列表。
判据（启发式，不是定理）：
    · 值域落在 0…100（或 0…1000 的十分位表示）
    · 采样点足够多、取值有变化但不是噪声
    · 变化平缓（相邻帧差值小），整体趋势单调（充电时上升 / 行驶时下降）
    · 帧周期稳定（SOC 广播一般是 100 ms ~ 1 s）

注意：脚本只做排序，不做判定。真正确认需要在两个时间点各存一次
（例如充电前 / 充电 10 分钟后），看候选值是否朝预期方向变化。
"""
from __future__ import annotations

import argparse
import csv
import statistics
import sys
from collections import defaultdict


COLUMNS = [
    "segment_id", "label_slot", "label", "phase", "relative_ms",
    "trigger_uptime_ms", "snapshot_uptime_ms", "frame_age_ms",
    "physical_bus", "bus_role", "source", "tx_ok", "id", "dlc", "raw",
]


def parse_rows(path: str):
    with open(path, newline="", encoding="utf-8", errors="replace") as handle:
        reader = csv.reader(handle)
        header: list[str] | None = None
        for row in reader:
            if not row or row[0].startswith("#"):
                continue
            if header is None:
                header = [cell.strip() for cell in row]
                continue
            if len(row) < 15:
                continue
            record = dict(zip(header or COLUMNS, row))
            yield record


def parse_raw(text: str) -> list[int]:
    text = text.strip().strip('"')
    if not text:
        return []
    out: list[int] = []
    for token in text.replace(",", " ").split():
        try:
            out.append(int(token, 16))
        except ValueError:
            pass
    return out


def monotonic_ratio(values: list[float]) -> float:
    """相邻差值的同号比例（1.0 = 完全单调，0.5 = 随机）。"""
    diffs = [b - a for a, b in zip(values, values[1:]) if b != a]
    if len(diffs) < 3:
        return 0.0
    positives = sum(1 for d in diffs if d > 0)
    return max(positives, len(diffs) - positives) / len(diffs)


def score(values: list[float], times: list[float]) -> tuple[float, dict]:
    """给一个 (id, byte) 序列打分；返回分数与统计。"""
    count = len(values)
    if count < 20:
        return 0.0, {}

    lo, hi = min(values), max(values)
    distinct = len(set(values))
    if distinct < 3:
        return 0.0, {}

    in_soc_range = 1.0 if lo >= 0 and hi <= 100 else 0.0
    in_deci_range = 1.0 if lo >= 0 and hi <= 1000 else 0.0

    diffs = [abs(b - a) for a, b in zip(values, values[1:])]
    mean_delta = statistics.fmean(diffs) if diffs else 0.0
    smooth = 1.0 / (1.0 + mean_delta)          # 变化越平缓越高
    mono = monotonic_ratio(values)

    gaps = [b - a for a, b in zip(times, times[1:]) if b > a]
    median_gap = statistics.median(gaps) if gaps else 0.0
    period_ok = 1.0 if 50 <= median_gap <= 2000 else 0.0

    value_range = hi - lo
    span = min(value_range / 20.0, 1.0)        # 至少要有可见变化

    raw_score = (
        1.2 * in_soc_range
        + 0.3 * in_deci_range
        + 1.4 * smooth
        + 1.2 * mono
        + 0.4 * period_ok
        + 1.0 * span
        + min(count / 500.0, 1.0) * 0.8
    )

    stats = {
        "count": count,
        "distinct": distinct,
        "min": lo,
        "max": hi,
        "mean_delta": mean_delta,
        "monotonic": mono,
        "period_ms": median_gap,
    }
    return raw_score, stats


def main() -> int:
    parser = argparse.ArgumentParser(description="在 P4-CAN RAW 捕获 CSV 中寻找电量（SOC）候选字段")
    parser.add_argument("csv_path", help="researchcapture/log.csv 导出的 CSV 文件")
    parser.add_argument("--bus", default=None, help="只看某一路总线（如 VEHICLE / CHASSIS / PARTY）")
    parser.add_argument("--top", type=int, default=25, help="输出前 N 个候选（默认 25）")
    parser.add_argument("--min-count", type=int, default=50, help="最少采样点数（默认 50）")
    args = parser.parse_args()

    series: dict[tuple[str, str, int], tuple[list[float], list[float]]] = {}
    total_rows = 0
    ids_by_bus: dict[str, set[str]] = defaultdict(set)

    for record in parse_rows(args.csv_path):
        bus = (record.get("bus_role") or record.get("physical_bus") or "?").strip()
        if args.bus and args.bus.upper() not in bus.upper():
            continue
        can_id = (record.get("id") or "").strip()
        if not can_id:
            continue
        data = parse_raw(record.get("raw", ""))
        if not data:
            continue
        try:
            timestamp = float(record.get("snapshot_uptime_ms") or record.get("relative_ms") or 0)
        except ValueError:
            timestamp = 0.0

        total_rows += 1
        ids_by_bus[bus].add(can_id)
        for index, byte in enumerate(data):
            key = (bus, can_id, index)
            values, times = series.setdefault(key, ([], []))
            values.append(float(byte))
            times.append(timestamp)

    if not total_rows:
        print("没有解析到任何帧，请确认 CSV 是 RAW 模式导出的（含 id / raw 列）。", file=sys.stderr)
        return 2

    scored = []
    for key, (values, times) in series.items():
        if len(values) < args.min_count:
            continue
        value, stats = score(values, times)
        if value > 0:
            scored.append((value, key, stats))
    scored.sort(key=lambda item: item[0], reverse=True)

    print(f"总帧数 {total_rows} · 候选序列 {len(scored)}")
    for bus, ids in sorted(ids_by_bus.items()):
        print(f"  {bus}: {len(ids)} 个 CAN ID")
    print()

    if not scored:
        print("没有达到阈值的候选。可以降低 --min-count，或换一段更长的捕获。")
        return 0

    header = f"{'score':>5}  {'bus':<10} {'can_id':<8} {'byte':>4} {'n':>6} {'distinct':>8} {'min':>5} {'max':>5} {'Δ/帧':>6} {'单调':>5} {'周期ms':>7}"
    print(header)
    print("-" * len(header))
    for value, (bus, can_id, index), stats in scored[: args.top]:
        print(
            f"{value:5.2f}  {bus:<10} {can_id:<8} {index:>4} {stats['count']:>6} "
            f"{stats['distinct']:>8} {stats['min']:>5.0f} {stats['max']:>5.0f} "
            f"{stats['mean_delta']:>6.2f} {stats['monotonic']:>5.2f} {stats['period_ms']:>7.0f}"
        )

    print()
    print("提示：SOC 通常是 0–100 的整数（或 ×10 的 0–1000）。")
    print("     确认方法：充电前/充电 10 分钟后各抓一次，候选值应朝同一方向变化；")
    print("     车速/里程类字段会随行驶快速变化，SOC 变化更慢。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
