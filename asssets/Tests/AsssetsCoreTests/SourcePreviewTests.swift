import Foundation
import Testing
import AsssetsCore

@Suite("Preview snapshot binding")
struct SourcePreviewTests {
    @Test func onlyExactBaselineCanBindAndRefreshClears() throws {
        var c = StudioCatalog()
        let id = c.importFile(path: "/source.png")!
        let old = SourceFingerprint(size: 10, modified: 1, sha256: "old")
        let new = SourceFingerprint(size: 11, modified: 2, sha256: "new")
        let before = c.bindSourcePreview(hash: "old", for: id, path: "/source.png")
        #expect(!before)
        _ = c.seedSourceFingerprint(old, for: id, path: "/source.png")
        let wrong = c.bindSourcePreview(hash: "wrong", for: id, path: "/source.png")
        #expect(!wrong)
        let bound = c.bindSourcePreview(hash: "old", for: id, path: "/source.png")
        #expect(bound)
        #expect(c.assets.first { $0.id == id }?.sourcePreviewHash == "old")
        _ = c.acceptChangedSource(new, for: id, path: "/source.png", palette: ["#000000"], resolution: "2 × 2")
        #expect(c.assets.first { $0.id == id }?.sourcePreviewHash == nil)
        let stale = c.bindSourcePreview(hash: "old", for: id, path: "/source.png")
        #expect(!stale)
        let decoded = try #require(StudioCatalog.decode(c.encoded()))
        #expect(decoded.assets.first { $0.id == id }?.sourcePreviewHash == nil)
    }

    @Test func olderAssetWithoutSnapshotDecodes() throws {
        var c = StudioCatalog()
        _ = c.importFile(path: "/old.png")
        var raw = try JSONSerialization.jsonObject(with: c.encoded()) as! [String: Any]
        var assets = raw["assets"] as! [[String: Any]]
        assets[0].removeValue(forKey: "sourcePreviewHash")
        raw["assets"] = assets
        let decoded = try #require(StudioCatalog.decode(JSONSerialization.data(withJSONObject: raw)))
        #expect(decoded.assets[0].sourcePreviewHash == nil)
    }
}
