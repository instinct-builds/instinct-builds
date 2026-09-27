#if os(macOS)
import SwiftUI
import ArchiterCore

struct DiceInlineBlock: View {
    @EnvironmentObject var model: AppModel
    @State private var expression = "2d6+3"

    var body: some View {
        BlockCard(title: "Dice") {
            HStack {
                TextField("Dice notation", text: $expression)
                    .textFieldStyle(InsetFieldStyle())
                    .frame(width: 160)
                    .onSubmit { model.roll(expression) }
                Button("Roll") { model.roll(expression) }
                    .buttonStyle(RollButtonStyle(prominent: true))
                ForEach(["d4", "d6", "d8", "d10", "d12", "d20"], id: \.self) { d in
                    Button(d) { model.roll(d) }.buttonStyle(RollButtonStyle())
                }
            }
            if let last = model.rollHistory.first {
                RollCard(roll: last)
            }
            Text("Full roller and history on the Dice tab.")
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.inkMuted)
        }
    }
}

public struct DiceRollerView: View {
    @EnvironmentObject var model: AppModel

    /// 2.74.0: harness hook - start with the Latest session scope on.
    /// 2.78.0/2.84.0: or with the crits-only / starred-only filter on.
    /// 2.97.0: or with a history filter drafted (render proofs).
    public init(initialLatestSession: Bool = false, initialCritsOnly: Bool = false,
                initialStarredOnly: Bool = false, initialHistoryFilter: String = "",
                initialSavingFilterPreset: Bool = false,
                initialFilterPresetNameDraft: String = "",
                initialConfirmingFilteredDelete: Bool = false,
                initialConfirmingClearAll: Bool = false,
                initialRenamingPresetOriginal: String? = nil,
                initialRenamePresetDraft: String = "") {
        _historyLatestSession = State(initialValue: initialLatestSession)
        _historyCritsOnly = State(initialValue: initialCritsOnly)
        _historyStarredOnly = State(initialValue: initialStarredOnly)
        _historyFilter = State(initialValue: initialHistoryFilter)
        _savingFilterPreset = State(initialValue: initialSavingFilterPreset)
        _filterPresetNameDraft = State(initialValue: initialFilterPresetNameDraft)
        _confirmingFilteredDelete = State(initialValue: initialConfirmingFilteredDelete)
        _confirmingClearAll = State(initialValue: initialConfirmingClearAll)
        _renamingPresetOriginal = State(initialValue: initialRenamingPresetOriginal)
        _renamePresetDraft = State(initialValue: initialRenamePresetDraft)
    }
    @State private var expression = "2d6+3"
    @State private var d20Mode: RollMode = .normal
    @State private var d20Modifier = 0
    /// Target DC draft (3.20.0): blank means no target; applies to the
    /// bar's free roll and d20 check.
    @State private var dcDraft = ""
    @State private var macroNameDraft = ""
    /// Free-roller damage type, persisted on the model across launches;
    /// nil keeps rolls untyped (no defense note).
    private var damageType: Binding<DamageType?> {
        Binding(get: { model.freeRollerDamageType }, set: { model.freeRollerDamageType = $0 })
    }
    /// The bar's target DC (3.20.0); nil when the draft is blank or
    /// not a number (the field validates on submit, not per keystroke).
    private var barTargetDC: Int? {
        let trimmed = dcDraft.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : Int(trimmed)
    }
    /// Save scope for new macros: true binds them to the selected character.
    @State private var saveForCharacter = true
    /// History scope: false = whole table, true = selected character only.
    @State private var historyForCharacter = false
    /// Latest-session scope (2.74.0): true shows only the newest
    /// session's rolls - the common case at the table.
    @State private var historyLatestSession = false
    /// Crits-only filter (2.78.0): true shows only rolls with a kept
    /// natural 20 or natural 1 - the moments that mattered.
    @State private var historyCritsOnly = false
    /// Starred-only filter (2.84.0): true shows only rolls the table
    /// starred - manual curation next to the automatic crits filter.
    @State private var historyStarredOnly = false
    /// Text filter over history labels and expressions; blank shows all.
    @State private var historyFilter = ""
    /// Filter-preset naming form (3.0.0): true while the bar is naming
    /// the current filter as a preset; the draft pre-fills with the query.
    @State private var savingFilterPreset = false
    @State private var filterPresetNameDraft = ""
    /// Filter-preset rename form (3.6.0): the preset being renamed
    /// while the inline form is open; the draft pre-fills with its
    /// current name.
    @State private var renamingPresetOriginal: String?
    @State private var renamePresetDraft = ""
    /// Filtered-delete confirm (3.3.0): true while the bar asks before
    /// removing the filter-visible subset; Undo restores it.
    @State private var confirmingFilteredDelete = false
    /// Clear-all confirm (3.4.0): true while the bar asks before
    /// emptying the whole log; Clear has no undo - the confirm
    /// carries the weight.
    @State private var confirmingClearAll = false

