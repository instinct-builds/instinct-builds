import Testing
import Foundation
@testable import AsssetsCore

private let starterFiles = [
    "ink-fiber-4k.png", "editorial-vector-03.svg", "ambient-bed.wav", "motion-loop-01.mp4",
    "device-stage-mockup.png", "concrete-dust-4k.png", ".DS_Store", "readme.txt",
]

private func freshCatalog(root: String = "/Users/me/Library/Application Support/ASSSETS/StarterLibrary") -> StudioCatalog {
    var c = StudioCatalog()
    c.mergeGenerated()
    c.mergeStarter(files: starterFiles, root: root, fingerprint: "a")
    return c
}

/// Mirrors what 0.3.0 wrote: 72 unkeyed generated studies plus starter files imported as "Imported".
private func legacy03JSON(root: String) throws -> Data {
    var assets = StarterCatalog.generated().map { a -> StudioAsset in var b = a; b.sourceKey = nil; b.id = UUID(); return b }
    for name in ["ink-fiber-4k.png", "editorial-vector-03.svg", "ambient-bed.wav"] {
        let ext = URL(fileURLWithPath: name).pathExtension
        assets.insert(StudioAsset(title: URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent, kind: .image,
                                  tags: [ext, "imported"], collection: "Imported", palette: ["#20242C"], seed: 1,
                                  importedPath: root + "/" + name, resolution: "Local file"), at: 0)
    }
    let ink = assets.firstIndex { $0.importedPath?.hasSuffix("ink-fiber-4k.png") == true }!
    assets[ink].favorite = true
    assets[ink].tags.append("client-x")
    // 0.3 JSON had no sourceKey field at all.
    let raw = try JSONSerialization.jsonObject(with: JSONEncoder().encode(assets)) as! [[String: Any]]
    return try JSONSerialization.data(withJSONObject: raw.map { var d = $0; d.removeValue(forKey: "sourceKey"); return d })
}

@Suite("Studio catalog install and migration")
struct StudioMigrationTests {
    @Test func freshInstallIndexesGeneratedAndPhysicalFiles() {
        let c = freshCatalog()
        #expect(c.assets.count == 72 + 6)           // hidden and unsupported files are skipped
        let linked = c.assets.filter(\.isStarter).allSatisfy { $0.importedPath != nil }
        #expect(linked)
        let ink = c.assets.first { $0.sourceKey == "starter:ink-fiber-4k.png" }
        #expect(ink?.collection == "Material Textures")
        #expect(ink?.kind == .texture)
        #expect(ink?.title == "Ink Fiber 4K")
        #expect(c.assets.first { $0.sourceKey == "starter:device-stage-mockup.png" }?.kind == .mockup)
        #expect(c.assets.first { $0.sourceKey == "starter:ambient-bed.wav" }?.collection == "Sound Beds")
        #expect(c.assets.first { $0.sourceKey == "starter:motion-loop-01.mp4" }?.collection == "Motion Loops")
        #expect(!c.collections.contains("Imported"))
    }

    @Test func mergingTwiceIsIdempotent() {
        var c = freshCatalog()
        let before = c
        let generated = c.mergeGenerated()
        let report = c.mergeStarter(files: starterFiles, root: "/Users/me/Library/Application Support/ASSSETS/StarterLibrary", fingerprint: "a")
        #expect(generated == 0)
        #expect(report.added == 0 && report.adopted == 0 && report.relinked == 0)
        #expect(report.unchanged == 6)
        #expect(c == before)
    }

    @Test func upgradeKeepsUserEditsAndAddsOnlyNewFiles() {
        var c = freshCatalog()
        let ink = c.assets.first { $0.sourceKey == "starter:ink-fiber-4k.png" }!.id
        c.toggleFavorite([ink])
        c.addTags("hero, client-x", to: [ink])
        c.move([ink], to: "Spring Campaign")
        let report = c.mergeStarter(files: starterFiles + ["sandstone-4k.png"], root: "/new/root/StarterLibrary", fingerprint: "b")
        #expect(report.added == 1)
        #expect(report.relinked == 6)
        let after = c.assets.first { $0.id == ink }!
        #expect(after.favorite)
        #expect(after.tags.contains("hero") && after.tags.contains("client-x"))
        #expect(after.collection == "Spring Campaign")
        #expect(after.importedPath == "/new/root/StarterLibrary/ink-fiber-4k.png")
        #expect(c.starterFingerprint == "b")
        #expect(Set(c.assets.compactMap(\.sourceKey)).count == c.assets.filter { $0.sourceKey != nil }.count)
    }

