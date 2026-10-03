import Foundation
import Testing
@testable import AsssetsCore

@Suite("Catalog recovery")
struct CatalogRecoveryTests {
    func tmp() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("rec-" + UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    func goodCatalog(_ n: Int) -> StudioCatalog {
        var c = StudioCatalog()
        for i in 0..<n { _ = c.importFile(path: "/r/a\(i).png") }
        return c
    }

    @Test func missingFileIsTheSilentFreshInstallPath() {
        let d = tmp()
        let out = CatalogRecovery.load(catalogURL: d.appendingPathComponent("studio-catalog.json"), legacyURL: d.appendingPathComponent("studio-library.json"))
        #expect(out == .fresh)
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: d.path)) ?? []).isEmpty)
    }

    @Test func corruptFileIsMovedAsideNotOverwritten() throws {
        let d = tmp(), url = d.appendingPathComponent("studio-catalog.json")
        try Data("{ not json".utf8).write(to: url)
        let out = CatalogRecovery.load(catalogURL: url, legacyURL: d.appendingPathComponent("studio-library.json"))
        guard case let .unreadable(original, preserved) = out, let kept = preserved else { Issue.record("expected unreadable with a preserved copy"); return }
        #expect(original == "studio-catalog.json")
        #expect(kept.lastPathComponent.hasPrefix("studio-catalog.corrupt-") && kept.pathExtension == "json")
        #expect(try String(contentsOf: kept, encoding: .utf8) == "{ not json")
        #expect(!FileManager.default.fileExists(atPath: url.path))
        // A second bad file in the same second must not replace the first .corrupt copy.
        try Data("second".utf8).write(to: url)
        let again = CatalogRecovery.load(catalogURL: url, legacyURL: d.appendingPathComponent("studio-library.json"), now: Date())
        guard case let .unreadable(_, p2) = again, let second = p2 else { Issue.record("expected second preserved copy"); return }
        #expect(second != kept)
        #expect(try String(contentsOf: kept, encoding: .utf8) == "{ not json")
        #expect(try String(contentsOf: second, encoding: .utf8) == "second")
    }

    @Test func readableCatalogLoadsAndAnEmptyOneIsFresh() throws {
        let d = tmp(), url = d.appendingPathComponent("studio-catalog.json"), legacy = d.appendingPathComponent("studio-library.json")
        try goodCatalog(3).encoded().write(to: url)
        if case let .loaded(c) = CatalogRecovery.load(catalogURL: url, legacyURL: legacy) { #expect(c.assets.count == 3) } else { Issue.record("expected loaded") }
        try StudioCatalog().encoded().write(to: url)
        #expect(CatalogRecovery.load(catalogURL: url, legacyURL: legacy) == .fresh)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func snapshotsKeepOnlyTheNewestFive() throws {
        let d = tmp(), url = d.appendingPathComponent("studio-catalog.json"), b = d.appendingPathComponent("Backups")
        try goodCatalog(2).encoded().write(to: url)
        for i in 0..<8 { _ = CatalogRecovery.snapshot(catalogURL: url, backups: b, now: Date(timeIntervalSince1970: 1_800_000_000 + Double(i) * 10)) }
        let kept = CatalogRecovery.snapshotURLs(backups: b)
        #expect(kept.count == CatalogRecovery.keepSnapshots)
        #expect(kept[0].lastPathComponent > kept[4].lastPathComponent)
        #expect(CatalogRecovery.snapshot(catalogURL: d.appendingPathComponent("missing.json"), backups: b) == nil)
    }

    @Test func restoreKeepsTheCurrentFileAndShowsCountsFirst() throws {
        let d = tmp(), url = d.appendingPathComponent("studio-catalog.json"), b = d.appendingPathComponent("Backups")
        try goodCatalog(4).encoded().write(to: url)
        CatalogRecovery.snapshot(catalogURL: url, backups: b)
        try Data("garbage".utf8).write(to: b.appendingPathComponent("catalog-00000000-000000.json"))
        let list = CatalogRecovery.backups(backups: b)
        #expect(list.count == 1 && list[0].assets == 4 && list[0].boards == 0)
        try goodCatalog(1).encoded().write(to: url)
        let before = try Data(contentsOf: url)
        guard let r = CatalogRecovery.restore(list[0], catalogURL: url), let kept = r.kept else { Issue.record("restore failed"); return }
        #expect(r.catalog.assets.count == 4)
        #expect((try? Data(contentsOf: kept)) == before)
        if case let .loaded(c) = CatalogRecovery.load(catalogURL: url, legacyURL: d.appendingPathComponent("l.json")) { #expect(c.assets.count == 4) } else { Issue.record("restored file should load") }
        let bad = CatalogRecovery.Backup(url: b.appendingPathComponent("catalog-00000000-000000.json"), assets: 0, boards: 0)
        let unchanged = try Data(contentsOf: url)
        #expect(CatalogRecovery.restore(bad, catalogURL: url) == nil)
        #expect(try Data(contentsOf: url) == unchanged)
    }
}
