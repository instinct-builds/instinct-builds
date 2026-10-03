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

    @Test func assetsWithOpenNotesLeaveTheListWhenFullyResolved() {
        var c = StudioCatalog()
        let a = c.importFile(path: "/notes/a.png")!, b = c.importFile(path: "/notes/b.png")!, none = c.importFile(path: "/notes/none.png")!
        let g = UUID().uuidString
        _ = c.recordGallery(GalleryRoster(gallery: g, title: "Round", created: "2026-10-02", assets: [a, b, none])!)
        _ = c.applyFeedback(.init(gallery: g, title: "Round", reviewer: "Sam", items: [
            .init(id: a.uuidString, favorite: false, note: "One"), .init(id: b.uuidString, favorite: false, note: "Two")]))
        _ = c.applyFeedback(.init(gallery: g, title: "Round", reviewer: "Alex", items: [
            .init(id: a.uuidString, favorite: false, note: "Three")]))
        #expect(c.openClientNoteAssetCount == 2)
        let first = c.assets.first { $0.id == a }!.clientNotes
        for n in first { _ = c.setClientNote(n, on: a, resolved: true) }
        #expect(c.openClientNoteAssetCount == 1 && c.assets.first { $0.id == a }!.hasOpenClientNotes == false)
        #expect(c.assets.first { $0.id == none }!.hasOpenClientNotes == false)
        let reopened = c.assets.first { $0.id == a }!.clientNotes[0]
        _ = c.setClientNote(reopened, on: a, resolved: false)
        #expect(c.openClientNoteAssetCount == 2)
    }

    @Test func hiddenSelectionMovesToTheFirstVisibleAsset() {
        let a = UUID(), b = UUID(), c = UUID()
        let hidden = FilterSelection.reconcile(selection: [c], focus: c, visible: [a, b])
        #expect(hidden.selection == [a] && hidden.focus == a)
        let kept = FilterSelection.reconcile(selection: [b], focus: b, visible: [a, b])
        #expect(kept.selection == [b] && kept.focus == b)
        let partial = FilterSelection.reconcile(selection: [b, c], focus: c, visible: [a, b])
        #expect(partial.selection == [b] && partial.focus == b)
        let none = FilterSelection.reconcile(selection: [c], focus: c, visible: [])
        #expect(none.selection.isEmpty && none.focus == nil)
        let empty = FilterSelection.reconcile(selection: [], focus: nil, visible: [a])
        #expect(empty.selection == [a])
    }

    @Test func noNotesIsHeaderOnly() {
        #expect(StudioCatalog().clientNoteCount == 0)
        #expect(StudioCatalog().clientNotesCSV().components(separatedBy: "\r\n").count == 2)
    }
}
