import Foundation

// MARK: - Audio waveform peaks from real WAV data

public struct WaveformSummary: Equatable, Sendable {
    public var peaks: [Float]        // 0...1, one per bucket
    public var sampleRate: Int
    public var channels: Int
    public var bitsPerSample: Int
    public var duration: Double      // seconds
}

public enum Waveform {
    /// Reads a PCM (16/24/32-bit int) or 32-bit float WAV and returns normalized peak buckets.
    /// Walks RIFF chunks, so LIST/INFO chunks before `data` are skipped correctly.
    public static func summarize(wav data: Data, buckets: Int = 96) -> WaveformSummary? {
        let bytes = [UInt8](data)
        guard buckets > 0, bytes.count >= 12, String(bytes: bytes[0..<4], encoding: .ascii) == "RIFF",
              String(bytes: bytes[8..<12], encoding: .ascii) == "WAVE" else { return nil }
        func u16(_ o: Int) -> Int { Int(bytes[o]) | Int(bytes[o + 1]) << 8 }
        func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
        var format = 0, channels = 0, rate = 0, bits = 0
        var dataRange: Range<Int>?
        var o = 12
        while o + 8 <= bytes.count {
            let id = String(bytes: bytes[o..<o + 4], encoding: .ascii) ?? ""
            let size = u32(o + 4)
            let body = o + 8
            if id == "fmt ", body + 16 <= bytes.count {
                format = u16(body); channels = u16(body + 2); rate = u32(body + 4); bits = u16(body + 14)
                if format == 0xFFFE, size >= 26, body + 26 <= bytes.count { format = u16(body + 24) } // WAVE_FORMAT_EXTENSIBLE
            } else if id == "data" {
                dataRange = body..<min(bytes.count, body + size)
            }
            o = body + size + (size & 1)
        }
        guard let range = dataRange, channels > 0, rate > 0, [16, 24, 32].contains(bits), format == 1 || (format == 3 && bits == 32) else { return nil }
        let frameBytes = channels * bits / 8
        let frames = range.count / frameBytes
        guard frames > 0 else { return nil }
        func sample(_ at: Int) -> Float {
            switch (format, bits) {
            case (3, 32):
                let raw = UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 | UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24
                return Float(bitPattern: raw)
            case (_, 16): return Float(Int16(bitPattern: UInt16(u16(at)))) / 32768
            case (_, 24):
                var v = Int32(bytes[at]) | Int32(bytes[at + 1]) << 8 | Int32(bytes[at + 2]) << 16
                if v & 0x800000 != 0 { v |= ~0xFFFFFF }
                return Float(v) / 8_388_608
            default:
                return Float(Int32(bitPattern: UInt32(u32(at)))) / 2_147_483_648
            }
        }
        var peaks = [Float](repeating: 0, count: buckets)
        let step = max(1, frames / (buckets * 256))          // sparse scan keeps long files fast
        var f = 0
        while f < frames {
            let b = min(buckets - 1, f * buckets / frames)
            for c in 0..<channels {
                let v = abs(sample(range.lowerBound + f * frameBytes + c * bits / 8))
                if v > peaks[b] { peaks[b] = v }
            }
            f += step
        }
        let top = peaks.max() ?? 0
        if top > 0 { peaks = peaks.map { min(1, $0 / top) } }
        return WaveformSummary(peaks: peaks, sampleRate: rate, channels: channels, bitsPerSample: bits, duration: Double(frames) / Double(rate))
    }
}

// MARK: - Minimal SVG scene for native vector previews

/// A small, dependency-free SVG reader covering what ASSSETS ships and common flat artwork:
/// rect, circle, ellipse, polygon, M/L/H/V/Z paths, linear gradients and text.
public struct VectorScene: Equatable, Sendable {
    public enum Fill: Equatable, Sendable { case color(String), gradient([String]), none }
    public enum Shape: Equatable, Sendable {
        case rect(x: Double, y: Double, width: Double, height: Double)
        case ellipse(cx: Double, cy: Double, rx: Double, ry: Double)
        case polygon([Point])
        case text(x: Double, y: Double, size: Double, string: String)
    }
    public struct Point: Equatable, Sendable { public var x: Double, y: Double }
    public struct Element: Equatable, Sendable { public var shape: Shape; public var fill: Fill; public var opacity: Double }

