import Foundation

public enum Ability: String, Codable, CaseIterable, Sendable {
    case strength, dexterity, constitution, intelligence, wisdom, charisma

    public var abbreviation: String { String(rawValue.prefix(3)).uppercased() }
    public var displayName: String { rawValue.capitalized }
}

/// The standard damage-type taxonomy; type names only, mechanics only.
public enum DamageType: String, Codable, CaseIterable, Sendable {
    case acid, bludgeoning, cold, fire, force, lightning, necrotic,
         piercing, poison, psychic, radiant, slashing, thunder

    public var displayName: String { rawValue.capitalized }
}

/// Per-character free-roller damage-type memory (2.33.0). The map stores
/// characterID.uuidString -> rawValue, with "" as an explicit "untyped"
/// choice (so a character can opt out while the table default is typed).
/// A missing entry falls back to the table-wide selection.
public func resolveFreeRollerType(map: [String: String], characterID: String?,
                                  tableDefault: DamageType?) -> DamageType? {
    guard let characterID, let stored = map[characterID] else { return tableDefault }
    return stored.isEmpty ? nil : DamageType(rawValue: stored)
}

/// Returns the map with one character's choice recorded ("" = untyped).
public func storingFreeRollerType(_ type: DamageType?, in map: [String: String],
                                  characterID: String) -> [String: String] {
    var map = map
    map[characterID] = type?.rawValue ?? ""
    return map
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

/// A tool the character is trained with. Only the training tier is stored;
/// the check's ability defaults to the per-tool pick below and can still be
/// changed per roll at the table.
public struct ToolProficiency: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID = UUID()
    public var name: String
    public var tier: ProficiencyTier
    /// The ability this tool's checks default to. Nil means no default was
    /// chosen (the UI falls back to dexterity). Optional so saves written
    /// before 2.23 decode unchanged.
    public var defaultAbility: Ability?

    public init(name: String, tier: ProficiencyTier = .proficient, defaultAbility: Ability? = nil) {
        self.name = name
        self.tier = tier
        self.defaultAbility = defaultAbility
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        tier = try c.decodeIfPresent(ProficiencyTier.self, forKey: .tier) ?? .proficient
        defaultAbility = try c.decodeIfPresent(Ability.self, forKey: .defaultAbility)
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
    /// Remaining ammunition; nil = the attack does not consume ammo.
    public var ammunition: Int?

    public init(name: String, ability: Ability? = .strength, proficient: Bool = true,
                bonusOverride: Int? = nil, damageExpression: String = "1d6",
                damageType: String = "", range: String = "5 ft", notes: String = "",
                mastery: WeaponMastery? = nil, versatileExpression: String? = nil,
                twoHanded: Bool = false, ammunition: Int? = nil) {
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
        self.ammunition = ammunition
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
        ammunition = try c.decodeIfPresent(Int.self, forKey: .ammunition)
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

/// One dated session-log entry on the sheet's journal.
public struct JournalEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID = UUID()
    /// Free-form date/session label ("Session 4 - Sep 22").
    public var date: String
    public var title: String
    public var text: String
    /// When the entry was created (2.46.0); nil for pre-2.46.0 entries,
    /// which decode unchanged and sit out of "today" session recaps.
    public var createdAt: Date? = nil

    public init(date: String = "", title: String = "", text: String = "",
                createdAt: Date? = nil) {
        self.date = date
        self.title = title
        self.text = text
        self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
    }
}

public extension JournalEntry {
    /// Export head line (2.47.0): the free-form date and title joined,
    /// with the creation time appended for stamped entries
    /// ("2026-09-24 06:51 - 4d6kh3"). Unstamped entries keep the
    /// pre-2.47.0 head.
    var exportHead: String {
        var day = date
        if let createdAt {
            let time = RollResult.historyTimeFormatter.string(from: createdAt)
            day = day.isEmpty ? time : "\(day) \(time)"
        }
        let head = [day, title].filter { !$0.isEmpty }.joined(separator: " - ")
        return head.isEmpty ? "Entry" : head
    }
}

/// Non-walking movement kinds. Genre-standard categories; walking speed
/// stays the base `speed` field.
public enum MovementMode: String, Codable, CaseIterable, Sendable {
    case fly, swim, climb, burrow

    public var displayName: String { rawValue.capitalized }
}

/// One additional movement speed, e.g. "fly 60 ft (hover)". `label` is a
/// free-text note for the source ("winged boots", "wild shape").
public struct MovementSpeed: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID = UUID()
    public var mode: MovementMode
    public var feet: Int
    public var hover: Bool
    public var label: String

    public init(mode: MovementMode, feet: Int, hover: Bool = false, label: String = "") {
        self.mode = mode
        self.feet = max(0, feet)
        self.hover = hover && mode == .fly
        self.label = label
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        mode = try c.decode(MovementMode.self, forKey: .mode)
        feet = try c.decodeIfPresent(Int.self, forKey: .feet) ?? 0
        hover = try c.decodeIfPresent(Bool.self, forKey: .hover) ?? false
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
    }

    /// "fly 60 ft (hover)"; label joins the note list when present.
    public var displayString: String { displayString(feet: feet) }

    /// Same readout with an adjusted value (e.g. after exhaustion).
    public func displayString(feet adjusted: Int) -> String {
        var notes: [String] = []
        if hover { notes.append("hover") }
        if !label.isEmpty { notes.append(label) }
        let suffix = notes.isEmpty ? "" : " (\(notes.joined(separator: ", ")))"
        return "\(mode.rawValue) \(adjusted) ft\(suffix)"
    }
}

/// A familiar, mount, pet, or hireling tracked alongside the sheet.
public struct Companion: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID = UUID()
    public var name: String
    public var kind: String
    public var maxHP: Int
    public var currentHP: Int
    public var armorClass: Int
    public var notes: String

    public init(name: String, kind: String = "", maxHP: Int = 5, currentHP: Int? = nil,
                armorClass: Int = 10, notes: String = "") {
        self.name = name
        self.kind = kind
        self.maxHP = max(1, maxHP)
        self.currentHP = max(0, min(self.maxHP, currentHP ?? self.maxHP))
        self.armorClass = armorClass
        self.notes = notes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? ""
        maxHP = try c.decodeIfPresent(Int.self, forKey: .maxHP) ?? 5
        currentHP = try c.decodeIfPresent(Int.self, forKey: .currentHP) ?? maxHP
        armorClass = try c.decodeIfPresent(Int.self, forKey: .armorClass) ?? 10
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }
}

