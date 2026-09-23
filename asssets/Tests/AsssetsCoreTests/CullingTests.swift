import Foundation
import Testing
@testable import AsssetsCore

@Suite("Culling, sort and undo")
struct CullingTests {
    func a(_ title: String, rating: Int = 0, label: ColorLabel? = nil) -> StudioAsset {
        var x = StudioAsset(title: title, kind: .image, tags: [], collection: "Inbox", palette: [], seed: 0, importedPath: "/x/\(title).png", resolution: "")
        x.rating = rating; x.label = label
        return x
    }

    @Test func sortsAreStable() {
        let list = [a("b 10", rating: 2), a("B 2", rating: 5, label: .blue), a("a", rating: 2, label: .red), a("c", rating: 5)]
        #expect(AssetSort.added.apply(list).map(\.title) == ["b 10", "B 2", "a", "c"])
        #expect(AssetSort.name.apply(list).map(\.title) == ["a", "B 2", "b 10", "c"])
        #expect(AssetSort.rating.apply(list).map(\.title) == ["B 2", "c", "b 10", "a"])
        #expect(AssetSort.label.apply(list).map(\.title) == ["a", "B 2", "b 10", "c"])
    }

    @Test func sortPerViewPersists() {
        var c = StudioCatalog(); c.assets = [a("x")]
        let smart = UUID()
        c.setSort(.rating, for: "Inbox"); c.setSort(.name, for: StudioCatalog.sortKey(collection: "All Assets", smart: smart))
        #expect(c.sort(for: "Inbox") == .rating && c.sort(for: "Other") == .added)
        c.setSort(.added, for: "Inbox"); #expect(c.viewSorts["Inbox"] == nil)
        let back = StudioCatalog.decode(try! c.encoded())!
        #expect(back.sort(for: "smart:" + smart.uuidString) == .name)
        // Unknown sort names from a newer build are dropped, not fatal.
        var json = String(data: try! c.encoded(), encoding: .utf8)!
        json = json.replacingOccurrences(of: "\"name\"", with: "\"future\"")
        #expect(StudioCatalog.decode(Data(json.utf8)) != nil)
    }

    @Test func cullStepsAndProgress() {
        var c = StudioCatalog(); c.assets = [a("1"), a("2"), a("3")]
        var s = CullSession(ids: c.assets.map(\.id), start: c.assets[1].id)!
        #expect(s.index == 1 && CullSession(ids: []) == nil)
        let moved = s.step(by: 5), stuck = s.step(by: 1)
        #expect(moved && s.isAtEnd && !stuck)
        s.step(by: -9); #expect(s.index == 0)
        c.setRating([s.current], 3); let adv = s.didDecide(); #expect(adv && s.index == 1)
        let rej = c.toggleReject([s.current]); #expect(rej)
        #expect(s.progress(in: c) == (2, 3))
        #expect(s.nextUndecided(in: c) == 2)
        s.autoAdvance = false; let adv2 = s.didDecide(); #expect(!adv2 && s.index == 1)
        c.setRating([c.assets[2].id], 1); #expect(s.nextUndecided(in: c) == nil)
    }

    @Test func rejectToggleClearsStarsAndPick() {
        var c = StudioCatalog(); c.assets = [a("1", rating: 4)]
        c.assets[0].tags = [StudioCatalog.pickTag]
        let on = c.toggleReject([c.assets[0].id]); #expect(on)
        #expect(c.assets[0].rating == 0 && c.assets[0].tags == [StudioCatalog.rejectTag])
        let off = c.toggleReject([c.assets[0].id]); #expect(!off && c.assets[0].tags.isEmpty)
    }

    @Test func undoRedoRestoresOnlyTheEdit() {
        var c = StudioCatalog(); c.assets = [a("1"), a("2"), a("3")]
        var h = UndoHistory()
        let before = c
        c.setRating([c.assets[0].id, c.assets[1].id], 4)
        let r1 = h.record("Rating", before: before, after: c), r2 = h.record("Nothing", before: c, after: c)
        #expect(r1 && !r2)
        // Background work lands afterwards: a new watched file and suggested tags on asset 1.
        c.assets.insert(a("new"), at: 0)
        c.assets[1].autoTags = ["warm"]
        let u = h.undo(&c); #expect(u == "Rating")
        #expect(c.assets.map(\.rating) == [0, 0, 0, 0] && c.assets.count == 4 && c.assets[1].autoTags == ["warm"])
        #expect(h.redoLabel == "Rating" && h.undoLabel == nil)
        let r = h.redo(&c); #expect(r == "Rating" && c.assets[1].rating == 4 && c.assets[2].rating == 4)
        let u1 = h.undo(&c), u2 = h.undo(&c); #expect(u1 != nil && u2 == nil)
    }

    @Test func undoBringsBackRemovedAssetsInPlace() {
        var c = StudioCatalog(); c.assets = [a("1"), a("2"), a("3")]
        var h = UndoHistory()
        let before = c, id = c.assets[1].id
        c.remove([id])
        h.record("Remove", before: before, after: c)
        _ = h.undo(&c)
        #expect(c.assets.map(\.title) == ["1", "2", "3"] && c.dismissedKeys == before.dismissedKeys)
        _ = h.redo(&c)
        #expect(!c.assets.contains { $0.id == id })
        // A new edit clears redo; history is capped.
        for i in 0..<60 { let b = c; c.setRating([c.assets[0].id], i % 5 + 1); h.record("r\(i)", before: b, after: c) }
        #expect(h.undoStack.count <= UndoHistory.limit && h.redoStack.isEmpty)
    }

    @Test func undoCollectionListsAndMoves() {
        var c = StudioCatalog(); c.assets = [a("1")]
        var h = UndoHistory()
        let before = c
        let name = c.createCollection(); c.move([c.assets[0].id], to: name)
        h.record("Move", before: before, after: c)
        _ = h.undo(&c)
        #expect(c.userCollections == before.userCollections && c.assets[0].collection == "Inbox")
    }
}
