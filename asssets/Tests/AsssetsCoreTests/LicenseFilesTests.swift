import Foundation
import Testing
@testable import AsssetsCore

@Suite("License files, rights presets and the export check")
struct LicenseFilesTests {
    let today = "2026-09-24"

    private func library() -> (StudioCatalog, [String: UUID]) {
        var c = StudioCatalog()
        var ids: [String: UUID] = [:]
        for n in ["Lobby", "Atrium", "Harbor", "Stage"] { ids[n] = c.importFile(path: "/drop/\(n).png")! }
        c.setRights(UsageRights(license: .licensed, source: "Harbor", credit: "Harbor", expires: "2026-09-15"), for: [ids["Harbor"]!])
        c.setRights(UsageRights(license: .editorial, source: "Wire"), for: [ids["Stage"]!])
        return (c, ids)
    }

    @Test func attachDetachAndCoverage() {
        var (c, ids) = library()
        let order = LicenseDoc(name: "NL-20417 order.pdf", added: today, bytes: 253_952)
        #expect(c.addLicenseDoc(order, to: [ids["Lobby"]!, ids["Atrium"]!]) == 2)
        #expect(c.attachLicenseDoc(order.id, to: [ids["Lobby"]!]) == 0)   // already there
        let mail = LicenseDoc(name: "Receipt.eml", added: today, bytes: 900)
        c.addLicenseDoc(mail, to: [ids["Atrium"]!])
        #expect(c.licenseDocs(for: ids["Atrium"]!).map(\.name) == ["NL-20417 order.pdf", "Receipt.eml"])
        let cov = c.licenseDocCoverage([ids["Lobby"]!, ids["Atrium"]!, ids["Stage"]!])
        #expect(cov.map(\.count) == [2, 1])
        #expect(c.detachLicenseDoc(order.id, from: [ids["Lobby"]!, ids["Stage"]!]) == 1)
        #expect(c.unusedLicenseDocs.isEmpty)
        c.detachLicenseDoc(mail.id, from: [ids["Atrium"]!])
        #expect(c.pruneLicenseDocs().map(\.id) == [mail.id] && c.licenseDocs.count == 1)
        #expect(order.kind == .pdf && mail.kind == .email && order.sizeLabel == "248 KB")
    }

    @Test func missingLicenseRepairPreservesIdentityAndLinks() throws {
        var (c, ids) = library()
        let d = LicenseDoc(name: "order.pdf", added: today, bytes: 10)
        c.addLicenseDoc(d, to: [ids["Lobby"]!, ids["Atrium"]!])
        let savedPreset = c.saveRightsPreset(name: "Order", rights: UsageRights(license: .licensed), docs: [d.id])
        let pid = try #require(savedPreset)
        let review = try #require(MissingLicenseRepair(catalog: c, id: d.id))
        #expect(Set(review.assetIDs) == Set([ids["Lobby"]!, ids["Atrium"]!]) && review.presetIDs == [pid])
        let wrongType = c.recordRepairedLicense(review, name: "new.txt", bytes: 22)
        let empty = c.recordRepairedLicense(review, name: "new.pdf", bytes: 0)
        let repaired = c.recordRepairedLicense(review, name: "new.pdf", bytes: 22)
        #expect(!wrongType && !empty && repaired)
        let updated = try #require(c.licenseDoc(d.id))
        #expect(updated.id == d.id && updated.stored == d.stored && updated.added == d.added)
        #expect(updated.name == "new.pdf" && updated.bytes == 22)
        #expect(c.assets.filter { $0.licenseDocs.contains(d.id) }.map(\.id) == review.assetIDs)
        #expect(c.rightsPreset(pid)?.docs == [d.id])
        let back = try #require(StudioCatalog.decode(c.encoded()))
        #expect(back.licenseDoc(d.id) == updated && back.rightsPreset(pid)?.docs == [d.id])
        #expect(!review.stillMatches(c))
        let stale = c.recordRepairedLicense(review, name: "stale.pdf", bytes: 9)
        #expect(!stale)
    }

    @Test func missingLicenseRepairRejectsChangedLinks() throws {
        var (c, ids) = library()
        let d = LicenseDoc(name: "order.pdf")
        c.addLicenseDoc(d, to: [ids["Lobby"]!])
        let review = try #require(MissingLicenseRepair(catalog: c, id: d.id))
        c.attachLicenseDoc(d.id, to: [ids["Atrium"]!])
        let stale = c.recordRepairedLicense(review, name: "order.pdf", bytes: 42)
        #expect(!review.stillMatches(c) && !stale)
        #expect(c.licenseDoc(d.id) == d)
    }

    @Test func storedNamesAreSafe() {
        let id = UUID(uuidString: "ABCDEF12-0000-0000-0000-000000000000")!
        #expect(LicenseDoc.storedName(for: "../a/b:c.pdf", id: id) == "abcdef12-a-b-c.pdf")
        #expect(LicenseDoc.storedName(for: "", id: id) == "abcdef12-license")
        let long = String(repeating: "x", count: 120) + ".pdf"
        #expect(LicenseDoc.storedName(for: long, id: id).count <= 9 + 75 && LicenseDoc.storedName(for: long, id: id).hasSuffix(".pdf"))
    }

