#if os(macOS)
import SwiftUI
import ArchiterCore

struct VitalsBlock: View {
    @Binding var character: Character
    @EnvironmentObject var model: AppModel
    @State private var damageAmount = ""
    @State private var healAmount = ""
    @State private var tempAmount = ""

    var body: some View {
        BlockCard(title: "Vitals") {
            // HP row with damage / heal / temp workflows
            HStack(spacing: Theme.Gap.md) {
                StatPlate(label: "Hit Points",
                          value: "\(character.currentHP)\(character.tempHP > 0 ? "+\(character.tempHP)" : "")",
                          tint: character.currentHP * 2 > character.maxHP ? Theme.ink : Theme.danger)
                VStack(spacing: Theme.Gap.xs) {
                    ResourceBar(current: character.currentHP, max: character.maxHP, temp: character.tempHP)
                    HStack(spacing: Theme.Gap.sm) {
                        Stepper("HP", value: $character.currentHP, in: 0...character.maxHP)
                            .font(Theme.Typeface.caption)
                        Stepper("Max \(character.maxHP)", value: $character.maxHP, in: 1...999)
                            .font(Theme.Typeface.caption)
                    }
                    .foregroundStyle(Theme.inkMuted)
                }
            }
            HStack(spacing: Theme.Gap.sm) {
                TextField("Damage", text: $damageAmount).frame(width: 64).textFieldStyle(InsetFieldStyle())
                Button("Apply") {
                    if let n = Int(damageAmount) { character.applyDamage(n); damageAmount = "" }
                }
                .buttonStyle(RollButtonStyle(prominent: true))
                TextField("Heal", text: $healAmount).frame(width: 64).textFieldStyle(InsetFieldStyle())
                Button("Apply") {
                    if let n = Int(healAmount) { character.applyHealing(n); healAmount = "" }
                }
                .buttonStyle(RollButtonStyle())
                TextField("Temp", text: $tempAmount).frame(width: 64).textFieldStyle(InsetFieldStyle())
                Button("Gain") {
                    if let n = Int(tempAmount) { character.gainTempHP(n); tempAmount = "" }
                }
                .buttonStyle(RollButtonStyle())
            }
            Divider().overlay(Theme.edge)
            // Defenses row
            HStack(spacing: Theme.Gap.md) {
                StatPlate(label: "Armor Class", value: "\(character.computedAC)", tint: Theme.accent)
                    .frame(maxWidth: 110)
                Picker("Armor", selection: $character.equippedArmor) {
                    Text("Unarmored").tag(String?.none)
                    ForEach(EquipmentLibrary.armors.filter { $0.category != .shield }) { def in
                        Text("\(def.name) (\(def.baseAC)\(def.addDex ? "+DEX" : ""))").tag(String?.some(def.name))
                    }
                }
                .frame(maxWidth: 220)
                Toggle("Shield", isOn: $character.shieldEquipped).toggleStyle(.checkbox)
                Stepper("Misc \(signed(character.armorClassBonus))", value: $character.armorClassBonus, in: -10...10)
            }
            HStack {
                Stepper("Manual AC \(character.armorClass)", value: $character.armorClass, in: 0...40)
                    .help("Used when unarmored")
                Stepper("Speed \(character.speed) ft", value: $character.speed, in: 0...120, step: 5)
                Stepper("Init misc \(signed(character.initiativeBonus))", value: $character.initiativeBonus, in: -10...20)
                Text("Initiative \(signed(character.initiative)) · Passive Perception \(character.passivePerception)")
                    .foregroundStyle(.secondary)
            }
            Divider().overlay(Theme.edge)
            // Hit dice + death saves + rests
            HStack {
                Picker("Hit die", selection: $character.hitDiceType) {
                    ForEach([6, 8, 10, 12], id: \.self) { Text("d\($0)").tag($0) }
                }
                .frame(width: 90)
                Text("\(character.hitDiceRemaining)/\(character.hitDiceTotal) remaining")
                    .foregroundStyle(.secondary)
                Button("Spend hit die") { model.spendHitDie() }
                    .buttonStyle(RollButtonStyle())
                    .disabled(character.hitDiceRemaining == 0)
                Spacer()
                Button("Short rest") { model.shortRest() }
                    .buttonStyle(RollButtonStyle())
                Button("Long rest") { model.longRest() }
                    .buttonStyle(RollButtonStyle(prominent: true))
            }
            HStack(spacing: Theme.Gap.md) {
                CardSectionLabel(text: "Death saves")
                Pips(filled: character.deathSaveSuccesses, total: 3, tint: Theme.success) { i in
                    character.deathSaveSuccesses = i < character.deathSaveSuccesses ? i : i + 1
                }
                Pips(filled: character.deathSaveFailures, total: 3, tint: Theme.danger) { i in
                    character.deathSaveFailures = i < character.deathSaveFailures ? i : i + 1
                }
                Button("Roll death save") { model.rollDeathSave() }
                    .buttonStyle(RollButtonStyle())
                    .disabled(character.currentHP > 0)
            }
            Divider().overlay(Theme.edge)
            // Conditions + exhaustion
            HStack {
                CardSectionLabel(text: "Exhaustion")
                Stepper("\(character.exhaustion)", value: $character.exhaustion, in: 0...character.era.exhaustionCap)
                    .font(Theme.Typeface.caption)
                if character.exhaustion > 0 {
                    Text(character.exhaustionStepNote)
                        .font(Theme.Typeface.caption)
                        .foregroundStyle(Theme.danger)
                }
            }
            .foregroundStyle(Theme.inkMuted)
            ConditionGrid(character: $character)
        }
    }
}

