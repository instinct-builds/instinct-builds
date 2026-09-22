import Foundation

public enum CharacterStoreError: Error {
    case writeFailed(String)
    case readFailed(String)
    case corruptData
}

/// JSON persistence in the app's Application Support folder (or anywhere the
/// caller points it, which is how tests exercise it on any platform).
public struct CharacterStore: Sendable {
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    public static func defaultStore(fileManager: FileManager = .default) -> CharacterStore {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return CharacterStore(directory: base.appendingPathComponent("ARCHITER", isDirectory: true))
    }

    private func fileURL(for character: Character) -> URL {
        directory.appendingPathComponent("\(character.id.uuidString).json")
    }

    public func save(_ character: Character) throws {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            enc.dateEncodingStrategy = .iso8601
            let data = try enc.encode(character)
            try data.write(to: fileURL(for: character), options: .atomic)
        } catch {
            throw CharacterStoreError.writeFailed(error.localizedDescription)
        }
    }

    public func load(id: UUID) throws -> Character {
        let url = directory.appendingPathComponent("\(id.uuidString).json")
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(Character.self, from: data)
        } catch let error as DecodingError {
            _ = error
            throw CharacterStoreError.corruptData
        } catch {
            throw CharacterStoreError.readFailed(error.localizedDescription)
        }
    }

    public func loadAll() throws -> [Character] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        var out: [Character] = []
        for f in files where f.pathExtension == "json" {
            if let data = try? Data(contentsOf: f),
               let c = try? JSONDecoder().decode(Character.self, from: data) {
                out.append(c)
            }
        }
        return out.sorted { $0.name < $1.name }
    }

    public func delete(_ character: Character) throws {
        try FileManager.default.removeItem(at: fileURL(for: character))
    }
}

/// JSON persistence for user-defined rulesets (the custom-ruleset library).
/// Stored as one rulesets.json next to the character files.
public struct RulesetStore: Sendable {
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    private var fileURL: URL { directory.appendingPathComponent("rulesets.json") }

    public func load() -> [Ruleset] {
        guard let data = try? Data(contentsOf: fileURL),
              let rulesets = try? JSONDecoder().decode([Ruleset].self, from: data) else {
            return []
        }
        return rulesets
    }

    public func saveAll(_ rulesets: [Ruleset]) throws {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(rulesets).write(to: fileURL, options: .atomic)
        } catch {
            throw CharacterStoreError.writeFailed(error.localizedDescription)
        }
    }

    public func delete(name: String) throws {
        try saveAll(load().filter { $0.name != name })
    }
}

extension Character {
    /// Captures the character's current custom abilities and skills as a
    /// reusable ruleset template under the given name.
    public func captureRuleset(named name: String) -> Ruleset {
        Ruleset(
            name: name,
            abilities: customAbilities.map(\.name),
            skills: customSkills.map { CustomSkillDef(name: $0.name, abilityName: $0.abilityName) }
        )
    }
}
