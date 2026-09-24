import Foundation

// MARK: - Board templates (1.22)

/// A board layout to start from: sections, headings, notes, palettes and arrows, with image slots left empty.
/// A slot is an asset card with no asset.
public struct BoardTemplate: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var summary: String
    public var builtIn: Bool
    public var items: [BoardItem]
    public var connectors: [BoardConnector]
    public init(id: UUID = UUID(), name: String, summary: String = "", builtIn: Bool = false, items: [BoardItem], connectors: [BoardConnector] = []) {
        self.id = id; self.name = name; self.summary = summary; self.builtIn = builtIn; self.items = items; self.connectors = connectors
    }

    public var slotCount: Int { items.filter { $0.kind == .asset }.count }

    enum CodingKeys: String, CodingKey { case id, name, summary, builtIn, items, connectors }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? "Template"
        summary = (try? c.decodeIfPresent(String.self, forKey: .summary)) ?? ""
        builtIn = (try? c.decodeIfPresent(Bool.self, forKey: .builtIn)) ?? false
        items = (try? c.decodeIfPresent([BoardItem].self, forKey: .items)) ?? []
        let ids = Set(items.map(\.id))
        connectors = ((try? c.decodeIfPresent([BoardConnector].self, forKey: .connectors)) ?? []).filter { ids.contains($0.from) && ids.contains($0.to) && $0.from != $0.to }
    }
}

extension BoardItem {
    /// An asset card waiting for an image.
    public var isSlot: Bool { kind == .asset && assetID == nil }
}

extension Moodboard {
    /// This board as a template: every image becomes an empty slot of the same size; everything else is kept.
    public func makeTemplate(named name: String, summary: String = "") -> BoardTemplate {
        let items = self.items.map { it -> BoardItem in
            var t = it
            if t.kind == .asset { t.assetID = nil; t.crop = nil }
            if t.kind == .palette { t.assetID = nil }
            return t
        }
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return BoardTemplate(name: n.isEmpty ? self.name : String(n.prefix(80)), summary: String(summary.prefix(200)), items: items, connectors: connectors)
    }

    /// Empty slots in reading order.
    public var emptySlots: [UUID] { readingOrder.filter(\.isSlot).map(\.id) }

    /// Puts an image in a slot. The slot keeps its size; the image is cropped to fill it from the middle.
    @discardableResult
    public mutating func fillSlot(_ slot: UUID, with asset: UUID, aspect: Double) -> Bool {
        guard let i = items.firstIndex(where: { $0.id == slot }), items[i].isSlot else { return false }
        items[i].assetID = asset
        let shape = items[i].w / max(1, items[i].h)
        items[i].crop = BoardItem.validCrop(Moodboard.centeredCrop(aspect: shape, natural: max(0.05, aspect)))
        return true
    }

    /// Fills empty slots in reading order (or starting with the slot under `point`), then lays out whatever is left
    /// the usual way. Assets already on the board are skipped. Returns the card ids that now show the assets.
    @discardableResult
    public mutating func place(_ assets: [(id: UUID, aspect: Double)], at point: (x: Double, y: Double)? = nil) -> [UUID] {
        let have = Set(items.compactMap { $0.kind == .asset ? $0.assetID : nil })
        var seen = Set<UUID>()
        var queue = assets.filter { !have.contains($0.id) && seen.insert($0.id).inserted }
        var slots = emptySlots
        if let p = point {
            // A drop fills only the slot it lands on; the rest go where they were dropped.
            guard let hit = layered.reversed().first(where: { $0.isSlot && $0.rect.contains(x: p.x, y: p.y) })?.id, !queue.isEmpty else {
                return addAssets(queue, at: point)
            }
            slots = [hit]
        }
        var placed: [UUID] = []
        for s in slots {
            guard !queue.isEmpty else { break }
            let a = queue.removeFirst()
            if fillSlot(s, with: a.id, aspect: a.aspect) { placed.append(s) }
        }
        return placed + (queue.isEmpty ? [] : addAssets(queue, at: point.map { (x: $0.x + 40, y: $0.y + 40) }))
    }

    /// Takes the image out of a card, leaving an empty slot where it was.
    public mutating func clearSlot(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }), items[i].kind == .asset else { return }
        items[i].assetID = nil; items[i].crop = nil
        statuses[id] = nil
    }
}

extension StudioCatalog {
    public var allTemplates: [BoardTemplate] { BoardTemplate.builtIns + templates }

    public func template(_ id: UUID) -> BoardTemplate? { allTemplates.first { $0.id == id } }

    /// Saves a board as a template; the name gets " 2", " 3"... if taken.
    @discardableResult
    public mutating func saveTemplate(from board: UUID, named name: String, summary: String = "") -> UUID? {
        guard let b = self.board(board) else { return nil }
        var t = b.makeTemplate(named: name, summary: summary)
        let taken = Set(allTemplates.map(\.name))
        let base = t.name; var n = 2
        while taken.contains(t.name) { t.name = "\(base) \(n)"; n += 1 }
        templates.append(t)
        return t.id
    }

    public mutating func deleteTemplate(_ id: UUID) { templates.removeAll { $0.id == id } }

    public mutating func renameTemplate(_ id: UUID, to name: String) {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let i = templates.firstIndex(where: { $0.id == id }) else { return }
        templates[i].name = String(t.prefix(80))
    }

