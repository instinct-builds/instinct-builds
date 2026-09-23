import Foundation
import Testing
@testable import AsssetsCore

@Suite("File metadata (XMP and IPTC)")
struct XmpMetadataTests {
    // A Lightroom Classic style sidecar: attribute-form rating and label, develop settings that must survive.
    let lightroom = """
    <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="Adobe XMP Core 7.0">
     <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
      <rdf:Description rdf:about=""
        xmlns:xmp="http://ns.adobe.com/xap/1.0/"
        xmlns:dc="http://purl.org/dc/elements/1.1/"
        xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
       xmp:Rating="4"
       xmp:Label="Green"
       crs:Exposure2012="+0.35"
       crs:Temperature="5200">
       <dc:title><rdf:Alt><rdf:li xml:lang="x-default">Lobby at Dusk</rdf:li></rdf:Alt></dc:title>
       <dc:subject>
        <rdf:Bag>
         <rdf:li>Architecture</rdf:li>
         <rdf:li>Night &amp; City</rdf:li>
        </rdf:Bag>
       </dc:subject>
      </rdf:Description>
     </rdf:RDF>
    </x:xmpmeta>
    """

    func iptcBlock(_ sets: [(UInt8, String)]) -> Data {
        var body = Data()
        for (tag, text) in sets {
            let v = Data(text.utf8)
            body += Data([0x1C, 0x02, tag, UInt8(v.count >> 8), UInt8(v.count & 0xFF)]) + v
        }
        var res = Data("8BIM".utf8) + Data([0x04, 0x04, 0x00, 0x00])   // id, empty padded name
        res += Data([UInt8(body.count >> 24 & 0xFF), UInt8(body.count >> 16 & 0xFF), UInt8(body.count >> 8 & 0xFF), UInt8(body.count & 0xFF)]) + body
        return res
    }

    /// A JPEG with an APP1 XMP packet and an APP13 IPTC block.
    func jpeg(xmp: String?, iptc: [(UInt8, String)]) -> Data {
        var d = Data([0xFF, 0xD8])
        if let xmp {
            let payload = Data("http://ns.adobe.com/xap/1.0/\0".utf8) + Data(xmp.utf8)
            d += Data([0xFF, 0xE1, UInt8((payload.count + 2) >> 8), UInt8((payload.count + 2) & 0xFF)]) + payload
        }
        if !iptc.isEmpty {
            let payload = Data("Photoshop 3.0\0".utf8) + iptcBlock(iptc)
            d += Data([0xFF, 0xED, UInt8((payload.count + 2) >> 8), UInt8((payload.count + 2) & 0xFF)]) + payload
        }
        return d + Data([0xFF, 0xD9])
    }

