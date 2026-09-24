import Foundation

// MARK: - License documents and rights presets (1.27)
// The paperwork behind a license (order PDF, receipt, email export) lives in the library next to the catalog,
// attached to the assets it covers. Presets save a rights setup, license files included, to apply in one go.

public struct LicenseDoc: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    /// What the user sees, usually the original file name.
    public var name: String
    /// File name inside the library's Licenses folder.
    public var stored: String
    /// Day it was added, yyyy-MM-dd.
    public var added: String
    public var bytes: Int

    public init(id: UUID = UUID(), name: String, stored: String? = nil, added: String = UsageRights.today(), bytes: Int = 0) {
        self.id = id; self.name = name
        self.stored = stored ?? LicenseDoc.storedName(for: name, id: id)
        self.added = added; self.bytes = bytes
    }

    public enum Kind: String, Sendable { case pdf = "PDF", image = "Image", email = "Email", text = "Text", document = "Document" }

    public var ext: String { (name as NSString).pathExtension.lowercased() }

    public var kind: Kind {
        switch ext {
        case "pdf": return .pdf
        case "png", "jpg", "jpeg", "heic", "tif", "tiff", "gif", "webp": return .image
        case "eml", "emlx", "msg": return .email
        case "txt", "md", "rtf", "html", "htm": return .text
        default: return .document
        }
    }

    public var symbol: String {
        switch kind {
        case .pdf: return "doc.richtext"
        case .image: return "photo"
        case .email: return "envelope"
        case .text: return "doc.plaintext"
        case .document: return "doc"
        }
    }

    /// "248 KB", "1.2 MB".
    public var sizeLabel: String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }

    /// A safe, unique file name: the id's first block plus the original name without path characters.
    public static func storedName(for name: String, id: UUID) -> String {
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        var clean = name.components(separatedBy: bad).joined(separator: "-").trimmingCharacters(in: .whitespaces)
        while clean.hasPrefix(".") || clean.hasPrefix("-") || clean.hasPrefix(" ") { clean.removeFirst() }
        if clean.isEmpty { clean = "license" }
        if clean.count > 80 {
            let ext = (clean as NSString).pathExtension
            let base = String((clean as NSString).deletingPathExtension.prefix(70))
            clean = ext.isEmpty ? base : base + "." + ext
        }
        return String(id.uuidString.prefix(8)).lowercased() + "-" + clean
    }
}

