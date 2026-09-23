#if os(macOS)
import SwiftUI
import AppKit
import AVFoundation
import AVKit
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UniformTypeIdentifiers
import CryptoKit
import PDFKit
import AsssetsCore

@main
struct ASSSETSApp: App {
    @StateObject private var library = StudioLibrary()
    var body: some Scene {
        WindowGroup("ASSSETS") {
            StudioView()
                .environmentObject(library)
                .frame(minWidth: 960, minHeight: 620)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Import Files…") { library.importFiles() }.keyboardShortcut("i")
                Button("Watch Folder…") { library.addWatchFolder() }.keyboardShortcut("i", modifiers: [.command, .shift])
                Button("Find Duplicates…") { library.findDuplicates() }.keyboardShortcut("d", modifiers: [.command, .option])
                Button("Compare Selection") { library.openCompare() }.keyboardShortcut("c", modifiers: [.command, .option]).disabled(!library.canCompare)
                Button("Cull Current View") { library.openCull() }.keyboardShortcut("k", modifiers: [.command, .option]).disabled(!library.canCull)
                Button("Find Similar") { if let id = library.focusID { library.findSimilar(id) } }.keyboardShortcut("f", modifiers: [.command, .option]).disabled(library.focusID == nil)
                Button("New Collection") { library.newCollection(with: []) }.keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Batch Rename…") { library.openBatchRename() }.keyboardShortcut("r", modifiers: [.command, .option]).disabled(library.selection.isEmpty)
                Divider()
                Button("Stack as Versions") { library.stackSelection() }.keyboardShortcut("g", modifiers: [.command]).disabled(!library.canStack)
                Button("Unstack") { library.unstackSelection() }.keyboardShortcut("g", modifiers: [.command, .shift]).disabled(!library.canUnstack)
                Divider()
                Menu("Rating") {
                    ForEach(0...5, id: \.self) { n in Button(n == 0 ? "No Rating  (0)" : String(repeating: "★", count: n) + "  (\(n))") { library.rate(library.selection, n) } }
                }.disabled(library.selection.isEmpty)
                Menu("Label") {
                    ForEach(ColorLabel.allCases) { l in Button(l.name + (l.key.map { "  (\($0))" } ?? "")) { library.label(library.selection, l) } }
                    Divider(); Button("No Label") { library.label(library.selection, nil) }
                }.disabled(library.selection.isEmpty)
            }
            CommandGroup(replacing: .undoRedo) {
                Button(library.history.undoLabel.map { "Undo \($0)" } ?? "Undo") { library.undo() }.keyboardShortcut("z")
                Button(library.history.redoLabel.map { "Redo \($0)" } ?? "Redo") { library.redo() }.keyboardShortcut("z", modifiers: [.command, .shift])
            }
            CommandGroup(after: .pasteboard) {
                Button("Select All Assets") { library.selectAllVisible() }.keyboardShortcut("a", modifiers: [.command, .option])
                Button("Deselect All") { library.clearSelection() }.keyboardShortcut("d", modifiers: [.command])
                Button("Toggle Favorite") { library.toggleFavorite(library.selection) }.keyboardShortcut("l", modifiers: [.command])
                Divider()
                Button("Export Selection As Shown…") { library.exportToFolder(library.selection, mode: .asShown) }
                    .keyboardShortcut("e", modifiers: [.command]).disabled(library.selection.isEmpty)
                Button("Export Original Files…") { library.exportToFolder(library.selection, mode: .originals) }
                    .keyboardShortcut("e", modifiers: [.command, .shift]).disabled(library.selection.isEmpty)
                Button("Export with Presets…") { library.openPresetExport() }
                    .keyboardShortcut("e", modifiers: [.command, .option]).disabled(library.selection.isEmpty)
                Button("Export Picks with Presets…") { library.openPresetExport(library.pickIDs, title: "Picks") }.disabled(library.pickIDs.isEmpty)
                Divider()
                Button("Export Review Gallery…") { library.exportGallery() }
                    .keyboardShortcut("g", modifiers: [.command, .option]).disabled(library.selection.isEmpty)
                Button("Export Current View as Review Gallery…") { library.exportGallery(library.filtered.map(\.id), title: library.browsingTitle) }
                Button("Import Client Feedback…") { library.importFeedback() }
                Button("Write Metadata to Files (.xmp sidecars)") { library.writeMetadata(library.selection) }.disabled(!library.canWriteMetadata)
                Button("Reveal in Finder") { library.reveal(library.selection) }
                    .keyboardShortcut("r", modifiers: [.command, .shift]).disabled(!library.canReveal)
                Button("Contact Sheet & Brand Kit…") { library.openContactSheetForCurrentView() }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
            }
        }
    }
}

extension UTType {
    /// Internal drag payload (asset IDs); declared in Info.plist and only visible inside ASSSETS.
    static let asssetsSelection = UTType(exportedAs: "co.instinct.asssets.selection")
}

enum Theme {
    static let accent = Color(red: 0.55, green: 0.38, blue: 1.0)
    static let ink = Color(red: 0.035, green: 0.04, blue: 0.065)
    static let panel = Color(red: 0.055, green: 0.058, blue: 0.09)
    static let raised = Color.white.opacity(0.055)
    static let hairline = Color.white.opacity(0.085)
    static let smart = Color(red: 0.36, green: 0.82, blue: 0.95)
    static let warning = Color(red: 1.0, green: 0.72, blue: 0.28)
    static let watch = Color(red: 0.45, green: 0.9, blue: 0.62)
    static let backdrop = LinearGradient(colors: [Color(red: 0.045, green: 0.05, blue: 0.08), Color(red: 0.075, green: 0.05, blue: 0.115)], startPoint: .top, endPoint: .bottom)
    static let sidebar = LinearGradient(colors: [Color(red: 0.04, green: 0.043, blue: 0.07), Color(red: 0.03, green: 0.032, blue: 0.05)], startPoint: .top, endPoint: .bottom)
}

enum EffectPreset: String, CaseIterable, Identifiable {
    case original = "Original", vivid = "Vivid", mono = "Noir", warm = "Warm Film", cool = "Arctic", chrome = "Chrome", blur = "Dream Blur", poster = "Poster"
    var id: String { rawValue }
}

// MARK: - Library model

@MainActor
final class StudioLibrary: ObservableObject {
    @Published var catalog = StudioCatalog()
    @Published var search = ""
    @Published var selectedKind: MediaKind?
    @Published var selectedCollection = StudioCatalog.allAssets
    @Published var selection: Set<UUID> = []
    @Published var focusID: UUID?
    @Published var effect: EffectPreset = .original
    @Published var intensity = 0.75
    @Published var gridScale = 150.0
    @Published var pendingRemoval: Set<UUID> = []
    @Published var renamingCollection: String?
    @Published var toast: String?
    @Published var selectedSmart: UUID?
    @Published var smartEditor: SmartEditorState?
    /// Per-asset PSD layer visibility flips for this session (layer indices).
    @Published var psdToggled: [UUID: Set<Int>] = [:]
    /// Texture repeat preview (1 = off, 2 = 2 x 2, 3 = 3 x 3) and per-asset seam fixing, for this session.
    @Published var tileRepeat = 1
    /// Asset shown in the full-window viewer (space bar), nil when closed.
    @Published var viewerID: UUID?
    var scrollInspectorToTags = false
    /// Full-window compare of 2-4 assets, nil when closed.
    @Published var compare: CompareSession?
    @Published var compareZoom = ZoomPan()
    @Published var compareSwipe = false
    @Published var swipeSplit = 0.5
    private var keyMonitor: Any?
    private var scrollMonitor: Any?

    func openViewer() {
        guard smartEditor == nil, duplicates == nil, sheetPreview == nil else { return }
        viewerID = focusID ?? selection.first ?? filtered.first?.id
    }
    func closeViewer() { viewerID = nil }

    // MARK: Export presets

    struct PresetExportState: Identifiable {
        let id = UUID()
        var ids: [UUID]
        var title: String
        var presets: Set<ExportPreset> = [.web, .social]
        var crop: CropMode = .detail
        var pattern = FilenamePattern.defaultPattern
        /// Subfolders inside the export folder, e.g. "{collection}/{label}". Empty exports flat (1.14). Remembered.
        var folders = UserDefaults.standard.string(forKey: "exportFolderPattern") ?? ""
        /// Write title, tags, rating and label into the exported JPEG and TIFF copies (1.13). Remembered.
        var embedMetadata = UserDefaults.standard.bool(forKey: "exportEmbedMetadata")
    }
    @Published var presetExport: PresetExportState?
    @Published var presetExportRunning = false

    var pickIDs: [UUID] { catalog.assets.filter { $0.tags.contains(StudioCatalog.pickTag) }.map(\.id) }

    func openPresetExport(_ ids: [UUID]? = nil, title: String? = nil) {
        let list = ids ?? (selection.isEmpty ? [] : filtered.map(\.id).filter(selection.contains))
        let usable = list.filter { id in catalog.assets.first { $0.id == id }?.kind != .audio }
        guard !usable.isEmpty else { flash("Select images, textures, vectors or mockups to export"); return }
        presetExport = PresetExportState(ids: usable, title: title ?? (usable.count == 1 ? "1 asset" : "\(usable.count) assets"))
    }