    private var visibleHistory: [RollResult] {
        let name = historyForCharacter ? model.selected?.wrappedValue.name : nil
        let base = model.rollHistory.forCharacter(name)
        let scoped = historyLatestSession ? base.latestSession() : base
        let critted = historyCritsOnly ? scoped.critRolls : scoped
        let starred = historyStarredOnly ? critted.starredRolls : critted
        return starred.matching(historyFilter)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                TextField("Dice notation", text: $expression)
                    .textFieldStyle(InsetFieldStyle())
                    .frame(width: 200)
                    .onSubmit { model.rollFree(expression, type: damageType.wrappedValue, targetDC: barTargetDC) }
                Button("Roll") { model.rollFree(expression, type: damageType.wrappedValue, targetDC: barTargetDC) }
                    .buttonStyle(RollButtonStyle(prominent: true))
                    .keyboardShortcut(.return)
                Picker("", selection: damageType) {
                    Text("No type").tag(DamageType?.none)
                    ForEach(DamageType.allCases, id: \.self) { Text($0.displayName).tag(DamageType?.some($0)) }
                }
                .labelsHidden()
                .frame(maxWidth: 110)
                .help("Damage type: typed rolls note what they deal against resistance, immunity, and vulnerability. Remembered per character (or for the table when none is selected).")
                TextField("DC", text: $dcDraft)
                    .textFieldStyle(InsetFieldStyle())
                    .frame(width: 48)
                    .help("Target DC: the roll's history card shows whether it met the DC. Blank means no target.")
                Text("d20 · 2d6+3 · 4d6kh3 · 4d6dl1 · 1d8+1d4+2")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Picker("Mode", selection: $d20Mode) {
                    ForEach([RollMode.normal, .advantage, .disadvantage], id: \.self) { m in
                        Text(m.rawValue.capitalized).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 320)
                Stepper("Modifier \(signed(d20Modifier))", value: $d20Modifier, in: -10...30)
                Button("Roll d20") { model.rollCheck("d20 roll", bonus: d20Modifier, mode: d20Mode, targetDC: barTargetDC) }
                    .buttonStyle(RollButtonStyle(prominent: true))
            }
            // 3.24.0: pre-roll visibility for side effects rollCheck already
            // enforces - advisory only, the roll-time downgrade + history tag
            // stays the single source of enforcement. Hidden when clean.
            if let sel = model.selected?.wrappedValue {
                let advisory = ConditionAdvisory.lines(for: sel)
                if !advisory.isEmpty {
                    Text(advisory.joined(separator: " \u{00B7} "))
                        .font(Theme.Typeface.caption)
                        .foregroundStyle(Theme.inkMuted)
                }
            }
            VStack(alignment: .leading, spacing: Theme.Gap.sm) {
                Text("Macros").font(.headline)
                // 3.15.0: pinned macros float to the top of their
                // group; the owner sections themselves stay put.
                let characterMacros = pinnedFirst(model.visibleMacros.filter { $0.characterName != nil })
                let tableMacros = pinnedFirst(model.visibleMacros.filter { $0.characterName == nil })
                if !characterMacros.isEmpty, let name = model.selected?.wrappedValue.name {
                    Text(name)
                        .font(Theme.Typeface.caption)
                        .foregroundStyle(Theme.inkMuted)
                    ForEach(characterMacros) { macroRow($0) }
                }
                if !characterMacros.isEmpty {
                    Text("Table")
                        .font(Theme.Typeface.caption)
                        .foregroundStyle(Theme.inkMuted)
                }
                ForEach(tableMacros) { macroRow($0) }
                HStack {
                    TextField("Macro name", text: $macroNameDraft)
                        .textFieldStyle(InsetFieldStyle())
                        .frame(width: 160)
                    Button("Save current as macro") {
                        model.saveMacro(
                            name: macroNameDraft, expression: expression,
                            forCharacter: saveForCharacter ? model.selected?.wrappedValue.name : nil)
                        macroNameDraft = ""
                    }
                    .buttonStyle(RollButtonStyle())
                    .disabled(macroNameDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    .help("Bind the dice notation above to a reusable shortcut")
                    if let name = model.selected?.wrappedValue.name {
                        Toggle("For \(name) only", isOn: $saveForCharacter)
                            .toggleStyle(.checkbox)
                            .font(Theme.Typeface.caption)
                    }
                }
            }
            InitiativeSectionView()
            GroupCheckSectionView()
            EncounterSectionView()
            TableLogView()
            HStack {
                Text("History").font(.headline)
                if let name = model.selected?.wrappedValue.name {
                    Picker("", selection: $historyForCharacter) {
                        Text("All").tag(false)
                        Text(name).tag(true)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 220)
                }
                // 3.14.0: bar chips never wrap - the label takes its
                // ideal one-line width and the spacer/field yield,
                // same treatment as the 3.13.1 count. "Latest session"
                // was the last wrap left in the bar; Crits and
                // Starred get it too for consistency.
                Toggle("Latest session", isOn: $historyLatestSession)
                    .toggleStyle(.checkbox)
                    .font(Theme.Typeface.caption)
                    .lineLimit(1)
                    .fixedSize()
                    .help("Show only the newest session's rolls - pane, count, and Copy all follow")
                Toggle("Crits", isOn: $historyCritsOnly)
                    .toggleStyle(.checkbox)
                    .font(Theme.Typeface.caption)
                    .lineLimit(1)
                    .fixedSize()
                    .help("Show only rolls with a kept natural 20 or natural 1")
                Toggle("Starred", isOn: $historyStarredOnly)
                    .toggleStyle(.checkbox)
                    .font(Theme.Typeface.caption)
                    .lineLimit(1)
                    .fixedSize()
                    .help("Show only rolls the table starred")
                TextField("Filter rolls", text: $historyFilter)
                    .textFieldStyle(InsetFieldStyle())
                    // 3.14.2: the field is the bar's designated shock
                    // absorber - 110 still shows long queries, and the
                    // freed 50px keeps every label right of it whole.
                    .frame(maxWidth: 110)
                // 3.10.0: clear the filter with one click instead of
                // select-all-delete; hidden while the field is empty.
                if !historyFilter.isEmpty {
                    Button {
                        historyFilter = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.inkMuted)
                    .controlSize(.small)
                    .help("Clear the filter")
                }
                // 3.0.0: named filter presets - save the current filter
                // under a name and re-apply it from the menu.
                Menu {
                    // 3.8.0: the preset whose query the filter text
                    // exactly matches is the active one - checkmarked
                    // here, and the bookmark fills.
                    let activePreset = model.filterPresets.preset(matchingQuery: historyFilter)
                    ForEach(model.filterPresets, id: \.name) { preset in
                        if preset.name == activePreset?.name {
                            Button { historyFilter = preset.query }
                        label: { Label(preset.name, systemImage: "checkmark") }
                        } else {
                            Button(preset.name) { historyFilter = preset.query }
                        }
                    }
                    if !model.filterPresets.isEmpty { Divider() }
                    Button("Save current filter…") {
                        // 3.9.0: while a preset is active the draft
                        // pre-fills with its name - re-saving under
                        // the same name takes no retype, and the
                        // 3.7.0 note shows the replace.
                        filterPresetNameDraft = model.filterPresets
                            .preset(matchingQuery: historyFilter)?.name
                            ?? historyFilter.trimmingCharacters(in: .whitespaces)
                        renamingPresetOriginal = nil
                        savingFilterPreset = true
                    }
                    .disabled(historyFilter.trimmingCharacters(in: .whitespaces).isEmpty)
                    if !model.filterPresets.isEmpty {
                        Divider()
                        // 3.6.0: rename a preset in place - no
                        // delete-and-recreate, its filter stays.
                        Menu("Rename") {
                            ForEach(model.filterPresets, id: \.name) { preset in
                                Button(preset.name) {
                                    renamingPresetOriginal = preset.name
                                    renamePresetDraft = preset.name
                                    savingFilterPreset = false
                                }
                            }
                        }
                        Menu("Remove") {
                            ForEach(model.filterPresets, id: \.name) { preset in
                                Button(preset.name) { model.deleteFilterPreset(name: preset.name) }
                            }
                        }
                    }
                } label: {
                    Image(systemName: model.filterPresets.preset(matchingQuery: historyFilter) != nil
                          ? "bookmark.fill" : "bookmark")
                }
                .controlSize(.small)
                .help(model.filterPresets.preset(matchingQuery: historyFilter)
                      .map { "Saved filter presets - active preset: \($0.name)" }
                      ?? "Saved filter presets - apply one, save the current filter, rename one, or remove one")
                if savingFilterPreset {
                    TextField("Preset name", text: $filterPresetNameDraft)
                        .textFieldStyle(InsetFieldStyle())
                        .frame(maxWidth: 120)
                    // 3.7.0: the form says why it stays open - a blank
                    // name disables Save; an existing name notes the
                    // replace instead of overwriting silently.
                    Button("Save") {
                        if model.saveFilterPreset(name: filterPresetNameDraft,
                                                  query: historyFilter) {
                            savingFilterPreset = false
                        }
                    }
                    .controlSize(.small)
                    .disabled(model.filterPresets.nameIssue(filterPresetNameDraft) == .blank)
                    .help("Save the current filter under this name")
                    Button("Cancel") { savingFilterPreset = false }
                        .controlSize(.small)
                    if model.filterPresets.nameIssue(filterPresetNameDraft) == .blank {
                        Text("Enter a preset name.")
                            .font(Theme.Typeface.caption)
                            .foregroundStyle(Theme.inkMuted)
                    } else if let existing = model.filterPresets.preset(named: filterPresetNameDraft) {
                        Text("Replaces \"\(existing.name)\".")
                            .font(Theme.Typeface.caption)
                            .foregroundStyle(Theme.inkMuted)
                    }
                }
                if let original = renamingPresetOriginal {
                    TextField("New preset name", text: $renamePresetDraft)
                        .textFieldStyle(InsetFieldStyle())
                        .frame(maxWidth: 120)
                    // 3.7.0: a rejected rename (blank, or clashing with
                    // another preset) says so inline and disables
                    // Rename instead of silently staying open.
                    Button("Rename") {
                        if model.renameFilterPreset(from: original, to: renamePresetDraft) {
                            renamingPresetOriginal = nil
                        }
                    }
                    .controlSize(.small)
                    .disabled(model.filterPresets.nameIssue(renamePresetDraft, replacing: original) != nil)
                    .help("Rename the preset, keeping its filter")
                    Button("Cancel") { renamingPresetOriginal = nil }
                        .controlSize(.small)
                    if let issue = model.filterPresets.nameIssue(renamePresetDraft, replacing: original) {
                        Text(presetNameIssueMessage(issue))
                            .font(Theme.Typeface.caption)
                            .foregroundStyle(Theme.inkMuted)
                    }
                }
                if !historyFilter.trimmingCharacters(in: .whitespaces).isEmpty {
                    // 3.11.0: when the filtered subset carries notes
                    // the count says how many, so a notes-hunt knows
                    // there is something to find. 3.13.0: the starred
                    // count rides the same line, mirroring the notes.
                    // 3.14.2: "noted" compacts the copy - with both
                    // suffixes the longer form overflowed the bar.
                    let noted = visibleHistory.notedCount
                    let starred = visibleHistory.starredCount
                    Text("\(visibleHistory.count) of \(model.rollHistory.forCharacter(historyForCharacter ? model.selected?.wrappedValue.name : nil).count)"
                         + (noted > 0 ? ", \(noted) noted" : "")
                         + (starred > 0 ? ", \(starred) starred" : ""))
                        .font(Theme.Typeface.caption)
                        .foregroundStyle(Theme.inkMuted)
                        // 3.13.1: the notes + starred suffixes can
                        // overrun the bar at narrow widths - keep the
                        // count to one line, scale before truncating,
                        // and let the spacer/field yield instead.
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .layoutPriority(1)
                }
                Spacer()
                // 2.45.0 auto-log: every roll also lands in the journal.
                Toggle("Journal", isOn: $model.autoLogRollsToJournal)
                    .controlSize(.small)
                    .help("Automatically add every roll to the journal")
                // 2.81.0: undo the last per-roll or per-session delete.
                // Visible only while a deletion is unconsumed.
                if let deletion = model.lastDeletion {
                    // 3.5.0: the button names its target - how many
                    // rolls the restore brings back.
                    Button(deletion.removedCount == 1
                           ? "Undo delete (1 roll)"
                           : "Undo delete (\(deletion.removedCount) rolls)") { model.undoDelete() }
                        .controlSize(.small)
                        // 3.18.0: the hover names what the restore
                        // brings back - session title when known.
                        .help(undoDeleteLabel(removedCount: deletion.removedCount,
                                              sessionName: deletion.sessionName))
                }
                // 3.0.1: while the preset naming form is open the
                // Copy/Digest/star cluster collapses so the bar never
                // wraps; the naming controls take the space instead.
                // 3.3.1: the same collapse while the filtered-delete
                // confirm is open - the confirm controls take the space.
                // 3.4.0: and while the Clear-all confirm is open.
                if !savingFilterPreset && renamingPresetOriginal == nil && !confirmingFilteredDelete && !confirmingClearAll {
                    // 2.97.0: the button says when the filter narrows what it
                    // copies - the journal's explicit Copy filtered (2.63.0)
                    // sets the precedent; the action already rides
                    // visibleHistory, notes included via shareLines.
                    Button(historyFilter.trimmingCharacters(in: .whitespaces).isEmpty ? "Copy" : "Copy filtered") {
                        let query = historyFilter.trimmingCharacters(in: .whitespaces)
                        if query.isEmpty {
                            model.copyRollsToPasteboard(visibleHistory)
                        } else {
                            // 2.98.0: the paste says it was narrowed.
                            model.copyFilteredRollsToPasteboard(
                                visibleHistory, query: query,
                                ofTotal: model.rollHistory.forCharacter(historyForCharacter ? model.selected?.wrappedValue.name : nil).count)
                        }
                    }
                        .controlSize(.small)
                        .disabled(visibleHistory.isEmpty)
                        .help("Copy the shown rolls (scope and filter applied) as text, oldest first")
                }
                // 2.99.0: file the filtered subset into the journal as
                // one digest entry titled with the query - the filter
                // view's counterpart of Digest starred.
                if !savingFilterPreset && renamingPresetOriginal == nil && !confirmingClearAll,
                   !historyFilter.trimmingCharacters(in: .whitespaces).isEmpty {
                    // 3.3.1: the overflow collapses while the delete
                    // confirm is open - the confirm controls take the
                    // space, same discipline as 3.0.1.
                    if confirmingFilteredDelete {
                        // 3.3.0: the destructive member of the filter
                        // family - behind a confirm, with one undo step.
                        Text("Delete \(visibleHistory.count) rolls?")
                            .font(Theme.Typeface.caption)
                            .foregroundStyle(Theme.inkMuted)
                        Button("Delete") {
                            model.deleteFilteredRolls(visibleHistory)
                            confirmingFilteredDelete = false
                        }
                        .controlSize(.small)
                        .help("Remove the filtered rolls from history - Undo restores them")
                        Button("Cancel") { confirmingFilteredDelete = false }
                            .controlSize(.small)
                    } else {
                        // 3.12.0: the three less-used filter actions
                        // collapse into one overflow menu so the bar
                        // stops wrapping; Copy filtered and Journal
                        // stay top-level. The ellipsis on Delete
                        // signals the confirm step.
                        Menu {
                            Button("Digest filtered") {
                                model.addFilteredRollsToJournal(
                                    visibleHistory,
                                    query: historyFilter.trimmingCharacters(in: .whitespaces))
                            }
                                .disabled(model.selected == nil)
                            // 3.1.0: the file side of the filter family -
                            // same shape as the starred export, headed
                            // by the query.
                            Button("Export filtered") {
                                model.exportFilteredMarkdown(
                                    visibleHistory,
                                    query: historyFilter.trimmingCharacters(in: .whitespaces),
                                    ofTotal: model.rollHistory.forCharacter(historyForCharacter ? model.selected?.wrappedValue.name : nil).count)
                            }
                                .disabled(visibleHistory.isEmpty)
                            Divider()
                            // 3.16.0: the item names the count it
                            // would remove - the only pre-click signal
                            // since the 3.12.0 collapse.
                            Button(deleteFilteredMenuLabel(count: visibleHistory.count)) { confirmingFilteredDelete = true }
                                .disabled(visibleHistory.isEmpty)
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .controlSize(.small)
                        .help("More filter actions - digest as one journal entry, export as Markdown, delete with one undo step")
                    }
                }
                // 2.85.0: the highlight reel - visible only while stars exist.
                // 3.0.1: also hidden while the preset naming form is open.
                // 3.4.0: and while the Clear-all confirm is open.
                if !savingFilterPreset && renamingPresetOriginal == nil && !confirmingClearAll && !model.rollHistory.starredRolls.isEmpty {
                    // 3.2.0: with the filter cluster also in the bar the
                    // four star actions collapse into one menu so the
                    // bar stays on one line; without a filter they keep
                    // their one-tap buttons.
                    if !historyFilter.trimmingCharacters(in: .whitespaces).isEmpty {
                        Menu {
                            Button("Copy starred") { model.copyStarredToPasteboard() }
                            Button("Unstar all") { model.unstarAll() }
                            Button("Export starred") { model.exportStarredMarkdown() }
                            Button("Digest starred") { model.addStarredToJournal() }
                                .disabled(model.selected == nil)
                        } label: {
                            Label("Starred", systemImage: "star")
                                .lineLimit(1)
                        }
                        .controlSize(.small)
                        // 3.14.1: the menu keeps its full label - the
                        // 3.14.0 chip fix moved bar pressure here and
                        // fixedSize on the label alone lost to the
                        // menu chrome's own compression, so the menu
                        // itself out-prioritizes the filter field,
                        // which is the element designed to yield.
                        .layoutPriority(1)
                        .help("Starred-roll actions - copy, unstar, export, digest")
                    } else {
                        Button("Copy starred") { model.copyStarredToPasteboard() }
                            .controlSize(.small)
                            .help("Copy just the starred rolls as text, oldest first")
                        // 2.86.0: the reset half of the loop - one tap
                        // clears every star once the reel is copied out.
                        Button("Unstar all") { model.unstarAll() }
                            .controlSize(.small)
                            .help("Clear every star - reset the highlight reel for the next scene")
                        // 2.88.0: the reel as a file - the star arc's
                        // output side beyond the pasteboard.
                        Button("Export starred") { model.exportStarredMarkdown() }
                            .controlSize(.small)
                            .help("Save the starred rolls as a Markdown file")
                        // 2.89.0: file the reel into the journal as one
                        // entry - the star arc's journal destination.
                        Button("Digest starred") { model.addStarredToJournal() }
                            .controlSize(.small)
                            .disabled(model.selected == nil)
                            .help("Add the starred rolls to the journal as one entry")
                    }
                }
                // 3.4.0: confirm parity - Clear asks inline before
                // emptying the whole log, the same idiom as Delete
                // filtered (3.3.0). Unlike the filtered delete, Clear
                // has no undo; the confirm carries the weight.
                if confirmingClearAll {
                    Text("Clear all \(model.rollHistory.count) rolls?")
                        .font(Theme.Typeface.caption)
                        .foregroundStyle(Theme.inkMuted)
                    Button("Clear") {
                        model.clearRollHistory()
                        confirmingClearAll = false
                    }
                    .controlSize(.small)
                    .help("Empty the roll history - this cannot be undone")
                    Button("Cancel") { confirmingClearAll = false }
                        .controlSize(.small)
                } else {
                    Button("Clear") { confirmingClearAll = true }
                        .controlSize(.small)
                        .disabled(model.rollHistory.isEmpty)
                        .help("Empty the roll history, behind a confirm")
                }
            }
            HistoryListView(rolls: visibleHistory)
        }
        .padding(Theme.Gap.lg)
        .background(Theme.surface)
        .preferredColorScheme(.dark)
    }
}

extension DiceRollerView {
    /// One macro row (view wrapper keeps per-row edit state).
    @ViewBuilder func macroRow(_ macro: DiceMacro) -> some View {
        MacroRowView(macro: macro)
    }
}

/// The session-divided history list with sticky headers (2.38.0 day
/// groups, 2.48.0 session dividers). Public so the render harness can
/// snapshot it with a crafted roll set: rendering the full DiceRollerView
/// at fitting size mis-measures the pinned sections (a nearly-10k-px
/// window with the second group's rows clipped), so the group proof
/// renders this list in a fixed frame instead.
public struct HistoryListView: View {
    @EnvironmentObject var model: AppModel
    let rolls: [RollResult]
    /// 2.58.0: divider whose digest is being named, and the draft title.
    @State private var namingSession: Int?
    @State private var digestTitle: String
    /// 2.67.0: divider whose session is being renamed, and the drafts -
    /// 2.71.0 adds the session note to the same inline form.
    @State private var renamingSession: Int?
    @State private var sessionNameDraft: String
    @State private var sessionNoteDraft: String

