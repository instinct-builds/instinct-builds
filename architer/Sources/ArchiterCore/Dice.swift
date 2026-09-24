import Foundation

/// A deterministic, seedable RNG so dice rolls are testable and replayable.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { self.state = seed &* 0x9E3779B97F4A7C15 &+ 1 }
    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

public enum DiceError: Error, Equatable {
    case emptyExpression
    case invalidToken(String)
    case invalidDie(String)
    case diceLimitExceeded
}

public enum RollMode: String, Codable, Sendable {
    case normal, advantage, disadvantage
}

public struct DieResult: Equatable, Codable, Sendable {
    public let sides: Int
    public let value: Int
    public let kept: Bool
}

public struct RollResult: Equatable, Codable, Sendable {
    public var expression: String
    public let dice: [DieResult]
    public let modifier: Int
    public let total: Int
    /// For advantage/disadvantage d20 rolls: both d20 results, best/worst chosen.
    public let alternateTotal: Int?
    /// What the roll was for ("Stealth check", "Longsword damage"); nil for raw notation.
    public var label: String? = nil
    /// Name of the character selected when the roll was made; nil for
    /// rolls made with no character selected (or pre-2.2 saves).
    public var characterName: String? = nil
    /// When the roll was made (2.35.0); nil for pre-2.35.0 saved rolls.
    /// Optional so old journal/history saves decode unchanged.
    public var rolledAt: Date? = nil
    /// How to make this roll again (2.40.0); nil for pre-2.40.0 rolls,
    /// which fall back to a plain reroll of the expression. Optional so
    /// old saves decode unchanged.
    public var reroll: RerollSpec? = nil
}

/// The roll path a history card replays (2.40.0).
public enum RerollKind: String, Codable, Sendable {
    /// Raw notation or a plain labeled roll.
    case plain
    /// A d20 check: mode and bonus replay, era/condition adjustments
    /// recompute against the character as they are now.
    case check
    /// A typed damage roll: the outgoing-defense note recomputes.
    case outgoingDamage
    /// Damage already taken: not rerollable (rolling again is not taking
    /// more damage). Stored so the card can hide its reroll button
    /// without sniffing the label.
    case incomingDamage
}

/// The undecorated inputs behind a roll's display label (2.40.0): the
/// label before condition tags or defense notes were folded in, the
/// requested d20 mode and bonus, and the damage-type tag. All optional
/// beyond the kind so specs stay minimal per path.
public struct RerollSpec: Equatable, Codable, Sendable {
    public var kind: RerollKind
    public var baseLabel: String?
    public var mode: RollMode?
    public var checkBonus: Int?
    /// DamageType raw value; unknown stored values fail safe to nil on
    /// reroll (2.33.0 pattern).
    public var damageType: String?

    public init(kind: RerollKind, baseLabel: String? = nil, mode: RollMode? = nil,
                checkBonus: Int? = nil, damageType: String? = nil) {
        self.kind = kind
        self.baseLabel = baseLabel
        self.mode = mode
        self.checkBonus = checkBonus
        self.damageType = damageType
    }
}

/// Reroll variant (2.43.0): how a roll-again departs from the recorded
/// inputs, picked from the card's context menu. Advantage/disadvantage
/// request a new d20 mode (conditions still apply); +/-2 shifts a check
/// bonus or appends to a plain/damage expression.
public enum RerollVariant: String, CaseIterable, Sendable {
    case same
    case advantage
    case disadvantage
    case plusTwo
    case minusTwo

    /// Context-menu label.
    public var displayName: String {
        switch self {
        case .same: return "Roll Again"
        case .advantage: return "With Advantage"
        case .disadvantage: return "With Disadvantage"
        case .plusTwo: return "With +2"
        case .minusTwo: return "With -2"
        }
    }

