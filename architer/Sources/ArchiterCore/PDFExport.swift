import Foundation

/// A minimal, dependency-free PDF 1.4 writer: Letter pages, the standard-14
/// Helvetica faces, text, filled/stroked rects, and lines. Enough for a
/// clean print layout without any platform APIs.
public struct PDFDocument {

    public enum Face { case regular, bold }

    public struct PageSize {
        public var width: Double
        public var height: Double
        public static let letter = PageSize(width: 612, height: 792)
        public static let a4 = PageSize(width: 595.28, height: 841.89)
    }

    public private(set) var pageSize: PageSize
    private var streams: [[String]] = [] // one operator list per page

    public init(pageSize: PageSize = .letter) {
        self.pageSize = pageSize
    }

    public var pageCount: Int { streams.count }

    @discardableResult
    public mutating func addPage() -> Int {
        streams.append([])
        return streams.count - 1
    }

    // Content streams are byte strings; keep text to ASCII so every reader
    // renders it identically. Common punctuation gets an ASCII stand-in.
    private static let asciiFallback: [UnicodeScalar: String] = [
        "\u{2018}": "'", "\u{2019}": "'", "\u{201C}": "\"", "\u{201D}": "\"",
        "\u{2013}": "-", "\u{2014}": "-", "\u{00B7}": "-", "\u{2026}": "...",
    ]

    private static func esc(_ s: String) -> String {
        var out = ""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "(": out += "\\("
            case ")": out += "\\)"
            case "\\": out += "\\\\"
            default:
                if scalar.value < 128 { out.unicodeScalars.append(scalar) }
                else if let mapped = asciiFallback[scalar] { out += mapped }
                else { out.append("?") }
            }
        }
        return out
    }

    public mutating func text(page: Int, x: Double, y: Double, _ s: String,
                              size: Double = 10, face: Face = .regular, gray: Double = 0,
                              rgb: (r: Double, g: Double, b: Double)? = nil) {
        guard streams.indices.contains(page) else { return }
        let font = face == .bold ? "F2" : "F1"
        let color = rgb.map { "\(fmt($0.r)) \(fmt($0.g)) \(fmt($0.b)) rg" } ?? "\(fmt(gray)) g"
        streams[page].append(
            "\(color) BT /\(font) \(fmt(size)) Tf \(fmt(x)) \(fmt(y)) Td (\(PDFDocument.esc(s))) Tj ET")
    }

    public mutating func fillRect(page: Int, x: Double, y: Double, w: Double, h: Double, gray: Double) {
        guard streams.indices.contains(page) else { return }
        streams[page].append("\(fmt(gray)) g \(fmt(x)) \(fmt(y)) \(fmt(w)) \(fmt(h)) re f 0 g")
    }

    public mutating func strokeRect(page: Int, x: Double, y: Double, w: Double, h: Double,
                                    lineWidth: Double = 0.8, gray: Double = 0,
                                    rgb: (r: Double, g: Double, b: Double)? = nil) {
        guard streams.indices.contains(page) else { return }
        let color = rgb.map { "\(fmt($0.r)) \(fmt($0.g)) \(fmt($0.b)) RG" } ?? "\(fmt(gray)) G"
        streams[page].append(
            "\(color) \(fmt(lineWidth)) w \(fmt(x)) \(fmt(y)) \(fmt(w)) \(fmt(h)) re S 0 G 1 w")
    }

    public mutating func line(page: Int, x1: Double, y1: Double, x2: Double, y2: Double,
                              lineWidth: Double = 0.8, gray: Double = 0,
                              rgb: (r: Double, g: Double, b: Double)? = nil) {
        guard streams.indices.contains(page) else { return }
        let color = rgb.map { "\(fmt($0.r)) \(fmt($0.g)) \(fmt($0.b)) RG" } ?? "\(fmt(gray)) G"
        streams[page].append(
            "\(color) \(fmt(lineWidth)) w \(fmt(x1)) \(fmt(y1)) m \(fmt(x2)) \(fmt(y2)) l S 0 G 1 w")
    }

    private func fmt(_ v: Double) -> String {
        if v == v.rounded() && abs(v) < 1e15 { return String(Int(v)) }
        return String(format: "%.2f", v)
    }

    public func render() -> Data {
        // Object layout: 1 catalog, 2 pages, 3 regular font, 4 bold font,
        // then per page i: page object (5 + 2i) and content object (6 + 2i).
        var objects: [String] = []
        let pageKids = streams.indices.map { "\(5 + 2 * $0) 0 R" }.joined(separator: " ")
        objects.append("<< /Type /Catalog /Pages 2 0 R >>")
        objects.append("<< /Type /Pages /Kids [\(pageKids)] /Count \(streams.count) >>")
        objects.append("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>")
        objects.append("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>")
        for (i, ops) in streams.enumerated() {
            let contentObj = 6 + 2 * i
            objects.append("""
            << /Type /Page /Parent 2 0 R /MediaBox [0 0 \(fmt(pageSize.width)) \(fmt(pageSize.height))] \
            /Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> /Contents \(contentObj) 0 R >>
            """)
            let body = ops.joined(separator: "\n")
            objects.append("<< /Length \(body.utf8.count) >>\nstream\n\(body)\nendstream")
        }

        var out = "%PDF-1.4\n"
        var offsets: [Int] = []
        for (i, body) in objects.enumerated() {
            offsets.append(out.utf8.count)
            out += "\(i + 1) 0 obj\n\(body)\nendobj\n"
        }
        let xrefPos = out.utf8.count
        out += "xref\n0 \(objects.count + 1)\n"
        out += "0000000000 65535 f \n"
        for off in offsets { out += String(format: "%010d 00000 n \n", off) }
        out += """
        trailer
        << /Size \(objects.count + 1) /Root 1 0 R >>
        startxref
        \(xrefPos)
        %%EOF
        """
        return Data(out.utf8)
    }
}

