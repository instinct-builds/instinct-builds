import Foundation

/// Finds files that are byte-for-byte identical and folds them into one asset.
/// Hashing happens in the app; this is the pure, tested logic around it.
public enum Duplicates {
    /// Only files that share a size can be identical, so only those need hashing.
    public static func needsHash(sizes: [UUID: Int64]) -> Set<UUID> {
        var bySize: [Int64: [UUID]] = [:]
        for (id, size) in sizes where size > 0 { bySize[size, default: []].append(id) }
        return Set(bySize.values.filter { $0.count > 1 }.flatMap { $0 })
    }

    /// Groups of two or more assets with the same content hash, ordered by the catalog's asset order.
    public static func groups(hashes: [UUID: String], order: [UUID]) -> [[UUID]] {
        var byHash: [String: [UUID]] = [:]
        for id in order { if let h = hashes[id] { byHash[h, default: []].append(id) } }
        let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        return byHash.values.filter { $0.count > 1 }.sorted { (rank[$0[0]] ?? 0) < (rank[$1[0]] ?? 0) }
    }

    /// Which copy to keep when the user doesn't pick: a favorite, then one filed in a real collection,
    /// then a bundled original, then the oldest (last in the catalog, since imports are inserted at the front).
    public static func suggestedKeeper(_ group: [StudioAsset]) -> UUID? {
        func score(_ a: StudioAsset) -> Int {
            var s = 0
            if a.favorite { s += 8 }
            if a.collection != StudioCatalog.importedCollection && a.collection != StudioCatalog.inboxCollection { s += 4 }
            if a.isStarter { s += 2 }
            return s
        }
        return group.enumerated().max { l, r in
            let (a, b) = (score(l.element), score(r.element))
            return a != b ? a < b : l.offset < r.offset
        }?.element.id
    }
}

extension StudioCatalog {
    /// Keeps one asset and removes the others from the library (files on disk are untouched).
    /// The keeper gains the others' tags and favorite, and their collection if it was only sitting in Imported or Inbox.
    /// Removed copies are remembered, so watch folders and bundled upgrades do not bring them back.
    @discardableResult
    public mutating func mergeDuplicates(keep: UUID, remove others: Set<UUID>) -> Int {
        let drop = others.subtracting([keep])
        guard let k = assets.firstIndex(where: { $0.id == keep }), !drop.isEmpty else { return 0 }
        let inbox: Set<String> = [Self.importedCollection, Self.inboxCollection]
        for a in assets where drop.contains(a.id) {
            for t in a.tags where !assets[k].tags.contains(t) { assets[k].tags.append(t) }
            if a.favorite { assets[k].favorite = true }
            if inbox.contains(assets[k].collection) && !inbox.contains(a.collection) { assets[k].collection = a.collection }
        }
        let stillWatched = assets[k].collection == Self.inboxCollection || (assets[k].importedPath.map(isWatched) ?? false)
        if !stillWatched { assets[k].tags.removeAll { $0 == "watched" } }
        return remove(drop)
    }
}
