import Foundation

// MARK: - Batch rename and folder-structure export (1.14)

/// Shared token engine for rename, file-name and folder patterns.
/// `{n}` is the running number with two digits; `{n:0000}` pads to as many digits as there are zeros.
public enum PatternTokens {
    public static func expand(_ pattern: String, values: [String: String], index: Int) -> String {
        var out = "", i = pattern.startIndex
        while i < pattern.endIndex {
            if pattern[i] == "{", let close = pattern[i...].firstIndex(of: "}") {
                let body = String(pattern[pattern.index(after: i)..<close])
                if let v = value(body, values: values, index: index) { out += v; i = pattern.index(after: close); continue }
            }
            out.append(pattern[i]); i = pattern.index(after: i)
        }
        return out
    }

    static func value(_ token: String, values: [String: String], index: Int) -> String? {
        if token == "n" { return String(format: "%02d", index) }
        if token.hasPrefix("n:") {
            let pad = token.dropFirst(2)
            guard !pad.isEmpty, pad.allSatisfy({ $0 == "0" }), pad.count <= 8 else { return nil }
            let s = String(index)
            return String(repeating: "0", count: max(0, pad.count - s.count)) + s
        }
        return values["{\(token)}"]
    }

    /// The per-asset values every pattern understands.
    public static func values(for a: StudioAsset, date: Date) -> [String: String] {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return ["{title}": a.title, "{collection}": a.collection, "{kind}": a.kind.singular,
                "{rating}": a.rating > 0 ? "\(a.rating) star\(a.rating == 1 ? "" : "s")" : "Unrated",
                "{label}": a.label?.name ?? "No Label", "{date}": f.string(from: date)]
    }
}

public enum RenamePattern {
    public static let defaultPattern = "{collection} {n:000}"
    public static let tokens = ["{title}", "{collection}", "{kind}", "{date}", "{rating}", "{label}", "{n}", "{n:000}"]

    public struct Row: Equatable, Identifiable, Sendable {
        public var id: UUID
        public var old: String
        public var new: String
        public var changed: Bool { old != new }
        /// Another row in this batch ends up with the same title.
        public var clash = false
    }

    /// One title: tokens filled, runs of spaces collapsed, trimmed. An empty result keeps the old title.
    public static func render(_ pattern: String, asset: StudioAsset, index: Int, date: Date = Date()) -> String {
        let raw = PatternTokens.expand(pattern, values: PatternTokens.values(for: asset, date: date), index: index)
        let s = raw.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).joined(separator: " ")
        return s.isEmpty ? asset.title : String(s.prefix(160))
    }

    /// Titles in grid order, numbered from `start`.
    public static func preview(_ pattern: String, assets: [StudioAsset], start: Int = 1, date: Date = Date()) -> [Row] {
        var rows = assets.enumerated().map { i, a in Row(id: a.id, old: a.title, new: render(pattern, asset: a, index: start + i, date: date)) }
        var seen: [String: Int] = [:]
        for r in rows { seen[r.new.lowercased(), default: 0] += 1 }
        for i in rows.indices { rows[i].clash = (seen[rows[i].new.lowercased()] ?? 0) > 1 }
        return rows
    }
}

extension StudioCatalog {
    /// Applies new titles; returns how many changed. Titles only - files on disk keep their names.
    @discardableResult
    public mutating func retitle(_ titles: [UUID: String]) -> Int {
        var n = 0
        for i in assets.indices {
            guard let t = titles[assets[i].id]?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty, t != assets[i].title else { continue }
            assets[i].title = t; n += 1
        }
        return n
    }
}

/// Subfolders for an export: "{collection}/{label}" puts each file under e.g. "Device Mockups/Green".
public enum FolderPattern {
    public static let tokens = ["{collection}", "{label}", "{rating}", "{kind}", "{date}"]
    public static let examples = ["{collection}", "{collection}/{label}", "{rating}", "{kind}/{collection}"]
    public static let maxDepth = 5

    /// Safe path components; empty for a flat export. "." and ".." never survive, and nothing climbs out of the export folder.
    public static func components(_ pattern: String, asset: StudioAsset, date: Date = Date()) -> [String] {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let values = PatternTokens.values(for: asset, date: date)
        // Split first, so a slash inside a title or collection name can't add a level.
        let parts = trimmed.split(separator: "/", omittingEmptySubsequences: true).map { part -> String in
            let v = PatternTokens.expand(String(part), values: values, index: 1).trimmingCharacters(in: .whitespacesAndNewlines)
            return v.isEmpty || v.allSatisfy({ $0 == "." }) ? "" : DragOut.safeName(v)
        }
        return Array(parts.filter { !$0.isEmpty }.prefix(maxDepth))
    }

    public static func relativePath(_ pattern: String, asset: StudioAsset, date: Date = Date()) -> String {
        components(pattern, asset: asset, date: date).joined(separator: "/")
    }
}
