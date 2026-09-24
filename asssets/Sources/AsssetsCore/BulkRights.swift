import Foundation

// MARK: - Bulk rights, renewals and the rights report (1.26)

/// One field across a selection: the same everywhere, or mixed.
public enum Shared<T: Equatable & Sendable>: Equatable, Sendable {
    case same(T)
    case mixed
    public var value: T? { if case .same(let v) = self { return v }; return nil }
    public var isMixed: Bool { self == .mixed }
}

public struct RightsCommon: Equatable, Sendable {
    public var license: Shared<RightsLicense>
    public var source: Shared<String>
    public var credit: Shared<String>
    public var uses: Shared<String>
    public var expires: Shared<String?>
    public var count: Int
}

/// A bulk change. nil fields are left alone; `expires: .some(nil)` removes the end date.
/// `credit` may use {title} and {n} (1-based position in the selection).
public struct RightsEdit: Equatable, Sendable {
    public var license: RightsLicense?
    public var source: String?
    public var credit: String?
    public var uses: String?
    public var expires: String??
    public init(license: RightsLicense? = nil, source: String? = nil, credit: String? = nil, uses: String? = nil, expires: String?? = nil) {
        self.license = license; self.source = source; self.credit = credit; self.uses = uses; self.expires = expires
    }
    public var isEmpty: Bool { license == nil && source == nil && credit == nil && uses == nil && expires == nil }

    public static func fill(_ pattern: String, title: String, n: Int) -> String {
        pattern.replacingOccurrences(of: "{title}", with: title).replacingOccurrences(of: "{n}", with: String(n))
    }
}

extension UsageRights {
    /// yyyy-MM-dd plus whole years; Feb 29 lands on Feb 28 in other years.
    public static func adding(years: Int, to day: String) -> String? {
        let h = day.split(separator: "-").compactMap { Int($0) }
        guard h.count == 3 else { return nil }
        var y = h[0] + years, m = h[1], d = h[2]
        if m == 2 && d == 29 && !(y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)) { d = 28 }
        if m > 12 { y += 1; m -= 12 }
        return normalizeDate(String(format: "%04d-%02d-%02d", y, m, d))
    }
}

extension StudioCatalog {
    public func commonRights(_ ids: [UUID]) -> RightsCommon {
        let set = Set(ids)
        let rs = assets.filter { set.contains($0.id) }.map { $0.rights ?? UsageRights() }
        func shared<T: Equatable & Sendable>(_ f: (UsageRights) -> T) -> Shared<T> {
            guard let first = rs.first.map(f) else { return .mixed }
            return rs.allSatisfy { f($0) == first } ? .same(first) : .mixed
        }
        return RightsCommon(license: shared(\.license), source: shared(\.source), credit: shared(\.credit), uses: shared(\.uses),
                            expires: shared(\.expires), count: rs.count)
    }

    /// Applies the fields that are set to every asset in `ids`, in the given order. Returns how many changed.
    @discardableResult
    public mutating func applyRights(_ edit: RightsEdit, to ids: [UUID]) -> Int {
        guard !edit.isEmpty else { return 0 }
        var n = 0, pos = 0
        var seen = Set<UUID>()
        for id in ids where seen.insert(id).inserted {
            guard let i = assets.firstIndex(where: { $0.id == id }) else { continue }
            pos += 1
            var r = assets[i].rights ?? UsageRights()
            if let v = edit.license { r.license = v }
            if let v = edit.source { r.source = v.trimmingCharacters(in: .whitespacesAndNewlines) }
            if let v = edit.credit { r.credit = RightsEdit.fill(v, title: assets[i].title, n: pos).trimmingCharacters(in: .whitespacesAndNewlines) }
            if let v = edit.uses { r.uses = v.trimmingCharacters(in: .whitespacesAndNewlines) }
            if let v = edit.expires { r.expires = v.flatMap(UsageRights.normalizeDate) }
            let new: UsageRights? = r.isEmpty ? nil : r
            if assets[i].rights != new { assets[i].rights = new; n += 1 }
        }
        return n
    }

    /// Moves each end date a year on, counting from today when it has already passed. Assets without an end date are skipped.
    @discardableResult
    public mutating func extendRights(_ ids: Set<UUID>, years: Int = 1, today: String = UsageRights.today()) -> Int {
        var n = 0
        for i in assets.indices where ids.contains(assets[i].id) {
            guard var r = assets[i].rights, let e = r.expires else { continue }
            let base = e < today ? today : e
            guard let next = UsageRights.adding(years: years, to: base) else { continue }
            r.expires = next
            assets[i].rights = r; n += 1
        }
        return n
    }

