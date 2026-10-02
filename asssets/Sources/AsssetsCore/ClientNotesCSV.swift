import Foundation

/// A revision to-do list: one row per imported client note. Reviewer names are local
/// draft labels from the feedback file, not verified identities. No images or paths.
public enum ClientNotesCSV {
    public static let columns = ["Asset title", "Source filename", "Reviewer", "Gallery", "Note"]

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
                out.append([a.title, file, n.reviewer, galleryTitles[n.gallery.lowercased()] ?? "Unknown gallery", n.text])
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
    public func clientNotesCSV() -> String {
        var titles: [String: String] = [:]
        for r in galleryRosters { titles[r.gallery.lowercased()] = r.title }
        return ClientNotesCSV.render(assets, galleryTitles: titles)
    }
}
