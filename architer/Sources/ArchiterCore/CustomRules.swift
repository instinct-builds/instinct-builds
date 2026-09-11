import Foundation

/// A user-defined ability for a custom ruleset (e.g. "Physique" in a sci-fi
/// game). Uses the same genre-standard modifier math as the built-in six.
public struct CustomAbility: Codable, Equatable, Sendable, Identifiable {
    public var id: String { name }
    public var name: String
    public var abbreviation: String
    public var score: Int

    public init(name: String, abbreviation: String? = nil, score: Int = 10) {
        self.name = name
        self.abbreviation = abbreviation ?? String(name.prefix(3)).uppercased()
        self.score = score
    }

    public var modifier: Int { RulesMath.modifier(for: score) }
}

/// A user-defined skill tied to a custom ability by name.
public struct CustomSkill: Codable, Equatable, Sendable, Identifiable {
    public var id: String { name }
    public var name: String
    public var abilityName: String
    public var tier: ProficiencyTier

    public init(name: String, abilityName: String, tier: ProficiencyTier = .none) {
        self.name = name
        self.abilityName = abilityName
        self.tier = tier
    }

    public func bonus(abilities: [CustomAbility], level: Int) -> Int {
        let mod = abilities.first { $0.name == abilityName }?.modifier ?? 0
        return mod + tier.multiplier * RulesMath.proficiencyBonus(level: level)
    }
}

public struct CustomSkillDef: Codable, Equatable, Sendable {
    public var name: String
    public var abilityName: String
    public init(name: String, abilityName: String) {
        self.name = name
        self.abilityName = abilityName
    }
}

/// A ruleset template: applying one fills a character's custom abilities and
/// custom skills so a group can play something other than the built-in list.
public struct Ruleset: Codable, Equatable, Sendable {
    public var name: String
    public var abilities: [String]
    public var skills: [CustomSkillDef]

    public init(name: String, abilities: [String], skills: [CustomSkillDef]) {
        self.name = name
        self.abilities = abilities
        self.skills = skills
    }

    /// Original example ruleset for a pulp space-adventure game.
    public static let starfarer = Ruleset(
        name: "Starfarer",
        abilities: ["Physique", "Reflex", "Logic", "Presence"],
        skills: [
            CustomSkillDef(name: "Piloting", abilityName: "Reflex"),
            CustomSkillDef(name: "Zero-G Maneuver", abilityName: "Reflex"),
            CustomSkillDef(name: "Astronavigation", abilityName: "Logic"),
            CustomSkillDef(name: "Engineering", abilityName: "Logic"),
            CustomSkillDef(name: "Xenology", abilityName: "Logic"),
            CustomSkillDef(name: "Haggling", abilityName: "Presence"),
            CustomSkillDef(name: "Command", abilityName: "Presence"),
            CustomSkillDef(name: "Salvage", abilityName: "Physique"),
        ])

    /// Original example ruleset for a light investigative game.
    public static let gumshoe = Ruleset(
        name: "Gumshoe",
        abilities: ["Grit", "Finesse", "Smarts", "Charm"],
        skills: [
            CustomSkillDef(name: "Shadowing", abilityName: "Finesse"),
            CustomSkillDef(name: "Lockwork", abilityName: "Finesse"),
            CustomSkillDef(name: "Research", abilityName: "Smarts"),
            CustomSkillDef(name: "Deduction", abilityName: "Smarts"),
            CustomSkillDef(name: "Interrogation", abilityName: "Charm"),
            CustomSkillDef(name: "Streetwise", abilityName: "Charm"),
            CustomSkillDef(name: "Scuffling", abilityName: "Grit"),
        ])
}

extension Character {
    /// Fills the custom-ruleset fields from a template. Existing custom
    /// scores are kept when an ability name carries over.
    public mutating func apply(ruleset: Ruleset) {
        rulesetName = ruleset.name
        let old = customAbilities
        customAbilities = ruleset.abilities.map { name in
            CustomAbility(name: name, score: old.first { $0.name == name }?.score ?? 10)
        }
        customSkills = ruleset.skills.map { CustomSkill(name: $0.name, abilityName: $0.abilityName) }
    }
}

/// Renders `{placeholder}` templates against a character, for user-defined
/// sheet blocks. Unknown placeholders stay visible as `[?name]` instead of
/// vanishing silently.
///
/// Supported: {name} {lineage} {calling} {background} {level} {xp} {prof}
/// {hp} {maxhp} {ac} {init} {speed} {passiveperception}
/// {str}/{dex}/{con}/{int}/{wis}/{cha} and their {.mod} signed modifiers,
/// and {c.<custom ability name>} / {c.<name>.mod} for ruleset abilities.
public enum TemplateRenderer {

    public static func render(_ template: String, for c: Character) -> String {
        var out = ""
        var rest = Substring(template)
        while let open = rest.firstIndex(of: "{") {
            out += rest[..<open]
            guard let close = rest[open...].firstIndex(of: "}") else {
                out += rest[open...]
                return out
            }
            let key = String(rest[rest.index(after: open)..<close])
            out += value(for: key, in: c) ?? "[?\(key)]"
            rest = rest[rest.index(after: close)...]
        }
        out += rest
        return out
    }

    private static func value(for rawKey: String, in c: Character) -> String? {
        let key = rawKey.trimmingCharacters(in: .whitespaces).lowercased()
        switch key {
        case "name": return c.name
        case "lineage": return c.lineage
        case "calling": return c.calling
        case "background": return c.background
        case "level": return "\(c.level)"
        case "xp": return "\(c.experience)"
        case "prof": return "+\(c.proficiencyBonus)"
        case "hp": return "\(c.currentHP)"
        case "maxhp": return "\(c.maxHP)"
        case "ac": return "\(c.armorClass)"
        case "init": return signed(c.initiative)
        case "speed": return "\(c.speed)"
        case "passiveperception": return "\(c.passivePerception)"
        default: break
        }
        if key.hasPrefix("c.") {
            let body = String(key.dropFirst(2))
            let isMod = body.hasSuffix(".mod")
            let abilityName = isMod ? String(body.dropLast(4)) : body
            guard let ability = c.customAbilities.first(where: { $0.name.lowercased() == abilityName }) else {
                return nil
            }
            return isMod ? signed(ability.modifier) : "\(ability.score)"
        }
        let isMod = key.hasSuffix(".mod")
        let base = isMod ? String(key.dropLast(4)) : key
        guard let ability = Ability.allCases.first(where: { $0.abbreviation.lowercased() == base }) else {
            return nil
        }
        return isMod ? signed(c.scores.modifier(ability)) : "\(c.scores[ability])"
    }

    private static func signed(_ n: Int) -> String { n >= 0 ? "+\(n)" : "\(n)" }
}