    /// The variants a reroll kind supports. d20 modes are check-only;
    /// incoming damage is never rerollable (2.40.0).
    public static func available(for kind: RerollKind) -> [RerollVariant] {
        switch kind {
        case .check: return RerollVariant.allCases
        case .plain, .outgoingDamage: return [.same, .plusTwo, .minusTwo]
        case .incomingDamage: return []
        }
    }
}

public extension RerollSpec {
    /// The spec adjusted for a variant (2.43.0): mode override or bonus
    /// shift. Only checks consume both fields; plain/damage variants
    /// adjust the expression instead (withRerollModifier).
    func adjusted(for variant: RerollVariant) -> RerollSpec {
        var copy = self
        switch variant {
        case .same:
            break
        case .advantage:
            copy.mode = .advantage
        case .disadvantage:
            copy.mode = .disadvantage
        case .plusTwo:
            copy.checkBonus = (checkBonus ?? 0) + 2
        case .minusTwo:
            copy.checkBonus = (checkBonus ?? 0) - 2
        }
        return copy
    }
}

public extension String {
    /// A roll expression adjusted for a +/-2 variant (2.43.0), for plain
    /// and damage rerolls where no check bonus exists.
    func withRerollModifier(_ variant: RerollVariant) -> String {
        switch variant {
        case .plusTwo: return self + " + 2"
        case .minusTwo: return self + " - 2"
        case .same, .advantage, .disadvantage: return self
        }
    }
}

public extension RollResult {
    /// Short clock time for history rows and the text export ("18:42").
    /// POSIX locale, local timezone, 24-hour: exports stay aligned and
    /// tests can pin expectations through the same formatter.
    static let historyTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()
    /// Date title for history day groups older than yesterday
    /// ("Sep 21, 2026"). Same pinning rationale as the time formatter.
    static let historyDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d, yyyy"
        return f
    }()
}

/// One day of history rows under a sticky date header (2.38.0).
public struct RollDayGroup: Equatable, Sendable {
    public let title: String
    public var rolls: [RollResult]
}

/// The group title for a roll's day: "Today", "Yesterday", a formatted
/// date, or "Undated" for rolls with no recorded time (pre-2.35.0).
/// `now` and `calendar` are injectable so tests pin the boundaries.
public func rollDayTitle(_ date: Date?, now: Date = Date(),
                         calendar: Calendar = .current) -> String {
    guard let date else { return "Undated" }
    let day = calendar.startOfDay(for: date)
    let today = calendar.startOfDay(for: now)
    if day == today { return "Today" }
    if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
       day == yesterday { return "Yesterday" }
    return RollResult.historyDateFormatter.string(from: date)
}

/// Groups a newest-first history list under day headers, preserving the
/// list's order: a new group starts whenever the title changes, so the
/// scope and text filters keep working exactly as before.
public func groupRollsByDay(_ rolls: [RollResult], now: Date = Date(),
                            calendar: Calendar = .current) -> [RollDayGroup] {
    var groups: [RollDayGroup] = []
    for roll in rolls {
        let title = rollDayTitle(roll.rolledAt, now: now, calendar: calendar)
        if let last = groups.last, last.title == title {
            groups[groups.count - 1].rolls.append(roll)
        } else {
            groups.append(RollDayGroup(title: title, rolls: [roll]))
        }
    }
    return groups
}

/// One session segment of the history (2.48.0): a run of neighbouring
/// rolls with no day change and no gap over the session threshold.
public struct RollSession: Equatable, Sendable {
    /// 1-based session number, oldest session first; 0 for undated runs.
    public let number: Int
    /// "Session 3 - Today", "Session 1 - Sep 21, 2026", or "Undated".
    public let title: String
    /// Newest roll first, matching history order.
    public var rolls: [RollResult]
}

