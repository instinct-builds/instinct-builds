import Foundation
import Testing
@testable import AsssetsCore

@Suite("Find similar")
struct SimilarityTests {
    /// Diagonal gradient with a bright disc, drawn at any size.
    func scene(_ w: Int, _ h: Int, disc: (Double, Double) = (0.3, 0.4), tint: Int = 0, noise: Bool = false) -> PixelBuffer {
        var px = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h { for x in 0..<w {
            let u = Double(x) / Double(w), v = Double(y) / Double(h)
            var l = 40 + 120 * u + 60 * v
            if (u - disc.0) * (u - disc.0) + (v - disc.1) * (v - disc.1) < 0.04 { l = 245 }
            if noise { l += Double((x * 7 + y * 13) % 5) - 2 }
            let i = (y * w + x) * 4
            px[i] = UInt8(max(0, min(255, l + Double(tint)))); px[i + 1] = UInt8(max(0, min(255, l))); px[i + 2] = UInt8(max(0, min(255, l - Double(tint)))); px[i + 3] = 255
        } }
        return PixelBuffer(width: w, height: h, rgba: px)
    }

    @Test func hashSurvivesResizeAndSmallEdits() {
        let a = Similarity.dHash(scene(320, 240))
        #expect(Similarity.distance(a, Similarity.dHash(scene(97, 73))) <= Similarity.nearDuplicateBits)
        #expect(Similarity.distance(a, Similarity.dHash(scene(320, 240, tint: 12, noise: true))) <= Similarity.nearDuplicateBits)
        #expect(Similarity.distance(a, Similarity.dHash(scene(320, 240, disc: (0.75, 0.7)))) > Similarity.nearDuplicateBits)
    }

    @Test func paletteDistanceBasics() {
        #expect(Similarity.paletteDistance(["#FF0000", "#00FF00"], ["#00ff00", "#ff0000"]) == 0)
        #expect(Similarity.paletteDistance(["#000000"], ["#FFFFFF"]) > 0.99)
        #expect(Similarity.paletteDistance(["#FF0000"], ["#EE1111"]) < 0.1)
        #expect(Similarity.paletteDistance([], ["#FFFFFF"]) == 1)
    }

    @Test func rankingPutsNearCopiesFirst() {
        let base = Similarity.Signature(hash: Similarity.dHash(scene(200, 150)), palette: ["#303030", "#A0A0A0"])
        let copy = UUID(), mood = UUID(), other = UUID(), noHash = UUID()
        let others: [(UUID, Similarity.Signature)] = [
            (other, .init(hash: Similarity.dHash(scene(200, 150, disc: (0.8, 0.8))) ^ 0xFFFF_0000_FFFF_0000, palette: ["#FF00FF"])),
            (mood, .init(hash: Similarity.dHash(scene(200, 150, disc: (0.7, 0.3))), palette: ["#323232", "#9E9E9E"])),
            (copy, .init(hash: Similarity.dHash(scene(64, 48)), palette: ["#303030", "#A0A0A0"])),
            (noHash, .init(hash: nil, palette: ["#313131", "#A1A1A1"])),
        ]
        let r = Similarity.rank(base, among: others)
        #expect(r.first?.id == copy && r.first?.nearDuplicate == true)
        #expect(!r.contains { $0.id == other })
        #expect(r.contains { $0.id == noHash && !$0.nearDuplicate })
    }

    @Test func nearGroupsChain() {
        let ids = (0..<4).map { _ in UUID() }
        let g = Similarity.nearGroups(hashes: [ids[0]: 0b0, ids[1]: 0b111, ids[2]: 0b111111_111, ids[3]: UInt64.max], order: ids)
        #expect(g == [[ids[0], ids[1], ids[2]]])   // 0~1 (3 bits), 1~2 (6 bits), 0 and 2 differ by 9 but chain
    }
}
