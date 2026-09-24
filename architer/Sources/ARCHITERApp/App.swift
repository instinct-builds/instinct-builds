#if os(macOS)
import SwiftUI
import ARCHITERUI
import ArchiterCore

@main
struct ARCHITERApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("ARCHITER") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 1024, minHeight: 680)
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
                Button("Export Compact PDF…") { model.exportCompactPDF() }
                    .keyboardShortcut("p", modifiers: [.command])
                Button("Export Compact PDF (Landscape)…") { model.exportCompactPDF(landscape: true) }
                Toggle("Compact PDF: Hide Empty Rows", isOn: $model.compactPDFHideEmptyRows)
                Toggle("Compact PDF: Session Log Appendix", isOn: $model.compactPDFSessionLog)
                Picker("Compact PDF: Session Log Range", selection: $model.compactPDFSessionLogRange) {
                    ForEach(SessionLogRange.allCases, id: \.self) { range in
                        Text(range.displayName).tag(range)
                    }
                }
                Divider()
                Button("Export Character File…") { model.exportCharacterJSON() }
                Button("Import Character File…") { model.importCharacterJSON() }
                Divider()
                Button("Load Sample Character") { model.loadSample() }
            }
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
