import Foundation

public enum LibraryError: Error {
    case importFailed(String)
    case notFound(UUID)
}

/// The user's local creative-asset library: their own files and properly
/// licensed assets. ASSSETS never ships or scrapes anyone else's database.
public struct Library: Codable, Sendable, Equatable {
    public private(set) var assets: [UUID: Asset]
    public var collections: [Collection]
    public var smartCollections: [SmartCollection]

    public init(assets: [UUID: Asset] = [:], collections: [Collection] = [],
                smartCollections: [SmartCollection] = []) {
        self.assets = assets
        self.collections = collections
        self.smartCollections = smartCollections
    }

    // Libraries saved before smart collections existed still decode.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        assets = try c.decode([UUID: Asset].self, forKey: .assets)
        collections = try c.decode([Collection].self, forKey: .collections)
        smartCollections = try c.decodeIfPresent([SmartCollection].self, forKey: .smartCollections) ?? []
    }

    /// Recursively import a folder. Re-importing the same path updates the
    /// existing asset instead of duplicating it.
    @discardableResult
    public mutating func importFolder(_ root: String) throws -> Int {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root, isDirectory: &isDir), isDir.boolValue else {
            throw LibraryError.importFailed("not a folder: \(root)")
        }
        guard let enumerator = fm.enumerator(atPath: root) else {
            throw LibraryError.importFailed("cannot enumerate: \(root)")
        }
        var count = 0
        var pathToID: [String: UUID] = [:]
        for a in assets.values { pathToID[a.path] = a.id }
        for case let rel as String in enumerator {
            let full = (root as NSString).appendingPathComponent(rel)
            guard let attrs = try? fm.attributesOfItem(atPath: full),
                  let type = attrs[.type] as? FileAttributeType, type == .typeRegular else { continue }
            let ext = (rel as NSString).pathExtension
            guard !ext.isEmpty else { continue }
            let kind = AssetKind.from(extension: ext)
            guard kind != .other else { continue }
            let size = (attrs[.size] as? Int64) ?? 0
            let dims = MetadataReader.dimensions(for: full, kind: kind)
            if let existing = pathToID[full], var a = assets[existing] {
                a.byteSize = size; a.width = dims?.0; a.height = dims?.1
                assets[a.id] = a
            } else {
                let a = Asset(path: full, kind: kind, byteSize: size, width: dims?.0, height: dims?.1)
                assets[a.id] = a
            }
            count += 1
        }
        return count
    }

    public mutating func removeAsset(_ id: UUID) throws {
        guard assets.removeValue(forKey: id) != nil else { throw LibraryError.notFound(id) }
        for i in collections.indices { collections[i].assetIDs.remove(id) }
    }

    /// Palette + thumbnail derivatives for image assets that lack them.
    /// Thumbnails are PNG files named <asset-id>.png under `thumbnailsDir`.
    /// Decodable formats only (PNG/BMP/PSD composite); other kinds keep
    /// header metadata and use QuickLook thumbnails in the macOS shell.
    @discardableResult
    public mutating func generateDerivatives(thumbnailsDir dir: String) -> Int {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        var made = 0
        for id in Array(assets.keys) {
            guard let asset = assets[id], asset.kind == .image || asset.kind == .psd else { continue }
            if asset.palette != nil && asset.thumbnailFile != nil { continue }
            let img = asset.kind == .psd ? PsdDecoder.decode(path: asset.path)
                                         : ImageDecoder.decode(path: asset.path)
            guard let img else { continue }
            var a = asset
            a.palette = PaletteExtractor.colors(from: img, count: 6).map(\.hex)
            let thumb = Thumbnailer.thumbnail(from: img, maxDim: 256)
            let file = (dir as NSString).appendingPathComponent("\(id.uuidString).png")
            if (try? PNGEncoder.encode(thumb).write(to: URL(fileURLWithPath: file), options: .atomic)) != nil {
                a.thumbnailFile = file
            }
            assets[id] = a
            made += 1
        }
        return made
    }

    // MARK: Tags

    public mutating func addTag(_ tag: String, to id: UUID) throws {
        guard var a = assets[id] else { throw LibraryError.notFound(id) }
        a.tags.insert(normalize(tag))
        assets[id] = a
    }

    public mutating func removeTag(_ tag: String, from id: UUID) throws {
        guard var a = assets[id] else { throw LibraryError.notFound(id) }
        a.tags.remove(normalize(tag))
        assets[id] = a
    }

    public var allTags: [String] {
        Array(Set(assets.values.flatMap(\.tags))).sorted()
    }

    // MARK: Collections

    @discardableResult
    public mutating func createCollection(_ name: String) -> UUID {
        let c = Collection(name: name)
        collections.append(c)
        return c.id
    }

    public mutating func addToCollection(_ assetID: UUID, collection id: UUID) throws {
        guard let i = collections.firstIndex(where: { $0.id == id }) else { throw LibraryError.notFound(id) }
        guard assets[assetID] != nil else { throw LibraryError.notFound(assetID) }
        collections[i].assetIDs.insert(assetID)
    }

    // MARK: Smart collections

    @discardableResult
    public mutating func createSmartCollection(name: String, query: Query) -> UUID {
        let sc = SmartCollection(name: name, query: query)
        smartCollections.append(sc)
        return sc.id
    }

    public mutating func deleteSmartCollection(_ id: UUID) throws {
        guard let i = smartCollections.firstIndex(where: { $0.id == id }) else {
            throw LibraryError.notFound(id)
        }
        smartCollections.remove(at: i)
    }

    /// Live membership: the query re-evaluates against the current library
    /// every call, so newly imported or retagged assets appear immediately.
    public func smartCollectionAssets(_ id: UUID) -> [Asset] {
        guard let sc = smartCollections.first(where: { $0.id == id }) else { return [] }
        return search(sc.query)
    }

    // MARK: Search

    public struct Query: Codable, Equatable, Sendable {
        public var text: String?
        public var kinds: Set<AssetKind>?
        public var requiredTags: Set<String>
        public var minMegapixels: Double?

        public init(text: String? = nil, kinds: Set<AssetKind>? = nil,
                    requiredTags: Set<String> = [], minMegapixels: Double? = nil) {
            self.text = text
            self.kinds = kinds
            self.requiredTags = requiredTags
            self.minMegapixels = minMegapixels
        }
    }

    public func search(_ q: Query) -> [Asset] {
        assets.values.filter { a in
            if let kinds = q.kinds, !kinds.contains(a.kind) { return false }
            if !q.requiredTags.isSubset(of: a.tags) { return false }
            if let mp = q.minMegapixels, (a.megapixels ?? 0) < mp { return false }
            if let text = q.text?.lowercased(), !text.isEmpty {
                let inName = a.filename.lowercased().contains(text)
                let inPath = a.path.lowercased().contains(text)
                let inTags = a.tags.contains { $0.contains(text) }
                if !inName && !inPath && !inTags { return false }
            }
            return true
        }.sorted { $0.filename < $1.filename }
    }

    private func normalize(_ tag: String) -> String {
        tag.trimmingCharacters(in: .whitespaces).lowercased()
    }
}

/// JSON persistence for the library. Dates keep fractional-second precision
/// so a save/load round-trip is exact.
public struct LibraryStore: Sendable {
    public let fileURL: URL
    public init(fileURL: URL) { self.fileURL = fileURL }

    public func save(_ library: Library) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .secondsSince1970 // exact Double round-trip
        try enc.encode(library).write(to: fileURL, options: .atomic)
    }

    public func load() throws -> Library {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .secondsSince1970
        return try dec.decode(Library.self, from: Data(contentsOf: fileURL))
    }
}
