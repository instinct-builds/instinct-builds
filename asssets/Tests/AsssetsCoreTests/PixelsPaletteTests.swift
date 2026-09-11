import Testing
import Foundation
@testable import AsssetsCore

// Fixtures produced by real encoders (Python zlib), embedded as base64.

/// 4x4 RGB PNG, quadrant colors: red / green / blue / white, filter 0 rows,
/// zlib-compressed IDAT (real dynamic/fixed-Huffman stream).
private let quad4B64 = "iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAIAAAAmkwkpAAAAGElEQVR4nGP4z8AARAz/kRCMAtMQgMIBAO5TF+nsKTSDAAAAAElFTkSuQmCC"

/// 8x8 RGB PNG, gradient r=x*32 g=y*32 b=128, scanline filters 0,1,2,3,4,1,2,4.
private let filtered8B64 = "iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAQklEQVR4nGNgYGhQYGhwYGhIYGhoYGhYwNBwgKHhAUMDI4MCUIIBEzFhEQMjZgYHBwEBBkzEApLHBhgZFpBoB06jAFNlDrIhe8dKAAAAAElFTkSuQmCC"

/// zlib level-9 stream with back-references (1400 bytes inflated).
private let payloadB64 = "eNpzDA4Odg0J1s3MS8tJLEnVLUiszMlPTGFgYGRiZmFlY+fg5OLm4eXjFxAUEhYRFROXkJSSlpGVk1dQVFJWUVVT19DU0tbR1dM3MDQyNjE1M7ewtLK2sbWzd3B0cnZxdXP38PTy9vH18w8IDAoOCQ0Lj4iMio6JjYtPSExKTklNS8/IzMrOyc3LLygsKi4pLSuvqKyqrqmtq29obGpuaW1r7+js6u7p7eufMHHS5ClTp02fMXPW7Dlz581fsHDR4iVLly1fsXLV6jVr163fsHHT5i1bt23fsXPX7j179+0/cPDQ4SNHjx0/cfLU6TNnz52/cPHS5StXr12/cfPW7Tt3791/8PDR4ydPnz1/8fLV6zdv373/8PHT5y9fv33/8fPX7z9///0f9f+o/0ey/0syUhUKSzOTsxWSivLL8xTS8isUskpzC4oV8stSixRA0jmJVZUKKfnpCqNqSVcLAFwXhzQ="

private func expectedPayload() -> [UInt8] {
    var out = [UInt8]("ASSSETS-inflate-payload\0".utf8)
    for _ in 0..<4 { for v in 0...255 { out.append(UInt8(v)) } }
    out.append(contentsOf: [UInt8](String(repeating: "the quick brown fox jumps over the lazy dog ", count: 8).utf8))
    return out
}

@Suite("zlib / DEFLATE")
struct ZlibTests {
    @Test func inflatesRealEncoderStream() throws {
        let compressed = Data(base64Encoded: payloadB64)!
        let out = try #require(Zlib.inflate(compressed))
        #expect(out == expectedPayload())
    }

    @Test func rejectsCorruptStream() {
        var compressed = [UInt8](Data(base64Encoded: payloadB64)!)
        compressed[20] ^= 0xFF
        #expect(Zlib.inflate(compressed) == nil)
    }

    @Test func storedDeflateRoundTrips() {
        let data = expectedPayload()
        let stored = Zlib.deflateStored(data)
        #expect(Zlib.inflate(stored) == data)
        #expect(Zlib.inflate(Zlib.deflateStored([])) == [])
    }
}

@Suite("PNG decode/encode")
struct PNGTests {
    @Test func decodesQuadrantColors() throws {
        let png = Data(base64Encoded: quad4B64)!
        let img = try #require(PNGDecoder.decode(png))
        #expect(img.width == 4 && img.height == 4)
        #expect(img.pixel(x: 0, y: 0) == (255, 0, 0, 255))       // red
        #expect(img.pixel(x: 3, y: 0) == (0, 255, 0, 255))       // green
        #expect(img.pixel(x: 0, y: 3) == (0, 0, 255, 255))       // blue
        #expect(img.pixel(x: 3, y: 3) == (255, 255, 255, 255))   // white
    }

