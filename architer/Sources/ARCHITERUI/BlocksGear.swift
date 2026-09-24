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
            // Weight + attunement
            HStack {
                Text("Carried \(fmtWeight(character.totalWeight)) / \(character.carryingCapacity) lb")
                    .monospacedDigit()
                if character.stowedWeight > 0 {
                    Text("(+\(fmtWeight(character.stowedWeight)) stowed)")
                        .font(.caption)
                        .foregroundStyle(Theme.inkFaint)
                }
                Text("Attuned \(character.attunedCount)/\(Character.attunementLimit)")
                    .monospacedDigit()
                    .foregroundStyle(character.overAttuned ? Theme.danger : Theme.inkMuted)
                if character.overAttuned {
                    Text("OVER LIMIT")
                        .font(.caption).bold()
                        .foregroundStyle(Theme.danger)
                }
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
                    // 2.37.0: one-tap consume/restock through the same
                    // binding, so each tap is a normal undoable edit.
                    HStack(spacing: 2) {
                        Button { item.consumeOne() } label: { Image(systemName: "minus.circle") }
                            .disabled(item.quantity == 0)
                            .help("Use one - undoable with Cmd-Z")
                        Text("×\(item.quantity)")
                            .font(.callout.monospacedDigit())
                            .frame(minWidth: 32)
                        Button { item.restockOne() } label: { Image(systemName: "plus.circle") }
                            .disabled(item.quantity == 999)
                            .help("Restock one - undoable with Cmd-Z")
                    }
                    TextField("lb", value: Binding(
                        get: { item.weight ?? 0 },
                        set: { item.weight = $0 == 0 ? nil : $0 }
                    ), format: .number)
                        .frame(width: 60)
                    Toggle("Attuned", isOn: $item.attuned).toggleStyle(.checkbox).font(.caption)
                    Toggle("Stowed", isOn: $item.stowed).toggleStyle(.checkbox).font(.caption)
                        .help("Dropped or cached: not counted as carried")
                    TextField("Notes", text: $item.notes)
                    Button(role: .destructive) {
                        character.inventory.removeAll { $0.id == item.id }
                    } label: { Image(systemName: "minus.circle") }
                }
                .opacity(item.stowed ? 0.55 : 1)
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

public struct JournalBlock: View {
    @Binding var character: Character
    @EnvironmentObject var model: AppModel
    /// 2.54.0: header filter text; display-only, never persisted.
    @State private var filter: String

    public init(character: Binding<Character>, initialFilter: String = "") {
        _character = character
        _filter = State(initialValue: initialFilter)
    }

    /// Case-insensitive match over date, title, and body (2.54.0); an
    /// empty query keeps every entry visible.
    private func matches(_ entry: JournalEntry, query: String) -> Bool {
        query.isEmpty
            || entry.title.lowercased().contains(query)
            || entry.date.lowercased().contains(query)
            || entry.text.lowercased().contains(query)
    }

