import Foundation
import Testing
@testable import AsssetsCore

@Suite("Changed source review")
struct SourceChangeTests {
    @Test func unchangedAndTimestampTouch() {
        let old = SourceFingerprint(size: 42, modified: 10, sha256: "same")
        #expect(old.status(against: old) == .unchanged)
        #expect(old.status(against: SourceFingerprint(size: 42, modified: 11, sha256: "same")) == .timestampOnly)
        #expect(old.status(against: SourceFingerprint(size: 42, modified: 10, sha256: "different")) == .changed)
        var c = StudioCatalog()
        let id = c.importFile(path: "/work/a.png")!
        let seeded = c.seedSourceFingerprint(old, for: id, path: "/work/a.png")
        #expect(seeded)
        let touched = c.acceptTimestampOnly(SourceFingerprint(size: 42, modified: 11, sha256: "same"), for: id, path: "/work/a.png")
        #expect(touched)
        #expect(c.assets.first { $0.id == id }?.sourceFingerprint?.modified == 11)
        let falseTouch = c.acceptTimestampOnly(SourceFingerprint(size: 42, modified: 12, sha256: "different"), for: id, path: "/work/a.png")
        #expect(!falseTouch)
    }

    @Test func samePathChangedBytesAndPreservedIdentity() throws {
        var catalog = StudioCatalog()
        let id = catalog.importFile(path: "/work/art.png")!
        let base = SourceFingerprint(size: 9, modified: 1, sha256: "first")
        let seeded = catalog.seedSourceFingerprint(base, for: id, path: "/work/art.png")
        let seededAgain = catalog.seedSourceFingerprint(base, for: id, path: "/work/art.png")
        #expect(seeded && !seededAgain)
        let new = SourceFingerprint(size: 9, modified: 2, sha256: "second")
        #expect(base.status(against: new) == .changed)
        let rights = UsageRights(license: .client, source: "Client")
        catalog.assets[catalog.assets.firstIndex { $0.id == id }!].rights = rights
        catalog.assets[catalog.assets.firstIndex { $0.id == id }!].tags = ["chosen"]
        let board = catalog.createBoard(named: "Reference")
        _ = catalog.updateBoard(board) { _ = $0.addAsset(id, aspect: 1) }
        let render = catalog.addPlacedMockup(path: "/work/render.png", art: id, mockup: id,
            resolution: "90 × 90", recipe: PlacementRecipe(artID: id, mockupID: id))!
        let accepted = catalog.acceptChangedSource(new, for: id, path: "/work/art.png", palette: ["#FF0000"], resolution: "90 × 90")
        #expect(accepted)
        let a = catalog.assets.first { $0.id == id }!
        #expect(a.id == id && a.rights == rights && a.importedPath == "/work/art.png")
        #expect(a.palette == ["#FF0000"] && a.resolution == "90 × 90" && a.sourceFingerprint == new)
        #expect(a.tags == ["chosen"] && catalog.boardsUsing(id).count == 1)
        #expect(catalog.assets.first { $0.id == render }?.placementRecipe?.artID == id)
        #expect(StudioCatalog.decode(try catalog.encoded())?.assets.first { $0.id == id }?.sourceFingerprint == new)
    }

    @Test func olderCatalogDecodesWithoutBaseline() throws {
        var catalog = StudioCatalog()
        let id = catalog.importFile(path: "/work/old.png")!
        var raw = try JSONSerialization.jsonObject(with: catalog.encoded()) as! [String: Any]
        var assets = raw["assets"] as! [[String: Any]]
        for i in assets.indices { assets[i].removeValue(forKey: "sourceFingerprint") }
        raw["assets"] = assets
        let old = StudioCatalog.decode(try JSONSerialization.data(withJSONObject: raw))!
        #expect(old.assets.first { $0.id == id }?.sourceFingerprint == nil)
    }
}
