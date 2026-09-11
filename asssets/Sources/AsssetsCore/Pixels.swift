import Foundation

/// A decoded raster image: 8-bit RGBA, row-major. Decoded without platform
/// image APIs so the core works the same on macOS and Linux.
public struct PixelBuffer: Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var rgba: [UInt8] // width * height * 4

    public init(width: Int, height: Int, rgba: [UInt8]) {
        precondition(rgba.count == width * height * 4, "pixel count mismatch")
        self.width = width
        self.height = height
        self.rgba = rgba
    }

    public func pixel(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let i = (y * width + x) * 4
        return (rgba[i], rgba[i + 1], rgba[i + 2], rgba[i + 3])
    }
}

// MARK: - CRC-32 (PNG chunk checksums)

public enum CRC32 {
    private static let table: [UInt32] = {
        var t = [UInt32]()
        t.reserveCapacity(256)
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
            t.append(c)
        }
        return t
    }()

    public static func of(_ bytes: [UInt8]) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for b in bytes { c = table[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFFFFFF
    }
}

// MARK: - zlib (RFC 1950) / DEFLATE (RFC 1951)

public enum Zlib {

    /// Inflate a zlib stream: stored, fixed-Huffman, and dynamic-Huffman
    /// blocks, with the Adler-32 trailer verified.
    public static func inflate(_ data: Data) -> [UInt8]? { inflate([UInt8](data)) }

    public static func inflate(_ bytes: [UInt8]) -> [UInt8]? {
        guard bytes.count >= 6 else { return nil }
        let cmf = Int(bytes[0]), flg = Int(bytes[1])
        guard cmf & 0x0F == 8, (cmf * 256 + flg) % 31 == 0 else { return nil }
        guard flg & 0x20 == 0 else { return nil } // preset dictionary unsupported
        var br = BitReader(data: bytes, pos: 2)
        guard let out = inflateBlocks(&br) else { return nil }
        let n = bytes.count
        let expect = (UInt32(bytes[n - 4]) << 24) | (UInt32(bytes[n - 3]) << 16)
            | (UInt32(bytes[n - 2]) << 8) | UInt32(bytes[n - 1])
        guard expect == adler32(out) else { return nil }
        return out
    }

    /// zlib stream wrapping DEFLATE "stored" blocks. Larger than real
    /// compression but valid everywhere; used for writing thumbnails.
    public static func deflateStored(_ data: [UInt8]) -> [UInt8] {
        var out: [UInt8] = [0x78, 0x01]
        var pos = 0
        while true {
            let chunkLen = min(65535, data.count - pos)
            let isFinal = pos + chunkLen >= data.count
            out.append(isFinal ? 1 : 0)
            out.append(UInt8(chunkLen & 0xFF))
            out.append(UInt8((chunkLen >> 8) & 0xFF))
            let nlen = ~chunkLen & 0xFFFF
            out.append(UInt8(nlen & 0xFF))
            out.append(UInt8((nlen >> 8) & 0xFF))
            out.append(contentsOf: data[pos..<(pos + chunkLen)])
            pos += chunkLen
            if isFinal { break }
        }
        let ad = adler32(data)
        out.append(UInt8((ad >> 24) & 0xFF))
        out.append(UInt8((ad >> 16) & 0xFF))
        out.append(UInt8((ad >> 8) & 0xFF))
        out.append(UInt8(ad & 0xFF))
        return out
    }

    public static func adler32(_ data: [UInt8]) -> UInt32 {
        var a: UInt32 = 1, b: UInt32 = 0
        for x in data {
            a = (a + UInt32(x)) % 65521
            b = (b + a) % 65521
        }
        return (b << 16) | a
    }

    // MARK: DEFLATE internals

    struct BitReader {
        let data: [UInt8]
        var pos: Int
        var bitBuf: Int = 0
        var bitCount: Int = 0

        mutating func bits(_ n: Int) -> Int? {
            while bitCount < n {
                guard pos < data.count else { return nil }
                bitBuf |= Int(data[pos]) << bitCount
                pos += 1
                bitCount += 8
            }
            let v = bitBuf & ((1 << n) - 1)
            bitBuf >>= n
            bitCount -= n
            return v
        }