    /// Asks for a folder, then renders every preset off the main thread. Never overwrites existing files.
    func runPresetExport(_ st: PresetExportState, to fixedDir: URL? = nil) {
        var dir = fixedDir
        if dir == nil {
            let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
            p.prompt = "Export Here"; p.message = "Export \(st.ids.count) assets with \(st.presets.count) presets"
            guard p.runModal() == .OK, let u = p.url else { return }
            dir = u
        }
        guard let dir else { return }
        presetExport = nil
        UserDefaults.standard.set(st.embedMetadata, forKey: "exportEmbedMetadata")
        UserDefaults.standard.set(st.folders, forKey: "exportFolderPattern")
        let byID = Dictionary(uniqueKeysWithValues: catalog.assets.map { ($0.id, $0) })
        let assets = st.ids.compactMap { byID[$0] }
        let jobs = assets.map { a in (a, effect, intensity, psdToggled[a.id] ?? [], tiles(for: a), fixSeams.contains(a.id)) }
        let metadata: [UUID: FileMetadata] = st.embedMetadata ? Dictionary(uniqueKeysWithValues: assets.compactMap { a in catalog.fileMetadata(for: a.id).map { (a.id, $0) } }) : [:]
        let presets = ExportPreset.allCases.filter(st.presets.contains)
        presetExportRunning = true
        flash("Exporting \(assets.count) assets…")
        let today = Date()
        Task.detached(priority: .userInitiated) {
            // Names already used, per folder, so clashes get "Name 2.jpg" inside each subfolder like Finder.
            var takenIn: [String: Set<String>] = [:]
            var written: [URL] = [], failed = 0
            for (n, job) in jobs.enumerated() {
                let (a, fx, amt, psd, tiles, fix) = job
                guard let img = MediaRenderer.exportBase(a, effect: fx, amount: amt, psdToggled: psd, tiles: tiles, fixSeams: fix) else { failed += 1; continue }
                var focus: [Double: ExportRect] = [:]
                if st.crop == .detail, let small = MediaRenderer.pixelBuffer(from: img, maxPixel: 256) {
                    for p in presets { if let asp = p.cropAspect { focus[asp] = SmartCrop.detailWindow(small, sourceWidth: img.width, sourceHeight: img.height, aspect: asp) } }
                }
                let sub = FolderPattern.relativePath(st.folders, asset: a, date: today)
                let folder = sub.isEmpty ? dir : dir.appendingPathComponent(sub, isDirectory: true)
                if !sub.isEmpty { try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
                if takenIn[sub] == nil { takenIn[sub] = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []) }
                for p in presets {
                    for o in p.outputs(width: img.width, height: img.height, crop: st.crop, focus: p.cropAspect.flatMap { focus[$0] }) {
                        let name = DragOut.uniqueName(FilenamePattern.render(st.pattern, asset: a, preset: p, output: o, index: n + 1, date: today), taken: takenIn[sub] ?? [])
                        let url = folder.appendingPathComponent(name)
                        if MediaRenderer.writePreset(img, output: o, to: url, metadata: metadata[a.id]) { takenIn[sub, default: []].insert(name); written.append(url) } else { failed += 1 }
                    }
                }
            }
            await MainActor.run { [written, failed] in
                self.presetExportRunning = false
                self.flash(failed == 0 ? "Exported \(written.count) files" : "Exported \(written.count) files, \(failed) failed")
                if fixedDir == nil, !written.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(written) }
                if fixedDir != nil {
                    let rel = written.map { String($0.path.dropFirst(dir.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
                    try? rel.sorted().joined(separator: "\n").write(to: dir.appendingPathComponent("done.txt"), atomically: true, encoding: .utf8)
                }
            }
        }
    }

    // MARK: Client review gallery

    @Published var galleryRunning = false

    /// Writes "<title> Review" (index.html, images/, thumbs/) and a zip of it into a folder the user picks.
    func exportGallery(_ ids: [UUID]? = nil, title: String? = nil, to fixedDir: URL? = nil) {
        let list = ids ?? filtered.map(\.id).filter(selection.contains)
        let byID = Dictionary(uniqueKeysWithValues: catalog.assets.map { ($0.id, $0) })
        let assets = list.compactMap { byID[$0] }.filter { $0.kind != .audio }
        guard !assets.isEmpty else { flash("Select images, textures, vectors, mockups or clips for a gallery"); return }
        let name = title ?? (selection.count > 1 || ids != nil ? browsingTitle : "Review")
        var parent = fixedDir
        if parent == nil {
            let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
            p.prompt = "Create Gallery Here"; p.message = "Creates a \"\(DragOut.safeName(name)) Review\" folder and zip with \(assets.count) assets"
            guard p.runModal() == .OK, let u = p.url else { return }
            parent = u
        }
        guard let parent else { return }
        let taken = Set((try? FileManager.default.contentsOfDirectory(atPath: parent.path)) ?? [])
        let folderName = DragOut.uniqueName(DragOut.safeName(name + " Review"), taken: taken)
        let folder = parent.appendingPathComponent(folderName, isDirectory: true)
        let jobs = assets.map { a in (a, effect, intensity, psdToggled[a.id] ?? [], tiles(for: a), fixSeams.contains(a.id)) }
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"; let created = df.string(from: Date())
        galleryRunning = true
        flash("Building gallery for \(assets.count) assets…")
        Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            try? fm.createDirectory(at: folder.appendingPathComponent("images"), withIntermediateDirectories: true)
            try? fm.createDirectory(at: folder.appendingPathComponent("thumbs"), withIntermediateDirectories: true)
            var items: [ReviewGallery.Item] = []
            for (i, job) in jobs.enumerated() {
                let (a, fx, amt, psd, tiles, fix) = job
                guard let img = MediaRenderer.exportBase(a, effect: fx, amount: amt, psdToggled: psd, tiles: tiles, fixSeams: fix) else { continue }
                let stem = ReviewGallery.stem(i, count: jobs.count)
                let full = ExportRect(x: 0, y: 0, w: img.width, h: img.height)
                func sized(_ edge: Int) -> ExportOutput {
                    let s = min(1, Double(edge) / Double(max(img.width, img.height)))
                    return ExportOutput(suffix: "", width: max(1, Int(Double(img.width) * s)), height: max(1, Int(Double(img.height) * s)), crop: full, format: .jpeg, dpi: 72)
                }
                guard MediaRenderer.writePreset(img, output: sized(2000), to: folder.appendingPathComponent("images/\(stem).jpg")),
                      MediaRenderer.writePreset(img, output: sized(640), to: folder.appendingPathComponent("thumbs/\(stem).jpg")) else { continue }
                items.append(.init(id: a.id.uuidString, title: a.title, kind: a.kind.singular, resolution: a.resolution, palette: a.palette,
                                   tags: a.tags, image: "images/\(stem).jpg", thumb: "thumbs/\(stem).jpg"))
            }
            let manifest = ReviewGallery.Manifest(title: name, created: created, items: items)
            let ok = (try? ReviewGallery.html(manifest).write(to: folder.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)) != nil
            // A zip next to the folder, ready to send.
            let zip = parent.appendingPathComponent(folderName + ".zip")
            try? fm.removeItem(at: zip)
            let proc = Process(); proc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            proc.arguments = ["-c", "-k", "--norsrc", "--keepParent", folder.path, zip.path]
            try? proc.run(); proc.waitUntilExit()
            let zipped = proc.terminationStatus == 0
            await MainActor.run { [items] in
                self.galleryRunning = false
                guard ok, !items.isEmpty else { self.flash("Could not build the gallery"); return }
                self.flash("Gallery ready: \(items.count) assets\(zipped ? ", zipped" : "")")
                if fixedDir == nil { NSWorkspace.shared.activateFileViewerSelecting([zipped ? zip : folder]) }
                else { try? "\(items.count)".write(to: parent.appendingPathComponent("gallery-done.txt"), atomically: true, encoding: .utf8) }
            }
        }
    }

    func importFeedback() {
        let p = NSOpenPanel(); p.allowedContentTypes = [.json]; p.allowsMultipleSelection = true
        p.message = "Choose the feedback file(s) your client downloaded from the review gallery"
        guard p.runModal() == .OK else { return }
        importFeedback(p.urls)
    }

    func importFeedback(_ urls: [URL]) {
        var total = StudioCatalog.FeedbackResult(), reviewers: [String] = [], bad = 0
        for u in urls {
            guard let data = try? Data(contentsOf: u), let f = ReviewGallery.decodeFeedback(data) else { bad += 1; continue }
            var r = StudioCatalog.FeedbackResult()
            mutate { r = $0.applyFeedback(f) }
            total.favorites += r.favorites; total.notes += r.notes; total.unknown += r.unknown
            total.smartCollection = r.smartCollection ?? total.smartCollection
            let who = f.reviewer.trimmingCharacters(in: .whitespaces); if !who.isEmpty && !reviewers.contains(who) { reviewers.append(who) }
        }
        if total.favorites + total.notes == 0 {
            flash(bad > 0 ? "That isn't an ASSSETS review feedback file" : "No favorites or notes in that feedback"); return
        }
        var msg = "\(total.favorites) client \(total.favorites == 1 ? "pick" : "picks"), \(total.notes) \(total.notes == 1 ? "note" : "notes")"
        if !reviewers.isEmpty { msg += " from " + reviewers.joined(separator: ", ") }
        if total.unknown > 0 { msg += " · \(total.unknown) not in this library" }
        flash(msg)
        if let id = total.smartCollection { show(smart: id) }
    }

    var canCompare: Bool { (2...CompareSession.maxAssets).contains(selection.count) }
    func openCompare(_ ids: [UUID]? = nil) {
        guard smartEditor == nil, duplicates == nil, sheetPreview == nil else { return }
        let order = filtered.map(\.id)
        let picked = ids ?? order.filter(selection.contains)
        guard let s = CompareSession(ids: picked) else { flash("Select 2 to 4 assets to compare"); return }
        viewerID = nil; compare = s; compareZoom = ZoomPan(); compareSwipe = false; swipeSplit = 0.5
    }
    /// Done writes the pass (keeps tagged "pick", rejects "rejected"); Esc closes without writing.
    func closeCompare(apply: Bool) {
        guard let s = compare else { return }
        compare = nil
        guard apply, !(s.keeps.isEmpty && s.rejects.isEmpty) else { return }
        let stars = keepRating
        mutate("Compare Pass") { $0.applyPicks(s, keepRating: stars) }
        flash(s.keeps.isEmpty ? "\(s.rejects.count) marked rejected" : "\(s.summary) · kept assets are in Picks")
        if !s.keeps.isEmpty { selection = Set(s.keeps); focusID = s.keeps.first }
    }
    func markCompare(_ v: CompareVerdict) { compare?.mark(v) }
    func stepViewer(_ delta: Int) {
        guard let next = ViewerNav.step(filtered.map(\.id), from: viewerID, by: delta) else { return }
        viewerID = next
        selection = [next]; focusID = next; anchorID = next
    }

    /// Space opens and closes the viewer; arrows browse and Esc closes while it is open. Typing in a field is left alone.
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let handled = MainActor.assumeIsolated { self.handleKey(event) }
            return handled ? nil : event
        }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            let handled = MainActor.assumeIsolated { self.handleScroll(event) }
            return handled ? nil : event
        }
    }

    /// In compare: a mouse wheel (or ⌘-scroll on a trackpad) zooms, two-finger trackpad scrolling pans.
    private func handleScroll(_ e: NSEvent) -> Bool {
        guard compare != nil else { return false }
        let dy = Double(e.scrollingDeltaY), dx = Double(e.scrollingDeltaX)
        if e.hasPreciseScrollingDeltas && !e.modifierFlags.contains(.command) {
            compareZoom.pan(dx: dx / 700, dy: dy / 700)
        } else if dy != 0 {
            compareZoom.zoom(by: pow(1.0035, dy * (e.hasPreciseScrollingDeltas ? 1 : 12)))
        }
        return true
    }

    private func handleKey(_ e: NSEvent) -> Bool {
        guard e.modifierFlags.intersection([.command, .control, .option]).isEmpty, smartEditor == nil, duplicates == nil, sheetPreview == nil, presetExport == nil else { return false }
        if cull != nil {
            if let ch = e.charactersIgnoringModifiers, ch.count == 1, let d = Int(ch), !e.modifierFlags.contains(.shift) {
                if d <= 5 { cullRate(d) } else if let l = ColorLabel.forKey(d) { cullLabel(l) }
                return true
            }
            switch e.keyCode {
            case 7, 51: cullReject()                                                  // X, Delete
            case 124, 125, 49: cull?.step(by: 1)                                       // → ↓ Space
            case 123, 126: cull?.step(by: -1)                                          // ← ↑
            case 0: cull?.autoAdvance.toggle(); flash(cull?.autoAdvance == true ? "Auto-advance on" : "Auto-advance off")  // A
            case 32: cullNextUndecided()                                               // U
            case 53, 36, 76: closeCull()                                               // Esc, Return
            default: break
            }
            return true
        }
        if compare != nil {
            switch e.keyCode {
            case 40: markCompare(.keep); return true                                   // K
            case 7, 51: markCompare(.reject); return true                             // X, Delete
            case 48, 124, 125: compare?.moveFocus(by: e.modifierFlags.contains(.shift) ? -1 : 1); return true   // Tab, → ↓
            case 123, 126: compare?.moveFocus(by: -1); return true                    // ← ↑
            case 1: if compare?.ids.count == 2 { compareSwipe.toggle() }; return true // S
            case 24, 69: compareZoom.zoom(by: 1.5); return true                       // = / keypad +
            case 27, 78: compareZoom.zoom(by: 1 / 1.5); return true                   // - / keypad -
            case 29, 82: compareZoom.reset(); return true                             // 0
            case 36, 76: closeCompare(apply: true); return true                       // Return
            case 53: closeCompare(apply: false); return true                          // Esc
            default: return true
            }
        }
        if viewerID == nil, NSApp.keyWindow?.firstResponder is NSText { return false }
        // 1-5 rate, 0 clears, 6-9 label the selection (or the asset in the viewer).
        if let ch = e.charactersIgnoringModifiers, ch.count == 1, let d = Int(ch), !e.modifierFlags.contains(.shift) {
            let ids: Set<UUID> = viewerID.map { [$0] } ?? selection
            guard !ids.isEmpty else { return false }
            if d <= 5 { rate(ids, d) } else if let l = ColorLabel.forKey(d) { label(ids, l) }
            return true
        }
        switch e.keyCode {
        case 49: if viewerID == nil { openViewer() } else { closeViewer() }; return true
        case 53 where viewerID != nil: closeViewer(); return true
        case 123 where viewerID != nil, 126 where viewerID != nil: stepViewer(-1); return true
        case 124 where viewerID != nil, 125 where viewerID != nil: stepViewer(1); return true
        default: return false
        }
    }
    @Published var fixSeams: Set<UUID> = []
    func tiles(for a: StudioAsset) -> Int { a.kind == .texture ? tileRepeat : 1 }

    func togglePsdLayer(_ index: Int, of id: UUID) {
        var set = psdToggled[id] ?? []
        if set.contains(index) { set.remove(index) } else { set.insert(index) }
        psdToggled[id] = set
    }
    func resetPsdLayers(_ id: UUID) { psdToggled[id] = nil }
    private var anchorID: UUID?

    let supportRoot: URL
    var catalogURL: URL { supportRoot.appendingPathComponent("studio-catalog.json") }
    var legacyURL: URL { supportRoot.appendingPathComponent("studio-library.json") }
    var starterRoot: URL { supportRoot.appendingPathComponent("StarterLibrary", isDirectory: true) }

    init() {
        supportRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ASSSETS", isDirectory: true)
        try? FileManager.default.createDirectory(at: supportRoot, withIntermediateDirectories: true)
        install()
        startWatching()
        refreshAutoTags()
        applyLaunchArguments()
        installKeyMonitor()
    }

    // MARK: Install and upgrade

    private func install() {
        var c = loadCatalog() ?? StudioCatalog()
        let fresh = c.assets.isEmpty
        if let archive = Bundle.main.url(forResource: "StarterLibrary", withExtension: "zip") {
            let fingerprint = Self.fingerprint(of: archive)
            let fm = FileManager.default
            let present = ((try? fm.contentsOfDirectory(atPath: starterRoot.path)) ?? []).filter { !$0.hasPrefix(".") }
            let missing = c.assets.filter { $0.isStarter }.compactMap(\.importedPath).filter { !fm.fileExists(atPath: $0) }.count
            if StudioCatalog.needsExtraction(installedFingerprint: c.starterFingerprint, bundledFingerprint: fingerprint, rootExists: !present.isEmpty, missingFiles: missing) {
                try? fm.createDirectory(at: starterRoot, withIntermediateDirectories: true)
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                task.arguments = ["-x", "-k", archive.path, starterRoot.path]
                try? task.run(); task.waitUntilExit()
            }
            let files = ((try? fm.contentsOfDirectory(atPath: starterRoot.path)) ?? []).filter { !$0.hasPrefix(".") }
            if fresh {
                c.mergeStarter(files: files, root: starterRoot.path, fingerprint: fingerprint)
                c.mergeGenerated()
            } else {
                c.mergeGenerated()
                c.mergeStarter(files: files, root: starterRoot.path, fingerprint: fingerprint)
            }
            enrichStarterMetadata(&c)
            c.seedSmartCollections()
        } else if fresh {
            c.mergeGenerated()
            c.seedSmartCollections()
        }
        enrichStarterMetadata(&c, userFilesOnly: true)
        catalog = c
        save()
        focusID = catalog.assets.first?.id
        selection = focusID.map { [$0] } ?? []
    }

    static func fingerprint(of url: URL) -> String {
        let attrs = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        return "\(version)-\(size)"
    }

    /// Reads real dimensions, durations and vector colors for the bundled files, and for the user's own
    /// imported or watched files that still show "Local file" (1.11: done right away instead of never).
    private func enrichStarterMetadata(_ c: inout StudioCatalog, userFilesOnly: Bool = false) {
        for i in c.assets.indices where userFilesOnly ? c.assets[i].needsFileMetadata : (c.assets[i].isStarter || c.assets[i].needsFileMetadata) {
            let placeholder = c.assets[i].palette == StudioCatalog.placeholderPalette
            guard let path = c.assets[i].importedPath else { continue }
            let url = URL(fileURLWithPath: path)
            switch url.pathExtension.lowercased() {
            case "svg":
                if let text = try? String(contentsOf: url, encoding: .utf8), let scene = VectorScene.parse(text) {
                    let colors = Array(scene.colors.prefix(5))
                    if colors.count >= 3 { c.assets[i].palette = colors }
                    else if placeholder { c.assets[i].palette = ["#1C1F26", "#E9ECF2", "#8B61FF"] }
                    c.assets[i].resolution = "SVG • \(Int(scene.width)) × \(Int(scene.height))"
                }
            case "psd":
                // Read once: on first install, or when the palette is still the collection default (0.6.0 installs).
                let defaultPalette = StarterCatalog.describe(filename: url.lastPathComponent)?.palette
                if !c.assets[i].resolution.hasPrefix("PSD") || c.assets[i].palette == defaultPalette || placeholder,
                   let data = try? Data(contentsOf: url), let doc = try? PsdLayers.read(data) {
                    c.assets[i].resolution = "PSD • \(doc.width) × \(doc.height) • \(doc.panelLayers.count) layers"
                    if !c.assets[i].tags.contains("layered") { c.assets[i].tags.append("layered") }
                    let colors = PsdLayers.palette(of: doc)
                    if colors.count >= 3 { c.assets[i].palette = colors }
                }
            case "wav":
                if let data = try? Data(contentsOf: url), let s = AsssetsCore.Waveform.summarize(wav: data, buckets: 8) {
                    let secs = Int(s.duration.rounded())
                    c.assets[i].resolution = String(format: "WAV • %.1f kHz • %d:%02d", Double(s.sampleRate) / 1000, secs / 60, secs % 60)
                }
            case "png", "jpg", "jpeg", "tif", "tiff":
                if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                   let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
                   let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int {
                    c.assets[i].resolution = "\(w) × \(h)"
                    StudioCatalog.correctResolutionClaims(&c.assets[i], width: w, height: h)
                    // Real swatches instead of the collection default (also fixes 0.7/0.8 installs).
                    if c.assets[i].palette == StarterCatalog.describe(filename: url.lastPathComponent)?.palette || placeholder,
                       let small = MediaRenderer.pixelBuffer(fromSource: src, maxPixel: 160) {
                        let colors = PaletteExtractor.colors(from: small, count: 5).map(\.hex)
                        if colors.count >= 3 { c.assets[i].palette = colors }
                    }
                    // Only claim "seamless" for textures that actually repeat without a seam.
                    if c.assets[i].kind == .texture, let small = MediaRenderer.pixelBuffer(fromSource: src, maxPixel: 512) {
                        let tileable = Seamless.analyze(small).tileable
                        if tileable, !c.assets[i].tags.contains("seamless") { c.assets[i].tags.append("seamless") }
                        if !tileable { c.assets[i].tags.removeAll { $0 == "seamless" } }
                    }
                }
            default: break
            }
        }
    }

    private func loadCatalog() -> StudioCatalog? {
        for url in [catalogURL, legacyURL] {
            if let data = try? Data(contentsOf: url), let c = StudioCatalog.decode(data), !c.assets.isEmpty { return c }
        }
        return nil
    }

    func save() {
        if let data = try? catalog.encoded() { try? data.write(to: catalogURL, options: .atomic) }
    }

    /// Pass a label for edits the user makes; background updates (scans, suggested tags, metadata) stay out of undo.
    func mutate(_ undo: String? = nil, _ change: (inout StudioCatalog) -> Void) {
        let before = undo == nil ? nil : catalog
        change(&catalog)
        if let undo, let before { history.record(undo, before: before, after: catalog) }
        selection = selection.filter { id in catalog.assets.contains { $0.id == id } }
        if let f = focusID, !selection.contains(f) { focusID = selection.first }
        save()
    }

    // MARK: Browsing and selection

    /// Stacks whose versions are all shown in the grid (toggled from the card badge or the inspector).
    @Published var expandedStacks: Set<UUID> = []
    /// Rating and label chips above the grid (1.11).
    @Published var ratingFilter = RatingFilter()
    /// Stars a compare "keep" gives an asset; 0 leaves ratings alone. Remembered between launches.
    @Published var keepRating = UserDefaults.standard.integer(forKey: "compareKeepRating") {
        didSet { UserDefaults.standard.set(keepRating, forKey: "compareKeepRating") }
    }
    /// Files in the current view before stacks collapse, for the header's "4 items · 7 files".
    var filteredFileCount: Int { unstackedFiltered.filter { ratingFilter.matches($0) && (keywordFilter.map($0.tags.contains) ?? true) }.count }
    var filtered: [StudioAsset] {
        let list = unstackedFiltered.filter { ratingFilter.matches($0) && (keywordFilter.map($0.tags.contains) ?? true) }
        if similarTo != nil || (selectedSmart == nil && selectedCollection == Self.missingCollection) { return list }
        return catalog.collapsingStacks(currentSort.apply(list), expanded: expandedStacks)
    }
    private var unstackedFiltered: [StudioAsset] {
        if let target = similarTo {
            let byID = Dictionary(uniqueKeysWithValues: catalog.assets.map { ($0.id, $0) })
            let hits = similarMatches.compactMap { byID[$0.id] }
            let visible = Set(catalog.filtered(search: search, kind: selectedKind, collection: StudioCatalog.allAssets).map(\.id))
            return (byID[target].map { [$0] } ?? []) + hits.filter { visible.contains($0.id) }
        }
        if selectedSmart == nil && selectedCollection == Self.missingCollection {
            return catalog.filtered(search: search, kind: selectedKind, collection: StudioCatalog.allAssets).filter { missing.contains($0.id) }
        }
        if let id = selectedSmart { return catalog.filtered(search: search, kind: selectedKind, smart: id) }
        return catalog.filtered(search: search, kind: selectedKind, collection: selectedCollection)
    }
    var browsingTitle: String {
        if let t = similarTo { return "Similar to " + (catalog.assets.first { $0.id == t }?.title ?? "asset") }
        return selectedSmart.flatMap { catalog.smartCollection($0)?.name } ?? selectedCollection
    }
    var canSaveSearch: Bool { selectedSmart == nil && (!search.trimmingCharacters(in: .whitespaces).isEmpty || selectedKind != nil || ratingFilter.isActive || keywordFilter != nil) }

    // MARK: File metadata and keywords (1.13)

    /// Keywords, title, stars and label that new files already carry (XMP sidecar, embedded XMP, IPTC).
    static func readFileMetadata(_ c: inout StudioCatalog, ids: [UUID]) {
        let set = Set(ids)
        for a in c.assets where set.contains(a.id) {
            guard let p = a.importedPath else { continue }
            c.applyFileMetadata(XmpMetadata.read(path: p), to: a.id)
        }
    }

    /// Writes "<name>.xmp" next to each of the user's files. Existing sidecars keep everything but our four fields.
    func writeMetadata(_ ids: Set<UUID>) {
        let fm = FileManager.default
        var written = 0, skipped = 0, failed = 0
        for a in catalog.assets where ids.contains(a.id) {
            guard !a.isStarter, let p = a.importedPath, fm.fileExists(atPath: p), let m = catalog.fileMetadata(for: a.id) else { skipped += 1; continue }
            let side = XmpMetadata.sidecarPath(for: p)
            let text = (try? String(contentsOfFile: side, encoding: .utf8)).map { XmpMetadata.update($0, with: m) } ?? XmpMetadata.packet(m)
            if (try? text.write(toFile: side, atomically: true, encoding: .utf8)) != nil { written += 1 } else { failed += 1 }
        }
        var msg = written == 0 ? "No sidecars written" : "Wrote \(written) .xmp sidecar\(written == 1 ? "" : "s"). Originals untouched."
        if skipped > 0 { msg += " \(skipped) bundled or missing skipped." }
        if failed > 0 { msg += " \(failed) could not be written." }
        flash(msg)
    }
    var canWriteMetadata: Bool { selectedAssets.contains { !$0.isStarter && $0.importedPath != nil } }

    /// Keyword picked in the sidebar; narrows the grid on top of everything else.
    @Published var keywordFilter: String?
    @Published var renamingKeyword: String?
    func toggleKeywordFilter(_ tag: String) { keywordFilter = keywordFilter == tag ? nil : tag }
    func renameKeyword(_ old: String, to new: String) {
        let target = StudioCatalog.parseTags(new).first ?? ""
        guard !target.isEmpty, target != old else { return }
        let merging = catalog.assets.contains { $0.tags.contains(target) }
        var n = 0
        mutate(merging ? "Merge Keyword" : "Rename Keyword") { n = $0.renameTag(old, to: target) }
        if keywordFilter == old { keywordFilter = target }
        flash(merging ? "Merged \"\(old)\" into \"\(target)\" on \(n) assets" : "Renamed \"\(old)\" to \"\(target)\" on \(n) assets")
    }

    // MARK: Batch rename (1.14)

    struct BatchRenameState: Identifiable {
        let id = UUID()
        var ids: [UUID]
        var pattern = UserDefaults.standard.string(forKey: "renamePattern") ?? RenamePattern.defaultPattern
        var start = 1
    }
    @Published var batchRename: BatchRenameState?
    func openBatchRename(_ ids: [UUID]? = nil) {
        let list = ids ?? filtered.map(\.id).filter(selection.contains)
        guard !list.isEmpty else { flash("Select assets to rename"); return }
        batchRename = BatchRenameState(ids: list)
    }
    /// Titles only, one undo step. Files on disk keep their names; exports pick up the new titles.
    func applyBatchRename(_ st: BatchRenameState) {
        let byID = Dictionary(uniqueKeysWithValues: catalog.assets.map { ($0.id, $0) })
        let rows = RenamePattern.preview(st.pattern, assets: st.ids.compactMap { byID[$0] }, start: st.start)
        UserDefaults.standard.set(st.pattern, forKey: "renamePattern")
        batchRename = nil
        var n = 0
        let titles = Dictionary(uniqueKeysWithValues: rows.filter(\.changed).map { ($0.id, $0.new) })
        guard !titles.isEmpty else { flash("Nothing to rename"); return }
        mutate("Batch Rename") { n = $0.retitle(titles) }
        flash("Renamed \(n) asset\(n == 1 ? "" : "s"). Undo with ⌘Z.")
    }

    // MARK: Undo, sort and cull (1.12)

    @Published var history = UndoHistory()
    func undo() {
        if NSApp.keyWindow?.firstResponder is NSText { NSApp.sendAction(Selector(("undo:")), to: nil, from: nil); return }
        var c = catalog
        guard let label = history.undo(&c) else { return }
        catalog = c; save(); dropMissingSelection()
        flash("Undid \(label)")
    }
    func redo() {
        if NSApp.keyWindow?.firstResponder is NSText { NSApp.sendAction(Selector(("redo:")), to: nil, from: nil); return }
        var c = catalog
        guard let label = history.redo(&c) else { return }
        catalog = c; save(); dropMissingSelection()
        flash("Redid \(label)")
    }
    private func dropMissingSelection() {
        selection = selection.filter { id in catalog.assets.contains { $0.id == id } }
        if let f = focusID, !catalog.assets.contains(where: { $0.id == f }) { focusID = selection.first }
    }

    var sortKey: String { StudioCatalog.sortKey(collection: selectedCollection, smart: selectedSmart) }
    var currentSort: AssetSort { catalog.sort(for: sortKey) }
    func setSort(_ sort: AssetSort) { let k = sortKey; mutate { $0.setSort(sort, for: k) } }

    @Published var cull: CullSession?
    var canCull: Bool { !filtered.isEmpty && compare == nil && smartEditor == nil && sheetPreview == nil && presetExport == nil && batchRename == nil && duplicates == nil }
    func openCull() {
        guard canCull else { return }
        viewerID = nil
        cull = CullSession(ids: filtered.map(\.id), start: focusID)
    }
    func closeCull() {
        guard let s = cull else { return }
        cull = nil
        selection = [s.current]; focusID = s.current
        let p = s.progress(in: catalog)
        flash("Culled \(p.decided) of \(p.total)")
    }
    func cullRate(_ stars: Int) {
        guard let id = cull?.current else { return }
        rate([id], stars)
        if stars > 0 { cull?.didDecide() }
    }
    func cullLabel(_ l: ColorLabel) { if let id = cull?.current { label([id], l) } }
    func cullReject() {
        guard let id = cull?.current else { return }
        var on = false
        mutate("Reject") { on = $0.toggleReject([id]) }
        flash(on ? "Rejected" : "Reject cleared")
        if on { cull?.didDecide() }
    }
    func cullNextUndecided() {
        guard let s = cull else { return }
        if let i = s.nextUndecided(in: catalog) { cull?.index = i } else { flash("Everything here is rated or rejected") }
    }

    // MARK: Ratings and labels (1.11)

    func rate(_ ids: Set<UUID>, _ stars: Int) {
        guard !ids.isEmpty else { return }
        mutate("Rating") { $0.setRating(ids, stars) }
        flash(stars == 0 ? "Rating cleared" : "Rated \(String(repeating: "★", count: stars))\(ids.count > 1 ? " · \(ids.count) assets" : "")")
    }
    func label(_ ids: Set<UUID>, _ l: ColorLabel?) {
        guard !ids.isEmpty else { return }
        var now: ColorLabel?
        mutate("Label") { now = $0.toggleLabel(ids, l) }
        flash(now.map { "\($0.name) label" } ?? "Label cleared")
    }
    func toggleLabelFilter(_ l: ColorLabel) {
        if ratingFilter.labels.contains(l) { ratingFilter.labels.remove(l) } else { ratingFilter.labels.insert(l) }
    }
    var focused: StudioAsset? { focusID.flatMap { id in catalog.assets.first { $0.id == id } } }
    var selectedAssets: [StudioAsset] { catalog.assets.filter { selection.contains($0.id) } }

    // MARK: Version stacks (1.10)

    /// Selection plus every hidden version behind a collapsed stack card.
    func withStackMembers(_ ids: Set<UUID>) -> Set<UUID> {
        var out = ids
        for a in catalog.assets where ids.contains(a.id) { if let s = a.stackID { for b in catalog.assets where b.stackID == s { out.insert(b.id) } } }
        return out
    }
    var canStack: Bool { selection.count >= 2 }
    var canUnstack: Bool { selectedAssets.contains { $0.stackID != nil } }
    func stackSelection() {
        let ids = withStackMembers(selection)
        var sid: UUID?
        mutate("Stack") { sid = $0.stack(ids) }
        guard let sid else { return }
        let top = catalog.stackTop(ids.first!)
        expandedStacks.remove(sid)
        if let top { selection = [top.id]; focusID = top.id }
        flash("Stacked \(ids.count) versions")
    }
    func unstackSelection() {
        let ids = withStackMembers(selection)
        mutate("Unstack") { $0.unstack(ids) }
        selection = ids; focusID = focusID ?? ids.first
        flash("Unstacked \(ids.count) assets")
    }
    func unstack(_ ids: Set<UUID>) {
        mutate("Unstack") { $0.unstack(ids) }
        flash(ids.count == 1 ? "Removed from stack" : "Unstacked \(ids.count) assets")
    }
    func toggleStackExpanded(_ asset: StudioAsset) {
        guard let s = asset.stackID else { return }
        if expandedStacks.contains(s) { expandedStacks.remove(s) } else { expandedStacks.insert(s) }
    }
    /// Groups new files by version name; runs after imports and watch-folder scans.
    func autoStackNew() {
        var c = catalog
        if c.autoStack() > 0 { mutate { $0 = c } }
    }
    func compareVersions(_ a: UUID, _ b: UUID) {
        let order = catalog.versions(of: a).map(\.id)
        let pair = order.filter { $0 == a || $0 == b }
        openCompare(pair.count == 2 ? pair : [a, b])
    }

    func show(collection: String) { similarTo = nil; selectedCollection = collection; selectedSmart = nil; anchorID = nil }
    func show(smart id: UUID) { similarTo = nil; selectedSmart = id; selectedCollection = StudioCatalog.allAssets; anchorID = nil }

    // MARK: Watch folders and missing files (1.2)

    static let missingCollection = "Missing Files"
    @Published var missing: Set<UUID> = []
    private var watchTimer: Timer?

    private func startWatching() {
        scanWatchFolders()
        watchTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.scanWatchFolders() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.scanWatchFolders()
        }
    }

    /// Lists supported-looking files under each watch folder (hidden files and package contents skipped,
    /// 4 levels deep, 5,000 files per folder), imports the new ones and refreshes missing-file flags.
    func scanWatchFolders() {
        let fm = FileManager.default
        var found: [String] = []
        for folder in catalog.watchFolders {
            guard let e = fm.enumerator(at: URL(fileURLWithPath: folder, isDirectory: true), includingPropertiesForKeys: [.isRegularFileKey],
                                        options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            var n = 0
            for case let url as URL in e {
                if e.level > 4 { e.skipDescendants(); continue }
                guard MediaKind.classify(extension: url.pathExtension) != nil else { continue }
                found.append(url.standardizedFileURL.path); n += 1
                if n >= 5000 { break }
            }
        }
        var added: [UUID] = []
        if !found.isEmpty {
            var c = catalog
            added = c.syncWatch(found: found)
            if !added.isEmpty { enrichStarterMetadata(&c, userFilesOnly: true); Self.readFileMetadata(&c, ids: added); c.autoStack(); mutate { $0 = c }; refreshAutoTags() }
        }
        let now = catalog.missingIDs { fm.fileExists(atPath: $0) }
        if now != missing { missing = now }
        if !added.isEmpty { flash("\(added.count) new \(added.count == 1 ? "file" : "files") in Inbox") }
    }

    func addWatchFolder() {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.allowsMultipleSelection = true
        p.prompt = "Watch"; p.message = "New images, PSDs, vectors, footage and audio in these folders will appear in Inbox."
        guard p.runModal() == .OK else { return }
        watch(p.urls.map(\.standardizedFileURL.path))
    }

    func watch(_ paths: [String]) {
        var changed = false
        mutate { c in for path in paths { if c.addWatchFolder(path) { changed = true } } }
        scanWatchFolders()   // also when the folder was already watched, so its newest files show up now
        if changed { show(collection: StudioCatalog.inboxCollection) } else { flash("Already watching that folder - rescanned it") }
    }

    func stopWatching(_ folder: String) {
        mutate { $0.removeWatchFolder(folder) }
        flash("Stopped watching \((folder as NSString).lastPathComponent). Its assets stay in the library.")
    }

    func watchedCount(_ folder: String) -> Int { catalog.assets.filter { $0.importedPath?.hasPrefix(folder + "/") == true }.count }

    /// Point a missing asset at its new location. Keeps title, tags, collection and favorite.
    func locate(_ id: UUID) {
        guard let a = catalog.assets.first(where: { $0.id == id }) else { return }
        let p = NSOpenPanel(); p.canChooseFiles = true; p.canChooseDirectories = false; p.prompt = "Use This File"
        p.message = "Locate \"\(a.title)\""
        if let ext = a.importedPath.map({ URL(fileURLWithPath: $0).pathExtension }), let t = UTType(filenameExtension: ext) { p.allowedContentTypes = [t] }
        guard p.runModal() == .OK, let url = p.url else { return }
        let path = url.standardizedFileURL.path
        if catalog.assets.contains(where: { $0.importedPath == path && $0.id != id }) { flash("That file is already in the library"); return }
        mutate { c in if let i = c.assets.firstIndex(where: { $0.id == id }) { c.assets[i].importedPath = path } }
        missing.remove(id)
        flash("Relinked \(a.title)")
    }

    func removeMissing() {
        let ids = missing
        guard !ids.isEmpty else { return }
        pendingRemoval = ids
    }

    // MARK: Duplicates and sharing (1.3)

    @Published var duplicates: DuplicateScan?

    /// Sizes every real file, hashes only same-size candidates (SHA-256, streamed) off the main thread,
    /// then shows groups of identical files.
    func findDuplicates(nearToo: Bool = false) {
        scanWatchFolders()   // results should include files that landed in watch folders a moment ago
        let order = catalog.assets.map(\.id)
        let paths = Dictionary(uniqueKeysWithValues: catalog.assets.compactMap { a in a.importedPath.map { (a.id, $0) } })
        duplicates = DuplicateScan(scanning: true, near: nearToo)
        Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            var sizes: [UUID: Int64] = [:]
            for (id, p) in paths { if let n = (try? fm.attributesOfItem(atPath: p))?[.size] as? NSNumber { sizes[id] = n.int64Value } }
            let candidates = Duplicates.needsHash(sizes: sizes)
            var hashes: [UUID: String] = [:]
            for id in candidates { if let p = paths[id], let h = Self.sha256(path: p) { hashes[id] = "\(sizes[id] ?? 0)-\(h)" } }
            let exact = Duplicates.groups(hashes: hashes, order: order)
            let checked = sizes.count
            await MainActor.run {
                guard self.duplicates != nil else { return }
                self.duplicates = DuplicateScan(scanning: nearToo, groups: exact, checked: checked, near: nearToo)
            }
            guard nearToo else { return }
            let looks = await self.lookHashes()
            await MainActor.run {
                guard self.duplicates?.near == true else { return }
                var groups = Similarity.nearGroups(hashes: looks, order: order)
                let covered = Set(groups.flatMap { $0 })
                groups += exact.filter { g in g.allSatisfy { !covered.contains($0) } }
                self.duplicates = DuplicateScan(scanning: false, groups: groups, checked: checked, near: true)
            }
        }
    }

    // MARK: Contact sheets and brand kits (1.5)

    @Published var sheetPreview: SheetPreview?

    func openContactSheetForCurrentView() {
        if selection.count > 1 { openContactSheet(ids: selectedAssets.map(\.id), title: "\(selection.count) Selected Assets") }
        else { openContactSheet(ids: filtered.map(\.id), title: browsingTitle) }
    }

    /// Renders the PDF to a temp file and opens the preview sheet; saving happens from there.
    func openContactSheet(ids: [UUID], title: String) {
        let byID = Dictionary(uniqueKeysWithValues: catalog.assets.map { ($0.id, $0) })
        let assets = ids.compactMap { byID[$0] }
        guard !assets.isEmpty else { flash("Nothing to put on a contact sheet"); return }
        flash("Laying out \(assets.count) assets…")
        Task { @MainActor in
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ASSSETS-sheet/\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(DragOut.safeName(title + " Contact Sheet") + ".pdf")
            let ok = await ContactSheetRenderer.render(title: title, assets: assets, to: url)
            guard ok else { flash("Could not render the contact sheet"); return }
            sheetPreview = SheetPreview(title: title, ids: assets.map(\.id), pdf: url)
        }
    }

    func saveContactSheet(_ p: SheetPreview) {
        let s = NSSavePanel(); s.nameFieldStringValue = p.pdf.lastPathComponent; s.allowedContentTypes = [.pdf]; s.canCreateDirectories = true
        guard s.runModal() == .OK, let dst = s.url else { return }
        try? FileManager.default.removeItem(at: dst)
        if (try? FileManager.default.copyItem(at: p.pdf, to: dst)) != nil { flash("Saved \(dst.lastPathComponent)"); NSWorkspace.shared.activateFileViewerSelecting([dst]) }
        else { flash("Could not save the PDF") }
    }

    /// One zip: the contact sheet, the files, and the combined palette as .ase and .json swatches.
    @discardableResult
    func buildBrandKit(_ p: SheetPreview, mode: DragOut.ExportMode, to zip: URL) -> Bool {
        let fm = FileManager.default
        let name = BrandKit.kitName(p.title)
        let stage = fm.temporaryDirectory.appendingPathComponent("ASSSETS-kit/\(UUID().uuidString)/\(name)", isDirectory: true)
        let files = stage.appendingPathComponent("Files", isDirectory: true)
        try? fm.createDirectory(at: files, withIntermediateDirectories: true)
        try? fm.copyItem(at: p.pdf, to: stage.appendingPathComponent("Contact Sheet.pdf"))
        let assets = p.ids.compactMap { id in catalog.assets.first { $0.id == id } }
        var taken = Set<String>()
        for a in assets { if let u = write(a, mode: mode, into: files, taken: taken, copy: true) { taken.insert(u.lastPathComponent) } }
        let palette = BrandKit.combinedPalette(assets.map(\.palette))
        let swatches = palette.enumerated().map { BrandKit.Swatch(name: "\(p.title) \($0.offset + 1)", hex: $0.element) }
        try? BrandKit.ase(swatches).write(to: stage.appendingPathComponent("Palette.ase"))
        try? BrandKit.swatchJSON(title: p.title, swatches).write(to: stage.appendingPathComponent("Palette.json"))
        try? fm.removeItem(at: zip)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        task.arguments = ["-c", "-k", "--norsrc", "--keepParent", stage.path, zip.path]
        do { try task.run(); task.waitUntilExit() } catch { return false }
        try? fm.removeItem(at: stage.deletingLastPathComponent())
        return task.terminationStatus == 0 && fm.fileExists(atPath: zip.path)
    }

    func saveBrandKit(_ p: SheetPreview, mode: DragOut.ExportMode) {
        let s = NSSavePanel(); s.nameFieldStringValue = BrandKit.kitName(p.title) + ".zip"; s.allowedContentTypes = [.zip]; s.canCreateDirectories = true
        guard s.runModal() == .OK, let dst = s.url else { return }
        if buildBrandKit(p, mode: mode, to: dst) { flash("Saved \(dst.lastPathComponent)"); NSWorkspace.shared.activateFileViewerSelecting([dst]) }
        else { flash("Could not build the brand kit") }
    }

    // MARK: Find similar (1.4)

    @Published var similarTo: UUID?
    @Published var similarMatches: [Similarity.Match] = []
    @Published var looksReady = false
    private var lookCache: [String: UInt64] = [:]

    private func lookKey(_ a: StudioAsset) -> String { a.id.uuidString + "|" + (a.importedPath ?? "") }

    /// Perceptual hashes for every visual asset, cached by asset and path. Files render off the main thread.
    func lookHashes() async -> [UUID: UInt64] {
        let todo = catalog.assets.filter { $0.kind != .audio && lookCache[lookKey($0)] == nil && !missing.contains($0.id) }
        for a in todo {
            let key = lookKey(a)
            if a.importedPath == nil {
                if let cg = MediaRenderer.generated(a, width: 96), let px = MediaRenderer.pixelBuffer(from: cg, maxPixel: 64) { lookCache[key] = Similarity.dHash(px) }
                await Task.yield()
            } else {
                let snap = a
                let hash: UInt64? = await Task.detached(priority: .userInitiated) {
                    guard let cg = await MediaRenderer.thumbnail(for: snap, maxPixel: 96), let px = MediaRenderer.pixelBuffer(from: cg, maxPixel: 64) else { return nil }
                    return Similarity.dHash(px)
                }.value
                if let hash { lookCache[key] = hash }
            }
        }
        looksReady = true
        var out: [UUID: UInt64] = [:]
        for a in catalog.assets { if let h = lookCache[lookKey(a)] { out[a.id] = h } }
        return out
    }

    func matches(for id: UUID, limit: Int = 24) -> [Similarity.Match] {
        guard let a = catalog.assets.first(where: { $0.id == id }) else { return [] }
        let target = Similarity.Signature(hash: lookCache[lookKey(a)], palette: a.palette)
        let others = catalog.assets.filter { $0.id != id && $0.kind != .audio }.map { ($0.id, Similarity.Signature(hash: lookCache[lookKey($0)], palette: $0.palette)) }
        return Similarity.rank(target, among: others, limit: limit)
    }

    /// Shows the library ranked by likeness to one asset: near copies first, then the same structure and mood.
    func findSimilar(_ id: UUID) {
        guard let a = catalog.assets.first(where: { $0.id == id }), a.kind != .audio else { flash("Find Similar works on images, vectors, mockups, textures and footage"); return }
        flash("Comparing looks…")
        Task { @MainActor in
            _ = await lookHashes()
            similarMatches = matches(for: id)
            similarTo = id
            selectedSmart = nil; selectedCollection = StudioCatalog.allAssets
            selection = [id]; focusID = id; anchorID = id
            let near = similarMatches.filter(\.nearDuplicate).count
            flash(near > 0 ? "\(near) near \(near == 1 ? "copy" : "copies") and \(similarMatches.count - near) look-alikes" : "\(similarMatches.count) look-alikes")
        }
    }

    func similarScore(_ id: UUID) -> Similarity.Match? { similarTo == nil ? nil : similarMatches.first { $0.id == id } }

    nonisolated static func sha256(path: String) -> String? {
        guard let h = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? h.close() }
        var hasher = SHA256()
        while let chunk = try? h.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    func keep(_ keeper: UUID, in group: [UUID]) {
        var removed = 0
        mutate("Merge Duplicates") { removed = $0.mergeDuplicates(keep: keeper, remove: Set(group)) }
        duplicates?.groups.removeAll { $0.contains(keeper) }
        flash("Kept 1, removed \(removed) duplicate\(removed == 1 ? "" : "s"). Files on disk are untouched.")
    }

    func keepSuggestedForAll() {
        guard let groups = duplicates?.groups else { return }
        var removed = 0
        mutate("Merge Duplicates") { c in
            for g in groups {
                let members = g.compactMap { id in c.assets.first { $0.id == id } }
                if let k = Duplicates.suggestedKeeper(members) { removed += c.mergeDuplicates(keep: k, remove: Set(g)) }
            }
        }
        duplicates?.groups = []
        flash("Removed \(removed) duplicates from the library. Files on disk are untouched.")
    }

    /// System share menu (AirDrop, Mail, Messages, Notes...) with the same files a drag-out would give.
    func share(_ ids: Set<UUID>, anchor: NSView? = nil) {
        let urls = dragFiles(for: ids)
        guard !urls.isEmpty else { flash("Nothing to share"); return }
        let picker = NSSharingServicePicker(items: urls)
        if let anchor {
            picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        } else if let view = NSApp.keyWindow?.contentView, let window = view.window {
            let p = view.convert(window.mouseLocationOutsideOfEventStream, from: nil)
            picker.show(relativeTo: NSRect(x: p.x, y: p.y, width: 1, height: 1), of: view, preferredEdge: .minY)
        }
    }

    // MARK: Smart collections

    func beginNewSmart() {
        var rules = SmartRules(text: search, kinds: selectedKind.map { [$0] } ?? [])
        ratingFilter.apply(to: &rules)
        if let k = keywordFilter, !rules.requiredTags.contains(k) { rules.requiredTags.append(k) }
        if selectedCollection == StudioCatalog.favorites { rules.favoritesOnly = true }
        else if selectedCollection != StudioCatalog.allAssets { rules.collection = selectedCollection }
        let t = search.trimmingCharacters(in: .whitespaces)
        smartEditor = SmartEditorState(existing: nil, name: t.isEmpty ? (selectedKind?.rawValue ?? (ratingFilter.minRating > 0 ? "\(ratingFilter.minRating) Stars and Up" : "Smart Collection")) : t.capitalized, rules: rules)
    }
    func beginEdit(smart id: UUID) {
        guard let s = catalog.smartCollection(id) else { return }
        smartEditor = SmartEditorState(existing: id, name: s.name, rules: s.rules)
    }
    func commit(_ state: SmartEditorState) {
        var rules = state.rules
        rules.requiredTags = StudioCatalog.parseTags(rules.requiredTags.joined(separator: ","))
        if let id = state.existing {
            mutate { $0.updateSmartCollection(id, name: state.name, rules: rules) }
            flash("Updated \(catalog.smartCollection(id)?.name ?? "smart collection")")
        } else {
            var id = UUID()
            mutate { id = $0.createSmartCollection(named: state.name, rules: rules) }
            search = ""; selectedKind = nil; ratingFilter = RatingFilter(); keywordFilter = nil
            show(smart: id)
            flash("Saved smart collection \(catalog.smartCollection(id)?.name ?? "")")
        }
        smartEditor = nil
    }
    func deleteSmart(_ id: UUID) {
        let name = catalog.smartCollection(id)?.name ?? ""
        mutate { $0.deleteSmartCollection(id) }
        if selectedSmart == id { show(collection: StudioCatalog.allAssets) }
        smartEditor = nil
        flash("Deleted smart collection \(name). No assets were changed.")
    }

    func click(_ id: UUID) {
        let flags = NSEvent.modifierFlags
        let visible = filtered.map(\.id)
        if flags.contains(.command) {
            if selection.contains(id) {
                selection.remove(id)
                if focusID == id { focusID = visible.first { selection.contains($0) } }
            } else { selection.insert(id); focusID = id }
            anchorID = id
        } else if flags.contains(.shift), let anchor = anchorID ?? focusID, let a = visible.firstIndex(of: anchor), let b = visible.firstIndex(of: id) {
            selection = Set(visible[min(a, b)...max(a, b)])
            focusID = id
        } else {
            selection = [id]; focusID = id; anchorID = id
        }
    }

    func selectAllVisible() { let ids = filtered.map(\.id); selection = Set(ids); if focusID == nil || !selection.contains(focusID!) { focusID = ids.first } }
    func clearSelection() { selection = []; focusID = nil; anchorID = nil }

    /// Right-click acts on the whole selection when the clicked card is part of it.
    func targets(for id: UUID) -> Set<UUID> { selection.contains(id) ? selection : [id] }

    // MARK: Edits

    func toggleFavorite(_ ids: Set<UUID>) { guard !ids.isEmpty else { return }; mutate("Favorite") { $0.toggleFavorite(ids) } }
    func addTags(_ raw: String, to ids: Set<UUID>) {
        var n = 0
        mutate("Add Tags") { n = $0.addTags(raw, to: ids) }
        if n > 1 { flash("Tagged \(n) assets") }
    }
    func removeTag(_ tag: String, from ids: Set<UUID>) { mutate("Remove Tag") { $0.removeTag(tag, from: ids) } }
    func removeClientNote(_ n: ClientNote, from id: UUID) {
        mutate("Remove Note") { c in if let i = c.assets.firstIndex(where: { $0.id == id }) { c.assets[i].clientNotes.removeAll { $0 == n } } }
    }
    func acceptSuggestions(_ tags: [String]? = nil, for ids: Set<UUID>) {
        let n = catalog.assets.filter { ids.contains($0.id) }.reduce(0) { sum, a in sum + (tags.map { t in t.filter(a.suggestedTags.contains).count } ?? a.suggestedTags.count) }
        guard n > 0 else { return }
        mutate("Accept Suggestions") { $0.acceptSuggestions(tags, for: ids) }
        if tags == nil || n > 1 { flash("Accepted \(n) suggested \(n == 1 ? "tag" : "tags")") }
    }
    func rejectSuggestion(_ tag: String, for ids: Set<UUID>) { mutate { $0.rejectSuggestion(tag, for: ids) } }

    /// Reads local facts for assets that have no suggestions yet and stores the suggestions.
    /// Runs off the main thread; nothing leaves the Mac.
    func refreshAutoTags(force: Bool = false) {
        let todo = catalog.assets.filter { force || $0.autoTags.isEmpty }
        guard !todo.isEmpty else { return }
        Task.detached(priority: .utility) {
            var results: [(UUID, [String])] = []
            for a in todo { results.append((a.id, AutoTags.suggest(await AutoTagReader.facts(for: a)))) }
            await MainActor.run { [results] in
                var changed = false
                var c = self.catalog
                for (id, tags) in results where c.setAutoTags(tags, for: id) { changed = true }
                if changed { self.mutate { $0 = c } }
            }
        }
    }
    func move(_ ids: Set<UUID>, to collection: String) {
        var n = 0
        mutate("Move") { n = $0.move(ids, to: collection) }
        if n > 0 { flash(collection == StudioCatalog.favorites ? "Added \(n) to Favorites" : "Moved \(n) to \(collection)") }
    }
    func newCollection(with ids: Set<UUID>) {
        var name = ""
        mutate { name = $0.createCollection() }
        if !ids.isEmpty { move(ids, to: name) }
        renamingCollection = name
    }
    func rename(_ old: String, to new: String) {
        var ok = false
        mutate { ok = $0.renameCollection(old, to: new) }
        if ok, selectedCollection == old { selectedCollection = new.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    func confirmRemoval() {
        let ids = pendingRemoval
        pendingRemoval = []
        var n = 0
        mutate("Remove from Library") { n = $0.remove(ids) }
        if n > 0 { flash("Removed \(n) from library. Files on disk were not touched.") }
    }

    static let dragPrefix = "asssets-ids:"
    func dragPayload(for id: UUID) -> String { Self.dragPrefix + targets(for: id).map(\.uuidString).joined(separator: ",") }

    /// One drag carries both: the asset IDs for dropping on a sidebar collection (visible only inside ASSSETS)
    /// and a real file for Finder, Keynote, Figma and the like - the original, or a PNG of what the preview shows.
    func dragProvider(for asset: StudioAsset) -> NSItemProvider {
        let provider: NSItemProvider
        if let url = dragFile(for: asset), let p = NSItemProvider(contentsOf: url) {
            provider = p
            provider.suggestedName = url.deletingPathExtension().lastPathComponent
        } else {
            provider = NSItemProvider()
        }
        let payload = Data(dragPayload(for: asset.id).utf8)
        provider.registerDataRepresentation(forTypeIdentifier: UTType.asssetsSelection.identifier, visibility: .ownProcess) { done in
            done(payload, nil); return nil
        }
        return provider
    }

    func look(for a: StudioAsset) -> DragOut.Look {
        DragOut.Look(effectApplied: effect != .original, psdLayersChanged: !(psdToggled[a.id] ?? []).isEmpty,
                     tiled: tiles(for: a) > 1, seamsFixed: fixSeams.contains(a.id))
    }

    func dragFile(for a: StudioAsset) -> URL? {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ASSSETS-drag/\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return write(a, mode: .asShown, into: dir, taken: [], copy: false)
    }

    /// Files for a multi-asset drag, all in one fresh temp folder so names never collide.
    func dragFiles(for ids: Set<UUID>) -> [URL] {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ASSSETS-drag/\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var taken = Set<String>(); var out: [URL] = []
        for a in catalog.assets where ids.contains(a.id) {
            if let u = write(a, mode: .asShown, into: dir, taken: taken, copy: false) { taken.insert(u.lastPathComponent); out.append(u) }
        }
        return out
    }

    /// Produces one asset's file: the original (returned in place, or copied into `dir` when `copy`), or a rendered PNG in `dir`.
    func write(_ a: StudioAsset, mode: DragOut.ExportMode, into dir: URL, taken: Set<String>, copy: Bool) -> URL? {
        let exists = a.importedPath.map { FileManager.default.fileExists(atPath: $0) } ?? false
        switch DragOut.exportPlan(mode: mode, title: a.title, importedPath: a.importedPath, fileExists: exists, look: look(for: a)) {
        case .file(let path):
            let src = URL(fileURLWithPath: path)
            let original = copy || taken.contains(src.lastPathComponent)
            if !original { return src }
            let name = DragOut.uniqueName(DragOut.safeName(a.title) + (src.pathExtension.isEmpty ? "" : "." + src.pathExtension), taken: taken)
            let dst = dir.appendingPathComponent(name)
            return (try? FileManager.default.copyItem(at: src, to: dst)) != nil ? dst : nil
        case .render(let name):
            guard a.kind != .audio else { return nil }
            let url = dir.appendingPathComponent(DragOut.uniqueName(name, taken: taken))
            return MediaRenderer.exportPNG(a, effect: effect, amount: intensity, psdToggled: psdToggled[a.id] ?? [],
                                           tiles: tiles(for: a), fixSeams: fixSeams.contains(a.id), to: url) ? url : nil
        }
    }

    /// Export to a folder the user picks. Never overwrites: clashes get "Name 2.png" like Finder.
    func exportToFolder(_ ids: Set<UUID>, mode: DragOut.ExportMode) {
        let picked = catalog.assets.filter { ids.contains($0.id) }
        guard !picked.isEmpty else { return }
        if picked.count == 1, let a = picked.first {
            // One asset: a save panel with the planned name, same rules as the folder export.
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("ASSSETS-export/\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            guard let made = write(a, mode: mode, into: tmp, taken: [], copy: true) else { flash("Nothing to export for \(a.title)"); return }
            let s = NSSavePanel(); s.nameFieldStringValue = made.lastPathComponent; s.canCreateDirectories = true
            if let t = UTType(filenameExtension: made.pathExtension) { s.allowedContentTypes = [t] }
            guard s.runModal() == .OK, let dst = s.url else { return }
            try? FileManager.default.removeItem(at: dst)
            let ok = (try? FileManager.default.moveItem(at: made, to: dst)) != nil
            flash(ok ? "Exported \(dst.lastPathComponent)" : "Export failed")
            if ok { NSWorkspace.shared.activateFileViewerSelecting([dst]) }
            return
        }
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
        p.prompt = "Export Here"
        p.message = mode == .originals ? "Export \(picked.count) original files (generated studies export as PNG)"
                                       : "Export \(picked.count) assets as shown (original file when unchanged, PNG otherwise)"
        guard p.runModal() == .OK, let dir = p.url else { return }
        var taken = Set((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
        var written: [URL] = []
        for a in picked {
            if let u = write(a, mode: mode, into: dir, taken: taken, copy: true) { taken.insert(u.lastPathComponent); written.append(u) }
        }
        flash(written.count == picked.count ? "Exported \(written.count) files" : "Exported \(written.count) of \(picked.count) files")
        if !written.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(written) }
    }

    var canReveal: Bool { selectedAssets.contains { $0.importedPath != nil } }

    func dropSelection(_ providers: [NSItemProvider], on collection: String) -> Bool {
        guard let p = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.asssetsSelection.identifier) }) else { return false }
        _ = p.loadDataRepresentation(forTypeIdentifier: UTType.asssetsSelection.identifier) { data, _ in
            guard let data, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { self.drop([text], on: collection) }
        }
        return true
    }
    @discardableResult
    func drop(_ items: [String], on collection: String) -> Bool {
        let ids = Set(items.filter { $0.hasPrefix(Self.dragPrefix) }.flatMap { $0.dropFirst(Self.dragPrefix.count).split(separator: ",") }.compactMap { UUID(uuidString: String($0)) })
        guard !ids.isEmpty, collection != StudioCatalog.allAssets else { return false }
        move(ids, to: collection)
        return true
    }

    func flash(_ message: String) {
        toast = message
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            if self.toast == message { self.toast = nil }
        }
    }

    // MARK: Files

    func importFiles() {
        let p = NSOpenPanel(); p.allowsMultipleSelection = true; p.canChooseDirectories = true; p.canChooseFiles = true
        guard p.runModal() == .OK else { return }
        var added: [UUID] = []
        mutate { c in
            for url in p.urls {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue,
                   let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey]) {
                    for case let file as URL in e { if let id = c.importFile(path: file.path) { added.append(id) } }
                } else if let id = c.importFile(path: url.path) { added.append(id) }
            }
            if !added.isEmpty { enrichStarterMetadata(&c, userFilesOnly: true); Self.readFileMetadata(&c, ids: added); c.autoStack() }
        }
        if !added.isEmpty { refreshAutoTags(); show(collection: StudioCatalog.importedCollection); selection = Set(added); focusID = added.first; flash("Imported \(added.count) files") }
        else { flash("No new supported files found") }
    }

    func reveal(_ ids: Set<UUID>) {
        let urls = catalog.assets.filter { ids.contains($0.id) }.compactMap(\.importedPath).map { URL(fileURLWithPath: $0) }
        if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    }
    func open(_ asset: StudioAsset) { if let p = asset.importedPath { NSWorkspace.shared.open(URL(fileURLWithPath: p)) } }
    func copyKeywords(_ ids: Set<UUID>) {
        var tags: [String] = []
        for a in catalog.assets where ids.contains(a.id) { for t in a.tags where !tags.contains(t) { tags.append(t) } }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(tags.joined(separator: ", "), forType: .string)
        flash("Copied \(tags.count) keywords")
    }

    // MARK: Screenshot harness (CI launches the app with these arguments)

    private func applyLaunchArguments() {
        let args = ProcessInfo.processInfo.arguments
        func value(_ flag: String) -> String? { args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
        let demo = value("-asssets-demo")
        if demo != nil { UserDefaults.standard.set(demo == "watch" ? "MEDIA|SMART COLLECTIONS" : demo == "keywords" ? "COLLECTIONS|SMART COLLECTIONS" : "", forKey: SidebarSections.key) }
        switch demo {
        case "batch":
            show(collection: "Material Textures")
            let ids = filtered.prefix(4).map(\.id)
            selection = Set(ids); focusID = ids.first
        case "media":
            search = "bundled"
            if let v = filtered.first(where: { $0.kind == .texture }) { selection = [v.id]; focusID = v.id }
            effect = .warm; intensity = 0.8
        case "psd":
            show(collection: "Device Mockups")
            search = "layered"
            if let a = filtered.first(where: { $0.importedPath?.hasSuffix("phone-screen-mockup.psd") == true }) ?? filtered.first {
                selection = [a.id]; focusID = a.id
                if let p = a.importedPath, let data = try? Data(contentsOf: URL(fileURLWithPath: p)), let doc = try? PsdLayers.read(data) {
                    // Swap to the alternate backdrop and switch the glare off, like a user would.
                    let flips = doc.layers.indices.filter { doc.layers[$0].hidden || doc.layers[$0].name == "Screen Glare" }
                    psdToggled[a.id] = Set(flips)
                }
            }
        case "smart":
            if let s = catalog.smartCollections.first(where: { $0.name == "Warm Palettes" }) {
                show(smart: s.id)
                if let a = filtered.first(where: { $0.isStarter }) ?? filtered.first { selection = [a.id]; focusID = a.id }
            }
        case "smart-editor":
            if let s = catalog.smartCollections.first(where: { $0.name == "Cool Palettes" }) {
                show(smart: s.id)
                if let a = filtered.first { selection = [a.id]; focusID = a.id }
                var rules = s.rules; rules.kinds = [.texture, .vector, .video]; rules.requiredTags = ["original"]
                smartEditor = SmartEditorState(existing: s.id, name: "Cool Brand Kit", rules: rules)
            }
        case "viewer":
            show(collection: "Device Mockups")
            if let a = filtered.first(where: { $0.importedPath?.hasSuffix("laptop-screen-mockup.psd") == true }) ?? filtered.first {
                selection = [a.id]; focusID = a.id; viewerID = a.id
            }
        case "textures", "seam-fix":
            show(collection: "Material Textures")
            let file = demo == "textures" ? "terrazzo-texture.png" : "night-grid-4k.png"
            if let a = filtered.first(where: { $0.importedPath?.hasSuffix(file) == true }) ?? filtered.first {
                selection = [a.id]; focusID = a.id
                tileRepeat = demo == "textures" ? 3 : 2
                if demo == "seam-fix" { fixSeams.insert(a.id) }
            }
        case "watch":
            // A client drop folder with real files; one gets deleted to show the missing-file flag.
            let fm = FileManager.default
            let drop = fm.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Client Drops", isDirectory: true)
            try? fm.removeItem(at: drop)
            try? fm.createDirectory(at: drop.appendingPathComponent("Round 2"), withIntermediateDirectories: true)
            let picks: [(String, String)] = [("terrazzo-texture.png", "Lobby Floor Reference.png"), ("phone-screen-mockup.psd", "Round 2/App Store Hero.psd"),
                                             ("night-grid-4k.png", "Keynote Backdrop.png"), ("coffee-cup-mockup.psd", "Cafe Menu Cup.psd")]
            for (src, dst) in picks where fm.fileExists(atPath: starterRoot.appendingPathComponent(src).path) {
                try? fm.copyItem(at: starterRoot.appendingPathComponent(src), to: drop.appendingPathComponent(dst))
            }
            if let svg = ((try? fm.contentsOfDirectory(atPath: starterRoot.path)) ?? []).sorted().first(where: { $0.hasSuffix(".svg") }) {
                try? fm.copyItem(at: starterRoot.appendingPathComponent(svg), to: drop.appendingPathComponent("Brand Mark v3.svg"))
            }
            watch([drop.path])
            try? fm.removeItem(at: drop.appendingPathComponent("Keynote Backdrop.png"))
            scanWatchFolders()
            show(collection: StudioCatalog.inboxCollection)
            if let a = filtered.first(where: { missing.contains($0.id) }) { selection = [a.id]; focusID = a.id }
        case "duplicates":
            // A drop folder holding a copy of a bundled texture and the same PSD twice.
            let fm = FileManager.default
            let drop = fm.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Client Drops", isDirectory: true)
            try? fm.removeItem(at: drop)
            try? fm.createDirectory(at: drop.appendingPathComponent("Round 2"), withIntermediateDirectories: true)
            for (src, dst) in [("terrazzo-texture.png", "Lobby Floor Reference.png"), ("phone-screen-mockup.psd", "App Store Hero.psd"),
                               ("phone-screen-mockup.psd", "Round 2/App Store Hero final.psd"), ("coffee-cup-mockup.psd", "Cafe Menu Cup.psd")] {
                try? fm.copyItem(at: starterRoot.appendingPathComponent(src), to: drop.appendingPathComponent(dst))
            }
            watch([drop.path])
            findDuplicates()
        case "similar":
            // A half-size JPEG re-export of a bundled texture, dropped into a watch folder: it should rank first as a near copy.
            let fm = FileManager.default
            let drop = fm.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Client Drops", isDirectory: true)
            try? fm.createDirectory(at: drop, withIntermediateDirectories: true)
            let src = starterRoot.appendingPathComponent("terrazzo-texture.png")
            if let isrc = CGImageSourceCreateWithURL(src as CFURL, nil),
               let small = CGImageSourceCreateThumbnailAtIndex(isrc, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1024] as CFDictionary),
               let dst = CGImageDestinationCreateWithURL(drop.appendingPathComponent("terrazzo-web.jpg") as CFURL, UTType.jpeg.identifier as CFString, 1, nil) {
                CGImageDestinationAddImage(dst, small, [kCGImageDestinationLossyCompressionQuality: 0.6] as CFDictionary)
                CGImageDestinationFinalize(dst)
            }
            watch([drop.path])
            if let a = catalog.assets.first(where: { $0.importedPath?.hasSuffix("terrazzo-texture.png") == true && $0.isStarter }) { findSimilar(a.id) }
        case "stacks", "stack-compare":
            // A client drop with three rounds of the same hero plus a draft of a mockup: auto-stacked on scan.
            let fm = FileManager.default
            let drop = fm.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Client Drops", isDirectory: true)
            try? fm.removeItem(at: drop)
            try? fm.createDirectory(at: drop, withIntermediateDirectories: true)
            let rounds: [(String, String)] = [("terrazzo-texture.png", "Lobby Floor v1.png"), ("marble-veins-texture.png", "Lobby Floor v2.png"),
                                              ("cork-board-texture.png", "Lobby Floor final.png"), ("night-grid-4k.png", "Keynote Backdrop.png"),
                                              ("phone-screen-mockup.psd", "App Store Hero draft.psd"), ("phone-screen-mockup.psd", "App Store Hero v2.psd"),
                                              ("coffee-cup-mockup.psd", "Cafe Menu Cup.psd")]
            for (src, dst) in rounds where fm.fileExists(atPath: starterRoot.appendingPathComponent(src).path) {
                try? fm.copyItem(at: starterRoot.appendingPathComponent(src), to: drop.appendingPathComponent(dst))
            }
            watch([drop.path])
            scanWatchFolders()
            show(collection: StudioCatalog.inboxCollection)
            if let top = catalog.assets.first(where: { $0.importedPath?.hasSuffix("Lobby Floor final.png") == true }) {
                selection = [top.id]; focusID = top.id
                if demo == "stack-compare", let v1 = catalog.assets.first(where: { $0.importedPath?.hasSuffix("Lobby Floor v1.png") == true }) {
                    compareVersions(v1.id, top.id); compareSwipe = true; swipeSplit = 0.5
                }
            }
        case "keywords":
            // The keyword list with one keyword picked; the grid narrows to it.
            show(collection: StudioCatalog.allAssets)
            let top = catalog.keywordCounts()
            keywordFilter = top.first(where: { $0.tag == "mockup" })?.tag ?? top.dropFirst(2).first?.tag
            if let a = filtered.first { selection = [a.id]; focusID = a.id }
        case "file-metadata":
            // Files that already carry keywords, a title, stars and a label: a JPEG with embedded XMP
            // and a PNG with a Lightroom-style sidecar (develop settings included). Then one edit is written back.
            let fm = FileManager.default
            let drop = fm.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Client Drops", isDirectory: true)
            try? fm.removeItem(at: drop)
            try? fm.createDirectory(at: drop, withIntermediateDirectories: true)
            if let src = CGImageSourceCreateWithURL(starterRoot.appendingPathComponent("terrazzo-texture.png") as CFURL, nil),
               let img = CGImageSourceCreateImageAtIndex(src, 0, nil) {
                let meta = FileMetadata(title: "Lobby Floor Hero", keywords: ["terrazzo", "lobby", "client-x", "approved"], rating: 4, label: .green)
                let out = ExportOutput(suffix: "", width: 1600, height: 1600, crop: ExportRect(x: 0, y: 0, w: img.width, h: img.height), format: .jpeg, dpi: 72)
                _ = MediaRenderer.writePreset(img, output: out, to: drop.appendingPathComponent("IMG_4471.jpg"), metadata: meta)
            }
            try? fm.copyItem(at: starterRoot.appendingPathComponent("marble-veins-texture.png"), to: drop.appendingPathComponent("DSC_0192.png"))
            let lightroom = """
            <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="Adobe XMP Core 7.0">
             <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
              <rdf:Description rdf:about="" xmlns:xmp="http://ns.adobe.com/xap/1.0/" xmlns:dc="http://purl.org/dc/elements/1.1/"
                xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/" xmp:Rating="5" xmp:Label="Purple" crs:Exposure2012="+0.35" crs:Temperature="5200">
               <dc:title><rdf:Alt><rdf:li xml:lang="x-default">Marble Wall Study</rdf:li></rdf:Alt></dc:title>
               <dc:subject><rdf:Bag><rdf:li>marble</rdf:li><rdf:li>wall</rdf:li><rdf:li>client-x</rdf:li></rdf:Bag></dc:subject>
              </rdf:Description>
             </rdf:RDF>
            </x:xmpmeta>
            """
            try? lightroom.write(to: drop.appendingPathComponent("DSC_0192.xmp"), atomically: true, encoding: .utf8)
            watch([drop.path])
            scanWatchFolders()
            show(collection: StudioCatalog.inboxCollection)
            if let png = catalog.assets.first(where: { $0.importedPath?.hasSuffix("DSC_0192.png") == true }) {
                label([png.id], .blue); addTags("round 2", to: [png.id])
                writeMetadata([png.id])
            }
            if let jpg = catalog.assets.first(where: { $0.importedPath?.hasSuffix("IMG_4471.jpg") == true }) { selection = [jpg.id]; focusID = jpg.id; scrollInspectorToTags = true }
        case "cull", "sort-rating":
            // Half the mockups already rated, then cull picks up at the first unrated one; or the same pass sorted by rating.
            show(collection: "Device Mockups")
            let ids = filtered.map(\.id)
            let stars = [5, 4, 3, 0, 4, 2, 5, 1, 3, 0, 4, 5]
            let labels: [ColorLabel?] = [.green, .blue, nil, .red, .green, nil, .purple, .yellow, nil, .red, .blue, .green]
            mutate { c in
                for (i, id) in ids.prefix(demo == "cull" ? 6 : 12).enumerated() {
                    c.setRating([id], stars[i]); if let l = labels[i] { c.toggleLabel([id], l) }
                }
                if demo == "cull", ids.count > 3 { c.toggleReject([ids[3]]) }
            }
            if demo == "cull" {
                if ids.count > 6 { focusID = ids[6]; selection = [ids[6]] }
                openCull()
            } else {
                setSort(.rating)
                if let a = filtered.first { selection = [a.id]; focusID = a.id }
            }
        case "ratings", "label-filter":
            // A rating pass on the mockups: stars and labels on the cards, the inspector row, then the chips narrowing the grid.
            show(collection: "Device Mockups")
            let ids = filtered.map(\.id)
            let stars = [5, 4, 3, 0, 4, 2, 5, 1, 3, 0, 4, 5]
            let labels: [ColorLabel?] = [.green, .blue, nil, .red, .green, nil, .purple, .yellow, nil, .red, .blue, .green]
            mutate { c in
                for (i, id) in ids.prefix(12).enumerated() {
                    c.setRating([id], stars[i])
                    if let l = labels[i] { c.toggleLabel([id], l) }
                }
            }
            if demo == "label-filter" {
                ratingFilter = RatingFilter(minRating: 4, labels: [.green, .blue])
                if let a = filtered.first { selection = [a.id]; focusID = a.id }
            } else if let first = ids.first {
                selection = [first]; focusID = first
            }
        case "contact-sheet":
            show(collection: "Material Textures")
            let ids = filtered.map(\.id)
            openContactSheet(ids: ids, title: "Material Textures")
            // CI keeps the rendered PDF and a listing of a small originals kit as proof.
            Task { @MainActor in
                var tries = 0
                while self.sheetPreview == nil && tries < 40 { try? await Task.sleep(nanoseconds: 150_000_000); tries += 1 }
                guard let p = self.sheetPreview else { return }
                let fm = FileManager.default
                try? fm.removeItem(at: self.supportRoot.appendingPathComponent("demo-contact-sheet.pdf"))
                try? fm.copyItem(at: p.pdf, to: self.supportRoot.appendingPathComponent("demo-contact-sheet.pdf"))
                let small = SheetPreview(title: p.title, ids: Array(p.ids.prefix(4)), pdf: p.pdf)
                self.buildBrandKit(small, mode: .originals, to: self.supportRoot.appendingPathComponent("demo-brand-kit.zip"))
                // Whole-library sheet, so CI can report the size of a 28-asset PDF with JPEG thumbnails.
                // Written under a temp name and renamed at the end, so CI never measures a half-written file.
                let tmp = self.supportRoot.appendingPathComponent("demo-contact-sheet-all.partial.pdf")
                if await ContactSheetRenderer.render(title: "ASSSETS Library", assets: self.catalog.assets, to: tmp) {
                    try? fm.removeItem(at: self.supportRoot.appendingPathComponent("demo-contact-sheet-all.pdf"))
                    try? fm.moveItem(at: tmp, to: self.supportRoot.appendingPathComponent("demo-contact-sheet-all.pdf"))
                }
            }
        case "autotags", "autotags-audio":
            // Suggested tags are searchable before they're accepted: "tileable" finds textures nobody tagged by hand.
            if demo == "autotags" {
                show(collection: StudioCatalog.allAssets); search = "tileable"; scrollInspectorToTags = true
                Task { @MainActor in
                    var tries = 0
                    while self.filtered.isEmpty && tries < 40 { try? await Task.sleep(nanoseconds: 150_000_000); tries += 1 }
                    if let a = self.filtered.first(where: { $0.importedPath?.hasSuffix("terrazzo-texture.png") == true }) ?? self.filtered.first { self.selection = [a.id]; self.focusID = a.id }
                }
            } else {
                show(collection: "Sound Beds")
                if let a = filtered.first(where: { $0.importedPath?.hasSuffix(".wav") == true }) ?? filtered.first { selection = [a.id]; focusID = a.id }
            }
        case "compare", "compare-swipe":
            show(collection: "Material Textures")
            let files = demo == "compare" ? ["terrazzo-texture.png", "marble-veins-texture.png", "cork-board-texture.png"] : ["terrazzo-texture.png", "marble-veins-texture.png"]
            let ids = files.compactMap { f in filtered.first(where: { $0.importedPath?.hasSuffix(f) == true })?.id }
            selection = Set(ids); focusID = ids.first
            openCompare(ids)
            if demo == "compare" {
                keepRating = 4
                markCompare(.keep); markCompare(.reject)
                compareZoom.zoom(by: 2.5, anchorX: 0.3, anchorY: 0.35)
            } else { swipeSplit = 0.46; compareSwipe = true }
        case "gallery":
            let ids = catalog.assets.filter { $0.collection == "Device Mockups" }.prefix(12).map(\.id)
            show(collection: "Device Mockups")
            let out = supportRoot.appendingPathComponent("demo-gallery", isDirectory: true)
            try? FileManager.default.removeItem(at: out)
            try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            exportGallery(Array(ids), title: "Launch Mockups", to: out)
        case "gallery-import":
            // The same file the gallery page writes when a client presses Download feedback.
            let mocks = catalog.assets.filter { $0.collection == "Device Mockups" }
            let notes = ["Love this one. Can we try it with the warmer backdrop?", "", "Great for the store page, maybe crop tighter."]
            let items = mocks.prefix(3).enumerated().map { i, a in ReviewGallery.Feedback.Entry(id: a.id.uuidString.lowercased(), favorite: i != 1, note: notes[i]) }
            let fb = ReviewGallery.Feedback(gallery: "demo", title: "Launch Mockups", reviewer: "Jordan (client)", items: Array(items))
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Launch Mockups feedback - Jordan.json")
            if let data = try? JSONEncoder().encode(fb) { try? data.write(to: url) }
            importFeedback([url])
            if let a = mocks.first { selection = [a.id]; focusID = a.id; scrollInspectorToTags = true }
        case "export-presets":
            // Wide 3:2 mockups, so the square and story crops have somewhere to slide.
            let files = ["cosmetic-plinth-mockup.png", "device-stage-mockup.png", "album-gatefold-mockup.png"]
            let ids = files.compactMap { f in catalog.assets.first(where: { $0.importedPath?.hasSuffix(f) == true })?.id }
            if let a = ids.first, let c = catalog.assets.first(where: { $0.id == a })?.collection { show(collection: c) }
            selection = Set(ids); focusID = ids.first
            openPresetExport(ids)
            presetExport?.presets = [.web, .social, .story]
            presetExport?.embedMetadata = true
            // CI also keeps a real export of every preset to list the files and their pixel sizes.
            if var st = presetExport {
                st.presets = Set(ExportPreset.allCases)
                let out = supportRoot.appendingPathComponent("demo-exports", isDirectory: true)
                try? FileManager.default.removeItem(at: out)
                try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
                let keep = presetExport
                runPresetExport(st, to: out)
                presetExport = keep
            }
        case "batch-rename":
            // Eight textures picked in the grid, renamed for a client hand-off.
            show(collection: "Material Textures")
            let ids = filtered.filter { $0.kind != .audio }.prefix(8).map(\.id)
            selection = Set(ids); focusID = ids.first
            openBatchRename(ids)
            batchRename?.pattern = "Client X {n:000} - {title}"
            batchRename?.start = 1
        case "folder-export":
            // Mockups and textures with mixed labels, exported into {collection}/{label} subfolders.
            let pick = ["cosmetic-plinth-mockup.png", "device-stage-mockup.png", "album-gatefold-mockup.png", "terrazzo-texture.png", "marble-veins-texture.png", "cork-board-texture.png"]
            let ids = pick.compactMap { f in catalog.assets.first(where: { $0.importedPath?.hasSuffix(f) == true })?.id }
            let labels: [ColorLabel?] = [.green, .blue, .green, .red, nil, .red]
            let want = Dictionary(uniqueKeysWithValues: zip(ids, labels))
            mutate { c in for i in c.assets.indices { if let l = want[c.assets[i].id] { c.assets[i].label = l } } }
            show(collection: StudioCatalog.allAssets)
            selection = Set(ids); focusID = ids.first
            openPresetExport(ids)
            presetExport?.presets = [.web, .social]
            presetExport?.folders = "{collection}/{label}"
            presetExport?.pattern = "{title}-{preset}"
            presetExport?.embedMetadata = true
            if var st = presetExport {
                st.presets = [.web, .social]
                let out = supportRoot.appendingPathComponent("demo-folder-export", isDirectory: true)
                try? FileManager.default.removeItem(at: out)
                try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
                let keep = presetExport
                runPresetExport(st, to: out)
                presetExport = keep
            }
        case "vectors":
            selectedKind = .vector
            if let v = filtered.first(where: { $0.isStarter }) { selection = [v.id]; focusID = v.id }
        default: break
        }
        if let secs = value("-asssets-quit-after").flatMap(Double.init) {
            DispatchQueue.main.asyncAfter(deadline: .now() + secs) { self.save(); NSApp.terminate(nil) }
        }
        if let size = value("-asssets-window")?.split(separator: "x").compactMap({ Double($0) }), size.count == 2 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                guard let window = NSApp.windows.first(where: { $0.isVisible }) ?? NSApp.windows.first, let screen = window.screen ?? NSScreen.main else { return }
                let vis = screen.visibleFrame
                let w = min(size[0], vis.width), h = min(size[1], vis.height)
                window.setFrame(NSRect(x: vis.minX + (vis.width - w) / 2, y: vis.minY + (vis.height - h) / 2, width: w, height: h), display: true, animate: false)
            }
        }
    }
}

