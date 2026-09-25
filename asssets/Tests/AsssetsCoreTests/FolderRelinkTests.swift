import Foundation
import Testing
@testable import AsssetsCore

@Suite("Folder relocation dry run")
struct FolderRelinkTests {
    @Test func exactPathsOnlyAndOneApplyKeepsIdentity() throws {
        var c = StudioCatalog()
        let a = c.importFile(path: "/old/project/sub/Poster.png")!
        let b = c.importFile(path: "/old/project/sub/Title.png")!
        let other = c.importFile(path: "/old/other/Poster.png")!
        let present: Set<String> = ["/new/project/sub/Poster.png", "/new/project/Title.png", "/old/other/Poster.png"]
        let preview = FolderRelinkPreview(catalog: c, oldRoot: "/old/project", newRoot: "/new/project",
                                          exists: { present.contains($0) }, isFile: { present.contains($0) })
        #expect(preview.matched.map(\.id) == [a])
        #expect(preview.unmatched.map(\.id) == [b])
        #expect(preview.rows.count == 2)
        #expect(c.relinkFolder(preview) == 1)
        #expect(c.assets.first { $0.id == a }?.importedPath == "/new/project/sub/Poster.png")
        #expect(c.assets.first { $0.id == b }?.importedPath == "/old/project/sub/Title.png")
        #expect(c.assets.first { $0.id == other }?.importedPath == "/old/other/Poster.png")
        #expect(StudioCatalog.decode(try c.encoded())?.assets.first { $0.id == a }?.id == a)
    }

    @Test func collisionAndDirectoryAreNotChanged() {
        var c = StudioCatalog()
        let a = c.importFile(path: "/old/a.png")!
        _ = c.importFile(path: "/new/a.png")!
        let b = c.importFile(path: "/old/sub/b.png")!
        let preview = FolderRelinkPreview(catalog: c, oldRoot: "/old", newRoot: "/new",
            exists: { $0 == "/new/a.png" || $0 == "/new/sub/b.png" }, isFile: { $0 == "/new/a.png" })
        #expect(Set(preview.ambiguous.map(\.id)) == Set([a, b]))
        #expect(c.relinkFolder(preview) == 0)
    }
}
