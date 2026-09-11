import Testing
import Foundation
@testable import AsssetsCore

@Suite("Smart collections")
struct SmartCollectionTests {

    @Test func membershipTracksTheLibrary() throws {
        let root = try makeFixtures()
        var lib = Library()
        _ = try lib.importFolder(root.path)

        let big = lib.createSmartCollection(
            name: "Big images",
            query: Library.Query(kinds: [.image], minMegapixels: 0.2))
        let matches = lib.smartCollectionAssets(big)
        #expect(matches.contains { $0.filename == "hero-banner.png" })   // 0.31 MP
        #expect(matches.contains { $0.filename == "photo-final.jpg" })   // 2.07 MP
        #expect(!matches.contains { $0.filename == "icon.gif" })         // 0.001 MP
        #expect(!matches.contains { $0.filename == "logo-mark.svg" })    // not an image

        // Tag-based smart collection picks up later edits immediately.
        let banner = try #require(lib.assets.values.first { $0.filename == "hero-banner.png" })
        let client = lib.createSmartCollection(
            name: "Client work",
            query: Library.Query(requiredTags: ["client-work"]))
        #expect(lib.smartCollectionAssets(client).isEmpty)
        try lib.addTag("client-work", to: banner.id)
        #expect(lib.smartCollectionAssets(client).map(\.filename) == ["hero-banner.png"])
    }

    @Test func persistsAcrossSaveLoad() throws {
        let root = try makeFixtures()
        var lib = Library()
        _ = try lib.importFolder(root.path)
        let id = lib.createSmartCollection(
            name: "Vectors",
            query: Library.Query(kinds: [.vector]))
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("asssets-smart-\(UUID().uuidString)/library.json")
        try LibraryStore(fileURL: storeURL).save(lib)
        let reloaded = try LibraryStore(fileURL: storeURL).load()
        #expect(reloaded.smartCollections.count == 1)
        #expect(reloaded.smartCollections.first?.name == "Vectors")
        #expect(reloaded.smartCollectionAssets(id).count == 2) // two svg fixtures
    }

    @Test func legacyJSONWithoutSmartCollectionsDecodes() throws {
        let root = try makeFixtures()
        var lib = Library()
        _ = try lib.importFolder(root.path)
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("asssets-legacy-\(UUID().uuidString)/library.json")
        try LibraryStore(fileURL: storeURL).save(lib)

        // Strip the smartCollections key to simulate a pre-Phase-2 file.
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: storeURL)) as! [String: Any]
        var legacy = raw
        legacy.removeValue(forKey: "smartCollections")
        let legacyData = try JSONSerialization.data(withJSONObject: legacy)
        try legacyData.write(to: storeURL)

        let decoded = try LibraryStore(fileURL: storeURL).load()
        #expect(decoded.smartCollections.isEmpty)
        #expect(decoded.assets.count == lib.assets.count)
    }

    @Test func deleteSmartCollection() throws {
        var lib = Library()
        let id = lib.createSmartCollection(name: "Temp", query: Library.Query())
        #expect(lib.smartCollections.count == 1)
        try lib.deleteSmartCollection(id)
        #expect(lib.smartCollections.isEmpty)
        #expect(throws: LibraryError.self) { try lib.deleteSmartCollection(id) }
    }
}
