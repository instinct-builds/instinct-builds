#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers
import ArchiterCore

@MainActor
public final class AppModel: ObservableObject {
    @Published public var characters: [Character] = []
    /// Session restore: the last-selected character id persists across launches.
    @Published public var selectedID: UUID? {
        didSet {
            if let id = selectedID {
                UserDefaults.standard.set(id.uuidString, forKey: AppModel.lastSelectedKey)
            } else {
                UserDefaults.standard.removeObject(forKey: AppModel.lastSelectedKey)
            }
        }
    }
    private static let lastSelectedKey = "architer.lastSelectedCharacterID"
    /// Free-roller damage-type selection (Dice tab), persisted across
    /// launches like the session restore above. nil means untyped rolls.
    @Published public var freeRollerDamageType: DamageType? =
        UserDefaults.standard.string(forKey: AppModel.freeRollerTypeKey)
            .flatMap(DamageType.init(rawValue:)) {
        didSet {
            if let type = freeRollerDamageType {
                UserDefaults.standard.set(type.rawValue, forKey: AppModel.freeRollerTypeKey)
            } else {
                UserDefaults.standard.removeObject(forKey: AppModel.freeRollerTypeKey)
            }
        }
    }
    private static let freeRollerTypeKey = "architer.freeRollerDamageType"
    @Published public var rollHistory: [RollResult] = []
    @Published public var showWizard = false
    @Published public var showCompendium = false
    @Published private var undoStacks: [UUID: UndoStack<Character>] = [:]

    public let store = CharacterStore.defaultStore()
    /// Compendium favorites (app-wide, persisted next to the character files).
    @Published public var favorites = CompendiumFavorites()
    public var favoritesStore: FavoritesStore { FavoritesStore(directory: store.directory) }
    public var rollHistoryStore: RollHistoryStore { RollHistoryStore(directory: store.directory) }
    /// Saved dice shortcuts (app-wide, persisted next to the character files).
    @Published public var macros: [DiceMacro] = []
    public var macroStore: MacroStore { MacroStore(directory: store.directory) }
    public var rulesetStore: RulesetStore { RulesetStore(directory: store.directory) }
    /// User-defined ruleset library (persisted).
    @Published public var rulesets: [Ruleset] = []
    public let roller = DiceRoller()

    public init() { reload() }

    public var selected: Binding<Character>? {
        guard let id = selectedID, let idx = characters.firstIndex(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { self.characters[idx] },
            set: { newValue in
                guard newValue != self.characters[idx] else { return }
                var stack = self.undoStacks[id] ?? UndoStack(self.characters[idx])
                stack.push(newValue)
                self.undoStacks[id] = stack
                self.characters[idx] = newValue
                try? self.store.save(newValue)
            }
        )
    }

    public func reload() {
        characters = (try? store.loadAll()) ?? []
        rulesets = rulesetStore.load()
        favorites = favoritesStore.load()
        rollHistory = rollHistoryStore.load()
        macros = macroStore.load()
        if selectedID == nil || !characters.contains(where: { $0.id == selectedID }) {
            if let saved = UserDefaults.standard.string(forKey: AppModel.lastSelectedKey),
               let uuid = UUID(uuidString: saved),
               characters.contains(where: { $0.id == uuid }) {
                selectedID = uuid
            } else {
                selectedID = characters.first?.id
            }
        }
    }

    // MARK: Characters

    public func newCharacter() {
        let c = Character(name: "Unnamed Adventurer")
        characters.append(c)
        try? store.save(c)
        selectedID = c.id
    }

    public func addCharacter(_ c: Character) {
        characters.append(c)
        characters.sort { $0.name < $1.name }
        try? store.save(c)
        selectedID = c.id
    }

    public func duplicateSelected() {
        guard let sel = selected?.wrappedValue else { return }
        var copy = sel
        copy.id = UUID()
        copy.name = sel.name + " (copy)"
        addCharacter(copy)
    }

    public func deleteSelected() {
        guard let id = selectedID, let idx = characters.firstIndex(where: { $0.id == id }) else { return }
        try? store.delete(characters[idx])
        characters.remove(at: idx)
        undoStacks.removeValue(forKey: id)
        selectedID = characters.first?.id
    }

    /// Adds or replaces a macro by scoped id; invalid names/expressions are
    /// ignored. Passing a character name binds the macro to that character,
    /// so a table macro and a character macro can share a name.
    public func saveMacro(name: String, expression: String, forCharacter characterName: String? = nil) {
        let macro = DiceMacro(
            name: name.trimmingCharacters(in: .whitespaces),
            expression: expression.trimmingCharacters(in: .whitespaces),
            characterName: characterName)
        guard macro.isValid else { return }
        macros.removeAll { $0.id == macro.id }
        macros.append(macro)
        macros.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        macroStore.save(macros)
    }

