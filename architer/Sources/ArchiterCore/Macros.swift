import Foundation

/// One step of a combo macro (3.21.0): a labeled notation roll with an
/// optional damage-type tag - the same inputs rollLabeled and
/// recordDamageRoll already take, so a part rolls through the existing
/// paths and inherits reroll, star, apply-to-HP, and the DC badge free.
public struct ComboPart: Codable, Equatable, Sendable {
    public var label: String
    public var expression: String
    /// DamageType raw value; unknown stored values fail safe to an
    /// untyped part on roll (the 2.33.0 / 2.36.0 pattern).
    public var damageType: String?

    public init(label: String, expression: String, damageType: String? = nil) {
        self.label = label
        self.expression = expression
        self.damageType = damageType
    }

    /// Trimmed label and an expression the dice parser accepts.
    public var isValid: Bool {
        !label.trimmingCharacters(in: .whitespaces).isEmpty
            && (try? DiceExpression.parse(expression)) != nil
    }
}

/// The summary a combo macro carries in its `expression` field - what
/// the row shows and old readers see: the part expressions joined.
public func comboSummary(_ parts: [ComboPart]) -> String {
    parts.map(\.expression).joined(separator: " \u{00B7} ")
}

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
    /// Combo parts (3.21.0): when present, one tap rolls each part in
    /// order as its own history entry (the rollAttack attack+damage
    /// precedent), and `expression` carries the summary. Optional, so
    /// macro files written before 3.21.0 decode unchanged; nil stays
    /// unencoded. Parts are self-contained - never references to other
    /// macros, so editing one macro can't drift another.
    public var parts: [ComboPart]?

    public init(name: String, expression: String, characterName: String? = nil,
                damageType: String? = nil, pinned: Bool? = nil, targetDC: Int? = nil,
                parts: [ComboPart]? = nil) {
        self.name = name
        self.expression = expression
        self.characterName = characterName
        self.damageType = damageType
        self.pinned = pinned
        self.targetDC = targetDC
        self.parts = parts
    }

    /// Trimmed, non-empty name plus either a parseable expression or a
    /// combo of 2+ valid parts.
    public var isValid: Bool {
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return false }
        if let parts { return parts.count >= 2 && parts.allSatisfy(\.isValid) }
        return (try? DiceExpression.parse(expression)) != nil
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
                     targetDC: macro.targetDC, parts: macro.parts)
}
