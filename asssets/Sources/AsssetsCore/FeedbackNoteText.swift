import Foundation

/// The exact note text persisted by a feedback import. Swift Character counts
/// match String.prefix, including composed Unicode characters.
public enum FeedbackNoteText {
    public static let limit = 4_000
    public static func trimmed(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    public static func saved(_ raw: String) -> String {
        String(trimmed(raw).prefix(limit))
    }
    public static func submittedCount(_ raw: String) -> Int { trimmed(raw).count }
}
