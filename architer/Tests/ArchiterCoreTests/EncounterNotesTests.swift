import Foundation
import Testing
@testable import ArchiterCore

/// Encounter notes + party journal search (3.46.0): the note decodes
/// leniently from pre-3.46.0 libraries, round-trips through the store,
/// and the party search attributes hits to the right character with the
/// per-character filter's own match rule.
@Suite struct EncounterNotesTests {
    @Test func pre346LibraryDecodesWithoutNotes() throws {
        let json = """
        [{"id": "\(UUID().uuidString)", "name": "Proof Den",
          "lines": [{"id": "\(UUID().uuidString)", "count": 2, "cr": 3.0, "label": "Gnolls"}]}]
        """
        let decoded = try JSONDecoder().decode([SavedEncounter].self, from: Data(json.utf8))
        #expect(decoded.count == 1)
        #expect(decoded[0].notes == "")
        #expect(decoded[0].summary == "2x Gnolls")
    }

    @Test func notesRoundTripThroughStore() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let store = EncounterLibraryStore(directory: dir)
        let saved = SavedEncounter(name: "Proof Den",
                                   lines: [EncounterLine(count: 2, cr: 3, label: "Gnolls")],
                                   notes: "focus the casters")
        store.save([saved])
        let loaded = store.load()
        #expect(loaded == [saved])
        #expect(loaded.first?.notes == "focus the casters")
    }

    @Test func partyJournalSearchAttributesAndMatches() throws {
        var wren = SampleContent.demoCharacter()
        wren.name = "Wren Halloway"
        wren.journal = [JournalEntry(date: "Session 8", title: "Fire season", text: "The bridge burned.")]
        var bram = SampleContent.demoCharacter()
        bram.id = UUID()
        bram.name = "Bram Oakfel"
        bram.journal = [JournalEntry(date: "Session 9", title: "Moonlight omen",
                                     text: "The Vault sigil flared under moonlight.")]
        let hits = JournalPartySearch.hits(in: [wren, bram], query: "MOONLIGHT")
        #expect(hits.count == 1)
        #expect(hits.first?.characterName == "Bram Oakfel")
        #expect(hits.first?.characterID == bram.id)   // 3.48.0: the jump target
        #expect(hits.first?.entry.title == "Moonlight omen")
        #expect(JournalPartySearch.hits(in: [wren, bram], query: "   ").isEmpty)
        #expect(JournalPartySearch.hits(in: [wren, bram], query: "no such thing").isEmpty)
        // The same query scoped to Wren alone finds nothing - the entry is Bram's.
        #expect(wren.journal.filter { $0.matchesFilter("moonlight") }.isEmpty)
    }
}
