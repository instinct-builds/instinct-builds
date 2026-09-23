import Foundation

// MARK: - Keywords, titles, ratings and labels in files (1.13)
// Reads XMP (sidecar or embedded) and IPTC-IIM keywords from JPEG, PNG, TIFF and PSD; writes XMP sidecars.
// Originals are never modified: write-back only creates or updates "<name>.xmp" next to the file.

public struct FileMetadata: Equatable, Sendable {
    public var title: String?
    public var keywords: [String] = []
    /// 1-5 stars; -1 means rejected (Lightroom and Bridge convention); nil when absent.
    public var rating: Int?
    public var label: ColorLabel?
    public init(title: String? = nil, keywords: [String] = [], rating: Int? = nil, label: ColorLabel? = nil) {
        self.title = title; self.keywords = keywords; self.rating = rating; self.label = label
    }
    public var isEmpty: Bool { (title ?? "").isEmpty && keywords.isEmpty && rating == nil && label == nil }

    /// Fills gaps from another source (sidecar first, then embedded XMP, then IPTC).
    public func filling(from other: FileMetadata) -> FileMetadata {
        var m = self
        if (m.title ?? "").isEmpty { m.title = other.title }
        for k in other.keywords where !m.keywords.contains(where: { $0.caseInsensitiveCompare(k) == .orderedSame }) { m.keywords.append(k) }
        if m.rating == nil { m.rating = other.rating }
        if m.label == nil { m.label = other.label }
        return m
    }
}

public enum XmpMetadata {
    // MARK: Reading

