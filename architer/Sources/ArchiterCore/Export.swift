import Foundation

/// Renders a character sheet as Markdown or self-contained styled HTML,
/// honoring the layout's block visibility and order.
public enum SheetExporter {

    public static func exportMarkdown(_ c: Character) -> String {
        var out: [String] = []
        for block in c.layout.visibleBlocks {
            switch block.kind {
            case .identity:
                var head = """
                # \(c.name)
                **Level \(c.level)** \(c.lineage) \(c.calling)\(c.background.isEmpty ? "" : " — \(c.background)")\(c.alignment.isEmpty ? "" : " (\(c.alignment))")
                XP: \(c.experience)\(c.xpToNextLevel.map { " (\($0) to level \(c.level + 1))" } ?? "") · Proficiency bonus: +\(c.proficiencyBonus)\(c.inspiration ? " · Inspired" : "")
                """
                if !c.proficienciesText.isEmpty { head += "\nProficiencies: \(c.proficienciesText)" }
                out.append(head)
            case .abilities:
                var lines = ["## Abilities", "| Ability | Score | Mod | Save |", "|---|---|---|---|"]
                for a in Ability.allCases {
                    let save = c.savingThrow(a)
                    let prof = c.savingThrowProficiencies.contains(a) ? " •" : ""
                    lines.append("| \(a.displayName) | \(c.scores[a]) | \(signed(c.scores.modifier(a))) | \(signed(save))\(prof) |")
                }
                out.append(lines.joined(separator: "\n"))
            case .vitals:
                var lines = [
                    "## Vitals",
                    "HP **\(c.currentHP)/\(c.maxHP)**\(c.tempHP > 0 ? " (+\(c.tempHP) temp)" : "") · AC **\(c.computedAC)** · Initiative **\(signed(c.initiative))** · Speed **\(c.speed) ft** · Passives **Perc \(c.passivePerception) / Inv \(c.passiveInvestigation) / Ins \(c.passiveInsight)**",
                    "Hit Dice **\(c.hitDiceRemaining)/\(c.hitDiceTotal) d\(c.hitDiceType)** · Death saves **\(c.deathSaveSuccesses)✓ / \(c.deathSaveFailures)✗**",
                ]
                if c.exhaustion > 0 { lines.append("Exhaustion: **\(c.exhaustion)**") }
                if !c.conditions.isEmpty {
                    lines.append("Conditions: " + c.conditions.map { $0.displayName }.sorted().joined(separator: ", "))
                }
                out.append(lines.joined(separator: "\n"))
            case .skills:
                var lines = ["## Skills"]
                for s in c.skills {
                    let mark = s.tier == .expert ? "◆" : (s.tier == .proficient ? "●" : "○")
                    lines.append("- \(mark) \(s.name) \(signed(s.bonus(scores: c.scores, level: c.level)))")
                }
                out.append(lines.joined(separator: "\n"))
            case .attacks:
                var lines = ["## Attacks", "| Attack | Bonus | Damage | Type | Range |", "|---|---|---|---|---|"]
                for a in c.attacks {
                    lines.append("| \(a.name)\(a.ammunition.map { " (ammo \($0))" } ?? "") | \(signed(a.attackBonus(scores: c.scores, level: c.level))) | \(a.damageString(scores: c.scores)) | \(a.damageType) | \(a.range) |")
                }
                if c.attacks.isEmpty { lines.append("| — | — | — | — | — |") }
                if let sc = c.spellcasting {
                    lines.append("")
                    lines.append("Spell attack **\(signed(sc.spellAttackBonus(scores: c.scores, level: c.level)))** · Spell save DC **\(sc.spellSaveDC(scores: c.scores, level: c.level))** (\(sc.ability.abbreviation))")
                }
                out.append(lines.joined(separator: "\n"))
            case .spells:
                guard let sc = c.spellcasting else { continue }
                var lines = ["## Spells (\(sc.progression.displayName))"]
                for sl in 1...9 {
                    let maxSlots = sc.slotsMax(spellLevel: sl, casterLevel: c.level)
                    if maxSlots > 0 {
                        lines.append("- Level \(sl) slots: **\(sc.slotsRemaining(spellLevel: sl, casterLevel: c.level))/\(maxSlots)**")
                    }
                }
                let cantrips = sc.cantrips
                if !cantrips.isEmpty {
                    lines.append("- Cantrips: " + cantrips.map { $0.name }.sorted().joined(separator: ", "))
                }
                for sl in 1...9 {
                    let atLevel = sc.spells(atLevel: sl)
                    if !atLevel.isEmpty {
                        lines.append("- Level \(sl): " + atLevel.map { $0.prepared ? $0.name : "\($0.name) (unprepared)" }.joined(separator: ", "))
                    }
                }
                out.append(lines.joined(separator: "\n"))
            case .inventory:
                var lines = ["## Inventory", "Currency: **\(c.currency.displayString)** · Carried: **\(fmtWeight(c.totalWeight)) / \(c.carryingCapacity) lb**"]
                for item in c.inventory {
                    var line = "- \(item.name)\(item.quantity > 1 ? " ×\(item.quantity)" : "")"
                    if item.equipped { line += " (equipped)" }
                    if item.attuned { line += " (attuned)" }
                    if !item.notes.isEmpty { line += " — \(item.notes)" }
                    lines.append(line)
                }
                if c.inventory.isEmpty { lines.append("_Empty pack_") }
                out.append(lines.joined(separator: "\n"))
            case .features:
                var lines = ["## Features & Traits"]
                for f in c.features {
                    var line = "- **\(f.name)**\(f.source.isEmpty ? "" : " (\(f.source))")"
                    if let remaining = f.usesRemaining { line += " — \(remaining)/\(f.usesMax) uses, recharges: \(f.recharge.displayName)" }
                    if !f.detail.isEmpty { line += ": \(f.detail)" }
                    lines.append(line)
                }
                if c.features.isEmpty { lines.append("_None recorded_") }
                out.append(lines.joined(separator: "\n"))
            case .personality:
                guard !c.personality.isEmpty else { continue }
                let p = c.personality
                var lines = ["## Personality"]
                if !p.traits.isEmpty { lines.append("- **Traits:** \(p.traits)") }
                if !p.ideals.isEmpty { lines.append("- **Ideals:** \(p.ideals)") }
                if !p.bonds.isEmpty { lines.append("- **Bonds:** \(p.bonds)") }
                if !p.flaws.isEmpty { lines.append("- **Flaws:** \(p.flaws)") }
                let appearanceBits = [p.age, p.height, p.weight, p.eyes, p.hair].filter { !$0.isEmpty }
                if !appearanceBits.isEmpty { lines.append("- **Appearance:** \(appearanceBits.joined(separator: ", "))") }
                if !p.appearance.isEmpty { lines.append("\n\(p.appearance)") }
                if !p.backstory.isEmpty { lines.append("\n### Backstory\n\(p.backstory)") }
                if !p.allies.isEmpty { lines.append("\n### Allies & Organizations\n\(p.allies)") }
                if !p.treasure.isEmpty { lines.append("\n### Treasure\n\(p.treasure)") }
                out.append(lines.joined(separator: "\n"))
            case .diceRoller:
                out.append("## Dice\n_In-app roller; see the Dice tab._")
            case .notes:
                if !c.notes.isEmpty { out.append("## Notes\n\(c.notes)") }
            case .journal:
                if !c.journal.isEmpty {
                    var lines = ["## Journal"]
                    for e in c.journal {
                        let head = [e.date, e.title].filter { !$0.isEmpty }.joined(separator: " - ")
                        lines.append("### \(head.isEmpty ? "Entry" : head)")
                        if !e.text.isEmpty { lines.append(e.text) }
                    }
                    out.append(lines.joined(separator: "\n"))
                }
            }
        }
        appendCustomSections(&out, c)
        return out.joined(separator: "\n\n") + "\n"
    }