/// Splits a newest-first history list into session segments (2.48.0): a
/// new session starts when the calendar day changes between neighbours or
/// the gap between them exceeds `gapHours` - so a table coming back after
/// a long break sees its next roll open a fresh session, and day rollover
/// always divides. Sessions never span days; the day title rides in the
/// label, keeping the 2.38.0 day headers' information. Numbering runs
/// oldest-first so a session keeps its number as newer sessions arrive.
/// Undated legacy rolls keep their own segments, unnumbered.
public func sessionSegments(_ rolls: [RollResult], now: Date = Date(),
                            calendar: Calendar = .current,
                            gapHours: Double = 4) -> [RollSession] {
    let gap = gapHours * 3600
    // Walk oldest-first so session numbers stay stable as new rolls land.
    var segments: [[RollResult]] = []
    var previous: RollResult?
    for roll in rolls.reversed() {
        let startsNew: Bool
        if let prev = previous, let prevAt = prev.rolledAt, let at = roll.rolledAt {
            startsNew = !calendar.isDate(prevAt, inSameDayAs: at)
                || at.timeIntervalSince(prevAt) > gap
        } else {
            // Undated neighbours only continue an undated run.
            startsNew = previous == nil || ((previous?.rolledAt == nil) != (roll.rolledAt == nil))
        }
        if startsNew {
            segments.append([roll])
        } else {
            segments[segments.count - 1].append(roll)
        }
        previous = roll
    }
    var result: [RollSession] = []
    var number = 0
    for segment in segments {
        if let at = segment[0].rolledAt {
            number += 1
            result.append(RollSession(number: number,
                                      title: "Session \(number) - \(rollDayTitle(at, now: now, calendar: calendar))",
                                      rolls: Array(segment.reversed())))
        } else {
            result.append(RollSession(number: 0, title: "Undated",
                                      rolls: Array(segment.reversed())))
        }
    }
    // Newest session first, matching history order.
    return Array(result.reversed())
}

/// One row of the compact-PDF session-log appendix (2.39.0).
public enum SessionLogRow: Equatable, Sendable {
    case dayHeader(String)
    case roll(String)
}

/// Chronological session-log rows for the compact-PDF appendix: oldest
/// rolls first, grouped under the same day titles as the on-screen
/// history (2.38.0), so the printed record reads like the session played.
/// Undated legacy rolls lead under "Undated".
public func sessionLogRows(_ rolls: [RollResult], now: Date = Date(),
                           calendar: Calendar = .current) -> [SessionLogRow] {
    groupRollsByDay(Array(rolls.reversed()), now: now, calendar: calendar).flatMap { group in
        [SessionLogRow.dayHeader(group.title)] + group.rolls.map { SessionLogRow.roll($0.historyLine) }
    }
}

/// Session-log appendix date range (2.41.0): which rolls the compact-PDF
/// appendix prints. Stored as a rawValue string; unknown stored values
/// fail safe to .all at the persistence layer.
public enum SessionLogRange: String, CaseIterable, Sendable {
    case all
    case today
    case last7Days

    /// Menu label.
    public var displayName: String {
        switch self {
        case .all: return "All rolls"
        case .today: return "Today"
        case .last7Days: return "Last 7 days"
        }
    }
}

/// Plain-text session log (2.42.0): the appendix's day-grouped rows as a
/// shareable text file - same rolls, same order, no PDF. Day headers flush
/// left, rolls indented two spaces, trailing newline so the file drops
/// cleanly into notes apps and chat.
public func sessionLogText(character: String, range: SessionLogRange,
                           rows: [SessionLogRow]) -> String {
    var lines = ["\(character) - Session Log (\(range.displayName))", ""]
    if rows.isEmpty {
        lines.append("No rolls in range.")
    } else {
        for row in rows {
            switch row {
            case .dayHeader(let title): lines.append(title)
            case .roll(let text): lines.append("  " + text)
            }
        }
    }
    return lines.joined(separator: "\n") + "\n"
}

