import Testing
import Foundation
@testable import AsssetsCore

private func wav(samples: [Int16], rate: Int = 44100, channels: Int = 1, listChunk: Bool = true) -> Data {
    var d = Data()
    func put32(_ v: Int) { var x = UInt32(v).littleEndian; d.append(Data(bytes: &x, count: 4)) }
    func put16(_ v: Int) { var x = UInt16(v).littleEndian; d.append(Data(bytes: &x, count: 2)) }
    let list = listChunk ? Data("LIST".utf8) + Data([5, 0, 0, 0]) + Data("INFOx".utf8) + Data([0]) : Data()  // odd size + pad
    d.append(Data("RIFF".utf8)); put32(0); d.append(Data("WAVE".utf8))
    d.append(Data("fmt ".utf8)); put32(16); put16(1); put16(channels); put32(rate); put32(rate * channels * 2); put16(channels * 2); put16(16)
    d.append(list)
    d.append(Data("data".utf8)); put32(samples.count * 2)
    for s in samples { put16(Int(UInt16(bitPattern: s))) }
    return d
}

@Suite("Audio waveform")
struct WaveformTests {
    @Test func readsPeaksPastAListChunk() throws {
        var samples = [Int16](repeating: 0, count: 44100)
        for i in 0..<4410 { samples[i] = 16000 }            // loud first tenth
        for i in 22050..<26460 { samples[i] = -8000 }       // half as loud in the middle
        let s = try #require(Waveform.summarize(wav: wav(samples: samples), buckets: 10))
        #expect(s.peaks.count == 10)
        #expect(s.sampleRate == 44100 && s.channels == 1 && s.bitsPerSample == 16)
        #expect(abs(s.duration - 1.0) < 0.001)
        #expect(s.peaks[0] == 1)
        #expect(abs(s.peaks[5] - 0.5) < 0.01)
        #expect(s.peaks[8] == 0)
    }

    @Test func rejectsNonWav() {
        #expect(Waveform.summarize(wav: Data("not audio at all".utf8)) == nil)
        #expect(Waveform.summarize(wav: Data()) == nil)
    }

    @Test func silenceStaysFlat() throws {
        let s = try #require(Waveform.summarize(wav: wav(samples: [Int16](repeating: 0, count: 1000), listChunk: false), buckets: 8))
        let flat = s.peaks.allSatisfy { $0 == 0 }
        #expect(flat)
    }
}

@Suite("Vector scene")
struct VectorSceneTests {
    let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" width="1200" height="800" viewBox="0 0 1200 800"><defs><linearGradient id="g" x2="1" y2="1"><stop stop-color="#e40f29"/><stop offset="1" stop-color="#e18fb2"/></linearGradient></defs><rect width="1200" height="800" fill="url(#g)"/><path d="M-34 883 L60 695 L154 883 Z" fill="#e40f29" opacity=".7"/><circle cx="401" cy="724" r="99" fill="#e18fb2" opacity=".72"/><text x="60" y="740" font-family="Helvetica" font-size="72" font-weight="700" fill="white">ASSSETS / VECTOR 03</text></svg>
    """

    @Test func parsesShippedVectorFormat() throws {
        let scene = try #require(VectorScene.parse(svg))
        #expect(scene.width == 1200 && scene.height == 800)
        #expect(scene.elements.count == 4)
        #expect(scene.elements[0].fill == .gradient(["#E40F29", "#E18FB2"]))
        #expect(scene.elements[1].shape == .polygon([.init(x: -34, y: 883), .init(x: 60, y: 695), .init(x: 154, y: 883)]))
        #expect(abs(scene.elements[1].opacity - 0.7) < 0.0001)
        #expect(scene.elements[2].shape == .ellipse(cx: 401, cy: 724, rx: 99, ry: 99))
        #expect(scene.elements[3].shape == .text(x: 60, y: 740, size: 72, string: "ASSSETS / VECTOR 03"))
        #expect(scene.elements[3].fill == .color("#FFFFFF"))
        #expect(scene.colors.first == "#E40F29")
    }

    @Test func relativeAndAxisPathCommands() {
        let polys = VectorScene.pathPolygons("m10 10 h20 v20 l-20 0 z M0 0 L5 5 L0 5")
        #expect(polys.count == 2)
        #expect(polys[0] == [.init(x: 10, y: 10), .init(x: 30, y: 10), .init(x: 30, y: 30), .init(x: 10, y: 30)])
        #expect(polys[1].count == 3)
    }

    @Test func viewBoxOnlyAndInvalidInput() {
        #expect(VectorScene.parse("<svg viewBox=\"0 0 64 32\"><rect width=\"4\" height=\"4\" fill=\"#abc\"/></svg>")?.width == 64)
        #expect(VectorScene.parse("<svg viewBox=\"0 0 64 32\"><rect width=\"4\" height=\"4\" fill=\"#abc\"/></svg>")?.elements.first?.fill == .color("#AABBCC"))
        #expect(VectorScene.parse("<html></html>") == nil)
    }
}

@Suite("Shipped starter media")
struct ShippedMediaTests {
    /// Reads the real archive contents when the test runs from the package root with the zip expanded
    /// by the workflow; skipped silently elsewhere.
    @Test func everyShippedFileIsDescribed() {
        let names = ["ink-fiber-4k.png", "editorial-vector-03.svg", "editorial-vector-12.svg", "concrete-dust-4k.png", "ambient-bed.wav",
                     "night-grid-4k.png", "prismatic-foil-4k.png", "motion-loop-01.mp4", "device-stage-mockup.png", "paper-grain-4k.png",
                     "motion-loop-02.mp4", "cosmetic-plinth-mockup.png", "folded-poster-mockup.png", "blueprint-4k.png", "sandstone-4k.png",
                     "risograph-4k.png", "album-gatefold-mockup.png"]
        for n in names { #expect(StarterCatalog.describe(filename: n) != nil, "\(n)") }
        #expect(StarterCatalog.describe(filename: "album-gatefold-mockup.png")?.collection == "Device Mockups")
        #expect(StarterCatalog.describe(filename: "risograph-4k.png")?.collection == "Material Textures")
    }
}
