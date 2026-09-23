import Foundation

public enum ArmorCategory: String, Codable, CaseIterable, Sendable {
    case light, medium, heavy, shield
}

/// A suit of armor from the built-in library. Functional stats, original names
/// follow genre-standard conventions.
public struct ArmorDef: Codable, Equatable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let category: ArmorCategory
    public let baseAC: Int
    public let addDex: Bool
    /// Medium armor caps the Dexterity contribution (usually +2). nil = uncapped.
    public let maxDexBonus: Int?
    public let weight: Double
    public let cost: String

    public init(name: String, category: ArmorCategory, baseAC: Int, addDex: Bool,
                maxDexBonus: Int? = nil, weight: Double, cost: String) {
        self.name = name
        self.category = category
        self.baseAC = baseAC
        self.addDex = addDex
        self.maxDexBonus = maxDexBonus
        self.weight = weight
        self.cost = cost
    }
}

/// A weapon from the built-in library.
public struct WeaponDef: Codable, Equatable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let damageExpression: String
    public let damageType: String
    public let range: String
    /// Strength-based unless finesse, which uses the better of STR/DEX.
    public let finesse: Bool
    public let properties: String
    public let weight: Double
    public let cost: String

    public init(name: String, damageExpression: String, damageType: String, range: String = "5 ft",
                finesse: Bool = false, properties: String = "", weight: Double, cost: String) {
        self.name = name
        self.damageExpression = damageExpression
        self.damageType = damageType
        self.range = range
        self.finesse = finesse
        self.properties = properties
        self.weight = weight
        self.cost = cost
    }
}

/// Plain adventuring gear.
public struct GearDef: Codable, Equatable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let weight: Double
    public let cost: String

    public init(name: String, weight: Double, cost: String) {
        self.name = name
        self.weight = weight
        self.cost = cost
    }
}

public enum EquipmentLibrary {

    /// Case-insensitive weapon search across name, damage type, and
    /// Case-insensitive weapon search across name, damage type, and
    /// properties. Empty query returns everything, damage-type-filtered if given.
    /// Distinct weapon damage types in the library, sorted, for filter pickers.
    public static var weaponDamageTypes: [String] {
        Array(Set(weapons.map { $0.damageType }.filter { !$0.isEmpty })).sorted()
    }

    public static func searchWeapons(_ query: String, damageType: String? = nil) -> [WeaponDef] {
        weapons.filter {
            if let damageType, $0.damageType != damageType { return false }
            return query.isEmpty
                || $0.name.localizedCaseInsensitiveContains(query)
                || $0.damageType.localizedCaseInsensitiveContains(query)
                || $0.properties.localizedCaseInsensitiveContains(query)
        }
    }

    /// Case-insensitive armor search across name and category.
    public static func searchArmor(_ query: String) -> [ArmorDef] {
        armors.filter {
            query.isEmpty
                || $0.name.localizedCaseInsensitiveContains(query)
                || $0.category.rawValue.localizedCaseInsensitiveContains(query)
        }
    }

    public static func armor(named name: String) -> ArmorDef? { armors.first { $0.name == name } }
    public static func weapon(named name: String) -> WeaponDef? { weapons.first { $0.name == name } }
    public static func gear(named name: String) -> GearDef? { gear.first { $0.name == name } }

    public static let armors: [ArmorDef] = [
        ArmorDef(name: "Padded", category: .light, baseAC: 11, addDex: true, weight: 8, cost: "5 gp"),
        ArmorDef(name: "Leather", category: .light, baseAC: 11, addDex: true, weight: 10, cost: "10 gp"),
        ArmorDef(name: "Studded Leather", category: .light, baseAC: 12, addDex: true, weight: 13, cost: "45 gp"),
        ArmorDef(name: "Hide", category: .medium, baseAC: 12, addDex: true, maxDexBonus: 2, weight: 12, cost: "10 gp"),
        ArmorDef(name: "Chain Shirt", category: .medium, baseAC: 13, addDex: true, maxDexBonus: 2, weight: 20, cost: "50 gp"),
        ArmorDef(name: "Scale Mail", category: .medium, baseAC: 14, addDex: true, maxDexBonus: 2, weight: 45, cost: "50 gp"),
        ArmorDef(name: "Breastplate", category: .medium, baseAC: 14, addDex: true, maxDexBonus: 2, weight: 20, cost: "400 gp"),
        ArmorDef(name: "Half Plate", category: .medium, baseAC: 15, addDex: true, maxDexBonus: 2, weight: 40, cost: "750 gp"),
        ArmorDef(name: "Ring Mail", category: .heavy, baseAC: 14, addDex: false, weight: 40, cost: "30 gp"),
        ArmorDef(name: "Chain Mail", category: .heavy, baseAC: 16, addDex: false, weight: 55, cost: "75 gp"),
        ArmorDef(name: "Splint", category: .heavy, baseAC: 17, addDex: false, weight: 60, cost: "200 gp"),
        ArmorDef(name: "Plate", category: .heavy, baseAC: 18, addDex: false, weight: 65, cost: "1,500 gp"),
        ArmorDef(name: "Shield", category: .shield, baseAC: 2, addDex: false, weight: 6, cost: "10 gp"),
    ]

