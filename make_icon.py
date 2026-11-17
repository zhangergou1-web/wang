#!/usr/bin/env python3
"""生成 App 图标：蓝底 + 白色账本符号 + 硬币点。纯标准库写 PNG，无需 Pillow。"""
import zlib, struct, math, os

SIZE = 1024
BLUE_TOP = (10, 132, 255)
BLUE_BOTTOM = (0, 90, 220)
WHITE = (255, 255, 255)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def blend(dst, src, alpha):
    return tuple(int(dst[i] * (1 - alpha) + src[i] * alpha) for i in range(3))


def rounded_rect_alpha(x, y, x0, y0, x1, y1, r):
    """返回 0..1 的抗锯齿覆盖度"""
    if x < x0 - 1 or x > x1 + 1 or y < y0 - 1 or y > y1 + 1:
        return 0.0
    cx = min(max(x, x0 + r), x1 - r)
    cy = min(max(y, y0 + r), y1 - r)
    d = math.hypot(x - cx, y - cy)
    return max(0.0, min(1.0, r - d + 0.5))


def circle_alpha(x, y, cx, cy, r):
    d = math.hypot(x - cx, y - cy)
    return max(0.0, min(1.0, r - d + 0.5))


def main():
    px = bytearray()
    rows = []
    # 账本：白色圆角矩形书本 + 装订线 + 三条横线 + 右下角硬币
    bx0, by0, bx1, by1 = 250, 200, 774, 824
    for y in range(SIZE):
        row = bytearray()
        t = y / (SIZE - 1)
        base = lerp(BLUE_TOP, BLUE_BOTTOM, t)
        for x in range(SIZE):
            c = base
            # 账本主体
            a = rounded_rect_alpha(x, y, bx0, by0, bx1, by1, 64)
            if a > 0:
                c = blend(c, WHITE, a)
            # 装订线（左侧竖条，用浅蓝）
            if bx0 + 60 <= x <= bx0 + 78 and by0 + 70 <= y <= by1 - 70:
                c = blend(c, (200, 225, 255), 0.95)
            # 三条横线
            for ly, w in ((360, 280), (470, 230), (580, 260)):
                a = rounded_rect_alpha(x, y, bx0 + 110, ly, bx0 + 110 + w, ly + 26, 13)
                if a > 0:
                    c = blend(c, (130, 180, 240), a)
            # 右下硬币
            ca = circle_alpha(x, y, 742, 760, 120)
            if ca > 0:
                c = blend(c, (255, 214, 80), ca)
                ca2 = circle_alpha(x, y, 742, 760, 92)
                if ca2 > 0:
                    c = blend(c, (255, 236, 150), ca2)
            row += bytes(c)
        rows.append(bytes(row))

    raw = b''.join(b'\x00' + r for r in rows)

    def chunk(tag, data):
        return (struct.pack('>I', len(data)) + tag + data +
                struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff))

    png = (b'\x89PNG\r\n\x1a\n' +
           chunk(b'IHDR', struct.pack('>IIBBBBB', SIZE, SIZE, 8, 2, 0, 0, 0)) +
           chunk(b'IDAT', zlib.compress(raw, 9)) +
           chunk(b'IEND', b''))

    out = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       'CostBook', 'Assets.xcassets', 'AppIcon.appiconset', 'icon-1024.png')
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, 'wb') as f:
        f.write(png)
    print('wrote', out, os.path.getsize(out), 'bytes')


if __name__ == '__main__':
    main()
