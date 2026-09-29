import Foundation

/// Table log condition filter (3.66.0): narrow the log to the entries
/// that name one condition - apply, removal and restore lines all carry
/// the condition's name in their text. Case-insensitive substring over
/// title and text, so a filter typed or picked as "frightened" finds
/// "Frightened" either way. Blank query shows everything; entry order
/// is the caller's to keep (the filter preserves it).
public enum TableLogConditionFilter {
    public static func filter(_ entries: [TableLogEntry], query rawQuery: String) -> [TableLogEntry] {
        let query = rawQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return entries }
        return entries.filter {
            $0.title.range(of: query, options: .caseInsensitive) != nil
                || $0.text.range(of: query, options: .caseInsensitive) != nil
        }
    }
}
