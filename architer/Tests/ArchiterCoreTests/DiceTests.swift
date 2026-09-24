import Foundation
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
        // rolledAt stamps at roll time (2.35.0) and is not part of the
        // determinism contract - normalize it before comparing.
        var r1 = e.roll(using: &g1)
        var r2 = e.roll(using: &g2)
        r1.rolledAt = nil
        r2.rolledAt = nil
        #expect(r1 == r2)
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

@Suite("Per-character roll history")
struct CharacterRollHistoryTests {

    private func roll(_ label: String, character: String?) -> RollResult {
        var r = RollResult(expression: "1d20", dice: [], modifier: 0, total: 10, alternateTotal: nil)
        r.label = label
        r.characterName = character
        return r
    }

    @Test func forCharacterFiltersByTag() {
        let rolls = [roll("a", character: "Wren"), roll("b", character: "Bram"),
                     roll("c", character: nil), roll("d", character: "Wren")]
        #expect(rolls.forCharacter(nil).count == 4)
        #expect(rolls.forCharacter("Wren").map { $0.label ?? "" } == ["a", "d"])
        #expect(rolls.forCharacter("Bram").count == 1)
        #expect(rolls.forCharacter("Nobody").isEmpty)
    }

    @Test func oldHistoryWithoutCharacterDecodes() throws {
        // Pre-2.2 roll-history entries have no characterName key.
        let json = Data(#"[{"expression":"1d20","dice":[],"modifier":0,"total":7}]"#.utf8)
        let rolls = try JSONDecoder().decode([RollResult].self, from: json)
        #expect(rolls.count == 1)
        #expect(rolls[0].characterName == nil)
        #expect(rolls[0].total == 7)
    }

    @Test func characterNameRoundTrips() throws {
        var r = RollResult(expression: "2d6", dice: [], modifier: 0, total: 9, alternateTotal: nil)
        r.characterName = "Wren"
        let data = try JSONEncoder().encode(r)
        let decoded = try JSONDecoder().decode(RollResult.self, from: data)
        #expect(decoded == r)
        #expect(decoded.characterName == "Wren")
    }
}

@Suite("Dice macro damage-type tags")
struct MacroDamageTypeTests {
    @Test func oldMacrosWithoutDamageTypeDecode() throws {
        // Macro files written before 2.36.0 have no damageType key.
        let json = Data(#"[{"name":"Fireball","expression":"8d6"}]"#.utf8)
        let macros = try JSONDecoder().decode([DiceMacro].self, from: json)
        #expect(macros.count == 1)
        #expect(macros[0].damageType == nil)
    }

    @Test func damageTypeRoundTrips() throws {
        let m = DiceMacro(name: "Fireball", expression: "8d6", characterName: "Wren", damageType: "fire")
        let data = try JSONEncoder().encode(m)
        let decoded = try JSONDecoder().decode(DiceMacro.self, from: data)
        #expect(decoded == m)
        #expect(decoded.damageType == "fire")
    }

    @Test func duplicateCarriesDamageType() {
        let m = DiceMacro(name: "Fireball", expression: "8d6", damageType: "fire")
        let copy = ArchiterCore.duplicatedMacro(m, existing: [m])
        #expect(copy.name == "Fireball copy")
        #expect(copy.damageType == "fire")
    }

    @Test func unknownTagFailsSafeToUntyped() {
        // A renamed type case decodes as stored but resolves to no type,
        // so the roll path falls back to a plain labeled roll (2.33.0 pattern).
        let m = DiceMacro(name: "Fireball", expression: "8d6", damageType: "pyro")
        let resolved = m.damageType.flatMap { DamageType(rawValue: $0) }
        #expect(resolved == nil)
    }
}

@Suite("Roll history day groups")
struct RollDayGroupTests {
    private func stamped(_ expression: String, label: String, at: Date?) -> RollResult {
        var r = RollResult(expression: expression, dice: [], modifier: 0, total: 10, alternateTotal: nil)
        r.label = label
        r.rolledAt = at
        return r
    }

