import Foundation

/// Header-level metadata extraction, parsed directly from file bytes.
/// No platform image APIs — this runs anywhere.
public enum MetadataReader {

    public static func dimensions(for path: String, kind: AssetKind) -> (Int, Int)? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        switch kind {
        case .image:
            return pngDimensions(data) ?? jpegDimensions(data) ?? gifDimensions(data)
        case .vector:
            return svgDimensions(data)
        case .psd:
            return psdDimensions(data)
        default:
            return nil
        }
    }

    /// PNG: 8-byte signature, then IHDR length(4) "IHDR" width(4) height(4), big-endian.
    public static func pngDimensions(_ d: Data) -> (Int, Int)? {
        let sig: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard d.count >= 24, d.prefix(8).elementsEqual(sig) else { return nil }
        guard d[12...15] == Data("IHDR".utf8) else { return nil }
        let w = Int(bigEndian32(d, at: 16))
        let h = Int(bigEndian32(d, at: 20))
        return w > 0 && h > 0 ? (w, h) : nil
    }

    /// JPEG: scan markers for a Start-Of-Frame (C0-CF except C4, C8, CC).
    public static func jpegDimensions(_ d: Data) -> (Int, Int)? {
        guard d.count > 4, d[0] == 0xFF, d[1] == 0xD8 else { return nil }
        var i = 2
        while i + 9 < d.count {
            guard d[i] == 0xFF else { i += 1; continue }
            let marker = d[i + 1]
            if marker == 0xD8 || marker == 0x01 || (0xD0...0xD7).contains(marker) { i += 2; continue }
            let len = Int(bigEndian16(d, at: i + 2))
            if len < 2 { return nil }
            if (0xC0...0xCF).contains(marker), marker != 0xC4, marker != 0xC8, marker != 0xCC {
                let h = Int(bigEndian16(d, at: i + 5))
                let w = Int(bigEndian16(d, at: i + 7))
                return w > 0 && h > 0 ? (w, h) : nil
            }
            i += 2 + len
        }
        return nil
    }

    /// GIF: "GIF8", width/height little-endian at bytes 6-9.
    public static func gifDimensions(_ d: Data) -> (Int, Int)? {
        guard d.count >= 10, d.prefix(3) == Data("GIF".utf8) else { return nil }
        let w = Int(d[6]) | Int(d[7]) << 8
        let h = Int(d[8]) | Int(d[9]) << 8
        return w > 0 && h > 0 ? (w, h) : nil
    }

    /// PSD: "8BPS", version, 6 reserved bytes, channels(2), height(4), width(4) big-endian.
    public static func psdDimensions(_ d: Data) -> (Int, Int)? {
        guard d.count >= 26, d.prefix(4) == Data("8BPS".utf8) else { return nil }
        let h = Int(bigEndian32(d, at: 14))
        let w = Int(bigEndian32(d, at: 18))
        return w > 0 && h > 0 ? (w, h) : nil
    }

    /// SVG: width/height attributes, or the viewBox fallback.
    public static func svgDimensions(_ d: Data) -> (Int, Int)? {
        guard d.count < 10_000_000, var s = String(data: d, encoding: .utf8) else { return nil }
        s = String(s.prefix(100_000)) // header region is plenty
        guard s.contains("<svg") else { return nil }
        if let w = svgAttr("width", in: s), let h = svgAttr("height", in: s) {
            return (w, h)
        }
        if let vb = svgAttrString("viewBox", in: s) {
            let parts = vb.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) }
            if parts.count == 4, parts[2] > 0, parts[3] > 0 {
                return (Int(parts[2]), Int(parts[3]))
            }
        }
        return nil
    }

    private static func svgAttr(_ name: String, in s: String) -> Int? {
        guard let str = svgAttrString(name, in: s) else { return nil }
        let numeric = str.replacingOccurrences(of: "px", with: "")
        return Double(numeric).map { Int($0) }
    }

    private static func svgAttrString(_ name: String, in s: String) -> String? {
        guard let r = s.range(of: "\(name)=\"") else { return nil }
        let rest = s[r.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<end])
    }

    private static func bigEndian32(_ d: Data, at i: Int) -> UInt32 {
        (UInt32(d[i]) << 24) | (UInt32(d[i+1]) << 16) | (UInt32(d[i+2]) << 8) | UInt32(d[i+3])
    }
    private static func bigEndian16(_ d: Data, at i: Int) -> UInt16 {
        (UInt16(d[i]) << 8) | UInt16(d[i+1])
    }
}
