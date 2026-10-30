#if os(macOS)
import SwiftUI
import ARCHITERUI
import ArchiterCore

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
                Button(model.undoMenuLabel) { model.undo() }
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
                Button("Export Session Log…") { model.exportSessionLog() }
                Button("Export Session Log (Markdown)…") { model.exportSessionLogMarkdown() }
                Toggle("Exports: Journal Entry Timestamps", isOn: $model.exportJournalTimestamps)
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
// Entry point: `--smoke <outdir>` runs the headless launch smoke used by CI
// to prove the installed DMG payload launches and renders; anything else
// starts the normal app.
@main
enum ARCHITERMain {
    static func main() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--smoke"), i + 1 < args.count {
            LaunchSmoke.run(outDir: args[i + 1])
        } else {
            ARCHITERApp.main()
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