    public var width: Double
    public var height: Double
    public var elements: [Element]

    public static func parse(_ svg: String) -> VectorScene? {
        guard let root = firstTag("svg", in: svg) else { return nil }
        let a = attributes(root)
        var w = number(a["width"]), h = number(a["height"])
        if let vb = a["viewBox"]?.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap({ Double($0) }), vb.count == 4 {
            w = w ?? vb[2]; h = h ?? vb[3]
        }
        guard let width = w, let height = h, width > 0, height > 0 else { return nil }
        var gradients: [String: [String]] = [:]
        for g in blocks("linearGradient", in: svg) {
            if let id = attributes(g.open)["id"] {
                gradients[id] = tags("stop", in: g.body).compactMap { attributes($0)["stop-color"].flatMap(normalizeHex) }
            }
        }
        var els: [Element] = []
        for tag in shapeTags(in: svg) {
            let at = attributes(tag.open)
            let op = Double(at["opacity"] ?? "") ?? 1
            let fill: Fill = {
                guard let f = at["fill"] else { return .color("#000000") }
                if f == "none" { return .none }
                if f.hasPrefix("url(#"), let id = f.dropFirst(5).split(separator: ")").first, let stops = gradients[String(id)] { return .gradient(stops) }
                if f == "white" { return .color("#FFFFFF") }
                if f == "black" { return .color("#000000") }
                return normalizeHex(f).map { .color($0) } ?? .color("#000000")
            }()
            switch tag.name {
            case "rect":
                els.append(Element(shape: .rect(x: number(at["x"]) ?? 0, y: number(at["y"]) ?? 0, width: number(at["width"]) ?? 0, height: number(at["height"]) ?? 0), fill: fill, opacity: op))
            case "circle":
                let r = number(at["r"]) ?? 0
                els.append(Element(shape: .ellipse(cx: number(at["cx"]) ?? 0, cy: number(at["cy"]) ?? 0, rx: r, ry: r), fill: fill, opacity: op))
            case "ellipse":
                els.append(Element(shape: .ellipse(cx: number(at["cx"]) ?? 0, cy: number(at["cy"]) ?? 0, rx: number(at["rx"]) ?? 0, ry: number(at["ry"]) ?? 0), fill: fill, opacity: op))
            case "polygon":
                let v = (at["points"] ?? "").split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) }
                let pts = stride(from: 0, to: v.count - 1, by: 2).map { Point(x: v[$0], y: v[$0 + 1]) }
                if pts.count >= 3 { els.append(Element(shape: .polygon(pts), fill: fill, opacity: op)) }
            case "path":
                for poly in pathPolygons(at["d"] ?? "") where poly.count >= 3 { els.append(Element(shape: .polygon(poly), fill: fill, opacity: op)) }
            case "text":
                let s = decodeEntities(tag.body.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))
                els.append(Element(shape: .text(x: number(at["x"]) ?? 0, y: number(at["y"]) ?? 0, size: number(at["font-size"]) ?? 16, string: s), fill: fill, opacity: op))
            default: break
            }
        }
        return VectorScene(width: width, height: height, elements: els)
    }

    /// Absolute and relative M/L/H/V/Z commands; each subpath becomes a polygon.
    static func pathPolygons(_ d: String) -> [[Point]] {
        var tokens: [String] = [], cur = ""
        for ch in d {
            if ch.isLetter { if !cur.isEmpty { tokens.append(cur); cur = "" }; tokens.append(String(ch)) }
            else if ch == " " || ch == "," { if !cur.isEmpty { tokens.append(cur); cur = "" } }
            else if ch == "-" && !cur.isEmpty && cur.last != "e" { tokens.append(cur); cur = "-" }
            else { cur.append(ch) }
        }
        if !cur.isEmpty { tokens.append(cur) }
        var out: [[Point]] = [], poly: [Point] = [], cmd = "M", x = 0.0, y = 0.0, i = 0
        func num() -> Double? { guard i < tokens.count, let v = Double(tokens[i]) else { return nil }; i += 1; return v }
        while i < tokens.count {
            if let c = tokens[i].first, c.isLetter { cmd = String(c); i += 1; if cmd == "Z" || cmd == "z" { if !poly.isEmpty { out.append(poly); poly = [] }; continue } }
            let rel = cmd == cmd.lowercased()
            switch cmd.uppercased() {
            case "M", "L":
                guard let a = num(), let b = num() else { i += 1; continue }
                x = rel ? x + a : a; y = rel ? y + b : b
                if cmd.uppercased() == "M" && !poly.isEmpty { out.append(poly); poly = [] }
                poly.append(Point(x: x, y: y))
                if cmd == "M" { cmd = "L" } else if cmd == "m" { cmd = "l" }
            case "H": guard let a = num() else { i += 1; continue }; x = rel ? x + a : a; poly.append(Point(x: x, y: y))
            case "V": guard let b = num() else { i += 1; continue }; y = rel ? y + b : b; poly.append(Point(x: x, y: y))
            default: i += 1   // curves and arcs are skipped in this lightweight preview
            }
        }
        if !poly.isEmpty { out.append(poly) }
        return out
    }

    // MARK: tiny tag scanner

    struct Tag { var name: String; var open: String; var body: String }

    static func firstTag(_ name: String, in s: String) -> String? {
        guard let r = s.range(of: "<\(name)[\\s>]", options: .regularExpression), let end = s[r.lowerBound...].firstIndex(of: ">") else { return nil }
        return String(s[r.lowerBound...end])
    }
    static func tags(_ name: String, in s: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: "<\(name)\\b[^>]*>") else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }
    static func blocks(_ name: String, in s: String) -> [(open: String, body: String)] {
        guard let re = try? NSRegularExpression(pattern: "(<\(name)\\b[^>]*>)(.*?)</\(name)>", options: [.dotMatchesLineSeparators]) else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { (ns.substring(with: $0.range(at: 1)), ns.substring(with: $0.range(at: 2))) }
    }
    static func shapeTags(in s: String) -> [Tag] {
        // Skip gradient definitions so their children never render as shapes.
        let stripped = s.replacingOccurrences(of: "<defs\\b.*?</defs>", with: "", options: [.regularExpression])
        guard let re = try? NSRegularExpression(pattern: "<(rect|circle|ellipse|polygon|path)\\b[^>]*>|<text\\b[^>]*>.*?</text>", options: [.dotMatchesLineSeparators]) else { return [] }
        let ns = stripped as NSString
        return re.matches(in: stripped, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            let whole = ns.substring(with: m.range)
            if whole.hasPrefix("<text") {
                guard let close = whole.firstIndex(of: ">") else { return nil }
                let body = whole[whole.index(after: close)...].replacingOccurrences(of: "</text>", with: "")
                return Tag(name: "text", open: String(whole[...close]), body: body)
            }
            return Tag(name: ns.substring(with: m.range(at: 1)), open: whole, body: "")
        }
    }
    static func attributes(_ tag: String) -> [String: String] {
        guard let re = try? NSRegularExpression(pattern: "([A-Za-z_:][-A-Za-z0-9_:.]*)\\s*=\\s*(\"([^\"]*)\"|'([^']*)')") else { return [:] }
        let ns = tag as NSString
        var out: [String: String] = [:]
        for m in re.matches(in: tag, range: NSRange(location: 0, length: ns.length)) {
            let key = ns.substring(with: m.range(at: 1))
            let r = m.range(at: 3).location != NSNotFound ? m.range(at: 3) : m.range(at: 4)
            out[key] = ns.substring(with: r)
        }
        return out
    }
    static func number(_ s: String?) -> Double? {
        guard let s else { return nil }
        return Double(s.replacingOccurrences(of: "px", with: "").trimmingCharacters(in: .whitespaces))
    }
    static func normalizeHex(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        guard s.hasPrefix("#") else { return nil }
        s.removeFirst()
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, UInt64(s, radix: 16) != nil else { return nil }
        return "#" + s.uppercased()
    }
    static func decodeEntities(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&quot;", with: "\"")
    }

    /// Distinct fill colors in paint order, handy for palettes.
    public var colors: [String] {
        var out: [String] = []
        for e in elements {
            switch e.fill {
            case .color(let c): if !out.contains(c) { out.append(c) }
            case .gradient(let cs): for c in cs where !out.contains(c) { out.append(c) }
            case .none: break
            }
        }
        return out
    }
}
