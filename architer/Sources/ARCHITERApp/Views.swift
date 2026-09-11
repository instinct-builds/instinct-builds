#if os(macOS)
import SwiftUI
import ArchiterCore

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selectedID) {
                ForEach(model.characters) { c in
                    Label(c.name, systemImage: "person.crop.rectangle")
                        .tag(c.id)
                }
            }
            .navigationTitle("Characters")
            .toolbar {
                ToolbarItem { Button(action: model.newCharacter) { Image(systemName: "plus") } }
                ToolbarItem { Button(action: model.deleteSelected) { Image(systemName: "trash") } }
            }
        } detail: {
            if let binding = model.selected {
                CharacterDetailView(character: binding)
            } else {
                ContentUnavailableView("No Character", systemImage: "person.crop.rectangle",
                                       description: Text("Create a character to begin."))
            }
        }
    }
}

struct CharacterDetailView: View {
    @Binding var character: Character
    @EnvironmentObject var model: AppModel
    @State private var tab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("Sheet").tag(0)
                Text("Builder").tag(1)
                Text("Dice").tag(2)
            }
            .pickerStyle(.segmented)
            .padding()
            Divider()
            switch tab {
            case 0: SheetView(character: $character)
            case 1: BuilderView(layout: $character.layout)
            default: DiceRollerView()
            }
        }
    }
}

/// Renders the character sheet from its layout — order and visibility come
/// straight from the builder.
struct SheetView: View {
    @Binding var character: Character

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(character.layout.visibleBlocks) { block in
                    blockView(for: block)
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func blockView(for block: SheetBlock) -> some View {
        switch block.kind {
        case .identity: IdentityBlock(character: $character)
        case .abilities: AbilitiesBlock(character: $character)
        case .vitals: VitalsBlock(character: $character)
        case .skills: SkillsBlock(character: $character)
        case .attacks: AttacksBlock(character: $character)
        case .inventory: InventoryBlock(character: $character)
        case .diceRoller: DiceInlineBlock()
        case .notes: NotesBlock(character: $character)
        }
    }
}

struct BlockCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        GroupBox(label: Text(title).font(.headline)) {
            VStack(alignment: .leading, spacing: 8) { content }.padding(.top, 4)
        }
    }
}

struct IdentityBlock: View {
    @Binding var character: Character
    var body: some View {
        BlockCard(title: "Identity") {
            HStack {
                TextField("Name", text: $character.name).font(.title2)
                Stepper("Level \(character.level)", value: $character.level, in: 1...20)
            }
            HStack {
                TextField("Lineage", text: $character.lineage)
                TextField("Calling", text: $character.calling)
                TextField("Background", text: $character.background)
            }
        }
    }
}

struct AbilitiesBlock: View {
    @Binding var character: Character
    private let cols = [GridItem(.adaptive(minimum: 110))]
    var body: some View {
        BlockCard(title: "Abilities (proficiency +\(character.proficiencyBonus))") {
            LazyVGrid(columns: cols, spacing: 10) {
                ForEach(Ability.allCases, id: \.self) { a in
                    AbilityCell(character: $character, ability: a)
                }
            }
        }
    }
}

