import Foundation

// MARK: - Search by color (1.15)

/// "Assets with a color near this one." Tolerance is a CIEDE2000 distance: about 2 is a just-visible
/// difference, 10 is clearly the same color family, 25 and up is loose.
public struct ColorQuery: Codable, Equatable, Hashable, Sendable {
    public var hex: String
    public var tolerance: Double
    public static let defaultTolerance = 14.0
    public static let toleranceRange = 4.0...40.0

    public init(hex: String, tolerance: Double = ColorQuery.defaultTolerance) {
        self.hex = ColorSearch.normalize(hex) ?? "#808080"
        self.tolerance = min(Self.toleranceRange.upperBound, max(Self.toleranceRange.lowerBound, tolerance))
    }

    enum CodingKeys: String, CodingKey { case hex, tolerance }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(hex: (try? c.decode(String.self, forKey: .hex)) ?? "#808080",
                  tolerance: (try? c.decode(Double.self, forKey: .tolerance)) ?? Self.defaultTolerance)
    }

    /// Plain words for chips and rule summaries: "close", "near", "loose".
    public var closeness: String { tolerance <= 8 ? "close to" : tolerance <= 20 ? "near" : "loosely like" }
}

public struct LabColor: Equatable, Sendable {
    public var l: Double, a: Double, b: Double
    public init(l: Double, a: Double, b: Double) { self.l = l; self.a = a; self.b = b }
}

public enum ColorSearch {
    /// "#4dabf7", "4DABF7", "#4ab" -> "#4DABF7". Nil for anything else.
    public static func normalize(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, s.allSatisfy({ $0.isHexDigit }) else { return nil }
        return "#" + s
    }

    public static func rgb(_ hex: String) -> (r: Double, g: Double, b: Double)? {
        guard let h = normalize(hex), let n = UInt32(h.dropFirst(), radix: 16) else { return nil }
        return (Double((n >> 16) & 255) / 255, Double((n >> 8) & 255) / 255, Double(n & 255) / 255)
    }

