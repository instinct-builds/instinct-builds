import Foundation
import Testing
@testable import ArchiterCore

/// Table log condition filter (3.66.0): case-insensitive name match over
/// title and text; blank shows all; order preserved.
@Suite("Table log condition filter (3.66.0)")
struct TableLogConditionFilterTests {
    private let entries = [
        TableLogEntry(createdAt: Date(timeIntervalSince1970: 1000),
                      title: "Party condition", text: "Frightened applied: Wren (note: the howl)"),
        TableLogEntry(createdAt: Date(timeIntervalSince1970: 2000),
                      title: "Ember Warrens", text: "The party reaches the bridge."),
        TableLogEntry(createdAt: Date(timeIntervalSince1970: 3000),
                      title: "Party condition", text: "Frightened removed: Wren (note: the howl)"),
        TableLogEntry(createdAt: Date(timeIntervalSince1970: 4000),
                      title: "Party condition", text: "restored Frightened on Wren (note: the howl)"),
    ]

    @Test func blankQueryShowsEverything() {
        #expect(TableLogConditionFilter.filter(entries, query: "") == entries)
        #expect(TableLogConditionFilter.filter(entries, query: "   ") == entries)
    }

    @Test func nameMatchFindsApplyRemovalAndRestoreLines() {
        let hits = TableLogConditionFilter.filter(entries, query: "Frightened")
        #expect(hits.count == 3)
        #expect(hits.map(\.createdAt) == [entries[0].createdAt, entries[2].createdAt, entries[3].createdAt])
    }

    @Test func matchIsCaseInsensitive() {
        #expect(TableLogConditionFilter.filter(entries, query: "frightened").count == 3)
        #expect(TableLogConditionFilter.filter(entries, query: "FRIGHTENED").count == 3)
    }

    @Test func titleMatchesToo() {
        let hits = TableLogConditionFilter.filter(entries, query: "Ember")
        #expect(hits == [entries[1]])
    }

    @Test func noMatchFiltersToEmpty() {
        #expect(TableLogConditionFilter.filter(entries, query: "Petrified").isEmpty)
    }
}