        mutating func discardToByteBoundary() {
            bitBuf = 0
            bitCount = 0
        }

        mutating func alignedBytes(_ n: Int) -> [UInt8]? {
            guard pos + n <= data.count else { return nil }
            let out = Array(data[pos..<(pos + n)])
            pos += n
            return out
        }
    }

    /// Canonical Huffman decoder built from code lengths (puff-style walk).
    struct Huffman {
        let maxLen: Int
        let counts: [Int]   // codes per length, index 1...maxLen
        let symbols: [Int]  // sorted by (length, symbol)

        init?(lengths: [Int]) {
            guard let maxLen = lengths.max(), maxLen > 0, maxLen <= 15 else { return nil }
            self.maxLen = maxLen
            var counts = [Int](repeating: 0, count: maxLen + 1)
            for l in lengths where l > 0 { counts[l] += 1 }
            // over-subscribed tables are invalid; incomplete tables are allowed
            var left = 1
            for l in 1...maxLen {
                left <<= 1
                left -= counts[l]
                if left < 0 { return nil }
            }
            self.counts = counts
            var offs = [Int](repeating: 0, count: maxLen + 2)
            for l in 1...maxLen { offs[l + 1] = offs[l] + counts[l] }
            var symbols = [Int](repeating: 0, count: lengths.filter { $0 > 0 }.count)
            for (sym, l) in lengths.enumerated() where l > 0 {
                symbols[offs[l]] = sym
                offs[l] += 1
            }
            self.symbols = symbols
        }

        func decode(_ br: inout BitReader) -> Int? {
            var code = 0, first = 0, index = 0
            for len in 1...maxLen {
                guard let bit = br.bits(1) else { return nil }
                code |= bit
                let count = counts[len]
                if code - first < count { return symbols[index + code - first] }
                index += count
                first = (first + count) << 1
                code <<= 1
            }
            return nil
        }
    }

    static let lengthBase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
                             35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
    static let lengthExtra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
                              3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
    static let distBase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
                           257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145,
                           8193, 12289, 16385, 24577]
    static let distExtra = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
                            7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]

    static func inflateBlocks(_ br: inout BitReader) -> [UInt8]? {
        var out: [UInt8] = []
        while true {
            guard let bfinal = br.bits(1), let btype = br.bits(2) else { return nil }
            switch btype {
            case 0: // stored
                br.discardToByteBoundary()
                guard let header = br.alignedBytes(4) else { return nil }
                let len = Int(header[0]) | Int(header[1]) << 8
                let nlen = Int(header[2]) | Int(header[3]) << 8
                guard len == (~nlen & 0xFFFF) else { return nil }
                guard let payload = br.alignedBytes(len) else { return nil }
                out.append(contentsOf: payload)
            case 1: // fixed Huffman
                var litLengths = [Int](repeating: 0, count: 288)
                for i in 0...143 { litLengths[i] = 8 }
                for i in 144...255 { litLengths[i] = 9 }
                for i in 256...279 { litLengths[i] = 7 }
                for i in 280...287 { litLengths[i] = 8 }
                let distLengths = [Int](repeating: 5, count: 30)
                guard let lit = Huffman(lengths: litLengths),
                      let dist = Huffman(lengths: distLengths),
                      decodeBlock(&br, lit, dist, &out) else { return nil }
            case 2: // dynamic Huffman
                guard let hlit = br.bits(5), let hdist = br.bits(5), let hclen = br.bits(4) else { return nil }
                let order = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]
                var clLengths = [Int](repeating: 0, count: 19)
                for i in 0..<(hclen + 4) {
                    guard let v = br.bits(3) else { return nil }
                    clLengths[order[i]] = v
                }
                guard let clHuff = Huffman(lengths: clLengths) else { return nil }
                let total = hlit + 257 + hdist + 1
                var lengths = [Int](repeating: 0, count: total)
                var i = 0
                while i < total {
                    guard let sym = clHuff.decode(&br) else { return nil }
                    switch sym {
                    case 0...15:
                        lengths[i] = sym
                        i += 1
                    case 16:
                        guard i > 0, let rep = br.bits(2) else { return nil }
                        let prev = lengths[i - 1]
                        for _ in 0..<(3 + rep) {
                            guard i < total else { return nil }
                            lengths[i] = prev
                            i += 1
                        }
                    case 17:
                        guard let rep = br.bits(3) else { return nil }
                        i += 3 + rep
                        guard i <= total else { return nil }
                    case 18:
                        guard let rep = br.bits(7) else { return nil }
                        i += 11 + rep
                        guard i <= total else { return nil }
                    default:
                        return nil
                    }
                }
                let litLengths = Array(lengths[0..<(hlit + 257)])
                var distLengths = Array(lengths[(hlit + 257)..<total])
                if distLengths.allSatisfy({ $0 == 0 }) { distLengths = [1] } // no matches used
                guard let lit = Huffman(lengths: litLengths),
                      let dist = Huffman(lengths: distLengths),
                      decodeBlock(&br, lit, dist, &out) else { return nil }
            default:
                return nil
            }
            if bfinal == 1 { break }
        }
        return out
    }

    static func decodeBlock(_ br: inout BitReader, _ lit: Huffman, _ dist: Huffman,
                            _ out: inout [UInt8]) -> Bool {
        while true {
            guard let sym = lit.decode(&br) else { return false }
            if sym < 256 {
                out.append(UInt8(sym))
            } else if sym == 256 {
                return true
            } else {
                let li = sym - 257
                guard li < 29, let extraLen = br.bits(lengthExtra[li]) else { return false }
                let len = lengthBase[li] + extraLen
                guard let dsym = dist.decode(&br), dsym < 30,
                      let extraDist = br.bits(distExtra[dsym]) else { return false }
                let d = distBase[dsym] + extraDist
                guard d <= out.count else { return false }
                for _ in 0..<len { out.append(out[out.count - d]) }
            }
        }
    }
}

