import Foundation
import Testing
@testable import AsssetsCore

@Suite("Usage rights and credits")
struct RightsTests {
    let today = "2026-09-24"

    private func library() -> (StudioCatalog, [String: UUID]) {
        var c = StudioCatalog()
        var ids: [String: UUID] = [:]
        for n in ["lobby", "atrium", "harbor", "plinth", "wire", "stage"] { ids[n] = c.importFile(path: "/drop/\(n).png")! }
        c.setRights(UsageRights(license: .licensed, source: "Northlight", credit: "Photo: Lena Ortiz / Northlight", uses: "Web", expires: "2026-10-06"), for: [ids["lobby"]!])
        c.setRights(UsageRights(license: .licensed, credit: "Photo: Lena Ortiz / Northlight", expires: "2027-03-01"), for: [ids["atrium"]!])
        c.setRights(UsageRights(license: .licensed, credit: "Harbor Stock", expires: "2026-09-15"), for: [ids["harbor"]!])
        c.setRights(UsageRights(license: .client, credit: "Courtesy of Maison Vale"), for: [ids["plinth"]!])
        c.setRights(UsageRights(license: .editorial, credit: "Wirepress"), for: [ids["wire"]!])
        return (c, ids)
    }

    @Test func statusFollowsLicenseAndDate() {
        let (c, ids) = library()
        func st(_ n: String) -> RightsStatus { c.assets.first { $0.id == ids[n] }!.rightsStatus(asOf: today) }
        #expect(st("lobby") == .expiring(12))
        #expect(st("atrium") == .ok)
        #expect(st("harbor") == .expired(9))
        #expect(st("plinth") == .ok)
        #expect(st("wire") == .editorial)
        #expect(st("stage") == .missing)
        #expect(RightsStatus.expired(9).label == "Rights expired 9 days ago" && RightsStatus.expiring(0).label == "Rights end today")
        // The last covered day is still fine; the day after is expired.
        var a = c.assets.first { $0.id == ids["lobby"] }!
        #expect(a.rightsStatus(asOf: "2026-10-06") == .expiring(0))
        #expect(a.rightsStatus(asOf: "2026-10-07") == .expired(1))
        a.sourceKey = "starter:terrazzo-texture.png"; a.rights = nil
        #expect(a.rightsStatus(asOf: today) == .ok)
    }

    @Test func smartRulesAndSeeding() {
        var (c, ids) = library()
        let n = c.seedRightsCollections()
        let again = c.seedRightsCollections()
        #expect(n == 3 && again == 0)
        let expired = c.assets.filter { $0.matches(.expired, asOf: today) }.map(\.id)
        #expect(expired == [ids["harbor"]!])
        #expect(c.assets.filter { $0.matches(.missing, asOf: today) }.map(\.id) == [ids["stage"]!])
        #expect(SmartRules(rights: .expiringSoon).summary.contains("rights ending"))
        // Rules round-trip through JSON with the new field.
        let rules = SmartRules(minRating: 2, rights: .expired)
        let back = try! JSONDecoder().decode(SmartRules.self, from: JSONEncoder().encode(rules))
        #expect(back == rules && !back.isEmpty)
        // Deleting a seeded collection keeps it deleted.
        c.smartCollections.removeAll { $0.name == "Rights Expired" }
        let third = c.seedRightsCollections()
        #expect(third == 0 && !c.smartCollections.contains { $0.name == "Rights Expired" })
    }

    @Test func issuesBoardsAndCredits() {
        var (c, ids) = library()
        let order = ["stage", "wire", "lobby", "harbor", "plinth", "atrium"].map { ids[$0]! }
        let issues = c.rightsIssues(order, asOf: today)
        #expect(issues.map(\.asset) == [ids["wire"]!, ids["harbor"]!])
        let b = c.createBoard(named: "Pitch")
        var cards: [UUID] = []
        _ = c.updateBoard(b) { m in for id in order { cards.append(m.addAsset(id, aspect: 1)) } }
        let probs = c.rightsProblems(on: b, asOf: today)
        #expect(Set(probs.keys) == [cards[1], cards[3]])
        let credits = c.credits(for: order)
        #expect(credits.map(\.credit) == ["Wirepress", "Photo: Lena Ortiz / Northlight", "Harbor Stock", "Courtesy of Maison Vale"])
        #expect(credits[1].titles.count == 2 && credits[1].license == "Licensed")
        // Clearing rights removes them; an empty record counts as none.
        let cleared = c.setRights(UsageRights(), for: [ids["wire"]!])
        #expect(cleared == 1)
        #expect(c.assets.first { $0.id == ids["wire"] }!.rights == nil)
    }

