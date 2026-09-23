import Foundation

// MARK: - Export presets: named sizes and formats, crops, and file names

public enum ExportFormat: String, Codable, Sendable {
    case jpeg, png, tiff
    public var ext: String { self == .jpeg ? "jpg" : rawValue }
}

public enum CropMode: String, CaseIterable, Codable, Sendable {
    case center = "Center"
    case detail = "Detail-aware"
}

public struct ExportRect: Equatable, Sendable {
    public var x: Int, y: Int, w: Int, h: Int
    public init(x: Int, y: Int, w: Int, h: Int) { self.x = x; self.y = y; self.w = w; self.h = h }
}

/// One file a preset writes: which region of the source, at what size.
public struct ExportOutput: Equatable, Sendable {
    public var suffix: String          // "@1x" etc; "" for the main file
    public var width: Int
    public var height: Int
    public var crop: ExportRect        // in source pixels
    public var format: ExportFormat
    public var dpi: Int
    public init(suffix: String, width: Int, height: Int, crop: ExportRect, format: ExportFormat, dpi: Int) {
        self.suffix = suffix; self.width = width; self.height = height; self.crop = crop; self.format = format; self.dpi = dpi
    }
}

public enum ExportPreset: String, CaseIterable, Codable, Identifiable, Sendable {
    case web = "Web"
    case social = "Social Square"
    case story = "Story"
    case uhd = "4K PNG"
    case print = "Print TIFF"

    public var id: String { rawValue }
    public var slug: String {
        switch self { case .web: "web"; case .social: "social"; case .story: "story"; case .uhd: "4k"; case .print: "print" }
    }
    public var detail: String {
        switch self {
        case .web: "JPEG, 2400 px long edge plus a 1200 px @1x"
        case .social: "JPEG, 1080 × 1080 crop"
        case .story: "JPEG, 1080 × 1920 crop"
        case .uhd: "PNG, 3840 px long edge"
        case .print: "TIFF at 300 dpi, full size"
        }
    }
    public var format: ExportFormat {
        switch self { case .web, .social, .story: .jpeg; case .uhd: .png; case .print: .tiff }
    }
    public var symbol: String {
        switch self { case .web: "globe"; case .social: "square"; case .story: "rectangle.portrait"; case .uhd: "4k.tv"; case .print: "printer" }
    }

    /// Files to write for a source of the given size. Long-edge presets never upscale; crop presets fill their frame.
    /// `focus` is the preferred crop window (from `SmartCrop`), used when it has the right aspect.
    public func outputs(width w: Int, height h: Int, crop: CropMode = .center, focus: ExportRect? = nil) -> [ExportOutput] {
        guard w > 0, h > 0 else { return [] }
        let full = ExportRect(x: 0, y: 0, w: w, h: h)
        func longEdge(_ edge: Int, suffix: String = "") -> ExportOutput {
            let s = min(1, Double(edge) / Double(max(w, h)))
            return ExportOutput(suffix: suffix, width: max(1, Int((Double(w) * s).rounded())), height: max(1, Int((Double(h) * s).rounded())),
                                crop: full, format: format, dpi: 72)
        }
        func framed(_ tw: Int, _ th: Int) -> ExportOutput {
            let window = (crop == .detail ? focus : nil) ?? SmartCrop.centered(width: w, height: h, aspect: Double(tw) / Double(th))
            return ExportOutput(suffix: "", width: tw, height: th, crop: window, format: format, dpi: 72)
        }
        switch self {
        case .web: return [longEdge(2400), longEdge(1200, suffix: "@1x")]
        case .social: return [framed(1080, 1080)]
        case .story: return [framed(1080, 1920)]
        case .uhd: return [longEdge(3840)]
        case .print: return [ExportOutput(suffix: "", width: w, height: h, crop: full, format: .tiff, dpi: 300)]
        }
    }

    /// Aspect ratio of the crop presets, nil for presets that keep the whole image.
    public var cropAspect: Double? {
        switch self { case .social: 1; case .story: 1080.0 / 1920.0; default: nil }
    }
}

public enum SmartCrop {
    /// The largest window of `aspect` (w/h) centered in the source.
    public static func centered(width w: Int, height h: Int, aspect: Double) -> ExportRect {
        let (cw, ch) = size(width: w, height: h, aspect: aspect)
        return ExportRect(x: (w - cw) / 2, y: (h - ch) / 2, w: cw, h: ch)
    }

