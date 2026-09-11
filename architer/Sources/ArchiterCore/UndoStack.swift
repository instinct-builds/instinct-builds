import Foundation

/// Value-type undo/redo for character edits. The app snapshots the character
/// before each edit; undo/redo walk the snapshots. Bounded history.
public struct UndoStack<State: Equatable & Sendable>: Sendable {
    public private(set) var current: State
    private var past: [State] = []
    private var future: [State] = []
    public let limit: Int

    public init(_ initial: State, limit: Int = 100) {
        self.current = initial
        self.limit = max(1, limit)
    }

    public var canUndo: Bool { !past.isEmpty }
    public var canRedo: Bool { !future.isEmpty }
    public var depth: Int { past.count }

    /// Records a new state after an edit. Clears the redo stack.
    public mutating func push(_ newState: State) {
        guard newState != current else { return }
        past.append(current)
        if past.count > limit { past.removeFirst(past.count - limit) }
        current = newState
        future.removeAll()
    }

    /// Steps back one state. Returns true when a state was restored.
    @discardableResult
    public mutating func undo() -> Bool {
        guard let prev = past.popLast() else { return false }
        future.append(current)
        current = prev
        return true
    }

    /// Steps forward one state (only right after undos).
    @discardableResult
    public mutating func redo() -> Bool {
        guard let next = future.popLast() else { return false }
        past.append(current)
        current = next
        return true
    }

    public mutating func clear() {
        past.removeAll()
        future.removeAll()
    }
}
