import Foundation

// MARK: - Moodboards (1.16): free canvases of assets, notes and palette cards

public struct BoardRect: Equatable, Sendable {
    public var x: Double, y: Double, w: Double, h: Double
    public init(x: Double, y: Double, w: Double, h: Double) { self.x = x; self.y = y; self.w = w; self.h = h }
    public var maxX: Double { x + w }
    public var maxY: Double { y + h }
    public var midX: Double { x + w / 2 }
    public var midY: Double { y + h / 2 }
    public func contains(_ r: BoardRect) -> Bool { r.x >= x && r.y >= y && r.maxX <= maxX && r.maxY <= maxY }
    public func contains(x px: Double, y py: Double) -> Bool { px >= x && px <= maxX && py >= y && py <= maxY }
    public func intersects(_ r: BoardRect) -> Bool { r.x < maxX && r.maxX > x && r.y < maxY && r.maxY > y }
    /// Rect spanning two corner points, in any order (a marquee drag).
    public static func spanning(_ a: (x: Double, y: Double), _ b: (x: Double, y: Double)) -> BoardRect {
        BoardRect(x: min(a.x, b.x), y: min(a.y, b.y), w: abs(a.x - b.x), h: abs(a.y - b.y))
    }
}

/// Where a dragged group lands and the alignment lines to draw (1.18).
public struct BoardGuides: Equatable, Sendable {
    public var dx: Double, dy: Double
    /// x positions of vertical guide lines and y positions of horizontal ones, in board coordinates.
    public var vertical: [Double], horizontal: [Double]
    public init(dx: Double, dy: Double, vertical: [Double] = [], horizontal: [Double] = []) { self.dx = dx; self.dy = dy; self.vertical = vertical; self.horizontal = horizontal }
}

public struct BoardItem: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case asset, note, palette, frame }
    public var id: UUID
    public var kind: Kind
    /// The library asset shown (asset cards) or the asset the colors came from (palette cards).
    public var assetID: UUID?
    public var text: String
    public var colors: [String]
    public var x: Double, y: Double, w: Double, h: Double
    public var z: Int

    public init(id: UUID = UUID(), kind: Kind, assetID: UUID? = nil, text: String = "", colors: [String] = [],
                x: Double, y: Double, w: Double, h: Double, z: Int = 0) {
        self.id = id; self.kind = kind; self.assetID = assetID; self.text = text; self.colors = colors
        self.x = x; self.y = y; self.w = w; self.h = h; self.z = z
    }
    public var rect: BoardRect { BoardRect(x: x, y: y, w: w, h: h) }

    enum CodingKeys: String, CodingKey { case id, kind, assetID, text, colors, x, y, w, h, z }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = (try? c.decode(Kind.self, forKey: .kind)) ?? .note
        assetID = try? c.decodeIfPresent(UUID.self, forKey: .assetID)
        text = (try? c.decodeIfPresent(String.self, forKey: .text)) ?? ""
        colors = ((try? c.decodeIfPresent([String].self, forKey: .colors)) ?? []).compactMap(ColorSearch.normalize)
        x = (try? c.decode(Double.self, forKey: .x)) ?? 0
        y = (try? c.decode(Double.self, forKey: .y)) ?? 0
        w = max(Moodboard.minSize, (try? c.decode(Double.self, forKey: .w)) ?? 200)
        h = max(Moodboard.minSize, (try? c.decode(Double.self, forKey: .h)) ?? 150)
        z = (try? c.decode(Int.self, forKey: .z)) ?? 0
    }
}

