import Foundation

// MARK: - Original layered mockups, drawn procedurally (no third-party content)

public struct Canvas {
    public let width: Int, height: Int
    public var rgba: [Float]   // straight alpha, 0...1

    public init(width: Int, height: Int) { self.width = width; self.height = height; rgba = [Float](repeating: 0, count: width * height * 4) }

    public typealias RGBA = (Float, Float, Float, Float)
    public static func hex(_ s: String, _ a: Float = 1) -> RGBA {
        var h = s; if h.hasPrefix("#") { h.removeFirst() }
        let v = UInt32(h, radix: 16) ?? 0
        return (Float((v >> 16) & 255) / 255, Float((v >> 8) & 255) / 255, Float(v & 255) / 255, a)
    }

    mutating func over(_ i: Int, _ c: RGBA, _ coverage: Float) {
        let sa = c.3 * coverage
        guard sa > 0 else { return }
        let da = rgba[i + 3], oa = sa + da * (1 - sa)
        for k in 0..<3 { let s = k == 0 ? c.0 : k == 1 ? c.1 : c.2; rgba[i + k] = (s * sa + rgba[i + k] * da * (1 - sa)) / oa }
        rgba[i + 3] = oa
    }

    /// Rounded rectangle with 1 px anti-aliased edges; `color` may vary per pixel.
    public mutating func roundedRect(x: Double, y: Double, w: Double, h: Double, radius: Double, color: (Double, Double) -> RGBA) {
        let x0 = max(0, Int(x) - 1), x1 = min(width, Int(x + w) + 2), y0 = max(0, Int(y) - 1), y1 = min(height, Int(y + h) + 2)
        guard x0 < x1, y0 < y1 else { return }
        let rr = min(radius, min(w, h) / 2)
        for py in y0..<y1 {
            for px in x0..<x1 {
                let cx = Double(px) + 0.5, cy = Double(py) + 0.5
                let qx = abs(cx - (x + w / 2)) - (w / 2 - rr), qy = abs(cy - (y + h / 2)) - (h / 2 - rr)
                let outside = (max(qx, 0) * max(qx, 0) + max(qy, 0) * max(qy, 0)).squareRoot() + min(max(qx, qy), 0) - rr
                let cov = Float(max(0, min(1, 0.5 - outside)))
                if cov > 0 { over((py * width + px) * 4, color((cx - x) / w, (cy - y) / h), cov) }
            }
        }
    }

    public mutating func rect(x: Double, y: Double, w: Double, h: Double, _ c: RGBA) { roundedRect(x: x, y: y, w: w, h: h, radius: 0) { _, _ in c } }

    public mutating func ellipse(cx: Double, cy: Double, rx: Double, ry: Double, _ c: RGBA) {
        let x0 = max(0, Int(cx - rx) - 1), x1 = min(width, Int(cx + rx) + 2), y0 = max(0, Int(cy - ry) - 1), y1 = min(height, Int(cy + ry) + 2)
        guard x0 < x1, y0 < y1 else { return }
        for py in y0..<y1 {
            for px in x0..<x1 {
                let dx = (Double(px) + 0.5 - cx) / rx, dy = (Double(py) + 0.5 - cy) / ry
                let d = (dx * dx + dy * dy).squareRoot()
                let cov = Float(max(0, min(1, (1 - d) * min(rx, ry) + 0.5)))
                if cov > 0 { over((py * width + px) * 4, c, cov) }
            }
        }
    }

    /// Fills the whole canvas with a vertical/diagonal gradient.
    public mutating func gradient(_ a: RGBA, _ b: RGBA, diagonal: Bool = false) {
        for py in 0..<height {
            for px in 0..<width {
                let t = Float(diagonal ? (Double(px) / Double(width) + Double(py) / Double(height)) / 2 : Double(py) / Double(height))
                over((py * width + px) * 4, (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, a.2 + (b.2 - a.2) * t, a.3 + (b.3 - a.3) * t), 1)
            }
        }
    }

