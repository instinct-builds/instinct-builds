import Foundation
import Testing
@testable import ArchiterCore

/// Table-log export (3.47.0): the whole log as one text block -
/// oldest-first, day labels, untitled entries fall back to "Note".
@Suite struct TableLogExportTests {
    @Test func oldestFirstWithDayLabels() {
        let entries = [
            TableLogEntry(createdAt: Date(timeIntervalSince1970: 2000),
                          title: "Fight recap", text: "Fight over."),
            TableLogEntry(createdAt: Date(timeIntervalSince1970: 1000),
                          title: "Ember Warrens", text: "The party reaches the bridge."),
        ]
        let text = TableLogExport.text(entries: entries)
        #expect(text.hasPrefix("Table log"))
        let ember = text.range(of: "Ember Warrens")
        let fight = text.range(of: "Fight recap")
        #expect(ember != nil && fight != nil)
        if let ember, let fight { #expect(ember.lowerBound < fight.lowerBound) }
        #expect(text.contains(JournalStamp.day(Date(timeIntervalSince1970: 1000))))
        #expect(text.contains(JournalStamp.day(Date(timeIntervalSince1970: 2000))))
    }

    @Test func untitledFallsBackToNote() {
        let text = TableLogExport.text(entries: [
            TableLogEntry(createdAt: Date(), title: "", text: "x"),
        ])
        #expect(text.contains("- Note"))
    }

    @Test func emptyTextIsHeadOnly() {
        let text = TableLogExport.text(entries: [
            TableLogEntry(createdAt: Date(), title: "T", text: ""),
        ])
        // "Table log" + blank separator + the head line, no body line.
        #expect(text.components(separatedBy: "\n").count == 3)
    }

    @Test func emptyLogIsHeadOnly() {
        #expect(TableLogExport.text(entries: []) == "Table log")
    }
}
