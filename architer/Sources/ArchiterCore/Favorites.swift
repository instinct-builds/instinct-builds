import Foundation

/// Which compendium library a favorited entry belongs to.
public enum CompendiumKind: String, Codable, Sendable {
    case spell, weapon, armor
}

/// App-wide compendium favorites: the entries a player reaches for at the
/// table, kept in a stable order and persisted as one small JSON file.
public struct CompendiumFavorites: Codable, Equatable, Sendable {
    public private(set) var keys: [String]

    public init(keys: [String] = []) { self.keys = keys }

    public static func key(_ kind: CompendiumKind, _ name: String) -> String {
        "\(kind.rawValue):\(name.lowercased())"
    }

    public func contains(kind: CompendiumKind, name: String) -> Bool {
        keys.contains(Self.key(kind, name))
    }

    public mutating func toggle(kind: CompendiumKind, name: String) {
        let k = Self.key(kind, name)
        if let i = keys.firstIndex(of: k) {
            keys.remove(at: i)
        } else {
            keys.append(k)
        }
    }

    public func isEmpty() -> Bool { keys.isEmpty }
}

/// JSON persistence for compendium favorites, alongside the character files.
public struct FavoritesStore: Sendable {
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    private var fileURL: URL { directory.appendingPathComponent("compendium-favorites.json") }

    public func load() -> CompendiumFavorites {
        guard let data = try? Data(contentsOf: fileURL),
              let f = try? JSONDecoder().decode(CompendiumFavorites.self, from: data) else {
            return CompendiumFavorites()
        }
        return f
    }

    public func save(_ favorites: CompendiumFavorites) {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(favorites) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
