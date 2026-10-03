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

    @Test func bulkResolveTouchesOnlySelectedAssetsAndCountsRealChanges() {
        var c = StudioCatalog()
        let a = c.importFile(path: "/notes/a.png")!, b = c.importFile(path: "/notes/b.png")!, other = c.importFile(path: "/notes/o.png")!
        let g = UUID().uuidString
        _ = c.recordGallery(GalleryRoster(gallery: g, title: "Round", created: "2026-10-03", assets: [a, b, other])!)
        _ = c.applyFeedback(.init(gallery: g, title: "Round", reviewer: "Sam", items: [
            .init(id: a.uuidString, favorite: false, note: "A1"), .init(id: b.uuidString, favorite: false, note: "B1"),
            .init(id: other.uuidString, favorite: false, note: "O1")]))
        _ = c.applyFeedback(.init(gallery: g, title: "Round", reviewer: "Alex", items: [
            .init(id: a.uuidString, favorite: false, note: "A2")]))
        let one = c.assets.first { $0.id == a }!.clientNotes[0]
        _ = c.setClientNote(one, on: a, resolved: true)
        let preview = c.clientNotesToChange(on: [a, b], resolved: true)
        #expect(preview.notes == 2 && preview.assets == 2)
        let done = c.setClientNotes(on: [a, b], resolved: true)
        #expect(done.notes == 2 && done.assets == 2)
        #expect(c.openClientNoteCount == 1 && c.assets.first { $0.id == other }!.hasOpenClientNotes)
        let again = c.setClientNotes(on: [a, b], resolved: true)
        #expect(again.notes == 0 && again.assets == 0)
        let reopened = c.setClientNotes(on: [b], resolved: false)
        #expect(reopened.notes == 1 && c.openClientNoteAssetCount == 2)
        #expect(c.clientNotesToChange(on: [], resolved: true).notes == 0)
    }

    @Test func decisionsAreStoredPerReviewerWithoutABoardAndReplacedOnReimport() throws {
        var c = StudioCatalog()
        let a = c.importFile(path: "/notes/a.png")!, b = c.importFile(path: "/notes/b.png")!
        let g = UUID().uuidString
        _ = c.recordGallery(GalleryRoster(gallery: g, title: "Round", created: "2026-10-03", assets: [a, b])!)
        func fb(_ who: String, _ items: [ReviewGallery.Feedback.Entry]) -> ReviewGallery.Feedback { .init(gallery: g, title: "Round", reviewer: who, items: items) }
        let first = c.applyFeedback(fb("Jordan", [.init(id: a.uuidString, favorite: false, note: "", status: "approved"),
                                                  .init(id: b.uuidString, favorite: false, note: "Fix", status: "changes")]))
        #expect(first.decisions == 2 && c.clientDecisionCount == 2)
        _ = c.applyFeedback(fb("Sam", [.init(id: a.uuidString, favorite: false, note: "", status: "changes"),
                                       .init(id: b.uuidString, favorite: false, note: "x", status: "bogus")]))
        #expect(c.clientDecisionCount == 3)
        #expect(c.assets.first { $0.id == a }!.clientDecisions.map(\.status).sorted { $0.rawValue < $1.rawValue } == [.approved, .changes])
        let again = c.applyFeedback(fb("Jordan", [.init(id: a.uuidString, favorite: false, note: "", status: "changes")]))
        #expect(again.decisions == 1 && c.clientDecisionCount == 2)
        #expect(c.assets.first { $0.id == b }!.clientDecisions.isEmpty)
        _ = c.applyFeedback(fb("Jordan", []))
        #expect(c.clientDecisionCount == 1)
        let csv = c.clientDecisionsCSV()
        #expect(csv.hasPrefix("\"Asset title\",\"Source filename\",\"Reviewer\",\"Gallery\",\"Decision\"\r\n"))
        #expect(csv.contains("\"Sam\",\"Round\",\"Changes\"") && !csv.contains("/notes/"))
        let json = String(decoding: try JSONEncoder().encode(c.assets.first { $0.id == b }!), as: UTF8.self)
        #expect(!json.contains("clientDecisionList"))
        let saved = try JSONDecoder().decode(StudioAsset.self, from: JSONEncoder().encode(c.assets.first { $0.id == a }!))
        #expect(saved.clientDecisions.count == 1 && saved.clientDecisions[0].reviewer == "Sam")
    }

    @Test func decisionFilterSeparatesChangesFromCleanApprovals() {
        var c = StudioCatalog()
        let a = c.importFile(path: "/d/a.png")!, b = c.importFile(path: "/d/b.png")!, m = c.importFile(path: "/d/m.png")!, n = c.importFile(path: "/d/n.png")!
        let g = UUID().uuidString
        _ = c.recordGallery(GalleryRoster(gallery: g, title: "Round", created: "2026-10-03", assets: [a, b, m, n])!)
        _ = c.applyFeedback(.init(gallery: g, title: "Round", reviewer: "Jordan", items: [
            .init(id: a.uuidString, favorite: false, note: "", status: "approved"),
            .init(id: b.uuidString, favorite: false, note: "", status: "changes"),
            .init(id: m.uuidString, favorite: false, note: "", status: "approved")]))
        _ = c.applyFeedback(.init(gallery: g, title: "Round", reviewer: "Sam", items: [
            .init(id: m.uuidString, favorite: false, note: "", status: "changes")]))
        #expect(c.assetCount(matching: .changes) == 2)   // b and the split asset m
        #expect(c.assetCount(matching: .approved) == 1)  // only a: m has a change request
        #expect(c.assetCount(matching: .any) == 4)
        #expect(ClientDecisionFilter.approved.matches(c.assets.first { $0.id == n }!) == false)
        #expect(ClientDecisionFilter.changes.matches(c.assets.first { $0.id == m }!))
    }

    @Test func smartRuleOnDecisionsFollowsFeedbackAndStaysBackwardCompatible() throws {
        var c = StudioCatalog()
        let a = c.importFile(path: "/s/a.png")!, b = c.importFile(path: "/s/b.png")!
        let g = UUID().uuidString
        _ = c.recordGallery(GalleryRoster(gallery: g, title: "Round", created: "2026-10-03", assets: [a, b])!)
        let rules = SmartRules(decision: .changes)
        #expect(!rules.isEmpty && rules.summary == "client requested changes")
        #expect(c.assets.filter(rules.matches).isEmpty)
        _ = c.applyFeedback(.init(gallery: g, title: "Round", reviewer: "Jordan", items: [
            .init(id: a.uuidString, favorite: false, note: "", status: "changes"),
            .init(id: b.uuidString, favorite: false, note: "", status: "approved")]))
        #expect(c.assets.filter(rules.matches).map(\.id) == [a])
        #expect(c.assets.filter(SmartRules(decision: .approved).matches).map(\.id) == [b])
        #expect(SmartRules(decision: .any).isEmpty)
        let data = try JSONEncoder().encode(rules)
        #expect(try JSONDecoder().decode(SmartRules.self, from: data).decision == .changes)
        #expect(!String(decoding: try JSONEncoder().encode(SmartRules(text: "x")), as: UTF8.self).contains("decision"))
        let old = #"{"text":"cats"}"#.data(using: .utf8)!
        #expect(try JSONDecoder().decode(SmartRules.self, from: old).decision == nil)
        // Two reviewers who later withdraw leave the collection without anyone editing it.
        _ = c.applyFeedback(.init(gallery: g, title: "Round", reviewer: "Jordan", items: []))
        #expect(c.assets.filter(rules.matches).isEmpty)
    }

    @Test func revisionBriefListsChangeRequestsAndOpenNotesOnly() {
        var c = StudioCatalog()
        let a = c.importFile(path: "/b/billboard.png")!, b = c.importFile(path: "/b/card.png")!, ok = c.importFile(path: "/b/ok.png")!
        let g = UUID().uuidString
        _ = c.recordGallery(GalleryRoster(gallery: g, title: "Round", created: "2026-10-03", assets: [a, b, ok])!)
        _ = c.applyFeedback(.init(gallery: g, title: "Round", reviewer: "Jordan", items: [
            .init(id: a.uuidString, favorite: false, note: "Warmer backdrop\nand less glare", status: "changes"),
            .init(id: b.uuidString, favorite: false, note: "Done already"),
            .init(id: ok.uuidString, favorite: false, note: "", status: "approved")]))
        _ = c.applyFeedback(.init(gallery: g, title: "Round", reviewer: "Sam", items: [
            .init(id: a.uuidString, favorite: false, note: "", status: "changes")]))
        let done = c.assets.first { $0.id == b }!.clientNotes[0]
        _ = c.setClientNote(done, on: b, resolved: true)
        let r = RevisionBrief.render(c.assets)
        #expect(r.assets == 1 && r.notes == 1)
        #expect(r.text.hasPrefix("Revision brief: 1 asset, 1 open note\n\n• Billboard (billboard.png)\n"))
        #expect(r.text.contains("  Changes requested by Jordan, Sam\n"))
        #expect(r.text.contains("  Open note, Jordan: Warmer backdrop\n    and less glare\n"))
        #expect(!r.text.contains("card.png") && !r.text.contains("ok.png") && !r.text.contains("Done already") && !r.text.contains("/b/"))
        #expect(r.text.hasSuffix("not verified identities.\n"))
        #expect(RevisionBrief.render([]).text.isEmpty && RevisionBrief.render(c.assets.filter { $0.id == ok }).assets == 0)
    }

    @Test func noNotesIsHeaderOnly() {
        #expect(StudioCatalog().clientNoteCount == 0)
        #expect(StudioCatalog().clientNotesCSV().components(separatedBy: "\r\n").count == 2)
    }

    @Test func searchMatchesClientNoteTextIncludingResolved() {
        var c = StudioCatalog()
        let a = c.importFile(path: "/s/one.png")!, b = c.importFile(path: "/s/two.png")!
        let g = UUID().uuidString
        _ = c.recordGallery(GalleryRoster(gallery: g, title: "R", created: "2026-10-03", assets: [a, b])!)
        _ = c.applyFeedback(.init(gallery: g, title: "R", reviewer: "Jordan", items: [
            .init(id: a.uuidString, favorite: false, note: "Fix the Shadow"),
            .init(id: b.uuidString, favorite: false, note: "Cooler tone")]))
        #expect(c.filtered(search: "shadow", kind: nil, collection: StudioCatalog.allAssets).map(\.id) == [a])
        let note = c.assets.first { $0.id == a }!.clientNotes[0]
        _ = c.setClientNote(note, on: a, resolved: true)
        #expect(c.filtered(search: "shadow", kind: nil, collection: StudioCatalog.allAssets).map(\.id) == [a])
        #expect(c.filtered(search: "shadow tone", kind: nil, collection: StudioCatalog.allAssets).isEmpty)
        #expect(SmartRules(text: "cooler").matches(c.assets.first { $0.id == b }!))
    }
}
