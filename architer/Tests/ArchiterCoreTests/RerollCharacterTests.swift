import Foundation
import Testing
@testable import ArchiterCore

@Suite("Reroll character identity (3.27.0)")
struct RerollCharacterTests {
    @Test func legacySpecWithoutCharacterIDDecodes() throws {
        // Pre-3.27.0 history entries carry no characterID; they must decode
        // unchanged with a nil identity (nil falls back to the selection).
        let json = """
        {"kind":"check","baseLabel":"Stealth check","mode":"normal","checkBonus":6,"targetDC":12}
        """
        let spec = try JSONDecoder().decode(RerollSpec.self, from: Data(json.utf8))
        #expect(spec.kind == .check)
        #expect(spec.checkBonus == 6)
        #expect(spec.characterID == nil)
    }

    @Test func characterIDRoundTrips() throws {
        let id = UUID()
        let spec = RerollSpec(kind: .check, baseLabel: "Wren - Stealth check",
                              mode: .normal, checkBonus: 6, targetDC: 12, characterID: id)
        let data = try JSONEncoder().encode(spec)
        let back = try JSONDecoder().decode(RerollSpec.self, from: data)
        #expect(back.characterID == id)
        #expect(back.baseLabel == "Wren - Stealth check")
    }

    @Test func variantsPreserveCharacterID() {
        let id = UUID()
        let spec = RerollSpec(kind: .check, baseLabel: "Check", mode: .normal,
                              checkBonus: 4, targetDC: 10, characterID: id)
        #expect(spec.adjusted(for: .same).characterID == id)
        #expect(spec.adjusted(for: .advantage).characterID == id)
        #expect(spec.adjusted(for: .plusTwo).characterID == id)
        #expect(spec.adjusted(for: .plusTwo).checkBonus == 6)
    }
}
