import Foundation

// MARK: - Layered PSD documents: read, composite with visibility overrides, write.
//
// Implements the documented Adobe PSD layer-and-mask section for 8-bit RGB:
// layer records, per-channel raw / PackBits RLE / ZIP / ZIP-with-prediction
// data, Unicode names (luni) and group markers (lsct). Blend modes: normal,
// multiply, screen, overlay, soft light (others fall back to normal).
// Layer masks and clipping groups are not applied.

public struct PsdLayer: Equatable, Sendable {
    public var name: String
    public var top: Int, left: Int, bottom: Int, right: Int
    public var opacity: UInt8
    public var hidden: Bool
    public var blendKey: String
    public var isGroupMarker: Bool
    /// Straight-alpha RGBA for the layer's bounds (width * height * 4).
    public var rgba: [UInt8]

    public var width: Int { max(0, right - left) }
    public var height: Int { max(0, bottom - top) }

    public init(name: String, top: Int, left: Int, bottom: Int, right: Int, opacity: UInt8 = 255, hidden: Bool = false,
                blendKey: String = "norm", isGroupMarker: Bool = false, rgba: [UInt8]) {
        self.name = name; self.top = top; self.left = left; self.bottom = bottom; self.right = right
        self.opacity = opacity; self.hidden = hidden; self.blendKey = blendKey; self.isGroupMarker = isGroupMarker; self.rgba = rgba
    }

    public var blendName: String {
        switch blendKey {
        case "norm": return "Normal"
        case "mul ": return "Multiply"
        case "scrn": return "Screen"
        case "over": return "Overlay"
        case "sLit": return "Soft Light"
        default: return blendKey.trimmingCharacters(in: .whitespaces)
        }
    }
}

public struct PsdDocument: Equatable, Sendable {
    public var width: Int
    public var height: Int
    /// Bottom-to-top, as stored in the file.
    public var layers: [PsdLayer]

    public init(width: Int, height: Int, layers: [PsdLayer]) { self.width = width; self.height = height; self.layers = layers }

    /// Layers a user can toggle (group markers removed), top-to-bottom like the Layers panel.
    public var panelLayers: [(index: Int, layer: PsdLayer)] {
        layers.enumerated().filter { !$0.element.isGroupMarker }.map { (index: $0.offset, layer: $0.element) }.reversed()
    }

    /// Flattens visible layers. `toggled` flips the stored visibility of those layer indices.
    public func composite(toggled: Set<Int> = [], background: (UInt8, UInt8, UInt8, UInt8)? = nil) -> PixelBuffer {
        let n = width * height
        var r = [Float](repeating: 0, count: n), g = r, b = r, a = r
        if let bg = background {
            for i in 0..<n { r[i] = Float(bg.0) / 255; g[i] = Float(bg.1) / 255; b[i] = Float(bg.2) / 255; a[i] = Float(bg.3) / 255 }
        }
        for (idx, L) in layers.enumerated() where !L.isGroupMarker {
            let visible = toggled.contains(idx) ? L.hidden : !L.hidden
            guard visible, L.width > 0, L.height > 0, L.rgba.count == L.width * L.height * 4 else { continue }
            let op = Float(L.opacity) / 255
            let x0 = max(0, L.left), x1 = min(width, L.right), y0 = max(0, L.top), y1 = min(height, L.bottom)
            guard x0 < x1, y0 < y1 else { continue }
            for y in y0..<y1 {
                let srow = (y - L.top) * L.width
                for x in x0..<x1 {
                    let si = (srow + x - L.left) * 4
                    let sa = Float(L.rgba[si + 3]) / 255 * op
                    if sa <= 0 { continue }
                    let di = y * width + x
                    let da = a[di]
                    let sr = Float(L.rgba[si]) / 255, sg = Float(L.rgba[si + 1]) / 255, sb = Float(L.rgba[si + 2]) / 255
                    let br = Self.blend(L.blendKey, r[di], sr), bgc = Self.blend(L.blendKey, g[di], sg), bb = Self.blend(L.blendKey, b[di], sb)
                    let cr = (1 - da) * sr + da * br, cg = (1 - da) * sg + da * bgc, cb = (1 - da) * sb + da * bb
                    let oa = sa + da * (1 - sa)
                    r[di] = (sa * cr + da * r[di] * (1 - sa)) / oa
                    g[di] = (sa * cg + da * g[di] * (1 - sa)) / oa
                    b[di] = (sa * cb + da * b[di] * (1 - sa)) / oa
                    a[di] = oa
                }
            }
        }
        var out = [UInt8](repeating: 0, count: n * 4)
        for i in 0..<n {
            out[i * 4] = Self.byte(r[i]); out[i * 4 + 1] = Self.byte(g[i]); out[i * 4 + 2] = Self.byte(b[i]); out[i * 4 + 3] = Self.byte(a[i])
        }
        return PixelBuffer(width: width, height: height, rgba: out)
    }

