import Foundation
import Testing
@testable import AsssetsCore

@Suite("Brand kit")
struct BrandKitTests {
    @Test func aseBytes() {
        let d = BrandKit.ase([.init(name: "Ink", hex: "#FF8000"), .init(name: "bad", hex: "nope")])
        let b = [UInt8](d)
        #expect(Array(b[0..<4]) == Array("ASEF".utf8))
        #expect(Array(b[4..<8]) == [0, 1, 0, 0])
        #expect(Array(b[8..<12]) == [0, 0, 0, 1])                  // invalid hex skipped
        #expect(Array(b[12..<14]) == [0, 1])                       // color entry
        let len = Int(b[14]) << 24 | Int(b[15]) << 16 | Int(b[16]) << 8 | Int(b[17])
        #expect(len == 2 + 4 * 2 + 4 + 12 + 2)
        #expect(b.count == 18 + len)
        #expect(Array(b[18..<20]) == [0, 4])                       // "Ink" + null in UTF-16
        #expect(Array(b[20..<28]) == [0, 73, 0, 110, 0, 107, 0, 0])
        #expect(Array(b[28..<32]) == Array("RGB ".utf8))
        let r = UInt32(b[32]) << 24 | UInt32(b[33]) << 16 | UInt32(b[34]) << 8 | UInt32(b[35])
        #expect(Float(bitPattern: r) == 1)
        #expect(Array(b[(b.count - 2)...]) == [0, 2])
    }

    @Test func jsonSwatches() throws {
        let d = BrandKit.swatchJSON(title: "Kit", [.init(name: "A", hex: "#abcdef")])
        let o = try JSONSerialization.jsonObject(with: d) as! [String: Any]
        #expect(o["name"] as? String == "Kit")
        #expect(((o["colors"] as! [[String: String]])[0]["hex"]) == "#ABCDEF")
    }

    @Test func combinedPaletteVotes() {
        let p = BrandKit.combinedPalette([["#101010", "#FF0000"], ["#121212", "#00FF00"], ["#111111", "#0000FF"]], count: 3)
        #expect(p.first == "#101010")       // three near-blacks merge into the first seen
        #expect(p == ["#101010", "#FF0000", "#00FF00"])
    }

    @Test func layoutPaginates() {
        let s = BrandKit.layout(count: 13)
        #expect(s.pages.map(\.count) == [12, 1])
        #expect(s.totalPages == 3)
        let last = s.pages[0][11]
        #expect(last.x + last.w <= 792 - 36 + 0.001 && last.y + last.h <= 612 - 36 + 0.001)
        #expect(s.pages[0][1].x > s.pages[0][0].x && s.pages[0][4].y > s.pages[0][0].y)
        #expect(BrandKit.layout(count: 0).pages.isEmpty)
        #expect(BrandKit.kitName("Warm / Palettes") == "Warm - Palettes Brand Kit")
    }
}
