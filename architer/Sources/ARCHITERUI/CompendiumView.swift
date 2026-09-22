#if os(macOS)
import SwiftUI
import ArchiterCore

/// The compendium: a searchable browser over the built-in spell and
/// equipment libraries (all original content), with add-to-character.
struct CompendiumView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0
    @State private var query = ""
    @State private var levelFilter: Int? = nil
    @State private var favoritesOnly = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("COMPENDIUM")
                    .font(Theme.Typeface.title)
                    .foregroundStyle(Theme.ink)
                Spacer()
                Picker("", selection: $tab) {
                    Text("Spells").tag(0)
                    Text("Weapons").tag(1)
                    Text("Armor").tag(2)
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
            }
            .padding()
            HStack(spacing: Theme.Gap.sm) {
                TextField("Search \(tab == 0 ? "spells" : tab == 1 ? "weapons" : "armor")…", text: $query)
                    .textFieldStyle(InsetFieldStyle())
                if tab == 0 {
                    Picker("Level", selection: $levelFilter) {
                        Text("All").tag(Int?.none)
                        Text("Cantrip").tag(Int?.some(0))
                        ForEach(1...9, id: \.self) { Text("Lvl \($0)").tag(Int?.some($0)) }
                    }
                    .frame(width: 130)
                }
                Button {
                    favoritesOnly.toggle()
                } label: {
                    Image(systemName: favoritesOnly ? "star.fill" : "star")
                        .foregroundStyle(favoritesOnly ? Theme.accent : Theme.inkMuted)
                }
                .buttonStyle(.plain)
                .help(favoritesOnly ? "Showing favorites only" : "Show favorites only")
            }
            .padding(.horizontal)
            Divider().overlay(Theme.edge).padding(.top, Theme.Gap.sm)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Gap.sm) {
                    switch tab {
                    case 0: spellsList
                    case 1: weaponsList
                    default: armorList
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 640, minHeight: 520)
        .background(Theme.surface)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var spellsList: some View {
        let matches = SpellLibrary.search(query, level: levelFilter)
            .filter { !favoritesOnly || model.favorites.contains(kind: .spell, name: $0.name) }
        if matches.isEmpty {
            Text("No library spell matches.")
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.inkMuted)
        }
        ForEach(matches) { spell in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(spell.name)
                        .font(Theme.Typeface.headline)
                        .foregroundStyle(Theme.ink)
                    if spell.ritual { badge("R", Theme.arcana) }
                    if spell.concentration { badge("C", Theme.accent) }
                    Spacer()
                    starToggle(kind: .spell, name: spell.name)
                    Text(spell.level == 0 ? "Cantrip" : "Level \(spell.level)")
                        .font(Theme.Typeface.caption)
                        .foregroundStyle(Theme.arcana)
                    Button("Add") { addSpell(spell) }
                        .buttonStyle(RollButtonStyle())
                        .disabled(model.selected?.wrappedValue.spellcasting == nil)
                }
                Text([spell.school, spell.castingTime, spell.range, spell.duration]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.inkMuted)
                if !spell.detail.isEmpty {
                    Text(spell.detail)
                        .font(Theme.Typeface.caption)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Theme.Gap.md)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        }
        if model.selected?.wrappedValue.spellcasting == nil {
            Text("The selected character has no spellcasting - enable it on the sheet to add spells.")
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.inkFaint)
        }
    }

    @ViewBuilder private var weaponsList: some View {
        ForEach(EquipmentLibrary.searchWeapons(query)
            .filter { !favoritesOnly || model.favorites.contains(kind: .weapon, name: $0.name) }) { w in
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(w.name)
                        .font(Theme.Typeface.headline)
                        .foregroundStyle(Theme.ink)
                    Text("\(w.damageExpression) \(w.damageType) · \(w.range)\(w.finesse ? " · finesse" : "")")
                        .font(Theme.Typeface.caption)
                        .foregroundStyle(Theme.inkMuted)
                    if !w.properties.isEmpty {
                        Text(w.properties)
                            .font(Theme.Typeface.captionSmall)
                            .foregroundStyle(Theme.inkFaint)
                    }
                }
                Spacer()
                starToggle(kind: .weapon, name: w.name)
                Text("\(w.weight, specifier: "%.1f") lb")
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.inkFaint)
                Button("Add") { addWeapon(w) }
                    .buttonStyle(RollButtonStyle())
            }
            .padding(Theme.Gap.md)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        }
    }

    @ViewBuilder private var armorList: some View {
        ForEach(EquipmentLibrary.searchArmor(query)
            .filter { !favoritesOnly || model.favorites.contains(kind: .armor, name: $0.name) }) { a in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(a.name)
                        .font(Theme.Typeface.headline)
                        .foregroundStyle(Theme.ink)
                    Text("AC \(a.baseAC)\(a.addDex ? " + Dex" : "")\(a.maxDexBonus.map { " (max +\($0))" } ?? "") · \(a.category.rawValue.capitalized)")
                        .font(Theme.Typeface.caption)
                        .foregroundStyle(Theme.inkMuted)
                }
                Spacer()
                starToggle(kind: .armor, name: a.name)
                Text(a.cost)
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.inkFaint)
                Button("Equip") { equipArmor(a) }
                    .buttonStyle(RollButtonStyle())
            }
            .padding(Theme.Gap.md)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        }
    }

    private func starToggle(kind: CompendiumKind, name: String) -> some View {
        let isFav = model.favorites.contains(kind: kind, name: name)
        return Button {
            model.toggleFavorite(kind: kind, name: name)
        } label: {
            Image(systemName: isFav ? "star.fill" : "star")
                .foregroundStyle(isFav ? Theme.accent : Theme.inkFaint)
        }
        .buttonStyle(.plain)
        .help(isFav ? "Remove from favorites" : "Add to favorites")
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(Theme.Typeface.captionSmall)
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(color.opacity(0.25), in: Capsule())
            .foregroundStyle(color)
    }

    private func addSpell(_ spell: Spell) {
        guard var c = model.selected?.wrappedValue, c.spellcasting != nil else { return }
        var copy = spell
        copy.id = UUID()
        c.spellcasting?.spells.append(copy)
        model.selected?.wrappedValue = c
    }

    private func addWeapon(_ w: WeaponDef) {
        guard var c = model.selected?.wrappedValue else { return }
        c.attacks.append(Attack(
            name: w.name,
            ability: w.finesse ? nil : .strength,
            proficient: true,
            damageExpression: w.damageExpression,
            damageType: w.damageType,
            range: w.range,
            notes: w.properties))
        model.selected?.wrappedValue = c
    }

    private func equipArmor(_ a: ArmorDef) {
        guard var c = model.selected?.wrappedValue else { return }
        c.equippedArmor = a.name
        model.selected?.wrappedValue = c
    }
}
#endif