// MARK: - PNG

public enum PNGDecoder {
    /// 8-bit PNGs: grayscale, grayscale+alpha, RGB, RGBA, and palette.
    /// Interlaced (Adam7) files are not decoded.
    public static func decode(_ data: Data) -> PixelBuffer? {
        let d = [UInt8](data)
        let sig: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard d.count >= 8, Array(d[0..<8]) == sig else { return nil }
        var pos = 8
        var width = 0, height = 0, colorType = -1, interlace = 1
        var bitDepth = 0
        var idat: [UInt8] = []
        var plte: [UInt8] = []
        var trns: [UInt8] = []
        while pos + 12 <= d.count {
            let len = Int(be32(d, pos))
            guard len >= 0, pos + 12 + len <= d.count else { return nil }
            let type = String(bytes: d[(pos + 4)..<(pos + 8)], encoding: .ascii) ?? ""
            let chunk = Array(d[(pos + 8)..<(pos + 8 + len)])
            switch type {
            case "IHDR":
                guard len == 13 else { return nil }
                width = Int(be32(chunk, 0))
                height = Int(be32(chunk, 4))
                bitDepth = Int(chunk[8])
                colorType = Int(chunk[9])
                interlace = Int(chunk[12])
            case "PLTE": plte = chunk
            case "tRNS": trns = chunk
            case "IDAT": idat.append(contentsOf: chunk)
            case "IEND": break
            default: break
            }
            pos += 12 + len
            if type == "IEND" { break }
        }
        guard width > 0, height > 0, bitDepth == 8, interlace == 0 else { return nil }
        let channels: Int
        switch colorType {
        case 0: channels = 1
        case 2: channels = 3
        case 3: channels = 1
        case 4: channels = 2
        case 6: channels = 4
        default: return nil
        }
        let stride = width * channels
        guard let raw = Zlib.inflate(idat), raw.count >= height * (1 + stride) else { return nil }

        // Unfilter scanlines.
        var recon = [UInt8](repeating: 0, count: height * stride)
        for y in 0..<height {
            let rowStart = y * (1 + stride)
            let filter = raw[rowStart]
            for x in 0..<stride {
                let v = Int(raw[rowStart + 1 + x])
                let a = x >= channels ? Int(recon[y * stride + x - channels]) : 0
                let b = y > 0 ? Int(recon[(y - 1) * stride + x]) : 0
                let c = (x >= channels && y > 0) ? Int(recon[(y - 1) * stride + x - channels]) : 0
                let add: Int
                switch filter {
                case 0: add = 0
                case 1: add = a
                case 2: add = b
                case 3: add = (a + b) / 2
                case 4: add = paeth(a, b, c)
                default: return nil
                }
                recon[y * stride + x] = UInt8((v + add) & 0xFF)
            }
        }

        // Expand to RGBA.
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        for i in 0..<(width * height) {
            let o = i * 4
            switch colorType {
            case 0:
                let g = recon[i]
                rgba[o] = g; rgba[o + 1] = g; rgba[o + 2] = g
            case 2:
                rgba[o] = recon[i * 3]; rgba[o + 1] = recon[i * 3 + 1]; rgba[o + 2] = recon[i * 3 + 2]
            case 3:
                let idx = Int(recon[i])
                guard idx * 3 + 2 < plte.count else { return nil }
                rgba[o] = plte[idx * 3]; rgba[o + 1] = plte[idx * 3 + 1]; rgba[o + 2] = plte[idx * 3 + 2]
                rgba[o + 3] = idx < trns.count ? trns[idx] : 255
            case 4:
                rgba[o] = recon[i * 2]; rgba[o + 1] = recon[i * 2]; rgba[o + 2] = recon[i * 2]
                rgba[o + 3] = recon[i * 2 + 1]
            default: // 6
                rgba[o] = recon[i * 4]; rgba[o + 1] = recon[i * 4 + 1]
                rgba[o + 2] = recon[i * 4 + 2]; rgba[o + 3] = recon[i * 4 + 3]
            }
        }
        return PixelBuffer(width: width, height: height, rgba: rgba)
    }

