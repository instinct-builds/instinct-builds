import Testing
import Foundation
@testable import AsssetsCore

// Build a fixture folder with real (minimal but valid) files.
func makeFixtures() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("asssets-fixtures-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: root.appendingPathComponent("mockups"), withIntermediateDirectories: true)

    // PNG 640x480
    var png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    png.append(contentsOf: [0, 0, 0, 0x0D])          // IHDR length
    png.append("IHDR".data(using: .ascii)!)
    png.append(contentsOf: [0, 0, 0x02, 0x80])       // width 640
    png.append(contentsOf: [0, 0, 0x01, 0xE0])       // height 480
    png.append(Data(repeating: 0, count: 32))
    try png.write(to: root.appendingPathComponent("hero-banner.png"))

    // JPEG 1920x1080 (SOI + SOF0 only — enough for header parsing)
    var jpg = Data([0xFF, 0xD8])
    jpg.append(contentsOf: [0xFF, 0xC0, 0x00, 0x11, 0x08])
    jpg.append(contentsOf: [0x04, 0x38])             // height 1080
    jpg.append(contentsOf: [0x07, 0x80])             // width 1920
    jpg.append(Data(repeating: 0, count: 16))
    try jpg.write(to: root.appendingPathComponent("photo-final.jpg"))

    // GIF 32x32
    var gif = Data("GIF89a".utf8)
    gif.append(contentsOf: [32, 0, 32, 0])
    gif.append(Data(repeating: 0, count: 8))
    try gif.write(to: root.appendingPathComponent("icon.gif"))

    // SVG 512x512 via viewBox
    let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><rect width="512" height="512"/></svg>"#
    try svg.write(to: root.appendingPathComponent("logo-mark.svg"), atomically: true, encoding: .utf8)

    // SVG with explicit width/height
    let svg2 = #"<svg width="300" height="150"><circle r="10"/></svg>"#
    try svg2.write(to: root.appendingPathComponent("badge.svg"), atomically: true, encoding: .utf8)

    // PSD 1024x768
    var psd = Data("8BPS".utf8)
    psd.append(contentsOf: [0, 1])                   // version
    psd.append(Data(repeating: 0, count: 6))         // reserved
    psd.append(contentsOf: [0, 3])                   // channels
    psd.append(contentsOf: [0, 0, 0x03, 0x00])       // height 768
    psd.append(contentsOf: [0, 0, 0x04, 0x00])       // width 1024
    psd.append(Data(repeating: 0, count: 8))
    try psd.write(to: root.appendingPathComponent("mockups/landing-page.psd"))

    // Video placeholder (kind detection only in phase 1)
    try Data(repeating: 0, count: 64).write(to: root.appendingPathComponent("teaser.mp4"))

    // Ignored files
    try "hello".write(to: root.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
    try Data([1,2,3]).write(to: root.appendingPathComponent("noext"))

    return root
}

@Suite("Metadata parsing")
struct MetadataTests {
    @Test func png() throws {
        let root = try makeFixtures()
        let d = try Data(contentsOf: root.appendingPathComponent("hero-banner.png"))
        #expect(MetadataReader.pngDimensions(d) != nil)
        #expect(MetadataReader.pngDimensions(d)!.0 == 640)
        #expect(MetadataReader.pngDimensions(d)!.1 == 480)
        #expect(MetadataReader.pngDimensions(Data("not a png".utf8)) == nil)
    }

    @Test func jpeg() throws {
        let root = try makeFixtures()
        let d = try Data(contentsOf: root.appendingPathComponent("photo-final.jpg"))
        let dims = MetadataReader.jpegDimensions(d)
        #expect(dims?.0 == 1920 && dims?.1 == 1080)
    }

    @Test func gifAndPSDAndSVG() throws {
        let root = try makeFixtures()
        let gif = try Data(contentsOf: root.appendingPathComponent("icon.gif"))
        #expect(MetadataReader.gifDimensions(gif)?.0 == 32)
        let psd = try Data(contentsOf: root.appendingPathComponent("mockups/landing-page.psd"))
        #expect(MetadataReader.psdDimensions(psd)?.0 == 1024)
        #expect(MetadataReader.psdDimensions(psd)?.1 == 768)
        let svg = try Data(contentsOf: root.appendingPathComponent("logo-mark.svg"))
        #expect(MetadataReader.svgDimensions(svg)?.0 == 512)
        let svg2 = try Data(contentsOf: root.appendingPathComponent("badge.svg"))
        #expect(MetadataReader.svgDimensions(svg2)?.0 == 300)
        #expect(MetadataReader.svgDimensions(svg2)?.1 == 150)
    }
}

@Suite("Library import and search")
struct LibraryTests {
    @Test func importIndexesKnownKindsAndReadsDimensions() throws {
        let root = try makeFixtures()
        var lib = Library()
        let count = try lib.importFolder(root.path)
        #expect(count == 7) // 7 supported files, txt + extensionless skipped
        let banner = lib.assets.values.first { $0.filename == "hero-banner.png" }
        #expect(banner != nil)
        #expect(banner?.kind == .image)
        #expect(banner?.width == 640 && banner?.height == 480)
        let psd = lib.assets.values.first { $0.filename == "landing-page.psd" }
        #expect(psd?.kind == .psd)
        #expect(psd?.megapixels == 1024.0 * 768.0 / 1_000_000.0)
        let video = lib.assets.values.first { $0.filename == "teaser.mp4" }
        #expect(video?.kind == .video)
        #expect(lib.assets.values.first { $0.filename == "notes.txt" } == nil)
    }

    @Test func reimportUpdatesNotDuplicates() throws {
        let root = try makeFixtures()
        var lib = Library()
        _ = try lib.importFolder(root.path)
        let firstCount = lib.assets.count
        _ = try lib.importFolder(root.path)
        #expect(lib.assets.count == firstCount)
    }

    @Test func searchByTextKindTagsAndMegapixels() throws {
        let root = try makeFixtures()
        var lib = Library()
        _ = try lib.importFolder(root.path)
        let banner = lib.assets.values.first { $0.filename == "hero-banner.png" }!
        try lib.addTag("Hero", to: banner.id)
        try lib.addTag("  CAMPAIGN ", to: banner.id) // normalizes

        #expect(lib.search(.init(text: "banner")).map(\.filename) == ["hero-banner.png"])
        #expect(lib.search(.init(text: "hero")).count >= 1) // tag hit too
        #expect(lib.search(.init(kinds: [.psd])).map(\.filename) == ["landing-page.psd"])
        #expect(lib.search(.init(requiredTags: ["campaign"])).count == 1)
        #expect(lib.search(.init(kinds: [.vector])).count == 2)
        // banner is 0.3 MP; photo is 2 MP
        #expect(lib.search(.init(minMegapixels: 1.0)).map(\.filename) == ["photo-final.jpg"])
        #expect(lib.search(.init(text: "zzz-no-match")).isEmpty)
    }

    @Test func collectionsAndRemoval() throws {
        let root = try makeFixtures()
        var lib = Library()
        _ = try lib.importFolder(root.path)
        let a = lib.assets.values.first { $0.filename == "hero-banner.png" }!
        let cid = lib.createCollection("Web")
        try lib.addToCollection(a.id, collection: cid)
        #expect(lib.collections.first { $0.id == cid }?.assetIDs.contains(a.id) == true)
        try lib.removeAsset(a.id)
        #expect(lib.collections.first { $0.id == cid }?.assetIDs.isEmpty == true)
        #expect(throws: LibraryError.self) { try lib.removeAsset(a.id) }
    }
}

@Suite("Persistence")
struct PersistenceTests {
    @Test func roundTrip() throws {
        let root = try makeFixtures()
        var lib = Library()
        _ = try lib.importFolder(root.path)
        let a = lib.assets.values.first { $0.filename == "hero-banner.png" }!
        try lib.addTag("hero", to: a.id)
        _ = lib.createCollection("Web")

        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("asssets-store-\(UUID().uuidString)/library.json")
        let store = LibraryStore(fileURL: file)
        try store.save(lib)
        let loaded = try store.load()
        #expect(loaded.collections == lib.collections)
        #expect(loaded.assets.count == lib.assets.count)
        // JSON dates round-trip to sub-millisecond precision, not bit-exact
        // Date identity, so compare fields with a time tolerance.
        for (id, a) in lib.assets {
            let b = try #require(loaded.assets[id])
            #expect(b.path == a.path && b.filename == a.filename && b.kind == a.kind)
            #expect(b.byteSize == a.byteSize && b.width == a.width && b.height == a.height)
            #expect(b.tags == a.tags)
            #expect(abs(b.addedAt.timeIntervalSince(a.addedAt)) < 0.001)
        }
    }
}
