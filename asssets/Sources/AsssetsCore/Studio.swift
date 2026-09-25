import Foundation

// MARK: - Studio catalog model (shared by the app and the tests)

public enum MediaKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case image = "Images", vector = "Vectors", mockup = "Mockups", texture = "Textures", video = "Footage", audio = "Audio"
    public var id: String { rawValue }
    public var symbol: String {
        switch self {
        case .image: return "photo"
        case .vector: return "scribble.variable"
        case .mockup: return "square.3.layers.3d"
        case .texture: return "circle.hexagongrid"
        case .video: return "film"
        case .audio: return "waveform"
        }
    }
    public var singular: String {
        switch self {
        case .image: return "Image"
        case .vector: return "Vector"
        case .mockup: return "Mockup"
        case .texture: return "Texture"
        case .video: return "Footage"
        case .audio: return "Audio"
        }
    }

    /// Kind for a file extension, or nil when ASSSETS does not index that type.
    public static func classify(extension raw: String) -> MediaKind? {
        let ext = raw.lowercased()
        if ["png", "jpg", "jpeg", "heic", "tiff", "tif", "gif", "webp", "bmp"].contains(ext) { return .image }
        if ["svg", "ai", "eps", "pdf"].contains(ext) { return .vector }
        if ext == "psd" { return .mockup }
        if ["mov", "mp4", "m4v", "webm"].contains(ext) { return .video }
        if ["wav", "aif", "aiff", "mp3", "m4a"].contains(ext) { return .audio }
        return nil
    }
}

public struct StudioAsset: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var title: String
    public var kind: MediaKind
    public var tags: [String]
    public var collection: String
    public var palette: [String]
    public var seed: Int
    public var favorite: Bool
    public var importedPath: String?
    public var resolution: String
    /// Stable identity for bundled content ("starter:<file>", "generated:<collection>:<n>").
    /// nil for the user's own imports. Added in 0.4; absent in 0.3 catalogs.
    public var sourceKey: String?
    /// Tags ASSSETS computed from pixels and metadata (1.6). Searchable, but only shown as suggestions until accepted.
    public var autoTags: [String] = []
    /// Suggestions the user dismissed; never suggested or matched again for this asset.
    public var rejectedTags: [String] = []
    /// Notes clients left in a review gallery (1.9), one per reviewer per gallery.
    public var clientNotes: [ClientNote] = []
    /// Version stack this asset belongs to (1.10); nil when it stands alone.
    public var stackID: UUID? = nil
    /// Set when the user unstacked it; auto-detection then leaves it alone.
    public var unstacked = false
    /// Star rating, 0 (unrated) to 5 (1.11).
    public var rating = 0
    /// Color label (1.11).
    public var label: ColorLabel? = nil
    /// Usage rights and credit (1.25); nil when nobody entered any.
    public var rights: UsageRights? = nil
    /// License documents attached to this asset (1.27), ids into `StudioCatalog.licenseDocs`.
    public var licenseDocs: [UUID] = []
    /// Original sources and settings of a rendered mockup (1.30); old renders remain flat.
    public var placementRecipe: PlacementRecipe? = nil

    public init(id: UUID = UUID(), title: String, kind: MediaKind, tags: [String], collection: String,
                palette: [String], seed: Int, favorite: Bool = false, importedPath: String? = nil,
                resolution: String, sourceKey: String? = nil) {
        self.id = id; self.title = title; self.kind = kind; self.tags = tags; self.collection = collection
        self.palette = palette; self.seed = seed; self.favorite = favorite; self.importedPath = importedPath
        self.resolution = resolution; self.sourceKey = sourceKey
    }

    enum CodingKeys: String, CodingKey { case id, title, kind, tags, collection, palette, seed, favorite, importedPath, resolution, sourceKey, autoTags, rejectedTags, clientNotes, stackID, unstacked, rating, label, rights, licenseDocs, placementRecipe }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        kind = try c.decode(MediaKind.self, forKey: .kind)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        collection = try c.decodeIfPresent(String.self, forKey: .collection) ?? StudioCatalog.importedCollection
        palette = try c.decodeIfPresent([String].self, forKey: .palette) ?? []
        seed = try c.decodeIfPresent(Int.self, forKey: .seed) ?? 0
        favorite = try c.decodeIfPresent(Bool.self, forKey: .favorite) ?? false
        importedPath = try c.decodeIfPresent(String.self, forKey: .importedPath)
        resolution = try c.decodeIfPresent(String.self, forKey: .resolution) ?? ""
        sourceKey = try c.decodeIfPresent(String.self, forKey: .sourceKey)
        autoTags = try c.decodeIfPresent([String].self, forKey: .autoTags) ?? []
        rejectedTags = try c.decodeIfPresent([String].self, forKey: .rejectedTags) ?? []
        clientNotes = try c.decodeIfPresent([ClientNote].self, forKey: .clientNotes) ?? []
        stackID = try c.decodeIfPresent(UUID.self, forKey: .stackID)
        unstacked = try c.decodeIfPresent(Bool.self, forKey: .unstacked) ?? false
        rating = min(5, max(0, try c.decodeIfPresent(Int.self, forKey: .rating) ?? 0))
        label = try? c.decodeIfPresent(ColorLabel.self, forKey: .label)
        rights = try? c.decodeIfPresent(UsageRights.self, forKey: .rights)
        licenseDocs = (try? c.decodeIfPresent([UUID].self, forKey: .licenseDocs)) ?? []
        placementRecipe = try? c.decodeIfPresent(PlacementRecipe.self, forKey: .placementRecipe)
    }

    /// Auto tags still waiting for the user: not already a real tag, not dismissed.
    public var suggestedTags: [String] { autoTags.filter { !tags.contains($0) && !rejectedTags.contains($0) } }
    /// What search and smart rules match against: the user's tags plus pending suggestions.
    public var searchTags: [String] { tags + suggestedTags }

    public var isStarter: Bool { sourceKey?.hasPrefix("starter:") ?? false }
}