    func tmp(_ name: String) -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("xmp-" + UUID().uuidString)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name)
    }

    @Test func parsesLightroomSidecar() {
        let m = XmpMetadata.parse(lightroom)
        #expect(m.title == "Lobby at Dusk" && m.keywords == ["Architecture", "Night & City"])
        #expect(m.rating == 4 && m.label == .green)
    }

    @Test func parsesElementFormAndBridgeLabels() {
        let x = "<rdf:Description><xmp:Rating>-1</xmp:Rating><xmp:Label>Review</xmp:Label><dc:subject><rdf:Bag/></dc:subject></rdf:Description>"
        let m = XmpMetadata.parse(x)
        #expect(m.rating == -1 && m.label == .blue && m.keywords.isEmpty && m.title == nil)
        #expect(XmpMetadata.parse("<x xmp:Rating=\"0\"/>").rating == nil)
        #expect(XmpMetadata.parse("<x xmp:Rating=\"9\"/>").rating == 5)
        #expect(XmpMetadata.label(named: "To Do") == .purple && XmpMetadata.label(named: "Magenta") == nil)
    }

    @Test func readsJpegXmpAndIptc() throws {
        let url = tmp("hero.jpg")
        let x = XmpMetadata.packet(FileMetadata(keywords: ["poster"], rating: 3, label: .red))
        try jpeg(xmp: x, iptc: [(5, "Launch Hero"), (25, "poster"), (25, "Campaign")]).write(to: url)
        let m = XmpMetadata.read(path: url.path)
        #expect(m.rating == 3 && m.label == .red && m.title == "Launch Hero")
        #expect(m.keywords == ["poster", "Campaign"])            // de-duplicated across XMP and IPTC
        // IPTC alone.
        try jpeg(xmp: nil, iptc: [(25, "Only IPTC")]).write(to: url)
        #expect(XmpMetadata.read(path: url.path).keywords == ["Only IPTC"])
    }

    @Test func readsPngITXtAndSidecarWins() throws {
        let url = tmp("card.png")
        let x = XmpMetadata.packet(FileMetadata(title: "Embedded", keywords: ["a"], rating: 2))
        var png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let chunk = Data("XML:com.adobe.xmp\0\0\0\0\0".utf8) + Data(x.utf8)
        png += Data([0, 0, UInt8(chunk.count >> 8), UInt8(chunk.count & 0xFF)]) + Data("iTXt".utf8) + chunk + Data([0, 0, 0, 0])
        try png.write(to: url)
        #expect(XmpMetadata.read(path: url.path).title == "Embedded")
        try XmpMetadata.packet(FileMetadata(title: "Sidecar", keywords: ["b"], rating: 5)).write(toFile: XmpMetadata.sidecarPath(for: url.path), atomically: true, encoding: .utf8)
        let m = XmpMetadata.read(path: url.path)
        #expect(m.title == "Sidecar" && m.rating == 5 && m.keywords == ["b", "a"])
        #expect(XmpMetadata.sidecarPath(for: "/p/card.final.png") == "/p/card.final.xmp")
        #expect(XmpMetadata.read(path: "/nope/missing.png").isEmpty)
    }

    @Test func packetRoundTripsAndEscapes() {
        let m = FileMetadata(title: "A <b> & \"c\"", keywords: ["x & y", "z"], rating: -1, label: .purple)
        #expect(XmpMetadata.parse(XmpMetadata.packet(m)) == m)
    }

    @Test func updateKeepsOtherSettings() {
        let out = XmpMetadata.update(lightroom, with: FileMetadata(title: "New", keywords: ["one"], rating: 2, label: .blue))
        #expect(out.contains("crs:Exposure2012=\"+0.35\"") && out.contains("crs:Temperature=\"5200\""))
        let m = XmpMetadata.parse(out)
        #expect(m == FileMetadata(title: "New", keywords: ["one"], rating: 2, label: .blue))
        #expect(!out.contains("Architecture") && !out.contains("xmp:Rating=\"4\""))
        // Clearing fields removes them; a self-closing description gets opened up.
        let cleared = XmpMetadata.update(out, with: FileMetadata())
        #expect(XmpMetadata.parse(cleared).isEmpty && cleared.contains("crs:Temperature"))
        let bare = "<x:xmpmeta><rdf:RDF><rdf:Description rdf:about=\"\" xmlns:tiff=\"t\" tiff:Make=\"Leica\"/></rdf:RDF></x:xmpmeta>"
        let opened = XmpMetadata.update(bare, with: FileMetadata(keywords: ["k"], rating: 1))
        #expect(opened.contains("tiff:Make=\"Leica\"") && XmpMetadata.parse(opened).keywords == ["k"] && XmpMetadata.parse(opened).rating == 1)
        #expect(XmpMetadata.update("garbage", with: FileMetadata(rating: 3)).contains("<xmp:Rating>3</xmp:Rating>"))
    }

    @Test func catalogApplyAndExport() {
        var c = StudioCatalog()
        c.assets = [StudioAsset(title: "img 0042", kind: .image, tags: ["jpg", "imported"], collection: "Inbox", palette: [], seed: 0, importedPath: "/x/img.jpg", resolution: "")]
        let id = c.assets[0].id
        let ch1 = c.applyFileMetadata(FileMetadata(title: "Lobby", keywords: ["Architecture", "night"], rating: 4, label: .green), to: id)
        #expect(ch1)
        #expect(c.assets[0].title == "Lobby" && c.assets[0].tags == ["jpg", "imported", "architecture", "night"] && c.assets[0].rating == 4 && c.assets[0].label == .green)
        let ch2 = c.applyFileMetadata(FileMetadata(keywords: ["night"], rating: 1), to: id)
        #expect(!ch2)   // existing stars win
        let out = c.fileMetadata(for: id)!
        #expect(out.keywords == ["architecture", "night"] && out.rating == 4 && out.title == "Lobby")
        c.assets[0].tags.append(StudioCatalog.rejectTag)
        #expect(c.fileMetadata(for: id)!.rating == -1 && !c.fileMetadata(for: id)!.keywords.contains("rejected"))
        var d = StudioCatalog(); d.assets = c.assets; d.assets[0].rating = 0; d.assets[0].tags = []
        d.applyFileMetadata(FileMetadata(rating: -1), to: id)
        #expect(d.assets[0].tags == [StudioCatalog.rejectTag] && d.assets[0].rating == 0)
    }

    @Test func keywordCountsAndRename() {
        func a(_ tags: [String]) -> StudioAsset { StudioAsset(title: "t", kind: .image, tags: tags, collection: "Inbox", palette: [], seed: 0, importedPath: nil, resolution: "") }
        var c = StudioCatalog()
        c.assets = [a(["png", "blu", "sky"]), a(["blue", "sky", "imported"]), a(["blu", "blue"])]
        c.smartCollections = [StudioSmartCollection(name: "Blue", rules: SmartRules(requiredTags: ["blu", "sky"]))]
        #expect(c.keywordCounts().map(\.tag) == ["blu", "blue", "sky"])
        let n = c.renameTag("blu", to: " Blue "); #expect(n == 2)
        #expect(c.assets[0].tags == ["png", "blue", "sky"] && c.assets[2].tags == ["blue"])
        #expect(c.smartCollections[0].rules.requiredTags == ["blue", "sky"])
        let top = c.keywordCounts().first!; #expect(top.tag == "blue" && top.count == 3)
        let n1 = c.renameTag("sky", to: "sky"), n2 = c.renameTag("sky", to: "  "); #expect(n1 == 0 && n2 == 0)
    }
}
