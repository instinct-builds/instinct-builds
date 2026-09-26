#if os(macOS)
import SwiftUI
import ArchiterCore

func signed(_ n: Int) -> String { n >= 0 ? "+\(n)" : "\(n)" }

extension String {
    func camelCasedToWords() -> String {
        unicodeScalars.reduce("") { acc, s in
            if CharacterSet.uppercaseLetters.contains(s), !acc.isEmpty { return acc + " " + String(s).lowercased() }
            return acc + String(s)
        }.capitalized
    }
}

public struct ContentView: View {
    @EnvironmentObject var model: AppModel
    /// Delete confirmation (3.32.0): the trash arms an inline confirm,
    /// matching the history-delete/clear patterns - Delete fires only from
    /// the armed state, and the character's undo stack dies with it.
    @State private var confirmingDelete = false

    public init(initialConfirmingDelete: Bool = false) {
        _confirmingDelete = State(initialValue: initialConfirmingDelete)
    }

    public var body: some View {
        NavigationSplitView {
            List(selection: $model.selectedID) {
                ForEach(model.characters) { c in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.name)
                            .font(Theme.Typeface.headline)
                            .foregroundStyle(Theme.ink)
                        Text("Lvl \(c.level) \(c.lineage) \(c.calling)")
                            .font(Theme.Typeface.caption)
                            .foregroundStyle(Theme.inkMuted)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 2)
                    .tag(c.id)
                }
            }
            .navigationTitle("Characters")
            .toolbar {
                ToolbarItem { Button(action: { model.showWizard = true }) { Image(systemName: "plus") }
                    .help("New character (wizard)") }
                ToolbarItem { Button(action: { model.showCompendium = true }) { Image(systemName: "books.vertical") }
                    .help("Compendium - browse spells and equipment") }
                ToolbarItem { Button(action: model.duplicateSelected) { Image(systemName: "plus.square.on.square") }
                    .help("Duplicate") }
                ToolbarItem {
                    if confirmingDelete {
                        HStack(spacing: Theme.Gap.sm) {
                            Text("Delete \(model.selected?.wrappedValue.name ?? "character")?")
                                .font(Theme.Typeface.caption)
                                .foregroundStyle(Theme.inkMuted)
                            Button("Delete", role: .destructive) {
                                model.deleteSelected()
                                confirmingDelete = false
                            }
                            .controlSize(.small)
                            .help("Delete this character for good - this cannot be undone")
                            Button("Cancel") { confirmingDelete = false }
                                .controlSize(.small)
                        }
                    } else {
                        Button(action: { confirmingDelete = true }) { Image(systemName: "trash") }
                            .disabled(model.selectedID == nil)
                            .help("Delete the selected character, behind a confirm")
                    }
                }
            }
        } detail: {
            if let binding = model.selected {
                CharacterDetailView(character: binding)
            } else {
                ContentUnavailableView("No Character", systemImage: "person.crop.rectangle",
                                       description: Text("Create a character to begin."))
            }
        }
        .sheet(isPresented: $model.showWizard) {
            CharacterWizardView()
                .environmentObject(model)
        }
        .sheet(isPresented: $model.showCompendium) {
            CompendiumView()
                .environmentObject(model)
        }
        .tint(Theme.accent)
        .accentColor(Theme.accent)
        .preferredColorScheme(.dark)
        .background(Theme.surface)
        .foregroundStyle(Theme.ink)
    }
}

struct CharacterDetailView: View {
    @Binding var character: Character
    @EnvironmentObject var model: AppModel
    @AppStorage("architer.detailTab") private var tab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("Sheet").tag(0)
                Text("Builder").tag(1)
                Text("Dice").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Theme.Gap.lg)
            .padding(.vertical, Theme.Gap.sm)
            // 3.29.0: party overview strip - read-only roster awareness on
            // every tab; hidden at a roster of one (nothing to overview).
            if model.characters.count > 1 {
                PartyStripView()
            }
            switch tab {
            case 0:
                ScrollView {
                    SheetColumnView(character: $character)
                        .padding(Theme.Gap.lg)
                        .frame(maxWidth: 900)
                        .frame(maxWidth: .infinity)
                }
                .background(Theme.surface)
            case 1: BuilderView(character: $character)
            default: DiceRollerView()
            }
        }
    }
}

/// Party overview strip (3.29.0): one card per roster character - name,
/// level, HP with a thin bar, condition and concentration chips (truncated
/// with a "+N more" marker). Read-only: a tap selects via the same binding
/// the sidebar list uses; the sheet stays the only editor.
public struct PartyStripView: View {
    @EnvironmentObject var model: AppModel