public struct MergeReport: Equatable, Sendable {
    public var added = 0
    public var adopted = 0
    public var relinked = 0
    public var unchanged = 0
    public init() {}
}

public struct StudioCatalog: Codable, Equatable, Sendable {
    public static let allAssets = "All Assets"
    public static let favorites = "Favorites"
    public static let importedCollection = "Imported"
    public static let currentSchema = 2

    public var schemaVersion: Int = StudioCatalog.currentSchema
    public var assets: [StudioAsset] = []
    /// Collections the user created, kept even while empty so they stay drop targets.
    public var userCollections: [String] = []
    /// Fingerprint of the bundled starter archive last merged into this catalog.
    public var starterFingerprint: String?
    /// Bundled records the user removed; upgrades never bring them back.
    public var dismissedKeys: [String] = []
    /// Rule-based collections whose membership is recomputed live (0.5).
    public var smartCollections: [StudioSmartCollection] = []
    /// Whether the starter smart collections were offered already.
    public var smartSeeded = false
    /// Whether the rights smart collections (1.25) were added already.
    public var rightsSeeded = false
    /// Folders ASSSETS watches for new files (1.2). New files land in the Inbox collection.
    public var watchFolders: [String] = []
    /// Grid sort per collection or smart collection (1.12); missing means date added.
    public var viewSorts: [String: AssetSort] = [:]
    /// Colors searched lately, newest first (1.15).
    public var recentColors: [String] = []
    /// Moodboards (1.16).
    public var boards: [Moodboard] = []
    /// Board templates the user saved (1.22). The built-in ones live in code, see `BoardTemplate.builtIns`.
    public var templates: [BoardTemplate] = []
    /// License documents stored in the library (1.27).
    public var licenseDocs: [LicenseDoc] = []
    /// Saved rights presets (1.27).
    public var rightsPresets: [RightsPreset] = []