    /// sRGB (D65) to CIE L*a*b*.
    public static func lab(_ hex: String) -> LabColor? {
        guard let c = rgb(hex) else { return nil }
        func lin(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let r = lin(c.r), g = lin(c.g), b = lin(c.b)
        let x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047
        let y = (0.2126729 * r + 0.7151522 * g + 0.0721750 * b)
        let z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883
        func f(_ t: Double) -> Double { t > 216.0 / 24389.0 ? cbrt(t) : (24389.0 / 27.0 * t + 16) / 116 }
        let fx = f(x), fy = f(y), fz = f(z)
        return LabColor(l: 116 * fy - 16, a: 500 * (fx - fy), b: 200 * (fy - fz))
    }

    /// CIEDE2000 color difference (Sharma, Wu and Dalal 2005).
    public static func deltaE(_ p: LabColor, _ q: LabColor) -> Double {
        let rad = Double.pi / 180
        let c1 = (p.a * p.a + p.b * p.b).squareRoot(), c2 = (q.a * q.a + q.b * q.b).squareRoot()
        let cm = (c1 + c2) / 2
        let g = 0.5 * (1 - (pow(cm, 7) / (pow(cm, 7) + pow(25, 7))).squareRoot())
        let a1 = (1 + g) * p.a, a2 = (1 + g) * q.a
        let c1p = (a1 * a1 + p.b * p.b).squareRoot(), c2p = (a2 * a2 + q.b * q.b).squareRoot()
        func hue(_ b: Double, _ a: Double) -> Double {
            if a == 0 && b == 0 { return 0 }
            let h = atan2(b, a) / rad
            return h < 0 ? h + 360 : h
        }
        let h1 = hue(p.b, a1), h2 = hue(q.b, a2)
        let dL = q.l - p.l, dC = c2p - c1p
        var dh = 0.0
        if c1p * c2p != 0 {
            dh = h2 - h1
            if dh > 180 { dh -= 360 } else if dh < -180 { dh += 360 }
        }
        let dH = 2 * (c1p * c2p).squareRoot() * sin(dh / 2 * rad)
        let lm = (p.l + q.l) / 2, cmp = (c1p + c2p) / 2
        var hm = h1 + h2
        if c1p * c2p != 0 {
            if abs(h1 - h2) <= 180 { hm = (h1 + h2) / 2 }
            else if h1 + h2 < 360 { hm = (h1 + h2 + 360) / 2 }
            else { hm = (h1 + h2 - 360) / 2 }
        }
        let t = 1 - 0.17 * cos((hm - 30) * rad) + 0.24 * cos(2 * hm * rad) + 0.32 * cos((3 * hm + 6) * rad) - 0.20 * cos((4 * hm - 63) * rad)
        let dTheta = 30 * exp(-pow((hm - 275) / 25, 2))
        let rc = 2 * (pow(cmp, 7) / (pow(cmp, 7) + pow(25, 7))).squareRoot()
        let sl = 1 + 0.015 * pow(lm - 50, 2) / (20 + pow(lm - 50, 2)).squareRoot()
        let sc = 1 + 0.045 * cmp
        let sh = 1 + 0.015 * cmp * t
        let rt = -sin(2 * dTheta * rad) * rc
        let x = dL / sl, y = dC / sc, z = dH / sh
        return (x * x + y * y + z * z + rt * y * z).squareRoot()
    }

    public static func deltaE(_ a: String, _ b: String) -> Double? {
        guard let p = lab(a), let q = lab(b) else { return nil }
        return deltaE(p, q)
    }

    /// Palettes are stored dominant color first. Each later swatch costs a little, so an asset where the
    /// color dominates ranks above one where it is a small accent.
    public static let positionPenalty = 1.5

    /// Closest palette distance and a ranking score, or nil when the asset has no usable palette.
    public static func match(_ query: ColorQuery, palette: [String]) -> (distance: Double, score: Double)? {
        guard let q = lab(query.hex) else { return nil }
        var best: (Double, Double)?
        for (i, hex) in palette.prefix(8).enumerated() {
            guard let c = lab(hex) else { continue }
            let d = deltaE(q, c), s = d + Double(i) * positionPenalty
            if best == nil || s < best!.1 { best = (d, s) }
        }
        return best.map { (distance: $0.0, score: $0.1) }
    }

    public static func matches(_ query: ColorQuery, _ a: StudioAsset) -> Bool {
        guard let m = match(query, palette: a.palette) else { return false }
        return m.distance <= query.tolerance
    }

    /// Assets within tolerance, best first. Ties keep the incoming order.
    public static func rank(_ assets: [StudioAsset], _ query: ColorQuery) -> [StudioAsset] {
        assets.enumerated().compactMap { i, a -> (Int, StudioAsset, Double)? in
            guard let m = match(query, palette: a.palette), m.distance <= query.tolerance else { return nil }
            return (i, a, m.score)
        }
        .sorted { $0.2 == $1.2 ? $0.0 < $1.0 : $0.2 < $1.2 }
        .map(\.1)
    }

    /// Swatches offered in the picker: a spread of hues plus neutrals.
    public static let swatches = ["#E03131", "#F76707", "#FAB005", "#40C057", "#12B886", "#15AABF",
                                  "#4DABF7", "#364FC7", "#7048E8", "#E64980", "#8B5E3C", "#F1E9DA",
                                  "#868E96", "#212529", "#FFFFFF"]
}

extension StudioCatalog {
    public static let recentColorLimit = 6

    /// Most recent first, no repeats.
    public mutating func noteRecentColor(_ hex: String) {
        guard let h = ColorSearch.normalize(hex) else { return }
        recentColors.removeAll { $0 == h }
        recentColors.insert(h, at: 0)
        if recentColors.count > Self.recentColorLimit { recentColors.removeLast(recentColors.count - Self.recentColorLimit) }
    }
}
