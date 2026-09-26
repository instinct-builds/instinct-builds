import Foundation

/// Session-only provenance. A quick sweep does not newly check duplicate hashes.
public struct HealthScanStatus: Equatable, Sendable {
    public let completedAt: Date
    public let full: Bool
    public let duplicateCheckedAt: Date?

    public init(completedAt: Date, full: Bool, previous: HealthScanStatus? = nil) {
        self.completedAt = completedAt
        self.full = full
        duplicateCheckedAt = full ? completedAt : previous?.duplicateCheckedAt
    }

    public var duplicateFreshForThisScan: Bool { full && duplicateCheckedAt == completedAt }
    public var scopeLabel: String { full ? "Full check" : "Quick check" }
}