/// Markdown session log (2.44.0): the same day-grouped rolls as one
/// table per day, for DMs who keep Obsidian/Notion notes. The Roll
/// column carries the label with its expression; pipes in labels are
/// escaped so a table never breaks.
public func sessionLogMarkdown(character: String, range: SessionLogRange,
                               groups: [RollDayGroup]) -> String {
    var lines = ["# \(character) - Session Log (\(range.displayName))", ""]
    if groups.isEmpty || groups.allSatisfy(\.rolls.isEmpty) {
        lines.append("No rolls in range.")
    } else {
        for group in groups {
            lines.append("## \(group.title)")
            lines.append("")
            lines.append("| Time | Roll | Total |")
            lines.append("| --- | --- | --- |")
            for roll in group.rolls {
                let stamp = roll.rolledAt
                    .map { RollResult.historyTimeFormatter.string(from: $0) } ?? ""
                let what = (roll.label.map { "\($0) (\(roll.expression))" } ?? roll.expression)
                    .replacingOccurrences(of: "|", with: "\\|")
                lines.append("| \(stamp) | \(what) | \(roll.total) |")
            }
            lines.append("")
        }
        // One trailing newline total, matching the text export: drop the
        // blank separator after the final group.
        if lines.last == "" { lines.removeLast() }
    }
    return lines.joined(separator: "\n") + "\n"
}

public extension Array where Element == RollResult {
    /// Rolls inside a session-log range (2.41.0), measured against now in
    /// the given calendar. .all keeps everything, including unstamped
    /// pre-2.35.0 rolls; ranged filters drop unstamped rolls, because an
    /// unplaceable roll inside a date range would mislead the printout.
    func within(_ range: SessionLogRange, now: Date = Date(),
                calendar: Calendar = .current) -> [RollResult] {
        switch range {
        case .all:
            return self
        case .today:
            return filter { roll in
                roll.rolledAt.map { calendar.isDate($0, inSameDayAs: now) } ?? false
            }
        case .last7Days:
            let startOfToday = calendar.startOfDay(for: now)
            guard let cutoff = calendar.date(byAdding: .day, value: -6, to: startOfToday) else {
                return self
            }
            return filter { roll in
                roll.rolledAt.map { $0 >= cutoff && $0 <= now } ?? false
            }
        }
    }
}

public extension RollResult {
    /// One session-log line (2.39.0, extracted from historyText):
    /// "[HH:mm] Stealth check: 25 (1d20+7)" when labeled, "[HH:mm] 2d6+3: 13"
    /// when not; pre-2.35.0 rolls without a stamp keep the 2.32.0 format.
    var historyLine: String {
        let stamp = rolledAt
            .map { "[\(RollResult.historyTimeFormatter.string(from: $0))] " } ?? ""
        if let label {
            return "\(stamp)\(label): \(total) (\(expression))"
        }
        return "\(stamp)\(expression): \(total)"
    }
}

public extension Array where Element == RollResult {
    /// Rolls made for one character. nil returns the full table log.
    func forCharacter(_ name: String?) -> [RollResult] {
        guard let name else { return self }
        return filter { $0.characterName == name }
    }

    /// One line per roll, oldest first, for sharing a session log:
    /// "Stealth check: 25 (1d20+7)" when labeled, "2d6+3: 13" when not.
    /// Pairs with forCharacter/matching - export exactly what you see.
    var historyText: String {
        reversed().map { $0.historyLine }.joined(separator: "\n")
    }

    /// Rolls whose label or expression contains the query, case- and
    /// diacritic-insensitive. A blank query returns everything, so the
    /// filter composes freely after forCharacter.
    func matching(_ query: String) -> [RollResult] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return self }
        return filter { roll in
            [roll.label, roll.expression].compactMap { $0 }.contains {
                $0.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
    }
}

