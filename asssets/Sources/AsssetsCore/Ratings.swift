import Foundation

// MARK: - Star ratings and color labels (1.11)

public enum ColorLabel: String, Codable, CaseIterable, Identifiable, Sendable {
    case red, orange, yellow, green, blue, purple
    public var id: String { rawValue }
    public var name: String { rawValue.capitalized }
    public var hex: String {
        switch self {
        case .red: "#FF5A5F"
        case .orange: "#FF9F43"
        case .yellow: "#FFD43B"
        case .green: "#51CF66"
        case .blue: "#4DABF7"
        case .purple: "#B197FC"
        }
    }
    /// Number-row shortcuts, as in most photo tools: 6 red, 7 yellow, 8 green, 9 blue.
    public static func forKey(_ digit: Int) -> ColorLabel? { [6: .red, 7: .yellow, 8: .green, 9: .blue][digit] }
    public var key: Int? { [ColorLabel.red: 6, .yellow: 7, .green: 8, .blue: 9][self] }
}

/// The grid's rating and label filter chips.
public struct RatingFilter: Equatable, Sendable {
    public var minRating = 0
    public var labels: Set<ColorLabel> = []
    public init(minRating: Int = 0, labels: Set<ColorLabel> = []) { self.minRating = minRating; self.labels = labels }
    public var isActive: Bool { minRating > 0 || !labels.isEmpty }
    public func matches(_ a: StudioAsset) -> Bool {
        a.rating >= minRating && (labels.isEmpty || (a.label.map(labels.contains) ?? false))
    }
    /// Label order follows ColorLabel so saved rules read the same way every time.
    public func apply(to rules: inout SmartRules) {
        rules.minRating = minRating
        rules.labels = ColorLabel.allCases.filter(labels.contains)
    }
}

extension StudioCatalog {
    /// Sets the stars (clamped 0-5). Returns how many assets changed.
    @discardableResult
    public mutating func setRating(_ ids: Set<UUID>, _ stars: Int) -> Int {
        let r = min(5, max(0, stars)); var n = 0
        for i in assets.indices where ids.contains(assets[i].id) && assets[i].rating != r { assets[i].rating = r; n += 1 }
        return n
    }

    /// Applies a label, or clears it when every target already has that label (so the same key toggles).
    /// Returns the label now on the targets.
    @discardableResult
    public mutating func toggleLabel(_ ids: Set<UUID>, _ label: ColorLabel?) -> ColorLabel? {
        let targets = assets.indices.filter { ids.contains(assets[$0].id) }
        guard !targets.isEmpty else { return nil }
        let new: ColorLabel? = label != nil && targets.allSatisfy({ assets[$0].label == label }) ? nil : label
        for i in targets { assets[i].label = new }
        return new
    }

    /// Placeholder swatches for a user file whose pixels haven't been read yet.
    public static let placeholderPalette = ["#20242C", "#586174", "#B8C0CF"]
}

extension StudioAsset {
    /// A user file still showing "Local file" and placeholder swatches: its pixels haven't been read.
    public var needsFileMetadata: Bool { !isStarter && importedPath != nil && resolution == "Local file" }
    public var stars: String { String(repeating: "★", count: rating) }
}
