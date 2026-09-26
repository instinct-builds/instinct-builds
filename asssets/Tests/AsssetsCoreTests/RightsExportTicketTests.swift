import Foundation
import Testing
@testable import AsssetsCore

@Suite("Rights export review tickets")
struct RightsExportTicketTests {
    @Test func unchangedScopeAndRights() {
        var c = StudioCatalog()
        let id = c.importFile(path: "/a.png")!
        let ticket = RightsExportTicket(catalog: c, ids: [id], day: "2026-09-26", decision: .cleared)!
        #expect(ticket.stillMatches(c, day: "2026-09-26", scope: [id]))
        #expect(!ticket.stillMatches(c, day: "2026-09-27", scope: [id]))
        #expect(!ticket.stillMatches(c, day: "2026-09-26", scope: []))
        c.assets[0].title = "New title"
        #expect(!ticket.stillMatches(c, day: "2026-09-26", scope: [id]))
    }
    @Test func midnightExpiryAndRightsEditFailClosed() {
        var c = StudioCatalog()
        let id = c.importFile(path: "/a.png")!
        c.assets[0].rights = UsageRights(license: .licensed, expires: "2026-09-26")
        let ticket = RightsExportTicket(catalog: c, ids: [id], day: "2026-09-26", decision: .cleared)!
        #expect(!ticket.stillMatches(c, day: "2026-09-27", scope: [id]))
        #expect(RightsExportTicket(catalog: c, ids: [id], day: "2026-09-27", decision: .cleared) == nil)
        c.assets[0].rights?.expires = "2027-09-26"
        #expect(!ticket.stillMatches(c, day: "2026-09-26", scope: [id]))
    }
    @Test func leaveOutCannotAddNewBoardCardOrRetainChangedRight() {
        var c = StudioCatalog()
        let good = c.importFile(path: "/good.png")!, bad = c.importFile(path: "/bad.png")!
        c.assets[c.assets.firstIndex { $0.id == bad }!].rights = UsageRights(license: .editorial)
        let ticket = RightsExportTicket(catalog: c, ids: [good], day: "2026-09-26", decision: .leaveOut,
                                        reviewedIDs: [good,bad], boardItems: [UUID(), UUID()])!
        #expect(ticket.stillMatches(c, day: "2026-09-26", scope: [good,bad], boardItems: ticket.boardItems))
        #expect(!ticket.stillMatches(c, day: "2026-09-26", scope: [good,bad,UUID()], boardItems: ticket.boardItems))
        #expect(!ticket.stillMatches(c, day: "2026-09-26", scope: [good,bad], boardItems: [UUID(), UUID()]))
        c.assets[c.assets.firstIndex { $0.id == good }!].rights = UsageRights(license: .editorial)
        #expect(!ticket.stillMatches(c, day: "2026-09-26", scope: [good,bad], boardItems: ticket.boardItems))
    }
    @Test func anywayRequiresExactReviewedProblem() {
        var c = StudioCatalog()
        let id = c.importFile(path: "/a.png")!
        c.assets[0].rights = UsageRights(license: .editorial)
        let ticket = RightsExportTicket(catalog: c, ids: [id], day: "2026-09-26", decision: .anyway)!
        #expect(ticket.stillMatches(c, day: "2026-09-26"))
        c.assets[0].rights = UsageRights(license: .licensed)
        #expect(!ticket.stillMatches(c, day: "2026-09-26"))
    }
}
