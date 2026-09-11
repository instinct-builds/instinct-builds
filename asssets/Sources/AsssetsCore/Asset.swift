import Foundation

public enum AssetKind: String, Codable, CaseIterable, Sendable {
    case psd          // layered Photoshop document (user's own mockups)
    case illustrator  // .ai
    case vector       // .svg / .eps
    case image        // .png / .jpg / .gif / .webp / .tiff
    case video        // .mp4 / .mov / .webm
    case other

    public static func from(extension ext: String) -> AssetKind {
        switch ext.lowercased() {
        case "psd": return .psd
        case "ai": return .illustrator
        case "svg", "eps": return .vector
        case "png", "jpg", "jpeg", "gif", "webp", "tiff", "tif", "bmp": return .image
        case "mp4", "mov", "webm", "m4v": return .video
        default: return .other
        }
    }
}

public struct Asset: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID = UUID()
    public var path: String
    public var filename: String
    public var kind: AssetKind
    public var byteSize: Int64
    public var width: Int?
    public var height: Int?
    public var tags: Set<String>
    public var addedAt: Date
    /// Dominant colors as hex strings, from palette extraction. nil until derived.
    public var palette: [String]?
    /// PNG thumbnail under the library's thumbnails dir. nil until derived.
    public var thumbnailFile: String?

    public init(path: String, kind: AssetKind, byteSize: Int64,
                width: Int? = nil, height: Int? = nil,
                tags: Set<String> = [], addedAt: Date = Date(),
                palette: [String]? = nil, thumbnailFile: String? = nil) {
        self.path = path
        self.filename = (path as NSString).lastPathComponent
        self.kind = kind
        self.byteSize = byteSize
        self.width = width
        self.height = height
        self.tags = tags
        self.addedAt = addedAt
        self.palette = palette
        self.thumbnailFile = thumbnailFile
    }

    public var megapixels: Double? {
        guard let w = width, let h = height else { return nil }
        return Double(w * h) / 1_000_000.0
    }
}

public struct Collection: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID = UUID()
    public var name: String
    public var assetIDs: Set<UUID>

    public init(name: String, assetIDs: Set<UUID> = []) {
        self.name = name
        self.assetIDs = assetIDs
    }
}

/// A saved search: membership is computed live from the library, so a smart
/// collection always reflects the assets that currently match its query.
public struct SmartCollection: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID = UUID()
    public var name: String
    public var query: Library.Query

    public init(name: String, query: Library.Query) {
        self.name = name
        self.query = query
    }
}
