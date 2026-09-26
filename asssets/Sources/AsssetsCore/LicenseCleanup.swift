import Foundation

/// A pure review of exactly which unused records and stray stored names would leave the library.
public struct LicenseCleanupReview: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let unused: [LicenseDoc]
    public let stray: [String]
    /// Physical identity of reviewed regular files, captured before asking for deletion.
    public let files: [File]
    public struct File: Codable, Equatable, Sendable {
        public let name: String
        public let device: UInt64
        public let inode: UInt64
        public let bytes: UInt64
        public let digest: String
        public init(name: String, device: UInt64, inode: UInt64, bytes: UInt64, digest: String) {
            self.name = name; self.device = device; self.inode = inode; self.bytes = bytes; self.digest = digest
        }
    }
    public var count: Int { unused.count + stray.count }
    public init?(catalog: StudioCatalog, folder: [String], files: [File] = [], id: UUID = UUID()) {
        let docs = catalog.unusedLicenseDocs
        let known = Set(catalog.licenseDocs.map(\.stored))
        let extras = folder.filter { !$0.hasPrefix(".") && !known.contains($0) }.sorted()
        guard !docs.isEmpty || !extras.isEmpty else { return nil }
        self.id = id; unused = docs; stray = extras; self.files = files
    }
    public func stillMatches(_ catalog: StudioCatalog, folder: [String], files: [File]? = nil) -> Bool {
        guard let current = LicenseCleanupReview(catalog: catalog, folder: folder, files: files ?? self.files, id: id) else { return false }
        return current == self
    }
    /// Only removes the exact reviewed unused records; caller separately handles stored bytes.
    public func apply(to catalog: inout StudioCatalog, folder: [String]) -> Bool {
        guard stillMatches(catalog, folder: folder) else { return false }
        let ids = Set(unused.map(\.id))
        catalog.licenseDocs.removeAll { ids.contains($0.id) }
        return true
    }
}

/// Durable marker for a staged destructive operation; always kept beside the catalog.
public struct LicenseCleanupJournal: Codable, Equatable, Sendable {
    public enum Phase: String, Codable, Sendable { case staging, committed }
    public let id: UUID
    public var phase: Phase
    public let beforeDigest: String
    public let afterDigest: String
    /// The reviewed physical copies. A record with no copy is intentionally absent here.
    public let files: [LicenseCleanupReview.File]
    public let recordCount: Int
    public init(id: UUID, phase: Phase, beforeDigest: String, afterDigest: String,
                files: [LicenseCleanupReview.File], recordCount: Int) {
        self.id = id; self.phase = phase; self.beforeDigest = beforeDigest; self.afterDigest = afterDigest
        self.files = files; self.recordCount = recordCount
    }
    /// With a valid persisted catalog, recovery never guesses whether deletion was committed.
    public func recovery(for catalogDigest: String) -> Recovery {
        // A stray-only cleanup changes no catalog bytes: the durable phase settles the tie.
        if beforeDigest == afterDigest && catalogDigest == beforeDigest {
            return phase == .committed ? .purge : .restore
        }
        if catalogDigest == beforeDigest { return .restore }
        if catalogDigest == afterDigest { return .purge }
        return .manual
    }
    public enum Recovery: Equatable, Sendable { case restore, purge, manual }
}
