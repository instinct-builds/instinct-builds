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

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                TextField("Dice notation", text: $expression)
                    .textFieldStyle(InsetFieldStyle())
                    .frame(width: 200)
                    .onSubmit { model.roll(expression) }
                Button("Roll") { model.roll(expression) }
                    .buttonStyle(RollButtonStyle(prominent: true))
                    .keyboardShortcut(.return)
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
                ForEach(model.macros) { macro in
                    HStack {
                        Text(macro.name)
                            .font(Theme.Typeface.headline)
                            .foregroundStyle(Theme.ink)
                        Text(macro.expression)
                            .font(Theme.Typeface.caption)
                            .foregroundStyle(Theme.inkMuted)
                        Spacer()
                        Button("Roll") { model.roll(macro.expression) }
                            .buttonStyle(RollButtonStyle())
                        Button(role: .destructive) {
                            model.deleteMacro(named: macro.name)
                        } label: { Image(systemName: "minus.circle") }
                    }
                }
                HStack {
                    TextField("Macro name", text: $macroNameDraft)
                        .textFieldStyle(InsetFieldStyle())
                        .frame(width: 160)
                    Button("Save current as macro") {
                        model.saveMacro(name: macroNameDraft, expression: expression)
                        macroNameDraft = ""
                    }
                    .buttonStyle(RollButtonStyle())
                    .disabled(macroNameDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    .help("Bind the dice notation above to a reusable shortcut")
                }
            }
            HStack {
                Text("History").font(.headline)
                Spacer()
                Button("Clear") { model.clearRollHistory() }.controlSize(.small)
            }
            ScrollView {
                LazyVStack(spacing: Theme.Gap.sm) {
                    ForEach(model.rollHistory.indices, id: \.self) { i in
                        RollCard(roll: model.rollHistory[i])
                    }
                }
            }
        }
        .padding(Theme.Gap.lg)
        .background(Theme.surface)
        .preferredColorScheme(.dark)
    }
}

/// A styled history entry: label, per-die chips (dropped dice struck out),
/// advantage alternate, and a crit glow on natural 20s / 1s.
struct RollCard: View {
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
