import Testing
import Foundation
@testable import AsssetsCore

// PSD fixtures produced by a real PackBits encoder (Python), embedded as
// base64. Composite-preview scope: 8-bit RGB / grayscale, raw and RLE.

/// 8x6 RGB, raw. r = x*32, g = y*40, b = 128 (planar).
private let rgbRawB64 = "OEJQUwABAAAAAAAAAAMAAAAGAAAACAAIAAMAAAAAAAAAAAAAAAAAAAAgQGCAoMDgACBAYICgwOAAIEBggKDA4AAgQGCAoMDgACBAYICgwOAAIEBggKDA4AAAAAAAAAAAKCgoKCgoKChQUFBQUFBQUHh4eHh4eHh4oKCgoKCgoKDIyMjIyMjIyICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgA=="
/// Same pixels, PackBits RLE per scanline.
private let rgbRleB64 = "OEJQUwABAAAAAAAAAAMAAAAGAAAACAAIAAMAAAAAAAAAAAAAAAAAAQAJAAkACQAJAAkACQACAAIAAgACAAIAAgACAAIAAgACAAIAAgcAIEBggKDA4AcAIEBggKDA4AcAIEBggKDA4AcAIEBggKDA4AcAIEBggKDA4AcAIEBggKDA4PkA+Sj5UPl4+aD5yPmA+YD5gPmA+YD5gA=="
/// Same pixels plus alpha channel a = 255 - x*16, RLE.
private let rgbaRleB64 = "OEJQUwABAAAAAAAAAAQAAAAGAAAACAAIAAMAAAAAAAAAAAAAAAAAAQAJAAkACQAJAAkACQACAAIAAgACAAIAAgACAAIAAgACAAIAAgAJAAkACQAJAAkACQcAIEBggKDA4AcAIEBggKDA4AcAIEBggKDA4AcAIEBggKDA4AcAIEBggKDA4AcAIEBggKDA4PkA+Sj5UPl4+aD5yPmA+YD5gPmA+YD5gAf/79/Pv6+fjwf/79/Pv6+fjwf/79/Pv6+fjwf/79/Pv6+fjwf/79/Pv6+fjwf/79/Pv6+fjw=="
/// 5x4 grayscale, raw. v = x + y*10.
private let grayRawB64 = "OEJQUwABAAAAAAAAAAEAAAAEAAAABQAIAAEAAAAAAAAAAAAAAAAAAAABAgMECgsMDQ4UFRYXGB4fICEi"
/// Same grayscale plus alpha channel a = 200 + y, raw.
private let grayAlphaRawB64 = "OEJQUwABAAAAAAAAAAIAAAAEAAAABQAIAAEAAAAAAAAAAAAAAAAAAAABAgMECgsMDQ4UFRYXGB4fICEiyMjIyMjJycnJycrKysrKy8vLy8s="
/// 16-bit RGB header (unsupported depth).
private let depth16B64 = "OEJQUwABAAAAAAAAAAMAAAACAAAAAgAQAAMAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=="
/// CMYK header (unsupported color mode).
private let cmykB64 = "OEJQUwABAAAAAAAAAAQAAAACAAAAAgAIAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

private func expectRGB(_ img: PixelBuffer) {
    #expect(img.width == 8 && img.height == 6)
    for y in 0..<6 {
        for x in 0..<8 {
            let p = img.pixel(x: x, y: y)
            #expect(p.r == UInt8(x * 32), "r at \(x),\(y)")
            #expect(p.g == UInt8(y * 40), "g at \(x),\(y)")
            #expect(p.b == 128, "b at \(x),\(y)")
        }
    }
}

@Suite("PSD composite decode")
struct PsdPixelsTests {
    @Test func decodesRawRGB() throws {
        let img = try #require(try? PsdDecoder.decode(Data(base64Encoded: rgbRawB64)!))
        expectRGB(img)
        #expect(img.pixel(x: 0, y: 0).a == 255)
    }

    @Test func decodesRleRGBIdenticalToRaw() throws {
        let raw = try #require(try? PsdDecoder.decode(Data(base64Encoded: rgbRawB64)!))
        let rle = try #require(try? PsdDecoder.decode(Data(base64Encoded: rgbRleB64)!))
        #expect(rle == raw)
    }

    @Test func decodesRleRGBAWithAlpha() throws {
        let img = try #require(try? PsdDecoder.decode(Data(base64Encoded: rgbaRleB64)!))
        expectRGB(img)
        for x in 0..<8 {
            #expect(img.pixel(x: x, y: 3).a == UInt8(255 - x * 16))
        }
    }

    @Test func decodesGrayscaleToRGB() throws {
        let img = try #require(try? PsdDecoder.decode(Data(base64Encoded: grayRawB64)!))
        #expect(img.width == 5 && img.height == 4)
        for y in 0..<4 {
            for x in 0..<5 {
                let p = img.pixel(x: x, y: y)
                let v = UInt8(x + y * 10)
                #expect(p.r == v && p.g == v && p.b == v && p.a == 255)
            }
        }
    }

    @Test func decodesGrayscalePlusAlpha() throws {
        let img = try #require(try? PsdDecoder.decode(Data(base64Encoded: grayAlphaRawB64)!))
        #expect(img.pixel(x: 2, y: 2).a == 202)
        #expect(img.pixel(x: 0, y: 0).a == 200)
    }

    @Test func rejectsUnsupportedVariants() {
        #expect((try? PsdDecoder.decode(Data("not a psd".utf8))) == nil)
        #expect((try? PsdDecoder.decode(Data(base64Encoded: depth16B64)!)) == nil)
        #expect((try? PsdDecoder.decode(Data(base64Encoded: cmykB64)!)) == nil)
    }

    @Test func rejectsTruncatedImageData() {
        var bytes = [UInt8](Data(base64Encoded: rgbRawB64)!)
        bytes.removeLast(10)
        #expect((try? PsdDecoder.decode(Data(bytes))) == nil)
    }

    @Test func packBitsEdgeCases() {
        // 128 = NOP between runs; long literal run > 127 needs multiple packets
        // (covered by fixtures), and a truncated literal is rejected.
        #expect(PsdDecoder.packBitsDecode([0xFE, 0x2A, 0x80, 0x00, 0x07], expected: 4) == [0x2A, 0x2A, 0x2A, 0x07])
        #expect(PsdDecoder.packBitsDecode([0x03, 0x01], expected: 4) == nil)
    }

    @Test func libraryBuildsDerivativesFromPsd() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("asssets-psd-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let psdURL = dir.appendingPathComponent("mockup.psd")
        try Data(base64Encoded: rgbRleB64)!.write(to: psdURL)

        var lib = Library()
        let count = try lib.importFolder(dir.path)
        #expect(count == 1)
        let asset = try #require(lib.assets.values.first)
        #expect(asset.kind == .psd)
        #expect(asset.width == 8 && asset.height == 6)

        let thumbs = dir.appendingPathComponent("thumbs").path
        let made = lib.generateDerivatives(thumbnailsDir: thumbs)
        #expect(made == 1)
        let updated = try #require(lib.assets[asset.id])
        #expect(updated.palette?.isEmpty == false)
        let thumbFile = try #require(updated.thumbnailFile)
        let thumb = try #require(ImageDecoder.decode(path: thumbFile))
        #expect(thumb.width <= 256 && thumb.height <= 256)
        // Thumbnail of the fixture: top-left pixel is black, top-right is red.
        #expect(thumb.pixel(x: 0, y: 0).r == 0)
        #expect(thumb.pixel(x: thumb.width - 1, y: 0).r > 180)
    }
}