    public static let weapons: [WeaponDef] = [
        WeaponDef(name: "Dagger", damageExpression: "1d4", damageType: "piercing", range: "5 ft (thrown 20/60)", finesse: true, properties: "Finesse, light, thrown", weight: 1, cost: "2 gp"),
        WeaponDef(name: "Shortsword", damageExpression: "1d6", damageType: "piercing", finesse: true, properties: "Finesse, light", weight: 2, cost: "10 gp"),
        WeaponDef(name: "Rapier", damageExpression: "1d8", damageType: "piercing", finesse: true, properties: "Finesse", weight: 2, cost: "25 gp"),
        WeaponDef(name: "Scimitar", damageExpression: "1d6", damageType: "slashing", finesse: true, properties: "Finesse, light", weight: 3, cost: "25 gp"),
        WeaponDef(name: "Handaxe", damageExpression: "1d6", damageType: "slashing", range: "5 ft (thrown 20/60)", properties: "Light, thrown", weight: 2, cost: "5 gp"),
        WeaponDef(name: "Mace", damageExpression: "1d6", damageType: "bludgeoning", weight: 4, cost: "5 gp"),
        WeaponDef(name: "Quarterstaff", damageExpression: "1d6", damageType: "bludgeoning", properties: "Versatile (1d8)", weight: 4, cost: "2 sp"),
        WeaponDef(name: "Spear", damageExpression: "1d6", damageType: "piercing", range: "5 ft (thrown 20/60)", properties: "Thrown, versatile (1d8)", weight: 3, cost: "1 gp"),
        WeaponDef(name: "Longsword", damageExpression: "1d8", damageType: "slashing", properties: "Versatile (1d10)", weight: 3, cost: "15 gp"),
        WeaponDef(name: "Battleaxe", damageExpression: "1d8", damageType: "slashing", properties: "Versatile (1d10)", weight: 4, cost: "10 gp"),
        WeaponDef(name: "Warhammer", damageExpression: "1d8", damageType: "bludgeoning", properties: "Versatile (1d10)", weight: 2, cost: "15 gp"),
        WeaponDef(name: "Greataxe", damageExpression: "1d12", damageType: "slashing", properties: "Heavy, two-handed", weight: 7, cost: "30 gp"),
        WeaponDef(name: "Greatsword", damageExpression: "2d6", damageType: "slashing", properties: "Heavy, two-handed", weight: 6, cost: "50 gp"),
        WeaponDef(name: "Maul", damageExpression: "2d6", damageType: "bludgeoning", properties: "Heavy, two-handed", weight: 10, cost: "10 gp"),
        WeaponDef(name: "Shortbow", damageExpression: "1d6", damageType: "piercing", range: "80/320 ft", finesse: true, properties: "Ammunition, two-handed", weight: 2, cost: "25 gp"),
        WeaponDef(name: "Longbow", damageExpression: "1d8", damageType: "piercing", range: "150/600 ft", finesse: true, properties: "Ammunition, heavy, two-handed", weight: 2, cost: "50 gp"),
        WeaponDef(name: "Light Crossbow", damageExpression: "1d8", damageType: "piercing", range: "80/320 ft", finesse: true, properties: "Ammunition, loading, two-handed", weight: 5, cost: "25 gp"),
        WeaponDef(name: "Heavy Crossbow", damageExpression: "1d10", damageType: "piercing", range: "100/400 ft", finesse: true, properties: "Ammunition, heavy, loading, two-handed", weight: 18, cost: "50 gp"),
    ]

    public static let gear: [GearDef] = [
        GearDef(name: "Backpack", weight: 5, cost: "2 gp"),
        GearDef(name: "Bedroll", weight: 7, cost: "1 gp"),
        GearDef(name: "Rope, hempen (50 ft)", weight: 10, cost: "1 gp"),
        GearDef(name: "Torch", weight: 1, cost: "1 cp"),
        GearDef(name: "Rations (1 day)", weight: 2, cost: "5 sp"),
        GearDef(name: "Waterskin", weight: 5, cost: "2 sp"),
        GearDef(name: "Lantern, hooded", weight: 2, cost: "5 gp"),
        GearDef(name: "Tinderbox", weight: 1, cost: "5 sp"),
        GearDef(name: "Healer's kit", weight: 3, cost: "5 gp"),
        GearDef(name: "Thieves' tools", weight: 1, cost: "25 gp"),
        GearDef(name: "Crowbar", weight: 5, cost: "2 gp"),
        GearDef(name: "Grappling hook", weight: 4, cost: "2 gp"),
        GearDef(name: "Potion of healing", weight: 0.5, cost: "50 gp"),
        GearDef(name: "Spellbook", weight: 3, cost: "50 gp"),
        GearDef(name: "Component pouch", weight: 2, cost: "25 gp"),
        GearDef(name: "Holy symbol", weight: 1, cost: "5 gp"),
    ]
}
