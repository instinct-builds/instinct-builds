import Foundation
import Testing
@testable import AsssetsCore

@Suite("Health three-state read coverage")
struct HealthReadTests {
    @Test func unknownIsNeitherMissingNorGreen() {
        var c = StudioCatalog()
        let a = c.importFile(path: "/lib/a.png")!
        let b = c.importFile(path: "/lib/b.png")!
        let d = LicenseDoc(name: "order.pdf")
        _ = c.addLicenseDoc(d, to: [a])
        let (h, coverage) = HealthReadClassification.make(catalog: c, asset: { path in
            path.hasSuffix("a.png") ? .unknown : .absent
        }, license: { _ in .unknown }, folder: .unknown)
        #expect(h.missingFiles == [b])
        #expect(h.missingLicenseFiles.isEmpty)
        #expect(!coverage.complete && !coverage.covers(.files) && !coverage.covers(.licenses))
        #expect(!coverage.covers(.folder) && !coverage.covers(.sizes))
        #expect(!coverage.covers(.sources) && coverage.covers(.duplicates))
        #expect(coverage.issues.count == 5 && coverage.totalFailures == 5)
        let status = HealthScanStatus(completedAt: Date(timeIntervalSince1970: 10), full: true, coverage: coverage)
        #expect(status.scopeLabel == "Full check incomplete" && !status.complete)
    }

    @Test func confirmedAbsenceAndRecovery() {
        var c = StudioCatalog()
        let a = c.importFile(path: "/lib/a.png")!
        let d = LicenseDoc(name: "order.pdf")
        _ = c.addLicenseDoc(d, to: [a])
        let missing = HealthReadClassification.make(catalog: c, asset: { _ in .absent },
                                                     license: { _ in .absent }, folder: .absent)
        #expect(missing.0.missingFiles == [a] && missing.0.missingLicenseFiles == [d.id])
        #expect(missing.1.complete)
        let recovered = HealthReadClassification.make(catalog: c, asset: { _ in .present(150) },
                                                       license: { _ in .present(true) }, folder: .present([]))
        #expect(recovered.1.complete && recovered.0.missingFiles.isEmpty && recovered.0.missingLicenseFiles.isEmpty)
        #expect(recovered.0.bigFiles.isEmpty)
    }

    @Test func injectedIOFailureCannotHideConfirmedFindingAndIsBounded() {
        var c = StudioCatalog()
        let missing = c.importFile(path: "/lib/missing.png")!
        for n in 0..<10 { _ = c.importFile(path: "/lib/unknown-\(n).png") }
        var initial = HealthCoverage()
        initial.failed(.duplicates, name: "Hash unavailable")
        let (h, coverage) = HealthReadClassification.make(catalog: c, asset: { path in
            path.hasSuffix("missing.png") ? .absent : .unknown
        }, license: { _ in .present(true) }, folder: .present([]), initial: initial)
        #expect(h.missingFiles == [missing])
        #expect(!coverage.covers(.duplicates) && !coverage.covers(.files))
        #expect(coverage.totalFailures == 31 && coverage.issues.count == 6)
        #expect(h.duplicateSets == nil)
    }
}