    public init(rolls: [RollResult], initialNamingSession: Int? = nil,
                initialDigestTitle: String = "",
                initialRenamingSession: Int? = nil,
                initialSessionNameDraft: String = "",
                initialSessionNoteDraft: String = "") {
        self.rolls = rolls
        _namingSession = State(initialValue: initialNamingSession)
        _digestTitle = State(initialValue: initialDigestTitle)
        _renamingSession = State(initialValue: initialRenamingSession)
        _sessionNameDraft = State(initialValue: initialSessionNameDraft)
        _sessionNoteDraft = State(initialValue: initialSessionNoteDraft)
    }

    /// Files the digest with the drafted name and closes the inline form.
    private func confirmDigest(_ session: RollSession) {
        model.addSessionToJournal(session, title: digestTitle)
        namingSession = nil
    }

    /// 2.67.0: stores the drafted custom name (blank restores the
    /// generated title) and note (2.71.0; blank clears), then closes
    /// the inline form.
    private func confirmRename(_ session: RollSession) {
        if let key = session.key {
            model.renameSession(key, to: sessionNameDraft)
            model.setSessionNote(key, to: sessionNoteDraft)
        }
        renamingSession = nil
    }

    /// The export-form day group a divider's day copies (2.77.0):
    /// named and summarized header with the day's rolls oldest first -
    /// exactly what the session-log exports print for the same day. A
    /// rendered session always has its group, so nil never reaches the
    /// button; the type's memberwise init stays inside ArchiterCore.
    private func dayGroup(for session: RollSession) -> RollDayGroup? {
        let dayTitle = rollDayTitle(session.rolls.last?.rolledAt)
        let groups = summarizedDayGroups(namedDayGroups(Array(rolls.reversed()),
                                                        names: model.sessionNames,
                                                        notes: model.sessionNotes))
        return groups.first { $0.title == dayTitle || $0.title.hasPrefix(dayTitle + " - ") }
    }

    /// Row identity namespaced by group: bare per-section offsets collide
    /// across sibling ForEaches inside a lazy stack, and SwiftUI drops the
    /// "duplicate" rows - which is exactly what the 2.38.0 renders showed
    /// (every later section rendered its header and no rows).
    private struct IndexedRoll: Identifiable {
        let id: String
        let roll: RollResult
    }

    public var body: some View {
        let sessions = model.namedSessions(rolls)
        return ScrollView {
            LazyVStack(spacing: Theme.Gap.sm, pinnedViews: [.sectionHeaders]) {
                ForEach(Array(sessions.enumerated()), id: \.offset) { index, session in
                    Section {
                        ForEach(session.rolls.enumerated().map {
                            IndexedRoll(id: "\(session.title)|\($0.offset)", roll: $0.element)
                        }) { item in
                            RollCard(roll: item.roll)
                        }
                    } header: {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(session.title)
                                    .font(Theme.Typeface.caption.bold())
                                    .foregroundStyle(Theme.inkMuted)
                                // 2.69.0: glanceable per-session summary -
                                // count, high/low, and crit tallies.
                                Text(sessionStats(session).line)
                                    .font(Theme.Typeface.captionSmall)
                                    .foregroundStyle(Theme.inkFaint)
                                // 2.71.0: the session note rides under
                                // the stats line, italic to read as prose.
                                if let note = session.note {
                                    Text(note)
                                        .font(Theme.Typeface.captionSmall.italic())
                                        .foregroundStyle(Theme.inkFaint)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                            }
                            Spacer()
                            // 2.49.0: digest the whole session into the
                            // journal as one entry. Hidden while auto-log
                            // is on (the rolls are already there), matching
                            // the 2.45.0 pencil; undated runs have no
                            // session to name. 2.58.0: the button opens an
                            // inline field pre-filled with the session's
                            // title so the digest can land named.
                            if namingSession == session.number {
                                TextField("Session name", text: $digestTitle)
                                    .textFieldStyle(InsetFieldStyle())
                                    .frame(width: 180)
                                    .onSubmit { confirmDigest(session) }
                                // 2.62.0: digest body layout - condensed
                                // one-line-per-roll or grouped by actor.
                                // The choice rides model.digestFormat, so
                                // the next digest preselects it.
                                Picker(selection: $model.digestFormat) {
                                    Text("Condensed").tag(DigestFormat.condensed)
                                    Text("By actor").tag(DigestFormat.byActor)
                                } label: {
                                    Image(systemName: "list.bullet.indent")
                                }
                                .pickerStyle(.menu)
                                .controlSize(.small)
                                .fixedSize()
                                .help("Digest body format - remembered for the next digest")
                                Button { confirmDigest(session) }
                                    label: { Image(systemName: "checkmark") }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(Theme.inkFaint)
                                    .help("Add to the journal with this name")
                                Button { namingSession = nil }
                                    label: { Image(systemName: "xmark") }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(Theme.inkFaint)
                                    .help("Cancel")
                            } else if renamingSession == session.number {
                                // 2.67.0: rename the session itself - the
                                // custom name replaces the generated
                                // "Session N - <day>" divider title, and a
                                // digest filed from it takes the name.
                                // 2.71.0: the same form edits the note.
                                VStack(alignment: .leading, spacing: 4) {
                                    TextField("Session name", text: $sessionNameDraft)
                                        .textFieldStyle(InsetFieldStyle())
                                        .frame(width: 180)
                                        .onSubmit { confirmRename(session) }
                                    TextField("Note (optional)", text: $sessionNoteDraft)
                                        .textFieldStyle(InsetFieldStyle())
                                        .frame(width: 180)
                                        .onSubmit { confirmRename(session) }
                                }
                                Button { confirmRename(session) }
                                    label: { Image(systemName: "checkmark") }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(Theme.inkFaint)
                                    .help("Rename this session")
                                Button { renamingSession = nil }
                                    label: { Image(systemName: "xmark") }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(Theme.inkFaint)
                                    .help("Cancel")
                            } else {
                                // 2.77.0: copy the whole day on the
                                // divider that opens it - the day's
                                // named, summarized header and rolls.
                                if index == 0 || rollDayTitle(sessions[index - 1].rolls.last?.rolledAt)
                                    != rollDayTitle(session.rolls.last?.rolledAt) {
                                    Button {
                                        if let group = dayGroup(for: session) {
                                            model.copyDayToPasteboard(group)
                                        }
                                    }
                                        label: { Image(systemName: "calendar") }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(Theme.inkFaint)
                                        .help("Copy this day's rolls as text")
                                }
                                // 2.87.0: star the whole session from its
                                // divider - the bulk version of a card's
                                // star. Filled once every roll is starred;
                                // a tap then clears them all.
                                let sessionStarred = !session.rolls.isEmpty
                                    && session.rolls.allSatisfy { $0.starred == true }
                                Button { model.toggleSessionStars(session) }
                                    label: { Image(systemName: sessionStarred ? "star.fill" : "star") }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(sessionStarred ? Theme.accent : Theme.inkFaint)
                                    .help(sessionStarred ? "Unstar every roll in this session" : "Star every roll in this session")
                                // 2.70.0: copy the session as plain
                                // text - title, stats line, rolls.
                                Button { model.copySessionToPasteboard(session) }
                                    label: { Image(systemName: "doc.on.doc") }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(Theme.inkFaint)
                                    .help("Copy this session's rolls as text")
                                // 2.72.0: export the session as its own
                                // Markdown file via save panel.
                                Button { model.exportSessionMarkdown(session) }
                                    label: { Image(systemName: "square.and.arrow.up") }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(Theme.inkFaint)
                                    .help("Export this session as a Markdown file")
                                // 2.67.0: rename pencil - only datable
                                // sessions carry a stable key to name.
                                if session.key != nil {
                                    Button {
                                        sessionNameDraft = session.title
                                        sessionNoteDraft = session.note ?? ""
                                        renamingSession = session.number
                                    } label: { Image(systemName: "pencil") }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(Theme.inkFaint)
                                        .help("Rename this session")
                                }
                                if session.number > 0, !model.autoLogRollsToJournal {
                                    Button {
                                        digestTitle = session.title
                                        namingSession = session.number
                                    } label: { Image(systemName: "text.book.closed") }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(Theme.inkFaint)
                                        .help("Add this session's rolls to the journal as one entry")
                                        .disabled(model.selected == nil)
                                }
                                // 2.80.0: delete the whole session - the
                                // middle ground between a card's trash
                                // and Clear. Removes its name and note too.
                                Button { model.deleteSession(session) }
                                    label: { Image(systemName: "trash") }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(Theme.inkFaint)
                                    .help(sessionDeleteLabel(session))
                            }
                        }
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity)
                        .background(Theme.surface)
                    }
                }
            }
        }
    }
}

