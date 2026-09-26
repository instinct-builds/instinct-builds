import Testing
import Foundation
@testable import ArchiterCore

@Suite("Character core")
struct CharacterTests {

    @Test func defaultsRoundTrip() throws {
        let c = Character(name: "Test")
        let store = CharacterStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString))
        try store.save(c)
        let loaded = try store.load(id: c.id)
        #expect(loaded == c)
    }

    @Test func damageTempHPAbsorbsFirst() {
        var c = Character(name: "T", maxHP: 20)
        c.gainTempHP(5)
        c.applyDamage(3)
        #expect(c.tempHP == 2)
        #expect(c.currentHP == 20)
        c.applyDamage(4)
        #expect(c.tempHP == 0)
        #expect(c.currentHP == 18)
    }

    @Test func tempHPNeverStacks() {
        var c = Character(name: "T", maxHP: 20)
        c.gainTempHP(5)
        c.gainTempHP(3)
        #expect(c.tempHP == 5)
        c.gainTempHP(8)
        #expect(c.tempHP == 8)
    }

    @Test func healingCapsAndResetsDeathSaves() {
        var c = Character(name: "T", maxHP: 20, currentHP: 5)
        c.applyHealing(50)
        #expect(c.currentHP == 20)
        c.applyDamage(30)
        #expect(c.currentHP == 0)
        c.deathSaveFailures = 2
        c.applyHealing(4)
        #expect(c.deathSaveFailures == 0)
    }

    @Test func hitDiceSpendAndRegain() {
        var c = Character(name: "T", level: 6, maxHP: 40, currentHP: 10, hitDiceSpent: 4)
        #expect(c.hitDiceRemaining == 2)
        #expect(c.hitDieRollExpression() != nil)
        c.spendHitDie(healingRolled: 7)
        #expect(c.hitDiceRemaining == 1)
        #expect(c.currentHP == 17)
        c.longRest()
        #expect(c.currentHP == 40)
        #expect(c.hitDiceSpent == 2) // 5 spent, regained max(1, 6/2) = 3
    }

    @Test func longRestResetsSlotsDeathSavesAndFeatures() {
        var c = Character(name: "T", level: 5, maxHP: 30, currentHP: 3,
                          deathSaveSuccesses: 1,
                          spellcasting: Spellcasting(ability: .intelligence, progression: .full,
                                                     slotsUsed: [4, 3, 2, 0, 0, 0, 0, 0, 0]),
                          features: [Feature(name: "F", usesMax: 1, usesUsed: 1, recharge: .longRest)])
        c.exhaustion = 2
        c.longRest()
        #expect(c.currentHP == 30)
        #expect(c.spellcasting?.slotsUsed.allSatisfy { $0 == 0 } == true)
        #expect(c.deathSaveSuccesses == 0)
        #expect(c.features[0].usesRemaining == 1)
        #expect(c.exhaustion == 1)
    }

    @Test func shortRestOnlyAffectsPactAndShortRestFeatures() {
        var c = Character(name: "T", level: 5,
                          spellcasting: Spellcasting(ability: .charisma, progression: .pact,
                                                     slotsUsed: [0, 0, 0, 0, 2, 0, 0, 0, 0]),
                          features: [
                            Feature(name: "Short", usesMax: 1, usesUsed: 1, recharge: .shortRest),
                            Feature(name: "Long", usesMax: 1, usesUsed: 1, recharge: .longRest),
                          ])
        c.shortRest()
        #expect(c.spellcasting?.slotsUsed.allSatisfy { $0 == 0 } == true)
        #expect(c.features[0].usesRemaining == 1)
        #expect(c.features[1].usesRemaining == 0)
    }

    @Test func companionsClampHPAndDecode() throws {
        var c = Character(name: "T", level: 1)
        c.companions = [Companion(name: "Inkpot", kind: "Familiar", maxHP: 3, armorClass: 11)]
        #expect(c.companions[0].currentHP == 3)
        // currentHP never exceeds maxHP through the initializer.
        let over = Companion(name: "Mule", maxHP: 10, currentHP: 25)
        #expect(over.currentHP == 10)
        // Old saves without the companions key decode empty.
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001",
        "name":"Old","lineage":"","calling":"","background":"",
        "level":1,"experience":0,"scores":{},"skills":[],
        "savingThrowProficiencies":[],"maxHP":8,"currentHP":8,"armorClass":10,"speed":30,
        "attacks":[],"inventory":[],"notes":"",
        "layout":{"blocks":[{"kind":"identity","visible":true,"size":"regular"}]}}
        """.data(using: .utf8)!
        let old = try JSONDecoder().decode(Character.self, from: json)
        #expect(old.companions.isEmpty)
    }

    @Test func movementSpeedsSummaryAndDecode() throws {
        var c = Character(name: "T", level: 1)
        c.speed = 30
        #expect(c.extraSpeeds.isEmpty)
        #expect(c.movementSummary == "30 ft")
        // Summary joins extra modes with their notes.
        let fly = MovementSpeed(mode: .fly, feet: 60, hover: true)
        let climb = MovementSpeed(mode: .climb, feet: 20, label: "claws")
        c.extraSpeeds = [fly, climb]
        #expect(c.movementSummary == "30 ft, fly 60 ft (hover), climb 20 ft (claws)")
        // Hover only applies to fly.
        #expect(MovementSpeed(mode: .swim, feet: 30, hover: true).hover == false)
        // Old saves without the extraSpeeds key decode empty.
        let json = """
        {"id":"00000000-0000-0000-0000-000000000002",
        "name":"Old","lineage":"","calling":"","background":"",
        "level":1,"experience":0,"scores":{},"skills":[],
        "savingThrowProficiencies":[],"maxHP":8,"currentHP":8,"armorClass":10,"speed":30,
        "attacks":[],"inventory":[],"notes":"",
        "layout":{"blocks":[{"kind":"identity","visible":true,"size":"regular"}]}}
        """.data(using: .utf8)!
        let old = try JSONDecoder().decode(Character.self, from: json)
        #expect(old.extraSpeeds.isEmpty)
        #expect(old.movementSummary == "30 ft")
    }

    @Test func customConditionsDecodeAndHinder() throws {
        var c = Character(name: "T", level: 1)
        #expect(c.customConditions.isEmpty)
        #expect(c.activeConditionNames.isEmpty)
        let marked = CustomCondition(name: "Marked", hindersChecks: true)
        let dazed = CustomCondition(name: "Dazed", hindersAttacks: true)
        c.customConditions = [marked, dazed]
        c.conditions = [.poisoned]
        // Built-ins sort first, then custom names.
        #expect(c.activeConditionNames == ["Poisoned", "Dazed", "Marked"])
        #expect(c.customDisadvantageSources(for: .check).map(\.name) == ["Marked"])
        #expect(c.customDisadvantageSources(for: .attack).map(\.name) == ["Dazed"])
        #expect(c.customDisadvantageSources(for: .save).isEmpty)
        // Combined display names feed the roll UI.
        #expect(c.disadvantageSourceNames(for: .check) == ["Poisoned", "Marked"])
        // Custom conditions drive effective roll mode like built-ins.
        #expect(c.effectiveRollMode(.normal, for: .attack) == .disadvantage)
        c.customConditions = [marked]
        // Poisoned (built-in) still hinders attacks; Marked hinders checks only.
        #expect(c.effectiveRollMode(.normal, for: .attack) == .disadvantage)
        c.conditions = []
        #expect(c.effectiveRollMode(.normal, for: .attack) == .normal)
        #expect(c.effectiveRollMode(.advantage, for: .check) == .normal)
        // Old saves without the customConditions key decode empty.
        let json = """
        {"id":"00000000-0000-0000-0000-000000000003",
        "name":"Old","lineage":"","calling":"","background":"",
        "level":1,"experience":0,"scores":{},"skills":[],
        "savingThrowProficiencies":[],"maxHP":8,"currentHP":8,"armorClass":10,"speed":30,
        "attacks":[],"inventory":[],"notes":"",
        "layout":{"blocks":[{"kind":"identity","visible":true,"size":"regular"}]}}
        """.data(using: .utf8)!
        let old = try JSONDecoder().decode(Character.self, from: json)
        #expect(old.customConditions.isEmpty)
        #expect(old.activeConditionNames.isEmpty)
    }

    @Test func toolProficienciesDecodeAndBonus() throws {
        var c = Character(name: "T", level: 5) // proficiency bonus +3
        #expect(c.toolProficiencies.isEmpty)
        #expect(c.toolSummary == "")
        let tools = ToolProficiency(name: "Thieves' tools")
        let expert = ToolProficiency(name: "Calligrapher's supplies", tier: .expert)
        c.toolProficiencies = [tools, expert]
        #expect(c.toolSummary == "Thieves' tools, Calligrapher's supplies (expertise)")
        // Bonus = ability modifier + tier multiplier x proficiency bonus.
        c.scores = AbilityScores([.dexterity: 16]) // +3 modifier
        #expect(c.toolBonus(tools, ability: .dexterity) == 6)
        #expect(c.toolBonus(expert, ability: .dexterity) == 9)
        // Old saves without the toolProficiencies key decode empty.
        let json = """
        {"id":"00000000-0000-0000-0000-000000000004",
        "name":"Old","lineage":"","calling":"","background":"",
        "level":1,"experience":0,"scores":{},"skills":[],
        "savingThrowProficiencies":[],"maxHP":8,"currentHP":8,"armorClass":10,"speed":30,
        "attacks":[],"inventory":[],"notes":"",
        "layout":{"blocks":[{"kind":"identity","visible":true,"size":"regular"}]}}
        """.data(using: .utf8)!
        let old = try JSONDecoder().decode(Character.self, from: json)
        #expect(old.toolProficiencies.isEmpty)
    }

    @Test func outgoingDefenseNoteMirrorsDefenseMath() throws {
        // The note shows what a damage total deals against each defense,
        // with the same rounding as adjustedDamage (halve rounds down).
        #expect(Character.outgoingDefenseNote(total: 13, type: .fire) == "fire: resist 6 - immune 0 - vuln 26")
        #expect(Character.outgoingDefenseNote(total: 14, type: .piercing) == "piercing: resist 7 - immune 0 - vuln 28")
        // Negative totals clamp like applyDamage does.
        #expect(Character.outgoingDefenseNote(total: -3, type: .cold) == "cold: resist 0 - immune 0 - vuln 0")
    }

    @Test func toolProficiencyDefaultAbilityPersists() throws {
        // Saves written before 2.23 carry no defaultAbility key.
        let legacy = Data(#"{"name":"Thieves' tools","tier":"proficient"}"#.utf8)
        let decoded = try JSONDecoder().decode(ToolProficiency.self, from: legacy)
        #expect(decoded.defaultAbility == nil)
        #expect(decoded.tier == .proficient)
        // A chosen default round-trips.
        var tool = ToolProficiency(name: "Calligrapher's supplies", tier: .expert, defaultAbility: .intelligence)
        let back = try JSONDecoder().decode(ToolProficiency.self, from: JSONEncoder().encode(tool))
        #expect(back == tool)
        #expect(back.defaultAbility == .intelligence)
        // Nil stays out of the JSON, keeping untouched saves byte-stable.
        tool.defaultAbility = nil
        let json = String(decoding: try JSONEncoder().encode(tool), as: UTF8.self)
        #expect(!json.contains("defaultAbility"))
    }

    @Test func immobilizedDropsSpeeds() throws {
        var c = Character(name: "T", level: 1)
        c.speed = 30
        let fly = MovementSpeed(mode: .fly, feet: 60)
        c.extraSpeeds = [fly]
        #expect(!c.immobilized)
        #expect(c.effectiveMovementSummary == "30 ft, fly 60 ft")
        // Built-in grappled and restrained both immobilize.
        c.conditions = [.grappled]
        #expect(c.immobilized)
        #expect(c.effectiveMovementSummary == "0 ft (immobilized)")
        c.conditions = [.restrained]
        #expect(c.immobilized)
        // Other built-ins do not.
        c.conditions = [.prone]
        #expect(!c.immobilized)
        // Custom conditions immobilize only when flagged.
        let rooted = CustomCondition(name: "Rooted", immobilizes: true)
        let marked = CustomCondition(name: "Marked", hindersChecks: true)
        c.conditions = []
        c.customConditions = [marked]
        #expect(!c.immobilized)
        c.customConditions = [marked, rooted]
        #expect(c.immobilized)
        // Legacy custom-condition JSON without the immobilizes key decodes false.
        let json = """
        {"name":"Rooted"}
        """.data(using: .utf8)!
        let cc = try JSONDecoder().decode(CustomCondition.self, from: json)
        #expect(!cc.immobilizes)
    }

    @Test func exhaustionAndProneAdjustMovement() {
        var c = Character(name: "T", level: 1)
        c.speed = 30
        c.extraSpeeds = [MovementSpeed(mode: .fly, feet: 60, hover: true),
                         MovementSpeed(mode: .swim, feet: 25, label: "clasp")]

        // 2014-style: step 2 halves every speed, step 5 zeroes them.
        c.era = .era2014
        c.exhaustion = 1
        #expect(c.effectiveMovementSummary == "30 ft, fly 60 ft (hover), swim 25 ft (clasp)")
        c.exhaustion = 2
        #expect(c.effectiveSpeed == 15)
        #expect(c.effectiveMovementSummary == "15 ft, fly 30 ft (hover), swim 12 ft (clasp)")
        c.exhaustion = 5
        #expect(c.effectiveMovementSummary == "0 ft, fly 0 ft (hover), swim 0 ft (clasp)")

        // 2024-style: each step shaves 5 ft, floored at 0.
        c.era = .era2024
        c.exhaustion = 3
        #expect(c.effectiveMovementSummary == "15 ft, fly 45 ft (hover), swim 10 ft (clasp)")
        c.exhaustion = 10
        #expect(c.effectiveSpeed == 0)

        // Prone appends stand-up and crawl costs from the effective speed.
        c.era = .era2014
        c.exhaustion = 0
        c.conditions = [.prone]
        #expect(c.proneStandingCost == 15)
        #expect(c.effectiveMovementSummary
            == "30 ft, fly 60 ft (hover), swim 25 ft (clasp), prone: stand up costs 15 ft, crawl at half")
        // Prone composes with exhaustion halving.
        c.exhaustion = 2
        #expect(c.proneStandingCost == 7)
        #expect(c.effectiveMovementSummary
            == "15 ft, fly 30 ft (hover), swim 12 ft (clasp), prone: stand up costs 7 ft, crawl at half")
        // Immobilize still wins outright: no prone note, no partial speeds.
        c.conditions = [.prone, .grappled]
        #expect(c.effectiveMovementSummary == "0 ft (immobilized)")
    }

    @Test func defensesAdjustIncomingDamage() {
        var c = Character(name: "T", level: 1, maxHP: 30)
        c.resistances = [.fire]
        c.immunities = [.poison]
        c.vulnerabilities = [.cold]
        // Resistance halves, rounding down.
        #expect(c.adjustedDamage(7, type: .fire) == 3)
        // Immunity reduces to zero.
        #expect(c.adjustedDamage(12, type: .poison) == 0)
        // Vulnerability doubles.
        #expect(c.adjustedDamage(6, type: .cold) == 12)
        // Untyped and unrelated types pass through.
        #expect(c.adjustedDamage(5, type: nil) == 5)
        #expect(c.adjustedDamage(5, type: .radiant) == 5)
        // Resistance applies before temp HP absorbs.
        c.tempHP = 4
        c.applyDamage(9, type: .fire)
        #expect(c.currentHP == 30)
        #expect(c.tempHP == 0)
        c.applyDamage(3, type: .poison)
        #expect(c.currentHP == 30)
    }

    @Test func defenseAdjustmentNoteLabelsRolls() {
        var c = Character(name: "T", level: 1)
        c.resistances = [.fire]
        c.immunities = [.poison]
        c.vulnerabilities = [.cold]
        #expect(c.defenseAdjustmentNote(amount: 14, type: .fire) == "resisted: 14 -> 7")
        #expect(c.defenseAdjustmentNote(amount: 14, type: .poison) == "immune: 14 -> 0")
        #expect(c.defenseAdjustmentNote(amount: 10, type: .cold) == "vulnerable: 10 -> 20")
        // No defense on the type, or no type at all: no note.
        #expect(c.defenseAdjustmentNote(amount: 14, type: .acid) == nil)
        #expect(c.defenseAdjustmentNote(amount: 14, type: nil) == nil)
        // Resist + vulnerable cancels on even amounts (halve then double).
        c.vulnerabilities.insert(.fire)
        #expect(c.defenseAdjustmentNote(amount: 14, type: .fire) == nil)
        // Odd amounts round down mid-pipe, so a note still appears.
        #expect(c.defenseAdjustmentNote(amount: 15, type: .fire) == "resisted + vulnerable: 15 -> 14")
    }

    @Test func stowedGearExcludedFromCarriedWeight() {
        var c = Character(name: "T", level: 1)
        c.inventory = [InventoryItem(name: "Rope", weight: 10),
                       InventoryItem(name: "Anvil", weight: 50)]
        #expect(c.totalWeight == 60)
        #expect(c.stowedWeight == 0)
        c.inventory[1].stowed = true
        #expect(c.totalWeight == 10)
        #expect(c.stowedWeight == 50)
        // Encumbrance looks only at what is carried.
        #expect(c.encumbrance == .normal)
    }

    @Test func customSkillsAddDedupesAndRemoves() {
        var c = Character(name: "T", level: 1)
        let before = c.skills.count
        let added = c.addSkill(name: "Boating", ability: .strength)
        #expect(added)
        #expect(c.skills.count == before + 1)
        #expect(c.skills.last?.name == "Boating")
        // Duplicates (any case) and blank names are refused.
        let dupe = c.addSkill(name: "boating", ability: .wisdom)
        let blank = c.addSkill(name: "  ", ability: .wisdom)
        #expect(!dupe)
        #expect(!blank)
        #expect(c.skills.count == before + 1)
        // Name is trimmed on the way in.
        let trimmed = c.addSkill(name: "  Brewing ", ability: .intelligence)
        #expect(trimmed)
        #expect(c.skills.last?.name == "Brewing")
        c.removeSkill(named: "Boating")
        #expect(c.skills.count == before + 1)
        #expect(c.skills.allSatisfy { $0.name != "Boating" })
    }

    @Test func ammunitionSpendsAndFloors() {
        var c = Character(name: "T", level: 1)
        c.attacks = [Attack(name: "Shortbow", damageExpression: "1d6", ammunition: 2),
                     Attack(name: "Dagger", damageExpression: "1d4")]
        let bow = c.attacks[0].id
        let first = c.spendAmmunition(attackID: bow)
        #expect(first)
        #expect(c.attacks[0].ammunition == 1)
        let second = c.spendAmmunition(attackID: bow)
        #expect(second)
        #expect(c.attacks[0].ammunition == 0)
        // Empty: no spend, no negative count.
        let third = c.spendAmmunition(attackID: bow)
        #expect(!third)
        #expect(c.attacks[0].ammunition == 0)
        // Untracked attacks never spend.
        let dagger = c.spendAmmunition(attackID: c.attacks[1].id)
        #expect(!dagger)
        #expect(c.attacks[1].ammunition == nil)
    }

    @Test func passiveSensesDeriveFromSkills() {
        var c = Character(name: "T", level: 5)
        c.scores = AbilityScores([.strength: 10, .dexterity: 10, .constitution: 10,
                                  .intelligence: 16, .wisdom: 14, .charisma: 10])
        // No proficiencies yet: raw ability modifiers (WIS +2, INT +3).
        #expect(c.passivePerception == 12)
        #expect(c.passiveInvestigation == 13)
        #expect(c.passiveInsight == 12)
        // Proficiency at level 5 adds +3.
        c.skills = c.skills.map { $0.name == "Perception" ? Skill(name: $0.name, ability: $0.ability, tier: .proficient) : $0 }
        c.skills = c.skills.map { $0.name == "Insight" ? Skill(name: $0.name, ability: $0.ability, tier: .expert) : $0 }
        #expect(c.passivePerception == 15)
        #expect(c.passiveInsight == 18)
        #expect(c.passiveInvestigation == 13)
        // A sheet without the skill falls back to the raw ability modifier.
        c.skills.removeAll { $0.name == "Investigation" }
        #expect(c.passiveInvestigation == 13)
    }

    @Test func xpAwardLevelsUp() {
        var c = Character(name: "T", level: 1)
        let noLevel = c.addXP(100)
        #expect(!noLevel)
        let leveled = c.addXP(300)
        #expect(leveled)
        #expect(c.level == 2)
        _ = c.addXP(14000)
        #expect(c.level == 6)
        #expect(c.proficiencyBonus == 3)
        #expect(c.xpToNextLevel != nil)
    }

    @Test func computedACFromArmorShieldAndMisc() {
        var scores = AbilityScores()
        scores[.dexterity] = 16 // +3
        var c = Character(name: "T", scores: scores, armorClass: 10)
        #expect(c.computedAC == 10)
        c.equippedArmor = "Leather"
        #expect(c.computedAC == 14) // 11 + 3
        c.equippedArmor = "Half Plate"
        #expect(c.computedAC == 17) // 15 + min(3, 2)
        c.shieldEquipped = true
        #expect(c.computedAC == 19)
        c.armorClassBonus = 1
        #expect(c.computedAC == 20)
        c.equippedArmor = nil
        #expect(c.computedAC == 13) // 10 + 2 + 1
    }

    @Test func attackBonusesDeriveFromAbilities() {
        var scores = AbilityScores()
        scores[.strength] = 16 // +3
        scores[.dexterity] = 14 // +2
        let c = Character(name: "T", level: 5, scores: scores) // prof +3
        let sword = Attack(name: "Longsword", ability: .strength, proficient: true, damageExpression: "1d8")
        #expect(sword.attackBonus(scores: c.scores, level: c.level) == 6)
        #expect(sword.damageString(scores: c.scores) == "1d8+3")
        let finesse = Attack(name: "Dagger", ability: nil, proficient: true, damageExpression: "1d4")
        #expect(finesse.effectiveAbility(scores: c.scores) == .strength)
        let pinned = Attack(name: "Old", attackBonus: 5, damageExpression: "1d6")
        #expect(pinned.attackBonus(scores: c.scores, level: c.level) == 5)
    }

    @Test func encumbranceBands() {
        var scores = AbilityScores()
        scores[.strength] = 10 // capacity 150
        var c = Character(name: "T", scores: scores)
        #expect(c.encumbrance == .normal)
        c.inventory = [InventoryItem(name: "Anvil", weight: 120)]
        #expect(c.encumbrance == .encumbered)
        c.inventory = [InventoryItem(name: "Anvils", weight: 200)]
        #expect(c.encumbrance == .heavilyEncumbered)
        c.inventory = [InventoryItem(name: "Anvils", weight: 350)]
        #expect(c.encumbrance == .overCapacity)
    }

    @Test func currencyTotalsAndDisplay() {
        let purse = Currency(copper: 5, silver: 2, electrum: 1, gold: 3, platinum: 1)
        #expect(purse.totalCopper == 5 + 20 + 50 + 300 + 1000)
        #expect(purse.displayString == "1 pp, 3 gp, 1 ep, 2 sp, 5 cp")
    }

    @Test func levelUpGainsHPAndNotes() {
        var c = Character(name: "T", level: 3)
        c.maxHP = 20
        c.currentHP = 15
        c.hitDiceType = 10
        c.notes = "Existing note"
        c.levelUp(hpGain: 8)
        #expect(c.level == 4)
        #expect(c.maxHP == 28)
        #expect(c.currentHP == 23)
        #expect(c.notes.contains("Reached level 4 (+8 HP)"))
        #expect(c.notes.contains("Existing note"))
    }

    @Test func levelUpFloorsAtOneAndCapsAtTwenty() {
        var c = Character(name: "T", level: 20)
        c.levelUp(hpGain: 5)
        #expect(c.level == 20)
        var d = Character(name: "T", level: 1)
        d.levelUp(hpGain: -4)
        #expect(d.level == 2)
        #expect(d.maxHP > 0)
    }

    @Test func averageLevelUpHPUsesHalfDiePlusCon() {
        var c = Character(name: "T")
        c.hitDiceType = 8
        var scores = AbilityScores()
        scores[.constitution] = 14
        c.scores = scores
        #expect(c.averageLevelUpHP == 7) // 8/2 + 1 + 2
        #expect(c.levelUpRollExpression == "1d8+2")
    }

    @Test func eraGovernsLongRestDiceRecovery() {
        var c = Character(name: "T", level: 4, hitDiceType: 8, hitDiceSpent: 4, era: .era2014)
        c.longRest()
        #expect(c.hitDiceSpent == 2) // half of 4 returns
        var d = Character(name: "T", level: 4, hitDiceType: 8, hitDiceSpent: 4, era: .era2024)
        d.longRest()
        #expect(d.hitDiceSpent == 0) // all return
    }

    @Test func eraGovernsExhaustionPenaltyAndCap() {
        var c = Character(name: "T", exhaustion: 3, era: .era2014)
        #expect(c.exhaustionRollPenalty == 0) // named side effects instead
        c.exhaustion = 7 // past the 2014 cap of 6 - UI/era clamp applies at init
        var d = Character(name: "T", exhaustion: 8, era: .era2024)
        #expect(d.exhaustionRollPenalty == 8)
        #expect(d.era.exhaustionCap == 10)
        #expect(RulesetVariant.era2014.exhaustionCap == 6)
    }

    @Test func eraGovernsPreparedLimit() {
        // 2014: level + casting modifier; 2024: fixed by level
        #expect(RulesetVariant.era2014.preparedLimit(casterLevel: 5, castingModifier: 4) == 9)
        #expect(RulesetVariant.era2024.preparedLimit(casterLevel: 5, castingModifier: 4) == 9)
        #expect(RulesetVariant.era2014.preparedLimit(casterLevel: 1, castingModifier: -1) == 1) // min 1
        #expect(RulesetVariant.era2024.preparedLimit(casterLevel: 1, castingModifier: 5) == 4) // scores don't add
    }

    @Test func weaponMasteryDefaultsNilAndDecodes() throws {
        let a = Attack(name: "Blade")
        #expect(a.mastery == nil)
        let json = """
        {"name":"Blade","ability":"strength","proficient":true,"damageExpression":"1d8","mastery":"Topple"}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Attack.self, from: json)
        #expect(decoded.mastery == .topple)
    }

    @Test func rulesetStoreRoundTrips() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("architer-test-\(UUID().uuidString)")
        let store = RulesetStore(directory: dir)
        #expect(store.load().isEmpty)
        try store.saveAll([.starfarer, .gumshoe])
        let loaded = store.load()
        #expect(loaded.count == 2)
        #expect(loaded.contains(.starfarer))
        try store.delete(name: "Starfarer")
        #expect(store.load() == [.gumshoe])
        try? FileManager.default.removeItem(at: dir)
    }

    @Test func captureRulesetCapturesCustomFields() {
        var c = Character(name: "T")
        c.apply(ruleset: .starfarer)
        c.customAbilities[0].score = 14
        let captured = c.captureRuleset(named: "My Game")
        #expect(captured.name == "My Game")
        #expect(captured.abilities == Ruleset.starfarer.abilities)
        #expect(captured.skills.count == Ruleset.starfarer.skills.count)
        // Captured template resets scores to 10 for a fresh character,
        // but a character carrying the same ability keeps its score.
        var d = Character(name: "U")
        d.apply(ruleset: captured)
        #expect(d.rulesetName == "My Game")
        #expect(d.customAbilities.map(\.name) == captured.abilities)
    }

    @Test func conditionsFoldDisadvantageIntoRollMode() {
        var c = Character(name: "T")
        c.conditions = [.poisoned]
        #expect(c.disadvantageSources(for: .attack) == [.poisoned])
        #expect(c.disadvantageSources(for: .check) == [.poisoned])
        #expect(c.effectiveRollMode(.normal, for: .attack) == .disadvantage)
        #expect(c.effectiveRollMode(.advantage, for: .attack) == .normal) // cancels
        #expect(c.effectiveRollMode(.disadvantage, for: .check) == .disadvantage)
        c.conditions = [.blinded]
        #expect(c.effectiveRollMode(.normal, for: .attack) == .disadvantage)
        #expect(c.effectiveRollMode(.normal, for: .check) == .normal) // checks unaffected
        c.conditions = []
        #expect(c.effectiveRollMode(.advantage, for: .attack) == .advantage)
    }

    @Test func spellLibrarySearchMatchesNameSchoolAndDetail() {
        #expect(SpellLibrary.search("").count == SpellLibrary.all.count)
        #expect(SpellLibrary.search("", level: 0).allSatisfy { $0.level == 0 })
        let byName = SpellLibrary.search("fire")
        #expect(!byName.isEmpty)
        let needle = byName[0]
        #expect(SpellLibrary.search(needle.name).contains(needle))
        #expect(SpellLibrary.search("zzzz-no-such-spell").isEmpty)
    }

    @Test func equipmentSearchMatchesNamesAndFilters() {
        #expect(EquipmentLibrary.searchWeapons("").count == EquipmentLibrary.weapons.count)
        #expect(EquipmentLibrary.searchArmor("").count == EquipmentLibrary.armors.count)
        let w = EquipmentLibrary.weapons[0]
        #expect(EquipmentLibrary.searchWeapons(w.name).contains(w))
        #expect(EquipmentLibrary.searchWeapons("zzzz").isEmpty)
        #expect(EquipmentLibrary.searchArmor("zzzz").isEmpty)
    }

    @Test func concentrationTracksAndDrops() {
        var c = Character(name: "T")
        #expect(c.concentratingOn == nil)
        c.beginConcentration(on: "Ward Bond")
        #expect(c.concentratingOn == "Ward Bond")
        c.beginConcentration(on: "Mist Step") // replaces
        #expect(c.concentratingOn == "Mist Step")
        c.dropConcentration()
        #expect(c.concentratingOn == nil)
    }

    @Test func pdfExportIncludesEraMasteryAndConcentration() {
        var c = Character(name: "PdfTest", era: .era2024, concentratingOn: "Ward Bond")
        c.spellcasting = Spellcasting(ability: .intelligence, progression: .full) // spells section prints the concentration line
        c.attacks = [Attack(name: "Blade", mastery: .topple)]
        c.exhaustion = 2
        let data = SheetPDFExporter.export(c)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("2024-style"))
        #expect(text.contains("Topple"))
        #expect(text.contains("Concentrating: Ward Bond"))
        #expect(text.contains("Exhaustion 2"))
        #expect(text.hasPrefix("%PDF"))
    }

    @Test func pdfExportHidesMasteryColumnIn2014() {
        var c = Character(name: "PdfTest", era: .era2014)
        c.attacks = [Attack(name: "Blade", mastery: .topple)] // ignored under 2014
        let text = String(decoding: SheetPDFExporter.export(c), as: UTF8.self)
        #expect(!text.contains("Mastery"))
        #expect(!text.contains("Concentrating:"))
    }

    @Test func critDoublesDiceKeepsModifier() throws {
        let a = try DiceExpression.parse("1d8+2")
        #expect(a.doubledDice() == "2d8+2")
        let b = try DiceExpression.parse("2d6")
        #expect(b.doubledDice() == "4d6")
        let c = try DiceExpression.parse("1d8+1d4+2")
        #expect(c.doubledDice() == "2d8+2d4+2")
        let d = try DiceExpression.parse("4d6kh3")
        #expect(d.doubledDice() == "8d6kh3")
    }

    @Test func favoritesToggleAndPersist() throws {
        var favs = CompendiumFavorites()
        #expect(!favs.contains(kind: .spell, name: "Fire Bolt"))
        favs.toggle(kind: .spell, name: "Fire Bolt")
        #expect(favs.contains(kind: .spell, name: "fire bolt"))
        favs.toggle(kind: .weapon, name: "Quarterstaff")
        #expect(favs.keys.count == 2)
        favs.toggle(kind: .spell, name: "FIRE BOLT")
        #expect(!favs.contains(kind: .spell, name: "Fire Bolt"))
        #expect(favs.keys.count == 1)

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("architer-favs-\(UUID().uuidString)")
        let store = FavoritesStore(directory: dir)
        store.save(favs)
        let loaded = store.load()
        #expect(loaded == favs)
        #expect(FavoritesStore(directory: dir.appendingPathComponent("nope")).load().keys.isEmpty)
        try? FileManager.default.removeItem(at: dir)
    }

    @Test func rollHistoryPersistsWithLimit() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("architer-rolls-\(UUID().uuidString)")
        let store = RollHistoryStore(directory: dir, limit: 3)
        #expect(store.load().isEmpty)

        let roller = DiceRoller()
        let r1 = try roller.roll("1d6+1")
        let r2 = try roller.roll("2d8")
        let r3 = try roller.roll("d20")
        let r4 = try roller.roll("4d6kh3")
        store.save([r1, r2, r3, r4])
        let loaded = store.load()
        #expect(loaded.count == 3)
        #expect(loaded == [r1, r2, r3])
        #expect(loaded[0].dice == r1.dice)
        try? FileManager.default.removeItem(at: dir)
    }

    @Test func rulesetSanitizedDropsBlanksAndRemapsSkills() {
        let r = Ruleset(
            name: "  Grit Game  ",
            abilities: [" Brawn ", "", "brawn", "Wits"],
            skills: [
                CustomSkillDef(name: " Punch ", abilityName: "Brawn"),
                CustomSkillDef(name: "Scheme", abilityName: "Gone"),
                CustomSkillDef(name: "", abilityName: "Wits"),
            ])
        let clean = r.sanitized()
        #expect(clean.name == "Grit Game")
        #expect(clean.abilities == ["Brawn", "Wits"])
        #expect(clean.skills.count == 2)
        #expect(clean.skills[0].name == "Punch")
        #expect(clean.skills[1].abilityName == "Brawn")
    }

    @Test func characterIORoundTripsWithFreshID() throws {
        let original = SampleContent.demoCharacter()
        let data = try CharacterIO.exportJSON(original)
        let imported = try CharacterIO.importJSON(data)
        #expect(imported.id != original.id)
        #expect(imported.name == original.name)
        #expect(imported.level == original.level)
        #expect(imported.scores == original.scores)
        #expect(imported.attacks == original.attacks)
        let again = try CharacterIO.importJSON(data)
        #expect(again.id != imported.id)
    }

    @Test func compendiumFiltersNarrowResults() {
        #expect(!SpellLibrary.schools.isEmpty)
        let evocations = SpellLibrary.search("", school: "Evocation")
        #expect(!evocations.isEmpty)
        #expect(evocations.allSatisfy { $0.school == "Evocation" })
        let cantripEvocations = SpellLibrary.search("", level: 0, school: "Evocation")
        #expect(cantripEvocations.allSatisfy { $0.level == 0 && $0.school == "Evocation" })
        #expect(cantripEvocations.count <= evocations.count)

        #expect(!EquipmentLibrary.weaponDamageTypes.isEmpty)
        let slashing = EquipmentLibrary.searchWeapons("", damageType: "slashing")
        #expect(!slashing.isEmpty)
        #expect(slashing.allSatisfy { $0.damageType == "slashing" })
        #expect(EquipmentLibrary.searchWeapons("", damageType: "not-a-type").isEmpty)
    }

    @Test func macrosValidateAndPersist() throws {
        let good = DiceMacro(name: "Fireball", expression: "8d6")
        #expect(good.isValid)
        #expect(!DiceMacro(name: "  ", expression: "8d6").isValid)
        #expect(!DiceMacro(name: "Bad", expression: "not dice").isValid)
        #expect(good.id == "fireball")

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("architer-macros-\(UUID().uuidString)")
        let store = MacroStore(directory: dir)
        #expect(store.load().isEmpty)
        store.save([good, DiceMacro(name: "Sneak", expression: "1d8+3d6+3")])
        let loaded = store.load()
        #expect(loaded.count == 2)
        #expect(loaded[0] == good)
        try? FileManager.default.removeItem(at: dir)
    }

    @Test func macrosScopePerCharacterAndDecodeLegacy() throws {
        // Legacy JSON without characterName decodes as table-wide.
        let legacy = #"[{"name":"Fireball","expression":"8d6"}]"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode([DiceMacro].self, from: legacy)
        #expect(decoded == [DiceMacro(name: "Fireball", expression: "8d6")])
        #expect(decoded[0].characterName == nil)
        #expect(decoded[0].id == "fireball")

        // Scoped ids let a table macro and a character macro share a name.
        let table = DiceMacro(name: "Initiative", expression: "1d20+2")
        let wren = DiceMacro(name: "Initiative", expression: "1d20+5", characterName: "Wren Halloway")
        let other = DiceMacro(name: "Sneak attack", expression: "2d6", characterName: "Bruk")
        #expect(table.id != wren.id)
        #expect(wren.id == "wren halloway:initiative")

        // Visibility: table-wide plus the selected character's own.
        let all = [table, wren, other]
        #expect(visibleMacros(all, for: "Wren Halloway") == [table, wren])
        #expect(visibleMacros(all, for: "wren halloway") == [table, wren])
        #expect(visibleMacros(all, for: nil) == [table])

        // Round-trip preserves scope, and the store round-trips scoped macros.
        let data = try JSONEncoder().encode(all)
        let roundTripped = try JSONDecoder().decode([DiceMacro].self, from: data)
        #expect(roundTripped == all)
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("architer-macros-\(UUID().uuidString)")
        let store = MacroStore(directory: dir)
        store.save(all)
        #expect(store.load() == all)
        try? FileManager.default.removeItem(at: dir)
    }

    @Test func pinnedFirstFloatsPinsKeepingOrder() throws {
        let a = DiceMacro(name: "A", expression: "1d6")
        var b = DiceMacro(name: "B", expression: "1d6")
        b.pinned = true
        let c = DiceMacro(name: "C", expression: "1d6")
        // The pin floats above unpinned; relative order is otherwise
        // kept, and a pin survives the JSON round-trip.
        #expect(pinnedFirst([a, b, c]) == [b, a, c])
        #expect(pinnedFirst([a, c]) == [a, c])
        let data = try JSONEncoder().encode([b])
        let roundTripped = try JSONDecoder().decode([DiceMacro].self, from: data)
        #expect(roundTripped == [b])
        // Files written before 3.15.0 carry no pin key and decode unpinned.
        let legacy = try JSONDecoder().decode(
            [DiceMacro].self,
            from: #"[{"name":"A","expression":"1d6"}]"#.data(using: .utf8)!)
        #expect(legacy.first?.pinned == nil)
    }

    @Test func freeRollerTypeMemoryResolvesPerCharacter() throws {
        // Missing entry falls back to the table-wide selection.
        #expect(resolveFreeRollerType(map: [:], characterID: "A", tableDefault: .fire) == .fire)
        #expect(resolveFreeRollerType(map: [:], characterID: nil, tableDefault: .cold) == .cold)
        // A stored type wins over the table default; "" is an explicit
        // untyped choice that beats a typed table default.
        let map = ["A": "lightning", "B": ""]
        #expect(resolveFreeRollerType(map: map, characterID: "A", tableDefault: .fire) == .lightning)
        #expect(resolveFreeRollerType(map: map, characterID: "B", tableDefault: .fire) == nil)
        // Unknown stored strings (renamed cases) decode to nil, not a crash.
        #expect(resolveFreeRollerType(map: ["C": "bogus"], characterID: "C", tableDefault: .fire) == nil)
        // The write helper records types and the explicit-untyped sentinel.
        let written = storingFreeRollerType(.acid, in: [:], characterID: "A")
        #expect(written == ["A": "acid"])
        #expect(storingFreeRollerType(nil, in: written, characterID: "A") == ["A": ""])
    }

    @Test func damageTypeRawValuesStayStableForPersistence() throws {
        // The free-roller type picker persists rawValue strings in
        // user defaults; renaming a case would silently drop the saved
        // selection, so the persisted vocabulary is pinned here.
        #expect(DamageType.allCases.map(\.rawValue) == [
            "acid", "bludgeoning", "cold", "fire", "force", "lightning",
            "necrotic", "piercing", "poison", "psychic", "radiant",
            "slashing", "thunder",
        ])
        #expect(DamageType(rawValue: "fire") == .fire)
        #expect(DamageType(rawValue: "bogus") == nil)
    }

    @Test func macroDuplicateCopiesAndBumpsNames() throws {
        let fireball = DiceMacro(name: "Fireball", expression: "8d6")

        // Plain copy: name, expression and owner binding all carry over.
        let copy = duplicatedMacro(fireball, existing: [fireball])
        #expect(copy == DiceMacro(name: "Fireball copy", expression: "8d6"))

        // Taken copy names bump: copy 2, copy 3, ...
        let taken = [fireball, copy, DiceMacro(name: "Fireball copy 2", expression: "8d6")]
        #expect(duplicatedMacro(fireball, existing: taken).name == "Fireball copy 3")

        // Owner binding is preserved and scoped: another character's
        // same-named macro does not force a bump.
        let wren = DiceMacro(name: "Fireball", expression: "9d6", characterName: "Wren Halloway")
        let wrenCopy = duplicatedMacro(wren, existing: [fireball, wren])
        #expect(wrenCopy == DiceMacro(name: "Fireball copy", expression: "9d6", characterName: "Wren Halloway"))
        #expect(wrenCopy.id != fireball.id)
    }

    @Test func currencyConsolidationKeepsValue() {
        let purse = Currency(copper: 1234, silver: 7, electrum: 3, gold: 5, platinum: 0)
        let tidy = purse.normalized()
        #expect(tidy.totalCopper == purse.totalCopper)
        #expect(tidy.electrum == 0)
        #expect(tidy.silver < 10 && tidy.copper < 10)
        #expect(Currency(copper: 1234).normalized() == Currency(copper: 4, silver: 3, gold: 2, platinum: 1))
        #expect(Currency().normalized() == Currency())
    }

    @Test func oldSaveFormatDecodes() throws {
        let json = """
        {"id":"\(UUID().uuidString)","name":"Legacy","lineage":"","calling":"","background":"",
        "level":3,"experience":900,"scores":{},"skills":[],
        "savingThrowProficiencies":[],"maxHP":20,"currentHP":20,"armorClass":12,"speed":30,
        "attacks":[{"name":"Sword","attackBonus":5,"damageExpression":"1d8+3","notes":""}],
        "inventory":[{"name":"Rope","quantity":1,"notes":""}],
        "notes":"","layout":{"blocks":[{"kind":"identity","visible":true,"size":"regular"}]}}
        """.data(using: .utf8)!
        let c = try JSONDecoder().decode(Character.self, from: json)
        #expect(c.attacks.first?.attackBonus(scores: c.scores, level: c.level) == 5)
        #expect(c.tempHP == 0)
        #expect(c.hitDiceType == 8)
        #expect(c.layout.blocks.count > 1)
        #expect(c.layout.blocks.contains { $0.kind == .spells })
        #expect(c.portrait == nil)
    }
}

