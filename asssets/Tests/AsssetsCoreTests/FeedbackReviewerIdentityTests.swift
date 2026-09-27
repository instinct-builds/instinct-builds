import Foundation
import Testing
@testable import AsssetsCore

@Suite("Feedback reviewer identity across replacements")
struct FeedbackReviewerIdentityTests {
    typealias E = ReviewGallery.Feedback.Entry

    @Test func caseVariantReplacesOneRoundAndKeepsOtherReviewer() throws {
        var c = StudioCatalog()
        let a = c.importFile(path: "/round/a.png")!, b = c.importFile(path: "/round/b.png")!
        let g = UUID().uuidString
        let board = c.createBoard(named: "Round")
        _ = c.addToBoard(board, assets: [a, b])
        let cards = c.board(board)!.items.compactMap { item -> GalleryRoster.Card? in
            guard let id = item.assetID else { return nil }
            return .init(id: item.id, asset: id)
        }
        let recorded = c.recordGallery(GalleryRoster(gallery: g, title: "Round", created: "2026-09-26", assets: [a, b], board: board, cards: cards)!)
        #expect(recorded)
        func f(_ reviewer: String, _ entries: [E], gallery: String? = nil) -> ReviewGallery.Feedback {
            .init(gallery: gallery ?? g, title: "Round", reviewer: reviewer, items: entries)
        }
        _ = c.applyFeedback(f("Jordan", [.init(id: a.uuidString, favorite: true, note: "Old crop"),
                                         .init(id: b.uuidString, favorite: true, note: "Old lighting")]))
        _ = c.applyFeedback(f("Sam", [.init(id: b.uuidString, favorite: true, note: "Sam stays")]))
        let replacement = f("jOrDaN", [.init(id: a.uuidString, favorite: false, note: "New crop")], gallery: g.lowercased())
        let p = c.previewFeedback(replacement)
        #expect(p.reviewer == "Jordan")
        #expect(p.replaces && p.withdrawals == 2 && p.noteRemovals == 1 && p.noteReplacements == 1)
        #expect(p.rows.first?.removedNote == "Old crop" && p.rows.last?.removedNote == "Old lighting")
        #expect(p.rows.last?.remainsPicked == true)
        let r = c.applyFeedback(replacement)
        #expect(r.withdrawn == 2 && r.notes == 1)
        #expect(c.feedbackPickLedger.count == 2)
        #expect(c.feedbackRound(gallery: g, reviewer: "JORDAN")?.reviewer == "Jordan")
        #expect(c.assets.first { $0.id == a }!.clientNotes.map(\.reviewer) == ["Jordan"])
        #expect(c.assets.first { $0.id == a }!.clientNotes.map(\.text) == ["New crop"])
        #expect(c.assets.first { $0.id == b }!.clientNotes.map(\.text) == ["Sam stays"])
        #expect(c.assets.first { $0.id == b }!.tags.contains(ReviewGallery.clientPickTag))
        let rounds = c.board(board)!.reviews
        #expect(rounds.count == 2)
        #expect(rounds.first { $0.reviewer == "Jordan" }?.notes[a] == "New crop")
        #expect(rounds.first { $0.reviewer == "Jordan" }?.notes[b] == nil)
        #expect(rounds.first { $0.reviewer == "Sam" }?.notes[b] == "Sam stays")
        let back = StudioCatalog.decode(try c.encoded())!
        #expect(back == c)
        let clear = f("JORDAN", [], gallery: g.lowercased())
        #expect(back.previewFeedback(clear).noteRemovals == 1)
        var final = back
        _ = final.applyFeedback(clear)
        #expect(final.assets.first { $0.id == a }!.clientNotes.isEmpty)
        #expect(final.board(board)!.reviews.count == 1)
        #expect(final.board(board)!.reviews[0].reviewer == "Sam")
    }
}
