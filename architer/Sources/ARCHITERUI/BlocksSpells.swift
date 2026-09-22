#if os(macOS)
import SwiftUI
import ArchiterCore

struct SpellcastingBlock: View {
    @Binding var character: Character
    @EnvironmentObject var model: AppModel
    @State private var searchText = ""

    var body: some View {
        BlockCard(title: "Spells") {
            if character.spellcasting == nil {
                HStack {
                    Text("Not a spellcaster yet.").foregroundStyle(.secondary)
                    Button("Enable spellcasting") {
                        character.spellcasting = Spellcasting(ability: .intelligence, progression: .full)
                    }
                }
            } else {
                let sc = character.spellcasting!
                // Config row
                HStack {
                    Picker("Casting ability", selection: Binding(
                        get: { sc.ability },
                        set: { character.spellcasting?.ability = $0 }
                    )) {
                        ForEach([Ability.intelligence, .wisdom, .charisma], id: \.self) {
                            Text($0.displayName).tag($0)
                        }
                    }
                    .frame(maxWidth: 220)
                    Picker("Progression", selection: Binding(
                        get: { sc.progression },
                        set: { character.spellcasting?.progression = $0 }
                    )) {
                        ForEach(CasterProgression.allCases, id: \.self) {
                            Text($0.displayName).tag($0)
                        }
                    }
                    .frame(maxWidth: 200)
                    Button("Disable spellcasting") { character.spellcasting = nil }
                        .foregroundStyle(.red)
                }
                HStack {
                    Text("Spell attack \(signed(sc.spellAttackBonus(scores: character.scores, level: character.level)))")
                    Text("Save DC \(sc.spellSaveDC(scores: character.scores, level: character.level))")
                        .foregroundStyle(.secondary)
                }
                Divider().overlay(Theme.edge)
                // Slots
                ForEach(1...9, id: \.self) { sl in
                    let maxSlots = sc.slotsMax(spellLevel: sl, casterLevel: character.level)
                    if maxSlots > 0 {
                        SlotRow(character: $character, spellLevel: sl, maxSlots: maxSlots)
                    }
                }
                Divider().overlay(Theme.edge)
                // Library search
                HStack {
                    TextField("Add spell from the built-in library (\(SpellLibrary.all.count) spells)…", text: $searchText)
                        .textFieldStyle(InsetFieldStyle())
                    if !searchText.isEmpty {
                        Button("Clear") { searchText = "" }
                    }
                }
                if !searchText.isEmpty {
                    let matches = SpellLibrary.all.filter {
                        $0.name.localizedCaseInsensitiveContains(searchText)
                    }
                    if matches.isEmpty {
                        Text("No library spell matches.").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(matches.prefix(6)) { spell in
                        HStack {
                            Text(spell.name).bold()
                            Text(spell.level == 0 ? "cantrip" : "level \(spell.level)")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(spell.school).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Add") {
                                var newSpell = spell
                                newSpell.id = UUID()
                                character.spellcasting?.spells.append(newSpell)
                                searchText = ""
                            }
                            .controlSize(.small)
                        }
                    }
                }
                if let limit = character.preparedSpellLimit {
                    let prepared = character.spellcasting?.spells.filter { $0.prepared && $0.level > 0 }.count ?? 0
                    HStack(spacing: Theme.Gap.xs) {
                        Text("Prepared \(prepared) / \(limit)")
                            .font(Theme.Typeface.caption.monospacedDigit())
                            .foregroundStyle(prepared > limit ? Theme.danger : Theme.inkMuted)
                        Text("(\(character.era.displayName))")
                            .font(Theme.Typeface.captionSmall)
                            .foregroundStyle(Theme.inkFaint)
                    }
                }
                // Known/prepared spells grouped by level
                SpellGroup(character: $character, level: 0)
                ForEach(1...9, id: \.self) { sl in
                    SpellGroup(character: $character, level: sl)
                }
            }
        }
    }
}

struct SlotRow: View {
    @Binding var character: Character
    let spellLevel: Int
    let maxSlots: Int
    @EnvironmentObject var model: AppModel

