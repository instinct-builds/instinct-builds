import Foundation

/// A dry run for moving a folder of user-owned files. No filename search is performed:
/// only the exact path below oldRoot is appended below newRoot.
public struct FolderRelinkPreview: Sendable {
    public struct Row: Sendable, Identifiable {
        public enum Status: String, Sendable { case matched, unmatched, ambiguous }
        public let id: UUID
        public let title: String
        public let oldPath: String
        public let newPath: String
        public let status: Status
        public let reason: String
    }
    public let oldRoot: String
    public let newRoot: String
    public let rows: [Row]
    public let outOfScopeCount: Int
    public var matched: [Row] { rows.filter { $0.status == .matched } }
    public var unmatched: [Row] { rows.filter { $0.status == .unmatched } }
    public var ambiguous: [Row] { rows.filter { $0.status == .ambiguous } }

    public init(catalog: StudioCatalog, oldRoot: String, newRoot: String,
                exists: (String) -> Bool, isFile: (String) -> Bool) {
        let old = URL(fileURLWithPath: oldRoot, isDirectory: true).standardizedFileURL.path
        let new = URL(fileURLWithPath: newRoot, isDirectory: true).standardizedFileURL.path
        self.oldRoot = old; self.newRoot = new
        let missing = catalog.missingIDs(exists: exists)
        let owned = Set(catalog.assets.compactMap(\.importedPath))
        let resolvedRoot = URL(fileURLWithPath: new, isDirectory: true).resolvingSymlinksInPath().path
        var draft: [(StudioAsset, String, String)] = []
        for art in catalog.assets where missing.contains(art.id) {
            guard let path = art.importedPath,
                  path.hasPrefix(old + "/"), !art.isStarter else { continue }
            let suffix = String(path.dropFirst(old.count + 1))
            let target = URL(fileURLWithPath: new, isDirectory: true).appendingPathComponent(suffix).standardizedFileURL.path
            draft.append((art, path, target))
        }
        let counts = Dictionary(draft.map { ($0.2, 1) }, uniquingKeysWith: +)
        outOfScopeCount = missing.count - draft.count
        rows = draft.map { art, path, target in
            let reason: String
            let status: Row.Status
            let resolvedTarget = URL(fileURLWithPath: target).resolvingSymlinksInPath().path
            if old == new || !target.hasPrefix(new + "/") || counts[target, default: 0] > 1 || owned.contains(target) {
                status = .ambiguous; reason = "Destination overlaps another library file or mapping"
            } else if exists(target) && !resolvedTarget.hasPrefix(resolvedRoot + "/") {
                status = .ambiguous; reason = "Destination points outside the chosen folder"
            } else if !exists(target) {
                status = .unmatched; reason = "Exact relative path not found"
            } else if !isFile(target) {
                status = .ambiguous; reason = "Destination is not a regular file"
            } else if URL(fileURLWithPath: path).pathExtension.lowercased() != URL(fileURLWithPath: target).pathExtension.lowercased() {
                status = .ambiguous; reason = "File type changed"
            } else {
                status = .matched; reason = "Exact relative path found"
            }
            return Row(id: art.id, title: art.title, oldPath: path, newPath: target, status: status, reason: reason)
        }
    }
}

extension StudioCatalog {
    /// Apply only the rows the owner previewed. The app refreshes the dry run from live disk state first.
    /// Preserve IDs and all metadata so recipes, boards and rights stay linked.
    @discardableResult
    public mutating func relinkFolder(_ preview: FolderRelinkPreview) -> Int {
        let exact = Dictionary(uniqueKeysWithValues: preview.matched.map { ($0.id, ($0.oldPath, $0.newPath)) })
        var count = 0
        for i in assets.indices {
            guard let pair = exact[assets[i].id], assets[i].importedPath == pair.0 else { continue }
            assets[i].importedPath = pair.1
            count += 1
        }
        return count
    }
}