    static func byte(_ v: Float) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }

    static func blend(_ key: String, _ d: Float, _ s: Float) -> Float {
        switch key {
        case "mul ": return d * s
        case "scrn": return d + s - d * s
        case "over": return d <= 0.5 ? 2 * d * s : 1 - 2 * (1 - d) * (1 - s)
        case "sLit":
            if s <= 0.5 { return d - (1 - 2 * s) * d * (1 - d) }
            let dd: Float = d <= 0.25 ? ((16 * d - 12) * d + 4) * d : d.squareRoot()
            return d + (2 * s - 1) * (dd - d)
        default: return s
        }
    }
}

public enum PsdLayers {
    public enum ReadError: Error, Equatable { case notPsd, unsupported(String), truncated }

    struct Reader {
        let b: [UInt8]; var p = 0
        mutating func need(_ n: Int) throws { if n < 0 || p + n > b.count { throw ReadError.truncated } }
        mutating func u8() throws -> Int { try need(1); defer { p += 1 }; return Int(b[p]) }
        mutating func u16() throws -> Int { try need(2); defer { p += 2 }; return Int(b[p]) << 8 | Int(b[p + 1]) }
        mutating func i16() throws -> Int { let v = try u16(); return v >= 0x8000 ? v - 0x10000 : v }
        mutating func u32() throws -> Int { try need(4); defer { p += 4 }; return Int(b[p]) << 24 | Int(b[p + 1]) << 16 | Int(b[p + 2]) << 8 | Int(b[p + 3]) }
        mutating func i32() throws -> Int { let v = try u32(); return v >= 0x8000_0000 ? v - 0x1_0000_0000 : v }
        mutating func bytes(_ n: Int) throws -> [UInt8] { try need(n); defer { p += n }; return Array(b[p..<p + n]) }
        mutating func ascii(_ n: Int) throws -> String { String(decoding: try bytes(n), as: UTF8.self) }
    }

