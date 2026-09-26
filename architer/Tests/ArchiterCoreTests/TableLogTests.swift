import Foundation
import Testing
@testable import ArchiterCore

/// Table log (3.45.0): the store round-trips entries, fails safe on
/// missing/corrupt data, and the day label derives from createdAt.
@Suite struct TableLogTests {
    @Test func storeRoundTripsEntries() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let store = TableLogStore(directory: dir)
        #expect(store.load().isEmpty)   // missing file loads empty
        let entries = [
            TableLogEntry(createdAt: Date(timeIntervalSince1970: 1000),
                          title: "Ember Warrens", text: "The party reaches the bridge."),
            TableLogEntry(createdAt: Date(timeIntervalSince1970: 2000),
                          title: "Fight recap", text: "Fight over: 2x CR 3 - 3 rounds"),
        ]
        store.save(entries)
        #expect(store.load() == entries)
    }

    @Test func corruptFileLoadsEmpty() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "not json".write(to: dir.appendingPathComponent("table-log.json"),
                             atomically: true, encoding: .utf8)
        #expect(TableLogStore(directory: dir).load().isEmpty)
    }

    @Test func dayLabelDerivesFromCreatedAt() {
        let now = Date()
        let entry = TableLogEntry(createdAt: now, title: "T", text: "x")
        #expect(JournalStamp.day(entry.createdAt) == JournalStamp.day(now))
    }
}
