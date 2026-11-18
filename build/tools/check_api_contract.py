#!/usr/bin/env python3
"""契约检查：App 控件提交的路径与参数，固件是否真的接。

背景：`FeatureControl` 里的 `extra` 表示「从 stats 读某个字段，再以同名字段提交」。
如果 stats 字段名和固件读取的参数名不一致（典型：读 selectedValue、写 value），
设备会回 400，界面上表现为「点了没反应」。这个脚本把这类问题变成可重复的检查。

用法：
    python3 build/tools/check_api_contract.py
退出码 0 = 全部一致；1 = 有可疑项（逐条打印）。
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIRMWARE = ROOT / "build/firmware-build/P4-CAN-Universal-v3.29.3/web_api.h"
CLIENT = ROOT / "P4CANCompanion/Core/P4APIClient.swift"
CATALOG = ROOT / "P4CANCompanion/Core/FeatureCatalog.swift"

# 固件里读取 query 参数的常见写法
ARG_CALL = re.compile(r'[A-Za-z_]*[Aa]rg\w*\(\s*"([^"]+)"')
ARG_NAME = re.compile(r'argName\(\s*\w+\s*\)\s*==\s*"([^"]+)"')


def function_body(source: str, name: str) -> str:
    match = re.search(r"static void %s\s*\([^)]*\)\s*\{" % re.escape(name), source)
    if not match:
        return ""
    start = match.end()
    depth = 1
    index = start
    while index < len(source) and depth:
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
        index += 1
    return source[start:index]


def balanced_blocks(text: str, marker: str) -> list[str]:
    """按括号配对切出每个 FeatureControl(...) 的完整片段（忽略字符串里的括号）。"""
    blocks: list[str] = []
    index = 0
    while True:
        start = text.find(marker, index)
        if start < 0:
            return blocks
        open_index = start + len(marker) - 1
        depth = 0
        pointer = open_index
        in_string = False
        escaped = False
        while pointer < len(text):
            char = text[pointer]
            if in_string:
                if escaped:
                    escaped = False
                elif char == "\\":
                    escaped = True
                elif char == '"':
                    in_string = False
            else:
                if char == '"':
                    in_string = True
                elif char == "(":
                    depth += 1
                elif char == ")":
                    depth -= 1
                    if depth == 0:
                        blocks.append(text[start:pointer + 1])
                        index = pointer + 1
                        break
            pointer += 1
        else:
            return blocks


def main() -> int:
    firmware = FIRMWARE.read_text(errors="ignore")
    routes: dict[str, list[str]] = {}
    for match in re.finditer(
        r'server\.on\("([^"]+)"\s*,\s*HTTP_(\w+)\s*,\s*([A-Za-z0-9_]+)', firmware
    ):
        routes.setdefault(match.group(1), []).append(match.group(3))

    def accepted_args(path: str) -> set[str]:
        args: set[str] = set()
        for fn in routes.get(path, []):
            body = function_body(firmware, fn)
            args |= set(ARG_CALL.findall(body))
            args |= set(ARG_NAME.findall(body))
        return args

    client = CLIENT.read_text()
    constants = dict(re.findall(r'static let (\w+)\s*=\s*"([^"]+)"', client))
    catalog = CATALOG.read_text()

    failures: list[str] = []

    # 1) 路径存在性
    for match in re.finditer(r'path:\s*(P4Route\.\w+|"/api/[^"]+")', catalog):
        raw = match.group(1)
        path = constants.get(raw.split(".")[-1]) if raw.startswith("P4Route.") else raw.strip('"')
        if path and path not in routes:
            failures.append(f"固件未注册路由：{path}")

    # 2) 控件参数名
    for body in balanced_blocks(catalog, "FeatureControl("):
        id_match = re.search(r'id:\s*"([^"]+)"', body)
        path_match = re.search(r'path:\s*P4Route\.(\w+)', body)
        if not id_match or not path_match:
            continue
        control_id = id_match.group(1)
        path = constants.get(path_match.group(1))
        if not path:
            continue
        accepted = accepted_args(path)
        submitted = re.findall(r'key:\s*"([^"]+)"', body)
        for extra in re.findall(r'extra:\s*\[([^\]]*)\]', body):
            # extra 支持 "read:write" 别名写法，提交名是冒号后面的部分
            submitted += [item.split(":")[-1] for item in re.findall(r'"([^"]+)"', extra)]
        submitted += re.findall(r'P4Param\(\s*"([^"]+)"', body)
        for key in submitted:
            if key and key not in accepted:
                failures.append(
                    f"{control_id:22s} → {path}：提交 `{key}`，固件只接受 {sorted(accepted) or '（无参数）'}"
                )

    if failures:
        print(f"发现 {len(failures)} 处契约不一致：")
        for item in failures:
            print("  ✗", item)
        return 1
    print("契约一致：路径与参数全部匹配固件实现。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
