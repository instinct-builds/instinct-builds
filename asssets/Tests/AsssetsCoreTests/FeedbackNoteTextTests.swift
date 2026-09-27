import Foundation
import Testing
@testable import AsssetsCore

@Suite("Feedback note save boundary")
struct FeedbackNoteTextTests {
    @Test func exactPrefixAndTailOnlyChangeDoNotInventReplacement() throws {
        var c = StudioCatalog()
        let a = c.importFile(path: "/notes/long.png")!
        let board = c.createBoard(named: "Review")
        _ = c.addToBoard(board, assets: [a])
        let card = c.board(board)!.items.first { $0.assetID == a }!.id
        let g = UUID().uuidString
        _ = c.recordGallery(GalleryRoster(gallery: g, title: "Review", created: "2026-09-27",
            assets: [a], board: board, cards: [.init(id: card, asset: a)])!)
        func f(_ note: String) -> ReviewGallery.Feedback {
            .init(gallery: g, title: "Review", reviewer: "Mara",
                  items: [.init(id: a.uuidString, favorite: false, note: note)])
        }
        let prefix = String(repeating: "🌿", count: 4_000)
        let exact = f(prefix)
        #expect(c.previewFeedback(exact).rows[0].submittedNoteCount == nil)
        let first = c.applyFeedback(exact)
        #expect(first.notes == 1 && c.assets.first { $0.id == a }!.clientNotes.first?.text == prefix)
        let long = f("  " + prefix + "X  ")
        let p = c.previewFeedback(long)
        #expect(p.rows[0].note == prefix && p.rows[0].submittedNoteCount == 4_001)
        #expect(p.noteReplacements == 0 && p.noteRemovals == 0)
        let r = c.applyFeedback(long)
        #expect(r.notesReplaced == 0 && r.notesRemoved == 0)
        #expect(c.board(board)!.pins()[card]?.comments.first?.text == prefix)
        #expect(c.assets.first { $0.id == a }!.clientNotes.first?.text == prefix)
        let back = StudioCatalog.decode(try c.encoded())!
        #expect(back == c)
    }
    @Test func changedPrefixCountsOneReplacementAndUnicodeCharacterBoundary() {
        var c = StudioCatalog()
        let a = c.importFile(path: "/notes/one.png")!, g = UUID().uuidString
        _ = c.recordGallery(GalleryRoster(gallery: g, title: "Proof", created: "2026-09-27", assets: [a])!)
        let first = ReviewGallery.Feedback(gallery: g, title: "Proof", reviewer: "Mara",
            items: [.init(id: a.uuidString, favorite: false, note: "Old")])
        _ = c.applyFeedback(first)
        let composed = String(repeating: "e\u{301}", count: 4_000)
        let next = ReviewGallery.Feedback(gallery: g, title: "Proof", reviewer: "Mara",
            items: [.init(id: a.uuidString, favorite: false, note: composed + "tail")])
        let p = c.previewFeedback(next)
        #expect(p.noteReplacements == 1 && p.rows[0].submittedNoteCount == 4_004)
        #expect(p.rows[0].note.count == 4_000 && p.rows[0].note == composed)
        let r = c.applyFeedback(next)
        #expect(r.notesReplaced == 1 && c.assets.first { $0.id == a }!.clientNotes.first?.text == composed)
    }
}