    /// Replaces a macro in place (edit-in-place): validates the drafts,
    /// removes the old scoped id, then upserts under the new one. The owner
    /// binding (table-wide vs character) is preserved.
    public func updateMacro(_ macro: DiceMacro, name: String, expression: String) {
        let updated = DiceMacro(
            name: name.trimmingCharacters(in: .whitespaces),
            expression: expression.trimmingCharacters(in: .whitespaces),
            characterName: macro.characterName)
        guard updated.isValid else { return }
        macros.removeAll { $0.id == macro.id }
        saveMacro(name: updated.name, expression: updated.expression, forCharacter: updated.characterName)
    }

    /// Clones a macro in place as "<name> copy" (bumped when taken); the
    /// owner binding rides along, so the copy lands in the same group.
    public func duplicateMacro(_ macro: DiceMacro) {
        let copy = ArchiterCore.duplicatedMacro(macro, existing: macros)
        saveMacro(name: copy.name, expression: copy.expression, forCharacter: copy.characterName)
    }

    public func deleteMacro(_ macro: DiceMacro) {
        macros.removeAll { $0.id == macro.id }
        macroStore.save(macros)
    }

    /// Table-wide macros plus any bound to the selected character.
    public var visibleMacros: [DiceMacro] {
        ArchiterCore.visibleMacros(macros, for: selected?.wrappedValue.name)
    }

    public func toggleFavorite(kind: CompendiumKind, name: String) {
        favorites.toggle(kind: kind, name: name)
        favoritesStore.save(favorites)
    }

    public func loadSample() {
        addCharacter(SampleContent.demoCharacter())
    }

    // MARK: Rolling

    /// Copies the given rolls (already scoped/filtered by the view) to the
    /// pasteboard as one line per roll, oldest first.
    public func copyRollsToPasteboard(_ rolls: [RollResult]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(rolls.historyText, forType: .string)
    }

    public func clearRollHistory() {
        rollHistory.removeAll()
        rollHistoryStore.save(rollHistory)
    }

    private func record(_ r: RollResult) {
        var r = r
        r.characterName = selected?.wrappedValue.name
        rollHistory.insert(r, at: 0)
        if rollHistory.count > 200 { rollHistory.removeLast(rollHistory.count - 200) }
        rollHistoryStore.save(rollHistory)
    }

    public func roll(_ expression: String) {
        if let r = try? roller.roll(expression) { record(r) }
    }

    /// Incoming damage on the dice path: roll the expression, fold the
    /// selected character's defenses into the total (halved, zeroed, or
    /// doubled), label history with the adjustment, and apply the result -
    /// temp HP still absorbs first. Type nil skips defenses entirely.
    public func rollIncomingDamage(_ expression: String, type: DamageType?) {
        guard var c = selected?.wrappedValue,
              let rolled = try? roller.roll(expression) else { return }
        let adjusted = c.adjustedDamage(rolled.total, type: type)
        var r = rolled
        let typeName = type?.displayName.lowercased() ?? "untyped"
        if let note = c.defenseAdjustmentNote(amount: rolled.total, type: type) {
            r.label = "\(typeName) damage taken (\(note))"
        } else {
            r.label = "\(typeName) damage taken"
        }
        record(r)
        // Defenses already folded in above; type nil keeps temp-HP absorption.
        c.applyDamage(adjusted, type: nil)
        selected?.wrappedValue = c
    }

    /// Free-roller roll with an optional damage type: when a type is picked
    /// the history entry carries the same outgoing-defense note attack rolls
    /// get (what the total deals against resist / immune / vuln). Untyped
    /// rolls record exactly as before.
    public func rollFree(_ expression: String, type: DamageType?) {
        guard let type else { roll(expression); return }
        recordDamageRoll(expression, expression, type: type)
    }

    public func rollLabeled(_ label: String, _ expression: String) {
        if let r = try? roller.rollLabeled(label, expression) { record(r) }
    }

    /// Damage roll labeled with the outgoing-defense math for its type -
    /// what the total deals against resistance, immunity, and vulnerability
    /// on the target. Untyped or unrecognized types roll without a note.
    private func recordDamageRoll(_ label: String, _ expression: String, type: DamageType?) {
        guard var r = try? roller.rollLabeled(label, expression) else { return }
        if let type {
            r.label = "\(label) (\(Character.outgoingDefenseNote(total: r.total, type: type)))"
        }
        record(r)
    }

