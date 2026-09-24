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

@Suite("Presenting and sharing boards")
struct BoardPresentTests {
    @Test func readingOrderIsRowsThenColumns() {
        var b = Moodboard(name: "B"); b.snap = false
        let c = b.addNote("c", at: (x: 600, y: 50))
        let a = b.addNote("a", at: (x: 40, y: 40))
        let d = b.addNote("d", at: (x: 40, y: 400))
        let bb = b.addNote("b", at: (x: 320, y: 90))   // starts lower but inside the first row's upper half
        #expect(b.readingOrder.map(\.id) == [a, bb, c, d])
        #expect(Moodboard(name: "E").readingOrder.isEmpty)
    }

    @Test func fitCentersAndClamps() {
        let f = Moodboard.fit(BoardRect(x: 100, y: 100, w: 200, h: 100), width: 1000, height: 600, margin: 50)
        #expect(f.scale == 4) // capped
        #expect(f.x == (1000 - 800) / 2 - 400 && f.y == (600 - 400) / 2 - 400)
        let g = Moodboard.fit(BoardRect(x: 0, y: 0, w: 2000, h: 500), width: 1000, height: 600, margin: 0)
        #expect(g.scale == 0.5 && g.x == 0 && g.y == 175)
        #expect(Moodboard.fit(BoardRect(x: 0, y: 0, w: 0, h: 0), width: 10, height: 10) == (1, 0, 0))
    }

