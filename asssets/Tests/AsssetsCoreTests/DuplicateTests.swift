import Foundation
import Testing
@testable import AsssetsCore

@Suite("Duplicates")
struct DuplicateTests {
    @Test func onlySameSizeFilesGetHashed() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        #expect(Duplicates.needsHash(sizes: [a: 10, b: 10, c: 11, d: 0]) == [a, b])
    }

    @Test func groupsFollowCatalogOrder() {
        let ids = (0..<5).map { _ in UUID() }
        let g = Duplicates.groups(hashes: [ids[4]: "x", ids[1]: "y", ids[3]: "y", ids[0]: "x", ids[2]: "z"], order: ids)
        #expect(g == [[ids[0], ids[4]], [ids[1], ids[3]]])
    }

    @Test func keeperPrefersFavoriteThenFiledThenBundledThenOldest() {
        func asset(_ col: String, fav: Bool = false, key: String? = nil) -> StudioAsset {
            StudioAsset(title: "t", kind: .image, tags: [], collection: col, palette: [], seed: 0, favorite: fav, importedPath: "/x", resolution: "", sourceKey: key)
        }
        let inbox = asset("Inbox"), filed = asset("Brand"), starter = asset("Material Textures", key: "starter:t.png"), fav = asset("Inbox", fav: true)
        #expect(Duplicates.suggestedKeeper([inbox, filed]) == filed.id)
        #expect(Duplicates.suggestedKeeper([filed, starter]) == starter.id)
        #expect(Duplicates.suggestedKeeper([starter, fav]) == fav.id)
        let older = asset("Inbox")
        #expect(Duplicates.suggestedKeeper([inbox, older]) == older.id)
    }

    @Test func mergeKeepsMetadataAndBlocksReimport() {
        var c = StudioCatalog()
        c.addWatchFolder("/w")
        _ = c.syncWatch(found: ["/w/copy.png"])
        let copy = c.assets[0].id
        c.toggleFavorite([copy])
        c.addTags("hero", to: [copy])
        let keep = c.importFile(path: "/lib/orig.png")!
        c.move([keep], to: "Brand")
        let removed = c.mergeDuplicates(keep: keep, remove: [copy, keep])
        #expect(removed == 1)
        let k = c.assets.first { $0.id == keep }!
        #expect(k.favorite && k.tags.contains("hero") && k.collection == "Brand" && !k.tags.contains("watched"))
        let again = c.syncWatch(found: ["/w/copy.png"])
        #expect(again.isEmpty)
    }
}
