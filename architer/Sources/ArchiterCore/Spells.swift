import Foundation

/// A spell on a character's sheet. All descriptive text is original.
public struct Spell: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID = UUID()
    public var name: String
    /// 0 = cantrip.
    public var level: Int
    public var school: String
    public var castingTime: String
    public var range: String
    public var duration: String
    public var components: String
    public var concentration: Bool
    public var ritual: Bool
    public var prepared: Bool
    public var detail: String

    public init(name: String, level: Int, school: String = "", castingTime: String = "1 action",
                range: String = "", duration: String = "", components: String = "V, S",
                concentration: Bool = false, ritual: Bool = false, prepared: Bool = true, detail: String = "") {
        self.name = name
        self.level = max(0, min(9, level))
        self.school = school
        self.castingTime = castingTime
        self.range = range
        self.duration = duration
        self.components = components
        self.concentration = concentration
        self.ritual = ritual
        self.prepared = prepared
        self.detail = detail
    }
}

/// How a caster's slots scale with level.
public enum CasterProgression: String, Codable, CaseIterable, Sendable {
    case full, half, third, pact

    public var displayName: String {
        switch self {
        case .full: return "Full caster"
        case .half: return "Half caster"
        case .third: return "Third caster"
        case .pact: return "Pact magic"
        }
    }

    /// Slots available for `spellLevel` at character level `level`.
    public func slots(spellLevel: Int, level: Int) -> Int {
        switch self {
        case .full:
            return RulesMath.spellSlots(casterLevel: level, spellLevel: spellLevel)
        case .half:
            return RulesMath.spellSlots(casterLevel: level / 2, spellLevel: spellLevel)
        case .third:
            return RulesMath.spellSlots(casterLevel: level / 3, spellLevel: spellLevel)
        case .pact:
            let pact = RulesMath.pactSlots(casterLevel: level)
            return spellLevel == pact.slotLevel ? pact.count : 0
        }
    }

    /// Highest spell level with any slots at this character level.
    public func maxSpellLevel(level: Int) -> Int {
        for sl in stride(from: 9, through: 1, by: -1) {
            if slots(spellLevel: sl, level: level) > 0 { return sl }
        }
        return 0
    }
}

/// The character's spellcasting state: casting ability, slot usage, spell list.
public struct Spellcasting: Codable, Equatable, Sendable {
    public var ability: Ability
    public var progression: CasterProgression
    /// Used slots per spell level (index 0 = level 1).
    public var slotsUsed: [Int]
    public var spells: [Spell]

    public init(ability: Ability = .intelligence, progression: CasterProgression = .full,
                slotsUsed: [Int]? = nil, spells: [Spell] = []) {
        self.ability = ability
        self.progression = progression
        self.slotsUsed = slotsUsed ?? [Int](repeating: 0, count: 9)
        self.spells = spells
    }

    public func slotsMax(spellLevel: Int, casterLevel: Int) -> Int {
        progression.slots(spellLevel: spellLevel, level: casterLevel)
    }

    public func slotsRemaining(spellLevel: Int, casterLevel: Int) -> Int {
        max(0, slotsMax(spellLevel: spellLevel, casterLevel: casterLevel) - slotsUsed[spellLevel - 1])
    }

    public mutating func useSlot(spellLevel: Int, casterLevel: Int) {
        guard (1...9).contains(spellLevel) else { return }
        if slotsUsed[spellLevel - 1] < slotsMax(spellLevel: spellLevel, casterLevel: casterLevel) {
            slotsUsed[spellLevel - 1] += 1
        }
    }

    public mutating func restoreSlot(spellLevel: Int) {
        guard (1...9).contains(spellLevel), slotsUsed[spellLevel - 1] > 0 else { return }
        slotsUsed[spellLevel - 1] -= 1
    }

    /// Long rest restores every slot; pact magic also recharges on a short rest.
    public mutating func restoreAllSlots() {
        slotsUsed = [Int](repeating: 0, count: 9)
    }

    public func spellAttackBonus(scores: AbilityScores, level: Int) -> Int {
        scores.modifier(ability) + RulesMath.proficiencyBonus(level: level)
    }

    public func spellSaveDC(scores: AbilityScores, level: Int) -> Int {
        8 + scores.modifier(ability) + RulesMath.proficiencyBonus(level: level)
    }

    public var cantrips: [Spell] { spells.filter { $0.level == 0 } }

    public func spells(atLevel level: Int) -> [Spell] {
        spells.filter { $0.level == level }.sorted { $0.name < $1.name }
    }
}

