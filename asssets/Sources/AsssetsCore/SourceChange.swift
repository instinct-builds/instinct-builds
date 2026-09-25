import Foundation

/// Stable baseline of a user-owned source. Size and modification time are a cheap gate;
/// the content hash resolves a changed timestamp without false alarms.
public struct SourceFingerprint: Codable, Hashable, Sendable {
    public let size: Int64
    public let modified: TimeInterval
    public let sha256: String
    public init(size: Int64, modified: TimeInterval, sha256: String) {
        self.size = size; self.modified = modified; self.sha256 = sha256
    }
    public func status(against current: SourceFingerprint) -> SourceChangeStatus {
        if sha256 != current.sha256 { return .changed }
        return size == current.size && modified == current.modified ? .unchanged : .timestampOnly
    }
}

public enum SourceChangeStatus: Equatable, Sendable { case unchanged, timestampOnly, changed }

extension StudioCatalog {
    /// Records a baseline only for the same path, never replacing a known baseline during a scan.
    @discardableResult
    public mutating func seedSourceFingerprint(_ fingerprint: SourceFingerprint, for id: UUID, path: String) -> Bool {
        guard let i = assets.firstIndex(where: { $0.id == id && $0.importedPath == path && !$0.isStarter }),
              assets[i].sourceFingerprint == nil else { return false }
        assets[i].sourceFingerprint = fingerprint
        return true
    }

    /// A timestamp-only touch is not a content change; advance the cheap baseline silently.
    @discardableResult
    public mutating func acceptTimestampOnly(_ fingerprint: SourceFingerprint, for id: UUID, path: String) -> Bool {
        guard let i = assets.firstIndex(where: { $0.id == id && $0.importedPath == path }),
              let old = assets[i].sourceFingerprint, old.status(against: fingerprint) == .timestampOnly else { return false }
        assets[i].sourceFingerprint = fingerprint
        return true
    }

    /// The user has reviewed this replacement and explicitly requested a refresh.
    @discardableResult
    public mutating func acceptChangedSource(_ fingerprint: SourceFingerprint, for id: UUID, path: String,
                                             palette: [String]?, resolution: String?) -> Bool {
        guard let i = assets.firstIndex(where: { $0.id == id && $0.importedPath == path && !$0.isStarter }),
              let old = assets[i].sourceFingerprint, old.sha256 != fingerprint.sha256 else { return false }
        assets[i].sourceFingerprint = fingerprint
        if let palette { assets[i].palette = palette }
        if let resolution { assets[i].resolution = resolution }
        assets[i].autoTags = []
        return true
    }
}
