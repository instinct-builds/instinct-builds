import Foundation
import Testing
@testable import AsssetsCore

@Suite("Watch folders")
struct WatchFolderTests {
    @Test func importsNewFilesIntoInboxOnce() {
        var c = StudioCatalog()
        let r1 = c.addWatchFolder("/Users/s/Drops/")
        #expect(r1)
        let found = ["/Users/s/Drops/hero shot.png", "/Users/s/Drops/notes.txt", "/Users/s/Drops/.hidden.png",
                     "/Users/s/Drops/.cache/x.png", "/Users/s/Drops/sub/icon.svg", "/Users/s/Elsewhere/a.png"]
        let first = c.syncWatch(found: found)
        #expect(first.count == 2)
        #expect(c.assets.allSatisfy { $0.collection == StudioCatalog.inboxCollection && $0.tags.contains("watched") })
        #expect(Set(c.assets.compactMap(\.importedPath)) == ["/Users/s/Drops/hero shot.png", "/Users/s/Drops/sub/icon.svg"])
        let r2 = c.syncWatch(found: found)
        #expect(r2.isEmpty)                     // idempotent
        #expect(c.collections.contains(StudioCatalog.inboxCollection))
    }

    @Test func respectsExistingImportsMovesAndRemovals() {
        var c = StudioCatalog()
        c.addWatchFolder("/w")
        let manual = c.importFile(path: "/w/a.png")!
        c.move([manual], to: "Brand")
        let r3 = c.syncWatch(found: ["/w/a.png", "/w/b.png"])
        #expect(r3.count == 1)
        #expect(c.assets.first { $0.id == manual }?.collection == "Brand")
        let b = c.assets.first { $0.importedPath == "/w/b.png" }!.id
        c.remove([b])
        let r4 = c.syncWatch(found: ["/w/a.png", "/w/b.png"])
        #expect(r4.isEmpty)   // removed stays removed
        let r5 = c.importFile(path: "/w/b.png")
        #expect(r5 != nil)                  // unless the user imports it by hand
    }

    @Test func folderListNormalizes() {
        var c = StudioCatalog()
        let r6 = c.addWatchFolder("/p/sub")
        #expect(r6)
        let r7 = c.addWatchFolder("/p")
        #expect(r7)            // parent replaces the child
        #expect(c.watchFolders == ["/p"])
        let r8 = c.addWatchFolder("/p/other")
        #expect(!r8)     // already covered
        let r9 = c.addWatchFolder("/p/")
        #expect(!r9)
        #expect(!c.isWatched("/px/file.png"))
        c.removeWatchFolder("/p/")
        #expect(c.watchFolders.isEmpty)
    }

    @Test func missingFilesAndPersistence() throws {
        var c = StudioCatalog()
        c.addWatchFolder("/w")
        c.syncWatch(found: ["/w/a.png", "/w/b.png"])
        c.mergeGenerated()
        let a = c.assets.first { $0.importedPath == "/w/a.png" }!.id
        #expect(c.missingIDs { $0 != "/w/a.png" } == [a])               // generated studies have no file, never "missing"
        let back = StudioCatalog.decode(try c.encoded())!
        #expect(back.watchFolders == ["/w"])
        let old = #"{"schemaVersion":2,"assets":[]}"#.data(using: .utf8)!
        #expect((try JSONDecoder().decode(StudioCatalog.self, from: old)).watchFolders.isEmpty)
    }
}
