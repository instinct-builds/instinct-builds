import Foundation

// MARK: - 1.24: boards follow versions, nudging, and copy / paste of cards

/// One card showing an asset (or another version of it) on a board.
public struct BoardUse: Equatable, Identifiable, Sendable {
    public var id: UUID { item }
    public var board: UUID
    public var boardName: String
    public var item: UUID
    /// The version on the card.
    public var asset: UUID
    /// Its version label: "v2", "Final", "Original".
    public var label: String
    /// The newest version, when the card shows an older one.
    public var newer: UUID?
}

extension StudioCatalog {
    /// The newest version in the asset's stack, when it is newer than the asset. Nil for unstacked assets.
    public func newerVersion(of asset: UUID) -> StudioAsset? {
        guard let a = assets.first(where: { $0.id == asset }), a.stackID != nil,
              let top = stackTop(asset), top.id != asset,
              VersionStacks.rank(top).0 > VersionStacks.rank(a).0 else { return nil }
        return top
    }

    /// Every card, on every board, that shows this asset or another version in its stack. Boards in sidebar order, cards in reading order.
    public func boardsUsing(_ asset: UUID) -> [BoardUse] {
        let family = Set(versions(of: asset).map(\.id))
        guard !family.isEmpty else { return [] }
        var out: [BoardUse] = []
        for b in boards {
            for it in b.readingOrder where it.kind == .asset {
                guard let a = it.assetID, family.contains(a) else { continue }
                let label = assets.first { $0.id == a }.map { VersionStacks.rank($0).1 } ?? ""
                out.append(BoardUse(board: b.id, boardName: b.name, item: it.id, asset: a, label: label, newer: newerVersion(of: a)?.id))
            }
        }
        return out
    }

    /// Cards on the board showing an older version, with the version they can move to.
    public func outdatedCards(on board: UUID) -> [UUID: StudioAsset] {
        guard let b = self.board(board) else { return [:] }
        var out: [UUID: StudioAsset] = [:]
        for it in b.items where it.kind == .asset { if let a = it.assetID, let n = newerVersion(of: a) { out[it.id] = n } }
        return out
    }

    /// Swaps outdated cards (all, or those in `only`) to the newest version. Saves a board version first,
    /// keeps each card's size and place, keeps the crop when the new image has the same shape (else crops it
    /// from the middle), sets the status back to Open and leaves a note in the card's thread. Returns how many changed.
    @discardableResult
    public mutating func updateToNewest(board: UUID, only: Set<UUID>? = nil, author: String, saved: String) -> Int {
        let todo = outdatedCards(on: board).filter { only?.contains($0.key) ?? true }
        guard !todo.isEmpty else { return 0 }
        let byID = Dictionary(assets.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var n = 0
        _ = updateBoard(board) { b in
            b.saveVersion(named: "Before Update to Newest", saved: saved)
            for it in b.readingOrder {
                guard let newest = todo[it.id], let i = b.items.firstIndex(where: { $0.id == it.id }),
                      let oldID = b.items[i].assetID, let old = byID[oldID] else { continue }
                let oldAspect = Moodboard.aspect(resolution: old.resolution), newAspect = Moodboard.aspect(resolution: newest.resolution)
                var earlier = b.earlierAssets[it.id] ?? []
                earlier.removeAll { $0 == oldID || $0 == newest.id }
                earlier.append(oldID)
                b.earlierAssets[it.id] = earlier
                b.items[i].assetID = newest.id
                if abs(oldAspect - newAspect) > 0.01 * max(oldAspect, newAspect) {
                    let shape = b.items[i].w / max(1, b.items[i].h)
                    b.items[i].crop = BoardItem.validCrop(Moodboard.centeredCrop(aspect: shape, natural: max(0.05, newAspect)))
                }
                var text = "Updated from \(VersionStacks.rank(old).1) to \(VersionStacks.rank(newest).1)."
                let was = b.status(of: it.id)
                if was != .open { b.statuses[it.id] = nil; text += " It was \(was.label); back to Open for a fresh look." }
                b.addReply(to: it.id, author: author, text: text, posted: saved)
                n += 1
            }
        }
        return n
    }
}

/// Cards copied from a board: kept inside ASSSETS so they paste onto any board with their arrows.
public struct BoardClipboard: Codable, Equatable, Sendable {
    public var source: UUID
    public var items: [BoardItem]
    public var connectors: [BoardConnector]
    public init(source: UUID, items: [BoardItem], connectors: [BoardConnector]) { self.source = source; self.items = items; self.connectors = connectors }

    /// The same cards moved by `d` in both directions, so repeated pastes step down and right.
    public func shifted(by d: Double) -> BoardClipboard {
        var c = self
        for i in c.items.indices { c.items[i].x += d; c.items[i].y += d }
        return c
    }
}

extension Moodboard {
    /// Copies the cards (a section brings what's inside it) and the arrows between copied cards. Nil when nothing matches.
    public func copyCards(_ ids: Set<UUID>) -> BoardClipboard? {
        let set = movingSet(ids)
        guard !set.isEmpty else { return nil }
        return BoardClipboard(source: id, items: layered.filter { set.contains($0.id) },
                              connectors: connectors.filter { set.contains($0.from) && set.contains($0.to) })
    }

    /// Pastes with fresh ids above everything else. On the board they came from they shift two grid steps
    /// so the copy is visible; on another board they keep their place. Status, threads and client rounds
    /// stay with the originals. Returns the new card ids.
    @discardableResult
    public mutating func paste(_ clip: BoardClipboard) -> [UUID] {
        let d = clip.source == id ? grid * 2 : 0
        var map: [UUID: UUID] = [:], z = topZ, out: [UUID] = []
        for it in clip.items {
            var n = it
            n.id = UUID(); n.x = max(0, it.x + d); n.y = max(0, it.y + d); n.z = z
            z += 1; map[it.id] = n.id; out.append(n.id); items.append(n)
        }
        connectors += clip.connectors.compactMap { c in
            guard let f = map[c.from], let t = map[c.to] else { return nil }
            return BoardConnector(from: f, to: t, label: c.label)
        }
        return out
    }

    /// Moves the cards (and what their sections hold) by dx, dy, never past the top-left edge. Returns how many moved.
    @discardableResult
    public mutating func nudge(_ ids: Set<UUID>, dx: Double, dy: Double) -> Int {
        let set = movingSet(ids)
        let idx = items.indices.filter { set.contains(items[$0].id) }
        guard !idx.isEmpty else { return 0 }
        let ddx = max(dx, -idx.map { items[$0].x }.min()!), ddy = max(dy, -idx.map { items[$0].y }.min()!)
        guard ddx != 0 || ddy != 0 else { return 0 }
        for i in idx { items[i].x += ddx; items[i].y += ddy }
        return idx.count
    }
}
