import Foundation

// MARK: - Usage rights and credits (1.25)
// Where a file came from, what it may be used for, who to credit and when the license ends.
// Stored in the catalog and written to the XMP sidecar next to the file.

public enum RightsLicense: String, Codable, CaseIterable, Identifiable, Sendable {
    case own = "Own work", licensed = "Licensed", client = "Client-supplied", editorial = "Editorial-only"
    public var id: String { rawValue }
    public var symbol: String {
        switch self {
        case .own: return "person.crop.square"
        case .licensed: return "checkmark.seal"
        case .client: return "building.2"
        case .editorial: return "newspaper"
        }
    }
    /// Loose match for values read from files.
    public static func named(_ raw: String) -> RightsLicense? {
        let s = raw.trimmingCharacters(in: .whitespaces).lowercased()
        return allCases.first { $0.rawValue.lowercased() == s || String(describing: $0) == s }
    }
}

public struct UsageRights: Codable, Equatable, Hashable, Sendable {
    public var license: RightsLicense
    public var source: String
    public var credit: String
    public var uses: String
    /// Last day the license covers, yyyy-MM-dd. nil means no end date.
    public var expires: String?
    /// Day the license was last renewed, yyyy-MM-dd (1.26).
    public var renewed: String?

    public init(license: RightsLicense = .own, source: String = "", credit: String = "", uses: String = "", expires: String? = nil, renewed: String? = nil) {
        self.license = license; self.source = source; self.credit = credit; self.uses = uses
        self.expires = expires.flatMap(UsageRights.normalizeDate)
        self.renewed = renewed.flatMap(UsageRights.normalizeDate)
    }

    enum CodingKeys: String, CodingKey { case license, source, credit, uses, expires, renewed }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        license = (try? c.decodeIfPresent(RightsLicense.self, forKey: .license)) ?? .own
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? ""
        credit = try c.decodeIfPresent(String.self, forKey: .credit) ?? ""
        uses = try c.decodeIfPresent(String.self, forKey: .uses) ?? ""
        expires = (try c.decodeIfPresent(String.self, forKey: .expires)).flatMap(UsageRights.normalizeDate)
        renewed = (try? c.decodeIfPresent(String.self, forKey: .renewed))?.flatMap(UsageRights.normalizeDate)
    }

    static let dayFormat: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    /// "2026-9-4", "2026-09-04T00:00:00Z" → "2026-09-04"; nil when it isn't a date.
    public static func normalizeDate(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard s.count >= 8 else { return nil }
        let head = String(s.prefix(10)).split(separator: "-")
        guard head.count == 3, let y = Int(head[0]), let m = Int(head[1]), let d = Int(head[2].prefix(2)),
              (1...12).contains(m), (1...31).contains(d), y > 1900 else { return nil }
        let out = String(format: "%04d-%02d-%02d", y, m, d)
        return dayFormat.date(from: out) == nil ? nil : out
    }

    /// Midnight of a yyyy-MM-dd day in the user's time zone, for date pickers.
    public static func localDate(_ day: String) -> Date? {
        let h = day.split(separator: "-")
        guard h.count == 3, let y = Int(h[0]), let m = Int(h[1]), let d = Int(h[2]) else { return nil }
        return Calendar(identifier: .gregorian).date(from: DateComponents(year: y, month: m, day: d))
    }

    public static func day(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = .current
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 2000, c.month ?? 1, c.day ?? 1)
    }

    /// Today as yyyy-MM-dd in the user's time zone. ASSSETS_TODAY overrides it for demos.
    public static func today() -> String {
        if let t = ProcessInfo.processInfo.environment["ASSSETS_TODAY"].flatMap(normalizeDate) { return t }
        return day(Date())
    }

    /// Whole days from `from` to `to` (both yyyy-MM-dd).
    public static func days(from: String, to: String) -> Int? {
        guard let a = dayFormat.date(from: from), let b = dayFormat.date(from: to) else { return nil }
        return Int((b.timeIntervalSince(a) / 86_400).rounded())
    }

    public var isEmpty: Bool { license == .own && source.isEmpty && credit.isEmpty && uses.isEmpty && expires == nil && renewed == nil }
}

public enum RightsStatus: Equatable, Sendable {
    case missing
    case ok
    /// Ends within the warning window; days left (0 = today is the last day).
    case expiring(Int)
    case expired(Int)
    case editorial

    /// Needs a warning before it goes into client work.
    public var isProblem: Bool {
        switch self { case .expired, .editorial: return true; default: return false }
    }

    public var label: String {
        switch self {
        case .missing: return "No rights info"
        case .ok: return "Rights OK"
        case .expiring(let d): return d == 0 ? "Rights end today" : "Rights end in \(d) day\(d == 1 ? "" : "s")"
        case .expired(let d): return d <= 1 ? "Rights expired" : "Rights expired \(d) days ago"
        case .editorial: return "Editorial only"
        }
    }

