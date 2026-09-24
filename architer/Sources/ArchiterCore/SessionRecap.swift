import Foundation

/// Journal-entry day stamps (2.46.0). POSIX locale so exports, recaps and
/// tests agree; local timezone, matching the history formatters.
public enum JournalStamp {
    public static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// "2026-09-24" for the entry's own day.
    public static func day(_ date: Date) -> String { dayFormatter.string(from: date) }
}

/// One shareable text block joining what was written with what was rolled
/// today (2.46.0): the character's journal entries stamped today, then
/// the character's rolls from today, oldest first. Entries without a
/// createdAt stamp (pre-2.46.0 saves) and rolls without a rolledAt stamp
/// sit out - an unplaceable line inside a "today" recap would mislead.
public func sessionRecap(character: Character, rolls: [RollResult],
                         now: Date = Date(), calendar: Calendar = .current) -> String {
    // 2.50.0: the recap follows the journal's own order (the user's
    // explicit order once they nudge entries), not creation time.
    let todayEntries = character.journal
        .filter { entry in entry.createdAt.map { calendar.isDate($0, inSameDayAs: now) } ?? false }
    let todayRolls = rolls.forCharacter(character.name).within(.today, now: now, calendar: calendar)

    var lines: [String] = ["\(character.name) - session recap (\(RollResult.historyDateFormatter.string(from: now)))"]
    // 2.65.0: the character's recap preamble rides at the top when set.
    if let preamble = character.recapPreamble?.trimmingCharacters(in: .whitespacesAndNewlines),
       !preamble.isEmpty {
        lines.append(preamble)
    }
    lines.append("")
    if todayEntries.isEmpty && todayRolls.isEmpty {
        lines.append("Nothing logged today yet.")
    } else {
        if !todayEntries.isEmpty {
            lines.append("JOURNAL - Today (\(todayEntries.count))")
            for entry in todayEntries {
                let stamp = entry.createdAt.map { RollResult.historyTimeFormatter.string(from: $0) } ?? ""
                let heading = !entry.title.isEmpty ? entry.title : (!entry.date.isEmpty ? entry.date : "Entry")
                lines.append("- [\(stamp)] \(heading)")
                if !entry.text.isEmpty {
                    lines.append("  " + entry.text.replacingOccurrences(of: "\n", with: "\n  "))
                }
            }
            lines.append("")
        }
        if !todayRolls.isEmpty {
            lines.append("ROLLS - Today (\(todayRolls.count))")
            for roll in todayRolls.reversed() {
                lines.append(roll.historyLine)
            }
        }
    }
    lines.append("")
    return lines.joined(separator: "\n")
}
