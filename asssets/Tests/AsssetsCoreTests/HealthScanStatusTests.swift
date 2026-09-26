import Foundation
import Testing
import AsssetsCore

@Suite("Health scan provenance")
struct HealthScanStatusTests {
    @Test func fullAndQuickAreNotInterchangeable() {
        let first = Date(timeIntervalSince1970: 100)
        let later = Date(timeIntervalSince1970: 200)
        let full = HealthScanStatus(completedAt: first, full: true)
        #expect(full.duplicateFreshForThisScan && full.duplicateCheckedAt == first && full.scopeLabel == "Full check")
        let quick = HealthScanStatus(completedAt: later, full: false, previous: full)
        #expect(quick.scopeLabel == "Quick check" && quick.completedAt == later)
        #expect(!quick.duplicateFreshForThisScan && quick.duplicateCheckedAt == first)
        let initial = HealthScanStatus(completedAt: first, full: false)
        #expect(initial.duplicateCheckedAt == nil && !initial.duplicateFreshForThisScan)
    }
}