// MARK: - Layout

struct StudioView: View {
    @EnvironmentObject var model: StudioLibrary
    var body: some View {
        NavigationSplitView {
            Sidebar().navigationSplitViewColumnWidth(min: 246, ideal: 258, max: 320)
        } content: {
            AssetBrowser().navigationSplitViewColumnWidth(min: 400, ideal: 600)
        } detail: {
            Group {
                if model.selection.count > 1 { BatchInspector(assets: model.selectedAssets) }
                else if let asset = model.focused { Inspector(asset: asset) }
                else { EmptyInspector() }
            }
            .navigationSplitViewColumnWidth(min: 290, ideal: 316, max: 420)
        }
        .navigationSplitViewStyle(.balanced)
        .background(Theme.ink)
        .toolbarBackground(Theme.panel, for: .windowToolbar)
        .toolbar {
            ToolbarItemGroup {
                Button { model.importFiles() } label: { Label("Import", systemImage: "plus") }.help("Import files or folders")
                Button { model.openViewer() } label: { Label("Quick Look", systemImage: "eye") }.help("View full size (Space)")
                HStack(spacing: 6) {
                    Image(systemName: "square.grid.3x3").font(.caption)
                    Slider(value: $model.gridScale, in: 120...280).frame(width: 90)
                    Image(systemName: "square.grid.2x2").font(.caption)
                }.foregroundStyle(.secondary).help("Thumbnail size")
            }
        }
        .confirmationDialog("Remove \(model.pendingRemoval.count) asset\(model.pendingRemoval.count == 1 ? "" : "s") from the library?",
                            isPresented: Binding(get: { !model.pendingRemoval.isEmpty }, set: { if !$0 { model.pendingRemoval = [] } })) {
            Button("Remove from Library", role: .destructive) { model.confirmRemoval() }
            Button("Cancel", role: .cancel) { model.pendingRemoval = [] }
        } message: { Text("Files on disk stay where they are.") }
        .sheet(item: $model.smartEditor) { state in SmartEditor(state: state).environmentObject(model) }
        .sheet(item: $model.sheetPreview) { p in ContactSheetPreview(preview: p).environmentObject(model) }
        .sheet(item: $model.presetExport) { st in PresetExportSheet(state: st).environmentObject(model) }
        .sheet(item: $model.batchRename) { st in BatchRenameSheet(state: st).environmentObject(model) }
        .sheet(isPresented: Binding(get: { model.duplicates != nil }, set: { if !$0 { model.duplicates = nil } })) {
            DuplicatesSheet().environmentObject(model)
        }
        .overlay {
            if let id = model.viewerID, let asset = model.catalog.assets.first(where: { $0.id == id }) {
                AssetViewer(asset: asset).transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.16), value: model.viewerID)
        .overlay {
            if model.compare != nil { CompareView().transition(.opacity) }
        }
        .animation(.easeOut(duration: 0.16), value: model.compare != nil)
        .overlay {
            if model.cull != nil { CullView().transition(.opacity) }
        }
        .animation(.easeOut(duration: 0.16), value: model.cull != nil)
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                Text(toast).font(.callout.weight(.medium)).padding(.horizontal, 16).padding(.vertical, 9)
                    .background(.ultraThinMaterial, in: Capsule()).overlay(Capsule().stroke(Theme.hairline))
                    .padding(.bottom, 22).transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.toast)
    }
}