/// One macro row: name, expression, roll (labeled with the macro name so
/// history reads clearly), edit-in-place, and delete. Public so the render
/// harness (ARCHITERRender target) can snapshot the editing state.
public struct MacroRowView: View {
    @EnvironmentObject var model: AppModel
    let macro: DiceMacro
    @State private var editing: Bool
    @State private var nameDraft: String
    @State private var expressionDraft: String
    @State private var typeDraft: DamageType?
    /// Target DC draft (3.20.0): blank means the macro rolls untargeted.
    @State private var dcDraft: String
    /// Combo editing (3.21.0): true while the edit form shows part rows.
    @State private var editingCombo: Bool
    @State private var partDrafts: [ComboPartDraft]

    /// Editable form of a combo part: Identifiable so the parts list
    /// can bind rows.
    private struct ComboPartDraft: Identifiable {
        let id = UUID()
        var label: String
        var expression: String
        var type: DamageType?
    }

    public init(macro: DiceMacro, startEditing: Bool = false) {
        self.macro = macro
        _editing = State(initialValue: startEditing)
        _nameDraft = State(initialValue: macro.name)
        _expressionDraft = State(initialValue: macro.expression)
        _typeDraft = State(initialValue: macro.damageType.flatMap { DamageType(rawValue: $0) })
        _dcDraft = State(initialValue: macro.targetDC.map(String.init) ?? "")
        _editingCombo = State(initialValue: macro.parts != nil)
        _partDrafts = State(initialValue: macro.parts?.map {
            ComboPartDraft(label: $0.label, expression: $0.expression,
                           type: $0.damageType.flatMap { DamageType(rawValue: $0) })
        } ?? [])
    }

    private var draftsValid: Bool {
        guard !nameDraft.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if editingCombo {
            return partDrafts.count >= 2 && partDrafts.allSatisfy {
                !$0.label.trimmingCharacters(in: .whitespaces).isEmpty
                    && (try? DiceExpression.parse($0.expression)) != nil
            }
        }
        let dcText = dcDraft.trimmingCharacters(in: .whitespaces)
        return (try? DiceExpression.parse(expressionDraft)) != nil
            && (dcText.isEmpty || Int(dcText) != nil)
    }

    /// Converts the single-expression draft into the first combo part
    /// and opens the parts editor with a blank second part.
    private func startCombo() {
        partDrafts = [ComboPartDraft(label: nameDraft, expression: expressionDraft, type: typeDraft),
                      ComboPartDraft(label: "", expression: "")]
        editingCombo = true
    }

    /// Collapses back to a single-expression macro, keeping part one's
    /// expression and type.
    private func collapseCombo() {
        if let first = partDrafts.first {
            expressionDraft = first.expression
            typeDraft = first.type
        }
        partDrafts = []
        editingCombo = false
    }

    private func saveCombo() {
        let parts = partDrafts.map {
            ComboPart(label: $0.label.trimmingCharacters(in: .whitespaces),
                      expression: $0.expression.trimmingCharacters(in: .whitespaces),
                      damageType: $0.type?.rawValue)
        }
        // Per-part types carry the tags; a leftover single-form type
        // would sit on the row ignored, so combo saves clear it.
        model.updateMacro(macro, name: nameDraft, expression: expressionDraft,
                          damageType: nil, parts: parts)
        editing = false
    }

    /// The combo edit form (3.21.0): one row per part plus add/save.
    private var comboEditor: some View {
        VStack(alignment: .leading, spacing: Theme.Gap.sm) {
            HStack {
                TextField("Name", text: $nameDraft)
                    .textFieldStyle(InsetFieldStyle())
                    .frame(width: 140)
                Text("combo")
                    .font(Theme.Typeface.captionSmall)
                    .foregroundStyle(Theme.accent)
                Button { collapseCombo() } label: { Image(systemName: "doc") }
                    .help("Back to a single-expression macro (keeps the first part)")
            }
            ForEach($partDrafts) { $part in
                HStack {
                    TextField("Part label", text: $part.label)
                        .textFieldStyle(InsetFieldStyle())
                        .frame(width: 130)
                    TextField("Expression", text: $part.expression)
                        .textFieldStyle(InsetFieldStyle())
                        .frame(maxWidth: 160)
                    Picker("", selection: $part.type) {
                        Text("No type").tag(DamageType?.none)
                        ForEach(DamageType.allCases, id: \.self) { Text($0.displayName).tag(DamageType?.some($0)) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 100)
                    Button { partDrafts.removeAll { $0.id == part.id } } label: { Image(systemName: "minus.circle") }
                        .help("Remove this part")
                }
            }
            HStack {
                Button { partDrafts.append(ComboPartDraft(label: "", expression: "")) } label: { Image(systemName: "plus.circle") }
                    .help("Add a part")
                Button { saveCombo() } label: { Image(systemName: "checkmark") }
                    .disabled(!draftsValid)
                    .help("Save macro")
                Button { editing = false } label: { Image(systemName: "xmark") }
                    .help("Discard edits")
            }
        }
    }

    public var body: some View {
        HStack {
            if editing {
                if editingCombo {
                    comboEditor
                } else {
                TextField("Name", text: $nameDraft)
                    .textFieldStyle(InsetFieldStyle())
                    .frame(width: 140)
                TextField("Expression", text: $expressionDraft)
                    .textFieldStyle(InsetFieldStyle())
                    .frame(maxWidth: 220)
                Picker("", selection: $typeDraft) {
                    Text("No type").tag(DamageType?.none)
                    ForEach(DamageType.allCases, id: \.self) { Text($0.displayName).tag(DamageType?.some($0)) }
                }
                .labelsHidden()
                .frame(maxWidth: 110)
                .help("Damage-type tag: rolls from this macro note what they deal against resistance, immunity, and vulnerability")
                TextField("DC", text: $dcDraft)
                    .textFieldStyle(InsetFieldStyle())
                    .frame(width: 48)
                    .help("Target DC: history cards show whether rolls from this macro met it. Blank means no target.")
                Button { startCombo() } label: { Image(systemName: "square.stack.3d.up") }
                    .disabled((try? DiceExpression.parse(expressionDraft)) == nil)
                    .help("Make this a combo macro: one tap rolls each part in order")
                Button {
                    model.updateMacro(macro, name: nameDraft, expression: expressionDraft,
                                      damageType: typeDraft?.rawValue,
                                      targetDC: Int(dcDraft.trimmingCharacters(in: .whitespaces)))
                    editing = false
                } label: { Image(systemName: "checkmark") }
                    .disabled(!draftsValid)
                    .help("Save macro")
                Button { editing = false } label: { Image(systemName: "xmark") }
                    .help("Discard edits")
                }
            } else {
                Text(macro.name)
                    .font(Theme.Typeface.headline)
                    .foregroundStyle(Theme.ink)
                Text(macro.expression)
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.inkMuted)
                if let type = macro.damageType.flatMap({ DamageType(rawValue: $0) }) {
                    Text(type.displayName.lowercased())
                        .font(Theme.Typeface.captionSmall)
                        .foregroundStyle(Theme.accent)
                        .help("Damage-type tag: rolls note what they deal against defenses")
                }
                if let dc = macro.targetDC {
                    Text("DC \(dc)")
                        .font(Theme.Typeface.captionSmall)
                        .foregroundStyle(Theme.accent)
                        .help("Target DC: history cards show whether rolls from this macro met it")
                }
                Spacer()
                Button("Roll") { model.rollMacro(macro) }
                    .buttonStyle(RollButtonStyle())
                // 3.15.0: pin the macro to the top of its group.
                Button {
                    model.toggleMacroPin(macro)
                } label: {
                    Image(systemName: macro.pinned == true ? "pin.fill" : "pin")
                }
                    .foregroundStyle(macro.pinned == true ? Theme.accent : Theme.inkMuted)
                    .help(macro.pinned == true ? "Unpin macro" : "Pin macro to the top")
                Button {
                    nameDraft = macro.name
                    expressionDraft = macro.expression
                    typeDraft = macro.damageType.flatMap { DamageType(rawValue: $0) }
                    dcDraft = macro.targetDC.map(String.init) ?? ""
                    editingCombo = macro.parts != nil
                    partDrafts = macro.parts?.map {
                        ComboPartDraft(label: $0.label, expression: $0.expression,
                                       type: $0.damageType.flatMap { DamageType(rawValue: $0) })
                    } ?? []
                    editing = true
                } label: { Image(systemName: "pencil") }
                    .help("Edit macro")
                Button {
                    model.duplicateMacro(macro)
                } label: { Image(systemName: "doc.on.doc") }
                    .help("Duplicate macro")
                Button(role: .destructive) {
                    model.deleteMacro(macro)
                } label: { Image(systemName: "minus.circle") }
            }
        }
    }
}