struct ConditionGrid: View {
    @Binding var character: Character
    private let cols = [GridItem(.adaptive(minimum: 130))]

    var body: some View {
        LazyVGrid(columns: cols, alignment: .leading, spacing: 6) {
            ForEach(Condition.allCases, id: \.self) { condition in
                Toggle(condition.displayName, isOn: Binding(
                    get: { character.conditions.contains(condition) },
                    set: { on in
                        if on { character.conditions.insert(condition) }
                        else { character.conditions.remove(condition) }
                    }
                ))
                .toggleStyle(.checkbox)
                .font(.caption)
            }
        }
    }
}

struct AttacksBlock: View {
    @Binding var character: Character
    @EnvironmentObject var model: AppModel
    @State private var rollMode: RollMode = .normal

    var body: some View {
        BlockCard(title: "Attacks & Combat") {
            HStack {
                Picker("Roll mode", selection: $rollMode) {
                    ForEach([RollMode.normal, .advantage, .disadvantage], id: \.self) { m in
                        Text(m.rawValue.capitalized).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)
                if !character.disadvantageSources(for: .attack).isEmpty {
                    Text("Disadvantage from \(character.disadvantageSources(for: .attack).map(\.displayName).joined(separator: ", "))")
                        .font(Theme.Typeface.caption)
                        .foregroundStyle(Theme.danger)
                }
                Spacer()
                Menu("Add from library") {
                    ForEach(EquipmentLibrary.weapons) { w in
                        Button(w.name) {
                            character.attacks.append(Attack(
                                name: w.name,
                                ability: w.finesse ? nil : .strength,
                                proficient: true,
                                damageExpression: w.damageExpression,
                                damageType: w.damageType,
                                range: w.range,
                                notes: w.properties))
                        }
                    }
                }
                Button("Add custom") {
                    character.attacks.append(Attack(name: "New attack"))
                }
            }
            ForEach($character.attacks) { $attack in
                AttackRow(character: $character, attack: $attack, rollMode: rollMode)
            }
            if let sc = character.spellcasting {
                Divider()
                HStack {
                    Text("Spell attack \(signed(sc.spellAttackBonus(scores: character.scores, level: character.level)))")
                    Text("Spell save DC \(sc.spellSaveDC(scores: character.scores, level: character.level))")
                    Text("(\(sc.ability.abbreviation))").foregroundStyle(.secondary)
                    Spacer()
                    Button("Roll spell attack") {
                        model.rollCheck("Spell attack", bonus: sc.spellAttackBonus(scores: character.scores, level: character.level), mode: rollMode)
                    }
                    .controlSize(.small)
                }
                .font(.callout)
            }
        }
    }
}

struct AttackRow: View {
    @Binding var character: Character
    @Binding var attack: Attack
    let rollMode: RollMode
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                TextField("Name", text: $attack.name).frame(width: 150)
                Picker("Ability", selection: $attack.ability) {
                    Text("Finesse").tag(Ability?.none)
                    ForEach(Ability.allCases, id: \.self) { Text($0.abbreviation).tag(Ability?.some($0)) }
                }
                .frame(width: 110)
                Toggle("Prof", isOn: $attack.proficient).toggleStyle(.checkbox)
                Text(signed(attack.attackBonus(scores: character.scores, level: character.level)))
                    .monospacedDigit().bold()
                    .frame(width: 40)
                Button("Attack") { model.rollAttack(attack, for: character, mode: rollMode) }
                    .controlSize(.small)
                Button(role: .destructive) {
                    character.attacks.removeAll { $0.id == attack.id }
                } label: { Image(systemName: "minus.circle") }
            }
            HStack {
                TextField("Damage dice", text: $attack.damageExpression).frame(width: 90)
                Text("= \(attack.damageString(scores: character.scores))")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Type", text: $attack.damageType).frame(width: 100)
                TextField("Range", text: $attack.range).frame(width: 130)
                TextField("Notes", text: $attack.notes)
                Button("Damage") {
                    model.rollLabeled("\(attack.name) damage", attack.damageString(scores: character.scores))
                }
                .controlSize(.small)
            }
            if character.era.usesWeaponMastery {
                HStack(spacing: Theme.Gap.xs) {
                    Text("Mastery")
                        .font(Theme.Typeface.caption)
                        .foregroundStyle(Theme.inkFaint)
                    Picker("", selection: $attack.mastery) {
                        Text("None").tag(WeaponMastery?.none)
                        ForEach(WeaponMastery.allCases, id: \.self) { m in
                            Text(m.rawValue).tag(WeaponMastery?.some(m))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 110)
                    if let mastery = attack.mastery {
                        Text(mastery.effect)
                            .font(Theme.Typeface.caption)
                            .foregroundStyle(Theme.inkMuted)
                    }
                    Spacer()
                }
            }
        }
    }
}
#endif
