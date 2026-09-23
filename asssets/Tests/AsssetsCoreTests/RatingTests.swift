import Foundation
import Testing
@testable import AsssetsCore

@Suite("Ratings and labels")
struct RatingTests {
    func a(_ title: String) -> StudioAsset {
        StudioAsset(title: title, kind: .image, tags: [], collection: "Inbox", palette: [], seed: 0, importedPath: "/x/\(title).png", resolution: "")
    }

    @Test func ratingClampsAndCounts() {
        var c = StudioCatalog(); c.assets = [a("A"), a("B"), a("C")]
        #expect(c.setRating([c.assets[0].id, c.assets[1].id], 4) == 2)
        #expect(c.setRating([c.assets[0].id], 4) == 0)
        c.setRating([c.assets[2].id], 9); #expect(c.assets[2].rating == 5)
        c.setRating([c.assets[2].id], -1); #expect(c.assets[2].rating == 0)
        #expect(c.assets[0].stars == "★★★★")
    }

    @Test func labelTogglesWhenAllMatch() {
        var c = StudioCatalog(); c.assets = [a("A"), a("B")]
        let both: Set = [c.assets[0].id, c.assets[1].id]
        c.toggleLabel([c.assets[0].id], .red)
        #expect(c.toggleLabel(both, .red) == .red)          // mixed: applies to all
        #expect(c.toggleLabel(both, .red) == nil)           // all red: clears
        c.toggleLabel(both, .green); #expect(c.toggleLabel(both, nil) == nil)
        #expect(ColorLabel.forKey(6) == .red && ColorLabel.forKey(9) == .blue && ColorLabel.forKey(5) == nil)
        #expect(ColorLabel.green.key == 8 && ColorLabel.orange.key == nil)
    }

    @Test func filterAndSmartRules() {
        var x = a("X"); x.rating = 4; x.label = .blue
        var y = a("Y"); y.rating = 2; y.label = .red
        let f = RatingFilter(minRating: 3, labels: [.blue, .green])
        #expect(f.isActive && f.matches(x) && !f.matches(y) && !RatingFilter().isActive)
        var rules = SmartRules(); f.apply(to: &rules)
        #expect(rules.labels == [.green, .blue] && rules.minRating == 3 && !rules.isEmpty)
        #expect(rules.matches(x) && !rules.matches(y))
        #expect(rules.summary == "rated 3★ or more • green or blue label")
        #expect(SmartRules(minRating: 5).summary == "rated 5★")
        // Round-trips; older rules decode with no rating or label limits.
        let back = try! JSONDecoder().decode(SmartRules.self, from: JSONEncoder().encode(rules))
        #expect(back == rules)
        let old = try! JSONDecoder().decode(SmartRules.self, from: Data(#"{"text":"a","favoritesOnly":false}"#.utf8))
        #expect(old.minRating == 0 && old.labels.isEmpty)
    }

    @Test func compareKeepSetsRating() {
        var c = StudioCatalog(); c.assets = [a("A"), a("B"), a("C")]
        c.assets[1].rating = 5
        var s = CompareSession(ids: c.assets.map(\.id))!
        s.mark(.keep); s.mark(.keep); s.mark(.reject)
        _ = c.applyPicks(s, keepRating: 4)
        #expect(c.assets[0].rating == 4 && c.assets[1].rating == 5 && c.assets[2].rating == 0)
        var d = StudioCatalog(); d.assets = [a("A"), a("B")]
        var t = CompareSession(ids: d.assets.map(\.id))!; t.mark(.keep)
        _ = d.applyPicks(t)
        #expect(d.assets[0].rating == 0)
    }

    @Test func persistsAndMetadataFlag() {
        var c = StudioCatalog(); c.assets = [a("A")]
        c.assets[0].rating = 3; c.assets[0].label = .purple
        let back = StudioCatalog.decode(try! c.encoded())!
        #expect(back.assets[0].rating == 3 && back.assets[0].label == .purple)
        let id = c.importFile(path: "/tmp/none/photo.jpg")!
        let imported = c.assets.first { $0.id == id }!
        #expect(imported.needsFileMetadata && imported.palette == StudioCatalog.placeholderPalette && imported.rating == 0)
        #expect(!back.assets[0].needsFileMetadata)
    }
}
