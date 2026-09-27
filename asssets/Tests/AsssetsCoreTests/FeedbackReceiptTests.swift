import Foundation
import Testing
@testable import AsssetsCore

@Suite("Feedback replacement result agrees with preview")
struct FeedbackReceiptTests {
    @Test func batchCountsAreSequentialAndOnlyAcceptedNotesCount() {
        var c = StudioCatalog()
        let a = c.importFile(path: "/receipt/a.png")!, b = c.importFile(path: "/receipt/b.png")!
        let g = UUID().uuidString
        let roster = GalleryRoster(gallery: g, title: "Round", created: "2026-09-27", assets: [a, b])!
        _ = c.recordGallery(roster)
        func f(_ who: String, _ entries: [ReviewGallery.Feedback.Entry]) -> ReviewGallery.Feedback {
            .init(gallery: g, title: "Round", reviewer: who, items: entries)
        }
        _ = c.applyFeedback(f("Jordan", [.init(id: a.uuidString, favorite: false, note: "Old A"),
                                         .init(id: b.uuidString, favorite: false, note: "Old B")]))
        _ = c.applyFeedback(f("Sam", [.init(id: b.uuidString, favorite: false, note: "Sam stays")]))
        let update = f("Jordan", [.init(id: a.uuidString, favorite: false, note: "New A")])
        let empty = f("Sam", [])
        let firstPreview = c.previewFeedback(update)
        let first = c.applyFeedback(update)
        let secondPreview = c.previewFeedback(empty)
        let second = c.applyFeedback(empty)
        #expect(first.notesRemoved == firstPreview.noteRemovals && first.notesReplaced == firstPreview.noteReplacements)
        #expect(second.notesRemoved == secondPreview.noteRemovals && second.notesReplaced == secondPreview.noteReplacements)
        #expect(first.notesRemoved + second.notesRemoved == 2)
        #expect(first.notesReplaced + second.notesReplaced == 1)
        #expect(first.notes + second.notes == 1)
        let outsider = f("Jordan", [.init(id: UUID().uuidString, favorite: false, note: "Outside")])
        let skipped = c.applyFeedback(outsider)
        #expect(skipped.notesRemoved == 0 && skipped.notesReplaced == 0 && skipped.unknown == 1)
    }
}
