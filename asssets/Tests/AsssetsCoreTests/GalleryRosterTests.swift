import Foundation
import Testing
@testable import AsssetsCore

@Suite("Gallery feedback provenance")
struct GalleryRosterTests {
    @Test func membershipAndLegacyFailClosed() throws {
        var c = StudioCatalog()
        let inside = c.importFile(path: "/x/in.png")!, outside = c.importFile(path: "/x/out.png")!
        let gallery = UUID().uuidString
        let f = ReviewGallery.Feedback(gallery: gallery, title: "Pitch", reviewer: "Client", items: [
            .init(id: inside.uuidString, favorite: true, note: "yes"),
            .init(id: outside.uuidString, favorite: true, note: "wrong")])
        #expect(c.previewFeedback(f).rosterIssue != nil)
        #expect(c.applyFeedback(f).favorites == 0)
        let roster = GalleryRoster(gallery: gallery, title: "Pitch", created: "2026-09-26", assets: [inside])!
        #expect(c.recordGallery(roster))
        #expect(!c.recordGallery(GalleryRoster(gallery: gallery, title: "Pitch", created: "2026-09-26", assets: [outside])!))
        let p = c.previewFeedback(f)
        #expect(p.picks == 1 && p.skippedCount == 1 && p.rows[1].skipped == "Not in this gallery")
        let result = c.applyFeedback(f)
        #expect(result.favorites == 1 && result.unknown == 1)
        #expect(!c.assets.first { $0.id == outside }!.tags.contains(ReviewGallery.clientPickTag))
        var repeated = f
        repeated.items.append(f.items[0])
        #expect(c.previewFeedback(repeated).rows[2].skipped == "Duplicate asset ID")
        #expect(c.applyFeedback(repeated).unknown == 2)
        c.assets.removeAll { $0.id == inside }
        #expect(c.previewFeedback(f).rows[0].skipped == "No longer in this library")
        #expect(c.applyFeedback(f).favorites == 0)
        let restored = StudioCatalog.decode(try c.encoded())!
        #expect(restored.roster(for: gallery) == roster)
        var noRoster = restored
        noRoster.galleryRosters = []
        var legacy = StudioCatalog.decode(try noRoster.encoded())!
        #expect(legacy.applyFeedback(f).favorites == 0)
    }

    @Test func originalPageManifestRecovery() {
        let id = UUID(), gallery = UUID().uuidString
        let item = ReviewGallery.Item(id: id.uuidString, title: "A", kind: "Image", resolution: "", palette: [], tags: [], image: "images/01.jpg", thumb: "thumbs/01.jpg")
        let manifest = ReviewGallery.Manifest(gallery: gallery, title: "Pitch", created: "2026-09-26", items: [item])
        #expect(ReviewGallery.manifest(fromHTML: ReviewGallery.html(manifest)) == manifest)
        #expect(ReviewGallery.manifest(fromHTML: "not a gallery") == nil)
        #expect(ReviewGallery.manifest(fromHTML: ReviewGallery.html(.init(gallery: gallery, title: "empty", created: "d", items: []))) == nil)
    }
}
