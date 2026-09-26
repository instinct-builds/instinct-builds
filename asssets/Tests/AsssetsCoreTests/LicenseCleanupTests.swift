import Foundation
import Testing
@testable import AsssetsCore

@Suite("Reviewed license Clean Up")
struct LicenseCleanupTests {
    @Test func exactUnusedAndStrayOnly() {
        var c = StudioCatalog()
        let a = c.importFile(path: "/a.png")!
        let used = LicenseDoc(name: "used.pdf"), unused = LicenseDoc(name: "unused.pdf")
        _ = c.addLicenseDoc(used, to: [a]); _ = c.addLicenseDoc(unused, to: [])
        let names = [used.stored, unused.stored, "orphan.eml", ".repair-temp"]
        let review = LicenseCleanupReview(catalog: c, folder: names)!
        #expect(review.unused == [unused] && review.stray == ["orphan.eml"] && review.count == 2)
        #expect(review.apply(to: &c, folder: names))
        #expect(c.licenseDocs == [used] && c.assets.first?.licenseDocs == [used.id])
    }
    @Test func staleReviewAbortsWholeBatch() {
        var c = StudioCatalog()
        let a = c.importFile(path: "/a.png")!, d = LicenseDoc(name: "order.pdf")
        _ = c.addLicenseDoc(d, to: [])
        let review = LicenseCleanupReview(catalog: c, folder: [d.stored, "orphan.txt"])!
        var attached = c
        _ = attached.attachLicenseDoc(d.id, to: [a])
        let attachedBefore = attached
        #expect(!review.apply(to: &attached, folder: [d.stored, "orphan.txt"]))
        #expect(attached == attachedBefore)
        #expect(!review.apply(to: &c, folder: [d.stored, "new.txt"]))
        #expect(c.licenseDocs == [d])
        c.licenseDocs[0].name = "changed.pdf"
        #expect(!review.stillMatches(c, folder: [d.stored, "orphan.txt"]))
    }
    @Test func physicalReviewIdentityMustMatch() {
        var c = StudioCatalog()
        let d = LicenseDoc(name: "invoice.pdf")
        _ = c.addLicenseDoc(d, to: [])
        let file = LicenseCleanupReview.File(name: d.stored, device: 10, inode: 20, bytes: 30, digest: "old")
        let review = LicenseCleanupReview(catalog: c, folder: [d.stored], files: [file])!
        #expect(review.stillMatches(c, folder: [d.stored], files: [file]))
        #expect(!review.stillMatches(c, folder: [d.stored], files: [.init(name: d.stored, device: 10, inode: 21, bytes: 30, digest: "old")]))
        #expect(!review.stillMatches(c, folder: [d.stored], files: [.init(name: d.stored, device: 10, inode: 20, bytes: 30, digest: "new")]))
        #expect(!review.stillMatches(c, folder: [], files: []))
    }
    @Test func absentCopyIsNotAStagedFile() {
        var c = StudioCatalog()
        let d = LicenseDoc(name: "gone.pdf")
        _ = c.addLicenseDoc(d, to: [])
        let review = LicenseCleanupReview(catalog: c, folder: [])!
        #expect(review.unused == [d] && review.files.isEmpty)
        let journal = LicenseCleanupJournal(id: review.id, phase: .staging, beforeDigest: "a", afterDigest: "b", files: review.files, recordCount: review.unused.count)
        #expect(journal.files.isEmpty && journal.recordCount == 1)
    }
    @Test func journalNeverGuessesUnknownCatalog() {
        let j = LicenseCleanupJournal(id: UUID(), phase: .staging, beforeDigest: "before", afterDigest: "after", files: [.init(name: "a.pdf", device: 1, inode: 2, bytes: 3, digest: "hash")], recordCount: 1)
        #expect(j.recovery(for: "before") == .restore)
        #expect(j.recovery(for: "after") == .purge)
        #expect(j.recovery(for: "other") == .manual)
        let bytes = try! JSONEncoder().encode(j)
        #expect(try! JSONDecoder().decode(LicenseCleanupJournal.self, from: bytes) == j)
        let strayOnly = LicenseCleanupJournal(id: UUID(), phase: .staging, beforeDigest: "same", afterDigest: "same", files: j.files, recordCount: 0)
        #expect(strayOnly.recovery(for: "same") == .restore)
        var committed = strayOnly; committed.phase = .committed
        #expect(committed.recovery(for: "same") == .purge)
    }
}