    private static func paeth(_ a: Int, _ b: Int, _ c: Int) -> Int {
        let p = a + b - c
        let pa = abs(p - a), pb = abs(p - b), pc = abs(p - c)
        if pa <= pb && pa <= pc { return a }
        return pb <= pc ? b : c
    }

    private static func be32(_ d: [UInt8], _ i: Int) -> UInt32 {
        (UInt32(d[i]) << 24) | (UInt32(d[i + 1]) << 16) | (UInt32(d[i + 2]) << 8) | UInt32(d[i + 3])
    }
}

public enum PNGEncoder {
    /// RGBA8 PNG with stored-DEFLATE IDAT: valid, simple, fast to write.
    public static func encode(_ img: PixelBuffer) -> Data {
        var raw: [UInt8] = []
        raw.reserveCapacity(img.height * (1 + img.width * 4))
        let rowBytes = img.width * 4
        for y in 0..<img.height {
            raw.append(0) // filter: none
            raw.append(contentsOf: img.rgba[(y * rowBytes)..<((y + 1) * rowBytes)])
        }
        var out = Data()
        out.append(contentsOf: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        var ihdr: [UInt8] = []
        ihdr.appendBE(UInt32(img.width))
        ihdr.appendBE(UInt32(img.height))
        ihdr.append(contentsOf: [8, 6, 0, 0, 0])
        appendChunk(&out, "IHDR", ihdr)
        appendChunk(&out, "IDAT", Zlib.deflateStored(raw))
        appendChunk(&out, "IEND", [])
        return out
    }

    private static func appendChunk(_ out: inout Data, _ type: String, _ payload: [UInt8]) {
        var lenBE = UInt32(payload.count).bigEndian
        Swift.withUnsafeBytes(of: &lenBE) { out.append(contentsOf: $0) }
        let typeBytes = [UInt8](type.utf8)
        out.append(contentsOf: typeBytes)
        out.append(contentsOf: payload)
        var crcBE = CRC32.of(typeBytes + payload).bigEndian
        Swift.withUnsafeBytes(of: &crcBE) { out.append(contentsOf: $0) }
    }
}

extension Array where Element == UInt8 {
    mutating func appendBE(_ v: UInt32) {
        var be = v.bigEndian
        Swift.withUnsafeBytes(of: &be) { append(contentsOf: $0) }
    }
}

// MARK: - BMP

public enum BMPDecoder {
    /// Uncompressed 24/32-bit BMP (BITMAPINFOHEADER or newer), bottom-up or
    /// top-down rows.
    public static func decode(_ data: Data) -> PixelBuffer? {
        let d = [UInt8](data)
        guard d.count >= 54, d[0] == 0x42, d[1] == 0x4D else { return nil } // "BM"
        let dataOffset = Int(le32(d, 10))
        guard Int(le32(d, 14)) >= 40 else { return nil }
        let width = Int(Int32(bitPattern: le32(d, 18)))
        let heightRaw = Int(Int32(bitPattern: le32(d, 22)))
        let topDown = heightRaw < 0
        let height = abs(heightRaw)
        let bpp = Int(le16(d, 28))
        guard Int(le16(d, 26)) == 1, Int(le32(d, 30)) == 0,
              bpp == 24 || bpp == 32, width > 0, height > 0 else { return nil }
        let bytesPerPx = bpp / 8
        let rowSize = ((bpp * width + 31) / 32) * 4
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            let srcY = topDown ? y : height - 1 - y
            let rowStart = dataOffset + srcY * rowSize
            guard rowStart >= 0, rowStart + width * bytesPerPx <= d.count else { return nil }
            for x in 0..<width {
                let o = rowStart + x * bytesPerPx
                let di = (y * width + x) * 4
                rgba[di] = d[o + 2]     // R (file order is BGRA)
                rgba[di + 1] = d[o + 1] // G
                rgba[di + 2] = d[o]     // B
                rgba[di + 3] = bpp == 32 ? d[o + 3] : 255
            }
        }
        return PixelBuffer(width: width, height: height, rgba: rgba)
    }

