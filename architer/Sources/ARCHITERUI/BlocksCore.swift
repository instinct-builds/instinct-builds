#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ArchiterCore

/// Downscale an imported image to a bounded PNG so sheets stay portable.
func portraitPNG(from data: Data, maxSide: CGFloat = 256) -> Data? {
    guard let image = NSImage(data: data) else { return nil }
    let size = image.size
    guard size.width > 0, size.height > 0 else { return nil }
    let scale = min(1, maxSide / max(size.width, size.height))
    let target = NSSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(target.width),
                                     pixelsHigh: Int(target.height), bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(origin: .zero, size: target))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

struct PortraitView: View {
    @Binding var character: Character

    var body: some View {
        VStack(spacing: 4) {
            if let data = character.portrait, let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable().scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.surfaceRaised)
                    .frame(width: 64, height: 64)
                    .overlay(
                        Text(String(character.name.prefix(1)).uppercased())
                            .font(Theme.Typeface.display)
                            .foregroundStyle(Theme.inkFaint)
                    )
            }
            HStack(spacing: 6) {
                Button("Portrait") { choosePortrait() }
                    .controlSize(.small)
                if character.portrait != nil {
                    Button(role: .destructive) { character.portrait = nil } label: {
                        Image(systemName: "minus.circle")
                    }
                    .controlSize(.small)
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func choosePortrait() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url),
              let png = portraitPNG(from: data) else { return }
        character.portrait = png
    }
}

struct IdentityBlock: View {
    @Binding var character: Character
    @EnvironmentObject var model: AppModel
    @State private var xpToAdd = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Gap.md) {
            HStack(alignment: .firstTextBaseline) {
                PortraitView(character: $character)
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
                Picker("Rules", selection: $character.era) {
                    ForEach(RulesetVariant.allCases, id: \.self) { era in
                        Text(era.displayName).tag(era)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
                .help(character.era.summary)
                Stepper(value: $character.level, in: 1...20) {
                    Text("LVL \(character.level)")
                        .font(Theme.Typeface.headline.monospacedDigit())
                        .foregroundStyle(Theme.accent)
                }
                if character.level < 20 {
                    Menu {
                        Button("Roll HP (\(character.levelUpRollExpression))") { model.levelUp(rollHP: true) }
                        Button("Take average (+\(character.averageLevelUpHP))") { model.levelUp(rollHP: false) }
                    } label: {
                        Text("Level up")
                    }
                    .menuStyle(.borderlessButton)
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.accent)
                    .help("Level up: roll or average HP, slots and proficiency update automatically")
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
            ForEach($character.toolProficiencies) { $tool in
                ToolProficiencyRow(tool: $tool, character: character) {
                    character.toolProficiencies.removeAll { $0.id == tool.id }
                }
            }
            Button("Add tool proficiency") {
                character.toolProficiencies.append(ToolProficiency(name: ""))
            }
            .controlSize(.small)
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
    @State private var newSkillName = ""
    @State private var newSkillAbility: Ability = .wisdom

    var body: some View {
        BlockCard(title: "Skills") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Gap.lg), GridItem(.flexible(), spacing: Theme.Gap.lg)], spacing: 6) {
                ForEach($character.skills) { $skill in
                    HStack(spacing: Theme.Gap.xs) {
                        Text(skill.name)
                            .font(Theme.Typeface.body)
                            .lineLimit(1)
                        Text(skill.ability.abbreviation.uppercased())
                            .font(Theme.Typeface.captionSmall)
                            .foregroundStyle(Theme.inkFaint)
                        Picker("", selection: $skill.tier) {
                            ForEach(ProficiencyTier.allCases, id: \.self) { t in
                                Text(t.rawValue).tag(t)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 170)
                        Spacer()
                        Text(signed(skill.bonus(scores: character.scores, level: character.level)))
                            .font(Theme.Typeface.body.monospacedDigit().bold())
                            .foregroundStyle(skill.tier == .none ? Theme.inkMuted : Theme.accent)
                        RollChip(label: skill.name, bonus: skill.bonus(scores: character.scores, level: character.level))
                        Button(role: .destructive) {
                            character.removeSkill(named: skill.name)
                        } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack(spacing: Theme.Gap.sm) {
                TextField("New skill", text: $newSkillName)
                    .textFieldStyle(InsetFieldStyle())
                    .frame(maxWidth: 160)
                Picker("Ability", selection: $newSkillAbility) {
                    ForEach(Ability.allCases, id: \.self) { Text($0.abbreviation).tag($0) }
                }
                .frame(width: 110)
                Button("Add") {
                    if character.addSkill(name: newSkillName, ability: newSkillAbility) {
                        newSkillName = ""
                    }
                }
                .buttonStyle(RollButtonStyle())
                .disabled(newSkillName.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer()
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

/// A trained tool row: name, tier, the bonus readout, and a check roll
/// against a chosen ability - tools borrow their ability from the check,
/// so the roller picks it per roll (DEX is the common case).
private struct ToolProficiencyRow: View {
    @EnvironmentObject var model: AppModel
    @Binding var tool: ToolProficiency
    let character: Character
    let remove: () -> Void
    @State private var ability: Ability = .dexterity

    var body: some View {
        HStack(spacing: Theme.Gap.sm) {
            TextField("Tool", text: $tool.name)
                .textFieldStyle(InsetFieldStyle()).frame(maxWidth: 180)
            Picker("", selection: $tool.tier) {
                ForEach([ProficiencyTier.proficient, .expert], id: \.self) {
                    Text($0 == .expert ? "Expertise" : "Proficient").tag($0)
                }
            }
            .labelsHidden().frame(width: 110)
            Menu(ability.abbreviation) {
                ForEach(Ability.allCases, id: \.self) { a in
                    Button(a.abbreviation) { ability = a }
                }
            }
            .frame(width: 52)
            .help("Ability for the tool check")
            Button("Roll") {
                model.rollCheck("\(tool.name) check (\(ability.abbreviation))",
                                bonus: character.toolBonus(tool, ability: ability))
            }
            .buttonStyle(RollButtonStyle())
            .disabled(tool.name.trimmingCharacters(in: .whitespaces).isEmpty)
            Text("+\(tool.tier.multiplier * character.proficiencyBonus) over ability")
                .font(Theme.Typeface.caption).foregroundStyle(Theme.inkFaint)
            Button(role: .destructive, action: remove) {
                Image(systemName: "minus.circle")
            }
        }
        .font(.caption)
    }
}
#endif