    static func size(width w: Int, height h: Int, aspect: Double) -> (Int, Int) {
        if Double(w) / Double(h) > aspect { return (max(1, Int((Double(h) * aspect).rounded())), h) }
        return (w, max(1, Int((Double(w) / aspect).rounded())))
    }

    /// Slides the largest `aspect` window along the free axis and keeps the one with the most edge detail,
    /// so a crop lands on the subject instead of an empty margin. `buffer` is a downsampled copy of the source;
    /// the result is in source pixels.
    public static func detailWindow(_ buffer: PixelBuffer, sourceWidth w: Int, sourceHeight h: Int, aspect: Double) -> ExportRect {
        let bw = buffer.width, bh = buffer.height
        let center = centered(width: w, height: h, aspect: aspect)
        guard bw > 2, bh > 2 else { return center }
        // Luma gradient energy per column and per row.
        var luma = [Double](repeating: 0, count: bw * bh)
        for i in 0..<(bw * bh) {
            let p = i * 4
            luma[i] = 0.299 * Double(buffer.rgba[p]) + 0.587 * Double(buffer.rgba[p + 1]) + 0.114 * Double(buffer.rgba[p + 2])
        }
        var col = [Double](repeating: 0, count: bw), row = [Double](repeating: 0, count: bh)
        // Forward differences, so fine one-pixel detail counts too.
        for y in 0..<(bh - 1) { for x in 0..<(bw - 1) {
            let v = luma[y * bw + x]
            let e = abs(luma[y * bw + x + 1] - v) + abs(luma[(y + 1) * bw + x] - v)
            col[x] += e; row[y] += e
        } }
        let horizontalFree = center.w < w
        let energy = horizontalFree ? col : row
        let n = energy.count
        let srcFree = horizontalFree ? w : h, srcWin = horizontalFree ? center.w : center.h
        let win = max(1, min(n, Int((Double(srcWin) / Double(srcFree) * Double(n)).rounded())))
        guard win < n else { return center }
        var prefix = [0.0]; for e in energy { prefix.append(prefix.last! + e) }
        let total = prefix[n]
        guard total > 0 else { return center }
        var best = (n - win) / 2, bestSum = prefix[best + win] - prefix[best]
        let mid = Double(n - win) / 2
        for s in 0...(n - win) {
            let sum = prefix[s + win] - prefix[s]
            // Ties (and near ties, within 2%) go to the window closer to the center.
            if sum > bestSum * 1.02 || (abs(sum - bestSum) <= bestSum * 0.02 && abs(Double(s) - mid) < abs(Double(best) - mid)) {
                best = s; bestSum = max(sum, bestSum)
            }
        }
        let offset = Int((Double(best) / Double(n) * Double(srcFree)).rounded())
        let o = min(srcFree - srcWin, max(0, offset))
        return horizontalFree ? ExportRect(x: o, y: 0, w: center.w, h: center.h) : ExportRect(x: 0, y: o, w: center.w, h: center.h)
    }
}

public enum FilenamePattern {
    public static let defaultPattern = "{title}-{preset}"
    public static let tokens = ["{title}", "{preset}", "{w}", "{h}", "{n}", "{collection}", "{rating}", "{label}", "{date}"]

    /// Renders a name like "Terrazzo Texture-web@1x.jpg". Unknown text is kept; path characters are replaced.
    public static func render(_ pattern: String, title: String, preset: ExportPreset, output: ExportOutput, index: Int, collection: String) -> String {
        render(pattern, values: ["{title}": title, "{collection}": collection], preset: preset, output: output, index: index)
    }

    /// Same, with every asset token ({rating}, {label}, {kind}, {date}) available (1.14).
    public static func render(_ pattern: String, asset: StudioAsset, preset: ExportPreset, output: ExportOutput, index: Int, date: Date = Date()) -> String {
        render(pattern, values: PatternTokens.values(for: asset, date: date), preset: preset, output: output, index: index)
    }

    static func render(_ pattern: String, values base: [String: String], preset: ExportPreset, output: ExportOutput, index: Int) -> String {
        let s = pattern.trimmingCharacters(in: .whitespaces).isEmpty ? defaultPattern : pattern
        var values = base
        values["{preset}"] = preset.slug; values["{w}"] = "\(output.width)"; values["{h}"] = "\(output.height)"
        return DragOut.safeName(PatternTokens.expand(s, values: values, index: index) + output.suffix) + "." + output.format.ext
    }
}
