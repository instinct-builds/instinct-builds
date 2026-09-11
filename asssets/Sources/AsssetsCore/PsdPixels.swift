import Foundation

/// PSD composite-preview decoding, no platform image APIs.
///
/// Reads the flattened composite image stored at the end of every PSD saved
/// with Maximize Compatibility: 8-bit RGB or grayscale, raw or PackBits RLE
/// per-scanline. Layer stacks, 16/32-bit depth, CMYK/Lab, and ZIP compression
/// are out of scope for the core decoder; the macOS shell falls back to
/// QuickLook for those. We parse only the documented Adobe file-format
/// structure - no third-party code or content.
public enum PsdDecoder {

    public enum PsdError: Error, Equatable {
        case notPsd
        case unsupportedVersion(Int)
        case unsupportedDepth(Int)
        case unsupportedColorMode(Int)
        case unsupportedCompression(Int)
        case truncated
        case dimensionsInvalid
    }

    private struct Header {
        var channels: Int
        var width: Int
        var height: Int
        var depth: Int
        var colorMode: Int
        var imageDataOffset: Int
    }

    /// Decodes the composite image to RGBA. Returns nil for unreadable or
    /// unsupported files (callers fall back to header-only metadata).
    public static func decode(path: String) -> PixelBuffer? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? decode(data)
    }

    public static func decode(_ data: Data) throws -> PixelBuffer {
        let bytes = [UInt8](data)
        let header = try parseHeader(bytes)

        guard header.depth == 8 else { throw PsdError.unsupportedDepth(header.depth) }
        // 1 = grayscale, 3 = RGB. Others (bitmap, indexed, CMYK, Lab, ...) unsupported.
        guard header.colorMode == 1 || header.colorMode == 3 else {
            throw PsdError.unsupportedColorMode(header.colorMode)
        }
        guard header.width > 0, header.height > 0,
              header.width <= 30000, header.height <= 30000 else {
            throw PsdError.dimensionsInvalid
        }

        var pos = header.imageDataOffset
        guard pos + 2 <= bytes.count else { throw PsdError.truncated }
        let compression = Int(readU16(bytes, &pos))
        guard compression == 0 || compression == 1 else {
            throw PsdError.unsupportedCompression(compression)
        }

        let ch = header.channels
        let w = header.width, h = header.height
        let planeSize = w * h
        var planes = [[UInt8]](repeating: [UInt8](repeating: 0, count: planeSize), count: ch)

        if compression == 0 {
            let need = planeSize * ch
            guard pos + need <= bytes.count else { throw PsdError.truncated }
            for c in 0..<ch {
                planes[c] = Array(bytes[(pos + c * planeSize)..<(pos + (c + 1) * planeSize)])
            }
        } else {
            // RLE: big-endian UInt16 byte counts, one per scanline per channel.
            let rowCounts = ch * h
            guard pos + rowCounts * 2 <= bytes.count else { throw PsdError.truncated }
            var counts = [Int](repeating: 0, count: rowCounts)
            for i in 0..<rowCounts { counts[i] = Int(readU16(bytes, &pos)) }
            for c in 0..<ch {
                for row in 0..<h {
                    let n = counts[c * h + row]
                    guard pos + n <= bytes.count else { throw PsdError.truncated }
                    let decoded = packBitsDecode(Array(bytes[pos..<(pos + n)]), expected: w)
                    guard let line = decoded else { throw PsdError.truncated }
                    planes[c].replaceSubrange((row * w)..<(row * w + w), with: line)
                    pos += n
                }
            }
        }

        var rgba = [UInt8](repeating: 255, count: planeSize * 4)
        switch header.colorMode {
        case 1: // grayscale (+ optional alpha channel)
            for i in 0..<planeSize {
                let g = planes[0][i]
                rgba[i * 4] = g
                rgba[i * 4 + 1] = g
                rgba[i * 4 + 2] = g
                rgba[i * 4 + 3] = ch >= 2 ? planes[1][i] : 255
            }
        default: // RGB (+ optional alpha as 4th channel)
            guard ch >= 3 else { throw PsdError.truncated }
            for i in 0..<planeSize {
                rgba[i * 4] = planes[0][i]
                rgba[i * 4 + 1] = planes[1][i]
                rgba[i * 4 + 2] = planes[2][i]
                rgba[i * 4 + 3] = ch >= 4 ? planes[3][i] : 255
            }
        }
        return PixelBuffer(width: w, height: h, rgba: rgba)
    }

    // MARK: - internals

    private static func parseHeader(_ b: [UInt8]) throws -> Header {
        guard b.count >= 26 else { throw PsdError.truncated }
        guard b[0] == 0x38, b[1] == 0x42, b[2] == 0x50, b[3] == 0x53 else { // "8BPS"
            throw PsdError.notPsd
        }
        var pos = 4
        let version = Int(readU16(b, &pos))
        guard version == 1 else { throw PsdError.unsupportedVersion(version) }
        pos += 6 // reserved
        let channels = Int(readU16(b, &pos))
        let height = Int(readU32(b, &pos))
        let width = Int(readU32(b, &pos))
        let depth = Int(readU16(b, &pos))
        let colorMode = Int(readU16(b, &pos))
        guard channels >= 1, channels <= 56 else { throw PsdError.dimensionsInvalid }

        // Skip color mode data, image resources, and layer/mask sections.
        for _ in 0..<3 {
            guard pos + 4 <= b.count else { throw PsdError.truncated }
            let len = Int(readU32(b, &pos))
            guard pos + len <= b.count else { throw PsdError.truncated }
            pos += len
        }
        return Header(channels: channels, width: width, height: height,
                      depth: depth, colorMode: colorMode, imageDataOffset: pos)
    }

    /// PackBits: control byte n; 0...127 = copy n+1 literals, 129...255 =
    /// repeat next byte 257-n times, 128 = NOP.
    static func packBitsDecode(_ src: [UInt8], expected: Int) -> [UInt8]? {
        var out = [UInt8]()
        out.reserveCapacity(expected)
        var i = 0
        while i < src.count && out.count < expected {
            let n = Int(src[i]); i += 1
            if n <= 127 {
                let count = n + 1
                guard i + count <= src.count else { return nil }
                out.append(contentsOf: src[i..<(i + count)])
                i += count
            } else if n >= 129 {
                let count = 257 - n
                guard i < src.count else { return nil }
                out.append(contentsOf: repeatElement(src[i], count: count))
                i += 1
            }
        }
        guard out.count == expected else { return nil }
        return out
    }

    private static func readU16(_ b: [UInt8], _ pos: inout Int) -> UInt16 {
        let v = (UInt16(b[pos]) << 8) | UInt16(b[pos + 1])
        pos += 2
        return v
    }

    private static func readU32(_ b: [UInt8], _ pos: inout Int) -> UInt32 {
        let v = (UInt32(b[pos]) << 24) | (UInt32(b[pos + 1]) << 16)
              | (UInt32(b[pos + 2]) << 8) | UInt32(b[pos + 3])
        pos += 4
        return v
    }
}