    /// Separable box blur (3 passes approximates a Gaussian), used for soft shadows.
    public mutating func blur(radius: Int) {
        guard radius > 0 else { return }
        for _ in 0..<3 { pass(horizontal: true, radius); pass(horizontal: false, radius) }
    }
    mutating func pass(horizontal: Bool, _ r: Int) {
        let lines = horizontal ? height : width, len = horizontal ? width : height
        var src = [Float](repeating: 0, count: len * 4)
        let win = Float(2 * r + 1)
        for line in 0..<lines {
            func idx(_ k: Int) -> Int { (horizontal ? line * width + k : k * width + line) * 4 }
            for k in 0..<len { let i = idx(k); let a = rgba[i + 3]; src[k * 4] = rgba[i] * a; src[k * 4 + 1] = rgba[i + 1] * a; src[k * 4 + 2] = rgba[i + 2] * a; src[k * 4 + 3] = a }
            var acc: [Float] = [0, 0, 0, 0]
            for k in -r...r { let kk = min(max(k, 0), len - 1); for c in 0..<4 { acc[c] += src[kk * 4 + c] } }
            for k in 0..<len {
                let i = idx(k); let a = acc[3] / win
                rgba[i + 3] = a
                if a > 0 { for c in 0..<3 { rgba[i + c] = acc[c] / win / a } }
                let add = min(k + r + 1, len - 1), sub = max(k - r, 0)
                for c in 0..<4 { acc[c] += src[add * 4 + c] - src[sub * 4 + c] }
            }
        }
    }

    /// Filled polygon with 4x4 supersampled edges; `color` gets the pixel's (u, v) within the bounding box.
    public mutating func polygon(_ pts: [(Double, Double)], color: (Double, Double) -> RGBA) {
        guard pts.count >= 3 else { return }
        let xs = pts.map(\.0), ys = pts.map(\.1)
        let minX = xs.min()!, maxX = xs.max()!, minY = ys.min()!, maxY = ys.max()!
        let x0 = max(0, Int(minX)), x1 = min(width, Int(maxX) + 1), y0 = max(0, Int(minY)), y1 = min(height, Int(maxY) + 1)
        guard x0 < x1, y0 < y1 else { return }
        func inside(_ px: Double, _ py: Double) -> Bool {
            var c = false, j = pts.count - 1
            for i in 0..<pts.count {
                let (xi, yi) = pts[i], (xj, yj) = pts[j]
                if (yi > py) != (yj > py), px < (xj - xi) * (py - yi) / (yj - yi) + xi { c.toggle() }
                j = i
            }
            return c
        }
        let bw = max(1, maxX - minX), bh = max(1, maxY - minY)
        for y in y0..<y1 { for x in x0..<x1 {
            var hits = 0
            for sy in 0..<4 { for sx in 0..<4 where inside(Double(x) + (Double(sx) + 0.5) / 4, Double(y) + (Double(sy) + 0.5) / 4) { hits += 1 } }
            guard hits > 0 else { continue }
            over((y * width + x) * 4, color((Double(x) - minX) / bw, (Double(y) - minY) / bh), Float(hits) / 16)
        } }
    }

    /// Crops to the painted bounds and converts to a PSD layer.
    public func layer(_ name: String, opacity: UInt8 = 255, blend: String = "norm", hidden: Bool = false) -> PsdLayer {
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height { for x in 0..<width where rgba[(y * width + x) * 4 + 3] > 0.002 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) } }
        if maxX < 0 { return PsdLayer(name: name, top: 0, left: 0, bottom: 0, right: 0, opacity: opacity, hidden: hidden, blendKey: blend, rgba: []) }
        let w = maxX - minX + 1, h = maxY - minY + 1
        var out = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h { for x in 0..<w { let s = ((y + minY) * width + x + minX) * 4, d = (y * w + x) * 4; for c in 0..<4 { out[d + c] = PsdDocument.byte(rgba[s + c]) } } }
        return PsdLayer(name: name, top: minY, left: minX, bottom: minY + h, right: minX + w, opacity: opacity, hidden: hidden, blendKey: blend, rgba: out)
    }
}

public enum MockupFactory {
    public static let names = ["phone-screen-mockup.psd", "poster-frame-mockup.psd", "packaging-box-mockup.psd", "business-card-mockup.psd",
                               "laptop-screen-mockup.psd", "tablet-desk-mockup.psd", "tote-bag-mockup.psd", "billboard-mockup.psd",
                               "magazine-spread-mockup.psd", "coffee-cup-mockup.psd"]

