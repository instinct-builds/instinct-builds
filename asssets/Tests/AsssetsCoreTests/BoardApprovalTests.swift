import Foundation
import Testing
@testable import AsssetsCore

@Suite("Board approval, replies and round summary")
struct BoardApprovalTests {
    @Test func statusesOnlyOnAssetCards() {
        var b = Moodboard(name: "B")
        let a = b.addAsset(UUID(), aspect: 1), c = b.addAsset(UUID(), aspect: 1)
        let note = b.addNote("n")
        #expect(b.status(of: a) == .open)
        let n = b.setStatus(.approved, for: [a, note]); #expect(n == 1)
        let again = b.setStatus(.approved, for: [a]); #expect(again == 0)
        b.setStatus(.changes, for: [c])
        #expect(b.cards(with: .approved) == [a] && b.cards(with: .changes) == [c] && b.cards(with: .open).isEmpty)
        #expect(b.statusCounts == [.open: 0, .approved: 1, .changes: 1])
        b.setStatus(.open, for: [a])
        #expect(b.statuses[a] == nil && b.statusCounts[.open] == 1)
    }

    @Test func repliesThreadInOrder() {
        var b = Moodboard(name: "B")
        let a = b.addAsset(UUID(), aspect: 1)
        let r1 = b.addReply(to: a, author: "  ", text: "Warmer backdrop coming", posted: "2026-09-24T10:00:00Z")
        let r2 = b.addReply(to: a, author: "Spence", text: "Done - see v3", posted: "2026-09-24T09:00:00Z")
        let none1 = b.addReply(to: a, author: "x", text: "   ", posted: ""), none2 = b.addReply(to: UUID(), author: "x", text: "hi", posted: "")
        #expect(r1 != nil && r2 != nil && none1 == nil && none2 == nil)
        #expect(b.replies(for: a).map(\.text) == ["Done - see v3", "Warmer backdrop coming"])
        #expect(b.replies(for: a).last?.author == "Studio")
        b.editReply(r1!, text: "Warmer backdrop in v3"); #expect(b.replies.first { $0.id == r1 }?.text == "Warmer backdrop in v3")
        b.editReply(r2!, text: " "); #expect(b.replies.count == 1)
        b.deleteReply(r1!); #expect(b.replies.isEmpty)
        let long = b.addReply(to: a, author: "S", text: String(repeating: "x", count: 5000), posted: "")
        #expect(long != nil && b.replies[0].text.count == Moodboard.maxReplyLength)
    }

    @Test func threadedCardsAndSummary() {
        var c = StudioCatalog()
        let x = c.importFile(path: "/x/plinth.png")!, y = c.importFile(path: "/x/stage.png")!, z = c.importFile(path: "/x/grain.png")!
        let board = c.createBoard(named: "Lobby")
        _ = c.addToBoard(board, assets: [x, y, z])
        c.noteGalleryShared("G", from: board)
        _ = c.applyFeedback(ReviewGallery.Feedback(gallery: "G", title: "", reviewer: "Mara", items: [
            .init(id: x.uuidString, favorite: true, note: "This one")]), imported: "2026-09-23")
        let cards = c.board(board)!.readingOrder.map(\.id)
        _ = c.updateBoard(board) { b in
            b.setStatus(.approved, for: [cards[0]]); b.setStatus(.changes, for: [cards[1]])
            b.addReply(to: cards[1], author: "Spence", text: "Swapping the screen art", posted: "t")
        }
        let b = c.board(board)!
        #expect(b.threadedCards() == [cards[0], cards[1]])
        let s = c.roundSummary(board)!
        #expect(s.board == "Lobby" && s.reviewers == ["Mara"] && s.rows.count == 3)
        #expect(s.rows[0].status == .approved && s.rows[0].pickedBy == ["Mara"] && s.rows[0].comments.first?.text == "This one")
        #expect(s.rows[1].status == .changes && s.rows[1].replies.first?.text == "Swapping the screen art")
        #expect(s.rows[2].status == .open && s.rows[2].title == c.assets.first { $0.id == z }?.title)
        #expect(s.tally == "1 approved · 1 changes · 1 open")
        #expect(c.roundSummary(UUID()) == nil)
    }

    @Test func decodeAndDuplicate() throws {
        var c = StudioCatalog()
        let board = c.createBoard(named: "P")
        _ = c.addToBoard(board, assets: [c.importFile(path: "/x/a.png")!])
        let card = c.board(board)!.items[0].id
        _ = c.updateBoard(board) { b in b.setStatus(.changes, for: [card]); b.addReply(to: card, author: "S", text: "ok", posted: "t") }
        let b = c.board(board)!
        let back = try JSONDecoder().decode(Moodboard.self, from: JSONEncoder().encode(b))
        #expect(back == b && back.status(of: card) == .changes && back.replies.count == 1)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(b)) as! [String: Any]
        json["statuses"] = "junk"; json["replies"] = nil
        let old = try JSONDecoder().decode(Moodboard.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.statuses.isEmpty && old.replies.isEmpty && old.items.count == 1)
        let copy = c.duplicateBoard(board)!
        #expect(c.board(copy)!.statuses.isEmpty && c.board(copy)!.replies.isEmpty)
    }
}
