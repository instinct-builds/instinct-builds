import Foundation
import Testing
@testable import AsssetsCore

@Suite("Feedback note replacement preview")
struct FeedbackNoteReplacementTests {
    typealias E = ReviewGallery.Feedback.Entry
    @Test func shortenedAndEmptyReplacementShowExactRemovedNotes() throws {
        var c = StudioCatalog()
        let a = c.importFile(path: "/notes/a.png")!, b = c.importFile(path: "/notes/b.png")!
        let g = UUID().uuidString
        let roster = GalleryRoster(gallery: g, title: "Round", created: "2026-09-26", assets: [a, b])!
        _ = c.recordGallery(roster)
        func f(_ who: String, _ entries: [E]) -> ReviewGallery.Feedback {
            .init(gallery: g, title: "Round", reviewer: who, items: entries)
        }
        _ = c.applyFeedback(f("Mara", [.init(id: a.uuidString, favorite: false, note: "Keep crop"),
                                      .init(id: b.uuidString, favorite: false, note: "Use warmer")]))
        _ = c.applyFeedback(f("Sam", [.init(id: b.uuidString, favorite: false, note: "Mine stays")]))
        let shortened = f("Mara", [.init(id: a.uuidString, favorite: false, note: "Keep crop updated")])
        let p = c.previewFeedback(shortened)
        #expect(p.noteRemovals == 1 && p.noteReplacements == 1 && p.canImport)
        #expect(p.rows[0].removedNote == "Keep crop" && p.rows[0].replacesNote)
        #expect(p.rows.last?.asset == b && p.rows.last?.removedNote == "Use warmer" && !p.rows.last!.replacesNote)
        _ = c.applyFeedback(shortened)
        #expect(c.assets.first { $0.id == a }!.clientNotes.map(\.text) == ["Keep crop updated"])
        #expect(c.assets.first { $0.id == b }!.clientNotes.map(\.text) == ["Mine stays"])
        let empty = f("Mara", [])
        #expect(c.previewFeedback(empty).noteRemovals == 1 && c.previewFeedback(empty).canImport)
        _ = c.applyFeedback(empty)
        #expect(c.assets.first { $0.id == a }!.clientNotes.isEmpty)
        #expect(c.assets.first { $0.id == b }!.clientNotes.map(\.text) == ["Mine stays"])
        let back = StudioCatalog.decode(try c.encoded())!
        #expect(back.assets == c.assets)
    }
    @Test func outsiderOnlyDoesNotClearNotes() {
        var c = StudioCatalog()
        let a = c.importFile(path: "/notes/a.png")!, g = UUID().uuidString
        _ = c.recordGallery(GalleryRoster(gallery: g, title: "Round", created: "2026-09-26", assets: [a])!)
        let first = ReviewGallery.Feedback(gallery: g, title: "Round", reviewer: "Mara", items: [.init(id: a.uuidString, favorite: false, note: "Keep")])
        _ = c.applyFeedback(first)
        let outsider = ReviewGallery.Feedback(gallery: g, title: "Round", reviewer: "Mara", items: [.init(id: UUID().uuidString, favorite: false, note: "Outside")])
        let preview = c.previewFeedback(outsider)
        #expect(preview.noteRemovals == 0 && !preview.canImport)
        _ = c.applyFeedback(outsider)
        #expect(c.assets.first { $0.id == a }!.clientNotes.map(\.text) == ["Keep"])
    }
}
