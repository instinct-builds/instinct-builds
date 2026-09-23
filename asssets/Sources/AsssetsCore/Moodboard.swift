import Foundation

// MARK: - Moodboards (1.16): free canvases of assets, notes and palette cards

public struct BoardRect: Equatable, Sendable {
    public var x: Double, y: Double, w: Double, h: Double
    public init(x: Double, y: Double, w: Double, h: Double) { self.x = x; self.y = y; self.w = w; self.h = h }
    public var maxX: Double { x + w }
    public var maxY: Double { y + h }
}

public struct BoardItem: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case asset, note, palette }
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

    public mutating func bringToFront(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
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

    /// Lays everything out in rows, back to front, keeping sizes.
    public mutating func tidy() {
        var x = Self.margin, y = Self.margin, rowH = 0.0
        for it in layered {
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