struct AbilityCell: View {
    @Binding var character: Character
    let ability: Ability
    var body: some View {
        VStack(spacing: 4) {
            Text(ability.abbreviation).font(.caption).foregroundStyle(.secondary)
            Text(signed(character.scores.modifier(ability))).font(.title).bold()
            Stepper("\(character.scores[ability])", value: Binding(
                get: { character.scores[ability] },
                set: { character.scores[ability] = min(30, max(1, $0)) }
            ), in: 1...30).labelsHidden()
            Toggle("Save \(signed(character.savingThrow(ability)))", isOn: Binding(
                get: { character.savingThrowProficiencies.contains(ability) },
                set: { on in
                    if on { character.savingThrowProficiencies.insert(ability) }
                    else { character.savingThrowProficiencies.remove(ability) }
                }
            )).toggleStyle(.checkbox).font(.caption)
        }
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct VitalsBlock: View {
    @Binding var character: Character
    var body: some View {
        BlockCard(title: "Vitals") {
            HStack {
                Stepper("HP \(character.currentHP)/\(character.maxHP)",
                        value: $character.currentHP, in: 0...character.maxHP)
                Stepper("Max HP \(character.maxHP)", value: $character.maxHP, in: 1...999)
            }
            HStack {
                Stepper("AC \(character.armorClass)", value: $character.armorClass, in: 0...40)
                Stepper("Speed \(character.speed) ft", value: $character.speed, in: 0...120, step: 5)
                Text("Initiative \(signed(character.initiative)) · Passive Perception \(character.passivePerception)")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct SkillsBlock: View {
    @Binding var character: Character
    var body: some View {
        BlockCard(title: "Skills") {
            ForEach($character.skills) { $skill in
                HStack {
                    Text(skill.name).frame(width: 140, alignment: .leading)
                    Text("(\(skill.ability.abbreviation))").font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $skill.tier) {
                        ForEach(ProficiencyTier.allCases, id: \.self) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)
                    Spacer()
                    Text(signed(skill.bonus(scores: character.scores, level: character.level)))
                        .monospacedDigit().bold()
                }
            }
        }
    }
}

struct AttacksBlock: View {
    @Binding var character: Character
    var body: some View {
        BlockCard(title: "Attacks") {
            ForEach($character.attacks) { $attack in
                HStack {
                    TextField("Name", text: $attack.name).frame(width: 160)
                    Stepper("\(signed(attack.attackBonus))", value: $attack.attackBonus, in: -10...30)
                    TextField("Damage (e.g. 1d8+3)", text: $attack.damageExpression)
                    Button(role: .destructive) {
                        character.attacks.removeAll { $0.id == attack.id }
                    } label: { Image(systemName: "minus.circle") }
                }
            }
            Button("Add attack") {
                character.attacks.append(Attack(name: "New attack", attackBonus: 0, damageExpression: "1d6"))
            }
        }
    }
}

struct InventoryBlock: View {
    @Binding var character: Character
    var body: some View {
        BlockCard(title: "Inventory") {
            ForEach($character.inventory) { $item in
                HStack {
                    TextField("Item", text: $item.name)
                    Stepper("×\(item.quantity)", value: $item.quantity, in: 0...999)
                    Button(role: .destructive) {
                        character.inventory.removeAll { $0.id == item.id }
                    } label: { Image(systemName: "minus.circle") }
                }
            }
            Button("Add item") {
                character.inventory.append(InventoryItem(name: "New item"))
            }
        }
    }
}

struct DiceInlineBlock: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        BlockCard(title: "Dice") {
            Text("Open the Dice tab for the full roller.").foregroundStyle(.secondary)
        }
    }
}

struct NotesBlock: View {
    @Binding var character: Character
    var body: some View {
        BlockCard(title: "Notes") {
            TextEditor(text: $character.notes).frame(minHeight: 120)
        }
    }
}

/// The sheet builder: reorder, show/hide, and resize blocks.
struct BuilderView: View {
    @Binding var layout: SheetLayout

    var body: some View {
        List {
            Section("Sheet blocks — drag to reorder") {
                ForEach($layout.blocks) { $block in
                    HStack {
                        Toggle("", isOn: $block.visible).labelsHidden()
                        Text(block.kind.rawValue.camelCasedToWords())
                        Spacer()
                        Picker("", selection: $block.size) {
                            ForEach(BlockSize.allCases, id: \.self) { s in
                                Text(s.rawValue).tag(s)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 240)
                    }
                }
                .onMove { layout.move(fromOffsets: $0, toOffset: $1) }
            }
        }
    }
}

struct DiceRollerView: View {
    @EnvironmentObject var model: AppModel
    @State private var expression = "2d6+3"
    @State private var d20Mode: RollMode = .normal
    @State private var d20Modifier = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                TextField("Dice notation", text: $expression)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .onSubmit { model.roll(expression) }
                Button("Roll") { model.roll(expression) }.keyboardShortcut(.return)
                Text("e.g. d20, 2d6+3, 4d6kh3, 4d6dl1").font(.caption).foregroundStyle(.secondary)
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
                Button("Roll d20") { model.rollD20(mode: d20Mode, modifier: d20Modifier) }
            }
            List(model.rollHistory.indices, id: \.self) { i in
                let r = model.rollHistory[i]
                HStack {
                    Text(r.expression).frame(width: 140, alignment: .leading)
                    Text(r.dice.map { $0.kept ? "\($0.value)" : "(\($0.value))" }.joined(separator: " "))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(r.total)").bold().font(.title3)
                }
            }
        }
        .padding()
    }
}

private func signed(_ n: Int) -> String { n >= 0 ? "+\(n)" : "\(n)" }

private extension String {
    func camelCasedToWords() -> String {
        unicodeScalars.reduce("") { acc, s in
            if CharacterSet.uppercaseLetters.contains(s), !acc.isEmpty { return acc + " " + String(s).lowercased() }
            return acc + String(s)
        }.capitalized
    }
}
#endif