/// Group checks (3.26.0): the whole roster attempts the same skill; each
/// participant's own conditions and exhaustion ride the plan, and the
/// summary panel is ephemeral - history carries the auditable rolls.
/// Encounter estimate (3.34.0): party thresholds derive from the roster's
/// levels; enemy strength is entered row by row, never inferred. The
/// verdict is a word plus the raw derivation - an estimate, not
/// adjudication.
public struct EncounterSectionView: View {
    @EnvironmentObject var model: AppModel
    @State private var startArmed = false
    @State private var awardArmed = false
    @State private var libraryOpen = false

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Gap.sm) {
            HStack {
                Text("Encounter estimate").font(.headline)
                    .help("Genre-standard difficulty estimate: party thresholds from roster levels, enemy XP from entered rows")
                Spacer()
                // Start fight (3.37.0): push the rows into the tracker as
                // individual CR'd entries. Replace semantics - arms a
                // confirm when a fight (or its leftovers) is on the tracker.
                if startArmed {
                    Button("Replace \(model.initiative.entries.count)") {
                        model.startFightFromPlanner()
                        startArmed = false
                    }
                    .controlSize(.small)
                    .help("Replace the tracker's entries with these enemies - the displaced tracker stays restorable (one level)")
                    Button("Cancel") { startArmed = false }
                        .controlSize(.small)
                } else {
                    Button("Start fight") {
                        if model.initiative.entries.isEmpty {
                            model.startFightFromPlanner()
                        } else {
                            startArmed = true
                        }
                    }
                    .controlSize(.small)
                    .disabled(!model.encounterLines.contains { $0.count > 0 && EncounterMath.xp(forCR: $0.cr) != nil })
                    .help("Replace the tracker with these enemies as individual entries - rolls flat (bonus 0); set bonuses at the table")
                }
                // Add to fight (3.39.0): append the rows to the current
                // fight - reinforcements. No confirm: non-destructive, and
                // the per-row remove is the undo.
                Button("Add to fight") { model.addToFightFromPlanner() }
                    .controlSize(.small)
                    .disabled(model.initiative.entries.isEmpty
                              || !model.encounterLines.contains { $0.count > 0 && EncounterMath.xp(forCR: $0.cr) != nil })
                    .help("Append these enemies to the current fight - reinforcements roll in at the bottom (with an empty tracker, use Start fight)")
                // Award XP (3.41.0): the fight's return edge - pay the
                // tracker's base XP to the roster. Arms a preview; the
                // award fires only from Apply inside the panel.
                Button("Award XP") { awardArmed.toggle() }
                    .controlSize(.small)
                    .disabled(!model.initiative.entries.contains { $0.cr != nil } || model.characters.isEmpty)
                    .help("Pay the fight's base XP to the roster - a preview lists every member's share; Apply is the second tap")
                Button("Add enemies") { model.addEncounterLine() }
                    .controlSize(.small)
                    .help("Add a row: how many enemies at what challenge rating")
            }
            if awardArmed {
                XPAwardPanelView(onClose: { awardArmed = false })
            }
            if model.characters.isEmpty {
                Text("Add characters to the roster for party thresholds.")
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.inkMuted)
            } else {
                Text("Party: " + model.characters.map { "\($0.name) L\($0.level)" }.joined(separator: ", "))
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.inkMuted)
            }
            ForEach($model.encounterLines) { $line in
                HStack(spacing: Theme.Gap.sm) {
                    Stepper("x\(line.count)", value: Binding(
                        get: { line.count },
                        set: { line.count = $0; model.saveEncounterLines() }
                    ), in: 0...40)
                    .frame(maxWidth: 140)
                    TextField("CR", text: Binding(
                        get: { EncounterMath.crText(line.cr) },
                        set: {
                            if let v = EncounterMath.parseCR($0) {
                                line.cr = v
                                model.saveEncounterLines()
                            }
                        }
                    ))
                    .textFieldStyle(InsetFieldStyle())
                    .frame(width: 56)
                    .help("Challenge rating: 0-30, or 1/8, 1/4, 1/2")
                    // 3.43.0: optional row label - named enemies flow into
                    // tracker names and numbering ("Gnolls" -> Gnolls #1).
                    TextField("Label", text: Binding(
                        get: { line.label },
                        set: { line.label = $0; model.saveEncounterLines() }
                    ))
                    .textFieldStyle(InsetFieldStyle())
                    .frame(width: 90)
                    .help("Optional row label: named enemies flow into tracker names (\"Gnolls\" -> Gnolls #1, #2)")
                    if let xp = EncounterMath.xp(forCR: line.cr) {
                        Text("\(xp * line.count) XP")
                            .font(Theme.Typeface.caption)
                            .foregroundStyle(Theme.inkMuted)
                    } else {
                        Text("unknown CR")
                            .font(Theme.Typeface.caption)
                            .foregroundStyle(Theme.danger)
                    }
                    Spacer()
                    Button(role: .destructive) { model.removeEncounterLine(line) }
                        label: { Image(systemName: "minus.circle") }
                        .controlSize(.small)
                }
            }
            if let est = model.encounterEstimate {
                let t = est.thresholds
                Text("\(est.band.displayName) - adjusted \(est.adjustedXP.formatted()) XP (base \(est.baseXP.formatted()) x \(est.multiplier.formatted()))")
                    .font(Theme.Typeface.body.bold())
                Text("Thresholds: Easy \(t.easy.formatted()) - Medium \(t.medium.formatted()) - Hard \(t.hard.formatted()) - Deadly \(t.deadly.formatted())")
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.inkMuted)
                Text("Estimate from levels and ratings only - terrain, synergy, magic items, and table feel aren't in it.")
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.inkMuted)
            } else if !model.encounterLines.isEmpty {
                Text("No valid enemy rows yet - set a count and a known CR.")
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.inkMuted)
            }
            // Live fight (3.36.0): derived from the initiative tracker's
            // CRs - the fight actually lined up, not a second entry surface.
            if let live = model.liveFightEstimate {
                Text("Live fight").font(.headline)
                    .help("Derived from the initiative tracker's challenge ratings - entered there once, never duplicated")
                Text("\(live.band.displayName) - adjusted \(live.adjustedXP.formatted()) XP (base \(live.baseXP.formatted()) x \(live.multiplier.formatted()))")
                    .font(Theme.Typeface.body.bold())
                Text("From initiative: \(model.initiative.crBreakdown)")
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.inkMuted)
                if model.initiative.entriesWithoutCR > 0 {
                    Text("\(model.initiative.entriesWithoutCR) entries without CR excluded from the estimate.")
                        .font(Theme.Typeface.caption)
                        .foregroundStyle(Theme.inkMuted)
                }
            }
            // Encounter library (3.43.0): saved encounters ride a chevron
            // so the section stays lean; the content is its own view so
            // the harness can render it expanded.
            Button(action: { libraryOpen.toggle() }) {
                HStack(spacing: Theme.Gap.xs) {
                    Image(systemName: libraryOpen ? "chevron.down" : "chevron.right")
                        .font(.caption)
                    Text("Saved encounters (\(model.savedEncounters.count))")
                        .font(Theme.Typeface.caption)
                }
                .foregroundStyle(Theme.inkMuted)
            }
            .buttonStyle(.plain)
            if libraryOpen {
                EncounterLibraryView()
            }
        }
    }
}

public struct GroupCheckSectionView: View {
    @EnvironmentObject var model: AppModel
    @State private var rollKind = 0 // 0 = skill check, 1 = saving throw (3.31.0)
    /// 3.47.0: party damage/heal amount draft; display-only.
    @State private var partyAmount = ""

    /// The party HP amount (3.47.0); 0 when the draft is blank or not a
    /// number, which disables both buttons (same discipline as barTargetDC).
    private var partyAmountValue: Int {
        Int(partyAmount.trimmingCharacters(in: .whitespaces)) ?? 0
    }
    /// 3.51.0: party-condition rounds draft; blank or not a positive
    /// number means an untimed apply (which never kills a running clock).
    @State private var partyCondRounds = ""
    private var partyCondRoundsValue: Int? {
        let v = Int(partyCondRounds.trimmingCharacters(in: .whitespaces)) ?? 0
        return v > 0 ? v : nil
    }
    /// 3.58.0: party-condition note draft - "why they have it". Attaches on
    /// apply; blank keeps any existing note (same discipline as blank rounds).
    @State private var partyCondNote = ""
    @State private var skillPick = "Stealth"
    @State private var abilityPick: Ability = .wisdom
    @State private var dcDraft = ""

    public init() {}

