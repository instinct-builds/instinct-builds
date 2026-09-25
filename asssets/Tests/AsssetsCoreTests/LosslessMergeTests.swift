import Foundation
import Testing
@testable import AsssetsCore

@Suite("Lossless merge and Library Health")
struct LosslessMergeTests {
    func twoCopies() -> (StudioCatalog, UUID, UUID) {
        var c = StudioCatalog()
        let keep = c.importFile(path: "/lib/orig.png")!
        let copy = c.importFile(path: "/lib/copy.png")!
        return (c, keep, copy)
    }
    func asset(_ c: StudioCatalog, _ id: UUID) -> StudioAsset { c.assets.first { $0.id == id }! }

    @Test func mergeCarriesRatingLabelRightsFilesNotesAndStack() {
        var (c, keep, copy) = twoCopies()
        let other = c.importFile(path: "/lib/v2.png")!
        _ = c.setRating([copy], 4)
        c.assets[c.assets.firstIndex { $0.id == copy }!].label = .purple
        c.assets[c.assets.firstIndex { $0.id == copy }!].rights = UsageRights(license: .licensed, source: "Northlight", credit: "Photo: L. Ortiz")
        c.assets[c.assets.firstIndex { $0.id == copy }!].clientNotes = [ClientNote(reviewer: "Ana", text: "Love it", gallery: "R1")]
        _ = c.addLicenseDoc(LicenseDoc(name: "order.pdf"), to: [copy])
        let stack = c.stack([copy, other])
        let p = c.mergePreview(keep: keep, group: [keep, copy])!
        #expect(p.ratingRaised && p.rating == 4 && p.labelAdopted && p.rightsAdopted && p.licenseFilesAdded == 1 && p.notesAdded == 1 && p.joinsStack)
        #expect(!p.hasRightsConflict && !p.keeperUnchanged)
        #expect(c.mergeDuplicates(keep: keep, remove: [keep, copy]) == 1)
        let k = asset(c, keep)
        #expect(k.rating == 4 && k.label == .purple && k.rights?.source == "Northlight" && k.licenseDocs.count == 1)
        #expect(k.clientNotes.count == 1 && k.stackID == stack)
        #expect(c.unusedLicenseDocs.isEmpty)
    }

    @Test func keeperRatingNeverDrops() {
        var (c, keep, copy) = twoCopies()
        _ = c.setRating([keep], 5); _ = c.setRating([copy], 2)
        #expect(c.mergePreview(keep: keep, group: [keep, copy])!.ratingRaised == false)
        c.mergeDuplicates(keep: keep, remove: [copy])
        #expect(asset(c, keep).rating == 5)
    }

    @Test func conflictingRightsAreFlaggedAndTheChoiceWins() {
        var (c, keep, copy) = twoCopies()
        c.assets[c.assets.firstIndex { $0.id == keep }!].rights = UsageRights(license: .editorial, source: "Wirepress", credit: "Wirepress")
        c.assets[c.assets.firstIndex { $0.id == copy }!].rights = UsageRights(license: .licensed, source: "Northlight", credit: "Northlight")
        let p = c.mergePreview(keep: keep, group: [keep, copy])!
        #expect(p.hasRightsConflict && p.rightsFrom == keep && !p.rightsAdopted)
        let picked = c.mergePreview(keep: keep, group: [keep, copy], rightsFrom: copy)!
        #expect(picked.rightsFrom == copy && picked.rightsAdopted)
        c.mergeDuplicates(keep: keep, remove: [copy], rightsFrom: copy)
        #expect(asset(c, keep).rights?.license == .licensed)
    }

    @Test func renewalStampAloneIsNotAConflict() {
        var (c, keep, copy) = twoCopies()
        let r = UsageRights(license: .licensed, source: "N", credit: "N", expires: "2027-01-01")
        var r2 = r; r2.renewed = "2026-01-01"
        c.assets[c.assets.firstIndex { $0.id == keep }!].rights = r
        c.assets[c.assets.firstIndex { $0.id == copy }!].rights = r2
        #expect(!c.mergePreview(keep: keep, group: [keep, copy])!.hasRightsConflict)
    }

    @Test func boardCardsAndReviewPicksFollowTheKeeper() {
        var (c, keep, copy) = twoCopies()
        let b = c.createBoard(named: "Pitch")
        var card = UUID()
        _ = c.updateBoard(b) { m in
            card = m.addAsset(copy, aspect: 1)
            m.reviews = [BoardReview(gallery: "R1", reviewer: "Ana", imported: "2026-09-01", picks: [copy], notes: [copy: "Hero"])]
        }
        #expect(c.mergePreview(keep: keep, group: [keep, copy])!.boardCardsMoved == 1)
        c.mergeDuplicates(keep: keep, remove: [copy])
        let m = c.boards.first { $0.id == b }!
        #expect(m.items.first { $0.id == card }?.assetID == keep)
        #expect(m.reviews[0].picks == [keep] && m.reviews[0].notes[keep] == "Hero")
    }

    @Test func plainCopyLeavesKeeperUnchanged() {
        let (c, keep, copy) = twoCopies()
        let p = c.mergePreview(keep: keep, group: [keep, copy])!
        #expect(p.removing == 1 && p.keeperUnchanged)
    }

    @Test func healthFindsMissingStrayBigAndUncredited() {
        var c = StudioCatalog()
        let gone = c.importFile(path: "/lib/gone.png")!
        let big = c.importFile(path: "/lib/big.mov")!
        let credited = c.importFile(path: "/lib/ok.png")!
        c.assets[c.assets.firstIndex { $0.id == credited }!].rights = UsageRights(license: .licensed, source: "N", credit: "")
        let used = LicenseDoc(name: "order.pdf")
        _ = c.addLicenseDoc(used, to: [credited])
        let lost = LicenseDoc(name: "receipt.eml")
        _ = c.addLicenseDoc(lost, to: [credited])
        let h = c.health(exists: { $0 != "/lib/gone.png" }, licenseExists: { $0.id != lost.id },
                         licenseFolder: [used.stored, "leftover.pdf", ".DS_Store"],
                         sizes: [big: Int64(300 * 1024 * 1024), gone: Int64(900 * 1024 * 1024), credited: Int64(10)], duplicateSets: 2)
        #expect(h.missingFiles == [gone])
        #expect(h.strayLicenseFiles == ["leftover.pdf"] && h.missingLicenseFiles == [lost.id] && h.unusedLicenseFiles.isEmpty)
        #expect(h.bigFiles.map(\.id) == [big])
        #expect(h.noCredit == [credited])
        #expect(h.issueCount == 7 && h.urgentCount == 2 && !h.isHealthy)
        c.forgetMissingLicenseFiles([lost.id])
        #expect(c.licenseDocs.map(\.id) == [used.id] && c.assets.first { $0.id == credited }!.licenseDocs == [used.id])
    }

    @Test func ownWorkNeedsNoCreditAndEmptyLibraryIsHealthy() {
        var c = StudioCatalog()
        let a = c.importFile(path: "/lib/a.png")!
        c.assets[0].rights = UsageRights(license: .own)
        #expect(c.health(exists: { _ in true }, licenseExists: { _ in true }).isHealthy)
        _ = a
    }
}
