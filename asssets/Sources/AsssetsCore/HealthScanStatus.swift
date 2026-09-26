import Foundation

/// Session-only provenance. A quick sweep does not newly check duplicate hashes.
public struct HealthScanStatus: Equatable, Sendable {
    public let completedAt: Date
    public let full: Bool
    public let duplicateCheckedAt: Date?
    public let coverage: HealthCoverage

    public init(completedAt: Date, full: Bool, previous: HealthScanStatus? = nil, coverage: HealthCoverage = HealthCoverage()) {
        self.completedAt = completedAt
        self.full = full
        self.coverage = coverage
        duplicateCheckedAt = full && coverage.covers(.duplicates) ? completedAt : previous?.duplicateCheckedAt
    }

    public var duplicateFreshForThisScan: Bool { full && coverage.covers(.duplicates) && duplicateCheckedAt == completedAt }
    public var scopeLabel: String { (full ? "Full check" : "Quick check") + (coverage.complete ? "" : " incomplete") }
    public var complete: Bool { coverage.complete }
}