    @Test func dateNormalizing() {
        #expect(UsageRights.normalizeDate("2026-9-4") == "2026-09-04")
        #expect(UsageRights.normalizeDate("2026-09-04T00:00:00Z") == "2026-09-04")
        #expect(UsageRights.normalizeDate("2026-02-30") == nil)
        #expect(UsageRights.normalizeDate("soon") == nil)
        #expect(UsageRights.days(from: "2026-09-24", to: "2026-10-06") == 12)
    }

    @Test func xmpRoundTripAndPreservation() {
        let r = UsageRights(license: .licensed, source: "Northlight & Co", credit: "Photo: Lena Ortiz / Northlight", uses: "Web <1 year>", expires: "2026-10-06")
        let m = FileMetadata(title: "Lobby", keywords: ["stone"], rights: r)
        let fresh = XmpMetadata.packet(m)
        #expect(fresh.contains("xmlns:photoshop=") && fresh.contains("xmlns:asssets=") && fresh.contains("<xmpRights:Marked>True</xmpRights:Marked>"))
        #expect(XmpMetadata.parse(fresh).rights == r)
        // An existing sidecar keeps its other fields; ours are replaced, not duplicated.
        let existing = """
        <x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
         <rdf:Description rdf:about="" xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/" xmlns:photoshop="http://ns.adobe.com/photoshop/1.0/" crs:Exposure2012="+0.35">
          <photoshop:Credit>Old credit</photoshop:Credit>
         </rdf:Description></rdf:RDF></x:xmpmeta>
        """
        let updated = XmpMetadata.update(existing, with: m)
        #expect(updated.contains("crs:Exposure2012=\"+0.35\""))
        #expect(updated.components(separatedBy: "photoshop:Credit>").count == 3 && !updated.contains("Old credit"))
        #expect(updated.components(separatedBy: "xmlns:photoshop=").count == 2)
        #expect(XmpMetadata.parse(updated).rights == r)
        // Without rights to write, another app's credit survives.
        let kept = XmpMetadata.update(existing, with: FileMetadata(title: "Lobby"))
        #expect(kept.contains("Old credit"))
        #expect(XmpMetadata.parse(kept).rights?.credit == "Old credit")
    }

    @Test func fileRightsApplyOnlyWhenEmptyAndCatalogCodes() {
        var c = StudioCatalog()
        let id = c.importFile(path: "/drop/a.png")!
        let fromFile = UsageRights(license: .client, credit: "Courtesy of Vale")
        let applied = c.applyFileMetadata(FileMetadata(rights: fromFile), to: id)
        #expect(applied)
        #expect(c.fileMetadata(for: id)?.rights == fromFile)
        c.applyFileMetadata(FileMetadata(rights: UsageRights(license: .editorial, credit: "Other")), to: id)
        #expect(c.assets[0].rights == fromFile)
        c.rightsSeeded = true
        let back = try! JSONDecoder().decode(StudioCatalog.self, from: JSONEncoder().encode(c))
        #expect(back.assets[0].rights == fromFile && back.rightsSeeded)
        // Older catalogs without the fields still load.
        let old = try! JSONDecoder().decode(UsageRights.self, from: Data(#"{"license":"Nope","credit":"X","expires":"bad"}"#.utf8))
        #expect(old.license == .own && old.credit == "X" && old.expires == nil)
    }

    @Test func galleryManifestCarriesCredits() {
        var m = ReviewGallery.Manifest(title: "Pitch", created: "2026-09-24", items: [])
        m.credits = [CreditLine(credit: "Photo: Lena Ortiz", license: "Licensed", titles: ["Lobby"])]
        let html = ReviewGallery.html(m)
        #expect(html.contains("\"credits\":[") && html.contains("id=\"creditsBtn\""))
    }
}