public struct Moodboard: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var items: [BoardItem]
    public var grid: Double
    public var snap: Bool

    public static let minSize = 40.0
    public static let margin = 40.0
    public static let defaultAssetWidth = 280.0
    /// New cards flow left to right and wrap past this width.
    public static let flowWidth = 1400.0

    public init(id: UUID = UUID(), name: String, items: [BoardItem] = [], grid: Double = 20, snap: Bool = true) {
        self.id = id; self.name = name; self.items = items; self.grid = grid; self.snap = snap
    }

    enum CodingKeys: String, CodingKey { case id, name, items, grid, snap }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? "Board"
        items = (try? c.decodeIfPresent([BoardItem].self, forKey: .items)) ?? []
        grid = min(80, max(4, (try? c.decode(Double.self, forKey: .grid)) ?? 20))
        snap = (try? c.decode(Bool.self, forKey: .snap)) ?? true
    }

    /// Back to front.
    public var layered: [BoardItem] { items.enumerated().sorted { $0.element.z == $1.element.z ? $0.offset < $1.offset : $0.element.z < $1.element.z }.map(\.element) }

    public static func snapped(_ v: Double, grid: Double) -> Double { grid > 0 ? (v / grid).rounded() * grid : v }
    func s(_ v: Double) -> Double { snap ? Self.snapped(v, grid: grid) : v }

    /// Width / height from a resolution like "2400 × 1600"; 4:3 when unknown.
    public static func aspect(resolution: String) -> Double {
        let nums = resolution.split(whereSeparator: { !$0.isNumber }).compactMap { Double($0) }.filter { $0 > 0 }
        guard nums.count >= 2 else { return 4.0 / 3.0 }
        return min(4, max(0.25, nums[0] / nums[1]))
    }

    /// Everything on the board, or nil when empty.
    public var bounds: BoardRect? {
        guard let f = items.first else { return nil }
        var minX = f.x, minY = f.y, maxX = f.x + f.w, maxY = f.y + f.h
        for i in items.dropFirst() { minX = min(minX, i.x); minY = min(minY, i.y); maxX = max(maxX, i.x + i.w); maxY = max(maxY, i.y + i.h) }
        return BoardRect(x: minX, y: minY, w: maxX - minX, h: maxY - minY)
    }

    var topZ: Int { (items.map(\.z).max() ?? -1) + 1 }

    /// Where the next card goes: to the right of the last row, wrapping below when past the flow width.
    public func nextOrigin(width: Double) -> (x: Double, y: Double) {
        guard let b = bounds else { return (Self.margin, Self.margin) }
        let lastRowTop = items.map(\.y).max() ?? b.y
        let row = items.filter { $0.y + $0.h > lastRowTop }
        let right = (row.map { $0.x + $0.w }.max() ?? b.maxX) + grid
        if right + width <= Self.flowWidth { return (s(right), s(row.map(\.y).min() ?? lastRowTop)) }
        return (s(b.x), s(b.maxY + grid))
    }

    @discardableResult
    public mutating func add(_ item: BoardItem, at point: (x: Double, y: Double)? = nil) -> UUID {
        var it = item
        let o = point ?? nextOrigin(width: it.w)
        it.x = max(0, s(o.x)); it.y = max(0, s(o.y)); it.z = topZ
        items.append(it)
        return it.id
    }

    @discardableResult
    public mutating func addAsset(_ asset: UUID, aspect: Double, width: Double = Moodboard.defaultAssetWidth, at point: (x: Double, y: Double)? = nil) -> UUID {
        let w = max(Self.minSize, width)
        return add(BoardItem(kind: .asset, assetID: asset, x: 0, y: 0, w: w, h: max(Self.minSize, (w / max(0.25, aspect)).rounded())), at: point)
    }

    /// Several assets in a row that wraps, starting at `point` (or after what is already there). Skips ones already on the board.
    @discardableResult
    public mutating func addAssets(_ assets: [(id: UUID, aspect: Double)], at point: (x: Double, y: Double)? = nil) -> [UUID] {
        let have = Set(items.compactMap { $0.kind == .asset ? $0.assetID : nil })
        var added: [UUID] = [], seen = Set<UUID>()
        var col = 0, x = point?.x ?? 0, y = point?.y ?? 0, rowH = 0.0
        for a in assets where !have.contains(a.id) && seen.insert(a.id).inserted {
            guard let p = point else { added.append(addAsset(a.id, aspect: a.aspect)); continue }
            // Dropped at a point: rows of four from there.
            if col == 4 { col = 0; x = p.x; y += rowH + grid; rowH = 0 }
            added.append(addAsset(a.id, aspect: a.aspect, at: (x, y)))
            if let it = items.last { x = it.x + it.w + grid; rowH = max(rowH, it.h) }
            col += 1
        }
        return added
    }

    @discardableResult
    public mutating func addNote(_ text: String, at point: (x: Double, y: Double)? = nil) -> UUID {
        add(BoardItem(kind: .note, text: text, x: 0, y: 0, w: 220, h: 140), at: point)
    }

    @discardableResult
    public mutating func addPalette(_ colors: [String], from asset: UUID? = nil, at point: (x: Double, y: Double)? = nil) -> UUID? {
        let c = Array(colors.compactMap(ColorSearch.normalize).prefix(6))
        guard !c.isEmpty else { return nil }
        return add(BoardItem(kind: .palette, assetID: asset, colors: c, x: 0, y: 0, w: Double(max(3, c.count)) * 60, h: 120), at: point)
    }

    public mutating func move(_ id: UUID, x: Double, y: Double) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].x = max(0, s(x)); items[i].y = max(0, s(y))
    }

    /// Asset cards keep their shape; notes and palettes resize freely.
    public mutating func resize(_ id: UUID, w: Double, h: Double) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        let nw = max(Self.minSize, s(w))
        if items[i].kind == .asset {
            let aspect = items[i].w / max(1, items[i].h)
            items[i].w = nw; items[i].h = max(Self.minSize, (nw / aspect).rounded())
        } else {
            items[i].w = nw; items[i].h = max(Self.minSize, s(h))
        }
    }

    /// Frames stay behind the cards.
    public mutating func bringToFront(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }), items[i].kind != .frame else { return }
        items[i].z = topZ
    }
    public mutating func sendToBack(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].z = (items.map(\.z).min() ?? 0) - 1
    }
    public mutating func setText(_ id: UUID, _ text: String) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].text = String(text.prefix(2000))
    }
    @discardableResult
    public mutating func remove(_ ids: Set<UUID>) -> Int {
        let before = items.count
        items.removeAll { ids.contains($0.id) }
        return before - items.count
    }
    /// Asset cards for assets that left the library go too; palette cards keep their colors.
    public mutating func forgetAssets(_ ids: Set<UUID>) {
        items.removeAll { $0.kind == .asset && ($0.assetID.map(ids.contains) ?? false) }
        for i in items.indices where items[i].kind == .palette && (items[i].assetID.map(ids.contains) ?? false) { items[i].assetID = nil }
    }

    /// Present order (1.17): rows top to bottom, left to right within a row. A card joins the current row
    /// when its top edge is above the middle of the row's first card.
    public var readingOrder: [BoardItem] {
        let byY = items.sorted { $0.y == $1.y ? $0.x < $1.x : $0.y < $1.y }
        var rows: [[BoardItem]] = []
        for it in byY {
            if let first = rows.last?.first, it.y < first.y + first.h / 2 { rows[rows.count - 1].append(it) }
            else { rows.append([it]) }
        }
        return rows.flatMap { $0.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x } }
    }

    /// Scale and offset that center `rect` inside a `width` x `height` view with `margin` on every side.
    /// Apply as: scale the board around its top-left corner, then translate by (x, y).
    public static func fit(_ rect: BoardRect, width: Double, height: Double, margin: Double = 40, maxScale: Double = 4) -> (scale: Double, x: Double, y: Double) {
        guard rect.w > 0, rect.h > 0, width > 0, height > 0 else { return (1, 0, 0) }
        let s = max(0.01, min((width - 2 * margin) / rect.w, (height - 2 * margin) / rect.h, maxScale))
        return (s, (width - rect.w * s) / 2 - rect.x * s, (height - rect.h * s) / 2 - rect.y * s)
    }

    // MARK: Sections and groups (1.18)

    /// Default padding between a frame's edge and its cards; the top leaves room for the label.
    public static let framePadding = 20.0, frameLabelSpace = 44.0

    /// Cards whose centers sit inside the frame, plus frames entirely inside it.
    public func contents(ofFrame id: UUID) -> Set<UUID> {
        guard let f = items.first(where: { $0.id == id && $0.kind == .frame }) else { return [] }
        let r = f.rect
        return Set(items.filter { it in
            it.id != id && (it.kind == .frame ? r.contains(it.rect) && it.rect != r : r.contains(x: it.rect.midX, y: it.rect.midY))
        }.map(\.id))
    }

    /// What actually moves when `ids` is dragged: frames bring their contents (and nested frames theirs).
    public func movingSet(_ ids: Set<UUID>) -> Set<UUID> {
        var out = ids.filter { id in items.contains { $0.id == id } }
        var queue = Array(out)
        while let id = queue.popLast() {
            for c in contents(ofFrame: id) where !out.contains(c) { out.insert(c); queue.append(c) }
        }
        return out
    }

    /// A marquee picks cards it touches; frames only when it covers them entirely.
    public func items(in r: BoardRect) -> Set<UUID> {
        Set(items.filter { $0.kind == .frame ? r.contains($0.rect) : r.intersects($0.rect) }.map(\.id))
    }

    public func bounds(of ids: Set<UUID>) -> BoardRect? {
        let sel = items.filter { ids.contains($0.id) }
        guard let f = sel.first else { return nil }
        var minX = f.x, minY = f.y, maxX = f.x + f.w, maxY = f.y + f.h
        for i in sel.dropFirst() { minX = min(minX, i.x); minY = min(minY, i.y); maxX = max(maxX, i.x + i.w); maxY = max(maxY, i.y + i.h) }
        return BoardRect(x: minX, y: minY, w: maxX - minX, h: maxY - minY)
    }

    /// Final offset for dragging `ids` by (dx, dy). Each axis snaps to the nearest edge or center of another card
    /// within `threshold`; otherwise it falls back to the grid (when snap is on) using the group's top-left corner.
    public func guides(moving ids: Set<UUID>, dx: Double, dy: Double, threshold: Double = 6) -> BoardGuides {
        let moving = movingSet(ids)
        guard let b = bounds(of: moving) else { return BoardGuides(dx: dx, dy: dy) }
        let others = items.filter { !moving.contains($0.id) }.map(\.rect)
        let mx = [b.x + dx, b.midX + dx, b.maxX + dx], my = [b.y + dy, b.midY + dy, b.maxY + dy]
        func best(_ mine: [Double], _ theirs: [Double]) -> (adjust: Double, line: Double)? {
            var pick: (Double, Double)?
            for m in mine { for t in theirs where abs(t - m) <= threshold { if pick == nil || abs(t - m) < abs(pick!.0) { pick = (t - m, t) } } }
            return pick.map { (adjust: $0.0, line: $0.1) }
        }
        var g = BoardGuides(dx: dx, dy: dy)
        if let v = best(mx, others.flatMap { [$0.x, $0.midX, $0.maxX] }) {
            g.dx = dx + v.adjust
            let lines = others.flatMap { [$0.x, $0.midX, $0.maxX] }.filter { t in [b.x, b.midX, b.maxX].contains { abs($0 + g.dx - t) < 0.001 } }
            g.vertical = Array(Set(lines)).sorted()
        } else if snap { g.dx = Self.snapped(b.x + dx, grid: grid) - b.x }
        if let h = best(my, others.flatMap { [$0.y, $0.midY, $0.maxY] }) {
            g.dy = dy + h.adjust
            let lines = others.flatMap { [$0.y, $0.midY, $0.maxY] }.filter { t in [b.y, b.midY, b.maxY].contains { abs($0 + g.dy - t) < 0.001 } }
            g.horizontal = Array(Set(lines)).sorted()
        } else if snap { g.dy = Self.snapped(b.y + dy, grid: grid) - b.y }
        // Nothing crosses the board's top or left edge.
        g.dx = max(g.dx, -b.x); g.dy = max(g.dy, -b.y)
        return g
    }

    /// Moves `ids` (and whatever frames among them contain) by an exact offset; use `guides` first to snap.
    public mutating func moveGroup(_ ids: Set<UUID>, dx: Double, dy: Double) {
        let moving = movingSet(ids)
        guard let b = bounds(of: moving) else { return }
        let ddx = max(dx, -b.x), ddy = max(dy, -b.y)
        for i in items.indices where moving.contains(items[i].id) { items[i].x += ddx; items[i].y += ddy }
    }

    /// Keeps the group's own stacking order.
    public mutating func bringToFront(_ ids: Set<UUID>) {
        var z = topZ
        for it in layered where ids.contains(it.id) && it.kind != .frame {
            if let i = items.firstIndex(where: { $0.id == it.id }) { items[i].z = z; z += 1 }
        }
    }
    public mutating func sendToBack(_ ids: Set<UUID>) {
        let sel = layered.filter { ids.contains($0.id) }
        var z = (items.map(\.z).min() ?? 0) - sel.count
        for it in sel { if let i = items.firstIndex(where: { $0.id == it.id }) { items[i].z = z; z += 1 } }
    }

    /// A labeled section. Frames sit behind every card.
    @discardableResult
    public mutating func addFrame(_ label: String, rect: BoardRect? = nil) -> UUID {
        let r = rect ?? {
            let o = nextOrigin(width: 480)
            return BoardRect(x: o.x, y: o.y, w: 480, h: 320)
        }()
        let z = (items.map(\.z).min() ?? 0) - 1
        let it = BoardItem(kind: .frame, text: label, x: max(0, s(r.x)), y: max(0, s(r.y)), w: max(Self.minSize * 3, s(r.w)), h: max(Self.minSize * 2, s(r.h)), z: z)
        items.append(it)
        return it.id
    }

    /// Frames the given cards with padding and room for the label above them.
    @discardableResult
    public mutating func frame(around ids: Set<UUID>, label: String) -> UUID? {
        guard let b = bounds(of: ids) else { return nil }
        let p = Self.framePadding
        // Unsnapped so the padding is exact on every side.
        let keep = snap; snap = false
        defer { snap = keep }
        let x = max(0, b.x - p), y = max(0, b.y - Self.frameLabelSpace)
        return addFrame(label, rect: BoardRect(x: x, y: y, w: b.maxX + p - x, h: b.maxY + p - y))
    }

    /// Lays out the loose cards in rows below any frames, back to front, keeping sizes. Frames and what they hold stay put.
    public mutating func tidy() {
        let framed = movingSet(Set(items.filter { $0.kind == .frame }.map(\.id)))
        let top = items.filter { framed.contains($0.id) }.map { $0.y + $0.h }.max().map { $0 + grid * 2 } ?? Self.margin
        var x = Self.margin, y = top, rowH = 0.0
        for it in layered where !framed.contains(it.id) {
            guard let i = items.firstIndex(where: { $0.id == it.id }) else { continue }
            if x > Self.margin && x + it.w > Self.flowWidth { x = Self.margin; y += rowH + grid; rowH = 0 }
            items[i].x = s(x); items[i].y = s(y)
            x += it.w + grid; rowH = max(rowH, it.h)
        }
    }

    /// The area an export covers: everything plus a margin.
    public var exportRect: BoardRect {
        guard let b = bounds else { return BoardRect(x: 0, y: 0, w: 800, h: 600) }
        return BoardRect(x: b.x - Self.margin, y: b.y - Self.margin, w: b.w + 2 * Self.margin, h: b.h + 2 * Self.margin)
    }
}

