import Foundation

// MARK: - Grid sort (1.12)

public enum AssetSort: String, Codable, CaseIterable, Identifiable, Sendable {
    case added, name, rating, label
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .added: "Date Added"
        case .name: "Name"
        case .rating: "Rating"
        case .label: "Label"
        }
    }
    public var symbol: String {
        switch self {
        case .added: "clock"
        case .name: "textformat"
        case .rating: "star"
        case .label: "circle.fill"
        }
    }

    /// Stable: ties keep the incoming order (newest first, as the catalog stores it).
    public func apply(_ list: [StudioAsset]) -> [StudioAsset] {
        let indexed = Array(list.enumerated())
        func stable(_ less: (StudioAsset, StudioAsset) -> Bool?) -> [StudioAsset] {
            indexed.sorted { l, r in less(l.element, r.element) ?? (l.offset < r.offset) }.map(\.element)
        }
        switch self {
        case .added: return list
        case .name:
            return stable { a, b in
                let c = a.title.localizedStandardCompare(b.title)
                return c == .orderedSame ? nil : c == .orderedAscending
            }
        case .rating: return stable { a, b in a.rating == b.rating ? nil : a.rating > b.rating }
        case .label:
            let order = Dictionary(uniqueKeysWithValues: ColorLabel.allCases.enumerated().map { ($0.element, $0.offset) })
            return stable { a, b in
                let x = a.label.flatMap { order[$0] } ?? Int.max, y = b.label.flatMap { order[$0] } ?? Int.max
                return x == y ? nil : x < y
            }
        }
    }
}

extension StudioCatalog {
    public static func sortKey(collection: String, smart: UUID?) -> String { smart.map { "smart:" + $0.uuidString } ?? collection }
    public func sort(for key: String) -> AssetSort { viewSorts[key] ?? .added }
    public mutating func setSort(_ sort: AssetSort, for key: String) {
        if sort == .added { viewSorts[key] = nil } else { viewSorts[key] = sort }
    }
}

// MARK: - Cull mode (1.12): one asset at a time, rate or reject, move on

public struct CullSession: Equatable, Sendable {
    public var ids: [UUID]
    public var index: Int
    /// Move to the next asset after a rating, label or reject.
    public var autoAdvance: Bool

    public init?(ids: [UUID], start: UUID? = nil, autoAdvance: Bool = true) {
        guard !ids.isEmpty else { return nil }
        self.ids = ids; self.autoAdvance = autoAdvance
        index = start.flatMap { ids.firstIndex(of: $0) } ?? 0
    }

    public var current: UUID { ids[index] }
    public var isAtEnd: Bool { index == ids.count - 1 }

    /// Clamped step; returns false at either end.
    @discardableResult
    public mutating func step(by delta: Int) -> Bool {
        let next = min(ids.count - 1, max(0, index + delta))
        defer { index = next }
        return next != index
    }

    /// Called after a rating, label or reject: moves on when auto-advance is on and there is somewhere to go.
    @discardableResult
    public mutating func didDecide() -> Bool { autoAdvance ? step(by: 1) : false }

    /// Decided means rated (1+ stars) or rejected.
    public static func isDecided(_ a: StudioAsset) -> Bool { a.rating > 0 || a.tags.contains(StudioCatalog.rejectTag) }

    public func progress(in c: StudioCatalog) -> (decided: Int, total: Int) {
        let set = Set(ids)
        return (c.assets.filter { set.contains($0.id) && Self.isDecided($0) }.count, ids.count)
    }

    /// The next undecided asset after the current one, wrapping around; nil when everything is decided.
    public func nextUndecided(in c: StudioCatalog) -> Int? {
        let byID = Dictionary(uniqueKeysWithValues: c.assets.map { ($0.id, $0) })
        for k in 1...ids.count {
            let i = (index + k) % ids.count
            if let a = byID[ids[i]], !Self.isDecided(a) { return i }
        }
        return nil
    }
}

extension StudioCatalog {
    /// Adds the reject tag (and clears pick and stars), or removes it when every target is already rejected.
    /// Returns true when the targets are now rejected.
    @discardableResult
    public mutating func toggleReject(_ ids: Set<UUID>) -> Bool {
        let idx = assets.indices.filter { ids.contains(assets[$0].id) }
        guard !idx.isEmpty else { return false }
        let clear = idx.allSatisfy { assets[$0].tags.contains(Self.rejectTag) }
        for i in idx {
            if clear { assets[i].tags.removeAll { $0 == Self.rejectTag } }
            else {
                assets[i].tags.removeAll { $0 == Self.pickTag }
                if !assets[i].tags.contains(Self.rejectTag) { assets[i].tags.append(Self.rejectTag) }
                assets[i].rating = 0
            }
        }
        return !clear
    }
}

