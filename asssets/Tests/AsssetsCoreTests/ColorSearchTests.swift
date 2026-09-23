import Foundation
import Testing
@testable import AsssetsCore

@Suite("Search by color")
struct ColorSearchTests {
    func asset(_ title: String, _ palette: [String]) -> StudioAsset {
        StudioAsset(title: title, kind: .texture, tags: [], collection: "Material Textures", palette: palette, seed: 1, resolution: "10 × 10")
    }

    @Test func normalizesHex() {
        #expect(ColorSearch.normalize("#4dabf7") == "#4DABF7")
        #expect(ColorSearch.normalize(" 4ab ") == "#44AABB")
        #expect(ColorSearch.normalize("#12345") == nil)
        #expect(ColorSearch.normalize("zzzzzz") == nil)
        #expect(ColorQuery(hex: "nope").hex == "#808080")
        #expect(ColorQuery(hex: "#fff", tolerance: 999).tolerance == ColorQuery.toleranceRange.upperBound)
    }

    @Test func labMatchesReferenceValues() {
        let red = ColorSearch.lab("#FF0000")!
        #expect(abs(red.l - 53.24) < 0.05 && abs(red.a - 80.09) < 0.05 && abs(red.b - 67.20) < 0.05)
        let white = ColorSearch.lab("#FFFFFF")!
        #expect(abs(white.l - 100) < 0.01 && abs(white.a) < 0.01 && abs(white.b) < 0.01)
    }

    // Sharma, Wu and Dalal (2005) CIEDE2000 test data.
    @Test func ciede2000ReferencePairs() {
        let pairs: [(LabColor, LabColor, Double)] = [
            (LabColor(l: 50, a: 2.6772, b: -79.7751), LabColor(l: 50, a: 0, b: -82.7485), 2.0425),
            (LabColor(l: 50, a: 0, b: 0), LabColor(l: 50, a: -1, b: 2), 2.3669),
            (LabColor(l: 50, a: 2.5, b: 0), LabColor(l: 73, a: 25, b: -18), 27.1492),
            (LabColor(l: 50, a: 2.5, b: 0), LabColor(l: 50, a: 3.2592, b: 0.3350), 1.0),
            (LabColor(l: 2.0776, a: 0.0795, b: -1.1350), LabColor(l: 0.9033, a: -0.0636, b: -0.5514), 0.9082),
        ]
        for (p, q, want) in pairs {
            #expect(abs(ColorSearch.deltaE(p, q) - want) < 0.0005, "\(p) \(q)")
            #expect(abs(ColorSearch.deltaE(q, p) - want) < 0.0005)
        }
        #expect(ColorSearch.deltaE("#123456", "#123456") == 0)
    }

    @Test func ranksDominantMatchesFirstAndDropsFarOnes() {
        let blue = ColorQuery(hex: "#4DABF7", tolerance: 14)
        let dominant = asset("Sky", ["#4CA8F5", "#FFFFFF"])
        let accent = asset("Accent", ["#222222", "#EEEEEE", "#333333", "#4DABF7"])
        let near = asset("Near", ["#5AB0F0"])
        let far = asset("Brick", ["#B5452A", "#6B2A1B"])
        let empty = asset("Empty", [])
        let ranked = ColorSearch.rank([far, accent, near, empty, dominant], blue)
        #expect(ranked.map(\.title) == ["Sky", "Near", "Accent"])
        #expect(!ColorSearch.matches(blue, far) && !ColorSearch.matches(blue, empty))
        #expect(ColorSearch.match(blue, palette: accent.palette)!.distance < 0.01)
        #expect(ColorSearch.rank([far], ColorQuery(hex: "#B04428", tolerance: 4)).count == 1)
    }

    @Test func smartRuleWithColor() throws {
        var rules = SmartRules(kinds: [.texture])
        #expect(!rules.isEmpty)
        rules.color = ColorQuery(hex: "#4DABF7", tolerance: 12)
        #expect(rules.matches(asset("Sky", ["#4CA8F5"])))
        #expect(!rules.matches(asset("Brick", ["#B5452A"])))
        #expect(rules.summary.contains("color near #4DABF7"))
        let back = try JSONDecoder().decode(SmartRules.self, from: JSONEncoder().encode(rules))
        #expect(back == rules)
        // Rules saved by 1.14 have no color key.
        let old = try JSONDecoder().decode(SmartRules.self, from: Data(#"{"text":"blue","kinds":[],"requiredTags":[],"favoritesOnly":false}"#.utf8))
        #expect(old.color == nil)
        #expect(SmartRules(color: ColorQuery(hex: "#000")).isEmpty == false)
    }

    @Test func recentColorsAreDedupedAndCapped() throws {
        var c = StudioCatalog()
        for h in ["#111111", "#222222", "#111111", "bad", "#333", "#444444", "#555555", "#666666", "#777777"] { c.noteRecentColor(h) }
        #expect(c.recentColors.first == "#777777")
        #expect(c.recentColors.count == StudioCatalog.recentColorLimit)
        #expect(Set(c.recentColors).count == c.recentColors.count)
        #expect(!c.recentColors.contains("#111111"))
        let back = StudioCatalog.decode(try c.encoded())!
        #expect(back.recentColors == c.recentColors)
    }
}
