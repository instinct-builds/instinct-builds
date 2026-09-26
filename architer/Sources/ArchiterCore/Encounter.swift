import Foundation

/// One row of enemies: how many at what challenge rating (3.34.0).
/// Enemy strength is entered, never inferred - the app holds no monster
/// stats. CR is a Double so the genre-standard fractions (0.125, 0.25,
/// 0.5) round-trip exactly.
public struct EncounterLine: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var count: Int
    public var cr: Double

    public init(id: UUID = UUID(), count: Int = 1, cr: Double = 1) {
        self.id = id
        self.count = count
        self.cr = cr
    }
}

/// Difficulty bands: the verdict is a word plus the raw derivation, never
/// adjudication.
public enum EncounterBand: String, Codable, CaseIterable, Sendable {
    case trivial, easy, medium, hard, deadly
    public var displayName: String { rawValue.capitalized }
}

/// Party thresholds summed over the roster's levels (explicit public init:
/// the memberwise one is internal).
public struct EncounterThresholds: Equatable, Sendable {
    public let easy: Int
    public let medium: Int
    public let hard: Int
    public let deadly: Int

    public init(easy: Int, medium: Int, hard: Int, deadly: Int) {
        self.easy = easy
        self.medium = medium
        self.hard = hard
        self.deadly = deadly
    }
}

public struct EncounterEstimate: Equatable, Sendable {
    public let thresholds: EncounterThresholds
    public let enemyCount: Int
    public let baseXP: Int
    public let multiplier: Double
    public let adjustedXP: Int
    public let band: EncounterBand

    public init(thresholds: EncounterThresholds, enemyCount: Int, baseXP: Int,
                multiplier: Double, adjustedXP: Int, band: EncounterBand) {
        self.thresholds = thresholds
        self.enemyCount = enemyCount
        self.baseXP = baseXP
        self.multiplier = multiplier
        self.adjustedXP = adjustedXP
        self.band = band
    }
}

/// Genre-standard encounter math, original code: per-level difficulty
/// thresholds, challenge-rating XP values, and the count multiplier.
public enum EncounterMath {
    /// (easy, medium, hard, deadly) per character level, 1...20.
    private static let thresholdTable: [(Int, Int, Int, Int)] = [
        (25, 50, 75, 100), (50, 100, 150, 200), (75, 150, 225, 400),
        (125, 250, 375, 500), (250, 500, 750, 1100), (300, 600, 900, 1400),
        (350, 750, 1100, 1700), (450, 900, 1400, 2100), (550, 1100, 1600, 2400),
        (600, 1200, 1900, 2800), (800, 1600, 2400, 3600), (1000, 2000, 3000, 4500),
        (1100, 2200, 3400, 5100), (1250, 2500, 3800, 5700), (1400, 2800, 4300, 6400),
        (1600, 3200, 4800, 7200), (2000, 3900, 5900, 8800), (2100, 4200, 6300, 9500),
        (2400, 4900, 7300, 10900), (2800, 5700, 8500, 12700),
    ]

    /// XP for a challenge rating; nil for a rating outside the genre-standard
    /// scale rather than a wrong value.
    public static func xp(forCR cr: Double) -> Int? {
        switch cr {
        case 0: return 10
        case 0.125: return 25
        case 0.25: return 50
        case 0.5: return 100
        case 1: return 200
        case 2: return 450
        case 3: return 700
        case 4: return 1100
        case 5: return 1800
        case 6: return 2300
        case 7: return 2900
        case 8: return 3900
        case 9: return 5000
        case 10: return 5900
        case 11: return 7200
        case 12: return 8400
        case 13: return 10000
        case 14: return 11500
        case 15: return 13000
        case 16: return 15000
        case 17: return 18000
        case 18: return 20000
        case 19: return 22000
        case 20: return 25000
        case 21: return 33000
        case 22: return 41000
        case 23: return 50000
        case 24: return 62000
        case 25: return 75000
        case 26: return 90000
        case 27: return 105000
        case 28: return 120000
        case 29: return 135000
        case 30: return 155000
        default: return nil
        }
    }

    /// More enemies are harder than raw XP says: the genre-standard count
    /// multiplier.
    public static func multiplier(forEnemyCount n: Int) -> Double {
        switch n {
        case ..<1: return 1
        case 1: return 1
        case 2: return 1.5
        case 3...6: return 2
        case 7...10: return 2.5
        case 11...14: return 3
        default: return 4
        }
    }

    public static func thresholds(forLevels levels: [Int]) -> EncounterThresholds {
        var easy = 0, medium = 0, hard = 0, deadly = 0
        for level in levels {
            let row = thresholdTable[max(1, min(20, level)) - 1]
            easy += row.0; medium += row.1; hard += row.2; deadly += row.3
        }
        return EncounterThresholds(easy: easy, medium: medium, hard: hard, deadly: deadly)
    }

    /// The estimate: nil for an empty roster or no valid enemy row - there
    /// is nothing to say.
    public static func estimate(levels: [Int], lines: [EncounterLine]) -> EncounterEstimate? {
        guard !levels.isEmpty else { return nil }
        var base = 0, n = 0
        for line in lines where line.count > 0 {
            guard let xp = xp(forCR: line.cr) else { continue }
            base += xp * line.count
            n += line.count
        }
        guard n > 0 else { return nil }
        let t = thresholds(forLevels: levels)
        let mult = multiplier(forEnemyCount: n)
        let adjusted = Int((Double(base) * mult).rounded())
        let band: EncounterBand
        switch adjusted {
        case ..<t.easy: band = .trivial
        case ..<t.medium: band = .easy
        case ..<t.hard: band = .medium
        case ..<t.deadly: band = .hard
        default: band = .deadly
        }
        return EncounterEstimate(thresholds: t, enemyCount: n, baseXP: base,
                                 multiplier: mult, adjustedXP: adjusted, band: band)
    }

    /// Display a CR: whole numbers bare, the fractions as fractions.
    public static func crText(_ cr: Double) -> String {
        switch cr {
        case 0.125: return "1/8"
        case 0.25: return "1/4"
        case 0.5: return "1/2"
        default:
            return cr == cr.rounded() ? String(Int(cr)) : String(cr)
        }
    }

    /// Parse a CR field: "1/8", "1/4", "1/2", integers, or decimals; nil
    /// for anything else.
    public static func parseCR(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        switch trimmed {
        case "1/8": return 0.125
        case "1/4": return 0.25
        case "1/2": return 0.5
        default:
            guard let v = Double(trimmed), v >= 0 else { return nil }
            return v
        }
    }
}

/// JSON persistence for the encounter rows, alongside the character files -
/// a DM revisits an encounter between sessions.
public struct EncounterStore {
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    private var fileURL: URL { directory.appendingPathComponent("encounter-lines.json") }

    public func load() -> [EncounterLine] {
        guard let data = try? Data(contentsOf: fileURL),
              let lines = try? JSONDecoder().decode([EncounterLine].self, from: data) else {
            return []
        }
        return lines
    }

    public func save(_ lines: [EncounterLine]) {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(lines) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