    /// Reads a layered 8-bit RGB PSD. Files without layers return a single "Background" layer from the composite.
    public static func read(_ data: Data) throws -> PsdDocument {
        var r = Reader(b: [UInt8](data))
        guard try r.ascii(4) == "8BPS" else { throw ReadError.notPsd }
        guard try r.u16() == 1 else { throw ReadError.unsupported("PSB / version") }
        r.p += 6
        _ = try r.u16()
        let height = try r.u32(), width = try r.u32(), depth = try r.u16(), mode = try r.u16()
        guard depth == 8 else { throw ReadError.unsupported("\(depth)-bit") }
        guard mode == 3 else { throw ReadError.unsupported("color mode \(mode)") }
        guard width > 0, height > 0, width <= 30000, height <= 30000 else { throw ReadError.unsupported("dimensions") }
        r.p += try r.u32()                      // color mode data
        try r.need(0)
        r.p += try r.u32()                      // image resources
        try r.need(0)
        let sectionLen = try r.u32()
        let sectionEnd = r.p + sectionLen
        var layers: [PsdLayer] = []
        if sectionLen > 0 {
            let infoLen = try r.u32()
            if infoLen > 0 {
                let infoEnd = r.p + infoLen
                let count = abs(try r.i16())
                struct Rec { var layer: PsdLayer; var channels: [(id: Int, len: Int)] }
                var recs: [Rec] = []
                for _ in 0..<count {
                    let top = try r.i32(), left = try r.i32(), bottom = try r.i32(), right = try r.i32()
                    let nch = try r.u16()
                    var chans: [(Int, Int)] = []
                    for _ in 0..<nch { let id = try r.i16(); let len = try r.u32(); chans.append((id, len)) }
                    guard try r.ascii(4) == "8BIM" else { throw ReadError.unsupported("blend signature") }
                    let key = try r.ascii(4)
                    let opacity = try r.u8(); _ = try r.u8(); let flags = try r.u8(); _ = try r.u8()
                    let extraLen = try r.u32()
                    let extraEnd = r.p + extraLen
                    r.p += try r.u32()          // layer mask data
                    r.p += try r.u32()          // blending ranges
                    let nameLen = try r.u8()
                    var name = String(decoding: try r.bytes(nameLen), as: UTF8.self)
                    let padded = (nameLen + 1 + 3) / 4 * 4
                    r.p += padded - (nameLen + 1)
                    var marker = false
                    while r.p + 12 <= extraEnd {
                        let sig = try r.ascii(4)
                        guard sig == "8BIM" || sig == "8B64" else { break }
                        let k = try r.ascii(4); let len = try r.u32(); let start = r.p
                        if k == "luni", len >= 4 {
                            let chars = try r.u32()
                            if chars * 2 <= len - 4 {
                                let raw = try r.bytes(chars * 2)
                                let units = stride(from: 0, to: raw.count, by: 2).map { UInt16(raw[$0]) << 8 | UInt16(raw[$0 + 1]) }
                                name = String(decoding: units, as: UTF16.self)
                            }
                        } else if k == "lsct" || k == "lsdk", len >= 4 {
                            let t = try r.u32(); if t >= 1 && t <= 3 { marker = true }
                        }
                        r.p = start + len + (len & 1)
                    }
                    r.p = extraEnd
                    try r.need(0)
                    let L = PsdLayer(name: name, top: top, left: left, bottom: bottom, right: right, opacity: UInt8(opacity),
                                     hidden: flags & 0x02 != 0, blendKey: key, isGroupMarker: marker, rgba: [])
                    recs.append(Rec(layer: L, channels: chans))
                }
                for var rec in recs {
                    let w = rec.layer.width, h = rec.layer.height
                    var rgba = [UInt8](repeating: 255, count: w * h * 4)
                    for (id, len) in rec.channels {
                        let start = r.p
                        let plane = try decodeChannel(&r, width: w, height: h, length: len)
                        r.p = start + len
                        try r.need(0)
                        let slot: Int? = id == -1 ? 3 : (0...2).contains(id) ? id : nil
                        if let slot, let plane, plane.count == w * h { for i in 0..<(w * h) { rgba[i * 4 + slot] = plane[i] } }
                    }
                    rec.layer.rgba = rgba
                    layers.append(rec.layer)
                }
                r.p = infoEnd
            }
        }
        if layers.isEmpty, let flat = try? PsdDecoder.decode(data) {
            layers = [PsdLayer(name: "Background", top: 0, left: 0, bottom: height, right: width, rgba: flat.rgba)]
        }
        _ = sectionEnd
        return PsdDocument(width: width, height: height, layers: layers)
    }

    static func decodeChannel(_ r: inout Reader, width w: Int, height h: Int, length: Int) throws -> [UInt8]? {
        guard length >= 2 else { return nil }
        let comp = try r.u16()
        let n = w * h
        if n == 0 { return [] }
        switch comp {
        case 0: return try r.bytes(n)
        case 1:
            var counts: [Int] = []
            for _ in 0..<h { counts.append(try r.u16()) }
            var out: [UInt8] = []; out.reserveCapacity(n)
            for c in counts {
                guard let row = PsdDecoder.packBitsDecode(try r.bytes(c), expected: w) else { return nil }
                out.append(contentsOf: row)
            }
            return out
        case 2, 3:
            guard var out = Zlib.inflate(try r.bytes(length - 2)), out.count >= n else { return nil }
            out = Array(out.prefix(n))
            if comp == 3 { for y in 0..<h { for x in 1..<max(1, w) { out[y * w + x] = out[y * w + x] &+ out[y * w + x - 1] } } }
            return out
        default: return nil
        }
    }
}

// MARK: - Writer (used to build the bundled layered mockups and test fixtures)

public enum PsdWriter {
    public static func packBits(_ row: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        var i = 0
        while i < row.count {
            var run = 1
            while i + run < row.count && run < 128 && row[i + run] == row[i] { run += 1 }
            if run >= 2 {
                out.append(UInt8(257 - run)); out.append(row[i]); i += run
            } else {
                var j = i
                while j < row.count && j - i < 128 && !(j + 1 < row.count && row[j] == row[j + 1]) { j += 1 }
                if j == i { j = i + 1 }
                out.append(UInt8(j - i - 1)); out.append(contentsOf: row[i..<j]); i = j
            }
        }
        return out
    }