    @Test func migratesA03CatalogWithoutDuplicates() throws {
        let root = "/Users/me/Library/Application Support/ASSSETS/StarterLibrary"
        let legacy = try legacy03JSON(root: root)
        var c = try #require(StudioCatalog.decode(legacy))
        #expect(c.assets.count == 75)
        let regenerated = c.mergeGenerated()
        #expect(regenerated == 0)
        let report = c.mergeStarter(files: starterFiles, root: root, fingerprint: "v4")
        #expect(report.adopted == 3)
        #expect(report.added == 3)
        #expect(c.assets.count == 78)
        let ink = try #require(c.assets.first { $0.sourceKey == "starter:ink-fiber-4k.png" })
        #expect(ink.collection == "Material Textures")
        #expect(ink.favorite)                       // user's favorite survives
        #expect(ink.tags.contains("client-x"))      // user's tag survives
        #expect(!ink.tags.contains("imported"))
        let keyed = c.assets.filter { $0.importedPath == nil }.allSatisfy { $0.sourceKey?.hasPrefix("generated:") == true }
        #expect(keyed)
        // A second launch after migration changes nothing.
        let settled = c
        c.mergeGenerated(); c.mergeStarter(files: starterFiles, root: root, fingerprint: "v4")
        #expect(c == settled)
    }

    @Test func userImportsAreNeverAdopted() {
        var c = freshCatalog()
        let id = c.importFile(path: "/Users/me/Desktop/ink-fiber-4k.png")
        #expect(id != nil)
        let again = c.importFile(path: "/Users/me/Desktop/ink-fiber-4k.png")
        #expect(again == nil)   // no double import
        c.mergeStarter(files: starterFiles, root: "/elsewhere/StarterLibrary", fingerprint: "c")
        let mine = c.assets.first { $0.id == id }!
        #expect(mine.sourceKey == nil)
        #expect(mine.collection == "Imported")
        #expect(mine.importedPath == "/Users/me/Desktop/ink-fiber-4k.png")
    }

    @Test func removedBundledAssetsStayRemovedAcrossUpgrades() {
        var c = freshCatalog()
        let ids = Set(c.assets.filter { $0.sourceKey == "starter:ambient-bed.wav" || $0.sourceKey == "generated:Sound Beds:0" }.map(\.id))
        let removed = c.remove(ids)
        #expect(removed == 2)
        c.mergeGenerated()
        c.mergeStarter(files: starterFiles, root: "/x/StarterLibrary", fingerprint: "z")
        #expect(!c.assets.contains { $0.sourceKey == "starter:ambient-bed.wav" })
        #expect(!c.assets.contains { $0.sourceKey == "generated:Sound Beds:0" })
    }

    @Test func extractionDecision() {
        #expect(StudioCatalog.needsExtraction(installedFingerprint: nil, bundledFingerprint: "a", rootExists: false, missingFiles: 0))
        #expect(StudioCatalog.needsExtraction(installedFingerprint: "a", bundledFingerprint: "b", rootExists: true, missingFiles: 0))
        #expect(StudioCatalog.needsExtraction(installedFingerprint: "a", bundledFingerprint: "a", rootExists: true, missingFiles: 2))
        #expect(!StudioCatalog.needsExtraction(installedFingerprint: "a", bundledFingerprint: "a", rootExists: true, missingFiles: 0))
    }

    @Test func roundTripsThroughJSON() throws {
        var c = freshCatalog()
        _ = c.createCollection(named: "Moodboard")
        let data = try c.encoded()
        let back = try #require(StudioCatalog.decode(data))
        #expect(back == c)
        #expect(back.collections.contains("Moodboard"))
    }
}

@Suite("Studio batch editing")
struct StudioBatchTests {
    @Test func batchTaggingNormalizesAndSkipsDuplicates() {
        var c = freshCatalog()
        let ids = Set(c.assets.prefix(5).map(\.id))
        let first = c.addTags("  Launch , launch, Q3 ", to: ids)
        let second = c.addTags("launch", to: ids)
        #expect(first == 5)
        #expect(second == 0)
        #expect(c.commonTags(ids).contains("launch"))
        #expect(c.commonTags(ids).contains("q3"))
        let untagged = c.removeTag("q3", from: ids)
        #expect(untagged == 5)
        #expect(!c.commonTags(ids).contains("q3"))
        #expect(StudioCatalog.parseTags(" , ,") == [])
    }

