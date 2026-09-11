#if os(macOS)
import SwiftUI
import ArchiterCore

@main
struct ARCHITERApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("ARCHITER") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 900, minHeight: 600)
        }
        .commands {
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { model.undo() }
                    .keyboardShortcut("z", modifiers: [.command])
                    .disabled(!model.canUndo)
                Button("Redo") { model.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!model.canRedo)
            }
            CommandGroup(after: .importExport) {
                Button("Export Markdown…") { model.exportMarkdown() }
                    .keyboardShortcut("e", modifiers: [.command])
                Button("Export HTML…") { model.exportHTML() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                Button("Export PDF…") { model.exportPDF() }
                    .keyboardShortcut("p", modifiers: [.command])
            }
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var characters: [Character] = []
    @Published var selectedID: UUID?
    @Published var rollHistory: [RollResult] = []
    @Published private var undoStacks: [UUID: UndoStack<Character>] = [:]

    let store = CharacterStore.defaultStore()
    let roller = DiceRoller()

    var selected: Binding<Character>? {
        guard let id = selectedID, let idx = characters.firstIndex(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { self.characters[idx] },
            set: { newValue in
                guard newValue != self.characters[idx] else { return }
                var stack = self.undoStacks[id] ?? UndoStack(self.characters[idx])
                stack.push(newValue)
                self.undoStacks[id] = stack
                self.characters[idx] = newValue
                try? self.store.save(newValue)
            }
        )
    }

    init() { reload() }

    func reload() {
        characters = (try? store.loadAll()) ?? []
        if selectedID == nil { selectedID = characters.first?.id }
    }

    func newCharacter() {
        let c = Character(name: "Unnamed Adventurer")
        characters.append(c)
        try? store.save(c)
        selectedID = c.id
    }

    func deleteSelected() {
        guard let id = selectedID, let idx = characters.firstIndex(where: { $0.id == id }) else { return }
        try? store.delete(characters[idx])
        characters.remove(at: idx)
        selectedID = characters.first?.id
    }

    func roll(_ expression: String) {
        if let r = try? roller.roll(expression) {
            rollHistory.insert(r, at: 0)
        }
    }

    func rollD20(mode: RollMode, modifier: Int) {
        rollHistory.insert(roller.rollD20(mode: mode, modifier: modifier), at: 0)
    }

    func exportMarkdown() {
        guard let sel = selected?.wrappedValue else { return }
        savePanel(text: SheetExporter.exportMarkdown(sel), name: "\(sel.name).md")
    }

    func exportHTML() {
        guard let sel = selected?.wrappedValue else { return }
        savePanel(text: SheetExporter.exportHTML(sel), name: "\(sel.name).html")
    }

    func exportPDF() {
        guard let sel = selected?.wrappedValue else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(sel.name).pdf"
        if panel.runModal() == .OK, let url = panel.url {
            try? SheetPDFExporter.export(sel).write(to: url)
        }
    }

    // MARK: Undo

    var canUndo: Bool { selectedID.flatMap { undoStacks[$0] }?.canUndo ?? false }
    var canRedo: Bool { selectedID.flatMap { undoStacks[$0] }?.canRedo ?? false }

    func undo() {
        guard let id = selectedID, let idx = characters.firstIndex(where: { $0.id == id }),
              var stack = undoStacks[id], stack.canUndo else { return }
        _ = stack.undo()
        undoStacks[id] = stack
        characters[idx] = stack.current
        try? store.save(stack.current)
    }

    func redo() {
        guard let id = selectedID, let idx = characters.firstIndex(where: { $0.id == id }),
              var stack = undoStacks[id], stack.canRedo else { return }
        _ = stack.redo()
        undoStacks[id] = stack
        characters[idx] = stack.current
        try? store.save(stack.current)
    }

    private func savePanel(text: String, name: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        if panel.runModal() == .OK, let url = panel.url {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
#else
@main
struct LinuxBuildStub {
    static func main() {
        print("ARCHITER is a native macOS app. On this platform, use the ArchiterCore library and its test suite.")
    }
}
#endif