    /// Label names used by Lightroom (color names) and Bridge's default label set.
    public static func label(named raw: String) -> ColorLabel? {
        switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
        case "red", "select": return .red
        case "orange": return .orange
        case "yellow", "second": return .yellow
        case "green", "approved": return .green
        case "blue", "review": return .blue
        case "purple", "to do": return .purple
        default: return nil
        }
    }

    /// Parses one XMP packet (the text between <x:xmpmeta> and </x:xmpmeta>, or a whole sidecar).
    public static func parse(_ xmp: String) -> FileMetadata {
        var m = FileMetadata()
        m.keywords = listItems(in: element("dc:subject", in: xmp) ?? "").filter { !$0.isEmpty }
        m.title = listItems(in: element("dc:title", in: xmp) ?? "").first.flatMap { $0.isEmpty ? nil : $0 }
        if let r = value("xmp:Rating", in: xmp).flatMap({ Double($0) }) {
            let n = Int(r.rounded())
            m.rating = n < 0 ? -1 : (n == 0 ? nil : min(5, n))
        }
        m.label = value("xmp:Label", in: xmp).flatMap(label(named:))
        return m
    }

    /// Value of a simple property written either as an attribute (prop="v") or an element (<prop>v</prop>).
    static func value(_ prop: String, in s: String) -> String? {
        if let r = s.range(of: prop + "=\"") ?? s.range(of: prop + "='") {
            let quote = s[s.index(before: r.upperBound)]
            if let end = s[r.upperBound...].firstIndex(of: quote) { return unescape(String(s[r.upperBound..<end])) }
        }
        if let inner = element(prop, in: s) {
            let t = inner.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.hasPrefix("<") ? nil : unescape(t)
        }
        return nil
    }

    /// Inner text of the first <name ...>...</name>.
    static func element(_ name: String, in s: String) -> String? {
        var search = s.startIndex
        while let open = s.range(of: "<" + name, range: search..<s.endIndex) {
            guard let close = s[open.upperBound...].firstIndex(of: ">") else { return nil }
            let next = s[open.upperBound]
            // Guard against prefixes such as <dc:subjectX.
            guard next == ">" || next == " " || next == "/" || next == "\n" || next == "\t" || next == "\r" else { search = open.upperBound; continue }
            if s[s.index(before: close)] == "/" { return "" }
            guard let end = s.range(of: "</" + name + ">", range: close..<s.endIndex) else { return nil }
            return String(s[s.index(after: close)..<end.lowerBound])
        }
        return nil
    }

    /// Text of each <rdf:li> in a Bag, Seq or Alt.
    static func listItems(in s: String) -> [String] {
        var out: [String] = []
        var search = s.startIndex
        while let open = s.range(of: "<rdf:li", range: search..<s.endIndex),
              let close = s[open.upperBound...].firstIndex(of: ">") {
            if s[s.index(before: close)] == "/" { search = s.index(after: close); continue }
            guard let end = s.range(of: "</rdf:li>", range: close..<s.endIndex) else { break }
            out.append(unescape(String(s[s.index(after: close)..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)))
            search = end.upperBound
        }
        return out
    }

    /// Finds an XMP packet anywhere in a file's bytes. JPEG APP1, PNG iTXt (uncompressed), TIFF tag 700
    /// and PSD resource 1060 all store it as plain UTF-8, so a byte search covers them.
    public static func embeddedPacket(in data: Data) -> String? {
        guard let start = data.range(of: Data("<x:xmpmeta".utf8)),
              let end = data.range(of: Data("</x:xmpmeta>".utf8), in: start.upperBound..<data.endIndex) else { return nil }
        return String(data: data[start.lowerBound..<end.upperBound], encoding: .utf8)
    }

    /// IPTC-IIM keywords (2:25) and object name (2:05) from the first IPTC block (JPEG APP13 or PSD resource 0x0404).
    public static func iptc(in data: Data) -> FileMetadata {
        var m = FileMetadata()
        guard let marker = data.range(of: Data("8BIM".utf8) + Data([0x04, 0x04])) else { return m }
        let b = [UInt8](data[marker.upperBound..<min(data.endIndex, marker.upperBound + 70_000)])
        guard !b.isEmpty else { return m }
        var i = Int(b[0]) + 1                 // Pascal name
        if i % 2 == 1 { i += 1 }              // padded to even
        guard i + 4 <= b.count else { return m }
        let size = Int(b[i]) << 24 | Int(b[i + 1]) << 16 | Int(b[i + 2]) << 8 | Int(b[i + 3])
        i += 4
        let end = min(b.count, i + size)
        while i + 5 <= end, b[i] == 0x1C {
            let record = b[i + 1], tag = b[i + 2], len = Int(b[i + 3]) << 8 | Int(b[i + 4])
            let v0 = i + 5, v1 = v0 + len
            guard v1 <= end else { break }
            if record == 2, let text = String(bytes: b[v0..<v1], encoding: .utf8) ?? String(bytes: b[v0..<v1], encoding: .isoLatin1) {
                if tag == 25, !text.isEmpty { m.keywords.append(text) }
                if tag == 5, !text.isEmpty { m.title = text }
            }
            i = v1
        }
        return m
    }

    public static func sidecarPath(for path: String) -> String {
        (path as NSString).deletingPathExtension + ".xmp"
    }

    /// Everything a file says about itself: sidecar first, then embedded XMP, then IPTC.
    /// Reads at most the first 16 MB of the file.
    public static func read(path: String) -> FileMetadata {
        var m = FileMetadata()
        if let side = try? String(contentsOfFile: sidecarPath(for: path), encoding: .utf8) { m = parse(side) }
        guard let h = FileHandle(forReadingAtPath: path) else { return m }
        defer { try? h.close() }
        let data = (try? h.read(upToCount: 16 << 20)) ?? Data()
        if let packet = embeddedPacket(in: data) { m = m.filling(from: parse(packet)) }
        return m.filling(from: iptc(in: data))
    }

    // MARK: Writing

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
    static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&apos;", with: "'").replacingOccurrences(of: "&amp;", with: "&")
    }

    static func fields(_ m: FileMetadata) -> String {
        var out = ""
        if let t = m.title, !t.isEmpty {
            out += "\n   <dc:title><rdf:Alt><rdf:li xml:lang=\"x-default\">\(escape(t))</rdf:li></rdf:Alt></dc:title>"
        }
        if !m.keywords.isEmpty {
            out += "\n   <dc:subject><rdf:Bag>" + m.keywords.map { "<rdf:li>\(escape($0))</rdf:li>" }.joined() + "</rdf:Bag></dc:subject>"
        }
        if let r = m.rating { out += "\n   <xmp:Rating>\(r)</xmp:Rating>" }
        if let l = m.label { out += "\n   <xmp:Label>\(l.name)</xmp:Label>" }
        return out
    }

    /// A fresh sidecar.
    public static func packet(_ m: FileMetadata) -> String {
        """
        <?xpacket begin="\u{FEFF}" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="ASSSETS">
         <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description rdf:about="" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:xmp="http://ns.adobe.com/xap/1.0/">\(fields(m))
          </rdf:Description>
         </rdf:RDF>
        </x:xmpmeta>
        <?xpacket end="w"?>
        """
    }

    /// Replaces title, keywords, rating and label in an existing sidecar and keeps everything else
    /// (develop settings, camera data, other namespaces). Falls back to a fresh packet if it can't find a description.
    public static func update(_ existing: String, with m: FileMetadata) -> String {
        var s = existing
        for name in ["dc:title", "dc:subject", "xmp:Rating", "xmp:Label"] {
            while let open = s.range(of: "<" + name + ">") ?? s.range(of: "<" + name + " "),
                  let close = s.range(of: "</" + name + ">", range: open.upperBound..<s.endIndex) {
                var lo = open.lowerBound
                while lo > s.startIndex, s[s.index(before: lo)] == " " || s[s.index(before: lo)] == "\t" { lo = s.index(before: lo) }
                if lo > s.startIndex, s[s.index(before: lo)] == "\n" { lo = s.index(before: lo) }
                s.removeSubrange(lo..<close.upperBound)
            }
            // Attribute form: name="..."
            while let a = s.range(of: " " + name + "=\"") ?? s.range(of: "\n" + name + "=\""),
                  let q = s[a.upperBound...].firstIndex(of: "\"") {
                var lo = a.lowerBound
                while lo > s.startIndex, s[s.index(before: lo)] == " " || s[s.index(before: lo)] == "\t" { lo = s.index(before: lo) }
                s.removeSubrange(lo...q)
                s.insert(" ", at: lo)
            }
        }
        guard let open = s.range(of: "<rdf:Description"), let gt = s[open.upperBound...].firstIndex(of: ">") else { return packet(m) }
        var tagEnd = gt
        let selfClosing = s[s.index(before: gt)] == "/"
        var tag = String(s[open.lowerBound..<(selfClosing ? s.index(before: gt) : gt)])
        if !tag.contains("xmlns:dc=") { tag += " xmlns:dc=\"http://purl.org/dc/elements/1.1/\"" }
        if !tag.contains("xmlns:xmp=") { tag += " xmlns:xmp=\"http://ns.adobe.com/xap/1.0/\"" }
        tagEnd = s.index(after: gt)
        let replacement = tag + ">" + fields(m) + (selfClosing ? "\n  </rdf:Description>" : "")
        s.replaceSubrange(open.lowerBound..<tagEnd, with: replacement)
        return s
    }
}