    @Test func decodesAllFilterTypes() throws {
        let png = Data(base64Encoded: filtered8B64)!
        let img = try #require(PNGDecoder.decode(png))
        #expect(img.width == 8 && img.height == 8)
        for y in 0..<8 {
            for x in 0..<8 {
                let p = img.pixel(x: x, y: y)
                #expect(p.r == UInt8(x * 32) && p.g == UInt8(y * 32) && p.b == 128 && p.a == 255)
            }
        }
    }

    @Test func encodeDecodeRoundTrip() throws {
        var rgba: [UInt8] = []
        for y in 0..<3 {
            for x in 0..<5 {
                rgba.append(contentsOf: [UInt8(x * 40), UInt8(y * 80), 200, 255])
            }
        }
        let img = PixelBuffer(width: 5, height: 3, rgba: rgba)
        let png = PNGEncoder.encode(img)
        #expect(MetadataReader.pngDimensions(png)?.0 == 5)
        #expect(MetadataReader.pngDimensions(png)?.1 == 3)
        let back = try #require(PNGDecoder.decode(png))
        #expect(back == img)
    }

    @Test func rejectsGarbage() {
        #expect(PNGDecoder.decode(Data("definitely not a png".utf8)) == nil)
    }
}

@Suite("BMP decode")
struct BMPTests {
    @Test func decodes24BitBottomUp() throws {
        // 2x2 24-bit BMP. Top row: red, green. Bottom row: blue, white.
        var d = [UInt8]("BM".utf8)
        let rowSize = 8 // 2 px * 3 B, padded to 4
        let pixelData = 54
        d.append(contentsOf: [0x36, 0, 0, 0])                  // file size = 54 + 16
        d.append(contentsOf: [0, 0, 0, 0])                       // reserved
        d.append(contentsOf: [54, 0, 0, 0])                      // pixel offset
        d.append(contentsOf: [40, 0, 0, 0])                      // header size
        d.append(contentsOf: [2, 0, 0, 0])                       // width
        d.append(contentsOf: [2, 0, 0, 0])                       // height (bottom-up)
        d.append(contentsOf: [1, 0])                              // planes
        d.append(contentsOf: [24, 0])                             // bpp
        d.append(contentsOf: [0, 0, 0, 0])                       // compression BI_RGB
        d.append(contentsOf: [UInt8](repeating: 0, count: 20))   // rest of header
        #expect(d.count == pixelData)
        // bottom row first (BGR): blue, white; pad; then top row: red, green; pad
        d.append(contentsOf: [255, 0, 0, 255, 255, 255, 0, 0])
        d.append(contentsOf: [0, 0, 255, 0, 255, 0, 0, 0])
        let img = try #require(BMPDecoder.decode(Data(d)))
        #expect(img.width == 2 && img.height == 2)
        #expect(img.pixel(x: 0, y: 0) == (255, 0, 0, 255))   // red
        #expect(img.pixel(x: 1, y: 0) == (0, 255, 0, 255))   // green
        #expect(img.pixel(x: 0, y: 1) == (0, 0, 255, 255))   // blue
        #expect(img.pixel(x: 1, y: 1) == (255, 255, 255, 255)) // white
        _ = rowSize
    }
}

@Suite("Palette extraction")
struct PaletteTests {
    private func halfRedHalfBlue() -> PixelBuffer {
        var rgba: [UInt8] = []
        for _ in 0..<100 {
            for x in 0..<100 {
                if x < 50 { rgba.append(contentsOf: [255, 0, 0, 255]) }
                else { rgba.append(contentsOf: [0, 0, 255, 255]) }
            }
        }
        return PixelBuffer(width: 100, height: 100, rgba: rgba)
    }

