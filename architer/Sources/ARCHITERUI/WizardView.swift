#if os(macOS)
import SwiftUI
import ArchiterCore

/// Guided character creation: identity, a calling preset (HP, hit die, save
/// proficiencies, suggested skills), ability scores three ways, and skills.
struct CharacterWizardView: View {
    @State private var era: RulesetVariant = .era2014
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var lineage = ""
    @State private var calling = ""
    @State private var background = ""
    @State private var alignment = ""
    @State private var level = 1
    @State private var hitDiceType = 8
    @State private var maxHP = 10
    @State private var abilityMethod: AbilityMethod = .standardArray
    @State private var scores: [Ability: Int] = Dictionary(uniqueKeysWithValues: Ability.allCases.map { ($0, 10) })
    @State private var standardPicks: [Ability: Int] = [:]
    @State private var chosenSkills: Set<String> = []
    @State private var chosenSaves: Set<Ability> = []

    enum AbilityMethod: String, CaseIterable {
        case standardArray = "Standard array"
        case pointBuy = "Point buy (27)"
        case manual = "Manual"
    }

    struct CallingPreset {
        let name: String
        let hitDie: Int
        let saves: [Ability]
        let skills: [String]
        let spellcasting: (Ability, CasterProgression)?
    }

    static let presets: [CallingPreset] = [
        CallingPreset(name: "Fighter", hitDie: 10, saves: [.strength, .constitution],
                      skills: ["Athletics", "Intimidation", "Perception", "Survival"], spellcasting: nil),
        CallingPreset(name: "Wizard", hitDie: 6, saves: [.intelligence, .wisdom],
                      skills: ["Arcana", "History", "Investigation", "Religion"], spellcasting: (.intelligence, .full)),
        CallingPreset(name: "Rogue", hitDie: 8, saves: [.dexterity, .intelligence],
                      skills: ["Acrobatics", "Stealth", "Sleight of Hand", "Perception", "Deception"], spellcasting: nil),
        CallingPreset(name: "Cleric", hitDie: 8, saves: [.wisdom, .charisma],
                      skills: ["Insight", "Medicine", "Religion", "Persuasion"], spellcasting: (.wisdom, .full)),
        CallingPreset(name: "Ranger", hitDie: 10, saves: [.strength, .dexterity],
                      skills: ["Athletics", "Nature", "Perception", "Stealth", "Survival"], spellcasting: (.wisdom, .half)),
        CallingPreset(name: "Warlock", hitDie: 8, saves: [.wisdom, .charisma],
                      skills: ["Arcana", "Deception", "Intimidation", "Investigation"], spellcasting: (.charisma, .pact)),
        CallingPreset(name: "Barbarian", hitDie: 12, saves: [.strength, .constitution],
                      skills: ["Athletics", "Intimidation", "Perception", "Survival"], spellcasting: nil),
        CallingPreset(name: "Bard", hitDie: 8, saves: [.dexterity, .charisma],
                      skills: ["Deception", "Performance", "Persuasion", "Insight", "History"], spellcasting: (.charisma, .full)),
        CallingPreset(name: "Druid", hitDie: 8, saves: [.intelligence, .wisdom],
                      skills: ["Nature", "Medicine", "Perception", "Survival", "Insight"], spellcasting: (.wisdom, .full)),
        CallingPreset(name: "Monk", hitDie: 8, saves: [.strength, .dexterity],
                      skills: ["Acrobatics", "Athletics", "Stealth", "Insight", "Perception"], spellcasting: nil),
        CallingPreset(name: "Paladin", hitDie: 10, saves: [.wisdom, .charisma],
                      skills: ["Athletics", "Intimidation", "Medicine", "Persuasion", "Religion"], spellcasting: (.charisma, .half)),
        CallingPreset(name: "Sorcerer", hitDie: 6, saves: [.constitution, .charisma],
                      skills: ["Arcana", "Deception", "Intimidation", "Persuasion"], spellcasting: (.charisma, .full)),
    ]