    public var body: some View {
        let query = filter.trimmingCharacters(in: .whitespaces).lowercased()
        BlockCard(title: "Journal") {
            ForEach($character.journal) { $entry in
                if matches(entry, query: query) {
                let long = entry.isLong
                let collapsed = (entry.isCollapsed ?? false) && long
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        TextField("Date", text: $entry.date)
                            .textFieldStyle(InsetFieldStyle())
                            .frame(width: 110)
                        TextField("Title", text: $entry.title)
                            .textFieldStyle(InsetFieldStyle())
                        // 2.57.0: bulk at a glance - lines for multiline,
                        // words for single-line entries.
                        if let size = entry.sizeLabel {
                            Text(size)
                                .font(Theme.Typeface.caption)
                                .foregroundStyle(Theme.inkFaint)
                        }
                        // 2.51.0: long entries collapse to a one-line
                        // preview; the state persists on the entry.
                        if long {
                            Button { entry.isCollapsed = !collapsed } label: {
                                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.inkFaint)
                            .help(collapsed ? "Expand entry" : "Collapse entry")
                        }
                        // 2.55.0: copy this one entry (head + body).
                        Button { model.copyJournalEntryToPasteboard(entry) } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.inkFaint)
                        .help("Copy this entry")
                        // 2.56.0: duplicate this entry right below.
                        Button { character.duplicateJournalEntry(entry.id) } label: {
                            Image(systemName: "plus.square.on.square")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.inkFaint)
                        .help("Duplicate this entry")
                        // 2.50.0: nudge entries into the user's order;
                        // exports and the session recap follow it.
                        Button { character.moveJournalEntry(entry.id, by: -1) }
                            label: { Image(systemName: "chevron.up") }
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.inkFaint)
                            .help("Move entry up")
                            .disabled(character.journal.first?.id == entry.id)
                        Button { character.moveJournalEntry(entry.id, by: 1) }
                            label: { Image(systemName: "chevron.down") }
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.inkFaint)
                            .help("Move entry down")
                            .disabled(character.journal.last?.id == entry.id)
                        Button(role: .destructive) {
                            character.journal.removeAll { $0.id == entry.id }
                        } label: { Image(systemName: "minus.circle") }
                    }
                    if collapsed {
                        Text(entry.text.replacingOccurrences(of: "\n", with: "  "))
                            .font(.callout)
                            .foregroundStyle(Theme.inkFaint)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    } else {
                        TextEditor(text: $entry.text)
                            .frame(minHeight: 44)
                            .font(.callout)
                    }
                }
                .padding(.vertical, 2)
                }
            }
            HStack {
                Button("Add entry") {
                    character.journal.append(JournalEntry(
                        date: JournalStamp.day(Date()),
                        title: "Session \(character.journal.count + 1)",
                        createdAt: Date()))
                }
                .controlSize(.small)
                // 2.59.0: stamp a starter outline in as a new entry.
                Menu("From template") {
                    ForEach(JournalTemplate.builtIn) { template in
                        Button(template.name) { character.addJournalEntry(from: template) }
                    }
                }
                .controlSize(.small)
                .menuStyle(.borderlessButton)
                .fixedSize()
                // 2.46.0: one-tap recap - today's journal entries and
                // rolls as one shareable text block.
                Button("Copy today") { model.copySessionRecapToPasteboard(character) }
                    .controlSize(.small)
                    .help("Copy today's journal entries and rolls as one shareable recap")
            }
        } trailing: {
            HStack(spacing: Theme.Gap.sm) {
                // 2.54.0: filter the journal by date/title/body;
                // display-only, pairs with collapse-all for scanning.
                if !query.isEmpty {
                    let shown = character.journal.filter { matches($0, query: query) }.count
                    Text("\(shown)/\(character.journal.count)")
                        .font(Theme.Typeface.caption)
                        .foregroundStyle(Theme.inkFaint)
                }
                TextField("Filter", text: $filter)
                    .textFieldStyle(InsetFieldStyle())
                    .frame(width: 130)
                // 2.53.0: one-tap scan - collapse every long entry at
                // once, or expand them all back. Persisted per entry.
                let anyLong = character.journal.contains { $0.isLong }
                let anyExpanded = character.journal.contains { $0.isLong && !($0.isCollapsed ?? false) }
                if anyLong {
                    Button { character.setAllJournalCollapsed(anyExpanded) } label: {
                        Image(systemName: anyExpanded
                              ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.inkFaint)
                    .help(anyExpanded ? "Collapse all long entries" : "Expand all entries")
                }
            }
        }
    }
}

struct CompanionsBlock: View {
    @Binding var character: Character

    var body: some View {
        BlockCard(title: "Companions") {
            ForEach($character.companions) { $comp in
                VStack(spacing: 4) {
                    HStack {
                        TextField("Name", text: $comp.name)
                            .textFieldStyle(InsetFieldStyle()).frame(minWidth: 140)
                        TextField("Kind", text: $comp.kind)
                            .textFieldStyle(InsetFieldStyle()).frame(maxWidth: 130)
                        Stepper("AC \(comp.armorClass)", value: $comp.armorClass, in: 0...30)
                        Stepper("HP \(comp.currentHP)/\(comp.maxHP)", value: Binding(
                            get: { comp.currentHP },
                            set: { comp.currentHP = max(0, min(comp.maxHP, $0)) }), in: 0...999)
                        Stepper("Max \(comp.maxHP)", value: Binding(
                            get: { comp.maxHP },
                            set: {
                                comp.maxHP = max(1, $0)
                                comp.currentHP = min(comp.currentHP, comp.maxHP)
                            }), in: 1...999)
                        Button(role: .destructive) {
                            character.companions.removeAll { $0.id == comp.id }
                        } label: { Image(systemName: "minus.circle") }
                    }
                    .font(.caption)
                    TextField("Notes", text: $comp.notes)
                        .textFieldStyle(InsetFieldStyle())
                }
                .padding(.vertical, 2)
            }
            Button("Add companion") {
                character.companions.append(Companion(name: "New companion"))
            }
            .controlSize(.small)
        }
    }
}
#endif