    private var utc: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    @Test func groupsNewestFirstByDay() throws {
        let cal = utc
        let now = try #require(cal.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 18)))
        let earlier = now.addingTimeInterval(-3600)
        let yesterday = try #require(cal.date(byAdding: .day, value: -1, to: now))
        let rolls = [
            stamped("1d20", label: "newer today", at: now),
            stamped("2d6", label: "older today", at: earlier),
            stamped("1d8", label: "yesterday", at: yesterday),
            stamped("1d4", label: "undated", at: nil),
        ]
        let groups = groupRollsByDay(rolls, now: now, calendar: cal)
        #expect(groups.map { $0.title } == ["Today", "Yesterday", "Undated"])
        #expect(groups[0].rolls.map { $0.label ?? "" } == ["newer today", "older today"])
        #expect(groups[1].rolls.count == 1)
        #expect(groups[2].rolls.count == 1)
    }

    @Test func olderDaysUseTheFormattedDate() throws {
        let cal = utc
        let now = try #require(cal.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 18)))
        let old = try #require(cal.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 12)))
        let groups = groupRollsByDay([stamped("1d6", label: "old", at: old)], now: now, calendar: cal)
        let expected = RollResult.historyDateFormatter.string(from: old)
        #expect(groups[0].title == expected)
        #expect(groups[0].title != "Today")
    }

    @Test func allTodayIsASingleGroup() throws {
        let cal = utc
        let now = try #require(cal.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 18)))
        let rolls = [stamped("1d20", label: "a", at: now), stamped("2d6", label: "b", at: now)]
        let groups = groupRollsByDay(rolls, now: now, calendar: cal)
        #expect(groups.count == 1)
        #expect(groups[0].title == "Today")
        #expect(groupRollsByDay([], now: now, calendar: cal).isEmpty)
    }
}

@Suite("Roll-again spec")
struct RerollSpecTests {
    @Test func rollsWithoutASpecDecodeUnchanged() throws {
        // The pre-2.40.0 saved shape: no reroll key at all.
        let json = #"{"expression":"2d6+3","dice":[],"modifier":3,"total":10,"alternateTotal":null,"label":null,"characterName":null,"rolledAt":null}"#
        let roll = try JSONDecoder().decode(RollResult.self, from: Data(json.utf8))
        #expect(roll.reroll == nil)
    }

    @Test func specRoundTrips() throws {
        var roll = RollResult(expression: "8d6", dice: [], modifier: 0, total: 26, alternateTotal: nil)
        roll.label = "Fireball (fire: resist 13 - immune 0 - vuln 52)"
        roll.reroll = RerollSpec(kind: .outgoingDamage, baseLabel: "Fireball", damageType: "fire")
        let data = try JSONEncoder().encode(roll)
        let back = try JSONDecoder().decode(RollResult.self, from: data)
        #expect(back == roll)
        #expect(back.reroll?.kind == .outgoingDamage)
        #expect(back.reroll?.baseLabel == "Fireball")
        #expect(back.reroll?.damageType == "fire")
    }

    @Test func checkSpecCarriesModeAndBonus() throws {
        let spec = RerollSpec(kind: .check, baseLabel: "Stealth check", mode: .advantage, checkBonus: 7)
        #expect(spec.mode == .advantage)
        #expect(spec.checkBonus == 7)
    }
}

@Suite("Session-log Markdown export")
struct SessionLogMarkdownTests {
    private func stamped(_ expression: String, label: String?, total: Int, at: Date?) -> RollResult {
        var r = RollResult(expression: expression, dice: [], modifier: 0, total: total, alternateTotal: nil)
        r.label = label
        r.rolledAt = at
        return r
    }

