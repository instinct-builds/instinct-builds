import Foundation

// MARK: - Live smart collections for the studio catalog

public enum PaletteTone: String, Codable, CaseIterable, Identifiable, Sendable {
    case warm = "Warm", cool = "Cool", neutral = "Neutral", vivid = "Vivid"
    public var id: String { rawValue }

    /// Classifies a palette from its hex colors: mostly low-saturation is neutral,
    /// high average saturation is vivid, otherwise the saturated hues vote warm or cool.
    public static func of(_ palette: [String]) -> PaletteTone? {
        let hsv = palette.compactMap(Self.hsv)
        guard !hsv.isEmpty else { return nil }
        let saturated = hsv.filter { $0.s > 0.22 && $0.v > 0.18 }
        if saturated.count * 2 < hsv.count { return .neutral }
        let avgS = saturated.map(\.s).reduce(0, +) / Double(saturated.count)
        let warmVotes = saturated.filter { $0.h < 70 || $0.h >= 300 }.count
        let coolVotes = saturated.count - warmVotes
        if avgS > 0.72 && warmVotes > 0 && coolVotes > 0 { return .vivid }
        return warmVotes >= coolVotes ? .warm : .cool
    }

    static func hsv(_ hex: String) -> (h: Double, s: Double, v: Double)? {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let n = UInt64(s, radix: 16) else { return nil }
        let r = Double((n >> 16) & 255) / 255, g = Double((n >> 8) & 255) / 255, b = Double(n & 255) / 255
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        var h = 0.0
        if d > 0 {
            if mx == r { h = 60 * ((g - b) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == g { h = 60 * ((b - r) / d + 2) }
            else { h = 60 * ((r - g) / d + 4) }
        }
        if h < 0 { h += 360 }
        return (h, mx == 0 ? 0 : d / mx, mx)
    }
}

public struct SmartRules: Codable, Equatable, Sendable {
    public var text: String = ""
    public var kinds: [MediaKind] = []
    public var requiredTags: [String] = []
    public var favoritesOnly = false
    public var tone: PaletteTone?
    public var collection: String?
    /// At least this many stars; 0 means any (1.11).
    public var minRating = 0
    /// Any of these color labels; empty means any (1.11).
    public var labels: [ColorLabel] = []
    /// Contains a color near this one (1.15).
    public var color: ColorQuery? = nil
    /// Rights state (1.25): ending soon, expired or missing.
    public var rights: RightsFilter? = nil

    public init(text: String = "", kinds: [MediaKind] = [], requiredTags: [String] = [], favoritesOnly: Bool = false,
                tone: PaletteTone? = nil, collection: String? = nil, minRating: Int = 0, labels: [ColorLabel] = [], color: ColorQuery? = nil,
                rights: RightsFilter? = nil) {
        self.text = text; self.kinds = kinds; self.requiredTags = requiredTags; self.favoritesOnly = favoritesOnly
        self.tone = tone; self.collection = collection; self.minRating = minRating; self.labels = labels; self.color = color
        self.rights = rights
    }

    enum CodingKeys: String, CodingKey { case text, kinds, requiredTags, favoritesOnly, tone, collection, minRating, labels, color, rights }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        kinds = try c.decodeIfPresent([MediaKind].self, forKey: .kinds) ?? []
        requiredTags = try c.decodeIfPresent([String].self, forKey: .requiredTags) ?? []
        favoritesOnly = try c.decodeIfPresent(Bool.self, forKey: .favoritesOnly) ?? false
        tone = try c.decodeIfPresent(PaletteTone.self, forKey: .tone)
        collection = try c.decodeIfPresent(String.self, forKey: .collection)
        minRating = try c.decodeIfPresent(Int.self, forKey: .minRating) ?? 0
        labels = (try? c.decodeIfPresent([ColorLabel].self, forKey: .labels)) ?? []
        color = try? c.decodeIfPresent(ColorQuery.self, forKey: .color)
        rights = try? c.decodeIfPresent(RightsFilter.self, forKey: .rights)
    }

    public var isEmpty: Bool { text.trimmingCharacters(in: .whitespaces).isEmpty && kinds.isEmpty && requiredTags.isEmpty && !favoritesOnly && tone == nil && collection == nil && minRating == 0 && labels.isEmpty && color == nil && rights == nil }

    public func matches(_ a: StudioAsset) -> Bool {
        if !kinds.isEmpty && !kinds.contains(a.kind) { return false }
        if favoritesOnly && !a.favorite { return false }
        if a.rating < minRating { return false }
        if !labels.isEmpty && !(a.label.map(labels.contains) ?? false) { return false }
        if let collection, a.collection != collection { return false }
        if !requiredTags.allSatisfy({ a.searchTags.contains($0) }) { return false }
        if let tone, PaletteTone.of(a.palette) != tone { return false }
        if let color, !ColorSearch.matches(color, a) { return false }
        if let rights, !a.matches(rights) { return false }
        let terms = text.lowercased().split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
        guard !terms.isEmpty else { return true }
        let hay = ([a.title, a.kind.rawValue, a.collection, a.resolution] + a.searchTags + a.palette).joined(separator: " ").lowercased()
        return terms.allSatisfy(hay.contains)
    }

    /// Plain-language summary for the sidebar and editor.
    public var summary: String {
        var parts: [String] = []
        if !kinds.isEmpty { parts.append(kinds.map(\.rawValue).joined(separator: " or ")) }
        if let tone { parts.append("\(tone.rawValue.lowercased()) palette") }
        if let color { parts.append("color \(color.closeness) \(color.hex)") }
        if favoritesOnly { parts.append("favorites") }
        if minRating > 0 { parts.append(minRating == 5 ? "rated 5★" : "rated \(minRating)★ or more") }
        if !labels.isEmpty { parts.append(labels.map(\.name).joined(separator: " or ").lowercased() + " label") }
        if !requiredTags.isEmpty { parts.append("tagged " + requiredTags.joined(separator: " + ")) }
        if let collection { parts.append("in \(collection)") }
        if let rights { parts.append(rights.summary) }
        let t = text.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty { parts.append("matching \"\(t)\"") }
        return parts.isEmpty ? "Everything" : parts.joined(separator: " • ")
    }
}

public struct StudioSmartCollection: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var rules: SmartRules
    public var symbol: String
    public init(id: UUID = UUID(), name: String, rules: SmartRules, symbol: String = "sparkles.rectangle.stack") {
        self.id = id; self.name = name; self.rules = rules; self.symbol = symbol
    }
}