    @Test func presetsSaveReplaceAndApply() {
        var (c, ids) = library()
        let doc = LicenseDoc(name: "NL-20417 order.pdf", added: today)
        c.addLicenseDoc(doc, to: [])
        let r = UsageRights(license: .licensed, source: "Northlight Images", credit: "Photo: {title} / Northlight", uses: "Web and social", renewed: "2026-01-01")
        let pid = c.saveRightsPreset(name: "Northlight order", rights: r, termYears: 1, docs: [doc.id, UUID()])!
        #expect(c.rightsPresets.count == 1 && c.rightsPreset(pid)?.docs == [doc.id] && c.rightsPreset(pid)?.rights.renewed == nil)
        #expect(c.saveRightsPreset(name: "  northlight ORDER ", rights: r, termYears: 1, docs: [doc.id]) == pid && c.rightsPresets.count == 1)
        #expect(c.saveRightsPreset(name: " ", rights: r) == nil)
        #expect(c.rightsPreset(pid)!.summary() == "Licensed · Northlight Images · 1-year term · 1 file")

        c.markRenewed([ids["Atrium"]!], today: "2026-02-01")
        let n = c.applyRightsPreset(pid, to: [ids["Lobby"]!, ids["Atrium"]!], today: today)
        #expect(n == 2)
        let a = { (k: String) in c.assets.first { $0.id == ids[k] }! }
        #expect(a("Lobby").rights?.credit == "Photo: Lobby / Northlight" && a("Lobby").rights?.expires == "2027-09-24")
        #expect(a("Atrium").rights?.renewed == "2026-02-01" && a("Atrium").licenseDocs == [doc.id])
        #expect(c.applyRightsPreset(pid, to: [ids["Lobby"]!], today: today) == 0)   // nothing new
        // Files a preset holds are not pruned.
        c.detachLicenseDoc(doc.id, from: [ids["Lobby"]!, ids["Atrium"]!])
        #expect(c.unusedLicenseDocs.isEmpty)
        c.deleteRightsPreset(pid)
        #expect(c.unusedLicenseDocs.map(\.id) == [doc.id])
    }

    @Test func draftFromAsset() {
        var (c, ids) = library()
        #expect(c.presetDraft(from: ids["Lobby"]!) == nil)
        c.addLicenseDoc(LicenseDoc(name: "h.pdf"), to: [ids["Harbor"]!])
        let d = c.presetDraft(from: ids["Harbor"]!)!
        #expect(d.name == "Harbor" && d.docs.count == 1 && d.rights.expires == "2026-09-15")
    }

    @Test func rightsCheckSplitsClearedFromProblems() {
        let (c, ids) = library()
        let chk = c.rightsCheck([ids["Harbor"]!, ids["Lobby"]!, ids["Stage"]!, ids["Lobby"]!, UUID()], asOf: today)
        #expect(chk.cleared == [ids["Lobby"]!])
        #expect(chk.issues.map(\.asset) == [ids["Harbor"]!, ids["Stage"]!])
    }

    @Test func reportListsFilesAndCatalogRoundTrips() throws {
        var (c, ids) = library()
        let doc = LicenseDoc(name: "Harbor; invoice.pdf", added: today, bytes: 10)
        c.addLicenseDoc(doc, to: [ids["Harbor"]!])
        c.saveRightsPreset(name: "Harbor", rights: UsageRights(license: .licensed, source: "Harbor"), docs: [doc.id])
        let rep = c.rightsReport([ids["Harbor"]!, ids["Lobby"]!], title: "T", today: today)
        #expect(rep.rows[0].licenseFiles == ["Harbor; invoice.pdf"] && rep.docs.map(\.id) == [doc.id])
        #expect(RightsReport.columns.last == "License files" && rep.csv.components(separatedBy: "\r\n")[1].hasSuffix(",\"Harbor; invoice.pdf\"") == false)
        #expect(rep.csv.components(separatedBy: "\r\n")[1].hasSuffix(",Harbor; invoice.pdf"))
        let back = StudioCatalog.decode(try c.encoded())!
        #expect(back.licenseDocs == c.licenseDocs && back.rightsPresets == c.rightsPresets)
        #expect(back.assets.first { $0.id == ids["Harbor"] }?.licenseDocs == [doc.id])
        // Older catalogs without the new keys still load.
        var json = try JSONSerialization.jsonObject(with: c.encoded()) as! [String: Any]
        json.removeValue(forKey: "licenseDocs"); json.removeValue(forKey: "rightsPresets")
        let old = StudioCatalog.decode(try JSONSerialization.data(withJSONObject: json))!
        #expect(old.licenseDocs.isEmpty && old.rightsPresets.isEmpty)
    }

    @Test func creditsNameLicenseFiles() throws {
        var (c, ids) = library()
        c.setRights(UsageRights(license: .licensed, credit: "Northlight"), for: [ids["Lobby"]!, ids["Atrium"]!])
        let d = LicenseDoc(name: "order.pdf")
        c.addLicenseDoc(d, to: [ids["Lobby"]!, ids["Atrium"]!])
        let lines = c.credits(for: [ids["Lobby"]!, ids["Atrium"]!, ids["Harbor"]!])
        #expect(lines.count == 2 && lines[0].files == [CreditFile(name: "order.pdf")] && lines[1].files == nil)
        let old = try JSONDecoder().decode(CreditLine.self, from: Data(#"{"credit":"a","license":"b","titles":[]}"#.utf8))
        #expect(old.files == nil)
    }
}
