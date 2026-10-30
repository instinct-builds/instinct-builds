#if os(macOS)
import SwiftUI
import AppKit
import ARCHITERUI
import ArchiterCore

// Headless launch smoke for the packaged binary: `ARCHITER --smoke <outdir>`
// renders one real party view through the app's own UI pipeline and writes a
// PNG, proving the DMG payload launches and renders from where it was
// installed - not merely that the pre-packaging build worked. Exits 0 on
// success, 1 with a named failure otherwise.
@MainActor
enum LaunchSmoke {
    static func run(outDir: String) {
        func fail(_ why: String) -> Never {
            print("launch-smoke failed (\(why))")
            exit(1)
        }
        do {
            try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        } catch { fail("mkdir: \(error)") }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.appearance = NSAppearance(named: .darkAqua)
        let model = AppModel()
        let character = SampleContent.demoCharacter()
        model.characters = [character]
        model.selectedID = character.id
        model.partyDetailPanelOpen = true

        let view = PartyDetailPanelView()
            .padding()
            .background(Theme.surface)
            .environmentObject(model)
        let hosting = NSHostingView(rootView: view)
        let width: CGFloat = 720
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: 100)
        hosting.layoutSubtreeIfNeeded()
        let fitting = hosting.fittingSize
        let size = NSSize(width: width, height: max(fitting.height, 120))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: size)
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            fail("no bitmap")
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            fail("png encode")
        }
        let path = "\(outDir)/viz-launch-smoke.png"
        do {
            try data.write(to: URL(fileURLWithPath: path))
        } catch { fail("write: \(error)") }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              (attrs[.size] as? Int ?? 0) > 0 else {
            fail("empty png")
        }
        print("launch-smoke OK: rendered viz-launch-smoke.png (\(data.count) bytes, \(Int(size.width))x\(Int(size.height))) from installed payload")
        window.close()
        exit(0)
    }
}
#endif
