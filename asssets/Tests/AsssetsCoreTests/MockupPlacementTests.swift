import Foundation
import Testing
@testable import AsssetsCore

@Suite("Place into Mockup")
struct MockupPlacementTests {
    func solid(_ w: Int, _ h: Int, _ c: (UInt8, UInt8, UInt8, UInt8)) -> PixelBuffer {
        PixelBuffer(width: w, height: h, rgba: Array((0..<(w * h)).flatMap { _ in [c.0, c.1, c.2, c.3] }))
    }
    /// Left half red, right half blue.
    func split(_ w: Int, _ h: Int) -> PixelBuffer {
        var px: [UInt8] = []
        for _ in 0..<h { for x in 0..<w { px += x < w / 2 ? [255, 0, 0, 255] : [0, 0, 255, 255] } }
        return PixelBuffer(width: w, height: h, rgba: px)
    }
    func layer(_ name: String, left: Int, top: Int, w: Int, h: Int, alpha: (Int, Int) -> UInt8 = { _, _ in 255 }) -> PsdLayer {
        var px: [UInt8] = []
        for y in 0..<h { for x in 0..<w { px += [10, 200, 10, alpha(x, y)] } }
        return PsdLayer(name: name, top: top, left: left, bottom: top + h, right: left + w, rgba: px)
    }

    @Test func picksTheSmartObjectLayer() {
        let doc = PsdDocument(width: 100, height: 100, layers: [
            layer("Backdrop", left: 0, top: 0, w: 100, h: 100), layer("Screen Glare", left: 0, top: 0, w: 50, h: 50),
            layer("Your Design (Smart Object)", left: 10, top: 10, w: 40, h: 60), layer("Label", left: 0, top: 0, w: 20, h: 20)])
        #expect(MockupPlacement.targetLayers(doc).first == 2)
    }

