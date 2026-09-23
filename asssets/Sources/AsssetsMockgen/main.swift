import Foundation
import AsssetsCore

// Writes the original generated media bundled with ASSSETS: layered PSD mockups,
// seamless textures and editorial vectors. Everything is drawn from code.
// Usage: asssets-mockgen <output-dir> [--small]
let args = CommandLine.arguments
guard args.count >= 2 else { print("usage: asssets-mockgen <dir> [--small]"); exit(2) }
let dir = URL(fileURLWithPath: args[1], isDirectory: true)
let small = args.contains("--small")
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
for name in MockupFactory.names {
    guard let doc = MockupFactory.make(name, width: small ? 400 : 1600, height: small ? 300 : 1200) else { continue }
    let data = PsdWriter.write(doc)
    try data.write(to: dir.appendingPathComponent(name))
    print("\(name): \(doc.layers.count) layers, \(data.count) bytes")
}
for name in TextureFactory.names {
    guard let img = TextureFactory.make(name, size: small ? 256 : 2048) else { continue }
    let data = PNGEncoder.encodeUpFiltered(img)
    try data.write(to: dir.appendingPathComponent(name))
    print("\(name): \(img.width)x\(img.height), \(data.count) bytes (stored; recompressed at packaging)")
}
for name in VectorFactory.names {
    guard let svg = VectorFactory.make(name) else { continue }
    try svg.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    print("\(name): \(svg.utf8.count) bytes")
}
