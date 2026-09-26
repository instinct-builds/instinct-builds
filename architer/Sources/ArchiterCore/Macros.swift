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
    /// Damage-type tag (2.36.0): typed macro rolls carry the same
    /// outgoing-defense note attack damage rolls get. Optional, so macro
    /// files written before 2.36.0 decode unchanged.
    public var damageType: String?
    /// Pinned to the top of its group (3.15.0): the rolls a fight
    /// actually needs stay above the fold. Optional, so macro files
    /// written before 3.15.0 decode unchanged; nil stays unencoded.
    public var pinned: Bool?
    /// Target DC for rolls from this macro (3.20.0): the history card
    /// shows whether the roll met it. Optional, so macro files written
    /// before 3.20.0 decode unchanged; nil stays unencoded.
    public var targetDC: Int?

    public init(name: String, expression: String, characterName: String? = nil,
                damageType: String? = nil, pinned: Bool? = nil, targetDC: Int? = nil) {
        self.name = name
        self.expression = expression
        self.characterName = characterName
        self.damageType = damageType
        self.pinned = pinned
        self.targetDC = targetDC
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

/// Pinned macros first, the original order otherwise preserved
/// (3.15.0). Applied per group (character, table) at render, so a pin
/// never lifts a macro out of its owner section.
public func pinnedFirst(_ macros: [DiceMacro]) -> [DiceMacro] {
    macros.enumerated()
        .sorted {
            ($0.element.pinned == true ? 0 : 1, $0.offset)
                < ($1.element.pinned == true ? 0 : 1, $1.offset)
        }
        .map(\.element)
}

/// A clone of `macro` named "<name> copy", bumped to "copy 2", "copy 3",
/// ... while that scoped id is taken. The owner binding (table-wide vs
/// character) is preserved, so a copy never collides with a same-named
/// macro owned by someone else.
public func duplicatedMacro(_ macro: DiceMacro, existing: [DiceMacro]) -> DiceMacro {
    func scopedId(_ name: String) -> String {
        guard let owner = macro.characterName else { return name.lowercased() }
        return "\(owner.lowercased()):\(name.lowercased())"
    }
    let taken = Set(existing.map { $0.id })
    var candidate = "\(macro.name) copy"
    var n = 2
    while taken.contains(scopedId(candidate)) {
        candidate = "\(macro.name) copy \(n)"
        n += 1
    }
    return DiceMacro(name: candidate, expression: macro.expression,
                     characterName: macro.characterName, damageType: macro.damageType,
                     targetDC: macro.targetDC)
}
