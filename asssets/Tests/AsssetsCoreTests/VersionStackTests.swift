import Foundation
import Testing
@testable import AsssetsCore

@Suite("Version stacks")
struct VersionStackTests {
    func a(_ title: String, _ kind: MediaKind = .image) -> StudioAsset {
        StudioAsset(title: title, kind: kind, tags: [], collection: "Inbox", palette: [], seed: 0, importedPath: "/x/\(title).png", resolution: "")
    }

    @Test func parsesMarkers() {
        #expect(VersionStacks.parse("Lobby Floor v2")?.base == "lobby floor")
        #expect(VersionStacks.parse("Lobby Floor v2")?.rank == 2)
        #expect(VersionStacks.parse("lobby_floor_v03")?.label == "v3")
        #expect(VersionStacks.parse("Hero version 4")?.rank == 4)
        #expect(VersionStacks.parse("Hero rev5")?.rank == 5)
        #expect(VersionStacks.parse("Hero Final")!.rank > VersionStacks.parse("Hero v9")!.rank)
        #expect(VersionStacks.parse("Hero final final")!.rank > VersionStacks.parse("Hero Final")!.rank)
        #expect(VersionStacks.parse("Hero FINAL 2")?.label == "Final 3")
        #expect(VersionStacks.parse("Hero draft")?.rank == -1)
        #expect(VersionStacks.parse("Hero copy 2")?.base == "hero")
        // Not versions.
        #expect(VersionStacks.parse("Editorial Vector 01") == nil)
        #expect(VersionStacks.parse("Night Grid 4K") == nil)
        #expect(VersionStacks.parse("Final") == nil)
        #expect(VersionStacks.parse("Vivid Poster") == nil)
        #expect(VersionStacks.parse("Brand Mark v3")?.base == "brand mark")
    }

    @Test func autoStackGroupsAndOrders() {
        var c = StudioCatalog()
        c.assets = [a("Lobby Floor final"), a("Lobby Floor v1"), a("Lobby Floor"), a("Lobby Floor v2"),
                    a("Lobby Floor v2", .video), a("Hero v1"), a("Other"), a("Editorial Vector 01"), a("Editorial Vector 02")]
        #expect(c.autoStack() == 4)
        let v = c.versions(of: c.assets[0].id).map(\.title)
        #expect(v == ["Lobby Floor", "Lobby Floor v1", "Lobby Floor v2", "Lobby Floor final"])
        #expect(c.assets[4].stackID == nil)          // a video isn't a version of an image
        #expect(c.assets[5].stackID == nil)          // one version alone is no stack
        #expect(c.assets[7].stackID == nil && c.assets[8].stackID == nil)
        #expect(c.autoStack() == 0)                  // idempotent
        // A new version joins the existing stack.
        c.assets.append(a("Lobby Floor v3"))
        #expect(c.autoStack() == 1)
        #expect(c.versions(of: c.assets[0].id).count == 5)
        #expect(c.stackTop(c.assets[1].id)?.title == "Lobby Floor final")
    }

    @Test func collapseShowsNewestInPlace() {
        var c = StudioCatalog()
        c.assets = [a("Other"), a("Hero v1"), a("Hero v2"), a("Last")]
        c.autoStack()
        #expect(c.collapsingStacks(c.assets).map(\.title) == ["Other", "Hero v2", "Last"])
        // Search that matches only v1 still shows it.
        #expect(c.collapsingStacks([c.assets[1]]).map(\.title) == ["Hero v1"])
        let s = c.assets[1].stackID!
        #expect(c.collapsingStacks(c.assets, expanded: [s]).count == 4)
        #expect(c.stackCount(c.assets[2]) == 2)
    }

    @Test func manualStackAndUnstack() {
        var c = StudioCatalog()
        c.assets = [a("Poster A"), a("Poster B"), a("Poster C"), a("Hero v1"), a("Hero v2")]
        let sid = c.stack([c.assets[0].id, c.assets[1].id, c.assets[2].id])
        #expect(sid != nil && c.stackCount(c.assets[0]) == 3)
        #expect(c.stack([c.assets[0].id]) == nil)
        c.autoStack()
        c.unstack([c.assets[4].id])                  // Hero stack dissolves, v2 stays out of auto
        #expect(c.assets[3].stackID == nil && c.assets[4].stackID == nil && c.assets[4].unstacked)
        #expect(c.autoStack() == 0)
        c.unstack([c.assets[0].id])
        #expect(c.stackCount(c.assets[1]) == 2)
        // Survives save and load; older catalogs decode with no stacks.
        let back = StudioCatalog.decode(try! c.encoded())!
        #expect(back.assets[1].stackID == c.assets[1].stackID && back.assets[4].unstacked)
    }
}