/// A saved rights setup. `termYears` sets the end date that many years from the day it is applied;
/// otherwise `rights.expires` is used as is. The credit may use {title} and {n}.
public struct RightsPreset: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var rights: UsageRights
    public var termYears: Int?
    public var docs: [UUID]

    public init(id: UUID = UUID(), name: String, rights: UsageRights, termYears: Int? = nil, docs: [UUID] = []) {
        self.id = id; self.name = name; self.rights = rights; self.termYears = termYears.flatMap { $0 > 0 ? $0 : nil }; self.docs = docs
    }

    /// "Licensed · Northlight Images · 1-year term · 1 file"
    public func summary(docCount: Int? = nil) -> String {
        var parts = [rights.license.rawValue]
        if !rights.source.isEmpty { parts.append(rights.source) }
        if let t = termYears { parts.append("\(t)-year term") } else if let e = rights.expires { parts.append("ends \(e)") }
        let n = docCount ?? docs.count
        if n > 0 { parts.append("\(n) file\(n == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }
}

extension StudioCatalog {
    public func licenseDoc(_ id: UUID) -> LicenseDoc? { licenseDocs.first { $0.id == id } }

    /// Documents attached to one asset, in attach order.
    public func licenseDocs(for asset: UUID) -> [LicenseDoc] {
        guard let a = assets.first(where: { $0.id == asset }) else { return [] }
        return a.licenseDocs.compactMap(licenseDoc)
    }

    /// Distinct documents across several assets, in first-use order.
    public func licenseDocs(forAll ids: [UUID]) -> [LicenseDoc] {
        let byID = Dictionary(assets.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var seen = Set<UUID>(), out: [LicenseDoc] = []
        for id in ids {
            for d in byID[id]?.licenseDocs ?? [] where seen.insert(d).inserted {
                if let doc = licenseDoc(d) { out.append(doc) }
            }
        }
        return out
    }

    /// How many of `ids` each document is attached to, for the batch inspector.
    public func licenseDocCoverage(_ ids: [UUID]) -> [(doc: LicenseDoc, count: Int)] {
        let set = Set(ids)
        let picked = assets.filter { set.contains($0.id) }
        return licenseDocs(forAll: ids).map { d in (d, picked.filter { $0.licenseDocs.contains(d.id) }.count) }
    }

    /// Stores a new document record and attaches it. Returns how many assets gained it.
    @discardableResult
    public mutating func addLicenseDoc(_ doc: LicenseDoc, to ids: [UUID]) -> Int {
        if !licenseDocs.contains(where: { $0.id == doc.id }) { licenseDocs.append(doc) }
        return attachLicenseDoc(doc.id, to: ids)
    }

    @discardableResult
    public mutating func attachLicenseDoc(_ docID: UUID, to ids: [UUID]) -> Int {
        guard licenseDoc(docID) != nil else { return 0 }
        let set = Set(ids)
        var n = 0
        for i in assets.indices where set.contains(assets[i].id) && !assets[i].licenseDocs.contains(docID) {
            assets[i].licenseDocs.append(docID); n += 1
        }
        return n
    }

    @discardableResult
    public mutating func detachLicenseDoc(_ docID: UUID, from ids: [UUID]) -> Int {
        let set = Set(ids)
        var n = 0
        for i in assets.indices where set.contains(assets[i].id) && assets[i].licenseDocs.contains(docID) {
            assets[i].licenseDocs.removeAll { $0 == docID }; n += 1
        }
        return n
    }

    public mutating func renameLicenseDoc(_ docID: UUID, to name: String) {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let i = licenseDocs.firstIndex(where: { $0.id == docID }) else { return }
        licenseDocs[i].name = t
    }

    /// Documents no asset or preset uses any more; the app deletes their files.
    public var unusedLicenseDocs: [LicenseDoc] {
        var used = Set(assets.flatMap(\.licenseDocs))
        used.formUnion(rightsPresets.flatMap(\.docs))
        return licenseDocs.filter { !used.contains($0.id) }
    }

    /// Drops unused document records and returns them so their files can go too.
    @discardableResult
    public mutating func pruneLicenseDocs() -> [LicenseDoc] {
        let gone = unusedLicenseDocs
        let ids = Set(gone.map(\.id))
        licenseDocs.removeAll { ids.contains($0.id) }
        return gone
    }

    // MARK: Presets

    public func rightsPreset(_ id: UUID) -> RightsPreset? { rightsPresets.first { $0.id == id } }

    /// Saves a preset; one with the same name (case-insensitive) is replaced and keeps its id.
    @discardableResult
    public mutating func saveRightsPreset(name: String, rights: UsageRights, termYears: Int? = nil, docs: [UUID] = []) -> UUID? {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        var r = rights; r.renewed = nil
        let docs = docs.filter { licenseDoc($0) != nil }
        if let i = rightsPresets.firstIndex(where: { $0.name.caseInsensitiveCompare(t) == .orderedSame }) {
            rightsPresets[i] = RightsPreset(id: rightsPresets[i].id, name: t, rights: r, termYears: termYears, docs: docs)
            return rightsPresets[i].id
        }
        let p = RightsPreset(name: t, rights: r, termYears: termYears, docs: docs)
        rightsPresets.append(p)
        return p.id
    }

    /// A preset built from one asset's rights and files, for "Save as Preset".
    public func presetDraft(from asset: UUID) -> RightsPreset? {
        guard let a = assets.first(where: { $0.id == asset }), let r = a.rights, !r.isEmpty else { return nil }
        let name = r.source.isEmpty ? r.license.rawValue : r.source
        return RightsPreset(name: name, rights: r, docs: a.licenseDocs)
    }

    public mutating func deleteRightsPreset(_ id: UUID) { rightsPresets.removeAll { $0.id == id } }

    public mutating func renameRightsPreset(_ id: UUID, to name: String) {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let i = rightsPresets.firstIndex(where: { $0.id == id }) else { return }
        rightsPresets[i].name = t
    }

    /// Sets every field from the preset (credit patterns filled per asset, end date from the term) and attaches its files.
    /// A renewal date already on an asset is kept. Returns how many assets changed.
    @discardableResult
    public mutating func applyRightsPreset(_ id: UUID, to ids: [UUID], today: String = UsageRights.today()) -> Int {
        guard let p = rightsPreset(id) else { return 0 }
        let expires = p.termYears.flatMap { UsageRights.adding(years: $0, to: today) } ?? p.rights.expires
        let docs = p.docs.filter { licenseDoc($0) != nil }
        var n = 0, pos = 0, seen = Set<UUID>()
        for aid in ids where seen.insert(aid).inserted {
            guard let i = assets.firstIndex(where: { $0.id == aid }) else { continue }
            pos += 1
            let before = assets[i]
            var r = p.rights
            r.credit = RightsEdit.fill(p.rights.credit, title: assets[i].title, n: pos).trimmingCharacters(in: .whitespacesAndNewlines)
            r.expires = expires
            r.renewed = assets[i].rights?.renewed
            assets[i].rights = r.isEmpty ? nil : r
            for d in docs where !assets[i].licenseDocs.contains(d) { assets[i].licenseDocs.append(d) }
            if assets[i] != before { n += 1 }
        }
        return n
    }

    // MARK: Export guard

    /// Splits `ids` into assets cleared for client use and those that are expired or editorial-only.
    public func rightsCheck(_ ids: [UUID], asOf today: String = UsageRights.today()) -> (cleared: [UUID], issues: [RightsIssue]) {
        let issues = rightsIssues(ids, asOf: today)
        let bad = Set(issues.map(\.asset))
        let known = Set(assets.map(\.id))
        var seen = Set<UUID>()
        let cleared = ids.filter { id in !bad.contains(id) && known.contains(id) && seen.insert(id).inserted }
        return (cleared, issues)
    }
}
