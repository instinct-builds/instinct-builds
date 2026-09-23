import Foundation

// MARK: - Version stacks: v1, v2, final grouped under one card

public enum VersionStacks {
    public struct Parsed: Equatable, Sendable {
        public var base: String      // lowercased name without the version marker
        public var rank: Double      // order inside the stack; higher is newer
        public var label: String     // short chip label: "v2", "Final", "Draft", "Original"
    }

    /// Reads a version marker at the end of a title or file stem:
    /// v2, v02, ver 3, version 4, rev 5, r6, draft, final, final 2, final final, copy, copy 2.
    /// Plain trailing numbers ("Editorial Vector 01", "Night Grid 4K") are not versions.
    public static func parse(_ name: String) -> Parsed? {
        var words = name.lowercased().split(whereSeparator: { " _-.()[]".contains($0) }).map(String.init)
        guard words.count >= 2 else { return nil }
        func number(_ s: String) -> Int? { s.allSatisfy(\.isNumber) && !s.isEmpty && s.count <= 4 ? Int(s) : nil }
        var rank: Double?, label = ""
        // Trailing "final" forms.
        if words.last == "final" || (words.count >= 3 && words[words.count - 2] == "final" && number(words.last!) != nil) {
            var extra = 0.0
            if let n = number(words.last!) { extra = Double(n); words.removeLast() }
            words.removeLast()
            while words.last == "final" { words.removeLast(); extra += 1 }   // "final final"
            rank = 10_000 + extra; label = extra > 0 ? "Final \(Int(extra) + 1)" : "Final"
        } else if words.last == "draft" {
            words.removeLast(); rank = -1; label = "Draft"
        } else if words.last == "copy" || (words.count >= 3 && words[words.count - 2] == "copy" && number(words.last!) != nil) {
            let n = number(words.last!) ?? 1
            if words.last != "copy" { words.removeLast() }
            words.removeLast(); rank = 5_000 + Double(n); label = n > 1 ? "Copy \(n)" : "Copy"
        } else if let last = words.last {
            // "v2", "r3", "rev4" glued to the number, or "v 2" / "version 2" / "rev 2" split.
            for prefix in ["version", "ver", "rev", "v", "r"] where last.hasPrefix(prefix) {
                if let n = number(String(last.dropFirst(prefix.count))) { words.removeLast(); rank = Double(n); label = "v\(n)"; break }
            }
            if rank == nil, words.count >= 3, let n = number(last), ["v", "ver", "version", "rev"].contains(words[words.count - 2]) {
                words.removeLast(2); rank = Double(n); label = "v\(n)"
            }
        }
        guard let rank, !words.isEmpty else { return nil }
        return Parsed(base: words.joined(separator: " "), rank: rank, label: label)
    }

    /// Ordering key for one asset in a stack: its version, or 0 ("Original") for the unmarked base.
    public static func rank(_ a: StudioAsset) -> (Double, String) {
        if let p = parse(a.title) { return (p.rank, p.label) }
        if let p = a.importedPath.flatMap({ parse(URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent) }) { return (p.rank, p.label) }
        return (0, "Original")
    }

    static func normalized(_ title: String) -> String {
        title.lowercased().split(whereSeparator: { " _-.()[]".contains($0) }).joined(separator: " ")
    }
}

extension StudioCatalog {
    /// Versions in the asset's stack, oldest first. Just the asset when it isn't stacked.
    public func versions(of id: UUID) -> [StudioAsset] {
        guard let a = assets.first(where: { $0.id == id }) else { return [] }
        guard let s = a.stackID else { return [a] }
        return assets.filter { $0.stackID == s }.sorted { l, r in
            let (a, b) = (VersionStacks.rank(l), VersionStacks.rank(r))
            return a.0 != b.0 ? a.0 < b.0 : l.title.localizedStandardCompare(r.title) == .orderedAscending
        }
    }

    /// The newest version, which stands in for the stack in the grid.
    public func stackTop(_ id: UUID) -> StudioAsset? { versions(of: id).last }

    /// Groups assets whose names differ only by a version marker (same kind). Leaves unstacked assets
    /// and existing stacks alone, but lets a new version join an existing stack. Returns how many assets moved.
    @discardableResult
    public mutating func autoStack() -> Int {
        var groups: [String: [Int]] = [:]
        var marked = Set<String>()
        for (i, a) in assets.enumerated() where !a.unstacked {
            let key: String
            if let p = VersionStacks.parse(a.title) { key = "\(a.kind.rawValue)|\(p.base)"; marked.insert(key) }
            else { key = "\(a.kind.rawValue)|\(VersionStacks.normalized(a.title))" }
            groups[key, default: []].append(i)
        }
        var moved = 0
        for (key, idx) in groups where idx.count >= 2 && marked.contains(key) {
            let existing = idx.compactMap { assets[$0].stackID }.first ?? UUID()
            for i in idx where assets[i].stackID != existing {
                assets[i].stackID = existing; moved += 1
            }
        }
        return moved
    }

    /// Stacks the given assets together (2 or more). Returns the stack id.
    @discardableResult
    public mutating func stack(_ ids: Set<UUID>) -> UUID? {
        let idx = assets.indices.filter { ids.contains(assets[$0].id) }
        guard idx.count >= 2 else { return nil }
        let sid = idx.compactMap { assets[$0].stackID }.first ?? UUID()
        for i in idx { assets[i].stackID = sid; assets[i].unstacked = false }
        return sid
    }

    /// Takes the assets out of their stacks and keeps them out of auto-detection.
    /// A stack left with a single version dissolves.
    public mutating func unstack(_ ids: Set<UUID>) {
        var touched = Set<UUID>()
        for i in assets.indices where ids.contains(assets[i].id) {
            if let s = assets[i].stackID { touched.insert(s) }
            assets[i].stackID = nil; assets[i].unstacked = true
        }
        for s in touched {
            let left = assets.indices.filter { assets[$0].stackID == s }
            if left.count == 1 { assets[left[0]].stackID = nil }
        }
    }

    /// Hides older versions: each stack shows only its newest member present in `list`, in that member's place.
    /// Stacks in `expanded` show every version.
    public func collapsingStacks(_ list: [StudioAsset], expanded: Set<UUID> = []) -> [StudioAsset] {
        var topFor: [UUID: UUID] = [:]
        for a in list { if let s = a.stackID, topFor[s] == nil, !expanded.contains(s) {
            let present = Set(list.filter { $0.stackID == s }.map(\.id))
            topFor[s] = versions(of: a.id).last(where: { present.contains($0.id) })?.id
        } }
        return list.filter { a in
            guard let s = a.stackID, let top = topFor[s] else { return true }
            return a.id == top
        }
    }

    public func stackCount(_ a: StudioAsset) -> Int {
        guard let s = a.stackID else { return 1 }
        return assets.reduce(0) { $0 + ($1.stackID == s ? 1 : 0) }
    }
}
