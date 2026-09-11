import Foundation

public enum Ability: String, Codable, CaseIterable, Sendable {
    case strength, dexterity, constitution, intelligence, wisdom, charisma

    public var abbreviation: String { String(rawValue.prefix(3)).uppercased() }
}

/// Genre-standard tabletop math (ability modifier, proficiency scaling). Game
/// mechanics are functional rules, not copyrighted expression; all naming and
/// text here is original.
public enum RulesMath {
    public static func modifier(for score: Int) -> Int {
        // Tabletop standard: always round down, including negatives.
        let d = score - 10
        return d >= 0 ? d / 2 : (d - 1) / 2
    }

    /// Proficiency bonus by level, the widely used +2..+6 curve.
    public static func proficiencyBonus(level: Int) -> Int {
        max(2, 2 + (max(1, min(level, 20)) - 1) / 4)
    }

    /// Point-buy budget check for a simplified builder (27 points, scores 8-15).
    public static func pointBuyCost(score: Int) -> Int? {
        switch score {
        case 8: return 0
        case 9: return 1
        case 10: return 2
        case 11: return 3
        case 12: return 4
        case 13: return 5
        case 14: return 7
        case 15: return 9
        default: return nil
        }
    }
}

public enum ProficiencyTier: String, Codable, CaseIterable, Sendable {
    case none, proficient, expert

    public var multiplier: Int {
        switch self {
        case .none: return 0
        case .proficient: return 1
        case .expert: return 2
        }
    }
}

public struct Skill: Codable, Equatable, Sendable, Identifiable {
    public var id: String { name }
    public var name: String
    public var ability: Ability
    public var tier: ProficiencyTier

    public init(name: String, ability: Ability, tier: ProficiencyTier = .none) {
        self.name = name
        self.ability = ability
        self.tier = tier
    }

    public func bonus(scores: AbilityScores, level: Int) -> Int {
        RulesMath.modifier(for: scores[ability])
            + tier.multiplier * RulesMath.proficiencyBonus(level: level)
    }
}

public struct AbilityScores: Codable, Equatable, Sendable {
    private var values: [Ability: Int]

    public init(_ v: [Ability: Int] = Dictionary(uniqueKeysWithValues: Ability.allCases.map { ($0, 10) })) {
        self.values = v
    }

    public subscript(a: Ability) -> Int {
        get { values[a] ?? 10 }
        set { values[a] = newValue }
    }

    public func modifier(_ a: Ability) -> Int { RulesMath.modifier(for: self[a]) }

    public var totalPointBuyCost: Int? {
        var sum = 0
        for a in Ability.allCases {
            guard let c = RulesMath.pointBuyCost(score: self[a]) else { return nil }
            sum += c
        }
        return sum
    }
}

public struct Attack: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID = UUID()
    public var name: String
    public var attackBonus: Int
    public var damageExpression: String // e.g. "1d8+3"
    public var notes: String = ""

    public init(name: String, attackBonus: Int, damageExpression: String, notes: String = "") {
        self.name = name
        self.attackBonus = attackBonus
        self.damageExpression = damageExpression
        self.notes = notes
    }
}

public struct InventoryItem: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID = UUID()
    public var name: String
    public var quantity: Int
    public var weight: Double?
    public var notes: String = ""

    public init(name: String, quantity: Int = 1, weight: Double? = nil, notes: String = "") {
        self.name = name
        self.quantity = quantity
        self.weight = weight
        self.notes = notes
    }
}

