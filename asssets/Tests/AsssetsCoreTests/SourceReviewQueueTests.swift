import Foundation
import Testing
import AsssetsCore

@Suite("Source review queue")
struct SourceReviewQueueTests {
    @Test func advancesWithoutAcceptingOthers() {
        let a = UUID(), b = UUID(), c = UUID()
        let q = SourceReviewQueue(pending: [a, b, c], selected: b)
        #expect(q.position == 2 && q.selected == b)
        #expect(q.next(after: b) == c)
        #expect(SourceReviewQueue(pending: [a, c], selected: c).next(after: c) == a)
        #expect(SourceReviewQueue(pending: [c], selected: c).next(after: c) == nil)
        #expect(SourceReviewQueue(pending: [a, b], selected: c).selected == a)
    }

    @Test func repeatedScansKeepChoiceIfStillPending() {
        let a = UUID(), b = UUID(), c = UUID()
        let before = SourceReviewQueue(pending: [a, b], selected: b)
        let after = SourceReviewQueue(pending: [a, b, c], selected: before.selected)
        #expect(after.selected == b && after.position == 2 && after.pending.count == 3)
        #expect(after.next(after: b) == c)
        #expect(SourceReviewQueue(pending: [a, b, b], selected: b).pending == [a, b])
    }
}
