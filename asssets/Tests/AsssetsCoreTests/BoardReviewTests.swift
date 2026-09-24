import Foundation
import Testing
@testable import AsssetsCore

@Suite("Board review rounds and versions")
struct BoardReviewTests {
    typealias FB = ReviewGallery.Feedback

    @Test func feedbackPinsOntoTheSharedBoard() {
        var c = StudioCatalog()
        let a = c.importFile(path: "/x/a.png")!, b = c.importFile(path: "/x/b.png")!, off = c.importFile(path: "/x/c.png")!
        let board = c.createBoard(named: "Pitch")
        _ = c.addToBoard(board, assets: [a, b])
        c.noteGalleryShared("G1", from: board)
        #expect(c.board(forGallery: "G1") == board)
        let f = FB(gallery: "G1", title: "Pitch", reviewer: "Mara", items: [
            .init(id: a.uuidString, favorite: true, note: "Love this"),
            .init(id: b.uuidString, favorite: false, note: "Too dark"),
            .init(id: off.uuidString, favorite: true, note: "")])
        let r = c.applyFeedback(f, imported: "2026-09-23")
        #expect(r.board == board)
        let mb = c.boards.first { $0.id == board }!
        #expect(mb.reviews.count == 1 && mb.reviews[0].picks == [a])
        let pins = mb.pins()
        #expect(pins.count == 2)
        let pa = pins.values.first { $0.pickedBy == ["Mara"] }!
        #expect(pa.comments.map(\.text) == ["Love this"])
        #expect(pins.values.contains { !$0.picked && $0.comments.first?.text == "Too dark" })
    }

    @Test func unrelatedGalleryLeavesBoardsAlone() {
        var c = StudioCatalog()
        let a = c.importFile(path: "/x/a.png")!
        let board = c.createBoard(named: "Pitch")
        _ = c.addToBoard(board, assets: [a])
        let r = c.applyFeedback(FB(gallery: "other", title: "", reviewer: "M", items: [.init(id: a.uuidString, favorite: true, note: "")]))
        #expect(r.board == nil && r.favorites == 1)
        #expect(c.boards.first { $0.id == board }!.reviews.isEmpty)
    }

    @Test func reimportReplacesAndReviewersStack() {
        var b = Moodboard(name: "B")
        let a = UUID(); let card = b.addAsset(a, aspect: 1)
        b.recordReview(FB(gallery: "G", title: "", reviewer: "Mara", items: [.init(id: a.uuidString, favorite: true, note: "v1")]), imported: "2026-09-20")
        b.recordReview(FB(gallery: "G", title: "", reviewer: "Mara", items: [.init(id: a.uuidString, favorite: true, note: "v2")]), imported: "2026-09-21")
        b.recordReview(FB(gallery: "G", title: "", reviewer: " ", items: [.init(id: a.uuidString, favorite: false, note: "ok")]), imported: "2026-09-22")
        #expect(b.reviews.count == 2 && b.reviewers == ["Mara", "Client"])
        let pin = b.pins()[card]!
        #expect(pin.pickedBy == ["Mara"] && pin.comments.map(\.text) == ["ok", "v2"])
        #expect(b.pins(reviewer: "Client")[card]!.picked == false)
        let none = b.recordReview(FB(gallery: "G", title: "", reviewer: "X", items: [.init(id: UUID().uuidString, favorite: true, note: "")]), imported: ""); #expect(!none)
    }

    @Test func saveRestoreVersions() {
        var b = Moodboard(name: "B")
        b.addAsset(UUID(), aspect: 1)
        let v1 = b.saveVersion(named: "  ", saved: "t1")
        #expect(b.versions[0].name == "Version 1")
        b.addAsset(UUID(), aspect: 1); b.addAsset(UUID(), aspect: 1)
        let ch = b.changes(since: v1)!; #expect(ch.added == 2 && ch.removed == 0 && ch.changed == 0)
        let ok1 = b.restoreVersion(v1, saved: "t2"); #expect(ok1)
        #expect(b.items.count == 1 && b.versions.count == 2 && b.versions[1].name == "Before restoring Version 1")
        #expect(b.versions[1].items.count == 3)
        // Restoring again from a state already saved doesn't pile up copies.
        let ok2 = b.restoreVersion(b.versions[1].id, saved: "t3"); #expect(ok2 && b.versions.count == 2 && b.items.count == 3)
        b.renameVersion(v1, to: "Client round 1"); #expect(b.versions[0].name == "Client round 1")
        b.deleteVersion(v1); #expect(b.versions.count == 1)
        let ok3 = b.restoreVersion(UUID(), saved: ""); #expect(!ok3)
        for i in 0..<40 { b.saveVersion(named: "v\(i)", saved: "") }
        #expect(b.versions.count == Moodboard.maxVersions && b.versions.last!.name == "v39")
    }

    @Test func decodesOldBoardsAndRoundTrips() throws {
        var b = Moodboard(name: "B")
        let a = UUID(); b.addAsset(a, aspect: 1)
        b.saveVersion(saved: "t"); b.sharedGalleries = ["G"]
        b.recordReview(FB(gallery: "G", title: "", reviewer: "M", items: [.init(id: a.uuidString, favorite: true, note: "n")]), imported: "d")
        let back = try JSONDecoder().decode(Moodboard.self, from: JSONEncoder().encode(b))
        #expect(back == b)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(b)) as! [String: Any]
        json["versions"] = nil; json["reviews"] = "junk"; json["sharedGalleries"] = nil
        let old = try JSONDecoder().decode(Moodboard.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.versions.isEmpty && old.reviews.isEmpty && old.items.count == 1)
    }

    @Test func duplicateStartsFreshHistory() {
        var c = StudioCatalog()
        let board = c.createBoard(named: "P")
        _ = c.updateBoard(board) { $0.saveVersion(saved: "t"); $0.sharedGalleries = ["G"] }
        let copy = c.duplicateBoard(board)!
        let d = c.boards.first { $0.id == copy }!
        #expect(d.versions.isEmpty && d.sharedGalleries.isEmpty && c.board(forGallery: "G") == board)
    }
}