/// Print layout for a character sheet: header, ability boxes, vitals chips,
/// then sections in layout order, flowing across Letter pages.
public enum SheetPDFExporter {

    /// Print-friendly brass, echoing the app's ink-and-brass theme.
    private static let brass = (r: 0.55, g: 0.40, b: 0.15)

    public static func export(_ c: Character) -> Data {
        var doc = PDFDocument()
        var cursor = Cursor(doc: doc)
        let margin = 54.0
        let contentW = doc.pageSize.width - margin * 2

        cursor.ensure(120)
        // Header
        cursor.text(margin, c.name, size: 22, face: .bold)
        cursor.advance(26)
        let subtitle = "Level \(c.level) \(c.lineage) \(c.calling)"
            .trimmingCharacters(in: .whitespaces)
        cursor.text(margin, subtitle, size: 12)
        cursor.advance(16)
        var meta = "XP \(c.experience)  ·  Proficiency bonus +\(c.proficiencyBonus)  ·  \(c.era.displayName)"
        if !c.background.isEmpty { meta += "  ·  \(c.background)" }
        if let ruleset = c.rulesetName { meta += "  ·  \(ruleset) ruleset" }
        cursor.text(margin, meta, size: 9, gray: 0.35)
        cursor.advance(10)
        cursor.ruleColored(margin, width: contentW, rgb: brass)
        cursor.advance(14)

        for block in c.layout.visibleBlocks {
            switch block.kind {
            case .identity:
                continue // already the header
            case .abilities:
                cursor.section("Abilities", margin: margin)
                let boxW = (contentW - 5 * 8) / 6
                cursor.ensure(58)
                let top = cursor.y
                for (i, a) in Ability.allCases.enumerated() {
                    let x = margin + Double(i) * (boxW + 8)
                    cursor.doc.strokeRect(page: cursor.page, x: x, y: top - 50, w: boxW, h: 50)
                    let label = a.abbreviation
                    cursor.doc.text(page: cursor.page, x: x + boxW / 2 - est(label, 7) / 2, y: top - 12,
                                    label, size: 7, gray: 0.35)
                    let score = "\(c.scores[a])"
                    cursor.doc.text(page: cursor.page, x: x + boxW / 2 - est(score, 16) / 2, y: top - 32,
                                    score, size: 16, face: .bold)
                    let save = "save \(signed(c.savingThrow(a)))"
                    cursor.doc.text(page: cursor.page, x: x + boxW / 2 - est(save, 6) / 2, y: top - 44,
                                    save, size: 6, gray: 0.35)
                }
                cursor.advance(58)
            case .vitals:
                cursor.section("Vitals", margin: margin)
                var chips: [(String, String)] = [
                    ("HP", "\(c.currentHP)/\(c.maxHP)\(c.tempHP > 0 ? " +\(c.tempHP)t" : "")"),
                    ("AC", "\(c.computedAC)"),
                    ("Initiative", signed(c.initiative)),
                    ("Speed", "\(c.speed) ft"),
                    ("Passive Perc", "\(c.passivePerception)"),
                    ("Passive Inv", "\(c.passiveInvestigation)"),
                    ("Passive Ins", "\(c.passiveInsight)"),
                    ("Hit Dice", "\(c.hitDiceRemaining)/\(c.hitDiceTotal) d\(c.hitDiceType)"),
                ]
                if c.exhaustion > 0 { chips.append(("Exhaustion", "\(c.exhaustion)")) }
                if !SheetExporter.defenseSummary(c).isEmpty {
                    chips.append(("Defenses", SheetExporter.defenseSummary(c)))
                }
                let perRow = 4
                let chipW = (contentW - Double(perRow - 1) * 8) / Double(perRow)
                let rowsNeeded = (chips.count + perRow - 1) / perRow
                cursor.ensure(Double(rowsNeeded) * 36)
                for (i, (label, value)) in chips.enumerated() {
                    let row = i / perRow
                    let col = i % perRow
                    let x = margin + Double(col) * (chipW + 8)
                    let top = cursor.y - Double(row) * 36
                    cursor.doc.strokeRect(page: cursor.page, x: x, y: top - 28, w: chipW, h: 28)
                    let t = "\(label)  \(value)"
                    cursor.doc.text(page: cursor.page, x: x + chipW / 2 - est(t, 8) / 2, y: top - 18,
                                    t, size: 8)
                }
                cursor.advance(Double(rowsNeeded) * 36)
                if !c.conditions.isEmpty {
                    cursor.line("Conditions: " + c.conditions.map { $0.displayName }.sorted().joined(separator: ", "), margin: margin, gray: 0.3)
                }
                if c.exhaustion > 0 {
                    cursor.line("Exhaustion \(c.exhaustion): \(c.exhaustionStepNote)", margin: margin, gray: 0.3)
                }
            case .skills:
                cursor.section("Skills", margin: margin)
                let trained = c.skills.filter { $0.tier != .none }
                if trained.isEmpty {
                    cursor.line("No trained skills", margin: margin, gray: 0.45)
                } else {
                    let colW = contentW / 2
                    for (i, s) in trained.enumerated() {
                        if i % 2 == 0 { cursor.ensure(13) }
                        let x = margin + Double(i % 2) * colW
                        let bonus = signed(s.bonus(scores: c.scores, level: c.level))
                        let text = "\(s.name) \(bonus)\(s.tier == .expert ? " (expert)" : "")"
                        cursor.put(x, text, size: 9)
                        if i % 2 == 1 || i == trained.count - 1 { cursor.advance(13) }
                    }
                }
            case .attacks:
                cursor.section("Attacks", margin: margin)
                let showMastery = c.era.usesWeaponMastery && c.attacks.contains { $0.mastery != nil }
                let cols: [(String, Double)] = showMastery
                    ? [("Attack", 0), ("Bonus", 150), ("Damage", 205), ("Type", 290), ("Mastery", 350), ("Range", 430)]
                    : [("Attack", 0), ("Bonus", 170), ("Damage", 230), ("Type", 320), ("Range", 400)]
                cursor.ensure(16)
                cursor.doc.fillRect(page: cursor.page, x: margin, y: cursor.y - 14, w: contentW, h: 16, gray: 0.9)
                for (title, off) in cols {
                    cursor.put(margin + 4 + off, title, size: 8, face: .bold)
                }
                cursor.advance(16)
                if c.attacks.isEmpty {
                    cursor.line("No attacks", margin: margin, gray: 0.45)
                }
                for a in c.attacks {
                    cursor.ensure(14)
                    cursor.put(margin + 4, a.name + (a.ammunition.map { " (ammo \($0))" } ?? ""), size: 9)
                    if showMastery {
                        cursor.put(margin + 4 + 150, signed(a.attackBonus(scores: c.scores, level: c.level)), size: 9)
                        cursor.put(margin + 4 + 205, a.damageString(scores: c.scores), size: 9)
                        cursor.put(margin + 4 + 290, a.damageType, size: 9)
                        cursor.put(margin + 4 + 350, a.mastery?.rawValue ?? "-", size: 9)
                        cursor.put(margin + 4 + 430, a.range, size: 9)
                    } else {
                        cursor.put(margin + 4 + 170, signed(a.attackBonus(scores: c.scores, level: c.level)), size: 9)
                        cursor.put(margin + 4 + 230, a.damageString(scores: c.scores), size: 9)
                        cursor.put(margin + 4 + 320, a.damageType, size: 9)
                        cursor.put(margin + 4 + 400, a.range, size: 9)
                    }
                    cursor.advance(13)
                    cursor.rule(margin, width: contentW, gray: 0.85)
                    cursor.advance(1)
                }
                if let sc = c.spellcasting {
                    cursor.line("Spell attack \(signed(sc.spellAttackBonus(scores: c.scores, level: c.level))) - Spell save DC \(sc.spellSaveDC(scores: c.scores, level: c.level)) (\(sc.ability.abbreviation))", margin: margin, gray: 0.3)
                }
            case .spells:
                guard let sc = c.spellcasting else { continue }
                cursor.section("Spells (\(sc.progression.displayName))", margin: margin)
                var slotChips: [String] = []
                for sl in 1...9 {
                    let maxSlots = sc.slotsMax(spellLevel: sl, casterLevel: c.level)
                    if maxSlots > 0 {
                        slotChips.append("Lvl \(sl) \(sc.slotsRemaining(spellLevel: sl, casterLevel: c.level))/\(maxSlots)")
                    }
                }
                if !slotChips.isEmpty {
                    cursor.line("Slots: " + slotChips.joined(separator: "  "), margin: margin)
                }
                if let concentrating = c.concentratingOn {
                    cursor.line("Concentrating: \(concentrating)", margin: margin, gray: 0.3)
                }
                let cantrips = sc.cantrips.map { $0.name }.sorted().joined(separator: ", ")
                if !cantrips.isEmpty {
                    for line in wrap("Cantrips: " + cantrips, width: contentW, size: 9) {
                        cursor.line(line, margin: margin)
                    }
                }
                for sl in 1...9 {
                    let atLevel = sc.spells(atLevel: sl)
                    if !atLevel.isEmpty {
                        let names = atLevel.map { $0.prepared ? $0.name : "\($0.name) (unprepared)" }.joined(separator: ", ")
                        for line in wrap("Level \(sl): " + names, width: contentW, size: 9) {
                            cursor.line(line, margin: margin)
                        }
                    }
                }
            case .inventory:
                cursor.section("Inventory", margin: margin)
                cursor.line("Currency: \(c.currency.displayString) - Carried \(SheetExporter.fmtWeight(c.totalWeight)) / \(c.carryingCapacity) lb", margin: margin, gray: 0.3)
                if c.inventory.isEmpty {
                    cursor.line("Empty pack", margin: margin, gray: 0.45)
                } else {
                    let colW = contentW / 2
                    for (i, item) in c.inventory.enumerated() {
                        if i % 2 == 0 { cursor.ensure(13) }
                        let x = margin + Double(i % 2) * colW
                        var text = item.name
                        if item.quantity > 1 { text += " x\(item.quantity)" }
                        if item.stowed { text += " (stowed)" }
                        if !item.notes.isEmpty { text += " - \(item.notes)" }
                        cursor.put(x, text, size: 9)
                        if i % 2 == 1 || i == c.inventory.count - 1 { cursor.advance(13) }
                    }
                }
            case .features:
                cursor.section("Features & Traits", margin: margin)
                if c.features.isEmpty {
                    cursor.line("None recorded", margin: margin, gray: 0.45)
                }
                for f in c.features {
                    var head = f.name + (f.source.isEmpty ? "" : " (\(f.source))")
                    if let remaining = f.usesRemaining { head += " - \(remaining)/\(f.usesMax) uses" }
                    cursor.line(head, margin: margin)
                    if !f.detail.isEmpty {
                        for line in wrap(f.detail, width: contentW - 14, size: 9) {
                            cursor.ensure(13)
                            cursor.put(margin + 14, line, size: 9, gray: 0.3)
                            cursor.advance(13)
                        }
                    }
                }
            case .personality:
                guard !c.personality.isEmpty else { continue }
                let p = c.personality
                cursor.section("Personality", margin: margin)
                let pairs: [(String, String)] = [("Traits", p.traits), ("Ideals", p.ideals), ("Bonds", p.bonds), ("Flaws", p.flaws)]
                for (label, value) in pairs where !value.isEmpty {
                    for (i, line) in wrap(value, width: contentW - 60, size: 9).enumerated() {
                        cursor.ensure(13)
                        if i == 0 {
                            cursor.put(margin, label + ":", size: 9, face: .bold)
                        }
                        cursor.put(margin + 60, line, size: 9)
                        cursor.advance(13)
                    }
                }
                if !p.backstory.isEmpty {
                    cursor.line("Backstory", margin: margin)
                    for para in p.backstory.components(separatedBy: "\n") {
                        for line in wrap(para, width: contentW, size: 9) {
                            cursor.ensure(13)
                            cursor.put(margin + 14, line, size: 9, gray: 0.3)
                            cursor.advance(13)
                        }
                    }
                }
            case .diceRoller:
                continue // interactive block, not printable
            case .notes:
                guard !c.notes.isEmpty else { continue }
                cursor.section("Notes", margin: margin)
                for para in c.notes.components(separatedBy: "\n") {
                    for line in wrap(para, width: contentW, size: 9) {
                        cursor.line(line, margin: margin)
                    }
                }
            case .journal:
                guard !c.journal.isEmpty else { continue }
                cursor.section("Journal", margin: margin)
                for e in c.journal {
                    let head = [e.date, e.title].filter { !$0.isEmpty }.joined(separator: " - ")
                    for line in wrap(head.isEmpty ? "Entry" : head, width: contentW, size: 9) {
                        cursor.line(line, margin: margin)
                    }
                    for para in e.text.components(separatedBy: "\n") {
                        for line in wrap(para, width: contentW - 14, size: 9) {
                            cursor.put(margin + 14, line, size: 9, gray: 0.3)
                            cursor.advance(13)
                        }
                    }
                }
            case .companions:
                guard !c.companions.isEmpty else { continue }
                cursor.section("Companions", margin: margin)
                for comp in c.companions {
                    var text = "\(comp.name)\(comp.kind.isEmpty ? "" : " (\(comp.kind))") - HP \(comp.currentHP)/\(comp.maxHP), AC \(comp.armorClass)"
                    if !comp.notes.isEmpty { text += " - \(comp.notes)" }
                    for line in wrap(text, width: contentW, size: 9) {
                        cursor.line(line, margin: margin)
                    }
                }
            }
            cursor.advance(8)
        }

        // Custom ruleset sections and user-defined templated blocks.
        if !c.customAbilities.isEmpty {
            cursor.section("\(c.rulesetName ?? "Custom") Abilities", margin: margin)
            let cols: [(String, Double)] = [("Ability", 0), ("Score", 200), ("Mod", 270)]
            cursor.ensure(16)
            cursor.doc.fillRect(page: cursor.page, x: margin, y: cursor.y - 14, w: contentW, h: 16, gray: 0.9)
            for (title, off) in cols {
                cursor.put(margin + 4 + off, title, size: 8, face: .bold)
            }
            cursor.advance(16)
            for a in c.customAbilities {
                cursor.ensure(14)
                cursor.put(margin + 4, a.name, size: 9)
                cursor.put(margin + 4 + 200, "\(a.score)", size: 9)
                cursor.put(margin + 4 + 270, signed(a.modifier), size: 9)
                cursor.advance(13)
            }
            cursor.advance(8)
        }
        if !c.customSkills.isEmpty {
            cursor.section("\(c.rulesetName ?? "Custom") Skills", margin: margin)
            let trained = c.customSkills.filter { $0.tier != .none }
            if trained.isEmpty {
                cursor.line("No trained skills", margin: margin, gray: 0.45)
            } else {
                let colW = contentW / 2
                for (i, s) in trained.enumerated() {
                    if i % 2 == 0 { cursor.ensure(13) }
                    let x = margin + Double(i % 2) * colW
                    let bonus = signed(s.bonus(abilities: c.customAbilities, level: c.level))
                    let text = "\(s.name) \(bonus)\(s.tier == .expert ? " (expert)" : "")"
                    cursor.put(x, text, size: 9)
                    if i % 2 == 1 || i == trained.count - 1 { cursor.advance(13) }
                }
            }
            cursor.advance(8)
        }
        for block in c.layout.customBlocks {
            cursor.section(TemplateRenderer.render(block.title, for: c), margin: margin)
            for para in TemplateRenderer.render(block.body, for: c).components(separatedBy: "\n") {
                for line in wrap(para, width: contentW, size: 9) {
                    cursor.line(line, margin: margin)
                }
            }
            cursor.advance(8)
        }

        // Cursor owns the working copy; take it back before finishing.
        doc = cursor.doc

        // Footer on every page.
        for p in 0..<doc.pageCount {
            doc.line(page: p, x1: margin, y1: 46, x2: margin + contentW, y2: 46, lineWidth: 0.5, gray: 0.8)
            doc.text(page: p, x: margin, y: 36, "Made with ARCHITER", size: 7, gray: 0.5)
            doc.text(page: p, x: margin + contentW - 40, y: 36, "Page \(p + 1) of \(doc.pageCount)", size: 7, gray: 0.5)
        }
        return doc.render()
    }

