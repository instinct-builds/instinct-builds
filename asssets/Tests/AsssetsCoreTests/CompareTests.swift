import Foundation
import Testing
@testable import AsssetsCore

@Suite("Compare")
struct CompareTests {
    func asset(_ tags: [String], _ palette: [String], collection: String = "Material Textures") -> StudioAsset {
        StudioAsset(title: "t", kind: .texture, tags: tags, collection: collection, palette: palette, seed: 0, resolution: "")
    }

    @Test func sessionNeedsTwoToFourDistinct() {
        let a = UUID(), b = UUID()
        #expect(CompareSession(ids: [a]) == nil)
        #expect(CompareSession(ids: [a, a]) == nil)
        #expect(CompareSession(ids: [a, b, a])?.ids == [a, b])
        #expect(CompareSession(ids: (0..<5).map { _ in UUID() }) == nil)
    }

    @Test func markAdvancesToNextUndecidedAndToggles() {
        let ids = (0..<3).map { _ in UUID() }
        var s = CompareSession(ids: ids)!
        s.mark(.keep); #expect(s.focus == 1)
        s.mark(.reject); #expect(s.focus == 2)
        s.mark(.keep); #expect(s.isComplete)
        #expect(s.keeps == [ids[0], ids[2]]); #expect(s.rejects == [ids[1]])
        s.focus = 0; s.mark(.keep)                       // same verdict again clears it
        #expect(s.undecided == [ids[0]]); #expect(s.focus == 0)
        #expect(s.summary == "1 kept · 1 rejected · 1 undecided")
        s.moveFocus(by: -1); #expect(s.focus == 2)
    }

    @Test func zoomKeepsAnchorAndClampsPan() {
        var z = ZoomPan()
        z.pan(dx: 0.3, dy: 0); #expect(z.panX == 0)        // nothing to pan at fit
        z.zoom(by: 2, anchorX: 1, anchorY: 0.5)           // zoom toward the right edge
        #expect(z.zoom == 2); #expect(abs(z.panX - -0.5) < 1e-9)
        // The content point that was at the right edge is still there: (0.5 - pan) / zoom == 0.5
        #expect(abs((0.5 - z.panX) / z.zoom - 0.5) < 1e-9)
        z.pan(dx: -5, dy: 5); #expect(z.panX == -0.5); #expect(z.panY == 0.5)
        z.zoom(by: 100); #expect(z.zoom == 8)
        z.zoom(by: 0.001); #expect(z.zoom == 1); #expect(z.panX == 0 && z.panY == 0)
    }

    @Test func diffFindsUniqueTagsAndColors() {
        let a = asset(["wood", "warm", "shared"], ["#FF0000", "#101010"])
        let b = asset(["stone", "shared"], ["#0000FF", "#121212"])
        #expect(CompareDiff.sharedTags([a, b]) == ["shared"])
        let rows = CompareDiff.rows([a, b])
        #expect(rows[0].uniqueTags == ["wood", "warm"]); #expect(rows[1].uniqueTags == ["stone"])
        #expect(rows[0].uniqueColors == ["#FF0000"]); #expect(rows[1].uniqueColors == ["#0000FF"])
    }

    @Test func applyPicksTagsAndMakesOneSmartCollection() {
        var c = StudioCatalog()
        let a = asset(["x", StudioCatalog.rejectTag], []), b = asset(["y", StudioCatalog.pickTag], []), d = asset([], [])
        c.assets = [a, b, d]
        var s = CompareSession(ids: [a.id, b.id, d.id])!
        s.mark(.keep); s.mark(.reject)
        let smart = c.applyPicks(s)
        #expect(smart != nil)
        #expect(c.assets[0].tags == ["x", "pick"]); #expect(c.assets[1].tags == ["y", "rejected"]); #expect(c.assets[2].tags.isEmpty)
        #expect(c.assets.allSatisfy { $0.collection == "Material Textures" })   // nothing moves out of its collection
        #expect(c.smartCollections.filter { $0.name == "Picks" }.count == 1)
        #expect(c.applyPicks(s) == smart)                                       // second pass reuses it
        #expect(c.smartCollections.filter { $0.rules.requiredTags == ["pick"] }.count == 1)
        let picks = c.smartCollections.first { $0.id == smart }!
        #expect(c.assets.filter { picks.rules.matches($0) }.map(\.id) == [a.id])
    }
}