    /// Quick-add a history roll to the selected character's journal.
    public func addRollToJournal(_ roll: RollResult) {
        guard var c = selected?.wrappedValue else { return }
        let title = roll.label ?? roll.expression
        c.journal.append(JournalEntry(date: "", title: title, text: "Rolled \(roll.total) (\(roll.expression))"))
        selected?.wrappedValue = c
    }

    /// Level-up assistant: roll the hit die or take the average, then apply.
    public func levelUp(rollHP: Bool) {
        guard var c = selected?.wrappedValue, c.level < 20 else { return }
        let gain: Int
        if rollHP {
            guard let r = try? roller.rollLabeled("Level up HP (level \(c.level + 1))", c.levelUpRollExpression) else { return }
            record(r)
            gain = max(1, r.total)
        } else {
            gain = c.averageLevelUpHP
        }
        c.levelUp(hpGain: gain)
        selected?.wrappedValue = c
    }

    /// Era- and condition-aware d20 roll: the 2024-style preset subtracts
    /// exhaustion from every d20 test, and hindering conditions (poisoned,
    /// blinded, prone...) fold disadvantage into the mode.
    public func rollCheck(_ label: String, bonus: Int, mode: RollMode = .normal) {
        guard let c = selected?.wrappedValue else {
            record(roller.check(label, bonus: bonus, mode: mode))
            return
        }
        let kind: Character.D20RollKind = label.localizedCaseInsensitiveContains("attack") ? .attack : .check
        let effective = c.effectiveRollMode(mode, for: kind)
        let penalty = c.exhaustionRollPenalty
        var tags: [String] = []
        if penalty > 0 { tags.append("exhaustion -\(penalty)") }
        if effective != mode, effective == .disadvantage {
            let names = c.disadvantageSourceNames(for: kind).joined(separator: ", ")
            tags.append("disadvantage: \(names)")
        } else if mode == .advantage, effective == .normal {
            tags.append("advantage canceled by condition")
        }
        let tagged = tags.isEmpty ? label : "\(label) (\(tags.joined(separator: "; ")))"
        record(roller.check(tagged, bonus: bonus - penalty, mode: effective))
    }

    /// Attack roll + damage roll as two history entries.
    public func rollAttack(_ attack: Attack, for c: Character, mode: RollMode = .normal) {
        let effective = c.effectiveRollMode(mode, for: .attack)
        var tags: [String] = []
        if c.exhaustionRollPenalty > 0 { tags.append("exhaustion -\(c.exhaustionRollPenalty)") }
        if effective != mode, effective == .disadvantage {
            tags.append("disadvantage: \(c.disadvantageSourceNames(for: .attack).joined(separator: ", "))")
        } else if mode == .advantage, effective == .normal {
            tags.append("advantage canceled by condition")
        }
        let label = tags.isEmpty ? "\(attack.name) attack" : "\(attack.name) attack (\(tags.joined(separator: "; ")))"
        let attackRoll = roller.check(label, bonus: attack.attackBonus(scores: c.scores, level: c.level) - c.exhaustionRollPenalty, mode: effective)
        record(attackRoll)
        let crit = attackRoll.dice.contains { $0.sides == 20 && $0.kept && $0.value == 20 }
        let damageExpr = attack.damageString(scores: c.scores)
        let grip = attack.twoHanded && attack.versatileExpression != nil ? " (two-handed)" : ""
        let damageType = DamageType(rawValue: attack.damageType.trimmingCharacters(in: .whitespaces).lowercased())
        if crit, let parsed = try? DiceExpression.parse(damageExpr) {
            recordDamageRoll("\(attack.name) damage (CRIT\(grip))", parsed.doubledDice(), type: damageType)
        } else {
            recordDamageRoll("\(attack.name) damage\(grip)", damageExpr, type: damageType)
        }
        if attack.ammunition != nil, var sel = selected?.wrappedValue {
            _ = sel.spendAmmunition(attackID: attack.id)
            selected?.wrappedValue = sel
        }
    }

    public func rollDeathSave() {
        guard var c = selected?.wrappedValue else { return }
        let r = roller.check("Death save", bonus: -c.exhaustionRollPenalty)
        record(r)
        let natural = r.dice.first?.value ?? 0
        if natural == 20 {
            c.applyHealing(1)
        } else if natural == 1 {
            c.deathSaveFailures = min(3, c.deathSaveFailures + 2)
        } else if r.total >= 10 {
            c.deathSaveSuccesses = min(3, c.deathSaveSuccesses + 1)
        } else {
            c.deathSaveFailures = min(3, c.deathSaveFailures + 1)
        }
        if c.deathSaveSuccesses >= 3 { // stable: reset the track
            c.deathSaveSuccesses = 0
            c.deathSaveFailures = 0
        }
        selected?.wrappedValue = c
    }

