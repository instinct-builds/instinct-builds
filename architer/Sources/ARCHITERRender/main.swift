#if os(macOS)
import SwiftUI

import AppKit
import ARCHITERUI
import ArchiterCore

// Renders the app's key views with a rich sample character to PNGs, plus the
// PDF/HTML/Markdown exports, so CI can attach visual proof to each build.
// Usage: architer-render <output-directory>

func renderPNG<V: View>(_ view: V, width: CGFloat, name: String, outDir: String, minHeight: CGFloat = 120) {
    let hosting = NSHostingView(rootView: view)
    hosting.frame = NSRect(x: 0, y: 0, width: width, height: 100)
    hosting.layoutSubtreeIfNeeded()
    let fitting = hosting.fittingSize
    let size = NSSize(width: width, height: max(fitting.height, minHeight))
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: [.titled], backing: .buffered, defer: false)
    window.title = name
    window.contentView = hosting
    hosting.frame = NSRect(origin: .zero, size: size)
    window.layoutIfNeeded()
    hosting.layoutSubtreeIfNeeded()
    guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
        print("render failed (no bitmap): \(name)")
        return
    }
    hosting.cacheDisplay(in: hosting.bounds, to: rep)
    if let data = rep.representation(using: .png, properties: [:]) {
        let path = "\(outDir)/\(name).png"
        do {
            try data.write(to: URL(fileURLWithPath: path))
            let nonWhite = data.count
            print("rendered \(name).png (\(nonWhite) bytes, \(Int(size.width))x\(Int(size.height)))")
        } catch {
            print("render failed (write): \(name): \(error)")
        }
    } else {
        print("render failed (png encode): \(name)")
    }
    window.close()
}

@MainActor
func run(model: AppModel, character: Character, outDir: String) {
    let width: CGFloat = 1180
    renderPNG(
        SheetColumnView(character: .constant(character))
            .padding()
            .environmentObject(model),
        width: width, name: "sheet-full", outDir: outDir)
    renderPNG(
        BuilderView(character: .constant(character))
            .environmentObject(model),
        width: width, name: "builder", outDir: outDir, minHeight: 700)
    renderPNG(
        DiceRollerView()
            .environmentObject(model),
        width: width, name: "dice", outDir: outDir, minHeight: 420)

    // Exports as files.
    let pdf = SheetPDFExporter.export(character)
    try? pdf.write(to: URL(fileURLWithPath: "\(outDir)/sample-sheet.pdf"))
    try? SheetExporter.exportHTML(character).write(toFile: "\(outDir)/sample-sheet.html", atomically: true, encoding: .utf8)
    try? SheetExporter.exportMarkdown(character).write(toFile: "\(outDir)/sample-sheet.md", atomically: true, encoding: .utf8)
    print("exports written (pdf \(pdf.count) bytes)")
    print("RENDER DONE")
}

@main
struct RenderMain {
    @MainActor
    static func main() {
        let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "render-out"
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let model = AppModel()
        let character = SampleContent.demoCharacter()
        run(model: model, character: character, outDir: outDir)
        exit(0)
    }
}
#else
@main
struct RenderStub {
    static func main() { print("architer-render is macOS-only.") }
}
#endif
