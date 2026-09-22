#if os(macOS)
import SwiftUI
import ArchiterCore

/// The sheet builder: reorder, show/hide, and resize blocks; manage custom
/// templated blocks; apply a whole custom ruleset to the character.
public struct BuilderView: View {
    @Binding var character: Character
    @EnvironmentObject var model: AppModel
    @State private var rulesetNameDraft = ""
    @State private var showSaveRuleset = false

    public init(character: Binding<Character>) {
        _character = character
    }

    public var body: some View {
        List {
            Section("Sheet blocks — drag to reorder") {
                ForEach($character.layout.blocks) { $block in
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
                .onMove { character.layout.move(fromOffsets: $0, toOffset: $1) }
            }
            Section("Custom blocks — free text with {placeholders}") {
                ForEach($character.layout.customBlocks) { $block in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            TextField("Title (supports {name}, {level}, {STR}…)", text: $block.title)
                            Button(role: .destructive) {
                                character.layout.customBlocks.removeAll { $0.id == block.id }
                            } label: { Image(systemName: "minus.circle") }
                        }
                        TextEditor(text: $block.body)
                            .frame(minHeight: 60)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
                    }
                }
                Button("Add custom block") {
                    character.layout.customBlocks.append(
                        CustomBlock(title: "About {name}", body: "Level {level} — proficiency +{proficiency}."))
                }
                Text("Placeholders: {name} {lineage} {calling} {background} {level} {xp} {prof} {hp} {maxhp} {ac} {STR} {DEX} {CON} {INT} {WIS} {CHA}")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Custom rulesets") {
                if let ruleset = character.rulesetName {
                    Text("Active ruleset: \(ruleset)")
                    Button("Remove ruleset") {
                        character.rulesetName = nil
                        character.customAbilities = []
                        character.customSkills = []
                    }
                    .foregroundStyle(.red)
                } else {
                    Text("Apply a ruleset to replace the built-in abilities/skills with your own game's. Built-ins stay on the sheet too, so nothing is lost.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Apply Starfarer (sci-fi)") { apply(Ruleset.starfarer) }
                        Button("Apply Gumshoe (investigation)") { apply(Ruleset.gumshoe) }
                    }
                }
                if !model.rulesets.isEmpty {
                    Text("Your ruleset library").font(.subheadline).bold()
                    ForEach(model.rulesets, id: \.name) { ruleset in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ruleset.name).bold()
                                Text("\(ruleset.abilities.count) abilities · \(ruleset.skills.count) skills")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Apply") { apply(ruleset) }
                            Button(role: .destructive) {
                                model.deleteRuleset(named: ruleset.name)
                            } label: { Image(systemName: "minus.circle") }
                        }
                    }
                }
                if !character.customAbilities.isEmpty {
                    if showSaveRuleset {
                        HStack {
                            TextField("Ruleset name", text: $rulesetNameDraft)
                            Button("Save") {
                                let name = rulesetNameDraft.trimmingCharacters(in: .whitespaces)
                                guard !name.isEmpty else { return }
                                model.saveRuleset(character.captureRuleset(named: name))
                                rulesetNameDraft = ""
                                showSaveRuleset = false
                            }
                            .disabled(rulesetNameDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                            Button("Cancel") {
                                rulesetNameDraft = ""
                                showSaveRuleset = false
                            }
                        }
                    } else {
                        Button("Save as ruleset…") { showSaveRuleset = true }
                            .help("Save the abilities/skills below as a reusable ruleset in your library")
                    }
                }
                if !character.customAbilities.isEmpty {
                    Text("Custom abilities").font(.subheadline).bold()
                    ForEach($character.customAbilities) { $a in
                        HStack {
                            TextField("Name", text: $a.name)
                            TextField("Abbr", text: $a.abbreviation).frame(width: 70)
                            Stepper("\(a.score)", value: $a.score, in: 1...30)
                            Button(role: .destructive) {
                                character.customAbilities.removeAll { $0.id == a.id }
                            } label: { Image(systemName: "minus.circle") }
                        }
                    }
                    Button("Add ability") {
                        character.customAbilities.append(CustomAbility(name: "New Ability"))
                    }
                    Text("Custom skills").font(.subheadline).bold()
                    ForEach($character.customSkills) { $skill in
                        HStack {
                            TextField("Name", text: $skill.name)
                            Picker("Ability", selection: $skill.abilityName) {
                                ForEach(character.customAbilities) { a in
                                    Text(a.name).tag(a.name)
                                }
                            }
                            Button(role: .destructive) {
                                character.customSkills.removeAll { $0.id == skill.id }
                            } label: { Image(systemName: "minus.circle") }
                        }
                    }
                    Button("Add skill") {
                        character.customSkills.append(
                            CustomSkill(name: "New Skill", abilityName: character.customAbilities.first?.name ?? ""))
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .foregroundStyle(Theme.ink)
    }

    private func apply(_ ruleset: Ruleset) {
        var c = character
        c.rulesetName = ruleset.name
        c.customAbilities = ruleset.abilities.map { CustomAbility(name: $0) }
        c.customSkills = ruleset.skills.map { CustomSkill(name: $0.name, abilityName: $0.abilityName) }
        character = c
    }
}
#endif