struct Sidebar: View {
    @EnvironmentObject var model: StudioLibrary
    @State private var renameText = ""
    @State private var renameKeywordText = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9).fill(LinearGradient(colors: [Theme.accent, Color(red: 0.95, green: 0.35, blue: 0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        Text("A").font(.system(size: 17, weight: .black)).foregroundStyle(.white)
                    }.frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("ASSSETS").font(.system(size: 14, weight: .black)).tracking(2.5)
                        Text("\(model.catalog.assets.count) assets").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.horizontal, 6).padding(.top, 4)

                SidebarSection(title: "LIBRARY") {
                    SidebarRow(title: StudioCatalog.allAssets, symbol: "square.grid.2x2", count: model.catalog.count(in: StudioCatalog.allAssets), selected: model.selectedSmart == nil && model.selectedCollection == StudioCatalog.allAssets) { model.show(collection: StudioCatalog.allAssets) }
                    SidebarRow(title: StudioCatalog.favorites, symbol: "heart.fill", count: model.catalog.count(in: StudioCatalog.favorites), selected: model.selectedSmart == nil && model.selectedCollection == StudioCatalog.favorites, dropTarget: StudioCatalog.favorites) { model.show(collection: StudioCatalog.favorites) }
                    if !model.missing.isEmpty {
                        SidebarRow(title: StudioLibrary.missingCollection, symbol: "exclamationmark.triangle", count: model.missing.count, selected: model.selectedSmart == nil && model.selectedCollection == StudioLibrary.missingCollection, accent: .warning) { model.show(collection: StudioLibrary.missingCollection) }
                            .contextMenu { Button("Remove All Missing from Library…", role: .destructive) { model.removeMissing() } }
                    }
                }

                SidebarSection(title: "COLLECTIONS", trailing: AnyView(
                    Button { model.newCollection(with: []) } label: { Image(systemName: "plus").font(.caption.bold()) }.buttonStyle(.plain).foregroundStyle(.secondary).help("New collection")
                )) {
                    ForEach(model.catalog.collections.filter { $0 != StudioCatalog.allAssets && $0 != StudioCatalog.favorites }, id: \.self) { name in
                        SidebarRow(title: name, symbol: symbol(for: name), count: model.catalog.count(in: name), selected: model.selectedSmart == nil && model.selectedCollection == name, dropTarget: name) { model.show(collection: name) }
                            .contextMenu {
                                Button("Rename…") { renameText = name; model.renamingCollection = name }
                                Button("Contact Sheet & Brand Kit…") { model.openContactSheet(ids: model.catalog.assets.filter { $0.collection == name }.map(\.id), title: name) }
                                Button("Show") { model.show(collection: name) }
                            }
                    }
                }

                SidebarSection(title: "SMART COLLECTIONS", trailing: AnyView(
                    Button { model.beginNewSmart() } label: { Image(systemName: "plus").font(.caption.bold()) }.buttonStyle(.plain).foregroundStyle(.secondary).help("New smart collection")
                )) {
                    ForEach(model.catalog.smartCollections) { smart in
                        SidebarRow(title: smart.name, symbol: smart.symbol, count: model.catalog.smartAssets(smart.id).count, selected: model.selectedSmart == smart.id, accent: .smart) { model.show(smart: smart.id) }
                            .contextMenu {
                                Button("Edit Rules…") { model.beginEdit(smart: smart.id) }
                                Button("Contact Sheet & Brand Kit…") { model.openContactSheet(ids: model.catalog.smartAssets(smart.id).map(\.id), title: smart.name) }
                                Button("Delete Smart Collection", role: .destructive) { model.deleteSmart(smart.id) }
                            }
                    }
                    if model.catalog.smartCollections.isEmpty {
                        Text("Save any search as a live collection.").font(.caption2).foregroundStyle(.tertiary).padding(.horizontal, 9)
                    }
                }

                KeywordsSection(renameText: $renameKeywordText)

                SidebarSection(title: "WATCH FOLDERS", trailing: AnyView(
                    Button { model.addWatchFolder() } label: { Image(systemName: "plus").font(.caption.bold()) }.buttonStyle(.plain).foregroundStyle(.secondary).help("Watch a folder for new files")
                )) {
                    ForEach(model.catalog.watchFolders, id: \.self) { folder in
                        SidebarRow(title: (folder as NSString).lastPathComponent, symbol: "eye", count: model.watchedCount(folder), selected: false, accent: .watch) {
                            model.show(collection: StudioCatalog.inboxCollection)
                        }
                        .help((folder as NSString).abbreviatingWithTildeInPath)
                        .contextMenu {
                            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folder)]) }
                            Button("Scan Now") { model.scanWatchFolders() }
                            Divider()
                            Button("Stop Watching") { model.stopWatching(folder) }
                        }
                    }
                    if model.catalog.watchFolders.isEmpty {
                        Text("Watch a folder and new files land in Inbox automatically.").font(.caption2).foregroundStyle(.tertiary).padding(.horizontal, 9)
                    }
                }

                SidebarSection(title: "MEDIA") {
                    SidebarRow(title: "Everything", symbol: "circle.grid.3x3", count: nil, selected: model.selectedKind == nil) { model.selectedKind = nil }
                    ForEach(MediaKind.allCases) { kind in
                        SidebarRow(title: kind.rawValue, symbol: kind.symbol, count: model.catalog.assets.filter { $0.kind == kind }.count, selected: model.selectedKind == kind) {
                            model.selectedKind = model.selectedKind == kind ? nil : kind
                        }
                    }
                }
                Text("Drag assets onto a collection to file them. ⌘-click or ⇧-click to select several.")
                    .font(.caption2).foregroundStyle(.tertiary).padding(.horizontal, 8)
            }
            .padding(12)
        }
        .background(Theme.sidebar)
        .alert("Rename Collection", isPresented: Binding(get: { model.renamingCollection != nil }, set: { if !$0 { model.renamingCollection = nil } })) {
            TextField("Collection name", text: $renameText)
            Button("Rename") { if let old = model.renamingCollection { model.rename(old, to: renameText) }; model.renamingCollection = nil }
            Button("Cancel", role: .cancel) { model.renamingCollection = nil }
        }
        .onChange(of: model.renamingCollection) { _, name in if let name { renameText = name } }
        .alert("Rename Keyword", isPresented: Binding(get: { model.renamingKeyword != nil }, set: { if !$0 { model.renamingKeyword = nil } })) {
            TextField("Keyword", text: $renameKeywordText)
            Button("Rename") { if let old = model.renamingKeyword { model.renameKeyword(old, to: renameKeywordText) }; model.renamingKeyword = nil }
            Button("Cancel", role: .cancel) { model.renamingKeyword = nil }
        } message: { Text("Every asset tagged \"\(model.renamingKeyword ?? "")\" is updated. Using an existing keyword merges the two. ⌘Z undoes it.") }
        .onChange(of: model.renamingKeyword) { _, k in if let k { renameKeywordText = k } }
    }

    private func symbol(for name: String) -> String {
        switch name {
        case "Device Mockups": return "square.3.layers.3d"
        case "Editorial Vectors": return "scribble.variable"
        case "Material Textures": return "circle.hexagongrid"
        case "Studio Photography": return "camera.aperture"
        case "Motion Loops": return "film.stack"
        case "Sound Beds": return "waveform"
        case StudioCatalog.importedCollection: return "tray.and.arrow.down"
        case StudioCatalog.inboxCollection: return "tray.full"
        default: return "folder"
        }
    }
}

/// Every keyword in the library with counts. Click to filter; right-click to rename or merge.
struct KeywordsSection: View {
    @EnvironmentObject var model: StudioLibrary
    @Binding var renameText: String
    @State private var showAll = false
    var body: some View {
        let all = model.catalog.keywordCounts()
        SidebarSection(title: "KEYWORDS", trailing: AnyView(Text("\(all.count)").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary))) {
            let shown = showAll ? all : Array(all.prefix(10))
            WrapLayout(spacing: 5) {
                ForEach(shown, id: \.tag) { k in
                    let on = model.keywordFilter == k.tag
                    HStack(spacing: 4) {
                        Text(k.tag).font(.system(size: 11, weight: on ? .semibold : .regular)).lineLimit(1)
                        Text("\(k.count)").font(.system(size: 9.5).monospacedDigit()).foregroundStyle(on ? Color.white.opacity(0.8) : Color.secondary)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(on ? Theme.accent.opacity(0.45) : Color.white.opacity(0.06), in: Capsule())
                    .overlay(Capsule().stroke(on ? Theme.accent : Theme.hairline))
                    .contentShape(Capsule())
                    .onTapGesture { model.toggleKeywordFilter(k.tag) }
                    .help("\(k.count) asset\(k.count == 1 ? "" : "s") · click to filter, right-click to rename or merge")
                    .contextMenu {
                        Button(on ? "Stop Filtering" : "Show Assets Tagged \"\(k.tag)\"") { model.toggleKeywordFilter(k.tag) }
                        Button("Rename…") { model.renamingKeyword = k.tag }
                        Menu("Merge Into") {
                            ForEach(all.filter { $0.tag != k.tag }.prefix(25), id: \.tag) { o in Button("\(o.tag)  (\(o.count))") { model.renameKeyword(k.tag, to: o.tag) } }
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
            if all.count > 10 {
                Button(showAll ? "Show fewer" : "Show all \(all.count)") { showAll.toggle() }
                    .buttonStyle(.plain).font(.caption).foregroundStyle(Theme.accent).padding(.horizontal, 9)
            }
            if all.isEmpty { Text("Tags you add show up here.").font(.caption2).foregroundStyle(.tertiary).padding(.horizontal, 9) }
        }
    }
}

struct SidebarSection<Content: View>: View {
    let title: String
    var trailing: AnyView? = nil
    @ViewBuilder let content: Content
    /// Collapsed section titles, remembered across launches.
    @AppStorage(SidebarSections.key) private var collapsedRaw = ""
    private var collapsed: Bool { SidebarSections.decode(collapsedRaw).contains(title) }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)).foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(collapsed ? 0 : 90))
                Text(title).font(.system(size: 10, weight: .bold)).tracking(1.4).foregroundStyle(.secondary)
                Spacer()
                if let trailing, !collapsed { trailing }
            }
            .padding(.horizontal, 8).padding(.bottom, 4)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { collapsedRaw = SidebarSections.toggle(title, in: collapsedRaw) } }
            .help(collapsed ? "Show \(title.capitalized)" : "Hide \(title.capitalized)")
            if !collapsed { content }
        }
    }
}

enum SidebarSections {
    static let key = "sidebar.collapsed"
    static func decode(_ raw: String) -> Set<String> { Set(raw.split(separator: "|").map(String.init)) }
    static func toggle(_ title: String, in raw: String) -> String {
        var set = decode(raw)
        if set.contains(title) { set.remove(title) } else { set.insert(title) }
        return set.sorted().joined(separator: "|")
    }
}

enum RowAccent { case standard, smart, warning, watch }

struct SidebarRow: View {
    @EnvironmentObject var model: StudioLibrary
    let title: String
    let symbol: String
    let count: Int?
    let selected: Bool
    var dropTarget: String? = nil
    var accent: RowAccent = .standard
    let action: () -> Void
    @State private var targeted = false
    @State private var hovering = false

    var body: some View {
        let row = HStack(spacing: 9) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).frame(width: 18)
                .foregroundStyle(accent == .smart ? Theme.smart : accent == .warning ? Theme.warning : accent == .watch ? Theme.watch : (selected ? Theme.accent : Color.secondary))
            Text(title).font(.system(size: 12.5, weight: selected ? .semibold : .regular)).lineLimit(1).truncationMode(.tail).layoutPriority(1)
            Spacer(minLength: 6)
            if let count {
                Text("\(count)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2).background(Color.white.opacity(0.06), in: Capsule())
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(targeted ? Theme.accent.opacity(0.38) : selected ? Theme.accent.opacity(0.2) : hovering ? Color.white.opacity(0.045) : .clear))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(targeted ? Theme.accent : .clear, lineWidth: 1.5))
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .onHover { hovering = $0 }
        .help(title)
        if let dropTarget {
            row.onDrop(of: [UTType.asssetsSelection], isTargeted: $targeted) { providers in model.dropSelection(providers, on: dropTarget) }
        } else { row }
    }
}

// MARK: - Browser

struct AssetBrowser: View {
    @EnvironmentObject var model: StudioLibrary
    @ViewBuilder private func headerControls(compact: Bool) -> some View {
        HStack(spacing: 8) {
            SortMenu(compact: compact)
            if let id = model.selectedSmart {
                Button { model.beginEdit(smart: id) } label: {
                    if compact { Image(systemName: "slider.horizontal.3") } else { Label("Edit Rules", systemImage: "slider.horizontal.3").fixedSize() }
                }.buttonStyle(.bordered).controlSize(.small).help("Edit rules")
            } else if model.canSaveSearch {
                Button { model.beginNewSmart() } label: {
                    if compact { Image(systemName: "sparkles") } else { Label("Save as Smart", systemImage: "sparkles").fixedSize() }
                }.buttonStyle(.borderedProminent).controlSize(.small).help("Save this search as a live smart collection")
            }
        }.fixedSize()
    }
    var body: some View {
        let items = model.filtered
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    if model.selectedSmart != nil { Image(systemName: "sparkles").foregroundStyle(Theme.smart).font(.title3) }
                    Text(model.browsingTitle).font(.system(size: 22, weight: .bold)).lineLimit(1).layoutPriority(2)
                    let files = model.filteredFileCount
                    Text(files > items.count ? "\(items.count) items · \(files) files" : "\(items.count) \(items.count == 1 ? "asset" : "assets")")
                        .font(.callout).foregroundStyle(.secondary).fixedSize()
                        .help(files > items.count ? "Stacks show as one card; \(files - items.count) older versions are tucked inside" : "")
                    Spacer(minLength: 8)
                    // Full labels when there is room; icons only when the title would otherwise be cut.
                    ViewThatFits(in: .horizontal) {
                        headerControls(compact: false)
                        headerControls(compact: true)
                    }
                }
                if let id = model.selectedSmart, let smart = model.catalog.smartCollection(id) {
                    Label(smart.rules.summary, systemImage: "line.3.horizontal.decrease.circle").font(.caption).foregroundStyle(Theme.smart).lineLimit(1)
                }
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search titles, tags, colors…", text: $model.search).textFieldStyle(.plain)
                    if !model.search.isEmpty { Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary) }
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.hairline))
                HStack(spacing: 8) {
                    // Full chips when they fit; otherwise one "Media" menu instead of squeezed, cut-off chips.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 6) {
                            KindChip(title: "All", symbol: "circle.grid.3x3", on: model.selectedKind == nil) { model.selectedKind = nil }
                            ForEach(MediaKind.allCases) { k in KindChip(title: k.rawValue, symbol: k.symbol, on: model.selectedKind == k) { model.selectedKind = model.selectedKind == k ? nil : k } }
                        }.fixedSize()
                        MediaFoldMenu()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Pinned outside the scrolling media chips so an active rating or label filter is always visible.
                    Rectangle().fill(Theme.hairline).frame(width: 1, height: 18)
                    HStack(spacing: 6) {
                        if let k = model.keywordFilter {
                            Button { model.keywordFilter = nil } label: {
                                HStack(spacing: 4) { Image(systemName: "tag.fill").font(.system(size: 9)); Text(k).lineLimit(1); Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
                                    .font(.system(size: 11.5, weight: .semibold)).padding(.horizontal, 9).padding(.vertical, 5)
                                    .background(Theme.accent.opacity(0.35), in: Capsule()).overlay(Capsule().stroke(Theme.accent))
                            }.buttonStyle(.plain).help("Stop filtering by this keyword")
                        }
                        RatingFilterChips()
                    }.fixedSize()
                }
            }
            .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 10)
            Divider().overlay(Theme.hairline)
            if items.isEmpty {
                let emptyTitle: String = model.search.isEmpty ? "Nothing here yet" : "No matches"
                let emptyHint: String = model.search.isEmpty ? "Drag assets onto this collection in the sidebar." : "Try another tag, color or title."
                ContentUnavailableView(emptyTitle, systemImage: model.search.isEmpty ? "tray" : "magnifyingglass", description: Text(emptyHint))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: model.gridScale), spacing: 14)], spacing: 16) {
                        ForEach(items) { asset in
                            AssetCard(asset: asset, selected: model.selection.contains(asset.id))
                                .onTapGesture { model.click(asset.id) }
                                .onDrag { model.dragProvider(for: asset) }
                                .contextMenu { AssetMenu(ids: model.targets(for: asset.id), primary: asset) }
                        }
                    }
                    .padding(18)
                }
                .background(Color.clear.contentShape(Rectangle()).onTapGesture { model.clearSelection() })
            }
            if model.selection.count > 1 { SelectionBar() }
        }
        .background(Theme.backdrop)
    }
}

/// Media kinds folded into one menu when the window is too narrow for the chips.
struct MediaFoldMenu: View {
    @EnvironmentObject var model: StudioLibrary
    var body: some View {
        let k = model.selectedKind
        Menu {
            Button("All Media") { model.selectedKind = nil }
            Divider()
            ForEach(MediaKind.allCases) { kind in Button { model.selectedKind = kind } label: { Label(kind.rawValue, systemImage: kind.symbol) } }
        } label: {
            Label(k?.rawValue ?? "All Media", systemImage: k?.symbol ?? "circle.grid.3x3").font(.system(size: 11.5, weight: .medium))
        }
        .menuStyle(.borderlessButton).fixedSize()
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Theme.accent.opacity(0.28), in: Capsule())
        .overlay(Capsule().stroke(Theme.accent.opacity(0.9)))
    }
}

/// Grid sort for the current collection; each collection remembers its own.
struct SortMenu: View {
    @EnvironmentObject var model: StudioLibrary
    var compact = false
    var body: some View {
        let cur = model.currentSort
        Menu {
            ForEach(AssetSort.allCases) { s in
                Button { model.setSort(s) } label: { Label(s.title, systemImage: s == cur ? "checkmark" : s.symbol) }
            }
        } label: {
            if compact { Image(systemName: "arrow.up.arrow.down").font(.system(size: 11.5, weight: .semibold)) }
            else { Label(cur.title, systemImage: "arrow.up.arrow.down").font(.system(size: 11.5, weight: .semibold)) }
        }
        .menuStyle(.borderlessButton).fixedSize()
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(cur == .added ? Color.white.opacity(0.05) : Theme.accent.opacity(0.22), in: Capsule())
        .overlay(Capsule().stroke(cur == .added ? Theme.hairline : Theme.accent.opacity(0.7)))
        .help("Sort this collection")
    }
}

