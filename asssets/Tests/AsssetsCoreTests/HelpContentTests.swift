import Foundation
import Testing
@testable import AsssetsCore

@Suite("Help window content")
struct HelpContentTests {
    func appSource() throws -> [String] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/AsssetsApp/App.swift")
        return try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
    }

    /// Reads `.keyboardShortcut("k", modifiers: [...])` from the declaring line or the next two.
    func shortcut(near i: Int, in lines: [String]) -> HelpContent.Shortcut? {
        for line in lines[i..<min(i + 3, lines.count)] {
            guard let r = line.range(of: ".keyboardShortcut(\"") else { continue }
            let rest = line[r.upperBound...]
            guard let q = rest.firstIndex(of: "\"") else { continue }
            let key = String(rest[..<q])
            var mods: Set<HelpContent.Mod> = [.command]
            if let m = rest.range(of: "modifiers: ") {
                mods = []
                let tail = rest[m.upperBound...].prefix { $0 != ")" }
                for mod in HelpContent.Mod.allCases where tail.contains(".\(mod.rawValue)") { mods.insert(mod) }
            }
            return HelpContent.Shortcut(key, mods)
        }
        return nil
    }

    @Test func everyListedControlExistsAndEveryShortcutIsWired() throws {
        let lines = try appSource()
        for section in HelpContent.sections {
            for e in section.entries {
                guard let anchor = e.anchor else { continue }
                guard let i = lines.firstIndex(where: { $0.contains(anchor) }) else {
                    Issue.record("Help lists \"\(e.title)\" but App.swift has no \(anchor)"); continue
                }
                if let want = e.shortcut {
                    let got = shortcut(near: i, in: lines)
                    #expect(got == want, "Help lists \(want.display) for \"\(e.title)\" but the app has \(got?.display ?? "none")")
                }
            }
        }
    }

    @Test func shortcutsAreUniqueAndEntriesAreNotEmpty() {
        var seen = Set<String>()
        for s in HelpContent.sections {
            #expect(!s.entries.isEmpty)
            for e in s.entries {
                #expect(!e.title.isEmpty && !e.detail.isEmpty)
                if let sc = e.shortcut, e.title != "Undo Import Client Feedback" { #expect(seen.insert(sc.display).inserted, "duplicate shortcut \(sc.display)") }
            }
        }
        #expect(HelpContent.Shortcut("d", [.command, .option]).display == "⌥⌘D")
        #expect(HelpContent.Shortcut("e", [.command, .shift]).display == "⇧⌘E")
        #expect(HelpContent.sections.count == 8)
    }
}
