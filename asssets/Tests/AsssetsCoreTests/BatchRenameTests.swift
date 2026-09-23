import Foundation
import Testing
@testable import AsssetsCore

@Suite("Batch rename and folder export")
struct BatchRenameTests {
    func asset(_ title: String, collection: String = "Device Mockups", rating: Int = 0, label: ColorLabel? = nil, kind: MediaKind = .mockup) -> StudioAsset {
        var a = StudioAsset(title: title, kind: kind, tags: [], collection: collection, palette: [], seed: 1, resolution: "10 × 10")
        a.rating = rating; a.label = label
        return a
    }
    let day = Date(timeIntervalSince1970: 1_790_000_000) // 2026-09-21

    @Test func numberPadding() {
        #expect(PatternTokens.expand("{n}", values: [:], index: 7) == "07")
        #expect(PatternTokens.expand("{n:000}", values: [:], index: 7) == "007")
        #expect(PatternTokens.expand("{n:0}", values: [:], index: 123) == "123")
        #expect(PatternTokens.expand("{n:abc} {x}", values: [:], index: 1) == "{n:abc} {x}")
        #expect(PatternTokens.expand("{title", values: ["{title}": "T"], index: 1) == "{title")
    }

    @Test func renderTokens() {
        let a = asset("Phone Screen", rating: 4, label: .green)
        #expect(RenamePattern.render("{collection} {n:000}", asset: a, index: 3, date: day) == "Device Mockups 003")
        #expect(RenamePattern.render("{title} - {rating} {label} {kind}", asset: a, index: 1, date: day) == "Phone Screen - 4 stars Green Mockup")
        #expect(RenamePattern.render("{date}", asset: a, index: 1, date: day).hasPrefix("2026-09-2"))
        #expect(RenamePattern.render("  {title}    v2 ", asset: a, index: 1) == "Phone Screen v2")
        #expect(RenamePattern.render("   ", asset: a, index: 1) == "Phone Screen")
        #expect(RenamePattern.render("{title}", asset: asset("x", rating: 1), index: 1) == "x")
        #expect(PatternTokens.values(for: asset("x", rating: 1), date: day)["{rating}"] == "1 star")
        #expect(PatternTokens.values(for: asset("x"), date: day)["{rating}"] == "Unrated")
        #expect(PatternTokens.values(for: asset("x"), date: day)["{label}"] == "No Label")
    }

    @Test func previewNumbersInOrderAndFlagsClashes() {
        let list = [asset("B"), asset("A"), asset("C")]
        let rows = RenamePattern.preview("Client X {n:00}", assets: list, start: 9)
        #expect(rows.map(\.new) == ["Client X 09", "Client X 10", "Client X 11"])
        #expect(rows.allSatisfy { $0.changed && !$0.clash })
        let same = RenamePattern.preview("{collection}", assets: list)
        #expect(same.allSatisfy { $0.clash })
        let keep = RenamePattern.preview("{title}", assets: list)
        #expect(keep.allSatisfy { !$0.changed })
    }

    @Test func retitleChangesOnlyTitlesAndIsCountable() {
        var c = StudioCatalog()
        var a = asset("Old"); a.importedPath = "/tmp/file.png"
        let b = asset("Keep")
        c.assets = [a, b]
        let n = c.retitle([a.id: "New", b.id: "Keep", UUID(): "Ghost"])
        #expect(n == 1)
        #expect(c.assets[0].title == "New" && c.assets[0].importedPath == "/tmp/file.png")
        #expect(c.retitle([a.id: "   "]) == 0)
    }

    @Test func folderComponents() {
        let a = asset("Phone", collection: "Device Mockups", rating: 5, label: .blue)
        #expect(FolderPattern.components("{collection}/{label}", asset: a) == ["Device Mockups", "Blue"])
        #expect(FolderPattern.components("", asset: a) == [])
        #expect(FolderPattern.components("{rating}", asset: a) == ["5 stars"])
        #expect(FolderPattern.relativePath("Client/{kind}", asset: a) == "Client/Mockup")
        #expect(FolderPattern.components("{label}", asset: asset("x")) == ["No Label"])
    }

    @Test func folderPatternCannotEscape() {
        let evil = asset("x", collection: "../../etc")
        let parts = FolderPattern.components("../{collection}/./a//b", asset: evil)
        #expect(!parts.contains(".."))
        #expect(!parts.contains("."))
        #expect(parts.allSatisfy { !$0.contains("/") && !$0.hasPrefix(".") })
        #expect(parts.last == "b")
        let slashy = asset("x", collection: "A/B")
        #expect(FolderPattern.components("{collection}", asset: slashy) == ["A-B"])
        #expect(FolderPattern.components("a/b/c/d/e/f/g", asset: slashy).count == FolderPattern.maxDepth)
    }

    @Test func fileNamesGetNewTokens() {
        let a = asset("Phone", rating: 3, label: .red)
        let o = ExportPreset.web.outputs(width: 4000, height: 2000)
        #expect(FilenamePattern.render("{title}-{rating}-{label}-{n:000}", asset: a, preset: .web, output: o[1], index: 4) == "Phone-3 stars-Red-004@1x.jpg")
        #expect(FilenamePattern.render("{title}-{preset}", title: "Terrazzo Texture", preset: .web, output: o[1], index: 3, collection: "M") == "Terrazzo Texture-web@1x.jpg")
    }
}