    private static func le32(_ d: [UInt8], _ i: Int) -> UInt32 {
        UInt32(d[i]) | (UInt32(d[i + 1]) << 8) | (UInt32(d[i + 2]) << 16) | (UInt32(d[i + 3]) << 24)
    }
    private static func le16(_ d: [UInt8], _ i: Int) -> UInt16 {
        UInt16(d[i]) | (UInt16(d[i + 1]) << 8)
    }
}

// MARK: - unified decode + thumbnails

public enum ImageDecoder {
    /// PNG and BMP decode without platform image APIs. JPEG/GIF/TIFF remain
    /// header-only here; the macOS shell uses QuickLook thumbnails for those.
    public static func decode(path: String) -> PixelBuffer? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return PNGDecoder.decode(data) ?? BMPDecoder.decode(data)
    }
}

public enum Thumbnailer {
    /// Box-average downscale so the longest side is at most maxDim pixels.
    /// Never upscales.
    public static func thumbnail(from img: PixelBuffer, maxDim: Int) -> PixelBuffer {
        guard maxDim > 0 else { return img }
        let scale = Double(maxDim) / Double(max(img.width, img.height))
        guard scale < 1.0 else { return img }
        let nw = max(1, Int((Double(img.width) * scale).rounded()))
        let nh = max(1, Int((Double(img.height) * scale).rounded()))
        var out = [UInt8](repeating: 0, count: nw * nh * 4)
        for dy in 0..<nh {
            let y0 = dy * img.height / nh
            let y1 = max(y0 + 1, (dy + 1) * img.height / nh)
            for dx in 0..<nw {
                let x0 = dx * img.width / nw
                let x1 = max(x0 + 1, (dx + 1) * img.width / nw)
                var r = 0, g = 0, b = 0, a = 0, n = 0
                for y in y0..<min(y1, img.height) {
                    for x in x0..<min(x1, img.width) {
                        let i = (y * img.width + x) * 4
                        r += Int(img.rgba[i])
                        g += Int(img.rgba[i + 1])
                        b += Int(img.rgba[i + 2])
                        a += Int(img.rgba[i + 3])
                        n += 1
                    }
                }
                let o = (dy * nw + dx) * 4
                out[o] = UInt8(r / n)
                out[o + 1] = UInt8(g / n)
                out[o + 2] = UInt8(b / n)
                out[o + 3] = UInt8(a / n)
            }
        }
        return PixelBuffer(width: nw, height: nh, rgba: out)
    }
}
