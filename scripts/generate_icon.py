#!/usr/bin/env python3
import math
import os
import struct
import subprocess
import zlib


def write_png_rgba(path, w, h, pixels):
    # pixels: list/bytes of length w*h*4, row-major, RGBA 8-bit.
    def chunk(tag, data):
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    signature = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)

    # Add filter byte 0 at start of each row.
    raw = bytearray()
    stride = w * 4
    for y in range(h):
        raw.append(0)
        start = y * stride
        raw.extend(pixels[start : start + stride])

    compressed = zlib.compress(bytes(raw), level=9)
    png = bytearray()
    png.extend(signature)
    png.extend(chunk(b"IHDR", ihdr))
    png.extend(chunk(b"IDAT", compressed))
    png.extend(chunk(b"IEND", b""))

    with open(path, "wb") as f:
        f.write(png)


def clamp01(x):
    return 0.0 if x < 0.0 else 1.0 if x > 1.0 else x


def lerp(a, b, t):
    return a + (b - a) * t


def srgb_to_u8(x):
    return int(round(clamp01(x) * 255.0))


def make_icon_base(size=1024):
    w = h = size
    px = bytearray(w * h * 4)

    # Background gradient (warm paper)
    c0 = (0xF7 / 255.0, 0xF4 / 255.0, 0xEE / 255.0)
    c1 = (0xE9 / 255.0, 0xD7 / 255.0, 0xB9 / 255.0)

    ink = (0x1E / 255.0, 0x2A / 255.0, 0x2F / 255.0)
    cream = (0xFD / 255.0, 0xFB / 255.0, 0xF6 / 255.0)

    def set_px(x, y, r, g, b, a=1.0):
        i = (y * w + x) * 4
        px[i + 0] = srgb_to_u8(r)
        px[i + 1] = srgb_to_u8(g)
        px[i + 2] = srgb_to_u8(b)
        px[i + 3] = srgb_to_u8(a)

    def blend_px(x, y, r, g, b, a):
        if a <= 0:
            return
        i = (y * w + x) * 4
        br = px[i + 0] / 255.0
        bg = px[i + 1] / 255.0
        bb = px[i + 2] / 255.0
        ba = px[i + 3] / 255.0

        oa = a + ba * (1 - a)
        if oa <= 1e-6:
            return
        or_ = (r * a + br * ba * (1 - a)) / oa
        og_ = (g * a + bg * ba * (1 - a)) / oa
        ob_ = (b * a + bb * ba * (1 - a)) / oa
        px[i + 0] = srgb_to_u8(or_)
        px[i + 1] = srgb_to_u8(og_)
        px[i + 2] = srgb_to_u8(ob_)
        px[i + 3] = srgb_to_u8(oa)

    # Rounded rect mask
    rr = int(size * 0.18)

    for y in range(h):
        for x in range(w):
            # gradient
            t = (x + y) / (2.0 * (size - 1))
            r = lerp(c0[0], c1[0], t)
            g = lerp(c0[1], c1[1], t)
            b = lerp(c0[2], c1[2], t)

            # rounded square alpha
            dx = min(x, w - 1 - x)
            dy = min(y, h - 1 - y)
            a = 1.0
            if dx < rr and dy < rr:
                cx = rr
                cy = rr
                # distance from corner circle
                dist = math.hypot(cx - dx, cy - dy)
                a = 1.0 if dist <= rr else 0.0

            set_px(x, y, r, g, b, a)

    # Magnifying glass (circle outline + handle)
    cx, cy = int(size * 0.42), int(size * 0.46)
    radius = int(size * 0.22)
    thick = int(size * 0.028)

    for y in range(h):
        for x in range(w):
            dx = x - cx
            dy = y - cy
            d = math.hypot(dx, dy)
            if abs(d - radius) <= thick:
                blend_px(x, y, ink[0], ink[1], ink[2], 0.95)

    # Handle as thick line segment
    x0, y0 = int(size * 0.56), int(size * 0.60)
    x1, y1 = int(size * 0.78), int(size * 0.82)
    handle_r = int(size * 0.032)

    vx = x1 - x0
    vy = y1 - y0
    vlen2 = vx * vx + vy * vy

    for y in range(h):
        for x in range(w):
            # distance point to segment
            wx = x - x0
            wy = y - y0
            t = 0.0 if vlen2 == 0 else (wx * vx + wy * vy) / vlen2
            t = 0.0 if t < 0.0 else 1.0 if t > 1.0 else t
            pxs = x0 + t * vx
            pys = y0 + t * vy
            d = math.hypot(x - pxs, y - pys)
            if d <= handle_r:
                blend_px(x, y, ink[0], ink[1], ink[2], 0.95)

    # Chat bubble (rounded rect + tail)
    bx0, by0 = int(size * 0.50), int(size * 0.18)
    bw, bh = int(size * 0.34), int(size * 0.22)
    br = int(size * 0.04)
    stroke = int(size * 0.020)

    def inside_round_rect(x, y, x0, y0, w0, h0, rad):
        # signed distance-like check
        rx = min(max(x - x0, 0), w0)
        ry = min(max(y - y0, 0), h0)
        # clamp to core rect
        ix = x0 + rx
        iy = y0 + ry
        # corners
        cx0 = x0 + rad
        cy0 = y0 + rad
        cx1 = x0 + w0 - rad
        cy1 = y0 + h0 - rad
        if (x0 + rad <= x <= x0 + w0 - rad) and (y0 <= y <= y0 + h0):
            return True
        if (x0 <= x <= x0 + w0) and (y0 + rad <= y <= y0 + h0 - rad):
            return True
        # corner circles
        if x < cx0 and y < cy0:
            return (x - cx0) ** 2 + (y - cy0) ** 2 <= rad * rad
        if x > cx1 and y < cy0:
            return (x - cx1) ** 2 + (y - cy0) ** 2 <= rad * rad
        if x < cx0 and y > cy1:
            return (x - cx0) ** 2 + (y - cy1) ** 2 <= rad * rad
        if x > cx1 and y > cy1:
            return (x - cx1) ** 2 + (y - cy1) ** 2 <= rad * rad
        return False

    # Fill
    for y in range(by0, by0 + bh):
        for x in range(bx0, bx0 + bw):
            if inside_round_rect(x, y, bx0, by0, bw, bh, br):
                blend_px(x, y, cream[0], cream[1], cream[2], 0.96)

    # Tail
    tx = int(bx0 + bw * 0.22)
    ty = int(by0 + bh)
    for y in range(ty, ty + int(size * 0.06)):
        for x in range(tx - int(size * 0.05), tx + int(size * 0.05)):
            # simple triangle
            if y - ty >= 0 and abs(x - tx) <= (y - ty):
                blend_px(x, y, cream[0], cream[1], cream[2], 0.96)

    # Stroke for bubble
    for y in range(by0 - stroke, by0 + bh + stroke * 2):
        for x in range(bx0 - stroke, bx0 + bw + stroke):
            in_outer = inside_round_rect(x, y, bx0, by0, bw, bh, br)
            in_inner = inside_round_rect(
                x,
                y,
                bx0 + stroke,
                by0 + stroke,
                bw - 2 * stroke,
                bh - 2 * stroke,
                max(0, br - stroke),
            )
            if in_outer and not in_inner:
                blend_px(x, y, ink[0], ink[1], ink[2], 0.95)

    # Dots inside bubble
    dot_y = int(by0 + bh * 0.55)
    for k in range(3):
        dot_x = int(bx0 + bw * (0.38 + k * 0.14))
        dr = int(size * 0.018)
        for y in range(dot_y - dr * 2, dot_y + dr * 2):
            for x in range(dot_x - dr * 2, dot_x + dr * 2):
                if (x - dot_x) ** 2 + (y - dot_y) ** 2 <= dr * dr:
                    blend_px(x, y, ink[0], ink[1], ink[2], 0.85)

    return px


def run(cmd):
    subprocess.check_call(cmd)


def main():
    root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    resources = os.path.join(root, "Resources")
    iconset = os.path.join(resources, "AppIcon.iconset")
    os.makedirs(iconset, exist_ok=True)

    base_png = os.path.join(iconset, "icon_1024x1024.png")
    pixels = make_icon_base(1024)
    write_png_rgba(base_png, 1024, 1024, pixels)

    sizes = [16, 32, 64, 128, 256, 512]
    for s in sizes:
        out1 = os.path.join(iconset, f"icon_{s}x{s}.png")
        out2 = os.path.join(iconset, f"icon_{s}x{s}@2x.png")
        run(["sips", "-z", str(s), str(s), base_png, "--out", out1])
        run(["sips", "-z", str(s * 2), str(s * 2), base_png, "--out", out2])

    icns = os.path.join(resources, "AppIcon.icns")
    run(["iconutil", "-c", "icns", iconset, "-o", icns])

    # Keep iconset for inspection; can be removed manually.
    print("Wrote:", icns)


if __name__ == "__main__":
    main()