extension StudioCatalog {
    public static let defaultSmartCollections: [(String, SmartRules, String)] = [
        ("Warm Palettes", SmartRules(tone: .warm), "sun.max"),
        ("Cool Palettes", SmartRules(tone: .cool), "snowflake"),
        ("Real Files", SmartRules(requiredTags: ["bundled"]), "doc.richtext"),
        ("Favorite Clips", SmartRules(kinds: [.video, .audio], favoritesOnly: true), "play.rectangle"),
    ]

    /// Adds the starter smart collections once; deleting one keeps it deleted.
    @discardableResult
    public mutating func seedSmartCollections() -> Int {
        // 0.5/0.6 named this "Favorite Motion & Sound", which truncated in the sidebar. Rename it only if untouched.
        if let i = smartCollections.firstIndex(where: { $0.name == "Favorite Motion & Sound" && $0.rules == SmartRules(kinds: [.video, .audio], favoritesOnly: true) }),
           !smartCollections.contains(where: { $0.name == "Favorite Clips" }) {
            smartCollections[i].name = "Favorite Clips"
        }
        guard !smartSeeded else { return 0 }
        smartSeeded = true
        var n = 0
        for (name, rules, symbol) in Self.defaultSmartCollections where !smartCollections.contains(where: { $0.name == name }) {
            smartCollections.append(StudioSmartCollection(name: name, rules: rules, symbol: symbol)); n += 1
        }
        return n
    }

    func uniqueSmartName(_ base: String, excluding id: UUID? = nil) -> String {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let root = trimmed.isEmpty ? "Smart Collection" : trimmed
        let taken = Set(smartCollections.filter { $0.id != id }.map(\.name)).union(collections)
        var name = root, n = 2
        while taken.contains(name) { name = "\(root) \(n)"; n += 1 }
        return name
    }

    @discardableResult
    public mutating func createSmartCollection(named name: String, rules: SmartRules) -> UUID {
        let s = StudioSmartCollection(name: uniqueSmartName(name), rules: rules)
        smartCollections.append(s)
        return s.id
    }

    @discardableResult
    public mutating func updateSmartCollection(_ id: UUID, name: String, rules: SmartRules) -> Bool {
        guard let i = smartCollections.firstIndex(where: { $0.id == id }) else { return false }
        smartCollections[i].name = uniqueSmartName(name, excluding: id)
        smartCollections[i].rules = rules
        return true
    }

    @discardableResult
    public mutating func deleteSmartCollection(_ id: UUID) -> Bool {
        let before = smartCollections.count
        smartCollections.removeAll { $0.id == id }
        return smartCollections.count != before
    }

    public func smartCollection(_ id: UUID) -> StudioSmartCollection? { smartCollections.first { $0.id == id } }

    /// Live membership: recomputed from the current catalog on every call.
    public func smartAssets(_ id: UUID) -> [StudioAsset] {
        guard let s = smartCollection(id) else { return [] }
        return assets.filter(s.rules.matches)
    }

    /// Browsing inside a smart collection: its rules AND the search box AND the media filter.
    public func filtered(search: String, kind: MediaKind?, smart id: UUID) -> [StudioAsset] {
        guard let s = smartCollection(id) else { return [] }
        return filtered(search: search, kind: kind, collection: StudioCatalog.allAssets).filter(s.rules.matches)
    }
}
