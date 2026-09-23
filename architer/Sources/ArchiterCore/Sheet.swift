import Foundation

/// A block in the character sheet layout. The builder lets the user choose
/// which blocks appear, in which order, and at what size — the "sheet builder"
/// half of the product.
public enum SheetBlockKind: String, Codable, CaseIterable, Sendable {
    case identity       // name, lineage, calling, background, level, XP
    case abilities      // six ability scores + modifiers + saves
    case vitals         // HP, AC, initiative, speed, conditions, hit dice
    case skills
    case attacks        // weapons/attacks + spellcasting stats
    case spells         // slots + spell list
    case inventory      // currency, items, weight
    case features       // features & traits with limited uses
    case personality    // traits/ideals/bonds/flaws, appearance, backstory
    case diceRoller
    case notes
    case journal       // dated session-log entries
}

public enum BlockSize: String, Codable, CaseIterable, Sendable {
    case compact, regular, large
}

public struct SheetBlock: Codable, Equatable, Sendable, Identifiable {
    public var id: String { kind.rawValue }
    public var kind: SheetBlockKind
    public var visible: Bool
    public var size: BlockSize

    public init(kind: SheetBlockKind, visible: Bool = true, size: BlockSize = .regular) {
        self.kind = kind
        self.visible = visible
        self.size = size
    }
}

/// A user-defined sheet block: a title plus free text with {placeholders}
/// (see TemplateRenderer). Custom blocks render after the standard blocks,
/// in the order the user arranged them.
public struct CustomBlock: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID = UUID()
    public var title: String
    public var body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

public struct SheetLayout: Codable, Equatable, Sendable {
    public var blocks: [SheetBlock]
    public var customBlocks: [CustomBlock]

    public init(blocks: [SheetBlock] = SheetBlockKind.allCases.map { SheetBlock(kind: $0) },
                customBlocks: [CustomBlock] = []) {
        self.blocks = blocks
        self.customBlocks = customBlocks
    }

    // Layouts saved before newer blocks existed gain them (visible) on decode.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = try c.decode([SheetBlock].self, forKey: .blocks)
        let have = Set(decoded.map { $0.kind })
        let missing = SheetBlockKind.allCases.filter { !have.contains($0) }.map { SheetBlock(kind: $0) }
        blocks = decoded + missing
        customBlocks = try c.decodeIfPresent([CustomBlock].self, forKey: .customBlocks) ?? []
    }

    public var visibleBlocks: [SheetBlock] { blocks.filter(\.visible) }

    public mutating func move(fromOffsets: IndexSet, toOffset: Int) {
        // Foundation-free move (Array.move is a SwiftUI helper).
        let moving = fromOffsets.sorted().map { blocks[$0] }
        for i in fromOffsets.sorted().reversed() { blocks.remove(at: i) }
        let insertAt = toOffset - fromOffsets.filter { $0 < toOffset }.count
        blocks.insert(contentsOf: moving, at: max(0, min(insertAt, blocks.count)))
    }

    public mutating func setVisible(_ kind: SheetBlockKind, _ visible: Bool) {
        guard let i = blocks.firstIndex(where: { $0.kind == kind }) else { return }
        blocks[i].visible = visible
    }

    public mutating func setSize(_ kind: SheetBlockKind, _ size: BlockSize) {
        guard let i = blocks.firstIndex(where: { $0.kind == kind }) else { return }
        blocks[i].size = size
    }
}
