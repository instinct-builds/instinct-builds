import Foundation
import Testing
@testable import ArchiterCore

@Suite("Session recap")
struct SessionRecapTests {
    private var utc: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func entry(_ title: String, text: String = "", at: Date?) -> JournalEntry {
        JournalEntry(date: at.map { JournalStamp.day($0) } ?? "",
                     title: title, text: text, createdAt: at)
    }

    private func roll(_ expression: String, label: String? = nil,
                      character: String? = nil, at: Date?) -> RollResult {
        var r = RollResult(expression: expression, dice: [], modifier: 0, total: 10, alternateTotal: nil)
        r.label = label
        r.characterName = character
        r.rolledAt = at
        return r
    }

    @Test func recapJoinsTodayEntriesAndRolls() throws {
        let cal = utc
        let now = try #require(cal.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 18)))
        let morning = try #require(cal.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 9)))
        let earlier = try #require(cal.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 8)))
        let yesterday = try #require(cal.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 20)))
        var c = Character(name: "Wren Halloway")
        c.journal = [
            entry("Lantern Street", text: "Bressa says the key predates the Athenaeum.", at: morning),
            entry("Old session", text: "Before.", at: yesterday),
            entry("Legacy", text: "No stamp.", at: nil),
            entry("The singing vault", text: "It sang.", at: earlier),
        ]
        let rolls = [
            roll("2d6+3", character: "Wren Halloway", at: now),
            roll("8d6", label: "Fireball", character: "Wren Halloway", at: morning),
            roll("1d6", character: "Mira", at: morning),
            roll("1d4", character: "Wren Halloway", at: yesterday),
            roll("1d8", character: "Wren Halloway", at: nil),
        ]
        let text = sessionRecap(character: c, rolls: rolls, now: now, calendar: cal)
        let day = RollResult.historyDateFormatter.string(from: now)
        let t8 = RollResult.historyTimeFormatter.string(from: earlier)
        let t9 = RollResult.historyTimeFormatter.string(from: morning)
        let t18 = RollResult.historyTimeFormatter.string(from: now)
        #expect(text == """
        Wren Halloway - session recap (\(day))

        JOURNAL - Today (2)
        - [\(t8)] The singing vault
          It sang.
        - [\(t9)] Lantern Street
          Bressa says the key predates the Athenaeum.

        ROLLS - Today (2)
        [\(t9)] Fireball: 10 (8d6)
        [\(t18)] 2d6+3: 10

        """)
    }

    @Test func nothingTodaySaysSo() throws {
        let cal = utc
        let now = try #require(cal.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 18)))
        let yesterday = try #require(cal.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 20)))
        var c = Character(name: "Wren Halloway")
        c.journal = [entry("Old", text: "x", at: yesterday), entry("Legacy", at: nil)]
        let rolls = [roll("1d6", character: "Wren Halloway", at: yesterday)]
        let text = sessionRecap(character: c, rolls: rolls, now: now, calendar: cal)
        let day = RollResult.historyDateFormatter.string(from: now)
        #expect(text == """
        Wren Halloway - session recap (\(day))

        Nothing logged today yet.

        """)
    }

    @Test func multiLineEntryTextIndents() throws {
        let cal = utc
        let now = try #require(cal.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 18)))
        let morning = try #require(cal.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 9)))
        var c = Character(name: "Wren Halloway")
        c.journal = [entry("Notes", text: "line one\nline two", at: morning)]
        let text = sessionRecap(character: c, rolls: [], now: now, calendar: cal)
        let t9 = RollResult.historyTimeFormatter.string(from: morning)
        #expect(text.contains("- [\(t9)] Notes\n  line one\n  line two\n"))
    }

    @Test func createdAtDecoding() throws {
        // The pre-2.46.0 saved shape: no createdAt key at all.
        let json = #"{"date":"Session 1","title":"Start","text":"It began."}"#
        let legacy = try JSONDecoder().decode(JournalEntry.self, from: Data(json.utf8))
        #expect(legacy.createdAt == nil)
        #expect(legacy.title == "Start")
        // New entries round-trip with their stamp.
        let stamped = JournalEntry(date: "2026-09-24", title: "T", text: "x",
                                   createdAt: Date(timeIntervalSince1970: 1_790_000_000))
        let decoded = try JSONDecoder().decode(JournalEntry.self, from: JSONEncoder().encode(stamped))
        #expect(decoded == stamped)
    }
}
