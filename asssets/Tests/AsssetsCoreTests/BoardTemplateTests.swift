import Foundation
import Testing
@testable import AsssetsCore

@Suite("Board templates")
struct BoardTemplateTests {
    @Test func builtInsAreSaneAndStable() {
        let t = BoardTemplate.builtIns
        #expect(t.map(\.name) == ["Moodboard 3x3", "Brand Direction A/B", "Product Launch"])
        #expect(t.map(\.slotCount) == [9, 6, 4])
        #expect(t.allSatisfy { $0.builtIn && Set($0.items.map(\.id)).count == $0.items.count && $0.items.allSatisfy { !$0.isSlot || $0.assetID == nil } })
        #expect(BoardTemplate.launch.connectors.count == 2)
        #expect(BoardTemplate.builtIns[0].id == BoardTemplate.moodboardID)
    }

    @Test func createFromTemplateGetsFreshIDs() {
        var c = StudioCatalog()
        let id = c.createBoard(from: BoardTemplate.launchID)!
        let b = c.board(id)!
        #expect(b.name == "Product Launch" && b.items.count == BoardTemplate.launch.items.count)
        #expect(Set(b.items.map(\.id)).isDisjoint(with: BoardTemplate.launch.items.map(\.id)))
        #expect(b.connectors.count == 2 && b.connectors.allSatisfy { c in b.items.contains { $0.id == c.from } })
        #expect(b.emptySlots.count == 4)
        #expect(c.createBoard(from: UUID()) == nil)
    }

    @Test func placeFillsSlotsInReadingOrderThenFlows() {
        var c = StudioCatalog()
        let ids = (0..<11).map { c.importFile(path: "/x/a\($0).png")! }
        let id = c.createBoard(from: BoardTemplate.moodboardID)!
        let n = c.placeOnBoard(id, assets: ids)
        let b = c.board(id)!
        #expect(n == 11 && b.emptySlots.isEmpty)
        let order = b.readingOrder.filter { $0.kind == .asset }.compactMap(\.assetID)
        #expect(Array(order.prefix(9)) == Array(ids.prefix(9)))
        #expect(b.items.filter { $0.kind == .asset }.count == 11)   // two extra cards laid out normally
        // Slots keep their size.
        let first = b.items.first { $0.assetID == ids[0] }!
        #expect(first.w == 240 && first.h == 180)
        // Re-placing the same assets adds nothing.
        #expect(c.placeOnBoard(id, assets: ids) == 0)
    }

    @Test func dropOnSlotFillsJustThatSlot() {
        var b = Moodboard(name: "B")
        b.items = BoardTemplate.brand.items
        let target = BoardTemplate.brand.items.first { $0.isSlot && $0.x > 500 && $0.w > 400 }!
        let a = UUID(), extra = UUID()
        let placed = b.place([(id: a, aspect: 1), (id: extra, aspect: 1.5)], at: (x: target.x + 10, y: target.y + 10))
        #expect(placed.first == target.id && placed.count == 2)
        let filled = b.items.first { $0.id == target.id }!
        #expect(filled.assetID == a && filled.w == target.w && filled.h == target.h)
        // A square image in a 440x260 slot is cropped from the middle, full width.
        #expect(filled.crop != nil && filled.crop!.w == 1 && abs(filled.crop!.h - 260.0 / 440.0) < 0.001)
        #expect(b.emptySlots.count == 5)
        // Dropped away from slots: normal layout.
        let away = b.place([(id: UUID(), aspect: 1)], at: (x: 3000, y: 3000))
        #expect(away.count == 1 && b.emptySlots.count == 5)
        b.clearSlot(target.id)
        #expect(b.emptySlots.count == 6 && b.items.first { $0.id == target.id }!.crop == nil)
    }

    @Test func saveRenameDeleteAndPersist() throws {
        var c = StudioCatalog()
        let a = c.importFile(path: "/x/a.png")!
        let id = c.createBoard(named: "Pitch")
        _ = c.addToBoard(id, assets: [a])
        _ = c.updateBoard(id) { $0.addNote("keep"); _ = $0.setStatus(.approved, for: Set($0.items.map(\.id))) }
        let t1 = c.saveTemplate(from: id, named: "Pitch")!, t2 = c.saveTemplate(from: id, named: "Pitch")!
        #expect(c.template(t2)?.name == "Pitch 2" && c.allTemplates.count == 5)
        let tpl = c.template(t1)!
        #expect(tpl.slotCount == 1 && tpl.items.first { $0.kind == .asset }?.assetID == nil && !tpl.builtIn)
        c.renameTemplate(t1, to: "Pitch deck"); #expect(c.template(t1)?.name == "Pitch deck")
        c.deleteTemplate(t2); #expect(c.templates.count == 1)
        var back = try JSONDecoder().decode(StudioCatalog.self, from: c.encoded())
        #expect(back.templates == c.templates)
        let fresh = back.createBoard(from: t1)
        #expect(fresh != nil)
        // Built-ins are never stored, and a stored one claiming to be built in is dropped.
        var json = try JSONSerialization.jsonObject(with: c.encoded()) as! [String: Any]
        var arr = json["templates"] as! [[String: Any]]; arr[0]["builtIn"] = true; json["templates"] = arr
        let dropped = try JSONDecoder().decode(StudioCatalog.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(dropped.templates.isEmpty)
    }

    @Test func manifestCarriesSummary() throws {
        let m = ReviewGallery.Manifest(title: "T", created: "d", items: [], summary: "round-summary.pdf")
        let back = try JSONDecoder().decode(ReviewGallery.Manifest.self, from: JSONEncoder().encode(m))
        #expect(back.summary == "round-summary.pdf")
        #expect(ReviewGallery.html(m).contains("id=\"summary\""))
        let old = try JSONDecoder().decode(ReviewGallery.Manifest.self, from: Data(#"{"gallery":"g","title":"t","created":"d","items":[]}"#.utf8))
        #expect(old.summary == nil)
    }
}
