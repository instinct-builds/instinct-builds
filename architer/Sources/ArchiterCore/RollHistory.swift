import Foundation

/// Persists the most recent dice rolls across launches, so the table's
/// roll history survives quitting the app mid-session. Kept deliberately
/// small: the last N rolls, one JSON file next to the character files.
public struct RollHistoryStore: Sendable {
    public static let defaultLimit = 50

    public let directory: URL
    public let limit: Int

    public init(directory: URL, limit: Int = RollHistoryStore.defaultLimit) {
        self.directory = directory
        self.limit = limit
    }

    private var fileURL: URL { directory.appendingPathComponent("roll-history.json") }

    public func load() -> [RollResult] {
        guard let data = try? Data(contentsOf: fileURL),
              let rolls = try? JSONDecoder().decode([RollResult].self, from: data) else {
            return []
        }
        return Array(rolls.prefix(limit))
    }

    public func save(_ rolls: [RollResult]) {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(Array(rolls.prefix(limit))) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
