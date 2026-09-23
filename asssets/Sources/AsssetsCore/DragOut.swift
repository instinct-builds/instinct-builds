import Foundation

/// Decides what a drag out of ASSSETS hands to Finder or another app:
/// the real file when what you see is the file, otherwise a rendered PNG of what you see.
public enum DragOut {
    public enum Plan: Equatable, Sendable {
        case file(String)          // path of the original file
        case render(String)        // suggested PNG file name
    }

    public struct Look: Equatable, Sendable {
        public var effectApplied = false
        public var psdLayersChanged = false
        public var tiled = false
        public var seamsFixed = false
        public init(effectApplied: Bool = false, psdLayersChanged: Bool = false, tiled: Bool = false, seamsFixed: Bool = false) {
            self.effectApplied = effectApplied; self.psdLayersChanged = psdLayersChanged; self.tiled = tiled; self.seamsFixed = seamsFixed
        }
        public var isOriginal: Bool { !effectApplied && !psdLayersChanged && !tiled && !seamsFixed }
    }

    public static func plan(title: String, importedPath: String?, fileExists: Bool, look: Look) -> Plan {
        if let p = importedPath, fileExists, look.isOriginal { return .file(p) }
        var suffix: [String] = []
        if look.psdLayersChanged { suffix.append("layers") }
        if look.tiled { suffix.append("tiled") }
        if look.seamsFixed { suffix.append("seamless") }
        if look.effectApplied { suffix.append("edit") }
        let base = safeName(title)
        return .render((suffix.isEmpty ? base : base + " (" + suffix.joined(separator: ", ") + ")") + ".png")
    }

    public enum ExportMode: String, CaseIterable, Sendable { case originals, asShown }

    /// Export plan for one asset. Originals mode copies the file whenever it exists; generated studies render.
    public static func exportPlan(mode: ExportMode, title: String, importedPath: String?, fileExists: Bool, look: Look) -> Plan {
        switch mode {
        case .asShown: return plan(title: title, importedPath: importedPath, fileExists: fileExists, look: look)
        case .originals: return plan(title: title, importedPath: importedPath, fileExists: fileExists, look: Look())
        }
    }

    /// Finder-style collision handling: "Name.png", "Name 2.png", "Name 3.png". Case-insensitive, like APFS defaults.
    public static func uniqueName(_ name: String, taken: Set<String>) -> String {
        let lower = Set(taken.map { $0.lowercased() })
        if !lower.contains(name.lowercased()) { return name }
        let dot = name.lastIndex(of: ".")
        let (stem, ext) = dot.map { (String(name[..<$0]), String(name[$0...])) } ?? (name, "")
        var n = 2
        while lower.contains("\(stem) \(n)\(ext)".lowercased()) { n += 1 }
        return "\(stem) \(n)\(ext)"
    }

    /// A file name Finder accepts: no slashes, colons or control characters, not hidden, not empty, at most 120 characters.
    public static func safeName(_ title: String) -> String {
        let bad = CharacterSet(charactersIn: "/:\\\\").union(.controlCharacters)
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var s = String(String.UnicodeScalarView(trimmed.unicodeScalars.map { bad.contains($0) ? "-" : $0 }))
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasPrefix(".") { s.removeFirst() }
        if s.count > 120 { s = String(s.prefix(120)).trimmingCharacters(in: .whitespaces) }
        return s.isEmpty ? "Asset" : s
    }
}