    private static func appendCustomSections(_ out: inout [String], _ c: Character) {
        let ruleset = c.rulesetName ?? "Custom"
        if !c.customAbilities.isEmpty {
            var lines = ["## \(ruleset) Abilities", "| Ability | Score | Mod |", "|---|---|---|---|"]
            for a in c.customAbilities {
                lines.append("| \(a.name) | \(a.score) | \(signed(a.modifier)) |")
            }
            out.append(lines.joined(separator: "\n"))
        }
        if !c.customSkills.isEmpty {
            var lines = ["## \(ruleset) Skills"]
            for s in c.customSkills where s.tier != .none {
                lines.append("- \(s.name) \(signed(s.bonus(abilities: c.customAbilities, level: c.level)))\(s.tier == .expert ? " (expert)" : "")")
            }
            if lines.count == 1 { lines.append("_No trained skills_") }
            out.append(lines.joined(separator: "\n"))
        }
        for block in c.layout.customBlocks {
            out.append("## \(TemplateRenderer.render(block.title, for: c))\n\(TemplateRenderer.render(block.body, for: c))")
        }
    }

    public static func exportHTML(_ c: Character) -> String {
        var body: [String] = []
        for block in c.layout.visibleBlocks {
            switch block.kind {
            case .identity:
                let portraitTag = c.portrait.map {
                    "<img class=\"portrait\" alt=\"\" src=\"data:image/png;base64,\($0.base64EncodedString())\">"
                } ?? ""
                body.append("""
                <section class="block identity">
                  \(portraitTag)
                  <h1>\(esc(c.name))</h1>
                  <p class="sub">Level \(c.level) \(esc(c.lineage)) \(esc(c.calling))\(c.alignment.isEmpty ? "" : " (\(esc(c.alignment)))")</p>
                  <p class="meta">XP \(c.experience) · Proficiency +\(c.proficiencyBonus)\(c.background.isEmpty ? "" : " · " + esc(c.background))\(c.inspiration ? " · Inspired" : "")</p>
                  \(c.proficienciesText.isEmpty ? "" : "<p class=\"meta\">" + esc(c.proficienciesText) + "</p>")
                </section>
                """)
            case .abilities:
                var rows = ""
                for a in Ability.allCases {
                    let save = c.savingThrow(a)
                    let dot = c.savingThrowProficiencies.contains(a) ? " ●" : ""
                    rows += "<tr><td>\(a.displayName)</td><td>\(c.scores[a])</td><td>\(signed(c.scores.modifier(a)))</td><td>\(signed(save))\(dot)</td></tr>"
                }
                body.append("""
                <section class="block"><h2>Abilities</h2>
                <table><thead><tr><th>Ability</th><th>Score</th><th>Mod</th><th>Save</th></tr></thead><tbody>\(rows)</tbody></table>
                </section>
                """)
            case .vitals:
                var extra = ""
                if c.exhaustion > 0 { extra += "<span class=\"chip\">Exhaustion <b>\(c.exhaustion)</b></span>" }
                body.append("""
                <section class="block vitals"><h2>Vitals</h2><div class="chips">
                  <span class="chip">HP <b>\(c.currentHP)/\(c.maxHP)</b>\(c.tempHP > 0 ? " +\(c.tempHP)t" : "")</span>
                  <span class="chip">AC <b>\(c.computedAC)</b></span>
                  <span class="chip">Init <b>\(signed(c.initiative))</b></span>
                  <span class="chip">Speed <b>\(c.speed) ft</b></span>
                  <span class="chip">Passive Perc <b>\(c.passivePerception)</b></span><span class="chip">Passive Inv <b>\(c.passiveInvestigation)</b></span><span class="chip">Passive Ins <b>\(c.passiveInsight)</b></span>
                  <span class="chip">Hit Dice <b>\(c.hitDiceRemaining)/\(c.hitDiceTotal) d\(c.hitDiceType)</b></span>
                  \(extra)
                </div>\(c.conditions.isEmpty ? "" : "<p class=\"meta\">Conditions: " + esc(c.conditions.map { $0.displayName }.sorted().joined(separator: ", ")) + "</p>")</section>
                """)
            case .skills:
                var items = ""
                for s in c.skills {
                    let mark = s.tier == .expert ? "◆" : (s.tier == .proficient ? "●" : "○")
                    items += "<li>\(mark) \(esc(s.name)) <b>\(signed(s.bonus(scores: c.scores, level: c.level)))</b></li>"
                }
                body.append("<section class=\"block\"><h2>Skills</h2><ul>\(items)</ul></section>")
            case .attacks:
                var rows = ""
                for a in c.attacks {
                    rows += "<tr><td>\(esc(a.name + (a.ammunition.map { " (ammo \($0))" } ?? "")))</td><td>\(signed(a.attackBonus(scores: c.scores, level: c.level)))</td><td>\(esc(a.damageString(scores: c.scores)))</td><td>\(esc(a.damageType))</td><td>\(esc(a.range))</td></tr>"
                }
                if rows.isEmpty { rows = "<tr><td colspan=\"5\" class=\"dim\">No attacks</td></tr>" }
                var spellLine = ""
                if let sc = c.spellcasting {
                    spellLine = "<p class=\"meta\">Spell attack <b>\(signed(sc.spellAttackBonus(scores: c.scores, level: c.level)))</b> · Spell save DC <b>\(sc.spellSaveDC(scores: c.scores, level: c.level))</b> (\(sc.ability.abbreviation))</p>"
                }
                body.append("""
                <section class="block"><h2>Attacks</h2>
                <table><thead><tr><th>Attack</th><th>Bonus</th><th>Damage</th><th>Type</th><th>Range</th></tr></thead><tbody>\(rows)</tbody></table>
                \(spellLine)</section>
                """)
            case .spells:
                guard let sc = c.spellcasting else { continue }
                var slots = ""
                for sl in 1...9 {
                    let maxSlots = sc.slotsMax(spellLevel: sl, casterLevel: c.level)
                    if maxSlots > 0 {
                        slots += "<span class=\"chip\">Lvl \(sl) <b>\(sc.slotsRemaining(spellLevel: sl, casterLevel: c.level))/\(maxSlots)</b></span>"
                    }
                }
                var lists = ""
                let cantrips = sc.cantrips.map { esc($0.name) }.sorted().joined(separator: ", ")
                if !cantrips.isEmpty { lists += "<li><b>Cantrips:</b> \(cantrips)</li>" }
                for sl in 1...9 {
                    let atLevel = sc.spells(atLevel: sl).map { $0.prepared ? esc($0.name) : "<em>\(esc($0.name))</em>" }.joined(separator: ", ")
                    if !atLevel.isEmpty { lists += "<li><b>Level \(sl):</b> \(atLevel)</li>" }
                }
                body.append("<section class=\"block\"><h2>Spells (\(sc.progression.displayName))</h2><div class=\"chips\">\(slots)</div><ul>\(lists)</ul></section>")
            case .inventory:
                var items = ""
                for item in c.inventory {
                    items += "<li>\(esc(item.name))\(item.quantity > 1 ? " ×\(item.quantity)" : "")\(item.equipped ? " (equipped)" : "")\(item.notes.isEmpty ? "" : " — " + esc(item.notes))</li>"
                }
                if items.isEmpty { items = "<li class=\"dim\">Empty pack</li>" }
                body.append("""
                <section class="block"><h2>Inventory</h2>
                <p class="meta">Currency <b>\(esc(c.currency.displayString))</b> · Carried <b>\(fmtWeight(c.totalWeight)) / \(c.carryingCapacity) lb</b></p>
                <ul>\(items)</ul></section>
                """)
            case .features:
                var items = ""
                for f in c.features {
                    var line = "<li><b>\(esc(f.name))</b>\(f.source.isEmpty ? "" : " (" + esc(f.source) + ")")"
                    if let remaining = f.usesRemaining { line += " — \(remaining)/\(f.usesMax) uses" }
                    if !f.detail.isEmpty { line += ": \(esc(f.detail))" }
                    items += line + "</li>"
                }
                if items.isEmpty { items = "<li class=\"dim\">None recorded</li>" }
                body.append("<section class=\"block\"><h2>Features &amp; Traits</h2><ul>\(items)</ul></section>")
            case .personality:
                guard !c.personality.isEmpty else { continue }
                let p = c.personality
                var items = ""
                if !p.traits.isEmpty { items += "<li><b>Traits:</b> \(esc(p.traits))</li>" }
                if !p.ideals.isEmpty { items += "<li><b>Ideals:</b> \(esc(p.ideals))</li>" }
                if !p.bonds.isEmpty { items += "<li><b>Bonds:</b> \(esc(p.bonds))</li>" }
                if !p.flaws.isEmpty { items += "<li><b>Flaws:</b> \(esc(p.flaws))</li>" }
                var paras = ""
                if !p.backstory.isEmpty { paras += "<h3>Backstory</h3><p>\(esc(p.backstory).replacingOccurrences(of: "\n", with: "<br>"))</p>" }
                if !p.allies.isEmpty { paras += "<h3>Allies</h3><p>\(esc(p.allies).replacingOccurrences(of: "\n", with: "<br>"))</p>" }
                body.append("<section class=\"block\"><h2>Personality</h2><ul>\(items)</ul>\(paras)</section>")
            case .diceRoller:
                body.append("<section class=\"block\"><h2>Dice</h2><p class=\"dim\">In-app roller; see the Dice tab.</p></section>")
            case .notes:
                if !c.notes.isEmpty {
                    body.append("<section class=\"block\"><h2>Notes</h2><p>\(esc(c.notes).replacingOccurrences(of: "\n", with: "<br>"))</p></section>")
                }
            case .journal:
                if !c.journal.isEmpty {
                    var items = ""
                    for e in c.journal {
                        let head = [e.date, e.title].filter { !$0.isEmpty }.joined(separator: " - ")
                        items += "<h3>\(esc(head.isEmpty ? "Entry" : head))</h3>"
                        if !e.text.isEmpty {
                            items += "<p>\(esc(e.text).replacingOccurrences(of: "\n", with: "<br>"))</p>"
                        }
                    }
                    body.append("<section class=\"block\"><h2>Journal</h2>\(items)</section>")
                }
            }
        }
        appendCustomHTML(&body, c)
        return """
        <!DOCTYPE html>
        <html lang="en"><head><meta charset="utf-8">
        <title>\(esc(c.name)) — ARCHITER</title>
        <style>
          :root { color-scheme: light dark; }
          body { font-family: -apple-system, "Helvetica Neue", sans-serif; max-width: 760px;
                 margin: 2rem auto; padding: 0 1rem; line-height: 1.45; }
          h1 { margin-bottom: 0.1rem; }
          h2 { font-size: 1rem; text-transform: uppercase; letter-spacing: 0.06em;
               border-bottom: 2px solid #8a5a2b; padding-bottom: 0.2rem; }
          h3 { font-size: 0.9rem; margin-bottom: 0.2rem; }
          .sub { font-size: 1.1rem; margin: 0.1rem 0; } .meta { opacity: 0.7; margin-top: 0; }
          .block { margin-bottom: 1.4rem; }
          table { border-collapse: collapse; width: 100%; }
          th, td { border: 1px solid #9995; padding: 0.3rem 0.6rem; text-align: left; }
          .chips { display: flex; flex-wrap: wrap; gap: 0.5rem; }
          .chip { border: 1px solid #9995; border-radius: 999px; padding: 0.25rem 0.8rem; }
          .dim { opacity: 0.55; }
          img.portrait { max-width: 128px; max-height: 128px; border-radius: 8px;
                         float: right; margin: 0 0 0.5rem 1rem; }
          ul { padding-left: 1.2rem; }
        </style></head>
        <body>
        \(body.joined(separator: "\n"))
        <footer class="dim">Made with ARCHITER</footer>
        </body></html>
        """
    }

