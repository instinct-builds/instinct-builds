import Foundation

/// Library Health (1.28): one place that lists what needs attention in the library.
/// The app supplies file checks; this is the pure, tested logic around them.
public struct LibraryHealth: Equatable, Sendable {
    public struct BigFile: Equatable, Sendable {
        public var id: UUID
        public var bytes: Int64
        public init(id: UUID, bytes: Int64) { self.id = id; self.bytes = bytes }
    }

    /// The user's own files that have moved or been deleted.
    public var missingFiles: [UUID] = []
    /// Files whose bytes changed since their reviewed baseline, not just their timestamp.
    public var changedSources: [UUID] = []
    /// License files no asset or preset uses any more.
    public var unusedLicenseFiles: [UUID] = []
    /// Files in the Licenses folder that no license record points at (left behind by a crash or a copied library).
    public var strayLicenseFiles: [String] = []
    /// License file records whose stored copy is gone from the Licenses folder.
    public var missingLicenseFiles: [UUID] = []
    /// The user's own files at or over `bigFileBytes`, largest first.
    public var bigFiles: [BigFile] = []
    /// Licensed, client-supplied or editorial assets with no credit line.
    public var noCredit: [UUID] = []
    /// Sets of identical files, when a duplicate scan has run.
    public var duplicateSets: Int? = nil

    public static let bigFileBytes: Int64 = 200 * 1024 * 1024

    public init() {}

    /// Unused records plus stray files: everything Clean Up would delete.
    public var licenseCleanupCount: Int { unusedLicenseFiles.count + strayLicenseFiles.count }
    /// Every problem counted once: each missing file, unused or missing license file, big file and uncredited asset,
    /// plus each duplicate set.
    public var issueCount: Int {
        missingFiles.count + changedSources.count + unusedLicenseFiles.count + strayLicenseFiles.count + missingLicenseFiles.count + bigFiles.count + noCredit.count + (duplicateSets ?? 0)
    }
    public var isHealthy: Bool { issueCount == 0 }
    /// Problems that stop something working (a file you can't open, paperwork you can't show) rather than tidy-ups.
    public var urgentCount: Int { missingFiles.count + missingLicenseFiles.count }
}

extension StudioCatalog {
    /// Builds the health report. `exists` checks an asset's file path; `licenseExists` checks a license file's stored copy;
    /// `licenseFolder` lists the file names in the Licenses folder; `sizes` gives byte sizes for the user's own files (bundled media is never flagged as big).
    public func health(exists: (String) -> Bool, licenseExists: (LicenseDoc) -> Bool,
                       licenseFolder: [String] = [], sizes: [UUID: Int64] = [:], duplicateSets: Int? = nil,
                       bigFileBytes: Int64 = LibraryHealth.bigFileBytes) -> LibraryHealth {
        var h = LibraryHealth()
        let missing = missingIDs(exists: exists)
        h.missingFiles = assets.map(\.id).filter(missing.contains)
        h.unusedLicenseFiles = unusedLicenseDocs.map(\.id)
        var used = Set(assets.flatMap(\.licenseDocs))
        used.formUnion(rightsPresets.flatMap(\.docs))
        let known = Set(licenseDocs.map(\.stored))
        h.strayLicenseFiles = licenseFolder.filter { !$0.hasPrefix(".") && !known.contains($0) }.sorted()
        h.missingLicenseFiles = licenseDocs.filter { used.contains($0.id) && !licenseExists($0) }.map(\.id)
        let own = Set(assets.filter { !$0.isStarter }.map(\.id))
        h.bigFiles = sizes.filter { own.contains($0.key) && $0.value >= bigFileBytes && !missing.contains($0.key) }
            .map { LibraryHealth.BigFile(id: $0.key, bytes: $0.value) }
            .sorted { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.id.uuidString < $1.id.uuidString }
        h.noCredit = assets.filter { a in
            guard let r = a.rights, r.license != .own else { return false }
            return r.credit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.map(\.id)
        h.duplicateSets = duplicateSets
        return h
    }

    /// Detaches license file records whose stored copy is gone, from every asset and preset. Returns how many records went.
    @discardableResult
    public mutating func forgetMissingLicenseFiles(_ ids: Set<UUID>) -> Int {
        guard !ids.isEmpty else { return 0 }
        for i in assets.indices { assets[i].licenseDocs.removeAll { ids.contains($0) } }
        for i in rightsPresets.indices { rightsPresets[i].docs.removeAll { ids.contains($0) } }
        let before = licenseDocs.count
        licenseDocs.removeAll { ids.contains($0.id) }
        return before - licenseDocs.count
    }
}