/// Full-window cull: one asset at a time. 1-5 rate and move on, X rejects, 6-9 label, arrows browse.
struct CullView: View {
    @EnvironmentObject var model: StudioLibrary
    var body: some View {
        if let s = model.cull {
            let byID = Dictionary(uniqueKeysWithValues: model.catalog.assets.map { ($0.id, $0) })
            let p = s.progress(in: model.catalog)
            ZStack {
                ZStack { Rectangle().fill(.ultraThinMaterial); Color.black.opacity(0.94) }.ignoresSafeArea()
                if let asset = byID[s.current] {
                    VStack(spacing: 14) {
                        header(s, asset: asset, progress: p)
                        HStack(spacing: 14) {
                            ViewerArrow(symbol: "chevron.left") { model.cull?.step(by: -1) }
                            ZStack(alignment: .topLeading) {
                                ProcessedPreview(asset: asset, effect: .original, amount: 0, pixels: 2000, fit: true).id(asset.id)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .opacity(asset.tags.contains(StudioCatalog.rejectTag) ? 0.4 : 1)
                                if asset.tags.contains(StudioCatalog.rejectTag) {
                                    Label("Rejected", systemImage: "xmark.circle.fill").font(.system(size: 12, weight: .bold))
                                        .padding(.horizontal, 10).padding(.vertical, 5).background(Color(red: 0.75, green: 0.2, blue: 0.25), in: Capsule()).padding(12)
                                }
                            }
                            ViewerArrow(symbol: "chevron.right") { model.cull?.step(by: 1) }
                        }
                        controls(asset)
                        strip(s, byID: byID)
                        Text("1-5 rate · 0 clear · X reject · 6-9 label · ← → browse · U next unrated · A auto-advance · ⌘Z undo · Esc done")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .padding(24)
                }
            }
        }
    }

    private func header(_ s: CullSession, asset: StudioAsset, progress p: (decided: Int, total: Int)) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Cull · " + model.browsingTitle).font(.system(size: 20, weight: .bold)).lineLimit(1)
                Text("\(asset.title) · \(asset.resolution)").font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                Text("\(s.index + 1) of \(s.ids.count) · \(p.decided) decided").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.1))
                        Capsule().fill(Theme.accent).frame(width: g.size.width * CGFloat(p.decided) / CGFloat(max(1, p.total)))
                    }
                }.frame(width: 220, height: 6)
            }
            Button { model.cull?.autoAdvance.toggle() } label: {
                Label("Auto-advance", systemImage: s.autoAdvance ? "forward.fill" : "forward").font(.system(size: 11.5, weight: .semibold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(s.autoAdvance ? Theme.accent.opacity(0.3) : Color.white.opacity(0.06), in: Capsule())
                    .overlay(Capsule().stroke(s.autoAdvance ? Theme.accent : Theme.hairline))
            }.buttonStyle(.plain).help("Move to the next asset after rating or rejecting (A)")
            Button { model.closeCull() } label: { Label("Done", systemImage: "checkmark") }.buttonStyle(.borderedProminent)
        }
    }

    private func controls(_ asset: StudioAsset) -> some View {
        HStack(spacing: 18) {
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { n in
                    Button { model.cullRate(asset.rating == n ? 0 : n) } label: {
                        Image(systemName: n <= asset.rating ? "star.fill" : "star").font(.system(size: 24))
                            .foregroundStyle(n <= asset.rating ? Theme.warning : Color.white.opacity(0.35))
                    }.buttonStyle(.plain).help("\(n) (\(n))")
                }
            }
            Rectangle().fill(Theme.hairline).frame(width: 1, height: 24)
            HStack(spacing: 6) { ForEach(ColorLabel.allCases) { l in LabelDot(label: l, on: asset.label == l, size: 18) { model.cullLabel(l) } } }
            Rectangle().fill(Theme.hairline).frame(width: 1, height: 24)
            let rejected = asset.tags.contains(StudioCatalog.rejectTag)
            Button { model.cullReject() } label: {
                Label(rejected ? "Rejected" : "Reject", systemImage: "xmark.circle").font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(rejected ? Color(red: 0.75, green: 0.2, blue: 0.25) : Color.white.opacity(0.07), in: Capsule())
            }.buttonStyle(.plain).help("Reject (X)")
        }
    }

    /// Neighbors on either side; a dot under each shows its decision.
    private func strip(_ s: CullSession, byID: [UUID: StudioAsset]) -> some View {
        let lo = max(0, s.index - 5), hi = min(s.ids.count - 1, s.index + 5)
        return HStack(spacing: 8) {
            ForEach(lo...hi, id: \.self) { i in
                if let a = byID[s.ids[i]] {
                    VStack(spacing: 4) {
                        Thumbnail(asset: a, pixels: 160).frame(width: 70, height: 50).clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(i == s.index ? Theme.accent : Theme.hairline, lineWidth: i == s.index ? 2 : 1))
                            .opacity(a.tags.contains(StudioCatalog.rejectTag) ? 0.35 : 1)
                        Text(a.tags.contains(StudioCatalog.rejectTag) ? "✕" : a.rating > 0 ? a.stars : "·")
                            .font(.system(size: 9)).foregroundStyle(a.tags.contains(StudioCatalog.rejectTag) ? Color.red : Theme.warning).frame(height: 10)
                    }
                    .onTapGesture { model.cull?.index = i }
                }
            }
        }
    }
}

/// A clickable color-label dot (filter chips, smart editor, inspector).
struct LabelDot: View {
    let label: ColorLabel, on: Bool
    var size: CGFloat = 14
    var idle = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Circle().fill(Color(hex: label.hex).opacity(on ? 1 : idle ? 0.8 : 0.35)).frame(width: size, height: size)
                .overlay(Circle().stroke(on ? Color.white : Color.clear, lineWidth: 2))
                .padding(2)
        }.buttonStyle(.plain).help(label.name + (label.key.map { " (\($0))" } ?? ""))
    }
}

/// Minimum-rating menu and label toggles next to the media chips.
struct RatingFilterChips: View {
    @EnvironmentObject var model: StudioLibrary
    var body: some View {
        let r = model.ratingFilter.minRating
        Menu {
            Button("Any rating") { model.ratingFilter.minRating = 0 }
            ForEach(1...5, id: \.self) { n in Button(n == 5 ? "★★★★★ only" : String(repeating: "★", count: n) + " and up") { model.ratingFilter.minRating = n } }
        } label: {
            Label(r == 0 ? "Rating" : String(repeating: "★", count: r) + (r < 5 ? "+" : ""), systemImage: "star").font(.system(size: 11.5, weight: .medium))
        }
        .menuStyle(.borderlessButton).fixedSize()
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(r > 0 ? Theme.warning.opacity(0.22) : Color.white.opacity(0.05), in: Capsule())
        .overlay(Capsule().stroke(r > 0 ? Theme.warning.opacity(0.9) : Theme.hairline))
        HStack(spacing: 3) {
            ForEach(ColorLabel.allCases) { l in
                LabelDot(label: l, on: model.ratingFilter.labels.contains(l), size: 12, idle: model.ratingFilter.labels.isEmpty) { model.toggleLabelFilter(l) }
            }
            if model.ratingFilter.isActive {
                Button { model.ratingFilter = RatingFilter() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 12)) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Clear rating and label filters")
            }
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(model.ratingFilter.labels.isEmpty ? Color.white.opacity(0.05) : Color.white.opacity(0.1), in: Capsule())
        .overlay(Capsule().stroke(Theme.hairline))
    }
}

/// Stars and label for the inspected asset.
struct RatingLabelRow: View {
    @EnvironmentObject var model: StudioLibrary
    let asset: StudioAsset
    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { n in
                    Button { model.rate([asset.id], asset.rating == n ? 0 : n) } label: {
                        Image(systemName: n <= asset.rating ? "star.fill" : "star").font(.system(size: 13))
                            .foregroundStyle(n <= asset.rating ? Theme.warning : Color.secondary.opacity(0.6))
                    }.buttonStyle(.plain).help("\(n) star\(n == 1 ? "" : "s") (\(n))")
                }
            }
            Rectangle().fill(Theme.hairline).frame(width: 1, height: 14)
            HStack(spacing: 4) {
                ForEach(ColorLabel.allCases) { l in LabelDot(label: l, on: asset.label == l, size: 12) { model.label([asset.id], l) } }
            }
            Spacer(minLength: 0)
            // One line or nothing: at narrow inspector widths the name hides instead of wrapping letter by letter (1.14).
            if let l = asset.label {
                ViewThatFits(in: .horizontal) {
                    Text(l.name).font(.caption.weight(.semibold)).foregroundStyle(Color(hex: l.hex)).lineLimit(1).fixedSize()
                    Color.clear.frame(width: 0, height: 0)
                }
            }
        }
    }
}

struct KindChip: View {
    let title: String, symbol: String, on: Bool, action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.system(size: 11.5, weight: .medium)).labelStyle(.titleAndIcon)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(on ? Theme.accent.opacity(0.28) : Color.white.opacity(0.05), in: Capsule())
                .overlay(Capsule().stroke(on ? Theme.accent.opacity(0.9) : Theme.hairline))
        }.buttonStyle(.plain)
    }
}

struct SelectionBar: View {
    @EnvironmentObject var model: StudioLibrary
    @State private var tagText = ""
    var body: some View {
        ViewThatFits(in: .horizontal) {
            bar(compact: false)
            bar(compact: true)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(Theme.panel.opacity(0.96))
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    private func bar(compact: Bool) -> some View {
        HStack(spacing: compact ? 8 : 10) {
            Text(compact ? "\(model.selection.count)" : "\(model.selection.count) selected")
                .font(.callout.weight(.semibold)).lineLimit(1).fixedSize()
                .padding(.horizontal, compact ? 8 : 0).padding(.vertical, compact ? 2 : 0)
                .background(compact ? Theme.accent.opacity(0.3) : .clear, in: Capsule())
            Button { model.toggleFavorite(model.selection) } label: {
                if compact { Image(systemName: "heart") } else { Label("Favorite", systemImage: "heart").fixedSize() }
            }.help("Favorite selection")
            TextField("Add tags…", text: $tagText).textFieldStyle(.roundedBorder).frame(minWidth: 90, maxWidth: 150)
                .onSubmit { model.addTags(tagText, to: model.selection); tagText = "" }
            if model.canCompare {
                Button { model.openCompare() } label: {
                    if compact { Image(systemName: "rectangle.split.2x1") } else { Label("Compare", systemImage: "rectangle.split.2x1").fixedSize() }
                }.help("Compare side by side (⌥⌘C)")
            }
            if model.canStack || model.canUnstack {
                Menu {
                    if model.canStack { Button("Stack as Versions") { model.stackSelection() } }
                    if model.canUnstack { Button("Unstack") { model.unstackSelection() } }
                } label: {
                    if compact { Image(systemName: "square.stack.3d.up") } else { Label("Stack", systemImage: "square.stack.3d.up") }
                }.menuStyle(.borderlessButton).fixedSize().help("Group versions under one card (⌘G) or split them (⇧⌘G)")
            }
            Button { model.openBatchRename() } label: {
                if compact { Image(systemName: "character.cursor.ibeam") } else { Label("Rename", systemImage: "character.cursor.ibeam").fixedSize() }
            }.buttonStyle(.borderless).help("Batch rename titles with a pattern (⌥⌘R)")
            MoveMenu(ids: model.selection, compact: compact)
            Menu {
                Button("As Shown…") { model.exportToFolder(model.selection, mode: .asShown) }
                Button("Original Files…") { model.exportToFolder(model.selection, mode: .originals) }
                Button("Presets…") { model.openPresetExport() }
                Button("Review Gallery…") { model.exportGallery() }
                if model.canWriteMetadata { Button("Write Metadata Sidecars") { model.writeMetadata(model.selection) } }
                if model.canReveal { Divider(); Button("Reveal in Finder") { model.reveal(model.selection) } }
                Divider()
                Button("Contact Sheet & Brand Kit…") { model.openContactSheet(ids: model.selectedAssets.map(\.id), title: "\(model.selection.count) Selected Assets") }
            } label: {
                if compact { Image(systemName: "square.and.arrow.up") } else { Label("Export", systemImage: "square.and.arrow.up") }
            }.menuStyle(.borderlessButton).fixedSize().help("Export the selection to a folder")
            ShareButton(ids: model.selection, compact: true)
            MultiDragHandle(count: model.selection.count, compact: compact) { model.dragFiles(for: model.selection) }
                .fixedSize()
            Spacer(minLength: 0)
            Button { model.clearSelection() } label: {
                if compact { Image(systemName: "xmark.circle") } else { Text("Clear").fixedSize() }
            }.help("Clear selection")
        }
    }
}

/// Drag every selected asset out at once (SwiftUI's onDrag carries one item, so this is an AppKit drag source).
struct MultiDragHandle: View {
    let count: Int
    var compact = false
    let files: () -> [URL]
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.up.forward.app")
            if !compact { Text("Drag \(count) files") }
        }
        .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.accent)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(Theme.accent.opacity(0.18), in: Capsule())
        .overlay(Capsule().stroke(Theme.accent.opacity(0.45)))
        .overlay(DragSourceView(files: files))
        .help("Drag all \(count) selected assets to Finder or another app")
    }
}

struct DragSourceView: NSViewRepresentable {
    let files: () -> [URL]
    func makeNSView(context: Context) -> Source { let v = Source(); v.files = files; return v }
    func updateNSView(_ v: Source, context: Context) { v.files = files }

    final class Source: NSView, NSDraggingSource {
        var files: () -> [URL] = { [] }
        private var down: NSPoint?
        override func mouseDown(with e: NSEvent) { down = e.locationInWindow }
        override func mouseDragged(with e: NSEvent) {
            guard let d = down, hypot(e.locationInWindow.x - d.x, e.locationInWindow.y - d.y) > 3 else { return }
            down = nil
            let urls = files()
            guard !urls.isEmpty else { NSSound.beep(); return }
            let items: [NSDraggingItem] = urls.enumerated().map { i, url in
                let item = NSDraggingItem(pasteboardWriter: url as NSURL)
                let icon = NSWorkspace.shared.icon(forFile: url.path); icon.size = NSSize(width: 48, height: 48)
                let at = convert(e.locationInWindow, from: nil)
                item.setDraggingFrame(NSRect(x: at.x - 24 + CGFloat(min(i, 4) * 6), y: at.y - 24 - CGFloat(min(i, 4) * 6), width: 48, height: 48), contents: icon)
                return item
            }
            let session = beginDraggingSession(with: items, event: e, source: self)
            session.draggingFormation = .pile
        }
        func draggingSession(_ s: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            context == .outsideApplication ? .copy : []
        }
    }
}

struct MoveMenu: View {
    @EnvironmentObject var model: StudioLibrary
    let ids: Set<UUID>
    var compact = false
    var body: some View {
        Menu {
            ForEach(model.catalog.collections.filter { $0 != StudioCatalog.allAssets && $0 != StudioCatalog.favorites }, id: \.self) { name in
                Button(name) { model.move(ids, to: name) }
            }
            Divider()
            Button("New Collection from Selection…") { model.newCollection(with: ids) }
        } label: {
            if compact { Image(systemName: "folder") } else { Label("Move to", systemImage: "folder") }
        }
        .menuStyle(.borderlessButton).fixedSize().help("Move selection to a collection")
    }
}

struct AssetMenu: View {
    @EnvironmentObject var model: StudioLibrary
    let ids: Set<UUID>
    let primary: StudioAsset
    var body: some View {
        let many = ids.count > 1
        let allFav = model.catalog.assets.filter { ids.contains($0.id) }.allSatisfy { $0.favorite }
        Button(allFav ? "Remove from Favorites" : (many ? "Favorite \(ids.count) Assets" : "Add to Favorites")) { model.toggleFavorite(ids) }
        Menu("Rating") {
            ForEach(0...5, id: \.self) { n in Button(n == 0 ? "No Rating" : String(repeating: "★", count: n)) { model.rate(ids, n) } }
        }
        Menu("Label") {
            ForEach(ColorLabel.allCases) { l in Button(l.name) { model.label(ids, l) } }
            Divider(); Button("No Label") { model.label(ids, nil) }
        }
        Menu("Move to") {
            ForEach(model.catalog.collections.filter { $0 != StudioCatalog.allAssets && $0 != StudioCatalog.favorites }, id: \.self) { name in
                Button(name) { model.move(ids, to: name) }
            }
            Divider()
            Button("New Collection…") { model.newCollection(with: ids) }
        }
        Button("New Collection from \(many ? "Selection" : "Asset")") { model.newCollection(with: ids) }
        Divider()
        if primary.importedPath != nil {
            Button("Open") { model.open(primary) }
            Button("Reveal in Finder") { model.reveal(ids) }
        }
        if !many && primary.kind != .audio { Button("Find Similar") { model.findSimilar(primary.id) } }
        Button("Share…") { model.share(ids) }
        Button("Copy Keywords") { model.copyKeywords(ids) }
        Menu(many ? "Export \(ids.count) Assets" : "Export") {
            Button("As Shown…") { model.exportToFolder(ids, mode: .asShown) }
            Button("Original Files…") { model.exportToFolder(ids, mode: .originals) }
        }
        Divider()
        Button(many ? "Remove \(ids.count) from Library…" : "Remove from Library…", role: .destructive) { model.pendingRemoval = ids }
    }
}

struct DragBadge: View {
    let asset: StudioAsset
    let count: Int
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: asset.kind.symbol)
            Text(count > 1 ? "\(count) assets" : asset.title).lineLimit(1)
        }
        .font(.callout.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 8)
        .background(Theme.accent, in: Capsule()).foregroundStyle(.white)
    }
}

struct AssetCard: View {
    @EnvironmentObject var model: StudioLibrary
    let asset: StudioAsset
    let selected: Bool
    @State private var hovering = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                Thumbnail(asset: asset, pixels: 480)
                    .aspectRatio(1.36, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                    .overlay(alignment: .bottomLeading) {
                        if let m = model.similarScore(asset.id) {
                            Text(m.nearDuplicate ? "Near copy" : "\(Int((m.score * 100).rounded()))% alike").font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(m.nearDuplicate ? .black : .white).padding(.horizontal, 7).padding(.vertical, 4)
                                .background(m.nearDuplicate ? Theme.watch : Theme.smart.opacity(0.55), in: Capsule()).padding(8)
                        } else if model.similarTo == asset.id {
                            Label("Original", systemImage: "scope").font(.system(size: 9.5, weight: .bold))
                                .padding(.horizontal, 7).padding(.vertical, 4).background(Theme.accent, in: Capsule()).padding(8)
                        } else if model.missing.contains(asset.id) {
                            Label("Missing", systemImage: "exclamationmark.triangle.fill").font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(.black).padding(.horizontal, 7).padding(.vertical, 4).background(Theme.warning, in: Capsule()).padding(8)
                        } else if asset.importedPath?.lowercased().hasSuffix(".psd") == true {
                            Label("PSD", systemImage: "square.3.layers.3d").font(.system(size: 9.5, weight: .bold)).labelStyle(.titleAndIcon)
                                .padding(.horizontal, 7).padding(.vertical, 4).background(.black.opacity(0.5), in: Capsule()).padding(8)
                        } else if asset.kind == .video || asset.kind == .audio {
                            Image(systemName: asset.kind == .video ? "play.fill" : "speaker.wave.2.fill").font(.caption.bold())
                                .padding(6).background(.black.opacity(0.45), in: Circle()).padding(8)
                        }
                    }
                if asset.favorite || hovering {
                    Button { model.toggleFavorite([asset.id]) } label: {
                        Image(systemName: asset.favorite ? "heart.fill" : "heart").font(.caption.bold())
                            .foregroundStyle(asset.favorite ? Color.pink : Color.white).padding(7).background(.black.opacity(0.4), in: Circle())
                    }.buttonStyle(.plain).padding(7)
                }
                if asset.stackID != nil, model.similarTo == nil {
                    let n = model.catalog.stackCount(asset)
                    let open = model.expandedStacks.contains(asset.stackID!)
                    Button { model.toggleStackExpanded(asset) } label: {
                        Label(open ? "\(VersionStacks.rank(asset).1)" : "\(n) versions", systemImage: "square.stack.3d.up.fill")
                            .font(.system(size: 9.5, weight: .bold)).padding(.horizontal, 7).padding(.vertical, 4)
                            .background(open ? Theme.smart.opacity(0.7) : Theme.accent, in: Capsule())
                    }.buttonStyle(.plain).padding(8).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .help(open ? "Collapse this stack" : "Show all versions in the grid")
                }
                if selected && model.selection.count > 1 {
                    Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(.white, Theme.accent).padding(7)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    if let l = asset.label { Circle().fill(Color(hex: l.hex)).frame(width: 8, height: 8).help("\(l.name) label") }
                    Text(asset.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                }
                HStack(spacing: 4) {
                    Text("\(asset.kind.singular) • \(asset.resolution)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 2)
                    if asset.rating > 0 { Text(asset.stars).font(.system(size: 9.5)).foregroundStyle(Theme.warning).fixedSize() }
                }
            }
            HStack(spacing: 2) { ForEach(Array(asset.palette.prefix(5).enumerated()), id: \.offset) { _, hex in Color(hex: hex).frame(height: 4) } }.clipShape(Capsule())
        }
        .padding(8)
        .background(alignment: .top) {
            // Collapsed stacks read as a pile: two offset card edges behind the top version.
            if asset.stackID != nil, model.similarTo == nil, !model.expandedStacks.contains(asset.stackID!) {
                ZStack {
                    RoundedRectangle(cornerRadius: 15).fill(Color(red: 0.13, green: 0.12, blue: 0.19))
                        .overlay(RoundedRectangle(cornerRadius: 15).stroke(Theme.accent.opacity(0.35)))
                        .padding(.horizontal, 16).offset(y: -11)
                    RoundedRectangle(cornerRadius: 15).fill(Color(red: 0.17, green: 0.155, blue: 0.24))
                        .overlay(RoundedRectangle(cornerRadius: 15).stroke(Theme.accent.opacity(0.5)))
                        .padding(.horizontal, 8).offset(y: -5.5)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 15).fill(selected ? Theme.accent.opacity(0.17) : hovering ? Color.white.opacity(0.075) : Theme.raised))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(selected ? Theme.accent : asset.label.map { Color(hex: $0.hex).opacity(0.55) } ?? Theme.hairline, lineWidth: selected ? 2 : 1))
        .shadow(color: .black.opacity(0.3), radius: 10, y: 6)
        .contentShape(RoundedRectangle(cornerRadius: 15))
        .onHover { hovering = $0 }
    }
}

// MARK: - Smart collection editor

struct SmartEditorState: Identifiable {
    let id = UUID()
    var existing: UUID?
    var name: String
    var rules: SmartRules
}

struct SmartEditor: View {
    @EnvironmentObject var model: StudioLibrary
    @State var state: SmartEditorState
    @State private var tagsText = ""
    @Environment(\.dismiss) private var dismiss

    private var effectiveRules: SmartRules {
        var r = state.rules
        r.requiredTags = StudioCatalog.parseTags(tagsText)
        return r
    }

    var body: some View {
        let rules = effectiveRules
        let matches = model.catalog.assets.filter(rules.matches)
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles").font(.title2).foregroundStyle(Theme.smart)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.existing == nil ? "New Smart Collection" : "Edit Smart Collection").font(.title3.bold())
                    Text("Membership updates live as you import, tag and favorite.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    Text("Name").foregroundStyle(.secondary)
                    TextField("Name", text: $state.name).textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Matching").foregroundStyle(.secondary)
                    TextField("Any words in titles, tags or colors", text: $state.rules.text).textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Media").foregroundStyle(.secondary)
                    WrapLayout(spacing: 6) {
                        ForEach(MediaKind.allCases) { kind in
                            let on = state.rules.kinds.contains(kind)
                            KindChip(title: kind.rawValue, symbol: kind.symbol, on: on) {
                                if on { state.rules.kinds.removeAll { $0 == kind } } else { state.rules.kinds.append(kind) }
                            }
                        }
                    }
                }
                GridRow {
                    Text("Tagged").foregroundStyle(.secondary)
                    TextField("All of these tags, comma separated", text: $tagsText).textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Palette").foregroundStyle(.secondary)
                    Picker("Palette", selection: $state.rules.tone) {
                        Text("Any").tag(PaletteTone?.none)
                        ForEach(PaletteTone.allCases) { Text($0.rawValue).tag(PaletteTone?.some($0)) }
                    }.pickerStyle(.segmented).labelsHidden()
                }
                GridRow {
                    Text("In").foregroundStyle(.secondary)
                    Picker("Collection", selection: $state.rules.collection) {
                        Text("Any collection").tag(String?.none)
                        ForEach(model.catalog.collections.filter { $0 != StudioCatalog.allAssets && $0 != StudioCatalog.favorites }, id: \.self) { Text($0).tag(String?.some($0)) }
                    }.labelsHidden().frame(maxWidth: 240)
                }
                GridRow {
                    Text("Rating").foregroundStyle(.secondary)
                    Picker("Rating", selection: $state.rules.minRating) {
                        Text("Any").tag(0)
                        ForEach(1...5, id: \.self) { n in Text(n == 5 ? "★★★★★" : String(repeating: "★", count: n) + "+").tag(n) }
                    }.pickerStyle(.segmented).labelsHidden()
                }
                GridRow {
                    Text("Label").foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        ForEach(ColorLabel.allCases) { l in
                            let on = state.rules.labels.contains(l)
                            LabelDot(label: l, on: on, size: 18) {
                                if on { state.rules.labels.removeAll { $0 == l } } else { state.rules.labels = ColorLabel.allCases.filter { state.rules.labels.contains($0) || $0 == l } }
                            }
                        }
                        Text(state.rules.labels.isEmpty ? "Any label" : "Any of these").font(.caption).foregroundStyle(.secondary)
                    }
                }
                GridRow {
                    Text("")
                    Toggle("Favorites only", isOn: $state.rules.favoritesOnly)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(matches.count) matching \(matches.count == 1 ? "asset" : "assets")").font(.callout.weight(.semibold))
                    Spacer()
                    Text(rules.summary).font(.caption).foregroundStyle(Theme.smart).lineLimit(1)
                }
                HStack(spacing: 6) {
                    ForEach(matches.prefix(6)) { a in
                        Thumbnail(asset: a, pixels: 240).frame(width: 72, height: 53).clipShape(RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.hairline))
                    }
                    if matches.isEmpty { Text("Nothing matches yet. It will fill in as assets fit the rules.").font(.caption).foregroundStyle(.tertiary).frame(height: 53) }
                }
            }
            .padding(12).background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            HStack {
                if let id = state.existing {
                    Button("Delete", role: .destructive) { model.deleteSmart(id) }
                }
                Spacer()
                Button("Cancel") { model.smartEditor = nil; dismiss() }.keyboardShortcut(.cancelAction)
                Button(state.existing == nil ? "Create" : "Save") {
                    var final = state; final.rules = effectiveRules
                    model.commit(final)
                }
                .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                .disabled(state.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 560)
        .background(Theme.panel)
        .onAppear { tagsText = state.rules.requiredTags.joined(separator: ", ") }
    }
}

// MARK: - Inspectors

struct EmptyInspector: View {
    var body: some View {
        ContentUnavailableView("Select an asset", systemImage: "square.dashed", description: Text("⌘-click to build a selection for batch tagging."))
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.panel)
    }
}

/// Same two choices everywhere: as shown (original when unchanged, PNG otherwise) or the original files.
struct ExportMenuButton: View {
    @EnvironmentObject var model: StudioLibrary
    let ids: Set<UUID>
    let title: String
    var body: some View {
        Menu {
            Button("As Shown…") { model.exportToFolder(ids, mode: .asShown) }
            Button(ids.count == 1 ? "Original File…" : "Original Files…") { model.exportToFolder(ids, mode: .originals) }
            Divider()
            Button("Presets…") { model.openPresetExport(Array(ids)) }
        } label: {
            Label(title, systemImage: "square.and.arrow.up")
        } primaryAction: { model.exportToFolder(ids, mode: .asShown) }
        .menuStyle(.button).buttonStyle(.borderedProminent).fixedSize()
        .help("Click to export as shown. Use the arrow for original files.")
    }
}

/// Opens the system share menu anchored on itself.
struct ShareButton: View {
    @EnvironmentObject var model: StudioLibrary
    let ids: Set<UUID>
    var compact = false
    @State private var anchor = AnchorBox()
    var body: some View {
        Button { model.share(ids, anchor: anchor.view) } label: {
            if compact { Image(systemName: "square.and.arrow.up.on.square") } else { Label("Share", systemImage: "square.and.arrow.up.on.square") }
        }
        .modifier(ShareStyle(compact: compact))
        .background(AnchorView(box: anchor))
        .help("Share with AirDrop, Mail, Messages and more")
    }
}

private struct ShareStyle: ViewModifier {
    let compact: Bool
    func body(content: Content) -> some View {
        if compact { content.buttonStyle(.borderless) } else { content.buttonStyle(.bordered) }
    }
}

final class AnchorBox { weak var view: NSView? }

struct AnchorView: NSViewRepresentable {
    let box: AnchorBox
    func makeNSView(context: Context) -> NSView { let v = NSView(); box.view = v; return v }
    func updateNSView(_ v: NSView, context: Context) { box.view = v }
}

struct SheetPreview: Identifiable {
    let id = UUID()
    let title: String
    let ids: [UUID]
    let pdf: URL
}

struct PDFPreview: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> PDFView {
        let v = PDFView(); v.autoScales = true; v.displayMode = .singlePageContinuous; v.displaysPageBreaks = true
        v.backgroundColor = NSColor(white: 0.04, alpha: 1); v.document = PDFDocument(url: url); return v
    }
    func updateNSView(_ v: PDFView, context: Context) { if v.document?.documentURL != url { v.document = PDFDocument(url: url) } }
}

struct ContactSheetPreview: View {
    @EnvironmentObject var model: StudioLibrary
    let preview: SheetPreview
    @State private var mode: DragOut.ExportMode = .asShown
    var body: some View {
        let pages = PDFDocument(url: preview.pdf)?.pageCount ?? 0
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Contact Sheet & Brand Kit").font(.system(size: 20, weight: .bold))
                    Text("\(preview.title) · \(preview.ids.count) assets · \(pages) pages, US Letter landscape").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(20)
            PDFPreview(url: preview.pdf).frame(minHeight: 380)
            HStack(spacing: 10) {
                Button { model.saveContactSheet(preview) } label: { Label("Save PDF…", systemImage: "doc.richtext") }.buttonStyle(.bordered)
                Divider().frame(height: 18)
                Picker("Files", selection: $mode) {
                    Text("As shown").tag(DragOut.ExportMode.asShown)
                    Text("Originals").tag(DragOut.ExportMode.originals)
                }.pickerStyle(.segmented).fixedSize().help("Files inside the kit: exactly what you see, or the original files")
                Button { model.saveBrandKit(preview, mode: mode) } label: { Label("Save Brand Kit…", systemImage: "shippingbox") }
                    .buttonStyle(.borderedProminent).help("Zip with the contact sheet, the files, and Palette.ase / Palette.json swatches")
                Spacer()
                Button("Done") { model.sheetPreview = nil }.keyboardShortcut(.cancelAction)
            }.padding(16)
        }
        .frame(minWidth: 860, idealWidth: 960, minHeight: 600, idealHeight: 700)
        .background(Theme.panel)
    }
}