    static func be16(_ v: Int, _ o: inout [UInt8]) { o.append(UInt8((v >> 8) & 255)); o.append(UInt8(v & 255)) }
    static func be32(_ v: Int, _ o: inout [UInt8]) { let u = UInt32(truncatingIfNeeded: v); for s in [24, 16, 8, 0] { o.append(UInt8((u >> UInt32(s)) & 255)) } }

    /// RLE channel: compression word, per-row byte counts, then rows.
    static func rleChannel(_ plane: [UInt8], width w: Int, height h: Int, includeCompression: Bool = true) -> (counts: [UInt8], data: [UInt8]) {
        var counts: [UInt8] = [], data: [UInt8] = []
        if includeCompression { be16(1, &counts) }
        for y in 0..<h {
            let row = packBits(Array(plane[(y * w)..<(y * w + w)]))
            be16(row.count, &counts); data.append(contentsOf: row)
        }
        return (counts, data)
    }

    public static func write(_ doc: PsdDocument) -> Data {
        var o: [UInt8] = Array("8BPS".utf8)
        be16(1, &o); o.append(contentsOf: [0, 0, 0, 0, 0, 0])
        be16(3, &o); be32(doc.height, &o); be32(doc.width, &o); be16(8, &o); be16(3, &o)
        be32(0, &o); be32(0, &o)
        var info: [UInt8] = []
        be16(doc.layers.count, &info)
        var channelData: [UInt8] = []
        for L in doc.layers {
            be32(L.top, &info); be32(L.left, &info); be32(L.bottom, &info); be32(L.right, &info)
            be16(4, &info)
            let w = L.width, h = L.height
            for (id, slot) in [(-1, 3), (0, 0), (1, 1), (2, 2)] {
                var plane = [UInt8](repeating: 0, count: w * h)
                for i in 0..<(w * h) { plane[i] = L.rgba[i * 4 + slot] }
                let ch = rleChannel(plane, width: w, height: h)
                let bytes = ch.counts + ch.data
                be16(id & 0xFFFF, &info); be32(bytes.count, &info)
                channelData.append(contentsOf: bytes)
            }
            info.append(contentsOf: Array("8BIM".utf8)); info.append(contentsOf: Array(L.blendKey.utf8.prefix(4)))
            info.append(L.opacity); info.append(0); info.append(L.hidden ? 0x0A : 0x08); info.append(0)
            var extra: [UInt8] = []
            be32(0, &extra); be32(0, &extra)
            let nameBytes = Array(L.name.utf8.prefix(255))
            extra.append(UInt8(nameBytes.count)); extra.append(contentsOf: nameBytes)
            while extra.count % 4 != 0 { extra.append(0) }
            let units = Array(L.name.utf16)
            extra.append(contentsOf: Array("8BIMluni".utf8)); be32(4 + units.count * 2 + (units.count % 2 == 1 ? 2 : 0), &extra)
            be32(units.count, &extra); for u in units { be16(Int(u), &extra) }
            if units.count % 2 == 1 { be16(0, &extra) }
            be32(extra.count, &info); info.append(contentsOf: extra)
        }
        info.append(contentsOf: channelData)
        if info.count % 2 == 1 { info.append(0) }
        be32(info.count + 8, &o); be32(info.count, &o); o.append(contentsOf: info); be32(0, &o)
        // Flattened composite (Maximize Compatibility), matted on white.
        let flat = doc.composite(background: (255, 255, 255, 255))
        be16(1, &o)
        var counts: [UInt8] = [], data: [UInt8] = []
        for slot in 0..<3 {
            var plane = [UInt8](repeating: 0, count: doc.width * doc.height)
            for i in 0..<plane.count { plane[i] = flat.rgba[i * 4 + slot] }
            let ch = rleChannel(plane, width: doc.width, height: doc.height, includeCompression: false)
            counts.append(contentsOf: ch.counts); data.append(contentsOf: ch.data)
        }
        o.append(contentsOf: counts); o.append(contentsOf: data)
        return Data(o)
    }
}
