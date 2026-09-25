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
    /// Free-roller damage-type selection (Dice tab), remembered per
    /// character; characters without a choice fall back to the table-wide
    /// selection kept when no character is selected. Persisted across
    /// launches like the session restore above. nil means untyped rolls.
    public var freeRollerDamageType: DamageType? {
        get {
            ArchiterCore.resolveFreeRollerType(
                map: freeRollerTypeMap, characterID: selectedID?.uuidString,
                tableDefault: tableFreeRollerDamageType)
        }
        set {
            if let id = selectedID {
                freeRollerTypeMap = ArchiterCore.storingFreeRollerType(
                    newValue, in: freeRollerTypeMap, characterID: id.uuidString)
                UserDefaults.standard.set(freeRollerTypeMap, forKey: AppModel.freeRollerTypesByCharacterKey)
            } else {
                tableFreeRollerDamageType = newValue
                if let type = newValue {
                    UserDefaults.standard.set(type.rawValue, forKey: AppModel.freeRollerTypeKey)
                } else {
                    UserDefaults.standard.removeObject(forKey: AppModel.freeRollerTypeKey)
                }
            }
        }
    }
    /// Table-wide fallback (the 2.30.0 key) used with no character selected
    /// and inherited by characters with no stored choice of their own.
    @Published private var tableFreeRollerDamageType: DamageType? =
        UserDefaults.standard.string(forKey: AppModel.freeRollerTypeKey)
            .flatMap(DamageType.init(rawValue:))
    @Published private var freeRollerTypeMap: [String: String] =
        (UserDefaults.standard.dictionary(forKey: AppModel.freeRollerTypesByCharacterKey) as? [String: String]) ?? [:]
    private static let freeRollerTypeKey = "architer.freeRollerDamageType"
    private static let freeRollerTypesByCharacterKey = "architer.freeRollerDamageTypesByCharacter"
    /// Compact-PDF option (2.34.0): drop zero-quantity inventory rows from
    /// compact exports. Persisted like the session restore above.
    @Published public var compactPDFHideEmptyRows: Bool =
        UserDefaults.standard.bool(forKey: AppModel.compactPDFHideEmptyRowsKey) {
        didSet {
            UserDefaults.standard.set(compactPDFHideEmptyRows, forKey: AppModel.compactPDFHideEmptyRowsKey)
        }
    }
    private static let compactPDFHideEmptyRowsKey = "architer.compactPDFHideEmptyRows"
    /// Digest body format (2.62.0): the session-divider naming row's
    /// picker; the last choice is remembered across digests and launches.
    @Published public var digestFormat: DigestFormat =
        DigestFormat(rawValue: UserDefaults.standard.string(forKey: AppModel.digestFormatKey) ?? "") ?? .condensed {
        didSet {
            UserDefaults.standard.set(digestFormat.rawValue, forKey: AppModel.digestFormatKey)
        }
    }
    private static let digestFormatKey = "architer.digestFormat"
    /// Journal timestamps in exports (2.66.0): on keeps the 2.47.0
    /// stamped heads; off gives clean archival sheets.
    @Published public var exportJournalTimestamps: Bool =
        UserDefaults.standard.object(forKey: AppModel.exportJournalTimestampsKey) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(exportJournalTimestamps, forKey: AppModel.exportJournalTimestampsKey)
        }
    }
    private static let exportJournalTimestampsKey = "architer.exportJournalTimestamps"
    /// Custom roll-session names (2.67.0), keyed by the session's stable
    /// key (its oldest roll's stamp); persisted like the maps above.
    @Published public var sessionNames: [String: String] =
        (UserDefaults.standard.dictionary(forKey: AppModel.sessionNamesKey) as? [String: String]) ?? [:] {
        didSet {
            UserDefaults.standard.set(sessionNames, forKey: AppModel.sessionNamesKey)
        }
    }
    private static let sessionNamesKey = "architer.sessionNames"
    /// Free-text session notes (2.71.0), keyed like the names above.
    @Published public var sessionNotes: [String: String] =
        (UserDefaults.standard.dictionary(forKey: AppModel.sessionNotesKey) as? [String: String]) ?? [:] {
        didSet {
            UserDefaults.standard.set(sessionNotes, forKey: AppModel.sessionNotesKey)
        }
    }
    private static let sessionNotesKey = "architer.sessionNotes"

    /// Sessions with the user's custom names and notes applied
    /// (2.67.0/2.71.0) - the history list, the digest button, and
    /// exports read these.
    public func namedSessions(_ rolls: [RollResult]) -> [RollSession] {
        sessionSegments(rolls).map {
            $0.renamed($0.key.flatMap { sessionNames[$0] })
              .noted($0.key.flatMap { sessionNotes[$0] })
        }
    }

    /// Note a roll session (2.71.0); blank clears the note.
    public func setSessionNote(_ key: String, to note: String) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            sessionNotes.removeValue(forKey: key)
        } else {
            sessionNotes[key] = trimmed
        }
    }

    /// Name a roll session (2.67.0); blank clears the custom name and
    /// the generated title returns.
    public func renameSession(_ key: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            sessionNames.removeValue(forKey: key)
        } else {
            sessionNames[key] = trimmed
        }
    }
    /// Compact-PDF option (2.39.0): append the exported character's roll
    /// history as a day-grouped session-log appendix. Off by default - the
    /// compact layout is for cheap printing, so extra pages are opt-in.
    @Published public var compactPDFSessionLog: Bool =
        UserDefaults.standard.bool(forKey: AppModel.compactPDFSessionLogKey) {
        didSet {
            UserDefaults.standard.set(compactPDFSessionLog, forKey: AppModel.compactPDFSessionLogKey)
        }
    }
    private static let compactPDFSessionLogKey = "architer.compactPDFSessionLog"
    /// Compact-PDF option (2.41.0): date range for the session-log
    /// appendix - all rolls, today only, or the last 7 days.
    @Published public var compactPDFSessionLogRange: SessionLogRange =
        SessionLogRange(rawValue: UserDefaults.standard.string(forKey: AppModel.compactPDFSessionLogRangeKey) ?? "") ?? .all {
        didSet {
            UserDefaults.standard.set(compactPDFSessionLogRange.rawValue, forKey: AppModel.compactPDFSessionLogRangeKey)
        }
    }
    private static let compactPDFSessionLogRangeKey = "architer.compactPDFSessionLogRange"
    /// Auto-log rolls to the journal (2.45.0): when on, every roll that
    /// lands in history also lands in the selected character's journal,
    /// making the journal a true session record. Off by default; the
    /// per-card pencil hides while it is on (the roll is already there).
    @Published public var autoLogRollsToJournal: Bool =
        UserDefaults.standard.bool(forKey: AppModel.autoLogRollsToJournalKey) {
        didSet {
            UserDefaults.standard.set(autoLogRollsToJournal, forKey: AppModel.autoLogRollsToJournalKey)
        }
    }
    private static let autoLogRollsToJournalKey = "architer.autoLogRollsToJournal"
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
    public func saveMacro(name: String, expression: String, forCharacter characterName: String? = nil,
                          damageType: String? = nil) {
        let macro = DiceMacro(
            name: name.trimmingCharacters(in: .whitespaces),
            expression: expression.trimmingCharacters(in: .whitespaces),
            characterName: characterName,
            damageType: damageType)
        guard macro.isValid else { return }
        macros.removeAll { $0.id == macro.id }
        macros.append(macro)
        macros.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        macroStore.save(macros)
    }

    /// Replaces a macro in place (edit-in-place): validates the drafts,
    /// removes the old scoped id, then upserts under the new one. The owner
    /// binding (table-wide vs character) is preserved.
    public func updateMacro(_ macro: DiceMacro, name: String, expression: String,
                            damageType: String? = nil) {
        let updated = DiceMacro(
            name: name.trimmingCharacters(in: .whitespaces),
            expression: expression.trimmingCharacters(in: .whitespaces),
            characterName: macro.characterName,
            damageType: damageType)
        guard updated.isValid else { return }
        macros.removeAll { $0.id == macro.id }
        saveMacro(name: updated.name, expression: updated.expression,
                  forCharacter: updated.characterName, damageType: updated.damageType)
    }

    /// Clones a macro in place as "<name> copy" (bumped when taken); the
    /// owner binding rides along, so the copy lands in the same group.
    public func duplicateMacro(_ macro: DiceMacro) {
        let copy = ArchiterCore.duplicatedMacro(macro, existing: macros)
        saveMacro(name: copy.name, expression: copy.expression,
                  forCharacter: copy.characterName, damageType: copy.damageType)
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

    /// Copy one roll session (2.70.0): title, stats line, rolls oldest
    /// first - a paste-ready record without filing a digest.
    public func copySessionToPasteboard(_ session: RollSession) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(sessionShareText(session), forType: .string)
    }

    /// Copy one day of history (2.77.0): the named, summarized day
    /// header, then the day's rolls oldest first - the day-level
    /// counterpart of copy-session.
    public func copyDayToPasteboard(_ group: RollDayGroup) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(dayShareText(group), forType: .string)
    }

    /// One-tap session recap (2.46.0): the character's journal entries
    /// and rolls from today as one shareable text block.
    public func copySessionRecapToPasteboard(_ character: Character) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(sessionRecap(character: character, rolls: rollHistory), forType: .string)
    }

    public func clearRollHistory() {
        rollHistory.removeAll()
        rollHistoryStore.save(rollHistory)
    }

    /// 2.79.0: per-roll delete - a mis-rolled entry leaves the log
    /// without clearing everything. Identical rolls are
    /// indistinguishable, so the first match goes.
    public func deleteRoll(_ roll: RollResult) {
        rollHistory = rollHistory.removingFirst(roll)
        rollHistoryStore.save(rollHistory)
    }

    private func record(_ r: RollResult) {
        var r = r
        r.characterName = selected?.wrappedValue.name
        rollHistory.insert(r, at: 0)
        if rollHistory.count > 200 { rollHistory.removeLast(rollHistory.count - 200) }
        rollHistoryStore.save(rollHistory)
        if autoLogRollsToJournal { addRollToJournal(r) }
    }

    public func roll(_ expression: String) {
        if var r = try? roller.roll(expression) {
            r.reroll = RerollSpec(kind: .plain)
            record(r)
        }
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
        r.reroll = RerollSpec(kind: .incomingDamage)
        record(r)
        // record() auto-logs the roll to the journal when the 2.45.0
        // toggle is on; re-read so the write-back below keeps the entry.
        c = selected?.wrappedValue ?? c
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
        if var r = try? roller.rollLabeled(label, expression) {
            r.reroll = RerollSpec(kind: .plain, baseLabel: label)
            record(r)
        }
    }

    /// 2.40.0 roll-again: replay a history card's roll. 2.40.0+ rolls
    /// carry their undecorated inputs, so condition tags and
    /// outgoing-defense notes recompute against the character as they are
    /// now; older rolls fall back to a plain reroll of the expression
    /// under the recorded display label. Incoming damage is not
    /// rerollable - rolling again is not taking more damage.
    public func rollAgain(_ source: RollResult, variant: RerollVariant = .same) {
        // 2.43.0 variants: advantage/disadvantage override the requested
        // d20 mode (conditions still apply); +/-2 shifts a check bonus or
        // appends to a plain/damage expression.
        guard let spec = source.reroll else {
            if let label = source.label { rollLabeled(label, source.expression.withRerollModifier(variant)) }
            else { roll(source.expression.withRerollModifier(variant)) }
            return
        }
        switch spec.kind {
        case .plain:
            if let base = spec.baseLabel { rollLabeled(base, source.expression.withRerollModifier(variant)) }
            else { roll(source.expression.withRerollModifier(variant)) }
        case .check:
            let adjusted = spec.adjusted(for: variant)
            rollCheck(adjusted.baseLabel ?? source.label ?? "Check",
                      bonus: adjusted.checkBonus ?? 0, mode: adjusted.mode ?? .normal)
        case .outgoingDamage:
            recordDamageRoll(spec.baseLabel ?? source.label ?? "Damage",
                             source.expression.withRerollModifier(variant),
                             type: spec.damageType.flatMap { DamageType(rawValue: $0) })
        case .incomingDamage:
            break
        }
    }

    /// Roll a saved macro: labeled with its name. A macro with a damage-type
    /// tag (2.36.0) takes the same outgoing-defense-note path as typed free
    /// rolls and attack damage; an unknown stored tag falls back to a plain
    /// labeled roll (fail-safe on a renamed case, like 2.33.0).
    public func rollMacro(_ macro: DiceMacro) {
        let type = macro.damageType.flatMap { DamageType(rawValue: $0) }
        if let type {
            recordDamageRoll(macro.name, macro.expression, type: type)
        } else {
            rollLabeled(macro.name, macro.expression)
        }
    }

    /// Damage roll labeled with the outgoing-defense math for its type -
    /// what the total deals against resistance, immunity, and vulnerability
    /// on the target. Untyped or unrecognized types roll without a note.
    private func recordDamageRoll(_ label: String, _ expression: String, type: DamageType?) {
        guard var r = try? roller.rollLabeled(label, expression) else { return }
        if let type {
            r.label = "\(label) (\(Character.outgoingDefenseNote(total: r.total, type: type)))"
        }
        r.reroll = RerollSpec(kind: .outgoingDamage, baseLabel: label,
                              damageType: type?.rawValue)
        record(r)
    }

    /// Quick-add a history roll to the selected character's journal.
    public func addRollToJournal(_ roll: RollResult) {
        guard var c = selected?.wrappedValue else { return }
        let title = roll.label ?? roll.expression
        // 2.46.0: stamp the entry with the roll's own day and creation
        // time so the session recap can place it.
        let stamp = roll.rolledAt ?? Date()
        c.journal.append(JournalEntry(date: JournalStamp.day(stamp), title: title,
                                      text: "Rolled \(roll.total) (\(roll.expression))",
                                      createdAt: stamp))
        selected?.wrappedValue = c
    }

    /// Copy one journal entry (2.55.0): the row button's action - the
    /// export head plus body, for sharing one finding without the whole
    /// session recap.
    public func copyJournalEntryToPasteboard(_ entry: JournalEntry) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(entry.shareText, forType: .string)
    }

    /// Copy-filtered export (2.63.0): the filter-visible entries as one
    /// share block, in display order.
    public func copyFilteredJournalToPasteboard(_ entries: [JournalEntry]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(JournalEntry.shareText(entries: entries), forType: .string)
    }

    /// One-tap session digest (2.49.0): drop a whole session's rolls into
    /// the journal as one entry, oldest first - the session-divider
    /// button's action, offered while auto-log is off.
    public func addSessionToJournal(_ session: RollSession, title: String? = nil,
                                    format: DigestFormat? = nil) {
        guard var c = selected?.wrappedValue else { return }
        // 2.62.0: no explicit format follows the remembered choice.
        c.journal.append(JournalEntry(sessionDigest: session, title: title,
                                      format: format ?? digestFormat))
        selected?.wrappedValue = c
    }

    /// Level-up assistant: roll the hit die or take the average, then apply.
    public func levelUp(rollHP: Bool) {
        guard var c = selected?.wrappedValue, c.level < 20 else { return }
        let gain: Int
        if rollHP {
            guard let r = try? roller.rollLabeled("Level up HP (level \(c.level + 1))", c.levelUpRollExpression) else { return }
            record(r)
            // Keep record()'s auto-logged journal entry (2.45.0) off the
            // stale copy written back below.
            c = selected?.wrappedValue ?? c
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
            var r = roller.check(label, bonus: bonus, mode: mode)
            r.reroll = RerollSpec(kind: .check, baseLabel: label, mode: mode, checkBonus: bonus)
            record(r)
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
        var r = roller.check(tagged, bonus: bonus - penalty, mode: effective)
        r.reroll = RerollSpec(kind: .check, baseLabel: label, mode: mode, checkBonus: bonus)
        record(r)
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
        // Re-read so record()'s auto-log journal entry (2.45.0) survives
        // the write-back below.
        c = selected?.wrappedValue ?? c
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
        // Re-read so record()'s auto-log journal entry (2.45.0) survives
        // the write-back below.
        c = selected?.wrappedValue ?? c
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
        savePanel(text: SheetExporter.exportMarkdown(sel, journalTimestamps: exportJournalTimestamps),
                  name: "\(sel.name).md")
    }

    public func exportHTML() {
        guard let sel = selected?.wrappedValue else { return }
        savePanel(text: SheetExporter.exportHTML(sel, journalTimestamps: exportJournalTimestamps),
                  name: "\(sel.name).html")
    }

    /// Per-session Markdown export (2.72.0): one divider's session as
    /// its own file - name as title, note, stats line, roll table.
    public func exportSessionMarkdown(_ session: RollSession) {
        let safe = session.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        savePanel(text: sessionMarkdown(session), name: "\(safe).md")
    }

    /// Session-log text export (2.42.0): the character's rolls as a
    /// day-grouped plain-text file, honoring the configured appendix range
    /// - the same rolls the compact-PDF appendix would print.
    public func exportSessionLog() {
        guard let sel = selected?.wrappedValue else { return }
        let rolls = rollHistory.forCharacter(sel.name).within(compactPDFSessionLogRange)
        let rows = sessionLogRows(rolls, names: sessionNames, notes: sessionNotes)
        savePanel(text: sessionLogText(character: sel.name,
                                       range: compactPDFSessionLogRange, rows: rows),
                  name: "\(sel.name)-session-log.txt")
    }

    /// Session-log Markdown export (2.44.0): the same rolls and range as
    /// the text export, as one Markdown table per day.
    public func exportSessionLogMarkdown() {
        guard let sel = selected?.wrappedValue else { return }
        let rolls = rollHistory.forCharacter(sel.name).within(compactPDFSessionLogRange)
        let groups = namedDayGroups(Array(rolls.reversed()), names: sessionNames, notes: sessionNotes)
        savePanel(text: sessionLogMarkdown(character: sel.name,
                                           range: compactPDFSessionLogRange, groups: groups),
                  name: "\(sel.name)-session-log.md")
    }

    public func exportPDF() {
        guard let sel = selected?.wrappedValue else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(sel.name).pdf"
        if panel.runModal() == .OK, let url = panel.url {
            try? SheetPDFExporter.export(sel, journalTimestamps: exportJournalTimestamps).write(to: url)
        }
    }

    public func exportCompactPDF(landscape: Bool = false) {
        guard let sel = selected?.wrappedValue else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = landscape ? "\(sel.name)-compact-landscape.pdf" : "\(sel.name)-compact.pdf"
        if panel.runModal() == .OK, let url = panel.url {
            try? SheetPDFExporter.export(sel, style: .compact,
                                         orientation: landscape ? .landscape : .portrait,
                                         collapseEmptyInventory: compactPDFHideEmptyRows,
                                         sessionRolls: compactPDFSessionLog
                                             ? rollHistory.forCharacter(sel.name).within(compactPDFSessionLogRange) : [],
                                         journalTimestamps: exportJournalTimestamps,
                                         sessionNames: sessionNames,
                                         sessionNotes: sessionNotes).write(to: url)
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
