import Foundation
import Testing
@testable import AsssetsCore

@Suite("Auto tags")
struct AutoTagTests {
    @Test func colorNames() {
        #expect(AutoTags.colorName("#1FA3A0") == "teal")
        #expect(AutoTags.colorName("#0A0A0A") == "black")
        #expect(AutoTags.colorName("#FFFFFF") == "white")
        #expect(AutoTags.colorName("#2B2B2E") == "charcoal")
        #expect(AutoTags.colorName("#C8BBA8") == "warm neutral")
        #expect(AutoTags.colorName("#9CA0A5") == "gray" || AutoTags.colorName("#9CA0A5") == "cool gray")
        #expect(AutoTags.colorName("#E03030") == "red")
        #expect(AutoTags.colorName("#7A4A22") == "brown")
        #expect(AutoTags.colorName("#1B2A5C") == "navy")
        #expect(AutoTags.colorName("#8E44E0") == "purple")
        #expect(AutoTags.colorName("nope") == nil)
    }

    @Test func imageFacts() {
        let t = AutoTags.suggest(.init(kind: .texture, palette: ["#101418", "#1C2430", "#0E1116"], width: 4096, height: 4096, tileable: true))
        #expect(t.contains("dark") && t.contains("square") && t.contains("4k+") && t.contains("print-ready") && t.contains("tileable"))
        #expect(!t.contains("light"))
        let p = AutoTags.suggest(.init(kind: .image, palette: ["#FF2A6D", "#05D9E8", "#FFD319"], width: 500, height: 750, hasAlpha: true))
        #expect(p.contains("vivid") && p.contains("portrait") && p.contains("small") && p.contains("transparent"))
    }

    @Test func mediaFacts() {
        #expect(AutoTags.suggest(.init(kind: .audio, palette: ["#FF0000"], durationSeconds: 90, loudnessDBFS: -35)) == ["long", "quiet"])
        #expect(AutoTags.suggest(.init(kind: .video, durationSeconds: 8)).contains("short"))
    }

    @Test func suggestionsAreSearchableUntilRejected() throws {
        var c = StudioCatalog()
        let id = c.importFile(path: "/x/wave.png")!
        c.setAutoTags(["teal", "dark", "png"], for: id)
        #expect(c.assets[0].suggestedTags == ["teal", "dark"])       // "png" is already a real tag
        #expect(c.filtered(search: "teal", kind: nil, collection: StudioCatalog.allAssets).count == 1)
        c.rejectSuggestion("teal", for: [id])
        #expect(c.filtered(search: "teal", kind: nil, collection: StudioCatalog.allAssets).isEmpty)
        c.acceptSuggestions(for: [id])
        #expect(c.assets[0].tags.contains("dark") && c.assets[0].suggestedTags.isEmpty)
        let back = StudioCatalog.decode(try c.encoded())!
        #expect(back.assets[0].rejectedTags == ["teal"] && back.assets[0].autoTags == ["teal", "dark", "png"])
    }

    @Test func dimensionLabels() {
        #expect(AutoTags.dimensions(in: "PSD • 1600 × 1200 • 7 layers")! == (1600, 1200))
        #expect(AutoTags.dimensions(in: "2048x2048")! == (2048, 2048))
        #expect(AutoTags.dimensions(in: "WAV • 48.0 kHz • 0:12") == nil)
        #expect(AutoTags.dimensions(in: "Local file") == nil)
    }
}
