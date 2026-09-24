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

    public init() {}
    @State private var expression = "2d6+3"
    @State private var d20Mode: RollMode = .normal
    @State private var d20Modifier = 0
    @State private var macroNameDraft = ""
    /// Free-roller damage type, persisted on the model across launches;
    /// nil keeps rolls untyped (no defense note).
    private var damageType: Binding<DamageType?> {
        Binding(get: { model.freeRollerDamageType }, set: { model.freeRollerDamageType = $0 })
    }
    /// Save scope for new macros: true binds them to the selected character.
    @State private var saveForCharacter = true
    /// History scope: false = whole table, true = selected character only.
    @State private var historyForCharacter = false
    /// Text filter over history labels and expressions; blank shows all.
    @State private var historyFilter = ""

    private var visibleHistory: [RollResult] {
        let name = historyForCharacter ? model.selected?.wrappedValue.name : nil
        return model.rollHistory.forCharacter(name).matching(historyFilter)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                TextField("Dice notation", text: $expression)
                    .textFieldStyle(InsetFieldStyle())
                    .frame(width: 200)
                    .onSubmit { model.rollFree(expression, type: damageType.wrappedValue) }
                Button("Roll") { model.rollFree(expression, type: damageType.wrappedValue) }
                    .buttonStyle(RollButtonStyle(prominent: true))
                    .keyboardShortcut(.return)
                Picker("", selection: damageType) {
                    Text("No type").tag(DamageType?.none)
                    ForEach(DamageType.allCases, id: \.self) { Text($0.displayName).tag(DamageType?.some($0)) }
                }
                .labelsHidden()
                .frame(maxWidth: 110)
                .help("Damage type: typed rolls note what they deal against resistance, immunity, and vulnerability. Remembered per character (or for the table when none is selected).")
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
                Button("Roll d20") { model.rollCheck("d20 roll", bonus: d20Modifier, mode: d20Mode) }
                    .buttonStyle(RollButtonStyle(prominent: true))
            }
            VStack(alignment: .leading, spacing: Theme.Gap.sm) {
                Text("Macros").font(.headline)
                let characterMacros = model.visibleMacros.filter { $0.characterName != nil }
                let tableMacros = model.visibleMacros.filter { $0.characterName == nil }
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
                TextField("Filter rolls", text: $historyFilter)
                    .textFieldStyle(InsetFieldStyle())
                    .frame(maxWidth: 160)
                if !historyFilter.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("\(visibleHistory.count) of \(model.rollHistory.forCharacter(historyForCharacter ? model.selected?.wrappedValue.name : nil).count)")
                        .font(Theme.Typeface.caption)
                        .foregroundStyle(Theme.inkMuted)
                }
                Spacer()
                // 2.45.0 auto-log: every roll also lands in the journal.
                Toggle("Journal", isOn: $model.autoLogRollsToJournal)
                    .controlSize(.small)
                    .help("Automatically add every roll to the journal")
                Button("Copy") { model.copyRollsToPasteboard(visibleHistory) }
                    .controlSize(.small)
                    .disabled(visibleHistory.isEmpty)
                    .help("Copy the shown rolls (scope and filter applied) as text, oldest first")
                Button("Clear") { model.clearRollHistory() }.controlSize(.small)
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

    /// Row identity namespaced by group: bare per-section offsets collide
    /// across sibling ForEaches inside a lazy stack, and SwiftUI drops the
    /// "duplicate" rows - which is exactly what the 2.38.0 renders showed
    /// (every later section rendered its header and no rows).
    private struct IndexedRoll: Identifiable {
        let id: String
        let roll: RollResult
    }

    public var body: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Gap.sm, pinnedViews: [.sectionHeaders]) {
                ForEach(Array(model.namedSessions(rolls).enumerated()), id: \.offset) { _, session in
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
                                // 2.70.0: copy the session as plain
                                // text - title, stats line, rolls.
                                Button { model.copySessionToPasteboard(session) }
                                    label: { Image(systemName: "doc.on.doc") }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(Theme.inkFaint)
                                    .help("Copy this session's rolls as text")
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

    public init(macro: DiceMacro, startEditing: Bool = false) {
        self.macro = macro
        _editing = State(initialValue: startEditing)
        _nameDraft = State(initialValue: macro.name)
        _expressionDraft = State(initialValue: macro.expression)
        _typeDraft = State(initialValue: macro.damageType.flatMap { DamageType(rawValue: $0) })
    }

    private var draftsValid: Bool {
        !nameDraft.trimmingCharacters(in: .whitespaces).isEmpty
            && (try? DiceExpression.parse(expressionDraft)) != nil
    }

    public var body: some View {
        HStack {
            if editing {
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
                Button {
                    model.updateMacro(macro, name: nameDraft, expression: expressionDraft,
                                      damageType: typeDraft?.rawValue)
                    editing = false
                } label: { Image(systemName: "checkmark") }
                    .disabled(!draftsValid)
                    .help("Save macro")
                Button { editing = false } label: { Image(systemName: "xmark") }
                    .help("Discard edits")
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
                Spacer()
                Button("Roll") { model.rollMacro(macro) }
                    .buttonStyle(RollButtonStyle())
                Button {
                    nameDraft = macro.name
                    expressionDraft = macro.expression
                    typeDraft = macro.damageType.flatMap { DamageType(rawValue: $0) }
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

/// A styled history entry: label, per-die chips (dropped dice struck out),
/// advantage alternate, and a crit glow on natural 20s / 1s.
struct RollCard: View {
    @EnvironmentObject var model: AppModel
    let roll: RollResult

    private var crit: Bool {
        roll.dice.contains { $0.sides == 20 && $0.kept && $0.value == 20 }
    }
    private var fumble: Bool {
        roll.dice.contains { $0.sides == 20 && $0.kept && $0.value == 1 }
    }

    var body: some View {
        HStack(spacing: Theme.Gap.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text(roll.label ?? roll.expression)
                    .font(Theme.Typeface.body.bold())
                    .foregroundStyle(Theme.ink)
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
            if let alt = roll.alternateTotal {
                Text("\(alt)")
                    .font(Theme.Typeface.caption.monospacedDigit())
                    .foregroundStyle(Theme.inkFaint)
                    .strikethrough()
                    .help("The die not taken")
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
#endif
