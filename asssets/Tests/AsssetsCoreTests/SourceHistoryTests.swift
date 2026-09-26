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

    @Test func timelineStaysWithOneAssetAndFindsNeighbors() throws {
        var c = StudioCatalog()
        let id = c.importFile(path: "/one.png")!
        let other = c.importFile(path: "/two.png")!
        _ = c.seedSourceFingerprint(SourceFingerprint(size: 1, modified: 1, sha256: "0"), for: id, path: "/one.png")
        _ = c.seedSourceFingerprint(SourceFingerprint(size: 1, modified: 1, sha256: "a"), for: other, path: "/two.png")
        for n in 1...3 {
            let next = SourceFingerprint(size: Int64(n + 1), modified: Double(n + 1), sha256: String(n))
            _ = c.acceptChangedSource(next, for: id, path: "/one.png", palette: [], resolution: "x", at: Date(timeIntervalSince1970: Double(n)))
        }
        _ = c.acceptChangedSource(SourceFingerprint(size: 2, modified: 2, sha256: "b"), for: other, path: "/two.png", palette: [], resolution: "x", at: Date())
        let history = c.sourceHistory(for: id)
        let newest = SourceReceiptTimeline(catalog: c, assetID: id, selectedID: history[0].id)
        #expect(newest.receipts.count == 3 && newest.position == 1)
        #expect(newest.newer == nil && newest.older?.id == history[1].id)
        let middle = SourceReceiptTimeline(catalog: c, assetID: id, selectedID: history[1].id)
        #expect(middle.position == 2 && middle.newer?.id == history[0].id && middle.older?.id == history[2].id)
        let oldest = SourceReceiptTimeline(catalog: c, assetID: id, selectedID: history[2].id)
        #expect(oldest.position == 3 && oldest.older == nil && oldest.newer?.id == history[1].id)
        #expect(!newest.receipts.contains(where: { $0.assetID == other }))
    }

    @Test func filenameAndInclusiveDateSearchAreReadOnly() throws {
        var c = StudioCatalog()
        let lobby = c.importFile(path: "/drops/Northlight Lobby.png")!
        let cork = c.importFile(path: "/drops/Atrium Cork Wall.png")!
        let first = Date(timeIntervalSince1970: 86_400)
        let second = Date(timeIntervalSince1970: 172_800)
        _ = c.seedSourceFingerprint(SourceFingerprint(size: 1, modified: 1, sha256: "a"), for: lobby, path: "/drops/Northlight Lobby.png")
        _ = c.seedSourceFingerprint(SourceFingerprint(size: 1, modified: 1, sha256: "b"), for: cork, path: "/drops/Atrium Cork Wall.png")
        _ = c.acceptChangedSource(SourceFingerprint(size: 2, modified: 2, sha256: "c"), for: lobby,
            path: "/drops/Northlight Lobby.png", palette: [], resolution: "x", at: first)
        _ = c.acceptChangedSource(SourceFingerprint(size: 2, modified: 2, sha256: "d"), for: cork,
            path: "/drops/Atrium Cork Wall.png", palette: [], resolution: "x", at: second)
        #expect(c.matchingSourceReceipts(filename: " lobby ").map(\.assetID) == [lobby])
        #expect(c.matchingSourceReceipts(filename: "NORTHLIGHT").map(\.assetID) == [lobby])
        #expect(c.matchingSourceReceipts(filename: "").map(\.assetID) == [cork, lobby])
        #expect(c.matchingSourceReceipts(filename: "", from: first, through: first).map(\.assetID) == [lobby])
        #expect(c.matchingSourceReceipts(filename: "", from: second, through: second).map(\.assetID) == [cork])
        #expect(c.matchingSourceReceipts(filename: "", from: second, through: first).isEmpty)
        #expect(c.sourceRefreshHistory.count == 2)
    }

    @Test func csvHasFilteredFactsButNoPathsOrBytes() throws {
        var c = StudioCatalog()
        let id = c.importFile(path: "/private/Client, one.png")!
        _ = c.seedSourceFingerprint(SourceFingerprint(size: 12, modified: 1, sha256: "old-hash"), for: id, path: "/private/Client, one.png")
        _ = c.acceptChangedSource(SourceFingerprint(size: 34, modified: 2, sha256: "new-hash"), for: id,
            path: "/private/Client, one.png", palette: ["#111111"], resolution: "4 × 4", at: Date(timeIntervalSince1970: 0))
        let rows = c.matchingSourceReceipts(filename: "Client")
        let csv = SourceReceiptCSV.render(rows, titles: [id: "=SUM(1,2)"])
        #expect(rows.count == 1)
        #expect(csv.contains("1970-01-01T00:00:00.000Z"))
        #expect(csv.contains("\"'=SUM(1,2)\"") && csv.contains("\"Client, one.png\""))
        #expect(csv.contains("\"12\",\"34\",\"old-hash\",\"new-hash\""))
        #expect(!csv.contains("/private") && !csv.contains("#111111"))
        #expect(csv.components(separatedBy: "\r\n").count == 3)
        #expect(SourceReceiptCSV.render([], titles: [:]).components(separatedBy: "\r\n").count == 2)
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
