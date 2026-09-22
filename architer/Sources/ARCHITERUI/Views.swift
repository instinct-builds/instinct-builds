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

    public init() {}

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
                ToolbarItem { Button(action: model.duplicateSelected) { Image(systemName: "plus.square.on.square") }
                    .help("Duplicate") }
                ToolbarItem { Button(action: model.deleteSelected) { Image(systemName: "trash") }
                    .help("Delete") }
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
    @State private var tab = 0

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
        }
    }
}

public struct BlockCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    public init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
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