    enum CodingKeys: String, CodingKey { case schemaVersion, assets, userCollections, starterFingerprint, dismissedKeys, smartCollections, smartSeeded, rightsSeeded, watchFolders, viewSorts, recentColors, boards, templates, licenseDocs, rightsPresets }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? StudioCatalog.currentSchema
        assets = try c.decode([StudioAsset].self, forKey: .assets)
        userCollections = try c.decodeIfPresent([String].self, forKey: .userCollections) ?? []
        starterFingerprint = try c.decodeIfPresent(String.self, forKey: .starterFingerprint)
        dismissedKeys = try c.decodeIfPresent([String].self, forKey: .dismissedKeys) ?? []
        smartCollections = try c.decodeIfPresent([StudioSmartCollection].self, forKey: .smartCollections) ?? []
        smartSeeded = try c.decodeIfPresent(Bool.self, forKey: .smartSeeded) ?? false
        rightsSeeded = try c.decodeIfPresent(Bool.self, forKey: .rightsSeeded) ?? false
        watchFolders = try c.decodeIfPresent([String].self, forKey: .watchFolders) ?? []
        viewSorts = ((try? c.decodeIfPresent([String: String].self, forKey: .viewSorts)) ?? [:]).compactMapValues(AssetSort.init(rawValue:))
        recentColors = ((try? c.decodeIfPresent([String].self, forKey: .recentColors)) ?? []).compactMap(ColorSearch.normalize)
        boards = (try? c.decodeIfPresent([Moodboard].self, forKey: .boards)) ?? []
        templates = ((try? c.decodeIfPresent([BoardTemplate].self, forKey: .templates)) ?? []).filter { !$0.builtIn }
        licenseDocs = (try? c.decodeIfPresent([LicenseDoc].self, forKey: .licenseDocs)) ?? []
        rightsPresets = (try? c.decodeIfPresent([RightsPreset].self, forKey: .rightsPresets)) ?? []
    }

    public init(assets: [StudioAsset] = [], userCollections: [String] = [], starterFingerprint: String? = nil) {
        self.assets = assets; self.userCollections = userCollections; self.starterFingerprint = starterFingerprint
    }

    // MARK: Persistence and legacy migration

    /// Decodes a 0.4 catalog, or migrates a 0.3 `studio-library.json` (a bare array of assets).
    public static func decode(_ data: Data) -> StudioCatalog? {
        let decoder = JSONDecoder()
        if var catalog = try? decoder.decode(StudioCatalog.self, from: data) {
            catalog.schemaVersion = currentSchema
            catalog.normalize()
            return catalog
        }
        if let legacy = try? decoder.decode([StudioAsset].self, from: data) {
            var catalog = StudioCatalog(assets: legacy)
            catalog.normalize()
            return catalog
        }
        return nil
    }

    public func encoded() throws -> Data {
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]
        return try e.encode(self)
    }

    /// Removes duplicate IDs, duplicate file paths and duplicate bundled keys; first record wins.
    public mutating func normalize() {
        var ids = Set<UUID>(), paths = Set<String>(), keys = Set<String>()
        assets = assets.filter { a in
            if ids.contains(a.id) { return false }
            if let p = a.importedPath, paths.contains(p) { return false }
            if let k = a.sourceKey, keys.contains(k) { return false }
            ids.insert(a.id); if let p = a.importedPath { paths.insert(p) }; if let k = a.sourceKey { keys.insert(k) }
            return true
        }
        var seen = Set<String>()
        userCollections = userCollections.filter { !$0.isEmpty && !Self.reserved($0) && seen.insert($0).inserted }
    }

    static func reserved(_ name: String) -> Bool { name == allAssets || name == favorites }

    // MARK: Browsing

    public var collections: [String] {
        [Self.allAssets, Self.favorites] + Array(Set(assets.map(\.collection)).union(userCollections)).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    public func count(in collection: String) -> Int {
        switch collection {
        case Self.allAssets: return assets.count
        case Self.favorites: return assets.filter(\.favorite).count
        default: return assets.filter { $0.collection == collection }.count
        }
    }

    public func filtered(search: String, kind: MediaKind?, collection: String) -> [StudioAsset] {
        let terms = search.lowercased().split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
        return assets.filter { a in
            guard kind == nil || a.kind == kind else { return false }
            switch collection {
            case Self.allAssets: break
            case Self.favorites: guard a.favorite else { return false }
            default: guard a.collection == collection else { return false }
            }
            let hay = ([a.title, a.kind.rawValue, a.collection, a.resolution] + a.searchTags + a.palette).joined(separator: " ").lowercased()
            return terms.allSatisfy(hay.contains)
        }
    }

    /// Tags shared by every asset in the set (for the batch inspector).
    public func commonTags(_ ids: Set<UUID>) -> [String] {
        let picked = assets.filter { ids.contains($0.id) }
        guard var common = picked.first.map({ Set($0.tags) }) else { return [] }
        for a in picked.dropFirst() { common.formIntersection(a.tags) }
        return common.sorted()
    }

    // MARK: Batch edits

    public static func parseTags(_ raw: String) -> [String] {
        var out: [String] = []
        for piece in raw.split(separator: ",") {
            let t = piece.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !t.isEmpty && !out.contains(t) { out.append(t) }
        }
        return out
    }

    /// Adds comma-separated tags to every asset in `ids`. Returns how many assets changed.
    @discardableResult
    public mutating func addTags(_ raw: String, to ids: Set<UUID>) -> Int {
        let tags = Self.parseTags(raw)
        guard !tags.isEmpty else { return 0 }
        var changed = 0
        for i in assets.indices where ids.contains(assets[i].id) {
            let before = assets[i].tags.count
            for t in tags where !assets[i].tags.contains(t) { assets[i].tags.append(t) }
            if assets[i].tags.count != before { changed += 1 }
        }
        return changed
    }

    @discardableResult
    public mutating func removeTag(_ tag: String, from ids: Set<UUID>) -> Int {
        var changed = 0
        for i in assets.indices where ids.contains(assets[i].id) {
            let before = assets[i].tags.count
            assets[i].tags.removeAll { $0 == tag }
            if assets[i].tags.count != before { changed += 1 }
        }
        return changed
    }

    /// Favorites all when any is not a favorite, otherwise clears them all (Finder-style toggle).
    public mutating func toggleFavorite(_ ids: Set<UUID>) {
        let picked = assets.filter { ids.contains($0.id) }
        guard !picked.isEmpty else { return }
        let target = picked.contains { !$0.favorite }
        for i in assets.indices where ids.contains(assets[i].id) { assets[i].favorite = target }
    }

    /// Moves assets into a collection (the drag-to-collection drop). Returns how many moved.
    @discardableResult
    public mutating func move(_ ids: Set<UUID>, to collection: String) -> Int {
        let name = collection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != Self.allAssets else { return 0 }
        if name == Self.favorites {
            var n = 0
            for i in assets.indices where ids.contains(assets[i].id) && !assets[i].favorite { assets[i].favorite = true; n += 1 }
            return n
        }
        var moved = 0
        for i in assets.indices where ids.contains(assets[i].id) && assets[i].collection != name {
            assets[i].collection = name; moved += 1
        }
        if !userCollections.contains(name) && !assets.contains(where: { $0.collection == name && !ids.contains($0.id) }) {
            userCollections.append(name)
        }
        return moved
    }

    /// Creates an empty user collection with a unique name and returns it.
    public mutating func createCollection(named base: String = "New Collection") -> String {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let root = trimmed.isEmpty || Self.reserved(trimmed) ? "New Collection" : trimmed
        var name = root, n = 2
        while collections.contains(name) { name = "\(root) \(n)"; n += 1 }
        userCollections.append(name)
        return name
    }

    @discardableResult
    public mutating func renameCollection(_ old: String, to new: String) -> Bool {
        let name = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !Self.reserved(old), !name.isEmpty, !Self.reserved(name), name != old, !collections.contains(name) else { return false }
        for i in assets.indices where assets[i].collection == old { assets[i].collection = name }
        for i in smartCollections.indices where smartCollections[i].rules.collection == old { smartCollections[i].rules.collection = name }
        userCollections = userCollections.map { $0 == old ? name : $0 }
        if !userCollections.contains(name) && collections.contains(name) == false { userCollections.append(name) }
        return true
    }

    /// Removes assets from the catalog. Files on disk are never touched.
    @discardableResult
    public mutating func remove(_ ids: Set<UUID>) -> Int {
        let before = assets.count
        for a in assets where ids.contains(a.id) {
            if let k = a.sourceKey, !dismissedKeys.contains(k) { dismissedKeys.append(k) }
            // Remember removed watched files so the next folder scan does not bring them back.
            if a.sourceKey == nil, let p = a.importedPath, isWatched(p), !dismissedKeys.contains("file:" + p) { dismissedKeys.append("file:" + p) }
        }
        assets.removeAll { ids.contains($0.id) }
        for i in boards.indices { boards[i].forgetAssets(ids) }
        return before - assets.count
    }

    // MARK: Imports

    /// Adds a local file. Returns the new asset ID, or nil for unsupported or already indexed files.
    @discardableResult
    public mutating func importFile(path: String, collection: String = StudioCatalog.importedCollection) -> UUID? {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()
        guard let kind = MediaKind.classify(extension: ext), !assets.contains(where: { $0.importedPath == path }) else { return nil }
        dismissedKeys.removeAll { $0 == "file:" + path }   // an explicit import wins over an earlier removal
        let asset = StudioAsset(title: Self.humanize(url.deletingPathExtension().lastPathComponent), kind: kind,
                                tags: [ext, "imported"], collection: collection,
                                palette: Self.placeholderPalette, seed: Self.stableSeed(path),
                                importedPath: path, resolution: "Local file")
        assets.insert(asset, at: 0)
        return asset.id
    }

    // MARK: Watch folders (1.2)

    public static let inboxCollection = "Inbox"

    /// Adds a folder to the watch list. Returns false when it is already covered (same folder or inside a watched one).
    @discardableResult
    public mutating func addWatchFolder(_ path: String) -> Bool {
        let p = Self.folderKey(path)
        if watchFolders.contains(where: { p == $0 || p.hasPrefix($0 + "/") }) { return false }
        watchFolders.removeAll { $0.hasPrefix(p + "/") }   // a parent replaces its subfolders
        watchFolders.append(p)
        return true
    }

    public mutating func removeWatchFolder(_ path: String) { let p = Self.folderKey(path); watchFolders.removeAll { $0 == p } }

    public func isWatched(_ file: String) -> Bool { watchFolders.contains { file.hasPrefix($0 + "/") } }

    /// Imports newly found files from watch folders into the Inbox. Idempotent: files already indexed
    /// (anywhere in the library), removed by the user, hidden, or unsupported are skipped.
    @discardableResult
    public mutating func syncWatch(found: [String]) -> [UUID] {
        var added: [UUID] = []
        for path in found.sorted() where isWatched(path) {
            let rel = watchFolders.first { path.hasPrefix($0 + "/") }.map { String(path.dropFirst($0.count + 1)) } ?? path
            if rel.split(separator: "/").contains(where: { $0.hasPrefix(".") }) { continue }
            if dismissedKeys.contains("file:" + path) { continue }
            let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
            guard MediaKind.classify(extension: ext) != nil, !assets.contains(where: { $0.importedPath == path }) else { continue }
            let url = URL(fileURLWithPath: path)
            let asset = StudioAsset(title: Self.humanize(url.deletingPathExtension().lastPathComponent), kind: MediaKind.classify(extension: ext)!,
                                    tags: [ext, "imported", "watched"], collection: Self.inboxCollection,
                                    palette: Self.placeholderPalette, seed: Self.stableSeed(path),
                                    importedPath: path, resolution: "Local file")
            assets.insert(asset, at: 0)
            added.append(asset.id)
        }
        return added
    }

    /// The user's own files whose path no longer exists. Bundled files are repaired on launch, so they never count.
    public func missingIDs(exists: (String) -> Bool) -> Set<UUID> {
        Set(assets.filter { !$0.isStarter }.compactMap { a in a.importedPath.flatMap { exists($0) ? nil : a.id } })
    }

    static func folderKey(_ path: String) -> String {
        var p = path
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        return p
    }

    // MARK: Bundled starter library

    /// Merges the bundled starter files into the catalog. Idempotent: running it again adds nothing.
    /// - Existing starter records keep favorites, tags and collection moves; only their path is relinked.
    /// - 0.3 records (same path, no sourceKey, still in "Imported") are adopted into their proper collection.
    @discardableResult
    public mutating func mergeStarter(files: [String], root: String, fingerprint: String) -> MergeReport {
        var report = MergeReport()
        let base = root.hasSuffix("/") ? String(root.dropLast()) : root
        for name in files.sorted() {
            guard let spec = StarterCatalog.describe(filename: name) else { continue }
            let key = "starter:\(name)"
            let path = base + "/" + name
            if dismissedKeys.contains(key) { continue }
            if let i = assets.firstIndex(where: { $0.sourceKey == key }) {
                if assets[i].importedPath != path { assets[i].importedPath = path; report.relinked += 1 } else { report.unchanged += 1 }
            } else if let i = assets.firstIndex(where: { $0.importedPath == path || ($0.sourceKey == nil && $0.importedPath.map { URL(fileURLWithPath: $0).lastPathComponent == name && $0.contains("/StarterLibrary/") } == true) }) {
                assets[i].sourceKey = key
                assets[i].importedPath = path
                if assets[i].collection == Self.importedCollection {
                    assets[i].collection = spec.collection
                    assets[i].title = spec.title
                    assets[i].kind = spec.kind
                    assets[i].resolution = spec.resolution
                    assets[i].palette = spec.palette
                    let userTags = assets[i].tags.filter { $0 != "imported" && $0 != URL(fileURLWithPath: name).pathExtension.lowercased() }
                    var tags = spec.tags
                    for t in userTags where !tags.contains(t) { tags.append(t) }
                    assets[i].tags = tags
                }
                report.adopted += 1
            } else {
                assets.append(StudioAsset(title: spec.title, kind: spec.kind, tags: spec.tags, collection: spec.collection,
                                          palette: spec.palette, seed: Self.stableSeed(name), importedPath: path,
                                          resolution: spec.resolution, sourceKey: key))
                report.added += 1
            }
        }
        starterFingerprint = fingerprint
        normalize()
        return report
    }

    /// Adds the generated original studies once (keyed so upgrades never duplicate them).
    @discardableResult
    public mutating func mergeGenerated() -> Int {
        let hasLegacyGenerated = assets.contains { $0.sourceKey == nil && $0.importedPath == nil }
        if hasLegacyGenerated {
            // 0.3 catalogs already hold the generated studies without keys; tag them instead of adding copies.
            var byCollection: [String: Int] = [:]
            for i in assets.indices where assets[i].sourceKey == nil && assets[i].importedPath == nil {
                let n = byCollection[assets[i].collection, default: 0]
                byCollection[assets[i].collection] = n + 1
                assets[i].sourceKey = "generated:\(assets[i].collection):\(n)"
            }
            normalize()
            return 0
        }
        var added = 0
        for g in StarterCatalog.generated() where !assets.contains(where: { $0.sourceKey == g.sourceKey }) && !dismissedKeys.contains(g.sourceKey ?? "") {
            assets.append(g); added += 1
        }
        return added
    }

    /// Whether the bundled archive must be expanded again on this launch.
    public static func needsExtraction(installedFingerprint: String?, bundledFingerprint: String, rootExists: Bool, missingFiles: Int) -> Bool {
        !rootExists || installedFingerprint != bundledFingerprint || missingFiles > 0
    }

    /// Keeps titles and tags honest about pixel size: a "4K" label stays only on files at least 3840 px wide or tall.
    public static func correctResolutionClaims(_ asset: inout StudioAsset, width: Int, height: Int) {
        let longest = max(width, height)
        guard longest > 0, longest < 3840 else { return }
        let label = longest >= 1920 ? "2K" : nil
        let words = asset.title.split(separator: " ").map(String.init)
        if words.contains(where: { $0.uppercased() == "4K" }) {
            asset.title = words.compactMap { $0.uppercased() == "4K" ? label : $0 }.joined(separator: " ")
        }
        if let i = asset.tags.firstIndex(of: "4k") {
            if let label, !asset.tags.contains(label.lowercased()) { asset.tags[i] = label.lowercased() } else { asset.tags.remove(at: i) }
        }
    }

    public static func humanize(_ stem: String) -> String {
        stem.split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == " " }).map { word -> String in
            let w = String(word)
            if w.lowercased() == "4k" { return "4K" }
            if w.allSatisfy(\.isNumber) { return w }
            return w.prefix(1).uppercased() + w.dropFirst().lowercased()
        }.joined(separator: " ")
    }

    public static func stableSeed(_ s: String) -> Int {
        var h: UInt64 = 1469598103934665603
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return Int(h % 1_000_000)
    }
}

