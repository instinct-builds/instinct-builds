import Testing
import AsssetsCore

@Suite("Bounded Health issue rows")
struct HealthRowWindowTests {
    @Test func startsAtThreeAndPagesWithoutSkipping() {
        #expect(HealthRowWindow.visible(total: 0, expanded: 0) == 0)
        #expect(HealthRowWindow.visible(total: 3, expanded: 0) == 3)
        #expect(HealthRowWindow.visible(total: 4, expanded: 0) == 3)
        #expect(HealthRowWindow.next(total: 4, expanded: 0) == 4)
        #expect(HealthRowWindow.next(total: 100, expanded: 0) == 43)
        #expect(HealthRowWindow.next(total: 100, expanded: 43) == 83)
        #expect(HealthRowWindow.next(total: 100, expanded: 83) == 100)
        #expect(HealthRowWindow.visible(total: 2, expanded: 100) == 2)
    }
}