    static let standardArray = [15, 14, 13, 12, 10, 8]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("New Character").font(.title2).bold()
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create") { create() }
                    .keyboardShortcut(.return)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .buttonStyle(.borderedProminent)
            }
            .padding()
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox("Identity") {
                        VStack(spacing: 8) {
                            HStack {
                                TextField("Name (required)", text: $name)
                                TextField("Lineage", text: $lineage)
                            }
                            HStack {
                                TextField("Calling", text: $calling)
                                TextField("Background", text: $background)
                                TextField("Alignment", text: $alignment)
                            }
                            HStack {
                                Stepper("Level \(level)", value: $level, in: 1...20)
                                Spacer()
                            }
                        }
                        .padding(.top, 4)
                    }
                    GroupBox("Ruleset era (mechanics preset)") {
                        Picker("Era", selection: $era) {
                            ForEach(RulesetVariant.allCases, id: \.self) { e in
                                Text(e.displayName).tag(e)
                            }
                        }
                        .pickerStyle(.segmented)
                        Text(era.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    GroupBox("Calling preset (fills HP, hit die, saves, suggested skills)") {
                        HStack {
                            ForEach(CharacterWizardView.presets, id: \.name) { preset in
                                Button(preset.name) { apply(preset: preset) }
                                    .controlSize(.small)
                            }
                        }
                        .padding(.top, 4)
                    }
                    GroupBox("Ability scores") {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("Method", selection: $abilityMethod) {
                                ForEach(AbilityMethod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            abilityEditor
                        }
                        .padding(.top, 4)
                    }
                    GroupBox("Skills (\(chosenSkills.count) chosen)") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], alignment: .leading, spacing: 6) {
                            ForEach(Skill.defaultList) { skill in
                                Toggle("\(skill.name) (\(skill.ability.abbreviation))", isOn: Binding(
                                    get: { chosenSkills.contains(skill.name) },
                                    set: { on in
                                        if on { chosenSkills.insert(skill.name) }
                                        else { chosenSkills.remove(skill.name) }
                                    }
                                ))
                                .toggleStyle(.checkbox)
                                .font(.caption)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding()
            }
        }
        .frame(width: 720, height: 640)
    }

    @ViewBuilder
    private var abilityEditor: some View {
        switch abilityMethod {
        case .standardArray:
            let remaining = CharacterWizardView.standardArray.filter { !standardPicks.values.contains($0) }
            VStack(alignment: .leading, spacing: 6) {
                Text("Assign \(CharacterWizardView.standardArray.map(String.init).joined(separator: ", ")) — left: \(remaining.map(String.init).joined(separator: ", "))")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(Ability.allCases, id: \.self) { a in
                    HStack {
                        Text(a.displayName).frame(width: 110, alignment: .leading)
                        Picker("", selection: Binding(
                            get: { standardPicks[a] },
                            set: { standardPicks[a] = $0 }
                        )) {
                            Text("—").tag(Int?.none)
                            ForEach(CharacterWizardView.standardArray, id: \.self) { v in
                                Text("\(v)").tag(Int?.some(v))
                                    .disabled(standardPicks.values.contains(v) && standardPicks[a] != v)
                            }
                        }
                        .frame(width: 90)
                        if let v = standardPicks[a] {
                            Text(signed(RulesMath.modifier(for: v))).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
            }
        case .pointBuy:
            let spent = Ability.allCases.reduce(0) { $0 + (RulesMath.pointBuyCost(score: scores[$1] ?? 10) ?? 0) }
            VStack(alignment: .leading, spacing: 6) {
                Text("Points spent: \(spent)/27 — scores 8 to 15")
                    .font(.caption)
                    .foregroundStyle(spent > 27 ? .red : .secondary)
                ForEach(Ability.allCases, id: \.self) { a in
                    HStack {
                        Text(a.displayName).frame(width: 110, alignment: .leading)
                        Stepper("\(scores[a] ?? 8) (\(signed(RulesMath.modifier(for: scores[a] ?? 8))))",
                                value: Binding(
                                    get: { scores[a] ?? 8 },
                                    set: { scores[a] = $0 }
                                ), in: 8...15)
                    }
                }
            }
        case .manual:
            ForEach(Ability.allCases, id: \.self) { a in
                HStack {
                    Text(a.displayName).frame(width: 110, alignment: .leading)
                    Stepper("\(scores[a] ?? 10) (\(signed(RulesMath.modifier(for: scores[a] ?? 10))))",
                            value: Binding(
                                get: { scores[a] ?? 10 },
                                set: { scores[a] = $0 }
                            ), in: 1...20)
                }
            }
        }
    }

    private func apply(preset: CallingPreset) {
        if calling.isEmpty { calling = preset.name }
        hitDiceType = preset.hitDie
        let conMod = RulesMath.modifier(for: scores[.constitution] ?? 10)
        maxHP = preset.hitDie + conMod + (level - 1) * (preset.hitDie / 2 + 1 + conMod)
        chosenSaves = Set(preset.saves)
        chosenSkills = Set(preset.skills)
    }

    private func create() {
        var finalScores: [Ability: Int]
        switch abilityMethod {
        case .standardArray:
            finalScores = Dictionary(uniqueKeysWithValues: Ability.allCases.map { ($0, standardPicks[$0] ?? 8) })
        case .pointBuy, .manual:
            finalScores = scores
        }
        let preset = CharacterWizardView.presets.first { $0.name == calling }
        var abilityScores = AbilityScores()
        for a in Ability.allCases { abilityScores[a] = finalScores[a] ?? 10 }
        var skills = Skill.defaultList
        for (i, s) in skills.enumerated() where chosenSkills.contains(s.name) {
            skills[i].tier = .proficient
        }
        var spellcasting: Spellcasting? = nil
        if let spec = preset?.spellcasting {
            spellcasting = Spellcasting(ability: spec.0, progression: spec.1)
        }
        let c = Character(
            name: name.trimmingCharacters(in: .whitespaces),
            lineage: lineage,
            calling: calling,
            background: background,
            alignment: alignment,
            level: level,
            scores: abilityScores,
            skills: skills,
            savingThrowProficiencies: chosenSaves,
            maxHP: max(1, maxHP),
            hitDiceType: hitDiceType,
            era: era,
            spellcasting: spellcasting
        )
        model.addCharacter(c)
        dismiss()
    }
}
#endif
