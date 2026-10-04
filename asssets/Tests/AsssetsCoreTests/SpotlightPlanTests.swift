import Foundation
import Testing
@testable import AsssetsCore

@Suite("Spotlight plan")
struct SpotlightPlanTests {
    @Test func recordsCarryTitleTagsAndNotesAndSkipSystemTagsAndStarterAssets() {
        var c = StudioCatalog()
        let a = c.importFile(path: "/s/Logo.png")!
        _ = c.addTags("client, hero", to: [a])
        let g = UUID().uuidString
        _ = c.recordGallery(GalleryRoster(gallery: g, title: "R", created: "2026-10-04", assets: [a])!)
        _ = c.applyFeedback(.init(gallery: g, title: "R", reviewer: "Jordan", items: [.init(id: a.uuidString, favorite: false, note: "Warmer backdrop")]))
        var starter = StudioAsset(title: "Bundled", kind: .image, tags: ["bundled"], collection: "Textures", palette: [], seed: 0, importedPath: "/x/b.png", resolution: "")
        starter.sourceKey = "starter:b"
        c.assets.append(starter)
        let r = SpotlightPlan.records(c)
        #expect(r.count == 1 && r[0].id == a)
        #expect(r[0].keywords.contains("client") && r[0].keywords.contains("hero"))
        #expect(!r[0].keywords.contains("imported") && !r[0].keywords.contains("png"))
        #expect(r[0].text == "Warmer backdrop" && r[0].path == "/s/Logo.png")
    }

    @Test func diffIndexesOnlyChangesAndDeletesRemovedAssets() {
        func rec(_ n: String, _ id: UUID) -> SpotlightRecord { SpotlightRecord(id: id, title: n, keywords: [], detail: "", text: "", path: nil) }
        let a = UUID(), b = UUID(), gone = UUID()
        let known = [a: rec("A", a), b: rec("B", b), gone: rec("G", gone)]
        let d = SpotlightPlan.diff(known: known, now: [rec("A", a), rec("B2", b), rec("New", UUID())])
        #expect(d.index.map(\.title).sorted() == ["B2", "New"])
        #expect(d.delete == [gone])
        let none = SpotlightPlan.diff(known: known, now: known.values.map { $0 })
        #expect(none.index.isEmpty && none.delete.isEmpty)
    }
}
