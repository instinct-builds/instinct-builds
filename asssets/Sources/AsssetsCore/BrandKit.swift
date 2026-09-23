import Foundation

/// Contact sheet layout, combined palettes and swatch files for brand-kit export (1.5).
public enum BrandKit {
    // MARK: Swatches

    public struct Swatch: Equatable, Sendable {
        public var name: String
        public var hex: String
        public init(name: String, hex: String) { self.name = name; self.hex = hex }
    }

    /// Adobe Swatch Exchange (.ase) 1.0: RGB global colors, readable by Photoshop, Illustrator, InDesign, Affinity and Figma plugins.
    public static func ase(_ swatches: [Swatch]) -> Data {
        var d = Data("ASEF".utf8)
        func u16(_ v: UInt16) { d.append(UInt8(v >> 8)); d.append(UInt8(v & 0xFF)) }
        func u32(_ v: UInt32) { for s in [24, 16, 8, 0] { d.append(UInt8((v >> UInt32(s)) & 0xFF)) } }
        u16(1); u16(0)
        let valid = swatches.compactMap { s in Similarity.rgb(s.hex).map { (s.name, $0) } }
        u32(UInt32(valid.count))
        for (name, rgb) in valid {
            let chars = Array(name.utf16) + [0]
            let length = 2 + chars.count * 2 + 4 + 12 + 2
            u16(0x0001); u32(UInt32(length))
            u16(UInt16(chars.count)); for c in chars { u16(c) }
            d.append(contentsOf: Array("RGB ".utf8))
            for v in [rgb.0, rgb.1, rgb.2] { u32(Float(v / 255).bitPattern) }
            u16(2)   // normal color
        }
        return d
    }

    /// Plain JSON swatches for Figma/Sketch scripts and design tokens.
    public static func swatchJSON(title: String, _ swatches: [Swatch]) -> Data {
        let body: [String: Any] = ["name": title, "colors": swatches.map { ["name": $0.name, "hex": $0.hex.uppercased()] }]
        return (try? JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }

    /// The colors a set of assets shares most: every palette votes, similar colors (within `tolerance` of 0...1 RGB distance)
    /// merge into the most-voted one. Returns up to `count` hex colors, most common first.
    public static func combinedPalette(_ palettes: [[String]], count: Int = 8, tolerance: Double = 0.09) -> [String] {
        var votes: [(hex: String, rgb: (Double, Double, Double), n: Int, first: Int)] = []
        var order = 0
        for p in palettes { for hex in p {
            guard let c = Similarity.rgb(hex) else { continue }
            if let i = votes.firstIndex(where: { dist($0.rgb, c) <= tolerance }) { votes[i].n += 1 }
            else { votes.append((hex.uppercased(), c, 1, order)); order += 1 }
        } }
        return votes.sorted { $0.n != $1.n ? $0.n > $1.n : $0.first < $1.first }.prefix(count).map(\.hex)
    }

    static func dist(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
        (((a.0 - b.0) * (a.0 - b.0) + (a.1 - b.1) * (a.1 - b.1) + (a.2 - b.2) * (a.2 - b.2)).squareRoot()) / 441.673
    }

    // MARK: Contact sheet layout

    public struct Rect: Equatable, Sendable {
        public var x, y, w, h: Double
        public init(x: Double, y: Double, w: Double, h: Double) { self.x = x; self.y = y; self.w = w; self.h = h }
    }

    public struct Sheet: Equatable, Sendable {
        public var pageWidth: Double
        public var pageHeight: Double
        /// Cells per content page, top-left origin, each holding a 1.36:1 thumbnail plus caption.
        public var pages: [[Rect]]
        public var totalPages: Int { pages.count + 1 }   // + cover
    }

    /// US Letter landscape by default; 4 columns x 3 rows per page with 36 pt margins and a 54 pt header band.
    public static func layout(count: Int, pageWidth: Double = 792, pageHeight: Double = 612, columns: Int = 4, rows: Int = 3,
                              margin: Double = 36, header: Double = 54, gap: Double = 14) -> Sheet {
        let cellW = (pageWidth - margin * 2 - gap * Double(columns - 1)) / Double(columns)
        let cellH = (pageHeight - margin * 2 - header - gap * Double(rows - 1)) / Double(rows)
        let perPage = columns * rows
        var pages: [[Rect]] = []
        var i = 0
        while i < count {
            var cells: [Rect] = []
            for k in 0..<min(perPage, count - i) {
                let c = k % columns, r = k / columns
                cells.append(Rect(x: margin + Double(c) * (cellW + gap), y: margin + header + Double(r) * (cellH + gap), w: cellW, h: cellH))
            }
            pages.append(cells); i += perPage
        }
        return Sheet(pageWidth: pageWidth, pageHeight: pageHeight, pages: pages)
    }

    /// File-safe base name for a kit: "Material Textures Brand Kit".
    public static func kitName(_ title: String) -> String { DragOut.safeName(title + " Brand Kit") }
}