/// Draws the contact sheet PDF with CoreGraphics: a cover with the combined palette and a mosaic,
/// then 12 assets per page with name, kind, resolution and palette.
@MainActor
enum ContactSheetRenderer {
    static let bg = NSColor(red: 0.055, green: 0.058, blue: 0.08, alpha: 1)
    static let card = NSColor(white: 1, alpha: 0.05)
    static let accent = NSColor(red: 0.55, green: 0.38, blue: 1.0, alpha: 1)

    /// Re-encodes a thumbnail as JPEG so Quartz embeds it with DCT compression instead of raw pixels.
    /// Transparent art is flattened onto the sheet's card color first so it doesn't turn black.
    static func jpegRoundTrip(_ img: CGImage, maxPixel: Int = 560, quality: Double = 0.72) -> CGImage? {
        let scale = min(1, Double(maxPixel) / Double(max(img.width, img.height)))
        let w = max(1, Int(Double(img.width) * scale)), h = max(1, Int(Double(img.height) * scale))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(red: 0.09, green: 0.092, blue: 0.13, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let flat = ctx.makeImage() else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, flat, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest), let src = CGImageSourceCreateWithData(data, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    static func render(title: String, assets: [StudioAsset], to url: URL) async -> Bool {
        var images: [UUID: CGImage] = [:]
        for a in assets {
            var img: CGImage?
            if a.importedPath == nil { img = MediaRenderer.generated(a, width: 600) }
            else { img = await MediaRenderer.thumbnail(for: a, maxPixel: 600) }
            if let img { images[a.id] = jpegRoundTrip(img) ?? img }
        }
        let sheet = BrandKit.layout(count: assets.count)
        var box = CGRect(x: 0, y: 0, width: sheet.pageWidth, height: sheet.pageHeight)
        let info: [CFString: Any] = [kCGPDFContextTitle: title + " Contact Sheet", kCGPDFContextCreator: "ASSSETS"]
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, info as CFDictionary) else { return false }
        let W = sheet.pageWidth, H = sheet.pageHeight
        let gc = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = gc
        defer { NSGraphicsContext.restoreGraphicsState() }

        func text(_ s: String, _ x: Double, _ yTop: Double, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .white,
                  width: Double = 600, align: NSTextAlignment = .left, kern: CGFloat = 0, mono: Bool = false) {
            let ps = NSMutableParagraphStyle(); ps.alignment = align; ps.lineBreakMode = .byTruncatingTail
            let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
            let str = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: ps, .kern: kern])
            let h = Double(font.ascender - font.descender + font.leading) + 2
            str.draw(in: NSRect(x: x, y: H - yTop - h, width: width, height: h))
        }
        func rect(_ r: BrandKit.Rect) -> CGRect { CGRect(x: r.x, y: H - r.y - r.h, width: r.w, height: r.h) }
        func fill(_ r: CGRect, _ c: NSColor, radius: CGFloat = 0) {
            ctx.setFillColor(c.cgColor); ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)); ctx.fillPath()
        }
        func draw(_ img: CGImage, in r: CGRect, radius: CGFloat) {
            ctx.saveGState()
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)); ctx.clip()
            let s = max(r.width / CGFloat(img.width), r.height / CGFloat(img.height))
            let w = CGFloat(img.width) * s, h = CGFloat(img.height) * s
            ctx.interpolationQuality = .high
            ctx.draw(img, in: CGRect(x: r.midX - w / 2, y: r.midY - h / 2, width: w, height: h))
            ctx.restoreGState()
        }
        let date = Date().formatted(date: .long, time: .omitted)
        let total = sheet.totalPages

        // Cover
        ctx.beginPDFPage(nil)
        fill(CGRect(x: 0, y: 0, width: W, height: H), bg)
        text("ASSSETS", 48, 44, size: 11, weight: .black, color: accent, kern: 3)
        text(title, 48, 150, size: 38, weight: .bold, width: 360)
        let kinds = Dictionary(grouping: assets, by: \.kind).sorted { $0.value.count > $1.value.count }.map { "\($0.value.count) \($0.key.rawValue.lowercased())" }
        text("\(assets.count) assets · " + kinds.prefix(3).joined(separator: ", "), 48, 200, size: 12, color: NSColor(white: 1, alpha: 0.6), width: 360)
        text(date, 48, 220, size: 11, color: NSColor(white: 1, alpha: 0.4), width: 360)
        text("PALETTE", 48, 300, size: 9, weight: .bold, color: NSColor(white: 1, alpha: 0.5), kern: 1.6)
        let palette = BrandKit.combinedPalette(assets.map(\.palette))
        for (i, hex) in palette.prefix(8).enumerated() {
            let x = 48 + Double(i % 4) * 88, yTop = 322 + Double(i / 4) * 92
            fill(CGRect(x: x, y: H - yTop - 56, width: 80, height: 56), NSColor(hex: hex) ?? .gray, radius: 8)
            text(hex, x, yTop + 60, size: 8.5, color: NSColor(white: 1, alpha: 0.65), width: 80, mono: true)
        }
        let mosaic = assets.prefix(6).compactMap { images[$0.id] }
        for (i, img) in mosaic.enumerated() {
            let c = i % 2, r = i / 2
            let cell = CGRect(x: 440 + Double(c) * 158, y: H - 60 - Double(r + 1) * 164 + 8, width: 150, height: 156)
            draw(img, in: cell, radius: 12)
        }
        text("Made with ASSSETS · 1 of \(total)", 48, H - 40, size: 8, color: NSColor(white: 1, alpha: 0.35))
        ctx.endPDFPage()

        // Content pages
        var k = 0
        for (pi, cells) in sheet.pages.enumerated() {
            ctx.beginPDFPage(nil)
            fill(CGRect(x: 0, y: 0, width: W, height: H), bg)
            text(title, 36, 30, size: 15, weight: .bold, width: 500)
            text("\(pi + 2) of \(total)", W - 236, 32, size: 9, color: NSColor(white: 1, alpha: 0.45), width: 200, align: .right)
            for cell in cells {
                let a = assets[k]; k += 1
                let r = rect(cell)
                fill(r, card, radius: 10)
                let thumbH = min(r.height - 44, (r.width - 12) / 1.36)
                let t = CGRect(x: r.minX + 6, y: r.maxY - 6 - thumbH, width: r.width - 12, height: thumbH)
                if let img = images[a.id] { draw(img, in: t, radius: 7) } else { fill(t, NSColor(white: 1, alpha: 0.06), radius: 7) }
                let capTop = cell.y + 6 + thumbH + 6
                text(a.title, cell.x + 8, capTop, size: 9.5, weight: .semibold, width: cell.w - 16)
                text("\(a.kind.singular) · \(a.resolution)", cell.x + 8, capTop + 13, size: 7.5, color: NSColor(white: 1, alpha: 0.55), width: cell.w - 16)
                let sw = a.palette.prefix(5)
                let segW = (cell.w - 16) / Double(max(sw.count, 1))
                for (j, hex) in sw.enumerated() {
                    fill(CGRect(x: cell.x + 8 + Double(j) * segW, y: H - (capTop + 27) - 3, width: segW - 1, height: 3), NSColor(hex: hex) ?? .gray)
                }
            }
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return true
    }
}

struct DuplicateScan: Equatable {
    var scanning: Bool
    var groups: [[UUID]] = []
    var checked = 0
    var near = false
}

/// Inspector strip: the closest look-alikes for the focused asset, live once looks are compared.
struct SimilarStrip: View {
    @EnvironmentObject var model: StudioLibrary
    let asset: StudioAsset
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                InspectorLabel(text: "SIMILAR")
                Spacer()
                Button(model.similarTo == asset.id ? "Showing in grid" : "Find Similar") { model.findSimilar(asset.id) }
                    .buttonStyle(.plain).font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                    .disabled(model.similarTo == asset.id)
            }
            if model.looksReady {
                let hits = Array(model.matches(for: asset.id, limit: 8))
                if hits.isEmpty {
                    Text("Nothing in the library looks close.").font(.caption2).foregroundStyle(.tertiary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(hits, id: \.id) { m in
                                if let a = model.catalog.assets.first(where: { $0.id == m.id }) {
                                    Button { model.selection = [a.id]; model.focusID = a.id } label: {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Thumbnail(asset: a, pixels: 160).frame(width: 74, height: 54).clipShape(RoundedRectangle(cornerRadius: 7))
                                                .overlay(RoundedRectangle(cornerRadius: 7).stroke(m.nearDuplicate ? Theme.watch : Theme.hairline, lineWidth: m.nearDuplicate ? 1.5 : 1))
                                            Text(m.nearDuplicate ? "Near copy" : "\(Int((m.score * 100).rounded()))%").font(.system(size: 9.5, weight: .semibold))
                                                .foregroundStyle(m.nearDuplicate ? Theme.watch : .secondary)
                                        }
                                    }.buttonStyle(.plain).help(a.title)
                                }
                            }
                        }
                    }
                }
            } else {
                Text("Compares shapes and colors across the library. Near copies (resized, recompressed, lightly edited) come first.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}

struct DuplicatesSheet: View {
    @EnvironmentObject var model: StudioLibrary
    var body: some View {
        let scan = model.duplicates ?? DuplicateScan(scanning: false)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Duplicates").font(.system(size: 20, weight: .bold))
                    Text(scan.scanning ? "Comparing file contents…"
                         : scan.groups.isEmpty ? "No identical files among \(scan.checked) files."
                         : "\(scan.groups.count) \(scan.groups.count == 1 ? "set" : "sets") of \(scan.near ? "identical or look-alike" : "identical") files among \(scan.checked). Keep one per set; the others leave the library, files on disk stay.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if scan.scanning { ProgressView().controlSize(.small) }
                Toggle("Include look-alikes", isOn: Binding(get: { scan.near }, set: { model.findDuplicates(nearToo: $0) }))
                    .toggleStyle(.switch).controlSize(.small).disabled(scan.scanning)
                    .help("Also group images that look the same but are not byte-identical: resized, re-exported or lightly edited copies")
            }
            .padding(20)
            Divider().overlay(Theme.hairline)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(scan.groups, id: \.self) { group in DuplicateGroupRow(group: group) }
                    if !scan.scanning && scan.groups.isEmpty {
                        ContentUnavailableView("All clear", systemImage: "checkmark.seal", description: Text("Every file in ASSSETS is unique."))
                            .frame(maxWidth: .infinity).padding(.top, 40)
                    }
                }.padding(20)
            }
            Divider().overlay(Theme.hairline)
            HStack {
                if !scan.groups.isEmpty {
                    Button { model.keepSuggestedForAll() } label: { Label("Keep Suggested for All \(scan.groups.count)", systemImage: "checkmark.circle") }
                        .buttonStyle(.borderedProminent)
                }
                Spacer()
                Button("Done") { model.duplicates = nil }.keyboardShortcut(.cancelAction)
            }.padding(16)
        }
        .frame(minWidth: 760, idealWidth: 860, minHeight: 520, idealHeight: 620)
        .background(Theme.panel)
    }
}

struct DuplicateGroupRow: View {
    @EnvironmentObject var model: StudioLibrary
    let group: [UUID]
    var body: some View {
        let members = group.compactMap { id in model.catalog.assets.first { $0.id == id } }
        let suggested = Duplicates.suggestedKeeper(members)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(members) { a in
                    VStack(alignment: .leading, spacing: 6) {
                        Thumbnail(asset: a, pixels: 320).frame(width: 170, height: 118).clipShape(RoundedRectangle(cornerRadius: 9))
                            .overlay(alignment: .topLeading) {
                                if a.id == suggested {
                                    Label("Suggested", systemImage: "star.fill").font(.system(size: 9.5, weight: .bold))
                                        .padding(.horizontal, 7).padding(.vertical, 3).background(Theme.accent, in: Capsule()).padding(6)
                                }
                            }
                        Text(a.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Label(a.collection, systemImage: a.isStarter ? "shippingbox" : "folder").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        Text(a.importedPath.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "").font(.caption2.monospaced()).foregroundStyle(.tertiary)
                            .lineLimit(1).truncationMode(.middle)
                        Button { model.keep(a.id, in: group) } label: { Text("Keep This").frame(maxWidth: .infinity) }
                            .buttonStyle(.bordered).tint(a.id == suggested ? Theme.accent : nil).controlSize(.small)
                    }
                    .frame(width: 170)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.raised))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(a.id == suggested ? Theme.accent : Theme.hairline, lineWidth: a.id == suggested ? 1.5 : 1))
                }
            }
        }
    }
}

/// Shown in the inspector when an imported file has moved or been deleted.
struct MissingBanner: View {
    @EnvironmentObject var model: StudioLibrary
    let asset: StudioAsset
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
            VStack(alignment: .leading, spacing: 1) {
                Text("File missing").font(.caption.weight(.semibold))
                Text(asset.importedPath.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "").font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 4)
            Button("Locate…") { model.locate(asset.id) }.controlSize(.small)
            Button("Remove") { model.pendingRemoval = [asset.id] }.controlSize(.small)
        }
        .padding(10)
        .background(Theme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.warning.opacity(0.4)))
    }
}

struct InspectorLabel: View {
    let text: String
    var body: some View { Text(text).font(.system(size: 10, weight: .bold)).tracking(1.3).foregroundStyle(.secondary) }
}

struct TagChip: View {
    let tag: String
    var remove: (() -> Void)? = nil
    var body: some View {
        HStack(spacing: 4) {
            Text(tag).font(.caption)
            if let remove { Button(action: remove) { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }.buttonStyle(.plain).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.white.opacity(0.07), in: Capsule())
        .overlay(Capsule().stroke(Theme.hairline))
    }
}

/// A suggested tag: dashed outline, tap to accept, x to dismiss.
struct SuggestionChip: View {
    let tag: String
    let accept: () -> Void
    let reject: () -> Void
    var body: some View {
        HStack(spacing: 4) {
            Button(action: accept) {
                HStack(spacing: 3) { Image(systemName: "plus").font(.system(size: 8, weight: .bold)); Text(tag).font(.caption) }
            }.buttonStyle(.plain).foregroundStyle(Theme.smart).help("Add \"\(tag)\" to tags")
            Button(action: reject) { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }.buttonStyle(.plain).foregroundStyle(.tertiary).help("Dismiss suggestion")
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Theme.smart.opacity(0.07), in: Capsule())
        .overlay(Capsule().stroke(Theme.smart.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
    }
}

/// The inspector's version strip: every version in the stack, oldest to newest. Click one to inspect it;
/// ⌘-click a second (or use the compare button) to open the two side by side.
struct VersionStrip: View {
    @EnvironmentObject var model: StudioLibrary
    let asset: StudioAsset
    @State private var pick: UUID?
    var body: some View {
        let versions = model.catalog.versions(of: asset.id)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                InspectorLabel(text: "VERSIONS · \(versions.count)")
                Spacer()
                if let p = pick, p != asset.id {
                    Button { model.compareVersions(p, asset.id); pick = nil } label: {
                        Label("Compare 2", systemImage: "rectangle.split.2x1").font(.caption.weight(.semibold))
                    }.buttonStyle(.plain).foregroundStyle(Theme.accent)
                } else if versions.count >= 2, let prev = versions.last(where: { $0.id != asset.id && VersionStacks.rank($0).0 < VersionStacks.rank(asset).0 }) ?? versions.first(where: { $0.id != asset.id }) {
                    Button { model.compareVersions(prev.id, asset.id) } label: {
                        Label("Compare with \(VersionStacks.rank(prev).1)", systemImage: "rectangle.split.2x1").font(.caption.weight(.semibold))
                    }.buttonStyle(.plain).foregroundStyle(Theme.accent).help("Open this version and the one before it in compare")
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(versions) { v in
                        let current = v.id == asset.id, picked = v.id == pick
                        VStack(spacing: 4) {
                            Thumbnail(asset: v, pixels: 160).frame(width: 64, height: 46).clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(current ? Theme.accent : picked ? Theme.smart : Theme.hairline, lineWidth: current || picked ? 2 : 1))
                            Text(VersionStacks.rank(v).1).font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(current ? Theme.accent : picked ? Theme.smart : .secondary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if NSEvent.modifierFlags.contains(.command) { pick = current ? nil : v.id }
                            else { pick = nil; model.selection = [v.id]; model.focusID = v.id }
                        }
                        .contextMenu {
                            if !current { Button("Compare with Current") { model.compareVersions(v.id, asset.id) } }
                            Button("Remove from Stack") { model.unstack([v.id]) }
                        }
                        .help(current ? "Showing this version" : "Click to inspect · ⌘-click to pick for compare")
                    }
                }
            }
            Text("⌘-click any version to compare it with the one shown.").font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

struct Inspector: View {
    @EnvironmentObject var model: StudioLibrary
    let asset: StudioAsset
    @State private var newTag = ""
    @State private var playing = false

    var body: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 0) {
                preview.frame(height: min(250, max(150, geo.size.height * 0.32)))
                    .clipShape(RoundedRectangle(cornerRadius: 13))
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(Theme.hairline))
                    .padding([.horizontal, .top], 14)
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(asset.title).font(.system(size: 17, weight: .bold)).lineLimit(1)
                        Text("\(asset.kind.singular) • \(asset.resolution)").font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                        HStack(spacing: 8) {
                            Label(asset.collection, systemImage: "folder").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            DragOutChip(asset: asset)
                        }
                    }
                    Spacer()
                    Button { model.toggleFavorite([asset.id]) } label: { Image(systemName: asset.favorite ? "heart.fill" : "heart").font(.title3).foregroundStyle(asset.favorite ? Color.pink : Color.secondary) }.buttonStyle(.plain)
                }
                .padding(.horizontal, 16).padding(.top, 10)
                RatingLabelRow(asset: asset).padding(.horizontal, 16).padding(.top, 8)
                if model.missing.contains(asset.id) { MissingBanner(asset: asset).padding(.horizontal, 14).padding(.top, 8) }
                if asset.kind != .audio { EffectStrip(asset: asset).padding(.top, 10) }
                Divider().overlay(Theme.hairline).padding(.top, 10)
                ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if asset.stackID != nil { VersionStrip(asset: asset) }
                        if asset.kind != .audio { SimilarStrip(asset: asset) }
                        if asset.importedPath?.lowercased().hasSuffix(".psd") == true { PsdLayersPanel(asset: asset) }
                        InspectorLabel(text: "COLOR PALETTE")
                        HStack(spacing: 5) {
                            ForEach(Array(asset.palette.prefix(5).enumerated()), id: \.offset) { _, hex in
                                VStack(spacing: 3) {
                                    Color(hex: hex).frame(height: 30).clipShape(RoundedRectangle(cornerRadius: 6))
                                    Text(hex).font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary)
                                }
                                .onTapGesture { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(hex, forType: .string); model.flash("Copied \(hex)") }
                            }
                        }
                        let smarts = model.catalog.smartCollections.filter { $0.rules.matches(asset) }
                        if !smarts.isEmpty {
                            InspectorLabel(text: "IN SMART COLLECTIONS")
                            WrapLayout(spacing: 5) {
                                ForEach(smarts) { smart in
                                    Button { model.show(smart: smart.id) } label: {
                                        Label(smart.name, systemImage: smart.symbol).font(.caption).padding(.horizontal, 8).padding(.vertical, 4)
                                            .background(Theme.smart.opacity(0.14), in: Capsule()).overlay(Capsule().stroke(Theme.smart.opacity(0.5)))
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                        if !asset.clientNotes.isEmpty {
                            InspectorLabel(text: "CLIENT NOTES").id("inspector-notes")
                            ForEach(asset.clientNotes, id: \.self) { n in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "text.bubble.fill").foregroundStyle(Color(red: 1, green: 0.36, blue: 0.54))
                                        Text(n.reviewer).font(.caption.weight(.semibold))
                                        Spacer()
                                        Button { model.removeClientNote(n, from: asset.id) } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
                                            .buttonStyle(.plain).foregroundStyle(.tertiary).help("Remove this note")
                                    }
                                    Text(n.text).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(red: 1, green: 0.36, blue: 0.54).opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color(red: 1, green: 0.36, blue: 0.54).opacity(0.35)))
                            }
                        }
                        InspectorLabel(text: "TAGS").id("inspector-tags")
                        WrapLayout(spacing: 5) { ForEach(asset.tags, id: \.self) { tag in TagChip(tag: tag) { model.removeTag(tag, from: [asset.id]) } } }
                        if !asset.suggestedTags.isEmpty {
                            HStack {
                                Label("SUGGESTED", systemImage: "sparkles").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.smart)
                                Spacer()
                                Button("Accept all") { model.acceptSuggestions(for: [asset.id]) }.buttonStyle(.plain).font(.caption.weight(.semibold)).foregroundStyle(Theme.smart)
                            }.padding(.top, 2)
                            WrapLayout(spacing: 5) {
                                ForEach(asset.suggestedTags, id: \.self) { tag in
                                    SuggestionChip(tag: tag, accept: { model.acceptSuggestions([tag], for: [asset.id]) }, reject: { model.rejectSuggestion(tag, for: [asset.id]) })
                                }
                            }
                            Text("Read on this Mac from the file's pixels and sound. Searchable before you accept.").font(.caption2).foregroundStyle(.tertiary)
                        }
                        HStack {
                            TextField("Add tags, comma separated", text: $newTag).textFieldStyle(.roundedBorder)
                                .onSubmit { model.addTags(newTag, to: [asset.id]); newTag = "" }
                            Button { model.addTags(newTag, to: [asset.id]); newTag = "" } label: { Image(systemName: "plus.circle.fill").font(.title3) }.buttonStyle(.plain).foregroundStyle(Theme.accent)
                        }
                        HStack(spacing: 8) {
                            ExportMenuButton(ids: [asset.id], title: "Export")
                            ShareButton(ids: [asset.id])
                            Button { model.copyKeywords([asset.id]) } label: { Label("Keywords", systemImage: "doc.on.doc") }.buttonStyle(.bordered)
                            if asset.importedPath != nil { Button { model.reveal([asset.id]) } label: { Image(systemName: "folder") }.buttonStyle(.bordered).help("Reveal in Finder") }
                        }
                        if let p = asset.importedPath {
                            InspectorLabel(text: "FILE")
                            Text(p).font(.caption2.monospaced()).foregroundStyle(.tertiary).lineLimit(3).textSelection(.enabled)
                        }
                    }
                    .padding(16)
                }
                .onAppear {
                    // Demo only: bring the tag rows into view for the suggested-tags screenshot.
                    guard model.scrollInspectorToTags else { return }
                    let target = asset.clientNotes.isEmpty ? "inspector-tags" : "inspector-notes"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { withAnimation { proxy.scrollTo(target, anchor: .top) } }
                }
                }
            }
        }
        .background(Theme.panel)
        .onChange(of: asset.id) { _, _ in playing = false }
    }

    @ViewBuilder private var preview: some View {
        if asset.kind == .video, playing, let p = asset.importedPath {
            LoopingVideo(url: URL(fileURLWithPath: p)).id(p)
        } else {
            ZStack {
                Color.black.opacity(0.35)
                ProcessedPreview(asset: asset, effect: model.effect, amount: model.intensity, psdToggled: model.psdToggled[asset.id] ?? [],
                                 tiles: model.tiles(for: asset), fixSeams: model.fixSeams.contains(asset.id))
                if asset.kind == .texture { TileControls(asset: asset).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom).padding(8) }
                if asset.kind == .video, asset.importedPath != nil {
                    Button { playing = true } label: { Image(systemName: "play.fill").font(.title2).padding(16).background(.ultraThinMaterial, in: Circle()) }.buttonStyle(.plain)
                }
                if asset.kind == .audio, let p = asset.importedPath { AudioButton(url: URL(fileURLWithPath: p)).id(p) }
            }
        }
    }
}

/// Drag handle in the inspector: drag it to Finder or another app to get the file.
struct DragOutChip: View {
    @EnvironmentObject var model: StudioLibrary
    let asset: StudioAsset
    var body: some View {
        Label("Drag out", systemImage: "arrow.up.forward.app").font(.system(size: 10.5, weight: .semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Theme.accent.opacity(0.18), in: Capsule())
            .overlay(Capsule().stroke(Theme.accent.opacity(0.45)))
            .foregroundStyle(Theme.accent)
            .onDrag { model.dragProvider(for: asset) }
            .help("Drag to Finder, Keynote, Figma or any app. You get the original file, or a PNG of the preview when layers, effects or tiling are on.")
    }
}

/// Full-window viewer: Space opens it from the grid, arrows browse the visible assets, Esc or Space closes.
struct AssetViewer: View {
    @EnvironmentObject var model: StudioLibrary
    let asset: StudioAsset
    var body: some View {
        let ids = model.filtered.map(\.id)
        let pos = ViewerNav.position(ids, of: asset.id)
        ZStack {
            ZStack { Rectangle().fill(.ultraThinMaterial); Color.black.opacity(0.9) }.ignoresSafeArea().onTapGesture { model.closeViewer() }
            VStack(spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(asset.title).font(.system(size: 20, weight: .bold))
                        Text("\(asset.kind.singular) • \(asset.resolution) • \(asset.collection)").font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let pos { Text("\(pos.index) of \(pos.count)").font(.callout.monospacedDigit()).foregroundStyle(.secondary) }
                    Button { model.toggleFavorite([asset.id]) } label: {
                        Image(systemName: asset.favorite ? "heart.fill" : "heart").font(.title3).foregroundStyle(asset.favorite ? Color.pink : Color.white.opacity(0.8))
                    }.buttonStyle(.plain).help("Favorite")
                    Button { model.closeViewer() } label: {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).padding(9).background(Color.white.opacity(0.1), in: Circle())
                    }.buttonStyle(.plain).help("Close (Esc)")
                }
                HStack(spacing: 14) {
                    ViewerArrow(symbol: "chevron.left") { model.stepViewer(-1) }
                    media.frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onDrag { model.dragProvider(for: asset) }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.6), radius: 30, y: 12)
                    ViewerArrow(symbol: "chevron.right") { model.stepViewer(1) }
                }
                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        ForEach(Array(asset.palette.prefix(5).enumerated()), id: \.offset) { _, hex in
                            Circle().fill(Color(hex: hex)).frame(width: 14, height: 14).overlay(Circle().stroke(Color.white.opacity(0.2)))
                        }
                    }
                    Text(asset.tags.prefix(6).joined(separator: "  ·  ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Text("← → browse   ·   drag the image out   ·   Space or Esc to close").font(.caption).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 28).padding(.vertical, 22)
        }
    }

    @ViewBuilder private var media: some View {
        if asset.kind == .video, let p = asset.importedPath {
            LoopingVideo(url: URL(fileURLWithPath: p)).id(p)
        } else {
            ZStack {
                ProcessedPreview(asset: asset, effect: model.effect, amount: model.intensity, pixels: 2400,
                                 psdToggled: model.psdToggled[asset.id] ?? [], tiles: model.tiles(for: asset),
                                 fixSeams: model.fixSeams.contains(asset.id), fit: true)
                if asset.kind == .audio, let p = asset.importedPath { AudioButton(url: URL(fileURLWithPath: p)).id(p) }
            }
        }
    }
}

/// Retitle a selection from a pattern, with a live before/after list. One undo step (1.14).
struct BatchRenameSheet: View {
    @EnvironmentObject var model: StudioLibrary
    @State var state: StudioLibrary.BatchRenameState

    static let examples = ["{collection} {n:000}", "{title} - {date}", "Client X {n:00} - {title}", "{kind} {n}"]