    public init() {}

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Gap.sm) {
                ForEach(model.characters) { c in
                    let summary = PartyCardSummary(character: c)
                    let isSelected = model.selectedID == c.id
                    Button { model.selectedID = c.id } label: {
                        VStack(alignment: .leading, spacing: Theme.Gap.xs) {
                            HStack {
                                Text(summary.name)
                                    .font(Theme.Typeface.headline)
                                    .lineLimit(1)
                                Spacer()
                                Text("Lvl \(summary.level)")
                                    .font(Theme.Typeface.caption)
                                    .foregroundStyle(Theme.inkMuted)
                            }
                            HStack(spacing: Theme.Gap.xs) {
                                Text("\(summary.currentHP)/\(summary.maxHP)")
                                    .font(Theme.Typeface.caption)
                                HPBarView(fraction: summary.maxHP > 0
                                          ? Double(summary.currentHP) / Double(summary.maxHP) : 0)
                                if summary.tempHP > 0 {
                                    Text("+\(summary.tempHP) temp")
                                        .font(Theme.Typeface.captionSmall)
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                            HStack(spacing: Theme.Gap.xs) {
                                ForEach(summary.visibleChips, id: \.self) { chip in
                                    Text(chip)
                                        .font(Theme.Typeface.captionSmall)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Theme.surfaceRaised)
                                        .clipShape(Capsule())
                                }
                                if summary.extraChipCount > 0 {
                                    Text("+\(summary.extraChipCount) more")
                                        .font(Theme.Typeface.captionSmall)
                                        .foregroundStyle(Theme.inkMuted)
                                }
                            }
                        }
                        .padding(Theme.Gap.sm)
                        .frame(width: 220)
                        .background(Theme.surfaceRaised)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.md)
                                .stroke(isSelected ? Theme.accent : Color.clear,
                                        lineWidth: 2)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                    }
                    .buttonStyle(.plain)
                    .help(isSelected ? "\(summary.name) - selected" : "Select \(summary.name)")
                }
            }
            .padding(.horizontal, Theme.Gap.lg)
            .padding(.bottom, Theme.Gap.sm)
        }
    }
}

/// The strip's thin HP bar: current over max, accent on a muted track.
private struct HPBarView: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.inkMuted.opacity(0.3))
                Capsule().fill(Theme.accent)
                    .frame(width: geo.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(width: 64, height: 5)
    }
}

/// Renders every visible block of the sheet in layout order, then custom
/// ruleset sections and user-defined templated blocks. A plain VStack (not
/// lazy) so the whole column can also render offscreen to an image.
public struct SheetColumnView: View {
    @Binding public var character: Character

    public init(character: Binding<Character>) {
        _character = character
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            contentBlocks
        }
        .preferredColorScheme(.dark)
        .foregroundStyle(Theme.ink)
    }

    @ViewBuilder
    private var contentBlocks: some View {
        Group {
            ForEach(character.layout.visibleBlocks) { block in
                blockView(for: block)
                    .scaleEffect(block.size == .compact ? 0.92 : (block.size == .large ? 1.06 : 1.0),
                                 anchor: .topLeading)
            }
            if !character.customAbilities.isEmpty {
                CustomAbilitiesBlock(character: $character)
            }
            if !character.customSkills.isEmpty {
                CustomSkillsBlock(character: $character)
            }
            ForEach($character.layout.customBlocks) { $block in
                CustomBlockView(character: $character, block: $block)
            }
        }
    }

    @ViewBuilder
    private func blockView(for block: SheetBlock) -> some View {
        switch block.kind {
        case .identity: IdentityBlock(character: $character)
        case .abilities: AbilitiesBlock(character: $character)
        case .vitals: VitalsBlock(character: $character)
        case .skills: SkillsBlock(character: $character)
        case .attacks: AttacksBlock(character: $character)
        case .spells: SpellcastingBlock(character: $character)
        case .inventory: InventoryBlock(character: $character)
        case .features: FeaturesBlock(character: $character)
        case .personality: PersonalityBlock(character: $character)
        case .diceRoller: DiceInlineBlock()
        case .notes: NotesBlock(character: $character)
        case .journal: JournalBlock(character: $character)
        case .companions: CompanionsBlock(character: $character)
        }
    }
}

public struct BlockCard<Content: View, Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    public init(title: String, @ViewBuilder content: () -> Content) where Trailing == EmptyView {
        self.title = title
        self.trailing = EmptyView()
        self.content = content()
    }

    /// Header trailing accessory (2.53.0): small controls that act on the
    /// whole block, e.g. the journal's collapse-all.
    public init(title: String, @ViewBuilder content: () -> Content,
                @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Gap.md) {
            HStack(spacing: Theme.Gap.sm) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Theme.accent)
                    .frame(width: 3, height: 13)
                Text(title.uppercased())
                    .font(Theme.Typeface.headline)
                    .tracking(1.4)
                    .foregroundStyle(Theme.inkMuted)
                Spacer()
                trailing
            }
            VStack(alignment: .leading, spacing: Theme.Gap.md) { content }
        }
        .padding(Theme.Gap.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .strokeBorder(Theme.edge.opacity(0.55), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
    }
}

/// Small d20 roll button used across blocks.
struct RollChip: View {
    let label: String
    let bonus: Int
    @EnvironmentObject var model: AppModel

    var body: some View {
        Button(action: { model.rollCheck(label, bonus: bonus) }) {
            Text("\(signed(bonus)) ⟡")
                .font(Theme.Typeface.caption.monospacedDigit())
        }
        .buttonStyle(RollButtonStyle())
        .help("Roll \(label)")
    }
}

/// A custom templated block ({placeholders} rendered against the character).
struct CustomBlockView: View {
    @Binding var character: Character
    @Binding var block: CustomBlock

    var body: some View {
        BlockCard(title: TemplateRenderer.render(block.title, for: character)) {
            Text(TemplateRenderer.render(block.body, for: character))
                .font(.body)
                .textSelection(.enabled)
        }
    }
}
#endif
