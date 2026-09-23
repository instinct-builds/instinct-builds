#if os(macOS)
import SwiftUI
import ArchiterCore

struct InventoryBlock: View {
    @Binding var character: Character

    var body: some View {
        BlockCard(title: "Inventory") {
            // Currency
            HStack {
                Text("Currency:").foregroundStyle(.secondary)
                Stepper("PP \(character.currency.platinum)", value: $character.currency.platinum, in: 0...99999)
                Stepper("GP \(character.currency.gold)", value: $character.currency.gold, in: 0...99999)
                Stepper("EP \(character.currency.electrum)", value: $character.currency.electrum, in: 0...99999)
                Stepper("SP \(character.currency.silver)", value: $character.currency.silver, in: 0...99999)
                Stepper("CP \(character.currency.copper)", value: $character.currency.copper, in: 0...99999)
                Button("Consolidate") { character.currency = character.currency.normalized() }
                    .buttonStyle(RollButtonStyle())
                    .help("Convert loose change into the fewest coins (same total value)")
            }
            .font(.caption)
            // Weight
            HStack {
                Text("Carried \(fmtWeight(character.totalWeight)) / \(character.carryingCapacity) lb")
                    .monospacedDigit()
                if character.encumbrance != .normal {
                    Text(character.encumbrance == .overCapacity ? "OVER CAPACITY" :
                            (character.encumbrance == .heavilyEncumbered ? "Heavily encumbered" : "Encumbered"))
                        .font(.caption).bold()
                        .foregroundStyle(.orange)
                }
                Spacer()
                Menu("Add weapon") {
                    ForEach(EquipmentLibrary.weapons) { w in
                        Button(w.name) {
                            character.inventory.append(InventoryItem(name: w.name, weight: w.weight, category: "Weapon", notes: w.properties))
                        }
                    }
                }
                Menu("Add gear") {
                    ForEach(EquipmentLibrary.gear) { g in
                        Button(g.name) {
                            character.inventory.append(InventoryItem(name: g.name, weight: g.weight, category: "Gear", notes: g.cost))
                        }
                    }
                }
                Button("Add custom") {
                    character.inventory.append(InventoryItem(name: "New item"))
                }
            }
            .font(.callout)
            // Items
            ForEach($character.inventory) { $item in
                HStack {
                    Toggle("", isOn: $item.equipped).labelsHidden().help("Equipped")
                    TextField("Item", text: $item.name).frame(minWidth: 160)
                    Stepper("×\(item.quantity)", value: $item.quantity, in: 0...999)
                    TextField("lb", value: Binding(
                        get: { item.weight ?? 0 },
                        set: { item.weight = $0 == 0 ? nil : $0 }
                    ), format: .number)
                        .frame(width: 60)
                    Toggle("Attuned", isOn: $item.attuned).toggleStyle(.checkbox).font(.caption)
                    TextField("Notes", text: $item.notes)
                    Button(role: .destructive) {
                        character.inventory.removeAll { $0.id == item.id }
                    } label: { Image(systemName: "minus.circle") }
                }
            }
        }
    }

    private func fmtWeight(_ w: Double) -> String {
        w.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(w))" : String(format: "%.1f", w)
    }
}

struct FeaturesBlock: View {
    @Binding var character: Character

    var body: some View {
        BlockCard(title: "Features & Traits") {
            ForEach($character.features) { $feature in
                VStack(spacing: 4) {
                    HStack {
                        TextField("Feature", text: $feature.name).bold().frame(minWidth: 180)
                        TextField("Source", text: $feature.source).frame(width: 110)
                        Picker("Recharge", selection: $feature.recharge) {
                            ForEach(Recharge.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                        .frame(width: 150)
                        Button(role: .destructive) {
                            character.features.removeAll { $0.id == feature.id }
                        } label: { Image(systemName: "minus.circle") }
                    }
                    HStack {
                        Stepper("Uses \(feature.usesMax == 0 ? "∞" : "\(feature.usesMax - min(feature.usesUsed, feature.usesMax))/\(feature.usesMax)")",
                                value: $feature.usesMax, in: 0...20)
                        if feature.usesMax > 0 {
                            Button("Use one") { feature.expendUse() }
                                .controlSize(.small)
                                .disabled(feature.usesUsed >= feature.usesMax)
                            Button("Reset") { feature.rechargeUses() }
                                .controlSize(.small)
                                .disabled(feature.usesUsed == 0)
                        }
                        Spacer()
                    }
                    TextField("Description", text: $feature.detail, axis: .vertical)
                        .font(.caption)
                        .lineLimit(1...4)
                }
                Divider()
            }
            Button("Add feature") {
                character.features.append(Feature(name: "New feature"))
            }
        }
    }
}

struct PersonalityBlock: View {
    @Binding var character: Character

    var body: some View {
        BlockCard(title: "Personality & Story") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                PersonalityField("Traits", text: $character.personality.traits)
                PersonalityField("Ideals", text: $character.personality.ideals)
                PersonalityField("Bonds", text: $character.personality.bonds)
                PersonalityField("Flaws", text: $character.personality.flaws)
            }
            HStack {
                TextField("Age", text: $character.personality.age).frame(width: 70)
                TextField("Height", text: $character.personality.height).frame(width: 80)
                TextField("Weight", text: $character.personality.weight).frame(width: 80)
                TextField("Eyes", text: $character.personality.eyes).frame(width: 90)
                TextField("Hair", text: $character.personality.hair).frame(width: 110)
            }
            PersonalityField("Appearance", text: $character.personality.appearance)
            PersonalityField("Backstory", text: $character.personality.backstory, lines: 4)
            PersonalityField("Allies & organizations", text: $character.personality.allies)
            PersonalityField("Treasure", text: $character.personality.treasure)
        }
    }
}

struct PersonalityField: View {
    let label: String
    @Binding var text: String
    var lines: Int = 2

    init(_ label: String, text: Binding<String>, lines: Int = 2) {
        self.label = label
        _text = text
        self.lines = lines
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(.callout)
                .frame(minHeight: CGFloat(lines) * 20)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
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
#endif