    public var shortLabel: String {
        switch self {
        case .missing: return "No rights"
        case .ok: return "OK"
        case .expiring(let d): return "\(d)d left"
        case .expired: return "Expired"
        case .editorial: return "Editorial"
        }
    }
}

public enum RightsFilter: String, Codable, CaseIterable, Sendable {
    case expiringSoon, expired, missing
    public var summary: String {
        switch self {
        case .expiringSoon: return "rights ending within \(StudioAsset.rightsWarningDays) days"
        case .expired: return "rights expired"
        case .missing: return "no rights info"
        }
    }
}

extension StudioAsset {
    public static let rightsWarningDays = 30

    /// Content that ships inside ASSSETS (starter files and generated assets) is not flagged as missing; user imports are.
    public func rightsStatus(asOf today: String = UsageRights.today()) -> RightsStatus {
        guard let r = rights, !r.isEmpty else { return isStarter || sourceKey?.hasPrefix("generated:") == true ? .ok : .missing }
        if let e = r.expires, let d = UsageRights.days(from: today, to: e) {
            if d < 0 { return .expired(-d) }
            if r.license == .editorial { return .editorial }
            if d <= Self.rightsWarningDays { return .expiring(d) }
        }
        return r.license == .editorial ? .editorial : .ok
    }

    public func matches(_ f: RightsFilter, asOf today: String = UsageRights.today()) -> Bool {
        switch (f, rightsStatus(asOf: today)) {
        case (.expiringSoon, .expiring), (.expired, .expired), (.missing, .missing): return true
        default: return false
        }
    }
}

public struct RightsIssue: Equatable, Sendable {
    public var asset: UUID
    public var title: String
    public var status: RightsStatus
}

public struct CreditLine: Codable, Equatable, Sendable {
    public var credit: String
    public var license: String
    public var titles: [String]
    public init(credit: String, license: String, titles: [String]) { self.credit = credit; self.license = license; self.titles = titles }
}

extension StudioCatalog {
    public static let rightsSmartCollections: [(String, SmartRules, String)] = [
        ("Rights Expiring", SmartRules(rights: .expiringSoon), "clock.badge.exclamationmark"),
        ("Rights Expired", SmartRules(rights: .expired), "exclamationmark.octagon"),
        ("No Rights Info", SmartRules(rights: .missing), "questionmark.square.dashed"),
    ]

    @discardableResult
    public mutating func setRights(_ rights: UsageRights?, for ids: Set<UUID>) -> Int {
        var n = 0
        for i in assets.indices where ids.contains(assets[i].id) {
            let new = (rights?.isEmpty ?? true) ? nil : rights
            if assets[i].rights != new { assets[i].rights = new; n += 1 }
        }
        return n
    }

    /// Assets among `ids` that are expired or editorial-only, in the given order.
    public func rightsIssues(_ ids: [UUID], asOf today: String = UsageRights.today()) -> [RightsIssue] {
        var seen = Set<UUID>(), out: [RightsIssue] = []
        let byID = Dictionary(assets.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for id in ids where seen.insert(id).inserted {
            guard let a = byID[id] else { continue }
            let s = a.rightsStatus(asOf: today)
            if s.isProblem { out.append(RightsIssue(asset: id, title: a.title, status: s)) }
        }
        return out
    }

    /// Board cards whose asset is expired or editorial-only, keyed by card id.
    public func rightsProblems(on board: UUID, asOf today: String = UsageRights.today()) -> [UUID: RightsStatus] {
        guard let b = self.board(board) else { return [:] }
        let byID = Dictionary(assets.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [UUID: RightsStatus] = [:]
        for item in b.items {
            guard let aid = item.assetID, let a = byID[aid] else { continue }
            let s = a.rightsStatus(asOf: today)
            if s.isProblem { out[item.id] = s }
        }
        return out
    }

    /// One line per distinct credit, in first-use order, listing what it covers. Assets without a credit are left out.
    public func credits(for ids: [UUID]) -> [CreditLine] {
        let byID = Dictionary(assets.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [CreditLine] = [], seen = Set<UUID>()
        for id in ids where seen.insert(id).inserted {
            guard let a = byID[id], let r = a.rights else { continue }
            let credit = r.credit.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !credit.isEmpty else { continue }
            if let i = out.firstIndex(where: { $0.credit == credit && $0.license == r.license.rawValue }) {
                if !out[i].titles.contains(a.title) { out[i].titles.append(a.title) }
            } else {
                out.append(CreditLine(credit: credit, license: r.license.rawValue, titles: [a.title]))
            }
        }
        return out
    }

    /// Adds the three rights smart collections once, for new and upgraded libraries alike.
    @discardableResult
    public mutating func seedRightsCollections() -> Int {
        guard !rightsSeeded else { return 0 }
        rightsSeeded = true
        var n = 0
        for (name, rules, symbol) in Self.rightsSmartCollections where !smartCollections.contains(where: { $0.name == name }) {
            smartCollections.append(StudioSmartCollection(name: name, rules: rules, symbol: symbol)); n += 1
        }
        return n
    }
}
