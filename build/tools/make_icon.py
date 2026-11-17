#!/usr/bin/env python3
"""P4-CAN 工具箱 · iOS 27（Liquid Glass）App 图标生成器

图形取自用户提供的放射状「光圈 / Iris」图案，用玻璃材质重绘为一个真实物件：
  · 锥形玻璃叶片，做折射（把身后背景放大偏移后透上来）
  · 每片叶有双侧镜面细边、迎光面亮带、根部内阴影
  · 缝隙里有接触阴影，叶片与背景之间有真实的"厚度"
  · 内外各一圈玻璃边（菲涅尔），保证 60px 下仍是清晰的环
  · 背景为平滑的多点渐变 + 大面积柔光，无硬边色块

输出 1024×1024 不透明 PNG（圆角由系统 squircle 裁切）：
  AppIcon.png / AppIcon-Dark.png / AppIcon-Tinted.png / preview-*.png
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

S = 1024
SS = 3
W = S * SS

BLADES = int(os.environ.get("P4_BLADES", "32"))
R_OUT = float(os.environ.get("P4_R", "0.345"))
R_IN = float(os.environ.get("P4_RIN", "0.126"))
TIP_HALF = 0.085
OUT_HALF = 0.315


# ------------------------------------------------------------------ 工具

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
    return nx, ny, np.sqrt(nx ** 2 + ny ** 2), np.arctan2(ny, nx)


def blur_np(img: Image.Image, radius: float) -> np.ndarray:
    return np.array(img.filter(ImageFilter.GaussianBlur(radius=radius)), np.float32)


# ------------------------------------------------------------------ 背景

def background(dark: bool) -> np.ndarray:
    nx, ny, r, _ = grid()

    if dark:
        stops = [(0.00, (16, 52, 70)), (0.30, (9, 28, 42)), (0.62, (4, 12, 20)), (1.00, (1, 3, 6))]
        glow_rgb = np.array([30, 132, 172], np.float32)
        glow_amp = 0.26
    else:
        stops = [(0.00, (58, 178, 206)), (0.26, (26, 122, 158)), (0.58, (10, 54, 82)), (1.00, (3, 11, 20))]
        glow_rgb = np.array([66, 198, 236], np.float32)
        glow_amp = 0.34

    d = np.sqrt((nx * 1.05) ** 2 + ((ny + 0.03) * 0.98) ** 2) / 0.74
    base = ramp(d, stops)

    # 中心柔光（宽、弱，避免"聚光灯"感）
    g = np.clip(1 - np.sqrt((nx + 0.01) ** 2 + (ny + 0.02) ** 2) / 0.62, 0, 1) ** 2.0
    base = base + g[..., None] * glow_rgb * glow_amp

    # 左上受光（很宽，几乎无边界）
    sx = np.clip(1 - np.sqrt((nx + 0.34) ** 2 + (ny + 0.42) ** 2) / 0.95, 0, 1) ** 1.9
    base = base + sx[..., None] * np.array([62, 88, 100], np.float32) * (0.26 if dark else 0.40)

    # 右下反弹（偏靛蓝，丰富色相）
    bx = np.clip(1 - np.sqrt((nx - 0.44) ** 2 + (ny - 0.54) ** 2) / 0.72, 0, 1) ** 2.0
    base = base + bx[..., None] * np.array([28, 76, 132], np.float32) * 0.26

    return np.clip(base, 0, 255)


# ------------------------------------------------------------------ 叶片

def blade_geometry():
    nx, ny, r, th = grid()
    t = (r - R_IN) / (R_OUT - R_IN)
    step = 2 * math.pi / BLADES
    idx = np.floor((th + math.pi / 2) / step)
    a0 = -math.pi / 2 + (idx + 0.5) * step
    dth = (th - a0 + math.pi) % (2 * math.pi) - math.pi
    tt = np.clip(t, 0, 1)
    half = step * (TIP_HALF + (OUT_HALF - TIP_HALF) * tt ** 0.8)
    u = dth / np.maximum(half, 1e-6)
    feather = np.maximum(0.55 / np.maximum(r * W, 1.0), 1e-5)
    cov = smoothstep((half - np.abs(dth)) / np.maximum(feather, 1e-6))
    rad = smoothstep(t / 0.010) * smoothstep((1.0 - t) / 0.016)
    return nx, ny, r, t, u, cov * rad, feather


def blades(dark: bool, bg: np.ndarray):
    nx, ny, r, t, u, alpha, feather = blade_geometry()
    tt = np.clip(t, 0, 1)

    # 折射：把背景沿径向放大后采样（玻璃把身后景物"顶"起来）
    mag = 1.055
    iy = np.clip(((ny * mag + 0.5) * W).astype(np.int32), 0, W - 1)
    ix = np.clip(((nx * mag + 0.5) * W).astype(np.int32), 0, W - 1)
    trans = bg[iy, ix] * (1.10 + 0.18 * tt[..., None])

    if dark:
        body_stops = [(0.00, (46, 150, 190)), (0.20, (104, 200, 228)),
                      (0.55, (198, 232, 246)), (1.00, (245, 252, 255))]
    else:
        body_stops = [(0.00, (92, 204, 236)), (0.18, (156, 230, 250)),
                      (0.52, (224, 246, 255)), (1.00, (255, 255, 255))]
    body = ramp(tt, body_stops)

    mixk = (0.28 + 0.62 * tt ** 0.75)[..., None]
    glass = trans * (1 - mixk) + body * mixk

    # 迎光弧面：中间偏亮，两侧收边
    shade = 0.82 + 0.26 * np.clip(1 - u ** 2, 0, 1) ** 0.9
    rgb = glass * shade[..., None]

    # 双侧镜面细边（玻璃棱）
    e1 = np.exp(-((u + 0.86) / 0.13) ** 2)
    e2 = np.exp(-((u - 0.86) / 0.13) ** 2) * 0.45
    rgb = rgb + ((e1 + e2) * (0.55 + 0.45 * tt))[..., None] * np.array([225, 248, 255], np.float32) * 0.95

    # 叶尖聚光 + 极窄收边
    tip = smoothstep((tt - 0.78) / 0.20)
    rgb = rgb + tip[..., None] * np.array([120, 150, 160], np.float32) * 0.26
    rgb = rgb * (1 - 0.10 * smoothstep((tt - 0.980) / 0.020)[..., None])

    # 根部压暗（插入轮毂的厚度）
    rgb = rgb * (1 - 0.34 * smoothstep((0.10 - tt) / 0.10)[..., None])

    a = alpha * (0.60 + 0.34 * tt ** 0.7)

    # 缝隙接触阴影：叶片两侧外沿压暗，制造"缝隙深度"
    gap = np.exp(-((np.abs(u) - 1.10) / 0.30) ** 2) * smoothstep(t / 0.035) * smoothstep((1.0 - t) / 0.02)
    return np.clip(rgb, 0, 255), np.clip(a, 0, 1), gap


# ------------------------------------------------------------------ 组装

def build(dark: bool) -> Image.Image:
    bg = background(dark)
    rgb, a, gap = blades(dark, bg)
    nx, ny, r, th = grid()

    mask_img = Image.fromarray((a * 255).astype(np.uint8), "L")

    # 1) 叶片投影（向下 + 大模糊，悬浮厚度）
    sh = blur_np(mask_img, 0.018 * W) / 255.0 * (0.50 if dark else 0.44)
    sh = np.roll(sh, int(0.014 * W), axis=0)
    bg = bg * (1 - sh[..., None])

    # 2) 缝隙接触阴影
    bg = bg * (1 - 0.28 * gap[..., None])

    # 3) 叶片
    bg = bg * (1 - a[..., None]) + rgb * a[..., None]

    # 3.5) 盘内极淡玻璃膜（统一材质，避免"叶片浮在背景上"）
    film = smoothstep((R_OUT + 0.004 - r) / 0.010)
    bg = bg * (1 - 0.05 * film[..., None]) + np.array([150, 215, 240], np.float32) * (0.045 * film[..., None])

    # 4) 中心孔：暗腔 + 靠壁更深 + 底部反光 + 左上镜面弧
    hole = smoothstep((R_IN - r) / 0.008)
    cav = np.clip(r / R_IN, 0, 1)
    depth = 0.52 + 0.16 * (1 - cav) ** 1.4          # 中心更深
    bg = bg * (1 - (depth * hole)[..., None]) * (1 - 0.10 * hole[..., None]) + np.array([2, 8, 22], np.float32) * (0.22 * hole[..., None])
    # 孔内右下角的反弹光（光从孔壁弹进来）
    bounce = np.exp(-(((nx - 0.012) / (R_IN * 0.62)) ** 2 + ((ny - R_IN * 0.42) / (R_IN * 0.42)) ** 2))
    bg = bg + (bounce * hole)[..., None] * np.array([30, 96, 120], np.float32) * 0.30
    wall = smoothstep((r - (R_IN - 0.004)) / 0.006) * smoothstep(((R_IN + 0.018) - r) / 0.014)
    bg = bg * (1 - 0.34 * wall[..., None])

    arc = 0.20 + 0.80 * np.clip(np.cos(th + 2.36), 0, 1) ** 1.8
    rim = np.exp(-((r - R_IN) / 0.005) ** 2)
    bg = bg + (rim * arc)[..., None] * np.array([168, 226, 246], np.float32) * 0.38

    # 5) 外缘玻璃边（细、带角度衰减）
    ring = np.exp(-((r - R_OUT) / 0.008) ** 2)
    ring_ang = np.clip(np.cos(th + 2.30), 0, 1) ** 1.3
    bg = bg + (ring * (0.18 + 0.82 * ring_ang))[..., None] * np.array([208, 244, 255], np.float32) * 0.55

    # 5.4) 底部反弹光（玻璃下沿的厚度高光）
    bounce_arc = np.exp(-((r - (R_OUT - 0.006)) / 0.012) ** 2) * np.clip(-ny / 0.5, 0, 1) ** 1.8
    bg = bg + bounce_arc[..., None] * np.array([90, 190, 220], np.float32) * 0.28

    # 5.5) 盘外轻微压暗（让玻璃盘从背景中"浮"出来）
    outside = smoothstep((r - R_OUT - 0.010) / 0.10)
    bg = bg * (1 - 0.10 * outside[..., None])

    # 6) 斜向镜面扫光（Liquid Glass 的受光面）
    sweep = np.clip((0.52 - (0.58 * nx + 0.81 * ny)) / 0.78, 0, 1) ** 2.4
    bg = bg + sweep[..., None] * np.array([255, 255, 255], np.float32) * (0.040 if dark else 0.058)

    # 7) 暗角 + 颗粒
    vig = 1 - 0.28 * smoothstep((np.sqrt(nx ** 2 + ny ** 2) - 0.50) / 0.50)
    bg = bg * vig[..., None]
    rng = np.random.default_rng(20261118)
    bg = bg + rng.normal(0, 1.3, (W, W, 1)).astype(np.float32)

    return Image.fromarray(np.clip(bg, 0, 255).astype(np.uint8), "RGB").resize((S, S), Image.LANCZOS)


def build_tinted() -> Image.Image:
    """着色外观：不透明深底 + 灰阶字形（系统按用户色调映射亮度）。"""
    nx, ny, r, t, u, alpha, _ = blade_geometry()
    tt = np.clip(t, 0, 1)

    # 背景：极深中性灰蓝，保证系统着色后仍是"深底浅符"
    g = np.clip(1 - np.sqrt(nx ** 2 + ny ** 2) / 0.80, 0, 1) ** 1.8
    bg = np.array([10, 12, 16], np.float32) + g[..., None] * np.array([26, 30, 38], np.float32)

    # 字形：白到浅灰，靠棱面明暗表达厚度（不使用透射，避免变成线框）
    shade = 0.72 + 0.28 * np.clip(1 - u ** 2, 0, 1) ** 0.8
    body = (np.array([238, 238, 240], np.float32) * shade[..., None])
    edge = np.exp(-((u + 0.86) / 0.14) ** 2)
    body = body + edge[..., None] * np.array([17, 17, 15], np.float32)
    body = np.clip(body * (1 - 0.18 * smoothstep((0.10 - tt) / 0.10)[..., None]), 0, 255)

    # 投影
    mask_img = Image.fromarray((alpha * 255).astype(np.uint8), "L")
    sh = blur_np(mask_img, 0.018 * W) / 255.0 * 0.55
    sh = np.roll(sh, int(0.014 * W), axis=0)
    bg = bg * (1 - sh[..., None])

    a = np.clip(alpha * 0.98, 0, 1)
    bg = bg * (1 - a[..., None]) + body * a[..., None]

    # 中心孔压暗
    hole = smoothstep((R_IN - r) / 0.008)
    bg = bg * (1 - 0.55 * hole[..., None])

    # 内外细边（着色后仍有轮廓）
    ring = np.exp(-((r - R_OUT) / 0.006) ** 2)
    bg = bg + ring[..., None] * np.array([120, 120, 124], np.float32) * 0.35
    rim = np.exp(-((r - R_IN) / 0.005) ** 2)
    bg = bg + rim[..., None] * np.array([110, 110, 114], np.float32) * 0.30

    return Image.fromarray(np.clip(bg, 0, 255).astype(np.uint8), "RGB").resize((S, S), Image.LANCZOS)


# ------------------------------------------------------------------ 预览

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
    light = build(False)
    dark = build(True)
    tinted = build_tinted()
    light.save(os.path.join(out, "AppIcon.png"), optimize=True)
    dark.save(os.path.join(out, "AppIcon-Dark.png"), optimize=True)
    tinted.save(os.path.join(out, "AppIcon-Tinted.png"), optimize=True)
    preview(light, os.path.join(out, "preview-sizes.png"))
    for n in ("AppIcon.png", "AppIcon-Dark.png", "AppIcon-Tinted.png"):
        print(f"{n}: {os.path.getsize(os.path.join(out, n)) / 1024:.1f} KB")


if __name__ == "__main__":
    main()