@Suite("Rules tables")
struct RulesTableTests {

    @Test func xpThresholdsAreMonotonic() {
        for i in 1..<RulesMath.xpThresholds.count {
            #expect(RulesMath.xpThresholds[i] > RulesMath.xpThresholds[i - 1])
        }
        #expect(RulesMath.level(forXP: 0) == 1)
        #expect(RulesMath.level(forXP: 354999) == 19)
        #expect(RulesMath.level(forXP: 355000) == 20)
    }

    @Test func fullCasterSlotsMatchTable() {
        #expect(RulesMath.spellSlots(casterLevel: 1, spellLevel: 1) == 2)
        #expect(RulesMath.spellSlots(casterLevel: 5, spellLevel: 3) == 2)
        #expect(RulesMath.spellSlots(casterLevel: 20, spellLevel: 9) == 1)
        #expect(RulesMath.spellSlots(casterLevel: 2, spellLevel: 2) == 0)
    }

    @Test func pactSlots() {
        #expect(RulesMath.pactSlots(casterLevel: 1) == (1, 1))
        #expect(RulesMath.pactSlots(casterLevel: 9) == (2, 5))
        #expect(RulesMath.pactSlots(casterLevel: 17) == (4, 5))
    }

    @Test func carryingCapacity() {
        #expect(RulesMath.carryingCapacity(strength: 10) == 150)
        #expect(RulesMath.pushDragLift(strength: 10) == 300)
    }
}

