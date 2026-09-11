import Testing
@testable import ArchiterCore

@Suite("Dice expression parsing")
struct DiceParsingTests {
    @Test func parsesPlainDie() throws {
        let e = try DiceExpression.parse("d20")
        #expect(e.terms == [DiceExpression.Term(count: 1, sides: 20, keepHighest: nil, dropLowest: nil, sign: 1)])
        #expect(e.modifier == 0)
    }

    @Test func parsesCountAndModifier() throws {
        let e = try DiceExpression.parse("2d6+3")
        #expect(e.terms.first?.count == 2)
        #expect(e.terms.first?.sides == 6)
        #expect(e.modifier == 3)
    }

    @Test func parsesKeepHighest() throws {
        let e = try DiceExpression.parse("4d6kh3")
        #expect(e.terms.first?.keepHighest == 3)
    }

    @Test func parsesDropLowest() throws {
        let e = try DiceExpression.parse("4d6dl1")
        #expect(e.terms.first?.dropLowest == 1)
    }

    @Test func parsesCompoundAndNegative() throws {
        let e = try DiceExpression.parse("1d8+1d4-2")
        #expect(e.terms.count == 2)
        #expect(e.modifier == -2)
    }

    @Test func rejectsGarbage() {
        #expect(throws: DiceError.self) { try DiceExpression.parse("fireball") }
        #expect(throws: DiceError.self) { try DiceExpression.parse("") }
        #expect(throws: DiceError.self) { try DiceExpression.parse("2d1") }
        #expect(throws: DiceError.self) { try DiceExpression.parse("101d6") }
    }
}

@Suite("Dice rolling")
struct DiceRollingTests {
    @Test func seededRollIsDeterministic() throws {
        var g1 = SeededGenerator(seed: 42)
        var g2 = SeededGenerator(seed: 42)
        let e = try DiceExpression.parse("3d6+2")
        #expect(e.roll(using: &g1) == e.roll(using: &g2))
    }

    @Test func totalsStayInRange() throws {
        var g = SeededGenerator(seed: 7)
        let e = try DiceExpression.parse("2d6+3")
        for _ in 0..<500 {
            let r = e.roll(using: &g)
            #expect(r.total >= 5 && r.total <= 15)
            #expect(r.dice.count == 2)
        }
    }

    @Test func keepHighestDropsCorrectDice() throws {
        var g = SeededGenerator(seed: 99)
        let e = try DiceExpression.parse("4d6kh3")
        for _ in 0..<200 {
            let r = e.roll(using: &g)
            let kept = r.dice.filter(\.kept).map(\.value)
            let dropped = r.dice.filter { !$0.kept }.map(\.value)
            #expect(kept.count == 3 && dropped.count == 1)
            #expect(kept.allSatisfy { $0 >= dropped[0] })
            #expect(r.total == kept.reduce(0, +))
        }
    }

    @Test func advantagePicksHigher() {
        let roller = DiceRoller(seed: 1234)
        for _ in 0..<100 {
            let r = roller.rollD20(mode: .advantage, modifier: 5)
            let kept = r.dice.filter(\.kept)[0].value
            let other = r.dice.filter { !$0.kept }[0].value
            #expect(kept >= other)
            #expect(r.total == kept + 5)
            #expect(r.alternateTotal == other + 5)
        }
    }

    @Test func disadvantagePicksLower() {
        let roller = DiceRoller(seed: 55)
        for _ in 0..<100 {
            let r = roller.rollD20(mode: .disadvantage)
            let kept = r.dice.filter(\.kept)[0].value
            let other = r.dice.filter { !$0.kept }[0].value
            #expect(kept <= other)
        }
    }
}
