import CoreServices
import Foundation

// Typed Launch Services probe for the .muew default-editor gate in CI.
// JXA cannot read the results of Create-rule LSCopy functions (they arrive as
// opaque Refs; run 709 proved neither .count nor ObjC.unwrap recovers them),
// so this probe is compiled Swift where the API contract is real types.

let proofPath = ProcessInfo.processInfo.environment["LS_PROOF"] ?? ""
let url = URL(fileURLWithPath: proofPath)

let uti = UTTypeCreatePreferredIdentifierForTag(
    kUTTagClassFilenameExtension as CFString, "muew" as CFString, nil
).takeRetainedValue() as String
print("uti: \(uti)")

var appPaths: [String] = []
if let apps = LSCopyApplicationURLsForURL(url as CFURL, .editor)?.takeRetainedValue() as? [URL] {
    appPaths = apps.map { $0.path }
}
print("apps: " + (appPaths.isEmpty ? "none" : appPaths.joined(separator: " | ")))

if let handler = LSCopyDefaultRoleHandlerForContentType(uti as CFString, .editor)?.takeRetainedValue() {
    print("default editor bundle id: \(handler)")
} else {
    print("default editor bundle id: none")
}
