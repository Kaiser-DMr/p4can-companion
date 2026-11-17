#!/usr/bin/env python3
"""P4-CAN 工具箱 · iOS 27（Liquid Glass）App 图标 —— LocatorJS 标志版

标志来源：build/icon/locatorjs.svg（四角取景框 + `< / >`）
标志由 macOS NSImage 光栅化（见 build/tools/render_svg.swift），本脚本负责：
  · 全局「液态玻璃」底：柔和多点渐变 + 品牌色渗光 + 大面积受光
  · 标志做悬浮处理：投影、顶部受光、极细亮边
  · 三套外观：默认（浅色玻璃）/ 深色 / 着色（系统 Tint）

输出 1024×1024 不透明 PNG（圆角由系统 squircle 裁切）：
  AppIcon.png / AppIcon-Dark.png / AppIcon-Tinted.png / preview-sizes.png
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

S = 1024
W = S * 2                     # 合成超采样
SS = W / S

MARK_RATIO = float(os.environ.get("P4_MARK", "0.66"))   # 标志占画布比例
MARK_Y = float(os.environ.get("P4_MARK_Y", "0.495"))    # 标志中心纵向位置


def smoothstep(x):
    x = np.clip(x, 0.0, 1.0)
    return x * x * (3 - 2 * x)


def ramp(t, stops):
    out = np.zeros(t.shape + (3,), np.float32)
    t = np.clip(t, 0, 1)
    for i in range(len(stops) - 1):
        p0, c0 = stops[i]
        p1, c1 = stops[i + 1]
        k = smoothstep((t - p0) / max(p1 - p0, 1e-6))[..., None]
        seg = np.array(c0, np.float32) + (np.array(c1, np.float32) - np.array(c0, np.float32)) * k
        out = np.where(((t >= p0) & (t <= p1))[..., None], seg, out)
    return out


def grid():
    yy, xx = np.mgrid[0:W, 0:W].astype(np.float32)
    nx = (xx + 0.5) / W - 0.5
    ny = (yy + 0.5) / W - 0.5
    return nx, ny


# ---------------------------------------------------------------- 背景

def background(kind: str) -> np.ndarray:
    nx, ny = grid()
    r = np.sqrt(nx ** 2 + ny ** 2)

    if kind == "light":
        # 垂直为主的柔光底：顶部近白、底部浅蓝灰（像一块立在光里的玻璃）
        t = np.clip((ny + 0.5), 0, 1)
        base = ramp(t, [(0.00, (252, 253, 255)), (0.50, (243, 245, 253)), (1.00, (228, 232, 246))])
        brand_blue = np.array([176, 174, 248], np.float32)
        brand_red = np.array([250, 192, 200], np.float32)
        amp = 0.34
        sweep = 0.05
    elif kind == "dark":
        d = np.sqrt(((nx + 0.08) * 1.02) ** 2 + ((ny + 0.14) * 0.94) ** 2) / 0.94
        base = ramp(d, [(0.00, (26, 31, 46)), (0.50, (15, 19, 30)), (1.00, (6, 8, 14))])
        brand_blue = np.array([96, 84, 214], np.float32)
        brand_red = np.array([190, 58, 62], np.float32)
        amp = 0.20
        sweep = 0.10
    else:  # tinted
        d = np.sqrt((nx * 1.02) ** 2 + (ny * 0.96) ** 2) / 0.92
        base = ramp(d, [(0.00, (22, 23, 26)), (0.60, (16, 17, 20)), (1.00, (9, 10, 12))])
        brand_blue = np.array([90, 90, 90], np.float32)
        brand_red = np.array([90, 90, 90], np.float32)
        amp = 0.06
        sweep = 0.05

    # 品牌色从左上（蓝）与右下（红）渗入
    gb = np.clip(1 - np.sqrt((nx + 0.44) ** 2 + (ny + 0.46) ** 2) / 0.90, 0, 1) ** 1.9
    gr = np.clip(1 - np.sqrt((nx - 0.46) ** 2 + (ny - 0.48) ** 2) / 0.90, 0, 1) ** 1.9
    if kind == "light":
        # 浅底用"混合"上色（相加会因接近纯白而溢出，导致看不出品牌色）
        kb = (gb * amp)[..., None]
        kr = (gr * amp)[..., None]
        base = base * (1 - kb) + brand_blue * kb
        base = base * (1 - kr) + brand_red * kr
    else:
        base = base + gb[..., None] * brand_blue * amp + gr[..., None] * brand_red * amp

    # 中心大面积柔光（玻璃受光）
    c = np.clip(1 - np.sqrt((nx + 0.02) ** 2 + (ny + 0.10) ** 2) / 0.72, 0, 1) ** 2.0
    if kind == "light":
        base = base + c[..., None] * np.array([255, 255, 255], np.float32) * 0.22
    else:
        base = base + c[..., None] * np.array([70, 92, 130], np.float32) * 0.16

    # 斜向镜面扫光
    sw = np.clip((0.55 - (0.62 * nx + 0.78 * ny)) / 0.85, 0, 1) ** 2.6
    base = base + sw[..., None] * np.array([255, 255, 255], np.float32) * sweep

    # 暗角
    vig = 1 - 0.10 * smoothstep((r - 0.46) / 0.52)
    base = base * vig[..., None]

    rng = np.random.default_rng(20261118)
    base = base + rng.normal(0, 0.0, (W, W, 1)).astype(np.float32)
    return np.clip(base, 0, 255)


# ---------------------------------------------------------------- 标志

def load_mark(path: str, size: int) -> Image.Image:
    im = Image.open(path).convert("RGBA")
    return im.resize((size, size), Image.LANCZOS)


def compose(kind: str, mark_path: str) -> Image.Image:
    bg = background(kind)
    size = int(W * MARK_RATIO)
    mark = load_mark(mark_path, size)

    # 标志位置
    x0 = (W - size) // 2
    y0 = int(W * MARK_Y - size / 2)

    canvas = Image.fromarray(bg.astype(np.uint8), "RGB").convert("RGBA")
    alpha = mark.getchannel("A")

    # 1) 投影：在带内边距的画布上模糊，避免被画布边界裁断
    pad = int(size * 0.24)
    padded = Image.new("RGBA", (size + 2 * pad, size + 2 * pad), (0, 0, 0, 0))
    padded.paste(mark, (pad, pad))
    sh = padded.getchannel("A").filter(ImageFilter.GaussianBlur(radius=0.016 * W))
    factor = {"light": 0.26, "dark": 0.50}.get(kind, 0.40)
    sh_alpha = np.array(sh, np.float32) * factor
    sh_img = Image.new("RGBA", padded.size, (16, 20, 32, 255))
    sh_img.putalpha(Image.fromarray(np.clip(sh_alpha, 0, 255).astype(np.uint8), "L"))
    canvas.alpha_composite(sh_img, (x0 - pad + int(0.004 * W), y0 - pad + int(0.008 * W)))

    # 2) 标志本体（带顶部受光的玻璃光泽）
    mark_rgba = mark.copy()
    arr = np.array(mark_rgba, np.float32)
    yy = np.linspace(0, 1, arr.shape[0], dtype=np.float32)[:, None]
    sheen = 1.10 - 0.16 * yy                      # 上亮下暗，模拟玻璃受光
    arr[..., :3] = np.clip(arr[..., :3] * sheen[..., None], 0, 255)
    mark_rgba = Image.fromarray(arr.astype(np.uint8), "RGBA")
    canvas.alpha_composite(mark_rgba, (x0, y0))

    # 3) 标志外沿极细亮边（玻璃边缘），只在上半部
    edge = np.array(alpha, np.float32) / 255.0
    inner = np.array(alpha.filter(ImageFilter.GaussianBlur(radius=0.004 * W)), np.float32) / 255.0
    rim = np.clip(edge - inner, 0, 1)
    rim_img = Image.fromarray((rim * 255).astype(np.uint8), "L")
    rim_layer = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    gy = np.linspace(0, 1, size, dtype=np.float32)[:, None]
    rim_alpha = np.array(rim_img, np.float32) / 255.0 * (0.35 + 0.45 * (1 - gy))
    rim_layer.putalpha(Image.fromarray((np.clip(rim_alpha, 0, 1) * 255).astype(np.uint8), "L"))
    canvas.alpha_composite(rim_layer, (x0, y0))

    out = canvas.convert("RGB").resize((S, S), Image.LANCZOS)
    return out


# ---------------------------------------------------------------- 预览

def squircle(size: int, ratio: float = 0.225) -> Image.Image:
    k = 4
    big = size * k
    m = Image.new("L", (big, big), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, big - 1, big - 1], radius=int(big * ratio), fill=255)
    return m.resize((size, size), Image.LANCZOS)


def preview(icon: Image.Image, path: str):
    sizes = [180, 120, 80, 60, 40]
    pad = 30
    row_h = 210
    width = pad * (len(sizes) + 1) + sum(sizes)
    sheet = Image.new("RGB", (width, row_h * 2), "#F2F2F7")
    ImageDraw.Draw(sheet).rectangle([0, row_h, width, row_h * 2], fill="#0B0D12")
    for row in range(2):
        x = pad
        for s in sizes:
            ic = icon.resize((s, s), Image.LANCZOS)
            ic.putalpha(squircle(s))
            sheet.paste(ic, (x, row * row_h + (row_h - s) // 2), ic)
            x += s + pad
    sheet.save(path)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(out, exist_ok=True)
    light = compose("light", "/tmp/loc_mark.png")
    dark = compose("dark", "/tmp/loc_mark_dark.png")
    tinted = compose("tinted", "/tmp/loc_mark_mono.png")

    light.save(os.path.join(out, "AppIcon.png"), optimize=True)
    dark.save(os.path.join(out, "AppIcon-Dark.png"), optimize=True)
    tinted.save(os.path.join(out, "AppIcon-Tinted.png"), optimize=True)
    preview(light, os.path.join(out, "preview-sizes.png"))
    for n in ("AppIcon.png", "AppIcon-Dark.png", "AppIcon-Tinted.png"):
        print(f"{n}: {os.path.getsize(os.path.join(out, n)) / 1024:.1f} KB")


if __name__ == "__main__":
    main()
