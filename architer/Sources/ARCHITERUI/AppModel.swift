#if os(macOS)
import SwiftUI
import ArchiterCore

@MainActor
public final class AppModel: ObservableObject {
    @Published public var characters: [Character] = []
    @Published public var selectedID: UUID?
    @Published public var rollHistory: [RollResult] = []
    @Published public var showWizard = false
    @Published private var undoStacks: [UUID: UndoStack<Character>] = [:]

    public let store = CharacterStore.defaultStore()
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
        if selectedID == nil || !characters.contains(where: { $0.id == selectedID }) {
            selectedID = characters.first?.id
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

    public func loadSample() {
        addCharacter(SampleContent.demoCharacter())
    }

    // MARK: Rolling

    private func record(_ r: RollResult) {
        rollHistory.insert(r, at: 0)
        if rollHistory.count > 200 { rollHistory.removeLast(rollHistory.count - 200) }
    }

    public func roll(_ expression: String) {
        if let r = try? roller.roll(expression) { record(r) }
    }

    public func rollLabeled(_ label: String, _ expression: String) {
        if let r = try? roller.rollLabeled(label, expression) { record(r) }
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

    public func rollCheck(_ label: String, bonus: Int, mode: RollMode = .normal) {
        record(roller.check(label, bonus: bonus, mode: mode))
    }

    /// Attack roll + damage roll as two history entries.
    public func rollAttack(_ attack: Attack, for c: Character, mode: RollMode = .normal) {
        record(roller.check("\(attack.name) attack", bonus: attack.attackBonus(scores: c.scores, level: c.level), mode: mode))
        rollLabeled("\(attack.name) damage", attack.damageString(scores: c.scores))
    }

    public func rollDeathSave() {
        guard var c = selected?.wrappedValue else { return }
        let r = roller.check("Death save", bonus: 0)
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

    public func castSpell(atSlotLevel slotLevel: Int) {
        guard var c = selected?.wrappedValue, var sc = c.spellcasting else { return }
        sc.useSlot(spellLevel: slotLevel, casterLevel: c.level)
        c.spellcasting = sc
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
