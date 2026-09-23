import Foundation

/// Browsing order for the full-window viewer: steps through the visible assets and wraps at the ends.
public enum ViewerNav {
    public static func step<ID: Equatable>(_ ids: [ID], from current: ID?, by delta: Int) -> ID? {
        guard !ids.isEmpty else { return nil }
        guard let current, let i = ids.firstIndex(of: current) else { return delta >= 0 ? ids.first : ids.last }
        let n = ids.count
        return ids[(((i + delta) % n) + n) % n]
    }

    /// "3 of 28" style position, or nil when the asset is not in the visible list.
    public static func position<ID: Equatable>(_ ids: [ID], of current: ID) -> (index: Int, count: Int)? {
        ids.firstIndex(of: current).map { ($0 + 1, ids.count) }
    }
}
