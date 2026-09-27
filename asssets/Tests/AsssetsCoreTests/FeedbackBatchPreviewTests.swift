import Foundation
import Testing
@testable import AsssetsCore

@Suite("Ordered feedback batch preview")
struct FeedbackBatchPreviewTests {
    func fixture() -> (StudioCatalog, UUID, UUID, UUID, String) {
        var c = StudioCatalog()
        let a = c.importFile(path: "/batch/a.png")!, b = c.importFile(path: "/batch/b.png")!
        let board = c.createBoard(named: "Round")
        _ = c.addToBoard(board, assets: [a, b])
        let cards = c.board(board)!.items.compactMap { item -> GalleryRoster.Card? in
            guard let asset = item.assetID else { return nil }
            return .init(id: item.id, asset: asset)
        }
        let g = UUID().uuidString
        _ = c.recordGallery(GalleryRoster(gallery: g, title: "Round", created: "2026-09-27", assets: [a, b], board: board, cards: cards)!)
        return (c, board, a, b, g)
    }
    @Test func differentReviewersSameCardShowOrderAndFinalStatus() throws {
        let (c, board, a, _, g) = fixture()
        func f(_ name: String, _ status: String) -> ReviewGallery.Feedback {
            .init(gallery: g, title: "Round", reviewer: name,
                  items: [.init(id: a.uuidString, favorite: false, note: "", status: status)])
        }
        let approved = f("Jordan", "approved"), changes = f("Sam", "changes")
        let forward = c.previewFeedbackBatch([approved, changes])
        #expect(forward.previews.count == 2 && forward.previews[0].rows[0].from == .open)
        #expect(forward.previews[1].rows[0].from == .approved)
        #expect(forward.conflicts.count == 1 && forward.conflicts[0].final == .changes)
        #expect(forward.conflicts[0].requests.map(\.reviewer) == ["Jordan", "Sam"])
        var applied = c
        _ = applied.applyFeedback(approved); _ = applied.applyFeedback(changes)
        #expect(applied.board(board)!.status(of: forward.conflicts[0].card) == forward.conflicts[0].final)
        let backward = c.previewFeedbackBatch([changes, approved])
        #expect(backward.previews[1].rows[0].from == .changes && backward.conflicts[0].final == .approved)
        #expect(c.board(board)!.status(of: forward.conflicts[0].card) == .open)
        let saved = StudioCatalog.decode(try applied.encoded())!
        #expect(saved == applied)
    }
    @Test func disjointCardsDoNotConflictAndChangedLibraryChangesPreview() {
        let (c, board, a, b, g) = fixture()
        let jordan = ReviewGallery.Feedback(gallery: g, title: "Round", reviewer: "Jordan",
            items: [.init(id: a.uuidString, favorite: false, note: "", status: "approved")])
        let sam = ReviewGallery.Feedback(gallery: g, title: "Round", reviewer: "Sam",
            items: [.init(id: b.uuidString, favorite: false, note: "", status: "changes")])
        let original = c.previewFeedbackBatch([jordan, sam])
        #expect(original.conflicts.isEmpty)
        var moved = c
        _ = moved.applyFeedback(jordan)
        #expect(moved.previewFeedbackBatch([jordan, sam]) != original)
        let changedFile = ReviewGallery.Feedback(gallery: g, title: "Round", reviewer: "Sam",
            items: [.init(id: a.uuidString, favorite: false, note: "", status: "changes")])
        #expect(c.previewFeedbackBatch([jordan, changedFile]) != original)
        #expect(c.board(board)!.statusCounts[.open] == 2)
    }
}