public struct InventoryItem: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID = UUID()
    public var name: String
    public var quantity: Int
    public var weight: Double?
    public var equipped: Bool
    public var attuned: Bool
    /// Stowed (dropped, cached, left at camp) gear does not count as carried.
    public var stowed: Bool
    public var category: String
    public var notes: String

    public init(name: String, quantity: Int = 1, weight: Double? = nil,
                equipped: Bool = false, attuned: Bool = false, stowed: Bool = false,
                category: String = "", notes: String = "") {
        self.name = name
        self.quantity = max(0, quantity)
        self.weight = weight
        self.equipped = equipped
        self.attuned = attuned
        self.stowed = stowed
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
        stowed = try c.decodeIfPresent(Bool.self, forKey: .stowed) ?? false
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }

    public var totalWeight: Double { (weight ?? 0) * Double(quantity) }

    /// One unit used / restocked (2.37.0), clamped like the init. The
    /// sheet's quick buttons call these through the character binding, so
    /// every tap lands on the undo stack.
    public mutating func consumeOne() { quantity = max(0, quantity - 1) }
    public mutating func restockOne() { quantity = min(999, quantity + 1) }
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
    /// Optional character portrait (PNG data, downscaled on import). The
    /// user's own image; ARCHITER ships no artwork.
    public var portrait: Data?
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
    /// User-defined conditions active on the sheet, alongside the built-ins.
    public var customConditions: [CustomCondition]
    public var resistances: Set<DamageType>
    public var immunities: Set<DamageType>
    public var vulnerabilities: Set<DamageType>
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
    public var companions: [Companion]
    /// Extra movement modes beyond walking speed (fly, swim, climb, burrow).
    public var extraSpeeds: [MovementSpeed]
    /// Genre-standard cap on simultaneously attuned magic items.
    public static let attunementLimit = 3
    /// Items currently attuned.
    public var attunedCount: Int { inventory.filter(\.attuned).count }
    /// True when attuned beyond the cap (allowed, but flagged in the UI).
    public var overAttuned: Bool { attunedCount > Character.attunementLimit }
    public var currency: Currency
    public var proficienciesText: String
    /// Structured tool training (name + tier); armor/weapon/language
    /// proficiencies stay in the free-text field above.
    public var toolProficiencies: [ToolProficiency]
    /// Dated session-log entries shown in the journal block.
    public var journal: [JournalEntry]

    /// Move a journal entry by a relative offset (2.50.0), clamped to the
    /// array bounds; unknown ids and zero/edge moves are no-ops. Journal
    /// order is the user's explicit order: the sheet, the sheet exports,
    /// and the session recap all follow it.
    public mutating func moveJournalEntry(_ id: UUID, by offset: Int) {
        guard offset != 0, let from = journal.firstIndex(where: { $0.id == id }) else { return }
        let to = max(0, min(journal.count - 1, from + offset))
        guard to != from else { return }
        let entry = journal.remove(at: from)
        journal.insert(entry, at: to)
    }
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
        portrait: Data? = nil,
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
        customConditions: [CustomCondition] = [],
        exhaustion: Int = 0,
        era: RulesetVariant = .era2014,
        concentratingOn: String? = nil,
        attacks: [Attack] = [],
        spellcasting: Spellcasting? = nil,
        inventory: [InventoryItem] = [],
        companions: [Companion] = [],
        extraSpeeds: [MovementSpeed] = [],
        currency: Currency = Currency(),
        proficienciesText: String = "",
        toolProficiencies: [ToolProficiency] = [],
        features: [Feature] = [],
        personality: Personality = Personality(),
        notes: String = "",
        journal: [JournalEntry] = [],
        layout: SheetLayout = SheetLayout(),
        rulesetName: String? = nil,
        customAbilities: [CustomAbility] = [],
        customSkills: [CustomSkill] = [],
        resistances: Set<DamageType> = [],
        immunities: Set<DamageType> = [],
        vulnerabilities: Set<DamageType> = []
    ) {
        self.name = name
        self.lineage = lineage
        self.calling = calling
        self.background = background
        self.alignment = alignment
        self.level = max(1, min(20, level))
        self.experience = max(0, experience)
        self.inspiration = inspiration
        self.portrait = portrait
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
        self.customConditions = customConditions
        self.resistances = resistances
        self.immunities = immunities
        self.vulnerabilities = vulnerabilities
        self.era = era
        self.concentratingOn = concentratingOn
        self.exhaustion = max(0, min(era.exhaustionCap, exhaustion))
        self.attacks = attacks
        self.spellcasting = spellcasting
        self.inventory = inventory
        self.companions = companions
        self.extraSpeeds = extraSpeeds
        self.currency = currency
        self.journal = journal
        self.proficienciesText = proficienciesText
        self.toolProficiencies = toolProficiencies
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
        portrait = try c.decodeIfPresent(Data.self, forKey: .portrait)
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
        customConditions = try c.decodeIfPresent([CustomCondition].self, forKey: .customConditions) ?? []
        resistances = try c.decodeIfPresent(Set<DamageType>.self, forKey: .resistances) ?? []
        immunities = try c.decodeIfPresent(Set<DamageType>.self, forKey: .immunities) ?? []
        vulnerabilities = try c.decodeIfPresent(Set<DamageType>.self, forKey: .vulnerabilities) ?? []
        era = try c.decodeIfPresent(RulesetVariant.self, forKey: .era) ?? .era2014
        concentratingOn = try c.decodeIfPresent(String.self, forKey: .concentratingOn)
        let rawExhaustion = try c.decodeIfPresent(Int.self, forKey: .exhaustion) ?? 0
        exhaustion = max(0, min(era.exhaustionCap, rawExhaustion))
        attacks = try c.decode([Attack].self, forKey: .attacks)
        spellcasting = try c.decodeIfPresent(Spellcasting.self, forKey: .spellcasting)
        inventory = try c.decode([InventoryItem].self, forKey: .inventory)
        companions = try c.decodeIfPresent([Companion].self, forKey: .companions) ?? []
        extraSpeeds = try c.decodeIfPresent([MovementSpeed].self, forKey: .extraSpeeds) ?? []
        currency = try c.decodeIfPresent(Currency.self, forKey: .currency) ?? Currency()
        journal = try c.decodeIfPresent([JournalEntry].self, forKey: .journal) ?? []
        proficienciesText = try c.decodeIfPresent(String.self, forKey: .proficienciesText) ?? ""
        toolProficiencies = try c.decodeIfPresent([ToolProficiency].self, forKey: .toolProficiencies) ?? []
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
    public var passivePerception: Int { passiveScore(forSkill: "Perception", ability: .wisdom) }
    public var passiveInvestigation: Int { passiveScore(forSkill: "Investigation", ability: .intelligence) }
    public var passiveInsight: Int { passiveScore(forSkill: "Insight", ability: .wisdom) }
    /// Full movement readout: walk speed plus any extra modes, e.g.
    /// "30 ft, fly 60 ft (hover)".
    public var movementSummary: String {
        (["\(speed) ft"] + extraSpeeds.map(\.displayString)).joined(separator: ", ")
    }
    /// Total bonus for a tool check with the given ability: ability modifier
    /// plus proficiency/expertise when trained.
    public func toolBonus(_ tool: ToolProficiency, ability: Ability) -> Int {
        scores.modifier(ability) + tool.tier.multiplier * RulesMath.proficiencyBonus(level: level)
    }
    /// Export readout: "Thieves' tools, calligrapher's supplies (expertise)".
    public var toolSummary: String {
        toolProficiencies.map {
            $0.tier == .expert ? "\($0.name) (expertise)" : $0.name
        }.joined(separator: ", ")
    }
    /// Genre-standard: grappled or restrained (built-in) - or any custom
    /// condition flagged immobilizing - drops every speed to 0.
    public var immobilized: Bool {
        conditions.contains(.grappled) || conditions.contains(.restrained)
            || customConditions.contains(where: \.immobilizes)
    }
    /// Walking speed after exhaustion under the current era (immobilizing
    /// conditions still zero it via effectiveMovementSummary).
    public var effectiveSpeed: Int {
        era.speedAfterExhaustion(speed, level: exhaustion)
    }
    /// Standing up from prone costs half the effective speed.
    public var proneStandingCost: Int { effectiveSpeed / 2 }
    /// Movement readout after condition effects: immobilized zeroes every
    /// speed; otherwise exhaustion adjusts each mode under the current era,
    /// and prone appends its stand-up and crawl costs.
    public var effectiveMovementSummary: String {
        if immobilized { return "0 ft (immobilized)" }
        var parts = ["\(effectiveSpeed) ft"]
        parts += extraSpeeds.map {
            $0.displayString(feet: era.speedAfterExhaustion($0.feet, level: exhaustion))
        }
        if conditions.contains(.prone) {
            parts.append("prone: stand up costs \(proneStandingCost) ft, crawl at half")
        }
        return parts.joined(separator: ", ")
    }
    /// Passive value for a skill: 10 + its bonus (raw ability modifier when the
    /// sheet has no such skill). The table standard for noticing without rolling.
    public func passiveScore(forSkill name: String, ability: Ability) -> Int {
        let skill = skills.first { $0.name == name }
        return 10 + (skill?.bonus(scores: scores, level: level) ?? scores.modifier(ability))
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

    /// Weight actually carried; stowed gear is excluded.
    public var totalWeight: Double {
        inventory.filter { !$0.stowed }.reduce(0) { $0 + $1.totalWeight }
    }
    /// Weight set aside as stowed.
    public var stowedWeight: Double {
        inventory.filter(\.stowed).reduce(0) { $0 + $1.totalWeight }
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

    /// Incoming damage adjusted for immunity, resistance, and vulnerability.
    /// Resistance halves (rounded down) before temp HP absorbs anything;
    /// vulnerability doubles; immunity reduces to zero. Untyped is unchanged.
    public func adjustedDamage(_ amount: Int, type: DamageType?) -> Int {
        guard let type else { return max(0, amount) }
        if immunities.contains(type) { return 0 }
        var value = max(0, amount)
        if resistances.contains(type) { value /= 2 }
        if vulnerabilities.contains(type) { value *= 2 }
        return value
    }

    /// "resisted: 14 -> 7" style note when defenses change an incoming damage
    /// amount, nil when they don't. Used to label incoming-damage rolls.
    public func defenseAdjustmentNote(amount: Int, type: DamageType?) -> String? {
        guard let type else { return nil }
        let adjusted = adjustedDamage(amount, type: type)
        guard adjusted != max(0, amount) else { return nil }
        let word: String
        if immunities.contains(type) { word = "immune" }
        else if resistances.contains(type) && vulnerabilities.contains(type) { word = "resisted + vulnerable" }
        else if resistances.contains(type) { word = "resisted" }
        else { word = "vulnerable" }
        return "\(word): \(amount) -> \(adjusted)"
    }

    /// Outgoing-defense annotation for a damage total of the given type:
    /// what the roll deals against resistance, immunity, and vulnerability.
    /// Mirrors adjustedDamage's math (halve rounds down, double, zero).
    public static func outgoingDefenseNote(total: Int, type: DamageType) -> String {
        let amount = max(0, total)
        return "\(type.rawValue): resist \(amount / 2) - immune 0 - vuln \(amount * 2)"
    }

    /// Damage eats temporary HP first, then real HP. Falling to 0 clears temp.
    public mutating func applyDamage(_ amount: Int, type: DamageType? = nil) {
        var remaining = adjustedDamage(amount, type: type)
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

    /// Active custom conditions imposing disadvantage on the roll kind.
    public func customDisadvantageSources(for kind: D20RollKind) -> [CustomCondition] {
        customConditions.filter {
            switch kind {
            case .check: return $0.hindersChecks
            case .attack: return $0.hindersAttacks
            case .save: return false
            }
        }.sorted { $0.name < $1.name }
    }

    /// Display names of every active disadvantage source, built-ins first.
    public func disadvantageSourceNames(for kind: D20RollKind) -> [String] {
        disadvantageSources(for: kind).map(\.displayName)
            + customDisadvantageSources(for: kind).map(\.name)
    }

    /// Names of all active conditions (built-in + custom), for exports.
    public var activeConditionNames: [String] {
        conditions.map(\.displayName).sorted() + customConditions.map(\.name).sorted()
    }

    /// Effective roll mode after condition side effects: disadvantage from a
    /// condition and a chosen advantage cancel to normal (genre-standard).
    public func effectiveRollMode(_ chosen: RollMode, for kind: D20RollKind) -> RollMode {
        let hindered = !disadvantageSources(for: kind).isEmpty
            || !customDisadvantageSources(for: kind).isEmpty
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

    // MARK: Skills

    /// Add a skill; false when the name is blank or already taken (any case).
    @discardableResult
    public mutating func addSkill(name: String, ability: Ability) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              !skills.contains(where: { $0.name.lowercased() == trimmed.lowercased() })
        else { return false }
        skills.append(Skill(name: trimmed, ability: ability))
        return true
    }

    /// Remove a skill by name (the skill id).
    public mutating func removeSkill(named name: String) {
        skills.removeAll { $0.name == name }
    }

    // MARK: Ammunition

    /// Spend one unit of ammunition for an attack. Returns false when the
    /// attack is untracked or already empty. Floors at zero.
    @discardableResult
    public mutating func spendAmmunition(attackID: UUID) -> Bool {
        guard let idx = attacks.firstIndex(where: { $0.id == attackID }),
              let ammo = attacks[idx].ammunition, ammo > 0 else { return false }
        attacks[idx].ammunition = ammo - 1
        return true
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
