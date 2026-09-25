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

    @Test func noteRoundTrips() throws {
        // 2.92.0: the note is part of the saved roll; pre-2.92.0 saves
        // carry no note key and decode to nil (same optional pattern as
        // reroll above).
        var roll = RollResult(expression: "8d6", dice: [], modifier: 0, total: 27, alternateTotal: nil)
        roll.label = "Fireball"
        roll.note = "The bridge collapses behind them"
        let data = try JSONEncoder().encode(roll)
        let back = try JSONDecoder().decode(RollResult.self, from: data)
        #expect(back == roll)
        #expect(back.note == "The bridge collapses behind them")
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

    // 2.92.0: the note rides the Roll cell after a dash, and pipes in
    /// notes are escaped like pipes in labels.
    @Test func noteRidesTheRollCell() throws {
        let cal = utc
        let t = try #require(cal.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 9, minute: 42)))
        var r = stamped("8d6", label: "Fireball", total: 27, at: t)
        r.note = "The bridge collapses | behind them"
        let groups = groupRollsByDay([r], now: t, calendar: cal)
        let text = sessionLogMarkdown(character: "Wren Halloway", range: .all, groups: groups)
        #expect(text.contains("| Fireball (8d6) - The bridge collapses \\| behind them | 27 |"))
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

        ## Today - 1 session \u{00B7} 2 rolls

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

    // 2.92.0: a note row follows its roll, indented two spaces deeper.
    @Test func noteLinesIndentPastTheRoll() {
        let rows: [SessionLogRow] = [
            .dayHeader("Today"),
            .roll("[04:25] Fireball: 27 (8d6)"),
            .note("The bridge collapses behind them"),
        ]
        let text = sessionLogText(character: "Wren Halloway", range: .today, rows: rows)
        #expect(text == """
        Wren Halloway - Session Log (Today)

        Today
          [04:25] Fireball: 27 (8d6)
            The bridge collapses behind them

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
        // 2.90.0: "Starred only" joins the menu.
        #expect(SessionLogRange.allCases.map(\.displayName) == ["All rolls", "Today", "Last 7 days", "Starred only"])
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

    // 2.92.0: a noted roll's row is followed by its note row.
    @Test func notedRollEmitsNoteRow() throws {
        let cal = utc
        let t = try #require(cal.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 9, minute: 42)))
        var r = stamped("8d6", label: "Fireball", at: t)
        r.note = "The bridge collapses behind them"
        let rows = sessionLogRows([r], now: t, calendar: cal)
        #expect(rows.count == 3)
        #expect(rows[1] == .roll(line("Fireball", "8d6", at: t)))
        #expect(rows[2] == .note("The bridge collapses behind them"))
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
            .dayHeader("Undated - 1 roll"),
            .roll("legacy: 10 (1d4)"),
            .dayHeader("Yesterday - 1 session \u{00B7} 2 rolls"),
            .roll(line("older yesterday", "1d6", at: earlierYesterday)),
            .roll(line("newer yesterday", "1d8", at: yesterday)),
            .dayHeader("Today - 1 session \u{00B7} 2 rolls"),
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

    // 2.93.0: a noted roll's note rides the share text as an indented
    /// line under it; unnoted rolls stay one line each.
    @Test func historyTextCarriesNotes() {
        var noted = roll("8d6", label: "Fireball")
        noted.note = "The bridge collapses behind them"
        let rolls = [roll("d20"), noted]
        #expect(rolls.historyText == """
            Fireball: 10 (8d6)
              The bridge collapses behind them
            d20: 10
            """)
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

    // 2.67.0: a session's key is its oldest roll's stamp - stable as new
    // rolls land on top; undated runs have no key and cannot be named.
    @Test func sessionKeyIsTheOldestRollsStamp() throws {
        let cal = utc
        let now = at(cal, 24, 20)
        let rolls = [stamped("d20", at: at(cal, 24, 18)),
                     stamped("2d6", at: at(cal, 24, 17)),
                     stamped("1d6", at: at(cal, 23, 18))]
        let segments = sessionSegments(rolls, now: now, calendar: cal)
        #expect(segments[0].key == ISO8601DateFormatter().string(from: at(cal, 24, 17)))
        #expect(segments[1].key == ISO8601DateFormatter().string(from: at(cal, 23, 18)))
        let undated = sessionSegments([stamped("d20", at: nil)], now: now, calendar: cal)
        #expect(undated[0].key == nil)
    }

    // 2.67.0: renamed() swaps the divider title for the custom name;
    // blank or nil restores the generated one. Number, key, and rolls
    // ride through unchanged.
    @Test func renamedSessionCarriesTheCustomName() throws {
        let cal = utc
        let now = at(cal, 24, 20)
        let rolls = [stamped("d20", at: at(cal, 24, 18)),
                     stamped("2d6", at: at(cal, 24, 17))]
        let session = sessionSegments(rolls, now: now, calendar: cal)[0]
        let named = session.renamed("Ember Warrens delve")
        #expect(named.title == "Ember Warrens delve")
        #expect(named.number == session.number)
        #expect(named.key == session.key)
        #expect(named.rolls == session.rolls)
        #expect(session.renamed(nil) == session)
        #expect(session.renamed("   ") == session)
    }

    // 2.67.0: a digest filed from a renamed session takes the custom
    // name as its title - no separate naming step needed.
    @Test func digestOfRenamedSessionTakesItsName() throws {
        let cal = utc
        let now = at(cal, 24, 20)
        let rolls = [stamped("d20", at: at(cal, 24, 18))]
        let session = sessionSegments(rolls, now: now, calendar: cal)[0]
            .renamed("Ember Warrens delve")
        let digest = JournalEntry(sessionDigest: session, now: now)
        #expect(digest.title == "Ember Warrens delve")
    }

    // 2.68.0: named sessions annotate their day's export header, oldest
    // session first; days with no named session keep the plain title.
    @Test func namedDayGroupsCarrySessionNames() throws {
        let cal = utc
        let now = at(cal, 24, 20)
        let rolls = [stamped("d20", at: at(cal, 24, 18)),
                     stamped("2d6", at: at(cal, 24, 12)),
                     stamped("1d6", at: at(cal, 23, 18))]
        let sessions = sessionSegments(rolls, now: now, calendar: cal)
        var names: [String: String] = [:]
        names[sessions[0].key!] = "Night watch"
        names[sessions[1].key!] = "Morning crawl"
        let groups = namedDayGroups(rolls, names: names, now: now, calendar: cal)
        #expect(groups.map(\.title) == ["Today - Morning crawl \u{00B7} Night watch", "Yesterday"])
        #expect(groups[0].rolls.map(\.expression) == ["d20", "2d6"])
        // An empty map and unnamed sessions annotate nothing.
        #expect(namedDayGroups(rolls, names: [:], now: now, calendar: cal).map(\.title)
                == ["Today", "Yesterday"])
        let partial = namedDayGroups(rolls, names: [sessions[0].key!: "Night watch"],
                                     now: now, calendar: cal)
        #expect(partial[0].title == "Today - Night watch")
    }

    // 2.68.0: the text/PDF row builder carries the annotated header.
    @Test func sessionLogRowsAnnotateNamedDays() throws {
        let cal = utc
        let now = at(cal, 24, 20)
        let rolls = [stamped("d20", at: at(cal, 24, 18))]
        let key = sessionSegments(rolls, now: now, calendar: cal)[0].key!
        let rows = sessionLogRows(rolls, names: [key: "Night watch"], now: now, calendar: cal)
        #expect(rows.first == .dayHeader("Today - Night watch - 1 session \u{00B7} 1 roll"))
        #expect(sessionLogRows(rolls, now: now, calendar: cal).first == .dayHeader("Today - 1 session \u{00B7} 1 roll"))
    }

    // 2.76.0: export day headers carry the day's summary - the session
    // count from the same segmentation as the pane, plus the roll
    // count - and a pane-set name lands deterministically even when the
    // named session has several rolls (the export's oldest-first order
    // used to collapse the day into one "session" keyed by its newest
    // roll, silently dropping the annotation).
    @Test func dayHeadersCarrySummariesAndPaneNames() throws {
        let cal = utc
        let now = at(cal, 24, 21)
        // Three sessions today, newest first as history stores them:
        // a two-roll morning and two lone later rolls (gaps over 4h).
        let rolls = [stamped("d20", at: at(cal, 24, 20)),
                     stamped("2d6", at: at(cal, 24, 15)),
                     stamped("1d8", at: at(cal, 24, 10)),
                     stamped("d4", at: at(cal, 24, 9))]
        let sessions = sessionSegments(rolls, now: now, calendar: cal)
        #expect(sessions.count == 3)
        let key = try #require(sessions[0].key)
        let rows = sessionLogRows(rolls, names: [key: "Night watch"], now: now, calendar: cal)
        #expect(rows.first == .dayHeader("Today - Night watch - 3 sessions \u{00B7} 4 rolls"))
    }

    // 2.69.0: the divider stats line - count and high/low over totals,
    // natural 20/1 tallies over kept d20 dice only (an unkept advantage
    // die is not a crit the table saw); crits leave the line when zero.
    @Test func sessionStatsSummarizeTheSession() throws {
        let cal = utc
        // Advantage roll: a kept 20 over an unkept 1 - one nat 20, the
        // dropped 1 is not a nat 1.
        var adv = RollResult(expression: "d20",
                             dice: [DieResult(sides: 20, value: 20, kept: true),
                                    DieResult(sides: 20, value: 1, kept: false)],
                             modifier: 7, total: 27, alternateTotal: 8)
        adv.rolledAt = at(cal, 24, 18)
        var critFail = RollResult(expression: "d20",
                                  dice: [DieResult(sides: 20, value: 1, kept: true)],
                                  modifier: 2, total: 3, alternateTotal: nil)
        critFail.rolledAt = at(cal, 24, 17)
        let plain = stamped("2d6", at: at(cal, 24, 16))   // total 10
        let session = RollSession(number: 1, title: "Session 1 - Today", key: nil,
                                  rolls: [adv, critFail, plain])
        let stats = sessionStats(session)
        #expect(stats.count == 3)
        #expect(stats.high == 27)
        #expect(stats.low == 3)
        #expect(stats.nat20s == 1)
        #expect(stats.nat1s == 1)
        // 2.75.0: 18:00 to 16:00 - a two-hour span, whole-hour format.
        #expect(stats.span == 7200)
        #expect(stats.line == "3 rolls \u{00B7} high 27 \u{00B7} low 3 \u{00B7} nat 20 \u{00D7}1 \u{00B7} nat 1 \u{00D7}1 \u{00B7} span 2h")
        let quiet = sessionStats(RollSession(number: 1, title: "t", key: nil, rolls: [plain]))
        #expect(quiet.line == "1 roll \u{00B7} high 10 \u{00B7} low 10")
    }

    // 2.75.0: the stats line carries the session's first-to-last-roll
    // span - hours and minutes "2h 14m", whole hours "2h", sub-hour
    // "38m", sub-minute "<1m"; single-roll and undated sessions print
    // no span at all.
    @Test func sessionStatsLineCarriesTheSpan() throws {
        let cal = utc
        let t0 = at(cal, 24, 16)
        let long = RollSession(number: 1, title: "t", key: nil,
                               rolls: [stamped("d20", at: at(cal, 24, 18, 14)),
                                       stamped("2d6", at: t0)])
        #expect(sessionStats(long).line.hasSuffix("span 2h 14m"))
        let short = RollSession(number: 1, title: "t", key: nil,
                                rolls: [stamped("d20", at: at(cal, 24, 18, 38)),
                                        stamped("2d6", at: at(cal, 24, 18))])
        #expect(sessionStats(short).line.hasSuffix("span 38m"))
        let blink = RollSession(number: 1, title: "t", key: nil,
                                rolls: [stamped("d20", at: cal.date(byAdding: .second, value: 20, to: at(cal, 24, 18))!),
                                        stamped("2d6", at: at(cal, 24, 18))])
        #expect(sessionStats(blink).line.hasSuffix("span <1m"))
        // A lone roll has no span, and neither does an undated pair.
        let lone = sessionStats(RollSession(number: 1, title: "t", key: nil,
                                            rolls: [stamped("d20", at: at(cal, 24, 18))]))
        #expect(lone.span == nil)
        let undated = RollSession(number: 1, title: "t", key: nil,
                                  rolls: [RollResult(expression: "d20", dice: [], modifier: 0,
                                                     total: 10, alternateTotal: nil),
                                          RollResult(expression: "2d6", dice: [], modifier: 0,
                                                     total: 7, alternateTotal: nil)])
        let undatedStats = sessionStats(undated)
        #expect(undatedStats.span == nil)
        #expect(!undatedStats.line.contains("span"))
    }

    // 2.70.0: share text = title (custom name included) + stats line +
    // rolls oldest first, one history line each.
    @Test func sessionShareTextCarriesStatsAndRolls() throws {
        let cal = utc
        let now = at(cal, 24, 20)
        let rolls = [stamped("d20", at: at(cal, 24, 18)),
                     stamped("2d6", at: at(cal, 24, 17))]
        let session = sessionSegments(rolls, now: now, calendar: cal)[0]
            .renamed("Night watch")
        let text = sessionShareText(session)
        #expect(text.hasPrefix("Night watch\n2 rolls \u{00B7} high 10 \u{00B7} low 10 \u{00B7} span 1h\n\n"))
        // lines[2] is the blank separator after the stats line.
        let lines = text.components(separatedBy: "\n")
        #expect(lines[2].isEmpty)
        #expect(lines[3].contains("2d6: 10"))
        #expect(lines[4].contains("d20: 10"))
    }

    // 2.93.0: the session share text carries a noted roll's note under
    /// its line, indented.
    @Test func sessionShareTextCarriesRollNotes() throws {
        let cal = utc
        let now = at(cal, 24, 20)
        var noted = stamped("8d6", at: at(cal, 24, 18))
        noted.label = "Fireball"
        noted.note = "The bridge collapses behind them"
        let rolls = [noted, stamped("2d6", at: at(cal, 24, 17))]
        let session = sessionSegments(rolls, now: now, calendar: cal)[0]
        let lines = sessionShareText(session).components(separatedBy: "\n")
        let fireballIdx = try #require(lines.firstIndex(where: { $0.contains("Fireball: 10 (8d6)") }))
        #expect(lines[fireballIdx + 1] == "  The bridge collapses behind them")
    }

    // 2.77.0: copy-day text = the named, summarized day header, a blank
    // line, then the day's rolls oldest first, one history line each.
    @Test func dayShareTextCarriesHeaderAndChronologicalRolls() throws {
        let cal = utc
        let now = at(cal, 24, 21)
        let rolls = [stamped("d20", at: at(cal, 24, 15)),
                     stamped("2d6", at: at(cal, 24, 10))]
        let groups = summarizedDayGroups(namedDayGroups(Array(rolls.reversed()),
                                                        names: [:],
                                                        now: now, calendar: cal),
                                         now: now, calendar: cal)
        let group = try #require(groups.first)
        #expect(group.title == "Today - 2 sessions \u{00B7} 2 rolls")
        let text = dayShareText(group)
        #expect(text.hasPrefix("Today - 2 sessions \u{00B7} 2 rolls\n\n"))
        let lines = text.components(separatedBy: "\n")
        #expect(lines[2].contains("2d6: 10"))
        #expect(lines[3].contains("d20: 10"))
    }

    // 2.93.0: the day copy carries a noted roll's note under its line.
    @Test func dayShareTextCarriesRollNotes() throws {
        let cal = utc
        let now = at(cal, 24, 21)
        var noted = stamped("8d6", at: at(cal, 24, 15))
        noted.label = "Fireball"
        noted.note = "The bridge collapses behind them"
        let rolls = [noted, stamped("2d6", at: at(cal, 24, 10))]
        let groups = summarizedDayGroups(namedDayGroups(Array(rolls.reversed()),
                                                        names: [:],
                                                        now: now, calendar: cal),
                                         now: now, calendar: cal)
        let group = try #require(groups.first)
        let lines = dayShareText(group).components(separatedBy: "\n")
        let fireballIdx = try #require(lines.firstIndex(where: { $0.contains("Fireball: 10 (8d6)") }))
        #expect(lines[fireballIdx + 1] == "  The bridge collapses behind them")
    }

    // 2.78.0: the crits-only filter keeps rolls with a kept natural 20
    // or natural 1; an unkept advantage die is not a crit the table saw.
    @Test func critRollsKeepOnlyTableSeenCrits() {
        let nat20 = RollResult(expression: "d20",
                               dice: [DieResult(sides: 20, value: 20, kept: true)],
                               modifier: 0, total: 20, alternateTotal: nil)
        let nat1 = RollResult(expression: "d20",
                              dice: [DieResult(sides: 20, value: 1, kept: true)],
                              modifier: 0, total: 1, alternateTotal: nil)
        let droppedCrit = RollResult(expression: "d20",
                                     dice: [DieResult(sides: 20, value: 20, kept: false),
                                            DieResult(sides: 20, value: 7, kept: true)],
                                     modifier: 0, total: 7, alternateTotal: 20)
        let plain = RollResult(expression: "2d6",
                               dice: [DieResult(sides: 6, value: 6, kept: true)],
                               modifier: 0, total: 6, alternateTotal: nil)
        let crits = [nat20, nat1, droppedCrit, plain].critRolls
        #expect(crits.count == 2)
        #expect(crits.contains { $0.total == 20 })
        #expect(crits.contains { $0.total == 1 })
    }

    // 2.79.0: per-roll delete removes only the first matching entry; an
    // absent roll leaves the log unchanged.
    @Test func removingFirstDeletesOnlyTheFirstMatch() {
        let a = RollResult(expression: "d20",
                           dice: [DieResult(sides: 20, value: 12, kept: true)],
                           modifier: 0, total: 12, alternateTotal: nil)
        let b = RollResult(expression: "2d6",
                           dice: [DieResult(sides: 6, value: 4, kept: true)],
                           modifier: 0, total: 4, alternateTotal: nil)
        let absent = RollResult(expression: "d8",
                                dice: [DieResult(sides: 8, value: 3, kept: true)],
                                modifier: 0, total: 3, alternateTotal: nil)
        let log = [a, b, a]
        let once = log.removingFirst(a)
        #expect(once == [b, a])
        #expect(once.removingFirst(a) == [b])
        #expect(once.removingFirst(absent) == once)
    }

    // 2.80.0: per-session delete drops one instance per removed entry -
    // duplicates elsewhere in the log survive.
    @Test func removingAllDropsOneInstancePerEntry() {
        let a = RollResult(expression: "d20",
                           dice: [DieResult(sides: 20, value: 12, kept: true)],
                           modifier: 0, total: 12, alternateTotal: nil)
        let b = RollResult(expression: "2d6",
                           dice: [DieResult(sides: 6, value: 4, kept: true)],
                           modifier: 0, total: 4, alternateTotal: nil)
        let log = [a, b, a, b]
        #expect(log.removingAll(in: [a, b]) == [a, b])
        #expect(log.removingAll(in: [a, a]) == [b, b])
        #expect(log.removingAll(in: []) == log)
    }

    // 2.82.0: edit roll label renames the first matching entry; blank
    // clears the label back to the expression, whitespace-only too.
    @Test func relabelingFirstRenamesAndClears() {
        var a = RollResult(expression: "d20",
                           dice: [DieResult(sides: 20, value: 12, kept: true)],
                           modifier: 0, total: 12, alternateTotal: nil)
        a.label = "Stealth check"
        let b = RollResult(expression: "2d6",
                           dice: [DieResult(sides: 6, value: 4, kept: true)],
                           modifier: 0, total: 4, alternateTotal: nil)
        let log = [a, b]
        let renamed = log.relabelingFirst(a, to: " Stealth, with boots ")
        #expect(renamed[0].label == "Stealth, with boots")
        #expect(renamed[1].label == nil)
        let cleared = renamed.relabelingFirst(renamed[0], to: "   ")
        #expect(cleared[0].label == nil)
        #expect(log.relabelingFirst(a, to: "X")[0].label == "X")
    }

    // 2.92.0: noting sets the story under the label, blank clears it,
    /// and an absent roll leaves the log unchanged.
    @Test func notingFirstNotesAndClears() {
        let a = RollResult(expression: "8d6",
                           dice: [DieResult(sides: 6, value: 5, kept: true)],
                           modifier: 0, total: 27, alternateTotal: nil)
        let b = RollResult(expression: "d20",
                           dice: [DieResult(sides: 20, value: 11, kept: true)],
                           modifier: 0, total: 11, alternateTotal: nil)
        let absent = RollResult(expression: "d8",
                                dice: [DieResult(sides: 8, value: 3, kept: true)],
                                modifier: 0, total: 3, alternateTotal: nil)
        let log = [a, b]
        let noted = log.notingFirst(a, to: "The bridge collapses behind them")
        #expect(noted[0].note == "The bridge collapses behind them")
        #expect(noted[1].note == nil)
        let cleared = noted.notingFirst(noted[0], to: "   ")
        #expect(cleared[0].note == nil)
        #expect(log.notingFirst(absent, to: "X") == log)
    }

    // 2.84.0: starring flips the first match on, then back to nil;
    // starredRolls filters to starred-only; an absent roll is a no-op.
    @Test func togglingStarFlipsAndClears() {
        let a = RollResult(expression: "d20",
                           dice: [DieResult(sides: 20, value: 20, kept: true)],
                           modifier: 0, total: 20, alternateTotal: nil)
        let b = RollResult(expression: "2d6",
                           dice: [DieResult(sides: 6, value: 4, kept: true)],
                           modifier: 0, total: 4, alternateTotal: nil)
        let absent = RollResult(expression: "d8",
                                dice: [DieResult(sides: 8, value: 3, kept: true)],
                                modifier: 0, total: 3, alternateTotal: nil)
        let log = [a, b]
        let starred = log.togglingStar(on: a)
        #expect(starred[0].starred == true)
        #expect(starred[1].starred == nil)
        #expect(starred.starredRolls.count == 1)
        let cleared = starred.togglingStar(on: starred[0])
        #expect(cleared[0].starred == nil)
        #expect(log.togglingStar(on: absent) == log)
    }

    // 2.86.0: clearingStars nils every star (true and false alike) and
    /// leaves the rolls themselves untouched; an empty log stays empty.
    @Test func clearingStarsClearsAll() {
        var a = RollResult(expression: "d20",
                           dice: [DieResult(sides: 20, value: 20, kept: true)],
                           modifier: 0, total: 20, alternateTotal: nil)
        a.starred = true
        var b = RollResult(expression: "2d6",
                           dice: [DieResult(sides: 6, value: 4, kept: true)],
                           modifier: 0, total: 4, alternateTotal: nil)
        b.starred = false
        let c = RollResult(expression: "d8",
                           dice: [DieResult(sides: 8, value: 3, kept: true)],
                           modifier: 0, total: 3, alternateTotal: nil)
        let cleared = [a, b, c].clearingStars()
        #expect(cleared.allSatisfy { $0.starred == nil })
        #expect(cleared.map(\.expression) == ["d20", "2d6", "d8"])
        #expect(cleared.map(\.total) == [20, 4, 3])
        #expect([RollResult]().clearingStars().isEmpty)
    }

    // 2.87.0: togglingStars stars every listed roll, leaves the rest
    /// untouched, and toggles back to nil when all are already starred.
    @Test func togglingStarsSessionWide() {
        let a = RollResult(expression: "d20",
                           dice: [DieResult(sides: 20, value: 20, kept: true)],
                           modifier: 0, total: 20, alternateTotal: nil)
        let b = RollResult(expression: "2d6",
                           dice: [DieResult(sides: 6, value: 4, kept: true)],
                           modifier: 0, total: 4, alternateTotal: nil)
        let c = RollResult(expression: "d8",
                           dice: [DieResult(sides: 8, value: 3, kept: true)],
                           modifier: 0, total: 3, alternateTotal: nil)
        let log = [a, b, c]
        let starred = log.togglingStars(on: [a, b])
        #expect(starred[0].starred == true)
        #expect(starred[1].starred == true)
        #expect(starred[2].starred == nil)
        #expect(starred.starredRolls.count == 2)
        let cleared = starred.togglingStars(on: [starred[0], starred[1]])
        #expect(cleared.allSatisfy { $0.starred == nil })
        var d = c
        d.starred = true
        let mixed = [a, d].togglingStars(on: [a, d])
        #expect(mixed.allSatisfy { $0.starred == true })
        #expect(log.togglingStars(on: []) == log)
    }

    // 2.91.0: a starred roll's reroll inherits the star on the new top;
    /// the original keeps its own star, an unstarred source carries
    /// nothing, and an unchanged top (a reroll that recorded nothing)
    /// leaves the log untouched.
    @Test func carryingStarToRerolledTop() {
        var source = RollResult(expression: "d20",
                                dice: [DieResult(sides: 20, value: 20, kept: true)],
                                modifier: 0, total: 20, alternateTotal: nil)
        source.starred = true
        let oldTop = RollResult(expression: "2d6",
                                dice: [DieResult(sides: 6, value: 4, kept: true)],
                                modifier: 0, total: 4, alternateTotal: nil)
        let rerolled = RollResult(expression: "d20",
                                  dice: [DieResult(sides: 20, value: 11, kept: true)],
                                  modifier: 0, total: 11, alternateTotal: nil)
        let log = [rerolled, oldTop, source]
        let carried = log.carryingStarToRerolledTop(from: source, previousTop: oldTop)
        #expect(carried[0].starred == true)
        #expect(carried[1].starred == nil)
        #expect(carried[2].starred == true)
        #expect(carried.starredRolls.count == 2)
        #expect(log.carryingStarToRerolledTop(from: oldTop, previousTop: oldTop) == log)
        #expect(log.carryingStarToRerolledTop(from: source, previousTop: rerolled) == log)
        #expect([RollResult]().carryingStarToRerolledTop(from: source, previousTop: nil).isEmpty)
    }

    // 2.88.0: the starred Markdown heads with the count and tables the
    /// starred rolls oldest first; unstarred rolls never reach the file.
    @Test func starredMarkdownCountsAndTables() throws {
        let t1 = try #require(ISO8601DateFormatter().date(from: "2026-09-24T20:00:00Z"))
        let t2 = try #require(ISO8601DateFormatter().date(from: "2026-09-24T21:00:00Z"))
        var a = RollResult(expression: "d20",
                           dice: [DieResult(sides: 20, value: 20, kept: true)],
                           modifier: 0, total: 20, alternateTotal: nil)
        a.label = "Death save"
        a.rolledAt = t1
        a.starred = true
        var b = RollResult(expression: "2d6",
                           dice: [DieResult(sides: 6, value: 4, kept: true)],
                           modifier: 0, total: 4, alternateTotal: nil)
        b.rolledAt = t2
        let md = starredMarkdown([b, a])
        #expect(md.hasPrefix("# Starred rolls (1)\n"))
        #expect(md.contains("| Death save (d20) | 20 |"))
        #expect(!md.contains("2d6"))
        var d = b
        d.starred = true
        let md2 = starredMarkdown([d, a])
        let aPos = try #require(md2.range(of: "Death save"))
        let dPos = try #require(md2.range(of: "2d6"))
        #expect(aPos.lowerBound < dPos.lowerBound)
        #expect(starredMarkdown([b]).hasPrefix("# Starred rolls (0)\n"))
    }

    // 2.89.0: the digest session wraps the starred rolls under a count
    /// title, newest first, ready for JournalEntry(sessionDigest:).
    @Test func starredDigestSessionWrapsReel() {
        var a = RollResult(expression: "d20",
                           dice: [DieResult(sides: 20, value: 20, kept: true)],
                           modifier: 0, total: 20, alternateTotal: nil)
        a.starred = true
        let b = RollResult(expression: "2d6",
                           dice: [DieResult(sides: 6, value: 4, kept: true)],
                           modifier: 0, total: 4, alternateTotal: nil)
        var c = RollResult(expression: "d8",
                           dice: [DieResult(sides: 8, value: 3, kept: true)],
                           modifier: 0, total: 3, alternateTotal: nil)
        c.starred = true
        let reel = [c, b, a].starredDigestSession()
        #expect(reel.title == "Starred rolls (2)")
        #expect(reel.rolls == [c, a])
        #expect(reel.key == nil)
        #expect([b].starredDigestSession().title == "Starred rolls (0)")
    }

    // 2.90.0: the Starred only range keeps starred rolls - even
    /// unstamped ones - and drops everything else.
    @Test func withinStarredKeepsOnlyStarred() throws {
        let t = try #require(ISO8601DateFormatter().date(from: "2026-09-24T20:00:00Z"))
        var a = RollResult(expression: "d20",
                           dice: [DieResult(sides: 20, value: 20, kept: true)],
                           modifier: 0, total: 20, alternateTotal: nil)
        a.starred = true
        a.rolledAt = t
        var b = RollResult(expression: "2d6",
                           dice: [DieResult(sides: 6, value: 4, kept: true)],
                           modifier: 0, total: 4, alternateTotal: nil)
        b.starred = true
        var c = RollResult(expression: "d8",
                           dice: [DieResult(sides: 8, value: 3, kept: true)],
                           modifier: 0, total: 3, alternateTotal: nil)
        c.rolledAt = t
        let out = [a, b, c].within(.starred)
        #expect(out == [a, b])
        #expect(SessionLogRange.starred.displayName == "Starred only")
    }

    // 2.85.0: the starred share text heads with the count and lists the
    /// starred rolls oldest first; an unstarred log still heads honestly.
    @Test func starredShareTextCountsAndLists() throws {
        let t = try #require(ISO8601DateFormatter().date(from: "2026-09-24T20:00:00Z"))
        var a = RollResult(expression: "d20",
                           dice: [DieResult(sides: 20, value: 20, kept: true)],
                           modifier: 0, total: 20, alternateTotal: nil)
        a.label = "Death save"
        a.rolledAt = t
        a.starred = true
        let b = RollResult(expression: "2d6",
                           dice: [DieResult(sides: 6, value: 4, kept: true)],
                           modifier: 0, total: 4, alternateTotal: nil)
        let text = [a, b].starredShareText
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count == 2)
        #expect(lines[0] == "Starred rolls (1)")
        #expect(lines[1].contains("Death save"))
        #expect(!text.contains("2d6"))
        #expect([b].starredShareText.hasPrefix("Starred rolls (0)"))
    }

    // 2.71.0: noted() carries the session note; blank clears it. The
    // note rides the copy text under the stats line and follows its
    // session's name into export headers in parentheses.
    @Test func sessionNotesRideCopyAndExports() throws {
        let cal = utc
        let now = at(cal, 24, 20)
        let rolls = [stamped("d20", at: at(cal, 24, 18)),
                     stamped("2d6", at: at(cal, 24, 17))]
        let session = sessionSegments(rolls, now: now, calendar: cal)[0]
        let noted = session.noted("The bridge over the Ember")
        #expect(noted.note == "The bridge over the Ember")
        #expect(noted.title == session.title)
        #expect(session.noted("  ").note == nil)
        // Copy text: note between the stats line and the rolls.
        let text = sessionShareText(noted)
        let lines = text.components(separatedBy: "\n")
        #expect(lines[1].hasPrefix("2 rolls"))
        #expect(lines[2] == "The bridge over the Ember")
        #expect(lines[3].isEmpty)
        // Export header: the note follows its session's name.
        let key = session.key!
        let groups = namedDayGroups(rolls, names: [key: "Night watch"],
                                    notes: [key: "The bridge over the Ember"],
                                    now: now, calendar: cal)
        #expect(groups[0].title == "Today - Night watch (The bridge over the Ember)")
        // A note without a name annotates nothing (names gate headers).
        let noteOnly = namedDayGroups(rolls, names: [:], notes: [key: "x"],
                                      now: now, calendar: cal)
        #expect(noteOnly[0].title == "Today")
    }

    // 2.72.0: the per-session Markdown file - name as heading, stats
    // line, note, then the roll table oldest first; a pipe in a label
    // escapes so the table never breaks.
    @Test func sessionMarkdownLaysOutTheSession() throws {
        let cal = utc
        let now = at(cal, 24, 20)
        var piped = stamped("d20", at: at(cal, 24, 18))
        piped.label = "Save | or suck"
        let rolls = [piped, stamped("2d6", at: at(cal, 24, 17))]
        let session = sessionSegments(rolls, now: now, calendar: cal)[0]
            .renamed("Night watch")
            .noted("The bridge over the Ember")
        let md = sessionMarkdown(session)
        let lines = md.components(separatedBy: "\n")
        #expect(lines[0] == "# Night watch")
        #expect(lines[2].hasPrefix("2 rolls"))
        #expect(lines[4] == "The bridge over the Ember")
        #expect(lines[6] == "| Time | Roll | Total |")
        #expect(lines[8].contains("| 2d6 | 10 |"))
        #expect(lines[9].contains("| Save \\| or suck (d20) | 10 |"))
    }

    // 2.74.0: the Latest session scope keeps only the newest session's
    /// rolls, in history order; empty stays empty.
    @Test func latestSessionKeepsOnlyTheNewestSession() throws {
        let cal = utc
        let now = at(cal, 24, 20)
        let rolls = [stamped("d20", at: at(cal, 24, 18)),
                     stamped("2d6", at: at(cal, 24, 17)),
                     stamped("1d6", at: at(cal, 23, 18))]
        let latest = rolls.latestSession(now: now, calendar: cal)
        #expect(latest.map(\.expression) == ["d20", "2d6"])
        #expect([RollResult]().latestSession(now: now, calendar: cal).isEmpty)
    }
}
