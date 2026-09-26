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