    @Test func roundedRectangleUsesItsBoundingBox() {
        let l = layer("S", left: 20, top: 30, w: 40, h: 20) { x, y in
            let r = 6, cx = min(max(x, r), 39 - r), cy = min(max(y, r), 19 - r)
            return (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r ? 255 : 0
        }
        let q = MockupPlacement.quad(of: l)!
        #expect(q.tl == Point2(x: 20, y: 30) && q.br == Point2(x: 60, y: 50))
        #expect(abs(q.aspect - 2) < 0.001)
    }

    @Test func tiltedShapeUsesItsCorners() {
        // A diamond: corners at top, right, bottom and left middles.
        let l = layer("S", left: 0, top: 0, w: 41, h: 41) { x, y in abs(x - 20) + abs(y - 20) <= 20 ? 255 : 0 }
        let q = MockupPlacement.quad(of: l)!
        #expect(abs(q.tl.y - q.tl.x) > 5 || abs(q.tr.x - q.br.x) > 5)
    }

    @Test func homographyMapsCornersAndInverts() {
        let q = Quad(tl: Point2(x: 10, y: 20), tr: Point2(x: 110, y: 30), br: Point2(x: 100, y: 140), bl: Point2(x: 5, y: 120))
        let m = MockupPlacement.homography(q)
        for (u, v, p) in [(0.0, 0.0, q.tl), (1, 0, q.tr), (1, 1, q.br), (0, 1, q.bl)] {
            let r = MockupPlacement.apply(m, u, v)
            #expect(abs(r.x - p.x) < 1e-6 && abs(r.y - p.y) < 1e-6)
        }
        let inv = MockupPlacement.inverse(m)!
        let mid = MockupPlacement.apply(m, 0.3, 0.7), back = MockupPlacement.apply(inv, mid.x, mid.y)
        #expect(abs(back.x - 0.3) < 1e-6 && abs(back.y - 0.7) < 1e-6)
    }

    @Test func fillCropsAndFitLetterboxes() {
        // Square art into a 2:1 area.
        let fill = MockupPlacement.region(mode: .fill, artAspect: 1, areaAspect: 2)
        #expect(abs(fill.w - 1) < 1e-9 && abs(fill.h - 0.5) < 1e-9 && abs(fill.y - 0.25) < 1e-9)
        let fit = MockupPlacement.region(mode: .fit, artAspect: 1, areaAspect: 2)
        #expect(abs(fit.w - 2) < 1e-9 && abs(fit.x + 0.5) < 1e-9 && abs(fit.h - 1) < 1e-9)
        // A crop on the left half of a 2:1 art into a square area is used as is.
        let crop = MockupPlacement.region(mode: .fill, artAspect: 2, areaAspect: 1, crop: BoardRect(x: 0, y: 0, w: 0.5, h: 1))
        #expect(abs(crop.x) < 1e-9 && abs(crop.w - 0.5) < 1e-9)
    }

    @Test func placeDrawsArtInsideTheMaskOnly() {
        let screen = layer("Screen (Smart Object)", left: 10, top: 10, w: 40, h: 20) { x, _ in x < 38 ? 255 : 0 }
        let doc = PsdDocument(width: 60, height: 40, layers: [layer("Backdrop", left: 0, top: 0, w: 60, h: 40), screen])
        let placed = MockupPlacement.place(split(80, 40), into: doc)!
        let l = placed.layers[1]
        func px(_ x: Int, _ y: Int) -> [UInt8] { let i = (y * l.width + x) * 4; return Array(l.rgba[i..<i + 4]) }
        #expect(px(2, 10) == [255, 0, 0, 255])
        #expect(px(30, 10) == [0, 0, 255, 255])
        #expect(px(39, 10)[3] == 0)
        #expect(placed.layers[0] == doc.layers[0])
    }

    @Test func fitShowsBackgroundInTheMargins() {
        let screen = layer("Artwork (Smart Object)", left: 0, top: 0, w: 40, h: 20)
        let doc = PsdDocument(width: 40, height: 20, layers: [screen])
        let placed = MockupPlacement.place(solid(10, 10, (255, 0, 0, 255)), into: doc, mode: .fit, background: (0, 0, 0))!
        let l = placed.layers[0]
        #expect(Array(l.rgba[0..<3]) == [0, 0, 0])
        let mid = (10 * 40 + 20) * 4
        #expect(Array(l.rgba[mid..<mid + 3]) == [255, 0, 0])
    }

    @Test func noDesignLayerMeansNoPlacement() {
        let doc = PsdDocument(width: 10, height: 10, layers: [layer("Backdrop", left: 0, top: 0, w: 10, h: 10)])
        #expect(MockupPlacement.place(solid(4, 4, (1, 2, 3, 255)), into: doc) == nil)
    }

    @Test func placedRenderJoinsTheMockupStackWithTheArtsRights() {
        var c = StudioCatalog()
        let mock = c.importFile(path: "/lib/Phone Mockup.psd", collection: "Device Mockups")!
        let art = c.importFile(path: "/lib/Launch Poster.png")!
        c.assets[c.assets.firstIndex { $0.id == art }!].rights = UsageRights(license: .client, source: "Maison Vale", credit: "Courtesy of Maison Vale")
        _ = c.addLicenseDoc(LicenseDoc(name: "brief.pdf"), to: [art])
        let id = c.addPlacedMockup(path: "/lib/Placed/Launch Poster on Phone Mockup.png", art: art, mockup: mock, resolution: "1600 × 1200")!
        let a = c.assets.first { $0.id == id }!
        #expect(a.title == "Launch Poster on Phone Mockup" && a.collection == "Device Mockups" && a.kind == .mockup)
        #expect(a.rights?.source == "Maison Vale" && a.licenseDocs.count == 1 && a.tags.contains("placed"))
        #expect(a.stackID != nil && a.stackID == c.assets.first { $0.id == mock }!.stackID)
    }
}

@Suite("Place into Mockup shapes")
struct MockupPlacementShapeTests {
    func layer(_ name: String, w: Int, h: Int, alpha: (Int, Int) -> UInt8) -> PsdLayer {
        var px: [UInt8] = []
        for y in 0..<h { for x in 0..<w { px += [0, 0, 0, alpha(x, y)] } }
        return PsdLayer(name: name, top: 0, left: 0, bottom: h, right: w, rgba: px)
    }
    @Test func circleUsesItsBoxAndKeepsItsMask() {
        let l = layer("Print (Smart Object)", w: 41, h: 41) { x, y in (x - 20) * (x - 20) + (y - 20) * (y - 20) <= 400 ? 255 : 0 }
        let q = MockupPlacement.quad(of: l)!
        #expect(q.tl == Point2(x: 0, y: 0) && abs(q.aspect - 1) < 0.001)
        #expect(!MockupPlacement.isSparse(l))
        let placed = MockupPlacement.place(PixelBuffer(width: 2, height: 2, rgba: [UInt8](repeating: 255, count: 16)), into: PsdDocument(width: 41, height: 41, layers: [l]))!
        #expect(placed.layers[0].rgba[3] == 0)
    }
    @Test func textLinesFillTheirWholeBox() {
        let lines = layer("Layout (Smart Object)", w: 40, h: 40) { _, y in y % 4 == 0 ? 255 : 0 }
        #expect(MockupPlacement.isSparse(lines))
        let placed = MockupPlacement.place(PixelBuffer(width: 2, height: 2, rgba: [UInt8](repeating: 200, count: 16)), into: PsdDocument(width: 40, height: 40, layers: [lines]))!
        let i = (2 * 40 + 5) * 4
        #expect(placed.layers[0].rgba[i + 3] == 255)
    }
    @Test func biggerLayerWinsATie() {
        let small = layer("Right Page Layout (Smart Object)", w: 20, h: 20) { _, y in y % 4 == 0 ? 255 : 0 }
        let big = layer("Left Page Photo (Smart Object)", w: 30, h: 30) { _, _ in 255 }
        #expect(MockupPlacement.targetLayers(PsdDocument(width: 40, height: 40, layers: [big, small])).first == 0)
    }
}

@Suite("Editable placement recipes")
struct PlacementRecipeTests {
    @Test func savesAndReopensExactSettings() throws {
        var c = StudioCatalog()
        let art = c.importFile(path: "/lib/Poster.png")!
        let mockup = c.importFile(path: "/lib/Frame.psd")!
        let crop = BoardRect(x: 0.15, y: 0.25, w: 0.6, h: 0.5)
        let recipe = PlacementRecipe(artID: art, mockupID: mockup, layerName: "Poster Design", mode: .fit, crop: crop, background: "Paper")
        let render = c.addPlacedMockup(path: "/lib/Placed/render.png", art: art, mockup: mockup, resolution: "1200 × 800", recipe: recipe)!
        let reopened = StudioCatalog.decode(try c.encoded())!
        #expect(reopened.assets.first { $0.id == render }?.placementRecipe == recipe)
        #expect(reopened.placementStatus(recipe, exists: { _ in true }) == .ready(art: art, mockup: mockup))
        #expect(reopened.assets.first { $0.id == mockup }?.placementRecipe == nil)
        // A catalog from 1.29 has no placementRecipe key and must keep decoding.
        var old = try JSONSerialization.jsonObject(with: c.encoded()) as! [String: Any]
        var assets = old["assets"] as! [[String: Any]]
        for i in assets.indices { assets[i].removeValue(forKey: "placementRecipe") }
        old["assets"] = assets
        let data = try JSONSerialization.data(withJSONObject: old)
        #expect(StudioCatalog.decode(data)?.assets.first { $0.id == render }?.placementRecipe == nil)
    }