    @Test func favoriteToggleActsOnTheWholeSelection() {
        var c = freshCatalog()
        let picked = Array(c.assets.prefix(3))
        let ids = Set(picked.map(\.id))
        c.toggleFavorite(ids)
        let allFav = c.assets.filter { ids.contains($0.id) }.allSatisfy { $0.favorite }
        #expect(allFav)
        c.toggleFavorite(ids)
        let noneFav = c.assets.filter { ids.contains($0.id) }.allSatisfy { !$0.favorite }
        #expect(noneFav)
    }

    @Test func dragToCollectionMovesAndRegistersTarget() {
        var c = freshCatalog()
        let ids = Set(c.assets.filter { $0.kind == .texture }.prefix(4).map(\.id))
        let moved = c.move(ids, to: "Brand Refresh")
        #expect(moved == 4)
        #expect(c.collections.contains("Brand Refresh"))
        #expect(c.count(in: "Brand Refresh") == 4)
        let movedAgain = c.move(ids, to: "Brand Refresh")
        let toAll = c.move(ids, to: StudioCatalog.allAssets)
        #expect(movedAgain == 0)
        #expect(toAll == 0)
        let favs = c.count(in: StudioCatalog.favorites)
        let notYet = c.assets.filter { ids.contains($0.id) && !$0.favorite }.count
        let faved = c.move(ids, to: StudioCatalog.favorites)
        #expect(faved == notYet)  // dropping on Favorites favorites them
        #expect(c.count(in: StudioCatalog.favorites) == favs + notYet)
        #expect(c.count(in: "Brand Refresh") == 4)                   // and does not move them
    }

    @Test func emptyCollectionsPersistAndRenameCleanly() {
        var c = freshCatalog()
        let a = c.createCollection()
        let b = c.createCollection()
        #expect(a == "New Collection" && b == "New Collection 2")
        #expect(c.count(in: a) == 0 && c.collections.contains(a))
        let reservedName = c.createCollection(named: "Favorites")
        #expect(reservedName == "New Collection 3")
        let id = c.assets[0].id
        c.move([id], to: a)
        let renamed = c.renameCollection(a, to: "Picks")
        #expect(renamed)
        #expect(c.assets.first { $0.id == id }?.collection == "Picks")
        #expect(!c.collections.contains(a))
        let toReserved = c.renameCollection("Picks", to: "All Assets")
        let toTaken = c.renameCollection("Picks", to: b)
        #expect(!toReserved)
        #expect(!toTaken)
    }

    @Test func searchMatchesTagsColorsAndCollections() {
        let c = freshCatalog()
        #expect(!c.filtered(search: "ink fiber", kind: nil, collection: StudioCatalog.allAssets).isEmpty)
        #expect(c.filtered(search: "", kind: .audio, collection: "Sound Beds").count == 13)
        #expect(!c.filtered(search: "#8C5CFF", kind: nil, collection: StudioCatalog.allAssets).isEmpty)
        #expect(c.filtered(search: "bundled", kind: nil, collection: StudioCatalog.allAssets).count == 6)
        #expect(c.filtered(search: "zzz-nothing", kind: nil, collection: StudioCatalog.allAssets).isEmpty)
    }

    @Test func resolutionClaimsMatchTheFile() {
        var a = StudioAsset(title: "Blueprint 4K", kind: .texture, tags: ["texture", "4k", "seamless"], collection: "Material Textures", palette: [], seed: 1, resolution: "2048 × 2048")
        StudioCatalog.correctResolutionClaims(&a, width: 2048, height: 2048)
        #expect(a.title == "Blueprint 2K")
        #expect(a.tags == ["texture", "2k", "seamless"])
        var b = StudioAsset(title: "Ink Fiber 4K", kind: .texture, tags: ["4k"], collection: "x", palette: [], seed: 1, resolution: "")
        StudioCatalog.correctResolutionClaims(&b, width: 4096, height: 4096)
        #expect(b.title == "Ink Fiber 4K" && b.tags == ["4k"])
        var c = StudioAsset(title: "Tiny 4K", kind: .texture, tags: ["4k"], collection: "x", palette: [], seed: 1, resolution: "")
        StudioCatalog.correctResolutionClaims(&c, width: 800, height: 600)
        #expect(c.title == "Tiny" && c.tags.isEmpty)
    }

    @Test func humanizedTitles() {
        #expect(StudioCatalog.humanize("editorial-vector-03") == "Editorial Vector 03")
        #expect(StudioCatalog.humanize("night_grid-4k") == "Night Grid 4K")
        #expect(StudioCatalog.stableSeed("a") == StudioCatalog.stableSeed("a"))
    }
}