// MARK: - Bundled content description

public enum StarterCatalog {
    public struct Spec: Equatable, Sendable {
        public var title: String, kind: MediaKind, collection: String, tags: [String], palette: [String], resolution: String
    }

    static let groups: [(MediaKind, String, [String], [String], String)] = [
        (.mockup, "Device Mockups", ["phone", "laptop", "screen", "presentation"], ["#101319", "#596273", "#DCE4F2", "#8C5CFF"], "6000 × 4000"),
        (.vector, "Editorial Vectors", ["geometric", "editorial", "brand", "scalable"], ["#14162B", "#EF476F", "#FFD166", "#06D6A0"], "SVG • infinite"),
        (.texture, "Material Textures", ["paper", "grain", "concrete", "overlay"], ["#1E2025", "#72665A", "#CDBDA7", "#F0E7DC"], "4096 × 4096"),
        (.image, "Studio Photography", ["product", "still life", "campaign", "photo"], ["#0A0B0F", "#315F74", "#E1A66E", "#F7E9D2"], "7200 × 4800"),
        (.video, "Motion Loops", ["loop", "abstract", "4k", "motion"], ["#090C22", "#3157FF", "#00C2FF", "#E7F0FF"], "4K • 00:12"),
        (.audio, "Sound Beds", ["ambient", "cinematic", "loop", "stereo"], ["#111318", "#28324A", "#C25BFF", "#F2CAFF"], "48 kHz • 00:24"),
    ]