@Suite("Spellcasting")
struct SpellcastingTests {

    @Test func slotUsage() {
        var sc = Spellcasting(ability: .intelligence, progression: .full)
        #expect(sc.slotsMax(spellLevel: 1, casterLevel: 3) == 4)
        sc.useSlot(spellLevel: 1, casterLevel: 3)
        #expect(sc.slotsRemaining(spellLevel: 1, casterLevel: 3) == 3)
        sc.restoreSlot(spellLevel: 1)
        #expect(sc.slotsRemaining(spellLevel: 1, casterLevel: 3) == 4)
    }

    @Test func halfAndThirdProgressions() {
        let half = CasterProgression.half
        #expect(half.slots(spellLevel: 1, level: 1) == 0)  // no casting at level 1
        #expect(half.slots(spellLevel: 1, level: 2) == 2)  // caster level 1
        let third = CasterProgression.third
        #expect(third.slots(spellLevel: 1, level: 3) == 2)
        #expect(third.maxSpellLevel(level: 3) == 1)
    }

    @Test func dcAndAttack() {
        var scores = AbilityScores()
        scores[.intelligence] = 16 // +3
        let sc = Spellcasting(ability: .intelligence)
        #expect(sc.spellSaveDC(scores: scores, level: 5) == 14) // 8 + 3 + 3
        #expect(sc.spellAttackBonus(scores: scores, level: 5) == 6)
    }