    var body: some View {
        let byID = Dictionary(uniqueKeysWithValues: model.catalog.assets.map { ($0.id, $0) })
        let rows = RenamePattern.preview(state.pattern, assets: state.ids.compactMap { byID[$0] }, start: state.start)
        let changes = rows.filter(\.changed).count, clashes = rows.filter(\.clash).count
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Batch Rename").font(.system(size: 20, weight: .bold))
                Text("\(rows.count) \(rows.count == 1 ? "asset" : "assets") · \(changes) will change").font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    InspectorLabel(text: "PATTERN")
                    TextField(RenamePattern.defaultPattern, text: $state.pattern).textFieldStyle(.roundedBorder).font(.callout.monospaced())
                    InspectorLabel(text: "INSERT").padding(.top, 4)
                    FlowChips(items: RenamePattern.tokens) { t in state.pattern += (state.pattern.hasSuffix(" ") || state.pattern.isEmpty ? "" : " ") + t }
                    InspectorLabel(text: "EXAMPLES").padding(.top, 4)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Self.examples, id: \.self) { ex in
                            Button { state.pattern = ex } label: {
                                Text(ex).font(.caption.monospaced()).frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 8).padding(.vertical, 5)
                                    .background(state.pattern == ex ? Theme.accent.opacity(0.2) : Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                    HStack {
                        InspectorLabel(text: "START AT")
                        Spacer()
                        Stepper(value: $state.start, in: 0...99999) { Text("\(state.start)").font(.callout.monospaced()) }
                    }.padding(.top, 4)
                    Text("Changes titles in ASSSETS only. Your files keep their names on disk; exports and sidecars use the new titles.")
                        .font(.caption).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
                }
                .frame(width: 300)
                VStack(alignment: .leading, spacing: 8) {
                    InspectorLabel(text: "PREVIEW")
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(rows) { r in
                                HStack(spacing: 10) {
                                    if let a = byID[r.id] { Thumbnail(asset: a, pixels: 96).frame(width: 40, height: 30).clipShape(RoundedRectangle(cornerRadius: 4)) }
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(r.new).font(.callout.weight(.semibold)).foregroundStyle(r.changed ? Color.primary : Color.secondary).lineLimit(1).truncationMode(.middle)
                                        Text(r.changed ? "was " + r.old : "unchanged").font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                                    }
                                    Spacer(minLength: 4)
                                    if r.clash { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning).help("Another asset in this batch gets the same title") }
                                }
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                Divider().opacity(0.4)
                            }
                        }
                    }
                    .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline))
                    if clashes > 0 {
                        Label("\(clashes) titles repeat. Add {n} to keep them apart.", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Theme.warning)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            HStack {
                Spacer()
                Button("Cancel") { model.batchRename = nil }.keyboardShortcut(.cancelAction)
                Button(changes == 0 ? "Rename" : "Rename \(changes)") { model.applyBatchRename(state) }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(changes == 0)
            }
        }
        .padding(22)
        .frame(width: 820, height: 580)
        .background(Theme.panel)
    }
}

/// Small token buttons that wrap onto new lines.
struct FlowChips: View {
    let items: [String]
    var perRow = 3
    var selected: String? = nil
    let action: (String) -> Void
    var body: some View {
        let rows = stride(from: 0, to: items.count, by: perRow).map { Array(items[$0..<min($0 + perRow, items.count)]) }
        VStack(alignment: .leading, spacing: 5) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 5) {
                    ForEach(row, id: \.self) { t in
                        Button(t) { action(t) }.buttonStyle(.plain).font(.caption.monospaced())
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Theme.accent.opacity(selected == t ? 0.32 : 0.14), in: Capsule())
                            .overlay(Capsule().stroke(Theme.accent.opacity(0.4)))
                            .lineLimit(1).fixedSize()
                    }
                }
            }
        }
    }
}

/// Pick presets, crop mode and a file-name pattern; shows the crops on the first asset before exporting.
struct PresetExportSheet: View {
    @EnvironmentObject var model: StudioLibrary
    @State var state: StudioLibrary.PresetExportState
    @State private var focus: [Double: ExportRect] = [:]
    @State private var base: CGImage?

    var body: some View {
        let byID = Dictionary(uniqueKeysWithValues: model.catalog.assets.map { ($0.id, $0) })
        let assets = state.ids.compactMap { byID[$0] }
        let first = assets.first
        let fileCount = assets.count * ExportPreset.allCases.filter(state.presets.contains).reduce(0) { $0 + ($1 == .web ? 2 : 1) }
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Export Presets").font(.system(size: 20, weight: .bold))
                    Text("\(state.title) · \(fileCount) \(fileCount == 1 ? "file" : "files")").font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Spacer()
                let picks = model.pickIDs
                if !picks.isEmpty && Set(picks) != Set(state.ids) {
                    Button { state.ids = picks; state.title = "Picks"; base = nil } label: { Label("Use Picks (\(picks.count))", systemImage: "checkmark.seal") }.buttonStyle(.bordered)
                }
            }
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    InspectorLabel(text: "PRESETS")
                    ForEach(ExportPreset.allCases) { p in
                        let on = state.presets.contains(p)
                        Button { if on { state.presets.remove(p) } else { state.presets.insert(p) } } label: {
                            HStack(spacing: 10) {
                                Image(systemName: on ? "checkmark.square.fill" : "square").foregroundStyle(on ? Theme.accent : .secondary).font(.system(size: 15))
                                Image(systemName: p.symbol).frame(width: 18).foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(p.rawValue).font(.callout.weight(.semibold))
                                    Text(p.detail).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(on ? Theme.accent.opacity(0.12) : Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? Theme.accent.opacity(0.5) : Theme.hairline))
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    InspectorLabel(text: "CROP").padding(.top, 6)
                    Picker("", selection: $state.crop) { ForEach(CropMode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.segmented).labelsHidden()
                    Text(state.crop == .detail ? "Square and story crops move toward the busiest detail." : "Square and story crops take the middle.")
                        .font(.caption).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
                    Toggle(isOn: $state.embedMetadata) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Embed title, tags, rating and label").font(.callout)
                            Text("In the JPEG and TIFF copies. Originals are never changed.").font(.caption).foregroundStyle(.tertiary)
                        }
                    }.toggleStyle(.checkbox).padding(.top, 4)
                }
                .frame(width: 330)
                VStack(alignment: .leading, spacing: 8) {
                    InspectorLabel(text: first.map { "CROPS · " + $0.title.uppercased() } ?? "CROPS")
                    if let base {
                        let crops = ExportPreset.allCases.filter { state.presets.contains($0) }
                        CropPreview(image: base, windows: crops.map { p in
                            (p.rawValue, p.outputs(width: base.width, height: base.height, crop: state.crop, focus: p.cropAspect.flatMap { focus[$0] })[0].crop)
                        })
                    } else {
                        ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    // Names and folders sit under the crops, so the sheet stays short enough for a 768 pt screen (1.14).
                    VStack(alignment: .leading, spacing: 6) {
                        VStack(alignment: .leading, spacing: 6) {
                            InspectorLabel(text: "FILE NAMES").padding(.top, 6)
                            TextField(FilenamePattern.defaultPattern, text: $state.pattern).textFieldStyle(.roundedBorder).font(.callout.monospaced())
                            Text(FilenamePattern.tokens.joined(separator: "  ")).font(.caption2.monospaced()).foregroundStyle(.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                            InspectorLabel(text: "FOLDERS").padding(.top, 6)
                            TextField("Flat - everything in one folder", text: $state.folders).textFieldStyle(.roundedBorder).font(.callout.monospaced())
                            FlowChips(items: FolderPattern.examples, perRow: 4, selected: state.folders) { state.folders = $0 }
                        }
                        if let a = first, let p = ExportPreset.allCases.first(where: state.presets.contains) {
                            let o = p.outputs(width: base?.width ?? 2048, height: base?.height ?? 2048)[0]
                            let sub = FolderPattern.relativePath(state.folders, asset: a)
                            Text("e.g. " + (sub.isEmpty ? "" : sub + "/") + FilenamePattern.render(state.pattern, asset: a, preset: p, output: o, index: 1))
                                .font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            if !state.folders.trimmingCharacters(in: .whitespaces).isEmpty {
                                let groups = Dictionary(grouping: assets) { FolderPattern.relativePath(state.folders, asset: $0) }
                                Text("\(groups.count) \(groups.count == 1 ? "folder" : "folders"): " + groups.keys.sorted().prefix(4).joined(separator: ", ") + (groups.count > 4 ? ", …" : ""))
                                    .font(.caption).foregroundStyle(.tertiary).lineLimit(2)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            HStack {
                if model.presetExportRunning { ProgressView().controlSize(.small); Text("Exporting…").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button("Cancel") { model.presetExport = nil }.keyboardShortcut(.cancelAction)
                Button("Export…") { model.runPresetExport(state) }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(state.presets.isEmpty || assets.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 860, height: 600)
        .background(Theme.panel)
        .task(id: state.ids.first) { await load(first) }
    }

    private func load(_ a: StudioAsset?) async {
        guard let a else { return }
        let fx = model.effect, amt = model.intensity, psd = model.psdToggled[a.id] ?? [], tiles = model.tiles(for: a), fix = model.fixSeams.contains(a.id)
        let result: (CGImage?, [Double: ExportRect]) = await Task.detached(priority: .userInitiated) {
            guard let img = MediaRenderer.exportBase(a, effect: fx, amount: amt, psdToggled: psd, tiles: tiles, fixSeams: fix) else { return (nil, [:]) }
            var f: [Double: ExportRect] = [:]
            if let small = MediaRenderer.pixelBuffer(from: img, maxPixel: 256) {
                for p in ExportPreset.allCases { if let asp = p.cropAspect { f[asp] = SmartCrop.detailWindow(small, sourceWidth: img.width, sourceHeight: img.height, aspect: asp) } }
            }
            guard let buf = MediaRenderer.pixelBuffer(from: img, maxPixel: 900), let preview = MediaRenderer.cgImage(buf) else { return (img, f) }
            return (preview, PresetExportSheet.scale(f, from: img, to: preview))
        }.value
        base = result.0; focus = result.1
    }

    /// Crop windows are computed on the full image; the preview image is smaller.
    nonisolated static func scale(_ f: [Double: ExportRect], from big: CGImage, to small: CGImage) -> [Double: ExportRect] {
        let s = Double(small.width) / Double(max(1, big.width))
        return f.mapValues { r in ExportRect(x: Int(Double(r.x) * s), y: Int(Double(r.y) * s), w: Int(Double(r.w) * s), h: Int(Double(r.h) * s)) }
    }
}

/// The source image with each preset's crop outlined and labeled.
struct CropPreview: View {
    let image: CGImage
    let windows: [(String, ExportRect)]
    static let colors = [Theme.accent, Theme.smart, Theme.watch, Theme.warning, Color.pink]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Labels live above the image, so a crop hugging an edge can't clip them.
            WrapLayout(spacing: 6) {
                ForEach(Array(windows.enumerated()), id: \.offset) { i, item in
                    HStack(spacing: 5) {
                        Text("\(i + 1)").font(.system(size: 9, weight: .heavy)).frame(width: 15, height: 15).background(Self.colors[i % 5], in: Circle()).foregroundStyle(.black)
                        Text(item.0).font(.system(size: 10.5, weight: .bold)).foregroundStyle(Self.colors[i % 5])
                    }
                    .padding(.horizontal, 7).padding(.vertical, 3).background(Self.colors[i % 5].opacity(0.14), in: Capsule())
                }
            }
            frames
        }
    }
    private var frames: some View {
        GeometryReader { geo in
            let s = min(geo.size.width / CGFloat(image.width), geo.size.height / CGFloat(image.height))
            let w = CGFloat(image.width) * s, h = CGFloat(image.height) * s
            ZStack(alignment: .topLeading) {
                Image(decorative: image, scale: 1).resizable().frame(width: w, height: h).opacity(0.55)
                ForEach(Array(windows.enumerated()), id: \.offset) { i, item in
                    let r = item.1
                    let color = [Theme.accent, Theme.smart, Theme.watch, Theme.warning, Color.pink][i % 5]
                    let full = r.x == 0 && r.y == 0 && r.w == image.width && r.h == image.height
                    ZStack(alignment: .topLeading) {
                        Image(decorative: image, scale: 1).resizable().frame(width: w, height: h)
                            .offset(x: -CGFloat(r.x) * s, y: -CGFloat(r.y) * s)
                            .frame(width: CGFloat(r.w) * s, height: CGFloat(r.h) * s, alignment: .topLeading).clipped()
                            .opacity(full ? 0 : 1)
                        RoundedRectangle(cornerRadius: 3).stroke(color, style: StrokeStyle(lineWidth: 2, dash: full ? [5, 3] : []))
                        // A small numbered corner tag ties each frame to its legend chip; it sits inside the frame, never clipped.
                        Text("\(i + 1)").font(.system(size: 9, weight: .heavy)).frame(width: 15, height: 15)
                            .background(color, in: Circle()).foregroundStyle(.black).padding(4)
                    }
                    .frame(width: CGFloat(r.w) * s, height: CGFloat(r.h) * s)
                    .offset(x: CGFloat(r.x) * s, y: CGFloat(r.y) * s)
                }
            }
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

/// Full-window compare: 2-4 panes (or a swipe between 2) sharing one zoom and pan, with a keep/reject pass.
struct CompareView: View {
    @EnvironmentObject var model: StudioLibrary
    @State private var lastDrag: CGSize = .zero
    @State private var lastMag: CGFloat = 1

    var body: some View {
        if let s = model.compare {
            let byID = Dictionary(uniqueKeysWithValues: model.catalog.assets.map { ($0.id, $0) })
            let assets = s.ids.compactMap { byID[$0] }
            let rows = Dictionary(uniqueKeysWithValues: CompareDiff.rows(assets).map { ($0.id, $0) })
            let shared = CompareDiff.sharedTags(assets)
            ZStack {
                ZStack { Rectangle().fill(.ultraThinMaterial); Color.black.opacity(0.92) }.ignoresSafeArea()
                VStack(spacing: 14) {
                    header(s)
                    Group {
                        if model.compareSwipe && assets.count == 2 {
                            // The frame hugs the first asset's shape instead of letterboxing inside a wide pane.
                            let d = AutoTags.dimensions(in: assets[0].resolution)
                            swipe(assets[0], assets[1], s).aspectRatio(d.map { CGFloat($0.0) / CGFloat(max(1, $0.1)) } ?? 16 / 10, contentMode: .fit)
                        }
                        else {
                            HStack(spacing: 12) {
                                ForEach(Array(assets.enumerated()), id: \.element.id) { i, a in pane(a, index: i, s: s) }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(Array(assets.enumerated()), id: \.element.id) { i, a in card(a, row: rows[a.id], index: i, s: s) }
                    }
                    HStack(spacing: 8) {
                        if !shared.isEmpty {
                            Text("SHARED").font(.system(size: 9.5, weight: .bold)).kerning(1.2).foregroundStyle(.tertiary)
                            Text(shared.prefix(8).joined(separator: "  ·  ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text("K keep  ·  X reject  ·  Tab next  ·  drag or scroll to pan, pinch, wheel or +/- to zoom  ·  S swipe  ·  Return done  ·  Esc cancel")
                            .font(.caption).foregroundStyle(.tertiary).lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
                .padding(.horizontal, 24).padding(.vertical, 20)
            }
        }
    }

    private func header(_ s: CompareSession) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Compare \(s.ids.count)").font(.system(size: 20, weight: .bold))
                Text(s.summary).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 2) {
                modeButton("Side by side", "rectangle.split.3x1", on: !model.compareSwipe) { model.compareSwipe = false }
                modeButton("Swipe", "rectangle.lefthalf.inset.filled", on: model.compareSwipe) { model.compareSwipe = true }.disabled(s.ids.count != 2)
                    .help(s.ids.count == 2 ? "Swipe between the two (S)" : "Swipe works with exactly 2 assets")
            }
            .padding(2).background(Color.white.opacity(0.06), in: Capsule()).overlay(Capsule().stroke(Theme.hairline))
            HStack(spacing: 6) {
                roundButton("minus") { model.compareZoom.zoom(by: 1 / 1.5) }
                Text("\(Int((model.compareZoom.zoom * 100).rounded()))%").font(.callout.monospacedDigit()).frame(width: 48)
                roundButton("plus") { model.compareZoom.zoom(by: 1.5) }
                Button("Fit") { model.compareZoom.reset() }.buttonStyle(.bordered).disabled(model.compareZoom.isFit)
            }
            Menu {
                Button("Keeps don't change ratings") { model.keepRating = 0 }
                ForEach(3...5, id: \.self) { n in Button("Keeps get at least " + String(repeating: "★", count: n)) { model.keepRating = n } }
            } label: {
                Label(model.keepRating == 0 ? "Keep: no rating" : "Keep: " + String(repeating: "★", count: model.keepRating), systemImage: "star.circle")
                    .font(.system(size: 11.5, weight: .semibold))
            }.menuStyle(.borderlessButton).fixedSize().help("Stars a kept asset gets when you press Done")
            Button { model.closeCompare(apply: true) } label: { Label("Done", systemImage: "checkmark") }
                .buttonStyle(.borderedProminent).help("Save keeps to Picks (Return)")
            Button { model.closeCompare(apply: false) } label: {
                Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).padding(9).background(Color.white.opacity(0.1), in: Circle())
            }.buttonStyle(.plain).help("Close without saving (Esc)")
        }
    }

    private func modeButton(_ title: String, _ symbol: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.system(size: 11.5, weight: .semibold))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(on ? Theme.accent : Color.clear, in: Capsule())
                .foregroundStyle(on ? Color.white : Color.white.opacity(0.75))
        }.buttonStyle(.plain)
    }

    private func roundButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .bold)).frame(width: 26, height: 26).background(Color.white.opacity(0.1), in: Circle())
        }.buttonStyle(.plain)
    }

    /// The asset drawn at the shared zoom and pan inside a clipped frame.
    private func zoomed(_ a: StudioAsset, size: CGSize) -> some View {
        let z = model.compareZoom
        return ProcessedPreview(asset: a, effect: .original, amount: 0, pixels: 2400, psdToggled: model.psdToggled[a.id] ?? [], fit: true)
            .frame(width: size.width, height: size.height)
            .scaleEffect(z.zoom)
            .offset(x: z.panX * size.width, y: z.panY * size.height)
            .frame(width: size.width, height: size.height).clipped()
    }

    private func gestures(size: CGSize) -> some Gesture {
        let drag = DragGesture(minimumDistance: 2)
            .onChanged { v in
                let d = CGSize(width: v.translation.width - lastDrag.width, height: v.translation.height - lastDrag.height)
                lastDrag = v.translation
                model.compareZoom.pan(dx: d.width / max(1, size.width), dy: d.height / max(1, size.height))
            }
            .onEnded { _ in lastDrag = .zero }
        let mag = MagnifyGesture()
            .onChanged { v in
                model.compareZoom.zoom(by: v.magnification / lastMag, anchorX: v.startAnchor.x, anchorY: v.startAnchor.y)
                lastMag = v.magnification
            }
            .onEnded { _ in lastMag = 1 }
        return drag.simultaneously(with: mag)
    }

    private func pane(_ a: StudioAsset, index: Int, s: CompareSession) -> some View {
        GeometryReader { geo in
            zoomed(a, size: geo.size)
                .background(Color(white: 0.06))
                .overlay(alignment: .topLeading) { verdictBadge(s.verdicts[a.id]).padding(10) }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(index == s.focus ? Theme.accent : Theme.hairline, lineWidth: index == s.focus ? 2.5 : 1))
                .contentShape(Rectangle())
                .gesture(gestures(size: geo.size))
                .simultaneousGesture(TapGesture().onEnded { model.compare?.focus = index })
        }
    }

    private func swipe(_ a: StudioAsset, _ b: StudioAsset, _ s: CompareSession) -> some View {
        GeometryReader { geo in
            let x = geo.size.width * model.swipeSplit
            ZStack(alignment: .leading) {
                zoomed(b, size: geo.size)
                zoomed(a, size: geo.size).mask(alignment: .leading) { Rectangle().frame(width: x) }
                Rectangle().fill(Color.white).frame(width: 2).offset(x: x - 1).shadow(color: .black.opacity(0.6), radius: 4)
                Circle().fill(Color.white).frame(width: 30, height: 30)
                    .overlay(Image(systemName: "arrow.left.and.right").font(.system(size: 11, weight: .bold)).foregroundStyle(.black))
                    .offset(x: x - 15)
                    .gesture(DragGesture(coordinateSpace: .named("swipe")).onChanged { v in model.swipeSplit = min(0.98, max(0.02, v.location.x / max(1, geo.size.width))) })
            }
            .coordinateSpace(name: "swipe")
            .background(Color(white: 0.06))
            .overlay(alignment: .topLeading) { HStack(spacing: 6) { Text(a.title).fontWeight(.semibold); verdictBadge(s.verdicts[a.id]) }.font(.caption).padding(8).background(.black.opacity(0.55), in: Capsule()).padding(10) }
            .overlay(alignment: .topTrailing) { HStack(spacing: 6) { verdictBadge(s.verdicts[b.id]); Text(b.title).fontWeight(.semibold) }.font(.caption).padding(8).background(.black.opacity(0.55), in: Capsule()).padding(10) }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline))
            .contentShape(Rectangle())
            .gesture(gestures(size: geo.size))
        }
    }

    @ViewBuilder private func verdictBadge(_ v: CompareVerdict?) -> some View {
        switch v {
        case .keep?: Label("Keep", systemImage: "checkmark.circle.fill").font(.system(size: 11, weight: .bold)).padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color(red: 0.16, green: 0.55, blue: 0.3), in: Capsule()).foregroundStyle(.white)
        case .reject?: Label("Reject", systemImage: "xmark.circle.fill").font(.system(size: 11, weight: .bold)).padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color(red: 0.62, green: 0.18, blue: 0.22), in: Capsule()).foregroundStyle(.white)
        case nil: EmptyView()
        }
    }

    private func card(_ a: StudioAsset, row: CompareDiff.Row?, index: Int, s: CompareSession) -> some View {
        let focused = index == s.focus
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(a.title).font(.callout.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 4)
                Button { model.compare?.focus = index; model.markCompare(.keep) } label: { Image(systemName: s.verdicts[a.id] == .keep ? "checkmark.circle.fill" : "checkmark.circle") }
                    .buttonStyle(.plain).foregroundStyle(s.verdicts[a.id] == .keep ? Color.green : Color.secondary).help("Keep (K)")
                Button { model.compare?.focus = index; model.markCompare(.reject) } label: { Image(systemName: s.verdicts[a.id] == .reject ? "xmark.circle.fill" : "xmark.circle") }
                    .buttonStyle(.plain).foregroundStyle(s.verdicts[a.id] == .reject ? Color.red : Color.secondary).help("Reject (X)")
            }
            Text(a.resolution).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1)
            HStack(spacing: 4) {
                ForEach(Array(a.palette.prefix(5).enumerated()), id: \.offset) { _, hex in
                    let unique = row?.uniqueColors.contains(hex) == true
                    Circle().fill(Color(hex: hex)).frame(width: 14, height: 14)
                        .overlay(Circle().stroke(unique ? Color.white : Color.white.opacity(0.2), lineWidth: unique ? 1.5 : 1))
                        .help(unique ? "\(hex): only in this asset" : hex)
                }
            }
            let only = row?.uniqueTags.prefix(4) ?? []
            Text(only.isEmpty ? "No tags the others lack" : "Only here: " + only.joined(separator: ", "))
                .font(.caption2).foregroundStyle(only.isEmpty ? .tertiary : .secondary).lineLimit(1)
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(focused ? Theme.accent.opacity(0.14) : Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(focused ? Theme.accent.opacity(0.6) : Theme.hairline))
        .contentShape(Rectangle()).onTapGesture { model.compare?.focus = index }
    }
}

struct ViewerArrow: View {
    let symbol: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 18, weight: .semibold)).frame(width: 40, height: 64)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain)
    }
}

/// Repeat preview and seam status for textures, floating over the inspector preview.
struct TileControls: View {
    @EnvironmentObject var model: StudioLibrary
    @ObservedObject private var store = ThumbnailStore.shared
    let asset: StudioAsset
    var body: some View {
        let report = store.seamReport(asset)
        let fixing = model.fixSeams.contains(asset.id)
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                ForEach([1, 2, 3], id: \.self) { n in
                    Button { model.tileRepeat = n } label: {
                        Text(n == 1 ? "1×" : "\(n)×\(n)").font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(model.tileRepeat == n ? Theme.accent : Color.clear, in: Capsule())
                            .foregroundStyle(model.tileRepeat == n ? Color.white : Color.white.opacity(0.72))
                    }.buttonStyle(.plain).help(n == 1 ? "Single tile" : "Preview a \(n) × \(n) repeat")
                }
            }
            .padding(2).background(Color(white: 0.07).opacity(0.9), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.12)))
            Spacer(minLength: 4)
            if let report {
                if report.tileable && !fixing {
                    Label("Seamless", systemImage: "checkmark.seal.fill").font(.system(size: 10.5, weight: .semibold))
                        .padding(.horizontal, 9).padding(.vertical, 5).background(Color(white: 0.07).opacity(0.9), in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.12))).foregroundStyle(Color(red: 0.42, green: 0.92, blue: 0.55))
                } else {
                    Button {
                        if fixing { model.fixSeams.remove(asset.id) } else { model.fixSeams.insert(asset.id) }
                    } label: {
                        Label(fixing ? "Seams fixed" : "Visible seam · Fix", systemImage: fixing ? "wand.and.stars" : "exclamationmark.triangle.fill")
                            .font(.system(size: 10.5, weight: .semibold))
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(fixing ? Theme.accent : Color(white: 0.07).opacity(0.9), in: Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.12)))
                            .foregroundStyle(fixing ? Color.white : Color.orange)
                    }.buttonStyle(.plain).help(fixing ? "Show the original file" : "Blend the edges so the texture repeats cleanly (preview and export only)")
                }
            }
        }
    }
}

struct PsdLayersPanel: View {
    @EnvironmentObject var model: StudioLibrary
    @ObservedObject private var store = ThumbnailStore.shared
    let asset: StudioAsset
    var body: some View {
        let toggled = model.psdToggled[asset.id] ?? []
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                InspectorLabel(text: "LAYERS")
                Spacer()
                if !toggled.isEmpty { Button("Reset") { model.resetPsdLayers(asset.id) }.buttonStyle(.plain).font(.caption).foregroundStyle(Theme.accent) }
            }
            if let doc = store.psdDocument(asset) {
                VStack(spacing: 0) {
                    ForEach(doc.panelLayers, id: \.index) { entry in
                        let L = entry.layer
                        let visible = toggled.contains(entry.index) ? L.hidden : !L.hidden
                        HStack(spacing: 8) {
                            Button { model.togglePsdLayer(entry.index, of: asset.id) } label: {
                                Image(systemName: visible ? "eye" : "eye.slash").font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(visible ? Color.primary : Color.secondary).frame(width: 20)
                            }.buttonStyle(.plain).help(visible ? "Hide layer" : "Show layer")
                            Image(systemName: L.name.contains("Smart Object") ? "square.on.square.badge.person.crop" : "square.fill.on.square")
                                .font(.system(size: 10)).foregroundStyle(L.name.contains("Smart Object") ? Theme.accent : Color.secondary).frame(width: 16)
                            Text(L.name).font(.system(size: 12)).lineLimit(1).foregroundStyle(visible ? Color.primary : Color.secondary)
                            Spacer(minLength: 4)
                            Text(L.blendKey == "norm" && L.opacity == 255 ? "" : "\(L.blendName) \(Int((Double(L.opacity) / 255 * 100).rounded()))%")
                                .font(.system(size: 9.5).monospacedDigit()).foregroundStyle(.tertiary).lineLimit(1)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(visible ? Color.white.opacity(0.035) : Color.clear)
                        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
                    }
                }
                .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.hairline))
                .clipShape(RoundedRectangle(cornerRadius: 9))
                Text("Toggles change the preview and PNG export. The file is never modified.").font(.caption2).foregroundStyle(.tertiary)
            } else {
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Reading layers…").font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}

struct EffectStrip: View {
    @EnvironmentObject var model: StudioLibrary
    let asset: StudioAsset
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                InspectorLabel(text: "LIVE EFFECTS")
                Spacer()
                if model.effect != .original { Button("Reset") { model.effect = .original; model.intensity = 0.75 }.buttonStyle(.plain).font(.caption).foregroundStyle(Theme.accent) }
            }.padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(EffectPreset.allCases) { preset in
                        Button { model.effect = preset } label: {
                            VStack(spacing: 4) {
                                ProcessedPreview(asset: asset, effect: preset, amount: 0.75, pixels: 180)
                                    .frame(width: 62, height: 44).clipShape(RoundedRectangle(cornerRadius: 7))
                                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(model.effect == preset ? Theme.accent : Theme.hairline, lineWidth: model.effect == preset ? 2 : 1))
                                Text(preset.rawValue).font(.system(size: 9.5, weight: model.effect == preset ? .semibold : .regular)).lineLimit(1)
                                    .foregroundStyle(model.effect == preset ? Color.primary : Color.secondary)
                            }.frame(width: 64)
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 16)
            }
            HStack(spacing: 8) {
                Text("Amount").font(.caption).foregroundStyle(.secondary)
                Slider(value: $model.intensity).disabled(model.effect == .original || model.effect == .mono || model.effect == .chrome)
                Text("\(Int(model.intensity * 100))%").font(.caption.monospacedDigit()).frame(width: 36, alignment: .trailing)
            }.padding(.horizontal, 16)
        }
    }
}

