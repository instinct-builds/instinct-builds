import Foundation

/// A saved dice shortcut: a name bound to a dice expression, so a table's
/// usual rolls ("Fireball", "Sneak attack") are one tap away.
public struct DiceMacro: Codable, Equatable, Sendable, Identifiable {
    public var id: String { name.lowercased() }
    public var name: String
    public var expression: String

    public init(name: String, expression: String) {
        self.name = name
        self.expression = expression
    }

    /// Trimmed, non-empty name and an expression the dice parser accepts.
    public var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && (try? DiceExpression.parse(expression)) != nil
    }
}

/// JSON persistence for dice macros, alongside the character files.
public struct MacroStore: Sendable {
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    private var fileURL: URL { directory.appendingPathComponent("dice-macros.json") }

    public func load() -> [DiceMacro] {
        guard let data = try? Data(contentsOf: fileURL),
              let macros = try? JSONDecoder().decode([DiceMacro].self, from: data) else {
            return []
        }
        return macros
    }

    public func save(_ macros: [DiceMacro]) {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(macros) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
