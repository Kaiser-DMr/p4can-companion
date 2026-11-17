#!/usr/bin/env python3
"""P4管家 · iOS 27（Liquid Glass）App 图标 —— Archive of Our Own 标志版

标志来源：build/icon/archive-of-our-own.svg（单色 #990000 的 AO3 字标）
处理思路：标志本身是单色线稿，若红字放浅底，小尺寸会显得单薄；
因此做成「深红玻璃底 + 白色标志」——对比最强、60px 仍可辨，也贴合 iOS 26/27 的层次感。

输出 1024×1024 不透明 PNG（圆角由系统 squircle 裁切）：
  AppIcon.png / AppIcon-Dark.png / AppIcon-Tinted.png / preview-sizes.png
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

S = 1024
W = S * 2                    # 合成超采样
MARK_RATIO = float(os.environ.get("P4_MARK", "0.72"))
MARK_Y = float(os.environ.get("P4_MARK_Y", "0.50"))


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
    return (xx + 0.5) / W - 0.5, (yy + 0.5) / W - 0.5


def background(kind: str) -> np.ndarray:
    nx, ny = grid()
    r = np.sqrt(nx ** 2 + ny ** 2)

    if kind == "light":
        # 品牌红玻璃：中部偏亮，边缘沉入近黑红
        t = np.clip(np.sqrt(((nx + 0.16) * 1.0) ** 2 + ((ny + 0.22) * 0.94) ** 2) / 1.05, 0, 1)
        base = ramp(t, [(0.00, (178, 24, 30)), (0.34, (140, 10, 16)),
                        (0.70, (92, 2, 6)), (1.00, (44, 0, 3))])
        gloss = np.array([255, 170, 170], np.float32)
        gamp = 0.10
    elif kind == "dark":
        t = np.clip(np.sqrt(((nx + 0.10) * 1.0) ** 2 + ((ny + 0.18) * 0.96) ** 2) / 1.06, 0, 1)
        base = ramp(t, [(0.00, (86, 10, 16)), (0.40, (46, 4, 8)),
                        (0.74, (22, 1, 4)), (1.00, (8, 1, 2))])
        gloss = np.array([180, 60, 60], np.float32)
        gamp = 0.20
    else:  # tinted
        t = np.clip(np.sqrt(((nx + 0.10) ** 2 + (ny + 0.16) ** 2)) / 1.05, 0, 1)
        base = ramp(t, [(0.00, (34, 34, 36)), (0.55, (20, 20, 22)), (1.00, (9, 9, 10))])
        gloss = np.array([70, 70, 72], np.float32)
        gamp = 0.08

    # 左上大面积受光（玻璃被点亮）
    g = np.clip(1 - np.sqrt((nx + 0.30) ** 2 + (ny + 0.34) ** 2) / 0.92, 0, 1) ** 2.0
    base = base + g[..., None] * gloss * gamp

    # 中心柔光（衬托标志）
    c = np.clip(1 - np.sqrt((nx + 0.02) ** 2 + (ny + 0.04) ** 2) / 0.74, 0, 1) ** 2.0
    base = base + c[..., None] * (gloss * (0.14 if kind != "tinted" else 0.06))

    # 斜向镜面扫光
    sw = np.clip((0.52 - (0.62 * nx + 0.78 * ny)) / 0.90, 0, 1) ** 2.6
    base = base + sw[..., None] * np.array([255, 235, 235], np.float32) * (0.07 if kind != "tinted" else 0.03)

    # 玻璃反射带：一条柔和斜向高光，模拟液态玻璃表面
    band = np.exp(-((0.60 * nx + 0.80 * ny + 0.42) / 0.16) ** 2) * (0.10 if kind != "tinted" else 0.04)
    base = base + band[..., None] * np.array([255, 225, 225], np.float32)

    # 暗角
    vig = 1 - 0.26 * smoothstep((r - 0.44) / 0.54)
    base = base * vig[..., None]

    rng = np.random.default_rng(20261118)
    base = base + rng.normal(0, 0.0, (W, W, 1)).astype(np.float32)
    return np.clip(base, 0, 255)


def load_mark(path: str, size: int) -> Image.Image:
    return Image.open(path).convert("RGBA").resize((size, size), Image.LANCZOS)


def compose(kind: str, mark_path: str) -> Image.Image:
    bg = background(kind)
    size = int(W * MARK_RATIO)
    mark = load_mark(mark_path, size)

    canvas = Image.fromarray(bg.astype(np.uint8), "RGB").convert("RGBA")
    alpha = mark.getchannel("A")

    # 标志纵向位置：按不透明像素的真实包围盒居中，避免 SVG 空白导致视觉偏心
    bbox = alpha.getbbox()
    if bbox:
        cy = (bbox[1] + bbox[3]) / 2
    else:
        cy = size / 2
    x0 = (W - size) // 2
    y0 = int(W * MARK_Y - cy)

    # 1) 投影（带内边距的画布上模糊，避免被裁断）
    pad = int(size * 0.24)
    padded = Image.new("RGBA", (size + 2 * pad, size + 2 * pad), (0, 0, 0, 0))
    padded.paste(mark, (pad, pad))
    sh = padded.getchannel("A").filter(ImageFilter.GaussianBlur(radius=0.010 * W))
    factor = {"light": 0.34, "dark": 0.42}.get(kind, 0.30)
    sh_img = Image.new("RGBA", padded.size, (48, 0, 4, 255))
    sh_img.putalpha(Image.fromarray(np.clip(np.array(sh, np.float32) * factor, 0, 255).astype(np.uint8), "L"))
    canvas.alpha_composite(sh_img, (x0 - pad + int(0.002 * W), y0 - pad + int(0.005 * W)))

    # 1.5) 标志背光（玻璃导光，小尺寸更醒目）
    halo = alpha.filter(ImageFilter.GaussianBlur(radius=0.026 * W))
    halo_a = np.array(halo, np.float32) * (0.09 if kind != "tinted" else 0.05)
    halo_img = Image.new("RGBA", (size, size), (255, 236, 236, 255))
    halo_img.putalpha(Image.fromarray(np.clip(halo_a, 0, 255).astype(np.uint8), "L"))
    canvas.alpha_composite(halo_img, (x0, y0))

    # 2) 标志本体：上部微亮、下部略暖（玻璃受光）
    arr = np.array(mark, np.float32)
    yy = np.linspace(0, 1, arr.shape[0], dtype=np.float32)[:, None]
    if kind == "tinted":
        sheen = 0.94 + 0.06 * (1 - yy)
    else:
        sheen = 0.90 + 0.14 * (1 - yy)
    arr[..., :3] = np.clip(arr[..., :3] * sheen[..., None], 0, 255)
    mark_rgba = Image.fromarray(arr.astype(np.uint8), "RGBA")
    canvas.alpha_composite(mark_rgba, (x0, y0))

    # 3) 标志外沿极细亮边（玻璃边缘）
    inner = alpha.filter(ImageFilter.GaussianBlur(radius=0.0035 * W))
    rim = np.clip(np.array(alpha, np.float32) - np.array(inner, np.float32), 0, 255)
    rim_layer = Image.new("RGBA", (size, size), (255, 245, 242, 0))
    gy = np.linspace(0, 1, size, dtype=np.float32)[:, None]
    rim_a = rim / 255.0 * (0.30 + 0.45 * (1 - gy))
    rim_layer.putalpha(Image.fromarray(np.clip(rim_a, 0, 1).astype(np.float32).__mul__(255).astype(np.uint8), "L"))
    canvas.alpha_composite(rim_layer, (x0, y0))

    return canvas.convert("RGB").resize((S, S), Image.LANCZOS)


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
    light = compose("light", "/tmp/ao3_white.png")
    dark = compose("dark", "/tmp/ao3_white.png")
    tinted = compose("tinted", "/tmp/ao3_white.png")
    light.save(os.path.join(out, "AppIcon.png"), optimize=True)
    dark.save(os.path.join(out, "AppIcon-Dark.png"), optimize=True)
    tinted.save(os.path.join(out, "AppIcon-Tinted.png"), optimize=True)
    preview(light, os.path.join(out, "preview-sizes.png"))
    for n in ("AppIcon.png", "AppIcon-Dark.png", "AppIcon-Tinted.png"):
        print(f"{n}: {os.path.getsize(os.path.join(out, n)) / 1024:.1f} KB")


if __name__ == "__main__":
    main()
