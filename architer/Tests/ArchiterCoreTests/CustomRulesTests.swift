import Testing
import Foundation
@testable import ArchiterCore

private func starfarerCharacter() -> Character {
    var c = Character(name: "Jax Veran", calling: "Free Trader", level: 3)
    c.apply(ruleset: .starfarer)
    c.customAbilities[0].score = 15 // Physique +2
    c.customAbilities[2].score = 16 // Logic +3
    if let i = c.customSkills.firstIndex(where: { $0.name == "Astronavigation" }) {
        c.customSkills[i].tier = .expert
    }
    return c
}

@Suite("Custom rulesets")
struct CustomRulesTests {

    @Test func rulesetApplicationFillsCustomFields() {
        let c = starfarerCharacter()
        #expect(c.rulesetName == "Starfarer")
        #expect(c.customAbilities.map(\.name) == ["Physique", "Reflex", "Logic", "Presence"])
        #expect(c.customAbilities.map(\.abbreviation) == ["PHY", "REF", "LOG", "PRE"])
        #expect(c.customSkills.count == 8)
        #expect(c.customSkills.allSatisfy { $0.tier == .none } == false)
    }

    @Test func customSkillBonusUsesAbilityAndTier() {
        let c = starfarerCharacter()
        let astro = c.customSkills.first { $0.name == "Astronavigation" }!
        // Logic 16 -> +3, expert at level 3 -> 2 * +2 = +4, total +7
        #expect(astro.bonus(abilities: c.customAbilities, level: c.level) == 7)
        let salvage = c.customSkills.first { $0.name == "Salvage" }!
        // Physique 15 -> +2, no tier
        #expect(salvage.bonus(abilities: c.customAbilities, level: c.level) == 2)
    }

    @Test func reapplyingKeepsCarriedOverScores() {
        var c = starfarerCharacter()
        c.apply(ruleset: .starfarer)
        #expect(c.customAbilities.first { $0.name == "Logic" }?.score == 16)
    }

    @Test func legacyCharacterJSONDecodes() throws {
        // Encode a character, strip the v0.3 keys, decode: defaults apply.
        let c = Character(name: "Legacy")
        let data = try JSONEncoder().encode(c)
        var obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        obj.removeValue(forKey: "rulesetName")
        obj.removeValue(forKey: "customAbilities")
        obj.removeValue(forKey: "customSkills")
        let stripped = try JSONSerialization.data(withJSONObject: obj)
        let decoded = try JSONDecoder().decode(Character.self, from: stripped)
        #expect(decoded.name == "Legacy")
        #expect(decoded.customAbilities.isEmpty && decoded.customSkills.isEmpty)
        #expect(decoded.rulesetName == nil)
    }

    @Test func customFieldsPersist() throws {
        let c = starfarerCharacter()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("architer-custom-\(UUID().uuidString)")
        let store = CharacterStore(directory: dir)
        try store.save(c)
        let loaded = try store.load(id: c.id)
        #expect(loaded.rulesetName == "Starfarer")
        #expect(loaded.customAbilities.count == 4)
        #expect(loaded.customSkills.count == 8)
    }
}

@Suite("Templated blocks")
struct TemplateTests {

    @Test func placeholdersResolve() {
        var c = starfarerCharacter()
        c.scores[.dexterity] = 16
        let out = TemplateRenderer.render(
            "{name} the {calling} (lvl {level}) DEX {dex}/{dex.mod} LOG {c.Logic}/{c.Logic.mod}",
            for: c)
        #expect(out == "Jax Veran the Free Trader (lvl 3) DEX 16/+3 LOG 16/+3")
    }

    @Test func unknownPlaceholdersStayVisible() {
        let c = Character(name: "N")
        #expect(TemplateRenderer.render("HP {hp} {nonsense}", for: c) == "HP 10 [?nonsense]")
    }

    @Test func customBlocksRenderInMarkdownAndHTML() {
        var c = starfarerCharacter()
        c.layout.customBlocks = [
            CustomBlock(title: "Ship Log", body: "Captain {name}, level {level}. Hull at {hp}/{maxhp}."),
        ]
        let md = SheetExporter.exportMarkdown(c)
        #expect(md.contains("## Ship Log"))
        #expect(md.contains("Captain Jax Veran, level 3."))
        #expect(md.contains("## Starfarer Abilities"))
        #expect(md.contains("| Logic | 16 | +3 |"))
        #expect(md.contains("## Starfarer Skills"))
        #expect(md.contains("Astronavigation +7 (expert)"))
        let html = SheetExporter.exportHTML(c)
        #expect(html.contains("<h2>Ship Log</h2>"))
        #expect(html.contains("Captain Jax Veran, level 3."))
    }

    @Test func customBlocksRenderInPDF() {
        var c = starfarerCharacter()
        c.layout.customBlocks = [
            CustomBlock(title: "Ship Log", body: "Captain {name} commands at Logic {c.Logic.mod}."),
        ]
        let text = String(decoding: SheetPDFExporter.export(c), as: UTF8.self)
        #expect(text.contains("(SHIP LOG)"))
        #expect(text.contains("Captain Jax Veran commands at Logic +3."))
        #expect(text.contains("(STARFARER ABILITIES)"))
        #expect(text.contains("(Physique)"))
    }

    @Test func legacyLayoutJSONDecodes() throws {
        let layout = SheetLayout()
        let data = try JSONEncoder().encode(layout)
        var obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        obj.removeValue(forKey: "customBlocks")
        let stripped = try JSONSerialization.data(withJSONObject: obj)
        let decoded = try JSONDecoder().decode(SheetLayout.self, from: stripped)
        #expect(decoded.blocks.count == SheetBlockKind.allCases.count)
        #expect(decoded.customBlocks.isEmpty)
    }
}