    /// A new board laid out like the template, with fresh ids, right after the selected one.
    @discardableResult
    public mutating func createBoard(from templateID: UUID, named name: String? = nil) -> UUID? {
        guard let t = template(templateID) else { return nil }
        let id = createBoard(named: name ?? t.name)
        var map: [UUID: UUID] = [:]
        let items = t.items.map { it -> BoardItem in var n = it; n.id = UUID(); map[it.id] = n.id; return n }
        let arrows = t.connectors.compactMap { c -> BoardConnector? in
            guard let f = map[c.from], let to = map[c.to] else { return nil }
            return BoardConnector(from: f, to: to, label: c.label)
        }
        _ = updateBoard(id) { b in b.items = items; b.connectors = arrows }
        return id
    }

    /// Like `addToBoard`, but fills empty template slots first.
    @discardableResult
    public mutating func placeOnBoard(_ id: UUID, assets ids: [UUID], at point: (x: Double, y: Double)? = nil) -> Int {
        let byID = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
        let list = ids.compactMap { byID[$0] }.map { (id: $0.id, aspect: Moodboard.aspect(resolution: $0.resolution)) }
        var n = 0
        updateBoard(id) { n = $0.place(list, at: point).count }
        return n
    }
}

// MARK: Built-in templates: original layouts that ship with ASSSETS.

extension BoardTemplate {
    private static func tid(_ n: Int) -> UUID { UUID(uuidString: String(format: "A5555E75-0122-4000-8000-%012d", n))! }

    private static func slot(_ n: Int, _ x: Double, _ y: Double, _ w: Double, _ h: Double, z: Int) -> BoardItem {
        BoardItem(id: tid(n), kind: .asset, x: x, y: y, w: w, h: h, z: z)
    }
    private static func text(_ n: Int, _ kind: BoardItem.Kind, _ s: String, _ x: Double, _ y: Double, _ w: Double, _ h: Double, z: Int) -> BoardItem {
        BoardItem(id: tid(n), kind: kind, text: s, x: x, y: y, w: w, h: h, z: z)
    }

    public static let moodboardID = tid(1000), brandID = tid(2000), launchID = tid(3000)

    public static let builtIns: [BoardTemplate] = [moodboard, brand, launch]

    static let moodboard: BoardTemplate = {
        var items = [text(1001, .heading, "Moodboard", 40, 40, 520, 64, z: 1)]
        var n = 1010
        for r in 0..<3 { for c in 0..<3 {
            items.append(slot(n, 40 + Double(c) * 260, 140 + Double(r) * 200, 240, 180, z: 2 + n - 1010)); n += 1
        } }
        items.append(text(1030, .note, "Three words for the feeling:\n\nWhat to avoid:", 840, 140, 240, 180, z: 20))
        items.append(BoardItem(id: tid(1031), kind: .palette, colors: ["#E9DFCF", "#C7A27C", "#8A6A52", "#3E3431", "#1F1C1B"], x: 840, y: 340, w: 240, h: 120, z: 21))
        return BoardTemplate(id: moodboardID, name: "Moodboard 3x3", summary: "Nine image slots, a note for the feeling and a starter palette.", builtIn: true, items: items)
    }()

    static let brand: BoardTemplate = {
        var items = [text(2001, .heading, "Brand directions", 40, 40, 640, 64, z: 1)]
        for (k, x) in [(0, 40.0), (1, 560.0)] {
            let b = 2010 + k * 20
            items.append(text(b, .frame, k == 0 ? "DIRECTION A" : "DIRECTION B", x, 130, 480, 520, z: 0))
            items.append(slot(b + 1, x + 20, 170, 440, 260, z: 2))
            items.append(slot(b + 2, x + 20, 450, 210, 140, z: 3))
            items.append(slot(b + 3, x + 250, 450, 210, 140, z: 4))
            items.append(text(b + 4, .note, k == 0 ? "Direction A in one line:" : "Direction B in one line:", x + 20, 600, 440, 40, z: 5))
        }
        items.append(text(2090, .note, "Pick one, or mix them and say what to keep from each.", 40, 680, 1000, 60, z: 6))
        return BoardTemplate(id: brandID, name: "Brand Direction A/B", summary: "Two side-by-side directions, each with a hero and two details.", builtIn: true, items: items)
    }()

    static let launch: BoardTemplate = {
        let items = [
            text(3001, .heading, "Product launch", 40, 40, 600, 64, z: 1),
            text(3010, .frame, "HERO", 40, 130, 600, 380, z: 0),
            slot(3011, 60, 170, 560, 320, z: 2),
            text(3020, .frame, "CHANNELS", 700, 130, 480, 620, z: 0),
            slot(3021, 720, 170, 200, 200, z: 3),
            slot(3022, 960, 170, 150, 266, z: 4),
            slot(3023, 720, 470, 440, 146, z: 5),
            text(3030, .note, "Launch date:\nMessage:\nMust-haves:", 40, 540, 600, 150, z: 6),
        ]
        let arrows = [
            BoardConnector(id: tid(3101), from: tid(3011), to: tid(3021), label: "social"),
            BoardConnector(id: tid(3102), from: tid(3011), to: tid(3023), label: "banner"),
        ]
        return BoardTemplate(id: launchID, name: "Product Launch", summary: "A hero shot feeding square, story and banner crops.", builtIn: true, items: items, connectors: arrows)
    }()
}
