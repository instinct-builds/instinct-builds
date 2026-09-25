import Foundation

// MARK: - Place into Mockup (1.29)
//
// Puts any artwork into a layered mockup's design layer (the "Smart Object" layer in the bundled mockups,
// or any layer the user picks in their own PSDs). The layer's own pixels define where the art goes:
// its opaque area gives the four corners, and its alpha stays as the mask, so rounded screens,
// perspective labels and multiply-blended prints keep their look. Pure Swift, no platform image APIs.

public struct Point2: Equatable, Sendable {
    public var x: Double, y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

/// Four corners in document pixels, clockwise from top-left.
public struct Quad: Equatable, Sendable {
    public var tl: Point2, tr: Point2, br: Point2, bl: Point2
    public init(tl: Point2, tr: Point2, br: Point2, bl: Point2) { self.tl = tl; self.tr = tr; self.br = br; self.bl = bl }
    static func dist(_ a: Point2, _ b: Point2) -> Double { ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot() }
    public var width: Double { (Quad.dist(tl, tr) + Quad.dist(bl, br)) / 2 }
    public var height: Double { (Quad.dist(tl, bl) + Quad.dist(tr, br)) / 2 }
    /// Width over height of the area the art fills.
    public var aspect: Double { height > 0 ? width / height : 1 }
}

public enum PlacementMode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Covers the whole design area, cropping the art's overflow.
    case fill = "Fill"
    /// Shows the whole art inside the design area, with the background color around it.
    case fit = "Fit"
    public var id: String { rawValue }
}

public enum MockupPlacement {
    /// Layers that are good design targets, best first: named Smart Object, then common design-layer names.
    public static func targetLayers(_ doc: PsdDocument) -> [Int] {
        let words = ["smart object", "your design", "screen design", "artwork", "design", "label", "print", "screen"]
        var scored: [(Int, Int)] = []
        for (i, l) in doc.layers.enumerated() where !l.isGroupMarker && l.width > 8 && l.height > 8 {
            let n = l.name.lowercased()
            if let w = words.firstIndex(where: { n.contains($0) }) { scored.append((w, i)) }
        }
        // Within the same rank, the layer covering the most area (a page photo beats a column of text lines).
        let cover = Dictionary(uniqueKeysWithValues: scored.map { ($0.1, coverage(doc.layers[$0.1]).filled) })
        return scored.sorted { $0.0 != $1.0 ? $0.0 < $1.0 : cover[$0.1]! != cover[$1.1]! ? cover[$0.1]! > cover[$1.1]! : $0.1 > $1.1 }.map(\.1)
    }