    @Test func libraryIntegrity() {
        let names = SpellLibrary.all.map { $0.name }
        #expect(Set(names).count == names.count) // unique
        #expect(SpellLibrary.all.count >= 50)
        #expect(SpellLibrary.all.allSatisfy { !$0.detail.isEmpty })
        for level in 0...9 {
            #expect(!SpellLibrary.spells(atLevel: level).isEmpty)
        }
        #expect(SpellLibrary.spell(named: "Fireball")?.level == 3)
    }
}

@Suite("Equipment library")
struct EquipmentTests {

    @Test func armorStats() {
        let leather = EquipmentLibrary.armor(named: "Leather")!
        #expect(leather.baseAC == 11 && leather.addDex)
        let plate = EquipmentLibrary.armor(named: "Plate")!
        #expect(plate.baseAC == 18 && !plate.addDex)
        #expect(EquipmentLibrary.armors.allSatisfy { $0.weight > 0 })
    }

    @Test func weaponStats() {
        let dagger = EquipmentLibrary.weapon(named: "Dagger")!
        #expect(dagger.finesse)
        #expect(dagger.damageExpression == "1d4")
        let greatsword = EquipmentLibrary.weapon(named: "Greatsword")!
        #expect(greatsword.damageExpression == "2d6")
        // Every weapon's damage expression parses.
        for w in EquipmentLibrary.weapons {
            #expect((try? DiceExpression.parse(w.damageExpression)) != nil)
        }
    }
}

