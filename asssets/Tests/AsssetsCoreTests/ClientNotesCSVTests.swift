import Foundation
import Testing
@testable import AsssetsCore

@Suite("Client notes CSV")
struct ClientNotesCSVTests {
    @Test func oneRowPerNoteSortedAndSpreadsheetSafe() {
        var c = StudioCatalog()
        let a = c.importFile(path: "/notes/zebra.png")!, b = c.importFile(path: "/notes/apple.png")!
        let g = UUID().uuidString
        _ = c.recordGallery(GalleryRoster(gallery: g, title: "Round, one", created: "2026-10-01", assets: [a, b])!)
        _ = c.applyFeedback(.init(gallery: g, title: "Round, one", reviewer: "Sam", items: [
            .init(id: a.uuidString, favorite: false, note: "=HYPERLINK(\"x\")"),
            .init(id: b.uuidString, favorite: false, note: "Line one\nLine \"two\"")]))
        _ = c.applyFeedback(.init(gallery: g, title: "Round, one", reviewer: "Alex", items: [
            .init(id: a.uuidString, favorite: true, note: "Crop tighter")]))
        let rows = ClientNotesCSV.rows(c.assets, galleryTitles: ["\(g.lowercased())": "Round, one"])
        #expect(c.clientNoteCount == 3 && rows.count == 3)
        #expect(rows[0][2] == "Sam" && rows[0][1] == "apple.png")
        #expect(rows[1][2] == "Alex" && rows[2][2] == "Sam")
        let csv = c.clientNotesCSV()
        #expect(csv.hasPrefix("\"Asset title\",\"Source filename\",\"Reviewer\",\"Gallery\",\"Note\"\r\n"))
        #expect(csv.contains("\"'=HYPERLINK(\"\"x\"\")\""))
        #expect(csv.contains("\"Line one\nLine \"\"two\"\"\""))
        #expect(csv.contains("\"Round, one\""))
        #expect(!csv.contains("/notes/"))
    }

    @Test func noNotesIsHeaderOnly() {
        #expect(StudioCatalog().clientNoteCount == 0)
        #expect(StudioCatalog().clientNotesCSV().components(separatedBy: "\r\n").count == 2)
    }
}