    @Test func gallerySpotsAndManifest() throws {
        var b = Moodboard(name: "B")
        let a1 = UUID(), a2 = UUID(), gone = UUID()
        b.addAsset(a1, aspect: 1, width: 200, at: (x: 40, y: 40))
        b.addAsset(a2, aspect: 2, width: 400, at: (x: 260, y: 40))
        b.addAsset(gone, aspect: 1, at: (x: 700, y: 40))
        b.addNote("note")
        let spots = ReviewGallery.spots(for: b, including: [a1, a2])
        #expect(spots.map(\.id) == [a1.uuidString, a2.uuidString])
        let r = b.exportRect
        #expect(abs(spots[0].x - 40 / r.w) < 1e-9 && abs(spots[1].w - 400 / r.w) < 1e-9)
        #expect(spots.allSatisfy { $0.x >= 0 && $0.y >= 0 && $0.x + $0.w <= 1 && $0.y + $0.h <= 1 })
        let m = ReviewGallery.Manifest(gallery: "g", title: "Board", created: "2026-09-23", items: [],
                                       board: .init(image: "board.png", width: 2000, height: 1000, spots: spots))
        let back = try JSONDecoder().decode(ReviewGallery.Manifest.self, from: JSONEncoder().encode(m))
        #expect(back == m)
        // 1.9-1.16 manifests have no board.
        let old = try JSONDecoder().decode(ReviewGallery.Manifest.self, from: Data(#"{"gallery":"g","title":"t","created":"x","items":[]}"#.utf8))
        #expect(old.board == nil)
        let html = ReviewGallery.html(m)
        #expect(html.contains("id=\"bwrap\"") && html.contains("\"board.png\"") && !html.contains("https://"))
    }
}

@Suite("Canvas editing")
struct BoardEditingTests {
    /// Three 100x100 notes in a row at x 40 / 200 / 360, y 40, snap off.
    func row() -> (Moodboard, [UUID]) {
        var b = Moodboard(name: "B"); b.snap = false
        let ids = [40.0, 200, 360].map { x -> UUID in
            let id = b.addNote("n", at: (x: x, y: 40)); b.resize(id, w: 100, h: 100); return id
        }
        return (b, ids)
    }

    @Test func framesHoldTheirContents() {
        var (b, ids) = row()
        let f = b.frame(around: [ids[0], ids[1]], label: "Materials")!
        let fr = b.items.first { $0.id == f }!
        #expect(fr.kind == .frame && fr.text == "Materials")
        #expect(fr.x == 20 && fr.y == 0 && fr.maxXY == (320, 160))
        #expect(b.layered.first?.id == f) // behind everything
        #expect(b.contents(ofFrame: f) == [ids[0], ids[1]])
        let inner = b.addFrame("Inner", rect: BoardRect(x: 30, y: 10, w: 150, h: 140))
        #expect(b.contents(ofFrame: f).contains(inner))
        #expect(b.movingSet([f]) == [f, inner, ids[0], ids[1]])
        b.moveGroup([f], dx: 100, dy: 50)
        #expect(b.items.first { $0.id == ids[0] }!.x == 140 && b.items.first { $0.id == ids[2] }!.x == 360)
        b.bringToFront(f)
        #expect(b.layered.first { $0.kind == .frame }.map { $0.z } ?? 0 < b.items.first { $0.id == ids[0] }!.z)
    }

    @Test func guidesSnapToEdgesAndCenters() {
        var (b, ids) = row()
        let d = b.addNote("d", at: (x: 40, y: 300)); b.resize(d, w: 100, h: 100)
        // Dragging d right by 163 puts its left edge 3 pt from the second note's left edge (200).
        let g = b.guides(moving: [d], dx: 163, dy: 0, threshold: 6)
        #expect(g.dx == 160 && g.vertical.contains(200))
        #expect(g.dy == 0 && g.horizontal.isEmpty)
        // Center to center: d's middle (90) toward the third note's middle (410): 318 + 2.
        #expect(b.guides(moving: [d], dx: 318, dy: 0).dx == 320)
        // Far from anything with snap on: grid fallback on the group's corner.
        b.snap = true
        let far = b.guides(moving: [d], dx: 7, dy: 133)
        #expect(far.dx == 0 && far.dy == 140 && far.vertical.isEmpty)
        b.snap = false
        #expect(b.guides(moving: [d], dx: 7, dy: 133, threshold: 1).dy == 133)
        // Clamped at the top-left edge.
        #expect(b.guides(moving: [ids[0]], dx: -500, dy: -500).dx == -40)
        b.moveGroup([ids[0], ids[1]], dx: -1000, dy: 10)
        #expect(b.items.first { $0.id == ids[0] }!.x == 0 && b.items.first { $0.id == ids[1] }!.x == 160)
    }

    @Test func marqueeAndGroupOrder() {
        var (b, ids) = row()
        let f = b.addFrame("F", rect: BoardRect(x: 500, y: 0, w: 200, h: 200))
        let r = BoardRect.spanning((x: 210, y: 90), (x: 10, y: 20))
        #expect(r == BoardRect(x: 10, y: 20, w: 200, h: 70))
        #expect(b.items(in: r) == [ids[0], ids[1]])
        #expect(!b.items(in: BoardRect(x: 480, y: 0, w: 100, h: 100)).contains(f))
        #expect(b.items(in: BoardRect(x: 480, y: 0, w: 300, h: 300)).contains(f))
        b.bringToFront([ids[1], ids[0]])
        #expect(b.layered.suffix(2).map(\.id) == [ids[0], ids[1]]) // relative order kept
        b.sendToBack([ids[2]])
        #expect(b.layered.first?.id == ids[2])
        #expect(b.bounds(of: [ids[0], ids[2]]) == BoardRect(x: 40, y: 40, w: 420, h: 100))
    }

    @Test func tidyLeavesSectionsAlone() {
        var (b, ids) = row()
        let f = b.frame(around: [ids[0]], label: "Keep")!
        let before = b.items.filter { [f, ids[0]].contains($0.id) }
        b.tidy()
        #expect(b.items.filter { [f, ids[0]].contains($0.id) } == before)
        let loose = b.items.filter { $0.id == ids[1] || $0.id == ids[2] }
        #expect(loose.allSatisfy { $0.y >= 160 + b.grid * 2 })
    }

    @Test func duplicateAndDecode() throws {
        var c = StudioCatalog()
        let id = c.createBoard(named: "Lobby")
        c.updateBoard(id) { $0.addNote("x"); $0.addFrame("Sec") }
        let d1 = c.duplicateBoard(id)!, d2 = c.duplicateBoard(id)!
        #expect(c.board(d1)?.name == "Lobby copy" && c.board(d2)?.name == "Lobby copy 2")
        #expect(c.boards.map(\.id) == [id, d2, d1])
        #expect(Set(c.board(d1)!.items.map(\.id)).isDisjoint(with: c.board(id)!.items.map(\.id)))
        #expect(c.board(d1)!.items.map(\.text) == c.board(id)!.items.map(\.text))
        #expect(c.duplicateBoard(UUID()) == nil)
        let back = StudioCatalog.decode(try c.encoded())!
        #expect(back.board(id)?.items.contains { $0.kind == .frame && $0.text == "Sec" } == true)
    }
}

extension BoardItem { var maxXY: (Double, Double) { (x + w, y + h) } }
