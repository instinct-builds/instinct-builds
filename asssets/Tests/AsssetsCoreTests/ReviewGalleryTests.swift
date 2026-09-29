import Foundation
import Testing
@testable import AsssetsCore

@Suite("Review gallery")
struct ReviewGalleryTests {
    func asset(_ title: String) -> StudioAsset {
        StudioAsset(title: title, kind: .mockup, tags: ["mockup"], collection: "Device Mockups", palette: ["#112233"], seed: 0, resolution: "2400 × 1600")
    }

    @Test func htmlEmbedsManifestSafely() {
        let item = ReviewGallery.Item(id: UUID().uuidString, title: "Evil </script><b>", kind: "Mockup", resolution: "2400 × 1600",
                                      palette: ["#112233"], tags: ["a"], image: "images/01.jpg", thumb: "thumbs/01.jpg")
        let html = ReviewGallery.html(.init(gallery: "g1", title: "Q3 <Launch>", created: "2026-09-23", items: [item]))
        #expect(html.contains("<title>Q3 &lt;Launch&gt; · Review</title>"))
        #expect(!html.contains("Evil </script>"))                       // cannot close the script tag early
        #expect(html.contains("Evil <\\/script>"))
        #expect(!html.contains("__MANIFEST__") && !html.contains("__TITLE__"))
        #expect(!html.contains("http://") && !html.contains("https://"))  // fully offline: no remote fonts, scripts or trackers
        // The embedded JSON decodes back to the manifest.
        let start = html.range(of: "id=\"manifest\">")!.upperBound, end = html.range(of: "</script>", range: start..<html.endIndex)!.lowerBound
        let json = html[start..<end].replacingOccurrences(of: "<\\/", with: "</")
        let m = try? JSONDecoder().decode(ReviewGallery.Manifest.self, from: Data(json.utf8))
        #expect(m?.items.first?.title == "Evil </script><b>")
    }

    @Test func stemsSortInGridOrder() {
        #expect(ReviewGallery.stem(0, count: 12) == "01")
        #expect(ReviewGallery.stem(99, count: 120) == "100"); #expect(ReviewGallery.stem(4, count: 120) == "005")
    }

    @Test func feedbackInTheShapeThePageWritesRoundTrips() {
        var c = StudioCatalog()
        let a = asset("Plinth"), b = asset("Stage"), d = asset("Album")
        c.assets = [a, b, d]
        // Exactly what the page's Download feedback button produces (lowercased id to check matching).
        let json = """
        {"format":"asssets-review-feedback","gallery":"g1","title":"Launch","reviewer":"Jordan",
         "items":[{"id":"\(a.id.uuidString.lowercased())","favorite":true,"note":"Love it"},
                  {"id":"\(b.id.uuidString)","favorite":false,"note":"Too dark"},
                  {"id":"not-in-library","favorite":true,"note":""}]}
        """
        let f = ReviewGallery.decodeFeedback(Data(json.utf8))!
        let recordedGallery0 = c.recordGallery(GalleryRoster(gallery: "g1", title: "Launch", created: "2026-09-26", assets: [a.id, b.id])!)
        #expect(recordedGallery0)
        let r = c.applyFeedback(f)
        #expect(r.favorites == 1 && r.notes == 2 && r.unknown == 1 && r.smartCollection != nil)
        #expect(c.assets[0].tags.contains("client-pick")); #expect(!c.assets[1].tags.contains("client-pick"))
        #expect(c.assets[0].clientNotes == [ClientNote(reviewer: "Jordan", text: "Love it", gallery: "g1")])
        // Re-import from the same reviewer replaces, doesn't stack; a second reviewer adds.
        var f2 = f; f2.items[0].note = "Love it, warmer please"
        c.applyFeedback(f2)
        #expect(c.assets[0].clientNotes.count == 1 && c.assets[0].clientNotes[0].text == "Love it, warmer please")
        var f3 = f; f3.reviewer = "Sam"; c.applyFeedback(f3)
        #expect(c.assets[0].clientNotes.map(\.reviewer) == ["Jordan", "Sam"])
        #expect(c.smartCollections.filter { $0.name == "Client Picks" }.count == 1)
        // Notes survive a save and load.
        let back = StudioCatalog.decode(try! c.encoded())!
        #expect(back.assets[0].clientNotes.count == 2)
    }

