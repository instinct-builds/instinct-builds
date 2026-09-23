import Foundation
import Testing
@testable import AsssetsCore

@Suite("Moodboards")
struct MoodboardTests {
    @Test func aspectFromResolution() {
        #expect(Moodboard.aspect(resolution: "2400 × 1600") == 1.5)
        #expect(Moodboard.aspect(resolution: "1080x1920") == 0.5625)
        #expect(Moodboard.aspect(resolution: "") == 4.0 / 3.0)
        #expect(Moodboard.aspect(resolution: "10000 × 1") == 4)
    }

    @Test func addFlowsAndSnaps() {
        var b = Moodboard(name: "B")
        let a1 = b.addAsset(UUID(), aspect: 1.5)
        let first = b.items[0]
        #expect(first.id == a1 && first.x == 40 && first.y == 40 && first.w == 280 && abs(first.h - 187) <= 1)
        b.addAsset(UUID(), aspect: 1)
        #expect(b.items[1].x == 340 && b.items[1].y == 40)
        for _ in 0..<6 { b.addAsset(UUID(), aspect: 1) }
        #expect(b.items.allSatisfy { $0.x.truncatingRemainder(dividingBy: 20) == 0 && $0.y.truncatingRemainder(dividingBy: 20) == 0 })
        #expect(b.items.allSatisfy { $0.x + $0.w <= Moodboard.flowWidth })
        #expect(b.items.map(\.y).max()! > 40) // wrapped onto a second row
        #expect(Set(b.items.map(\.z)).count == b.items.count)
    }

    @Test func addAssetsAtPointSkipsDuplicates() {
        var b = Moodboard(name: "B")
        let ids = (0..<6).map { _ in UUID() }
        let added = b.addAssets(ids.map { (id: $0, aspect: 1.0) } + [(id: ids[0], aspect: 1.0)], at: (x: 100, y: 100))
        #expect(added.count == 6)
        #expect(b.items[0].x == 100 && b.items[0].y == 100)
        #expect(b.items[4].x == 100 && b.items[4].y > 100) // fifth wraps
        #expect(b.addAssets([(id: ids[2], aspect: 1)]).isEmpty)
    }

    @Test func moveResizeLayer() {
        var b = Moodboard(name: "B")
        let a = b.addAsset(UUID(), aspect: 2)
        let n = b.addNote("Warm lobby, brass details")
        b.move(a, x: 133, y: -50)
        #expect(b.items[0].x == 140 && b.items[0].y == 0)
        b.resize(a, w: 401, h: 999)
        #expect(b.items[0].w == 400 && b.items[0].h == 200) // keeps 2:1
        b.resize(n, w: 10, h: 10)
        #expect(b.items[1].w == Moodboard.minSize && b.items[1].h == Moodboard.minSize)
        #expect(b.layered.last?.id == n)
        b.bringToFront(a)
        #expect(b.layered.last?.id == a)
        b.sendToBack(a)
        #expect(b.layered.first?.id == a)
        b.snap = false
        b.move(n, x: 133.5, y: 7)
        #expect(b.items[1].x == 133.5)
        b.setText(n, "Changed")
        #expect(b.items[1].text == "Changed")
        #expect(b.remove([a]) == 1 && b.items.count == 1)
    }

    @Test func paletteCardsAndForgetting() {
        var b = Moodboard(name: "B")
        let src = UUID()
        #expect(b.addPalette(["zzz", ""]) == nil)
        let p = b.addPalette(["#aabbcc", "#112233", "nope", "#445566"], from: src)!
        #expect(b.items.first { $0.id == p }?.colors == ["#AABBCC", "#112233", "#445566"])
        b.addAsset(src, aspect: 1)
        b.forgetAssets([src])
        #expect(b.items.count == 1 && b.items[0].kind == .palette && b.items[0].assetID == nil)
    }

    @Test func tidyAndBounds() {
        var b = Moodboard(name: "B")
        #expect(b.bounds == nil && b.exportRect.w == 800)
        for i in 0..<5 { b.addNote("n\(i)", at: (x: Double(i) * 37, y: 900)) }
        b.tidy()
        #expect(b.items.allSatisfy { $0.y >= 40 && $0.x >= 40 })
        let bb = b.bounds!
        #expect(bb.x == 40 && bb.y == 40)
        #expect(b.exportRect.x == 0 && b.exportRect.w == bb.w + 80)
    }

    @Test func catalogBoardsRoundTripAndCleanUp() throws {
        var c = StudioCatalog()
        let asset = StudioAsset(title: "A", kind: .image, tags: [], collection: "X", palette: ["#FF0000"], seed: 1, resolution: "1600 × 1200")
        c.assets = [asset]
        let id = c.createBoard(named: "Lobby")
        let id2 = c.createBoard(named: "Lobby")
        #expect(c.board(id2)?.name == "Lobby 2")
        #expect(!c.renameBoard(id2, to: "Lobby") && c.renameBoard(id2, to: "Cafe"))
        #expect(c.addToBoard(id, assets: [asset.id, UUID()]) == 1)
        #expect(c.board(id)?.items.first?.h == 210) // 280 wide at 4:3
        c.updateBoard(id) { $0.addNote("hi") }
        let back = StudioCatalog.decode(try c.encoded())!
        #expect(back.boards == c.boards)
        _ = c.remove([asset.id])
        #expect(c.board(id)?.items.map(\.kind) == [.note])
        #expect(c.deleteBoard(id2) && c.boards.count == 1)
        // 1.15 catalogs have no boards key.
        let old = StudioCatalog.decode(Data(#"{"assets":[]}"#.utf8))!
        #expect(old.boards.isEmpty)
    }
}
