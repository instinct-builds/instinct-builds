import Testing
import Foundation
@testable import AsssetsCore

private func catalog() -> StudioCatalog {
    var c = StudioCatalog()
    c.mergeStarter(files: ["ink-fiber-4k.png", "editorial-vector-03.svg", "ambient-bed.wav", "motion-loop-01.mp4", "device-stage-mockup.png"],
                   root: "/lib/StarterLibrary", fingerprint: "a")
    c.mergeGenerated()
    return c
}

@Suite("Studio smart collections")
struct SmartStudioTests {
    @Test func tonesClassifyPalettes() {
        #expect(PaletteTone.of(["#E1A66E", "#C0392B", "#F4D03F"]) == .warm)
        #expect(PaletteTone.of(["#3157FF", "#00C2FF", "#1B4F72"]) == .cool)
        #expect(PaletteTone.of(["#1E2025", "#72665A", "#CDBDA7", "#F0E7DC"]) == .neutral)
        #expect(PaletteTone.of(["#FF0033", "#00FF66", "#0044FF"]) == .vivid)
        #expect(PaletteTone.of([]) == nil)
        #expect(PaletteTone.of(["nothex"]) == nil)
    }

    @Test func membershipIsLiveAndCombinesRules() {
        var c = catalog()
        let id = c.createSmartCollection(named: "Hero Motion", rules: SmartRules(kinds: [.video], requiredTags: ["hero"]))
        #expect(c.smartAssets(id).isEmpty)
        let clip = c.assets.first { $0.sourceKey == "starter:motion-loop-01.mp4" }!.id
        c.addTags("hero", to: [clip])
        #expect(c.smartAssets(id).map(\.id) == [clip])
        let tex = c.assets.first { $0.kind == .texture }!.id
        c.addTags("hero", to: [tex])                                 // wrong kind, stays out
        #expect(c.smartAssets(id).count == 1)
        c.removeTag("hero", from: [clip])
        #expect(c.smartAssets(id).isEmpty)
    }

    @Test func browsingAppliesSearchAndKindOnTop() {
        var c = catalog()
        let id = c.createSmartCollection(named: "Bundled", rules: SmartRules(requiredTags: ["bundled"]))
        #expect(c.smartAssets(id).count == 5)
        #expect(c.filtered(search: "", kind: .audio, smart: id).count == 1)
        #expect(c.filtered(search: "vector", kind: nil, smart: id).count == 1)
        #expect(c.filtered(search: "", kind: nil, smart: UUID()).isEmpty)
    }

    @Test func seedingHappensOnceAndDeletesStick() {
        var c = catalog()
        let first = c.seedSmartCollections()
        #expect(first == StudioCatalog.defaultSmartCollections.count)
        let warm = c.smartCollections.first { $0.name == "Warm Palettes" }!.id
        let deleted = c.deleteSmartCollection(warm)
        #expect(deleted)
        let again = c.seedSmartCollections()
        #expect(again == 0)
        #expect(!c.smartCollections.contains { $0.name == "Warm Palettes" })
        let real = c.smartCollections.first { $0.name == "Real Files" }!.id
        #expect(c.smartAssets(real).count == 5)
    }

    @Test func namesStayUniqueAndEditsApply() {
        var c = catalog()
        let a = c.createSmartCollection(named: "Picks", rules: SmartRules(favoritesOnly: true))
        let b = c.createSmartCollection(named: "Picks", rules: SmartRules())
        #expect(c.smartCollection(b)?.name == "Picks 2")
        let clash = c.createSmartCollection(named: "Sound Beds", rules: SmartRules())
        #expect(c.smartCollection(clash)?.name == "Sound Beds 2")      // never shadows a real collection
        let updated = c.updateSmartCollection(a, name: "Picks", rules: SmartRules(kinds: [.audio]))
        #expect(updated)
        #expect(c.smartCollection(a)?.name == "Picks")                 // keeping its own name is fine
        #expect(c.smartAssets(a).allSatisfy { $0.kind == .audio })
        #expect(SmartRules(kinds: [.audio], favoritesOnly: true, tone: .warm).summary == "Audio • warm palette • favorites")
        #expect(SmartRules().isEmpty && SmartRules().summary == "Everything")
    }

    @Test func renamingACollectionFollowsIntoRules() {
        var c = catalog()
        let id = c.createSmartCollection(named: "Sound Favs", rules: SmartRules(collection: "Sound Beds"))
        let before = c.smartAssets(id).count
        let ok = c.renameCollection("Sound Beds", to: "Audio Beds")
        #expect(ok)
        #expect(c.smartCollection(id)?.rules.collection == "Audio Beds")
        #expect(c.smartAssets(id).count == before)
    }

    @Test func persistsAndDecodesOlderCatalogs() throws {
        var c = catalog()
        c.seedSmartCollections()
        _ = c.createSmartCollection(named: "Q3", rules: SmartRules(text: "loop", tone: .cool))
        let data = try c.encoded()
        let back = try #require(StudioCatalog.decode(data))
        #expect(back == c)
        // A 0.4 catalog has neither key: it decodes with no smart collections and unseeded.
        var raw = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        raw.removeValue(forKey: "smartCollections"); raw.removeValue(forKey: "smartSeeded")
        let old = try #require(StudioCatalog.decode(try JSONSerialization.data(withJSONObject: raw)))
        #expect(old.smartCollections.isEmpty && !old.smartSeeded)
    }
}
