import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// 1.94: Finder tags live in the `com.apple.metadata:_kMDItemUserTags` extended attribute, a binary plist array of
/// strings. A tag with a color is stored as "Name\n<color index>". ASSSETS reads these on import and can write them onto
/// exported COPIES. It never writes them onto the library's original files.
public enum FinderTags {
    public static let attribute = "com.apple.metadata:_kMDItemUserTags"

    /// Tag names from the attribute's plist bytes, without color suffixes, in file order.
    public static func names(from data: Data) -> [String] {
        guard let list = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String] else { return [] }
        return list.map(name(of:)).filter { !$0.isEmpty }
    }

    static func name(of entry: String) -> String {
        String(entry.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
    }

    /// Existing entries kept verbatim (including color suffixes), then each wanted name that is not already there
    /// (compared case-insensitively on the name part) appended as a plain tag. Returns nil when nothing needs adding.
    public static func merged(existing: Data?, adding wanted: [String]) -> (data: Data, added: Int)? {
        let current = existing.flatMap { (try? PropertyListSerialization.propertyList(from: $0, options: [], format: nil)) as? [String] } ?? []
        var have = Set(current.map { name(of: $0).lowercased() })
        var out = current, added = 0
        for w in wanted {
            let n = w.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !n.isEmpty, !n.contains("\n"), have.insert(n.lowercased()).inserted else { continue }
            out.append(n); added += 1
        }
        guard added > 0, let data = try? PropertyListSerialization.data(fromPropertyList: out, format: .binary, options: 0) else { return nil }
        return (data, added)
    }

    public static func rawData(path: String) -> Data? {
        #if canImport(Darwin)
        let size = getxattr(path, attribute, nil, 0, 0, 0)
        guard size > 0 else { return nil }
        var buf = [UInt8](repeating: 0, count: size)
        let got = getxattr(path, attribute, &buf, size, 0, 0)
        return got > 0 ? Data(buf.prefix(got)) : nil
        #else
        return nil
        #endif
    }

    public static func read(path: String) -> [String] {
        rawData(path: path).map(names(from:)) ?? []
    }

    @discardableResult
    static func setRaw(path: String, data: Data) -> Bool {
        #if canImport(Darwin)
        return data.withUnsafeBytes { setxattr(path, attribute, $0.baseAddress, data.count, 0, 0) == 0 }
        #else
        return false
        #endif
    }

    /// Replaces the attribute with exactly these entries (used for fixtures and tests).
    @discardableResult
    public static func writeEntries(path: String, entries: [String]) -> Bool {
        guard let data = try? PropertyListSerialization.data(fromPropertyList: entries, format: .binary, options: 0) else { return false }
        return setRaw(path: path, data: data)
    }

    public enum WriteResult: Equatable, Sendable { case written(added: Int), unchanged, failed }

    /// Adds missing tag names to a file, keeping every tag it already has.
    public static func write(path: String, adding wanted: [String]) -> WriteResult {
        guard let m = merged(existing: rawData(path: path), adding: wanted) else { return .unchanged }
        return setRaw(path: path, data: m.data) ? .written(added: m.added) : .failed
    }
}
