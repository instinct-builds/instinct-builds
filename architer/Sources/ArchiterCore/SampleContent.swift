import Foundation

/// A rich demo character used by the renderer, the tests, and the app's
/// "load sample" action so every feature shows up in screenshots.
public enum SampleContent {

    public static func demoCharacter() -> Character {
        var scores = AbilityScores()
        scores[.strength] = 12
        scores[.dexterity] = 14
        scores[.constitution] = 13
        scores[.intelligence] = 16
        scores[.wisdom] = 10
        scores[.charisma] = 8

        var skills = Skill.defaultList
        for (i, s) in skills.enumerated() {
            switch s.name {
            case "Arcana", "Investigation": skills[i].tier = .expert
            case "History", "Religion", "Perception", "Stealth": skills[i].tier = .proficient
            default: break
            }
        }

        var c = Character(
            name: "Wren Halloway",
            lineage: "High Elf",
            calling: "Wizard",
            background: "Sage",
            alignment: "Neutral Good",
            level: 5,
            experience: 7200,
            inspiration: true,
            scores: scores,
            skills: skills,
            savingThrowProficiencies: [.intelligence, .wisdom],
            maxHP: 32,
            currentHP: 24,
            tempHP: 5,
            hitDiceType: 6,
            hitDiceSpent: 2,
            armorClass: 12,
            initiativeBonus: 0,
            speed: 30,
            conditions: [],
            attacks: [
                Attack(name: "Dagger", ability: nil, proficient: true,
                       damageExpression: "1d4", damageType: "piercing", range: "5 ft (thrown 20/60)"),
                Attack(name: "Quarterstaff", ability: .strength, proficient: true,
                       damageExpression: "1d6", damageType: "bludgeoning",
                       versatileExpression: "1d8"),
                Attack(name: "Fire Bolt", ability: .intelligence, proficient: true, bonusOverride: nil,
                       damageExpression: "2d10", damageType: "fire", range: "120 ft",
                       notes: "Cantrip; scales with level"),
            ],
            spellcasting: Spellcasting(
                ability: .intelligence,
                progression: .full,
                slotsUsed: [2, 1, 0, 0, 0, 0, 0, 0, 0],
                spells: [
                    Spell(name: "Fire Bolt", level: 0, school: "Evocation", range: "120 ft",
                          detail: "Ranged spell attack, 2d10 fire at this level."),
                    Spell(name: "Mage Hand", level: 0, school: "Conjuration", range: "30 ft", duration: "1 minute",
                          detail: "Spectral hand; 10 lb limit."),
                    Spell(name: "Minor Illusion", level: 0, school: "Illusion", range: "30 ft", duration: "1 minute",
                          detail: "Sound or static image, 5-ft cube."),
                    Spell(name: "Prestidigitation", level: 0, school: "Transmutation", range: "10 ft", duration: "1 hour",
                          detail: "Minor magical tricks."),
                    Spell(name: "Mage Armor", level: 1, school: "Abjuration", range: "Touch", duration: "8 hours",
                          detail: "AC becomes 13 + DEX."),
                    Spell(name: "Magic Missile", level: 1, school: "Evocation", range: "120 ft",
                          detail: "3 darts, 1d4+1 force each, unerring."),
                    Spell(name: "Shield", level: 1, school: "Abjuration", castingTime: "1 reaction", range: "Self", duration: "1 round",
                          detail: "+5 AC until next turn."),
                    Spell(name: "Detect Magic", level: 1, school: "Divination", range: "Self", duration: "10 minutes",
                          concentration: true, ritual: true, prepared: false,
                          detail: "Sense magic within 30 ft."),
                    Spell(name: "Misty Step", level: 2, school: "Conjuration", castingTime: "1 bonus action", range: "Self",
                          detail: "Teleport 30 ft to a seen space."),
                    Spell(name: "Invisibility", level: 2, school: "Illusion", range: "Touch", duration: "1 hour",
                          concentration: true, prepared: false,
                          detail: "Invisible until attacking or casting."),
                    Spell(name: "Fireball", level: 3, school: "Evocation", range: "150 ft",
                          detail: "20-ft radius, 8d6 fire, DEX half."),
                    Spell(name: "Counterspell", level: 3, school: "Abjuration", castingTime: "1 reaction", range: "60 ft",
                          detail: "Interrupt a casting; check for 4th+."),
                ]),
            inventory: [
                InventoryItem(name: "Quarterstaff", quantity: 1, weight: 4, equipped: true, attuned: true, category: "Weapon"),
                InventoryItem(name: "Dagger", quantity: 2, weight: 1, category: "Weapon"),
                InventoryItem(name: "Spellbook", quantity: 1, weight: 3, category: "Focus"),
                InventoryItem(name: "Component pouch", quantity: 1, weight: 2, equipped: true, category: "Focus"),
                InventoryItem(name: "Backpack", quantity: 1, weight: 5, category: "Gear"),
                InventoryItem(name: "Rations (1 day)", quantity: 6, weight: 2, category: "Gear"),
                InventoryItem(name: "Potion of healing", quantity: 2, weight: 0.5, category: "Consumable", notes: "2d4+2"),
                InventoryItem(name: "Rope, hempen (50 ft)", quantity: 1, weight: 10, category: "Gear"),
                InventoryItem(name: "Waterskin", quantity: 1, weight: 5, category: "Gear"),
            ],
            currency: Currency(copper: 7, silver: 23, electrum: 0, gold: 112, platinum: 2),
            proficienciesText: "Armor: none · Weapons: daggers, darts, slings, quarterstaffs, light crossbows · Languages: Common, Elvish, Draconic, Dwarvish",
            toolProficiencies: [
                // A decade copying marginalia leaves a mark.
                ToolProficiency(name: "Calligrapher's supplies", tier: .expert),
                ToolProficiency(name: "Forgery kit"),
            ],
            features: [
                Feature(name: "Arcane Recovery", source: "Wizard 1",
                        detail: "Once per day after a short rest, recover spell slots totaling half your wizard level (rounded up).",
                        usesMax: 1, usesUsed: 0, recharge: .longRest),
                Feature(name: "Sculpt Spells", source: "Evoker 2",
                        detail: "Allies auto-succeed saves against your evocations and take no damage on a success."),
                Feature(name: "Fey Ancestry", source: "High Elf",
                        detail: "Advantage on saves against being charmed; magic can't put you to sleep."),
                Feature(name: "Trance", source: "High Elf",
                        detail: "Meditate 4 hours instead of sleeping 8."),
                Feature(name: "Keen Senses", source: "High Elf",
                        detail: "Proficiency in Perception."),
                Feature(name: "Researcher", source: "Sage",
                        detail: "When you don't know lore, you know where to find it."),
            ],
            personality: Personality(
                traits: "I quote old texts at the worst moments. I keep a labelled jar for everything.",
                ideals: "Knowledge belongs to everyone who can reach a library.",
                bonds: "The Athenaeum of Greyharbor took me in; I owe its archivists my life.",
                flaws: "I will walk into obvious danger for a look at a sealed book.",
                appearance: "Wiry, ink-stained fingers, spectacles repaired with wire.",
                backstory: "Raised among the stacks of the Greyharbor Athenaeum, Wren copied marginalia for a decade before the night the restricted vault sang to them. They left with a borrowed spellbook and a debt they intend to repay.",
                allies: "Archivist Bressa of the Athenaeum; the Lantern Street booksellers' guild.",
                treasure: "A brass key stamped with an eye, found inside a hollow commentary on planar theory.",
                age: "127", height: "5'7\"", weight: "132 lb", eyes: "Grey", hair: "Silver-white"),
            notes: "- Ask Bressa about the brass key.\n- The vault door had no lock from the inside.\n- 50 gp owed to the Lantern Street courier.",
            journal: [
                JournalEntry(date: "Session 1", title: "The singing vault",
                             text: "The restricted vault sang in a key I almost recognized. I took the commentary on planar theory. I should not have."),
                JournalEntry(date: "Session 2", title: "Lantern Street",
                             text: "Bressa says the brass key predates the Athenaeum. The booksellers' guild wants it bought, not borrowed."),
            ]
        )
        c.companions = [Companion(name: "Inkpot", kind: "Familiar (owl)", maxHP: 3,
                                  armorClass: 11,
                                  notes: "Perches on the spellbook. Delivers notes across the reading room.")]
        // Original curio: a clasp that lets the wearer move through water
        // as if it were air.
        c.inventory.append(InventoryItem(name: "Tideglass clasp", quantity: 1, weight: 0.2,
                                         attuned: true, category: "Wondrous",
                                         notes: "Grants a swim speed equal to walking speed."))
        c.extraSpeeds = [MovementSpeed(mode: .swim, feet: 30, label: "Tideglass clasp")]
        // Story residue from the singing vault: a homebrew state that hinders
        // ability checks until Wren shakes it.
        c.customConditions = [CustomCondition(name: "Vault-marked", hindersChecks: true)]
        // The vault's song left an ember-ward: fire resistance.
        c.resistances = [.fire]
        // Winded and knocked prone in the last scene: exhaustion 2 halves
        // every speed under her 2014-style rules, and standing up costs
        // half of what remains.
        c.exhaustion = 2
        c.conditions = [.prone]
        c.armorClass = 15 // Mage Armor active: 13 + DEX
        return c
    }
}
