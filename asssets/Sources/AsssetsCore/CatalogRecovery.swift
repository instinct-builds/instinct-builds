import Foundation

/// 1.90: the catalog file is the only copy of every tag, note, board and rights record, so an unreadable file
/// is moved aside and reported, never overwritten, and a rolling set of last-good snapshots is kept.
public enum CatalogRecovery {
    /// Snapshots kept in Backups/, newest first. One is taken per launch after a successful load.
    public static let keepSnapshots = 5
    public static let backupsFolder = "Backups"

    public enum Outcome: Equatable, Sendable {
        /// No file, or a readable file with no assets: the silent fresh-install path. Nothing is moved.
        case fresh
        case loaded(StudioCatalog)
        /// An existing file could not be read or decoded. `preserved` is where it was moved; nil means the move failed
        /// and the caller must not save over it.
        case unreadable(original: String, preserved: URL?)
    }

    public static func stamp(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone.current
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: date)
    }

    /// A path next to `base` that does not exist yet: name, name-2, name-3...
    public static func freeURL(dir: URL, stem: String, ext: String, fm: FileManager = .default) -> URL {
        var url = dir.appendingPathComponent("\(stem).\(ext)"), n = 2
        while fm.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("\(stem)-\(n).\(ext)"); n += 1
        }
        return url
    }

    public static func load(catalogURL: URL, legacyURL: URL, now: Date = Date(), fm: FileManager = .default) -> Outcome {
        for url in [catalogURL, legacyURL] {
            guard fm.fileExists(atPath: url.path) else { continue }
            if let data = try? Data(contentsOf: url), let c = StudioCatalog.decode(data) {
                if c.assets.isEmpty { continue }
                return .loaded(c)
            }
            let dir = url.deletingLastPathComponent()
            let stem = url.deletingPathExtension().lastPathComponent + ".corrupt-" + stamp(now)
            let target = freeURL(dir: dir, stem: stem, ext: url.pathExtension, fm: fm)
            if (try? fm.moveItem(at: url, to: target)) != nil || (try? fm.copyItem(at: url, to: target)) != nil {
                return .unreadable(original: url.lastPathComponent, preserved: target)
            }
            return .unreadable(original: url.lastPathComponent, preserved: nil)
        }
        return .fresh
    }

    /// Copies a catalog file that just loaded into Backups/ and prunes to the newest `keepSnapshots`.
    @discardableResult
    public static func snapshot(catalogURL: URL, backups: URL, now: Date = Date(), fm: FileManager = .default) -> URL? {
        guard fm.fileExists(atPath: catalogURL.path) else { return nil }
        try? fm.createDirectory(at: backups, withIntermediateDirectories: true)
        let target = freeURL(dir: backups, stem: "catalog-" + stamp(now), ext: "json", fm: fm)
        do { try fm.copyItem(at: catalogURL, to: target) } catch { return nil }
        let all = snapshotURLs(backups: backups, fm: fm)
        for old in all.dropFirst(keepSnapshots) { try? fm.removeItem(at: old) }
        return target
    }

    /// Newest first. Only files this machinery wrote (catalog-*.json).
    public static func snapshotURLs(backups: URL, fm: FileManager = .default) -> [URL] {
        let names = (try? fm.contentsOfDirectory(atPath: backups.path)) ?? []
        return names.filter { $0.hasPrefix("catalog-") && $0.hasSuffix(".json") }.sorted(by: >).map { backups.appendingPathComponent($0) }
    }

    public struct Backup: Equatable, Sendable {
        public var url: URL
        public var assets: Int
        public var boards: Int
        public var name: String { url.lastPathComponent }
    }

    /// Readable snapshots with the counts the user sees before any restore. Unreadable snapshots are skipped.
    public static func backups(backups dir: URL, fm: FileManager = .default) -> [Backup] {
        snapshotURLs(backups: dir, fm: fm).compactMap { url in
            guard let data = try? Data(contentsOf: url), let c = StudioCatalog.decode(data), !c.assets.isEmpty else { return nil }
            return Backup(url: url, assets: c.assets.count, boards: c.boards.count)
        }
    }

    /// Replaces the catalog file with a snapshot. The file being replaced is kept first as
    /// studio-catalog.before-restore-<stamp>.json, so a restore never destroys the current state either.
    /// Returns the restored catalog and the kept copy, or nil with nothing changed.
    public static func restore(_ backup: Backup, catalogURL: URL, now: Date = Date(), fm: FileManager = .default) -> (catalog: StudioCatalog, kept: URL?)? {
        guard let data = try? Data(contentsOf: backup.url), let c = StudioCatalog.decode(data), !c.assets.isEmpty else { return nil }
        var kept: URL?
        if fm.fileExists(atPath: catalogURL.path) {
            let target = freeURL(dir: catalogURL.deletingLastPathComponent(), stem: "studio-catalog.before-restore-" + stamp(now), ext: "json", fm: fm)
            do { try fm.copyItem(at: catalogURL, to: target); kept = target } catch { return nil }
        }
        do { try data.write(to: catalogURL, options: .atomic) } catch { return nil }
        return (c, kept)
    }

    /// 1.91: a user-chosen file. Counts come from a full decode, so the preview is what a restore would load.
    public static func inspect(_ url: URL) -> Backup? {
        guard let data = try? Data(contentsOf: url), let c = StudioCatalog.decode(data), !c.assets.isEmpty else { return nil }
        return Backup(url: url, assets: c.assets.count, boards: c.boards.count)
    }

    /// 1.91: writes the in-memory catalog (including edits not yet saved) to a file the user chose, then reads it
    /// back and compares counts. Returns nil, and removes the partial file, when the copy cannot be verified.
    public static func export(_ catalog: StudioCatalog, to url: URL, fm: FileManager = .default) -> Backup? {
        guard let data = try? catalog.encoded(), (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        if let b = inspect(url), b.assets == catalog.assets.count, b.boards == catalog.boards.count { return b }
        try? fm.removeItem(at: url)
        return nil
    }

    public static func notice(original: String, preserved: URL?) -> String {
        if let preserved {
            return "Your library couldn't be read. The original is preserved as \(preserved.lastPathComponent). Nothing was overwritten."
        }
        return "Your library couldn't be read, and the original \(original) could not be moved aside. ASSSETS will not save until you restart or restore a backup."
    }
}