    public static func make(_ name: String, width W: Int = 1600, height H: Int = 1200) -> PsdDocument? {
        let w = Double(W), h = Double(H)
        func fresh() -> Canvas { Canvas(width: W, height: H) }
        func design(_ c: inout Canvas, x: Double, y: Double, cw: Double, ch: Double, radius: Double, a: String, b: String, dots: [String]) {
            let ca = Canvas.hex(a), cb = Canvas.hex(b)
            c.roundedRect(x: x, y: y, w: cw, h: ch, radius: radius) { u, v in
                let t = Float((u + v) / 2)
                let r: Float = ca.0 + (cb.0 - ca.0) * t
                let g: Float = ca.1 + (cb.1 - ca.1) * t
                let b: Float = ca.2 + (cb.2 - ca.2) * t
                return (r, g, b, 1)
            }
            for (i, d) in dots.enumerated() {
                let fx = [0.28, 0.7, 0.45, 0.8][i % 4], fy = [0.3, 0.42, 0.72, 0.8][i % 4], fr = [0.22, 0.16, 0.12, 0.08][i % 4]
                c.ellipse(cx: x + cw * fx, cy: y + ch * fy, rx: min(cw, ch) * fr, ry: min(cw, ch) * fr, Canvas.hex(d, 0.8))
            }
            c.rect(x: x + cw * 0.12, y: y + ch * 0.1, w: cw * 0.36, h: max(4, ch * 0.028), Canvas.hex("#FFFFFF", 0.92))
            c.rect(x: x + cw * 0.12, y: y + ch * 0.1 + ch * 0.05, w: cw * 0.22, h: max(3, ch * 0.018), Canvas.hex("#FFFFFF", 0.6))
        }
        func shadow(_ x: Double, _ y: Double, _ sw: Double, _ sh: Double, radius: Double, blur: Int, alpha: Float) -> Canvas {
            var c = fresh(); c.roundedRect(x: x, y: y, w: sw, h: sh, radius: radius) { _, _ in (0.02, 0.02, 0.04, alpha) }; c.blur(radius: blur); return c
        }
        var layers: [PsdLayer] = []
        switch name {
        case "phone-screen-mockup.psd":
            var bg = fresh(); bg.gradient(Canvas.hex("#1A1D2B"), Canvas.hex("#0B0C12")); layers.append(bg.layer("Backdrop"))
            var sand = fresh(); sand.gradient(Canvas.hex("#E8DCCB"), Canvas.hex("#C9B79F")); layers.append(sand.layer("Backdrop - Sand", hidden: true))
            let pw = w * 0.3, ph = h * 0.78, px = (w - pw) / 2, py = h * 0.1
            var floor = fresh(); floor.ellipse(cx: w / 2, cy: py + ph + 18, rx: pw * 0.62, ry: 26, Canvas.hex("#000000", 0.85)); floor.blur(radius: 14)
            layers.append(floor.layer("Floor Shadow", opacity: 200, blend: "mul "))
            layers.append(shadow(px + 14, py + 26, pw, ph, radius: 64, blur: 18, alpha: 0.7).layer("Drop Shadow", opacity: 170, blend: "mul "))
            var body = fresh()
            body.roundedRect(x: px, y: py, w: pw, h: ph, radius: 64) { u, _ in
                let edge: Double = abs(u - 0.5) * 2
                let t = Float(0.16 + 0.1 * (1 - edge))
                return (t, t, t * 1.08, 1)
            }
            body.roundedRect(x: px + 10, y: py + 10, w: pw - 20, h: ph - 20, radius: 54) { _, _ in (0.02, 0.02, 0.03, 1) }
            body.roundedRect(x: px + pw * 0.36, y: py + 26, w: pw * 0.28, h: 22, radius: 11) { _, _ in (0, 0, 0, 1) }
            layers.append(body.layer("Device Body"))
            var screen = fresh(); design(&screen, x: px + 22, y: py + 22, cw: pw - 44, ch: ph - 44, radius: 44, a: "#7B3FF2", b: "#FF5C8A", dots: ["#FFD166", "#06D6A0", "#FFFFFF", "#3A86FF"])
            layers.append(screen.layer("Your Design (Smart Object)"))
            var glare = fresh()
            glare.roundedRect(x: px + 22, y: py + 22, w: pw - 44, h: ph - 44, radius: 44) { u, v in
                let g: Double = max(0, 0.55 - (u + v) * 0.6)
                return (1, 1, 1, Float(g))
            }
            layers.append(glare.layer("Screen Glare", opacity: 150, blend: "scrn"))
        case "poster-frame-mockup.psd":
            var wall = fresh(); wall.gradient(Canvas.hex("#EFE6DA"), Canvas.hex("#D7C8B4")); layers.append(wall.layer("Wall"))
            var slate = fresh(); slate.gradient(Canvas.hex("#3C4250"), Canvas.hex("#23262E")); layers.append(slate.layer("Wall - Slate", hidden: true))
            let fw = w * 0.42, fh = h * 0.74, fx = (w - fw) / 2, fy = h * 0.1
            layers.append(shadow(fx + 18, fy + 30, fw, fh, radius: 4, blur: 22, alpha: 0.8).layer("Frame Shadow", opacity: 150, blend: "mul "))
            var frame = fresh(); frame.rect(x: fx, y: fy, w: fw, h: fh, Canvas.hex("#16171B")); frame.rect(x: fx + 22, y: fy + 22, w: fw - 44, h: fh - 44, Canvas.hex("#F6F3EE"))
            layers.append(frame.layer("Frame + Mat"))
            var art = fresh(); design(&art, x: fx + 78, y: fy + 78, cw: fw - 156, ch: fh - 156, radius: 0, a: "#E76F51", b: "#264653", dots: ["#F4A261", "#E9C46A", "#2A9D8F", "#FFFFFF"])
            layers.append(art.layer("Artwork (Smart Object)"))
            var light = fresh()
            light.roundedRect(x: 0, y: 0, w: w, h: h, radius: 0) { u, v in
                let du: Double = u - 0.5, dv: Double = v - 0.35
                let d = Float((du * du + dv * dv).squareRoot())
                return (0.35, 0.3, 0.25, min(1, d * 1.3))
            }
            layers.append(light.layer("Light Falloff", opacity: 140, blend: "mul "))
        case "packaging-box-mockup.psd":
            var bg = fresh(); bg.gradient(Canvas.hex("#DDE7EE"), Canvas.hex("#A9BCCB"), diagonal: true); layers.append(bg.layer("Backdrop"))
            let bw = w * 0.34, bh = h * 0.56, bx = w * 0.3, by = h * 0.2, side = w * 0.12
            layers.append(shadow(bx + 30, by + bh - 40, bw + side, 80, radius: 40, blur: 20, alpha: 0.9).layer("Contact Shadow", opacity: 170, blend: "mul "))
            var sideC = fresh(); sideC.roundedRect(x: bx + bw - 4, y: by + 16, w: side, h: bh - 16, radius: 6) { u, _ in
                let t = Float(0.55 - u * 0.2)
                return (t * 0.9, t * 0.75, t * 0.95, 1)
            }
            layers.append(sideC.layer("Box Side"))
            var front = fresh(); design(&front, x: bx, y: by, cw: bw, ch: bh, radius: 8, a: "#8E44AD", b: "#F39C12", dots: ["#FFFFFF", "#F1C40F", "#E74C3C", "#1ABC9C"])
            layers.append(front.layer("Front Label (Smart Object)"))
            var lid = fresh(); lid.roundedRect(x: bx + 6, y: by - 26, w: bw + side - 14, h: 34, radius: 8) { _, _ in (0.93, 0.9, 0.95, 1) }
            layers.append(lid.layer("Lid"))
            var sheen = fresh(); sheen.roundedRect(x: bx, y: by, w: bw * 0.45, h: bh, radius: 8) { u, _ in
                let g: Double = 0.35 * (1 - u)
                return (1, 1, 1, Float(g))
            }
            layers.append(sheen.layer("Sheen", opacity: 160, blend: "scrn"))
        case "business-card-mockup.psd":
            var desk = fresh(); desk.gradient(Canvas.hex("#2B2F36"), Canvas.hex("#15171B"), diagonal: true); layers.append(desk.layer("Desk"))
            var linen = fresh(); linen.gradient(Canvas.hex("#F2EEE8"), Canvas.hex("#D9D2C7"), diagonal: true); layers.append(linen.layer("Desk - Linen", hidden: true))
            let cw = w * 0.4, ch = cw * 0.58
            layers.append(shadow(w * 0.18 + 16, h * 0.18 + 22, cw, ch, radius: 14, blur: 16, alpha: 0.8).layer("Back Card Shadow", opacity: 160, blend: "mul "))
            var back = fresh(); back.roundedRect(x: w * 0.18, y: h * 0.18, w: cw, h: ch, radius: 14) { _, _ in Canvas.hex("#101114") }
            back.ellipse(cx: w * 0.18 + cw / 2, cy: h * 0.18 + ch / 2, rx: ch * 0.2, ry: ch * 0.2, Canvas.hex("#C9A227"))
            back.ellipse(cx: w * 0.18 + cw / 2, cy: h * 0.18 + ch / 2, rx: ch * 0.13, ry: ch * 0.13, Canvas.hex("#101114"))
            layers.append(back.layer("Card Back"))
            layers.append(shadow(w * 0.4 + 18, h * 0.44 + 26, cw, ch, radius: 14, blur: 18, alpha: 0.85).layer("Front Card Shadow", opacity: 170, blend: "mul "))
            var front = fresh(); front.roundedRect(x: w * 0.4, y: h * 0.44, w: cw, h: ch, radius: 14) { _, _ in Canvas.hex("#F7F4EF") }
            front.rect(x: w * 0.4, y: h * 0.44 + ch - 26, w: cw, h: 26, Canvas.hex("#C9A227"))
            front.ellipse(cx: w * 0.4 + 90, cy: h * 0.44 + 90, rx: 44, ry: 44, Canvas.hex("#101114"))
            for (i, bw2) in [0.42, 0.3, 0.36].enumerated() { front.rect(x: w * 0.4 + 60, y: h * 0.44 + ch * 0.55 + Double(i) * 30, w: cw * bw2, h: i == 0 ? 16 : 10, Canvas.hex("#2B2F36", i == 0 ? 1 : 0.55)) }
            layers.append(front.layer("Card Front (Smart Object)"))
        case "laptop-screen-mockup.psd":
            var bg = fresh(); bg.gradient(Canvas.hex("#20232E"), Canvas.hex("#0E0F14"), diagonal: true); layers.append(bg.layer("Backdrop"))
            var studio = fresh(); studio.gradient(Canvas.hex("#E9EEF3"), Canvas.hex("#C3CCD6")); layers.append(studio.layer("Backdrop - Studio White", hidden: true))
            let lw = w * 0.56, lh = lw * 0.62, lx = (w - lw) / 2, ly = h * 0.12
            let baseY = ly + lh, bx0 = lx - w * 0.05, bx1 = lx + lw + w * 0.05
            var floor = fresh(); floor.ellipse(cx: w / 2, cy: baseY + 46, rx: lw * 0.62, ry: 30, Canvas.hex("#000000", 0.9)); floor.blur(radius: 16)
            layers.append(floor.layer("Floor Shadow", opacity: 190, blend: "mul "))
            var lid = fresh(); lid.roundedRect(x: lx, y: ly, w: lw, h: lh, radius: 18) { _, _ in (0.13, 0.13, 0.15, 1) }
            lid.roundedRect(x: lx + 14, y: ly + 14, w: lw - 28, h: lh - 24, radius: 8) { _, _ in (0.01, 0.01, 0.02, 1) }
            layers.append(lid.layer("Display Lid"))
            var screen = fresh(); design(&screen, x: lx + 24, y: ly + 24, cw: lw - 48, ch: lh - 44, radius: 4, a: "#0F4C75", b: "#3282B8", dots: ["#BBE1FA", "#FF7B54", "#FFD56F", "#FFFFFF"])
            layers.append(screen.layer("Screen Design (Smart Object)"))
            var base = fresh()
            base.polygon([(lx - 6, baseY - 2), (lx + lw + 6, baseY - 2), (bx1, baseY + 26), (bx0, baseY + 26)]) { _, v in
                let t = Float(0.72 - v * 0.3)
                return (t, t, t * 1.03, 1)
            }
            base.roundedRect(x: w / 2 - lw * 0.1, y: baseY - 2, w: lw * 0.2, h: 8, radius: 4) { _, _ in (0.5, 0.5, 0.53, 1) }
            layers.append(base.layer("Keyboard Deck"))
            var glare = fresh(); glare.polygon([(lx + 24, ly + 24), (lx + lw * 0.55, ly + 24), (lx + lw * 0.3, ly + lh - 20), (lx + 24, ly + lh - 20)]) { u, _ in (1, 1, 1, Float(0.16 * (1 - u))) }
            layers.append(glare.layer("Screen Reflection", opacity: 170, blend: "scrn"))
        case "tablet-desk-mockup.psd":
            var desk = fresh(); desk.gradient(Canvas.hex("#C9A27E"), Canvas.hex("#8E6B4E"), diagonal: true); layers.append(desk.layer("Walnut Desk"))
            var slate = fresh(); slate.gradient(Canvas.hex("#3A3F4A"), Canvas.hex("#1E2128"), diagonal: true); layers.append(slate.layer("Desk - Slate", hidden: true))
            let tw = w * 0.5, th = tw * 0.72, tx = (w - tw) / 2 - w * 0.04, ty = (h - th) / 2
            layers.append(shadow(tx + 22, ty + 30, tw, th, radius: 40, blur: 24, alpha: 0.75).layer("Tablet Shadow", opacity: 175, blend: "mul "))
            var body = fresh(); body.roundedRect(x: tx, y: ty, w: tw, h: th, radius: 40) { _, _ in (0.09, 0.09, 0.1, 1) }
            layers.append(body.layer("Tablet Body"))
            var screen = fresh(); design(&screen, x: tx + 26, y: ty + 26, cw: tw - 52, ch: th - 52, radius: 18, a: "#FF9A8B", b: "#6A0572", dots: ["#FFE66D", "#FFFFFF", "#4ECDC4", "#FF6B6B"])
            layers.append(screen.layer("Screen Design (Smart Object)"))
            var pencil = fresh(); pencil.roundedRect(x: tx + tw + 50, y: ty + 20, w: 22, h: th * 0.8, radius: 11) { _, v in v > 0.94 ? (0.2, 0.2, 0.22, 1) : (0.95, 0.95, 0.96, 1) }
            layers.append(pencil.layer("Stylus"))
            var sun = fresh(); sun.polygon([(0, 0), (w * 0.55, 0), (w * 0.2, h), (0, h)]) { u, _ in (1, 0.95, 0.85, Float(0.22 * (1 - u))) }
            layers.append(sun.layer("Window Light", opacity: 160, blend: "scrn"))
        case "tote-bag-mockup.psd":
            var bg = fresh(); bg.gradient(Canvas.hex("#E6D5C3"), Canvas.hex("#CDB49A")); layers.append(bg.layer("Backdrop"))
            var sage = fresh(); sage.gradient(Canvas.hex("#B7C4B0"), Canvas.hex("#8FA388")); layers.append(sage.layer("Backdrop - Sage", hidden: true))
            let bw = w * 0.36, bh = bw * 1.05, bx = (w - bw) / 2, by = h * 0.3
            var straps = fresh()
            for sx in [bx + bw * 0.2, bx + bw * 0.58] {
                // Each strap is an arch: outer half-ellipse minus the inner one, as a single ring polygon.
                let cx = sx + bw * 0.11, top = by + bh * 0.05, ro = bw * 0.11, ri = bw * 0.11 * 0.68, rise = h * 0.2, band = bw * 0.035
                var ring: [(Double, Double)] = []
                for k in 0...24 { let a = Double.pi * Double(k) / 24; ring.append((cx - cos(a) * ro, top - sin(a) * rise)) }
                for k in stride(from: 24, through: 0, by: -1) { let a = Double.pi * Double(k) / 24; ring.append((cx - cos(a) * ri, top - sin(a) * (rise - band))) }
                straps.polygon(ring) { u, _ in (0.74 - Float(u) * 0.06, 0.68 - Float(u) * 0.06, 0.58 - Float(u) * 0.05, 1) }
            }
            layers.append(straps.layer("Straps"))
            layers.append(shadow(bx + 14, by + 22, bw, bh, radius: 10, blur: 22, alpha: 0.6).layer("Bag Shadow", opacity: 150, blend: "mul "))
            let canvasTone = TileNoise(seed: 42)
            var bag = fresh(); bag.roundedRect(x: bx, y: by, w: bw, h: bh, radius: 10) { u, v in
                let t = 0.9 + (canvasTone.value(u, v, period: 180) - 0.5) * 0.06
                return (t, t * 0.96, t * 0.88, 1)
            }
            layers.append(bag.layer("Canvas Bag"))
            var print = fresh(); design(&print, x: bx + bw * 0.18, y: by + bh * 0.2, cw: bw * 0.64, ch: bw * 0.64, radius: bw * 0.32, a: "#E63946", b: "#1D3557", dots: ["#F1FAEE", "#A8DADC", "#FFB703", "#FFFFFF"])
            layers.append(print.layer("Print Artwork (Smart Object)", opacity: 235, blend: "mul "))
            var folds = fresh(); folds.polygon([(bx + bw * 0.4, by), (bx + bw * 0.48, by), (bx + bw * 0.44, by + bh), (bx + bw * 0.34, by + bh)]) { _, _ in (0, 0, 0, 0.12) }
            folds.blur(radius: 12)
            layers.append(folds.layer("Fabric Folds", opacity: 200, blend: "mul "))
        case "billboard-mockup.psd":
            var sky = fresh(); sky.gradient(Canvas.hex("#FFB88C"), Canvas.hex("#6A82FB")); layers.append(sky.layer("Sunset Sky"))
            var night = fresh(); night.gradient(Canvas.hex("#0B1026"), Canvas.hex("#2B3A67")); layers.append(night.layer("Sky - Night", hidden: true))
            var city = fresh(); var cxp = 0.0; var bi = 0
            let skyline = TileNoise(seed: 9)
            while cxp < w { let bw2 = 60 + Double(skyline.hash(bi, 1)) * 120, bh2 = h * (0.12 + Double(skyline.hash(bi, 2)) * 0.22); city.rect(x: cxp, y: h - bh2, w: bw2 - 6, h: bh2, Canvas.hex("#1B1F3B")); cxp += bw2; bi += 1 }
            layers.append(city.layer("City Skyline"))
            let bw = w * 0.62, bh = bw * 0.42, bx = (w - bw) / 2, by = h * 0.14
            var pole = fresh(); pole.rect(x: w / 2 - 22, y: by + bh, w: 44, h: h - by - bh, Canvas.hex("#2A2D34")); pole.rect(x: bx + 30, y: by + bh + 10, w: bw - 60, h: 10, Canvas.hex("#3A3D44"))
            layers.append(pole.layer("Pole + Catwalk"))
            var frame = fresh(); frame.rect(x: bx - 14, y: by - 14, w: bw + 28, h: bh + 28, Canvas.hex("#23262D")); layers.append(frame.layer("Board Frame"))
            var art = fresh(); design(&art, x: bx, y: by, cw: bw, ch: bh, radius: 0, a: "#F72585", b: "#3A0CA3", dots: ["#4CC9F0", "#FFFFFF", "#F8961E", "#90BE6D"])
            layers.append(art.layer("Billboard Art (Smart Object)"))
            var lamps = fresh()
            for k in 0..<4 { let lx = bx + bw * (0.15 + Double(k) * 0.23); lamps.polygon([(lx - 8, by - 20), (lx + 8, by - 20), (lx + 90, by + bh * 0.9), (lx - 90, by + bh * 0.9)]) { _, v in (1, 0.95, 0.8, Float(0.28 * (1 - v))) } }
            layers.append(lamps.layer("Flood Lights", opacity: 150, blend: "scrn", hidden: true))
        case "magazine-spread-mockup.psd":
            var desk = fresh(); desk.gradient(Canvas.hex("#DCD6CE"), Canvas.hex("#B9B1A6"), diagonal: true); layers.append(desk.layer("Desk"))
            var ink = fresh(); ink.gradient(Canvas.hex("#1F2A36"), Canvas.hex("#0F151C"), diagonal: true); layers.append(ink.layer("Desk - Ink", hidden: true))
            let pw = w * 0.34, ph = pw * 1.3, px = w / 2 - pw, py = (h - ph) / 2
            layers.append(shadow(px + 16, py + 26, pw * 2, ph, radius: 6, blur: 22, alpha: 0.7).layer("Spread Shadow", opacity: 165, blend: "mul "))
            var pages = fresh(); pages.rect(x: px, y: py, w: pw * 2, h: ph, Canvas.hex("#FAF8F4")); layers.append(pages.layer("Paper"))
            var left = fresh(); design(&left, x: px, y: py, cw: pw, ch: ph, radius: 0, a: "#2B2D42", b: "#8D99AE", dots: ["#EF233C", "#EDF2F4", "#FFB4A2", "#FFFFFF"])
            layers.append(left.layer("Left Page Photo (Smart Object)"))
            var right = fresh()
            right.rect(x: w / 2 + pw * 0.12, y: py + ph * 0.1, w: pw * 0.7, h: 34, Canvas.hex("#1B1B1E"))
            right.rect(x: w / 2 + pw * 0.12, y: py + ph * 0.1 + 50, w: pw * 0.45, h: 18, Canvas.hex("#EF233C"))
            for line in 0..<18 { right.rect(x: w / 2 + pw * 0.12, y: py + ph * 0.24 + Double(line) * 28, w: pw * (line % 6 == 5 ? 0.4 : 0.76), h: 9, Canvas.hex("#3D3D44", 0.7)) }
            layers.append(right.layer("Right Page Layout (Smart Object)"))
            var gutter = fresh(); gutter.roundedRect(x: w / 2 - 50, y: py, w: 100, h: ph, radius: 0) { u, _ in (0.1, 0.08, 0.06, Float(0.45 * pow(1 - abs(u - 0.5) * 2, 2))) }
            layers.append(gutter.layer("Gutter Shade", opacity: 170, blend: "mul "))
        case "coffee-cup-mockup.psd":
            var bg = fresh(); bg.gradient(Canvas.hex("#F3E9DC"), Canvas.hex("#D8C3A5")); layers.append(bg.layer("Backdrop"))
            var moss = fresh(); moss.gradient(Canvas.hex("#3E4A3D"), Canvas.hex("#222A22")); layers.append(moss.layer("Backdrop - Moss", hidden: true))
            let cw = w * 0.24, ch = cw * 1.45, cx = (w - cw) / 2, cy = h * 0.2
            var floor = fresh(); floor.ellipse(cx: w / 2 + 20, cy: cy + ch + 10, rx: cw * 0.75, ry: 34, Canvas.hex("#000000", 0.85)); floor.blur(radius: 16)
            layers.append(floor.layer("Contact Shadow", opacity: 180, blend: "mul "))
            var cup = fresh(); cup.polygon([(cx, cy), (cx + cw, cy), (cx + cw * 0.9, cy + ch), (cx + cw * 0.1, cy + ch)]) { u, _ in
                let t = Float(0.97 - pow(abs(u - 0.4) * 1.6, 2) * 0.25)
                return (t, t * 0.98, t * 0.95, 1)
            }
            layers.append(cup.layer("Paper Cup"))
            var sleeve = fresh(); sleeve.polygon([(cx + cw * 0.03, cy + ch * 0.32), (cx + cw * 0.97, cy + ch * 0.32), (cx + cw * 0.93, cy + ch * 0.7), (cx + cw * 0.07, cy + ch * 0.7)]) { u, v in
                let a = Canvas.hex("#6D597A"), b = Canvas.hex("#E56B6F")
                let t = Float((u + v) / 2)
                return (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, a.2 + (b.2 - a.2) * t, 1)
            }
            sleeve.ellipse(cx: cx + cw / 2, cy: cy + ch * 0.51, rx: cw * 0.16, ry: cw * 0.16, Canvas.hex("#FFFFFF", 0.9))
            layers.append(sleeve.layer("Sleeve Design (Smart Object)"))
            var lid = fresh(); lid.roundedRect(x: cx - 12, y: cy - 36, w: cw + 24, h: 44, radius: 14) { _, v in (0.18 + Float(v) * 0.05, 0.16, 0.15, 1) }
            layers.append(lid.layer("Lid"))
            var shade = fresh(); shade.polygon([(cx + cw * 0.62, cy), (cx + cw, cy), (cx + cw * 0.9, cy + ch), (cx + cw * 0.56, cy + ch)]) { u, _ in (0.1, 0.08, 0.06, Float(0.35 * u)) }
            layers.append(shade.layer("Cylinder Shade", opacity: 190, blend: "mul "))
            var steam = fresh(); steam.ellipse(cx: w / 2 - 20, cy: cy - 120, rx: 30, ry: 70, Canvas.hex("#FFFFFF", 0.5)); steam.ellipse(cx: w / 2 + 25, cy: cy - 190, rx: 24, ry: 60, Canvas.hex("#FFFFFF", 0.4)); steam.blur(radius: 18)
            layers.append(steam.layer("Steam", opacity: 170, blend: "scrn"))
        default: return nil
        }
        return PsdDocument(width: W, height: H, layers: layers)
    }
}
