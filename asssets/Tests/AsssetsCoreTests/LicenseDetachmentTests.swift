import Testing
import Foundation
@testable import AsssetsCore

struct LicenseDetachmentTests {
    private func fixture() -> (StudioCatalog, LicenseDoc, LicenseDoc, UUID) {
        var c = StudioCatalog()
        let a = c.importFile(path: "/lib/lobby.png")!
        let b = c.importFile(path: "/lib/atrium.png")!
        let first = LicenseDoc(name: "order.pdf", bytes: 200)
        let second = LicenseDoc(name: "receipt.eml", bytes: 300)
        _ = c.addLicenseDoc(first, to: [a,b])
        _ = c.addLicenseDoc(second, to: [a])
        c.saveRightsPreset(name: "Northlight", rights: UsageRights(license: .licensed), docs: [first.id])
        return (c,first,second,a)
    }

    @Test func selectedDetachesOnlyExactRecordAndLinks() {
        var (c, first, second, a) = fixture()
        let review = MissingLicenseDetachment(catalog: c, missing: [first.id, second.id], selected: first.id)!
        #expect(!review.allMissing && review.entries.count == 1)
        #expect(review.assetLinkCount == 2 && review.presetLinkCount == 1)
        let didDetach = c.detachMissingLicenses(review, missing: [first.id, second.id])
        #expect(didDetach)
        #expect(c.licenseDoc(first.id) == nil && c.licenseDoc(second.id) == second)
        #expect(c.assets.first { $0.id == a }?.licenseDocs == [second.id])
        #expect(c.rightsPresets.first?.docs == [])
    }

    @Test func allDetachesEntireReviewedSetButNotNewlyMissing() {
        var (c, first, second, _) = fixture()
        let review = MissingLicenseDetachment(catalog: c, missing: [first.id, second.id])!
        #expect(review.allMissing && review.entries.count == 2)
        let didDetach = c.detachMissingLicenses(review, missing: [first.id, second.id])
        #expect(didDetach)
        #expect(c.licenseDocs.isEmpty && c.assets.allSatisfy { $0.licenseDocs.isEmpty })
        #expect(c.rightsPresets.first?.docs.isEmpty == true)
        let later = LicenseDoc(name: "later.pdf")
        var (fresh, _, _, a) = fixture()
        _ = fresh.addLicenseDoc(later, to: [a])
        #expect(!review.stillMatches(fresh, missing: [first.id, second.id, later.id]))
        let newMissingResult = fresh.detachMissingLicenses(review, missing: [first.id, second.id, later.id])
        #expect(!newMissingResult)
    }

    @Test func staleReviewAbortsWholeBatch() {
        let (original, first, second, a) = fixture()
        let review = MissingLicenseDetachment(catalog: original, missing: [first.id, second.id])!
        var repaired = original
        let repairedResult = repaired.detachMissingLicenses(review, missing: [second.id])
        #expect(!repairedResult)
        #expect(repaired == original)
        var relinked = original
        relinked.assets[relinked.assets.firstIndex { $0.id == a }!].licenseDocs.reverse()
        let relinkedResult = relinked.detachMissingLicenses(review, missing: [first.id, second.id])
        #expect(!relinkedResult)
        var renamed = original
        renamed.licenseDocs[0].name = "other.pdf"
        let renamedResult = renamed.detachMissingLicenses(review, missing: [first.id, second.id])
        #expect(!renamedResult)
        var presetChanged = original
        presetChanged.rightsPresets[0].name = "Other"
        let presetResult = presetChanged.detachMissingLicenses(review, missing: [first.id, second.id])
        #expect(!presetResult)
        #expect(MissingLicenseDetachment(catalog: original, missing: [first.id], selected: second.id) == nil)
        #expect(MissingLicenseDetachment(catalog: original, missing: [first.id, second.id], selected: nil) != nil)
        // A canceled review is just a value, not a catalog mutation.
        #expect(original.licenseDocs.count == 2)
    }
}
