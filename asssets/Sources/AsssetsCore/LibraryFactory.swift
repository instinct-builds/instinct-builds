import Foundation

// MARK: - Original seamless textures and editorial vectors, generated from code (no third-party content)

/// Tileable value noise: the lattice wraps every `period` cells, so textures repeat without seams.
struct TileNoise {
    let seed: UInt32
    func hash(_ x: Int, _ y: Int) -> Float {
        var h = UInt32(truncatingIfNeeded: x &* 374761393 &+ y &* 668265263) &+ seed &* 2246822519
        h = (h ^ (h >> 13)) &* 1274126177
        h ^= h >> 16
        return Float(h & 0xFFFF) / 65535
    }
    /// u, v in 0..<1 across the tile; `period` lattice cells per tile.
    func value(_ u: Double, _ v: Double, period: Int) -> Float { value(u, v, periodX: period, periodY: period) }

    /// Anisotropic version: different lattice counts across and down, still wrapping on both axes.
    func value(_ u: Double, _ v: Double, periodX: Int, periodY: Int) -> Float {
        let x = u * Double(periodX), y = v * Double(periodY)
        let xi = Int(floor(x)), yi = Int(floor(y))
        let fx = Float(x - floor(x)), fy = Float(y - floor(y))
        func wx(_ i: Int) -> Int { ((i % periodX) + periodX) % periodX }
        func wy(_ i: Int) -> Int { ((i % periodY) + periodY) % periodY }
        let a = hash(wx(xi), wy(yi)), b = hash(wx(xi + 1), wy(yi)), c = hash(wx(xi), wy(yi + 1)), d = hash(wx(xi + 1), wy(yi + 1))
        let sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy)
        return (a + (b - a) * sx) * (1 - sy) + (c + (d - c) * sx) * sy
    }
    func fbm(_ u: Double, _ v: Double, period: Int, octaves: Int = 5) -> Float {
        var sum: Float = 0, amp: Float = 0.5, norm: Float = 0, p = period
        for _ in 0..<octaves { sum += value(u, v, period: p) * amp; norm += amp; amp *= 0.5; p *= 2 }
        return sum / norm
    }
}

public enum TextureFactory {
    public static let names = ["terrazzo-texture.png", "brushed-metal-texture.png", "marble-veins-texture.png", "halftone-dots-texture.png",
                               "woven-linen-texture.png", "topo-lines-texture.png", "watercolor-wash-texture.png", "cork-board-texture.png"]

    static func mix(_ a: Canvas.RGBA, _ b: Canvas.RGBA, _ t: Float) -> (Float, Float, Float) {
        let k = min(1, max(0, t)); return (a.0 + (b.0 - a.0) * k, a.1 + (b.1 - a.1) * k, a.2 + (b.2 - a.2) * k)
    }