    @Test func missingSourcesStayExplicitUntilRelinked() throws {
        var c = StudioCatalog()
        let art = c.importFile(path: "/old/Poster.png")!
        let mockup = c.importFile(path: "/lib/Frame.psd")!
        let recipe = PlacementRecipe(artID: art, mockupID: mockup)
        #expect(c.placementStatus(recipe, exists: { $0 == "/lib/Frame.psd" }) == .missingArt(art))
        c.assets[c.assets.firstIndex { $0.id == art }!].importedPath = "/new/Poster.png"
        #expect(c.placementStatus(recipe, exists: { $0 != "/lib/Frame.psd" }) == .missingMockup(mockup))
        #expect(c.placementStatus(recipe, exists: { _ in true }) == .ready(art: art, mockup: mockup))
        c.assets.removeAll { $0.id == art }
        #expect(c.placementStatus(recipe, exists: { _ in true }) == .missingArt(art))
    }

    @Test func revisionIsASeparateVersion() {
        var c = StudioCatalog()
        let art = c.importFile(path: "/lib/Poster.png")!
        let mockup = c.importFile(path: "/lib/Frame.psd")!
        let a = PlacementRecipe(artID: art, mockupID: mockup, mode: .fill)
        let b = PlacementRecipe(artID: art, mockupID: mockup, mode: .fit, background: "Black")
        let first = c.addPlacedMockup(path: "/lib/render-1.png", art: art, mockup: mockup, resolution: "100 × 100", recipe: a)!
        let next = c.addPlacedMockup(path: "/lib/render-2.png", art: art, mockup: mockup, resolution: "100 × 100", recipe: b)!
        #expect(first != next)
        #expect(c.assets.first { $0.id == first }?.placementRecipe == a)
        #expect(c.assets.first { $0.id == next }?.placementRecipe == b)
        #expect(c.assets.first { $0.id == first }?.stackID == c.assets.first { $0.id == next }?.stackID)
    }
}

extension PlacementRecipeTests {
    @Test func generatedStarterArtIsAValidSource() {
        let art = StudioAsset(title: "Generated Study", kind: .image, tags: [], collection: "Bundled",
                              palette: [], seed: 2, resolution: "1200 × 800", sourceKey: "generated:studies:2")
        var c = StudioCatalog(assets: [art])
        let mockup = c.importFile(path: "/lib/Frame.psd")!
        let recipe = PlacementRecipe(artID: art.id, mockupID: mockup)
        #expect(c.placementStatus(recipe, exists: { $0 == "/lib/Frame.psd" }) == .ready(art: art.id, mockup: mockup))
    }
}

extension PlacementRecipeTests {
    @Test func batchRendersHaveIndependentArtworkStacksAndRights() {
        var c = StudioCatalog()
        let mockup = c.importFile(path: "/lib/Frame.psd")!
        let artA = c.importFile(path: "/lib/A.png")!
        let artB = c.importFile(path: "/lib/B.png")!
        c.assets[c.assets.firstIndex { $0.id == artA }!].rights = UsageRights(license: .client, source: "Client A")
        c.assets[c.assets.firstIndex { $0.id == artB }!].rights = UsageRights(license: .licensed, source: "Vendor B")
        let a = c.addPlacedMockup(path: "/lib/render-A.png", art: artA, mockup: mockup, resolution: "100 × 100",
                                  recipe: PlacementRecipe(artID: artA, mockupID: mockup), stackOnArt: true)!
        let b = c.addPlacedMockup(path: "/lib/render-B.png", art: artB, mockup: mockup, resolution: "100 × 100",
                                  recipe: PlacementRecipe(artID: artB, mockupID: mockup), stackOnArt: true)!
        let renderA = c.assets.first { $0.id == a }!, renderB = c.assets.first { $0.id == b }!
        #expect(renderA.stackID == c.assets.first { $0.id == artA }?.stackID)
        #expect(renderB.stackID == c.assets.first { $0.id == artB }?.stackID)
        #expect(renderA.stackID != renderB.stackID)
        #expect(c.assets.first { $0.id == mockup }?.stackID == nil)
        #expect(renderA.rights?.source == "Client A" && renderB.rights?.source == "Vendor B")
        #expect(renderA.placementRecipe?.artID == artA && renderB.placementRecipe?.artID == artB)
    }
}

@Suite("Placement presets")
struct PlacementPresetTests {
    @Test func storesNamedPresetAndUpdatesByCaseInsensitiveName() throws {
        var c = StudioCatalog()
        let mockup = c.importFile(path: "/lib/Poster.psd")!
        let id = c.savePlacementPreset(name: "  Poster Launch  ", mockupID: mockup, layerName: "Artwork",
                                       mode: .fill, background: "Paper")!
        #expect(c.placementPresets.count == 1)
        #expect(c.placementPresets[0].name == "Poster Launch")
        let same = c.savePlacementPreset(name: "poster launch", mockupID: mockup, layerName: "Design",
                                         mode: .fit, background: "Black")!
        #expect(same == id && c.placementPresets.count == 1)
        let decoded = StudioCatalog.decode(try c.encoded())!
        #expect(decoded.placementPresets[0].layerName == "Design" && decoded.placementPresets[0].mode == .fit)
        #expect(decoded.placementPresets[0].background == "Black")
        c.deletePlacementPreset(id)
        #expect(c.placementPresets.isEmpty)
    }