    /// Rough Helvetica advance estimate for centering/wrapping (~0.5 em).
    private static func est(_ s: String, _ size: Double) -> Double {
        Double(s.count) * size * 0.5
    }

    private static func wrap(_ s: String, width: Double, size: Double) -> [String] {
        var lines: [String] = []
        var current = ""
        for word in s.split(separator: " ", omittingEmptySubsequences: false) {
            let candidate = current.isEmpty ? String(word) : current + " " + word
            if est(candidate, size) > width, !current.isEmpty {
                lines.append(current)
                current = String(word)
            } else {
                current = candidate
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines.isEmpty ? [""] : lines
    }

    private static func signed(_ n: Int) -> String { n >= 0 ? "+\(n)" : "\(n)" }

    /// Tracks the vertical cursor and opens new pages as needed.
    private struct Cursor {
        var doc: PDFDocument
        var page: Int
        var y: Double
        let bottom = 60.0

        init(doc: PDFDocument) {
            var d = doc
            self.page = d.addPage()
            self.doc = d
            self.y = d.pageSize.height - 54
        }

        mutating func ensure(_ space: Double) {
            if y - space < bottom {
                page = doc.addPage()
                y = doc.pageSize.height - 54
            }
        }

        mutating func advance(_ dy: Double) { y -= dy }

        /// Draws at the current cursor baseline - the single convention for
        /// all rows so ascenders never overlap the previous line.
        mutating func put(_ x: Double, _ s: String, size: Double = 9,
                          face: PDFDocument.Face = .regular, gray: Double = 0) {
            doc.text(page: page, x: x, y: y, s, size: size, face: face, gray: gray)
        }

        mutating func text(_ x: Double, _ s: String, size: Double, face: PDFDocument.Face = .regular, gray: Double = 0) {
            doc.text(page: page, x: x, y: y, s, size: size, face: face, gray: gray)
        }

        mutating func section(_ title: String, margin: Double) {
            ensure(30)
            doc.text(page: page, x: margin, y: y, title.uppercased(), size: 10, face: .bold,
                     rgb: SheetPDFExporter.brass)
            advance(13)
            ruleColored(margin, width: doc.pageSize.width - margin * 2, rgb: SheetPDFExporter.brass)
            advance(11)
        }

        mutating func ruleColored(_ x: Double, width: Double, rgb: (r: Double, g: Double, b: Double)) {
            doc.line(page: page, x1: x, y1: y, x2: x + width, y2: y, lineWidth: 0.9, rgb: rgb)
        }

        mutating func line(_ s: String, margin: Double, gray: Double = 0) {
            ensure(13)
            text(margin, s, size: 9, gray: gray)
            advance(13)
        }

        mutating func rule(_ x: Double, width: Double, gray: Double = 0) {
            doc.line(page: page, x1: x, y1: y, x2: x + width, y2: y, lineWidth: 0.8, gray: gray)
        }
    }
}
