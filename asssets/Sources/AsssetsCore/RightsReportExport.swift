import Foundation

/// Exact catalog facts approved at the start of a report export; does not attest physical file bytes.
public struct RightsReportExport: Equatable, Sendable {
    public let ids: [UUID]
    public let title: String
    public let day: String
    public let report: RightsReport
    public let documents: [LicenseDoc]
    /// Original ordered rows, not just sorted render order, so a changed selection cannot pass by accident.
    public let inputs: [Input]
    public struct Input: Equatable, Sendable {
        public let id: UUID
        public let title: String
        public let file: String?
        public let rights: UsageRights?
        public let documentIDs: [UUID]
    }
    public init?(catalog: StudioCatalog, ids: [UUID], title: String, day: String) {
        guard !ids.isEmpty, ids.count == Set(ids).count,
              ids.allSatisfy({ id in catalog.assets.contains(where: { $0.id == id }) }) else { return nil }
        self.ids = ids; self.title = title; self.day = day
        let byID = Dictionary(catalog.assets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let selected = ids.compactMap { byID[$0] }
        guard selected.count == ids.count,
              selected.allSatisfy({ asset in asset.licenseDocs.allSatisfy { catalog.licenseDoc($0) != nil } }) else { return nil }
        inputs = selected.map { asset in
            Input(id: asset.id, title: asset.title, file: asset.importedPath,
                  rights: asset.rights, documentIDs: asset.licenseDocs)
        }
        report = catalog.rightsReport(ids, title: title, today: day)
        documents = report.docs
    }
    public func stillMatches(_ catalog: StudioCatalog, ids: [UUID], title: String, day: String) -> Bool {
        self == RightsReportExport(catalog: catalog, ids: ids, title: title, day: day)
    }
}
