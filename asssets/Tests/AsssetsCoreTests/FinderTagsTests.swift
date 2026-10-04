import Foundation
import Testing
@testable import AsssetsCore

@Suite("Finder tags")
struct FinderTagsTests {
    func file() throws -> String {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("ft-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let f = d.appendingPathComponent("a.png")
        try Data([0, 1, 2]).write(to: f)
        return f.path
    }

    @Test func namesDropColorSuffixes() throws {
        let data = try PropertyListSerialization.data(fromPropertyList: ["Client", "Red\n6", "Final\n2"], format: .binary, options: 0)
        #expect(FinderTags.names(from: data) == ["Client", "Red", "Final"])
        #expect(FinderTags.names(from: Data("not a plist".utf8)).isEmpty)
    }

    @Test func mergeKeepsExistingEntriesVerbatimAndSkipsCaseInsensitiveDuplicates() throws {
        let existing = try PropertyListSerialization.data(fromPropertyList: ["Client", "Red\n6"], format: .binary, options: 0)
        let m = FinderTags.merged(existing: existing, adding: ["client", "RED", "approved", " ", "approved"])
        #expect(m?.added == 1)
        let list = m.flatMap { (try? PropertyListSerialization.propertyList(from: $0.data, options: [], format: nil)) as? [String] }
        #expect(list == ["Client", "Red\n6", "approved"])
        #expect(FinderTags.merged(existing: existing, adding: ["client"]) == nil)
        #expect(FinderTags.merged(existing: nil, adding: ["a"])?.added == 1)
    }

    #if canImport(Darwin)
    @Test func attributeRoundTripsOnARealFile() throws {
        let p = try file()
        #expect(FinderTags.read(path: p).isEmpty)
        #expect(FinderTags.writeEntries(path: p, entries: ["Client", "Red\n6"]))
        #expect(FinderTags.read(path: p) == ["Client", "Red"])
        #expect(FinderTags.write(path: p, adding: ["Client", "approved"]) == .written(added: 1))
        #expect(FinderTags.read(path: p) == ["Client", "Red", "approved"])
        #expect(FinderTags.write(path: p, adding: ["approved"]) == .unchanged)
        let raw = FinderTags.rawData(path: p).flatMap { (try? PropertyListSerialization.propertyList(from: $0, options: [], format: nil)) as? [String] }
        #expect(raw == ["Client", "Red\n6", "approved"])
        #expect(FinderTags.write(path: "/no/such/file.png", adding: ["x"]) == .failed)
    }
    #endif
}
