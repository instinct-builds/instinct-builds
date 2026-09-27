import Foundation
import Testing
@testable import AsssetsCore

@Suite("Feedback duplicate reviewer batch")
struct FeedbackDuplicateBatchTests {
    func fixture() -> (StudioCatalog, UUID, String) {
        var c = StudioCatalog()
        let asset = c.importFile(path: "/batch/one.png")!, gallery = UUID().uuidString
        _ = c.recordGallery(GalleryRoster(gallery: gallery, title: "Proof", created: "2026-09-27", assets: [asset])!)
        return (c, asset, gallery)
    }
    func f(_ g: String, _ who: String, _ asset: UUID) -> ReviewGallery.Feedback {
        .init(gallery: g, title: "Proof", reviewer: who,
              items: [.init(id: asset.uuidString, favorite: true, note: "Review")])
    }
    @Test func caseVariantAndBlankClientCollideBeforeSimulation() {
        let (c, a, g) = fixture()
        let first = f(g, "Jordan", a), second = f(g.lowercased(), " jOrDaN ", a)
        let preview = c.previewFeedbackBatch([first, second])
        #expect(preview.duplicates.count == 1 && preview.duplicates[0].indices == [0, 1])
        #expect(preview.duplicates[0].reviewer == "Jordan" && preview.duplicates[0].gallery == g.lowercased())
        #expect(preview.conflicts.isEmpty)
        #expect(preview.previews[0].replaces == preview.previews[1].replaces)
        let blank = c.previewFeedbackBatch([f(g, " ", a), f(g, "Client", a)])
        #expect(blank.duplicates.count == 1 && blank.duplicates[0].reviewer == "Client")
        #expect(FeedbackRoundKey(gallery: g, reviewer: " ") == FeedbackRoundKey(gallery: g, reviewer: "Client"))
        #expect(c.feedbackPickLedger.isEmpty && c.assets.first { $0.id == a }!.clientNotes.isEmpty)
    }
    @Test func differentReviewersRemainActionableAndStateChangesRefreshPreview() {
        let (c, a, g) = fixture()
        let jordan = f(g, "Jordan", a), sam = f(g, "Sam", a)
        let batch = c.previewFeedbackBatch([jordan, sam])
        #expect(batch.duplicates.isEmpty && batch.previews.allSatisfy(\.canImport))
        var changed = c
        _ = changed.applyFeedback(jordan)
        #expect(changed.previewFeedbackBatch([jordan, sam]) != batch)
        #expect(c.previewFeedbackBatch([jordan, f(g, "JORDAN", a)]).duplicates.count == 1)
    }
}