    private var utc: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    @Test func oneTablePerDayGroup() throws {
        let cal = utc
        let t1 = try #require(cal.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 9, minute: 42)))
        let t2 = try #require(cal.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 10, minute: 5)))
        // Oldest first, as groupRollsByDay expects.
        let rolls = [
            stamped("2d6+3", label: nil, total: 8, at: t1),
            stamped("1d20+7", label: "Stealth check", total: 19, at: t2),
        ]
        let groups = groupRollsByDay(rolls, now: t2, calendar: cal)
        let text = sessionLogMarkdown(character: "Wren Halloway", range: .all, groups: groups)
        #expect(text == """
        # Wren Halloway - Session Log (All rolls)

        ## Today

        | Time | Roll | Total |
        | --- | --- | --- |
        | 09:42 | 2d6+3 | 8 |
        | 10:05 | Stealth check (1d20+7) | 19 |

        """)
    }

    @Test func pipesInLabelsAreEscaped() throws {
        let cal = utc
        let t = try #require(cal.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 9)))
        let rolls = [stamped("1d8", label: "Odd | label", total: 4, at: t)]
        let groups = groupRollsByDay(rolls, now: t, calendar: cal)
        let text = sessionLogMarkdown(character: "Wren Halloway", range: .today, groups: groups)
        #expect(text.contains("Odd \\| label (1d8)"))
    }

    @Test func emptyRangeSaysSo() {
        let text = sessionLogMarkdown(character: "Wren Halloway", range: .today, groups: [])
        #expect(text == """
        # Wren Halloway - Session Log (Today)

        No rolls in range.

        """)
    }
}

@Suite("Reroll variants")
struct RerollVariantTests {
    @Test func availabilityPerKind() {
        #expect(RerollVariant.available(for: .check) == RerollVariant.allCases)
        #expect(RerollVariant.available(for: .plain) == [.same, .plusTwo, .minusTwo])
        #expect(RerollVariant.available(for: .outgoingDamage) == [.same, .plusTwo, .minusTwo])
        #expect(RerollVariant.available(for: .incomingDamage).isEmpty)
    }

    @Test func checkSpecAdjustments() {
        let spec = RerollSpec(kind: .check, baseLabel: "Stealth", mode: .normal, checkBonus: 7)
        #expect(spec.adjusted(for: .same) == spec)
        #expect(spec.adjusted(for: .advantage).mode == .advantage)
        #expect(spec.adjusted(for: .disadvantage).mode == .disadvantage)
        #expect(spec.adjusted(for: .plusTwo).checkBonus == 9)
        #expect(spec.adjusted(for: .minusTwo).checkBonus == 5)
        // A spec without a bonus still adjusts from zero.
        let bare = RerollSpec(kind: .check)
        #expect(bare.adjusted(for: .minusTwo).checkBonus == -2)
    }

    @Test func expressionModifiers() {
        #expect("2d10+3".withRerollModifier(.plusTwo) == "2d10+3 + 2")
        #expect("2d10+3".withRerollModifier(.minusTwo) == "2d10+3 - 2")
        #expect("2d10+3".withRerollModifier(.same) == "2d10+3")
        #expect("2d10+3".withRerollModifier(.advantage) == "2d10+3")
    }

    @Test func displayNamesAreStable() {
        #expect(RerollVariant.allCases.map(\.displayName) ==
            ["Roll Again", "With Advantage", "With Disadvantage", "With +2", "With -2"])
    }
}

@Suite("Session-log text export")
struct SessionLogTextTests {
    @Test func dayGroupedLayoutWithIndentedRolls() {
        let rows: [SessionLogRow] = [
            .dayHeader("Yesterday"),
            .roll("[04:01] 4d6kh3: 14"),
            .dayHeader("Today"),
            .roll("[04:25] d20: 7"),
            .roll("[04:27] 4d6kh3: 6"),
        ]
        let text = sessionLogText(character: "Wren Halloway", range: .today, rows: rows)
        #expect(text == """
        Wren Halloway - Session Log (Today)

        Yesterday
          [04:01] 4d6kh3: 14
        Today
          [04:25] d20: 7
          [04:27] 4d6kh3: 6

        """)
    }

    @Test func emptyRangeSaysSo() {
        let text = sessionLogText(character: "Wren Halloway", range: .last7Days, rows: [])
        #expect(text == """
        Wren Halloway - Session Log (Last 7 days)

        No rolls in range.

        """)
    }
}

@Suite("Session-log appendix date range")
struct SessionLogRangeTests {
    private func stamped(_ expression: String, at: Date?) -> RollResult {
        var r = RollResult(expression: expression, dice: [], modifier: 0, total: 10, alternateTotal: nil)
        r.rolledAt = at
        return r
    }

    private var utc: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    @Test func allKeepsEverythingIncludingUnstamped() throws {
        let cal = utc
        let now = try #require(cal.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 18)))
        let old = try #require(cal.date(byAdding: .day, value: -30, to: now))
        let rolls = [stamped("1d20", at: now), stamped("1d8", at: old), stamped("1d4", at: nil)]
        let kept = rolls.within(.all, now: now, calendar: cal)
        #expect(kept.count == 3)
    }

    @Test func todayKeepsOnlySameDayStamps() throws {
        let cal = utc
        let now = try #require(cal.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 18)))
        let earlierToday = try #require(cal.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 0, minute: 1)))
        let yesterday = try #require(cal.date(byAdding: .day, value: -1, to: now))
        let rolls = [stamped("1d20", at: now), stamped("2d6", at: earlierToday),
                     stamped("1d8", at: yesterday), stamped("1d4", at: nil)]
        let kept = rolls.within(.today, now: now, calendar: cal)
        #expect(kept.map(\.expression) == ["1d20", "2d6"])
    }

    @Test func last7DaysCoversTheRollingWeek() throws {
        let cal = utc
        let now = try #require(cal.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 18)))
        let sixDaysAgoStart = try #require(cal.date(from: DateComponents(year: 2026, month: 9, day: 17, hour: 0)))
        let sevenDaysAgo = try #require(cal.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 23, minute: 59)))
        let future = try #require(cal.date(byAdding: .day, value: 1, to: now))
        let rolls = [stamped("1d20", at: now), stamped("1d12", at: sixDaysAgoStart),
                     stamped("1d8", at: sevenDaysAgo), stamped("1d6", at: future),
                     stamped("1d4", at: nil)]
        let kept = rolls.within(.last7Days, now: now, calendar: cal)
        // 6 days back at day start is the cutoff (today + 6 = 7 days);
        // 7 days back and future stamps fall outside; unstamped drops out.
        #expect(kept.map(\.expression) == ["1d20", "1d12"])
    }

    @Test func displayNamesAreStable() {
        #expect(SessionLogRange.allCases.map(\.displayName) == ["All rolls", "Today", "Last 7 days"])
        #expect(SessionLogRange(rawValue: "bogus") == nil)
    }
}

@Suite("Session-log appendix rows")
struct SessionLogRowTests {
    private func stamped(_ expression: String, label: String?, at: Date?) -> RollResult {
        var r = RollResult(expression: expression, dice: [], modifier: 0, total: 10, alternateTotal: nil)
        r.label = label
        r.rolledAt = at
        return r
    }

    private var utc: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func line(_ label: String, _ expression: String, at: Date) -> String {
        "[\(RollResult.historyTimeFormatter.string(from: at))] \(label): 10 (\(expression))"
    }

    @Test func chronologicalDayGroupsOldestRollsFirst() throws {
        let cal = utc
        let now = try #require(cal.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 18)))
        let earlierToday = now.addingTimeInterval(-7200)
        let yesterday = try #require(cal.date(byAdding: .day, value: -1, to: now))
        let earlierYesterday = yesterday.addingTimeInterval(-7200)
        // History order is newest first, as stored.
        let rolls = [
            stamped("1d20", label: "newer today", at: now),
            stamped("2d6", label: "older today", at: earlierToday),
            stamped("1d8", label: "newer yesterday", at: yesterday),
            stamped("1d6", label: "older yesterday", at: earlierYesterday),
            stamped("1d4", label: "legacy", at: nil),
        ]
        let rows = sessionLogRows(rolls, now: now, calendar: cal)
        #expect(rows == [
            .dayHeader("Undated"),
            .roll("legacy: 10 (1d4)"),
            .dayHeader("Yesterday"),
            .roll(line("older yesterday", "1d6", at: earlierYesterday)),
            .roll(line("newer yesterday", "1d8", at: yesterday)),
            .dayHeader("Today"),
            .roll(line("older today", "2d6", at: earlierToday)),
            .roll(line("newer today", "1d20", at: now)),
        ])
        #expect(sessionLogRows([], now: now, calendar: cal).isEmpty)
    }

    @Test func historyLineFormats() throws {
        let cal = utc
        let t = try #require(cal.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 9, minute: 42)))
        let stampedUnlabeled = stamped("2d6+3", label: nil, at: t)
        #expect(stampedUnlabeled.historyLine ==
            "[\(RollResult.historyTimeFormatter.string(from: t))] 2d6+3: 10")
        #expect(stamped("2d6+3", label: nil, at: nil).historyLine == "2d6+3: 10")
        #expect(stamped("1d20+7", label: "Stealth", at: nil).historyLine == "Stealth: 10 (1d20+7)")
        #expect(stamped("1d20+7", label: "Stealth", at: t).historyLine ==
            "[\(RollResult.historyTimeFormatter.string(from: t))] Stealth: 10 (1d20+7)")
    }
}

@Suite("Roll history filtering")
struct RollHistoryFilterTests {
    private func roll(_ expression: String, label: String? = nil, character: String? = nil) -> RollResult {
        var r = RollResult(expression: expression, dice: [], modifier: 0, total: 10, alternateTotal: nil)
        r.label = label
        r.characterName = character
        return r
    }

    @Test func historyTextFormatsOldestFirst() throws {
        let rolls = [
            roll("1d20+7", label: "Stealth check"),
            roll("2d10+3", label: "Fire Bolt damage (fire: resist 7 - immune 0 - vuln 28)"),
            roll("2d6+3"),
        ]
        // History is newest-first; export reads oldest first.
        #expect(rolls.historyText == """
            2d6+3: 10
            Fire Bolt damage (fire: resist 7 - immune 0 - vuln 28): 10 (2d10+3)
            Stealth check: 10 (1d20+7)
            """)
        #expect([RollResult]().historyText == "")
    }

    @Test func historyTextIncludesTimestamps() throws {
        var a = roll("1d20+7", label: "Stealth check")
        var b = roll("2d6+3")
        let t1 = Date(timeIntervalSince1970: 1_700_000_000)
        let t2 = Date(timeIntervalSince1970: 1_700_000_600)
        a.rolledAt = t1
        b.rolledAt = t2
        let s1 = RollResult.historyTimeFormatter.string(from: t1)
        let s2 = RollResult.historyTimeFormatter.string(from: t2)
        // History is newest-first; export reads oldest first with stamps.
        let text = [a, b].historyText
        #expect(text == "[\(s2)] 2d6+3: 10\n[\(s1)] Stealth check: 10 (1d20+7)")
        // Rolls without a recorded time keep the 2.32.0 format.
        let plain = [roll("2d6+3")].historyText
        #expect(plain == "2d6+3: 10")
    }

    @Test func oldRollsWithoutTimestampsDecode() throws {
        // Pre-2.35.0 journal/history entries have no rolledAt key.
        let json = Data(#"[{"expression":"1d20","dice":[],"modifier":0,"total":7,"characterName":"Wren"}]"#.utf8)
        let rolls = try JSONDecoder().decode([RollResult].self, from: json)
        #expect(rolls.count == 1)
        #expect(rolls[0].rolledAt == nil)
        #expect(rolls[0].characterName == "Wren")
    }

    @Test func engineRollsAreTimestamped() throws {
        let before = Date(timeIntervalSinceNow: -5)
        let d20 = DiceRoller(seed: 42).rollD20(mode: .normal)
        let stamped = try #require(d20.rolledAt)
        #expect(stamped >= before)
        #expect(stamped <= Date())
        let expr = try DiceRoller(seed: 42).roll("2d6+3")
        #expect(expr.rolledAt != nil)
        let adv = DiceRoller(seed: 42).rollD20(mode: .advantage)
        #expect(adv.rolledAt != nil)
    }

    @Test func matchesLabelsAndExpressions() throws {
        let rolls = [
            roll("2d10+3", label: "Fire Bolt damage (fire: resist 7 - immune 0 - vuln 28)", character: "Wren"),
            roll("1d20+7", label: "Stealth check", character: "Wren"),
            roll("2d6+3"),
        ]
        // Label text matches, case- and diacritic-insensitive.
        #expect(rolls.matching("stealth").count == 1)
        #expect(rolls.matching("FIRE BOLT").count == 1)
        // Expression matches even when a label is present.
        #expect(rolls.matching("2d10").count == 1)
        #expect(rolls.matching("2d6+3").count == 1)
        // No match yields empty; blank queries return everything.
        #expect(rolls.matching("dragon").isEmpty)
        #expect(rolls.matching("").count == 3)
        #expect(rolls.matching("   ").count == 3)
        // Composes with the character scope filter.
        #expect(rolls.forCharacter("Wren").matching("damage").count == 1)
        #expect(rolls.forCharacter("Wren").matching("2d6").isEmpty)
    }
}

@Suite("Session segments")
struct SessionSegmentTests {
    private var utc: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func stamped(_ expression: String, at: Date?) -> RollResult {
        var r = RollResult(expression: expression, dice: [], modifier: 0, total: 10, alternateTotal: nil)
        r.rolledAt = at
        return r
    }

    private func at(_ cal: Calendar, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    @Test func gapsWithinThresholdStayOneSession() throws {
        let cal = utc
        let now = at(cal, 24, 20)
        let rolls = [stamped("d20", at: at(cal, 24, 18)),
                     stamped("2d6", at: at(cal, 24, 17)),
                     stamped("1d6", at: at(cal, 24, 16))]
        let segments = sessionSegments(rolls, now: now, calendar: cal)
        #expect(segments.count == 1)
        #expect(segments[0].number == 1)
        #expect(segments[0].title == "Session 1 - Today")
        #expect(segments[0].rolls.map(\.expression) == ["d20", "2d6", "1d6"])
    }

    @Test func gapOverFourHoursSplitsSameDay() throws {
        let cal = utc
        let now = at(cal, 24, 20)
        let rolls = [stamped("d20", at: at(cal, 24, 18)),
                     stamped("2d6", at: at(cal, 24, 12))]
        let segments = sessionSegments(rolls, now: now, calendar: cal)
        #expect(segments.map(\.title) == ["Session 2 - Today", "Session 1 - Today"])
        #expect(segments[0].rolls.map(\.expression) == ["d20"])
        #expect(segments[1].rolls.map(\.expression) == ["2d6"])
        // Exactly four hours is still the same session.
        let tight = [stamped("d20", at: at(cal, 24, 16)),
                     stamped("2d6", at: at(cal, 24, 12))]
        #expect(sessionSegments(tight, now: now, calendar: cal).count == 1)
    }

    @Test func dayChangeSplitsEvenUnderGap() throws {
        let cal = utc
        let now = at(cal, 24, 20)
        let rolls = [stamped("d20", at: at(cal, 24, 0, 30)),
                     stamped("2d6", at: at(cal, 23, 23, 30))]
        let segments = sessionSegments(rolls, now: now, calendar: cal)
        #expect(segments.map(\.title) == ["Session 2 - Today", "Session 1 - Yesterday"])
        #expect(segments.map(\.number) == [2, 1])
    }

    @Test func numberingRunsOldestFirstAcrossDays() throws {
        let cal = utc
        let now = at(cal, 24, 20)
        let rolls = [stamped("d20", at: at(cal, 24, 18)),
                     stamped("2d6", at: at(cal, 23, 18)),
                     stamped("1d6", at: at(cal, 21, 18))]
        let segments = sessionSegments(rolls, now: now, calendar: cal)
        #expect(segments.map(\.number) == [3, 2, 1])
        #expect(segments[2].title == "Session 1 - \(RollResult.historyDateFormatter.string(from: at(cal, 21, 18)))")
    }

    @Test func undatedRollsKeepAnUnnumberedSegment() throws {
        let cal = utc
        let now = at(cal, 24, 20)
        let rolls = [stamped("d20", at: at(cal, 24, 18)),
                     stamped("2d6", at: nil),
                     stamped("1d6", at: nil)]
        let segments = sessionSegments(rolls, now: now, calendar: cal)
        #expect(segments.map(\.title) == ["Session 1 - Today", "Undated"])
        #expect(segments.map(\.number) == [1, 0])
        #expect(segments[1].rolls.map(\.expression) == ["2d6", "1d6"])
        #expect(sessionSegments([], now: now, calendar: cal).isEmpty)
    }
}
