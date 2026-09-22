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
                HStack {
                    Text(last.label ?? last.expression).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(last.total)")
                        .font(Theme.Typeface.statBig)
                        .foregroundStyle(Theme.accent)
                }
            }
            Text("Full roller and history on the Dice tab.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

public struct DiceRollerView: View {
    @EnvironmentObject var model: AppModel

    public init() {}
    @State private var expression = "2d6+3"
    @State private var d20Mode: RollMode = .normal
    @State private var d20Modifier = 0

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
            HStack {
                Text("History").font(.headline)
                Spacer()
                Button("Clear") { model.rollHistory.removeAll() }.controlSize(.small)
            }
            List(model.rollHistory.indices, id: \.self) { i in

                let r = model.rollHistory[i]
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r.label ?? r.expression)
                        if r.label != nil {
                            Text(r.expression).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 200, alignment: .leading)
                    Text(r.dice.map { $0.kept ? "\($0.value)" : "(\($0.value))" }.joined(separator: " "))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let alt = r.alternateTotal {
                        Text("(\(alt))").foregroundStyle(.secondary)
                    }
                    Text("\(r.total)")
                        .font(Theme.Typeface.headline.monospacedDigit())
                        .foregroundStyle(Theme.accent)
                }
                .listRowBackground(Theme.surfaceRaised)
            }
            .scrollContentBackground(.hidden)
        }
        .padding(Theme.Gap.lg)
        .background(Theme.surface)
    }
}
#endif
