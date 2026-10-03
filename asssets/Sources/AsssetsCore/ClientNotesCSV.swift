import Foundation

/// A revision to-do list: one row per imported client note. Reviewer names are local
/// draft labels from the feedback file, not verified identities. No images or paths.
public enum ClientNotesCSV {
    public static let columns = ["Asset title", "Source filename", "Reviewer", "Gallery", "Note", "Status"]

    public static func quoted(_ raw: String) -> String {
        // Spreadsheets run text that starts with these characters as formulas.
        let leading = raw.drop(while: { $0.isWhitespace }).first
        let value = leading.map { "=+-@".contains($0) } == true ? "'" + raw : raw
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    public static func rows(_ assets: [StudioAsset], galleryTitles: [String: String]) -> [[String]] {
        var out: [[String]] = []
        for a in assets.sorted(by: { ($0.title.lowercased(), $0.id.uuidString) < ($1.title.lowercased(), $1.id.uuidString) }) {
            let file = a.importedPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
            for n in a.clientNotes.sorted(by: { ($0.gallery, $0.reviewer.lowercased()) < ($1.gallery, $1.reviewer.lowercased()) }) {
                out.append([a.title, file, n.reviewer, galleryTitles[n.gallery.lowercased()] ?? "Unknown gallery", n.text, n.resolved ? "Resolved" : "Open"])
            }
        }
        return out
    }

    public static func render(_ assets: [StudioAsset], galleryTitles: [String: String]) -> String {
        let lines = [columns] + rows(assets, galleryTitles: galleryTitles)
        return lines.map { $0.map(quoted).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }
}

extension StudioCatalog {
    public var clientNoteCount: Int { assets.reduce(0) { $0 + $1.clientNotes.count } }
    /// Assets that still carry at least one unresolved client note.
    public var openClientNoteAssetCount: Int { assets.filter(\.hasOpenClientNotes).count }
    public var openClientNoteCount: Int { assets.reduce(0) { $0 + $1.clientNotes.filter { !$0.resolved }.count } }
    /// How many notes on these assets would change if all were set to `resolved`.
    public func clientNotesToChange(on ids: Set<UUID>, resolved: Bool) -> (notes: Int, assets: Int) {
        let hit = assets.filter { ids.contains($0.id) }.map { $0.clientNotes.filter { $0.resolved != resolved }.count }.filter { $0 > 0 }
        return (hit.reduce(0, +), hit.count)
    }
    /// Sets every client note on these assets in one step. Returns what actually changed.
    @discardableResult public mutating func setClientNotes(on ids: Set<UUID>, resolved: Bool) -> (notes: Int, assets: Int) {
        let changed = clientNotesToChange(on: ids, resolved: resolved)
        for i in assets.indices where ids.contains(assets[i].id) {
            for j in assets[i].clientNotes.indices { assets[i].clientNotes[j].resolved = resolved }
        }
        return changed
    }
    /// Ticks or unticks exactly this note. Returns false when the note is gone (for example after a re-import).
    @discardableResult public mutating func setClientNote(_ note: ClientNote, on id: UUID, resolved: Bool) -> Bool {
        guard let i = assets.firstIndex(where: { $0.id == id }),
              let j = assets[i].clientNotes.firstIndex(where: { $0.reviewer == note.reviewer && $0.gallery == note.gallery && $0.text == note.text })
        else { return false }
        assets[i].clientNotes[j].resolved = resolved
        return true
    }
    public func clientNotesCSV() -> String {
        var titles: [String: String] = [:]
        for r in galleryRosters { titles[r.gallery.lowercased()] = r.title }
        return ClientNotesCSV.render(assets, galleryTitles: titles)
    }
}

extension StudioAsset {
    public var hasOpenClientNotes: Bool { clientNotes.contains { !$0.resolved } }
}

/// Keeps the inspector honest when a view filter hides what was selected.
public enum FilterSelection {
    /// Hidden assets drop out. If nothing visible remains selected, the first visible asset
    /// takes over; with no visible asset the selection clears.
    public static func reconcile(selection: Set<UUID>, focus: UUID?, visible: [UUID]) -> (selection: Set<UUID>, focus: UUID?) {
        let shown = Set(visible)
        let kept = selection.intersection(shown)
        if !kept.isEmpty { return (kept, focus.flatMap { kept.contains($0) ? $0 : nil } ?? visible.first(where: kept.contains)) }
        guard let first = visible.first else { return ([], nil) }
        return ([first], first)
    }
}

/// One row per client decision. Names are local draft labels from the feedback file.
public enum ClientDecisionsCSV {
    public static let columns = ["Asset title", "Source filename", "Reviewer", "Gallery", "Decision"]
    public static func render(_ assets: [StudioAsset], galleryTitles: [String: String]) -> String {
        var lines = [columns]
        for a in assets.sorted(by: { ($0.title.lowercased(), $0.id.uuidString) < ($1.title.lowercased(), $1.id.uuidString) }) {
            let file = a.importedPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
            for d in a.clientDecisions.sorted(by: { ($0.gallery, $0.reviewer.lowercased()) < ($1.gallery, $1.reviewer.lowercased()) }) {
                lines.append([a.title, file, d.reviewer, galleryTitles[d.gallery.lowercased()] ?? "Unknown gallery", d.status.label])
            }
        }
        return lines.map { $0.map(ClientNotesCSV.quoted).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }
}

extension StudioCatalog {
    public var clientDecisionCount: Int { assets.reduce(0) { $0 + $1.clientDecisions.count } }
    public func clientDecisionsCSV() -> String {
        var titles: [String: String] = [:]
        for r in galleryRosters { titles[r.gallery.lowercased()] = r.title }
        return ClientDecisionsCSV.render(assets, galleryTitles: titles)
    }
}

/// 1.85: a view filter over imported client decisions. "Changes" means any reviewer asked for changes;
/// "Approved" means someone approved and nobody asked for changes.
public enum ClientDecisionFilter: String, CaseIterable, Codable, Sendable {
    case any, changes, approved
    public var label: String {
        switch self { case .any: return "Any decision"; case .changes: return "Changes requested"; case .approved: return "Approved, no changes" }
    }
    public func matches(_ a: StudioAsset) -> Bool {
        let d = a.clientDecisions.map(\.status)
        switch self {
        case .any: return true
        case .changes: return d.contains(.changes)
        case .approved: return d.contains(.approved) && !d.contains(.changes)
        }
    }
    /// Smart-collection wording.
    public var summary: String {
        switch self { case .any: return ""; case .changes: return "client requested changes"; case .approved: return "client approved, no changes" }
    }
}

extension StudioCatalog {
    public func assetCount(matching f: ClientDecisionFilter) -> Int { assets.filter(f.matches).count }
}

/// A plain-text to-do for the next revision pass: assets a reviewer asked to change, and their open notes.
/// Reviewer names are local draft labels from the feedback file, not verified identities.
public enum RevisionBrief {
    public struct Result: Equatable, Sendable { public var text: String; public var assets: Int; public var notes: Int }

    public static func render(_ assets: [StudioAsset]) -> Result {
        var blocks: [String] = [], noteTotal = 0
        for a in assets {
            let changers = a.clientDecisions.filter { $0.status == .changes }.map(\.reviewer)
            let open = a.clientNotes.filter { !$0.resolved }
            guard !changers.isEmpty || !open.isEmpty else { continue }
            let file = a.importedPath.map { URL(fileURLWithPath: $0).lastPathComponent }
            var lines = ["• " + a.title + (file.map { $0 == a.title ? "" : " (\($0))" } ?? "")]
            if !changers.isEmpty { lines.append("  Changes requested by " + uniqued(changers).joined(separator: ", ")) }
            for n in open {
                let body = n.text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
                lines.append("  Open note, " + n.reviewer + ": " + body[0])
                for extra in body.dropFirst() { lines.append("    " + extra) }
                noteTotal += 1
            }
            blocks.append(lines.joined(separator: "\n"))
        }
        guard !blocks.isEmpty else { return Result(text: "", assets: 0, notes: 0) }
        let head = "Revision brief: \(blocks.count) \(blocks.count == 1 ? "asset" : "assets"), \(noteTotal) open \(noteTotal == 1 ? "note" : "notes")"
        let foot = "Reviewer names are labels typed into the review gallery, not verified identities."
        return Result(text: ([head, ""] + blocks + ["", foot]).joined(separator: "\n") + "\n", assets: blocks.count, notes: noteTotal)
    }
    private static func uniqued(_ names: [String]) -> [String] {
        var seen = Set<String>(); return names.filter { seen.insert($0.lowercased()).inserted }
    }
}