// MARK: - Catalog side

extension StudioCatalog {
    /// Tags that describe how a file got here rather than what it shows; kept out of the keyword list and sidecars.
    public static func isSystemTag(_ t: String) -> Bool {
        ["imported", "watched", "bundled"].contains(t) || MediaKind.classify(extension: t) != nil
    }

    /// Applies what a file says about itself: keywords become tags, a title replaces the file-name title,
    /// stars and label are taken when the asset has none yet, and a -1 rating marks it rejected.
    /// Returns true when anything changed.
    @discardableResult
    public mutating func applyFileMetadata(_ m: FileMetadata, to id: UUID) -> Bool {
        guard let i = assets.firstIndex(where: { $0.id == id }), !m.isEmpty else { return false }
        let before = assets[i]
        for t in Self.parseTags(m.keywords.joined(separator: ",")) where !assets[i].tags.contains(t) { assets[i].tags.append(t) }
        if let t = m.title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { assets[i].title = t }
        if let r = m.rating, assets[i].rating == 0 {
            if r < 0 { if !assets[i].tags.contains(Self.rejectTag) { assets[i].tags.append(Self.rejectTag) } }
            else { assets[i].rating = min(5, r) }
        }
        if assets[i].label == nil, let l = m.label { assets[i].label = l }
        return assets[i] != before
    }

    /// What ASSSETS would write to a sidecar for this asset.
    public func fileMetadata(for id: UUID) -> FileMetadata? {
        guard let a = assets.first(where: { $0.id == id }) else { return nil }
        let rejected = a.tags.contains(Self.rejectTag)
        return FileMetadata(title: a.title, keywords: a.tags.filter { !Self.isSystemTag($0) && $0 != Self.rejectTag },
                            rating: rejected ? -1 : (a.rating > 0 ? a.rating : nil), label: a.label)
    }

    /// Every keyword with how many assets carry it, most used first.
    public func keywordCounts() -> [(tag: String, count: Int)] {
        var counts: [String: Int] = [:]
        for a in assets { for t in Set(a.tags) where !Self.isSystemTag(t) { counts[t, default: 0] += 1 } }
        return counts.map { ($0.key, $0.value) }.sorted { $0.count != $1.count ? $0.count > $1.count : $0.tag < $1.tag }
    }

    /// Renames a tag everywhere, merging into `new` when it already exists. Smart collection rules follow.
    /// Returns how many assets changed.
    @discardableResult
    public mutating func renameTag(_ old: String, to new: String) -> Int {
        guard let target = Self.parseTags(new).first, target != old else { return 0 }
        var n = 0
        for i in assets.indices where assets[i].tags.contains(old) {
            let hadTarget = assets[i].tags.contains(target)
            assets[i].tags = assets[i].tags.compactMap { $0 == old ? (hadTarget ? nil : target) : $0 }
            n += 1
        }
        for i in smartCollections.indices where smartCollections[i].rules.requiredTags.contains(old) {
            var tags = smartCollections[i].rules.requiredTags.map { $0 == old ? target : $0 }
            var seen = Set<String>(); tags = tags.filter { seen.insert($0).inserted }
            smartCollections[i].rules.requiredTags = tags
        }
        return n
    }
}