/// Parses and evaluates dice notation: `d20`, `2d6+3`, `4d6kh3` (keep highest 3),
/// `4d6dl1` (drop lowest 1), `1d8+1d4+2`, combined with +/- and plain integers.
public struct DiceExpression: Equatable, Sendable {
    public struct Term: Equatable, Sendable {
        public var count: Int
        public var sides: Int
        /// keep highest N (nil = keep all)
        public var keepHighest: Int?
        /// drop lowest N (nil = drop none)
        public var dropLowest: Int?
        public var sign: Int
    }
    public let terms: [Term]
    public let modifier: Int
    public let source: String

    public static let maxDice = 100

    public static func parse(_ input: String) throws -> DiceExpression {
        var s = input.trimmingCharacters(in: .whitespaces).lowercased()
        if s.isEmpty { throw DiceError.emptyExpression }
        s = s.replacingOccurrences(of: " ", with: "")
        // Normalise leading sign handling
        var tokens: [(sign: Int, text: String)] = []
        var current = ""
        var sign = 1
        var first = true
        for ch in s {
            if ch == "+" || ch == "-" {
                if !current.isEmpty { tokens.append((sign, current)); current = "" }
                sign = ch == "+" ? 1 : -1
                first = false
            } else {
                current.append(ch)
            }
            if first { first = false }
        }
        if !current.isEmpty { tokens.append((sign, current)) }
        if tokens.isEmpty { throw DiceError.invalidToken(input) }

        var terms: [Term] = []
        var modifier = 0
        var diceCount = 0
        for (tsign, tok) in tokens {
            if let die = try? parseDie(tok, sign: tsign) {
                diceCount += die.count
                if diceCount > maxDice { throw DiceError.diceLimitExceeded }
                terms.append(die)
            } else if let n = Int(tok) {
                modifier += tsign * n
            } else {
                throw DiceError.invalidToken(tok)
            }
        }
        return DiceExpression(terms: terms, modifier: modifier, source: input)
    }

    /// The crit version of an expression: every dice term doubled,
    /// modifiers untouched (genre-standard critical-hit damage).
    public func doubledDice() -> String {
        var parts: [String] = []
        for t in terms {
            var term = "\(t.count * 2)d\(t.sides)"
            if let kh = t.keepHighest { term += "kh\(kh)" }
            if let dl = t.dropLowest { term += "dl\(dl)" }
            if t.sign < 0 { term = "-" + term }
            parts.append(term)
        }
        var expr = ""
        for p in parts {
            if p.hasPrefix("-") { expr += p } else { expr += (expr.isEmpty ? p : "+" + p) }
        }
        if modifier != 0 {
            expr += modifier > 0 ? "+\(modifier)" : "\(modifier)"
        }
        return expr.isEmpty ? source : expr
    }

    private static func parseDie(_ tok: String, sign: Int) throws -> Term {
        // forms: d20, 2d6, 4d6kh3, 4d6dl1
        guard let dIdx = tok.firstIndex(of: "d") else { throw DiceError.invalidDie(tok) }
        let countStr = String(tok[tok.startIndex..<dIdx])
        let count = countStr.isEmpty ? 1 : Int(countStr) ?? -1
        var rest = String(tok[tok.index(after: dIdx)...])
        var keepHighest: Int? = nil
        var dropLowest: Int? = nil
        if let kh = rest.range(of: "kh") {
            keepHighest = Int(rest[kh.upperBound...])
            rest = String(rest[..<kh.lowerBound])
        } else if let dl = rest.range(of: "dl") {
            dropLowest = Int(rest[dl.upperBound...])
            rest = String(rest[..<dl.lowerBound])
        }
        guard let sides = Int(rest), count >= 1, sides >= 2, sides <= 1000 else {
            throw DiceError.invalidDie(tok)
        }
        return Term(count: count, sides: sides, keepHighest: keepHighest, dropLowest: dropLowest, sign: sign)
    }

