import Foundation

/// Checks whether an image repeats without a visible seam.
/// Compares the wrap-around edge (last column against first, last row against first)
/// with the typical difference between neighboring columns and rows inside the image.
public enum Seamless {
    public struct Report: Equatable, Sendable {
        /// Wrap-edge difference divided by the interior neighbor difference. About 1 means no seam.
        public var horizontal: Double
        public var vertical: Double
        public var tileable: Bool { horizontal <= Seamless.threshold && vertical <= Seamless.threshold }
    }

    public static let threshold = 2.5

    public static func analyze(_ img: PixelBuffer) -> Report {
        guard img.width >= 4, img.height >= 4 else { return Report(horizontal: .infinity, vertical: .infinity) }
        func d(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) -> Double {
            let p = img.pixel(x: x0, y: y0), q = img.pixel(x: x1, y: y1)
            return abs(Double(p.r) - Double(q.r)) + abs(Double(p.g) - Double(q.g)) + abs(Double(p.b) - Double(q.b))
        }
        let W = img.width, H = img.height
        var wrapX = 0.0, innerX = 0.0, wrapY = 0.0, innerY = 0.0
        for y in 0..<H {
            wrapX += d(W - 1, y, 0, y)
            for x in 0..<(W - 1) { innerX += d(x, y, x + 1, y) }
        }
        for x in 0..<W {
            wrapY += d(x, H - 1, x, 0)
            for y in 0..<(H - 1) { innerY += d(x, y, x, y + 1) }
        }
        wrapX /= Double(H); innerX /= Double(H * (W - 1))
        wrapY /= Double(W); innerY /= Double(W * (H - 1))
        // A floor keeps flat images (tiny interior differences) from reading as seams over rounding noise.
        return Report(horizontal: wrapX / max(innerX, 2), vertical: wrapY / max(innerY, 2))
    }

    /// Repeats an image `n` x `n` times (for previews and tiled exports).
    public static func tiled(_ img: PixelBuffer, times n: Int) -> PixelBuffer {
        let n = max(1, n)
        let W = img.width * n, H = img.height * n, row = img.width * 4
        var out = [UInt8](repeating: 0, count: W * H * 4)
        for ty in 0..<n { for y in 0..<img.height {
            let src = y * row, dstRow = (ty * img.height + y) * W * 4
            for tx in 0..<n { out.replaceSubrange((dstRow + tx * row)..<(dstRow + (tx + 1) * row), with: img.rgba[src..<(src + row)]) }
        } }
        return PixelBuffer(width: W, height: H, rgba: out)
    }

    /// Offset-and-blend: mixes the image with a copy shifted by half its size. The shifted copy is
    /// continuous across the wrap edges, so it takes over near the borders; the original stays in the middle.
    public static func makeTileable(_ img: PixelBuffer) -> PixelBuffer {
        let W = img.width, H = img.height
        guard W >= 4, H >= 4 else { return img }
        var out = img.rgba
        for y in 0..<H {
            let sy = (y + H / 2) % H
            let fy = abs(Double(y) / Double(H - 1) * 2 - 1)          // 0 at center, 1 at top/bottom edge
            for x in 0..<W {
                let sx = (x + W / 2) % W
                let fx = abs(Double(x) / Double(W - 1) * 2 - 1)
                let e = max(fx, fy)
                let t = min(1, max(0, (e - 0.55) / 0.45))           // original until 55% out, then ease to the shifted copy
                let m = t * t * (3 - 2 * t)
                let i = (y * W + x) * 4, j = (sy * W + sx) * 4
                for c in 0..<3 { out[i + c] = UInt8((Double(img.rgba[i + c]) * (1 - m) + Double(img.rgba[j + c]) * m).rounded()) }
                out[i + 3] = max(img.rgba[i + 3], img.rgba[j + 3])
            }
        }
        return PixelBuffer(width: W, height: H, rgba: out)
    }
}