    var body: some View {
        let used = character.spellcasting?.slotsUsed[spellLevel - 1] ?? 0
        HStack(spacing: Theme.Gap.sm) {
            Text("LVL \(spellLevel)")
                .font(Theme.Typeface.statLabel).tracking(1)
                .foregroundStyle(Theme.inkMuted)
                .frame(width: 46, alignment: .leading)
            Pips(filled: maxSlots - used, total: maxSlots, tint: Theme.arcana)
            Text("\(maxSlots - used)/\(maxSlots)")
                .font(Theme.Typeface.caption.monospacedDigit())
                .foregroundStyle(Theme.inkMuted)
            Spacer()
            Button("Cast at level \(spellLevel)") {
                model.castSpell(atSlotLevel: spellLevel)
            }
            .buttonStyle(RollButtonStyle())
            .controlSize(.small)
            .disabled(used >= maxSlots)
            Button("Restore one") {
                character.spellcasting?.restoreSlot(spellLevel: spellLevel)
            }
            .controlSize(.small)
            .disabled(used == 0)
        }
        .font(.callout)
    }
}

struct SpellGroup: View {
    @Binding var character: Character
    let level: Int
    @EnvironmentObject var model: AppModel
    @State private var expandedIDs: Set<UUID> = []

    var body: some View {
        let spells = character.spellcasting?.spells(atLevel: level) ?? []
        if !spells.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(level == 0 ? "CANTRIPS" : "LEVEL \(level)")
                    .font(Theme.Typeface.statLabel).tracking(1.2)
                    .foregroundStyle(Theme.arcana)
                ForEach(spells) { spell in
                    HStack(alignment: .top) {
                        Toggle("", isOn: Binding(
                            get: { spell.prepared },
                            set: { on in
                                if let idx = character.spellcasting?.spells.firstIndex(where: { $0.id == spell.id }) {
                                    character.spellcasting?.spells[idx].prepared = on
                                }
                            }
                        ))
                        .labelsHidden()
                        .help("Prepared")
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: Theme.Gap.xs) {
                                Button(action: {
                                    if expandedIDs.contains(spell.id) { expandedIDs.remove(spell.id) }
                                    else { expandedIDs.insert(spell.id) }
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: expandedIDs.contains(spell.id) ? "chevron.down" : "chevron.right")
                                            .font(.caption2)
                                            .foregroundStyle(Theme.inkFaint)
                                        Text(spell.name)
                                            .font(Theme.Typeface.body.bold())
                                            .foregroundStyle(Theme.ink)
                                    }
                                }
                                .buttonStyle(.plain)
                                if spell.ritual {
                                    Text("R")
                                        .font(Theme.Typeface.captionSmall)
                                        .padding(.horizontal, 4).padding(.vertical, 1)
                                        .background(Theme.arcana.opacity(0.25), in: Capsule())
                                        .foregroundStyle(Theme.arcana)
                                        .help("Ritual")
                                }
                                if spell.concentration {
                                    Text("C")
                                        .font(Theme.Typeface.captionSmall)
                                        .padding(.horizontal, 4).padding(.vertical, 1)
                                        .background(Theme.accent.opacity(0.22), in: Capsule())
                                        .foregroundStyle(Theme.accent)
                                        .help("Concentration")
                                }
                            }
                            Text([spell.school, spell.castingTime, spell.range, spell.duration]
                                    .filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(Theme.Typeface.caption)
                                .foregroundStyle(Theme.inkMuted)
                            if expandedIDs.contains(spell.id) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Components: \(spell.components)")
                                        .font(Theme.Typeface.caption)
                                        .foregroundStyle(Theme.inkMuted)
                                    if !spell.detail.isEmpty {
                                        Text(spell.detail)
                                            .font(Theme.Typeface.caption)
                                            .foregroundStyle(Theme.ink)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                .padding(Theme.Gap.sm)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.surfaceInset, in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
                            } else if !spell.detail.isEmpty {
                                Text(spell.detail)
                                    .font(Theme.Typeface.caption)
                                    .foregroundStyle(Theme.inkMuted)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        if spell.level > 0, character.spellcasting != nil {
                            let lvl = spell.level
                            let remaining = character.spellcasting?.slotsRemaining(spellLevel: lvl, casterLevel: character.level) ?? 0
                            Button("Cast") { model.castSpell(atSlotLevel: lvl) }
                                .buttonStyle(RollButtonStyle(prominent: true))
                                .disabled(remaining == 0)
                        }
                        Button(role: .destructive) {
                            character.spellcasting?.spells.removeAll { $0.id == spell.id }
                        } label: { Image(systemName: "minus.circle") }
                    }
                }
            }
            Divider().overlay(Theme.edge)
        }
    }
}
#endif
