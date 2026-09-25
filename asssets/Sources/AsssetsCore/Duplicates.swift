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

/// What merging a duplicate set will do to the keeper (1.28), so the review sheet can say it before anything changes.
public struct MergePreview: Equatable, Sendable {
    public var keeper: UUID
    /// Copies that leave the library.
    public var removing: Int = 0
    public var tagsAdded: [String] = []
    public var becomesFavorite = false
    /// Collection the keeper moves to when it was only sitting in Imported or Inbox.
    public var collection: String? = nil
    /// Star rating after the merge (the highest in the set), and whether it goes up.
    public var rating = 0
    public var ratingRaised = false
    /// Color label after the merge, and whether the keeper gains it from a copy.
    public var label: ColorLabel? = nil
    public var labelAdopted = false
    /// Rights after the merge and which asset they come from.
    public var rights: UsageRights? = nil
    public var rightsFrom: UUID? = nil
    public var rightsAdopted = false
    /// Assets in the set whose rights disagree (two or more different entries). Empty when there is no conflict.
    public var rightsConflict: [UUID] = []
    public var licenseFilesAdded = 0
    public var notesAdded = 0
    /// Board cards (asset and palette cards) that point at a removed copy and will point at the keeper instead.
    public var boardCardsMoved = 0
    /// The keeper joins a copy's version stack (it had none of its own).
    public var joinsStack = false

    public var hasRightsConflict: Bool { rightsConflict.count > 1 }
    /// True when the merge only removes copies and changes nothing on the keeper.
    public var keeperUnchanged: Bool {
        tagsAdded.isEmpty && !becomesFavorite && collection == nil && !ratingRaised && !labelAdopted && !rightsAdopted
            && licenseFilesAdded == 0 && notesAdded == 0 && boardCardsMoved == 0 && !joinsStack
    }
}

extension UsageRights {
    /// Same license terms, ignoring the renewal stamp: what counts as agreeing rights for duplicates.
    public func sameTerms(_ o: UsageRights) -> Bool {
        license == o.license && source.trimmingCharacters(in: .whitespaces) == o.source.trimmingCharacters(in: .whitespaces)
            && credit.trimmingCharacters(in: .whitespaces) == o.credit.trimmingCharacters(in: .whitespaces)
            && uses.trimmingCharacters(in: .whitespaces) == o.uses.trimmingCharacters(in: .whitespaces) && expires == o.expires
    }
}

extension StudioCatalog {
    /// Plans a lossless merge of `group` into `keep` (1.28). `rightsFrom` picks whose rights win when they disagree;
    /// otherwise the keeper's rights stay, or the first copy's when the keeper has none.
    public func mergePreview(keep: UUID, group: [UUID], rightsFrom: UUID? = nil) -> MergePreview? {
        guard let k = assets.first(where: { $0.id == keep }) else { return nil }
        let members = group.compactMap { id in assets.first { $0.id == id } }
        let drop = members.filter { $0.id != keep }
        var p = MergePreview(keeper: keep)
        p.removing = drop.count
        guard !drop.isEmpty else { return p }
        var tags = k.tags
        for a in drop { for t in a.tags where !tags.contains(t) { tags.append(t); p.tagsAdded.append(t) } }
        p.becomesFavorite = !k.favorite && drop.contains { $0.favorite }
        let inbox: Set<String> = [Self.importedCollection, Self.inboxCollection]
        if inbox.contains(k.collection), let c = drop.first(where: { !inbox.contains($0.collection) })?.collection { p.collection = c }
        p.rating = members.map(\.rating).max() ?? k.rating
        p.ratingRaised = p.rating > k.rating
        p.label = k.label ?? drop.first { $0.label != nil }?.label
        p.labelAdopted = k.label == nil && p.label != nil
        // Rights: distinct entries across the set decide whether there is a conflict.
        var distinct: [UsageRights] = []
        for a in members { if let r = a.rights, !distinct.contains(where: { $0.sameTerms(r) }) { distinct.append(r) } }
        if distinct.count > 1 { p.rightsConflict = members.filter { $0.rights != nil }.map(\.id) }
        let chosen = rightsFrom.flatMap { id in members.first { $0.id == id && $0.rights != nil } }
            ?? (k.rights != nil ? k : drop.first { $0.rights != nil })
        p.rights = chosen?.rights
        p.rightsFrom = chosen?.id
        p.rightsAdopted = chosen != nil && chosen?.id != keep && !(k.rights.map { $0.sameTerms(chosen!.rights!) } ?? false)
        var docs = Set(k.licenseDocs)
        for a in drop { for d in a.licenseDocs where docs.insert(d).inserted { p.licenseFilesAdded += 1 } }
        var notes = Set(k.clientNotes)
        for a in drop { for n in a.clientNotes where notes.insert(n).inserted { p.notesAdded += 1 } }
        let dropIDs = Set(drop.map(\.id))
        p.boardCardsMoved = boards.reduce(0) { n, b in n + b.items.filter { ($0.kind == .asset || $0.kind == .palette) && ($0.assetID.map(dropIDs.contains) ?? false) }.count }
        p.joinsStack = k.stackID == nil && drop.contains { $0.stackID != nil }
        return p
    }

