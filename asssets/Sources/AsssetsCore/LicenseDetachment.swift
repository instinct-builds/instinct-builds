import Foundation

/// What a person reviewed before removing missing paperwork references. No file operation is implied.
public struct MissingLicenseDetachment: Equatable, Sendable, Identifiable {
    public struct Link: Equatable, Sendable, Identifiable {
        public let id: UUID
        public let name: String
        public let documentIDs: [UUID]
        public let rightsPreset: RightsPreset?
    }
    public struct Entry: Equatable, Sendable, Identifiable {
        public var id: UUID { document.id }
        public let document: LicenseDoc
        public let assets: [Link]
        public let presets: [Link]
    }

    public let entries: [Entry]
    public let allMissing: Bool
    public var id: UUID { entries[0].id }
    public var ids: Set<UUID> { Set(entries.map(\.id)) }
    public var assetLinkCount: Int { entries.reduce(0) { $0 + $1.assets.count } }
    public var presetLinkCount: Int { entries.reduce(0) { $0 + $1.presets.count } }

    /// `missing` is a current scan's missing record IDs, never a guessed path/name match.
    public init?(catalog: StudioCatalog, missing: [UUID], selected: UUID? = nil) {
        let scope = selected.map { [$0] } ?? missing
        guard !scope.isEmpty, Set(scope).count == scope.count,
              Set(scope).isSubset(of: Set(missing)) else { return nil }
        var gathered: [Entry] = []
        for id in scope {
            guard let doc = catalog.licenseDoc(id) else { return nil }
            let assets = catalog.assets.filter { $0.licenseDocs.contains(id) }.map { Link(id: $0.id, name: $0.title, documentIDs: $0.licenseDocs, rightsPreset: nil) }
            let presets = catalog.rightsPresets.filter { $0.docs.contains(id) }.map { Link(id: $0.id, name: $0.name, documentIDs: $0.docs, rightsPreset: $0) }
            guard !assets.isEmpty || !presets.isEmpty else { return nil }
            gathered.append(Entry(document: doc, assets: assets, presets: presets))
        }
        entries = gathered
        allMissing = selected == nil
    }

    /// Abort an entire reviewed batch on one stale record. An all-record review also rejects newly missing records.
    public func stillMatches(_ catalog: StudioCatalog, missing: [UUID]) -> Bool {
        guard let now = MissingLicenseDetachment(catalog: catalog, missing: missing,
                                                 selected: allMissing ? nil : entries[0].id) else { return false }
        return now == self
    }
}

extension StudioCatalog {
    /// Pure catalog edit; the caller checks disk and persists atomically before publishing the new catalog.
    @discardableResult
    public mutating func detachMissingLicenses(_ review: MissingLicenseDetachment, missing: [UUID]) -> Bool {
        guard review.stillMatches(self, missing: missing) else { return false }
        return forgetMissingLicenseFiles(review.ids) == review.entries.count
    }
}
