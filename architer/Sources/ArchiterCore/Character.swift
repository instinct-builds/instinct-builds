import Foundation

public enum Ability: String, Codable, CaseIterable, Sendable {
    case strength, dexterity, constitution, intelligence, wisdom, charisma

    public var abbreviation: String { String(rawValue.prefix(3)).uppercased() }
    public var displayName: String { rawValue.capitalized }
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

    private enum CodingKeys: String, CodingKey { case values }

    public init(from decoder: Decoder) throws {
        // Current format: {"values": {...}}. Legacy 0.1.x saves stored the
        // dictionary directly; accept both.
        if let keyed = try? decoder.container(keyedBy: CodingKeys.self),
           let v = try keyed.decodeIfPresent([Ability: Int].self, forKey: .values) {
            values = v
        } else if let dict = try? [Ability: Int](from: decoder) {
            values = dict
        } else {
            values = Dictionary(uniqueKeysWithValues: Ability.allCases.map { ($0, 10) })
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(values, forKey: .values)
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

/// An attack or weapon on the sheet. Attack and damage bonuses are derived
/// from the character's abilities and proficiency, or pinned by an override.
public struct Attack: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID = UUID()
    public var name: String
    /// Ability used for the roll; nil = finesse (better of STR/DEX).
    public var ability: Ability?
    public var proficient: Bool
    /// Pinned total attack bonus; nil = derive from ability + proficiency.
    public var bonusOverride: Int?
    public var damageExpression: String
    public var damageType: String
    public var range: String
    public var notes: String
    /// 2024-era weapon mastery trait; ignored under the 2014 era preset.
    public var mastery: WeaponMastery?
    /// Damage expression when wielded with both hands (versatile weapons), e.g. "1d10".
    public var versatileExpression: String?
    /// Whether the weapon is currently wielded two-handed.
    public var twoHanded: Bool

    public init(name: String, ability: Ability? = .strength, proficient: Bool = true,
                bonusOverride: Int? = nil, damageExpression: String = "1d6",
                damageType: String = "", range: String = "5 ft", notes: String = "",
                mastery: WeaponMastery? = nil, versatileExpression: String? = nil,
                twoHanded: Bool = false) {
        self.name = name
        self.ability = ability
        self.proficient = proficient
        self.bonusOverride = bonusOverride
        self.damageExpression = damageExpression
        self.damageType = damageType
        self.range = range
        self.notes = notes
        self.mastery = mastery
        self.versatileExpression = versatileExpression
        self.twoHanded = twoHanded
    }

    /// Back-compatible: old sheets pinned `attackBonus` (0.1.x format).
    public init(name: String, attackBonus: Int, damageExpression: String, notes: String = "") {
        self.init(name: name, ability: .strength, proficient: false,
                  bonusOverride: attackBonus, damageExpression: damageExpression, notes: notes)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        ability = try c.decodeIfPresent(Ability.self, forKey: .ability)
        proficient = try c.decodeIfPresent(Bool.self, forKey: .proficient) ?? true
        bonusOverride = try c.decodeIfPresent(Int.self, forKey: .bonusOverride)
        if bonusOverride == nil {
            // Legacy 0.1.x sheets pinned `attackBonus`.
            struct LegacyKeys: CodingKey {
                var stringValue: String
                init?(stringValue: String) { self.stringValue = stringValue }
                var intValue: Int? { nil }
                init?(intValue: Int) { nil }
            }
            if let legacy = try? decoder.container(keyedBy: LegacyKeys.self) {
                bonusOverride = try legacy.decodeIfPresent(Int.self, forKey: LegacyKeys(stringValue: "attackBonus")!)
            }
        }
        damageExpression = try c.decodeIfPresent(String.self, forKey: .damageExpression) ?? "1d6"
        damageType = try c.decodeIfPresent(String.self, forKey: .damageType) ?? ""
        range = try c.decodeIfPresent(String.self, forKey: .range) ?? "5 ft"
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        mastery = try c.decodeIfPresent(WeaponMastery.self, forKey: .mastery)
        versatileExpression = try c.decodeIfPresent(String.self, forKey: .versatileExpression)
        twoHanded = try c.decodeIfPresent(Bool.self, forKey: .twoHanded) ?? false
    }

    /// The ability actually rolled: the set ability, or the better of
    /// STR/DEX for finesse attacks.
    public func effectiveAbility(scores: AbilityScores) -> Ability {
        if let ability { return ability }
        return scores[.dexterity] >= scores[.strength] ? .dexterity : .strength
    }

    public func attackBonus(scores: AbilityScores, level: Int) -> Int {
        if let bonusOverride { return bonusOverride }
        let prof = proficient ? RulesMath.proficiencyBonus(level: level) : 0
        return scores.modifier(effectiveAbility(scores: scores)) + prof
    }

    /// Ability modifier added to damage (genre-standard for weapon attacks).
    public func damageBonus(scores: AbilityScores) -> Int {
        scores.modifier(effectiveAbility(scores: scores))
    }

    /// The dice expression currently rolled for damage: the versatile
    /// expression when wielded two-handed, otherwise the base expression.
    public var currentDamageExpression: String {
        if twoHanded, let versatileExpression { return versatileExpression }
        return damageExpression
    }

    /// Damage expression with the ability modifier folded in, e.g. "1d8+3".
    /// Pinned attacks (bonusOverride set, e.g. legacy sheets) are literal.
    public func damageString(scores: AbilityScores) -> String {
        if bonusOverride != nil { return currentDamageExpression }
        let bonus = damageBonus(scores: scores)
        if bonus == 0 { return currentDamageExpression }
        return currentDamageExpression + (bonus > 0 ? "+\(bonus)" : "\(bonus)")
    }
}

public struct InventoryItem: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID = UUID()
    public var name: String
    public var quantity: Int
    public var weight: Double?
    public var equipped: Bool
    public var attuned: Bool
    public var category: String
    public var notes: String

    public init(name: String, quantity: Int = 1, weight: Double? = nil,
                equipped: Bool = false, attuned: Bool = false, category: String = "", notes: String = "") {
        self.name = name
        self.quantity = max(0, quantity)
        self.weight = weight
        self.equipped = equipped
        self.attuned = attuned
        self.category = category
        self.notes = notes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        quantity = try c.decodeIfPresent(Int.self, forKey: .quantity) ?? 1
        weight = try c.decodeIfPresent(Double.self, forKey: .weight)
        equipped = try c.decodeIfPresent(Bool.self, forKey: .equipped) ?? false
        attuned = try c.decodeIfPresent(Bool.self, forKey: .attuned) ?? false
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }

    public var totalWeight: Double { (weight ?? 0) * Double(quantity) }
}

public struct Character: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID = UUID()
    public var name: String
    public var lineage: String       // ancestry/race, original free-text
    public var calling: String       // class/archetype, original free-text
    public var background: String
    public var alignment: String
    public var level: Int
    public var experience: Int
    public var inspiration: Bool
    public var scores: AbilityScores
    public var skills: [Skill]
    public var savingThrowProficiencies: Set<Ability>
    // Vitals
    public var maxHP: Int
    public var currentHP: Int
    public var tempHP: Int
    public var hitDiceType: Int
    public var hitDiceSpent: Int
    public var deathSaveSuccesses: Int
    public var deathSaveFailures: Int
    public var armorClass: Int           // manual AC when no armor is equipped
    public var equippedArmor: String?    // name from EquipmentLibrary
    public var shieldEquipped: Bool
    public var armorClassBonus: Int      // misc (ring, features, barkskin-like)
    public var initiativeBonus: Int      // misc initiative on top of DEX
    public var speed: Int
    public var conditions: Set<Condition>
    public var exhaustion: Int
    /// Which d20 era preset governs rest/exhaustion/weapon/prep mechanics.
    public var era: RulesetVariant
    /// Name of the spell currently being concentrated on, if any.
    public var concentratingOn: String?
    // Combat & magic
    public var attacks: [Attack]
    public var spellcasting: Spellcasting?
    // Gear & story
    public var inventory: [InventoryItem]
    /// Genre-standard cap on simultaneously attuned magic items.
    public static let attunementLimit = 3
    /// Items currently attuned.
    public var attunedCount: Int { inventory.filter(\.attuned).count }
    /// True when attuned beyond the cap (allowed, but flagged in the UI).
    public var overAttuned: Bool { attunedCount > Character.attunementLimit }
    public var currency: Currency
    public var proficienciesText: String
    public var features: [Feature]
    public var personality: Personality
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
        alignment: String = "",
        level: Int = 1,
        experience: Int = 0,
        inspiration: Bool = false,
        scores: AbilityScores = AbilityScores(),
        skills: [Skill] = Skill.defaultList,
        savingThrowProficiencies: Set<Ability> = [],
        maxHP: Int = 10,
        currentHP: Int? = nil,
        tempHP: Int = 0,
        hitDiceType: Int = 8,
        hitDiceSpent: Int = 0,
        deathSaveSuccesses: Int = 0,
        deathSaveFailures: Int = 0,
        armorClass: Int = 10,
        equippedArmor: String? = nil,
        shieldEquipped: Bool = false,
        armorClassBonus: Int = 0,
        initiativeBonus: Int = 0,
        speed: Int = 30,
        conditions: Set<Condition> = [],
        exhaustion: Int = 0,
        era: RulesetVariant = .era2014,
        concentratingOn: String? = nil,
        attacks: [Attack] = [],
        spellcasting: Spellcasting? = nil,
        inventory: [InventoryItem] = [],
        currency: Currency = Currency(),
        proficienciesText: String = "",
        features: [Feature] = [],
        personality: Personality = Personality(),
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
        self.alignment = alignment
        self.level = max(1, min(20, level))
        self.experience = max(0, experience)
        self.inspiration = inspiration
        self.scores = scores
        self.skills = skills
        self.savingThrowProficiencies = savingThrowProficiencies
        self.maxHP = max(1, maxHP)
        self.currentHP = max(0, min(self.maxHP, currentHP ?? self.maxHP))
        self.tempHP = max(0, tempHP)
        self.hitDiceType = [6, 8, 10, 12].contains(hitDiceType) ? hitDiceType : 8
        self.hitDiceSpent = max(0, hitDiceSpent)
        self.deathSaveSuccesses = max(0, min(3, deathSaveSuccesses))
        self.deathSaveFailures = max(0, min(3, deathSaveFailures))
        self.armorClass = armorClass
        self.equippedArmor = equippedArmor
        self.shieldEquipped = shieldEquipped
        self.armorClassBonus = armorClassBonus
        self.initiativeBonus = initiativeBonus
        self.speed = speed
        self.conditions = conditions
        self.era = era
        self.concentratingOn = concentratingOn
        self.exhaustion = max(0, min(era.exhaustionCap, exhaustion))
        self.attacks = attacks
        self.spellcasting = spellcasting
        self.inventory = inventory
        self.currency = currency
        self.proficienciesText = proficienciesText
        self.features = features
        self.personality = personality
        self.notes = notes
        self.layout = layout
        self.rulesetName = rulesetName
        self.customAbilities = customAbilities
        self.customSkills = customSkills
    }

    // Characters saved in earlier versions still decode; new fields default.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        lineage = try c.decode(String.self, forKey: .lineage)
        calling = try c.decode(String.self, forKey: .calling)
        background = try c.decode(String.self, forKey: .background)
        alignment = try c.decodeIfPresent(String.self, forKey: .alignment) ?? ""
        level = try c.decode(Int.self, forKey: .level)
        experience = try c.decode(Int.self, forKey: .experience)
        inspiration = try c.decodeIfPresent(Bool.self, forKey: .inspiration) ?? false
        scores = try c.decode(AbilityScores.self, forKey: .scores)
        skills = try c.decode([Skill].self, forKey: .skills)
        savingThrowProficiencies = try c.decode(Set<Ability>.self, forKey: .savingThrowProficiencies)
        maxHP = try c.decode(Int.self, forKey: .maxHP)
        currentHP = try c.decode(Int.self, forKey: .currentHP)
        tempHP = try c.decodeIfPresent(Int.self, forKey: .tempHP) ?? 0
        hitDiceType = try c.decodeIfPresent(Int.self, forKey: .hitDiceType) ?? 8
        hitDiceSpent = try c.decodeIfPresent(Int.self, forKey: .hitDiceSpent) ?? 0
        deathSaveSuccesses = try c.decodeIfPresent(Int.self, forKey: .deathSaveSuccesses) ?? 0
        deathSaveFailures = try c.decodeIfPresent(Int.self, forKey: .deathSaveFailures) ?? 0
        armorClass = try c.decode(Int.self, forKey: .armorClass)
        equippedArmor = try c.decodeIfPresent(String.self, forKey: .equippedArmor)
        shieldEquipped = try c.decodeIfPresent(Bool.self, forKey: .shieldEquipped) ?? false
        armorClassBonus = try c.decodeIfPresent(Int.self, forKey: .armorClassBonus) ?? 0
        initiativeBonus = try c.decodeIfPresent(Int.self, forKey: .initiativeBonus) ?? 0
        speed = try c.decode(Int.self, forKey: .speed)
        conditions = try c.decodeIfPresent(Set<Condition>.self, forKey: .conditions) ?? []
        era = try c.decodeIfPresent(RulesetVariant.self, forKey: .era) ?? .era2014
        concentratingOn = try c.decodeIfPresent(String.self, forKey: .concentratingOn)
        let rawExhaustion = try c.decodeIfPresent(Int.self, forKey: .exhaustion) ?? 0
        exhaustion = max(0, min(era.exhaustionCap, rawExhaustion))
        attacks = try c.decode([Attack].self, forKey: .attacks)
        spellcasting = try c.decodeIfPresent(Spellcasting.self, forKey: .spellcasting)
        inventory = try c.decode([InventoryItem].self, forKey: .inventory)
        currency = try c.decodeIfPresent(Currency.self, forKey: .currency) ?? Currency()
        proficienciesText = try c.decodeIfPresent(String.self, forKey: .proficienciesText) ?? ""
        features = try c.decodeIfPresent([Feature].self, forKey: .features) ?? []
        personality = try c.decodeIfPresent(Personality.self, forKey: .personality) ?? Personality()
        notes = try c.decode(String.self, forKey: .notes)
        layout = try c.decode(SheetLayout.self, forKey: .layout)
        rulesetName = try c.decodeIfPresent(String.self, forKey: .rulesetName)
        customAbilities = try c.decodeIfPresent([CustomAbility].self, forKey: .customAbilities) ?? []
        customSkills = try c.decodeIfPresent([CustomSkill].self, forKey: .customSkills) ?? []
    }

    // MARK: Derived stats

    public var proficiencyBonus: Int { RulesMath.proficiencyBonus(level: level) }
    public var initiative: Int { scores.modifier(.dexterity) + initiativeBonus }
    public var passivePerception: Int {
        let skill = skills.first { $0.name == "Perception" }
        return 10 + (skill?.bonus(scores: scores, level: level) ?? scores.modifier(.wisdom))
    }

    /// Equipped-armor AC when armor is worn, else manual AC; shield and misc
    /// bonuses always apply.
    public var computedAC: Int {
        var ac: Int
        if let armorName = equippedArmor, let def = EquipmentLibrary.armor(named: armorName), def.category != .shield {
            let dex = scores.modifier(.dexterity)
            let contribution = def.addDex ? min(dex, def.maxDexBonus ?? dex) : 0
            ac = def.baseAC + contribution
        } else {
            ac = armorClass
        }
        if shieldEquipped { ac += 2 }
        return ac + armorClassBonus
    }

    public var hitDiceTotal: Int { level }
    public var hitDiceRemaining: Int { max(0, hitDiceTotal - hitDiceSpent) }

    public var totalWeight: Double {
        inventory.reduce(0) { $0 + $1.totalWeight }
    }
    public var carryingCapacity: Int { RulesMath.carryingCapacity(strength: scores[.strength]) }
    public var encumbrance: Encumbrance {
        let w = totalWeight
        let cap = Double(carryingCapacity)
        if cap <= 0 { return w > 0 ? .overCapacity : .normal }
        if w > cap * 2 { return .overCapacity }
        if w > cap { return .heavilyEncumbered }
        if w > cap * 2 / 3 { return .encumbered }
        return .normal
    }

    public var xpToNextLevel: Int? {
        guard let next = RulesMath.xpForNextLevel(level) else { return nil }
        return max(0, next - experience)
    }

    public var isAlive: Bool { currentHP > 0 || deathSaveFailures < 3 }

    public func savingThrow(_ a: Ability) -> Int {
        scores.modifier(a) + (savingThrowProficiencies.contains(a) ? proficiencyBonus : 0)
    }

    // MARK: Vitals

    /// Damage eats temporary HP first, then real HP. Falling to 0 clears temp.
    public mutating func applyDamage(_ amount: Int) {
        var remaining = max(0, amount)
        if tempHP > 0 {
            let absorbed = min(tempHP, remaining)
            tempHP -= absorbed
            remaining -= absorbed
        }
        currentHP = max(0, currentHP - remaining)
        if currentHP == 0 {
            deathSaveSuccesses = 0
            deathSaveFailures = 0
        }
    }

    public mutating func applyHealing(_ amount: Int) {
        let before = currentHP
        currentHP = min(maxHP, currentHP + max(0, amount))
        if before == 0 && currentHP > 0 {
            deathSaveSuccesses = 0
            deathSaveFailures = 0
        }
    }

    /// Temporary HP never stacks: take the better pool.
    public mutating func gainTempHP(_ amount: Int) {
        tempHP = max(tempHP, max(0, amount))
    }

    // MARK: Rests

    /// Short rest: pact slots return, short-rest features recharge.
    public mutating func shortRest() {
        if spellcasting?.progression == .pact { spellcasting?.restoreAllSlots() }
        for i in features.indices where features[i].recharge == .shortRest {
            features[i].rechargeUses()
        }
    }

    /// Spend one hit die: returns the notation to roll ("1d8+2").
    public func hitDieRollExpression() -> String? {
        guard hitDiceRemaining > 0 else { return nil }
        let con = scores.modifier(.constitution)
        return "1d\(hitDiceType)" + (con >= 0 ? "+\(con)" : "\(con)")
    }

    /// Record a spent hit die and apply the healing rolled for it.
    public mutating func spendHitDie(healingRolled: Int) {
        guard hitDiceRemaining > 0 else { return }
        hitDiceSpent += 1
        applyHealing(max(1, healingRolled))
    }

    /// Long rest: full HP, spent hit dice return per the era preset (half in
    /// the 2014 style, all in the 2024 style, min 1), all slots, death saves
    /// reset, long-rest features recharge.
    public mutating func longRest() {
        currentHP = maxHP
        hitDiceSpent = max(0, hitDiceSpent - era.longRestDiceRecovered(total: hitDiceTotal))
        deathSaveSuccesses = 0
        deathSaveFailures = 0
        spellcasting?.restoreAllSlots()
        for i in features.indices where features[i].recharge == .longRest || features[i].recharge == .dawn {
            features[i].rechargeUses()
        }
        if exhaustion > 0 { exhaustion -= 1 }
    }

    /// Start concentrating on a spell; any previous concentration ends.
    public mutating func beginConcentration(on spellName: String) {
        concentratingOn = spellName
    }

    public mutating func dropConcentration() {
        concentratingOn = nil
    }

    /// Level up by one: max HP rises by the (rolled or average) gain, current
    /// HP rises with it, and the milestone lands in notes.
    public mutating func levelUp(hpGain: Int) {
        guard level < 20 else { return }
        level += 1
        let gain = max(1, hpGain)
        maxHP += gain
        currentHP += gain
        notes = (notes.isEmpty ? "" : notes + "\n") + "Reached level \(level) (+\(gain) HP)."
    }

    /// Average HP gain on a level-up (genre-standard: half the die + 1 + CON).
    public var averageLevelUpHP: Int {
        max(1, hitDiceType / 2 + 1 + scores.modifier(.constitution))
    }

    /// What kind of d20 roll is being made, for condition side effects.
    public enum D20RollKind: String, Sendable {
        case check, attack, save
    }

    /// Conditions that impose disadvantage on the given roll kind.
    /// Original modeling of the genre-standard side effects: poisoned and
    /// frightened hinder checks; blinded, poisoned, prone, restrained and
    /// frightened hinder attacks. Saves are left to the era preset (the
    /// 2014-style exhaustion track covers them by note).
    public func disadvantageSources(for kind: D20RollKind) -> [Condition] {
        conditions.filter {
            switch kind {
            case .check: return $0.hindersChecks
            case .attack: return $0.hindersAttacks
            case .save: return false
            }
        }.sorted { $0.rawValue < $1.rawValue }
    }

    /// Effective roll mode after condition side effects: disadvantage from a
    /// condition and a chosen advantage cancel to normal (genre-standard).
    public func effectiveRollMode(_ chosen: RollMode, for kind: D20RollKind) -> RollMode {
        let hindered = !disadvantageSources(for: kind).isEmpty
        switch (chosen, hindered) {
        case (.disadvantage, _), (.normal, true): return .disadvantage
        case (.advantage, true): return .normal
        case (.advantage, false): return .advantage
        case (.normal, false): return .normal
        }
    }

    /// Flat d20 penalty from exhaustion under the current era (2024 style).
    public var exhaustionRollPenalty: Int {
        era.exhaustionRollPenalty(level: exhaustion)
    }

    /// What the current exhaustion step means under the current era.
    public var exhaustionStepNote: String {
        era.exhaustionStepNote(level: exhaustion)
    }

    /// Prepared-spell limit under the current era, for prepared casters.
    public var preparedSpellLimit: Int? {
        guard let sc = spellcasting else { return nil }
        return era.preparedLimit(casterLevel: level, castingModifier: scores.modifier(sc.ability))
    }

    /// HP roll expression for a level-up ("1d10+2"), independent of dice left.
    public var levelUpRollExpression: String {
        let con = scores.modifier(.constitution)
        return "1d\(hitDiceType)" + (con >= 0 ? "+\(con)" : "\(con)")
    }

    // MARK: Experience

    /// Award XP; returns true when the character crossed into a new level.
    @discardableResult
    public mutating func addXP(_ amount: Int) -> Bool {
        let before = level
        experience = max(0, experience + max(0, amount))
        level = RulesMath.level(forXP: experience)
        return level > before
    }
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