    /// Renders a seamless square texture. Returns nil for unknown names.
    public static func make(_ name: String, size: Int = 2048) -> PixelBuffer? {
        guard let idx = names.firstIndex(of: name) else { return nil }
        let n = TileNoise(seed: UInt32(idx + 11) &* 7919)
        let n2 = TileNoise(seed: UInt32(idx + 101) &* 104729)
        var out = [UInt8](repeating: 255, count: size * size * 4)
        let S = Double(size)
        func put(_ x: Int, _ y: Int, _ c: (Float, Float, Float)) {
            let i = (y * size + x) * 4
            out[i] = UInt8(max(0, min(255, c.0 * 255))); out[i + 1] = UInt8(max(0, min(255, c.1 * 255))); out[i + 2] = UInt8(max(0, min(255, c.2 * 255)))
        }
        func H(_ s: String) -> Canvas.RGBA { Canvas.hex(s) }
        switch name {
        case "terrazzo-texture.png":
            let chips = [H("#C8553D"), H("#2D6A4F"), H("#F2CC8F"), H("#3D405B"), H("#81B29A"), H("#E07A5F")]
            for y in 0..<size { for x in 0..<size {
                let u = Double(x) / S, v = Double(y) / S
                let g = n2.fbm(u, v, period: 64, octaves: 3)
                var c = mix(H("#EFE8DE"), H("#DCD2C4"), g)
                // Chips: cells of a jittered grid, each an irregular blob that wraps with the tile.
                let cells = 26, cu = u * Double(cells), cv = v * Double(cells)
                let ci = Int(cu), cj = Int(cv)
                outer: for dj in -1...1 { for di in -1...1 {
                    let gi = ((ci + di) % cells + cells) % cells, gj = ((cj + dj) % cells + cells) % cells
                    let hx = n.hash(gi, gj), hy = n.hash(gj + 999, gi), hr = n.hash(gi + 77, gj + 33)
                    guard hr > 0.25 else { continue }
                    let px = Double(ci + di) + Double(hx), py = Double(cj + dj) + Double(hy)
                    let wob = Double(n.value(u * 3 + Double(gi), v * 3 + Double(gj), period: 8)) * 0.18
                    let r = 0.18 + Double(hr) * 0.3 + wob
                    let dx = cu - px, dy = (cv - py) * (0.7 + Double(hx) * 0.6)
                    if dx * dx + dy * dy < r * r {
                        let chip = chips[Int(n.hash(gj, gi + 5) * Float(chips.count)) % chips.count]
                        c = mix(chip, H("#FFFFFF"), n2.value(u, v, period: 512) * 0.18); break outer
                    }
                } }
                put(x, y, c)
            } }
        case "brushed-metal-texture.png":
            for y in 0..<size { for x in 0..<size {
                let u = Double(x) / S, v = Double(y) / S
                // Long horizontal grain: few lattice cells across, many down, wrapping both ways.
                let grain = n.value(u, v, periodX: 6, periodY: 700) * 0.5 + n.value(u, v, periodX: 12, periodY: 1400) * 0.3 + n.value(u, v, periodX: 3, periodY: 350) * 0.2
                let streak = n.value(u, v, period: 1024) * 0.2 + grain * 0.6
                let t = 0.55 + (streak - 0.4) * 0.5 + Float(sin(v * .pi * 2)) * 0.04
                put(x, y, (t * 0.93, t * 0.95, t))
            } }
        case "marble-veins-texture.png":
            for y in 0..<size { for x in 0..<size {
                let u = Double(x) / S, v = Double(y) / S
                let turb = Double(n.fbm(u, v, period: 4, octaves: 6))
                let s = abs(sin((u + v) * .pi * 6 + turb * 9))
                let vein = Float(pow(1 - s, 10))
                let fine = Float(pow(1 - abs(sin((u - v) * .pi * 14 + turb * 14)), 30)) * 0.4
                var c = mix(H("#F4F2EE"), H("#DAD6CF"), n2.fbm(u, v, period: 8, octaves: 4))
                c = mix((c.0, c.1, c.2, 1), H("#6B6F76"), vein * 0.85 + fine)
                put(x, y, c)
            } }
        case "halftone-dots-texture.png":
            let cells = 96
            for y in 0..<size { for x in 0..<size {
                let u = Double(x) / S, v = Double(y) / S
                let tone = Double(n.fbm(u, v, period: 3, octaves: 4))
                let fu = u * Double(cells) - floor(u * Double(cells)) - 0.5, fv = v * Double(cells) - floor(v * Double(cells)) - 0.5
                let r = 0.1 + tone * 0.5
                let d = (fu * fu + fv * fv).squareRoot()
                let cov = Float(max(0, min(1, (r - d) * Double(size / cells) + 0.5)))
                let paper = mix(H("#F3EEE3"), H("#E8E0CF"), n2.value(u, v, period: 256))
                put(x, y, mix((paper.0, paper.1, paper.2, 1), H("#1D3557"), cov))
            } }
        case "woven-linen-texture.png":
            let threads = 256
            for y in 0..<size { for x in 0..<size {
                let u = Double(x) / S, v = Double(y) / S
                let tu = u * Double(threads), tv = v * Double(threads)
                let over = (Int(tu) + Int(tv)) % 2 == 0
                let across = Float(sin((over ? tv : tu) * .pi * 2)) * 0.5 + 0.5
                let slub = n.value(over ? 0 : u, over ? v : 0, period: 512) * 0.2
                let t = 0.78 + across * 0.08 - slub + (n2.value(u, v, period: 1024) - 0.5) * 0.06
                put(x, y, (t * 0.98, t * 0.95, t * 0.88))
            } }
        case "topo-lines-texture.png":
            for y in 0..<size { for x in 0..<size {
                let u = Double(x) / S, v = Double(y) / S
                let h = Double(n.fbm(u, v, period: 3, octaves: 4)) * 14
                let f = h - floor(h)
                let major = Int(floor(h)) % 5 == 0
                let line = Float(max(0, 1 - min(f, 1 - f) * (major ? 9 : 16)))
                let base = mix(H("#0F2A2E"), H("#133A3F"), Float(h / 14))
                put(x, y, mix((base.0, base.1, base.2, 1), major ? H("#E9C46A") : H("#8AB6A8"), line * (major ? 0.95 : 0.6)))
            } }
        case "watercolor-wash-texture.png":
            for y in 0..<size { for x in 0..<size {
                let u = Double(x) / S, v = Double(y) / S
                let a = n.fbm(u, v, period: 2, octaves: 6), b = n2.fbm(u + 0.3, v, period: 3, octaves: 6)
                let sa = max(0, min(1, (a - 0.4) * 3)), sb = max(0, min(1, (b - 0.46) * 3))
                var c = mix(H("#FBF7F0"), H("#7FA7C9"), sa * sa * (3 - 2 * sa) * 0.85)
                c = mix((c.0, c.1, c.2, 1), H("#E5989B"), sb * sb * (3 - 2 * sb) * 0.75)
                let grain = (n2.value(u, v, period: 1024) - 0.5) * 0.04
                put(x, y, (c.0 + grain, c.1 + grain, c.2 + grain))
            } }
        case "cork-board-texture.png":
            for y in 0..<size { for x in 0..<size {
                let u = Double(x) / S, v = Double(y) / S
                let g = n.fbm(u, v, period: 128, octaves: 3)
                let speck = n2.value(u, v, period: 768)
                var c = mix(H("#B7865A"), H("#8C5E3C"), g)
                if speck > 0.82 { c = mix((c.0, c.1, c.2, 1), H("#4A2E1C"), (speck - 0.82) * 4) }
                if speck < 0.1 { c = mix((c.0, c.1, c.2, 1), H("#D9B38C"), (0.1 - speck) * 6) }
                put(x, y, c)
            } }
        default: return nil
        }
        return PixelBuffer(width: size, height: size, rgba: out)
    }
}

