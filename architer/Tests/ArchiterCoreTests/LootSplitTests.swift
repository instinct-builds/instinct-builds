import Foundation
import Testing
@testable import ArchiterCore

@Suite("Split gold (3.83.0)")
struct LootSplitTests {
    @Test func evenSplitHasNoLeftover() {
        let s = LootSplit(totalCopper: 9000, members: 3)!
        #expect(s.shareCopper == 3000)
        #expect(s.leftoverCopper == 0)
        #expect(s.share == Currency(gold: 30))
    }

    @Test func unevenSplitFloorsAndKeepsRemainderInThePot() {
        let s = LootSplit(totalCopper: 10000, members: 3)!
        #expect(s.shareCopper == 3333)
        #expect(s.leftoverCopper == 1)
        #expect(s.share == Currency(copper: 3, silver: 3, gold: 33))
        #expect(s.shareCopper * 3 + s.leftoverCopper == 10000)
    }

    @Test func noMembersOrNoPotYieldsNoSplit() {
        #expect(LootSplit(totalCopper: 100, members: 0) == nil)
        #expect(LootSplit(totalCopper: 0, members: 3) == nil)
        #expect(LootSplit(totalCopper: -5, members: 3) == nil)
    }

    @Test func addingNeverConsolidatesExistingCoins() {
        let a = Currency(copper: 7, silver: 12, electrum: 1, gold: 2)
        let b = a.adding(Currency(copper: 5, gold: 1))
        #expect(b == Currency(copper: 12, silver: 12, electrum: 1, gold: 3))
    }
}