    public func roll<G: RandomNumberGenerator>(using rng: inout G) -> RollResult {
        var results: [DieResult] = []
        var total = modifier
        for term in terms {
            var rolled: [Int] = []
            for _ in 0..<term.count {
                rolled.append(Int.random(in: 1...term.sides, using: &rng))
            }
            var kept = [Bool](repeating: true, count: rolled.count)
            if let kh = term.keepHighest, kh < rolled.count {
                let indexed = rolled.enumerated().sorted { $0.element > $1.element }
                kept = [Bool](repeating: false, count: rolled.count)
                for i in 0..<max(0, min(kh, rolled.count)) { kept[indexed[i].offset] = true }
            }
            if let dl = term.dropLowest, dl > 0 {
                let indexed = rolled.enumerated().sorted { $0.element < $1.element }
                for i in 0..<min(dl, rolled.count) { kept[indexed[i].offset] = false }
            }
            for (i, v) in rolled.enumerated() {
                results.append(DieResult(sides: term.sides, value: v, kept: kept[i]))
                if kept[i] { total += term.sign * v }
            }
        }
        return RollResult(expression: source, dice: results, modifier: modifier, total: total, alternateTotal: nil, rolledAt: Date())
    }
}

public struct DiceRoller: Sendable {
    public var seed: UInt64?
    public init(seed: UInt64? = nil) { self.seed = seed }

    /// Roll a d20 with advantage/disadvantage/normal.
    public func rollD20(mode: RollMode, modifier: Int = 0) -> RollResult {
        var g = seededOrSystem()
        func d20() -> Int { Int.random(in: 1...20, using: &g) }
        switch mode {
        case .normal:
            let v = d20()
            return RollResult(expression: "d20", dice: [DieResult(sides: 20, value: v, kept: true)],
                              modifier: modifier, total: v + modifier, alternateTotal: nil, rolledAt: Date())
        case .advantage, .disadvantage:
            let a = d20(), b = d20()
            let chosen = mode == .advantage ? max(a, b) : min(a, b)
            let other = mode == .advantage ? min(a, b) : max(a, b)
            return RollResult(expression: "d20 \(mode.rawValue)",
                              dice: [DieResult(sides: 20, value: chosen, kept: true),
                                     DieResult(sides: 20, value: other, kept: false)],
                              modifier: modifier, total: chosen + modifier, alternateTotal: other + modifier,
                              rolledAt: Date())
        }
    }

    public func roll(_ expression: String) throws -> RollResult {
        let expr = try DiceExpression.parse(expression)
        var g = seededOrSystem()
        return expr.roll(using: &g)
    }

    /// Roll notation with a purpose label for the history log.
    public func rollLabeled(_ label: String, _ expression: String) throws -> RollResult {
        var result = try roll(expression)
        result.label = label
        return result
    }

    /// A labeled d20 check: "Stealth check", "STR save", attack rolls.
    public func check(_ label: String, bonus: Int, mode: RollMode = .normal) -> RollResult {
        var result = rollD20(mode: mode, modifier: bonus)
        result.label = label
        let sign = bonus >= 0 ? "+" : ""
        result.expression = "1d20\(sign)\(bonus)"
        return result
    }

    private func seededOrSystem() -> AnyRNG {
        if let seed { return AnyRNG(SeededGenerator(seed: seed)) }
        return AnyRNG(SystemRandomNumberGenerator())
    }
}

/// Type-erased RNG so we can switch seeded/system at runtime.
public struct AnyRNG: RandomNumberGenerator, Sendable {
    private var _next: @Sendable () -> UInt64
    public init<G: RandomNumberGenerator & Sendable>(_ g: G) {
        let box = Box(g)
        _next = { box.next() }
    }
    private final class Box<G: RandomNumberGenerator & Sendable>: @unchecked Sendable {
        private var g: G
        init(_ g: G) { self.g = g }
        func next() -> UInt64 { g.next() }
    }
    public mutating func next() -> UInt64 { _next() }
}