    /// The selected character's skill names, else the default list.
    private var skillNames: [String] {
        let names = model.selected?.wrappedValue.skills.map(\.name) ?? []
        return names.isEmpty ? Skill.defaultList.map(\.name) : names
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Gap.sm) {
            HStack {
                Text(rollKind == 0 ? "Group check" : "Group save").font(.headline)
                    .help("Roll the same test for every roster character - the group succeeds when half or more beat the DC")
                Spacer()
                Picker("", selection: $rollKind) {
                    Text("Check").tag(0)
                    Text("Save").tag(1)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 130)
                if rollKind == 0 {
                    Picker("", selection: $skillPick) {
                        ForEach(skillNames, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 150)
                } else {
                    Picker("", selection: $abilityPick) {
                        ForEach(Ability.allCases, id: \.self) { Text($0.abbreviation).tag($0) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 90)
                }
                TextField("DC", text: $dcDraft)
                    .textFieldStyle(InsetFieldStyle())
                    .frame(width: 56)
                    .help("Optional - without one, results list totals with no verdict")
                Button("Roll") {
                    let dc = Int(dcDraft.trimmingCharacters(in: .whitespaces))
                    if rollKind == 0 {
                        model.rollGroupCheck(skillName: skillPick, targetDC: dc)
                    } else {
                        model.rollGroupSave(ability: abilityPick, targetDC: dc)
                    }
                }
                .buttonStyle(RollButtonStyle())
                .disabled(model.characters.isEmpty)
                .help("Roll for all \(model.characters.count) roster characters")
            }
            // Party rest (3.45.0): the DM says "you rest" to the party.
            // Each member rides their own undo stack (the award path);
            // recovery-direction, so no confirm - matching the
            // per-character rest buttons.
            HStack(spacing: Theme.Gap.sm) {
                Button("Short rest (party)") { model.restParty(long: false) }
                    .controlSize(.small)
                    .disabled(model.characters.isEmpty)
                    .help("Short rest for all \(model.characters.count) roster characters - pact slots and short-rest features recharge; timed conditions run out")
                Button("Long rest (party)") { model.restParty(long: true) }
                    .controlSize(.small)
                    .disabled(model.characters.isEmpty)
                    .help("Long rest for all \(model.characters.count) roster characters - HP, slots, hit dice, exhaustion per the era preset; timed conditions clear")
            }
            // Party damage/heal (3.47.0): "the fireball hits everyone for
            // 26". The rest row's exact discipline - own undo stacks,
            // temp-HP absorption, 0-HP floor, no confirm.
            HStack(spacing: Theme.Gap.sm) {
                TextField("Amount", text: $partyAmount)
                    .textFieldStyle(InsetFieldStyle())
                    .frame(width: 72) // 3.48.0: 56 clipped the placeholder
                Button("Damage (party)") { model.adjustPartyHP(amount: partyAmountValue, damage: true) }
                    .controlSize(.small)
                    .disabled(partyAmountValue <= 0 || model.characters.isEmpty)
                    .help("Damage all \(model.characters.count) roster characters - temp HP absorbs, floor at 0, undo restores")
                Button("Heal (party)") { model.adjustPartyHP(amount: partyAmountValue, damage: false) }
                    .controlSize(.small)
                    .disabled(partyAmountValue <= 0 || model.characters.isEmpty)
                    .help("Heal all \(model.characters.count) roster characters - capped at max HP, undo restores")
                // Party condition (3.51.0): "the shove lands on everyone".
                // Same discipline as party damage/heal - own undo stacks,
                // no confirm. Rounds blank = untimed apply.
                TextField("Rounds", text: $partyCondRounds)
                    .textFieldStyle(InsetFieldStyle())
                    .frame(width: 72) // 56 clipped the placeholder, same fix as 3.48.0's Amount field
                TextField("Note", text: $partyCondNote)
                    .textFieldStyle(InsetFieldStyle())
                    .frame(width: 72) // 3.59.0: 120 clipped the row's labels at narrow widths; "Note" is 4 chars, drafts scroll
                    .help("Why they have it - attaches on apply (max 24 chars); blank keeps any existing note")
                // 3.59.0: title shortened to reclaim the header - the party
                // semantics live in the sections below and the help text.
                Menu("Condition") {
                    // 3.56.0: apply is scoped too - "Everyone" (3.51.0, byte-
                    // identical path) or one item per roster character.
                    // Apply lists EVERYONE (granting is the point); remove
                    // lists only holders. Rounds feeds every apply path.
                    Section("Apply") {
                        ForEach(Condition.allCases, id: \.self) { cond in
                            Menu(cond.displayName) {
                                Button("Everyone") { model.applyPartyCondition(cond, rounds: partyCondRoundsValue, note: partyCondNote) }
                                if !model.characters.isEmpty {
                                    Divider()
                                    ForEach(model.characters) { target in
                                        Button(target.name) { model.applyPartyCondition(cond, rounds: partyCondRoundsValue, note: partyCondNote, from: [target.id]) }
                                    }
                                }
                            }
                        }
                        // 3.60.0: roster customs join the section after the
                        // built-ins - same submenu shape, name identity;
                        // customs are born in the per-character editor.
                        let applyCustomNames = model.partyCustomConditionNames
                        if !applyCustomNames.isEmpty {
                            Divider()
                            ForEach(applyCustomNames, id: \.self) { customName in
                                Menu(customName) {
                                    Button("Everyone") { model.applyPartyCustomCondition(name: customName, rounds: partyCondRoundsValue, note: partyCondNote) }
                                    if !model.characters.isEmpty {
                                        Divider()
                                        ForEach(model.characters) { target in
                                            Button(target.name) { model.applyPartyCustomCondition(name: customName, rounds: partyCondRoundsValue, note: partyCondNote, from: [target.id]) }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    // 3.52.0: the remove sibling - clears the condition and
                    // its clock; Rounds does not apply.
                    // 3.55.0: removal is scoped - "Everyone" (3.52.0) or one
                    // item per current holder, derived live so names never
                    // go stale. Section retitled to match.
                    Section("Remove") {
                        ForEach(Condition.allCases, id: \.self) { cond in
                            Menu(cond.displayName) {
                                Button("Everyone") { model.removePartyCondition(cond) }
                                let holders = model.characters.filter { $0.conditions.contains(cond) }
                                if !holders.isEmpty {
                                    Divider()
                                    ForEach(holders) { holder in
                                        Button(holder.name) { model.removePartyCondition(cond, from: [holder.id]) }
                                    }
                                }
                            }
                        }
                        // 3.60.0: custom removal mirrors the built-ins -
                        // "Everyone" or one item per current holder, live.
                        let removeCustomNames = model.partyCustomConditionNames
                        if !removeCustomNames.isEmpty {
                            Divider()
                            ForEach(removeCustomNames, id: \.self) { customName in
                                Menu(customName) {
                                    Button("Everyone") { model.removePartyCustomCondition(name: customName) }
                                    let customHolders = model.characters.filter { $0.customConditions.contains { $0.name == customName } }
                                    if !customHolders.isEmpty {
                                        Divider()
                                        ForEach(customHolders) { holder in
                                            Button(holder.name) { model.removePartyCustomCondition(name: customName, from: [holder.id]) }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .controlSize(.small)
                .disabled(model.characters.isEmpty)
                .help("Apply a condition to all \(model.characters.count) roster characters - never stacks; rounds refresh timers, blank rounds keeps them; undo restores")
            }
            // Party condition summary (3.53.0): who's holding what plus
            // clocks, at a glance. Read-only, derived from stored state;
            // hidden when the roster holds nothing.
            // 3.54.0: segments are tappable - a name click-through lands
            // on that character's sheet (read-only navigation).
            let partyCondItems = partyConditionSummaryItems(model.characters)
            if !partyCondItems.isEmpty {
                HStack(spacing: 4) {
                    ForEach(Array(partyCondItems.enumerated()), id: \.element.id) { idx, item in
                        if idx > 0 {
                            Text("\u{00B7}")
                                .font(.caption)
                                .foregroundStyle(Theme.inkFaint)
                        }
                        Button {
                            model.revealOnSheet(item.characterID)
                        } label: {
                            // 3.57.0: expiring labels (clock at 1) render in
                            // accent; everything else stays muted. Same line,
                            // same density - a glance, not a billboard.
                            item.parts.enumerated().reduce(Text("\(item.name): ").font(.caption).foregroundStyle(Theme.inkMuted)) { acc, pair in
                                let (idx, part) = pair
                                // 3.58.0: the note rides the label in faint -
                                // never accent, which stays reserved for expiring.
                                var line = acc + Text(idx == 0 ? part.label : ", \(part.label)").font(.caption)
                                    .foregroundStyle(part.expiring ? Theme.accent : Theme.inkMuted)
                                if let note = part.note {
                                    line = line + Text(" (\(note))").font(.caption).foregroundStyle(Theme.inkFaint)
                                }
                                return line
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Open \(item.name)'s sheet")
                    }
                }
            }
            if let outcome = model.lastGroupCheck {
                VStack(alignment: .leading, spacing: Theme.Gap.xs) {
                    ForEach(outcome.lines, id: \.name) { line in
                        HStack(spacing: Theme.Gap.sm) {
                            Text(line.name)
                            Spacer()
                            if !line.tags.isEmpty {
                                Text(line.tags.joined(separator: "; "))
                                    .foregroundStyle(Theme.inkMuted)
                            }
                            Text("\(line.total)")
                                .foregroundStyle(Theme.accent)
                            if let passed = line.passed {
                                Text(passed ? "met" : "missed")
                                    .foregroundStyle(passed ? Theme.accent : Theme.inkMuted)
                            }
                        }
                    }
                    if let verdict = outcome.verdictLine {
                        Text(verdict)
                            .foregroundStyle(Theme.accent)
                    }
                }
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.ink)
            }
        }
    }
}

/// The initiative tracker (3.22.0): order, the active turn, and the
/// round. Rolls stay here - they never record to History.
public struct InitiativeSectionView: View {
    @EnvironmentObject var model: AppModel
    @State private var nameDraft = ""
    @State private var bonusDraft = ""
    @State private var crDraft = ""
    @State private var restoreArmed = false

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Gap.sm) {
            HStack {
                Text("Initiative").font(.headline)
                Text("Round \(model.initiative.round)")
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.accent)
                Spacer()
                Button("Roll all") { model.rollInitiative() }
                    .buttonStyle(RollButtonStyle())
                    .disabled(model.initiative.entries.isEmpty)
                    .help("Roll 1d20 + bonus for every entry - stays out of History")
                Button("Next") { model.advanceInitiative() }
                    .buttonStyle(RollButtonStyle())
                    .disabled(model.initiative.rolledOrder.count < 2)
                    .help("Advance the turn; wrapping the list increments the round")
                Button("End combat") { model.endCombat() }
                    .buttonStyle(RollButtonStyle())
                    .disabled(model.initiative.entries.isEmpty)
                    .help("Clear totals and the round; entries stay for the rerun - a fight that ran files a recap to the selected character's journal")
                // Restore pre-fight (3.44.0): the tracker Start fight
                // displaced is one armed confirm away. Consumed on use.
                if model.initiative.preFightSnapshot != nil {
                    if restoreArmed {
                        Button("Restore?") {
                            model.restorePreFight()
                            restoreArmed = false
                        }
                        .buttonStyle(RollButtonStyle())
                        .help("Replace the current fight with the displaced tracker - the snapshot is consumed")
                        Button("Cancel") { restoreArmed = false }
                            .buttonStyle(RollButtonStyle())
                    } else {
                        Button("Restore pre-fight") { restoreArmed = true }
                            .buttonStyle(RollButtonStyle())
                            .help("Bring back the tracker Start fight replaced - one level, consumed on use")
                    }
                }
            }
            ForEach(model.initiative.ordered) { entry in
                InitiativeRowView(entry: entry,
                                  active: model.initiative.activeID == entry.id)
            }
            HStack {
                TextField("Name", text: $nameDraft)
                    .textFieldStyle(InsetFieldStyle())
                    .frame(width: 140)
                TextField("Bonus", text: $bonusDraft)
                    .textFieldStyle(InsetFieldStyle())
                    .frame(width: 56)
                TextField("CR", text: $crDraft)
                    .textFieldStyle(InsetFieldStyle())
                    .frame(width: 48)
                    .help("Challenge rating (optional) - feeds the live-fight estimate")
                Button("Add") {
                    model.addInitiativeEntry(name: nameDraft,
                                             bonus: Int(bonusDraft.trimmingCharacters(in: .whitespaces)) ?? 0,
                                             cr: EncounterMath.parseCR(crDraft))
                    nameDraft = ""
                    bonusDraft = ""
                    crDraft = ""
                }
                .buttonStyle(RollButtonStyle())
                .disabled(nameDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                if let name = model.selected?.wrappedValue.name {
                    Button("Add \(name)") { model.addSelectedToInitiative() }
                        .buttonStyle(RollButtonStyle())
                        .help("Link the selected character - pulls the sheet's live initiative bonus")
                }
                // Add party (3.40.0): the whole roster in one click, live
                // bonuses and links; names already on the tracker skip.
                Button("Add party") { model.addRosterToInitiative() }
                    .buttonStyle(RollButtonStyle())
                    .disabled(model.characters.isEmpty)
                    .help("Add every roster character with their live bonus - skips ones already on the tracker")
            }
        }
    }
}

/// One combatant row: active marker, name, bonus, editable total, reroll.
public struct InitiativeRowView: View {
    @EnvironmentObject var model: AppModel
    let entry: InitiativeEntry
    let active: Bool
    @State private var totalDraft: String
    @State private var crDraft: String
    @State private var renaming = false
    @State private var nameDraft: String
    @State private var bonusDraft: String

    public init(entry: InitiativeEntry, active: Bool) {
        self.entry = entry
        self.active = active
        _totalDraft = State(initialValue: entry.total.map(String.init) ?? "")
        _crDraft = State(initialValue: entry.cr.map { EncounterMath.crText($0) } ?? "")
        _nameDraft = State(initialValue: entry.name)
        _bonusDraft = State(initialValue: signed(entry.bonus))
    }

    public var body: some View {
        HStack {
            Image(systemName: active ? "arrowtriangle.right.fill" : "circle")
                .font(Theme.Typeface.captionSmall)
                .foregroundStyle(active ? Theme.accent : Theme.inkFaint)
            if renaming {
                TextField("Name", text: $nameDraft)
                    .textFieldStyle(InsetFieldStyle())
                    .frame(width: 140)
                    .onSubmit {
                        model.renameInitiativeEntry(entry, name: nameDraft)
                        renaming = false
                    }
            } else {
                Text(entry.name)
                    .font(Theme.Typeface.headline)
                    .foregroundStyle(Theme.ink)
            }
            TextField("", text: $bonusDraft)
                .textFieldStyle(InsetFieldStyle())
                .frame(width: 44)
                .onSubmit {
                    let trimmed = bonusDraft.trimmingCharacters(in: .whitespaces)
                    model.setInitiativeBonus(entry, bonus: Int(trimmed))
                }
                .help("Initiative bonus - drives Roll all and tie-breaks; blank or invalid keeps the current value")
            TextField("CR", text: $crDraft)
                .textFieldStyle(InsetFieldStyle())
                .frame(width: 44)
                .onSubmit {
                    let trimmed = crDraft.trimmingCharacters(in: .whitespaces)
                    model.setInitiativeCR(entry, cr: trimmed.isEmpty ? nil : EncounterMath.parseCR(trimmed))
                }
                .help("Challenge rating - feeds the live-fight estimate; blank excludes the entry")
            Spacer()
            TextField("", text: $totalDraft)
                .textFieldStyle(InsetFieldStyle())
                .frame(width: 48)
                .onSubmit {
                    let trimmed = totalDraft.trimmingCharacters(in: .whitespaces)
                    model.setInitiativeTotal(entry, total: trimmed.isEmpty ? nil : Int(trimmed))
                }
                .help("Rolled total - edit by hand if the table rolled physically")
            Button { nameDraft = entry.name; renaming = true } label: { Image(systemName: "pencil") }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.inkFaint)
                .help("Rename this entry - blank keeps the current name")
            Button { model.rerollInitiative(entry) } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.inkFaint)
                .help("Reroll this entry")
            Button { model.removeInitiativeEntry(entry) } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.inkFaint)
                .help("Remove from the tracker")
        }
        .padding(.horizontal, Theme.Gap.sm)
        .padding(.vertical, 3)
        .background(active ? Theme.surfaceRaised : Color.clear,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }
}

/// A styled history entry: label, per-die chips (dropped dice struck out),
/// advantage alternate, and a crit glow on natural 20s / 1s.
struct RollCard: View {
    @EnvironmentObject var model: AppModel
    let roll: RollResult
    /// 2.82.0: inline label editing - the pencil swaps the title for a
    /// field; blank restores the expression as the title.
    @State private var editingLabel = false
    @State private var labelDraft = ""
    /// 2.92.0: inline note editing - the note button swaps in a field;
    /// blank clears the note.
    @State private var editingNote = false
    @State private var noteDraft = ""

    private var crit: Bool {
        roll.dice.contains { $0.sides == 20 && $0.kept && $0.value == 20 }
    }
    private var fumble: Bool {
        roll.dice.contains { $0.sides == 20 && $0.kept && $0.value == 1 }
    }

    var body: some View {
        HStack(spacing: Theme.Gap.md) {
            VStack(alignment: .leading, spacing: 3) {
                if editingLabel {
                    TextField("Roll label", text: $labelDraft)
                        .textFieldStyle(InsetFieldStyle())
                        .frame(width: 180)
                        .onSubmit {
                            model.renameRoll(roll, to: labelDraft)
                            editingLabel = false
                        }
                } else {
                    Text(roll.label ?? roll.expression)
                        .font(Theme.Typeface.body.bold())
                        .foregroundStyle(Theme.ink)
                }
                HStack(spacing: 4) {
                    if roll.label != nil {
                        Text(roll.expression)
                            .font(Theme.Typeface.captionSmall)
                            .foregroundStyle(Theme.inkFaint)
                    }
                    ForEach(roll.dice.indices, id: \.self) { i in
                        dieChip(roll.dice[i])
                    }
                    if roll.modifier != 0 {
                        Text(signed(roll.modifier))
                            .font(Theme.Typeface.caption.monospacedDigit())
                            .foregroundStyle(Theme.inkMuted)
                    }
                }
                // 2.92.0: the story behind the roll, under the label.
                if editingNote {
                    TextField("Note", text: $noteDraft)
                        .textFieldStyle(InsetFieldStyle())
                        .frame(width: 220)
                        .onSubmit {
                            model.noteRoll(roll, to: noteDraft)
                            editingNote = false
                        }
                } else if let note = roll.note {
                    Text(note)
                        .font(Theme.Typeface.captionSmall.italic())
                        .foregroundStyle(Theme.inkMuted)
                }
            }
            Spacer()
            if let rolledAt = roll.rolledAt {
                Text(RollResult.historyTimeFormatter.string(from: rolledAt))
                    .font(Theme.Typeface.captionSmall.monospacedDigit())
                    .foregroundStyle(Theme.inkFaint)
                    .help(rolledAt.formatted(date: .abbreviated, time: .shortened))
            }
            // 2.40.0 roll-again: every card except incoming damage (rolling
            // again is not taking more damage).
            if roll.reroll?.kind != .incomingDamage {
                Button {
                    model.rollAgain(roll)
                } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.inkFaint)
                    .help(roll.reroll == nil
                        ? "Roll \(roll.expression) again - right-click for variants"
                        : "Roll again - condition tags and defense notes recompute; right-click for variants")
                    // 2.43.0 reroll variants: right-click offers mode flips
                    // for checks and +/-2 for anything rerollable.
                    .contextMenu {
                        ForEach(RerollVariant.available(for: roll.reroll?.kind ?? .plain), id: \.self) { variant in
                            Button(variant.displayName) { model.rollAgain(roll, variant: variant) }
                        }
                    }
            }
            // 3.19.0: apply the roll to the selected character's HP.
            // Plain click applies damage (the recorded type folds
            // defenses in); the menu offers healing. Incoming-damage
            // cards are excluded - that damage already landed.
            if roll.reroll?.kind != .incomingDamage,
               let applyTarget = model.selected?.wrappedValue.name {
                Button {
                    model.applyRollToHP(roll, healing: false)
                } label: { Image(systemName: "heart") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.inkFaint)
                    .help("Apply as damage to \(applyTarget) - right-click for healing")
                    .contextMenu {
                        Button(hpApplyMenuLabel(amount: roll.total,
                                                type: roll.reroll?.damageType.flatMap { DamageType(rawValue: $0) },
                                                healing: false, characterName: applyTarget)) {
                            model.applyRollToHP(roll, healing: false)
                        }
                        Button(hpApplyMenuLabel(amount: roll.total, type: nil,
                                                healing: true, characterName: applyTarget)) {
                            model.applyRollToHP(roll, healing: true)
                        }
                    }
            }
            // 2.84.0: star the memorable ones by hand.
            Button { model.toggleStar(roll) }
                label: { Image(systemName: roll.starred == true ? "star.fill" : "star") }
                .buttonStyle(.plain)
                .foregroundStyle(roll.starred == true ? Theme.accent : Theme.inkFaint)
                .help(roll.starred == true ? "Unstar this roll" : "Star this roll")
            // 2.82.0: rename the label in place.
            Button {
                labelDraft = roll.label ?? ""
                editingLabel = true
            } label: { Image(systemName: "pencil") }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.inkFaint)
                .help("Rename this roll's label")
            // 2.92.0: add or edit the roll's note - the story the short
            // label leaves out.
            Button {
                noteDraft = roll.note ?? ""
                editingNote = true
            } label: { Image(systemName: "note.text") }
                .buttonStyle(.plain)
                .foregroundStyle(roll.note == nil ? Theme.inkFaint : Theme.inkMuted)
                .help(roll.note == nil ? "Add a note to this roll" : "Edit this roll's note")
            // 2.83.0: copy just this roll's line.
            Button { model.copyRollToPasteboard(roll) }
                label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.inkFaint)
                .help("Copy this roll as text")
            // 2.45.0: with auto-log on the roll is already journaled.
            if !model.autoLogRollsToJournal {
                Button {
                    model.addRollToJournal(roll)
                } label: { Image(systemName: "square.and.pencil") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.inkFaint)
                    .help("Add this roll to the journal")
                    .disabled(model.selected == nil)
            }
            // 2.79.0: remove a mis-rolled entry without clearing the
            // whole history (Clear stays all-or-nothing).
            Button {
                model.deleteRoll(roll)
            } label: { Image(systemName: "trash") }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.inkFaint)
                .help("Remove this roll from history")
            if let alt = roll.alternateTotal {
                Text("\(alt)")
                    .font(Theme.Typeface.caption.monospacedDigit())
                    .foregroundStyle(Theme.inkFaint)
                    .strikethrough()
                    .help("The die not taken")
            }
            // 3.20.0: the target badge, derived from the recorded DC
            // and total - met in the crit green, missed in the fumble red.
            if let badge = targetBadgeLabel(for: roll) {
                Text(badge)
                    .font(Theme.Typeface.caption.monospacedDigit())
                    .foregroundStyle(targetOutcome(for: roll) == .met ? Theme.success : Theme.danger)
            }
            Text("\(roll.total)")
                .font(Theme.Typeface.statBig.monospacedDigit())
                .foregroundStyle(crit ? Theme.success : fumble ? Theme.danger : Theme.accent)
        }
        .padding(.horizontal, Theme.Gap.md)
        .padding(.vertical, Theme.Gap.sm)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(crit ? Theme.success.opacity(0.5) : fumble ? Theme.danger.opacity(0.5) : Theme.edge,
                        lineWidth: crit || fumble ? 1.5 : 0.5)
        )
    }

    private func dieChip(_ die: DieResult) -> some View {
        Text("\(die.value)")
            .font(Theme.Typeface.caption.monospacedDigit())
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(die.kept ? Theme.surfaceInset : Color.clear,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .stroke(die.kept ? Theme.accent.opacity(0.35) : Theme.edge, lineWidth: 0.5)
            )
            .foregroundStyle(die.kept ? Theme.ink : Theme.inkFaint)
            .strikethrough(!die.kept)
            .help("d\(die.sides)\(die.kept ? "" : " (dropped)")")
    }
}

/// 3.7.0: the inline reason a preset name can't be used.
private func presetNameIssueMessage(_ issue: FilterPresetNameIssue) -> String {
    switch issue {
    case .blank:
        return "Enter a preset name."
    case .taken(let name):
        return "\"\(name)\" is already saved."
    }
}
/// Award XP preview panel (3.41.0): every roster member listed, all
/// checked by default; unchecking re-splits among the rest live. The pool
/// derives from the tracker's challenge ratings - base pays, adjusted
/// stays the budgeting yardstick, and the header names both. Apply is the
/// second tap; the award never fires on arm.
public struct XPAwardPanelView: View {
    @EnvironmentObject var model: AppModel
    @State private var mode: XPAwardPlan.Mode = .equalSplit
    @State private var excluded: Set<UUID> = []
    public var onClose: () -> Void

    public init(onClose: @escaping () -> Void = {}) { self.onClose = onClose }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Gap.xs) {
            if let plan = model.xpAwardPlan(mode: mode, excluded: excluded) {
                Text("Award \(plan.baseXP.formatted()) XP base (adjusted \(Int(plan.adjustedXP.rounded()).formatted()))")
                    .font(Theme.Typeface.body.bold())
                    .help("Raw XP is the payout; the count multiplier budgets difficulty and is not paid")
                Picker("Split", selection: $mode) {
                    Text("Split evenly").tag(XPAwardPlan.Mode.equalSplit)
                    Text("Full pool each").tag(XPAwardPlan.Mode.fullPool)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 280)
                ForEach(plan.shares) { share in
                    HStack(spacing: Theme.Gap.sm) {
                        Toggle(isOn: Binding(
                            get: { !excluded.contains(share.id) },
                            set: { on in
                                if on { excluded.remove(share.id) } else { excluded.insert(share.id) }
                            }
                        )) {
                            Text("\(share.name): \(share.currentXP.formatted()) + \(share.amount.formatted()) = \(share.newXP.formatted())")
                                .font(Theme.Typeface.caption.monospacedDigit())
                        }
                        .toggleStyle(.checkbox)
                        if share.included && share.levelsUp {
                            Text("LEVEL UP -> L\(share.newLevel)")
                                .font(Theme.Typeface.caption.bold())
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }
                if model.initiative.entriesWithoutCR > 0 {
                    Text("\(model.initiative.entriesWithoutCR) tracker entries carry no challenge rating and pay nothing.")
                        .font(Theme.Typeface.caption)
                        .foregroundStyle(Theme.inkFaint)
                }
                HStack(spacing: Theme.Gap.sm) {
                    Button("Apply") {
                        model.awardFightXP(mode: mode, excluded: excluded)
                        onClose()
                    }
                    .buttonStyle(RollButtonStyle())
                    .help("Pay each checked member - one undo step per character, like any sheet edit; applying again pays again")
                    Button("Cancel") { onClose() }
                        .controlSize(.small)
                }
            } else {
                Text("Nothing to pay - check at least one member and line up a fight with challenge ratings.")
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.inkMuted)
                Button("Cancel") { onClose() }
                    .controlSize(.small)
            }
        }
    }
}

/// The table log (3.45.0): the party-level session record - manual notes
/// and the fight recap's second home, newest first. Deletes arm inline;
/// the log is not a character, so there is no undo stack.
public struct TableLogView: View {
    @EnvironmentObject var model: AppModel
    @State private var titleDraft = ""
    @State private var textDraft = ""
    @State private var deleteArmedID: UUID?
    /// 3.49.0: which entry is being edited, plus its drafts.
    @State private var editingID: UUID?
    @State private var editTitleDraft = ""
    @State private var editTextDraft = ""

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Gap.xs) {
            HStack(spacing: Theme.Gap.sm) {
                Text("Table log").font(.headline)
                    .help("The party's shared session record - manual notes and fight recaps")
                Spacer()
                TextField("Title", text: $titleDraft)
                    .textFieldStyle(InsetFieldStyle())
                    .frame(maxWidth: 150)
                TextField("Note", text: $textDraft)
                    .textFieldStyle(InsetFieldStyle())
                    .frame(maxWidth: 200)
                Button("Add") {
                    model.addTableLogEntry(title: titleDraft, text: textDraft)
                    titleDraft = ""
                    textDraft = ""
                }
                .controlSize(.small)
                .disabled(titleDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          && textDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Add a note to the table log")
                // 3.47.0: copy the whole log as one text block.
                Button("Copy") { model.copyTableLogToPasteboard() }
                    .controlSize(.small)
                    .disabled(model.tableLog.isEmpty)
                    .help("Copy the whole table log as one text block")
            }
            ForEach(model.tableLog.sorted { $0.createdAt > $1.createdAt }) { entry in
                HStack(alignment: .firstTextBaseline, spacing: Theme.Gap.sm) {
                    if editingID == entry.id {
                        // 3.49.0: edit in place, mirroring the encounter-notes
                        // editor; commit on return from either field.
                        TextField("Title", text: $editTitleDraft, onCommit: {
                            model.editTableLogEntry(id: entry.id, title: editTitleDraft, text: editTextDraft)
                            editingID = nil
                        })
                        .textFieldStyle(InsetFieldStyle())
                        .frame(maxWidth: 150)
                        TextField("Note", text: $editTextDraft, onCommit: {
                            model.editTableLogEntry(id: entry.id, title: editTitleDraft, text: editTextDraft)
                            editingID = nil
                        })
                        .textFieldStyle(InsetFieldStyle())
                        .frame(maxWidth: 200)
                    } else {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: Theme.Gap.sm) {
                            Text(entry.title.isEmpty ? "Note" : entry.title)
                                .font(Theme.Typeface.caption)
                                .foregroundStyle(Theme.ink)
                            Text(JournalStamp.day(entry.createdAt))
                                .font(Theme.Typeface.caption)
                                .foregroundStyle(Theme.inkMuted)
                        }
                        if !entry.text.isEmpty {
                            Text(entry.text)
                                .font(Theme.Typeface.caption)
                                .foregroundStyle(Theme.inkMuted)
                                .lineLimit(2)
                        }
                    }
                    }
                    Spacer()
                    // 3.49.0: the pencil opens the inline editor.
                    if editingID != entry.id {
                        Button {
                            editTitleDraft = entry.title
                            editTextDraft = entry.text
                            editingID = entry.id
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.inkFaint)
                        .help("Edit this entry in place")
                    }
                    if deleteArmedID == entry.id {
                        Button("Delete?") {
                            model.deleteTableLogEntry(entry)
                            deleteArmedID = nil
                        }
                        .controlSize(.small)
                        .help("Remove this entry - no undo")
                        Button("Cancel") { deleteArmedID = nil }
                            .controlSize(.small)
                    } else {
                        Button { deleteArmedID = entry.id } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.inkMuted)
                        .help("Delete this entry (arms a confirm)")
                    }
                }
            }
        }
    }
}

/// The encounter library content (3.43.0): save the current rows under a
/// name, reload them later. Overwrite, load-replace, and delete each arm
/// an inline confirm - prep is rebuildable in theory but not experienced
/// that way at the table. The chevron header lives in
/// EncounterSectionView so the harness can render this content expanded.

public struct EncounterLibraryView: View {
    @EnvironmentObject var model: AppModel
    @State private var libraryName = ""
    @State private var saveArmed = false
    @State private var loadArmedID: UUID?
    @State private var deleteArmedID: UUID?
    /// 3.46.0: which row's tactics note is being edited, plus its draft.
    @State private var notesEditingID: UUID?
    @State private var notesDraft = ""
    /// 3.50.0: which row's name is being renamed, plus its draft.
    @State private var renameEditingID: UUID?
    @State private var renameDraft = ""