    /// Describes a physical file from the bundled archive, placing it in the matching collection.
    public static func describe(filename: String) -> Spec? {
        let url = URL(fileURLWithPath: filename)
        let ext = url.pathExtension.lowercased()
        let stem = url.deletingPathExtension().lastPathComponent.lowercased()
        guard !filename.hasPrefix("."), let baseKind = MediaKind.classify(extension: ext) else { return nil }
        let title = StudioCatalog.humanize(url.deletingPathExtension().lastPathComponent)
        var kind = baseKind, collection: String, tags: [String], palette: [String], res: String
        if stem.contains("mockup") {
            kind = .mockup; collection = "Device Mockups"; tags = ["mockup", "smart object", "scene"]; palette = groups[0].3; res = "Layered scene"
        } else if baseKind == .vector {
            collection = "Editorial Vectors"; tags = ["vector", "geometric", "editorial"]; palette = groups[1].3; res = "SVG • 1200 × 800"
        } else if stem.hasSuffix("4k") || stem.contains("texture") {
            kind = .texture; collection = "Material Textures"; tags = ["texture", "4k", "seamless"]; palette = groups[2].3; res = "4096 × 4096"
        } else if baseKind == .video {
            collection = "Motion Loops"; tags = ["footage", "loop", "motion"]; palette = groups[4].3; res = "MP4 loop"
        } else if baseKind == .audio {
            collection = "Sound Beds"; tags = ["audio", "ambient", "bed"]; palette = groups[5].3; res = "WAV • 44.1 kHz"
        } else {
            collection = "Studio Photography"; tags = ["photo"]; palette = groups[3].3; res = "Image"
        }
        tags.append(contentsOf: ["original", "bundled", ext])
        for word in stem.split(separator: "-").map(String.init) where word.count > 2 && !word.allSatisfy(\.isNumber) && !tags.contains(word) && word != "mockup" {
            tags.append(word)
        }
        return Spec(title: title, kind: kind, collection: collection, tags: tags, palette: palette, resolution: res)
    }

    /// The 72 generated original studies shipped since 0.2, now with stable keys.
    public static func generated() -> [StudioAsset] {
        let nouns = ["Aurora", "Obsidian", "Halo", "Monolith", "Prism", "Tidal", "Sienna", "Signal", "Flux", "Afterglow", "Orbit", "Nocturne"]
        var out: [StudioAsset] = []
        for (g, (kind, collection, tags, palette, res)) in groups.enumerated() {
            for i in 0..<12 {
                let suffix = kind == .audio ? "Sound" : kind == .video ? "Loop" : kind == .mockup ? "Scene" : "Study"
                let shift = i % palette.count
                out.append(StudioAsset(title: "\(nouns[i]) \(suffix)", kind: kind, tags: tags + [i % 2 == 0 ? "minimal" : "bold", "original"],
                                       collection: collection, palette: Array(palette[shift...] + palette[..<shift]), seed: g * 101 + i * 17,
                                       favorite: i == 0, resolution: res, sourceKey: "generated:\(collection):\(i)"))
            }
        }
        return out
    }
}
