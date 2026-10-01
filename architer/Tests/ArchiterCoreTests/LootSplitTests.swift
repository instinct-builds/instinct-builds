import Foundation
import Testing
@testable import ArchiterCore

@Suite("Split gold (3.83.0)")
struct LootSplitTests {
    @Test func evenSplitHasNoLeftover() {
        let s = LootSplit(totalCopper: 9000, members: 3)!
        #expect(s.shareCopper == 3000)
        #expect(s.leftoverCopper == 0)
        #expect(s.share == Currency(platinum: 3))
    }

    @Test func unevenSplitFloorsAndKeepsRemainderInThePot() {
        let s = LootSplit(totalCopper: 10000, members: 3)!
        #expect(s.shareCopper == 3333)
        #expect(s.leftoverCopper == 1)
        #expect(s.share == Currency(copper: 3, silver: 3, gold: 3, platinum: 3))
        #expect(s.shareCopper * 3 + s.leftoverCopper == 10000)
    }

    @Test func noMembersOrNoPotYieldsNoSplit() {
        #expect(LootSplit(totalCopper: 100, members: 0) == nil)
        #expect(LootSplit(totalCopper: 0, members: 3) == nil)
        #expect(LootSplit(totalCopper: -5, members: 3) == nil)
        #expect(LootSplit(totalCopper: 2, members: 3) == nil)
        #expect(LootSplit(totalCopper: 3, members: 3)?.shareCopper == 1)
    }

    @Test func addingNeverConsolidatesExistingCoins() {
        let a = Currency(copper: 7, silver: 12, electrum: 1, gold: 2)
        let b = a.adding(Currency(copper: 5, gold: 1))
        #expect(b == Currency(copper: 12, silver: 12, electrum: 1, gold: 3))
    }
}

@Suite("Coin amount parsing (3.85.0)")
struct CoinAmountTests {
    @Test func bareNumberIsGold() {
        #expect(CoinAmount.parseCopper("250") == 25000)
        #expect(CoinAmount.parseCopper(" 7 ") == 700)
    }

    @Test func suffixesAndCombinations() {
        #expect(CoinAmount.parseCopper("250gp") == 25000)
        #expect(CoinAmount.parseCopper("40sp") == 400)
        #expect(CoinAmount.parseCopper("75cp") == 75)
        #expect(CoinAmount.parseCopper("3pp") == 3000)
        #expect(CoinAmount.parseCopper("2ep") == 100)
        #expect(CoinAmount.parseCopper("2gp 5sp 3cp") == 253)
        #expect(CoinAmount.parseCopper("2gp, 5sp") == 250)
        #expect(CoinAmount.parseCopper("40SP") == 400)
    }

    @Test func junkIsRejectedNotGuessed() {
        #expect(CoinAmount.parseCopper("") == nil)
        #expect(CoinAmount.parseCopper("  ") == nil)
        #expect(CoinAmount.parseCopper("2.5gp") == nil)
        #expect(CoinAmount.parseCopper("gp") == nil)
        #expect(CoinAmount.parseCopper("12xp") == nil)
        #expect(CoinAmount.parseCopper("-5") == nil)
        #expect(CoinAmount.parseCopper("99999999999999999999") == nil)
    }

    @Test func potTextReadsBack() {
        #expect(CoinAmount.potText(copper: 10000) == "100 gp")
        #expect(CoinAmount.potText(copper: 475) == "4 gp, 7 sp, 5 cp")
    }
}