@Suite("Journal")
struct JournalTests {

    @Test func moveJournalEntryNudgesAndClamps() throws {
        var c = Character(name: "Wren Halloway")
        c.journal = [JournalEntry(title: "A"), JournalEntry(title: "B"), JournalEntry(title: "C")]
        let a = c.journal[0].id, b = c.journal[1].id
        // Middle entry moves up.
        c.moveJournalEntry(b, by: -1)
        #expect(c.journal.map(\.title) == ["B", "A", "C"])
        // Edge moves clamp to a no-op.
        c.moveJournalEntry(b, by: -1)
        #expect(c.journal.map(\.title) == ["B", "A", "C"])
        // Large offsets clamp to the far edge.
        c.moveJournalEntry(b, by: 99)
        #expect(c.journal.map(\.title) == ["A", "C", "B"])
        // Unknown ids and zero offsets change nothing.
        c.moveJournalEntry(UUID(), by: 1)
        c.moveJournalEntry(a, by: 0)
        #expect(c.journal.map(\.title) == ["A", "C", "B"])
    }

    @Test func collapseStateDecodesAndRoundTrips() throws {
        // The pre-2.51.0 saved shape: no isCollapsed key at all.
        let json = #"{"date":"Session 1","title":"Start","text":"It began."}"#
        let legacy = try JSONDecoder().decode(JournalEntry.self, from: Data(json.utf8))
        #expect(legacy.isCollapsed == nil)
        // A collapsed entry round-trips with its state.
        var e = JournalEntry(title: "Long", text: "one\ntwo")
        e.isCollapsed = true
        let decoded = try JSONDecoder().decode(JournalEntry.self, from: JSONEncoder().encode(e))
        #expect(decoded == e)
        #expect(decoded.isCollapsed == true)
    }

