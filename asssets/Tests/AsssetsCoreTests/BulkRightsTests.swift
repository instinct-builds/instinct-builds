import Foundation
import Testing
@testable import AsssetsCore

@Suite("Bulk rights, renewals and the rights report")
struct BulkRightsTests {
    let today = "2026-09-24"

    private func library() -> (StudioCatalog, [String: UUID]) {
        var c = StudioCatalog()
        var ids: [String: UUID] = [:]
        for n in ["Lobby", "Atrium", "Harbor", "Stage"] { ids[n] = c.importFile(path: "/drop/\(n).png")! }
        c.setRights(UsageRights(license: .licensed, source: "Northlight", credit: "Photo: Lena", uses: "Web", expires: "2026-10-06"), for: [ids["Lobby"]!])
        c.setRights(UsageRights(license: .licensed, source: "Northlight", credit: "Photo: Sam", uses: "Print", expires: "2027-01-01"), for: [ids["Atrium"]!])
        c.setRights(UsageRights(license: .licensed, source: "Harbor", credit: "Harbor, \"K\"", expires: "2026-09-15"), for: [ids["Harbor"]!])
        return (c, ids)
    }

    @Test func commonFieldsReadMixed() {
        let (c, ids) = library()
        let common = c.commonRights([ids["Lobby"]!, ids["Atrium"]!])
        #expect(common.license == .same(.licensed) && common.source == .same("Northlight"))
        #expect(common.credit.isMixed && common.uses.isMixed && common.expires.isMixed && common.count == 2)
        let withNone = c.commonRights([ids["Lobby"]!, ids["Stage"]!])
        #expect(withNone.license.isMixed && withNone.source.isMixed)
    }

    @Test func applyOnlySetFieldsWithPattern() {
        var (c, ids) = library()
        let order = [ids["Atrium"]!, ids["Lobby"]!, ids["Stage"]!]
        let n = c.applyRights(RightsEdit(credit: "Photo: {title} ({n}/3) / Northlight", expires: .some("2027-06-30")), to: order)
        #expect(n == 3)
        let r = { (k: String) in c.assets.first { $0.id == ids[k] }!.rights! }
        #expect(r("Atrium").credit == "Photo: Atrium (1/3) / Northlight" && r("Lobby").credit == "Photo: Lobby (2/3) / Northlight")
        #expect(r("Lobby").uses == "Web" && r("Atrium").uses == "Print" && r("Lobby").source == "Northlight")
        #expect(r("Stage").license == .own && r("Stage").expires == "2027-06-30")
        // Removing the end date; an empty edit changes nothing.
        let removed = c.applyRights(RightsEdit(expires: .some(nil)), to: [ids["Lobby"]!])
        #expect(removed == 1 && r("Lobby").expires == nil)
        let none = c.applyRights(RightsEdit(), to: order)
        #expect(none == 0)
    }

    @Test func extendAndRenew() {
        var (c, ids) = library()
        let n = c.extendRights([ids["Lobby"]!, ids["Harbor"]!, ids["Stage"]!], today: today)
        #expect(n == 2)
        let r = { (k: String) in c.assets.first { $0.id == ids[k] }?.rights }
        #expect(r("Lobby")?.expires == "2027-10-06")
        #expect(r("Harbor")?.expires == "2027-09-24")   // already expired: a year from today
        #expect(r("Stage") == nil)
        let m = c.markRenewed([ids["Stage"]!, ids["Atrium"]!], today: today)
        #expect(m == 2 && r("Stage")?.renewed == today && r("Stage")?.expires == "2027-09-24" && r("Atrium")?.license == .licensed)
        #expect(UsageRights.adding(years: 1, to: "2028-02-29") == "2029-02-28")
    }

    @Test func expiredSinceAndAlertCounts() {
        let (c, ids) = library()
        #expect(c.expired(since: "2026-09-04", today: today).map(\.asset) == [ids["Harbor"]!])
        #expect(c.expired(since: "2026-09-20", today: today).isEmpty)
        let a = c.rightsAlertCounts(today: today)
        #expect(a.expiring == 1 && a.expired == 1)
    }

    @Test func reportSortsProblemsFirstAndQuotesCSV() {
        let (c, ids) = library()
        let rep = c.rightsReport([ids["Stage"]!, ids["Atrium"]!, ids["Lobby"]!, ids["Harbor"]!, ids["Harbor"]!], title: "Pitch", today: today)
        #expect(rep.rows.map(\.title) == ["Harbor", "Lobby", "Stage", "Atrium"])
        #expect(rep.rows[0].status == "Rights expired 9 days ago" && rep.rows[2].status == "No rights info")
        let c4 = rep.counts
        #expect(c4.problems == 1 && c4.expiring == 1 && c4.missing == 1 && c4.ok == 1)
        let lines = rep.csv.components(separatedBy: "\r\n")
        #expect(lines[0] == RightsReport.columns.joined(separator: ","))
        #expect(lines[1].contains("\"Harbor, \"\"K\"\"\"") && lines[1].hasPrefix("Harbor,Harbor.png,"))
        #expect(lines.count == 6 && lines.last == "")
    }

    @Test func renewedRoundTripsThroughXmpAndJSON() {
        let r = UsageRights(license: .licensed, credit: "C", expires: "2027-09-24", renewed: "2026-09-24")
        #expect(XmpMetadata.parse(XmpMetadata.packet(FileMetadata(rights: r))).rights == r)
        let back = try! JSONDecoder().decode(UsageRights.self, from: JSONEncoder().encode(r))
        #expect(back == r && !UsageRights(renewed: "2026-01-01").isEmpty)
    }
}
