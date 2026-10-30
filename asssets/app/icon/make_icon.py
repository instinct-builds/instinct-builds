# Generates ASSSETS-icon-1024.png and ASSSETS-icon-small-256.png.
# Original artwork: a stack of asset cards with an image glyph and a palette
# strip, violet-on-dark like the app's studio theme. Needs Pillow. The build
# uses the committed .b64, not this script.
from PIL import Image, ImageDraw, ImageFilter
import os

STROKE = float(os.environ.get('ASSSETS_STROKE', '1.0'))  # multiplier; small variant uses 1.45
OUTSIZE = int(os.environ.get('ASSSETS_OUTSIZE', '1024'))
OUTNAME = os.environ.get('ASSSETS_OUT', 'ASSSETS-icon-1024.png')

S = 1024
SS = 2
N = S * SS

VIOLET = (0x8C, 0x61, 0xFF)
VIOLET_LT = (0xC4, 0xA8, 0xFF)
CYAN = (0x5C, 0xD1, 0xF2)
AMBER = (0xFF, 0xB8, 0x47)
DARKTOP = (0x16, 0x17, 0x24)
DARKBOT = (0x07, 0x08, 0x0D)

def squircle_mask(n, inset, r):
    m = Image.new('L', (n, n), 0)
    d = ImageDraw.Draw(m)
    d.rounded_rectangle([inset, inset, n - inset - 1, n - inset - 1], radius=r, fill=255)
    return m

inset = int(0.098 * N)
mask = squircle_mask(N, inset, int(0.225 * N))

# Background: dark vertical gradient with a soft violet glow behind the cards.
bg = Image.new('RGB', (N, N))
px = bg.load()
for y in range(N):
    t = y / (N - 1)
    c = tuple(int(DARKTOP[i] * (1 - t) + DARKBOT[i] * t) for i in range(3))
    for x in range(N):
        px[x, y] = c
glowmask = Image.new('L', (N, N), 0)
gd = ImageDraw.Draw(glowmask)
gd.ellipse([N * 0.18, N * 0.14, N * 0.82, N * 0.78], fill=110)
glowmask = glowmask.filter(ImageFilter.GaussianBlur(N * 0.09))
bg = Image.composite(Image.new('RGB', (N, N), (0x24, 0x1E, 0x44)), bg, glowmask)

img = bg.copy()
d = ImageDraw.Draw(img)

# Card geometry: front card centered slightly low-left; two stack cards offset up-right.
cw, ch = N * 0.46, N * 0.52
cx0, cy0 = N * 0.24, N * 0.30
off = N * 0.045
cr = N * 0.055  # card corner radius

def card(x0, y0, fill, outline, width):
    d.rounded_rectangle([x0, y0, x0 + cw, y0 + ch], radius=cr, fill=fill, outline=outline, width=width)

sw = int(0.016 * N * STROKE)  # base stroke
# back stack cards: progressively darker violet outlines, no fill
card(cx0 + 2 * off, cy0 - 2 * off, None, (0x3A, 0x2E, 0x66), sw)
card(cx0 + off, cy0 - off, (0x10, 0x11, 0x1C), (0x55, 0x44, 0x99), sw)
# front card
card(cx0, cy0, (0x13, 0x14, 0x22), VIOLET, int(sw * 1.25))

# Image glyph inside the front card: sun dot + mountain ridge, violet -> light violet.
gx0, gy0 = cx0 + cw * 0.16, cy0 + ch * 0.16
gw, gh = cw * 0.68, ch * 0.56
gw2 = int(0.028 * N * STROKE)
# sun
sr = 0.052 * N
sx, sy = gx0 + gw * 0.72, gy0 + gh * 0.24
d.ellipse([sx - sr, sy - sr, sx + sr, sy + sr], fill=VIOLET_LT)
# mountains: two ridge polylines
m1 = [(gx0, gy0 + gh * 0.95), (gx0 + gw * 0.34, gy0 + gh * 0.38), (gx0 + gw * 0.55, gy0 + gh * 0.72)]
m2 = [(gx0 + gw * 0.42, gy0 + gh * 0.95), (gx0 + gw * 0.68, gy0 + gh * 0.55), (gx0 + gw, gy0 + gh * 0.95)]
d.line(m1, fill=VIOLET, width=gw2, joint='curve')
d.line(m2, fill=VIOLET_LT, width=gw2, joint='curve')

# Palette strip at the card's lower edge: three dots (violet, cyan, amber).
pr = 0.030 * N
py = cy0 + ch * 0.85
for i, col in enumerate((VIOLET, CYAN, AMBER)):
    px0 = cx0 + cw * (0.30 + i * 0.20)
    d.ellipse([px0 - pr, py - pr, px0 + pr, py + pr], fill=col)

# Squircle clip, then downscale.
out = Image.new('RGB', (N, N), (0, 0, 0))
out.paste(img, (0, 0), mask)
out = out.resize((OUTSIZE, OUTSIZE), Image.LANCZOS)
out.save(OUTNAME)
print(OUTNAME)
