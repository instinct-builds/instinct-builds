import Foundation
import Testing
@testable import AsssetsCore

@Suite("Reviewed source history")
struct SourceHistoryTests {
    @Test func receiptAndPreservationAcrossReload() throws {
        var c = StudioCatalog()
        let id = c.importFile(path: "/art.png")!
        let board = c.createBoard(named: "Client board")
        _ = c.updateBoard(board) { _ = $0.addAsset(id, aspect: 1) }
        let rights = UsageRights(license: .client, source: "Client", credit: "Client")
        let i = c.assets.firstIndex { $0.id == id }!
        c.assets[i].rights = rights
        c.assets[i].tags = ["approved"]
        c.assets[i].resolution = "80 × 80"
        c.assets[i].palette = ["#111111"]
        let before = SourceFingerprint(size: 100, modified: 1, sha256: "old")
        let after = SourceFingerprint(size: 111, modified: 2, sha256: "new")
        let date = Date(timeIntervalSince1970: 42)
        let seeded = c.seedSourceFingerprint(before, for: id, path: "/art.png")
        #expect(seeded)
        let accepted = c.acceptChangedSource(after, for: id, path: "/art.png", palette: ["#222222"], resolution: "90 × 90", at: date)
        #expect(accepted)
        let record = try #require(c.sourceHistory(for: id).first)
        #expect(record.before == before && record.after == after && record.refreshedAt == date)
        #expect(record.beforePalette == ["#111111"] && record.afterPalette == ["#222222"])
        #expect(record.beforeResolution == "80 × 80" && record.afterResolution == "90 × 90")
        #expect(c.assets.first { $0.id == id }?.rights == rights)
        #expect(c.assets.first { $0.id == id }?.tags == ["approved"] && c.boardsUsing(id).count == 1)
        let duplicate = c.acceptChangedSource(after, for: id, path: "/art.png", palette: [], resolution: "", at: date)
        #expect(!duplicate)
        #expect(c.sourceRefreshHistory.count == 1)
        let decoded = try #require(StudioCatalog.decode(c.encoded()))
        #expect(decoded.sourceHistory(for: id) == [record])
    }

    @Test func onlyFiveNewestReceiptsEligibleForVisuals() throws {
        var c = StudioCatalog()
        let id = c.importFile(path: "/history.png")!
        _ = c.seedSourceFingerprint(SourceFingerprint(size: 1, modified: 1, sha256: "0"), for: id, path: "/history.png")
        for n in 1...7 {
            let next = SourceFingerprint(size: Int64(n + 1), modified: Double(n + 1), sha256: String(n))
            let accepted = c.acceptChangedSource(next, for: id, path: "/history.png", palette: [], resolution: "x", at: Date(timeIntervalSince1970: Double(n)))
            #expect(accepted)
        }
        let history = c.sourceHistory(for: id)
        let retained = c.sourceHistoryPreviewIDs(for: id)
        #expect(history.count == 7)
        #expect(retained.count == 5)
        #expect(retained == Set(history.prefix(5).map(\.id)))
        #expect(!retained.contains(history.last!.id))
        let decoded = try #require(StudioCatalog.decode(c.encoded()))
        #expect(decoded.sourceHistoryPreviewIDs(for: id) == retained)
    }

    @Test func legacyCatalogHasEmptyHistory() throws {
        var c = StudioCatalog()
        _ = c.importFile(path: "/old.png")
        var raw = try JSONSerialization.jsonObject(with: c.encoded()) as! [String: Any]
        raw.removeValue(forKey: "sourceRefreshHistory")
        let decoded = try #require(StudioCatalog.decode(JSONSerialization.data(withJSONObject: raw)))
        #expect(decoded.sourceRefreshHistory.isEmpty)
    }
}
