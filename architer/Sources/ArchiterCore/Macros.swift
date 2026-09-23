import Foundation

/// A saved dice shortcut: a name bound to a dice expression, so a table's
/// usual rolls ("Fireball", "Sneak attack") are one tap away.
public struct DiceMacro: Codable, Equatable, Sendable, Identifiable {
    /// Scoped id: table-wide macros key by name alone (the pre-2.18 shape),
    /// character macros prefix the owner, so both can share a name.
    public var id: String {
        guard let characterName else { return name.lowercased() }
        return "\(characterName.lowercased()):\(name.lowercased())"
    }
    public var name: String
    public var expression: String
    /// Owner when the macro is per-character; nil means shared by the table.
    /// Optional, so macro files written before 2.18 decode unchanged.
    public var characterName: String?

    public init(name: String, expression: String, characterName: String? = nil) {
        self.name = name
        self.expression = expression
        self.characterName = characterName
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

/// The macros worth showing when `characterName` sits at the table: the
/// shared table-wide set plus that character's own. Matching is
/// case-insensitive; a nil selection sees the shared set only.
public func visibleMacros(_ macros: [DiceMacro], for characterName: String?) -> [DiceMacro] {
    macros.filter {
        guard let owner = $0.characterName else { return true }
        guard let characterName else { return false }
        return owner.caseInsensitiveCompare(characterName) == .orderedSame
    }
}