// MARK: - Undo and redo (1.12)

/// Records what one edit changed: the affected assets before and after (with their positions),
/// plus the catalog-level lists when they changed. Undo restores only those pieces, so background
/// work that landed in between (suggested tags, file metadata, new watched files) is kept.
public struct UndoStep: Equatable, Sendable {
    public var label: String
    var before: [UUID: (Int, StudioAsset)]
    var after: [UUID: (Int, StudioAsset)]
    var lists: (before: Lists, after: Lists)?

    struct Lists: Equatable, Sendable {
        var userCollections: [String], dismissedKeys: [String], smartCollections: [StudioSmartCollection]
        init(_ c: StudioCatalog) { userCollections = c.userCollections; dismissedKeys = c.dismissedKeys; smartCollections = c.smartCollections }
        func apply(to c: inout StudioCatalog) { c.userCollections = userCollections; c.dismissedKeys = dismissedKeys; c.smartCollections = smartCollections }
    }

    public static func == (l: UndoStep, r: UndoStep) -> Bool {
        l.label == r.label && l.before.keys == r.before.keys && l.after.keys == r.after.keys
    }

    init?(label: String, before b: StudioCatalog, after a: StudioCatalog) {
        let bi = Dictionary(uniqueKeysWithValues: b.assets.enumerated().map { ($0.element.id, ($0.offset, $0.element)) })
        let ai = Dictionary(uniqueKeysWithValues: a.assets.enumerated().map { ($0.element.id, ($0.offset, $0.element)) })
        var before: [UUID: (Int, StudioAsset)] = [:], after: [UUID: (Int, StudioAsset)] = [:]
        for id in Set(bi.keys).union(ai.keys) where bi[id]?.1 != ai[id]?.1 {
            before[id] = bi[id]; after[id] = ai[id]
            if bi[id] == nil { before[id] = nil }
        }
        let lb = Lists(b), la = Lists(a)
        let changedIDs = Set(bi.keys).union(ai.keys).filter { bi[$0]?.1 != ai[$0]?.1 }
        guard !changedIDs.isEmpty || lb != la else { return nil }
        self.label = label
        self.before = before.filter { changedIDs.contains($0.key) }
        self.after = after.filter { changedIDs.contains($0.key) }
        self.changed = changedIDs
        lists = lb != la ? (lb, la) : nil
    }
    var changed: Set<UUID> = []

    /// Puts one side back: assets that side had are restored (keeping newer suggested tags, size and palette),
    /// assets it lacked are removed.
    func restore(_ side: [UUID: (Int, StudioAsset)], lists: Lists?, into c: inout StudioCatalog) {
        for id in changed where side[id] == nil { c.assets.removeAll { $0.id == id } }
        for (id, (pos, saved)) in side.sorted(by: { $0.value.0 < $1.value.0 }) {
            if let i = c.assets.firstIndex(where: { $0.id == id }) {
                var a = saved
                a.autoTags = c.assets[i].autoTags; a.resolution = c.assets[i].resolution; a.palette = c.assets[i].palette
                c.assets[i] = a
            } else {
                c.assets.insert(saved, at: min(pos, c.assets.count))
            }
        }
        lists?.apply(to: &c)
    }
}

public struct UndoHistory: Sendable {
    public static let limit = 50
    public private(set) var undoStack: [UndoStep] = []
    public private(set) var redoStack: [UndoStep] = []
    public init() {}

    public var undoLabel: String? { undoStack.last?.label }
    public var redoLabel: String? { redoStack.last?.label }

    /// Records an edit. Nothing is recorded when the edit changed nothing. A new edit clears redo.
    @discardableResult
    public mutating func record(_ label: String, before: StudioCatalog, after: StudioCatalog) -> Bool {
        guard let step = UndoStep(label: label, before: before, after: after) else { return false }
        undoStack.append(step)
        if undoStack.count > Self.limit { undoStack.removeFirst(undoStack.count - Self.limit) }
        redoStack.removeAll()
        return true
    }

    /// Returns the label of the undone edit.
    public mutating func undo(_ c: inout StudioCatalog) -> String? {
        guard let step = undoStack.popLast() else { return nil }
        step.restore(step.before, lists: step.lists?.before, into: &c)
        redoStack.append(step)
        return step.label
    }

    public mutating func redo(_ c: inout StudioCatalog) -> String? {
        guard let step = redoStack.popLast() else { return nil }
        step.restore(step.after, lists: step.lists?.after, into: &c)
        undoStack.append(step)
        return step.label
    }
}