extension StudioCatalog {
    public func board(_ id: UUID) -> Moodboard? { boards.first { $0.id == id } }

    @discardableResult
    public mutating func createBoard(named base: String = "New Board") -> UUID {
        let root = base.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "New Board" : base.trimmingCharacters(in: .whitespacesAndNewlines)
        let taken = Set(boards.map(\.name))
        var name = root, n = 2
        while taken.contains(name) { name = "\(root) \(n)"; n += 1 }
        let b = Moodboard(name: name)
        boards.append(b)
        return b.id
    }

    @discardableResult
    public mutating func renameBoard(_ id: UUID, to name: String) -> Bool {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let i = boards.firstIndex(where: { $0.id == id }), !boards.contains(where: { $0.id != id && $0.name == t }) else { return false }
        boards[i].name = t
        return true
    }

    /// A copy with fresh ids, named "<name> copy" (or "copy 2"...).
    @discardableResult
    public mutating func duplicateBoard(_ id: UUID) -> UUID? {
        guard let src = board(id) else { return nil }
        let taken = Set(boards.map(\.name))
        var name = src.name + " copy", n = 2
        while taken.contains(name) { name = "\(src.name) copy \(n)"; n += 1 }
        var b = src
        b.id = UUID(); b.name = name
        b.items = src.items.map { var it = $0; it.id = UUID(); return it }
        if let i = boards.firstIndex(where: { $0.id == id }) { boards.insert(b, at: i + 1) } else { boards.append(b) }
        return b.id
    }

    @discardableResult
    public mutating func deleteBoard(_ id: UUID) -> Bool {
        let before = boards.count
        boards.removeAll { $0.id == id }
        return boards.count != before
    }

    @discardableResult
    public mutating func updateBoard(_ id: UUID, _ change: (inout Moodboard) -> Void) -> Bool {
        guard let i = boards.firstIndex(where: { $0.id == id }) else { return false }
        change(&boards[i])
        return true
    }

    /// Adds library assets to a board with their own proportions.
    @discardableResult
    public mutating func addToBoard(_ id: UUID, assets ids: [UUID], at point: (x: Double, y: Double)? = nil) -> Int {
        let byID = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
        let list = ids.compactMap { byID[$0] }.map { (id: $0.id, aspect: Moodboard.aspect(resolution: $0.resolution)) }
        var n = 0
        updateBoard(id) { n = $0.addAssets(list, at: point).count }
        return n
    }
}