public enum VectorFactory {
    public static let names: [String] = (1...6).map { String(format: "bauhaus-vector-%02d.svg", $0) } + (1...6).map { String(format: "contour-vector-%02d.svg", $0) }

    static let palettes: [[String]] = [
        ["#F2E8CF", "#BC4749", "#386641", "#F4A259", "#1D3557"],
        ["#101820", "#FEE715", "#F95738", "#EE964B", "#F4D35E"],
        ["#FAF3DD", "#2A9D8F", "#E76F51", "#264653", "#E9C46A"],
        ["#0B132B", "#5BC0BE", "#FFB5A7", "#3A506B", "#F6F7EB"],
        ["#FFF8E7", "#D62828", "#003049", "#F77F00", "#FCBF49"],
        ["#1B1B1E", "#D8DBE2", "#A9BCD0", "#58A4B0", "#FF6B6B"],
    ]

    static func f(_ d: Double) -> String { String(Int(d.rounded())) }

    /// Returns an original SVG (1200 x 800) using only shapes the ASSSETS renderer draws natively.
    public static func make(_ name: String) -> String? {
        guard let i = names.firstIndex(of: name) else { return nil }
        let p = palettes[i % 6]
        var rng = TileNoise(seed: UInt32(i * 31 + 7)), k = 0
        func r() -> Double { k += 1; return Double(rng.hash(k, i)) }
        var body = ""
        if i < 6 {
            // Bauhaus grid: tiles of quarter circles, half circles, triangles and bars.
            body += "<rect width=\"1200\" height=\"800\" fill=\"\(p[0])\"/>"
            let cell = 200.0
            for gy in 0..<4 { for gx in 0..<6 {
                let x = Double(gx) * cell, y = Double(gy) * cell
                let c1 = p[1 + Int(r() * 4) % 4], c2 = p[1 + Int(r() * 4) % 4]
                let kind = Int(r() * 5)
                if r() > 0.55 { body += "<rect x=\"\(f(x))\" y=\"\(f(y))\" width=\"200\" height=\"200\" fill=\"\(c2)\"/>" }
                switch kind {
                case 0: // quarter circle from a corner
                    let corner = Int(r() * 4)
                    let cx = x + (corner % 2 == 0 ? 0 : cell), cy = y + (corner < 2 ? 0 : cell)
                    var pts = ["\(f(cx)),\(f(cy))"]
                    for s in 0...16 {
                        let a = Double(s) / 16 * .pi / 2 + Double(corner == 0 ? 0 : corner == 1 ? 1 : corner == 3 ? 2 : 3) * .pi / 2
                        pts.append("\(f(cx + cos(a) * cell)),\(f(cy + sin(a) * cell))")
                    }
                    body += "<polygon points=\"\(pts.joined(separator: " "))\" fill=\"\(c1)\"/>"
                case 1: body += "<circle cx=\"\(f(x + 100))\" cy=\"\(f(y + 100))\" r=\"\(f(40 + r() * 50))\" fill=\"\(c1)\"/>"
                case 2: body += "<polygon points=\"\(f(x)),\(f(y + cell)) \(f(x + cell)),\(f(y + cell)) \(f(x + (r() > 0.5 ? 0 : cell))),\(f(y))\" fill=\"\(c1)\"/>"
                case 3:
                    for b in 0..<3 { body += "<rect x=\"\(f(x + 30))\" y=\"\(f(y + 40 + Double(b) * 50))\" width=\"140\" height=\"22\" fill=\"\(c1)\"/>" }
                default:
                    var pts: [String] = []
                    for s in 0...16 { let a = Double(s) / 16 * .pi; pts.append("\(f(x + 100 + cos(a) * 90)),\(f(y + 100 + sin(a) * 90))") }
                    body += "<polygon points=\"\(pts.joined(separator: " "))\" fill=\"\(c1)\"/>"
                }
            } }
        } else {
            // Contour ribbons: stacked wave bands with a gradient sky.
            body += "<defs><linearGradient id=\"g\" x2=\"0\" y2=\"1\"><stop stop-color=\"\(p[0])\"/><stop offset=\"1\" stop-color=\"\(p[3])\"/></linearGradient></defs>"
            body += "<rect width=\"1200\" height=\"800\" fill=\"url(#g)\"/>"
            body += "<circle cx=\"\(f(250 + r() * 700))\" cy=\"\(f(170 + r() * 80))\" r=\"\(f(70 + r() * 50))\" fill=\"\(p[4])\" opacity=\".9\"/>"
            let bands = 7
            let j = Double(i - 6)
            let ph1 = j * 1.9 + r(), ph2 = j * 2.7 + r(), amp = 22 + j * 7, f1 = 150 + j * 22, f2 = 55 + j * 9
            for b in 0..<bands {
                let base = 300 + Double(b) * 75
                var top: [String] = []
                for s in 0...48 {
                    let x = Double(s) * 25
                    let yv = base + sin(x / f1 + ph1 + Double(b) * 0.6) * amp + sin(x / f2 + ph2 + Double(b)) * amp * 0.35
                    top.append("\(f(x)),\(f(yv))")
                }
                let pts = top.joined(separator: " ") + " 1200,800 0,800"
                let color = p[1 + (b % 4)]
                body += "<polygon points=\"\(pts)\" fill=\"\(color)\" opacity=\"\(b == 0 ? ".85" : ".95")\"/>"
            }
        }
        return "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1200\" height=\"800\" viewBox=\"0 0 1200 800\">\(body)</svg>"
    }
}

extension PNGEncoder {
    /// PNG with the "Up" row filter, which makes smooth generated textures far more compressible
    /// once the build re-deflates the stream (see scripts/recompress_png.py).
    public static func encodeUpFiltered(_ img: PixelBuffer) -> Data {
        var raw: [UInt8] = []
        let rowBytes = img.width * 4
        raw.reserveCapacity(img.height * (1 + rowBytes))
        for y in 0..<img.height {
            let row = y * rowBytes
            if y == 0 { raw.append(0); raw.append(contentsOf: img.rgba[row..<(row + rowBytes)]); continue }
            raw.append(2)
            for x in 0..<rowBytes { raw.append(img.rgba[row + x] &- img.rgba[row - rowBytes + x]) }
        }
        return encodeRaw(width: img.width, height: img.height, filtered: raw)
    }
}
