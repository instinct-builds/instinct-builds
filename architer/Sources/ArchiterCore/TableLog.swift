import Foundation

/// One entry in the table log (3.45.0): the party-level session record.
/// createdAt is the only stored fact - the day label derives at display
/// (JournalStamp.day), never stored.
public struct TableLogEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var createdAt: Date
    public var title: String
    public var text: String

    public init(id: UUID = UUID(), createdAt: Date = Date(), title: String, text: String) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.text = text
    }
}

/// Share text for the whole log (3.47.0): a head line, then each entry
/// oldest-first as "day - title" with its body. Derived from the entries,
/// mirroring the journal's copy-filtered precedent.
public enum TableLogExport {
    public static func text(entries: [TableLogEntry]) -> String {
        var blocks = ["Table log"]
        for entry in entries.sorted(by: { $0.createdAt < $1.createdAt }) {
            let head = "\(JournalStamp.day(entry.createdAt)) - \(entry.title.isEmpty ? "Note" : entry.title)"
            blocks.append(entry.text.isEmpty ? head : head + "\n" + entry.text)
        }
        return blocks.joined(separator: "\n\n")
    }
}

/// JSON persistence for the table log, alongside the character files.
/// Missing or corrupt data loads empty - every store's fail-safe.
public struct TableLogStore: Sendable {
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    private var fileURL: URL { directory.appendingPathComponent("table-log.json") }

    public func load() -> [TableLogEntry] {
        guard let data = try? Data(contentsOf: fileURL),
              let entries = try? JSONDecoder().decode([TableLogEntry].self, from: data) else {
            return []
        }
        return entries
    }

    public func save(_ entries: [TableLogEntry]) {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