    /// Keeps one asset and removes the others from the library (files on disk are untouched).
    /// Lossless since 1.28: the keeper gains the others' tags, favorite, highest rating, color label, license files,
    /// client notes and version stack, their collection if it was only sitting in Imported or Inbox, and their rights
    /// when it has none (or `rightsFrom` names whose rights to keep). Board cards showing a removed copy show the keeper.
    /// Removed copies are remembered, so watch folders and bundled upgrades do not bring them back.
    @discardableResult
    public mutating func mergeDuplicates(keep: UUID, remove others: Set<UUID>, rightsFrom: UUID? = nil) -> Int {
        let drop = others.subtracting([keep])
        guard let k = assets.firstIndex(where: { $0.id == keep }), !drop.isEmpty,
              let plan = mergePreview(keep: keep, group: [keep] + assets.map(\.id).filter(drop.contains), rightsFrom: rightsFrom) else { return 0 }
        let copies = assets.filter { drop.contains($0.id) }
        for a in copies {
            for t in a.tags where !assets[k].tags.contains(t) { assets[k].tags.append(t) }
            for t in a.autoTags where !assets[k].autoTags.contains(t) && !assets[k].rejectedTags.contains(t) { assets[k].autoTags.append(t) }
            for d in a.licenseDocs where !assets[k].licenseDocs.contains(d) { assets[k].licenseDocs.append(d) }
            for n in a.clientNotes where !assets[k].clientNotes.contains(n) { assets[k].clientNotes.append(n) }
        }
        if plan.becomesFavorite { assets[k].favorite = true }
        if let c = plan.collection { assets[k].collection = c }
        assets[k].rating = plan.rating
        assets[k].label = plan.label
        if plan.rightsFrom != nil { assets[k].rights = plan.rights }
        if plan.joinsStack, let s = copies.first(where: { $0.stackID != nil })?.stackID { assets[k].stackID = s; assets[k].unstacked = false }
        let stillWatched = assets[k].collection == Self.inboxCollection || (assets[k].importedPath.map(isWatched) ?? false)
        if !stillWatched { assets[k].tags.removeAll { $0 == "watched" } }
        // Point board cards at the keeper before removal, which would otherwise drop them.
        for b in boards.indices { for i in boards[b].items.indices where boards[b].items[i].assetID.map(drop.contains) ?? false {
            boards[b].items[i].assetID = keep
        }
            // Client picks and notes from review rounds follow the card.
            for r in boards[b].reviews.indices {
                var picks: [UUID] = []
                for id in boards[b].reviews[r].picks { let n = drop.contains(id) ? keep : id; if !picks.contains(n) { picks.append(n) } }
                boards[b].reviews[r].picks = picks
                for (id, text) in boards[b].reviews[r].notes where drop.contains(id) {
                    boards[b].reviews[r].notes[id] = nil
                    if let mine = boards[b].reviews[r].notes[keep], mine != text { boards[b].reviews[r].notes[keep] = mine + "\n" + text }
                    else { boards[b].reviews[r].notes[keep] = text }
                }
            }
        }
        return remove(drop)
    }
}
