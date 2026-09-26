import Foundation
import Testing
@testable import AsssetsCore

@Suite("Rights report export snapshot")
struct RightsReportExportTests {
    @Test func detectsChangedRowsDocumentsAndDay() {
        var c = StudioCatalog()
        let a = c.importFile(path: "/a.png")!, b = c.importFile(path: "/b.png")!
        let d = LicenseDoc(name: "order.pdf")
        _ = c.addLicenseDoc(d, to: [a])
        let snapshot = RightsReportExport(catalog: c, ids: [a,b], title: "Pitch", day: "2026-09-26")!
        #expect(snapshot.stillMatches(c, ids: [a,b], title: "Pitch", day: "2026-09-26"))
        #expect(!snapshot.stillMatches(c, ids: [b,a], title: "Pitch", day: "2026-09-26"))
        #expect(!snapshot.stillMatches(c, ids: [a,b], title: "Other", day: "2026-09-26"))
        #expect(!snapshot.stillMatches(c, ids: [a,b], title: "Pitch", day: "2026-09-27"))
        c.licenseDocs[0].name = "new.pdf"
        #expect(!snapshot.stillMatches(c, ids: [a,b], title: "Pitch", day: "2026-09-26"))
        c.licenseDocs[0].name = d.name
        c.assets[0].rights = UsageRights(license: .editorial)
        #expect(!snapshot.stillMatches(c, ids: [a,b], title: "Pitch", day: "2026-09-26"))
        c.assets[0].rights = nil
        c.assets[0].importedPath = "/same-basename/a.png"
        #expect(!snapshot.stillMatches(c, ids: [a,b], title: "Pitch", day: "2026-09-26"))
    }
    @Test func missingAssetDoesNotShrinkReport() {
        let c = StudioCatalog()
        #expect(RightsReportExport(catalog: c, ids: [UUID()], title: "X", day: "2026-09-26") == nil)
    }
}
