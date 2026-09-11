import Foundation

/// Renders a character sheet as Markdown or self-contained styled HTML,
/// honoring the layout's block visibility and order.
public enum SheetExporter {

    public static func exportMarkdown(_ c: Character) -> String {
        var out: [String] = []
        for block in c.layout.visibleBlocks {
            switch block.kind {
            case .identity:
                out.append("""
                # \(c.name)
                **Level \(c.level)** \(c.lineage) \(c.calling)\(c.background.isEmpty ? "" : " — \(c.background)")
                XP: \(c.experience) · Proficiency bonus: +\(c.proficiencyBonus)
                """)
            case .abilities:
                var lines = ["## Abilities", "| Ability | Score | Mod | Save |", "|---|---|---|---|"]
                for a in Ability.allCases {
                    let save = c.savingThrow(a)
                    let prof = c.savingThrowProficiencies.contains(a) ? " •" : ""
                    lines.append("| \(a.rawValue.capitalized) | \(c.scores[a]) | \(signed(c.scores.modifier(a))) | \(signed(save))\(prof) |")
                }
                out.append(lines.joined(separator: "\n"))
            case .vitals:
                out.append("""
                ## Vitals
                HP **\(c.currentHP)/\(c.maxHP)** · AC **\(c.armorClass)** · Initiative **\(signed(c.initiative))** · Speed **\(c.speed) ft** · Passive Perception **\(c.passivePerception)**
                """)
            case .skills:
                var lines = ["## Skills"]
                for s in c.skills where s.tier != .none {
                    lines.append("- \(s.name) \(signed(s.bonus(scores: c.scores, level: c.level)))\(s.tier == .expert ? " (expert)" : "")")
                }
                if lines.count == 1 { lines.append("_No trained skills_") }
                out.append(lines.joined(separator: "\n"))
            case .attacks:
                var lines = ["## Attacks", "| Attack | Bonus | Damage | Notes |", "|---|---|---|---|"]
                for a in c.attacks {
                    lines.append("| \(a.name) | \(signed(a.attackBonus)) | \(a.damageExpression) | \(a.notes) |")
                }
                if c.attacks.isEmpty { lines.append("| — | — | — | — |") }
                out.append(lines.joined(separator: "\n"))
            case .inventory:
                var lines = ["## Inventory"]
                for item in c.inventory {
                    lines.append("- \(item.name)\(item.quantity > 1 ? " ×\(item.quantity)" : "")\(item.notes.isEmpty ? "" : " — \(item.notes)")")
                }
                if c.inventory.isEmpty { lines.append("_Empty pack_") }
                out.append(lines.joined(separator: "\n"))
            case .diceRoller:
                out.append("## Dice\n_In-app roller; see the Dice tab._")
            case .notes:
                if !c.notes.isEmpty { out.append("## Notes\n\(c.notes)") }
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
                body.append("""
                <section class="block identity">
                  <h1>\(esc(c.name))</h1>
                  <p class="sub">Level \(c.level) \(esc(c.lineage)) \(esc(c.calling))</p>
                  <p class="meta">XP \(c.experience) · Proficiency +\(c.proficiencyBonus)\(c.background.isEmpty ? "" : " · " + esc(c.background))</p>
                </section>
                """)
            case .abilities:
                var rows = ""
                for a in Ability.allCases {
                    let save = c.savingThrow(a)
                    let dot = c.savingThrowProficiencies.contains(a) ? " ●" : ""
                    rows += "<tr><td>\(a.rawValue.capitalized)</td><td>\(c.scores[a])</td><td>\(signed(c.scores.modifier(a)))</td><td>\(signed(save))\(dot)</td></tr>"
                }
                body.append("""
                <section class="block"><h2>Abilities</h2>
                <table><thead><tr><th>Ability</th><th>Score</th><th>Mod</th><th>Save</th></tr></thead><tbody>\(rows)</tbody></table>
                </section>
                """)
            case .vitals:
                body.append("""
                <section class="block vitals"><h2>Vitals</h2><div class="chips">
                  <span class="chip">HP <b>\(c.currentHP)/\(c.maxHP)</b></span>
                  <span class="chip">AC <b>\(c.armorClass)</b></span>
                  <span class="chip">Init <b>\(signed(c.initiative))</b></span>
                  <span class="chip">Speed <b>\(c.speed) ft</b></span>
                  <span class="chip">Passive Perc <b>\(c.passivePerception)</b></span>
                </div></section>
                """)
            case .skills:
                var items = ""
                for s in c.skills where s.tier != .none {
                    items += "<li>\(esc(s.name)) <b>\(signed(s.bonus(scores: c.scores, level: c.level)))</b>\(s.tier == .expert ? " <em>(expert)</em>" : "")</li>"
                }
                if items.isEmpty { items = "<li class=\"dim\">No trained skills</li>" }
                body.append("<section class=\"block\"><h2>Skills</h2><ul>\(items)</ul></section>")
            case .attacks:
                var rows = ""
                for a in c.attacks {
                    rows += "<tr><td>\(esc(a.name))</td><td>\(signed(a.attackBonus))</td><td>\(esc(a.damageExpression))</td><td>\(esc(a.notes))</td></tr>"
                }
                if rows.isEmpty { rows = "<tr><td colspan=\"4\" class=\"dim\">No attacks</td></tr>" }
                body.append("""
                <section class="block"><h2>Attacks</h2>
                <table><thead><tr><th>Attack</th><th>Bonus</th><th>Damage</th><th>Notes</th></tr></thead><tbody>\(rows)</tbody></table>
                </section>
                """)
            case .inventory:
                var items = ""
                for item in c.inventory {
                    items += "<li>\(esc(item.name))\(item.quantity > 1 ? " ×\(item.quantity)" : "")\(item.notes.isEmpty ? "" : " — " + esc(item.notes))</li>"
                }
                if items.isEmpty { items = "<li class=\"dim\">Empty pack</li>" }
                body.append("<section class=\"block\"><h2>Inventory</h2><ul>\(items)</ul></section>")
            case .diceRoller:
                body.append("<section class=\"block\"><h2>Dice</h2><p class=\"dim\">In-app roller; see the Dice tab.</p></section>")
            case .notes:
                if !c.notes.isEmpty {
                    body.append("<section class=\"block\"><h2>Notes</h2><p>\(esc(c.notes).replacingOccurrences(of: "\n", with: "<br>"))</p></section>")
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
          .sub { font-size: 1.1rem; margin: 0.1rem 0; } .meta { opacity: 0.7; margin-top: 0; }
          .block { margin-bottom: 1.4rem; }
          table { border-collapse: collapse; width: 100%; }
          th, td { border: 1px solid #9995; padding: 0.3rem 0.6rem; text-align: left; }
          .chips { display: flex; flex-wrap: wrap; gap: 0.5rem; }
          .chip { border: 1px solid #9995; border-radius: 999px; padding: 0.25rem 0.8rem; }
          .dim { opacity: 0.55; }
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

    private static func signed(_ n: Int) -> String { n >= 0 ? "+\(n)" : "\(n)" }

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
