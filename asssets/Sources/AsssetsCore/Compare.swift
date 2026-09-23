import Foundation

// MARK: - Compare: 2-4 assets side by side, synced zoom/pan, and a keep/reject pass

public enum CompareVerdict: String, Codable, Sendable { case keep, reject }

public struct CompareSession: Equatable, Sendable {
    public static let maxAssets = 4
    public private(set) var ids: [UUID]
    public private(set) var verdicts: [UUID: CompareVerdict] = [:]
    public var focus: Int = 0

    /// Nil unless 2 to 4 distinct assets are given; order is kept.
    public init?(ids: [UUID]) {
        var seen = Set<UUID>(); let unique = ids.filter { seen.insert($0).inserted }
        guard (2...Self.maxAssets).contains(unique.count) else { return nil }
        self.ids = unique
    }

    public var focusedID: UUID { ids[focus] }
    public var keeps: [UUID] { ids.filter { verdicts[$0] == .keep } }
    public var rejects: [UUID] { ids.filter { verdicts[$0] == .reject } }
    public var undecided: [UUID] { ids.filter { verdicts[$0] == nil } }
    public var isComplete: Bool { undecided.isEmpty }

    public mutating func moveFocus(by delta: Int) {
        let n = ids.count
        focus = (((focus + delta) % n) + n) % n
    }

    /// Sets (or, when repeated, clears) the verdict for the focused asset, then moves to the next undecided one.
    public mutating func mark(_ v: CompareVerdict) {
        let id = focusedID
        if verdicts[id] == v { verdicts[id] = nil; return }
        verdicts[id] = v
        let (n, f, vs, all) = (ids.count, focus, verdicts, ids)
        if let next = (1..<n).map({ (f + $0) % n }).first(where: { vs[all[$0]] == nil }) { focus = next }
    }

    public var summary: String {
        let k = keeps.count, r = rejects.count, u = undecided.count
        var parts = ["\(k) kept", "\(r) rejected"]
        if u > 0 { parts.append("\(u) undecided") }
        return parts.joined(separator: " · ")
    }
}

/// One shared zoom and pan for every pane. Pan is in units of the pane size, so panes of any size stay aligned.
public struct ZoomPan: Equatable, Sendable {
    public static let range: ClosedRange<Double> = 1...8
    public private(set) var zoom: Double = 1
    public private(set) var panX: Double = 0
    public private(set) var panY: Double = 0
    public init() {}

    public var isFit: Bool { zoom == 1 }

    /// Zooms keeping `anchor` (0...1 across the pane, 0.5 = center) fixed on screen.
    public mutating func zoom(by factor: Double, anchorX: Double = 0.5, anchorY: Double = 0.5) {
        let new = min(Self.range.upperBound, max(Self.range.lowerBound, zoom * factor))
        guard new != zoom else { return }
        let ax = anchorX - 0.5, ay = anchorY - 0.5
        // Content point under the anchor: (a - pan) / zoom. Keep it under the anchor after zooming.
        panX = ax - (ax - panX) * new / zoom
        panY = ay - (ay - panY) * new / zoom
        zoom = new
        clamp()
    }

    public mutating func pan(dx: Double, dy: Double) { panX += dx; panY += dy; clamp() }
    public mutating func reset() { zoom = 1; panX = 0; panY = 0 }

    /// The content always covers the pane: pan limit is half the overflow.
    mutating func clamp() {
        let limit = (zoom - 1) / 2
        panX = min(limit, max(-limit, panX)); panY = min(limit, max(-limit, panY))
    }
}

public enum CompareDiff {
    public struct Row: Equatable, Sendable {
        public var id: UUID
        public var uniqueTags: [String]     // tags no other compared asset has
        public var uniqueColors: [String]   // palette colors far from every other asset's palette
    }

    /// Tags every compared asset shares (user and suggested).
    public static func sharedTags(_ assets: [StudioAsset]) -> [String] {
        guard let first = assets.first else { return [] }
        return first.searchTags.filter { t in assets.dropFirst().allSatisfy { $0.searchTags.contains(t) } }
    }

    public static func rows(_ assets: [StudioAsset], colorThreshold: Double = 60) -> [Row] {
        assets.map { a in
            let others = assets.filter { $0.id != a.id }
            let otherTags = Set(others.flatMap(\.searchTags))
            let otherColors = others.flatMap(\.palette).compactMap(Similarity.rgb)
            let colors = a.palette.filter { hex in
                guard let c = Similarity.rgb(hex) else { return false }
                return otherColors.allSatisfy { o in
                    let d = ((c.0 - o.0) * (c.0 - o.0) + (c.1 - o.1) * (c.1 - o.1) + (c.2 - o.2) * (c.2 - o.2)).squareRoot()
                    return d > colorThreshold
                }
            }
            return Row(id: a.id, uniqueTags: a.searchTags.filter { !otherTags.contains($0) }, uniqueColors: colors)
        }
    }
}

extension StudioCatalog {
    public static let picksName = "Picks"
    public static let pickTag = "pick"
    public static let rejectTag = "rejected"

    /// Writes a compare pass: keeps get the "pick" tag, rejects get "rejected" (and lose "pick").
    /// Assets stay in their own collections; a "Picks" smart collection lists every pick.
    /// Returns the Picks smart collection id when anything was kept.
    @discardableResult
    public mutating func applyPicks(_ session: CompareSession) -> UUID? {
        let keep = Set(session.keeps), reject = Set(session.rejects)
        for i in assets.indices {
            let id = assets[i].id
            if keep.contains(id) {
                assets[i].tags.removeAll { $0 == Self.rejectTag }
                if !assets[i].tags.contains(Self.pickTag) { assets[i].tags.append(Self.pickTag) }
            } else if reject.contains(id) {
                assets[i].tags.removeAll { $0 == Self.pickTag }
                if !assets[i].tags.contains(Self.rejectTag) { assets[i].tags.append(Self.rejectTag) }
            }
        }
        guard !keep.isEmpty else { return nil }
        if let s = smartCollections.first(where: { $0.rules == SmartRules(requiredTags: [Self.pickTag]) }) { return s.id }
        let s = StudioSmartCollection(name: uniqueSmartName(Self.picksName), rules: SmartRules(requiredTags: [Self.pickTag]), symbol: "checkmark.seal")
        smartCollections.append(s)
        return s.id
    }
}
