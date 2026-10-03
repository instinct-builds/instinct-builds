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
        #expect(csv.hasPrefix("\"Asset title\",\"Source filename\",\"Reviewer\",\"Gallery\",\"Note\",\"Status\"\r\n"))
        #expect(csv.contains("\"'=HYPERLINK(\"\"x\"\")\""))
        #expect(csv.contains("\"Line one\nLine \"\"two\"\"\""))
        #expect(csv.contains("\"Round, one\""))
        #expect(!csv.contains("/notes/"))
    }

    @Test func resolvedTicksSurviveOnlyIdenticalReimportAndOldCatalogsDecode() throws {
        var c = StudioCatalog()
        let a = c.importFile(path: "/notes/a.png")!, b = c.importFile(path: "/notes/b.png")!
        let g = UUID().uuidString
        _ = c.recordGallery(GalleryRoster(gallery: g, title: "Round", created: "2026-10-02", assets: [a, b])!)
        func fb(_ who: String, _ aNote: String, _ bNote: String) -> ReviewGallery.Feedback {
            .init(gallery: g, title: "Round", reviewer: who, items: [
                .init(id: a.uuidString, favorite: false, note: aNote), .init(id: b.uuidString, favorite: false, note: bNote)])
        }
        _ = c.applyFeedback(fb("Sam", "Crop tighter", "Warmer"))
        _ = c.applyFeedback(fb("Alex", "Crop tighter", "Cooler"))
        #expect(c.openClientNoteCount == 4)
        let samA = c.assets.first { $0.id == a }!.clientNotes.first { $0.reviewer == "Sam" }!
        let ticked = c.setClientNote(samA, on: a, resolved: true)
        #expect(ticked && c.openClientNoteCount == 3)
        // Alex's identical text on the same asset is a different note and stays open.
        #expect(c.assets.first { $0.id == a }!.clientNotes.first { $0.reviewer == "Alex" }!.resolved == false)
        _ = c.applyFeedback(fb("Sam", "Crop tighter", "Much warmer"))
        let after = c.assets.flatMap(\.clientNotes).filter { $0.reviewer == "Sam" }
        #expect(after.first { $0.text == "Crop tighter" }?.resolved == true)
        #expect(after.first { $0.text == "Much warmer" }?.resolved == false)
        _ = c.applyFeedback(fb("Sam", "Crop tighter again", "Much warmer"))
        #expect(c.assets.flatMap(\.clientNotes).first { $0.text == "Crop tighter again" }?.resolved == false)
        let stale = c.setClientNote(samA, on: a, resolved: true)
        #expect(!stale)
        let csv = c.clientNotesCSV()
        #expect(csv.contains("\"Open\"") && !csv.contains("\"Resolved\""))
        var d = StudioCatalog()
        let x = d.importFile(path: "/notes/x.png")!
        d.assets[0].clientNotes = [ClientNote(reviewer: "R", text: "t", gallery: "g", resolved: true)]
        let data = try JSONEncoder().encode(d.assets[0])
        #expect(d.assets[0].id == x)
        #expect(try JSONDecoder().decode(StudioAsset.self, from: data).clientNotes[0].resolved)
        let legacy = #"{"reviewer":"R","text":"t","gallery":"g"}"#.data(using: .utf8)!
        #expect(try JSONDecoder().decode(ClientNote.self, from: legacy).resolved == false)
        #expect(!String(decoding: try JSONEncoder().encode(ClientNote(reviewer: "R", text: "t", gallery: "g")), as: UTF8.self).contains("resolved"))
    }

    @Test func noNotesIsHeaderOnly() {
        #expect(StudioCatalog().clientNoteCount == 0)
        #expect(StudioCatalog().clientNotesCSV().components(separatedBy: "\r\n").count == 2)
    }
}
