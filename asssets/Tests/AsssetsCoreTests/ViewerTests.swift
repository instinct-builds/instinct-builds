import Testing
@testable import AsssetsCore

@Suite("Viewer navigation")
struct ViewerTests {
    @Test func stepsAndWraps() {
        let ids = ["a", "b", "c"]
        #expect(ViewerNav.step(ids, from: "a", by: 1) == "b")
        #expect(ViewerNav.step(ids, from: "c", by: 1) == "a")
        #expect(ViewerNav.step(ids, from: "a", by: -1) == "c")
        #expect(ViewerNav.step(ids, from: "b", by: -4) == "a")
    }

    @Test func missingOrEmpty() {
        #expect(ViewerNav.step([String](), from: "a", by: 1) == nil)
        #expect(ViewerNav.step(["a", "b"], from: "z", by: 1) == "a")
        #expect(ViewerNav.step(["a", "b"], from: nil, by: -1) == "b")
        #expect(ViewerNav.position(["a", "b", "c"], of: "c")! == (3, 3))
        #expect(ViewerNav.position(["a"], of: "q") == nil)
    }
}