    @Test func journalEntryIsLongRule() throws {
        #expect(JournalEntry(text: "short").isLong == false)
        #expect(JournalEntry(text: String(repeating: "x", count: 80)).isLong == false)
        #expect(JournalEntry(text: String(repeating: "x", count: 81)).isLong == true)
        #expect(JournalEntry(text: "one\ntwo").isLong == true)
    }

    @Test func setAllJournalCollapsedTogglesLongOnly() throws {
        var c = Character(name: "Wren Halloway")
        c.journal = [
            JournalEntry(title: "Short", text: "brief"),
            JournalEntry(title: "Long", text: "one\ntwo"),
            JournalEntry(title: "Longer", text: String(repeating: "x", count: 90)),
        ]
        c.setAllJournalCollapsed(true)
        #expect(c.journal[0].isCollapsed == nil)
        #expect(c.journal[1].isCollapsed == true)
        #expect(c.journal[2].isCollapsed == true)
        // Expanding restores the default nil, and short entries stay out.
        c.setAllJournalCollapsed(false)
        #expect(c.journal[0].isCollapsed == nil)
        #expect(c.journal[1].isCollapsed == nil)
        #expect(c.journal[2].isCollapsed == nil)
    }

    @Test func journalEntryShareText() throws {
        // Stamped entry: head carries the creation time, body follows.
        let stamped = JournalEntry(date: "2026-09-24", title: "Fire Bolt damage",
                                   text: "Rolled 15 (2d10+3)",
                                   createdAt: Date(timeIntervalSince1970: 1_790_000_000))
        let head = stamped.exportHead
        #expect(stamped.shareText == head + "\nRolled 15 (2d10+3)")
        #expect(stamped.shareText.hasPrefix("2026-09-24 "))
        // Bodiless entry shares its head alone.
        #expect(JournalEntry(date: "Session 1", title: "Start").shareText == "Session 1 - Start")
    }

    @Test func duplicateJournalEntryInsertsCopyBelow() throws {
        var c = Character(name: "Wren Halloway")
        c.journal = [JournalEntry(title: "A", text: "alpha"),
                     JournalEntry(title: "B", text: "bravo")]
        let a = c.journal[0].id
        c.duplicateJournalEntry(a)
        #expect(c.journal.count == 3)
        #expect(c.journal[1].title == "A")
        #expect(c.journal[1].text == "alpha")
        #expect(c.journal[1].id != a)
        #expect(c.journal[1].createdAt != nil)
        #expect(c.journal[0].id == a)
        #expect(c.journal[2].title == "B")
        // Unknown ids change nothing.
        c.duplicateJournalEntry(UUID())
        #expect(c.journal.count == 3)
    }

    @Test func journalTemplateEntryAppendsStampedOutline() throws {
        var c = Character(name: "Wren Halloway")
        c.journal = [JournalEntry(title: "A", text: "alpha")]
        let combat = JournalTemplate.builtIn[0]
        c.addJournalEntry(from: combat)
        #expect(c.journal.count == 2)
        let entry = c.journal[1]
        #expect(entry.title == "Combat debrief")
        #expect(entry.text.hasPrefix("Encounter:"))
        #expect(entry.text.contains("Loose ends:"))
        #expect(entry.createdAt != nil)
        #expect(entry.id != c.journal[0].id)
        #expect(JournalTemplate.builtIn.map { $0.name } == ["Combat debrief", "NPC meeting", "Loot log"])
    }

    @Test func journalMatchingLinesFindsCaseInsensitiveHits() throws {
        let e = JournalEntry(text: "Rolled 15 (2d10+3)\nFire Bolt damage\nno hit here\nFIRE again")
        #expect(e.matchingLines("fire") == ["Fire Bolt damage", "FIRE again"])
        #expect(e.matchingLines("") == [])
        #expect(e.matchingLines("   ") == [])
        #expect(e.matchingLines("absent") == [])
        #expect(JournalEntry(text: "").matchingLines("x") == [])
    }

