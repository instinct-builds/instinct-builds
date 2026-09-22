#if os(macOS)
import SwiftUI
import ArchiterCore

struct IdentityBlock: View {
    @Binding var character: Character
    @State private var xpToAdd = ""

    var body: some View {
        BlockCard(title: "Identity") {
            HStack {
                TextField("Name", text: $character.name).font(.title2)
                Toggle("Inspiration", isOn: $character.inspiration).toggleStyle(.checkbox)
                Stepper("Level \(character.level)", value: $character.level, in: 1...20)
            }
            HStack {
                TextField("Lineage", text: $character.lineage)
                TextField("Calling", text: $character.calling)
                TextField("Background", text: $character.background)
                TextField("Alignment", text: $character.alignment)
            }
            HStack {
                Text("XP \(character.experience)").monospacedDigit()
                if let toNext = character.xpToNextLevel {
                    Text("(\(toNext) to level \(character.level + 1))")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("(max level)").font(.caption).foregroundStyle(.secondary)
                }
                TextField("Award XP", text: $xpToAdd)
                    .frame(width: 80)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    if let amount = Int(xpToAdd), amount > 0 {
                        var c = character
                        _ = c.addXP(amount)
                        character = c
                        xpToAdd = ""
                    }
                }
                .disabled(Int(xpToAdd) == nil)
                Text("Proficiency \(signed(character.proficiencyBonus))")
                    .foregroundStyle(.secondary)
            }
            TextField("Proficiencies & languages", text: $character.proficienciesText)
                .font(.caption)
        }
    }
}

struct AbilitiesBlock: View {
    @Binding var character: Character
    private let cols = [GridItem(.adaptive(minimum: 120))]

    var body: some View {
        BlockCard(title: "Abilities (proficiency \(signed(character.proficiencyBonus)))") {
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
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 4) {
            Text(ability.abbreviation).font(.caption).foregroundStyle(.secondary)
            Text(signed(character.scores.modifier(ability))).font(.title).bold()
            Stepper("\(character.scores[ability])", value: Binding(
                get: { character.scores[ability] },
                set: { character.scores[ability] = min(30, max(1, $0)) }
            ), in: 1...30).labelsHidden()
            HStack(spacing: 4) {
                Button("Check") {
                    model.rollCheck("\(ability.abbreviation) check", bonus: character.scores.modifier(ability))
                }
                .controlSize(.small)
                Toggle("Save \(signed(character.savingThrow(ability)))", isOn: Binding(
                    get: { character.savingThrowProficiencies.contains(ability) },
                    set: { on in
                        if on { character.savingThrowProficiencies.insert(ability) }
                        else { character.savingThrowProficiencies.remove(ability) }
                    }
                ))
                .toggleStyle(.checkbox).font(.caption)
            }
            Button("Roll save") {
                model.rollCheck("\(ability.abbreviation) save", bonus: character.savingThrow(ability))
            }
            .controlSize(.small)
        }
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct SkillsBlock: View {
    @Binding var character: Character
    @EnvironmentObject var model: AppModel

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
                    Button("Roll") {
                        model.rollCheck(skill.name, bonus: skill.bonus(scores: character.scores, level: character.level))
                    }
                    .controlSize(.small)
                }
            }
        }
    }
}

struct CustomAbilitiesBlock: View {
    @Binding var character: Character
    private let cols = [GridItem(.adaptive(minimum: 120))]

    var body: some View {
        BlockCard(title: "\(character.rulesetName ?? "Custom") Abilities") {
            LazyVGrid(columns: cols, spacing: 10) {
                ForEach($character.customAbilities) { $a in
                    VStack(spacing: 4) {
                        Text(a.abbreviation).font(.caption).foregroundStyle(.secondary)
                        Text(signed(a.modifier)).font(.title).bold()
                        Stepper("\(a.score)", value: $a.score, in: 1...30).labelsHidden()
                    }
                    .padding(8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
}

struct CustomSkillsBlock: View {
    @Binding var character: Character
    @EnvironmentObject var model: AppModel

    var body: some View {
        BlockCard(title: "\(character.rulesetName ?? "Custom") Skills") {
            ForEach($character.customSkills) { $skill in
                HStack {
                    Text(skill.name).frame(width: 140, alignment: .leading)
                    Text("(\(skill.abilityName))").font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $skill.tier) {
                        ForEach(ProficiencyTier.allCases, id: \.self) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)
                    Spacer()
                    Text(signed(skill.bonus(abilities: character.customAbilities, level: character.level)))
                        .monospacedDigit().bold()
                    Button("Roll") {
                        model.rollCheck(skill.name, bonus: skill.bonus(abilities: character.customAbilities, level: character.level))
                    }
                    .controlSize(.small)
                }
            }
        }
    }
}
#endif
