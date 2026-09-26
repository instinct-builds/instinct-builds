import Foundation

/// An exact review boundary for restoring a missing stored license copy.
/// The source file's bytes are checked separately by the app immediately before commit.
public struct MissingLicenseRepair: Equatable, Sendable {
    public let document: LicenseDoc
    public let assetIDs: [UUID]
    public let presetIDs: [UUID]

    public init?(catalog: StudioCatalog, id: UUID) {
        guard let document = catalog.licenseDoc(id) else { return nil }
        self.document = document
        assetIDs = catalog.assets.filter { $0.licenseDocs.contains(id) }.map(\.id)
        presetIDs = catalog.rightsPresets.filter { $0.docs.contains(id) }.map(\.id)
        guard !assetIDs.isEmpty || !presetIDs.isEmpty else { return nil }
    }

    public func stillMatches(_ catalog: StudioCatalog) -> Bool {
        guard let current = MissingLicenseRepair(catalog: catalog, id: document.id) else { return false }
        return self == current
    }
}

extension StudioCatalog {
    /// Change only the human-facing file facts. The ID, storage name, added date, rights and all links stay fixed.
    @discardableResult
    public mutating func recordRepairedLicense(_ review: MissingLicenseRepair, name: String, bytes: Int) -> Bool {
        guard review.stillMatches(self), bytes > 0,
              !name.isEmpty, (name as NSString).pathExtension.lowercased() == review.document.ext,
              let i = licenseDocs.firstIndex(where: { $0.id == review.document.id }) else { return false }
        licenseDocs[i].name = name
        licenseDocs[i].bytes = bytes
        return true
    }
}
