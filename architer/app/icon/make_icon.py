# Generates ARCHITER-icon-1024.png and ARCHITER-icon-small-256.png
# (then: base64 -w76 X.png > X.png.b64). Needs Pillow. The build uses the
# committed .b64, not this script. Original ink-and-brass d20 artwork.
from PIL import Image, ImageDraw, ImageFilter
import math

def squircle_mask(N, inset, radius):
    m = Image.new('L', (N, N), 0)
    d = ImageDraw.Draw(m)
    d.rounded_rectangle([inset, inset, N - inset - 1, N - inset - 1], radius=radius, fill=255)
    return m

def d20_points(cx, cy, R):
    # pointy-top hexagon vertices, clockwise from the top
    return [(cx + R * math.cos(math.radians(a)), cy - R * math.sin(math.radians(a)))
            for a in (90, 30, -30, -90, -150, 150)]

def build(out, SIZE, STROKE):
    N = 2048  # supersample
    inset = int(0.098 * N); radius = int(0.225 * N)
    mask = squircle_mask(N, inset, radius)
    # ink background, vertical gradient
    top = (0x1b, 0x13, 0x0b); bot = (0x0b, 0x07, 0x05)
    bg = Image.new('RGB', (N, N))
    px = bg.load()
    for y in range(N):
        t = y / (N - 1)
        c = tuple(int(top[i] * (1 - t) + bot[i] * t) for i in range(3))
        for x in range(N):
            px[x, y] = c
    # soft brass glow behind the die, centred a touch high
    glow = Image.new('L', (N, N), 0)
    gd = ImageDraw.Draw(glow)
    cx, cy = N * 0.5, N * 0.52
    gr = N * 0.34
    gd.ellipse([cx - gr, cy - gr, cx + gr, cy + gr], fill=90)
    glow = glow.filter(ImageFilter.GaussianBlur(N * 0.09))
    brass = (0xc9, 0x9a, 0x4e); brass_lt = (0xf0, 0xd2, 0x8a)
    img = Image.composite(Image.new('RGB', (N, N), (0x4a, 0x35, 0x1a)), bg, glow)
    # d20 facet line art on its own layer
    layer = Image.new('L', (N, N), 0)
    d = ImageDraw.Draw(layer)
    R = N * 0.335
    v = d20_points(cx, cy, R)
    w = int(STROKE * N)
    d.polygon(v, outline=255, width=w)
    # upright triangle through alternating vertices (top, lower-left, lower-right)
    tri = [v[0], v[4], v[2]]
    d.polygon(tri, outline=255, width=w)
    # facet spokes: the other three vertices to the opposite triangle edge midpoints
    def mid(a, b):
        return ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
    d.line([v[1], mid(v[0], v[2])], fill=255, width=w)
    d.line([v[3], mid(v[2], v[4])], fill=255, width=w)
    d.line([v[5], mid(v[4], v[0])], fill=255, width=w)
    # brass gradient on the line art: light at top, deep at bottom
    line_col = Image.new('RGB', (N, N))
    lp = line_col.load()
    for y in range(N):
        t = y / (N - 1)
        c = tuple(int(brass_lt[i] * (1 - t) + brass[i] * t) for i in range(3))
        for x in range(N):
            lp[x, y] = c
    img = Image.composite(line_col, img, layer)
    # clip to the squircle, subtle inner border
    out_img = Image.new('RGBA', (N, N), (0, 0, 0, 0))
    out_img.paste(img, (0, 0), mask)
    border = Image.new('L', (N, N), 0)
    bd = ImageDraw.Draw(border)
    bd.rounded_rectangle([inset, inset, N - inset - 1, N - inset - 1], radius=radius,
                         outline=255, width=int(0.004 * N))
    ov = Image.new('RGBA', (N, N), (255, 255, 255, 0))
    ov.putalpha(border.point(lambda val: int(val * 0.10)))
    out_img = Image.alpha_composite(out_img, ov)
    out_img = out_img.resize((SIZE, SIZE), Image.LANCZOS)
    out_img.save(out, optimize=True)

build('ARCHITER-icon-1024.png', 1024, 0.016)
build('ARCHITER-icon-small-256.png', 256, 0.030)  # thicker stroke, for the sizes where the fine line vanishes
