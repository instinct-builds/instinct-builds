#if os(macOS)
import SwiftUI
import ArchiterCore

struct IdentityBlock: View {
    @Binding var character: Character
    @State private var xpToAdd = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Gap.md) {
            HStack(alignment: .firstTextBaseline) {
                TextField("Name", text: $character.name)
                    .textFieldStyle(.plain)
                    .font(Theme.Typeface.display)
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button(action: { character.inspiration.toggle() }) {
                    Image(systemName: character.inspiration ? "star.fill" : "star")
                        .font(.title3)
                        .foregroundStyle(character.inspiration ? Theme.accent : Theme.inkFaint)
                }
                .buttonStyle(.plain)
                .help("Inspiration")
                Stepper(value: $character.level, in: 1...20) {
                    Text("LVL \(character.level)")
                        .font(Theme.Typeface.headline.monospacedDigit())
                        .foregroundStyle(Theme.accent)
                }
            }
            HStack(spacing: Theme.Gap.sm) {
                TextField("Lineage", text: $character.lineage).textFieldStyle(InsetFieldStyle())
                TextField("Calling", text: $character.calling).textFieldStyle(InsetFieldStyle())
                TextField("Background", text: $character.background).textFieldStyle(InsetFieldStyle())
                TextField("Alignment", text: $character.alignment).textFieldStyle(InsetFieldStyle())
            }
            HStack(spacing: Theme.Gap.sm) {
                Text("XP \(character.experience)")
                    .font(Theme.Typeface.caption.monospacedDigit())
                    .foregroundStyle(Theme.inkMuted)
                if let toNext = character.xpToNextLevel {
                    ProgressView(value: min(1, Double(character.experience) / Double(character.experience + toNext)))
                        .tint(Theme.accent)
                        .frame(maxWidth: 160)
                    Text("\(toNext) to level \(character.level + 1)")
                        .font(Theme.Typeface.caption)
                        .foregroundStyle(Theme.inkFaint)
                } else {
                    Text("max level")
                        .font(Theme.Typeface.caption)
                        .foregroundStyle(Theme.inkFaint)
                }
                Spacer()
                TextField("Award XP", text: $xpToAdd)
                    .textFieldStyle(InsetFieldStyle())
                    .frame(width: 80)
                Button("Add") {
                    if let amount = Int(xpToAdd), amount > 0 {
                        var c = character
                        _ = c.addXP(amount)
                        character = c
                        xpToAdd = ""
                    }
                }
                .buttonStyle(RollButtonStyle())
                .disabled(Int(xpToAdd) == nil)
                Text("PROF \(signed(character.proficiencyBonus))")
                    .font(Theme.Typeface.caption.monospacedDigit())
                    .foregroundStyle(Theme.accent)
            }
            TextField("Proficiencies & languages", text: $character.proficienciesText)
                .textFieldStyle(InsetFieldStyle())
                .font(Theme.Typeface.caption)
        }
        .padding(Theme.Gap.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Theme.surfaceRaised, Theme.heroGlow],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: Theme.Radius.lg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
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
        let modifier = character.scores.modifier(ability)
        return VStack(spacing: Theme.Gap.xs) {
            Text(ability.abbreviation)
                .font(Theme.Typeface.statLabel)
                .tracking(1.4)
                .foregroundStyle(Theme.inkMuted)
            Text(signed(modifier))
                .font(Theme.Typeface.statBig)
                .foregroundStyle(Theme.ink)
            Stepper(value: Binding(
                get: { character.scores[ability] },
                set: { character.scores[ability] = min(30, max(1, $0)) }
            ), in: 1...30) {
                Text("\(character.scores[ability])")
                    .font(Theme.Typeface.caption.monospacedDigit())
                    .foregroundStyle(Theme.inkMuted)
            }
            Divider().overlay(Theme.edge)
            Button(action: {
                model.rollCheck("\(ability.abbreviation) check", bonus: modifier)
            }) {
                Text("Check \(signed(modifier))")
            }
            .buttonStyle(RollButtonStyle())
            HStack(spacing: 4) {
                Button(action: {
                    model.rollCheck("\(ability.abbreviation) save", bonus: character.savingThrow(ability))
                }) {
                    Text("Save \(signed(character.savingThrow(ability)))")
                }
                .buttonStyle(RollButtonStyle())
                Button(action: {
                    if character.savingThrowProficiencies.contains(ability) {
                        character.savingThrowProficiencies.remove(ability)
                    } else {
                        character.savingThrowProficiencies.insert(ability)
                    }
                }) {
                    Image(systemName: character.savingThrowProficiencies.contains(ability) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(character.savingThrowProficiencies.contains(ability) ? Theme.accent : Theme.inkFaint)
                }
                .buttonStyle(.plain)
                .help("Toggle save proficiency")
            }
        }
        .padding(Theme.Gap.sm)
        .frame(maxWidth: .infinity)
        .background(Theme.surfaceInset, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .strokeBorder(Theme.edge.opacity(0.6), lineWidth: 1)
        )
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
