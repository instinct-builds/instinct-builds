import Foundation
import Testing
@testable import AsssetsCore

@Suite("Feedback import undo")
struct FeedbackUndoTests {
    func fixture() -> (StudioCatalog, GalleryRoster, UUID, UUID) {
        var c = StudioCatalog()
        let a = c.importFile(path: "/u/one.png")!, b = c.importFile(path: "/u/two.png")!
        let g = UUID().uuidString
        let roster = GalleryRoster(gallery: g, title: "Round", created: "2026-10-03", assets: [a, b])!
        _ = c.recordGallery(roster)
        return (c, roster, a, b)
    }
    func feedback(_ g: String, who: String = "Jordan", _ a: UUID, _ b: UUID) -> ReviewGallery.Feedback {
        .init(gallery: g, title: "Round", reviewer: who, items: [
            .init(id: a.uuidString, favorite: true, note: "Warmer backdrop", status: "changes"),
            .init(id: b.uuidString, favorite: false, note: "", status: "approved")])
    }

    @Test func undoRestoresAssetsPicksLedgerAndRostersExactly() {
        let (c0, roster, a, b) = fixture()
        var c = c0
        var h = UndoHistory()
        let before = c
        _ = c.applyFeedback(feedback(roster.gallery, a, b))
        let after = c
        #expect(after != before && !after.feedbackPickLedger.isEmpty)
        let recorded = h.record("Import Client Feedback", before: before, after: after, includeFeedbackState: true)
        #expect(recorded)
        #expect(h.blockedUndoReason(c) == nil)
        let undone = h.undo(&c)
        #expect(undone == "Import Client Feedback")
        #expect(c == before)
        #expect(c.feedbackPickLedger.isEmpty && c.ledgerOwnedPickTags.isEmpty)
        #expect(h.blockedRedoReason(c) == nil)
        let redone = h.redo(&c)
        #expect(redone == "Import Client Feedback")
        #expect(c == after)
    }

    @Test func undoIsRefusedWhenPicksChangedAfterTheImport() {
        let (c0, roster, a, b) = fixture()
        var c = c0
        var h = UndoHistory()
        let before = c
        _ = c.applyFeedback(feedback(roster.gallery, a, b))
        _ = h.record("Import Client Feedback", before: before, after: c, includeFeedbackState: true)
        // A later import that was not recorded changes the ledger. Reverting the first one would discard it.
        _ = c.applyFeedback(feedback(roster.gallery, who: "Sam", a, b))
        let snapshot = c
        #expect(h.blockedUndoReason(c) != nil)
        #expect(h.undoStack.count == 1)
        #expect(c == snapshot)
    }

    @Test func ordinaryStepsAreUnaffectedByTheFeedbackState() {
        let fx = fixture()
        var c = fx.0
        let roster = fx.1, a = fx.2, b = fx.3
        var h = UndoHistory()
        let imported = c
        _ = c.applyFeedback(feedback(roster.gallery, a, b))
        let tagBefore = c
        c.assets[0].favorite.toggle()
        _ = h.record("Toggle Favorite", before: tagBefore, after: c)
        #expect(h.blockedUndoReason(c) == nil)
        _ = h.undo(&c)
        #expect(c == tagBefore && c != imported)
    }
}
