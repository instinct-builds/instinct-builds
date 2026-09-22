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
        return RollResult(expression: source, dice: results, modifier: modifier, total: total, alternateTotal: nil)
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
                              modifier: modifier, total: v + modifier, alternateTotal: nil)
        case .advantage, .disadvantage:
            let a = d20(), b = d20()
            let chosen = mode == .advantage ? max(a, b) : min(a, b)
            let other = mode == .advantage ? min(a, b) : max(a, b)
            return RollResult(expression: "d20 \(mode.rawValue)",
                              dice: [DieResult(sides: 20, value: chosen, kept: true),
                                     DieResult(sides: 20, value: other, kept: false)],
                              modifier: modifier, total: chosen + modifier, alternateTotal: other + modifier)
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
