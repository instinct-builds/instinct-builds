import Foundation
import Testing
@testable import AsssetsCore

@Suite("Boards follow versions, nudge, copy and paste")
struct BoardFollowTests {
    private func stacked() -> (StudioCatalog, UUID, UUID, UUID) {
        var c = StudioCatalog()
        let v1 = c.importFile(path: "/drop/Lobby Floor v1.png")!, v2 = c.importFile(path: "/drop/Lobby Floor v2.png")!
        for i in c.assets.indices { c.assets[i].resolution = "2400 × 1600" }
        c.autoStack()
        let fin = c.importFile(path: "/drop/Lobby Floor final.png")!
        if let i = c.assets.firstIndex(where: { $0.id == fin }) { c.assets[i].resolution = "2000 × 2000" }
        c.autoStack()
        return (c, v1, v2, fin)
    }

    @Test func newerVersionAndWhereUsed() {
        var (c, v1, v2, fin) = stacked()
        #expect(c.newerVersion(of: v1)?.id == fin && c.newerVersion(of: v2)?.id == fin && c.newerVersion(of: fin) == nil)
        let loose = c.importFile(path: "/drop/Poster.png")!
        #expect(c.newerVersion(of: loose) == nil)
        let a = c.createBoard(named: "Lobby"), b = c.createBoard(named: "Options")
        _ = c.addToBoard(a, assets: [v2, loose]); _ = c.addToBoard(b, assets: [v1, fin])
        let uses = c.boardsUsing(fin)
        #expect(uses.map(\.boardName) == ["Lobby", "Options", "Options"])
        #expect(uses.map(\.label) == ["v2", "v1", "Final"])
        #expect(uses[0].newer == fin && uses[2].newer == nil)
        #expect(c.boardsUsing(loose).count == 1 && c.boardsUsing(UUID()).isEmpty)
        #expect(c.outdatedCards(on: a).count == 1 && c.outdatedCards(on: b).count == 1)
    }

    @Test func updateKeepsPlaceCropsNewShapeAndKeepsThread() {
        var (c, _, v2, fin) = stacked()
        let board = c.createBoard(named: "Lobby")
        _ = c.addToBoard(board, assets: [v2])
        c.noteGalleryShared("G", from: board)
        _ = c.applyFeedback(ReviewGallery.Feedback(gallery: "G", title: "", reviewer: "Mara", items: [.init(id: v2.uuidString, favorite: true, note: "Warmer", status: "approved")]), imported: "d")
        let card = c.board(board)!.items[0]
        #expect(c.board(board)!.status(of: card.id) == .approved)
        let n = c.updateToNewest(board: board, author: "Ari", saved: "2026-09-24T07:00:00Z")
        let b = c.board(board)!, now = b.items[0]
        #expect(n == 1 && now.assetID == fin && now.x == card.x && now.w == card.w && now.h == card.h)
        #expect(now.crop != nil)                              // square final in a 3:2 card: cropped from the middle
        #expect(b.status(of: card.id) == .open)
        #expect(b.replies(for: card.id).last?.text == "Updated from v2 to Final. It was Approved; back to Open for a fresh look.")
        #expect(b.versions.last?.name == "Before Update to Newest" && b.versions.last?.items[0].assetID == v2)
        #expect(b.pins()[card.id]?.pickedBy == ["Mara"] && b.pins()[card.id]?.comments.first?.text == "Warmer")
        #expect(b.earlierAssets[card.id] == [v2])
        #expect(c.updateToNewest(board: board, author: "Ari", saved: "t") == 0)
        let back = try! JSONDecoder().decode(Moodboard.self, from: JSONEncoder().encode(b))
        #expect(back.earlierAssets == b.earlierAssets)
    }

    @Test func updateOnlySomeAndSameShapeKeepsCrop() {
        var (c, v1, v2, _) = stacked()
        for i in c.assets.indices { c.assets[i].resolution = "2400 × 1600" }
        let board = c.createBoard(named: "L")
        _ = c.addToBoard(board, assets: [v1])
        _ = c.updateBoard(board) { b in b.addAsset(v2, aspect: 1.5) }
        let cards = c.board(board)!.items.map(\.id)
        let crop = BoardRect(x: 0.1, y: 0.1, w: 0.5, h: 0.5)
        _ = c.updateBoard(board) { b in b.setCrop(cards[0], crop) }
        #expect(c.updateToNewest(board: board, only: [cards[0]], author: "", saved: "t") == 1)
        let b = c.board(board)!
        #expect(b.items[0].crop == crop && b.items[1].assetID == v2)
        #expect(b.replies(for: cards[0]).first?.author == "Studio")
    }

    @Test func nudgeClampsAndMovesSections() {
        var b = Moodboard(name: "N"); b.snap = false
        let note = b.addNote("n", at: (x: 100, y: 5))
        let r = { (id: UUID) in b.items.first { $0.id == id }!.rect }
        #expect(b.nudge([note], dx: 1, dy: 0) == 1 && r(note).x == 101)
        b.nudge([note], dx: -10, dy: -10); #expect(r(note).x == 91 && r(note).y == 0)
        #expect(b.nudge([note], dx: 0, dy: -5) == 0 && b.nudge([UUID()], dx: 1, dy: 1) == 0)
        let inside = b.addNote("in", at: (x: 420, y: 420))
        let frame = b.addFrame("S", rect: BoardRect(x: 400, y: 400, w: 400, h: 300))
        b.nudge([frame], dx: 20, dy: 0); #expect(r(inside).x == 440 && r(frame).x == 420)
    }

    @Test func copyPasteKeepsArrowsAndStepsOnSameBoard() {
        var a = Moodboard(name: "A"); a.snap = false
        let x = a.addNote("x", at: (x: 40, y: 40)), y = a.addNote("y", at: (x: 400, y: 40)), z = a.addNote("z", at: (x: 800, y: 40))
        _ = a.connect(x, y, label: "then"); _ = a.connect(y, z)
        a.setStatus(.approved, for: [x])
        let clip = a.copyCards([x, y])!
        #expect(clip.items.count == 2 && clip.connectors.count == 1 && a.copyCards([UUID()]) == nil)
        let pasted = a.paste(clip)
        #expect(pasted.count == 2 && a.items.count == 5 && a.connectors.count == 3)
        let p0 = a.items.first { $0.id == pasted[0] }!
        #expect(p0.x == 40 + a.grid * 2 && p0.z > a.items.first { $0.id == z }!.z && a.status(of: pasted[0]) == .open)
        #expect(a.connectors.last?.label == "then" && Set([a.connectors.last!.from, a.connectors.last!.to]) == Set(pasted))
        let again = a.paste(clip.shifted(by: a.grid * 2))
        #expect(a.items.first { $0.id == again[0] }!.x == 40 + a.grid * 4)
        var other = Moodboard(name: "B")
        let onB = other.paste(clip)
        #expect(other.items.first { $0.id == onB[0] }!.x == 40 && other.connectors.count == 1)
    }
}
