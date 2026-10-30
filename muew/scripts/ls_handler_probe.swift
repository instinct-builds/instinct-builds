import CoreServices
import Foundation

// Typed Launch Services probe for the .muew default-editor gate in CI.
// JXA cannot read the results of Create-rule LSCopy functions (they arrive as
// opaque Refs; run 709 proved neither .count nor ObjC.unwrap recovers them),
// so this probe is compiled Swift where the API contract is real types.
// Run 710 compile evidence: on the current SDK these calls return optional
// Unmanaged<T>?, so every result is explicitly nil-guarded before takeRetainedValue.

let proofPath = ProcessInfo.processInfo.environment["LS_PROOF"] ?? ""
let url = URL(fileURLWithPath: proofPath)

var uti: String? = nil
if let utiRef = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension as CFString, "muew" as CFString, nil) {
    uti = utiRef.takeRetainedValue() as String
}
print("uti: " + (uti ?? "null"))

var appPaths: [String] = []
if let appsRef = LSCopyApplicationURLsForURL(url as CFURL, .editor) {
    if let apps = appsRef.takeRetainedValue() as? [URL] {
        appPaths = apps.map { $0.path }
    }
}
print("apps: " + (appPaths.isEmpty ? "none" : appPaths.joined(separator: " | ")))

if let utiValue = uti {
    if let handlerRef = LSCopyDefaultRoleHandlerForContentType(utiValue as CFString, .editor) {
        print("default editor bundle id: \(handlerRef.takeRetainedValue())")
    } else {
        print("default editor bundle id: none")
    }
} else {
    print("default editor bundle id: skipped (no uti)")
}