    /// Records a renewal today and sets a fresh one-year term from today. Works on assets that had no end date too.
    @discardableResult
    public mutating func markRenewed(_ ids: Set<UUID>, years: Int = 1, today: String = UsageRights.today()) -> Int {
        var n = 0
        for i in assets.indices where ids.contains(assets[i].id) {
            var r = assets[i].rights ?? UsageRights(license: .licensed)
            r.renewed = today
            r.expires = UsageRights.adding(years: years, to: today)
            if assets[i].rights != r { assets[i].rights = r; n += 1 }
        }
        return n
    }

    /// Assets whose license ended on or after `since` and before `today`: what expired while the app was closed.
    public func expired(since: String, today: String = UsageRights.today()) -> [RightsIssue] {
        assets.compactMap { a in
            guard let e = a.rights?.expires, e >= since, e < today else { return nil }
            return RightsIssue(asset: a.id, title: a.title, status: a.rightsStatus(asOf: today))
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// How many assets need attention: (expiring soon, expired).
    public func rightsAlertCounts(today: String = UsageRights.today()) -> (expiring: Int, expired: Int) {
        var e = 0, x = 0
        for a in assets {
            switch a.rightsStatus(asOf: today) { case .expiring: e += 1; case .expired: x += 1; default: break }
        }
        return (e, x)
    }
}

// MARK: Report

public struct RightsReport: Equatable, Sendable {
    public struct Row: Equatable, Sendable {
        public var asset: UUID
        public var title: String
        public var file: String
        public var license: String
        public var credit: String
        public var source: String
        public var uses: String
        public var expires: String
        public var renewed: String
        public var status: String
        /// 0 expired, 1 editorial, 2 expiring, 3 missing, 4 OK. Lower sorts first.
        public var rank: Int
    }
    public var title: String
    public var date: String
    public var rows: [Row]

    public var counts: (problems: Int, expiring: Int, missing: Int, ok: Int) {
        (rows.filter { $0.rank <= 1 }.count, rows.filter { $0.rank == 2 }.count, rows.filter { $0.rank == 3 }.count, rows.filter { $0.rank == 4 }.count)
    }

    public static let columns = ["Title", "File", "Status", "License", "Credit", "Source", "Allowed uses", "Ends", "Renewed"]

    /// RFC 4180 CSV with a header row; fields with commas, quotes or line breaks are quoted.
    public var csv: String {
        func q(_ s: String) -> String {
            s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
        }
        var lines = [Self.columns.joined(separator: ",")]
        for r in rows { lines.append([r.title, r.file, r.status, r.license, r.credit, r.source, r.uses, r.expires, r.renewed].map(q).joined(separator: ",")) }
        return lines.joined(separator: "\r\n") + "\r\n"
    }
}

extension StudioCatalog {
    /// Every asset in `ids` with its rights, problems first (expired, editorial, ending soon, missing, OK), then by end date and title.
    public func rightsReport(_ ids: [UUID], title: String, today: String = UsageRights.today()) -> RightsReport {
        let byID = Dictionary(assets.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var seen = Set<UUID>()
        let rows: [RightsReport.Row] = ids.compactMap { id in
            guard seen.insert(id).inserted, let a = byID[id] else { return nil }
            let st = a.rightsStatus(asOf: today)
            let rank: Int = { switch st { case .expired: return 0; case .editorial: return 1; case .expiring: return 2; case .missing: return 3; case .ok: return 4 } }()
            let r = a.rights
            let bundled = r == nil && st == .ok
            return RightsReport.Row(asset: a.id, title: a.title, file: a.importedPath.map { ($0 as NSString).lastPathComponent } ?? (a.sourceKey.map { _ in "Bundled with ASSSETS" } ?? ""),
                                    license: r?.license.rawValue ?? (bundled ? "Bundled" : ""), credit: r?.credit ?? "", source: r?.source ?? "",
                                    uses: r?.uses ?? "", expires: r?.expires ?? "", renewed: r?.renewed ?? "", status: st.label, rank: rank)
        }
        let sorted = rows.enumerated().sorted { x, y in
            let a = x.element, b = y.element
            if a.rank != b.rank { return a.rank < b.rank }
            let ea = a.expires.isEmpty ? "9999" : a.expires, eb = b.expires.isEmpty ? "9999" : b.expires
            if ea != eb { return ea < eb }
            let t = a.title.localizedStandardCompare(b.title)
            return t == .orderedSame ? x.offset < y.offset : t == .orderedAscending
        }.map(\.element)
        return RightsReport(title: title, date: today, rows: sorted)
    }
}