    private static func appendCustomHTML(_ body: inout [String], _ c: Character) {
        let ruleset = esc(c.rulesetName ?? "Custom")
        if !c.customAbilities.isEmpty {
            var rows = ""
            for a in c.customAbilities {
                rows += "<tr><td>\(esc(a.name))</td><td>\(a.score)</td><td>\(signed(a.modifier))</td></tr>"
            }
            body.append("""
            <section class="block"><h2>\(ruleset) Abilities</h2>
            <table><thead><tr><th>Ability</th><th>Score</th><th>Mod</th></tr></thead><tbody>\(rows)</tbody></table>
            </section>
            """)
        }
        if !c.customSkills.isEmpty {
            var items = ""
            for s in c.customSkills where s.tier != .none {
                items += "<li>\(esc(s.name)) <b>\(signed(s.bonus(abilities: c.customAbilities, level: c.level)))</b>\(s.tier == .expert ? " <em>(expert)</em>" : "")</li>"
            }
            if items.isEmpty { items = "<li class=\"dim\">No trained skills</li>" }
            body.append("<section class=\"block\"><h2>\(ruleset) Skills</h2><ul>\(items)</ul></section>")
        }
        for block in c.layout.customBlocks {
            body.append("""
            <section class="block"><h2>\(esc(TemplateRenderer.render(block.title, for: c)))</h2>
            <p>\(esc(TemplateRenderer.render(block.body, for: c)).replacingOccurrences(of: "\n", with: "<br>"))</p>
            </section>
            """)
        }
    }

    static func signed(_ n: Int) -> String { n >= 0 ? "+\(n)" : "\(n)" }

    static func fmtWeight(_ w: Double) -> String {
        w.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(w))" : String(format: "%.1f", w)
    }

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