/// A built-in spellbook of genre-standard spells with original descriptions,
/// so the app is content-rich out of the box with no downloads or APIs.
public enum SpellLibrary {

    /// Case-insensitive search across name, school, and original detail
    /// text. Empty query returns everything, level-filtered if given.
    /// Distinct schools in the library, sorted, for filter pickers.
    public static var schools: [String] {
        Array(Set(all.map { $0.school }.filter { !$0.isEmpty })).sorted()
    }

    public static func search(_ query: String, level: Int? = nil, school: String? = nil) -> [Spell] {
        all.filter { spell in
            if let level, spell.level != level { return false }
            if let school, spell.school != school { return false }
            if query.isEmpty { return true }
            return spell.name.localizedCaseInsensitiveContains(query)
                || spell.school.localizedCaseInsensitiveContains(query)
                || spell.detail.localizedCaseInsensitiveContains(query)
        }
    }

    public static func spell(named name: String) -> Spell? {
        all.first { $0.name == name }
    }

    public static func spells(atLevel level: Int) -> [Spell] {
        all.filter { $0.level == level }
    }

    public static let all: [Spell] = [
        // Cantrips
        Spell(name: "Acid Splash", level: 0, school: "Conjuration", range: "60 ft", duration: "Instantaneous",
              detail: "Hurl a bubble of acid at one creature, or two within 5 ft of each other. Dexterity save or 1d6 acid damage. Scales at levels 5, 11, 17."),
        Spell(name: "Fire Bolt", level: 0, school: "Evocation", range: "120 ft", duration: "Instantaneous",
              detail: "Ranged spell attack for 1d10 fire damage; ignites unattended flammables. Scales at levels 5, 11, 17."),
        Spell(name: "Guidance", level: 0, school: "Divination", range: "Touch", duration: "1 minute", concentration: true,
              detail: "Touch a willing creature; once before the spell ends it adds 1d4 to one ability check."),
        Spell(name: "Light", level: 0, school: "Evocation", range: "Touch", duration: "1 hour",
              detail: "An object you touch sheds bright light in a 20-ft radius and dim light 20 ft beyond."),
        Spell(name: "Mage Hand", level: 0, school: "Conjuration", range: "30 ft", duration: "1 minute",
              detail: "A spectral hand manipulates objects, opens doors, and carries up to 10 pounds."),
        Spell(name: "Minor Illusion", level: 0, school: "Illusion", range: "30 ft", duration: "1 minute",
              detail: "Create a small sound or a static image no larger than a 5-ft cube. Investigation reveals the trick."),
        Spell(name: "Prestidigitation", level: 0, school: "Transmutation", range: "10 ft", duration: "1 hour",
              detail: "Minor magical tricks: sparks, scents, cleaning, chilling or warming small objects, tiny marks."),
        Spell(name: "Ray of Frost", level: 0, school: "Evocation", range: "60 ft", duration: "Instantaneous",
              detail: "Ranged spell attack for 1d8 cold damage and the target's speed drops 10 ft until your next turn."),
        Spell(name: "Sacred Flame", level: 0, school: "Evocation", range: "60 ft", duration: "Instantaneous",
              detail: "Dexterity save or 1d8 radiant damage; no benefit from cover. Scales at levels 5, 11, 17."),
        Spell(name: "Shocking Grasp", level: 0, school: "Evocation", range: "Touch", duration: "Instantaneous",
              detail: "Melee spell attack (advantage vs metal armor) for 1d8 lightning damage and no reactions."),
        Spell(name: "Thaumaturgy", level: 0, school: "Transmutation", range: "30 ft", duration: "1 minute",
              detail: "Minor divine wonders: booming voice, flickering flames, tremors, unlocked doors swinging open."),
        Spell(name: "Vicious Mockery", level: 0, school: "Enchantment", range: "60 ft", duration: "Instantaneous",
              detail: "Wisdom save or 1d4 psychic damage and disadvantage on its next attack roll."),
        // Level 1
        Spell(name: "Burning Hands", level: 1, school: "Evocation", range: "Self (15-ft cone)", duration: "Instantaneous",
              detail: "A cone of flame; Dexterity save for half of 3d6 fire damage. +1d6 per slot above 1st."),
        Spell(name: "Cure Wounds", level: 1, school: "Evocation", range: "Touch", duration: "Instantaneous",
              detail: "Touch a creature to restore 1d8 + spellcasting modifier hit points. +1d8 per slot above 1st."),
        Spell(name: "Detect Magic", level: 1, school: "Divination", range: "Self", duration: "10 minutes", concentration: true, ritual: true,
              detail: "Sense magic within 30 ft and see its school as a faint aura around visible bearers."),
        Spell(name: "Faerie Fire", level: 1, school: "Evocation", range: "60 ft", duration: "1 minute", concentration: true,
              detail: "Creatures in a 20-ft cube glow (Dexterity save negates); attacks against them have advantage and they can't turn invisible."),
        Spell(name: "Healing Word", level: 1, school: "Evocation", castingTime: "1 bonus action", range: "60 ft", duration: "Instantaneous",
              detail: "A creature you see regains 1d4 + spellcasting modifier hit points. +1d4 per slot above 1st."),
        Spell(name: "Identify", level: 1, school: "Divination", castingTime: "1 minute", range: "Touch", duration: "Instantaneous", components: "V, S, M (a pearl)", ritual: true,
              detail: "Learn a magic item's properties, attunement needs, and any spells affecting it or the touched creature."),
        Spell(name: "Mage Armor", level: 1, school: "Abjuration", range: "Touch", duration: "8 hours",
              detail: "An unarmored willing creature's AC becomes 13 + its Dexterity modifier."),
        Spell(name: "Magic Missile", level: 1, school: "Evocation", range: "120 ft", duration: "Instantaneous",
              detail: "Three unerring darts, 1d4+1 force damage each, split among targets as you choose. +1 dart per slot above 1st."),
        Spell(name: "Shield", level: 1, school: "Abjuration", castingTime: "1 reaction", range: "Self", duration: "1 round",
              detail: "+5 AC until the start of your next turn, including against the triggering attack; no Magic Missile damage."),
        Spell(name: "Sleep", level: 1, school: "Enchantment", castingTime: "1 action", range: "90 ft", duration: "1 minute",
              detail: "Roll 5d8; creatures within 20 ft of a chosen point fall unconscious in ascending HP order. +2d8 per slot above 1st."),
        Spell(name: "Thunderwave", level: 1, school: "Evocation", range: "Self (15-ft cube)", duration: "Instantaneous",
              detail: "Constitution save or 2d8 thunder damage and pushed 10 ft; half on success. +1d8 per slot above 1st."),
        // Level 2
        Spell(name: "Hold Person", level: 2, school: "Enchantment", range: "60 ft", duration: "1 minute", concentration: true,
              detail: "Wisdom save or paralyzed; repeats the save each turn. One extra target per slot above 2nd."),
        Spell(name: "Invisibility", level: 2, school: "Illusion", range: "Touch", duration: "1 hour", concentration: true,
              detail: "A creature and its gear turn invisible until it attacks or casts. One extra target per slot above 2nd."),
        Spell(name: "Lesser Restoration", level: 2, school: "Abjuration", range: "Touch", duration: "Instantaneous",
              detail: "End one disease or one condition: blinded, deafened, paralyzed, or poisoned."),
        Spell(name: "Misty Step", level: 2, school: "Conjuration", castingTime: "1 bonus action", range: "Self", duration: "Instantaneous",
              detail: "Teleport up to 30 ft to a space you can see."),
        Spell(name: "Scorching Ray", level: 2, school: "Evocation", range: "120 ft", duration: "Instantaneous",
              detail: "Three rays, each a ranged spell attack for 2d6 fire damage. +1 ray per slot above 2nd."),
        Spell(name: "Spider Climb", level: 2, school: "Transmutation", range: "Touch", duration: "1 hour", concentration: true,
              detail: "A willing creature climbs sheer surfaces and ceilings, hands free."),
        // Level 3
        Spell(name: "Counterspell", level: 3, school: "Abjuration", castingTime: "1 reaction", range: "60 ft", duration: "Instantaneous",
              detail: "Interrupt a casting of 3rd level or lower outright; higher spells need an ability check (DC 10 + spell level)."),
        Spell(name: "Dispel Magic", level: 3, school: "Abjuration", range: "120 ft", duration: "Instantaneous",
              detail: "End spells of 3rd level or lower on a target; higher spells need an ability check. Automatic at matching slot."),
        Spell(name: "Fireball", level: 3, school: "Evocation", range: "150 ft", duration: "Instantaneous",
              detail: "A 20-ft-radius burst; Dexterity save for half of 8d6 fire damage. +1d6 per slot above 3rd."),
        Spell(name: "Fly", level: 3, school: "Transmutation", range: "Touch", duration: "10 minutes", concentration: true,
              detail: "A willing creature gains a 60-ft fly speed. One extra target per slot above 3rd."),
        Spell(name: "Haste", level: 3, school: "Transmutation", range: "30 ft", duration: "1 minute", concentration: true,
              detail: "Target doubles speed, +2 AC, advantage on Dexterity saves, and one extra action each turn."),
        Spell(name: "Lightning Bolt", level: 3, school: "Evocation", range: "Self (100-ft line)", duration: "Instantaneous",
              detail: "A 5-ft-wide line; Dexterity save for half of 8d6 lightning damage. +1d6 per slot above 3rd."),
        Spell(name: "Revivify", level: 3, school: "Necromancy", range: "Touch", duration: "Instantaneous", components: "V, S, M (diamonds worth 300 gp)",
              detail: "Return a creature dead less than a minute to life with 1 hit point."),
        // Level 4
        Spell(name: "Banishment", level: 4, school: "Abjuration", range: "60 ft", duration: "1 minute", concentration: true,
              detail: "Charisma save or the target is sent to a harmless demiplane (or its home plane if native elsewhere)."),
        Spell(name: "Greater Invisibility", level: 4, school: "Illusion", range: "Touch", duration: "1 minute", concentration: true,
              detail: "The target stays invisible even while attacking and casting."),
        Spell(name: "Ice Storm", level: 4, school: "Evocation", range: "300 ft", duration: "Instantaneous",
              detail: "A 20-ft-radius hail; Dexterity save for half of 2d8 bludgeoning + 4d6 cold, and difficult terrain briefly."),
        Spell(name: "Polymorph", level: 4, school: "Transmutation", range: "60 ft", duration: "1 hour", concentration: true,
              detail: "Transform a creature into a beast of its level or less; it reverts at 0 hit points."),
        // Level 5
        Spell(name: "Cone of Cold", level: 5, school: "Evocation", range: "Self (60-ft cone)", duration: "Instantaneous",
              detail: "Constitution save for half of 8d8 cold damage. +1d8 per slot above 5th."),
        Spell(name: "Greater Restoration", level: 5, school: "Abjuration", range: "Touch", duration: "Instantaneous", components: "V, S, M (diamond dust worth 100 gp)",
              detail: "End one of: exhaustion level, charm, petrification, a curse, or an ability-score/HP-max reduction."),
        Spell(name: "Scrying", level: 5, school: "Divination", castingTime: "10 minutes", range: "Self", duration: "10 minutes", concentration: true,
              detail: "Spy on a creature or place you know through an invisible sensor; Wisdom save modified by familiarity."),
        Spell(name: "Teleportation Circle", level: 5, school: "Conjuration", castingTime: "1 minute", range: "10 ft", duration: "1 round",
              detail: "Open a portal to a permanent circle whose sigil you know, on the same plane."),
        // Level 6
        Spell(name: "Chain Lightning", level: 6, school: "Evocation", range: "150 ft", duration: "Instantaneous",
              detail: "Up to four targets; Dexterity save for half of 10d8 lightning damage. +1 target per slot above 6th."),
        Spell(name: "Heal", level: 6, school: "Evocation", range: "60 ft", duration: "Instantaneous",
              detail: "Restore 70 hit points and end blindness, deafness, and disease. +10 HP per slot above 6th."),
        // Level 7
        Spell(name: "Resurrection", level: 7, school: "Necromancy", castingTime: "1 hour", range: "Touch", duration: "Instantaneous", components: "V, S, M (a diamond worth 1,000 gp)",
              detail: "Return a creature dead up to a century to life at full hit points, mending mundane wounds."),
        Spell(name: "Teleport", level: 7, school: "Conjuration", range: "10 ft", duration: "Instantaneous",
              detail: "Transport up to eight willing creatures anywhere on one plane; accuracy depends on familiarity."),
        // Level 8
        Spell(name: "Dominate Monster", level: 8, school: "Enchantment", range: "60 ft", duration: "1 hour", concentration: true,
              detail: "Wisdom save or the creature is charmed and obeys your mental commands; it resaves when damaged."),
        // Level 9
        Spell(name: "Meteor Swarm", level: 9, school: "Evocation", range: "1 mile", duration: "Instantaneous",
              detail: "Four 40-ft-radius meteors; Dexterity save for half of 20d6 fire + 20d6 bludgeoning damage."),
        Spell(name: "Wish", level: 9, school: "Conjuration", range: "Self", duration: "Instantaneous",
              detail: "Rewrite reality: duplicate any spell of 8th level or lower without components, or attempt greater effects at a price."),
    ]
}
