import Foundation

/// A catalog receipt, not a backup. The old file's bytes are not retained.
public struct SourceRefreshRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let assetID: UUID
    public let path: String
    public let refreshedAt: Date
    public let before: SourceFingerprint
    public let after: SourceFingerprint
    public let beforeResolution: String
    public let afterResolution: String
    public let beforePalette: [String]
    public let afterPalette: [String]

    public init(id: UUID = UUID(), assetID: UUID, path: String, refreshedAt: Date,
                before: SourceFingerprint, after: SourceFingerprint,
                beforeResolution: String, afterResolution: String,
                beforePalette: [String], afterPalette: [String]) {
        self.id = id; self.assetID = assetID; self.path = path; self.refreshedAt = refreshedAt
        self.before = before; self.after = after
        self.beforeResolution = beforeResolution; self.afterResolution = afterResolution
        self.beforePalette = beforePalette; self.afterPalette = afterPalette
    }
}

extension StudioCatalog {
    /// The accepted refresh and its receipt are a single catalog mutation.
    @discardableResult
    public mutating func acceptChangedSource(_ after: SourceFingerprint, for id: UUID, path: String,
                                             palette: [String], resolution: String, at date: Date) -> Bool {
        guard let current = assets.first(where: { $0.id == id && $0.importedPath == path }),
              let before = current.sourceFingerprint, before.sha256 != after.sha256 else { return false }
        guard acceptChangedSource(after, for: id, path: path, palette: palette, resolution: resolution) else { return false }
        sourceRefreshHistory.append(SourceRefreshRecord(assetID: id, path: path, refreshedAt: date,
            before: before, after: after, beforeResolution: current.resolution,
            afterResolution: resolution, beforePalette: current.palette, afterPalette: palette))
        return true
    }

    public func sourceHistory(for id: UUID) -> [SourceRefreshRecord] {
        sourceRefreshHistory.filter { $0.assetID == id }.reversed()
    }

    /// Receipts stay complete, but only the newest five are eligible for on-disk miniatures.
    public func sourceHistoryPreviewIDs(for id: UUID) -> Set<UUID> {
        Set(sourceHistory(for: id).prefix(5).map(\.id))
    }

    /// Read-only catalog search: filename fragment and optional inclusive acceptance dates.
    public func matchingSourceReceipts(filename query: String, from start: Date? = nil, through end: Date? = nil) -> [SourceRefreshRecord] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return sourceRefreshHistory.reversed().filter { record in
            let name = URL(fileURLWithPath: record.path).lastPathComponent
            if !term.isEmpty && !name.localizedCaseInsensitiveContains(term) { return false }
            if let start, record.refreshedAt < start { return false }
            if let end, record.refreshedAt > end { return false }
            return true
        }
    }
}

/// Read-only navigation across one asset's accepted receipts, newest first.
public struct SourceReceiptTimeline: Sendable {
    public let receipts: [SourceRefreshRecord]
    public let selected: Int

    public init(catalog: StudioCatalog, assetID: UUID, selectedID: UUID) {
        receipts = catalog.sourceHistory(for: assetID)
        selected = receipts.firstIndex(where: { $0.id == selectedID }) ?? 0
    }

    public var current: SourceRefreshRecord? { receipts.indices.contains(selected) ? receipts[selected] : nil }
    public var older: SourceRefreshRecord? { receipts.indices.contains(selected + 1) ? receipts[selected + 1] : nil }
    public var newer: SourceRefreshRecord? { selected > 0 && receipts.indices.contains(selected - 1) ? receipts[selected - 1] : nil }
    public var position: Int { receipts.isEmpty ? 0 : selected + 1 }
}

/// CSV only contains receipt facts. There are no source or preview bytes in this export.
public enum SourceReceiptCSV {
    public static let columns = ["Accepted UTC", "Asset title", "Source filename", "Before bytes", "After bytes", "Before SHA-256", "After SHA-256"]

    public static func render(_ receipts: [SourceRefreshRecord], titles: [UUID: String]) -> String {
        let clock = ISO8601DateFormatter()
        clock.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        clock.timeZone = TimeZone(secondsFromGMT: 0)!
        func quoted(_ raw: String) -> String {
            // CSV may be opened in a spreadsheet. Treat titles and filenames as text, never formulas.
            let leading = raw.drop(while: { $0.isWhitespace }).first
            let value = leading.map { "=+-@".contains($0) } == true ? "'" + raw : raw
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        var lines = [columns.map(quoted).joined(separator: ",")]
        for receipt in receipts {
            let fields = [clock.string(from: receipt.refreshedAt), titles[receipt.assetID] ?? "Removed asset",
                URL(fileURLWithPath: receipt.path).lastPathComponent,
                String(receipt.before.size), String(receipt.after.size), receipt.before.sha256, receipt.after.sha256]
            lines.append(fields.map(quoted).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }
}
