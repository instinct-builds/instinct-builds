import Foundation

/// "Find Similar": a perceptual difference hash for near-identical images, plus palette distance for mood.
public enum Similarity {
    /// 64-bit difference hash: 9x8 grayscale grid, each bit says whether a cell is brighter than its right neighbour.
    /// Survives resizing, recompression and small edits; changes a lot for different pictures.
    public static func dHash(_ img: PixelBuffer) -> UInt64 {
        guard img.width > 0, img.height > 0 else { return 0 }
        var grid = [Double](repeating: 0, count: 9 * 8)
        for gy in 0..<8 {
            let y0 = gy * img.height / 8, y1 = max(y0 + 1, (gy + 1) * img.height / 8)
            for gx in 0..<9 {
                let x0 = gx * img.width / 9, x1 = max(x0 + 1, (gx + 1) * img.width / 9)
                var sum = 0.0, n = 0.0
                var y = y0
                while y < min(y1, img.height) {
                    var x = x0
                    while x < min(x1, img.width) {
                        let p = img.pixel(x: x, y: y)
                        let a = Double(p.a) / 255
                        // Transparent pixels count as white so cut-out art hashes like it looks on a page.
                        let lum = 0.299 * Double(p.r) + 0.587 * Double(p.g) + 0.114 * Double(p.b)
                        sum += lum * a + 255 * (1 - a); n += 1
                        x += 1
                    }
                    y += 1
                }
                grid[gy * 9 + gx] = n > 0 ? sum / n : 0
            }
        }
        var h: UInt64 = 0
        for gy in 0..<8 { for gx in 0..<8 {
            h <<= 1
            if grid[gy * 9 + gx] > grid[gy * 9 + gx + 1] { h |= 1 }
        } }
        return h
    }

    public static func distance(_ a: UInt64, _ b: UInt64) -> Int { (a ^ b).nonzeroBitCount }

    /// Near-identical when at most this many of the 64 bits differ.
    public static let nearDuplicateBits = 6

    /// 0 = same colors, 1 = opposite. Symmetric average of each color's nearest match in the other palette.
    public static func paletteDistance(_ a: [String], _ b: [String]) -> Double {
        let pa = a.compactMap(rgb), pb = b.compactMap(rgb)
        guard !pa.isEmpty, !pb.isEmpty else { return 1 }
        func oneWay(_ x: [(Double, Double, Double)], _ y: [(Double, Double, Double)]) -> Double {
            x.map { c in y.map { d in ((c.0 - d.0) * (c.0 - d.0) + (c.1 - d.1) * (c.1 - d.1) + (c.2 - d.2) * (c.2 - d.2)).squareRoot() }.min()! }
                .reduce(0, +) / Double(x.count)
        }
        return min(1, (oneWay(pa, pb) + oneWay(pb, pa)) / 2 / 441.673)
    }

    public struct Signature: Equatable, Sendable {
        public var hash: UInt64?
        public var palette: [String]
        public init(hash: UInt64?, palette: [String]) { self.hash = hash; self.palette = palette }
    }

    public struct Match: Equatable, Sendable {
        public var id: UUID
        public var score: Double      // 0...1, higher is more alike
        public var nearDuplicate: Bool
    }

    /// Everything ranked by likeness to `target`: 70% structure (hash), 30% palette; palette only when a hash is missing.
    public static func rank(_ target: Signature, among others: [(UUID, Signature)], limit: Int = 24, minScore: Double = 0.55) -> [Match] {
        let matches: [Match] = others.map { id, s in
            let pal = 1 - paletteDistance(target.palette, s.palette)
            if let a = target.hash, let b = s.hash {
                let d = distance(a, b)
                return Match(id: id, score: 0.7 * (1 - Double(d) / 64) + 0.3 * pal, nearDuplicate: d <= nearDuplicateBits)
            }
            return Match(id: id, score: 0.85 * pal, nearDuplicate: false)
        }
        return Array(matches.filter { $0.score >= minScore || $0.nearDuplicate }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.id.uuidString < $1.id.uuidString }
            .prefix(limit))
    }

    /// Groups of near-identical images (single-link: A~B and B~C puts all three together), in catalog order.
    public static func nearGroups(hashes: [UUID: UInt64], order: [UUID], maxBits: Int = nearDuplicateBits) -> [[UUID]] {
        let ids = order.filter { hashes[$0] != nil }
        var parent = Dictionary(uniqueKeysWithValues: ids.map { ($0, $0) })
        func find(_ x: UUID) -> UUID { var r = x; while parent[r]! != r { r = parent[r]! }; parent[x] = r; return r }
        for i in ids.indices { for j in ids.indices where j > i {
            if distance(hashes[ids[i]]!, hashes[ids[j]]!) <= maxBits { parent[find(ids[j])] = find(ids[i]) }
        } }
        var groups: [UUID: [UUID]] = [:]
        for id in ids { groups[find(id), default: []].append(id) }
        let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        return groups.values.filter { $0.count > 1 }.sorted { rank[$0[0]]! < rank[$1[0]]! }
    }

    static func rgb(_ hex: String) -> (Double, Double, Double)? {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        return (Double((v >> 16) & 0xFF), Double((v >> 8) & 0xFF), Double(v & 0xFF))
    }
}