public struct Character: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID = UUID()
    public var name: String
    public var lineage: String       // ancestry/race, original free-text
    public var calling: String       // class/archetype, original free-text
    public var background: String
    public var level: Int
    public var experience: Int
    public var scores: AbilityScores
    public var skills: [Skill]
    public var savingThrowProficiencies: Set<Ability>
    public var maxHP: Int
    public var currentHP: Int
    public var armorClass: Int
    public var speed: Int
    public var attacks: [Attack]
    public var inventory: [InventoryItem]
    public var notes: String
    public var layout: SheetLayout
    /// Custom ruleset fields (v0.3): user-defined abilities/skills, filled by
    /// applying a Ruleset or edited directly. Empty for built-in-rules games.
    public var rulesetName: String?
    public var customAbilities: [CustomAbility]
    public var customSkills: [CustomSkill]

    public init(
        name: String = "Unnamed Adventurer",
        lineage: String = "",
        calling: String = "",
        background: String = "",
        level: Int = 1,
        experience: Int = 0,
        scores: AbilityScores = AbilityScores(),
        skills: [Skill] = Skill.defaultList,
        savingThrowProficiencies: Set<Ability> = [],
        maxHP: Int = 10,
        currentHP: Int? = nil,
        armorClass: Int = 10,
        speed: Int = 30,
        attacks: [Attack] = [],
        inventory: [InventoryItem] = [],
        notes: String = "",
        layout: SheetLayout = SheetLayout(),
        rulesetName: String? = nil,
        customAbilities: [CustomAbility] = [],
        customSkills: [CustomSkill] = []
    ) {
        self.name = name
        self.lineage = lineage
        self.calling = calling
        self.background = background
        self.level = max(1, min(20, level))
        self.experience = experience
        self.scores = scores
        self.skills = skills
        self.savingThrowProficiencies = savingThrowProficiencies
        self.maxHP = max(1, maxHP)
        self.currentHP = currentHP ?? max(1, maxHP)
        self.armorClass = armorClass
        self.speed = speed
        self.attacks = attacks
        self.inventory = inventory
        self.notes = notes
        self.layout = layout
        self.rulesetName = rulesetName
        self.customAbilities = customAbilities
        self.customSkills = customSkills
    }

    // Characters saved before custom rulesets existed still decode.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        lineage = try c.decode(String.self, forKey: .lineage)
        calling = try c.decode(String.self, forKey: .calling)
        background = try c.decode(String.self, forKey: .background)
        level = try c.decode(Int.self, forKey: .level)
        experience = try c.decode(Int.self, forKey: .experience)
        scores = try c.decode(AbilityScores.self, forKey: .scores)
        skills = try c.decode([Skill].self, forKey: .skills)
        savingThrowProficiencies = try c.decode(Set<Ability>.self, forKey: .savingThrowProficiencies)
        maxHP = try c.decode(Int.self, forKey: .maxHP)
        currentHP = try c.decode(Int.self, forKey: .currentHP)
        armorClass = try c.decode(Int.self, forKey: .armorClass)
        speed = try c.decode(Int.self, forKey: .speed)
        attacks = try c.decode([Attack].self, forKey: .attacks)
        inventory = try c.decode([InventoryItem].self, forKey: .inventory)
        notes = try c.decode(String.self, forKey: .notes)
        layout = try c.decode(SheetLayout.self, forKey: .layout)
        rulesetName = try c.decodeIfPresent(String.self, forKey: .rulesetName)
        customAbilities = try c.decodeIfPresent([CustomAbility].self, forKey: .customAbilities) ?? []
        customSkills = try c.decodeIfPresent([CustomSkill].self, forKey: .customSkills) ?? []
    }

    public var proficiencyBonus: Int { RulesMath.proficiencyBonus(level: level) }
    public var initiative: Int { scores.modifier(.dexterity) }
    public var passivePerception: Int {
        let skill = skills.first { $0.name == "Perception" }
        return 10 + (skill?.bonus(scores: scores, level: level) ?? scores.modifier(.wisdom))
    }

    public func savingThrow(_ a: Ability) -> Int {
        scores.modifier(a) + (savingThrowProficiencies.contains(a) ? proficiencyBonus : 0)
    }

    public mutating func applyDamage(_ amount: Int) {
        currentHP = max(0, currentHP - max(0, amount))
    }

    public mutating func applyHealing(_ amount: Int) {
        currentHP = min(maxHP, currentHP + max(0, amount))
    }

    /// Long rest: restore HP to full.
    public mutating func longRest() { currentHP = maxHP }
}

extension Skill {
    /// An original, generic skill list for a simplified fantasy sheet.
    public static let defaultList: [Skill] = [
        Skill(name: "Athletics", ability: .strength),
        Skill(name: "Acrobatics", ability: .dexterity),
        Skill(name: "Sleight of Hand", ability: .dexterity),
        Skill(name: "Stealth", ability: .dexterity),
        Skill(name: "Arcana", ability: .intelligence),
        Skill(name: "History", ability: .intelligence),
        Skill(name: "Investigation", ability: .intelligence),
        Skill(name: "Nature", ability: .intelligence),
        Skill(name: "Religion", ability: .intelligence),
        Skill(name: "Insight", ability: .wisdom),
        Skill(name: "Medicine", ability: .wisdom),
        Skill(name: "Perception", ability: .wisdom),
        Skill(name: "Survival", ability: .wisdom),
        Skill(name: "Deception", ability: .charisma),
        Skill(name: "Intimidation", ability: .charisma),
        Skill(name: "Performance", ability: .charisma),
        Skill(name: "Persuasion", ability: .charisma),
    ]
}