    /// initialRenameID opens a row's rename field directly (renders).
    public init(initialRenameID: UUID? = nil) {
        _renameEditingID = State(initialValue: initialRenameID)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Gap.xs) {
            HStack(spacing: Theme.Gap.sm) {
                TextField("Encounter name", text: $libraryName)
                    .textFieldStyle(InsetFieldStyle())
                    .frame(maxWidth: 180)
                if saveArmed {
                    Button("Overwrite?") {
                        model.saveEncounterAs(name: libraryName)
                        libraryName = ""
                        saveArmed = false
                    }
                    .controlSize(.small)
                    .help("Replace the saved encounter that has this name")
                    Button("Cancel") { saveArmed = false }
                        .controlSize(.small)
                } else {
                    Button("Save") {
                        if model.savedEncounterExists(named: libraryName.trimmingCharacters(in: .whitespaces)) {
                            saveArmed = true
                        } else {
                            model.saveEncounterAs(name: libraryName)
                            libraryName = ""
                        }
                    }
                    .controlSize(.small)
                    .disabled(libraryName.trimmingCharacters(in: .whitespaces).isEmpty
                              || model.encounterLines.isEmpty)
                    .help("Save the current rows under this name")
                }
            }
            ForEach(model.savedEncounters) { saved in
                VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Gap.sm) {
                    // 3.50.0: tap the name to rename in place - a typo'd
                    // save no longer costs a delete-and-resave.
                    Text(saved.name)
                        .font(Theme.Typeface.body)
                        .onTapGesture {
                            renameDraft = saved.name
                            renameEditingID = saved.id
                        }
                        .help("Click to rename")
                    Text(saved.summary)
                        .font(Theme.Typeface.caption)
                        .foregroundStyle(Theme.inkMuted)
                    // 3.48.0: the band re-derives from the CURRENT roster -
                    // "is Goblin Ambush still deadly now that we're 6th?"
                    if let band = model.savedEncounterBand(saved) {
                        Text(band.displayName)
                            .font(Theme.Typeface.caption)
                            .foregroundStyle(Theme.inkMuted)
                            .help("Difficulty vs the current roster's levels - re-derived, never stored")
                    }
                    Spacer()
                    // 3.46.0: tactics note - the pencil opens the inline
                    // editor below; a filled note shows a tinted pencil.
                    Button {
                        if notesEditingID == saved.id {
                            notesEditingID = nil
                        } else {
                            notesDraft = saved.notes
                            notesEditingID = saved.id
                        }
                    } label: {
                        Image(systemName: saved.notes.isEmpty ? "pencil" : "pencil.and.scribble")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(saved.notes.isEmpty ? Theme.inkFaint : Theme.accent)
                    .help("Edit tactics note")
                    // 3.49.0: copy the encounter as one text block.
                    Button("Copy") { model.copySavedEncounterToPasteboard(saved) }
                        .controlSize(.small)
                        .help("Copy this encounter as one text block - rows, band vs the current party, note")
                    // 3.50.0: duplicate - the copy carries rows and the
                    // tactics note, the start of a variant.
                    Button("Duplicate") { model.duplicateSavedEncounter(id: saved.id) }
                        .controlSize(.small)
                        .help("Save a copy with its rows and tactics note - lands as 'Name copy'")
                    if loadArmedID == saved.id {
                        Button("Replace \(model.encounterLines.count) rows") {
                            model.loadSavedEncounter(saved)
                            loadArmedID = nil
                        }
                        .controlSize(.small)
                        .help("Replace the current planner rows with this encounter")
                        Button("Cancel") { loadArmedID = nil }
                            .controlSize(.small)
                    } else {
                        Button("Load") {
                            if model.encounterLines.isEmpty {
                                model.loadSavedEncounter(saved)
                            } else {
                                loadArmedID = saved.id
                            }
                        }
                        .controlSize(.small)
                    }
                    if deleteArmedID == saved.id {
                        Button("Delete?") {
                            model.deleteSavedEncounter(saved)
                            deleteArmedID = nil
                        }
                        .controlSize(.small)
                    } else {
                        Button(role: .destructive) { deleteArmedID = saved.id }
                            label: { Image(systemName: "minus.circle") }
                            .controlSize(.small)
                    }
                }
                if renameEditingID == saved.id {
                    TextField("Encounter name", text: $renameDraft, onCommit: {
                        model.renameSavedEncounter(id: saved.id, name: renameDraft)
                        renameEditingID = nil
                    })
                    .textFieldStyle(InsetFieldStyle())
                    .onAppear { if renameDraft.isEmpty { renameDraft = saved.name } }
                }
                if notesEditingID == saved.id {
                    TextField("Tactics note (optional)", text: $notesDraft, onCommit: {
                        model.setSavedEncounterNotes(id: saved.id, notes: notesDraft)
                        notesEditingID = nil
                    })
                    .textFieldStyle(InsetFieldStyle())
                } else if !saved.notes.isEmpty {
                    Text(saved.notes)
                        .font(Theme.Typeface.caption)
                        .foregroundStyle(Theme.inkMuted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                }
            }
            if model.savedEncounters.isEmpty {
                Text("No saved encounters yet.")
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.inkFaint)
            }
        }
    }
}

#endif