    @Test func findsDominantColorsWithWeights() {
        let colors = PaletteExtractor.colors(from: halfRedHalfBlue(), count: 2)
        #expect(colors.count == 2)
        #expect(abs(colors[0].weight - 0.5) < 0.05)
        #expect(abs(colors[1].weight - 0.5) < 0.05)
        let hexes = Set(colors.map(\.hex))
        #expect(hexes == ["#FF0000", "#0000FF"])
    }

    @Test func weightsSumToOne() {
        let colors = PaletteExtractor.colors(from: halfRedHalfBlue(), count: 6)
        let sum = colors.reduce(0.0) { $0 + $1.weight }
        #expect(abs(sum - 1.0) < 0.001)
    }
}

@Suite("Thumbnails")
struct ThumbnailTests {
    @Test func boxDownscaleAveragesQuadrants() {
        var rgba: [UInt8] = []
        let quad: [(UInt8, UInt8, UInt8)] = [(255, 0, 0), (0, 255, 0), (0, 0, 255), (255, 255, 255)]
        for y in 0..<4 {
            for x in 0..<4 {
                let c = quad[(y / 2) * 2 + (x / 2)]
                rgba.append(contentsOf: [c.0, c.1, c.2, 255])
            }
        }
        let img = PixelBuffer(width: 4, height: 4, rgba: rgba)
        let t = Thumbnailer.thumbnail(from: img, maxDim: 2)
        #expect(t.width == 2 && t.height == 2)
        #expect(t.pixel(x: 0, y: 0) == (255, 0, 0, 255))
        #expect(t.pixel(x: 1, y: 0) == (0, 255, 0, 255))
        #expect(t.pixel(x: 0, y: 1) == (0, 0, 255, 255))
        #expect(t.pixel(x: 1, y: 1) == (255, 255, 255, 255))
    }

    @Test func neverUpscales() {
        let img = PixelBuffer(width: 3, height: 2, rgba: [UInt8](repeating: 128, count: 3 * 2 * 4))
        let t = Thumbnailer.thumbnail(from: img, maxDim: 256)
        #expect(t == img)
    }
}

@Suite("Library derivatives")
struct DerivativeTests {
    @Test func importGeneratesPaletteAndThumbnail() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("asssets-deriv-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)

        // 600x400 PNG: left half orange, right half teal, written via our encoder.
        var rgba: [UInt8] = []
        for _ in 0..<400 {
            for x in 0..<600 {
                if x < 300 { rgba.append(contentsOf: [255, 128, 0, 255]) }
                else { rgba.append(contentsOf: [0, 128, 128, 255]) }
            }
        }
        let img = PixelBuffer(width: 600, height: 400, rgba: rgba)
        let pngURL = root.appendingPathComponent("art.png")
        try PNGEncoder.encode(img).write(to: pngURL)

        var lib = Library()
        _ = try lib.importFolder(root.path)
        let thumbsDir = root.appendingPathComponent("thumbs").path
        let made = lib.generateDerivatives(thumbnailsDir: thumbsDir)
        #expect(made == 1)

        let asset = try #require(lib.assets.values.first { $0.filename == "art.png" })
        let palette = try #require(asset.palette)
        #expect(palette.count >= 2)
        #expect(palette.contains("#FF8000"))
        #expect(palette.contains("#008080"))

        let thumbPath = try #require(asset.thumbnailFile)
        let thumbData = try Data(contentsOf: URL(fileURLWithPath: thumbPath))
        let thumb = try #require(PNGDecoder.decode(thumbData))
        #expect(thumb.width == 256 && thumb.height == 171)

        // Idempotent: second run derives nothing new.
        #expect(lib.generateDerivatives(thumbnailsDir: thumbsDir) == 0)

        // Palette and thumbnail survive JSON persistence.
        let storeURL = root.appendingPathComponent("library.json")
        try LibraryStore(fileURL: storeURL).save(lib)
        let reloaded = try LibraryStore(fileURL: storeURL).load()
        let reloadedAsset = try #require(reloaded.assets.values.first { $0.filename == "art.png" })
        #expect(reloadedAsset.palette == asset.palette)
        #expect(reloadedAsset.thumbnailFile == asset.thumbnailFile)

        try? fm.removeItem(at: root)
    }
}