    @Test func missingMockupAndLayerNeverFallBackSilently() {
        var c = StudioCatalog()
        let mockup = c.importFile(path: "/lib/Poster.psd")!
        let preset = PlacementPreset(name: "Poster", mockupID: mockup, layerName: "Artwork")
        #expect(c.placementPresetStatus(preset, exists: { _ in true }, layers: { _ in ["Other", "Artwork"] }) == .ready(1))
        #expect(c.placementPresetStatus(preset, exists: { _ in true }, layers: { _ in ["Other"] }) == .missingLayer)
        #expect(c.placementPresetStatus(preset, exists: { _ in false }, layers: { _ in ["Artwork"] }) == .missingMockup)
        c.assets.removeAll { $0.id == mockup }
        #expect(c.placementPresetStatus(preset, exists: { _ in true }, layers: { _ in ["Artwork"] }) == .missingMockup)
        #expect(c.savePlacementPreset(name: " ", mockupID: mockup, layerName: "Artwork", mode: .fill, background: "White") == nil)
    }

    @Test func oldCatalogDecodesWithoutPresets() throws {
        let c = StudioCatalog(assets: [StudioAsset(title: "A", kind: .image, tags: [], collection: "C", palette: [], seed: 1, resolution: "1")])
        var json = try JSONSerialization.jsonObject(with: c.encoded()) as! [String: Any]
        json.removeValue(forKey: "placementPresets")
        let old = try JSONSerialization.data(withJSONObject: json)
        #expect(StudioCatalog.decode(old)?.placementPresets.isEmpty == true)
    }
}

@Suite("Per-art batch framing")
struct BatchFramingTests {
    @Test func distinctArtworkCropsRenderAndPersistIndependently() throws {
        let tool = MockupPlacementTests()
        let screen = tool.layer("Poster Design (Smart Object)", left: 0, top: 0, w: 20, h: 20)
        let doc = PsdDocument(width: 20, height: 20, layers: [screen])
        let striped = tool.split(40, 20)
        let left = BoardRect(x: 0, y: 0, w: 0.5, h: 1)
        let right = BoardRect(x: 0.5, y: 0, w: 0.5, h: 1)
        let red = MockupPlacement.place(striped, into: doc, mode: .fill, crop: left)!.layers[0].rgba
        let blue = MockupPlacement.place(striped, into: doc, mode: .fill, crop: right)!.layers[0].rgba
        let center = (10 * 20 + 10) * 4
        #expect(red[center] > red[center + 2])
        #expect(blue[center + 2] > blue[center])
        var catalog = StudioCatalog()
        let art1 = catalog.importFile(path: "/art-1.png")!, art2 = catalog.importFile(path: "/art-2.png")!
        let mockup = catalog.importFile(path: "/mockup.psd")!
        let a = catalog.addPlacedMockup(path: "/render-1.png", art: art1, mockup: mockup, resolution: "20 × 20",
            recipe: PlacementRecipe(artID: art1, mockupID: mockup, layerName: "Poster Design", crop: left), stackOnArt: true)!
        let b = catalog.addPlacedMockup(path: "/render-2.png", art: art2, mockup: mockup, resolution: "20 × 20",
            recipe: PlacementRecipe(artID: art2, mockupID: mockup, layerName: "Poster Design", crop: right), stackOnArt: true)!
        let decoded = StudioCatalog.decode(try catalog.encoded())!
        #expect(decoded.assets.first { $0.id == a }?.placementRecipe?.crop == left)
        #expect(decoded.assets.first { $0.id == b }?.placementRecipe?.crop == right)
        #expect(decoded.assets.first { $0.id == a }?.stackID != decoded.assets.first { $0.id == b }?.stackID)
    }
}