    @Test func journalPinFixesEntryAtTop() throws {
        var c = Character(name: "Wren Halloway")
        c.journal = [JournalEntry(title: "A"), JournalEntry(title: "B"), JournalEntry(title: "C")]
        #expect(c.journal[1].isPinned == nil)
        let b = c.journal[1].id
        c.setJournalEntryPinned(b, true)
        #expect(c.journal[0].id == b)
        #expect(c.journal[0].isPinned == true)
        // Pinned entries ignore reorder moves.
        c.moveJournalEntry(b, by: 1)
        #expect(c.journal[0].id == b)
        // Other entries cannot move above the pinned block.
        let cId = c.journal[2].id
        c.moveJournalEntry(cId, by: -1)
        #expect(c.journal[1].id == cId)
        c.moveJournalEntry(cId, by: -1)
        #expect(c.journal[1].id == cId)
        #expect(c.journal[0].id == b)
        // Unpin clears the flag to nil and frees the entry.
        c.setJournalEntryPinned(b, false)
        #expect(c.journal[0].isPinned == nil)
        c.moveJournalEntry(b, by: 1)
        #expect(c.journal[1].id == b)
        // A second pin piles after the first.
        c.setJournalEntryPinned(cId, true)
        c.setJournalEntryPinned(b, true)
        #expect(c.journal[0].id == cId)
        #expect(c.journal[1].id == b)
        // Unknown ids are a no-op.
        c.setJournalEntryPinned(UUID(), true)
        #expect(c.journal.count == 3)
    }

    @Test func digestBodyFormats() throws {
        var r1 = RollResult(expression: "1d20+6", dice: [DieResult(sides: 20, value: 15, kept: true)],
                            modifier: 6, total: 21, alternateTotal: nil)
        r1.label = "Stealth check"
        r1.characterName = "Wren"
        var r2 = RollResult(expression: "2d10+3", dice: [DieResult(sides: 10, value: 4, kept: true)],
                            modifier: 3, total: 7, alternateTotal: nil)
        r2.label = "Fire Bolt damage"
        r2.characterName = "Wren"
        let r3 = RollResult(expression: "1d8", dice: [DieResult(sides: 8, value: 5, kept: true)],
                            modifier: 0, total: 5, alternateTotal: nil)
        // r3 has no character - filed under Table.
        let session = RollSession(number: 2, title: "Session 2 - Today", key: nil, rolls: [r3, r2, r1])
        let condensed = JournalEntry.digestBody(session: session, format: .condensed)
        // 2.73.0: the body opens with the stats line, then a blank line.
        #expect(condensed.hasPrefix("3 rolls \u{00B7} high 21 \u{00B7} low 5\n\n"))
        #expect(condensed.components(separatedBy: "\n").count == 5)
        #expect(!condensed.contains("Wren:"))
        let grouped = JournalEntry.digestBody(session: session, format: .byActor)
        let groups = grouped.components(separatedBy: "\n\n")
        #expect(groups.count == 3)
        #expect(groups[0] == "3 rolls \u{00B7} high 21 \u{00B7} low 5")
        #expect(groups[1].hasPrefix("Wren:"))
        #expect(groups[1].components(separatedBy: "\n").count == 3)
        #expect(groups[2].hasPrefix("Table:"))
        // A noted session adds its note under the stats line.
        let noted = JournalEntry.digestBody(session: session.noted("The bridge over the Ember"),
                                            format: .condensed)
        #expect(noted.hasPrefix("3 rolls \u{00B7} high 21 \u{00B7} low 5\nThe bridge over the Ember\n\n"))
        // The digest init defaults to condensed and honors the format.
        #expect(JournalEntry(sessionDigest: session).text == condensed)
        #expect(JournalEntry(sessionDigest: session, format: .byActor).text == grouped)
    }

    // 2.93.0: a noted roll's note rides the digest body under its line,
    /// in both layouts; unnoted rolls stay one line each.
    @Test func digestBodyCarriesRollNotes() throws {
        var r1 = RollResult(expression: "8d6", dice: [DieResult(sides: 6, value: 5, kept: true)],
                            modifier: 0, total: 27, alternateTotal: nil)
        r1.label = "Fireball"
        r1.characterName = "Wren"
        r1.note = "The bridge collapses behind them"
        let r2 = RollResult(expression: "d20", dice: [DieResult(sides: 20, value: 11, kept: true)],
                            modifier: 0, total: 11, alternateTotal: nil)
        let session = RollSession(number: 1, title: "Session 1 - Today", key: nil, rolls: [r2, r1])
        let condensed = JournalEntry.digestBody(session: session, format: .condensed)
        let condensedLines = condensed.components(separatedBy: "\n")
        let fireballIdx = try #require(condensedLines.firstIndex(where: { $0.contains("Fireball: 27 (8d6)") }))
        #expect(condensedLines[fireballIdx + 1] == "  The bridge collapses behind them")
        let grouped = JournalEntry.digestBody(session: session, format: .byActor)
        let groups = grouped.components(separatedBy: "\n\n")
        let wren = try #require(groups.first(where: { $0.hasPrefix("Wren:") }))
        let wrenLines = wren.components(separatedBy: "\n")
        let wrenFireballIdx = try #require(wrenLines.firstIndex(where: { $0.contains("Fireball: 27 (8d6)") }))
        #expect(wrenLines[wrenFireballIdx + 1] == "  The bridge collapses behind them")
        let table = try #require(groups.first(where: { $0.hasPrefix("Table:") }))
        #expect(table.components(separatedBy: "\n").count == 2)
    }

    @Test func journalFilteredShareText() throws {
        let a = JournalEntry(date: "Session 1", title: "Start", text: "It began.")
        let b = JournalEntry(date: "Session 2", title: "Fire fight", text: "Burning.")
        #expect(a.matchesFilter(""))
        #expect(a.matchesFilter("  "))
        #expect(a.matchesFilter("START"))
        #expect(b.matchesFilter("fire"))
        #expect(!a.matchesFilter("fire"))
        #expect(JournalEntry.shareText(entries: [a, b]) == a.shareText + "\n\n" + b.shareText)
        #expect(JournalEntry.shareText(entries: [a]) == a.shareText)
        #expect(JournalEntry.shareText(entries: []) == "")
    }

    @Test func journalBulkSummaryCountsLinesAndWords() throws {
        let entries = [JournalEntry(title: "A", text: "one two\nthree"),
                       JournalEntry(title: "B", text: "four"),
                       JournalEntry(title: "C", text: "   ")]
        #expect(JournalEntry.bulkSummary(entries: entries) == "3 lines · 4 words")
        #expect(JournalEntry.bulkSummary(entries: [JournalEntry(text: "")]) == nil)
        #expect(JournalEntry.bulkSummary(entries: []) == nil)
        #expect(JournalEntry.bulkSummary(entries: [JournalEntry(text: "a\nb\nc")]) == "3 lines · 3 words")
    }

    @Test func journalEntrySizeLabel() throws {
        #expect(JournalEntry(text: "").sizeLabel == nil)
        #expect(JournalEntry(text: "   \n  ").sizeLabel == nil)
        #expect(JournalEntry(text: "one").sizeLabel == "1 word")
        #expect(JournalEntry(text: "Rolled 15 (2d10+3)").sizeLabel == "3 words")
        #expect(JournalEntry(text: "a\nb").sizeLabel == "2 lines")
        #expect(JournalEntry(text: "a\nb\nc").sizeLabel == "3 lines")
        // A trailing newline does not inflate the count.
        #expect(JournalEntry(text: "a\nb\n").sizeLabel == "2 lines")
    }

    @Test func journalRoundTripsAndDefaults() throws {
        var c = Character(name: "Test")
        #expect(c.journal.isEmpty)
        c.journal = [JournalEntry(date: "Session 1", title: "Start", text: "It began.")]
        let data = try JSONEncoder().encode(c)
        let decoded = try JSONDecoder().decode(Character.self, from: data)
        #expect(decoded.journal == c.journal)
        // Old layouts gain the journal block on decode.
        #expect(decoded.layout.blocks.contains { $0.kind == .journal })
    }

    @Test func exportsIncludeJournal() {
        var c = Character(name: "Test")
        c.journal = [JournalEntry(date: "Session 1", title: "Start", text: "It began.")]
        let md = SheetExporter.exportMarkdown(c)
        #expect(md.contains("## Journal"))
        #expect(md.contains("Session 1 - Start"))
        let html = SheetExporter.exportHTML(c)
        #expect(html.contains("<h2>Journal</h2>"))
        let pdf = String(decoding: SheetPDFExporter.export(c), as: UTF8.self)
        #expect(pdf.contains("(JOURNAL"))
        // Empty journal stays out of every export.
        let empty = SheetExporter.exportMarkdown(Character(name: "Test"))
        #expect(!empty.contains("## Journal"))
    }