    /// Opaque pixels in the layer and the area of their bounding box.
    public static func coverage(_ l: PsdLayer, threshold: UInt8 = 128) -> (filled: Int, box: Int) {
        guard l.width > 0, l.height > 0, l.rgba.count == l.width * l.height * 4 else { return (0, 0) }
        var n = 0, minX = Int.max, maxX = Int.min, minY = Int.max, maxY = Int.min
        for y in 0..<l.height { for x in 0..<l.width where l.rgba[(y * l.width + x) * 4 + 3] >= threshold {
            n += 1; minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        return n == 0 ? (0, 0) : (n, (maxX - minX + 1) * (maxY - minY + 1))
    }

    /// A layer that covers under half its bounding box (text lines, scattered shapes) is a layout, not a shape:
    /// the art fills the whole box instead of showing through the gaps.
    public static func isSparse(_ l: PsdLayer) -> Bool {
        let c = coverage(l)
        return c.box > 0 && Double(c.filled) < 0.5 * Double(c.box)
    }

    /// The design area's corners in document pixels. Upright shapes (including rounded rectangles) use
    /// their bounding box; tilted or perspective shapes use the extreme opaque pixels in each diagonal direction.
    public static func quad(of l: PsdLayer, threshold: UInt8 = 128) -> Quad? {
        guard l.width > 0, l.height > 0, l.rgba.count == l.width * l.height * 4 else { return nil }
        var minX = Int.max, maxX = Int.min, minY = Int.max, maxY = Int.min
        var sMin = Int.max, sMax = Int.min, dMin = Int.max, dMax = Int.min
        var tl = (0, 0), br = (0, 0), tr = (0, 0), bl = (0, 0)
        var top = (0, 0), bottom = (0, 0), left = (0, 0), right = (0, 0)
        var filled = 0
        for y in 0..<l.height {
            for x in 0..<l.width where l.rgba[(y * l.width + x) * 4 + 3] >= threshold {
                filled += 1
                if y < minY { top = (x, y) }
                if y >= maxY { bottom = (x, y) }
                if x < minX { left = (x, y) }
                if x > maxX { right = (x, y) }
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                let s = x + y, d = x - y
                if s < sMin { sMin = s; tl = (x, y) }
                if s > sMax { sMax = s; br = (x, y) }
                if d > dMax { dMax = d; tr = (x, y) }
                if d < dMin { dMin = d; bl = (x, y) }
            }
        }
        guard minX <= maxX, minY <= maxY else { return nil }
        let ox = Double(l.left), oy = Double(l.top)
        let w = Double(maxX - minX + 1), h = Double(maxY - minY + 1)

        func pt(_ c: (Int, Int)) -> Point2 { Point2(x: ox + Double(c.0) + 0.5, y: oy + Double(c.1) + 0.5) }
        func area(_ c: [(Int, Int)]) -> Double {
            var a2 = 0.0
            for k in 0..<4 { let a = c[k], b = c[(k + 1) % 4]; a2 += Double(a.0 * b.1 - b.0 * a.1) }
            return abs(a2) / 2
        }
        // Tilted shapes: take the corner set (diagonal extremes, or axis extremes for ~45° turns) whose quad
        // the shape actually fills. Circles, blobs and sparse layouts fill neither and use the bounding box.
        let fits: ([(Int, Int)]) -> Bool = { c in
            let a = area(c); return a > 0 && Double(filled) >= 0.85 * a && Double(filled) <= 1.2 * a
        }
        let diag = [tl, tr, br, bl], axis = [top, right, bottom, left]
        if Double(filled) < 0.9 * w * h {
            let pick = fits(diag) ? diag : fits(axis) ? axis : nil
            if let c = pick { return Quad(tl: pt(c[0]), tr: pt(c[1]), br: pt(c[2]), bl: pt(c[3])) }
        }
        return Quad(tl: Point2(x: ox + Double(minX), y: oy + Double(minY)), tr: Point2(x: ox + Double(maxX + 1), y: oy + Double(minY)),
                    br: Point2(x: ox + Double(maxX + 1), y: oy + Double(maxY + 1)), bl: Point2(x: ox + Double(minX), y: oy + Double(maxY + 1)))
    }

    /// 3x3 matrix (row-major) mapping the unit square (u, v) onto the quad: (0,0)->tl, (1,0)->tr, (1,1)->br, (0,1)->bl.
    public static func homography(_ q: Quad) -> [Double] {
        let (x0, y0, x1, y1, x2, y2, x3, y3) = (q.tl.x, q.tl.y, q.tr.x, q.tr.y, q.br.x, q.br.y, q.bl.x, q.bl.y)
        let sx = x0 - x1 + x2 - x3, sy = y0 - y1 + y2 - y3
        if abs(sx) < 1e-9 && abs(sy) < 1e-9 {
            return [x1 - x0, x3 - x0, x0, y1 - y0, y3 - y0, y0, 0, 0, 1]
        }
        let dx1 = x1 - x2, dx2 = x3 - x2, dy1 = y1 - y2, dy2 = y3 - y2
        let den = dx1 * dy2 - dx2 * dy1
        let g = (sx * dy2 - dx2 * sy) / den, h = (dx1 * sy - sx * dy1) / den
        return [x1 - x0 + g * x1, x3 - x0 + h * x3, x0, y1 - y0 + g * y1, y3 - y0 + h * y3, y0, g, h, 1]
    }

    public static func apply(_ m: [Double], _ u: Double, _ v: Double) -> Point2 {
        let w = m[6] * u + m[7] * v + m[8]
        return Point2(x: (m[0] * u + m[1] * v + m[2]) / w, y: (m[3] * u + m[4] * v + m[5]) / w)
    }

    public static func inverse(_ m: [Double]) -> [Double]? {
        let a = m[0], b = m[1], c = m[2], d = m[3], e = m[4], f = m[5], g = m[6], h = m[7], i = m[8]
        let A = e * i - f * h, B = -(d * i - f * g), C = d * h - e * g
        let det = a * A + b * B + c * C
        guard abs(det) > 1e-12 else { return nil }
        let inv = [A, -(b * i - c * h), b * f - c * e,
                   B, a * i - c * g, -(a * f - c * d),
                   C, -(a * h - b * g), a * e - b * d]
        return inv.map { $0 / det }
    }

    /// Which part of the art (fractions of its width and height) fills the whole design area.
    /// Fill crops the art to the area's shape; Fit leaves margins (the region runs past 0...1).
    /// A user crop (from the crop drag) wins for Fill and is widened to the area's shape.
    public static func region(mode: PlacementMode, artAspect: Double, areaAspect: Double, crop: BoardRect? = nil) -> BoardRect {
        guard artAspect > 0, areaAspect > 0 else { return BoardRect(x: 0, y: 0, w: 1, h: 1) }
        let base = crop.map { c in BoardRect(x: max(0, c.x), y: max(0, c.y), w: min(1 - max(0, c.x), max(0.02, c.w)), h: min(1 - max(0, c.y), max(0.02, c.h))) }
            ?? BoardRect(x: 0, y: 0, w: 1, h: 1)
        // Aspect of the base region in art pixels.
        let baseAspect = artAspect * base.w / base.h
        switch mode {
        case .fill:
            if baseAspect > areaAspect {
                let w = base.w * areaAspect / baseAspect
                return BoardRect(x: base.midX - w / 2, y: base.y, w: w, h: base.h)
            } else {
                let h = base.h * baseAspect / areaAspect
                return BoardRect(x: base.x, y: base.midY - h / 2, w: base.w, h: h)
            }
        case .fit:
            if baseAspect > areaAspect {
                let h = base.h * baseAspect / areaAspect
                return BoardRect(x: base.x, y: base.midY - h / 2, w: base.w, h: h)
            } else {
                let w = base.w * areaAspect / baseAspect
                return BoardRect(x: base.midX - w / 2, y: base.y, w: w, h: base.h)
            }
        }
    }

    /// Bilinear sample in art pixel space; nil outside the art.
    static func sample(_ img: PixelBuffer, _ x: Double, _ y: Double) -> (Double, Double, Double, Double)? {
        guard x >= 0, y >= 0, x <= Double(img.width), y <= Double(img.height) else { return nil }
        let fx = min(max(x - 0.5, 0), Double(img.width - 1)), fy = min(max(y - 0.5, 0), Double(img.height - 1))
        let x0 = Int(fx), y0 = Int(fy), x1 = min(x0 + 1, img.width - 1), y1 = min(y0 + 1, img.height - 1)
        let tx = fx - Double(x0), ty = fy - Double(y0)
        var out = [0.0, 0, 0, 0]
        for k in 0..<4 {
            let a = Double(img.rgba[(y0 * img.width + x0) * 4 + k]), b = Double(img.rgba[(y0 * img.width + x1) * 4 + k])
            let c = Double(img.rgba[(y1 * img.width + x0) * 4 + k]), d = Double(img.rgba[(y1 * img.width + x1) * 4 + k])
            out[k] = (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty
        }
        return (out[0], out[1], out[2], out[3])
    }

    /// The design layer redrawn with the art. The layer's alpha stays as the mask; transparent art and Fit margins
    /// show `background`.
    public static func render(art: PixelBuffer, into l: PsdLayer, quad: Quad, region: BoardRect,
                              background: (UInt8, UInt8, UInt8) = (255, 255, 255), fullMask: Bool = false) -> PsdLayer {
        var out = l
        let qx0 = Int(min(quad.tl.x, quad.bl.x)) - l.left, qx1 = Int(max(quad.tr.x, quad.br.x).rounded(.up)) - l.left
        let qy0 = Int(min(quad.tl.y, quad.tr.y)) - l.top, qy1 = Int(max(quad.bl.y, quad.br.y).rounded(.up)) - l.top
        guard art.width > 0, art.height > 0, let inv = inverse(homography(quad)) else { return out }
        let bg = (Double(background.0), Double(background.1), Double(background.2))
        for y in 0..<l.height {
            for x in 0..<l.width {
                let i = (y * l.width + x) * 4
                if fullMask && x >= qx0 && x < qx1 && y >= qy0 && y < qy1 { out.rgba[i + 3] = 255 }
                guard out.rgba[i + 3] > 0 else { continue }
                let uv = apply(inv, Double(l.left + x) + 0.5, Double(l.top + y) + 0.5)
                let ax = (region.x + uv.x * region.w) * Double(art.width), ay = (region.y + uv.y * region.h) * Double(art.height)
                var c = bg
                if let s = sample(art, ax, ay) {
                    let a = s.3 / 255
                    c = (s.0 * a + bg.0 * (1 - a), s.1 * a + bg.1 * (1 - a), s.2 * a + bg.2 * (1 - a))
                }
                out.rgba[i] = UInt8(max(0, min(255, c.0.rounded())))
                out.rgba[i + 1] = UInt8(max(0, min(255, c.1.rounded())))
                out.rgba[i + 2] = UInt8(max(0, min(255, c.2.rounded())))
            }
        }
        out.hidden = false
        return out
    }

    /// The mockup with `art` in layer `index` (default: the best target). Nil when there is no usable design layer.
    public static func place(_ art: PixelBuffer, into doc: PsdDocument, layer index: Int? = nil, mode: PlacementMode = .fill,
                             crop: BoardRect? = nil, background: (UInt8, UInt8, UInt8) = (255, 255, 255)) -> PsdDocument? {
        guard let i = index ?? targetLayers(doc).first, doc.layers.indices.contains(i), let q = quad(of: doc.layers[i]) else { return nil }
        let r = region(mode: mode, artAspect: Double(art.width) / Double(max(1, art.height)), areaAspect: q.aspect, crop: crop)
        var d = doc
        d.layers[i] = render(art: art, into: doc.layers[i], quad: q, region: r, background: background, fullMask: isSparse(doc.layers[i]))
        return d
    }
}

extension StudioCatalog {
    /// Files a placed mockup render as a new version on the mockup's stack (1.29). The render takes the mockup's
    /// collection and tags plus the art's tags, and the art's rights, credit and license files, since the artwork
    /// is what a client is licensing. Returns the new asset's id.
    @discardableResult
    public mutating func addPlacedMockup(path: String, art: UUID, mockup: UUID, resolution: String) -> UUID? {
        guard let a = assets.first(where: { $0.id == art }), let m = assets.first(where: { $0.id == mockup }),
              let id = importFile(path: path, collection: m.collection), let i = assets.firstIndex(where: { $0.id == id }) else { return nil }
        assets[i].title = "\(a.title) on \(m.title)"
        assets[i].kind = .mockup
        assets[i].resolution = resolution
        var tags = m.tags.filter { !["psd", "imported", "watched"].contains($0) }
        for t in a.tags where !tags.contains(t) && !["imported", "watched"].contains(t) { tags.append(t) }
        if !tags.contains("placed") { tags.append("placed") }
        assets[i].tags = tags
        // Bundled art has no rights record because it ships with ASSSETS; the render is a user file, so say where it came from.
        assets[i].rights = a.rights ?? ((a.isStarter || a.sourceKey?.hasPrefix("generated:") == true)
            ? UsageRights(license: .own, source: "ASSSETS bundled library", uses: "Any use") : nil)
        assets[i].licenseDocs = a.licenseDocs
        _ = stack([mockup, id])
        return id
    }
}
