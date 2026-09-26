import Foundation

/// Stable, bounded slices for Health issue cards. Pagination never reorders the scan's rows.
public enum HealthRowWindow {
    public static let initial = 3
    public static let page = 40

    public static func visible(total: Int, expanded: Int) -> Int {
        min(max(0, total), max(initial, expanded))
    }

    public static func next(total: Int, expanded: Int) -> Int {
        let shown = visible(total: total, expanded: expanded)
        return min(max(0, total), shown > Int.max - page ? Int.max : shown + page)
    }
}
