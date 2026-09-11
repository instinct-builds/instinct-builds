import Foundation

public struct PaletteColor: Codable, Equatable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    public var weight: Double // share of sampled pixels, 0..1

    public init(r: UInt8, g: UInt8, b: UInt8, weight: Double) {
        self.r = r; self.g = g; self.b = b; self.weight = weight
    }

    public var hex: String { String(format: "#%02X%02X%02X", r, g, b) }
}

/// Dominant-color extraction by median-cut quantization over sampled pixels.
/// Deterministic; transparent pixels are ignored.
public enum PaletteExtractor {

    public static func colors(from img: PixelBuffer, count: Int = 6) -> [PaletteColor] {
        guard count > 0, img.width > 0, img.height > 0 else { return [] }
        let total = img.width * img.height
        let step = max(1, total / 16384) // sample at most ~16k pixels
        var pixels: [(r: Int, g: Int, b: Int)] = []
        pixels.reserveCapacity(min(total, 16384))
        var idx = 0
        while idx < total {
            let o = idx * 4
            if img.rgba[o + 3] > 16 {
                pixels.append((Int(img.rgba[o]), Int(img.rgba[o + 1]), Int(img.rgba[o + 2])))
            }
            idx += step
        }
        guard !pixels.isEmpty else { return [] }

        var buckets = [pixels]
        while buckets.count < count {
            // Split the bucket with the widest single-channel range.
            var best = -1, bestRange = 0, bestChan = 0
            for (bi, bucket) in buckets.enumerated() where bucket.count > 1 {
                var mins = (r: 255, g: 255, b: 255), maxs = (r: 0, g: 0, b: 0)
                for p in bucket {
                    mins.r = min(mins.r, p.r); maxs.r = max(maxs.r, p.r)
                    mins.g = min(mins.g, p.g); maxs.g = max(maxs.g, p.g)
                    mins.b = min(mins.b, p.b); maxs.b = max(maxs.b, p.b)
                }
                let ranges = [maxs.r - mins.r, maxs.g - mins.g, maxs.b - mins.b]
                for ch in 0..<3 where ranges[ch] > bestRange {
                    bestRange = ranges[ch]
                    best = bi
                    bestChan = ch
                }
            }
            guard best >= 0 else { break }
            var bucket = buckets[best]
            switch bestChan {
            case 0: bucket.sort { $0.r < $1.r }
            case 1: bucket.sort { $0.g < $1.g }
            default: bucket.sort { $0.b < $1.b }
            }
            let mid = bucket.count / 2
            buckets[best] = Array(bucket[0..<mid])
            buckets.append(Array(bucket[mid...]))
        }

        return buckets.map { bucket -> PaletteColor in
            var r = 0, g = 0, b = 0
            for p in bucket { r += p.r; g += p.g; b += p.b }
            let n = bucket.count
            return PaletteColor(r: UInt8(r / n), g: UInt8(g / n), b: UInt8(b / n),
                                weight: Double(n) / Double(pixels.count))
        }.sorted { $0.weight > $1.weight }
    }
}
