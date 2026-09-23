import Testing
@testable import AsssetsCore

@Suite("Drag out")
struct DragOutTests {
    @Test func originalFileWhenUnchanged() {
        #expect(DragOut.plan(title: "Blueprint 2K", importedPath: "/lib/blueprint-4k.png", fileExists: true, look: .init()) == .file("/lib/blueprint-4k.png"))
    }

    @Test func renderWhenTheLookDiffers() {
        #expect(DragOut.plan(title: "Phone Screen Mockup", importedPath: "/lib/p.psd", fileExists: true, look: .init(psdLayersChanged: true))
                == .render("Phone Screen Mockup (layers).png"))
        #expect(DragOut.plan(title: "Night Grid 2K", importedPath: "/lib/n.png", fileExists: true, look: .init(tiled: true, seamsFixed: true))
                == .render("Night Grid 2K (tiled, seamless).png"))
        #expect(DragOut.plan(title: "Aurora Study", importedPath: nil, fileExists: false, look: .init()) == .render("Aurora Study.png"))
        #expect(DragOut.plan(title: "Gone", importedPath: "/lib/missing.png", fileExists: false, look: .init()) == .render("Gone.png"))
        #expect(DragOut.plan(title: "Warm", importedPath: "/lib/w.png", fileExists: true, look: .init(effectApplied: true)) == .render("Warm (edit).png"))
    }

    @Test func safeNames() {
        #expect(DragOut.safeName("a/b:c") == "a-b-c")
        #expect(DragOut.safeName("  .hidden  ") == "hidden")
        #expect(DragOut.safeName("\n") == "Asset")
        #expect(DragOut.safeName(String(repeating: "x", count: 300)).count == 120)
    }
}
