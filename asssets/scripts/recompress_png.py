#!/usr/bin/env python3
"""Re-deflates PNG IDAT streams at level 9 (stdlib only). The Swift core writes stored DEFLATE.
Opaque RGBA images whose rows use filter None/Up are also reduced to RGB, which keeps the filtering valid."""
import struct, sys, zlib

def recompress(path):
    data = open(path, "rb").read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", path
    pos, chunks, idat = 8, [], b""
    while pos < len(data):
        n, = struct.unpack(">I", data[pos:pos + 4]); kind = data[pos + 4:pos + 8]; body = data[pos + 8:pos + 8 + n]
        pos += 12 + n
        if kind == b"IDAT": idat += body
        else: chunks.append((kind, body))
    raw = zlib.decompress(idat)
    kind0, ihdr = chunks[0]
    w, h, depth, ctype = struct.unpack(">IIBB", ihdr[:10])
    if ctype == 6 and depth == 8:
        stride = 1 + w * 4
        rows = [raw[y * stride:(y + 1) * stride] for y in range(h)]
        if all(r[0] in (0, 2) for r in rows) and all(r[4::4] == (b"\xff" * w if (y == 0 or r[0] == 0) else b"\x00" * w) for y, r in enumerate(rows)):
            out_rows = []
            for r in rows:
                px = r[1:]; rgb = bytearray(w * 3)
                rgb[0::3] = px[0::4]; rgb[1::3] = px[1::4]; rgb[2::3] = px[2::4]
                out_rows.append(bytes([r[0]]) + bytes(rgb))
            raw = b"".join(out_rows)
            chunks[0] = (kind0, ihdr[:9] + bytes([2]) + ihdr[10:])
    out = [data[:8]]
    def chunk(kind, body): out.append(struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xffffffff))
    for kind, body in chunks:
        if kind == b"IEND": chunk(b"IDAT", zlib.compress(raw, 9))
        chunk(kind, body)
    open(path, "wb").write(b"".join(out))

for p in sys.argv[1:]:
    before = len(open(p, "rb").read()); recompress(p); print(p, before, "->", len(open(p, "rb").read()))
