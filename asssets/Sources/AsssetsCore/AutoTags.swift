import Foundation

/// Local, deterministic auto-tagging from palette, pixels and metadata (1.6). No network, no models.
public enum AutoTags {
    public struct Facts: Equatable, Sendable {
        public var kind: MediaKind
        public var palette: [String] = []
        public var width: Int? = nil
        public var height: Int? = nil
        public var hasAlpha = false
        public var tileable: Bool? = nil
        public var durationSeconds: Double? = nil
        public var loudnessDBFS: Double? = nil
        public init(kind: MediaKind, palette: [String] = [], width: Int? = nil, height: Int? = nil, hasAlpha: Bool = false,
                    tileable: Bool? = nil, durationSeconds: Double? = nil, loudnessDBFS: Double? = nil) {
            self.kind = kind; self.palette = palette; self.width = width; self.height = height; self.hasAlpha = hasAlpha
            self.tileable = tileable; self.durationSeconds = durationSeconds; self.loudnessDBFS = loudnessDBFS
        }
    }

    public static func suggest(_ f: Facts) -> [String] {
        var out: [String] = []
        func add(_ t: String) { if !out.contains(t) { out.append(t) } }
        if f.kind != .audio {
            let hsl = f.palette.compactMap(hsl)
            for name in f.palette.compactMap(colorName).prefix(3) { add(name) }
            if !hsl.isEmpty {
                let l = hsl.map(\.l).reduce(0, +) / Double(hsl.count)
                let chroma = hsl.map { $0.s * (1 - abs(2 * $0.l - 1)) }.reduce(0, +) / Double(hsl.count)
                if l < 0.32 { add("dark") } else if l > 0.72 { add("light") }
                if chroma > 0.38 { add("vivid") } else if chroma < 0.12 { add("muted") }
            }
        }
        if let w = f.width, let h = f.height, w > 0, h > 0 {
            let r = Double(w) / Double(h)
            add(abs(r - 1) <= 0.05 ? "square" : r > 1 ? "landscape" : "portrait")
            if max(w, h) >= 3840 { add("4k+") }
            // A4 or US Letter at 300 dpi, either orientation.
            if min(w, h) >= 2480 && max(w, h) >= 3300 { add("print-ready") }
            if max(w, h) < 800 { add("small") }
        }
        if f.hasAlpha { add("transparent") }
        if f.tileable == true { add("tileable") }
        if let d = f.durationSeconds {
            if d < 15 { add("short") } else if d > 60 { add("long") }
        }
        if let db = f.loudnessDBFS {
            if db < -30 { add("quiet") } else if db > -14 { add("loud") }
        }
        return out
    }

    /// Pixel dimensions from a resolution label like "PSD • 1600 × 1200 • 7 layers" or "2048 x 2048".
    public static func dimensions(in label: String) -> (Int, Int)? {
        let chars = Array(label)
        var i = 0
        while i < chars.count {
            if chars[i].isNumber {
                var j = i; while j < chars.count && chars[j].isNumber { j += 1 }
                var k = j; while k < chars.count && chars[k] == " " { k += 1 }
                if k < chars.count && (chars[k] == "×" || chars[k] == "x") {
                    var m = k + 1; while m < chars.count && chars[m] == " " { m += 1 }
                    var n = m; while n < chars.count && chars[n].isNumber { n += 1 }
                    if n > m, let w = Int(String(chars[i..<j])), let h = Int(String(chars[m..<n])) { return (w, h) }
                }
                i = j
            } else { i += 1 }
        }
        return nil
    }

    /// Plain color names designers search for: "teal", "warm neutral", "charcoal" and so on.
    public static func colorName(_ hex: String) -> String? {
        guard let c = hsl(hex) else { return nil }
        let chroma = c.s * (1 - abs(2 * c.l - 1))
        if c.l < 0.1 { return "black" }
        if c.l > 0.93 && chroma < 0.12 { return "white" }
        if chroma < 0.1 || c.s < 0.3 {
            if c.l < 0.28 { return "charcoal" }
            let warm = c.s > 0.04 && (c.h < 60 || c.h >= 330)
            let cool = c.s > 0.04 && c.h >= 180 && c.h < 260
            return warm ? "warm neutral" : cool ? "cool gray" : "gray"
        }
        switch c.h {
        case ..<15, 345...: return c.l > 0.7 ? "pink" : "red"
        case 15..<40: return c.l < 0.45 ? "brown" : "orange"
        case 40..<52: return c.l < 0.45 ? "olive" : c.l > 0.75 ? "cream" : "gold"
        case 52..<70: return c.l < 0.4 ? "olive" : "yellow"
        case 70..<160: return "green"
        case 160..<195: return "teal"
        case 195..<250: return c.l < 0.3 ? "navy" : "blue"
        case 250..<290: return "purple"
        default: return "magenta"
        }
    }

    public static func hsl(_ hex: String) -> (h: Double, s: Double, l: Double)? {
        guard let (r0, g0, b0) = Similarity.rgb(hex) else { return nil }
        let r = r0 / 255, g = g0 / 255, b = b0 / 255
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        let l = (mx + mn) / 2
        guard d > 0.0001 else { return (0, 0, l) }
        let s = d / (1 - abs(2 * l - 1))
        var h: Double
        switch mx {
        case r: h = ((g - b) / d).truncatingRemainder(dividingBy: 6)
        case g: h = (b - r) / d + 2
        default: h = (r - g) / d + 4
        }
        h *= 60; if h < 0 { h += 360 }
        return (h, min(1, s), l)
    }
}

extension StudioCatalog {
    /// Replaces an asset's computed tags. Returns true when they changed.
    @discardableResult
    public mutating func setAutoTags(_ tags: [String], for id: UUID) -> Bool {
        guard let i = assets.firstIndex(where: { $0.id == id }), assets[i].autoTags != tags else { return false }
        assets[i].autoTags = tags
        return true
    }

    /// Accept suggestions: they become real tags.
    public mutating func acceptSuggestions(_ tags: [String]? = nil, for ids: Set<UUID>) {
        for i in assets.indices where ids.contains(assets[i].id) {
            for t in tags ?? assets[i].suggestedTags where assets[i].suggestedTags.contains(t) { assets[i].tags.append(t) }
        }
    }

    /// Dismiss a suggestion for good on these assets.
    public mutating func rejectSuggestion(_ tag: String, for ids: Set<UUID>) {
        for i in assets.indices where ids.contains(assets[i].id) && !assets[i].rejectedTags.contains(tag) { assets[i].rejectedTags.append(tag) }
    }
}
