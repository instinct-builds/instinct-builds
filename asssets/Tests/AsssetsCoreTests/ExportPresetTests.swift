import Foundation
import Testing
@testable import AsssetsCore

@Suite("Export presets")
struct ExportPresetTests {
    @Test func longEdgeNeverUpscales() {
        let web = ExportPreset.web.outputs(width: 2048, height: 1024)
        #expect(web.map(\.width) == [2048, 1200]); #expect(web.map(\.height) == [1024, 600])
        #expect(web.map(\.suffix) == ["", "@1x"])
        let big = ExportPreset.uhd.outputs(width: 8000, height: 4000)[0]
        #expect(big.width == 3840 && big.height == 1920 && big.format == .png)
        let print = ExportPreset.print.outputs(width: 3000, height: 2000)[0]
        #expect(print.width == 3000 && print.dpi == 300 && print.format == .tiff)
    }

    @Test func cropPresetsFillTheirFrame() {
        let sq = ExportPreset.social.outputs(width: 2000, height: 1000)[0]
        #expect(sq.width == 1080 && sq.height == 1080); #expect(sq.crop == ExportRect(x: 500, y: 0, w: 1000, h: 1000))
        let story = ExportPreset.story.outputs(width: 2048, height: 2048)[0]
        #expect(story.crop.h == 2048); #expect(story.crop.w == 1152); #expect(story.crop.x == 448)
    }

    @Test func detailWindowFindsTheBusySide() {
        // 40 × 10 buffer: flat on the left, striped on the right. A square crop should move right.
        var rgba = [UInt8](repeating: 128, count: 40 * 10 * 4)
        for y in 0..<10 { for x in 28..<40 where x % 2 == 0 { for c in 0..<3 { rgba[(y * 40 + x) * 4 + c] = 255 } } }
        for i in stride(from: 3, to: rgba.count, by: 4) { rgba[i] = 255 }
        let r = SmartCrop.detailWindow(PixelBuffer(width: 40, height: 10, rgba: rgba), sourceWidth: 4000, sourceHeight: 1000, aspect: 1)
        #expect(r.w == 1000 && r.h == 1000); #expect(r.x >= 2700); #expect(r.x + r.w <= 4000)
        // Flat image: stays centered.
        let flat = PixelBuffer(width: 40, height: 10, rgba: [UInt8](repeating: 90, count: 1600))
        #expect(SmartCrop.detailWindow(flat, sourceWidth: 4000, sourceHeight: 1000, aspect: 1) == SmartCrop.centered(width: 4000, height: 1000, aspect: 1))
    }

    @Test func detailCropIsUsedOnlyInDetailMode() {
        let focus = ExportRect(x: 0, y: 0, w: 1000, h: 1000)
        #expect(ExportPreset.social.outputs(width: 2000, height: 1000, crop: .detail, focus: focus)[0].crop == focus)
        #expect(ExportPreset.social.outputs(width: 2000, height: 1000, crop: .center, focus: focus)[0].crop.x == 500)
    }

    @Test func filenamesFollowThePattern() {
        let o = ExportPreset.web.outputs(width: 2048, height: 2048)
        #expect(FilenamePattern.render("{title}-{preset}", title: "Terrazzo Texture", preset: .web, output: o[1], index: 3, collection: "Material Textures")
                == "Terrazzo Texture-web@1x.jpg")
        #expect(FilenamePattern.render("{n}_{collection}/{w}x{h}", title: "t", preset: .web, output: o[0], index: 3, collection: "Picks")
                == "03_Picks-2048x2048.jpg")
        #expect(FilenamePattern.render("  ", title: "Cork", preset: .uhd, output: ExportPreset.uhd.outputs(width: 10, height: 10)[0], index: 1, collection: "")
                == "Cork-4k.png")
    }
}
