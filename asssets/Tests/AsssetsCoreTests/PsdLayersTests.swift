import Testing
import Foundation
@testable import AsssetsCore

private func solid(_ name: String, _ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: (UInt8, UInt8, UInt8, UInt8),
                   opacity: UInt8 = 255, blend: String = "norm", hidden: Bool = false) -> PsdLayer {
    var px = [UInt8](); for _ in 0..<(w * h) { px += [c.0, c.1, c.2, c.3] }
    return PsdLayer(name: name, top: y, left: x, bottom: y + h, right: x + w, opacity: opacity, hidden: hidden, blendKey: blend, rgba: px)
}

@Suite("PSD layers")
struct PsdLayersTests {
    let doc = PsdDocument(width: 8, height: 6, layers: [
        solid("Background", 0, 0, 8, 6, (200, 100, 50, 255)),
        solid("Alt Background", 0, 0, 8, 6, (10, 20, 30, 255), hidden: true),
        solid("Shade", 2, 1, 4, 3, (128, 128, 128, 255), blend: "mul "),
        solid("Half White", 4, 2, 4, 4, (255, 255, 255, 255), opacity: 128),
        solid("Ünïcode Läyer ✦", 7, 5, 1, 1, (0, 255, 0, 255)),
    ])

    @Test func writeReadRoundTripKeepsEverything() throws {
        let back = try PsdLayers.read(PsdWriter.write(doc))
        #expect(back == doc)
        #expect(back.panelLayers.first?.layer.name == "Ünïcode Läyer ✦")    // top of the panel first
        #expect(back.panelLayers.last?.layer.name == "Background")
        #expect(back.layers[2].blendName == "Multiply")
    }

    @Test func compositeBlendsAndRespectsVisibility() {
        let c = doc.composite()
        #expect(c.pixel(x: 0, y: 0) == (200, 100, 50, 255))                   // hidden layer ignored
        let m = c.pixel(x: 2, y: 1)                                            // multiply by 50% gray
        #expect(m.r == 100 && m.g == 50 && abs(Int(m.b) - 25) <= 1)
        let h = c.pixel(x: 7, y: 2)                                            // 50% white over background
        #expect(abs(Int(h.r) - 228) <= 1 && abs(Int(h.g) - 178) <= 1)
        #expect(c.pixel(x: 7, y: 5) == (0, 255, 0, 255))
        let alt = doc.composite(toggled: [1, 4])                               // show hidden, hide the top
        #expect(alt.pixel(x: 0, y: 0) == (10, 20, 30, 255))
        #expect(alt.pixel(x: 7, y: 5).g != 255)
    }

    @Test func flattenedCompositeMatchesForOtherReaders() throws {
        let data = PsdWriter.write(doc)
        let flat = try PsdDecoder.decode(data)
        let ours = doc.composite(background: (255, 255, 255, 255))
        for i in stride(from: 0, to: ours.rgba.count, by: 4) { #expect(ours.rgba[i] == flat.rgba[i] && ours.rgba[i + 2] == flat.rgba[i + 2]) }
    }

    @Test func packBitsRoundTrip() {
        let rows: [[UInt8]] = [[], [7], [1, 1, 1, 1, 1], Array(0..<200).map { UInt8($0 % 3) }, [UInt8](repeating: 9, count: 300), [1, 2, 2, 3, 3, 3, 4]]
        for row in rows {
            let enc = PsdWriter.packBits(row)
            #expect(PsdDecoder.packBitsDecode(enc, expected: row.count) == row)
        }
    }

    @Test func flatOnlyPsdReadsAsSingleBackground() throws {
        // Existing fixture style: composite only, no layer section.
        var b: [UInt8] = Array("8BPS".utf8) + [0, 1, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 2, 0, 0, 0, 2, 0, 8, 0, 3]
        b += [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        b += [10, 10, 10, 10, 20, 20, 20, 20, 30, 30, 30, 30]
        let doc = try PsdLayers.read(Data(b))
        #expect(doc.layers.count == 1 && doc.layers[0].name == "Background")
        #expect(doc.composite().pixel(x: 1, y: 1) == (10, 20, 30, 255))
    }

    @Test func rejectsWhatItCannotRead() {
        #expect(throws: PsdLayers.ReadError.notPsd) { try PsdLayers.read(Data("nope".utf8)) }
        #expect(throws: (any Error).self) { try PsdLayers.read(Data(Array("8BPS".utf8) + [0, 1])) }
    }

    @Test func bundledMockupsAreLayeredAndToggleable() throws {
        for name in MockupFactory.names {
            let doc = try #require(MockupFactory.make(name, width: 160, height: 120))
            #expect(doc.layers.count >= 6, "\(name)")
            #expect(doc.layers.contains { $0.name.contains("Smart Object") }, "\(name)")
            #expect(doc.layers.contains { $0.blendKey != "norm" }, "\(name)")
            let back = try PsdLayers.read(PsdWriter.write(doc))
            #expect(back.layers.map(\.name) == doc.layers.map(\.name))
            #expect(StarterCatalog.describe(filename: name)?.collection == "Device Mockups")
        }
        let phone = try #require(MockupFactory.make("phone-screen-mockup.psd", width: 160, height: 120))
        let sand = try #require(phone.layers.firstIndex { $0.hidden })
        #expect(phone.composite().pixel(x: 4, y: 4) != phone.composite(toggled: [sand]).pixel(x: 4, y: 4))
        #expect(MockupFactory.make("unknown.psd") == nil)
    }
}