struct BatchInspector: View {
    @EnvironmentObject var model: StudioLibrary
    let assets: [StudioAsset]
    @State private var tagText = ""
    var body: some View {
        let ids = Set(assets.map(\.id))
        let common = model.catalog.commonTags(ids)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ZStack {
                    ForEach(Array(assets.prefix(4).enumerated().reversed()), id: \.offset) { i, a in
                        Thumbnail(asset: a, pixels: 360).frame(width: 190, height: 136).clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.2)))
                            .shadow(color: .black.opacity(0.45), radius: 10, y: 6)
                            .rotationEffect(.degrees(Double(i) * 5 - 6)).offset(x: CGFloat(i) * 14 - 20, y: CGFloat(i) * -6)
                    }
                }.frame(maxWidth: .infinity).frame(height: 190)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(assets.count) assets selected").font(.system(size: 17, weight: .bold))
                    Text(Dictionary(grouping: assets, by: \.kind).map { "\($0.value.count) \($0.key.rawValue.lowercased())" }.sorted().joined(separator: " • "))
                        .font(.caption).foregroundStyle(.secondary)
                }
                InspectorLabel(text: "BATCH TAGS")
                HStack {
                    TextField("Tags for all \(assets.count), comma separated", text: $tagText).textFieldStyle(.roundedBorder)
                        .onSubmit { model.addTags(tagText, to: ids); tagText = "" }
                    Button("Apply") { model.addTags(tagText, to: ids); tagText = "" }.buttonStyle(.borderedProminent).disabled(tagText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if common.isEmpty { Text("No tags shared by every selected asset.").font(.caption).foregroundStyle(.tertiary) }
                else {
                    Text("Shared by all").font(.caption).foregroundStyle(.secondary)
                    WrapLayout(spacing: 5) { ForEach(common, id: \.self) { tag in TagChip(tag: tag) { model.removeTag(tag, from: ids) } } }
                }
                let pending = assets.reduce(0) { $0 + $1.suggestedTags.count }
                if pending > 0 {
                    HStack {
                        Label("\(pending) suggested \(pending == 1 ? "tag" : "tags") across the selection", systemImage: "sparkles").font(.caption).foregroundStyle(Theme.smart)
                        Spacer()
                        Button("Accept all") { model.acceptSuggestions(for: ids) }.buttonStyle(.bordered).tint(Theme.smart)
                    }
                }
                InspectorLabel(text: "ORGANIZE")
                HStack(spacing: 8) {
                    Button { model.toggleFavorite(ids) } label: { Label(assets.allSatisfy { $0.favorite } ? "Unfavorite" : "Favorite All", systemImage: "heart") }.buttonStyle(.bordered)
                    MoveMenu(ids: ids).buttonStyle(.bordered)
                }
                Button { model.newCollection(with: ids) } label: { Label("New Collection from Selection", systemImage: "folder.badge.plus") }.buttonStyle(.bordered)
                InspectorLabel(text: "OUTPUT")
                HStack(spacing: 8) {
                    ExportMenuButton(ids: ids, title: "Export \(ids.count)")
                    ShareButton(ids: ids)
                    Button { model.copyKeywords(ids) } label: { Label("Keywords", systemImage: "doc.on.doc") }.buttonStyle(.bordered)
                }
                Button(role: .destructive) { model.pendingRemoval = ids } label: { Label("Remove from Library…", systemImage: "trash") }.buttonStyle(.borderless).padding(.top, 4)
            }
            .padding(16)
        }
        .background(Theme.panel)
    }
}

struct LoopingVideo: View {
    let url: URL
    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?
    var body: some View {
        VideoPlayer(player: player)
            .onAppear {
                let q = AVQueuePlayer(); q.isMuted = true
                looper = AVPlayerLooper(player: q, templateItem: AVPlayerItem(url: url))
                player = q; q.play()
            }
            .onDisappear { player?.pause(); player = nil; looper = nil }
    }
}

struct AudioButton: View {
    let url: URL
    @State private var sound: NSSound?
    @State private var playing = false
    var body: some View {
        Button {
            if playing { sound?.stop(); playing = false }
            else { let s = sound ?? NSSound(contentsOf: url, byReference: true); sound = s; s?.play(); playing = s != nil }
        } label: {
            Image(systemName: playing ? "stop.fill" : "play.fill").font(.title2).padding(16).background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .onDisappear { sound?.stop() }
    }
}

/// Wrapping row of chips (tags wrap instead of running off the inspector edge).
struct WrapLayout: Layout {
    var spacing: CGFloat = 5
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += line + spacing; line = 0 }
            x += size.width + spacing; line = max(line, size.height)
        }
        return CGSize(width: width, height: y + line)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += line + spacing; line = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing; line = max(line, size.height)
        }
    }
}

// MARK: - Thumbnails and rendering

/// Caches decoded previews. Real files decode off the main thread through ImageIO/AVFoundation.
/// Collects the local facts behind suggested tags: real pixels, alpha, seams, durations and peaks.
enum AutoTagReader {
    static func facts(for a: StudioAsset) async -> AutoTags.Facts {
        var f = AutoTags.Facts(kind: a.kind, palette: a.palette)
        if let d = AutoTags.dimensions(in: a.resolution) { f.width = d.0; f.height = d.1 }
        guard let path = a.importedPath, FileManager.default.fileExists(atPath: path) else { return f }
        let url = URL(fileURLWithPath: path)
        switch url.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "tif", "tiff", "heic", "gif", "webp":
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { break }
            if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
               let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int { f.width = w; f.height = h }
            if let small = MediaRenderer.pixelBuffer(fromSource: src, maxPixel: 256) {
                // Transparent only when real pixels are see-through, not just because the file has an alpha channel.
                var clear = 0
                for i in stride(from: 3, to: small.rgba.count, by: 4) where small.rgba[i] < 250 { clear += 1 }
                f.hasAlpha = clear * 50 > small.width * small.height
                if a.kind == .texture { f.tileable = Seamless.analyze(small).tileable }
            }
        case "mov", "mp4", "m4v", "webm":
            if let d = try? await AVURLAsset(url: url).load(.duration), d.isNumeric { f.durationSeconds = d.seconds }
        case "wav":
            if let data = try? Data(contentsOf: url), let s = AsssetsCore.Waveform.summarize(wav: data, buckets: 8) {
                f.durationSeconds = s.duration; f.loudnessDBFS = s.peakDBFS
            }
        case "aif", "aiff", "mp3", "m4a":
            if let d = try? await AVURLAsset(url: url).load(.duration), d.isNumeric { f.durationSeconds = d.seconds }
        default: break
        }
        return f
    }
}

@MainActor
final class ThumbnailStore: ObservableObject {
    static let shared = ThumbnailStore()
    @Published private(set) var revision = 0
    private var cache: [String: CGImage] = [:]
    private var inflight: Set<String> = []

    func image(for asset: StudioAsset, pixels: Int) -> CGImage? {
        let key = "\(asset.id.uuidString)|\(asset.importedPath ?? "")|\(pixels)"
        if let hit = cache[key] { return hit }
        if asset.importedPath == nil {
            let img = MediaRenderer.generated(asset, width: pixels)
            cache[key] = img
            return img
        }
        guard !inflight.contains(key) else { return nil }
        inflight.insert(key)
        let snapshot = asset
        Task.detached(priority: .userInitiated) {
            let img = await MediaRenderer.thumbnail(for: snapshot, maxPixel: pixels)
            await MainActor.run {
                self.cache[key] = img ?? MediaRenderer.generated(snapshot, width: pixels)
                self.inflight.remove(key)
                self.revision += 1
            }
        }
        return nil
    }

    private var psdDocs: [String: PsdDocument] = [:]
    private var psdImages: [String: CGImage] = [:]

    /// Parsed layer stack for a PSD, loaded off the main thread.
    func psdDocument(_ asset: StudioAsset) -> PsdDocument? {
        guard let path = asset.importedPath else { return nil }
        if let d = psdDocs[path] { return d }
        let key = "doc|" + path
        guard !inflight.contains(key) else { return nil }
        inflight.insert(key)
        Task.detached(priority: .userInitiated) {
            let doc = (try? Data(contentsOf: URL(fileURLWithPath: path))).flatMap { try? PsdLayers.read($0) }
            await MainActor.run {
                if let doc { self.psdDocs[path] = doc }
                self.inflight.remove(key); self.revision += 1
            }
        }
        return nil
    }

    /// Live composite honoring the user's layer toggles.
    func psdComposite(_ asset: StudioAsset, toggled: Set<Int>, maxPixel: Int) -> CGImage? {
        guard let path = asset.importedPath else { return nil }
        let key = path + "|" + toggled.sorted().map(String.init).joined(separator: ",") + "|\(maxPixel)"
        if let hit = psdImages[key] { return hit }
        guard let doc = psdDocument(asset) else { return image(for: asset, pixels: maxPixel) }
        guard !inflight.contains(key) else { return psdImages.first { $0.key.hasPrefix(path + "|") }?.value }
        inflight.insert(key)
        Task.detached(priority: .userInitiated) {
            let img = MediaRenderer.cgImage(doc.composite(toggled: toggled), maxPixel: maxPixel)
            await MainActor.run {
                if self.psdImages.count > 60 { self.psdImages.removeAll() }
                if let img { self.psdImages[key] = img }
                self.inflight.remove(key); self.revision += 1
            }
        }
        return psdImages.first { $0.key.hasPrefix(path + "|") }?.value
    }

    private var fx: [String: CGImage] = [:]
    private var tileCache: [String: CGImage] = [:]
    private var seamCache: [String: Seamless.Report] = [:]

    /// Repeat preview: downsized first so a 3 x 3 grid stays small, then optionally seam-fixed and tiled.
    func tiled(_ img: CGImage, id: String, times n: Int, fixSeams: Bool) -> CGImage {
        let key = "\(id)|\(img.width)|\(n)|\(fixSeams)"
        if let hit = tileCache[key] { return hit }
        guard var buf = MediaRenderer.pixelBuffer(from: img, maxPixel: n > 1 ? 640 : 1400) else { return img }
        if fixSeams { buf = Seamless.makeTileable(buf) }
        let out = MediaRenderer.cgImage(Seamless.tiled(buf, times: n)) ?? img
        if tileCache.count > 40 { tileCache.removeAll() }
        tileCache[key] = out
        return out
    }

    /// Seam check on the displayed image (cached per asset and size).
    func seamReport(_ asset: StudioAsset) -> Seamless.Report? {
        guard let img = image(for: asset, pixels: 1400) else { return nil }
        let key = "\(asset.id)|\(img.width)"
        if let hit = seamCache[key] { return hit }
        guard let buf = MediaRenderer.pixelBuffer(from: img, maxPixel: 512) else { return nil }
        let r = Seamless.analyze(buf)
        seamCache[key] = r
        return r
    }

    func processed(_ base: CGImage, id: String, effect: EffectPreset, amount: Double) -> CGImage {
        guard effect != .original else { return base }
        let key = "\(id)|\(base.width)|\(effect.rawValue)|\(Int(amount * 50))"
        if let hit = fx[key] { return hit }
        let out = MediaRenderer.apply(effect, amount: amount, to: base) ?? base
        if fx.count > 400 { fx.removeAll() }
        fx[key] = out
        return out
    }
}

struct Thumbnail: View {
    let asset: StudioAsset
    let pixels: Int
    @ObservedObject private var store = ThumbnailStore.shared
    var body: some View {
        GeometryReader { geo in
            if let cg = store.image(for: asset, pixels: pixels) {
                Image(decorative: cg, scale: 1).resizable().scaledToFill().frame(width: geo.size.width, height: geo.size.height).clipped()
            } else {
                ZStack {
                    LinearGradient(colors: asset.palette.prefix(3).map { Color(hex: $0) }, startPoint: .topLeading, endPoint: .bottomTrailing).opacity(0.5)
                    ProgressView().controlSize(.small)
                }
            }
        }
    }
}

struct ProcessedPreview: View {
    let asset: StudioAsset
    let effect: EffectPreset
    let amount: Double
    var pixels = 1400
    var psdToggled: Set<Int> = []
    var tiles = 1
    var fixSeams = false
    var fit = false
    @ObservedObject private var store = ThumbnailStore.shared
    var body: some View {
        GeometryReader { geo in
            let isPsd = asset.importedPath?.lowercased().hasSuffix(".psd") == true
            let fetched: CGImage? = isPsd ? store.psdComposite(asset, toggled: psdToggled, maxPixel: pixels) : store.image(for: asset, pixels: pixels)
            if let base = fetched {
                let key = isPsd ? asset.id.uuidString + "|" + psdToggled.sorted().map(String.init).joined(separator: ",") : asset.id.uuidString
                let fx = store.processed(base, id: key, effect: effect, amount: amount)
                let cg = (tiles > 1 || fixSeams) ? store.tiled(fx, id: key + "|\(effect.rawValue)|\(Int(amount * 50))", times: tiles, fixSeams: fixSeams) : fx
                Image(decorative: cg, scale: 1).resizable()
                    .aspectRatio(contentMode: fit || asset.kind == .vector || asset.kind == .mockup ? .fit : .fill)
                    .frame(width: geo.size.width, height: geo.size.height).clipped()
            } else {
                ProgressView().controlSize(.small).frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }
}

enum MediaRenderer {
    static let ciContext = CIContext(options: [.cacheIntermediates: false])

    static func thumbnail(for asset: StudioAsset, maxPixel: Int) async -> CGImage? {
        guard let path = asset.importedPath else { return nil }
        let url = URL(fileURLWithPath: path)
        switch url.pathExtension.lowercased() {
        case "svg":
            guard let text = try? String(contentsOf: url, encoding: .utf8), let scene = VectorScene.parse(text) else { return nil }
            return vector(scene, width: maxPixel)
        case "mov", "mp4", "m4v", "webm":
            let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: maxPixel, height: maxPixel)
            if let frame = try? await gen.image(at: CMTime(seconds: 1.0, preferredTimescale: 600)).image { return frame }
            return try? await gen.image(at: .zero).image
        case "wav":
            guard let data = try? Data(contentsOf: url), let s = AsssetsCore.Waveform.summarize(wav: data, buckets: 72) else { return nil }
            return waveform(s.peaks, palette: asset.palette, width: maxPixel)
        case "aif", "aiff", "mp3", "m4a":
            return nil
        case "pdf", "ai", "eps":
            guard let img = NSImage(contentsOf: url) else { return nil }
            var rect = CGRect(x: 0, y: 0, width: maxPixel, height: Int(Double(maxPixel) / max(0.1, img.size.width / max(1, img.size.height))))
            return img.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        default:
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                         kCGImageSourceThumbnailMaxPixelSize: maxPixel, kCGImageSourceShouldCacheImmediately: true]
            return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
        }
    }

    static func bitmap(_ w: Int, _ h: Int) -> CGContext? {
        CGContext(data: nil, width: max(1, w), height: max(1, h), bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    static func cg(_ hex: String, _ alpha: CGFloat = 1) -> CGColor { (NSColor(hex: hex) ?? .gray).withAlphaComponent(alpha).cgColor }

    /// Renders the shipped SVG subset natively (top-left SVG origin mapped onto CoreGraphics).
    static func vector(_ scene: VectorScene, width: Int) -> CGImage? {
        let scale = Double(width) / scene.width
        let h = Int(scene.height * scale)
        guard let ctx = bitmap(width, h) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: CGFloat(scale), y: CGFloat(-scale))
        for el in scene.elements {
            ctx.saveGState()
            ctx.setAlpha(CGFloat(el.opacity))
            let path = CGMutablePath()
            var box = CGRect.zero
            switch el.shape {
            case .rect(let x, let y, let w, let hh): box = CGRect(x: x, y: y, width: w, height: hh); path.addRect(box)
            case .ellipse(let cx, let cy, let rx, let ry): box = CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2); path.addEllipse(in: box)
            case .polygon(let pts):
                path.addLines(between: pts.map { CGPoint(x: $0.x, y: $0.y) }); path.closeSubpath(); box = path.boundingBox
            case .text(let x, let y, let size, let string):
                var color = NSColor.white.cgColor
                if case .color(let hex) = el.fill { color = cg(hex) }
                let font = NSFont.systemFont(ofSize: CGFloat(size), weight: .bold)
                let attr = NSAttributedString(string: string, attributes: [.font: font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): color])
                let line = CTLineCreateWithAttributedString(attr)
                ctx.translateBy(x: CGFloat(x), y: CGFloat(y)); ctx.scaleBy(x: 1, y: -1)
                ctx.textPosition = .zero
                CTLineDraw(line, ctx)
                ctx.restoreGState()
                continue
            }
            switch el.fill {
            case .none: break
            case .color(let hex): ctx.addPath(path); ctx.setFillColor(cg(hex)); ctx.fillPath()
            case .gradient(let stops):
                if let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: stops.map { cg($0) } as CFArray, locations: nil) {
                    ctx.addPath(path); ctx.clip()
                    ctx.drawLinearGradient(g, start: CGPoint(x: box.minX, y: box.minY), end: CGPoint(x: box.maxX, y: box.maxY), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                }
            }
            ctx.restoreGState()
        }
        return ctx.makeImage()
    }

    /// Waveform card drawn from the file's real peaks.
    static func waveform(_ peaks: [Float], palette: [String], width: Int) -> CGImage? {
        let h = Int(Double(width) / 1.36)
        guard let ctx = bitmap(width, h) else { return nil }
        let colors = (palette.count >= 3 ? palette : ["#111318", "#28324A", "#C25BFF"]).map { cg($0) }
        if let bg = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [colors[0], colors[1]] as CFArray, locations: nil) {
            ctx.drawLinearGradient(bg, start: .zero, end: CGPoint(x: width, y: h), options: [])
        }
        let n = max(1, peaks.count)
        let inset = CGFloat(width) * 0.08
        let slot = (CGFloat(width) - inset * 2) / CGFloat(n)
        let mid = CGFloat(h) / 2
        ctx.setFillColor(colors[min(2, colors.count - 1)])
        for (i, p) in peaks.enumerated() {
            let bar = max(2, CGFloat(p) * CGFloat(h) * 0.62)
            let r = CGRect(x: inset + CGFloat(i) * slot + slot * 0.18, y: mid - bar / 2, width: slot * 0.64, height: bar)
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: slot * 0.3, cornerHeight: slot * 0.3, transform: nil)); ctx.fillPath()
        }
        return ctx.makeImage()
    }

    /// Original generated study art for catalog records without a file.
    static func generated(_ asset: StudioAsset, width: Int) -> CGImage? {
        let h = Int(Double(width) / 1.36)
        guard let ctx = bitmap(width, h) else { return nil }
        let colors = asset.palette.map { cg($0) }
        if colors.count >= 2, let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: h), end: CGPoint(x: width, y: 0), options: [])
        }
        var rng = Seeded(seed: UInt64(asset.seed + 500))
        ctx.setBlendMode(.screen)
        let W = CGFloat(width), H = CGFloat(h)
        for i in 0..<18 {
            let w = CGFloat(rng.next() % 100 + 20) / 400 * W
            let x = CGFloat(rng.next() % 1000) / 1000 * W, y = CGFloat(rng.next() % 1000) / 1000 * H
            ctx.setFillColor((colors.isEmpty ? NSColor.white.cgColor : colors[i % colors.count]).copy(alpha: 0.16) ?? NSColor.white.cgColor)
            if asset.kind == .vector || asset.kind == .audio { ctx.fillEllipse(in: CGRect(x: x - w / 2, y: y - w / 2, width: w, height: w)) }
            else { let p = CGMutablePath(); p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: min(W, x + w), y: H)); p.addLine(to: CGPoint(x: max(0, x - w), y: H)); p.closeSubpath(); ctx.addPath(p); ctx.fillPath() }
        }
        ctx.setBlendMode(.normal)
        if asset.kind == .audio {
            ctx.setFillColor(NSColor.white.withAlphaComponent(0.85).cgColor)
            for i in 0..<40 {
                let bar = CGFloat(6 + abs((i * 13 + asset.seed) % 28)) / 34 * H * 0.5
                ctx.fill(CGRect(x: W * 0.1 + CGFloat(i) * W * 0.02, y: H / 2 - bar / 2, width: W * 0.011, height: bar))
            }
        }
        let label = asset.kind == .mockup ? "SMART OBJECT" : asset.kind == .video ? "4K MOTION" : asset.kind == .audio ? "" : asset.title.uppercased()
        if !label.isEmpty {
            let font = NSFont.systemFont(ofSize: min(38, W / 11), weight: .heavy)
            let attr = NSAttributedString(string: label, attributes: [.font: font, .kern: 2, NSAttributedString.Key(kCTForegroundColorAttributeName as String): NSColor.white.withAlphaComponent(0.9).cgColor])
            let line = CTLineCreateWithAttributedString(attr)
            let bounds = CTLineGetBoundsWithOptions(line, [])
            ctx.textPosition = CGPoint(x: (W - bounds.width) / 2, y: H / 2 - bounds.height / 3)
            CTLineDraw(line, ctx)
        }
        return ctx.makeImage()
    }

    static func apply(_ preset: EffectPreset, amount: Double, to image: CGImage) -> CGImage? {
        guard preset != .original else { return image }
        let ci = CIImage(cgImage: image)
        var out = ci
        switch preset {
        case .vivid: let f = CIFilter.vibrance(); f.inputImage = ci; f.amount = Float(amount * 1.4); out = f.outputImage ?? ci
        case .mono: let f = CIFilter.photoEffectNoir(); f.inputImage = ci; out = f.outputImage ?? ci
        case .warm: let f = CIFilter.temperatureAndTint(); f.inputImage = ci; f.neutral = CIVector(x: 6500, y: 0); f.targetNeutral = CIVector(x: 6500 - 1800 * amount, y: 0); out = f.outputImage ?? ci
        case .cool: let f = CIFilter.temperatureAndTint(); f.inputImage = ci; f.neutral = CIVector(x: 6500, y: 0); f.targetNeutral = CIVector(x: 6500 + 2200 * amount, y: 0); out = f.outputImage ?? ci
        case .chrome: let f = CIFilter.photoEffectChrome(); f.inputImage = ci; out = f.outputImage ?? ci
        case .blur:
            let f = CIFilter.gaussianBlur(); f.inputImage = ci.clampedToExtent(); f.radius = Float(amount * 18 * Double(image.width) / 1400)
            out = (f.outputImage ?? ci).cropped(to: ci.extent)
        case .poster: let f = CIFilter.colorPosterize(); f.inputImage = ci; f.levels = Float(3 + (1 - amount) * 9); out = f.outputImage ?? ci
        case .original: break
        }
        return ciContext.createCGImage(out, from: ci.extent)
    }

    /// Full-resolution export: real files are processed at native size, generated studies at 2400 px.
    /// Converts a core pixel buffer to a CGImage, downscaled so the long side is at most `maxPixel`.
    static func cgImage(_ buf: PixelBuffer, maxPixel: Int = 0) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(buf.rgba) as CFData),
              let full = CGImage(width: buf.width, height: buf.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: buf.width * 4,
                                 space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                                 provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        guard maxPixel > 0, max(buf.width, buf.height) > maxPixel else { return full }
        let scale = Double(maxPixel) / Double(max(buf.width, buf.height))
        let w = Int(Double(buf.width) * scale), h = Int(Double(buf.height) * scale)
        guard let ctx = bitmap(w, h) else { return full }
        ctx.interpolationQuality = .high
        ctx.draw(full, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    /// Draws a CGImage into 8-bit RGBA (straight alpha), downscaled so the long side is at most `maxPixel`.
    static func pixelBuffer(from img: CGImage, maxPixel: Int) -> PixelBuffer? {
        let scale = min(1, Double(maxPixel) / Double(max(img.width, img.height)))
        let w = max(1, Int(Double(img.width) * scale)), h = max(1, Int(Double(img.height) * scale))
        guard let ctx = bitmap(w, h) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return nil }
        let row = ctx.bytesPerRow
        let src = data.bindMemory(to: UInt8.self, capacity: row * h)
        var out = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h { for x in 0..<w {
            let s = y * row + x * 4, d = (y * w + x) * 4
            let a = src[s + 3]
            out[d + 3] = a
            for c in 0..<3 { out[d + c] = a == 0 ? 0 : UInt8(min(255, Int(src[s + c]) * 255 / Int(a))) }
        } }
        return PixelBuffer(width: w, height: h, rgba: out)
    }

    static func pixelBuffer(fromSource src: CGImageSource, maxPixel: Int) -> PixelBuffer? {
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: maxPixel, kCGImageSourceCreateThumbnailWithTransform: true]
        guard let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return pixelBuffer(from: img, maxPixel: maxPixel)
    }

    static func exportPNG(_ asset: StudioAsset, effect: EffectPreset, amount: Double, psdToggled: Set<Int> = [], tiles: Int = 1, fixSeams: Bool = false, to url: URL) -> Bool {
        guard let out = exportBase(asset, effect: effect, amount: amount, psdToggled: psdToggled, tiles: tiles, fixSeams: fixSeams),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(dest, out, nil)
        return CGImageDestinationFinalize(dest)
    }

    /// Crops and scales one preset output, then encodes it (JPEG 0.86, PNG, or TIFF with its dpi).
    static func writePreset(_ img: CGImage, output o: ExportOutput, to url: URL, metadata: FileMetadata? = nil) -> Bool {
        let r = CGRect(x: o.crop.x, y: o.crop.y, width: o.crop.w, height: o.crop.h)
        guard let cropped = (r == CGRect(x: 0, y: 0, width: img.width, height: img.height)) ? img : img.cropping(to: r) else { return false }
        let opaque = o.format == .jpeg
        guard let ctx = CGContext(data: nil, width: o.width, height: o.height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: opaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        if opaque { ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: o.width, height: o.height)) }
        ctx.interpolationQuality = .high
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: o.width, height: o.height))
        guard let scaled = ctx.makeImage() else { return false }
        let type: UTType = o.format == .jpeg ? .jpeg : o.format == .png ? .png : .tiff
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else { return false }
        var props: [CFString: Any] = [kCGImagePropertyDPIWidth: o.dpi, kCGImagePropertyDPIHeight: o.dpi]
        if o.format == .jpeg { props[kCGImageDestinationLossyCompressionQuality] = 0.86 }
        if o.format == .tiff { props[kCGImagePropertyTIFFDictionary] = [kCGImagePropertyTIFFCompression: 5] }   // LZW
        if let metadata, o.format != .png, let xmp = CGImageMetadataCreateFromXMPData(Data(XmpMetadata.packet(metadata).utf8) as CFData) {
            CGImageDestinationAddImageAndMetadata(dest, scaled, xmp, props as CFDictionary)
        } else {
            CGImageDestinationAddImage(dest, scaled, props as CFDictionary)
        }
        return CGImageDestinationFinalize(dest)
    }

    /// The asset as it would export "as shown": effect, PSD layer toggles, tiling and seam fix applied.
    static func exportBase(_ asset: StudioAsset, effect: EffectPreset, amount: Double, psdToggled: Set<Int> = [], tiles: Int = 1, fixSeams: Bool = false) -> CGImage? {
        var base: CGImage?
        if let p = asset.importedPath {
            let file = URL(fileURLWithPath: p)
            switch file.pathExtension.lowercased() {
            case "psd":
                if let doc = (try? Data(contentsOf: file)).flatMap({ try? PsdLayers.read($0) }) { base = cgImage(doc.composite(toggled: psdToggled)) }
                else if let src = CGImageSourceCreateWithURL(file as CFURL, nil) { base = CGImageSourceCreateImageAtIndex(src, 0, nil) }
            case "svg": base = (try? String(contentsOf: file, encoding: .utf8)).flatMap(VectorScene.parse).flatMap { vector($0, width: 2400) }
            case "mov", "mp4", "m4v", "webm":
                let gen = AVAssetImageGenerator(asset: AVURLAsset(url: file)); gen.appliesPreferredTrackTransform = true
                base = try? gen.copyCGImage(at: CMTime(seconds: 1, preferredTimescale: 600), actualTime: nil)
            default:
                if let src = CGImageSourceCreateWithURL(file as CFURL, nil) { base = CGImageSourceCreateImageAtIndex(src, 0, nil) }
            }
        } else { base = generated(asset, width: 2400) }
        if let img = base, tiles > 1 || fixSeams {
            // Tiled exports stay at or under 6144 px on the long side.
            let limit = tiles > 1 ? 6144 / tiles : max(img.width, img.height)
            if var buf = pixelBuffer(from: img, maxPixel: limit) {
                if fixSeams { buf = Seamless.makeTileable(buf) }
                base = cgImage(tiles > 1 ? Seamless.tiled(buf, times: tiles) : buf)
            }
        }
        guard let img = base else { return nil }
        return apply(effect, amount: amount, to: img)
    }
}

struct Seeded { var state: UInt64; init(seed: UInt64) { state = seed | 1 }; mutating func next() -> UInt64 { state = state &* 6364136223846793005 &+ 1442695040888963407; return state >> 33 } }
extension Color { init(hex: String) { self.init(nsColor: NSColor(hex: hex) ?? .gray) } }
extension NSColor {
    convenience init?(hex: String) {
        var s = hex; if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt64(s, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
    }
}
#else
@main struct LinuxBuildStub { static func main() { print("ASSSETS requires macOS 14 or later.") } }
#endif
