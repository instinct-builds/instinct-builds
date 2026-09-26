import Foundation

/// A failed read is not evidence of absence. The adapter can be injected in tests.
public enum HealthRead<Value: Sendable>: Sendable {
    case present(Value)
    case absent
    case unknown
}

public enum HealthCheck: String, CaseIterable, Sendable {
    case files = "Asset files"
    case sources = "Source changes"
    case licenses = "License files"
    case folder = "License folder"
    case sizes = "Large files"
    case duplicates = "Identical files"
}

public struct HealthReadIssue: Equatable, Sendable {
    public let check: HealthCheck
    public let name: String
    public init(_ check: HealthCheck, _ name: String) { self.check = check; self.name = name }
}

/// A bounded, scoped summary. `issues` never carries raw OS errors or paths.
public struct HealthCoverage: Equatable, Sendable {
    public private(set) var issues: [HealthReadIssue] = []
    public private(set) var affected: Set<HealthCheck> = []
    public private(set) var totalFailures = 0
    public init() {}
    public mutating func failed(_ check: HealthCheck, name: String) {
        totalFailures += 1
        affected.insert(check)
        if issues.count < 6 { issues.append(HealthReadIssue(check, name)) }
    }
    public func covers(_ check: HealthCheck) -> Bool { !affected.contains(check) }
    public var complete: Bool { totalFailures == 0 }
}

/// Classify path reads before calculating Health. Unknown paths are excluded from missing lists.
public enum HealthReadClassification {
    public static func make(catalog: StudioCatalog, asset: (String) -> HealthRead<Int64>,
                            license: (LicenseDoc) -> HealthRead<Bool>,
                            folder: HealthRead<[String]>, duplicateSets: Int? = nil,
                            initial: HealthCoverage = HealthCoverage()) -> (LibraryHealth, HealthCoverage) {
        var coverage = initial
        var assetReads: [String: HealthRead<Int64>] = [:]
        var sizes: [UUID: Int64] = [:]
        for a in catalog.assets {
            guard let path = a.importedPath else { continue }
            let result = assetReads[path] ?? asset(path)
            assetReads[path] = result
            switch result {
            case .present(let size): sizes[a.id] = size
            case .absent: break
            case .unknown:
                coverage.failed(.files, name: a.title)
                coverage.failed(.sources, name: a.title)
                coverage.failed(.sizes, name: a.title)
            }
        }
        var licenseReads: [UUID: HealthRead<Bool>] = [:]
        for d in catalog.licenseDocs {
            let result = license(d)
            licenseReads[d.id] = result
            if case .unknown = result { coverage.failed(.licenses, name: d.name) }
        }
        let folderNames: [String]
        switch folder {
        case .present(let names): folderNames = names
        case .absent: folderNames = []
        case .unknown:
            folderNames = []
            coverage.failed(.folder, name: "Licenses folder")
        }
        let h = catalog.health(exists: { path in
            switch assetReads[path] { case .absent: return false; default: return true }
        }, licenseExists: { doc in
            switch licenseReads[doc.id] { case .absent: return false; default: return true }
        }, licenseFolder: folderNames, sizes: sizes, duplicateSets: duplicateSets)
        return (h, coverage)
    }
}