    public func spendHitDie() {
        guard var c = selected?.wrappedValue, let expr = c.hitDieRollExpression() else { return }
        guard let r = try? roller.rollLabeled("Hit die healing", expr) else { return }
        record(r)
        c.spendHitDie(healingRolled: r.total)
        selected?.wrappedValue = c
    }

    public func shortRest() {
        guard var c = selected?.wrappedValue else { return }
        c.shortRest()
        selected?.wrappedValue = c
    }

    public func longRest() {
        guard var c = selected?.wrappedValue else { return }
        c.longRest()
        selected?.wrappedValue = c
    }

    /// Cast a specific spell: spends the slot and, for concentration spells,
    /// moves concentration to it (ending any previous one).
    public func castSpell(_ spell: Spell) {
        castSpell(atSlotLevel: spell.level)
        if spell.concentration {
            guard var c = selected?.wrappedValue else { return }
            c.beginConcentration(on: spell.name)
            selected?.wrappedValue = c
        }
    }

    public func dropConcentration() {
        guard var c = selected?.wrappedValue else { return }
        c.dropConcentration()
        selected?.wrappedValue = c
    }

    public func castSpell(atSlotLevel slotLevel: Int) {
        guard var c = selected?.wrappedValue, var sc = c.spellcasting else { return }
        sc.useSlot(spellLevel: slotLevel, casterLevel: c.level)
        c.spellcasting = sc
        selected?.wrappedValue = c
    }

    // MARK: Ruleset library

    /// Adds or replaces a ruleset in the library (matched by name).
    public func saveRuleset(_ ruleset: Ruleset) {
        rulesets.removeAll { $0.name == ruleset.name }
        rulesets.append(ruleset)
        rulesets.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        try? rulesetStore.saveAll(rulesets)
    }

    public func deleteRuleset(named name: String) {
        rulesets.removeAll { $0.name == name }
        try? rulesetStore.saveAll(rulesets)
    }

    /// Applies a library ruleset to the selected character.
    public func applyRuleset(_ ruleset: Ruleset) {
        guard var c = selected?.wrappedValue else { return }
        c.apply(ruleset: ruleset)
        selected?.wrappedValue = c
    }

    // MARK: Export

    public func exportMarkdown() {
        guard let sel = selected?.wrappedValue else { return }
        savePanel(text: SheetExporter.exportMarkdown(sel), name: "\(sel.name).md")
    }

    public func exportHTML() {
        guard let sel = selected?.wrappedValue else { return }
        savePanel(text: SheetExporter.exportHTML(sel), name: "\(sel.name).html")
    }

    public func exportPDF() {
        guard let sel = selected?.wrappedValue else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(sel.name).pdf"
        if panel.runModal() == .OK, let url = panel.url {
            try? SheetPDFExporter.export(sel).write(to: url)
        }
    }

    public func exportCompactPDF(landscape: Bool = false) {
        guard let sel = selected?.wrappedValue else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = landscape ? "\(sel.name)-compact-landscape.pdf" : "\(sel.name)-compact.pdf"
        if panel.runModal() == .OK, let url = panel.url {
            try? SheetPDFExporter.export(sel, style: .compact,
                                         orientation: landscape ? .landscape : .portrait).write(to: url)
        }
    }

    public func exportCharacterJSON() {
        guard let sel = selected?.wrappedValue,
              let data = try? CharacterIO.exportJSON(sel),
              let text = String(data: data, encoding: .utf8) else { return }
        savePanel(text: text, name: "\(sel.name).architer.json")
    }

    public func importCharacterJSON() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url),
              let c = try? CharacterIO.importJSON(data) else { return }
        addCharacter(c)
    }

    // MARK: Undo

    public var canUndo: Bool { selectedID.flatMap { undoStacks[$0] }?.canUndo ?? false }
    public var canRedo: Bool { selectedID.flatMap { undoStacks[$0] }?.canRedo ?? false }

    public func undo() {
        guard let id = selectedID, let idx = characters.firstIndex(where: { $0.id == id }),
              var stack = undoStacks[id], stack.canUndo else { return }
        _ = stack.undo()
        undoStacks[id] = stack
        characters[idx] = stack.current
        try? store.save(stack.current)
    }

    public func redo() {
        guard let id = selectedID, let idx = characters.firstIndex(where: { $0.id == id }),
              var stack = undoStacks[id], stack.canRedo else { return }
        _ = stack.redo()
        undoStacks[id] = stack
        characters[idx] = stack.current
        try? store.save(stack.current)
    }

    private func savePanel(text: String, name: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        if panel.runModal() == .OK, let url = panel.url {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
#endif
