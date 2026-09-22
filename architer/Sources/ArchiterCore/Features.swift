import Foundation

/// When a limited-use feature recharges.
public enum Recharge: String, Codable, CaseIterable, Sendable {
    case none, shortRest, longRest, dawn

    public var displayName: String {
        switch self {
        case .none: return "No recharge"
        case .shortRest: return "Short rest"
        case .longRest: return "Long rest"
        case .dawn: return "Dawn"
        }
    }
}

/// A class/lineage/background feature or trait, with optional limited uses.
public struct Feature: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID = UUID()
    public var name: String
    public var source: String
    public var detail: String
    /// 0 = unlimited use.
    public var usesMax: Int
    public var usesUsed: Int
    public var recharge: Recharge

    public init(name: String, source: String = "", detail: String = "",
                usesMax: Int = 0, usesUsed: Int = 0, recharge: Recharge = .none) {
        self.name = name
        self.source = source
        self.detail = detail
        self.usesMax = max(0, usesMax)
        self.usesUsed = max(0, usesUsed)
        self.recharge = recharge
    }

    public var usesRemaining: Int? {
        usesMax > 0 ? max(0, usesMax - usesUsed) : nil
    }

    public mutating func expendUse() {
        if usesMax > 0, usesUsed < usesMax { usesUsed += 1 }
    }

    public mutating func rechargeUses() { usesUsed = 0 }
}

/// The roleplay half of the sheet: personality, appearance, and story.
public struct Personality: Codable, Equatable, Sendable {
    public var traits: String
    public var ideals: String
    public var bonds: String
    public var flaws: String
    public var appearance: String
    public var backstory: String
    public var allies: String
    public var treasure: String
    public var age: String
    public var height: String
    public var weight: String
    public var eyes: String
    public var hair: String

    public init(traits: String = "", ideals: String = "", bonds: String = "", flaws: String = "",
                appearance: String = "", backstory: String = "", allies: String = "", treasure: String = "",
                age: String = "", height: String = "", weight: String = "", eyes: String = "", hair: String = "") {
        self.traits = traits
        self.ideals = ideals
        self.bonds = bonds
        self.flaws = flaws
        self.appearance = appearance
        self.backstory = backstory
        self.allies = allies
        self.treasure = treasure
        self.age = age
        self.height = height
        self.weight = weight
        self.eyes = eyes
        self.hair = hair
    }

    public var isEmpty: Bool {
        [traits, ideals, bonds, flaws, appearance, backstory, allies, treasure,
         age, height, weight, eyes, hair].allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}
