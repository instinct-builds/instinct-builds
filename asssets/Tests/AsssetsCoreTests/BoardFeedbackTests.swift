import Foundation
import Testing
@testable import AsssetsCore

@Suite("Client approval from the gallery, import preview and Arrange")
struct BoardFeedbackTests {
    private func edit(_ b: inout Moodboard, _ id: UUID, _ f: (inout BoardItem) -> Void) { if let i = b.items.firstIndex(where: { $0.id == id }) { f(&b.items[i]) } }

    private func round() -> (StudioCatalog, UUID, [UUID], [UUID]) {
        var c = StudioCatalog()
        let a = ["/x/plinth.png", "/x/stage.png", "/x/grain.png"].map { c.importFile(path: $0)! }
        let board = c.createBoard(named: "Lobby")
        _ = c.addToBoard(board, assets: a)
        c.noteGalleryShared("G", from: board)
        let cards = a.map { id in c.board(board)!.items.first { $0.assetID == id }!.id }
        return (c, board, a, cards)
    }

    @Test func oldFilesDecodeAndStatusIsOptional() throws {
        let old = #"{"format":"asssets-review-feedback","gallery":"G","title":"T","reviewer":"R","items":[{"id":"x","favorite":true,"note":""}]}"#
        let f = try #require(ReviewGallery.decodeFeedback(Data(old.utf8)))
        #expect(f.items[0].status == nil && f.items[0].cardStatus == nil)
        let e = ReviewGallery.Feedback.Entry(id: "x", favorite: false, note: "", status: "Changes")
        #expect(e.cardStatus == .changes && ReviewGallery.Feedback.Entry(id: "x", favorite: false, note: "", status: "maybe").cardStatus == nil)
        // No status written back when there is none, so older ASSSETS builds read new files unchanged.
        let json = String(decoding: try JSONEncoder().encode(f), as: UTF8.self)
        #expect(!json.contains("status"))
    }

    @Test func previewChangesNothingAndCountsRows() {
        let (c, board, a, cards) = round()
        let f = ReviewGallery.Feedback(gallery: "G", title: "Lobby", reviewer: " Mara ", items: [
            .init(id: a[0].uuidString.lowercased(), favorite: true, note: " Brass by the door ", status: "approved"),
            .init(id: a[1].uuidString, favorite: false, note: "", status: "changes"),
            .init(id: UUID().uuidString, favorite: true, note: "gone", status: "approved")])
        let p = c.previewFeedback(f)
        #expect(p.reviewer == "Mara" && p.board == board && p.boardName == "Lobby" && !p.replaces)
        #expect(p.picks == 1 && p.notes == 1 && p.approvals == 1 && p.changeRequests == 1 && p.unknown == 1 && p.statusChanges == 2)
        #expect(p.rows[0].note == "Brass by the door" && p.rows[0].from == .open && p.rows[0].to == .approved && p.rows[2].title == "Not in this library")
        #expect(c.board(board)!.status(of: cards[0]) == .open && c.board(board)!.reviews.isEmpty)
    }

    @Test func importSetsStatusesAndPreviewThenSeesReplace() {
        var (c, board, a, cards) = round()
        let f = ReviewGallery.Feedback(gallery: "G", title: "Lobby", reviewer: "Mara", items: [
            .init(id: a[0].uuidString, favorite: true, note: "Yes", status: "approved"),
            .init(id: a[1].uuidString, favorite: false, note: "", status: "changes")])
        let r = c.applyFeedback(f, imported: "2026-09-24")
        #expect(r.board == board && r.statuses == 2 && r.favorites == 1 && r.notes == 1)
        let b = c.board(board)!
        #expect(b.status(of: cards[0]) == .approved && b.status(of: cards[1]) == .changes && b.status(of: cards[2]) == .open)
        #expect(b.pins()[cards[0]]?.comments.first?.reviewer == "Mara")
        let again = c.previewFeedback(f)
        #expect(again.replaces && again.statusChanges == 0)
    }

    @Test func statusOnlyFileStillLandsOnTheBoard() {
        var (c, board, a, cards) = round()
        let f = ReviewGallery.Feedback(gallery: "G", title: "Lobby", reviewer: "", items: [.init(id: a[2].uuidString, favorite: false, note: "", status: "approved")])
        #expect(!c.previewFeedback(f).isEmpty)
        let r = c.applyFeedback(f, imported: "d")
        #expect(r.board == board && r.statuses == 1 && c.board(board)!.status(of: cards[2]) == .approved)
    }

    @Test func alignAndMatch() {
        var b = Moodboard(name: "A"); b.snap = false
        let x = b.addNote("x", at: (x: 10, y: 10)), y = b.addNote("y", at: (x: 300, y: 80)), z = b.addNote("z", at: (x: 120, y: 40))
        edit(&b, y) { $0.w = 300; $0.h = 50 }
        let r = { (id: UUID) in b.items.first { $0.id == id }!.rect }
        #expect(b.arrange([x], .left) == 0)
        b.arrange([x, y, z], .left); #expect(r(x).x == 10 && r(y).x == 10 && r(z).x == 10)
        b.arrange([x, y, z], .right); #expect(r(x).maxX == 310 && r(y).maxX == 310)
        b.arrange([x, y, z], .top); #expect(r(x).y == 10 && r(y).y == 10 && r(z).y == 10)
        b.arrange([x, y], .bottom); #expect(r(x).maxY == 150 && r(y).maxY == 150)
        b.arrange([x, y, z], .matchWidth); #expect(r(x).w == 300 && r(z).w == 300 && r(x).h == 140)
        b.arrange([x, y], .matchHeight); #expect(r(y).h == 140)
        b.arrange([x, y, z], .centerX); #expect(r(x).midX == r(y).midX && r(y).midX == r(z).midX)
        // Image cards keep their shape: matching width scales the height too.
        let img = b.addAsset(UUID(), aspect: 2, width: 100, at: (x: 0, y: 400))
        b.arrange([img, x], .matchWidth); #expect(r(img).w == 300 && r(img).h == 150)
    }

    @Test func distributeEvensGaps() {
        var b = Moodboard(name: "D"); b.snap = false
        let ids = [0.0, 100, 500].map { x in b.addNote("n", at: (x: x, y: 0)) }
        for id in ids { edit(&b, id) { $0.w = 50 } }
        #expect(b.arrange(Set(ids.prefix(2)), .distributeH) == 0)
        b.arrange(Set(ids), .distributeH)
        let xs = ids.map { id in b.items.first { $0.id == id }!.x }
        #expect(xs == [0, 250, 500])
        let v = [0.0, 30, 400].map { y in b.addNote("v", at: (x: 900, y: y)) }
        for id in v { edit(&b, id) { $0.h = 100 } }
        b.arrange(Set(v), .distributeV)
        #expect(v.map { id in b.items.first { $0.id == id }!.y } == [0, 200, 400])
    }
}