    @Test func exportJournalTimestampOptionDropsTimes() {
        let stamp = Date(timeIntervalSince1970: 1_790_000_000)
        let e = JournalEntry(date: "2026-09-24", title: "4d6kh3", createdAt: stamp)
        #expect(e.exportHeadWithoutTime == "2026-09-24 - 4d6kh3")
        #expect(JournalEntry().exportHeadWithoutTime == "Entry")
        var c = Character(name: "Test")
        c.journal = [e]
        let time = RollResult.historyTimeFormatter.string(from: stamp)
        // Default exports keep the stamped head.
        #expect(SheetExporter.exportMarkdown(c).contains(time))
        #expect(SheetExporter.exportHTML(c).contains(time))
        let pdf = String(decoding: SheetPDFExporter.export(c), as: UTF8.self)
        #expect(pdf.contains(time))
        // The option drops it everywhere.
        #expect(!SheetExporter.exportMarkdown(c, journalTimestamps: false).contains(time))
        #expect(!SheetExporter.exportHTML(c, journalTimestamps: false).contains(time))
        let plainPdf = String(decoding: SheetPDFExporter.export(c, journalTimestamps: false), as: UTF8.self)
        #expect(!plainPdf.contains(time))
        // The head itself survives in both modes.
        #expect(SheetExporter.exportMarkdown(c, journalTimestamps: false).contains("2026-09-24 - 4d6kh3"))
    }

    @Test func exportHeadAddsTimeForStampedEntries() {
        let stamp = Date(timeIntervalSince1970: 1_790_000_000)
        let time = RollResult.historyTimeFormatter.string(from: stamp)
        // Unstamped entries keep the pre-2.47.0 head.
        #expect(JournalEntry(date: "Session 1", title: "Start").exportHead == "Session 1 - Start")
        // Stamped entries render their creation time after the date.
        #expect(JournalEntry(date: "2026-09-24", title: "4d6kh3",
                             createdAt: stamp).exportHead == "2026-09-24 \(time) - 4d6kh3")
        // A stamp with no free-form date still shows the time.
        #expect(JournalEntry(title: "T", createdAt: stamp).exportHead == "\(time) - T")
        // Nothing at all stays "Entry".
        #expect(JournalEntry().exportHead == "Entry")
    }

    @Test func exportsShowStampedEntryTimes() {
        let stamp = Date(timeIntervalSince1970: 1_790_000_000)
        let time = RollResult.historyTimeFormatter.string(from: stamp)
        var c = Character(name: "Test")
        c.journal = [JournalEntry(date: "2026-09-24", title: "4d6kh3",
                                  text: "Rolled 12.", createdAt: stamp)]
        let md = SheetExporter.exportMarkdown(c)
        #expect(md.contains("### 2026-09-24 \(time) - 4d6kh3"))
        let html = SheetExporter.exportHTML(c)
        #expect(html.contains("<h3>2026-09-24 \(time) - 4d6kh3</h3>"))
        let pdf = String(decoding: SheetPDFExporter.export(c), as: UTF8.self)
        #expect(pdf.contains("(2026-09-24 \(time) - 4d6kh3)"))
        // Unstamped entries render no time anywhere.
        var legacy = Character(name: "Test")
        legacy.journal = [JournalEntry(date: "Session 1", title: "Start", text: "It began.")]
        #expect(!SheetExporter.exportMarkdown(legacy).contains(time))
    }
}

@Suite("Character portrait")
struct PortraitTests {

    @Test func portraitRoundTripsAndDefaults() throws {
        var c = Character(name: "Test")
        #expect(c.portrait == nil)
        c.portrait = Data([0x89, 0x50, 0x4E, 0x47]) // PNG magic bytes
        let data = try JSONEncoder().encode(c)
        let decoded = try JSONDecoder().decode(Character.self, from: data)
        #expect(decoded.portrait == c.portrait)
    }

    @Test func htmlExportEmbedsPortraitOnlyWhenSet() {
        var c = Character(name: "Test")
        let without = SheetExporter.exportHTML(c)
        #expect(!without.contains("img class=\"portrait\""))
        c.portrait = Data([1, 2, 3, 4])
        let with = SheetExporter.exportHTML(c)
        #expect(with.contains("img class=\"portrait\""))
        #expect(with.contains("data:image/png;base64,"))
    }
}

@Suite("Attunement tracking")
struct AttunementTests {

    @Test func countsAttunedItems() {
        var c = Character(name: "Test")
        #expect(c.attunedCount == 0)
        #expect(!c.overAttuned)
        c.inventory = [
            InventoryItem(name: "Ring", attuned: true),
            InventoryItem(name: "Cloak", attuned: true),
            InventoryItem(name: "Rations"),
        ]
        #expect(c.attunedCount == 2)
        #expect(!c.overAttuned)
    }

    @Test func overLimitFlagsAtFour() {
        var c = Character(name: "Test")
        c.inventory = (1...4).map { InventoryItem(name: "Item \($0)", attuned: true) }
        #expect(c.attunedCount == 4)
        #expect(c.overAttuned)
        #expect(Character.attunementLimit == 3)
    }
}

@Suite("Versatile weapons")
struct VersatileTests {

    @Test func libraryParsesVersatileDice() {
        let staff = EquipmentLibrary.weapons.first { $0.name == "Quarterstaff" }
        #expect(staff?.versatileDamageExpression == "1d8")
        let longsword = EquipmentLibrary.weapons.first { $0.name == "Longsword" }
        #expect(longsword?.versatileDamageExpression == "1d10")
        let dagger = EquipmentLibrary.weapons.first { $0.name == "Dagger" }
        #expect(dagger?.versatileDamageExpression == nil)
    }

    @Test func twoHandedSwitchesDamageExpression() {
        var scores = AbilityScores()
        scores[.strength] = 16 // +3
        var attack = Attack(name: "Longsword", damageExpression: "1d8",
                            versatileExpression: "1d10")
        #expect(attack.damageString(scores: scores) == "1d8+3")
        attack.twoHanded = true
        #expect(attack.damageString(scores: scores) == "1d10+3")
        // Non-versatile attacks ignore the grip flag.
        var plain = Attack(name: "Dagger", damageExpression: "1d4")
        plain.twoHanded = true
        #expect(plain.damageString(scores: scores) == "1d4+3")
    }

    @Test func pinnedAttackIgnoresGrip() {
        // Legacy pinned attacks roll their literal expression either way.
        var attack = Attack(name: "Old blade", attackBonus: 5, damageExpression: "1d8+3")
        attack.versatileExpression = "1d10"
        attack.twoHanded = true
        #expect(attack.damageString(scores: AbilityScores()) == "1d10")
    }

    @Test func versatileFieldsRoundTrip() throws {
        var attack = Attack(name: "Spear", damageExpression: "1d6",
                            versatileExpression: "1d8", twoHanded: true)
        let data = try JSONEncoder().encode(attack)
        let decoded = try JSONDecoder().decode(Attack.self, from: data)
        #expect(decoded == attack)
        // Old saves without the new fields decode with defaults.
        let minimal = Data(#"{"name":"Club","damageExpression":"1d4"}"#.utf8)
        let old = try JSONDecoder().decode(Attack.self, from: minimal)
        #expect(old.versatileExpression == nil)
        #expect(old.twoHanded == false)
        attack = old
        #expect(attack.damageString(scores: AbilityScores()) == "1d4")
    }
}

@Suite("Sample content")
struct SampleContentTests {

    @Test func demoCharacterIsRichAndValid() {
        let c = SampleContent.demoCharacter()
        #expect(c.spellcasting != nil)
        #expect(c.features.count >= 4)
        #expect(c.attacks.count >= 2)
        #expect(c.inventory.count >= 5)
        #expect(!c.personality.isEmpty)
        #expect(c.currency.totalCopper > 0)
        // Exports cover the new sections.
        let md = SheetExporter.exportMarkdown(c)
        #expect(md.contains("## Spells"))
        #expect(md.contains("## Features"))
        #expect(md.contains("## Personality"))
        #expect(md.contains("Currency:"))
        let pdf = String(decoding: SheetPDFExporter.export(c), as: UTF8.self)
        #expect(pdf.contains("(SPELLS"))
        #expect(pdf.contains("(FEATURES"))
    }
}

@Suite("Inventory consume and restock")
struct InventoryConsumeRestockTests {
    @Test func consumeDecrementsAndClampsAtZero() {
        var item = InventoryItem(name: "Potion of healing", quantity: 2)
        item.consumeOne()
        #expect(item.quantity == 1)
        item.consumeOne()
        item.consumeOne() // floor: never negative
        #expect(item.quantity == 0)
    }

    @Test func restockIncrementsAndClampsAt999() {
        var item = InventoryItem(name: "Arrows", quantity: 0)
        item.restockOne()
        #expect(item.quantity == 1)
        var full = InventoryItem(name: "Arrows", quantity: 999)
        full.restockOne() // ceiling: matches the init's 0...999 range
        #expect(full.quantity == 999)
    }
}