    @Test func pageOffersApproveAndWritesStatusOnlyWhenChosen() {
        let h = ReviewGallery.html(.init(title: "T", created: "2026-09-24", items: []))
        #expect(h.contains("id=\"lbap\"") && h.contains("Request changes"))
        #expect(h.contains("if(s.status==='approved'||s.status==='changes')x.status=s.status"))
        #expect(h.contains(".filter(x=>x.favorite||x.note||x.status)"))
    }

    @Test func downloadedBrowserDraftsImportSeparately() throws {
        // CI writes these from actual Chrome clicks on the exported offline gallery, not hand-authored feedback.
        guard let folder = ProcessInfo.processInfo.environment["ASSSETS_REVIEW_BROWSER_RESULTS"] else { return }
        let root = URL(fileURLWithPath: folder, isDirectory: true)
        let manifest = try JSONDecoder().decode(ReviewGallery.Manifest.self,
            from: Data(contentsOf: root.appendingPathComponent("manifest.json")))
        var catalog = StudioCatalog()
        catalog.assets = manifest.items.compactMap { item in
            guard let id = UUID(uuidString: item.id) else { return nil }
            var a = asset(item.title); a.id = id; return a
        }
        #expect(catalog.assets.count == manifest.items.count && !catalog.assets.isEmpty)
        let recorded = catalog.recordGallery(GalleryRoster(gallery: manifest.gallery, title: manifest.title,
            created: manifest.created, assets: catalog.assets.map(\.id))!)
        #expect(recorded)
        func read(_ file: String) throws -> ReviewGallery.Feedback {
            try #require(ReviewGallery.decodeFeedback(Data(contentsOf: root.appendingPathComponent(file))))
        }
        let alex = try read("drafts-0.json"), sam = try read("drafts-1.json")
        let renamed = try read("drafts-2.json"), backSam = try read("drafts-3.json"), backAlex = try read("drafts-4.json")
        #expect(alex.reviewer == "Alex" && sam.reviewer == "Sam" && renamed.reviewer == "Alex Updated")
        #expect(alex.items.first?.favorite == true && alex.items.first?.cardStatus == .approved)
        #expect(sam.items.first?.favorite == false && sam.items.first?.cardStatus == .changes)
        #expect(renamed.items.first?.note == "Alex note" && backSam == sam && backAlex == renamed)
        #expect(try read("legacy-continue-0.json").items.first?.note == "Older note")
        #expect(try read("legacy-fresh-0.json").items.isEmpty)
        for mode in ["storage-denied", "storage-quota", "storage-partial", "storage-readback"] {
            let unsaved = try read("\(mode)-0.json")
            #expect(unsaved.reviewer == "Failed Draft")
            #expect(unsaved.items.first?.favorite == true && unsaved.items.first?.cardStatus == .approved)
            #expect(unsaved.items.first?.note == "Keep this note")
            var independent = catalog
            let applied = independent.applyFeedback(unsaved)
            #expect(applied.favorites == 1 && applied.notes == 1)
            #expect(independent.assets[0].clientNotes.contains(ClientNote(reviewer: "Failed Draft", text: "Keep this note", gallery: manifest.gallery)))
        }
        let warningFile = try read("storage-warning-0.json")
        #expect(warningFile.items.first?.note == "Keep this note")
        let survived = try read("reload-0.json")
        #expect(survived.reviewer == "Reloaded Draft" && survived.items.first?.note == "Saved before reload")
        _ = catalog.applyFeedback(alex)
        _ = catalog.applyFeedback(sam)
        #expect(catalog.assets[0].clientNotes.contains(ClientNote(reviewer: "Alex", text: "Alex note", gallery: manifest.gallery)))
        #expect(catalog.assets[0].clientNotes.contains(ClientNote(reviewer: "Sam", text: "Sam note", gallery: manifest.gallery)))
        _ = catalog.applyFeedback(renamed)
        #expect(catalog.assets[0].clientNotes.contains(ClientNote(reviewer: "Alex Updated", text: "Alex note", gallery: manifest.gallery)))
        #expect(catalog.assets[0].clientNotes.contains(ClientNote(reviewer: "Sam", text: "Sam note", gallery: manifest.gallery)))
        // A rename in the browser cannot merge the old name's already-imported receipts in the native library.
        // That is a distinct native import identity; the gallery does not assert verified identity.
    }

    @Test func rejectsOtherJSON() {
        #expect(ReviewGallery.decodeFeedback(Data(#"{"format":"other","gallery":"g","title":"t","reviewer":"r","items":[]}"#.utf8)) == nil)
        #expect(ReviewGallery.decodeFeedback(Data("not json".utf8)) == nil)
    }
}
