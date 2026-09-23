import Foundation
import AsssetsCore

// Writes the original layered PSD mockups bundled with ASSSETS.
// Usage: asssets-mockgen <output-dir> [width height]
let args = CommandLine.arguments
guard args.count >= 2 else { print("usage: asssets-mockgen <dir> [w h]"); exit(2) }
let dir = URL(fileURLWithPath: args[1], isDirectory: true)
let w = args.count >= 4 ? Int(args[2]) ?? 1600 : 1600, h = args.count >= 4 ? Int(args[3]) ?? 1200 : 1200
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
for name in MockupFactory.names {
    guard let doc = MockupFactory.make(name, width: w, height: h) else { continue }
    let data = PsdWriter.write(doc)
    try data.write(to: dir.appendingPathComponent(name))
    print("\(name): \(doc.layers.count) layers, \(data.count) bytes")
}
