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
