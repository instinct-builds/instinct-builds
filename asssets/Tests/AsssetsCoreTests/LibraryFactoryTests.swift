import Testing
import Foundation
@testable import AsssetsCore

@Suite("Generated library")
struct LibraryFactoryTests {
    static let existingStarter = ["ink-fiber-4k.png", "concrete-dust-4k.png", "night-grid-4k.png", "prismatic-foil-4k.png", "paper-grain-4k.png",
                                  "blueprint-4k.png", "sandstone-4k.png", "risograph-4k.png", "device-stage-mockup.png", "cosmetic-plinth-mockup.png",
                                  "folded-poster-mockup.png", "album-gatefold-mockup.png", "ambient-bed.wav", "motion-loop-01.mp4", "motion-loop-02.mp4"]
        + (1...12).map { String(format: "editorial-vector-%02d.svg", $0) }

    @Test func namesAreUniqueAndFileAsExpected() {
        let generated = MockupFactory.names + TextureFactory.names + VectorFactory.names
        #expect(generated.count == 30)
        #expect(Set(generated).count == generated.count)
        #expect(Set(generated).isDisjoint(with: Self.existingStarter))
        #expect(Self.existingStarter.count + generated.count == 57)
        for n in MockupFactory.names { #expect(StarterCatalog.describe(filename: n)?.collection == "Device Mockups", "\(n)") }
        for n in TextureFactory.names { #expect(StarterCatalog.describe(filename: n)?.collection == "Material Textures", "\(n)") }
        for n in VectorFactory.names { #expect(StarterCatalog.describe(filename: n)?.collection == "Editorial Vectors", "\(n)") }
    }

    @Test func texturesAreSeamlessAndRoundTrip() throws {
        for name in TextureFactory.names {
            let img = try #require(TextureFactory.make(name, size: 128))
            let png = PNGEncoder.encodeUpFiltered(img)
            let back = try #require(PNGDecoder.decode(png))
            #expect(back == img, "\(name) Up-filtered PNG must decode to the same pixels")
            // Opposite edges should be about as similar as neighboring columns inside the tile.
            func colDiff(_ a: Int, _ b: Int) -> Double {
                var d = 0.0
                for y in 0..<img.height { let p = img.pixel(x: a, y: y), q = img.pixel(x: b, y: y); d += abs(Double(p.r) - Double(q.r)) + abs(Double(p.g) - Double(q.g)) + abs(Double(p.b) - Double(q.b)) }
                return d / Double(img.height)
            }
            #expect(colDiff(127, 0) <= colDiff(63, 64) * 3 + 12, "\(name) wraps horizontally")
        }
        #expect(TextureFactory.make("nope.png") == nil)
    }

    @Test func vectorsParseWithTheNativeRenderer() throws {
        var bodies = Set<String>()
        for name in VectorFactory.names {
            let svg = try #require(VectorFactory.make(name))
            let scene = try #require(VectorScene.parse(svg), "\(name)")
            #expect(scene.width == 1200 && scene.height == 800)
            #expect(scene.elements.count >= 8, "\(name)")
            #expect(scene.colors.count >= 3, "\(name)")
            bodies.insert(svg)
        }
        #expect(bodies.count == VectorFactory.names.count, "every vector is distinct")
    }

    @Test func everyMockupHasASmartObjectAndReadsBack() throws {
        for name in MockupFactory.names {
            let doc = try #require(MockupFactory.make(name, width: 160, height: 120), "\(name)")
            #expect(doc.layers.contains { $0.name.contains("Smart Object") }, "\(name)")
            let back = try PsdLayers.read(PsdWriter.write(doc))
            #expect(back.layers.count == doc.layers.count)
            #expect(PsdLayers.palette(of: back).count >= 3, "\(name)")
        }
    }

    @Test func legacySmartNameIsRenamedOnce() {
        var c = StudioCatalog()
        c.smartSeeded = true
        c.smartCollections = [StudioSmartCollection(name: "Favorite Motion & Sound", rules: SmartRules(kinds: [.video, .audio], favoritesOnly: true))]
        #expect(c.seedSmartCollections() == 0)
        #expect(c.smartCollections.map(\.name) == ["Favorite Clips"])
        c.seedSmartCollections()
        #expect(c.smartCollections.map(\.name) == ["Favorite Clips"])
        // A user-edited collection with the old name keeps its name.
        var d = StudioCatalog(); d.smartSeeded = true
        d.smartCollections = [StudioSmartCollection(name: "Favorite Motion & Sound", rules: SmartRules(kinds: [.video], favoritesOnly: true))]
        d.seedSmartCollections()
        #expect(d.smartCollections.map(\.name) == ["Favorite Motion & Sound"])
    }
}

@Suite("Seamless check")
struct SeamlessTests {
    @Test func generatedTexturesAreTileable() throws {
        for name in TextureFactory.names {
            let img = try #require(TextureFactory.make(name, size: 512))
            let r = Seamless.analyze(img)
            #expect(r.tileable, "\(name): \(r)")
            // The app checks a downscaled copy, which smooths the interior but keeps any wrap mismatch.
            let small = Seamless.analyze(Thumbnailer.thumbnail(from: img, maxDim: 128))
            #expect(small.tileable, "\(name) downscaled: \(small)")
        }
    }

    @Test func gradientHasASeam() {
        var px = [UInt8]()
        for _ in 0..<64 { for x in 0..<64 { let v = UInt8(x * 4); px += [v, v, v, 255] } }
        let r = Seamless.analyze(PixelBuffer(width: 64, height: 64, rgba: px))
        #expect(!r.tileable)
        #expect(r.horizontal > 10)
        #expect(r.vertical < 1)
    }

    @Test func offsetBlendRemovesTheSeam() {
        var px = [UInt8]()
        for y in 0..<96 { for x in 0..<128 { px += [UInt8(x * 2), UInt8(y * 2), UInt8((x + y) % 256), 255] } }
        let img = PixelBuffer(width: 128, height: 96, rgba: px)
        #expect(!Seamless.analyze(img).tileable)
        let fixed = Seamless.makeTileable(img)
        #expect(Seamless.analyze(fixed).tileable, "\(Seamless.analyze(fixed))")
        // The middle of the image is left alone.
        #expect(fixed.pixel(x: 64, y: 48) == img.pixel(x: 64, y: 48))
    }

    @Test func flatImageIsTileable() {
        let r = Seamless.analyze(PixelBuffer(width: 16, height: 16, rgba: [UInt8](repeating: 128, count: 16 * 16 * 4)))
        #expect(r.tileable)
    }

    @Test func tilingRepeatsPixels() {
        var px = [UInt8]()
        for y in 0..<3 { for x in 0..<2 { px += [UInt8(x), UInt8(y), 7, 255] } }
        let img = PixelBuffer(width: 2, height: 3, rgba: px)
        let t = Seamless.tiled(img, times: 3)
        #expect(t.width == 6 && t.height == 9)
        for y in 0..<9 { for x in 0..<6 { #expect(t.pixel(x: x, y: y) == img.pixel(x: x % 2, y: y % 3)) } }
        #expect(Seamless.tiled(img, times: 0) == img)
    }
}
