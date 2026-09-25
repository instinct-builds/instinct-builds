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
import QuickLook
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
                Button("Library Health…") { library.openLibraryHealth() }.keyboardShortcut("l", modifiers: [.command, .option])
                Button("Compare Selection") { library.openCompare() }.keyboardShortcut("c", modifiers: [.command, .option]).disabled(!library.canCompare)
                Button("Cull Current View") { library.openCull() }.keyboardShortcut("k", modifiers: [.command, .option]).disabled(!library.canCull)
                Button("Find Similar") { if let id = library.focusID { library.findSimilar(id) } }.keyboardShortcut("f", modifiers: [.command, .option]).disabled(library.focusID == nil)
                Button("New Collection") { library.newCollection(with: []) }.keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Place into Mockup…") { library.openPlaceIntoMockup() }.keyboardShortcut("p", modifiers: [.command, .option]).disabled(!library.canPlaceFocus)
                Button("Batch Place into Mockup…") { library.openBatchPlacement() }.disabled(!library.canBatchPlace)
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
    static let danger = Color(red: 0.95, green: 0.3, blue: 0.33)
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
    /// Moodboard shown in place of the grid (1.16), its selected card, and the note being edited.
    @Published var selectedBoard: UUID?
    /// Selected cards on the open board (1.18: several at once). `boardItem` is the single selection, when there is one.
    @Published var boardSelection: Set<UUID> = []
    var boardItem: UUID? {
        get { boardSelection.count == 1 ? boardSelection.first : nil }
        set { boardSelection = newValue.map { [$0] } ?? [] }
    }
    /// A drag the board demo shows mid-flight (ids, dx, dy) so CI can capture the guides.
    var demoDrag: (Set<UUID>, Double, Double)?
    /// An arrow the annotate demo shows mid-drag (from card, board point) so CI can capture it.
    var demoLink: (UUID, Double, Double)?
    /// The crop sheet (1.19) and the arrow whose label is being typed.
    @Published var cropping: CropState?
    @Published var editingConnector: UUID?
    @Published var editingNote: UUID?
    @Published var renamingBoard: UUID?
    @Published var boardZoom = 1.0
    /// Client rounds on the board (1.20): only cards a client picked, one reviewer or everyone, comment callouts, the versions popover.
    @Published var boardClientOnly = false
    @Published var boardReviewer: String?
    @Published var boardShowComments = true
    @Published var boardVersionsOpen = false
    /// Approval (1.21): the status filter, the card whose thread is open, and who replies are signed as.
    @Published var boardStatusFilter: CardStatus?
    /// Templates (1.22): the picker sheet and the board being saved as a template.
    @Published var templatePickerOpen = false
    @Published var savingTemplate: UUID?
    /// Client feedback read but not applied yet (1.23): the import preview sheet shows it.
    @Published var pendingFeedback: PendingFeedback?
    /// Licenses that ended since the last launch (1.26); shown once as a banner.
    @Published var rightsNotice: [RightsIssue]?
    /// Warning shown before expired or editorial-only assets go into client work (1.25).
    @Published var rightsWarning: RightsWarning?
    /// License file shown in Quick Look (1.27).
    @Published var quickLookURL: URL?
    /// "Save as Preset" sheet (1.27).
    @Published var presetDraft: PresetDraft?
    /// Copy license files into shared galleries (1.27). Off by default: license paperwork can carry prices.
    @Published var includeLicenseFiles = UserDefaults.standard.bool(forKey: "includeLicenseFiles") {
        didSet { UserDefaults.standard.set(includeLicenseFiles, forKey: "includeLicenseFiles") }
    }
    /// Demo only: inspector section to scroll to (1.27).
    var inspectorAnchor: String?
    /// Add a credits page to galleries, round summaries and contact sheets (1.25).
    @Published var includeCredits = UserDefaults.standard.object(forKey: "includeCredits") as? Bool ?? true {
        didSet { UserDefaults.standard.set(includeCredits, forKey: "includeCredits") }
    }
    /// Cards copied with ⌘C on a board (1.24); ⌘V pastes them on any board.
    @Published var cardClipboard: BoardClipboard?
    @Published var threadCard: UUID?
    @Published var replyAuthor = UserDefaults.standard.string(forKey: "replyAuthor") ?? (NSFullUserName().isEmpty ? "Studio" : NSFullUserName()) {
        didSet { UserDefaults.standard.set(replyAuthor, forKey: "replyAuthor") }
    }
    @Published var fitBoardRequest = 0
    /// Inspector column on/off (1.17), remembered between launches.
    @Published var showInspector = UserDefaults.standard.object(forKey: "showInspector") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showInspector, forKey: "showInspector") }
    }
    /// Board being presented and the card in focus (-1 = the whole board).
    @Published var presenting: UUID?
    @Published var presentIndex = -1
    var presentEnteredFullScreen = false
    var isDemo = false
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

    func openPresetExport(_ ids: [UUID]? = nil, title: String? = nil, checked: Bool = false) {
        let list = ids ?? (selection.isEmpty ? [] : filtered.map(\.id).filter(selection.contains))
        let usable = list.filter { id in catalog.assets.first { $0.id == id }?.kind != .audio }
        guard !usable.isEmpty else { flash("Select images, textures, vectors or mockups to export"); return }
        if !checked {
            guardRights(usable, action: "Export", skip: { self.openPresetExport($0, title: title, checked: true) }) { self.openPresetExport(usable, title: title, checked: true) }
            return
        }
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
    func exportGallery(_ ids: [UUID]? = nil, title: String? = nil, to fixedDir: URL? = nil, board: (png: Data, width: Int, height: Int, layout: Moodboard)? = nil, summaryPDF: URL? = nil, checked: Bool = false) {
        let galleryID = UUID().uuidString, boardID = board?.layout.id
        let list = ids ?? filtered.map(\.id).filter(selection.contains)
        let byID = Dictionary(uniqueKeysWithValues: catalog.assets.map { ($0.id, $0) })
        let assets = list.compactMap { byID[$0] }.filter { $0.kind != .audio }
        guard !assets.isEmpty else { flash("Select images, textures, vectors, mockups or clips for a gallery"); return }
        if fixedDir == nil, !checked {
            let fixedList = assets.map(\.id)
            guardRights(fixedList, action: "Share gallery", skip: board == nil ? { self.exportGallery($0, title: title, to: nil, board: nil, summaryPDF: summaryPDF, checked: true) } : nil) {
                self.exportGallery(fixedList, title: title, to: nil, board: board, summaryPDF: summaryPDF, checked: true)
            }
            return
        }
        var creditLines = credits(assets.map(\.id))
        // License files travel with the gallery only when the user opted in (1.27).
        var licenseCopies: [(URL, String)] = []
        if includeLicenseFiles, includeCredits {
            let docs = catalog.licenseDocs(forAll: assets.map(\.id)).filter { FileManager.default.fileExists(atPath: licenseURL($0).path) }
            let byName = Dictionary(docs.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
            for d in docs { licenseCopies.append((licenseURL(d), "licenses/" + d.stored)) }
            for i in creditLines.indices {
                creditLines[i].files = creditLines[i].files?.map { f in CreditFile(name: f.name, href: byName[f.name].map { "licenses/" + $0.stored }) }
            }
        }
        let name = title ?? (selection.count > 1 || ids != nil ? browsingTitle : "Review")
        let galleryCredits = creditLines, galleryLicenses = licenseCopies
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
                var item = ReviewGallery.Item(id: a.id.uuidString, title: a.title, kind: a.kind.singular, resolution: a.resolution, palette: a.palette,
                                              tags: a.tags, image: "images/\(stem).jpg", thumb: "thumbs/\(stem).jpg")
                if let c = a.rights?.credit.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty { item.credit = c }
                items.append(item)
            }
            var boardView: ReviewGallery.Board?
            if let board, (try? board.png.write(to: folder.appendingPathComponent("board.png"))) != nil {
                let spots = ReviewGallery.spots(for: board.layout, including: Set(items.compactMap { UUID(uuidString: $0.id) }))
                boardView = .init(image: "board.png", width: board.width, height: board.height, spots: spots)
            }
            if !galleryLicenses.isEmpty {
                try? fm.createDirectory(at: folder.appendingPathComponent("licenses"), withIntermediateDirectories: true)
                for (src, rel) in galleryLicenses { try? fm.copyItem(at: src, to: folder.appendingPathComponent(rel)) }
            }
            var summaryName: String?
            if let summaryPDF, (try? fm.copyItem(at: summaryPDF, to: folder.appendingPathComponent("round-summary.pdf"))) != nil { summaryName = "round-summary.pdf" }
            var manifest = ReviewGallery.Manifest(gallery: galleryID, title: name, created: created, items: items, board: boardView, summary: summaryName)
            if !galleryCredits.isEmpty { manifest.credits = galleryCredits }
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
                // Remember where it came from, so the client's feedback pins back onto this board (1.20).
                if let boardID { self.mutate { $0.noteGalleryShared(galleryID, from: boardID) } }
                self.flash("Gallery ready: \(items.count) assets\(summaryPDF != nil ? " + round summary" : "")\(zipped ? ", zipped" : "")")
                if fixedDir == nil { NSWorkspace.shared.activateFileViewerSelecting([zipped ? zip : folder]) }
                else { try? "\(items.count)".write(to: parent.appendingPathComponent("gallery-done.txt"), atomically: true, encoding: .utf8) }
            }
        }
    }

    func importFeedback() {
        let p = NSOpenPanel(); p.allowedContentTypes = [.json]; p.allowsMultipleSelection = true
        p.message = "Choose the feedback file(s) your client downloaded from the review gallery"
        guard p.runModal() == .OK else { return }
        previewFeedback(p.urls)
    }

    /// Reads the files and opens the preview sheet; nothing changes until Import.
    func previewFeedback(_ urls: [URL]) {
        var files: [PendingFeedback.File] = [], bad = 0
        for u in urls {
            guard let data = try? Data(contentsOf: u), let f = ReviewGallery.decodeFeedback(data) else { bad += 1; continue }
            files.append(.init(feedback: f, preview: catalog.previewFeedback(f), name: u.lastPathComponent))
        }
        guard !files.isEmpty else { flash("That isn't an ASSSETS review feedback file"); return }
        pendingFeedback = PendingFeedback(files: files, unreadable: bad)
    }

    func applyPendingFeedback() {
        guard let p = pendingFeedback else { return }
        pendingFeedback = nil
        importFeedback(feedback: p.files.map(\.feedback), unreadable: p.unreadable)
    }

    func importFeedback(_ urls: [URL]) {
        var list: [ReviewGallery.Feedback] = [], bad = 0
        for u in urls {
            if let data = try? Data(contentsOf: u), let f = ReviewGallery.decodeFeedback(data) { list.append(f) } else { bad += 1 }
        }
        importFeedback(feedback: list, unreadable: bad)
    }

    func importFeedback(feedback list: [ReviewGallery.Feedback], unreadable bad: Int) {
        var total = StudioCatalog.FeedbackResult(), reviewers: [String] = []
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"; let today = df.string(from: Date())
        for f in list {
            var r = StudioCatalog.FeedbackResult()
            mutate { r = $0.applyFeedback(f, imported: today) }
            total.favorites += r.favorites; total.notes += r.notes; total.unknown += r.unknown; total.statuses += r.statuses
            total.smartCollection = r.smartCollection ?? total.smartCollection
            total.board = r.board ?? total.board
            let who = f.reviewer.trimmingCharacters(in: .whitespaces); if !who.isEmpty && !reviewers.contains(who) { reviewers.append(who) }
        }
        if total.favorites + total.notes + total.statuses == 0 && total.board == nil {
            flash(bad > 0 && list.isEmpty ? "That isn't an ASSSETS review feedback file" : "No favorites, notes or decisions in that feedback"); return
        }
        var msg = "\(total.favorites) client \(total.favorites == 1 ? "pick" : "picks"), \(total.notes) \(total.notes == 1 ? "note" : "notes")"
        if total.statuses > 0 { msg += ", \(total.statuses) \(total.statuses == 1 ? "status" : "statuses") updated" }
        if !reviewers.isEmpty { msg += " from " + reviewers.joined(separator: ", ") }
        if total.unknown > 0 { msg += " · \(total.unknown) not in this library" }
        if let b = total.board, let name = catalog.board(b)?.name {
            // Shared from a board: the round lands back on it as pins.
            flash(msg + " · pinned on \(name)")
            show(board: b); boardReviewer = nil; boardShowComments = true
        } else {
            flash(msg)
            if let id = total.smartCollection { show(smart: id) }
        }
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
        if presenting != nil {
            switch e.keyCode {
            case 124, 125, 49, 36: stepPresent(1)                                     // → ↓ Space Return
            case 123, 126: stepPresent(-1)                                            // ← ↑
            case 115, 29: presentIndex = -1                                           // Home, 0: whole board
            case 53: stopPresenting()                                                 // Esc
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
        if selectedBoard != nil, viewerID == nil {
            if !boardSelection.isEmpty, e.keyCode == 51 || e.keyCode == 117 { removeFromBoard(boardSelection); return true }   // Delete
            if e.keyCode == 0, e.modifierFlags.contains(.command), let b = currentBoard { boardSelection = Set(b.items.map(\.id)); return true }  // ⌘A
            if e.keyCode == 53, !boardSelection.isEmpty { boardSelection = []; return true }                                    // Esc
            let cmd = e.modifierFlags.contains(.command)
            if cmd, e.keyCode == 8, !boardSelection.isEmpty { copyCards(); return true }                                          // ⌘C
            if cmd, e.keyCode == 9, cardClipboard != nil { pasteCards(); return true }                                            // ⌘V
            if !cmd, !boardSelection.isEmpty, (123...126).contains(e.keyCode) {                                                   // arrows nudge
                let step = e.modifierFlags.contains(.shift) ? (currentBoard?.grid ?? 20) : 1
                switch e.keyCode {
                case 123: nudgeCards(dx: -step, dy: 0)
                case 124: nudgeCards(dx: step, dy: 0)
                case 125: nudgeCards(dx: 0, dy: step)
                default: nudgeCards(dx: 0, dy: -step)
                }
                return true
            }
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
        if !isDemo { checkRightsSinceLastLaunch(); pruneLicenseFiles(); refreshHealth() }
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
        c.seedRightsCollections()
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
    var filteredFileCount: Int { unstackedFiltered.filter(passesPinnedFilters).count }
    /// Rating, label, keyword and color filters that sit on top of the collection and search box.
    func passesPinnedFilters(_ a: StudioAsset) -> Bool {
        ratingFilter.matches(a) && (keywordFilter.map(a.tags.contains) ?? true) && (colorQuery.map { ColorSearch.matches($0, a) } ?? true)
    }
    var filtered: [StudioAsset] {
        let list = unstackedFiltered.filter(passesPinnedFilters)
        // A color search ranks by closeness (dominant matches first) and shows every version, like Find Similar.
        if let q = colorQuery, similarTo == nil { return ColorSearch.rank(list, q) }
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
    var canSaveSearch: Bool { selectedSmart == nil && (!search.trimmingCharacters(in: .whitespaces).isEmpty || selectedKind != nil || ratingFilter.isActive || keywordFilter != nil || colorQuery != nil) }

    // MARK: File metadata and keywords (1.13)

    /// Keywords, title, stars and label that new files already carry (XMP sidecar, embedded XMP, IPTC).
    static func readFileMetadata(_ c: inout StudioCatalog, ids: [UUID]) {
        let set = Set(ids)
        for a in c.assets where set.contains(a.id) {
            guard let p = a.importedPath else { continue }
            c.applyFileMetadata(XmpMetadata.read(path: p), to: a.id)
        }
    }

    static func seedSourceFingerprints(_ c: inout StudioCatalog, ids: [UUID]) {
        let set = Set(ids)
        for a in c.assets where set.contains(a.id) && !a.isStarter && a.placementRecipe == nil {
            if let path = a.importedPath, let fingerprint = sourceFingerprint(path) {
                c.seedSourceFingerprint(fingerprint, for: a.id, path: path)
            }
        }
    }

    /// Writes "<name>.xmp" next to each of the user's files. Existing sidecars keep everything but our four fields.
    func writeMetadata(_ ids: Set<UUID>, quiet: Bool = false) {
        let fm = FileManager.default
        var written = 0, skipped = 0, failed = 0
        for a in catalog.assets where ids.contains(a.id) {
            guard !a.isStarter, let p = a.importedPath, fm.fileExists(atPath: p), let m = catalog.fileMetadata(for: a.id) else { skipped += 1; continue }
            let side = XmpMetadata.sidecarPath(for: p)
            let text = (try? String(contentsOfFile: side, encoding: .utf8)).map { XmpMetadata.update($0, with: m) } ?? XmpMetadata.packet(m)
            if (try? text.write(toFile: side, atomically: true, encoding: .utf8)) != nil { written += 1 } else { failed += 1 }
        }
        if quiet { return }
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

    // MARK: Search by color (1.15)

    @Published var colorQuery: ColorQuery?
    @Published var showColorPicker = false
    /// Filters and ranks the grid by a color. `remember` adds it to the recent colors (not while dragging in the color panel).
    func searchColor(_ hex: String, tolerance: Double? = nil, remember: Bool = true) {
        guard let h = ColorSearch.normalize(hex) else { flash("Not a color: \(hex)"); return }
        colorQuery = ColorQuery(hex: h, tolerance: tolerance ?? colorQuery?.tolerance ?? ColorQuery.defaultTolerance)
        if remember && catalog.recentColors.first != h { mutate { $0.noteRecentColor(h) } }
    }
    func setColorTolerance(_ t: Double) { if let q = colorQuery { colorQuery = ColorQuery(hex: q.hex, tolerance: t) } }
    func clearColorSearch() { colorQuery = nil }
    /// The system eyedropper: pick a color anywhere on screen.
    func sampleScreenColor() {
        showColorPicker = false
        NSColorSampler().show { [weak self] c in
            guard let c else { return }
            let h = Self.hex(c)
            DispatchQueue.main.async { self?.searchColor(h) }
        }
    }
    nonisolated static func hex(_ c: NSColor) -> String {
        let s = c.usingColorSpace(.sRGB) ?? c
        func v(_ x: CGFloat) -> Int { Int((min(1, max(0, x)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", v(s.redComponent), v(s.greenComponent), v(s.blueComponent))
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

    func show(collection: String) { selectedBoard = nil; similarTo = nil; selectedCollection = collection; selectedSmart = nil; anchorID = nil }
    func show(smart id: UUID) { selectedBoard = nil; similarTo = nil; selectedSmart = id; selectedCollection = StudioCatalog.allAssets; anchorID = nil }

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
            if !added.isEmpty { enrichStarterMetadata(&c, userFilesOnly: true); Self.readFileMetadata(&c, ids: added); Self.seedSourceFingerprints(&c, ids: added); c.autoStack(); mutate { $0 = c }; refreshAutoTags() }
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
    @discardableResult
    func locate(_ id: UUID) -> Bool {
        guard let a = catalog.assets.first(where: { $0.id == id }) else { return false }
        let p = NSOpenPanel(); p.canChooseFiles = true; p.canChooseDirectories = false; p.prompt = "Use This File"
        p.message = "Locate \"\(a.title)\""
        if let ext = a.importedPath.map({ URL(fileURLWithPath: $0).pathExtension }), let t = UTType(filenameExtension: ext) { p.allowedContentTypes = [t] }
        guard p.runModal() == .OK, let url = p.url else { return false }
        let path = url.standardizedFileURL.path
        if let old = a.importedPath, URL(fileURLWithPath: old).pathExtension.lowercased() != url.pathExtension.lowercased() {
            flash("Choose the original file type (\(URL(fileURLWithPath: old).pathExtension))"); return false
        }
        if catalog.assets.contains(where: { $0.importedPath == path && $0.id != id }) { flash("That file is already in the library"); return false }
        mutate { c in if let i = c.assets.firstIndex(where: { $0.id == id }) { c.assets[i].importedPath = path } }
        missing.remove(id)
        flash("Relinked \(a.title)")
        return true
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

    // MARK: Place into Mockup (1.29)

    @Published var placing: PlaceState?
    @Published var batchPlacement: BatchPlaceState?
    private var psdCache: [String: PsdDocument] = [:]

    /// Layered PSD mockups in the library whose file is still there (bundled and the user's own).
    var mockupAssets: [StudioAsset] {
        catalog.assets.filter { a in
            guard let p = a.importedPath, p.lowercased().hasSuffix(".psd") else { return false }
            return FileManager.default.fileExists(atPath: p)
        }.sorted { ($0.isStarter ? 1 : 0, $0.title) < ($1.isStarter ? 1 : 0, $1.title) }
    }
    func canPlace(_ a: StudioAsset) -> Bool {
        a.kind != .audio && a.kind != .video && a.placementRecipe == nil && a.importedPath?.lowercased().hasSuffix(".psd") != true
    }
    var canPlaceFocus: Bool { focusID.flatMap { id in catalog.assets.first { $0.id == id } }.map(canPlace) ?? false }

    func psdDocument(_ a: StudioAsset) -> PsdDocument? {
        guard let p = a.importedPath else { return nil }
        guard FileManager.default.fileExists(atPath: p) else { psdCache.removeValue(forKey: p); return nil }
        if let d = psdCache[p] { return d }
        guard let d = (try? Data(contentsOf: URL(fileURLWithPath: p))).flatMap({ try? PsdLayers.read($0) }) else { return nil }
        psdCache[p] = d
        return d
    }

    /// The art as straight RGBA with the long side at most `maxPixel` (any still: photos, vectors, generated studies).
    func artPixels(_ a: StudioAsset, maxPixel: Int) -> PixelBuffer? {
        guard let img = MediaRenderer.exportBase(a, effect: .original, amount: 0) else { return nil }
        return MediaRenderer.pixelBuffer(from: img, maxPixel: maxPixel)
    }

    func openPlaceIntoMockup(_ artID: UUID? = nil, mockup: UUID? = nil) {
        guard let id = artID ?? focusID, let art = catalog.assets.first(where: { $0.id == id }), canPlace(art) else { flash("Pick an image to place into a mockup"); return }
        let mockups = mockupAssets.filter { psdDocument($0).map { !MockupPlacement.targetLayers($0).isEmpty } ?? false }
        guard !mockups.isEmpty else { flash("No layered PSD mockups in the library"); return }
        guard let px = artPixels(art, maxPixel: 900) else { flash("Could not read \(art.title)"); return }
        let pick = mockup.flatMap { m in mockups.first { $0.id == m } } ?? mockups[0]
        placing = PlaceState(art: art, preview: px, mockups: mockups.map(\.id), mockup: pick.id)
    }

    var batchPlaceArts: [StudioAsset] {
        catalog.assets.filter { selection.contains($0.id) && canPlace($0) && $0.kind != .mockup &&
            ($0.importedPath.map { FileManager.default.fileExists(atPath: $0) } ?? ($0.sourceKey?.hasPrefix("generated:") == true)) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    var canBatchPlace: Bool { batchPlaceArts.count >= 2 }

    func openBatchPlacement() {
        let arts = batchPlaceArts
        guard arts.count >= 2 else { flash("Select two or more still artworks"); return }
        let mockups = mockupAssets.filter { psdDocument($0).map { !MockupPlacement.targetLayers($0).isEmpty } ?? false }
        guard let first = mockups.first else { flash("No layered PSD mockups in the library"); return }
        batchPlacement = BatchPlaceState(arts: arts.map(\.id), mockups: mockups.map(\.id), mockup: first.id)
    }

    /// Renders each artwork separately and records one undo step for the batch. The selected asset IDs
    /// are resolved again at save time so removed or moved files cannot turn into a different artwork.
    func saveBatchPlacementPreset(_ state: BatchPlaceState, name: String) {
        guard let mockup = catalog.assets.first(where: { $0.id == state.mockup }), let doc = psdDocument(mockup),
              let layer = state.layer ?? MockupPlacement.targetLayers(doc).first,
              doc.layers.indices.contains(layer) else { flash("Pick a design layer first"); return }
        let prior = catalog.placementPresets.first { $0.name.caseInsensitiveCompare(name.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame }
        var id: UUID?
        mutate(prior == nil ? "Save Placement Preset" : "Update Placement Preset") { c in
            id = c.savePlacementPreset(name: name, mockupID: mockup.id, layerName: doc.layers[layer].name,
                                       mode: state.mode, background: state.background.rawValue)
        }
        flash(id == nil ? "Enter a name for the preset" : "Saved placement preset \(name.trimmingCharacters(in: .whitespacesAndNewlines))")
    }

    func removePlacementPreset(_ id: UUID) { mutate("Delete Placement Preset") { $0.deletePlacementPreset(id) } }

    /// Either apply the exact saved layer or keep the current choices and show why the preset cannot be used.
    func usePlacementPreset(_ preset: PlacementPreset, in state: inout BatchPlaceState) -> PlacementPresetStatus {
        let status = catalog.placementPresetStatus(preset,
            exists: { FileManager.default.fileExists(atPath: $0) },
            layers: { a in psdDocument(a).map { d in MockupPlacement.targetLayers(d).map { d.layers[$0].name } } ?? [] })
        guard case .ready(let index) = status,
              let mockup = catalog.assets.first(where: { $0.id == preset.mockupID }),
              let doc = psdDocument(mockup) else { return status }
        let candidates = MockupPlacement.targetLayers(doc)
        guard candidates.indices.contains(index) else { return .missingLayer }
        guard let background = PlaceBackground(rawValue: preset.background) else { return .missingLayer }
        state.mockup = mockup.id; state.layer = candidates[index]
        state.mode = preset.mode; state.background = background
        return status
    }

    func commitBatchPlacement(_ state: BatchPlaceState) {
        guard let mockup = catalog.assets.first(where: { $0.id == state.mockup }), let doc = psdDocument(mockup),
              let layer = state.layer ?? MockupPlacement.targetLayers(doc).first,
              doc.layers.indices.contains(layer), MockupPlacement.targetLayers(doc).contains(layer) else {
            flash("Choose a mockup design layer"); return
        }
        batchPlacement = nil
        let before = catalog, mode = state.mode, bg = state.background.rgb, name = doc.layers[layer].name
        let arts = state.arts.compactMap { id in catalog.assets.first { $0.id == id } }
        flash("Placing \(arts.count) artworks into \(mockup.title)…")
        Task { @MainActor in
            var ids: [UUID] = []
            for a in arts {
                guard let current = catalog.assets.first(where: { $0.id == a.id }),
                      current.importedPath.map({ FileManager.default.fileExists(atPath: $0) }) ?? (current.sourceKey?.hasPrefix("generated:") == true),
                      let art = artPixels(current, maxPixel: 2400) else { continue }
                let crop = mode == .fill ? state.crops[current.id] : nil
                let image = await Task.detached(priority: .userInitiated) {
                    Self.renderPlaced(art: art, doc: doc, layer: layer, mode: mode, crop: crop, background: bg)
                }.value
                let recipe = PlacementRecipe(artID: current.id, mockupID: mockup.id, layerName: name, mode: mode,
                                             crop: crop, background: state.background.rawValue)
                if let image, let id = savePlaced(image, art: current, mockup: mockup, recipe: recipe, stackOnArt: true, undo: nil) { ids.append(id) }
            }
            if !ids.isEmpty { _ = history.record("Batch Place into Mockup", before: before, after: catalog) }
            refreshAutoTags()
            guard !ids.isEmpty else { flash("No artworks could be placed"); return }
            selection = Set(ids); focusID = ids.first
            flash(ids.count == arts.count ? "Placed \(ids.count) artworks into \(mockup.title)" :
                "Placed \(ids.count) of \(arts.count); check missing source files")
            if isDemo {
                let recipes = ids.compactMap { id in catalog.assets.first { $0.id == id }?.placementRecipe }
                let rights = ids.compactMap { id in catalog.assets.first { $0.id == id }?.rights }.count
                try? "done placed=\(ids.count) recipes=\(recipes.count) rights=\(rights) unique-art=\(Set(recipes.map(\.artID)).count) cropped=\(recipes.filter { $0.crop != nil }.count)".write(
                    to: supportRoot.appendingPathComponent("demo-batch-place.txt"), atomically: true, encoding: .utf8)
            }
        }
    }

    /// Opens the stored placement without guessing when either source moved or left the library.
    func editPlacement(_ render: StudioAsset) {
        guard var recipe = render.placementRecipe else { return }
        let status = catalog.placementStatus(recipe, exists: { FileManager.default.fileExists(atPath: $0) })
        switch status {
        case .missingArt(let id), .missingMockup(let id):
            let isArt: Bool
            if case .missingArt = status { isArt = true } else { isArt = false }
            let name = isArt ? "source artwork" : "PSD mockup"
            if catalog.assets.contains(where: { $0.id == id }) {
                // Locate keeps the source ID and its metadata. Cancel leaves the recipe untouched.
                guard locate(id) else { return }
            } else {
                let p = NSOpenPanel(); p.canChooseFiles = true; p.canChooseDirectories = false
                p.allowedContentTypes = isArt ? [.image, .pdf] : [UTType(filenameExtension: "psd") ?? .data]
                p.prompt = "Use as Source"
                p.message = "The original \(name) is no longer in the library. Choose the replacement for \(render.title)."
                guard p.runModal() == .OK, let url = p.url else { return }
                let path = url.standardizedFileURL.path
                guard (isArt ? MediaKind.classify(extension: url.pathExtension).map { $0 != .audio && $0 != .video && $0 != .mockup } ?? false : url.pathExtension.lowercased() == "psd") else {
                    flash("Choose a \(isArt ? "still artwork" : "PSD mockup") source"); return
                }
                if let existing = catalog.assets.first(where: { $0.importedPath == path }) {
                    guard isArt ? canPlace(existing) && existing.kind != .mockup : existing.importedPath?.lowercased().hasSuffix(".psd") == true else {
                        flash("That library file is not a \(isArt ? "still artwork" : "PSD mockup") source"); return
                    }
                    if isArt { recipe.artID = existing.id } else { recipe.mockupID = existing.id }
                } else {
                    var replacement: UUID?
                    mutate("Relink Placement Source") { replacement = $0.importFile(path: path, collection: render.collection) }
                    guard let replacement else { flash("Could not add source file"); return }
                    if isArt { recipe.artID = replacement } else { recipe.mockupID = replacement }
                }
                mutate("Relink Placement Source") { c in
                    if let i = c.assets.firstIndex(where: { $0.id == render.id }) { c.assets[i].placementRecipe = recipe }
                }
            }
            // Another source may also be missing; run the same validation again, never guess.
            editPlacement(catalog.assets.first(where: { $0.id == render.id }) ?? render)
            return
        case .ready: break
        }
        guard let art = catalog.assets.first(where: { $0.id == recipe.artID }),
              let mockup = catalog.assets.first(where: { $0.id == recipe.mockupID }),
              let doc = psdDocument(mockup),
              let px = artPixels(art, maxPixel: 900),
              canPlace(art) else { flash("Source cannot be opened. Relink the source before editing."); return }
        var mockups = mockupAssets.filter { psdDocument($0).map { !MockupPlacement.targetLayers($0).isEmpty } ?? false }
        if !mockups.contains(where: { $0.id == mockup.id }) { mockups.insert(mockup, at: 0) }
        var st = PlaceState(art: art, preview: px, mockups: mockups.map(\.id), mockup: mockup.id)
        st.editing = render.id
        st.mode = recipe.mode; st.crop = recipe.crop
        st.background = PlaceBackground(rawValue: recipe.background) ?? .white
        if let name = recipe.layerName {
            st.layer = MockupPlacement.targetLayers(doc).first { doc.layers[$0].name == name }
            if st.layer == nil { st.layerMissing = name }
        }
        placing = st
    }

    /// Renders one mockup with the art at full mockup size; the placed composite and the layer used.
    nonisolated static func renderPlaced(art: PixelBuffer, doc: PsdDocument, layer: Int?, mode: PlacementMode, crop: BoardRect?, background: (UInt8, UInt8, UInt8)) -> PixelBuffer? {
        MockupPlacement.place(art, into: doc, layer: layer, mode: mode, crop: crop, background: background)?.composite()
    }

    /// Writes the render next to the library and files it on the mockup's version stack. Returns the new asset id.
    @discardableResult
    func savePlaced(_ buf: PixelBuffer, art: StudioAsset, mockup: StudioAsset, recipe: PlacementRecipe, stackOnArt: Bool = false, undo: String? = "Place into Mockup") -> UUID? {
        let dir = supportRoot.appendingPathComponent("Placed", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(DragOut.safeName("\(art.title) on \(mockup.title)") + "-" + String(UUID().uuidString.prefix(6)) + ".png")
        guard let cg = MediaRenderer.cgImage(buf), let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        let small = MediaRenderer.pixelBuffer(from: cg, maxPixel: 160)
        var id: UUID?
        mutate(undo) { c in
            id = c.addPlacedMockup(path: url.path, art: art.id, mockup: mockup.id, resolution: "\(buf.width) × \(buf.height)", recipe: recipe, stackOnArt: stackOnArt)
            if let id, let i = c.assets.firstIndex(where: { $0.id == id }), let small {
                let colors = PaletteExtractor.colors(from: small, count: 5).map(\.hex)
                if colors.count >= 3 { c.assets[i].palette = colors }
            }
        }
        return id
    }

    func commitPlace(_ st: PlaceState) {
        guard st.layerMissing == nil,
              let currentArt = catalog.assets.first(where: { $0.id == st.art.id }),
              currentArt.importedPath.map { FileManager.default.fileExists(atPath: $0) } ?? (currentArt.sourceKey?.hasPrefix("generated:") == true),
              let mockup = catalog.assets.first(where: { $0.id == st.mockup }), let doc = psdDocument(mockup),
              let art = artPixels(currentArt, maxPixel: 2400),
              let buf = Self.renderPlaced(art: art, doc: doc, layer: st.layer, mode: st.mode, crop: st.crop, background: st.background.rgb),
              let id = savePlaced(buf, art: currentArt, mockup: mockup, recipe: PlacementRecipe(artID: st.art.id, mockupID: mockup.id, layerName: st.layer.flatMap { doc.layers.indices.contains($0) ? doc.layers[$0].name : nil } ?? MockupPlacement.targetLayers(doc).first.map { doc.layers[$0].name }, mode: st.mode, crop: st.crop, background: st.background.rawValue)) else { flash("Could not place \(st.art.title)"); return }
        placing = nil
        refreshAutoTags()
        selection = [id]; focusID = id
        flash("Saved \u{201C}\(st.art.title) on \(mockup.title)\u{201D} as a new version")
    }

    /// Every mockup gets the art in its best design layer with the sheet's Fill/Fit, crop and background;
    /// the renders land on each mockup's stack and open as one contact sheet.
    func placeIntoAll(_ st: PlaceState, checked: Bool = false, then done: ((Int) -> Void)? = nil) {
        placing = nil
        let mockups = st.mockups.compactMap { m in catalog.assets.first { $0.id == m } }
        guard let currentArt = catalog.assets.first(where: { $0.id == st.art.id }),
              currentArt.importedPath.map { FileManager.default.fileExists(atPath: $0) } ?? (currentArt.sourceKey?.hasPrefix("generated:") == true),
              let art = artPixels(currentArt, maxPixel: 2400) else { flash("Could not read \(st.art.title)"); return }
        flash("Placing \(st.art.title) into \(mockups.count) mockups…")
        let jobs = mockups.compactMap { m in psdDocument(m).map { (m, $0) } }
        let mode = st.mode, crop = st.crop, bg = st.background.rgb
        let before = catalog
        Task { @MainActor in
            var ids: [UUID] = []
            for (m, doc) in jobs {
                let buf = await Task.detached(priority: .userInitiated) { Self.renderPlaced(art: art, doc: doc, layer: nil, mode: mode, crop: crop, background: bg) }.value
                if let buf, let id = savePlaced(buf, art: currentArt, mockup: m, recipe: PlacementRecipe(artID: st.art.id, mockupID: m.id, layerName: MockupPlacement.targetLayers(doc).first.map { doc.layers[$0].name }, mode: mode, crop: crop, background: st.background.rawValue), undo: nil) { ids.append(id) }
            }
            if !ids.isEmpty { _ = history.record("Place into All Mockups", before: before, after: catalog) }
            refreshAutoTags()
            guard !ids.isEmpty else { flash("Nothing could be placed"); return }
            selection = Set(ids); focusID = ids.first
            openContactSheet(ids: ids, title: "\(st.art.title) in \(ids.count) Mockups", checked: checked)
            done?(ids.count)
        }
    }

    // MARK: Contact sheets and brand kits (1.5)

    @Published var sheetPreview: SheetPreview?

    func openContactSheetForCurrentView() {
        if selection.count > 1 { openContactSheet(ids: selectedAssets.map(\.id), title: "\(selection.count) Selected Assets") }
        else { openContactSheet(ids: filtered.map(\.id), title: browsingTitle) }
    }

    /// Renders the PDF to a temp file and opens the preview sheet; saving happens from there.
    func openContactSheet(ids: [UUID], title: String, checked: Bool = false) {
        let byID = Dictionary(uniqueKeysWithValues: catalog.assets.map { ($0.id, $0) })
        let assets = ids.compactMap { byID[$0] }
        guard !assets.isEmpty else { flash("Nothing to put on a contact sheet"); return }
        if !checked {
            guardRights(ids, action: "Contact sheet", skip: { self.openContactSheet(ids: $0, title: title, checked: true) }) { self.openContactSheet(ids: ids, title: title, checked: true) }
            return
        }
        let creditLines = credits(assets.map(\.id))
        flash("Laying out \(assets.count) assets…")
        Task { @MainActor in
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ASSSETS-sheet/\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(DragOut.safeName(title + " Contact Sheet") + ".pdf")
            let ok = await ContactSheetRenderer.render(title: title, assets: assets, to: url, credits: creditLines)
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
        do {
            while let chunk = try h.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        } catch { return nil }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Lossless merge and Library Health (1.28)

    /// Per duplicate set (keyed by its first id): the copy the user picked to keep, and whose rights win when they disagree.
    @Published var duplicateKeeper: [UUID: UUID] = [:]
    @Published var duplicateRights: [UUID: UUID] = [:]

    func keeper(for group: [UUID]) -> UUID? {
        if let k = duplicateKeeper[group[0]], group.contains(k) { return k }
        return Duplicates.suggestedKeeper(group.compactMap { id in catalog.assets.first { $0.id == id } })
    }

    func mergePlan(for group: [UUID]) -> MergePreview? {
        guard let k = keeper(for: group) else { return nil }
        return catalog.mergePreview(keep: k, group: group, rightsFrom: duplicateRights[group[0]])
    }

    /// A set is ready when its rights agree or the user picked whose rights to keep.
    func mergeReady(_ group: [UUID]) -> Bool {
        guard let p = mergePlan(for: group) else { return false }
        return !p.hasRightsConflict || duplicateRights[group[0]] != nil
    }

    func keep(_ keeper: UUID, in group: [UUID]) {
        var removed = 0
        let plan = catalog.mergePreview(keep: keeper, group: group, rightsFrom: duplicateRights[group[0]])
        let rightsFrom = duplicateRights[group[0]]
        mutate("Merge Duplicates") { removed = $0.mergeDuplicates(keep: keeper, remove: Set(group), rightsFrom: rightsFrom) }
        duplicates?.groups.removeAll { $0.contains(keeper) }
        duplicateKeeper[group[0]] = nil; duplicateRights[group[0]] = nil
        var carried: [String] = []
        if let p = plan {
            if p.ratingRaised { carried.append("rating") }
            if p.labelAdopted { carried.append("label") }
            if p.rightsAdopted { carried.append("rights") }
            if p.licenseFilesAdded > 0 { carried.append("license files") }
            if p.boardCardsMoved > 0 { carried.append("board cards") }
        }
        if health != nil { refreshHealth(full: true) }
        flash("Kept 1, removed \(removed) duplicate\(removed == 1 ? "" : "s")" + (carried.isEmpty ? "" : ", moved over its " + carried.joined(separator: ", ")) + ". Files on disk are untouched.")
    }

    /// Merges every set that is ready. Sets whose rights disagree wait for a choice.
    func keepSuggestedForAll() {
        guard let groups = duplicates?.groups else { return }
        let ready = groups.filter(mergeReady)
        var removed = 0
        // Resolve keepers and rights choices first: the merge closure must not read the catalog it is changing.
        let plans: [(UUID, [UUID], UUID?)] = ready.compactMap { g in keeper(for: g).map { ($0, g, duplicateRights[g[0]]) } }
        mutate("Merge Duplicates") { c in
            for (k, g, r) in plans { removed += c.mergeDuplicates(keep: k, remove: Set(g), rightsFrom: r) }
        }
        for g in ready { duplicateKeeper[g[0]] = nil; duplicateRights[g[0]] = nil }
        duplicates?.groups.removeAll { g in ready.contains(g) }
        let waiting = duplicates?.groups.count ?? 0
        flash("Removed \(removed) duplicates from the library." + (waiting > 0 ? " \(waiting) \(waiting == 1 ? "set needs" : "sets need") a rights choice." : " Files on disk are untouched."))
    }

    @Published var health: LibraryHealth?
    @Published var healthOpen = false
    @Published var healthScanning = false
    @Published var sourceRefreshBusy = false
    @Published var sourceRefreshError: String?
    @Published var reviewedSourceID: UUID?
    @Published var sourceReviewPreview: SourceReviewPreview?
    @Published var sourceHistoryExpanded = false
    @Published var sourceQueueSelected: UUID?
    @Published var sourceQueueOpen = false
    @Published var sourceQueueAnchor: UUID?
    var sourceReviewQueue: SourceReviewQueue {
        SourceReviewQueue(pending: health?.changedSources ?? [], selected: sourceQueueSelected)
    }
    func selectSourceInQueue(_ id: UUID) {
        guard sourceReviewQueue.pending.contains(id) else { return }
        sourceQueueSelected = id
        sourceRefreshError = nil
    }

    struct SourceReviewPreview {
        let id: UUID
        let path: String
        let baseline: SourceFingerprint
        let current: SourceFingerprint
        let beforeResolution: String
        let afterResolution: String
        let beforePalette: [String]
        let afterPalette: [String]
    }
    private var healthGeneration = 0

    nonisolated static func sourceStat(_ path: String) -> (size: Int64, modified: TimeInterval)? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        guard let size = attrs?[.size] as? NSNumber, let date = attrs?[.modificationDate] as? Date,
              attrs?[.type] as? FileAttributeType == .typeRegular else { return nil }
        return (size.int64Value, date.timeIntervalSince1970)
    }

    nonisolated static func sourceFingerprint(_ path: String) -> SourceFingerprint? {
        guard let before = sourceStat(path), let digest = sha256(path: path), let after = sourceStat(path),
              before.size == after.size && before.modified == after.modified else { return nil }
        return SourceFingerprint(size: after.size, modified: after.modified, sha256: digest)
    }

    /// Prepare the actual on-disk candidate before asking for acceptance.
    func reviewChangedSource(_ id: UUID) {
        sourceReviewPreview = nil; sourceRefreshError = nil
        sourceQueueSelected = id
        guard !sourceRefreshBusy, let a = catalog.assets.first(where: { $0.id == id }),
              let path = a.importedPath, let old = a.sourceFingerprint,
              health?.changedSources.contains(id) == true,
              let current = Self.sourceFingerprint(path), old.status(against: current) == .changed else {
            sourceRefreshError = "Source changed since the scan. Check Again before reviewing."
            refreshHealth(full: true)
            return
        }
        var updated = a
        updated.palette = StudioCatalog.placeholderPalette
        updated.resolution = "Local file"
        var temp = StudioCatalog()
        temp.assets = [updated]
        enrichStarterMetadata(&temp, userFilesOnly: true)
        guard let derived = temp.assets.first, derived.resolution != "Local file",
              Self.sourceFingerprint(path) == current,
              catalog.assets.first(where: { $0.id == id })?.sourceFingerprint == old else {
            sourceRefreshError = "Could not read a stable source and its metadata. Check Again."
            refreshHealth(full: true)
            return
        }
        sourceReviewPreview = SourceReviewPreview(id: id, path: path, baseline: old, current: current,
            beforeResolution: a.resolution, afterResolution: derived.resolution,
            beforePalette: a.palette, afterPalette: derived.palette)
        reviewedSourceID = id
    }

    /// Refresh only the exact bytes and metadata the designer just reviewed.
    func refreshChangedSource(_ id: UUID) {
        guard !sourceRefreshBusy, let reviewed = sourceReviewPreview, reviewed.id == id,
              let a = catalog.assets.first(where: { $0.id == id }),
              a.importedPath == reviewed.path, a.sourceFingerprint == reviewed.baseline,
              a.resolution == reviewed.beforeResolution, a.palette == reviewed.beforePalette,
              health?.changedSources.contains(id) == true else {
            sourceRefreshError = "Library details changed since review. Check Again."
            sourceReviewPreview = nil
            return
        }
        sourceRefreshBusy = true; sourceRefreshError = nil
        sourceReviewPreview = nil
        // The source can change while the alert is open; a new digest requires a new review.
        guard Self.sourceFingerprint(reviewed.path) == reviewed.current else {
            sourceRefreshBusy = false
            sourceRefreshError = "Source changed since review. Check Again before refreshing."
            refreshHealth(full: true)
            return
        }
        var applied = false
        // A source refresh cannot be undone: the previous disk bytes are not in ASSSETS.
        // Keep the receipt out of transient catalog undo snapshots.
        mutate { c in
            applied = c.acceptChangedSource(reviewed.current, for: id, path: reviewed.path,
                palette: reviewed.afterPalette, resolution: reviewed.afterResolution, at: Date())
        }
        sourceRefreshBusy = false
        if applied {
            sourceQueueSelected = sourceReviewQueue.next(after: id)
            sourceQueueAnchor = sourceQueueSelected
            ThumbnailStore.shared.invalidate(id: id, path: reviewed.path)
            psdCache.removeValue(forKey: reviewed.path)
            lookCache.removeValue(forKey: lookKey(a))
            refreshAutoTags()
            refreshHealth(full: true)
            flash("Refreshed \(a.title); metadata receipt saved, not old file bytes.")
        }
    }
    @Published var folderRelinkOpen = false
    @Published var folderRelinkPreview: FolderRelinkPreview?
    @Published var folderRelinkMoveWatches = false

    func previewFolderRelink(oldRoot: String, newRoot: String) {
        let fm = FileManager.default
        folderRelinkPreview = FolderRelinkPreview(catalog: catalog, oldRoot: oldRoot, newRoot: newRoot,
            exists: { fm.fileExists(atPath: $0) }, isFile: { path in
                guard let attrs = try? fm.attributesOfItem(atPath: path) else { return false }
                return attrs[.type] as? FileAttributeType == .typeRegular
            }, isDirectory: { path in
                guard let attrs = try? fm.attributesOfItem(atPath: path) else { return false }
                return attrs[.type] as? FileAttributeType == .typeDirectory
            })
        folderRelinkMoveWatches = !(folderRelinkPreview?.watchMoves.isEmpty ?? true) && folderRelinkPreview?.watchIssue == nil
    }

    func applyFolderRelink() {
        guard let preview = folderRelinkPreview, !preview.matched.isEmpty else { return }
        let fm = FileManager.default
        // Disk and catalog can change while the sheet is open: never commit a stale preview.
        let fresh = FolderRelinkPreview(catalog: catalog, oldRoot: preview.oldRoot, newRoot: preview.newRoot,
            exists: { fm.fileExists(atPath: $0) }, isFile: { path in
                guard let attrs = try? fm.attributesOfItem(atPath: path) else { return false }
                return attrs[.type] as? FileAttributeType == .typeRegular
            }, isDirectory: { path in
                guard let attrs = try? fm.attributesOfItem(atPath: path) else { return false }
                return attrs[.type] as? FileAttributeType == .typeDirectory
            })
        let accepted = Set(preview.matched.map { "\($0.id):\($0.oldPath):\($0.newPath)" })
        let current = Set(fresh.matched.map { "\($0.id):\($0.oldPath):\($0.newPath)" })
        guard accepted == current && preview.watchMoves == fresh.watchMoves && preview.watchIssue == fresh.watchIssue else {
            folderRelinkPreview = fresh
            folderRelinkMoveWatches = false
            flash("Files or watch folders changed since preview. Review them again before relinking.")
            return
        }
        var n = 0
        let moveWatches = folderRelinkMoveWatches && fresh.watchIssue == nil
        mutate("Relink Moved Folder") { n = $0.relinkFolder(fresh, moveWatches: moveWatches) }
        missing = catalog.missingIDs { fm.fileExists(atPath: $0) }
        folderRelinkPreview = nil
        folderRelinkOpen = false
        refreshHealth()
        if moveWatches { scanWatchFolders() }
        flash("Relinked \(n) \(n == 1 ? "file" : "files")." +
            (moveWatches ? " Updated \(fresh.watchMoves.count) watched folder(s)." : " Watched folders stayed unchanged.") +
            " Unmatched files stayed untouched.")
    }

    /// Checks files, license copies and sizes off the main thread. `full` also hashes same-size files to count identical sets.
    func refreshHealth(full: Bool = false) {
        healthGeneration += 1
        let generation = healthGeneration
        let c = catalog
        // Every file, bundled ones too, so the identical-set count matches Find Duplicates. Big-file checks skip bundled media.
        let paths = Dictionary(uniqueKeysWithValues: c.assets.compactMap { a in a.importedPath.map { (a.id, $0) } })
        let root = licensesRoot
        let order = c.assets.map(\.id)
        if full { healthScanning = true }
        Task.detached(priority: .utility) {
            let fm = FileManager.default
            var sizes: [UUID: Int64] = [:]
            for (id, p) in paths { if let n = (try? fm.attributesOfItem(atPath: p))?[.size] as? NSNumber { sizes[id] = n.int64Value } }
            let folder = (try? fm.contentsOfDirectory(atPath: root.path)) ?? []
            var sets: Int? = nil
            if full {
                var hashes: [UUID: String] = [:]
                for id in Duplicates.needsHash(sizes: sizes) { if let p = paths[id], let h = Self.sha256(path: p) { hashes[id] = "\(sizes[id] ?? 0)-\(h)" } }
                sets = Duplicates.groups(hashes: hashes, order: order).count
            }
            var report = c.health(exists: { fm.fileExists(atPath: $0) }, licenseExists: { fm.fileExists(atPath: root.appendingPathComponent($0.stored).path) },
                                  licenseFolder: folder, sizes: sizes, duplicateSets: sets)
            // Normal sweeps use the cheap stat gate. Full Library Health checks hash even with unchanged
            // size/time, detecting same-path edits whose tools preserved metadata.
            var baselines: [(UUID, String, SourceFingerprint, Bool)] = []
            for a in c.assets where !a.isStarter && a.placementRecipe == nil {
                guard let path = a.importedPath, let stat = Self.sourceStat(path) else { continue }
                if let old = a.sourceFingerprint,
                   !full && old.size == stat.size && old.modified == stat.modified { continue }
                guard let current = Self.sourceFingerprint(path) else { continue }
                if let old = a.sourceFingerprint {
                    switch old.status(against: current) {
                    case .changed: report.changedSources.append(a.id)
                    case .timestampOnly: baselines.append((a.id, path, current, false))
                    case .unchanged: break
                    }
                } else { baselines.append((a.id, path, current, true)) }
            }
            await MainActor.run {
                guard generation == self.healthGeneration else { return }
                var r = report
                if !full, let old = self.health?.duplicateSets { r.duplicateSets = old }
                // Never overwrite a baseline that was added/accepted while this scan was running.
                var c = self.catalog, changed = false
                for (id, path, fingerprint, first) in baselines {
                    if first { changed = c.seedSourceFingerprint(fingerprint, for: id, path: path) || changed }
                    else { changed = c.acceptTimestampOnly(fingerprint, for: id, path: path) || changed }
                }
                if changed { self.catalog = c; self.save() }
                r.changedSources.removeAll { id in
                    guard let snapshot = c.assets.first(where: { $0.id == id }),
                          let live = self.catalog.assets.first(where: { $0.id == id }) else { return true }
                    return snapshot.importedPath != live.importedPath || snapshot.sourceFingerprint != live.sourceFingerprint
                }
                self.health = r
                self.sourceQueueSelected = SourceReviewQueue(pending: r.changedSources, selected: self.sourceQueueSelected).selected
                self.healthScanning = false
            }
        }
    }

    func openLibraryHealth() {
        healthOpen = true
        refreshHealth(full: true)
    }

    /// Deletes license records nothing uses and stray files in the Licenses folder.
    func cleanUpLicenseFolder() {
        guard let h = health else { return }
        let n = h.licenseCleanupCount
        pruneLicenseFiles()
        for f in h.strayLicenseFiles { try? FileManager.default.removeItem(at: licensesRoot.appendingPathComponent(f)) }
        flash("Removed \(n) unused license \(n == 1 ? "file" : "files")")
        refreshHealth()
    }

    func forgetMissingLicenseFiles() {
        guard let ids = health?.missingLicenseFiles, !ids.isEmpty else { return }
        var n = 0
        mutate("Detach Missing License Files") { n = $0.forgetMissingLicenseFiles(Set(ids)) }
        flash("Detached \(n) missing license \(n == 1 ? "file" : "files")")
        refreshHealth()
    }

    /// Closes Library Health and shows these assets selected in All Assets.
    func showFromHealth(_ ids: [UUID]) {
        healthOpen = false
        show(collection: StudioCatalog.allAssets)
        selection = Set(ids); focusID = ids.first
    }

    func reviewDuplicatesFromHealth() {
        healthOpen = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self.findDuplicates() }
    }

    /// System share menu (AirDrop, Mail, Messages, Notes...) with the same files a drag-out would give.
    func share(_ ids: Set<UUID>, anchor: NSView? = nil, checked: Bool = false) {
        if !checked {
            let order = filtered.map(\.id).filter(ids.contains) + ids.filter { id in !filtered.contains { $0.id == id } }
            guardRights(order, action: "Share", skip: { self.share(Set($0), anchor: nil, checked: true) }) { self.share(ids, anchor: anchor, checked: true) }
            return
        }
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
        rules.color = colorQuery
        if selectedCollection == StudioCatalog.favorites { rules.favoritesOnly = true }
        else if selectedCollection != StudioCatalog.allAssets { rules.collection = selectedCollection }
        let t = search.trimmingCharacters(in: .whitespaces)
        let colorName = colorQuery.map { "Near " + $0.hex }
        smartEditor = SmartEditorState(existing: nil, name: t.isEmpty ? (colorName ?? selectedKind?.rawValue ?? (ratingFilter.minRating > 0 ? "\(ratingFilter.minRating) Stars and Up" : "Smart Collection")) : t.capitalized, rules: rules)
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
            search = ""; selectedKind = nil; ratingFilter = RatingFilter(); keywordFilter = nil; colorQuery = nil
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
    func exportToFolder(_ ids: Set<UUID>, mode: DragOut.ExportMode, checked: Bool = false) {
        let picked = catalog.assets.filter { ids.contains($0.id) }
        guard !picked.isEmpty else { return }
        if !checked {
            guardRights(picked.map(\.id), action: "Export", skip: { self.exportToFolder(Set($0), mode: mode, checked: true) }) { self.exportToFolder(ids, mode: mode, checked: true) }
            return
        }
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
            if !added.isEmpty { enrichStarterMetadata(&c, userFilesOnly: true); Self.readFileMetadata(&c, ids: added); Self.seedSourceFingerprints(&c, ids: added); c.autoStack() }
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
        if demo != nil { isDemo = true; showInspector = demo != "focus" && demo != "board-edit" && demo != "board-annotate" && demo != "board-crop" && demo != "present-annotate" && demo != "board-review" && demo != "board-versions" && demo != "board-thread" && demo != "board-status" && demo != "board-templates" && demo != "board-template" && demo != "share-round" && demo != "feedback-preview" && demo != "feedback-imported" && demo != "board-arrange" && demo != "board-arrange-before" && demo != "board-versions-follow" && demo != "board-updated" && demo != "board-paste" && demo != "rights-expiring" && demo != "board-rights" && demo != "share-credits" }
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
        case "batch-place", "batch-place-results", "placement-presets", "batch-crop", "batch-crop-results", "batch-compare", "batch-focus", "batch-focus-next", "batch-focus-last", "batch-focus-fit":
            let starters = catalog.assets.filter(\.isStarter)
            let names = ["risograph-4k.png", "blueprint-4k.png", "ink-fiber-4k.png"]
            let art = names.compactMap { name in starters.first { $0.importedPath?.hasSuffix(name) == true } }
            if art.count >= 2 {
                show(collection: art[0].collection); selection = Set(art.map(\.id)); focusID = art[0].id
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    self.openBatchPlacement()
                    if let poster = self.mockupAssets.first(where: { $0.importedPath?.hasSuffix("poster-frame-mockup.psd") == true }) {
                        self.batchPlacement?.mockup = poster.id
                    }
                    if demo == "placement-presets", let state = self.batchPlacement {
                        self.saveBatchPlacementPreset(state, name: "Poster Launch")
                        if let saved = self.catalog.placementPresets.first(where: { $0.name == "Poster Launch" }) {
                            var active = state
                            _ = self.usePlacementPreset(saved, in: &active)
                            self.batchPlacement = active
                        }
                    }
                    if demo == "batch-crop" || demo == "batch-crop-results" || demo == "batch-compare" || demo == "batch-focus" || demo == "batch-focus-next" || demo == "batch-focus-last" {
                        self.batchPlacement?.crops[art[0].id] = BoardRect(x: 0.18, y: 0.12, w: 0.5, h: 0.5)
                        self.batchPlacement?.crops[art[1].id] = BoardRect(x: 0.05, y: 0.25, w: 0.7, h: 0.6)
                    }
                    if demo == "batch-focus-fit" {
                        self.batchPlacement?.mode = .fit
                        self.batchPlacement?.background = .slate
                    }
                    if demo == "batch-place-results" || demo == "batch-crop-results", let state = self.batchPlacement {
                        self.commitBatchPlacement(state)
                    }
                }
            }
        case "place-mockup", "place-all", "place-edit", "place-relink":
            // The risograph print into every bundled mockup: the sheet on the poster frame with a dragged crop, or all ten at once.
            let starters = catalog.assets.filter(\.isStarter)
            if let art = starters.first(where: { $0.importedPath?.hasSuffix("risograph-4k.png") == true }) {
                show(collection: art.collection)
                selection = [art.id]; focusID = art.id
                let poster = mockupAssets.first { $0.importedPath?.hasSuffix("poster-frame-mockup.psd") == true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    self.openPlaceIntoMockup(art.id, mockup: poster?.id)
                    guard var st = self.placing else { return }
                    st.crop = BoardRect(x: 0.18, y: 0.12, w: 0.5, h: 0.5)
                    if demo == "place-all" {
                        self.placeIntoAll(st, checked: true) { n in
                            try? "done placed=\(n)".write(to: self.supportRoot.appendingPathComponent("demo-place-all.txt"), atomically: true, encoding: .utf8)
                        }
                    } else if demo == "place-edit" || demo == "place-relink" {
                        self.commitPlace(st)
                        guard let id = self.focusID, let render = self.catalog.assets.first(where: { $0.id == id && $0.placementRecipe != nil }) else { return }
                        if demo == "place-relink" {
                            self.mutate { c in if let i = c.assets.firstIndex(where: { $0.id == art.id }) { c.assets[i].importedPath = "/missing/risograph-4k.png" } }
                        } else {
                            self.editPlacement(render)
                        }
                    } else {
                        self.placing = st
                    }
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
        case "color-search", "color-smart", "color-smart-editor":
            // A deep blue picked from the library's mockup backdrops; two earlier picks show in Recent.
            show(collection: StudioCatalog.allAssets)
            let blue = "#254BB4"
            if demo == "color-search" {
                for h in ["#E03131", "#40C057"] { mutate { $0.noteRecentColor(h) } }
                searchColor(blue, tolerance: 12)
                if let a = filtered.first { selection = [a.id]; focusID = a.id }
                // CI keeps the ranking with distances as text proof.
                let lines = filtered.prefix(20).compactMap { a -> String? in
                    guard let m = ColorSearch.match(colorQuery!, palette: a.palette) else { return nil }
                    return String(format: "%@\t%@\t%.2f", a.title, a.palette.first ?? "", m.distance)
                }
                try? (["query \(blue) tolerance 12 · \(filtered.count) matches"] + lines).joined(separator: "\n")
                    .write(to: supportRoot.appendingPathComponent("demo-color-search.txt"), atomically: true, encoding: .utf8)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.showColorPicker = true }
            } else {
                var id = UUID()
                mutate("New Smart Collection") { id = $0.createSmartCollection(named: "Blue Hour", rules: SmartRules(color: ColorQuery(hex: blue, tolerance: 12))) }
                show(smart: id)
                if let a = filtered.first { selection = [a.id]; focusID = a.id }
                if demo == "color-smart-editor" { beginEdit(smart: id) }
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
        case "board", "board-export":
            let id = makeDemoBoard()
            show(board: id)
            if demo == "board" {
                // An asset card is selected so the resize handle and card chrome show in the shot.
                if let b = catalog.board(id), let first = b.items.first(where: { $0.kind == .asset }) {
                    boardItem = first.id; if let a = first.assetID { selection = [a]; focusID = a }
                }
            } else {
                let out = supportRoot.appendingPathComponent("demo-board.png")
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    let size = await self.writeBoard(id, pdf: false, to: out)
                    let pdf = await self.writeBoard(id, pdf: true, to: self.supportRoot.appendingPathComponent("demo-board.pdf"))
                    let items = self.catalog.board(id)?.items.count ?? 0
                    try? "done \(Int(size?.width ?? 0))x\(Int(size?.height ?? 0)) \(items) items pdf=\(pdf != nil)".write(to: self.supportRoot.appendingPathComponent("demo-board.txt"), atomically: true, encoding: .utf8)
                }
            }
        case "focus", "present", "board-gallery":
            let id = makeDemoBoard()
            show(board: id)
            if demo == "present" {
                startPresenting(id)
                presentIndex = 0
            } else if demo == "board-gallery" {
                let out = supportRoot.appendingPathComponent("demo-board-gallery", isDirectory: true)
                try? FileManager.default.removeItem(at: out)
                try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.shareBoardGallery(id, to: out) }
            } else if let b = catalog.board(id), let first = b.items.first(where: { $0.kind == .asset }) {
                boardItem = first.id; if let a = first.assetID { selection = [a]; focusID = a }
            }
        case "board-templates":
            // One saved template next to the built-ins, then the picker.
            let id = makeDemoApproval().0
            mutate { _ = $0.saveTemplate(from: id, named: "Lobby Review Layout", summary: "Our lobby board: sections, notes and palette, images cleared.") }
            show(board: id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.templatePickerOpen = true }
        case "board-template":
            // Brand Direction A/B filled from the library, one slot left empty on purpose.
            var id: UUID?
            mutate { id = $0.createBoard(from: BoardTemplate.brandID, named: "Cafe Rebrand") }
            if let id {
                // Reading order fills A hero, B hero, A detail; the two fills then take A detail 2 and B detail 1.
                let files = ["terrazzo-texture.png", "bauhaus-vector-01.svg", "marble-veins-texture.png", "watercolor-wash-texture.png", "bauhaus-vector-02.svg"]
                let ids = files.compactMap { f in catalog.assets.first { $0.importedPath?.hasSuffix(f) == true }?.id }
                let aspects = ids.map { i in Moodboard.aspect(resolution: catalog.assets.first { $0.id == i }?.resolution ?? "") }
                mutate { c in
                    _ = c.placeOnBoard(id, assets: Array(ids.prefix(3)))
                    _ = c.updateBoard(id) { b in
                        // The first two slots left in Direction B, so its small detail slot stays empty.
                        for (i, slot) in b.emptySlots.prefix(2).enumerated() where i + 3 < ids.count {
                            b.fillSlot(slot, with: ids[i + 3], aspect: aspects[i + 3])
                        }
                        let notes = b.items.filter { $0.kind == .note }.map(\.id)
                        if notes.count >= 2 {
                            b.setText(notes[0], "Direction A: stone, marble and wash, quiet and tactile.")
                            b.setText(notes[1], "Direction B: bold shapes and color, louder at the counter.")
                        }
                    }
                }
                show(board: id)
            }
        case "share-round":
            let id = makeDemoApproval().0
            show(board: id)
            let out = supportRoot.appendingPathComponent("demo-share-round", isDirectory: true)
            try? FileManager.default.removeItem(at: out)
            try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.shareRound(id, to: out) }
        case "feedback-preview", "feedback-imported":
            // A third reviewer's file with Approve / Request changes, against the Lobby Refresh round.
            let id = makeDemoApproval().0
            show(board: id)
            let f = demoApprovalFeedback()
            if demo == "feedback-preview" {
                let u = FileManager.default.temporaryDirectory.appendingPathComponent("Lobby Refresh feedback - Jordan Lee.json")
                if let data = try? JSONEncoder().encode(f) { try? data.write(to: u) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { self.previewFeedback([u]) }
            } else {
                importFeedback(feedback: [f], unreadable: 0)
            }
        case "board-arrange", "board-arrange-before":
            // Four signage options dropped in by hand, then matched, top-aligned and evenly spaced.
            let all = catalog.assets
            func find(_ f: String) -> StudioAsset? { all.first { $0.importedPath?.hasSuffix(f) == true } }
            var id = UUID(), cards: [UUID] = []
            mutate { c in
                id = c.createBoard(named: "Signage Options")
                _ = c.updateBoard(id) { b in
                    b.snap = false
                    b.addHeading("Signage options", at: (x: 40, y: 20))
                    let place: [(String, Double, Double, Double)] = [
                        ("album-gatefold-mockup.png", 40, 150, 260), ("cosmetic-plinth-mockup.png", 430, 230, 200),
                        ("device-stage-mockup.png", 790, 120, 300), ("terrazzo-texture.png", 1220, 260, 180)]
                    for (f, x, y, w) in place { if let a = find(f) { cards.append(b.addAsset(a.id, aspect: Moodboard.aspect(resolution: a.resolution), width: w, at: (x: x, y: y))) } }
                    b.addNote("Line these up before the client call.", at: (x: 40, y: 520))
                }
            }
            if demo == "board-arrange" {
                let sel = Set(cards)
                updateBoard(id, "Match Heights") { $0.arrange(sel, .matchHeight) }
                updateBoard(id, "Align Top Edges") { $0.arrange(sel, .top) }
                updateBoard(id, "Distribute Horizontally") { $0.arrange(sel, .distributeH) }
            }
            show(board: id)
            boardSelection = Set(cards)
        case "board-versions-follow", "board-updated", "inspector-on-boards", "board-paste":
            // A client drop with three rounds of the lobby floor; the board still shows v1 and v2 (1.24).
            let fm = FileManager.default
            let drop = fm.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Client Drops", isDirectory: true)
            try? fm.removeItem(at: drop)
            try? fm.createDirectory(at: drop, withIntermediateDirectories: true)
            for (src, dst) in [("terrazzo-texture.png", "Lobby Floor v1.png"), ("marble-veins-texture.png", "Lobby Floor v2.png"),
                               ("cork-board-texture.png", "Lobby Floor final.png")] where fm.fileExists(atPath: starterRoot.appendingPathComponent(src).path) {
                try? fm.copyItem(at: starterRoot.appendingPathComponent(src), to: drop.appendingPathComponent(dst))
            }
            watch([drop.path])
            scanWatchFolders()
            let all = catalog.assets
            func find(_ f: String) -> StudioAsset? { all.first { $0.importedPath?.hasSuffix(f) == true } }
            var id = UUID(), second = UUID(), cards: [UUID] = []
            mutate { c in
                id = c.createBoard(named: "Lobby Concepts")
                _ = c.updateBoard(id) { b in
                    b.addHeading("Lobby concepts · round 2", at: (x: 40, y: 20))
                    let place: [(String, Double, Double, Double)] = [("Lobby Floor v1.png", 40, 130, 380), ("Lobby Floor v2.png", 470, 130, 380),
                                                                     ("device-stage-mockup.png", 900, 130, 420)]
                    for (f, x, y, w) in place { if let a = find(f) { cards.append(b.addAsset(a.id, aspect: Moodboard.aspect(resolution: a.resolution), width: w, at: (x: x, y: y))) } }
                    if cards.count > 2 { _ = b.connect(cards[1], cards[2], label: "floor → stage") }
                    if let first = cards.first { _ = b.setStatus(.approved, for: [first]) }
                    b.addNote("Client approved the floor in round 1. The studio has since sent v2 and a final.", at: (x: 40, y: 560))
                }
                second = c.createBoard(named: "Client Deck")
                _ = c.updateBoard(second) { b in
                    b.addHeading("Client deck · lobby", at: (x: 40, y: 20))
                    if let a = find("album-gatefold-mockup.png") { _ = b.addAsset(a.id, aspect: Moodboard.aspect(resolution: a.resolution), width: 320, at: (x: 40, y: 130)) }
                    if let a = find("Lobby Floor v2.png") { _ = b.addAsset(a.id, aspect: Moodboard.aspect(resolution: a.resolution), width: 240, at: (x: 1100, y: 480)) }
                }
            }
            switch demo {
            case "board-updated":
                updateToNewest(id)
                show(board: id)
                boardSelection = Set(cards.prefix(2))
            case "inspector-on-boards":
                show(collection: StudioCatalog.inboxCollection)
                if let v2 = find("Lobby Floor v2.png") { selection = [v2.id]; focusID = v2.id }
            case "board-paste":
                show(board: id)
                boardSelection = Set(cards.suffix(2))
                copyCards()
                show(board: second)
                pasteCards()
            default:
                show(board: id)
                boardSelection = []
            }
        case "rights-inspector", "rights-expiring", "board-rights", "share-credits", "rights-bulk", "rights-report", "rights-alerts",
             "license-files", "rights-presets", "export-guard", "batch-license-row", "duplicates-merge", "library-health", "folder-relink", "folder-relink-apply", "folder-relink-collapsed", "changed-source", "changed-source-review", "changed-source-apply", "changed-source-inspector", "source-history-inspector", "source-review-queue", "source-review-queue-next":
            // A client drop for a hotel pitch: licensed photos with credits and end dates, one expired,
            // one editorial-only, one client-supplied and one with nothing entered yet (1.25).
            let fm = FileManager.default
            let drop = fm.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Client Drops", isDirectory: true)
            try? fm.removeItem(at: drop)
            try? fm.createDirectory(at: drop, withIntermediateDirectories: true)
            let files: [(String, String)] = [("marble-veins-texture.png", "Northlight Lobby.png"), ("cork-board-texture.png", "Atrium Cork Wall.png"),
                                             ("night-grid-4k.png", "Harbor Night.png"), ("cosmetic-plinth-mockup.png", "Plinth Campaign.png"),
                                             ("terrazzo-texture.png", "Wire Terrazzo.png"), ("device-stage-mockup.png", "Stage Mockup.png")]
            for (src, dst) in files where fm.fileExists(atPath: starterRoot.appendingPathComponent(src).path) {
                try? fm.copyItem(at: starterRoot.appendingPathComponent(src), to: drop.appendingPathComponent(dst))
            }
            if demo == "duplicates-merge" || demo == "library-health" {
                // 1.28: the client re-sent two files. Same bytes, different names, and each copy picked up its own metadata.
                try? fm.createDirectory(at: drop.appendingPathComponent("Round 2"), withIntermediateDirectories: true)
                try? fm.copyItem(at: starterRoot.appendingPathComponent("marble-veins-texture.png"), to: drop.appendingPathComponent("Round 2/Lobby Hero final.png"))
                try? fm.copyItem(at: starterRoot.appendingPathComponent("terrazzo-texture.png"), to: drop.appendingPathComponent("Round 2/Terrazzo Swatch.png"))
            }
            if demo == "library-health" {
                // A walkthrough render the client sent: a bundled loop padded out past the big-file line.
                let mov = drop.appendingPathComponent("Lobby Walkthrough.mp4")
                try? fm.copyItem(at: starterRoot.appendingPathComponent("motion-loop-01.mp4"), to: mov)
                if let h = try? FileHandle(forWritingTo: mov) { try? h.truncate(atOffset: UInt64(LibraryHealth.bigFileBytes) + 36 * 1024 * 1024); try? h.close() }
            }
            watch([drop.path])
            scanWatchFolders()
            let all = catalog.assets
            func find(_ f: String) -> StudioAsset? { all.first { $0.importedPath?.hasSuffix(f) == true } }
            func inDays(_ d: Int) -> String { UsageRights.day(Calendar.current.date(byAdding: .day, value: d, to: Date()) ?? Date()) }
            let rights: [(String, UsageRights)] = [
                ("Northlight Lobby.png", UsageRights(license: .licensed, source: "Northlight Images · order NL-20417", credit: "Photo: Lena Ortiz / Northlight",
                                                     uses: "Web, social and print pitch decks", expires: inDays(12))),
                ("Atrium Cork Wall.png", UsageRights(license: .licensed, source: "Northlight Images · order NL-20417", credit: "Photo: Sam Reyes / Northlight",
                                                     uses: "Web and social", expires: inDays(26))),
                ("Harbor Night.png", UsageRights(license: .licensed, source: "Harbor Stock", credit: "Harbor Stock / K. Maru", uses: "Web only", expires: inDays(-9))),
                ("Plinth Campaign.png", UsageRights(license: .client, source: "Maison Vale brand team", credit: "Courtesy of Maison Vale", uses: "This campaign only")),
                ("Wire Terrazzo.png", UsageRights(license: .editorial, source: "Wirepress", credit: "Photo: Dev Arora / Wirepress", uses: "News and commentary only")),
            ]
            for (f, r) in rights { if let a = find(f) { setRights(r, for: [a.id], quiet: true) } }
            // License paperwork (1.27): the Northlight order covers both Northlight photos; Harbor's invoice sits with Harbor Night.
            let docs = makeDemoLicenseFiles()
            let northlight = [find("Northlight Lobby.png"), find("Atrium Cork Wall.png")].compactMap { $0?.id }
            let order = docs["order"].map { attachLicenseFiles([$0], to: northlight, quiet: true) } ?? []
            if let r = docs["receipt"], let lobby = northlight.first { attachLicenseFiles([r], to: [lobby], quiet: true) }
            if let h = docs["harbor"], let a = find("Harbor Night.png") { attachLicenseFiles([h], to: [a.id], quiet: true) }
            mutate { c in
                c.saveRightsPreset(name: "Northlight · NL-20417", rights: UsageRights(license: .licensed, source: "Northlight Images · order NL-20417",
                                   credit: "Photo: {title} / Northlight", uses: "Web and social"), termYears: 1, docs: order.map(\.id))
                c.saveRightsPreset(name: "Maison Vale", rights: UsageRights(license: .client, source: "Maison Vale brand team",
                                   credit: "Courtesy of Maison Vale", uses: "This campaign only"))
                c.saveRightsPreset(name: "Own work", rights: UsageRights(license: .own, credit: "Studio"))
            }
            var id = UUID()
            mutate { c in
                id = c.createBoard(named: "Hotel Pitch")
                _ = c.updateBoard(id) { b in
                    b.addHeading("Hotel pitch · lobby and atrium", at: (x: 40, y: 20))
                    let place: [(String, Double, Double, Double)] = [("Northlight Lobby.png", 40, 130, 330), ("Harbor Night.png", 410, 130, 430),
                                                                     ("Wire Terrazzo.png", 880, 130, 300), ("Plinth Campaign.png", 40, 620, 330),
                                                                     ("Atrium Cork Wall.png", 410, 620, 300)]
                    for (f, x, y, w) in place { if let a = find(f) { _ = b.addAsset(a.id, aspect: Moodboard.aspect(resolution: a.resolution), width: w, at: (x: x, y: y)) } }
                }
            }
            if demo == "duplicates-merge" || demo == "library-health" {
                // The re-sent lobby photo was rated, labeled, tagged and pinned on the board; the terrazzo copy came with
                // an agency license that disagrees with the editorial-only original.
                if let hero = find("Lobby Hero final.png") {
                    mutate { c in
                        _ = c.setRating([hero.id], 4)
                        _ = c.toggleLabel([hero.id], .purple)
                        _ = c.addTags("hero, lobby", to: [hero.id])
                        _ = c.updateBoard(id) { b in _ = b.addAsset(hero.id, aspect: Moodboard.aspect(resolution: hero.resolution), width: 300, at: (x: 880, y: 620)) }
                    }
                }
                if let sw = find("Terrazzo Swatch.png") {
                    setRights(UsageRights(license: .licensed, source: "Harbor Stock · order HS-3381", credit: "Harbor Stock / K. Maru", uses: "Web and print"), for: [sw.id], quiet: true)
                }
            }
            switch demo {
            case "batch-license-row":
                // Both Northlight photos: the order covers both, the receipt only the lobby, so the receipt shows "Add to all".
                show(collection: StudioCatalog.inboxCollection)
                let pair = ["Northlight Lobby.png", "Atrium Cork Wall.png"].compactMap { find($0)?.id }
                selection = Set(pair); focusID = pair.first
                inspectorAnchor = "license-files"
            case "duplicates-merge":
                show(collection: StudioCatalog.inboxCollection)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.findDuplicates() }
            case "folder-relink", "folder-relink-apply", "folder-relink-collapsed":
                let previous = fm.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Moved Project")
                let current = fm.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Relocated Project")
                try? fm.removeItem(at: previous); try? fm.removeItem(at: current)
                try? fm.createDirectory(at: previous.appendingPathComponent("Campaign"), withIntermediateDirectories: true)
                try? fm.createDirectory(at: current.appendingPathComponent("Campaign"), withIntermediateDirectories: true)
                _ = catalog.addWatchFolder(previous.path)
                for (source, name) in [("risograph-4k.png", "Campaign/Poster.png"),
                                       ("ink-fiber-4k.png", "Campaign/Texture.png"),
                                       ("blueprint-4k.png", "Campaign/Unmatched.png")] {
                    let old = previous.appendingPathComponent(name)
                    try? fm.copyItem(at: starterRoot.appendingPathComponent(source), to: old)
                    _ = catalog.importFile(path: old.path)
                    if name != "Campaign/Unmatched.png" {
                        try? fm.moveItem(at: old, to: current.appendingPathComponent(name))
                    } else { try? fm.removeItem(at: old) }
                }
                missing = catalog.missingIDs { fm.fileExists(atPath: $0) }
                show(collection: StudioCatalog.inboxCollection)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    self.openLibraryHealth()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        self.folderRelinkOpen = true
                        self.previewFolderRelink(oldRoot: previous.path, newRoot: current.path)
                        if ProcessInfo.processInfo.arguments.contains("folder-relink-apply") {
                            self.applyFolderRelink()
                            let watchOK = self.catalog.watchFolders.contains(current.path) && !self.catalog.watchFolders.contains(previous.path)
                            let paths = self.catalog.assets.compactMap(\.importedPath)
                            let n = paths.filter { $0.hasPrefix(current.path + "/") }.count
                            let old = paths.filter { $0.hasPrefix(previous.path + "/") }.count
                            try? "done relinked=\(n) unmatched=\(old) watch=\(watchOK ? "moved" : "not-moved")".write(to: self.supportRoot.appendingPathComponent("demo-folder-relink.txt"), atomically: true, encoding: .utf8)
                        }
                    }
                }
            case "changed-source", "changed-source-review", "changed-source-apply", "changed-source-inspector", "source-history-inspector", "source-review-queue", "source-review-queue-next":
                show(collection: StudioCatalog.inboxCollection)
                if let source = find("Northlight Lobby.png"), let path = source.importedPath,
                   let baseline = Self.sourceFingerprint(path) {
                    // `find` above came from `all` before the demo's rights were assigned.
                    let expectedRights = catalog.assets.first { $0.id == source.id }?.rights
                    mutate { $0.seedSourceFingerprint(baseline, for: source.id, path: path) }
                    let replacement = starterRoot.appendingPathComponent("risograph-4k.png")
                    try? fm.removeItem(atPath: path)
                    try? fm.copyItem(at: replacement, to: URL(fileURLWithPath: path))
                    if demo == "source-review-queue" || demo == "source-review-queue-next" {
                        // Second changed original in the same import set, separately fingerprinted and replaced.
                        if let another = find("Atrium Cork Wall.png"), let otherPath = another.importedPath,
                           let otherBase = Self.sourceFingerprint(otherPath) {
                            mutate { $0.seedSourceFingerprint(otherBase, for: another.id, path: otherPath) }
                            try? fm.removeItem(atPath: otherPath)
                            try? fm.copyItem(at: starterRoot.appendingPathComponent("blueprint-4k.png"), to: URL(fileURLWithPath: otherPath))
                        }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                        self.openLibraryHealth()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            if demo == "source-review-queue" || demo == "source-review-queue-next" {
                                self.sourceQueueOpen = true
                                self.sourceQueueAnchor = source.id
                                self.sourceQueueSelected = source.id
                                if demo == "source-review-queue-next" {
                                    self.reviewChangedSource(source.id)
                                    self.reviewedSourceID = nil
                                    self.refreshChangedSource(source.id)
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                        let q = self.sourceReviewQueue
                                        let ok = q.pending.count == 1 && q.selected != source.id &&
                                            self.catalog.sourceHistory(for: source.id).count == 1 &&
                                            self.catalog.sourceHistory(for: q.selected ?? source.id).isEmpty
                                        try? "done queue-next=\(ok) pending=\(q.pending.count)".write(
                                            to: self.supportRoot.appendingPathComponent("demo-source-queue.txt"), atomically: true, encoding: .utf8)
                                    }
                                }
                            }
                            if demo == "changed-source-review" { self.reviewChangedSource(source.id) }
                            if demo == "changed-source-inspector" {
                                self.healthOpen = false
                                self.selection = [source.id]; self.focusID = source.id
                                self.inspectorAnchor = "source-changes"
                            }
                            if demo == "changed-source-apply" || demo == "source-history-inspector" {
                                self.reviewChangedSource(source.id)
                                self.reviewedSourceID = nil
                                self.refreshChangedSource(source.id)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                    let a = self.catalog.assets.first { $0.id == source.id }
                                    let passed = a?.sourceFingerprint?.sha256 != baseline.sha256 && a?.rights == expectedRights
                                        && self.catalog.boardsUsing(source.id).count > 0 && self.catalog.sourceHistory(for: source.id).count == 1
                                    if demo == "source-history-inspector" {
                                        self.healthOpen = false
                                        self.selection = [source.id]; self.focusID = source.id
                                        self.inspectorAnchor = "source-changes"
                                    }
                                    try? "done changed=\(passed) rights=\(a?.rights != nil) boards=\(self.catalog.boardsUsing(source.id).count)".write(
                                        to: self.supportRoot.appendingPathComponent("demo-changed-source.txt"), atomically: true, encoding: .utf8)
                                }
                            }
                        }
                    }
                }
            case "library-health":
                // One file moved away, one license copy deleted, a stray file in the Licenses folder, and a licensed photo with no credit.
                if let atrium = find("Atrium Cork Wall.png"), let p = atrium.importedPath {
                    try? fm.moveItem(atPath: p, toPath: fm.temporaryDirectory.appendingPathComponent("Atrium Cork Wall.png").path)
                }
                if let harbor = find("Harbor Night.png"), let d = catalog.licenseDocs(for: harbor.id).first { try? fm.removeItem(at: licenseURL(d)) }
                try? "Harbor Stock quote, superseded".write(to: licensesRoot.appendingPathComponent("old-quote-HS-3102.txt"), atomically: true, encoding: .utf8)
                if let stage = find("Stage Mockup.png") {
                    setRights(UsageRights(license: .licensed, source: "Mockup Market · order MM-889", uses: "Pitch decks"), for: [stage.id], quiet: true)
                }
                missing = catalog.missingIDs { fm.fileExists(atPath: $0) }
                show(collection: StudioCatalog.inboxCollection)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.openLibraryHealth() }
            case "rights-inspector":
                show(collection: StudioCatalog.inboxCollection)
                if let a = find("Northlight Lobby.png") { selection = [a.id]; focusID = a.id }
            case "rights-expiring":
                if let smart = catalog.smartCollections.first(where: { $0.name == "Rights Expiring" }) { show(smart: smart.id) }
            case "board-rights":
                show(board: id)
            case "rights-bulk":
                // Two files from the same Northlight order: license and source match, credit, uses and end date differ.
                show(collection: StudioCatalog.inboxCollection)
                let pair = ["Northlight Lobby.png", "Atrium Cork Wall.png"].compactMap { find($0)?.id }
                selection = Set(pair); focusID = pair.first
            case "rights-report":
                show(collection: StudioCatalog.inboxCollection)
                let ids = filtered.map(\.id)
                selection = Set(ids)
                let report = catalog.rightsReport(ids, title: "Hotel Pitch · client drop")
                let pdf = supportRoot.appendingPathComponent("demo-rights-report.pdf"), csv = supportRoot.appendingPathComponent("demo-rights-report.csv")
                let png = supportRoot.appendingPathComponent("demo-rights-report.png")
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    let pages = await self.writeRightsReport(report, pdf: pdf, csv: csv, png: png)
                    try? "done pages=\(pages) rows=\(report.rows.count)".write(to: self.supportRoot.appendingPathComponent("demo-rights-report.txt"), atomically: true, encoding: .utf8)
                }
            case "license-files":
                show(collection: StudioCatalog.inboxCollection)
                if let a = find("Northlight Lobby.png") { selection = [a.id]; focusID = a.id }
                inspectorAnchor = "license-files"
            case "rights-presets":
                // Three new files that need rights: one click on a preset fills them in.
                show(collection: StudioCatalog.inboxCollection)
                let three = ["Northlight Lobby.png", "Atrium Cork Wall.png", "Stage Mockup.png"].compactMap { find($0)?.id }
                selection = Set(three); focusID = three.first
            case "export-guard":
                show(collection: StudioCatalog.inboxCollection)
                let ids = filtered.map(\.id)
                selection = Set(ids)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.exportToFolder(Set(ids), mode: .asShown) }
            case "rights-alerts":
                // As if ASSSETS was last opened 20 days ago: Harbor Night's license ended in between.
                show(collection: StudioCatalog.inboxCollection)
                checkRightsSinceLastLaunch(since: inDays(-20))
                if let a = find("Harbor Night.png") { selection = [a.id]; focusID = a.id }
            default:
                show(board: id)
                let out = supportRoot.appendingPathComponent("demo-share-credits", isDirectory: true)
                try? fm.removeItem(at: out)
                try? fm.createDirectory(at: out, withIntermediateDirectories: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.shareRound(id, to: out) }
            }
        case "board-thread", "board-status":
            let (id, stage) = makeDemoApproval()
            show(board: id)
            if demo == "board-thread" {
                boardSelection = [stage]
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { self.threadCard = stage }
            } else {
                boardStatusFilter = .approved
                let out = supportRoot.appendingPathComponent("demo-summary.pdf"), png = supportRoot.appendingPathComponent("demo-summary.png")
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    let rows = await self.writeRoundSummary(id, to: out, png: png)
                    try? "done rows=\(rows ?? -1)".write(to: self.supportRoot.appendingPathComponent("demo-summary.txt"), atomically: true, encoding: .utf8)
                }
            }
        case "board-review", "board-versions":
            let id = makeDemoReviewRound()
            show(board: id)
            if demo == "board-review" { boardClientOnly = true }
            else { DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { self.boardVersionsOpen = true } }
        case "board-edit":
            let id = makeDemoSections()
            show(board: id)
            boardSelection = demoDrag?.0 ?? []   // show() cleared it
        case "board-annotate", "board-crop", "present-annotate":
            let (id, picked, plinth) = makeDemoAnnotated()
            show(board: id)
            if demo == "board-annotate" {
                boardSelection = [picked]
                let out = supportRoot.appendingPathComponent("demo-annotate.png")
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    let size = await self.writeBoard(id, pdf: false, to: out)
                    let arrows = self.catalog.board(id)?.connectors.count ?? 0
                    try? "done \(Int(size?.width ?? 0))x\(Int(size?.height ?? 0)) arrows=\(arrows)".write(to: self.supportRoot.appendingPathComponent("demo-annotate.txt"), atomically: true, encoding: .utf8)
                }
            } else if demo == "board-crop" {
                demoLink = nil
                if let it = catalog.board(id)?.items.first(where: { $0.id == plinth }) {
                    boardSelection = [plinth]
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.beginCrop(it) }
                }
            } else {
                demoLink = nil
                startPresenting(id)
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

// MARK: - Moodboards (1.16)

extension StudioLibrary {
    var currentBoard: Moodboard? { selectedBoard.flatMap { catalog.board($0) } }

    func show(board id: UUID) {
        guard catalog.board(id) != nil else { return }
        similarTo = nil; selectedSmart = nil; boardItem = nil; editingNote = nil; editingConnector = nil
        if selectedBoard != id { boardClientOnly = false; boardReviewer = nil; boardVersionsOpen = false; boardStatusFilter = nil; threadCard = nil }
        selectedBoard = id
        fitBoardRequest += 1
    }

    /// Records one undo step for any board edit.
    func updateBoard(_ id: UUID, _ undo: String, _ change: (inout Moodboard) -> Void) {
        mutate(undo) { _ = $0.updateBoard(id, change) }
    }

    func newBoard(with ids: Set<UUID>) {
        var id = UUID()
        let ordered = filtered.map(\.id).filter(ids.contains) + ids.filter { i in !filtered.contains { $0.id == i } }
        mutate("New Board") { c in
            id = c.createBoard(named: "New Board")
            _ = c.addToBoard(id, assets: ordered)
        }
        show(board: id)
        renamingBoard = id
    }

    func addToBoard(_ id: UUID, ids: Set<UUID>, at point: (x: Double, y: Double)? = nil) {
        let ordered = filtered.map(\.id).filter(ids.contains) + ids.filter { i in !filtered.contains { $0.id == i } }
        var n = 0
        // Empty template slots fill first (1.22).
        mutate("Add to Board") { n = $0.placeOnBoard(id, assets: ordered, at: point) }
        let name = catalog.board(id)?.name ?? "board"
        let issues = n == 0 ? [] : catalog.rightsIssues(ordered)
        if let first = issues.first {
            flash("Added \(n) to \(name) · \(issues.count == 1 ? first.title + ": " + first.status.label.lowercased() : "\(issues.count) have expired or editorial-only rights")")
        } else {
            flash(n == 0 ? "Already on \(name)" : "Added \(n) to \(name)")
        }
    }

    func newBoard(fromTemplate tid: UUID) {
        var id: UUID?
        mutate("New Board from Template") { id = $0.createBoard(from: tid) }
        templatePickerOpen = false
        if let id { show(board: id); flash("Drag images onto the empty slots, or use Add to Board") }
    }

    func saveTemplate(_ board: UUID, named name: String) {
        var t: UUID?
        mutate("Save as Template") { t = $0.saveTemplate(from: board, named: name) }
        if let t, let tpl = catalog.template(t) { flash("Saved template \(tpl.name) · \(tpl.slotCount) image slots") }
    }

    func clearSlot(_ item: UUID) {
        guard let id = selectedBoard else { return }
        updateBoard(id, "Remove Image") { $0.clearSlot(item) }
    }

    /// Share Round (1.22): the board's review gallery with the round summary PDF inside the same zip.
    func shareRound(_ id: UUID, to fixedDir: URL? = nil, checked: Bool = false) {
        if fixedDir == nil, !checked, let b = catalog.board(id) {
            guardRights(b.items.compactMap(\.assetID), action: "Share Round") { self.shareRound(id, to: nil, checked: true) }
            return
        }
        let pdf = FileManager.default.temporaryDirectory.appendingPathComponent("round-summary-\(UUID().uuidString).pdf")
        Task { @MainActor in
            guard await self.writeRoundSummary(id, to: pdf) != nil else { self.flash("Couldn't make the round summary"); return }
            self.shareBoardGallery(id, to: fixedDir, summaryPDF: pdf, checked: true)
        }
    }

    func renameBoard(_ id: UUID, to name: String) {
        var ok = false
        mutate("Rename Board") { ok = $0.renameBoard(id, to: name) }
        if !ok { flash("A board with that name already exists") }
    }

    func deleteBoard(_ id: UUID) {
        let name = catalog.board(id)?.name ?? "board"
        mutate("Delete Board") { _ = $0.deleteBoard(id) }
        if selectedBoard == id { show(collection: StudioCatalog.allAssets) }
        flash("Deleted \(name) · ⌘Z to undo")
    }

    /// Runs `proceed` right away when every asset is cleared for use; otherwise asks first (1.25).
    /// With `skip`, the warning also offers to go ahead with only the cleared assets (1.27).
    func guardRights(_ ids: [UUID], action: String, skip: (([UUID]) -> Void)? = nil, proceed: @escaping () -> Void) {
        let check = catalog.rightsCheck(ids)
        if check.issues.isEmpty { proceed() }
        else { rightsWarning = RightsWarning(action: action, issues: check.issues, cleared: check.cleared, proceed: proceed, skip: check.cleared.isEmpty ? nil : skip) }
    }

    /// Saves usage rights and writes them to the sidecar of the user's own files.
    func setRights(_ r: UsageRights?, for ids: Set<UUID>, quiet: Bool = false) {
        var n = 0
        mutate("Edit Rights") { n = $0.setRights(r, for: ids) }
        guard n > 0 else { return }
        writeMetadata(ids, quiet: true)
        if quiet { return }
        flash(r?.isEmpty ?? true ? "Cleared rights" : "Saved rights\(catalog.assets.contains { ids.contains($0.id) && !$0.isStarter && $0.importedPath != nil } ? " · written to the .xmp sidecar" : "")")
    }

    func credits(_ ids: [UUID]) -> [CreditLine] { includeCredits ? catalog.credits(for: ids) : [] }

    // MARK: Bulk rights and the rights report (1.26)

    func applyRights(_ edit: RightsEdit, to ids: [UUID]) {
        var n = 0
        mutate("Edit Rights") { n = $0.applyRights(edit, to: ids) }
        guard n > 0 else { flash("Nothing to change"); return }
        writeMetadata(Set(ids), quiet: true)
        flash("Updated rights on \(n) asset\(n == 1 ? "" : "s")")
    }

    func extendRights(_ ids: Set<UUID>) {
        var n = 0
        mutate("Extend Rights") { n = $0.extendRights(ids) }
        if n > 0 { writeMetadata(ids, quiet: true) }
        flash(n == 0 ? "No end dates to extend" : "Extended \(n) license\(n == 1 ? "" : "s") by a year · ⌘Z to undo")
    }

    func markRenewed(_ ids: Set<UUID>) {
        var n = 0
        mutate("Mark Renewed") { n = $0.markRenewed(ids) }
        if n > 0 { writeMetadata(ids, quiet: true) }
        flash("Marked \(n) renewed today, ending in a year · ⌘Z to undo")
    }

    /// Asks where to save, then writes "<title> rights report.pdf" and ".csv" side by side.
    func exportRightsReport(_ ids: [UUID], title: String) {
        guard !ids.isEmpty else { flash("Nothing to report on"); return }
        let report = catalog.rightsReport(ids, title: title)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = DragOut.safeName(title + " rights report") + ".pdf"
        panel.message = report.docs.isEmpty ? "A CSV with the same rows is saved next to the PDF."
                                            : "A CSV with the same rows and a folder with the \(report.docs.count) license file\(report.docs.count == 1 ? "" : "s") are saved next to the PDF."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let csv = url.deletingPathExtension().appendingPathExtension("csv")
        Task { @MainActor in
            let pages = await self.writeRightsReport(report, pdf: url, csv: csv)
            let folder = self.copyLicenseFiles(report.docs, nextTo: url)
            if pages > 0 {
                self.flash("Saved rights report: \(report.rows.count) assets, \(pages) page\(pages == 1 ? "" : "s") + CSV\(folder != nil ? " + \(report.docs.count) license file\(report.docs.count == 1 ? "" : "s")" : "")")
                NSWorkspace.shared.activateFileViewerSelecting([url, csv] + (folder.map { [$0] } ?? []))
            }
            else { self.flash("Couldn't write the rights report") }
        }
    }

    /// Renders the report as landscape letter pages. Returns the page count, 0 on failure.
    func writeRightsReport(_ report: RightsReport, pdf url: URL, csv: URL?, png: URL? = nil) async -> Int {
        if let csv { try? report.csv.write(to: csv, atomically: true, encoding: .utf8) }
        let per = RightsReportPage.rowsPerPage
        let chunks = stride(from: 0, to: max(report.rows.count, 1), by: per).map { Array(report.rows[$0..<min($0 + per, report.rows.count)]) }
        var box = CGRect(x: 0, y: 0, width: RightsReportPage.size.width, height: RightsReportPage.size.height)
        let info: [CFString: Any] = [kCGPDFContextTitle: report.title + " rights report", kCGPDFContextCreator: "ASSSETS"]
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, info as CFDictionary) else { return 0 }
        for (i, rows) in chunks.enumerated() {
            let page = RightsReportPage(report: report, rows: rows, page: i + 1, pages: chunks.count)
            let r = ImageRenderer(content: page)
            r.proposedSize = ProposedViewSize(RightsReportPage.size)
            r.render { _, draw in ctx.beginPDFPage(nil); draw(ctx); ctx.endPDFPage() }
            if i == 0, let png {
                r.scale = 2
                if let cg = r.cgImage, let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) { try? data.write(to: png, options: .atomic) }
            }
        }
        ctx.closePDF()
        return chunks.count
    }

    /// Once per launch: what expired since ASSSETS was last opened. The first launch only records the day.
    func checkRightsSinceLastLaunch(since override: String? = nil) {
        let key = "rightsLastChecked", today = UsageRights.today()
        let since = override ?? UserDefaults.standard.string(forKey: key)
        UserDefaults.standard.set(today, forKey: key)
        guard let since, since < today else { return }
        let lapsed = catalog.expired(since: since, today: today)
        if !lapsed.isEmpty { rightsNotice = lapsed }
    }

    // MARK: License files and rights presets (1.27)

    var licensesRoot: URL { supportRoot.appendingPathComponent("Licenses", isDirectory: true) }
    func licenseURL(_ d: LicenseDoc) -> URL { licensesRoot.appendingPathComponent(d.stored) }

    func chooseLicenseFiles(for ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let p = NSOpenPanel(); p.allowsMultipleSelection = true; p.canChooseDirectories = false; p.canChooseFiles = true
        p.prompt = "Attach"
        p.message = "Choose the license, order or receipt for \(ids.count == 1 ? "this asset" : "these \(ids.count) assets"). A copy is kept in the library."
        guard p.runModal() == .OK else { return }
        attachLicenseFiles(p.urls, to: ids)
    }

    /// Copies files into the library's Licenses folder and attaches them. The originals stay where they are.
    @discardableResult
    func attachLicenseFiles(_ urls: [URL], to ids: [UUID], quiet: Bool = false) -> [LicenseDoc] {
        let fm = FileManager.default
        try? fm.createDirectory(at: licensesRoot, withIntermediateDirectories: true)
        var docs: [LicenseDoc] = []
        for u in urls where !u.hasDirectoryPath {
            let size = (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let d = LicenseDoc(name: u.lastPathComponent, bytes: size)
            if (try? fm.copyItem(at: u, to: licenseURL(d))) != nil { docs.append(d) }
        }
        guard !docs.isEmpty else { if !quiet { flash("Couldn't copy \(urls.count == 1 ? "that file" : "those files") into the library") }; return [] }
        mutate("Attach License File") { c in for d in docs { c.addLicenseDoc(d, to: ids) } }
        if !quiet {
            flash("Attached \(docs.count == 1 ? docs[0].name : "\(docs.count) license files") to \(ids.count == 1 ? "this asset" : "\(ids.count) assets")")
        }
        return docs
    }

    func attachExistingLicenseDoc(_ id: UUID, to ids: [UUID]) {
        var n = 0
        mutate("Attach License File") { n = $0.attachLicenseDoc(id, to: ids) }
        if n > 0, let d = catalog.licenseDoc(id) { flash("Attached \(d.name) to \(n) more asset\(n == 1 ? "" : "s")") }
    }

    /// Detaches only; the stored copy is deleted on the next launch if nothing uses it, so ⌘Z still works.
    func detachLicenseDoc(_ id: UUID, from ids: [UUID]) {
        var n = 0
        mutate("Remove License File") { n = $0.detachLicenseDoc(id, from: ids) }
        if n > 0 { flash("Removed the license file from \(n == 1 ? "this asset" : "\(n) assets") · ⌘Z to undo") }
    }

    func quickLook(_ d: LicenseDoc) {
        let u = licenseURL(d)
        if FileManager.default.fileExists(atPath: u.path) { quickLookURL = u } else { flash("\(d.name) is missing from the library") }
    }

    func revealLicense(_ d: LicenseDoc) { NSWorkspace.shared.activateFileViewerSelecting([licenseURL(d)]) }

    func pruneLicenseFiles() {
        var gone: [LicenseDoc] = []
        mutate { gone = $0.pruneLicenseDocs() }
        for d in gone { try? FileManager.default.removeItem(at: licenseURL(d)) }
    }

    /// Demo only: an order confirmation PDF, an email receipt and an invoice PDF, all made up for the demo library.
    func makeDemoLicenseFiles() -> [String: URL] {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ASSSETS-demo-licenses", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var out: [String: URL] = [:]
        func pdf(_ name: String, _ page: DemoLicensePage) -> URL? {
            let url = dir.appendingPathComponent(name)
            let r = ImageRenderer(content: page)
            r.proposedSize = ProposedViewSize(width: 612, height: 792)
            var ok = false
            r.render { _, draw in
                var box = CGRect(x: 0, y: 0, width: 612, height: 792)
                guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
                ctx.beginPDFPage(nil); draw(ctx); ctx.endPDFPage(); ctx.closePDF(); ok = true
            }
            return ok ? url : nil
        }
        out["order"] = pdf("NL-20417 order confirmation.pdf", DemoLicensePage(vendor: "Northlight Images", doc: "Order confirmation NL-20417",
            lines: [("Northlight Lobby", "Web, social and print pitch decks", "$240.00"), ("Atrium Cork Wall", "Web and social", "$180.00")],
            terms: "Licensed for the client named on the order. One year from the order date. Credit the photographer as shown."))
        out["harbor"] = pdf("Harbor Stock invoice 88-114.pdf", DemoLicensePage(vendor: "Harbor Stock", doc: "Invoice 88-114",
            lines: [("Harbor Night", "Web only", "$95.00")], terms: "Web use only. License ends on the date shown on the image record."))
        let eml = dir.appendingPathComponent("Northlight receipt.eml")
        let mail = "From: orders@northlight.example\r\nTo: studio@example.com\r\nSubject: Your Northlight receipt NL-20417\r\nDate: Mon, 7 Sep 2026 10:12:00 +0000\r\n\r\nThanks for your order. Receipt for NL-20417: 2 images, $420.00 paid by card.\r\n"
        if (try? mail.write(to: eml, atomically: true, encoding: .utf8)) != nil { out["receipt"] = eml }
        return out
    }

    /// "<report> license files" folder next to a rights report; nil when there is nothing to copy.
    func copyLicenseFiles(_ docs: [LicenseDoc], nextTo report: URL) -> URL? {
        let fm = FileManager.default
        let present = docs.filter { fm.fileExists(atPath: licenseURL($0).path) }
        guard !present.isEmpty else { return nil }
        let parent = report.deletingLastPathComponent()
        let taken = Set((try? fm.contentsOfDirectory(atPath: parent.path)) ?? [])
        let folder = parent.appendingPathComponent(DragOut.uniqueName(report.deletingPathExtension().lastPathComponent + " license files", taken: taken), isDirectory: true)
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        var names = Set<String>()
        for d in present {
            let n = DragOut.uniqueName(DragOut.safeName((d.name as NSString).deletingPathExtension), taken: names)
            names.insert(n)
            let ext = (d.name as NSString).pathExtension
            try? fm.copyItem(at: licenseURL(d), to: folder.appendingPathComponent(ext.isEmpty ? n : n + "." + ext))
        }
        return folder
    }

    /// Opens "Save as Preset" with what the selection shares: every field that matches, files attached to all of them.
    func startPresetDraft(from ids: [UUID]) {
        guard !ids.isEmpty else { return }
        if ids.count == 1 {
            guard let d = catalog.presetDraft(from: ids[0]) else { flash("Add rights to this asset first, then save them as a preset"); return }
            presetDraft = PresetDraft(name: d.name, rights: d.rights, termYears: nil, docs: d.docs, count: 1)
            return
        }
        let c = catalog.commonRights(ids)
        let r = UsageRights(license: c.license.value ?? .licensed, source: c.source.value ?? "", credit: c.credit.value ?? "",
                            uses: c.uses.value ?? "", expires: c.expires.value ?? nil)
        let docs = catalog.licenseDocCoverage(ids).filter { $0.count == ids.count }.map(\.doc.id)
        presetDraft = PresetDraft(name: r.source.isEmpty ? r.license.rawValue : r.source, rights: r, termYears: nil, docs: docs, count: ids.count)
    }

    func savePreset(_ d: PresetDraft) {
        var id: UUID?
        mutate("Save Rights Preset") { id = $0.saveRightsPreset(name: d.name, rights: d.rights, termYears: d.termYears, docs: d.includeFiles ? d.docs : []) }
        presetDraft = nil
        if id != nil { flash("Saved preset \(d.name.trimmingCharacters(in: .whitespaces))") }
    }

    func applyPreset(_ pid: UUID, to ids: [UUID]) {
        guard let p = catalog.rightsPreset(pid), !ids.isEmpty else { return }
        var n = 0
        mutate("Apply \(p.name)") { n = $0.applyRightsPreset(pid, to: ids) }
        if n > 0 { writeMetadata(Set(ids), quiet: true) }
        flash(n == 0 ? "\(p.name) is already on \(ids.count == 1 ? "this asset" : "these assets")" : "Applied \(p.name) to \(n) asset\(n == 1 ? "" : "s") · ⌘Z to undo")
    }

    func deletePreset(_ pid: UUID) {
        let name = catalog.rightsPreset(pid)?.name ?? "preset"
        mutate("Delete Preset") { $0.deleteRightsPreset(pid) }
        flash("Deleted preset \(name) · ⌘Z to undo")
    }

    /// Swaps outdated cards to the newest version in their stack (1.24): all of them, or just `only`.
    func updateToNewest(_ boardID: UUID, only: Set<UUID>? = nil) {
        let saved = ISO8601DateFormatter().string(from: Date()), author = replyAuthor
        var n = 0
        mutate("Update to Newest") { n = $0.updateToNewest(board: boardID, only: only, author: author, saved: saved) }
        flash(n == 0 ? "Everything here is already the newest version" : "Updated \(n) \(n == 1 ? "card" : "cards") to the newest version · the board was saved first in Versions")
    }

    func copyCards() {
        guard let b = currentBoard, let clip = b.copyCards(boardSelection) else { return }
        cardClipboard = clip
        flash("Copied \(clip.items.count) \(clip.items.count == 1 ? "card" : "cards")")
    }

    func pasteCards() {
        guard let id = selectedBoard, let clip = cardClipboard else { return }
        var made: [UUID] = []
        updateBoard(id, "Paste") { made = $0.paste(clip) }
        // Pasting again on the same board steps down and right instead of stacking in one spot.
        if clip.source == id, let g = currentBoard?.grid { cardClipboard = clip.shifted(by: g * 2) }
        boardSelection = Set(made)
    }

    func nudgeCards(dx: Double, dy: Double) {
        guard let id = selectedBoard, !boardSelection.isEmpty else { return }
        let sel = boardSelection
        updateBoard(id, "Nudge") { _ = $0.nudge(sel, dx: dx, dy: dy) }
    }

    func removeFromBoard(_ items: Set<UUID>) {
        guard let id = selectedBoard else { return }
        updateBoard(id, "Remove from Board") { _ = $0.remove(items) }
        boardSelection.subtract(items)
    }

    func dragIDs(_ text: String) -> [UUID] {
        guard text.hasPrefix(Self.dragPrefix) else { return [] }
        return text.dropFirst(Self.dragPrefix.count).split(separator: ",").compactMap { UUID(uuidString: String($0)) }
    }

    func dropSelection(_ providers: [NSItemProvider], onBoard id: UUID, at point: CGPoint?) -> Bool {
        guard let p = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.asssetsSelection.identifier) }) else { return false }
        _ = p.loadDataRepresentation(forTypeIdentifier: UTType.asssetsSelection.identifier) { data, _ in
            guard let data, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                let ids = self.dragIDs(text)
                guard !ids.isEmpty else { return }
                self.addToBoard(id, ids: Set(ids), at: point.map { (x: Double($0.x), y: Double($0.y)) })
            }
        }
        return true
    }

    /// Palette card from an asset on the board, placed beside it.
    func addPaletteCard(for item: BoardItem) {
        guard let id = selectedBoard, let aid = item.assetID, let a = catalog.assets.first(where: { $0.id == aid }) else { return }
        var made: UUID?
        updateBoard(id, "Add Palette Card") { made = $0.addPalette(a.palette, from: aid, at: (x: item.x + item.w + 20, y: item.y)) }
        if let made { boardItem = made } else { flash("No palette for this asset yet") }
    }

    func addNote() {
        guard let id = selectedBoard else { return }
        var made = UUID()
        updateBoard(id, "Add Note") { made = $0.addNote("New note") }
        boardItem = made; editingNote = made
    }

    func searchFromBoard(_ hex: String) {
        show(collection: StudioCatalog.allAssets)
        searchColor(hex)
    }

    // MARK: Export

    /// Draws the board at 2x with real thumbnails (the live canvas loads them lazily, so they are fetched first).
    func renderBoard(_ id: UUID) async -> (ImageRenderer<BoardExportView>, BoardRect)? {
        guard let board = catalog.board(id) else { return nil }
        var images: [UUID: CGImage] = [:]
        for it in board.items where it.kind == .asset {
            guard let aid = it.assetID, let a = catalog.assets.first(where: { $0.id == aid }) else { continue }
            let zoomIn = it.crop.map { 1 / min($0.w, $0.h) } ?? 1
            let px = Int(min(4000, max(it.w, it.h) * 2 * zoomIn))
            let thumb = await MediaRenderer.thumbnail(for: a, maxPixel: px)
            images[aid] = thumb ?? MediaRenderer.generated(a, width: px)
        }
        let assets = Dictionary(uniqueKeysWithValues: catalog.assets.filter { a in board.items.contains { $0.assetID == a.id } }.map { ($0.id, $0) })
        let rect = board.exportRect
        let r = ImageRenderer(content: BoardExportView(board: board, assets: assets, images: images, rect: rect))
        r.scale = 2
        return (r, rect)
    }

    func writeBoard(_ id: UUID, pdf: Bool, to url: URL) async -> CGSize? {
        guard let rendered = await renderBoard(id) else { return nil }
        let (r, rect) = rendered
        if pdf {
            var ok = false
            r.render { size, draw in
                var box = CGRect(origin: .zero, size: size)
                guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
                ctx.beginPDFPage(nil); draw(ctx); ctx.endPDFPage(); ctx.closePDF(); ok = true
            }
            return ok ? CGSize(width: rect.w, height: rect.h) : nil
        }
        guard let cg = r.cgImage, let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]),
              (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        return CGSize(width: cg.width, height: cg.height)
    }

    func exportBoard(_ id: UUID, pdf: Bool, checked: Bool = false) {
        guard let board = catalog.board(id) else { return }
        if !checked { guardRights(board.items.compactMap(\.assetID), action: pdf ? "Export PDF" : "Export PNG") { self.exportBoard(id, pdf: pdf, checked: true) }; return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [pdf ? UTType.pdf : UTType.png]
        panel.nameFieldStringValue = board.name + (pdf ? ".pdf" : ".png")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { @MainActor in
            if await writeBoard(id, pdf: pdf, to: url) != nil { flash("Exported \(url.lastPathComponent)") } else { flash("Couldn't export \(board.name)") }
        }
    }

    /// The lobby board after a client round: two saved versions, a shared gallery and two reviewers' feedback files imported (1.20).
    func makeDemoReviewRound() -> UUID {
        let id = makeDemoBoard()
        let gallery = "demo-review-round"
        let stamp = { (m: Int) in ISO8601DateFormatter().string(from: Date().addingTimeInterval(Double(-m) * 60)) }
        mutate { c in
            _ = c.updateBoard(id) { b in
                b.saveVersion(named: "First pass", saved: stamp(26 * 60))
                b.saveVersion(named: "Sent to client", saved: stamp(95))
            }
            c.noteGalleryShared(gallery, from: id)
        }
        let all = catalog.assets
        func aid(_ f: String) -> String { all.first { $0.importedPath?.hasSuffix(f) == true }?.id.uuidString.lowercased() ?? "" }
        typealias E = ReviewGallery.Feedback.Entry
        let rounds = [
            ReviewGallery.Feedback(gallery: gallery, title: "Lobby Refresh", reviewer: "Mara Quinn", items: [
                E(id: aid("cosmetic-plinth-mockup.png"), favorite: true, note: "This is the lobby. Brass plinth by the entrance."),
                E(id: aid("sandstone-4k.png"), favorite: true, note: ""),
                E(id: aid("device-stage-mockup.png"), favorite: false, note: "Feels too tech for us - drop it?"),
                E(id: aid("paper-grain-4k.png"), favorite: true, note: "")]),
            ReviewGallery.Feedback(gallery: gallery, title: "Lobby Refresh", reviewer: "Theo Park", items: [
                E(id: aid("album-gatefold-mockup.png"), favorite: true, note: "Use this type for the signage."),
                E(id: aid("cosmetic-plinth-mockup.png"), favorite: true, note: "")])]
        let dir = FileManager.default.temporaryDirectory
        let urls: [URL] = rounds.compactMap { f in
            let u = dir.appendingPathComponent("Lobby Refresh feedback - \(f.reviewer).json")
            guard let data = try? JSONEncoder().encode(f), (try? data.write(to: u)) != nil else { return nil }
            return u
        }
        importFeedback(urls)
        // A tweak after the round, so the versions list has something to compare.
        if let b = catalog.board(id), let motion = b.items.first(where: { it in it.kind == .asset && all.first { a in a.id == it.assetID }?.importedPath?.hasSuffix("motion-loop-01.mp4") == true }) {
            updateBoard(id, "Move") { $0.moveGroup([motion.id], dx: 20, dy: 20) }
        }
        return id
    }

    /// The client round with the studio's answers (1.21): statuses on four cards and replies under two comments.
    /// Jordan's feedback on the Lobby Refresh round: one approval that flips Changes, one new change request, a note, a stray asset.
    func demoApprovalFeedback() -> ReviewGallery.Feedback {
        let all = catalog.assets
        func aid(_ f: String) -> String { all.first { $0.importedPath?.hasSuffix(f) == true }?.id.uuidString.lowercased() ?? "" }
        typealias E = ReviewGallery.Feedback.Entry
        return ReviewGallery.Feedback(gallery: "demo-review-round", title: "Lobby Refresh", reviewer: "Jordan Lee", items: [
            E(id: aid("device-stage-mockup.png"), favorite: false, note: "The stone-frame screen works. Approved.", status: "approved"),
            E(id: aid("prismatic-foil-4k.png"), favorite: false, note: "Too loud next to the brass - a softer foil?", status: "changes"),
            E(id: aid("paper-grain-4k.png"), favorite: true, note: "", status: "approved"),
            E(id: aid("cosmetic-plinth-mockup.png"), favorite: true, note: "", status: "approved"),
            E(id: aid("motion-loop-01.mp4"), favorite: true, note: "Could this run on the lobby screen?"),
            E(id: UUID().uuidString.lowercased(), favorite: true, note: "The old logo lockup", status: "approved")])
    }

    func makeDemoApproval() -> (UUID, UUID) {
        let id = makeDemoReviewRound()
        guard let b = catalog.board(id) else { return (id, id) }
        func card(_ f: String) -> UUID? {
            b.items.first { it in it.kind == .asset && catalog.assets.first { $0.id == it.assetID }?.importedPath?.hasSuffix(f) == true }?.id
        }
        let plinth = card("cosmetic-plinth-mockup.png"), stage = card("device-stage-mockup.png"), gatefold = card("album-gatefold-mockup.png"), stone = card("sandstone-4k.png")
        let stamp = { (m: Int) in ISO8601DateFormatter().string(from: Date().addingTimeInterval(Double(-m) * 60)) }
        mutate { c in
            _ = c.updateBoard(id) { b in
                b.setStatus(.approved, for: Set([plinth, gatefold, stone].compactMap { $0 }))
                if let stage {
                    b.setStatus(.changes, for: [stage])
                    b.addReply(to: stage, author: "Ari (studio)", text: "Fair - swapping the screen for the stone-frame version. New mock by Friday.", posted: stamp(40))
                }
                if let plinth { b.addReply(to: plinth, author: "Ari (studio)", text: "Locked in. Brass finish sample goes out Monday.", posted: stamp(32)) }
            }
        }
        return (id, stage ?? id)
    }

    /// Demo board: mockups, textures and a loop with notes and a palette card, laid out by hand.
    func makeDemoBoard() -> UUID {
        let all = catalog.assets
        func find(_ f: String) -> StudioAsset? { all.first { $0.importedPath?.hasSuffix(f) == true } }
        var id = UUID()
        mutate { c in
            id = c.createBoard(named: "Lobby Refresh")
            _ = c.updateBoard(id) { b in
                let place: [(String, Double, Double, Double)] = [
                    ("cosmetic-plinth-mockup.png", 40, 40, 440), ("device-stage-mockup.png", 500, 40, 300),
                    ("album-gatefold-mockup.png", 500, 260, 300), ("sandstone-4k.png", 820, 40, 200),
                    ("prismatic-foil-4k.png", 820, 260, 200), ("paper-grain-4k.png", 40, 360, 200), ("motion-loop-01.mp4", 260, 360, 220)]
                for (f, x, y, w) in place { if let a = find(f) { b.addAsset(a.id, aspect: Moodboard.aspect(resolution: a.resolution), width: w, at: (x: x, y: y)) } }
                b.addNote("Warm stone, brass and soft foil. Keep the lobby calm - no neon.", at: (x: 1040, y: 40))
                if let a = find("sandstone-4k.png") { b.addPalette(a.palette, from: a.id, at: (x: 1040, y: 260)) }
                b.addNote("Signage: gatefold type, cream on stone", at: (x: 500, y: 480))
            }
        }
        return id
    }
}


// MARK: - Canvas editing (1.18)

extension StudioLibrary {
    /// Frames the selection when there is one, otherwise drops an empty section; either way the label is ready to type.
    func addFrame() {
        guard let id = selectedBoard else { return }
        var made: UUID?
        let sel = boardSelection
        updateBoard(id, sel.isEmpty ? "Add Section" : "Put in Section") { b in
            made = sel.isEmpty ? b.addFrame("") : b.frame(around: sel, label: "")
        }
        if let made { boardSelection = [made]; editingNote = made }
    }

    func duplicateBoard(_ id: UUID) {
        var copy: UUID?
        mutate("Duplicate Board") { copy = $0.duplicateBoard(id) }
        if let copy { show(board: copy) }
    }

    /// A board from a collection or smart collection: up to 48 assets in the view's order, flowed into rows.
    func newBoard(named name: String, assets ids: [UUID]) {
        guard !ids.isEmpty else { flash("\(name) is empty"); return }
        let pick = Array(ids.prefix(48))
        var id = UUID()
        mutate("New Board") { c in id = c.createBoard(named: name); _ = c.addToBoard(id, assets: pick) }
        show(board: id)
        if ids.count > pick.count { flash("Added the first \(pick.count) of \(ids.count) assets") }
    }

    /// Demo: the lobby board arranged in two sections, two loose cards selected and caught mid-drag on a guide.
    func makeDemoSections() -> UUID {
        // Resolved up front: the board closure is nonisolated and can't call back into main-actor helpers.
        let files = ["cosmetic-plinth-mockup.png", "device-stage-mockup.png", "album-gatefold-mockup.png",
                     "sandstone-4k.png", "prismatic-foil-4k.png", "paper-grain-4k.png", "motion-loop-01.mp4"]
        var found: [String: StudioAsset] = [:]
        for f in files { found[f] = catalog.assets.first { $0.importedPath?.hasSuffix(f) == true } }
        let byFile = found
        var id = UUID()
        var loose: Set<UUID> = []
        mutate { c in
            id = c.createBoard(named: "Lobby Sections")
            _ = c.updateBoard(id) { b in
                func put(_ f: String, _ x: Double, _ y: Double, _ w: Double) -> UUID? {
                    guard let a = byFile[f] else { return nil }
                    return b.addAsset(a.id, aspect: Moodboard.aspect(resolution: a.resolution), width: w, at: (x: x, y: y))
                }
                let mock = [put("cosmetic-plinth-mockup.png", 60, 100, 360), put("device-stage-mockup.png", 440, 100, 260), put("album-gatefold-mockup.png", 440, 300, 260)].compactMap { $0 }
                var mats = [put("sandstone-4k.png", 800, 100, 180), put("prismatic-foil-4k.png", 1000, 100, 180), put("paper-grain-4k.png", 800, 300, 180)].compactMap { $0 }
                if let a = byFile["sandstone-4k.png"], let p = b.addPalette(a.palette, from: a.id, at: (x: 1000, y: 300)) { b.resize(p, w: 180, h: 180); mats.append(p) }
                b.frame(around: Set(mock), label: "Mockups")
                b.frame(around: Set(mats), label: "Materials")
                if let clip = put("motion-loop-01.mp4", 300, 580, 220) { loose.insert(clip) }
                loose.insert(b.addNote("Warm stone, brass and soft foil. Keep the lobby calm - no neon.", at: (x: 540, y: 580)))
            }
            // Two more boards so the sidebar shows Duplicate and New Board from Collection at work.
            _ = c.duplicateBoard(id)
            let tex = c.assets.filter { $0.collection == "Material Textures" }.prefix(12).map(\.id)
            let t = c.createBoard(named: "Material Textures"); _ = c.addToBoard(t, assets: Array(tex))
        }
        boardSelection = loose
        // Dragged left until the clip's edge meets the Mockups section's left edge.
        demoDrag = (loose, -236, 0)
        return id
    }
}

// MARK: - Board annotation (1.19)

extension StudioLibrary {
    func addHeading() {
        guard let id = selectedBoard else { return }
        var made = UUID()
        updateBoard(id, "Add Heading") { made = $0.addHeading("") }
        boardItem = made; editingNote = made
    }

    /// Two selected cards: an arrow in reading order (left to right, then down). Reverse it from the arrow's menu.
    func connectSelection() {
        guard let b = currentBoard, boardSelection.count == 2 else { return }
        let pair = b.readingOrder.filter { boardSelection.contains($0.id) }.map(\.id)
        guard pair.count == 2 else { return }
        connect(pair[0], to: pair[1])
    }

    func connect(_ a: UUID, to b: UUID) {
        guard let id = selectedBoard else { return }
        var made: UUID?
        updateBoard(id, "Add Arrow") { made = $0.connect(a, b) }
        if made == nil { flash("Those two are already joined") }
    }

    func beginCrop(_ item: BoardItem) {
        guard let id = selectedBoard, let b = catalog.board(id), let natural = b.naturalAspect(item.id),
              let aid = item.assetID, let a = catalog.assets.first(where: { $0.id == aid }) else { return }
        cropping = CropState(board: id, item: item.id, asset: a, natural: natural, crop: item.crop ?? BoardRect(x: 0, y: 0, w: 1, h: 1))
    }

    func applyCrop(_ st: CropState) {
        let crop = st.crop, item = st.item
        updateBoard(st.board, "Crop") { $0.setCrop(item, crop) }
        cropping = nil
    }

    /// Demo: headings, cropped cards and labeled arrows; returns the board, the card to select and the plinth card.
    func makeDemoAnnotated() -> (UUID, UUID, UUID) {
        let files = ["cosmetic-plinth-mockup.png", "device-stage-mockup.png", "album-gatefold-mockup.png", "sandstone-4k.png", "prismatic-foil-4k.png"]
        var found: [String: StudioAsset] = [:]
        for f in files { found[f] = catalog.assets.first { $0.importedPath?.hasSuffix(f) == true } }
        let byFile = found
        var id = UUID(), picked = UUID(), plinth = UUID(), note = UUID()
        mutate { c in
            id = c.createBoard(named: "Lobby Direction A")
            _ = c.updateBoard(id) { b in
                b.snap = false
                func put(_ f: String, _ x: Double, _ y: Double, _ w: Double, crop aspect: Double?) -> UUID? {
                    guard let a = byFile[f] else { return nil }
                    let natural = Moodboard.aspect(resolution: a.resolution)
                    let card = b.addAsset(a.id, aspect: natural, width: w, at: (x: x, y: y))
                    if let aspect { b.setCrop(card, Moodboard.centeredCrop(aspect: aspect, natural: natural)) }
                    return card
                }
                b.addHeading("Lobby refresh - direction A", at: (x: 60, y: 36))
                if let i = b.items.indices.last { b.items[i].w = 820; b.items[i].h = 64 }
                let p = put("cosmetic-plinth-mockup.png", 60, 150, 300, crop: 0.8)
                let d = put("device-stage-mockup.png", 470, 150, 340, crop: 16.0 / 9)
                let s = put("sandstone-4k.png", 920, 150, 200, crop: 0.75)
                let g = put("album-gatefold-mockup.png", 920, 470, 200, crop: 1)
                b.addHeading("Finishes", at: (x: 920, y: 104))
                if let i = b.items.indices.last { b.items[i].w = 220; b.items[i].h = 36 }
                note = b.addNote("Screens sit in warm stone frames. Keep the glow low.", at: (x: 470, y: 470))
                if let p, let d { b.connect(p, d, label: "screen art") }
                if let d, let s { b.connect(d, s, label: "frame finish") }
                if let s, let g { b.connect(s, g) }
                if let p { plinth = p }
                if let d { picked = d }
            }
        }
        // The device card's arrow handle caught mid-drag over the note.
        if let b = catalog.board(id), let n = b.items.first(where: { $0.id == note }) { demoLink = (picked, n.x + n.w * 0.55, n.y + n.h * 0.45) }
        return (id, picked, plinth)
    }
}

// MARK: - Present and share boards (1.17)

extension StudioLibrary {
    func startPresenting(_ id: UUID) {
        guard let b = catalog.board(id), !b.items.isEmpty else { flash("Add something to the board first"); return }
        editingNote = nil; viewerID = nil
        presentIndex = -1
        presenting = id
        // Real full screen when the user starts it; demos stay in the window so CI can capture them.
        if !isDemo, let w = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }), !w.styleMask.contains(.fullScreen) {
            presentEnteredFullScreen = true
            w.toggleFullScreen(nil)
        }
    }

    func stopPresenting() {
        presenting = nil
        if presentEnteredFullScreen {
            presentEnteredFullScreen = false
            if let w = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }), w.styleMask.contains(.fullScreen) { w.toggleFullScreen(nil) }
        }
    }

    func stepPresent(_ d: Int) {
        guard let b = presenting.flatMap({ catalog.board($0) }) else { return }
        presentIndex = max(-1, min(b.items.count - 1, presentIndex + d))
    }

    /// Review gallery of the board's assets (reading order) with the rendered board on top.
    func shareBoardGallery(_ id: UUID, to fixedDir: URL? = nil, summaryPDF: URL? = nil, checked: Bool = false) {
        guard let board = catalog.board(id) else { return }
        var seen = Set<UUID>()
        let ids = board.readingOrder.compactMap { $0.kind == .asset ? $0.assetID : nil }.filter { seen.insert($0).inserted }
        guard !ids.isEmpty else { flash("Add assets to the board first"); return }
        Task { @MainActor in
            guard let rendered = await self.renderBoard(id), let cg = rendered.0.cgImage,
                  let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { self.flash("Couldn't render \(board.name)"); return }
            self.exportGallery(ids, title: board.name, to: fixedDir, board: (png, cg.width, cg.height, board), summaryPDF: summaryPDF, checked: checked)
        }
    }
}

/// Drag to resize the inspector; double-click restores the default width.
struct InspectorResizeHandle: View {
    @Binding var width: Double
    @State private var start: Double?
    @State private var hovering = false
    var body: some View {
        Rectangle().fill(hovering || start != nil ? Theme.accent.opacity(0.5) : Theme.hairline).frame(width: hovering || start != nil ? 3 : 1)
            .padding(.horizontal, 3).contentShape(Rectangle())
            .onHover { h in hovering = h; if h { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
            .gesture(DragGesture(minimumDistance: 1)
                .onChanged { v in
                    let base = start ?? width
                    if start == nil { start = width }
                    width = min(420, max(290, base - Double(v.translation.width)))
                }
                .onEnded { _ in start = nil })
            .onTapGesture(count: 2) { width = 316 }
            .help("Drag to resize the inspector")
    }
}

/// Full-window board presentation: the whole board, then card by card in reading order.
struct PresentView: View {
    @EnvironmentObject var model: StudioLibrary
    let board: Moodboard

    var body: some View {
        let order = board.readingOrder
        let idx = model.presentIndex
        let focus: BoardItem? = idx >= 0 && idx < order.count ? order[idx] : nil
        let bounds = board.bounds ?? BoardRect(x: 0, y: 0, w: 800, h: 600)
        let canvasW = bounds.maxX + Moodboard.margin, canvasH = bounds.maxY + Moodboard.margin
        GeometryReader { geo in
            let f = Moodboard.fit(focus?.rect ?? bounds, width: Double(geo.size.width), height: Double(geo.size.height) - 64,
                                  margin: focus == nil ? 48 : 72, maxScale: focus == nil ? 1.5 : 3)
            ZStack(alignment: .topLeading) {
                Color(red: 0.02, green: 0.022, blue: 0.035)
                ZStack(alignment: .topLeading) {
                    ForEach(board.layered) { item in
                        BoardItemView(item: item, asset: item.assetID.flatMap { id in model.catalog.assets.first { $0.id == id } },
                                      selected: false, editing: false, detail: focus == nil ? 2 : 4)
                            .frame(width: item.w, height: item.h)
                            .opacity(focus == nil || focus?.id == item.id ? 1 : 0.18)
                            .offset(x: item.x, y: item.y)
                            .onTapGesture {
                                if let i = order.firstIndex(where: { $0.id == item.id }) { model.presentIndex = model.presentIndex == i ? -1 : i }
                            }
                    }
                    BoardArrows(connectors: board.connectors, rects: board.rects, showLabels: true)
                        .opacity(focus == nil ? 1 : 0.18).allowsHitTesting(false)
                }
                .frame(width: canvasW, height: canvasH, alignment: .topLeading)
                .scaleEffect(CGFloat(f.scale), anchor: .topLeading)
                .offset(x: f.x, y: f.y)
                .animation(.spring(response: 0.5, dampingFraction: 0.86), value: idx)
                // Pin the oversized board to the view's corner; without this the ZStack centers it and the fit drifts left.
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .overlay(alignment: .bottom) { caption(order: order, idx: idx, focus: focus).padding(.bottom, 18) }
            .overlay(alignment: .topTrailing) {
                Button { model.stopPresenting() } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.1), in: Circle())
                }.buttonStyle(.plain).foregroundStyle(.white).padding(18).help("Stop presenting (Esc)")
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private func label(_ item: BoardItem) -> String {
        switch item.kind {
        case .asset: return item.assetID.flatMap { id in model.catalog.assets.first { $0.id == id }?.title } ?? "Asset"
        case .note: return item.text.split(separator: "\n").first.map(String.init) ?? "Note"
        case .palette: return "Palette · " + item.colors.joined(separator: " ")
        case .frame: return "Section · " + (item.text.isEmpty ? "Untitled" : item.text)
        case .heading: return item.text.isEmpty ? "Heading" : item.text
        }
    }

    private func caption(order: [BoardItem], idx: Int, focus: BoardItem?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.3.group").foregroundStyle(Theme.accent)
            Text(board.name).font(.system(size: 13, weight: .bold))
            Text(focus == nil ? "Whole board" : "\(idx + 1) of \(order.count)").font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary)
            if let focus { Text(label(focus)).font(.system(size: 12.5, weight: .medium)).lineLimit(1).frame(maxWidth: 360, alignment: .leading) }
            Divider().frame(height: 14)
            HStack(spacing: 6) {
                Button { model.stepPresent(-1) } label: { Image(systemName: "chevron.left") }.disabled(idx < 0)
                Button { model.stepPresent(1) } label: { Image(systemName: "chevron.right") }.disabled(idx >= order.count - 1)
            }.buttonStyle(.borderless)
            Text("← → step · 0 whole board · Esc exit").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
        .background(.ultraThinMaterial, in: Capsule()).overlay(Capsule().stroke(Theme.hairline))
    }
}

// MARK: - Board canvas

struct BoardCanvas: View {
    @EnvironmentObject var model: StudioLibrary
    let board: Moodboard
    /// The drag in flight: what was grabbed, what moves with it (frame contents) and where guides put it.
    @State private var drag: (ids: Set<UUID>, moving: Set<UUID>, guides: BoardGuides)?
    @State private var sizing: (id: UUID, dw: Double, dh: Double)?
    @State private var marquee: BoardRect?
    @State private var marqueeBase: Set<UUID> = []
    /// An arrow being dragged out of a card's handle: source card and the pointer in board space.
    @State private var linking: (from: UUID, x: Double, y: Double)?
    @State private var viewport: CGSize = .zero
    @State private var dropTargeted = false
    /// Off after a manual zoom; while on, the board refits when the view changes size (inspector, window).
    @State private var autoFit = true
    /// Gestures measure in board points here, before the zoom is applied.
    static let space = "board-canvas"

    private var z: Double { model.boardZoom }
    private var canvas: CGSize {
        let b = board.bounds
        // At low zoom the canvas still reaches the edges of the view, so the dot grid never stops short.
        let z = max(0.25, model.boardZoom)
        return CGSize(width: max(1600.0, (b?.maxX ?? 0) + 400, Double(viewport.width) / z),
                      height: max(1100.0, (b?.maxY ?? 0) + 400, Double(viewport.height) / z))
    }
    private var zf: CGFloat { CGFloat(model.boardZoom) }
    private static let guideColor = Color(red: 1.0, green: 0.36, blue: 0.62)

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.hairline)
            GeometryReader { geo in
                ScrollView([.horizontal, .vertical]) {
                    ZStack(alignment: .topLeading) {
                        BoardGrid(step: board.grid, zoom: model.boardZoom).frame(width: canvas.width, height: canvas.height)
                            .contentShape(Rectangle())
                            .gesture(marqueeGesture)
                            .onTapGesture { model.boardSelection = []; model.editingNote = nil }
                        ForEach(board.layered) { item in card(item) }
                        connectorLayer
                        pinLayer
                        versionLayer
                        linkLine
                        guideLines
                        if let m = marquee {
                            Rectangle().fill(Theme.accent.opacity(0.08))
                                .overlay(Rectangle().stroke(Theme.accent.opacity(0.85), lineWidth: 1 / max(0.1, z)))
                                .frame(width: m.w, height: m.h).offset(x: m.x, y: m.y).allowsHitTesting(false)
                        }
                        if board.items.isEmpty { emptyHint }
                    }
                    .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
                    .coordinateSpace(name: Self.space)
                    .scaleEffect(zf, anchor: .topLeading)
                    .frame(width: canvas.width * zf, height: canvas.height * zf, alignment: .topLeading)
                    // Pinned top-left; a board smaller than the view used to float in the middle.
                    .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .topLeading)
                    .onDrop(of: [UTType.asssetsSelection], isTargeted: $dropTargeted) { providers, loc in
                        model.dropSelection(providers, onBoard: board.id, at: CGPoint(x: loc.x / zf, y: loc.y / zf))
                    }
                }
                .background(Theme.ink)
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(dropTargeted ? Theme.accent : .clear, lineWidth: 2))
                .onAppear {
                    viewport = geo.size; fit()
                    if let d = model.demoDrag {
                        drag = (d.0, board.movingSet(d.0), board.guides(moving: d.0, dx: d.1, dy: d.2, threshold: 6 / max(0.1, z)))
                    }
                    if let l = model.demoLink, board.items.contains(where: { $0.id == l.0 }) { linking = (l.0, l.1, l.2) }
                }
                .onChange(of: geo.size) { _, s in viewport = s; if autoFit { fit() } }
                .onChange(of: model.fitBoardRequest) { _, _ in autoFit = true; fit() }
            }
        }
        .background(Theme.backdrop)
    }

    /// Drag on empty canvas: select what the rectangle touches (shift adds to the selection).
    private var marqueeGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.space))
            .onChanged { v in
                if marquee == nil {
                    marqueeBase = NSEvent.modifierFlags.contains(.shift) ? model.boardSelection : []
                    model.editingNote = nil
                }
                let r = BoardRect.spanning((x: Double(v.startLocation.x), y: Double(v.startLocation.y)), (x: Double(v.location.x), y: Double(v.location.y)))
                marquee = r
                model.boardSelection = marqueeBase.union(board.items(in: r))
            }
            .onEnded { _ in marquee = nil; syncInspector() }
    }

    /// Arrows use the same live rects as the cards, so they follow a drag or resize as it happens.
    private var liveRects: [UUID: BoardRect] {
        Dictionary(board.items.map { ($0.id, itemRect($0)) }, uniquingKeysWith: { a, _ in a })
    }

    @ViewBuilder private var connectorLayer: some View {
        let rects = liveRects
        BoardArrows(connectors: board.connectors, rects: rects, highlight: model.boardSelection, lineScale: 1 / max(0.1, z))
            .allowsHitTesting(false)
        ForEach(board.connectors) { c in connectorKnob(c, rects: rects) }
    }

    /// The arrow's middle: its label, or a small dot to grab. Double-click to label; right-click to reverse or delete.
    @ViewBuilder private func connectorKnob(_ c: BoardConnector, rects: [UUID: BoardRect]) -> some View {
        if let a = rects[c.from], let b = rects[c.to], let l = Moodboard.connectorLine(from: a, to: b) {
            let boardID = board.id
            ArrowLabel(text: c.label, editing: model.editingConnector == c.id,
                       hot: model.boardSelection.contains(c.from) || model.boardSelection.contains(c.to)) { text in
                if text != c.label { model.updateBoard(boardID, "Label Arrow") { $0.setConnectorLabel(c.id, text) } }
                model.editingConnector = nil
            }
            .fixedSize()
            .position(x: spot(l, c).x, y: spot(l, c).y)
            .onTapGesture(count: 2) { model.editingConnector = c.id }
            .contextMenu {
                Button(c.label.isEmpty ? "Add Label" : "Edit Label") { model.editingConnector = c.id }
                Button("Reverse Arrow") { model.updateBoard(boardID, "Reverse Arrow") { $0.reverseConnector(c.id) } }
                Divider()
                Button("Delete Arrow", role: .destructive) { model.updateBoard(boardID, "Delete Arrow") { $0.disconnect(c.id) } }
            }
            .help(c.label.isEmpty ? "Double-click to label this arrow" : c.label)
        }
    }

    private func spot(_ l: (x1: Double, y1: Double, x2: Double, y2: Double), _ c: BoardConnector) -> (x: Double, y: Double) {
        if model.editingConnector == c.id { return (x: (l.x1 + l.x2) / 2, y: (l.y1 + l.y2) / 2) }
        return Moodboard.labelSpot(l, labelWidth: ArrowLabel.width(c.label))
    }

    /// The arrow being dragged out of a card, and the card it would land on.
    @ViewBuilder private var linkLine: some View {
        if let l = linking, let src = board.items.first(where: { $0.id == l.from }) {
            let s = Moodboard.edgePoint(of: itemRect(src), toward: (x: l.x, y: l.y), gap: 6)
            let t = 1 / max(0.1, z)
            if let target = board.item(at: l.x, l.y, excluding: l.from), let it = board.items.first(where: { $0.id == target }) {
                let r = itemRect(it)
                RoundedRectangle(cornerRadius: 13).stroke(Theme.accent, lineWidth: 3 * t)
                    .frame(width: r.w + 10, height: r.h + 10).offset(x: r.x - 5, y: r.y - 5).allowsHitTesting(false)
            }
            ArrowLine(x1: s.x, y1: s.y, x2: l.x, y2: l.y, head: 12 * max(1, t))
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2 * max(1, t), lineCap: .round, dash: [7, 5]))
                .allowsHitTesting(false)
            ArrowHead(x1: s.x, y1: s.y, x2: l.x, y2: l.y, head: 12 * max(1, t)).fill(Theme.accent).allowsHitTesting(false)
        }
    }

    /// Drag from here to another card to draw an arrow.
    private func linkHandle(_ item: BoardItem) -> some View {
        Image(systemName: "arrow.right").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
            .frame(width: 18, height: 18).background(Theme.accent, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 1.5))
            .offset(x: 26)
            .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.space))
                .onChanged { v in linking = (item.id, Double(v.location.x), Double(v.location.y)) }
                .onEnded { v in
                    linking = nil
                    if let t = board.item(at: Double(v.location.x), Double(v.location.y), excluding: item.id) { model.connect(item.id, to: t) }
                })
            .help("Drag to another card to draw an arrow")
    }

    @ViewBuilder private var guideLines: some View {
        if let g = drag?.guides {
            let t = 1 / max(0.1, z)
            ForEach(g.vertical, id: \.self) { x in
                Rectangle().fill(Self.guideColor).frame(width: t, height: canvas.height).offset(x: x - t / 2).allowsHitTesting(false)
            }
            ForEach(g.horizontal, id: \.self) { y in
                Rectangle().fill(Self.guideColor).frame(width: canvas.width, height: t).offset(y: y - t / 2).allowsHitTesting(false)
            }
        }
    }

    private func fit() {
        guard let b = board.bounds, viewport.width > 50 else { model.boardZoom = 1; return }
        let zx = (Double(viewport.width) - 24) / (b.maxX + Moodboard.margin), zy = (Double(viewport.height) - 24) / (b.maxY + Moodboard.margin)
        model.boardZoom = max(0.25, min(1, min(zx, zy)))
    }

    /// Full header when there's room; otherwise tighter spacing, no zoom steppers and an icon-only Export,
    /// so the board name keeps its space next to the inspector (1.17 fix).
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            headerRow(compact: false)
            headerRow(compact: true)
        }
        .buttonStyle(.borderless)
        // On the header, not the button: ViewThatFits builds both rows, and one popover must own the flag.
        .popover(isPresented: $model.boardVersionsOpen, attachmentAnchor: .point(UnitPoint(x: 0.8, y: 1)), arrowEdge: .top) {
            BoardVersionsPanel(board: board).environmentObject(model)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel)
    }

    private var subtitle: String {
        let n = "\(board.items.count) item\(board.items.count == 1 ? "" : "s")"
        let approved = board.statusCounts[.approved] ?? 0
        let empty = board.emptySlots.count
        let newer = model.catalog.outdatedCards(on: board.id).count
        let tail = (approved > 0 ? " · \(approved) approved" : "") + (empty > 0 ? " · \(empty) empty slot\(empty == 1 ? "" : "s")" : "")
            + (newer > 0 ? " · \(newer) newer version\(newer == 1 ? "" : "s")" : "")
        guard !board.reviews.isEmpty else { return n + tail }
        let picked = pins.values.filter(\.picked).count
        return n + " · \(picked) picked by " + (model.boardReviewer ?? (board.reviewers.count == 1 ? board.reviewers[0] : "\(board.reviewers.count) reviewers")) + tail
    }

    private var pins: [UUID: BoardPin] { board.pins(reviewer: model.boardReviewer) }

    private func dimmed(_ item: BoardItem) -> Bool {
        if item.kind == .frame || item.kind == .heading { return false }
        if let f = model.boardStatusFilter, item.kind != .asset || board.status(of: item.id) != f { return true }
        guard model.boardClientOnly, !board.reviews.isEmpty else { return false }
        return pins[item.id]?.picked != true
    }

    /// Chips on the card's top-left corner: "Final available" on cards showing an older version (1.24, click to update)
    /// and a red rights chip on cards whose asset is expired or editorial-only (1.25, click to open the asset).
    @ViewBuilder private var versionLayer: some View {
        let outdated = model.catalog.outdatedCards(on: board.id)
        let rights = model.catalog.rightsProblems(on: board.id)
        let threaded = board.threadedCards()
        if !outdated.isEmpty || !rights.isEmpty {
            let t = min(2.2, 1 / max(0.1, z))
            ForEach(board.layered.filter { (outdated[$0.id] != nil || rights[$0.id] != nil) && !dimmed($0) }) { item in
                let r = itemRect(item)
                let label = outdated[item.id].map { VersionStacks.rank($0).1 }
                let longest = max(label.map { $0.count + 10 } ?? 0, rights[item.id].map { $0.label.count } ?? 0)
                // Within the left half when the card has a thread badge on the right; otherwise most of the width.
                let room = r.w * (threaded.contains(item.id) ? 0.5 : 0.85) - 8
                let bt = min(t, max(0.45, room / (Double(longest) * 6.6 + 34)))
                VStack(alignment: .leading, spacing: 5) {
                    if let label {
                        Button { model.updateToNewest(board.id, only: [item.id]) } label: {
                            chip("arrow.up.circle.fill", "\(label) available", Theme.warning, Color.black.opacity(0.85))
                        }
                        .buttonStyle(.plain).help("Update this card to \(label)")
                    }
                    if let st = rights[item.id] {
                        Button { if let a = item.assetID { model.selection = [a]; model.focusID = a; model.showInspector = true } } label: {
                            chip(st == .editorial ? "newspaper.fill" : "exclamationmark.octagon.fill", st.label, Theme.danger, .white)
                        }
                        .buttonStyle(.plain).help("Check the license before this goes to a client")
                    }
                }
                .fixedSize()
                .scaleEffect(CGFloat(bt), anchor: .topLeading)
                .frame(width: max(1, r.w - 16), alignment: .topLeading)
                .offset(x: r.x + 8, y: r.y + 8)
            }
        }
    }

    private func chip(_ symbol: String, _ text: String, _ bg: Color, _ fg: Color) -> some View {
        HStack(spacing: 4) { Image(systemName: symbol); Text(text) }
            .font(.system(size: 11, weight: .bold)).foregroundStyle(fg)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(bg, in: Capsule())
            .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
    }

    /// Client picks and comments from imported feedback (1.20), plus status and replies (1.21), drawn on the cards they belong to.
    /// Clicking the badge opens the card's thread.
    @ViewBuilder private var pinLayer: some View {
        let all = pins
        let threaded = board.threadedCards().union(model.threadCard.map { [$0] } ?? [])
        if !threaded.isEmpty {
            let t = min(2.2, 1 / max(0.1, z))
            ForEach(board.layered.filter { threaded.contains($0.id) }) { item in
                let r = itemRect(item), pin = all[item.id]
                let hidden = dimmed(item)
                let replies = board.replies(for: item.id)
                let badge = CardThreadBadge(pin: hidden ? nil : pin, status: board.status(of: item.id), replies: hidden ? 0 : replies.count)
                // Never wider than the card, so badges on neighbouring cards can't overlap (1.21 fix).
                let bt = min(t, max(0.5, (r.w - 16) / badge.estimatedWidth))
                badge
                    .opacity(hidden ? 0.35 : 1)
                    .onTapGesture { model.threadCard = item.id }
                    .popover(isPresented: Binding(get: { model.threadCard == item.id }, set: { if !$0 && model.threadCard == item.id { model.threadCard = nil } }),
                             arrowEdge: .trailing) {
                        CardThreadPanel(boardID: board.id, itemID: item.id).environmentObject(model)
                    }
                    .scaleEffect(CGFloat(bt), anchor: .topTrailing)
                    .frame(width: r.w - 8, alignment: .topTrailing)
                    .offset(x: r.x, y: r.y + 8)
                if !hidden, model.boardShowComments, let pin, !pin.comments.isEmpty {
                    let scale = min(t, max(1, (r.w - 16) / 220))
                    ClientCommentCallout(comments: pin.comments, width: max(120, (r.w - 16) / scale), replies: replies.count)
                        .scaleEffect(CGFloat(scale), anchor: .bottomLeading)
                        .frame(width: r.w - 16, height: r.h - 16, alignment: .bottomLeading)
                        .offset(x: r.x + 8, y: r.y + 8)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private func reviewMenu(compact: Bool) -> some View {
        Menu {
            Button("Import Client Feedback…") { model.importFeedback() }
            Button("Share as Review Gallery…") { model.shareBoardGallery(board.id) }
            Button(board.versions.isEmpty ? "Versions…" : "Versions (\(board.versions.count))…") { model.boardVersionsOpen = true }
            Button("Export Round Summary PDF…") { model.exportRoundSummary(board.id) }
            Toggle("Include Credits Page", isOn: $model.includeCredits)
            Toggle("Include License Files in Galleries", isOn: $model.includeLicenseFiles).disabled(!model.includeCredits)
            Button("Rights Report (PDF + CSV)…") { model.exportRightsReport(board.items.compactMap(\.assetID), title: board.name) }
            let newer = model.catalog.outdatedCards(on: board.id).count
            if newer > 0 { Button("Update All to Newest (\(newer))") { model.updateToNewest(board.id) } }
            Button("Share Round (Gallery + Summary)…") { model.shareRound(board.id) }
            Divider()
            Picker("Status", selection: $model.boardStatusFilter) {
                Text("All Cards").tag(CardStatus?.none)
                ForEach(CardStatus.allCases, id: \.self) { st in Text("\(st.label) (\(board.statusCounts[st] ?? 0))").tag(CardStatus?.some(st)) }
            }
            if !board.reviews.isEmpty {
                Divider()
                Toggle("Picked by Client Only", isOn: $model.boardClientOnly)
                Toggle("Show Comments", isOn: $model.boardShowComments)
                Picker("Reviewer", selection: $model.boardReviewer) {
                    Text("All Reviewers").tag(String?.none)
                    ForEach(board.reviewers, id: \.self) { r in Text(r).tag(String?.some(r)) }
                }
                Divider()
                Button("Clear Client Rounds", role: .destructive) {
                    model.updateBoard(board.id, "Clear Client Rounds") { $0.reviews = [] }
                    model.boardClientOnly = false; model.boardReviewer = nil
                }
            }
        } label: {
            if let f = model.boardStatusFilter {
                Label(f.label, systemImage: CardThreadBadge.symbol(f)).foregroundStyle(CardThreadBadge.color(f))
            } else if model.boardClientOnly {
                Label(compact ? "Picked" : "Picked by Client", systemImage: "heart.fill").foregroundStyle(ClientPinBadge.pink)
            } else {
                Image(systemName: board.reviews.isEmpty ? "person.2" : "person.2.fill")
            }
        }
        .menuIndicator(compact ? .hidden : .visible)
        .fixedSize().help(board.reviews.isEmpty ? "Client review: share a gallery, import the feedback" : "Client picks and comments on this board")
    }

    private var versionsButton: some View {
        Button { model.boardVersionsOpen.toggle() } label: {
            HStack(spacing: 3) {
                Image(systemName: "clock.arrow.circlepath")
                if !board.versions.isEmpty { Text("\(board.versions.count)").font(.caption2.monospacedDigit()) }
            }
        }
        .help("Board versions")
    }

    private func headerRow(compact: Bool) -> some View {
        HStack(spacing: compact ? 7 : 10) {
            Image(systemName: "rectangle.3.group").foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(board.name).font(.system(size: 15, weight: .bold)).lineLimit(1)
                Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            .fixedSize(horizontal: !compact, vertical: false)
            .layoutPriority(1)
            Spacer(minLength: compact ? 4 : 8)
            Button { model.addNote() } label: { Image(systemName: "note.text.badge.plus") }.help("Add a note")
            Button { model.addHeading() } label: { Image(systemName: "textformat.size") }.help("Add a heading")
            Button { model.addFrame() } label: { Image(systemName: "rectangle.dashed") }.help(model.boardSelection.isEmpty ? "Add a section" : "Put the selection in a section")
            ArrangeMenu(board: board, selection: model.boardSelection)
            Toggle(isOn: Binding(get: { board.snap }, set: { v in model.updateBoard(board.id, v ? "Snap On" : "Snap Off") { $0.snap = v } })) { Image(systemName: "grid") }
                .toggleStyle(.button).help("Snap to grid")
            HStack(spacing: 4) {
                if !compact { Button { autoFit = false; model.boardZoom = max(0.25, z / 1.25) } label: { Image(systemName: "minus.magnifyingglass") } }
                Button { autoFit = true; fit() } label: { Text("\(Int((z * 100).rounded()))%").font(.caption.monospacedDigit()).frame(minWidth: 34) }.help("Fit the board")
                if !compact { Button { autoFit = false; model.boardZoom = min(2, z * 1.25) } label: { Image(systemName: "plus.magnifyingglass") } }
            }
            reviewMenu(compact: compact)
            // Next to the inspector the versions button folds into the people menu, so the board name keeps its room (1.20 fix).
            if !compact { versionsButton }
            Button { model.startPresenting(board.id) } label: { Image(systemName: "play.fill").foregroundStyle(Theme.accent) }.help("Present the board full screen")
            Menu {
                Button("PNG…") { model.exportBoard(board.id, pdf: false) }
                Button("PDF…") { model.exportBoard(board.id, pdf: true) }
                Divider()
                Button("Share as Review Gallery…") { model.shareBoardGallery(board.id) }
                Button("Share Round (Gallery + Summary)…") { model.shareRound(board.id) }
                Divider()
                Button("Save as Template…") { model.savingTemplate = board.id }
            } label: {
                if compact { Image(systemName: "square.and.arrow.up") } else { Label("Export", systemImage: "square.and.arrow.up") }
            }.menuIndicator(compact ? .hidden : .visible).fixedSize().help("Export the board")
        }
    }

    private var emptyHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "rectangle.3.group").font(.system(size: 34)).foregroundStyle(.tertiary)
            Text("Drop assets here").font(.headline)
            Text("Drag from the grid onto this board in the sidebar, or use Add to Board in any asset's menu.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(width: 360).offset(x: 80, y: 80)
    }

    private func itemRect(_ item: BoardItem) -> BoardRect {
        var r = item.rect
        if let d = drag, d.moving.contains(item.id) { r.x += d.guides.dx; r.y += d.guides.dy }
        if let s = sizing, s.id == item.id {
            r.w = max(Moodboard.minSize, r.w + s.dw)
            r.h = item.kind == .asset ? r.w * item.h / max(1, item.w) : max(Moodboard.minSize, r.h + s.dh)
        }
        return r
    }

    @ViewBuilder private func card(_ item: BoardItem) -> some View {
        let r = itemRect(item)
        let selected = model.boardSelection.contains(item.id)
        BoardItemView(item: item, asset: item.assetID.flatMap { id in model.catalog.assets.first { $0.id == id } }, selected: selected, editing: model.editingNote == item.id)
            .frame(width: r.w, height: r.h)
            .opacity(dimmed(item) ? 0.2 : 1)
            .overlay(alignment: .bottomTrailing) {
                if selected && model.boardSelection.count == 1 {
                    RoundedRectangle(cornerRadius: 3).fill(Theme.accent).frame(width: 12, height: 12)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(.white, lineWidth: 1.5))
                        .offset(x: 5, y: 5)
                        .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.space))
                            .onChanged { v in sizing = (item.id, Double(v.translation.width), Double(v.translation.height)) }
                            .onEnded { v in
                                let w = item.w + Double(v.translation.width), h = item.h + Double(v.translation.height)
                                sizing = nil
                                model.updateBoard(board.id, item.kind == .frame ? "Resize Section" : "Resize") { $0.resize(item.id, w: w, h: h) }
                            })
                        .help("Drag to resize")
                }
            }
            .overlay(alignment: .trailing) {
                if selected && model.boardSelection.count == 1 && item.kind != .frame && linking == nil { linkHandle(item) }
            }
            .offset(x: r.x, y: r.y)
            .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.space))
                .onChanged { v in
                    if drag == nil {
                        if !model.boardSelection.contains(item.id) { select(item) }
                        model.editingNote = nil
                    }
                    let ids = model.boardSelection.contains(item.id) ? model.boardSelection : [item.id]
                    let g = board.guides(moving: ids, dx: Double(v.translation.width), dy: Double(v.translation.height), threshold: 6 / max(0.1, z))
                    drag = (ids, board.movingSet(ids), g)
                }
                .onEnded { _ in
                    guard let d = drag else { return }
                    drag = nil
                    model.updateBoard(board.id, d.ids.count > 1 ? "Move \(d.ids.count) Cards" : "Move") { $0.moveGroup(d.ids, dx: d.guides.dx, dy: d.guides.dy); $0.bringToFront(d.ids) }
                })
            .onTapGesture(count: 2) {
                if item.kind == .note || item.kind == .frame || item.kind == .heading { select(item); model.editingNote = item.id }
                else if item.kind == .asset, let a = item.assetID { select(item); model.viewerID = a }
            }
            .onTapGesture {
                let flags = NSEvent.modifierFlags
                if flags.contains(.shift) || flags.contains(.command) {
                    if model.boardSelection.contains(item.id) { model.boardSelection.remove(item.id) } else { model.boardSelection.insert(item.id) }
                    model.editingNote = nil
                    syncInspector()
                } else { select(item) }
            }
            .contextMenu { menu(item) }
    }

    private func select(_ item: BoardItem) {
        model.boardSelection = [item.id]
        if model.editingNote != item.id { model.editingNote = nil }
        syncInspector()
    }

    /// The inspector follows the assets among the selected cards.
    private func syncInspector() {
        let assets = board.layered.filter { model.boardSelection.contains($0.id) && $0.kind == .asset }.compactMap(\.assetID)
        guard let first = assets.first else { return }
        model.selection = Set(assets); model.focusID = first
    }

    @ViewBuilder private func menu(_ item: BoardItem) -> some View {
        let sel = model.boardSelection
        if sel.count > 1 && sel.contains(item.id) {
            Button("Bring \(sel.count) to Front") { model.updateBoard(board.id, "Bring to Front") { $0.bringToFront(sel) } }
            Button("Send \(sel.count) to Back") { model.updateBoard(board.id, "Send to Back") { $0.sendToBack(sel) } }
            Button("Put in New Section") { model.addFrame() }
            if sel.count == 2 { Button("Connect with Arrow") { model.connectSelection() } }
            ArrangeMenu(board: board, selection: sel, inContextMenu: true)
            Button("Copy \(sel.count) Cards") { model.copyCards() }
            let stale = Set(model.catalog.outdatedCards(on: board.id).keys).intersection(sel)
            if !stale.isEmpty { Button("Update \(stale.count) to Newest") { model.updateToNewest(board.id, only: stale) } }
            Menu("Mark \(sel.count) as") {
                ForEach(CardStatus.allCases, id: \.self) { st in Button(st.label) { model.updateBoard(board.id, "Mark \(st.label)") { $0.setStatus(st, for: sel) } } }
            }
            Divider()
            Button("Remove \(sel.count) from Board", role: .destructive) { model.removeFromBoard(sel) }
        } else {
            if item.kind != .frame {
                Button("Bring to Front") { model.updateBoard(board.id, "Bring to Front") { $0.bringToFront(item.id) } }
                Button("Send to Back") { model.updateBoard(board.id, "Send to Back") { $0.sendToBack(item.id) } }
                Button("Put in New Section") { select(item); model.addFrame() }
                Divider()
            }
            switch item.kind {
            case .asset where item.isSlot:
                Text("Empty slot: drag an image here")
            case .asset:
                Menu("Status") {
                    ForEach(CardStatus.allCases, id: \.self) { st in
                        Button { model.updateBoard(board.id, "Mark \(st.label)") { $0.setStatus(st, for: [item.id]) } } label: {
                            if board.status(of: item.id) == st { Label(st.label, systemImage: "checkmark") } else { Text(st.label) }
                        }
                    }
                }
                Button("Comments & Status…") { select(item); model.threadCard = item.id }
                if let a = item.assetID, let newest = model.catalog.newerVersion(of: a) {
                    Button("Update to \(VersionStacks.rank(newest).1)") { model.updateToNewest(board.id, only: [item.id]) }
                }
                Divider()
                Button("Add Palette Card") { model.addPaletteCard(for: item) }
                if let a = item.assetID, let asset = model.catalog.assets.first(where: { $0.id == a }), let hex = asset.palette.first {
                    Button("Search Library by Its Color") { model.searchFromBoard(hex) }
                }
                if let a = item.assetID { Button("Quick Look") { model.viewerID = a } }
                Button("Crop…") { select(item); model.beginCrop(item) }
                if item.crop != nil { Button("Show Whole Image") { model.updateBoard(board.id, "Reset Crop") { $0.setCrop(item.id, nil) } } }
                Button("Remove Image (Keep Slot)") { model.clearSlot(item.id) }
            case .heading:
                Button("Edit Heading") { select(item); model.editingNote = item.id }
            case .note:
                Button("Edit Note") { select(item); model.editingNote = item.id }
            case .palette:
                Menu("Search Library by Color") {
                    ForEach(item.colors, id: \.self) { h in Button(h) { model.searchFromBoard(h) } }
                }
                Button("Copy Hex Codes") {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(item.colors.joined(separator: " "), forType: .string)
                }
            case .frame:
                Button("Rename Section") { select(item); model.editingNote = item.id }
                Button("Select Contents") { model.boardSelection = board.contents(ofFrame: item.id); syncInspector() }
            }
            let arrows = board.connectors(touching: item.id)
            if !arrows.isEmpty {
                let gone = Set(arrows.map(\.id))
                Button(arrows.count == 1 ? "Remove Its Arrow" : "Remove Its \(arrows.count) Arrows") {
                    model.updateBoard(board.id, "Remove Arrows") { b in b.connectors.removeAll { gone.contains($0.id) } }
                }
            }
            Divider()
            Button(item.kind == .frame ? "Remove Section (Keep Cards)" : "Remove from Board", role: .destructive) { model.removeFromBoard([item.id]) }
        }
    }
}

struct BoardGrid: View {
    let step: Double
    var zoom = 1.0
    var body: some View {
        Canvas { ctx, size in
            // Dots keep the same size on screen at any zoom; minor dots drop out when they would crowd.
            let z = max(0.1, zoom)
            let minor = step * z >= 8
            let s = max(10.0, step)
            let W = Double(size.width), H = Double(size.height)
            var y = 0.0
            while y <= H {
                var x = 0.0
                while x <= W {
                    let major = Int((x / s).rounded()) % 5 == 0 && Int((y / s).rounded()) % 5 == 0
                    let d = (major ? 2.2 : 1.2) / z
                    if major || minor { ctx.fill(Path(ellipseIn: CGRect(x: x - d / 2, y: y - d / 2, width: d, height: d)), with: .color(.white.opacity(major ? 0.16 : 0.07))) }
                    x += s
                }
                y += s
            }
        }
    }
}

struct BoardItemView: View {
    @EnvironmentObject var model: StudioLibrary
    let item: BoardItem
    let asset: StudioAsset?
    let selected: Bool
    let editing: Bool
    /// Thumbnail pixels per point; Present asks for more because it zooms in.
    var detail = 2.0
    @State private var draft = ""
    @State private var hovering = false

    var body: some View {
        if item.kind == .frame || item.kind == .heading {
            content
        } else {
            content
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Theme.accent : Color.white.opacity(hovering ? 0.18 : 0.08), lineWidth: selected ? 2 : 1))
                .shadow(color: .black.opacity(0.45), radius: selected ? 14 : 8, y: 4)
                .onHover { hovering = $0 }
        }
    }

    @ViewBuilder private var content: some View {
        switch item.kind {
        case .asset where item.isSlot:
            TemplateSlot()
        case .asset:
            ZStack(alignment: .bottomLeading) {
                if let asset {
                    CroppedFill(crop: item.crop) {
                        Thumbnail(asset: asset, pixels: Int(min(3200, max(item.w, item.h) * detail / min(item.crop?.w ?? 1, item.crop?.h ?? 1))))
                    }
                } else { Theme.panel }
                if let asset, hovering || selected {
                    Text(asset.title).font(.caption.weight(.semibold)).lineLimit(1).padding(.horizontal, 8).padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
        case .note:
            BoardNote(text: item.text, editing: editing, draft: $draft) { text in
                guard let b = model.selectedBoard else { return }
                if text != item.text { model.updateBoard(b, "Edit Note") { $0.setText(item.id, text) } }
                model.editingNote = nil
            }
            .onAppear { draft = item.text }
            .onChange(of: editing) { _, e in if e { draft = item.text } }
        case .palette:
            BoardPalette(colors: item.colors)
        case .frame:
            BoardFrame(label: item.text, selected: selected, editing: editing, draft: $draft) { text in
                guard let b = model.selectedBoard else { return }
                if text != item.text { model.updateBoard(b, "Rename Section") { $0.setText(item.id, text) } }
                model.editingNote = nil
            }
            .onAppear { draft = item.text }
            .onChange(of: editing) { _, e in if e { draft = item.text } }
        case .heading:
            BoardHeading(text: item.text, height: item.h, selected: selected, editing: editing, draft: $draft) { text in
                guard let b = model.selectedBoard else { return }
                if text != item.text { model.updateBoard(b, "Edit Heading") { $0.setText(item.id, text) } }
                model.editingNote = nil
            }
            .onAppear { draft = item.text }
            .onChange(of: editing) { _, e in if e { draft = item.text } }
        }
    }
}

/// Large type straight on the canvas (1.19). The text size follows the box height.
struct BoardHeading: View {
    let text: String
    let height: Double
    let selected: Bool
    let editing: Bool
    @Binding var draft: String
    let commit: (String) -> Void
    @FocusState private var focused: Bool
    var body: some View {
        let size = CGFloat(Moodboard.headingFontSize(height: height))
        ZStack(alignment: .leading) {
            if selected {
                RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            }
            if editing {
                TextField("Heading", text: $draft).textFieldStyle(.plain).font(.system(size: size, weight: .heavy))
                    .foregroundStyle(.white).focused($focused).onAppear { focused = true }.onSubmit { commit(draft) }
                    .onChange(of: focused) { _, f in if !f { commit(draft) } }
                    .onExitCommand { commit(draft) }
                    .padding(.horizontal, 8)
            } else {
                Text(text.isEmpty ? "Heading" : text).font(.system(size: size, weight: .heavy))
                    .foregroundStyle(Color.white.opacity(text.isEmpty ? 0.35 : 0.94)).lineLimit(1).minimumScaleFactor(0.4)
                    .padding(.horizontal, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// Shows the `crop` part of its content (1.19): the content is laid out at full size and shifted so the crop fills the frame.
struct CroppedFill<Content: View>: View {
    let crop: BoardRect?
    @ViewBuilder let content: () -> Content
    var body: some View {
        if let c = crop {
            GeometryReader { geo in
                let fw = geo.size.width / CGFloat(c.w), fh = geo.size.height / CGFloat(c.h)
                content().frame(width: fw, height: fh).offset(x: -CGFloat(c.x) * fw, y: -CGFloat(c.y) * fh)
            }
            .clipped()
        } else {
            content()
        }
    }
}

/// A straight arrow shaft that stops where the head starts.
struct ArrowLine: Shape {
    let x1: Double, y1: Double, x2: Double, y2: Double, head: Double
    func path(in rect: CGRect) -> Path {
        let dx = x2 - x1, dy = y2 - y1, len = max(0.001, (dx * dx + dy * dy).squareRoot())
        let back = min(len, head * 0.8)
        var p = Path()
        p.move(to: CGPoint(x: x1, y: y1))
        p.addLine(to: CGPoint(x: x2 - dx / len * back, y: y2 - dy / len * back))
        return p
    }
}

struct ArrowHead: Shape {
    let x1: Double, y1: Double, x2: Double, y2: Double, head: Double
    func path(in rect: CGRect) -> Path {
        let dx = x2 - x1, dy = y2 - y1, len = max(0.001, (dx * dx + dy * dy).squareRoot())
        let ux = dx / len, uy = dy / len
        let bx = x2 - ux * head, by = y2 - uy * head, half = head * 0.5
        var p = Path()
        p.move(to: CGPoint(x: x2, y: y2))
        p.addLine(to: CGPoint(x: bx - uy * half, y: by + ux * half))
        p.addLine(to: CGPoint(x: bx + uy * half, y: by - ux * half))
        p.closeSubpath()
        return p
    }
}

/// Arrows between cards (1.19). One view for the canvas, Present and export so they always match.
struct BoardArrows: View {
    let connectors: [BoardConnector]
    let rects: [UUID: BoardRect]
    var highlight: Set<UUID> = []
    /// Keeps lines readable when the canvas is zoomed out.
    var lineScale = 1.0
    /// Board point drawn at the top-left corner (export crops to the content).
    var originX = 0.0, originY = 0.0
    var showLabels = false
    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(connectors) { c in arrow(c) }
        }
    }
    @ViewBuilder private func arrow(_ c: BoardConnector) -> some View {
        if let a = rects[c.from], let b = rects[c.to], let l = Moodboard.connectorLine(from: a, to: b) {
            let hot = highlight.contains(c.from) || highlight.contains(c.to)
            let color = hot ? Theme.accent : Color(red: 0.86, green: 0.84, blue: 0.95).opacity(0.78)
            let k = max(1, lineScale)
            let x1 = l.x1 - originX, y1 = l.y1 - originY, x2 = l.x2 - originX, y2 = l.y2 - originY
            ArrowLine(x1: x1, y1: y1, x2: x2, y2: y2, head: 13 * k)
                .stroke(color, style: StrokeStyle(lineWidth: 2.2 * k, lineCap: .round))
            ArrowHead(x1: x1, y1: y1, x2: x2, y2: y2, head: 13 * k).fill(color)
            if showLabels && !c.label.isEmpty {
                let p = Moodboard.labelSpot((x1, y1, x2, y2), labelWidth: ArrowLabel.width(c.label))
                ArrowLabel(text: c.label, editing: false, hot: false) { _ in }
                    .fixedSize().position(x: p.x, y: p.y)
            }
        }
    }
}

/// An arrow's label capsule; an unlabeled arrow shows a dot to grab.
struct ArrowLabel: View {
    let text: String
    let editing: Bool
    let hot: Bool
    let commit: (String) -> Void
    @State private var draft = ""
    @State private var done = false
    @FocusState private var focused: Bool
    var body: some View {
        if editing {
            TextField("Label", text: $draft).textFieldStyle(.plain).font(.system(size: 12, weight: .semibold))
                .frame(width: 150).focused($focused)
                .onAppear { draft = text; done = false; focused = true }
                .onSubmit { finish(draft) }
                .onExitCommand { finish(text) }
                .onChange(of: focused) { _, f in if !f { finish(draft) } }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Theme.panel, in: Capsule()).overlay(Capsule().stroke(Theme.accent, lineWidth: 1.5))
        } else if text.isEmpty {
            Circle().fill(hot ? Theme.accent : Color.white.opacity(0.55)).frame(width: 9, height: 9)
                .padding(6).contentShape(Circle())
        } else {
            Text(text).font(.system(size: 12, weight: .semibold)).lineLimit(1).foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color(red: 0.1, green: 0.1, blue: 0.145), in: Capsule())
                .overlay(Capsule().stroke(hot ? Theme.accent : Color.white.opacity(0.28), lineWidth: 1))
        }
    }
    /// Rough capsule width for placing the label (12 pt semibold plus padding); a dot when empty.
    static func width(_ text: String) -> Double { text.isEmpty ? 21 : Double(text.count) * 6.9 + 22 }

    private func finish(_ s: String) {
        guard !done else { return }
        done = true
        commit(s)
    }
}

// MARK: - Batch place artworks into one mockup (1.31)

struct BatchPlaceState: Identifiable {
    let id = UUID()
    let arts: [UUID]
    let mockups: [UUID]
    var mockup: UUID
    var layer: Int?
    var mode: PlacementMode = .fill
    var background: PlaceBackground = .white
    /// Artwork-specific framing; named presets only change the shared placement settings.
    var crops: [UUID: BoardRect] = [:]
}

struct BatchPlaceSheet: View {
    @EnvironmentObject var model: StudioLibrary
    @State var state: BatchPlaceState
    @State private var previews: [UUID: CGImage] = [:]
    @State private var sourceImages: [UUID: CGImage] = [:]
    @State private var cropArt: StudioAsset?
    @State private var focusedArt: StudioAsset?
    @State private var presetName = ""
    @State private var namingPreset = false
    @State private var presetIssue: String?
    private var mockup: StudioAsset? { model.catalog.assets.first { $0.id == state.mockup } }
    private var doc: PsdDocument? { mockup.flatMap { model.psdDocument($0) } }
    private var layers: [Int] { doc.map { MockupPlacement.targetLayers($0) } ?? [] }
    private var layerIndex: Int? { state.layer ?? layers.first }
    private var renderKey: String {
        let crops = state.arts.map { id in
            let c = state.crops[id]
            return "\(id):\(c.map { "\($0.x),\($0.y),\($0.w),\($0.h)" } ?? "-")"
        }.joined(separator: "|")
        return "\(state.mockup)|\(layerIndex ?? -1)|\(state.mode.rawValue)|\(state.background.rawValue)|\(crops)"
    }
    private var arts: [StudioAsset] { state.arts.compactMap { id in model.catalog.assets.first { $0.id == id } } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "square.stack.3d.up").foregroundStyle(Theme.accent)
                Text("Batch Place into Mockup").font(.system(size: 17, weight: .bold))
                Spacer()
                Text("\(state.arts.count) artworks · renders on this Mac")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                InspectorLabel(text: "PLACEMENT PRESETS")
                Menu {
                    if model.catalog.placementPresets.isEmpty { Text("No saved presets") }
                    ForEach(model.catalog.placementPresets.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { preset in
                        Button(preset.name) {
                            let status = model.usePlacementPreset(preset, in: &state)
                            switch status {
                            case .ready: presetIssue = nil
                            case .missingMockup: presetIssue = "\(preset.name): mockup missing. Locate or replace the source, then try again."
                            case .missingLayer:
                                if let m = model.catalog.assets.first(where: { $0.id == preset.mockupID }), state.mockups.contains(m.id) {
                                    state.mockup = m.id; state.layer = nil
                                }
                                presetIssue = "\(preset.name): design layer changed. Pick a layer and save the preset again."
                            }
                        }
                    }
                } label: { Label("Choose Preset", systemImage: "square.stack.3d.up") }
                .disabled(model.catalog.placementPresets.isEmpty)
                Button("Save Current…") {
                    presetName = (mockup?.title ?? "Mockup") + " · " + state.mode.rawValue
                    namingPreset = true
                }.disabled(layerIndex == nil)
                Spacer()
                if !model.catalog.placementPresets.isEmpty {
                    Menu("Manage") {
                        ForEach(model.catalog.placementPresets) { preset in
                            Button("Delete \(preset.name)", role: .destructive) { model.removePlacementPreset(preset.id) }
                        }
                    }
                }
            }.font(.caption)
            if let issue = presetIssue {
                HStack(spacing: 6) {
                    Label(issue, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2).foregroundStyle(Theme.warning).lineLimit(2)
                    if let preset = model.catalog.placementPresets.first(where: { issue.hasPrefix($0.name + ": mockup missing") }),
                       model.catalog.assets.contains(where: { $0.id == preset.mockupID }) {
                        Button("Locate…") {
                            if model.locate(preset.mockupID) {
                                if case .ready = model.usePlacementPreset(preset, in: &state) { presetIssue = nil }
                                else { presetIssue = "\(preset.name): design layer changed. Pick a layer and save the preset again." }
                            }
                        }.buttonStyle(.borderless).font(.caption2.weight(.semibold))
                    }
                }
            }
            HStack(spacing: 8) {
                Menu {
                    ForEach(state.mockups, id: \.self) { id in
                        if let a = model.catalog.assets.first(where: { $0.id == id }) {
                            Button(a.title) { state.mockup = id; state.layer = nil }
                        }
                    }
                } label: {
                    Label(mockup?.title ?? "Choose Mockup", systemImage: "square.3.layers.3d")
                        .lineLimit(1).font(.caption.weight(.semibold))
                }.frame(width: 195)
                Menu {
                    ForEach(layers, id: \.self) { i in
                        Button(doc?.layers[i].name ?? "Layer") { state.layer = i }
                    }
                } label: {
                    Text(layerIndex.flatMap { doc?.layers[$0].name } ?? "Design layer")
                        .font(.caption.weight(.semibold)).lineLimit(1)
                }.frame(width: 100).disabled(layers.count < 2)
                Spacer(minLength: 0)
                Picker("Mode", selection: $state.mode) {
                    ForEach(PlacementMode.allCases) { m in Text(m.rawValue).tag(m) }
                }.frame(width: 110)
                Picker("Background", selection: $state.background) {
                    ForEach(PlaceBackground.allCases) { b in Text(b.rawValue).tag(b) }
                }.frame(width: 150)
            }
            HStack {
                InspectorLabel(text: "ONE RENDER PER ARTWORK")
                Spacer()
                Text("Each render keeps its artwork's rights and editable settings")
                    .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(arts) { art in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(spacing: 5) {
                                BatchSourceFrame(image: sourceImages[art.id], mode: state.mode,
                                    areaAspect: designAspect, crop: state.crops[art.id])
                                    .overlay(alignment: .topLeading) { comparisonLabel("SOURCE · FRAME") }
                                ZStack {
                                    Theme.panel
                                    if let image = previews[art.id] {
                                        Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fit)
                                    } else { ProgressView().controlSize(.small) }
                                }
                                .overlay(alignment: .topLeading) { comparisonLabel("PLACED") }
                            }
                            .frame(height: 135)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            HStack(spacing: 5) {
                                Text(art.title).font(.caption.weight(.semibold)).lineLimit(1)
                                Spacer(minLength: 0)
                                Button { focusedArt = art } label: {
                                    Label("Inspect", systemImage: "arrow.up.left.and.arrow.down.right")
                                        .font(.caption2.weight(.semibold))
                                }.buttonStyle(.borderless).help("Compare this artwork at larger size")
                                Button { cropArt = art } label: {
                                    Label(state.crops[art.id] == nil ? "Crop" : "Adjusted", systemImage: "crop.rotate")
                                        .font(.caption2.weight(.semibold))
                                }.buttonStyle(.borderless).disabled(layerIndex == nil || state.mode == .fit)
                                    .help("Adjust the visible region for this artwork")
                            }
                            Label(rightsLine(art), systemImage: art.rightsStatus().isProblem || art.rightsStatus() == .missing ? "exclamationmark.circle" : "checkmark.seal")
                                .font(.caption2).foregroundStyle(art.rightsStatus().isProblem || art.rightsStatus() == .missing ? Theme.warning : .secondary)
                                .lineLimit(1)
                        }
                        .padding(10).background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 11))
                        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.hairline))
                    }
                }
                .padding(2)
            }.frame(height: 408)
            .sheet(item: $focusedArt) { art in
                BatchFocusedComparison(arts: arts, initialArtID: art.id, sources: sourceImages, placed: previews,
                    mode: state.mode, areaAspect: designAspect, crops: state.crops,
                    mockupName: mockup?.title ?? "Mockup", close: { focusedArt = nil },
                    edit: { selected in
                        focusedArt = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { cropArt = selected }
                    })
                    .environment(\.colorScheme, .dark)
            }
            .popover(item: $cropArt) { art in
                BatchArtCropper(art: art, image: sourceImages[art.id], mode: state.mode,
                    areaAspect: designAspect, crop: Binding(
                        get: { state.crops[art.id] },
                        set: { state.crops[art.id] = $0 }))
                    .environment(\.colorScheme, .dark)
            }
            HStack {
                Button("Cancel") { model.batchPlacement = nil }.keyboardShortcut(.cancelAction)
                Spacer()
                Text("\(state.arts.count) new versions · one undo step").font(.caption).foregroundStyle(.secondary)
                Button("Place \(state.arts.count) Artworks") { model.commitBatchPlacement(state) }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(layerIndex == nil)
            }
        }
        .padding(20).frame(width: 900).background(Theme.backdrop)
        .environment(\.colorScheme, .dark)
        .task(id: renderKey) {
            await makePreviews()
            if ProcessInfo.processInfo.arguments.contains("batch-crop"), cropArt == nil {
                cropArt = arts.first
            }
            if ProcessInfo.processInfo.arguments.contains("batch-focus-fit"), focusedArt == nil {
                focusedArt = arts.first
            } else if ProcessInfo.processInfo.arguments.contains("batch-focus-last"), focusedArt == nil {
                focusedArt = arts.last
            } else if ProcessInfo.processInfo.arguments.contains("batch-focus-next"), focusedArt == nil {
                focusedArt = arts.dropFirst().first
            } else if ProcessInfo.processInfo.arguments.contains("batch-focus"), focusedArt == nil {
                focusedArt = arts.first
            }
        }
        .alert("Save Placement Preset", isPresented: $namingPreset) {
            TextField("Preset name", text: $presetName)
            Button("Save") { model.saveBatchPlacementPreset(state, name: presetName) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Stores this mockup, design layer, mode and background for future batches. A name already in use is updated.") }
    }

    private func comparisonLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 8, weight: .bold, design: .rounded)).tracking(0.5)
            .foregroundStyle(.white)
            .padding(.horizontal, 5).padding(.vertical, 3)
            .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 4))
            .padding(5)
    }

    private var designAspect: Double {
        guard let d = doc, let i = layerIndex, d.layers.indices.contains(i),
              let q = MockupPlacement.quad(of: d.layers[i]) else { return 1 }
        return q.aspect
    }

    private func rightsLine(_ art: StudioAsset) -> String {
        if let rights = art.rights, !rights.isEmpty {
            let status = art.rightsStatus()
            let flag: String
            switch status {
            case .expired: flag = "Expired · "
            case .expiring: flag = "Expiring · "
            case .editorial: flag = "Editorial · "
            default: flag = ""
            }
            return flag + [rights.license.rawValue, rights.credit.isEmpty ? rights.source : rights.credit]
                .filter { !$0.isEmpty }.joined(separator: " · ")
        }
        return art.isStarter || art.sourceKey?.hasPrefix("generated:") == true ? "ASSSETS bundled library" : "No rights info"
    }

    private func makePreviews() async {
        previews = [:]
        guard let doc else { return }
        let layer = layerIndex, mode = state.mode, bg = state.background.rgb
        for art in arts {
            guard !Task.isCancelled else { return }
            guard let pixels = model.artPixels(art, maxPixel: 480) else { continue }
            if let source = MediaRenderer.cgImage(pixels) { sourceImages[art.id] = source }
            let crop = mode == .fill ? state.crops[art.id] : nil
            let result = await Task.detached(priority: .userInitiated) {
                StudioLibrary.renderPlaced(art: pixels, doc: doc, layer: layer, mode: mode, crop: crop, background: bg)
            }.value
            guard !Task.isCancelled else { return }
            if let result, let image = MediaRenderer.cgImage(result, maxPixel: 360) { previews[art.id] = image }
        }
    }
}

/// A read-only, fitted source with the same visible region used by the placement renderer.
/// This sits beside each live mockup render, so opening the crop editor is optional for review.
struct BatchSourceFrame: View {
    let image: CGImage?
    let mode: PlacementMode
    let areaAspect: Double
    let crop: BoardRect?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Theme.panel
                if let image {
                    let aspect = CGFloat(image.width) / CGFloat(max(1, image.height))
                    let w = min(geo.size.width, geo.size.height * aspect)
                    let h = w / aspect
                    let region = MockupPlacement.region(mode: mode, artAspect: Double(aspect), areaAspect: areaAspect,
                        crop: mode == .fill ? crop : nil)
                    let x0 = CGFloat(max(0, region.x)), y0 = CGFloat(max(0, region.y))
                    let x1 = CGFloat(min(1, region.x + region.w)), y1 = CGFloat(min(1, region.y + region.h))
                    ZStack(alignment: .topLeading) {
                        Image(decorative: image, scale: 1).resizable().interpolation(.high)
                            .frame(width: w, height: h)
                        if mode == .fill, x1 > x0, y1 > y0 {
                            Rectangle().fill(.black.opacity(0.42))
                                .frame(width: w, height: y0 * h)
                            Rectangle().fill(.black.opacity(0.42))
                                .frame(width: w, height: (1 - y1) * h).offset(y: y1 * h)
                            Rectangle().fill(.black.opacity(0.42))
                                .frame(width: x0 * w, height: (y1 - y0) * h).offset(y: y0 * h)
                            Rectangle().fill(.black.opacity(0.42))
                                .frame(width: (1 - x1) * w, height: (y1 - y0) * h)
                                .offset(x: x1 * w, y: y0 * h)
                            Rectangle().stroke(.white, lineWidth: 1.5)
                                .frame(width: (x1 - x0) * w, height: (y1 - y0) * h)
                                .offset(x: x0 * w, y: y0 * h)
                        }
                    }
                    .frame(width: w, height: h)
                    .clipped()
                } else { ProgressView().controlSize(.small) }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityLabel("Source artwork with visible framing")
    }
}

/// A larger, read-only comparison for one batch artwork. Keeps the same state in the batch
/// sheet so closing the view neither commits a render nor loses the other artworks' crops.
struct BatchFocusedComparison: View {
    let arts: [StudioAsset]
    let sources: [UUID: CGImage]
    let placed: [UUID: CGImage]
    let mode: PlacementMode
    let areaAspect: Double
    let crops: [UUID: BoardRect]
    let mockupName: String
    let close: () -> Void
    let edit: (StudioAsset) -> Void
    @State private var selectedID: UUID

    init(arts: [StudioAsset], initialArtID: UUID, sources: [UUID: CGImage], placed: [UUID: CGImage],
         mode: PlacementMode, areaAspect: Double, crops: [UUID: BoardRect], mockupName: String,
         close: @escaping () -> Void, edit: @escaping (StudioAsset) -> Void) {
        self.arts = arts; self.sources = sources; self.placed = placed; self.mode = mode
        self.areaAspect = areaAspect; self.crops = crops; self.mockupName = mockupName
        self.close = close; self.edit = edit
        _selectedID = State(initialValue: initialArtID)
    }

    private var index: Int { arts.firstIndex { $0.id == selectedID } ?? 0 }
    private var art: StudioAsset? { arts.indices.contains(index) ? arts[index] : nil }
    private var crop: BoardRect? { art.flatMap { crops[$0.id] } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.split.2x1").foregroundStyle(Theme.accent)
                Text("Inspect Placement").font(.system(size: 17, weight: .bold))
                Spacer()
                if let art { Text(art.title).font(.caption.weight(.semibold)).lineLimit(1).foregroundStyle(.secondary) }
            }
            HStack(spacing: 14) {
                panel("SOURCE · FRAME") {
                    BatchSourceFrame(image: art.flatMap { sources[$0.id] }, mode: mode, areaAspect: areaAspect, crop: crop)
                }
                panel("PLACED · \(mockupName)") {
                    ZStack {
                        Theme.panel
                        if let image = art.flatMap({ placed[$0.id] }) {
                            Image(decorative: image, scale: 1).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                        } else { ProgressView().controlSize(.small) }
                    }
                }
            }
            HStack(spacing: 8) {
                Text(mode == .fill ? (crop == nil ? "Automatic Fill framing" : "Custom Fill framing") : "Fit shows the whole artwork")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button { selectedID = arts[index - 1].id } label: {
                    Label("Previous", systemImage: "chevron.left")
                }.disabled(index == 0)
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .help("Inspect the previous artwork (←)")
                Text("\(arts.isEmpty ? 0 : index + 1) of \(arts.count)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .frame(minWidth: 38)
                Button { selectedID = arts[index + 1].id } label: {
                    Label("Next", systemImage: "chevron.right")
                }.disabled(index >= arts.count - 1)
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .help("Inspect the next artwork (→)")
                Button("Back to Batch") { close() }.keyboardShortcut(.cancelAction)
                Button("Adjust Crop…") { if let art { edit(art) } }
                    .buttonStyle(.borderedProminent).disabled(mode == .fit || art == nil)
            }
        }
        .padding(20).frame(width: 850).background(Theme.backdrop)
    }

    private func panel<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1)
                .foregroundStyle(Theme.accent).lineLimit(1)
            content().frame(height: 320)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline))
        }
        .frame(maxWidth: .infinity)
    }
}

/// Per-art framing in the batch. The white outline is the visible design region; moving and
/// resizing it updates only this artwork, while the preset's layer, mode and background stay shared.
struct BatchArtCropper: View {
    let art: StudioAsset
    let image: CGImage?
    let mode: PlacementMode
    let areaAspect: Double
    @Binding var crop: BoardRect?
    @State private var dragStart: BoardRect?
    private let canvas = CGSize(width: 320, height: 250)

    private var artAspect: Double { guard let image else { return 1 }; return Double(image.width) / Double(max(1, image.height)) }
    private var box: CGSize {
        let aspect = CGFloat(artAspect)
        return aspect > canvas.width / canvas.height
            ? CGSize(width: canvas.width, height: canvas.width / aspect)
            : CGSize(width: canvas.height * aspect, height: canvas.height)
    }
    private var region: BoardRect { MockupPlacement.region(mode: mode, artAspect: artAspect, areaAspect: areaAspect, crop: crop) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Frame artwork", systemImage: "crop.rotate").font(.headline)
                Spacer()
                Button("Reset") { crop = nil }.disabled(crop == nil).buttonStyle(.borderless)
            }
            Text(art.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            ZStack { artCropper.frame(width: canvas.width, height: canvas.height) }
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 8))
            Text("Drag the frame to move it; drag the corner to zoom. This crop saves with this artwork's editable placement.")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16).frame(width: 352).background(Theme.backdrop)
    }

    private var artCropper: some View {
        let b = box, r0 = region
        let x0 = max(0, r0.x), y0 = max(0, r0.y), x1 = min(1, r0.x + r0.w), y1 = min(1, r0.y + r0.h)
        let r = CGRect(x: x0 * b.width, y: y0 * b.height, width: max(0, x1 - x0) * b.width, height: max(0, y1 - y0) * b.height)
        return ZStack(alignment: .topLeading) {
            if let image { Image(decorative: image, scale: 1).resizable().interpolation(.high).frame(width: b.width, height: b.height) }
            Group {
                Rectangle().frame(width: b.width, height: r.minY)
                Rectangle().frame(width: b.width, height: max(0, b.height - r.maxY)).offset(y: r.maxY)
                Rectangle().frame(width: r.minX, height: r.height).offset(y: r.minY)
                Rectangle().frame(width: max(0, b.width - r.maxX), height: r.height).offset(x: r.maxX, y: r.minY)
            }.foregroundStyle(Color.black.opacity(0.62)).allowsHitTesting(false)
            Rectangle().stroke(.white, lineWidth: 1.5).frame(width: r.width, height: r.height)
                .offset(x: r.minX, y: r.minY).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 1).onChanged { value in
                    let start = dragStart ?? r0; if dragStart == nil { dragStart = start }
                    var next = start
                    next.x = min(1 - next.w, max(0, start.x + Double(value.translation.width / b.width)))
                    next.y = min(1 - next.h, max(0, start.y + Double(value.translation.height / b.height)))
                    crop = next
                }.onEnded { _ in dragStart = nil })
            RoundedRectangle(cornerRadius: 3).fill(Theme.accent).frame(width: 13, height: 13)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(.white, lineWidth: 1.5))
                .offset(x: r.maxX - 6.5, y: r.maxY - 6.5)
                .gesture(DragGesture(minimumDistance: 1).onChanged { value in
                    let start = dragStart ?? r0; if dragStart == nil { dragStart = start }
                    let scale = max(0.1, min((1 - start.x) / start.w, (1 - start.y) / start.h,
                        1 + Double(value.translation.width / b.width) / start.w))
                    crop = BoardRect(x: start.x, y: start.y, w: start.w * scale, h: start.h * scale)
                }.onEnded { _ in dragStart = nil }).help("Drag to zoom")
        }
        .frame(width: b.width, height: b.height).clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.hairline))
    }
}

// MARK: - Place into Mockup (1.29)

enum PlaceBackground: String, CaseIterable, Identifiable {
    case white = "White", paper = "Paper", slate = "Slate", black = "Black"
    var id: String { rawValue }
    var rgb: (UInt8, UInt8, UInt8) {
        switch self {
        case .white: return (255, 255, 255)
        case .paper: return (243, 238, 228)
        case .slate: return (52, 56, 66)
        case .black: return (12, 12, 14)
        }
    }
    var color: Color { let c = rgb; return Color(red: Double(c.0) / 255, green: Double(c.1) / 255, blue: Double(c.2) / 255) }
}

struct PlaceState: Identifiable {
    let id = UUID()
    let art: StudioAsset
    /// A small copy of the art for the live preview; saving re-reads it at full size.
    let preview: PixelBuffer
    let mockups: [UUID]
    var mockup: UUID
    /// The design layer (nil: the mockup's best one).
    var layer: Int?
    var mode: PlacementMode = .fill
    /// Part of the art (fractions) the user dragged to; Fill only.
    var crop: BoardRect?
    var background: PlaceBackground = .white
    var editing: UUID?
    var layerMissing: String?
    var artAspect: Double { Double(preview.width) / Double(max(1, preview.height)) }
}

/// Pick a mockup, a design layer, Fill or Fit and the part of the art to show; the preview renders on this Mac.
struct PlaceMockupSheet: View {
    @EnvironmentObject var model: StudioLibrary
    @State var state: PlaceState
    @State private var rendered: CGImage?
    @State private var rendering = false
    @State private var dragStart: BoardRect?
    private let previewBox = CGSize(width: 470, height: 352)
    private let artBox = CGSize(width: 214, height: 160)

    private var mockup: StudioAsset? { model.catalog.assets.first { $0.id == state.mockup } }
    private var doc: PsdDocument? { mockup.flatMap { model.psdDocument($0) } }
    private var layers: [Int] { doc.map { MockupPlacement.targetLayers($0) } ?? [] }
    private var layerIndex: Int? { state.layer ?? layers.first }
    private var areaAspect: Double {
        guard let d = doc, let i = layerIndex, d.layers.indices.contains(i), let q = MockupPlacement.quad(of: d.layers[i]) else { return 1 }
        return q.aspect
    }
    /// What the design area shows, in art fractions (Fit runs past the edges).
    private var region: BoardRect { MockupPlacement.region(mode: state.mode, artAspect: state.artAspect, areaAspect: areaAspect, crop: state.mode == .fill ? state.crop : nil) }
    private var renderKey: String {
        let c = state.crop.map { "\($0.x),\($0.y),\($0.w),\($0.h)" } ?? "-"
        return "\(state.mockup)|\(layerIndex ?? -1)|\(state.mode.rawValue)|\(c)|\(state.background.rawValue)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.on.rectangle.angled").foregroundStyle(Theme.accent)
                Text(state.editing == nil ? "Place into Mockup" : "Edit Placement").font(.system(size: 15, weight: .bold))
                Text(state.art.title).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Label("Renders on this Mac", systemImage: "cpu").font(.caption).foregroundStyle(.tertiary)
            }
            HStack(alignment: .top, spacing: 14) {
                mockupList
                VStack(alignment: .leading, spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.35))
                        if let rendered {
                            Image(decorative: rendered, scale: 1).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                        }
                        if rendering || rendered == nil { ProgressView().controlSize(.small).padding(8).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing) }
                    }
                    .frame(width: previewBox.width, height: previewBox.height)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline))
                    HStack(spacing: 8) {
                        Text("Design layer").font(.caption).foregroundStyle(.secondary)
                        Menu {
                            ForEach(layers, id: \.self) { i in Button(layerName(i)) { state.layer = i; state.layerMissing = nil } }
                        } label: {
                            Text(layerIndex.map(layerName) ?? "None").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        }
                        .menuStyle(.borderlessButton).fixedSize()
                        .disabled(layers.count < 2 && state.layerMissing == nil)
                        if state.layerMissing != nil { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning).help("Design layer changed. Choose a layer before saving.") }
                        Spacer()
                        Text(doc.map { "\($0.width) × \($0.height) PNG" } ?? "").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                    }
                }
                controls
            }
            HStack {
                Button("Cancel") { model.placing = nil }.keyboardShortcut(.cancelAction)
                Spacer()
                if state.editing == nil {
                    Button("Place into All \(state.mockups.count) Mockups") { model.placeIntoAll(state) }
                        .help("Render every mockup with this art and open them as a contact sheet")
                }
                Button(state.editing == nil ? "Save as New Version" : "Save Revised Version") { model.commitPlace(state) }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(layerIndex == nil || state.layerMissing != nil)
            }
        }
        .padding(20)
        .frame(width: 900)
        .background(Theme.backdrop)
        .environment(\.colorScheme, .dark)
        .task(id: renderKey) { await render() }
    }

    private var mockupList: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(state.mockups, id: \.self) { id in
                    if let m = model.catalog.assets.first(where: { $0.id == id }) {
                        Button {
                            state.mockup = id; state.layer = nil; state.layerMissing = nil
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Thumbnail(asset: m, pixels: 240).frame(width: 128, height: 80).clipShape(RoundedRectangle(cornerRadius: 7))
                                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(id == state.mockup ? Theme.accent : Theme.hairline, lineWidth: id == state.mockup ? 2 : 1))
                                Text(m.title).font(.system(size: 11, weight: id == state.mockup ? .semibold : .regular)).lineLimit(1)
                                    .foregroundStyle(id == state.mockup ? .primary : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .frame(width: 136, height: previewBox.height + 30)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            InspectorLabel(text: "ARTWORK")
            artCropper
            HStack(spacing: 6) {
                ForEach(PlacementMode.allCases) { m in
                    Button(m == .fill ? "Fill" : "Fit") { state.mode = m }
                        .buttonStyle(.plain).font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(state.mode == m ? Theme.accent.opacity(0.35) : Color.white.opacity(0.07), in: Capsule())
                }
                Spacer()
                Button("Reset") { state.crop = nil }.buttonStyle(.plain).font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                    .disabled(state.crop == nil)
            }
            Text(state.mode == .fill ? "Drag the frame to choose what shows. Drag the corner to zoom." : "The whole artwork shows; the margins take the background.")
                .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            if let missing = state.layerMissing {
                Text("Layer \"\(missing)\" changed. Choose a design layer before saving.")
                    .font(.caption2).foregroundStyle(Theme.warning).fixedSize(horizontal: false, vertical: true)
            }
            InspectorLabel(text: "BACKGROUND").padding(.top, 4)
            HStack(spacing: 8) {
                ForEach(PlaceBackground.allCases) { b in
                    Button { state.background = b } label: {
                        Circle().fill(b.color).frame(width: 20, height: 20)
                            .overlay(Circle().stroke(state.background == b ? Theme.accent : Color.white.opacity(0.25), lineWidth: state.background == b ? 2.5 : 1))
                    }
                    .buttonStyle(.plain).help(b.rawValue)
                }
                Spacer()
            }
            InspectorLabel(text: "SAVES WITH").padding(.top, 4)
            VStack(alignment: .leading, spacing: 4) {
                Label(rightsLine, systemImage: "checkmark.seal").lineLimit(2)
                Label("Stacked on \(mockup?.title ?? "the mockup")", systemImage: "square.stack.3d.up").lineLimit(1)
                if !state.art.licenseDocs.isEmpty { Label("\(state.art.licenseDocs.count) license file\(state.art.licenseDocs.count == 1 ? "" : "s")", systemImage: "doc.text") }
            }
            .font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(width: artBox.width, height: previewBox.height + 30, alignment: .topLeading)
    }

    private var rightsLine: String {
        if let r = state.art.rights, !r.isEmpty {
            return [r.license.rawValue, r.credit.isEmpty ? r.source : r.credit].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        return state.art.isStarter ? "Own work · ASSSETS bundled library" : "No rights info yet"
    }

    private var artCropper: some View {
        let box = fitted(artBox)
        let r0 = region
        // Only the part inside the art can be shown as a frame.
        let x0 = max(0, r0.x), y0 = max(0, r0.y), x1 = min(1, r0.x + r0.w), y1 = min(1, r0.y + r0.h)
        let r = CGRect(x: x0 * box.width, y: y0 * box.height, width: (x1 - x0) * box.width, height: (y1 - y0) * box.height)
        return ZStack(alignment: .topLeading) {
            if let cg = MediaRenderer.cgImage(state.preview) {
                Image(decorative: cg, scale: 1).resizable().interpolation(.high).frame(width: box.width, height: box.height)
            }
            Group {
                Rectangle().frame(width: box.width, height: r.minY)
                Rectangle().frame(width: box.width, height: max(0, box.height - r.maxY)).offset(y: r.maxY)
                Rectangle().frame(width: r.minX, height: r.height).offset(y: r.minY)
                Rectangle().frame(width: max(0, box.width - r.maxX), height: r.height).offset(x: r.maxX, y: r.minY)
            }
            .foregroundStyle(Color.black.opacity(0.6)).allowsHitTesting(false)
            Rectangle().stroke(Color.white, lineWidth: 1.5)
                .frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 1).onChanged { v in
                    guard state.mode == .fill else { return }
                    let s0 = dragStart ?? r0; if dragStart == nil { dragStart = s0 }
                    var n = s0
                    n.x = min(1 - n.w, max(0, s0.x + Double(v.translation.width / box.width)))
                    n.y = min(1 - n.h, max(0, s0.y + Double(v.translation.height / box.height)))
                    state.crop = n
                }.onEnded { _ in dragStart = nil })
            if state.mode == .fill {
                RoundedRectangle(cornerRadius: 3).fill(Theme.accent).frame(width: 13, height: 13)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(.white, lineWidth: 1.5))
                    .offset(x: r.maxX - 6.5, y: r.maxY - 6.5)
                    .gesture(DragGesture(minimumDistance: 1).onChanged { v in
                        let s0 = dragStart ?? r0; if dragStart == nil { dragStart = s0 }
                        // Zoom about the top-left corner, keeping the design area's shape.
                        let scale = max(0.1, min((1 - s0.x) / s0.w, (1 - s0.y) / s0.h, 1 + Double(v.translation.width / box.width) / s0.w))
                        state.crop = BoardRect(x: s0.x, y: s0.y, w: s0.w * scale, h: s0.h * scale)
                    }.onEnded { _ in dragStart = nil })
                    .help("Drag to zoom")
            }
        }
        .frame(width: box.width, height: box.height)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.hairline))
    }

    private func fitted(_ limit: CGSize) -> CGSize {
        let n = CGFloat(max(0.1, state.artAspect))
        return n >= limit.width / limit.height ? CGSize(width: limit.width, height: (limit.width / n).rounded())
                                               : CGSize(width: (limit.height * n).rounded(), height: limit.height)
    }

    private func layerName(_ i: Int) -> String {
        guard let d = doc, d.layers.indices.contains(i) else { return "Layer" }
        return d.layers[i].name.replacingOccurrences(of: " (Smart Object)", with: "")
    }

    private func render() async {
        guard let doc else { rendered = nil; return }
        rendering = true
        let art = state.preview, layer = layerIndex, mode = state.mode, crop = state.crop, bg = state.background.rgb
        let buf = await Task.detached(priority: .userInitiated) {
            StudioLibrary.renderPlaced(art: art, doc: doc, layer: layer, mode: mode, crop: crop, background: bg)
        }.value
        guard !Task.isCancelled else { return }
        rendered = buf.flatMap { MediaRenderer.cgImage($0) }
        rendering = false
    }
}

/// Inspector strip: a few mockups to drop the focused art into.
struct PlaceStrip: View {
    @EnvironmentObject var model: StudioLibrary
    let asset: StudioAsset
    var body: some View {
        let mockups = Array(model.mockupAssets.prefix(4))
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                InspectorLabel(text: "PLACE INTO MOCKUP")
                Spacer()
                Button("Choose…") { model.openPlaceIntoMockup(asset.id) }
                    .buttonStyle(.plain).font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                    .help("Place this art into a PSD mockup (⌥⌘P)")
            }
            if mockups.isEmpty {
                Text("Import a layered PSD mockup to place art into it.").font(.caption2).foregroundStyle(.tertiary)
            } else {
                HStack(spacing: 8) {
                    ForEach(mockups, id: \.id) { m in
                        Button { model.openPlaceIntoMockup(asset.id, mockup: m.id) } label: {
                            Thumbnail(asset: m, pixels: 160).frame(width: 58, height: 42).clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.hairline))
                        }
                        .buttonStyle(.plain).help(m.title)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

struct PlacementRecipeStrip: View {
    @EnvironmentObject var model: StudioLibrary
    let asset: StudioAsset
    var body: some View {
        if let recipe = asset.placementRecipe {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    InspectorLabel(text: "EDITABLE PLACEMENT")
                    Spacer()
                    Button("Edit…") { model.editPlacement(asset) }.buttonStyle(.plain)
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                }
                Text("\(recipe.mode.rawValue) · \(recipe.layerName ?? "Auto layer") · \(recipe.background) background")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                let status = model.catalog.placementStatus(recipe, exists: { FileManager.default.fileExists(atPath: $0) })
                switch status {
                case .ready: EmptyView()
                case .missingArt: Label("Source art missing · Edit to relink", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.warning).font(.caption)
                case .missingMockup: Label("Mockup missing · Edit to relink", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.warning).font(.caption)
                }
            }
        }
    }
}

// MARK: - Crop sheet (1.19)

struct CropState: Identifiable {
    let id = UUID()
    let board: UUID
    let item: UUID
    let asset: StudioAsset
    /// Width / height of the whole image.
    let natural: Double
    var crop: BoardRect
}

/// Non-destructive crop for an asset card: drag the frame to move it, the corner to size it, or pick a shape.
struct CropSheet: View {
    @EnvironmentObject var model: StudioLibrary
    @State var state: CropState
    @State private var start: BoardRect?
    private static let shapes: [(String, Double?)] = [("Free", nil), ("1:1", 1), ("4:5", 0.8), ("4:3", 4.0 / 3), ("3:2", 1.5), ("16:9", 16.0 / 9)]
    @State private var lock: Double?

    var body: some View {
        let box = fitted(CGSize(width: 520, height: 330))
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "crop").foregroundStyle(Theme.accent)
                Text("Crop Card").font(.system(size: 15, weight: .bold))
                Text(state.asset.title).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Text("The file is not changed").font(.caption).foregroundStyle(.tertiary)
            }
            ZStack(alignment: .topLeading) {
                Thumbnail(asset: state.asset, pixels: 1400).frame(width: box.width, height: box.height)
                let c = state.crop
                let r = CGRect(x: c.x * box.width, y: c.y * box.height, width: c.w * box.width, height: c.h * box.height)
                // Dim what the card will not show: four bands around the crop.
                Group {
                    Rectangle().frame(width: box.width, height: r.minY)
                    Rectangle().frame(width: box.width, height: max(0, box.height - r.maxY)).offset(y: r.maxY)
                    Rectangle().frame(width: r.minX, height: r.height).offset(y: r.minY)
                    Rectangle().frame(width: max(0, box.width - r.maxX), height: r.height).offset(x: r.maxX, y: r.minY)
                }
                .foregroundStyle(Color.black.opacity(0.62)).allowsHitTesting(false)
                Rectangle().stroke(Color.white, lineWidth: 1.5)
                    .overlay(thirds)
                    .frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 1).onChanged { v in
                        let s0 = start ?? state.crop; if start == nil { start = s0 }
                        var n = s0
                        n.x = min(1 - n.w, max(0, s0.x + Double(v.translation.width / box.width)))
                        n.y = min(1 - n.h, max(0, s0.y + Double(v.translation.height / box.height)))
                        state.crop = n
                    }.onEnded { _ in start = nil })
                RoundedRectangle(cornerRadius: 3).fill(Theme.accent).frame(width: 14, height: 14)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(.white, lineWidth: 1.5))
                    .offset(x: r.maxX - 7, y: r.maxY - 7)
                    .gesture(DragGesture(minimumDistance: 1).onChanged { v in
                        let s0 = start ?? state.crop; if start == nil { start = s0 }
                        state.crop = resized(s0, dw: Double(v.translation.width / box.width), dh: Double(v.translation.height / box.height))
                    }.onEnded { _ in start = nil })
                    .help("Drag to size the crop")
            }
            .frame(width: box.width, height: box.height)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .frame(maxWidth: .infinity)
            HStack(spacing: 6) {
                ForEach(Self.shapes, id: \.0) { shape in
                    let (name, aspect) = shape
                    Button(name) {
                        lock = aspect
                        if let aspect { state.crop = Moodboard.centeredCrop(aspect: aspect, natural: state.natural) }
                    }
                    .buttonStyle(.plain).font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(lock == aspect ? Theme.accent.opacity(0.35) : Color.white.opacity(0.07), in: Capsule())
                }
                Spacer()
                Text(sizeText).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            HStack {
                Button("Whole Image") { lock = nil; state.crop = BoardRect(x: 0, y: 0, w: 1, h: 1) }
                Spacer()
                Button("Cancel") { model.cropping = nil }.keyboardShortcut(.cancelAction)
                Button("Crop Card") { model.applyCrop(state) }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 580)
        .background(Theme.backdrop)
        .onAppear {
            // Light up the shape that matches an existing crop.
            let c = state.crop, shown = state.natural * c.w / c.h
            if c.w < 0.999 || c.h < 0.999 { lock = Self.shapes.compactMap(\.1).first { abs($0 - shown) < 0.01 } }
        }
        .environment(\.colorScheme, .dark)
    }

    private var thirds: some View {
        GeometryReader { g in
            Path { p in
                for i in 1...2 {
                    let x = g.size.width * CGFloat(i) / 3, y = g.size.height * CGFloat(i) / 3
                    p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: g.size.height))
                    p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: g.size.width, y: y))
                }
            }
            .stroke(Color.white.opacity(0.35), lineWidth: 0.8)
        }
        .allowsHitTesting(false)
    }

    /// The image fitted inside `limit`, keeping its shape.
    private func fitted(_ limit: CGSize) -> CGSize {
        let n = CGFloat(max(0.1, state.natural))
        return n >= limit.width / limit.height ? CGSize(width: limit.width, height: (limit.width / n).rounded())
                                               : CGSize(width: (limit.height * n).rounded(), height: limit.height)
    }

    /// Corner drag, keeping the picked shape when one is locked.
    private func resized(_ s0: BoardRect, dw: Double, dh: Double) -> BoardRect {
        var w = min(1 - s0.x, max(0.05, s0.w + dw)), h = min(1 - s0.y, max(0.05, s0.h + dh))
        if let lock {
            // Shown aspect = (w * natural) / h.
            let hw = w * state.natural / lock
            if hw <= 1 - s0.y { h = max(0.05, hw) } else { h = 1 - s0.y; w = h * lock / state.natural }
        }
        return BoardRect(x: s0.x, y: s0.y, w: w, h: h)
    }

    private var sizeText: String {
        let c = state.crop
        let shown = state.natural * c.w / c.h
        return c.w > 0.999 && c.h > 0.999 ? "Whole image" : String(format: "%.0f%% × %.0f%% · %.2f:1", c.w * 100, c.h * 100, shown)
    }
}

/// A labeled section behind the cards (1.18). Draws its own border, so it skips the card shadow.
struct BoardFrame: View {
    let label: String
    let selected: Bool
    let editing: Bool
    @Binding var draft: String
    let commit: (String) -> Void
    @FocusState private var focused: Bool
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.028))
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(selected ? Theme.accent : Color.white.opacity(0.2), style: StrokeStyle(lineWidth: selected ? 2 : 1.2, dash: selected ? [] : [7, 5]))
            if editing {
                TextField("Section name", text: $draft).textFieldStyle(.plain).font(.system(size: 18, weight: .bold))
                    .focused($focused).onAppear { focused = true }.onSubmit { commit(draft) }
                    .onChange(of: focused) { _, f in if !f { commit(draft) } }
                    .onExitCommand { commit(draft) }
                    .padding(.horizontal, 16).padding(.top, 11).frame(maxWidth: 360, alignment: .leading)
            } else {
                Text((label.isEmpty ? "Untitled section" : label).uppercased()).font(.system(size: 16, weight: .heavy)).tracking(1.6)
                    .foregroundStyle(Color.white.opacity(label.isEmpty ? 0.35 : 0.72)).lineLimit(1)
                    .padding(.horizontal, 16).padding(.top, 12)
            }
        }
    }
}

struct BoardNote: View {
    let text: String
    let editing: Bool
    @Binding var draft: String
    let commit: (String) -> Void
    @FocusState private var focused: Bool
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10).fill(Color(red: 0.99, green: 0.93, blue: 0.72))
            if editing {
                TextEditor(text: $draft).font(.system(size: 14, weight: .medium)).scrollContentBackground(.hidden)
                    .foregroundStyle(Color(red: 0.2, green: 0.16, blue: 0.08)).padding(10).focused($focused)
                    .onAppear { focused = true }
                    .onChange(of: focused) { _, f in if !f { commit(draft) } }
                    .onExitCommand { commit(draft) }
                Button("Done") { commit(draft) }.buttonStyle(.borderedProminent).controlSize(.small)
                    .keyboardShortcut(.return, modifiers: .command)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(8)
            } else {
                Text(text.isEmpty ? "Double-click to write" : text).font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(red: 0.2, green: 0.16, blue: 0.08).opacity(text.isEmpty ? 0.5 : 1)).padding(14)
            }
        }
    }
}

struct BoardPalette: View {
    let colors: [String]
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) { ForEach(colors, id: \.self) { h in Color(hex: h) } }
            HStack(spacing: 0) {
                ForEach(colors, id: \.self) { h in
                    Text(h).font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.6).frame(maxWidth: .infinity)
                }
            }.frame(height: 24).background(Theme.panel)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// Static board for PNG/PDF export: dark backdrop, cards back to front, no grid or selection.
struct BoardExportView: View {
    let board: Moodboard
    let assets: [UUID: StudioAsset]
    let images: [UUID: CGImage]
    let rect: BoardRect
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(red: 0.045, green: 0.05, blue: 0.08)
            ForEach(board.layered) { item in
                piece(item).frame(width: item.w, height: item.h)
                    .shadow(color: .black.opacity(item.kind == .heading ? 0 : 0.4), radius: 8, y: 4)
                    .offset(x: item.x - rect.x, y: item.y - rect.y)
            }
            BoardArrows(connectors: board.connectors, rects: board.rects, originX: rect.x, originY: rect.y, showLabels: true)
        }
        .frame(width: rect.w, height: rect.h, alignment: .topLeading)
        .environment(\.colorScheme, .dark)
    }
    @ViewBuilder private func piece(_ item: BoardItem) -> some View {
        switch item.kind {
        case .asset:
            Group {
                if let id = item.assetID, let cg = images[id] {
                    CroppedFill(crop: item.crop) { Image(decorative: cg, scale: 1).resizable().scaledToFill() }
                } else { Color.gray.opacity(0.2) }
            }
            .frame(width: item.w, height: item.h).clipShape(RoundedRectangle(cornerRadius: 10))
        case .note:
            BoardNote(text: item.text, editing: false, draft: .constant(item.text)) { _ in }
        case .palette:
            BoardPalette(colors: item.colors)
        case .frame:
            BoardFrame(label: item.text, selected: false, editing: false, draft: .constant(item.text)) { _ in }
        case .heading:
            BoardHeading(text: item.text, height: item.h, selected: false, editing: false, draft: .constant(item.text)) { _ in }
        }
    }
}

// MARK: - Layout

struct StudioView: View {
    @EnvironmentObject var model: StudioLibrary
    @AppStorage("inspectorWidth") private var inspectorWidth = 316.0
    var body: some View {
        // Sidebar | content + inspector. The inspector lives inside the detail column so it can collapse (1.17).
        NavigationSplitView {
            Sidebar().navigationSplitViewColumnWidth(min: 246, ideal: 258, max: 320)
        } detail: {
            HStack(spacing: 0) {
                Group {
                    if let id = model.selectedBoard, let board = model.catalog.board(id) { BoardCanvas(board: board) } else { AssetBrowser() }
                }
                .frame(minWidth: 400, maxWidth: .infinity)
                .safeAreaInset(edge: .top, spacing: 0) {
                    if let lapsed = model.rightsNotice { RightsNoticeBanner(issues: lapsed).transition(.move(edge: .top).combined(with: .opacity)) }
                }
                if model.showInspector {
                    InspectorResizeHandle(width: $inspectorWidth)
                    Group {
                        if model.selection.count > 1 { BatchInspector(assets: model.selectedAssets) }
                        else if let asset = model.focused { Inspector(asset: asset) }
                        else { EmptyInspector() }
                    }
                    .frame(width: min(420, max(290, inspectorWidth)))
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.18), value: model.showInspector)
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
                Button { model.showInspector.toggle() } label: { Label("Inspector", systemImage: "sidebar.right") }
                    .keyboardShortcut("i", modifiers: [.command, .option])
                    .help(model.showInspector ? "Hide the inspector (⌥⌘I)" : "Show the inspector (⌥⌘I)")
            }
        }
        .confirmationDialog("Remove \(model.pendingRemoval.count) asset\(model.pendingRemoval.count == 1 ? "" : "s") from the library?",
                            isPresented: Binding(get: { !model.pendingRemoval.isEmpty }, set: { if !$0 { model.pendingRemoval = [] } })) {
            Button("Remove from Library", role: .destructive) { model.confirmRemoval() }
            Button("Cancel", role: .cancel) { model.pendingRemoval = [] }
        } message: { Text("Files on disk stay where they are.") }
        .sheet(item: $model.smartEditor) { state in SmartEditor(state: state).environmentObject(model) }
        .sheet(item: $model.cropping) { st in CropSheet(state: st).environmentObject(model) }
        .sheet(item: $model.placing) { st in PlaceMockupSheet(state: st).environmentObject(model) }
        .sheet(item: $model.batchPlacement) { st in BatchPlaceSheet(state: st).environmentObject(model) }
        .sheet(item: $model.sheetPreview) { p in ContactSheetPreview(preview: p).environmentObject(model) }
        .sheet(item: $model.rightsWarning) { w in RightsWarningSheet(warning: w).environmentObject(model) }
        .sheet(item: $model.presetDraft) { d in PresetSaveSheet(draft: d).environmentObject(model) }
        .quickLookPreview($model.quickLookURL)
        .sheet(item: $model.presetExport) { st in PresetExportSheet(state: st).environmentObject(model) }
        .sheet(item: $model.batchRename) { st in BatchRenameSheet(state: st).environmentObject(model) }
        .sheet(isPresented: Binding(get: { model.duplicates != nil }, set: { if !$0 { model.duplicates = nil } })) {
            DuplicatesSheet().environmentObject(model)
        }
        .sheet(isPresented: $model.healthOpen) { LibraryHealthSheet().environmentObject(model) }
        .overlay {
            if let id = model.viewerID, let asset = model.catalog.assets.first(where: { $0.id == id }) {
                AssetViewer(asset: asset).transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.16), value: model.viewerID)
        .overlay {
            if model.compare != nil { CompareView().transition(.opacity) }
        }
        .overlay {
            if let id = model.presenting, let board = model.catalog.board(id) { PresentView(board: board).transition(.opacity) }
        }
        .animation(.easeOut(duration: 0.2), value: model.presenting)
        .animation(.easeOut(duration: 0.16), value: model.compare != nil)
        .overlay {
            if model.cull != nil { CullView().transition(.opacity) }
        }
        .animation(.easeOut(duration: 0.16), value: model.cull != nil)
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                Text(toast).font(.callout.weight(.medium)).padding(.horizontal, 16).padding(.vertical, 9)
                    .background(.ultraThinMaterial, in: Capsule()).overlay(Capsule().stroke(Theme.hairline))
                    .padding(.bottom, 62).transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.toast)
    }
}

struct Sidebar: View {
    @EnvironmentObject var model: StudioLibrary
    @State private var renameText = ""
    @State private var renameKeywordText = ""
    @State private var renameBoardText = ""
    @State private var templateNameText = ""
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
                    SidebarRow(title: StudioCatalog.allAssets, symbol: "square.grid.2x2", count: model.catalog.count(in: StudioCatalog.allAssets), selected: model.selectedBoard == nil && model.selectedSmart == nil && model.selectedCollection == StudioCatalog.allAssets) { model.show(collection: StudioCatalog.allAssets) }
                    SidebarRow(title: StudioCatalog.favorites, symbol: "heart.fill", count: model.catalog.count(in: StudioCatalog.favorites), selected: model.selectedBoard == nil && model.selectedSmart == nil && model.selectedCollection == StudioCatalog.favorites, dropTarget: StudioCatalog.favorites) { model.show(collection: StudioCatalog.favorites) }
                    if !model.missing.isEmpty {
                        SidebarRow(title: StudioLibrary.missingCollection, symbol: "exclamationmark.triangle", count: model.missing.count, selected: model.selectedBoard == nil && model.selectedSmart == nil && model.selectedCollection == StudioLibrary.missingCollection, accent: .warning) { model.show(collection: StudioLibrary.missingCollection) }
                            .contextMenu { Button("Remove All Missing from Library…", role: .destructive) { model.removeMissing() } }
                    }
                    let alerts = model.catalog.rightsAlertCounts()
                    if alerts.expiring + alerts.expired > 0 {
                        let target = model.catalog.smartCollections.first { $0.name == (alerts.expired > 0 ? "Rights Expired" : "Rights Expiring") }
                        SidebarRow(title: "Rights to Check", symbol: alerts.expired > 0 ? "exclamationmark.octagon" : "clock.badge.exclamationmark",
                                   count: alerts.expiring + alerts.expired, selected: target != nil && model.selectedSmart == target?.id, accent: .warning,
                                   badge: alerts.expired > 0 ? Theme.danger : Theme.warning) {
                            if let target { model.show(smart: target.id) } else { model.show(collection: StudioCatalog.allAssets) }
                        }
                        .help("\(alerts.expired) expired · \(alerts.expiring) ending within \(StudioAsset.rightsWarningDays) days")
                    }
                    let issues = model.health?.issueCount ?? 0
                    SidebarRow(title: "Library Health", symbol: issues > 0 ? "stethoscope" : "checkmark.seal", count: issues > 0 ? issues : nil,
                               selected: model.healthOpen, accent: issues > 0 ? .warning : .standard, badge: (model.health?.urgentCount ?? 0) > 0 ? Theme.danger : nil) {
                        model.openLibraryHealth()
                    }
                    .help(issues > 0 ? "\(issues) things to look at" : "Check files, license paperwork and duplicates")
                }

                SidebarSection(title: "COLLECTIONS", trailing: AnyView(
                    Button { model.newCollection(with: []) } label: { Image(systemName: "plus").font(.caption.bold()) }.buttonStyle(.plain).foregroundStyle(.secondary).help("New collection")
                )) {
                    ForEach(model.catalog.collections.filter { $0 != StudioCatalog.allAssets && $0 != StudioCatalog.favorites }, id: \.self) { name in
                        SidebarRow(title: name, symbol: symbol(for: name), count: model.catalog.count(in: name), selected: model.selectedBoard == nil && model.selectedSmart == nil && model.selectedCollection == name, dropTarget: name) { model.show(collection: name) }
                            .contextMenu {
                                Button("Rename…") { renameText = name; model.renamingCollection = name }
                                Button("Contact Sheet & Brand Kit…") { model.openContactSheet(ids: model.catalog.assets.filter { $0.collection == name }.map(\.id), title: name) }
                                Button("Rights Report…") { model.exportRightsReport(model.catalog.assets.filter { $0.collection == name }.map(\.id), title: name) }
                                Button("New Board from Collection") { model.newBoard(named: name, assets: model.catalog.assets.filter { $0.collection == name }.map(\.id)) }
                                Button("Show") { model.show(collection: name) }
                            }
                    }
                }

                SidebarSection(title: "BOARDS", trailing: AnyView(
                    Menu {
                        Button("Blank Board") { model.newBoard(with: []) }
                        Button("From Template…") { model.templatePickerOpen = true }
                    } label: { Image(systemName: "plus").font(.caption.bold()) }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().foregroundStyle(.secondary).help("New moodboard")
                )) {
                    ForEach(model.catalog.boards) { board in
                        SidebarRow(title: board.name, symbol: "rectangle.3.group", count: board.items.count, selected: model.selectedBoard == board.id, boardDrop: board.id) { model.show(board: board.id) }
                            .contextMenu {
                                Button("Present") { model.show(board: board.id); model.startPresenting(board.id) }
                                Button("Duplicate Board") { model.duplicateBoard(board.id) }
                                Button("Share as Review Gallery…") { model.shareBoardGallery(board.id) }
                                Divider()
                                Button("Rename…") { renameBoardText = board.name; model.renamingBoard = board.id }
                                Button("Save as Template…") { templateNameText = board.name; model.savingTemplate = board.id }
                                Button("Export PNG…") { model.exportBoard(board.id, pdf: false) }
                                Button("Export PDF…") { model.exportBoard(board.id, pdf: true) }
                                Divider()
                                Button("Delete Board", role: .destructive) { model.deleteBoard(board.id) }
                            }
                    }
                    if model.catalog.boards.isEmpty {
                        Text("Lay out assets, notes and palettes on a free canvas.").font(.caption2).foregroundStyle(.tertiary).padding(.horizontal, 9)
                    }
                }

                SidebarSection(title: "SMART COLLECTIONS", trailing: AnyView(
                    Button { model.beginNewSmart() } label: { Image(systemName: "plus").font(.caption.bold()) }.buttonStyle(.plain).foregroundStyle(.secondary).help("New smart collection")
                )) {
                    ForEach(model.catalog.smartCollections) { smart in
                        let n = model.catalog.smartAssets(smart.id).count
                        let badge: Color? = n == 0 ? nil : smart.rules.rights == .expired ? Theme.danger : smart.rules.rights == .expiringSoon ? Theme.warning : nil
                        SidebarRow(title: smart.name, symbol: smart.symbol, count: n, selected: model.selectedSmart == smart.id, accent: .smart, badge: badge) { model.show(smart: smart.id) }
                            .contextMenu {
                                Button("Edit Rules…") { model.beginEdit(smart: smart.id) }
                                Button("Rights Report…") { model.exportRightsReport(model.catalog.smartAssets(smart.id).map(\.id), title: smart.name) }
                                Button("Contact Sheet & Brand Kit…") { model.openContactSheet(ids: model.catalog.smartAssets(smart.id).map(\.id), title: smart.name) }
                                Button("New Board from Smart Collection") { model.newBoard(named: smart.name, assets: model.catalog.smartAssets(smart.id).map(\.id)) }
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
        .alert("Rename Board", isPresented: Binding(get: { model.renamingBoard != nil }, set: { if !$0 { model.renamingBoard = nil } })) {
            TextField("Board name", text: $renameBoardText)
            Button("Rename") { if let id = model.renamingBoard { model.renameBoard(id, to: renameBoardText) }; model.renamingBoard = nil }
            Button("Cancel", role: .cancel) { model.renamingBoard = nil }
        }
        .alert("Save as Template", isPresented: Binding(get: { model.savingTemplate != nil }, set: { if !$0 { model.savingTemplate = nil } })) {
            TextField("Template name", text: $templateNameText)
            Button("Save") { if let id = model.savingTemplate { model.saveTemplate(id, named: templateNameText) }; model.savingTemplate = nil }
            Button("Cancel", role: .cancel) { model.savingTemplate = nil }
        } message: { Text("Sections, headings, notes, palettes and arrows are kept. Every image becomes an empty slot of the same size.") }
        .sheet(isPresented: $model.templatePickerOpen) { TemplatePickerSheet().environmentObject(model) }
        .sheet(item: $model.pendingFeedback) { p in FeedbackPreviewSheet(pending: p).environmentObject(model) }
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
    var boardDrop: UUID? = nil
    var accent: RowAccent = .standard
    /// Colors the count when it needs attention (1.26 rights alerts).
    var badge: Color? = nil
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
                // Never wraps: the title truncates first (1.18 caught "11" stacking as 1/1 beside a long board name).
                Text("\(count)").font(.caption2.monospacedDigit().weight(badge == nil ? .regular : .bold))
                    .foregroundStyle(badge == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.black.opacity(0.85))).lineLimit(1).fixedSize()
                    .padding(.horizontal, 6).padding(.vertical, 2).background(badge ?? Color.white.opacity(0.06), in: Capsule())
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(targeted ? Theme.accent.opacity(0.38) : selected ? Theme.accent.opacity(0.2) : hovering ? Color.white.opacity(0.045) : .clear))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(targeted ? Theme.accent : .clear, lineWidth: 1.5))
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .onHover { hovering = $0 }
        .help(title)
        if let boardDrop {
            row.onDrop(of: [UTType.asssetsSelection], isTargeted: $targeted) { providers in model.dropSelection(providers, onBoard: boardDrop, at: nil) }
        } else if let dropTarget {
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
                    ColorSearchButton()
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
                        if let q = model.colorQuery {
                            Button { model.clearColorSearch() } label: {
                                HStack(spacing: 5) {
                                    Circle().fill(Color(hex: q.hex)).frame(width: 11, height: 11).overlay(Circle().stroke(Color.white.opacity(0.6)))
                                    Text(q.hex).font(.system(size: 11, weight: .semibold, design: .monospaced)).lineLimit(1)
                                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                                }
                                .padding(.horizontal, 9).padding(.vertical, 5)
                                .background(Color(hex: q.hex).opacity(0.28), in: Capsule()).overlay(Capsule().stroke(Color(hex: q.hex)))
                            }.buttonStyle(.plain).help("Ranked by how close each palette is to \(q.hex). Click to stop filtering by color.")
                        }
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
        Menu("Add to Board") {
            ForEach(model.catalog.boards) { b in Button(b.name) { model.addToBoard(b.id, ids: ids) } }
            if !model.catalog.boards.isEmpty { Divider() }
            Button("New Board from \(many ? "Selection" : "Asset")") { model.newBoard(with: ids) }
        }
        Divider()
        if primary.importedPath != nil {
            Button("Open") { model.open(primary) }
            Button("Reveal in Finder") { model.reveal(ids) }
        }
        if !many && primary.kind != .audio { Button("Find Similar") { model.findSimilar(primary.id) } }
        if !many && model.canPlace(primary) { Button("Place into Mockup…") { model.openPlaceIntoMockup(primary.id) } }
        if many && model.canBatchPlace { Button("Batch Place into Mockup…") { model.openBatchPlacement() } }
        if !many && primary.placementRecipe != nil { Button("Edit Placement…") { model.editPlacement(primary) } }
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
                    Text("Color").foregroundStyle(.secondary)
                    SmartColorRule(color: $state.rules.color)
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
                        Spacer(minLength: 12)
                        // Shares the label row since 1.15, which keeps the editor's height with the new Color row.
                        Toggle("Favorites only", isOn: $state.rules.favoritesOnly)
                    }
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

    static func render(title: String, assets: [StudioAsset], to url: URL, credits: [CreditLine] = []) async -> Bool {
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
        let total = sheet.totalPages + (credits.isEmpty ? 0 : 1)

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
        // Credits (1.25): who made what, and how it is licensed.
        if !credits.isEmpty {
            ctx.beginPDFPage(nil)
            fill(CGRect(x: 0, y: 0, width: W, height: H), bg)
            text(title, 36, 30, size: 15, weight: .bold, width: 500)
            text("\(total) of \(total)", W - 236, 32, size: 9, color: NSColor(white: 1, alpha: 0.45), width: 200, align: .right)
            text("CREDITS", 36, 76, size: 9, weight: .bold, color: accent, kern: 1.6)
            var y = 100.0
            for c in credits where y < H - 70 {
                text(c.credit, 36, y, size: 11, weight: .semibold, width: 220)
                text(c.license, 264, y + 1, size: 9, color: NSColor(white: 1, alpha: 0.55), width: 110)
                text(c.titles.joined(separator: ", "), 380, y + 1, size: 9, color: NSColor(white: 1, alpha: 0.7), width: W - 416)
                y += 26
                fill(CGRect(x: 36, y: H - y + 8, width: W - 72, height: 0.5), NSColor(white: 1, alpha: 0.1))
            }
            text("Keep these credits with any use of the images.", 36, H - 40, size: 8, color: NSColor(white: 1, alpha: 0.35))
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
                         : "\(scan.groups.count) \(scan.groups.count == 1 ? "set" : "sets") of \(scan.near ? "identical or look-alike" : "identical") files among \(scan.checked). Pick the copy to keep; everything on the others moves onto it. Files on disk stay.")
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
            HStack(spacing: 12) {
                if !scan.groups.isEmpty {
                    let ready = scan.groups.filter(model.mergeReady).count
                    Button { model.keepSuggestedForAll() } label: { Label(ready == scan.groups.count ? "Merge All \(ready)" : "Merge \(ready) Ready", systemImage: "arrow.triangle.merge") }
                        .buttonStyle(.borderedProminent).disabled(ready == 0)
                        .help("Merges each set into its picked copy. Ratings, labels, rights, license files, notes, stacks and board cards move over.")
                    if ready < scan.groups.count {
                        Label("\(scan.groups.count - ready) waiting for a rights choice", systemImage: "exclamationmark.shield").font(.caption).foregroundStyle(Theme.warning)
                    }
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
        let keeper = model.keeper(for: group)
        let plan = model.mergePlan(for: group)
        let conflict = plan?.hasRightsConflict == true
        let chosenRights = model.duplicateRights[group[0]]
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("\(members.count) copies").font(.system(size: 12, weight: .bold))
                Text("Click the one to keep").font(.caption).foregroundStyle(.tertiary)
                Spacer()
                if conflict {
                    Label("Rights differ", systemImage: "exclamationmark.shield.fill").font(.system(size: 10.5, weight: .bold)).foregroundStyle(Theme.danger)
                        .padding(.horizontal, 8).padding(.vertical, 3).background(Theme.danger.opacity(0.14), in: Capsule())
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(members) { a in DuplicateCopyCard(asset: a, keep: a.id == keeper, rightsWin: conflict && plan?.rightsFrom == a.id) {
                        model.duplicateKeeper[group[0]] = a.id
                    } }
                }
            }
            if let plan { MergeSummary(plan: plan, keeperTitle: members.first { $0.id == plan.keeper }?.title ?? "", sourceTitle: plan.rightsFrom.flatMap { id in members.first { $0.id == id }?.title }, rightsChosen: chosenRights != nil) }
            if conflict {
                VStack(alignment: .leading, spacing: 6) {
                    Text("These copies carry different rights. Choose which to keep; the others' rights are dropped.").font(.caption).foregroundStyle(.secondary)
                    WrapLayout(spacing: 6) {
                        ForEach(members.filter { $0.rights != nil }) { a in
                            let on = chosenRights == a.id
                            Button { model.duplicateRights[group[0]] = a.id } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: on ? "largecircle.fill.circle" : "circle").font(.system(size: 10))
                                    Image(systemName: a.rights!.license.symbol).font(.system(size: 10))
                                    Text(a.rights!.license.rawValue + (a.rights!.source.isEmpty ? "" : " · " + a.rights!.source)).font(.caption).lineLimit(1)
                                }
                                .padding(.horizontal, 9).padding(.vertical, 5)
                                .background(on ? Theme.accent.opacity(0.22) : Color.white.opacity(0.05), in: Capsule())
                                .overlay(Capsule().stroke(on ? Theme.accent : Theme.hairline))
                            }.buttonStyle(.plain).help("From \(a.title)")
                        }
                    }
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.danger.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.danger.opacity(0.3)))
            }
            HStack {
                Spacer()
                if let k = keeper, let title = members.first(where: { $0.id == k })?.title {
                    Button { model.keep(k, in: group) } label: { Label("Merge into \(title)", systemImage: "arrow.triangle.merge").lineLimit(1) }
                        .buttonStyle(.bordered).tint(Theme.accent).controlSize(.small)
                        .disabled(!model.mergeReady(group))
                        .help(model.mergeReady(group) ? "Keep this copy and remove the others from the library" : "Choose whose rights to keep first")
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.raised))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(conflict && chosenRights == nil ? Theme.danger.opacity(0.45) : Theme.hairline))
    }
}

/// One copy in a duplicate set: what it carries, and whether it is the one staying.
struct DuplicateCopyCard: View {
    @EnvironmentObject var model: StudioLibrary
    let asset: StudioAsset
    let keep: Bool
    let rightsWin: Bool
    let pick: () -> Void
    var body: some View {
        let cards = model.catalog.boards.reduce(0) { n, b in n + b.items.filter { $0.kind == .asset && $0.assetID == asset.id }.count }
        Button(action: pick) {
            VStack(alignment: .leading, spacing: 5) {
                Thumbnail(asset: asset, pixels: 320).frame(width: 156, height: 100).clipShape(RoundedRectangle(cornerRadius: 8))
                    .opacity(keep ? 1 : 0.55)
                    .overlay(alignment: .topLeading) {
                        Text(keep ? "KEEP" : "REMOVE").font(.system(size: 9, weight: .heavy)).tracking(0.8)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(keep ? Theme.accent : Color.black.opacity(0.6), in: Capsule()).foregroundStyle(.white).padding(6)
                    }
                Text(asset.title).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
                Text(asset.importedPath.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? asset.collection).font(.system(size: 9.5).monospaced()).foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.middle)
                HStack(spacing: 6) {
                    if asset.rating > 0 { Text(String(repeating: "★", count: asset.rating)).font(.system(size: 9.5)).foregroundStyle(Theme.warning) }
                    if let l = asset.label { Circle().fill(Color(hex: l.hex)).frame(width: 8, height: 8) }
                    if asset.favorite { Image(systemName: "heart.fill").font(.system(size: 9)).foregroundStyle(.pink) }
                    if let r = asset.rights { Image(systemName: r.license.symbol).font(.system(size: 9.5)).foregroundStyle(rightsWin ? Theme.accent : Color.secondary).help(r.license.rawValue) }
                    if !asset.licenseDocs.isEmpty { Label("\(asset.licenseDocs.count)", systemImage: "paperclip").font(.system(size: 9.5)).foregroundStyle(.secondary) }
                    if cards > 0 { Label("\(cards)", systemImage: "rectangle.on.rectangle").font(.system(size: 9.5)).foregroundStyle(.secondary).help("On \(cards) board \(cards == 1 ? "card" : "cards")") }
                    if asset.rating == 0 && asset.label == nil && !asset.favorite && asset.rights == nil && asset.licenseDocs.isEmpty && cards == 0 {
                        Text("No ratings, rights or boards").font(.system(size: 9.5)).foregroundStyle(.tertiary)
                    }
                }.frame(height: 12)
            }
            .frame(width: 156)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 11).fill(keep ? Theme.accent.opacity(0.1) : Color.black.opacity(0.18)))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(keep ? Theme.accent : Theme.hairline, lineWidth: keep ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
    }
}

/// "What moves over": the merge spelled out before it happens.
struct MergeSummary: View {
    let plan: MergePreview
    let keeperTitle: String
    let sourceTitle: String?
    var rightsChosen = false
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "arrow.triangle.merge").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accent).padding(.top, 4)
            if plan.keeperUnchanged {
                Text("Nothing to move over. \(plan.removing == 1 ? "The copy leaves" : "The copies leave") the library; \(keeperTitle) stays as it is.")
                    .font(.caption).foregroundStyle(.secondary).padding(.top, 3)
            } else {
                WrapLayout(spacing: 6) {
                    if plan.ratingRaised { chip(String(repeating: "★", count: plan.rating) + " rating", "star.fill") }
                    if plan.labelAdopted, let l = plan.label { chip(l.name + " label", "circle.fill", tint: Color(hex: l.hex)) }
                    if plan.becomesFavorite { chip("Favorite", "heart.fill") }
                    if !plan.tagsAdded.isEmpty { chip("+\(plan.tagsAdded.count) \(plan.tagsAdded.count == 1 ? "tag" : "tags")", "tag") }
                    if let c = plan.collection { chip("Filed in \(c)", "folder") }
                    if plan.hasRightsConflict && !rightsChosen { chip("Rights: choose below", "exclamationmark.shield", tint: Theme.danger) }
                    else if plan.rightsAdopted, let r = plan.rights { chip("Rights: \(r.license.rawValue)" + (sourceTitle.map { " from \($0)" } ?? ""), r.license.symbol) }
                    if plan.licenseFilesAdded > 0 { chip("\(plan.licenseFilesAdded) license \(plan.licenseFilesAdded == 1 ? "file" : "files")", "paperclip") }
                    if plan.notesAdded > 0 { chip("\(plan.notesAdded) client \(plan.notesAdded == 1 ? "note" : "notes")", "text.bubble") }
                    if plan.boardCardsMoved > 0 { chip("\(plan.boardCardsMoved) board \(plan.boardCardsMoved == 1 ? "card follows" : "cards follow")", "rectangle.on.rectangle") }
                    if plan.joinsStack { chip("Joins version stack", "square.stack.3d.up") }
                }
            }
        }
    }
    private func chip(_ text: String, _ symbol: String, tint: Color = Theme.accent) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 9, weight: .semibold)).foregroundStyle(tint)
            Text(text).font(.system(size: 10.5, weight: .medium)).lineLimit(1)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Theme.accent.opacity(0.1), in: Capsule())
        .overlay(Capsule().stroke(Theme.accent.opacity(0.3)))
    }
}

/// Library Health (1.28): what needs attention, each with the fix one click away.
struct LibraryHealthSheet: View {
    @EnvironmentObject var model: StudioLibrary
    var body: some View {
        let h = model.health ?? LibraryHealth()
        let byID = Dictionary(uniqueKeysWithValues: model.catalog.assets.map { ($0.id, $0) })
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle().fill((h.isHealthy ? Theme.watch : h.urgentCount > 0 ? Theme.danger : Theme.warning).opacity(0.16)).frame(width: 46, height: 46)
                    Image(systemName: h.isHealthy ? "checkmark.seal.fill" : "stethoscope").font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(h.isHealthy ? Theme.watch : h.urgentCount > 0 ? Theme.danger : Theme.warning)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Library Health").font(.system(size: 20, weight: .bold))
                    Text(model.healthScanning && model.health == nil ? "Checking files…"
                         : h.isHealthy ? "Everything checks out across \(model.catalog.assets.count) assets."
                         : "\(h.issueCount) \(h.issueCount == 1 ? "thing needs" : "things need") a look" + (h.urgentCount > 0 ? ", \(h.urgentCount) of them can't open right now." : "."))
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if model.healthScanning { ProgressView().controlSize(.small) }
                Button { model.refreshHealth(full: true) } label: { Label("Check Again", systemImage: "arrow.clockwise") }.controlSize(.small).disabled(model.healthScanning)
            }
            .padding(20)
            .alert("Refresh changed source?", isPresented: Binding(get: { model.reviewedSourceID != nil },
                set: { if !$0 { model.reviewedSourceID = nil; model.sourceReviewPreview = nil } })) {
                Button("Cancel", role: .cancel) { model.reviewedSourceID = nil; model.sourceReviewPreview = nil }
                Button("Refresh Source") {
                    if let id = model.reviewedSourceID { model.refreshChangedSource(id) }
                    model.reviewedSourceID = nil
                }
            } message: {
                let p = model.sourceReviewPreview
                let a = model.catalog.assets.first { $0.id == model.reviewedSourceID }
                Text("\(a?.title ?? "Source") at \((p?.path as NSString?)?.abbreviatingWithTildeInPath ?? "unknown path")\nSize: \(p.map { ByteCountFormatter.string(fromByteCount: $0.baseline.size, countStyle: .file) } ?? "?") → \(p.map { ByteCountFormatter.string(fromByteCount: $0.current.size, countStyle: .file) } ?? "?")\nFile facts: \(p?.beforeResolution ?? "?") → \(p?.afterResolution ?? "?")\nPalette: \(p?.beforePalette.prefix(3).joined(separator: ", ") ?? "?") → \(p?.afterPalette.prefix(3).joined(separator: ", ") ?? "?")\nThe new bytes get the preview. ID, rights, boards and placed versions remain. The receipt saves metadata, not old bytes; this cannot restore the old file.")
            }
            Divider().overlay(Theme.hairline)
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !h.missingFiles.isEmpty {
                        HealthCard(symbol: "exclamationmark.triangle.fill", tint: Theme.danger, title: "\(h.missingFiles.count) missing \(h.missingFiles.count == 1 ? "file" : "files")",
                                   detail: "Moved or deleted outside ASSSETS. Relink a moved folder or locate files one by one; tags, rights and boards stay.",
                                   action: ("Relink Folder…", { model.folderRelinkOpen = true })) {
                            ForEach(h.missingFiles.prefix(3), id: \.self) { id in
                                if let a = byID[id] {
                                    HealthRow(asset: a, detail: a.importedPath.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "") {
                                        Button("Locate…") { model.locate(id); model.refreshHealth() }.controlSize(.small)
                                    }
                                }
                            }
                        }
                    }
                    if !h.changedSources.isEmpty {
                        SourceReviewQueueCard(byID: byID).id("source-review-queue")
                    }
                    if !h.missingLicenseFiles.isEmpty {
                        let docs = h.missingLicenseFiles.compactMap { model.catalog.licenseDoc($0) }
                        HealthCard(symbol: "doc.badge.ellipsis", tint: Theme.danger, title: "\(docs.count) license \(docs.count == 1 ? "file is" : "files are") gone",
                                   detail: "The record is there but the stored copy was deleted from the Licenses folder. Attach it again, or detach the empty record.",
                                   action: ("Detach \(docs.count)", { model.forgetMissingLicenseFiles() })) {
                            ForEach(docs) { d in
                                let on = model.catalog.assets.filter { $0.licenseDocs.contains(d.id) }
                                HealthDocRow(name: d.name, detail: on.isEmpty ? "On a rights preset" : "On " + on.prefix(2).map(\.title).joined(separator: ", ") + (on.count > 2 ? " +\(on.count - 2)" : ""))
                            }
                        }
                    }
                    if let sets = h.duplicateSets, sets > 0 {
                        HealthCard(symbol: "square.on.square", tint: Theme.warning, title: "\(sets) \(sets == 1 ? "set" : "sets") of identical files",
                                   detail: "The same file indexed more than once. Merging keeps one copy and moves ratings, rights, license files and board cards onto it.",
                                   action: ("Review…", { model.reviewDuplicatesFromHealth() })) { EmptyView() }
                    }
                    if !h.noCredit.isEmpty {
                        HealthCard(symbol: "text.badge.xmark", tint: Theme.warning, title: "\(h.noCredit.count) licensed \(h.noCredit.count == 1 ? "asset has" : "assets have") no credit",
                                   detail: "Credits print on galleries, round summaries and contact sheets. Select them to fill the credit in once for all.",
                                   action: ("Select \(h.noCredit.count)", { model.showFromHealth(h.noCredit) })) {
                            ForEach(h.noCredit.prefix(3), id: \.self) { id in
                                if let a = byID[id] { HealthRow(asset: a, detail: (a.rights?.license.rawValue ?? "") + (a.rights.map { $0.source.isEmpty ? "" : " · " + $0.source } ?? "")) { EmptyView() } }
                            }
                        }
                    }
                    if h.licenseCleanupCount > 0 {
                        HealthCard(symbol: "paperclip.badge.ellipsis", tint: Theme.smart, title: "\(h.licenseCleanupCount) unused license \(h.licenseCleanupCount == 1 ? "file" : "files")",
                                   detail: "In the Licenses folder but not attached to any asset or preset.",
                                   action: ("Clean Up", { model.cleanUpLicenseFolder() })) {
                            ForEach((h.unusedLicenseFiles.compactMap { model.catalog.licenseDoc($0)?.name } + h.strayLicenseFiles).prefix(3), id: \.self) { n in
                                HealthDocRow(name: n, detail: "Not attached")
                            }
                        }
                    }
                    if !h.bigFiles.isEmpty {
                        HealthCard(symbol: "externaldrive.badge.exclamationmark", tint: Theme.smart, title: "\(h.bigFiles.count) very large \(h.bigFiles.count == 1 ? "file" : "files")",
                                   detail: "Over \(ByteCountFormatter.string(fromByteCount: LibraryHealth.bigFileBytes, countStyle: .file)). They slow exports and galleries; consider a lighter version for sharing.",
                                   action: nil) {
                            ForEach(h.bigFiles.prefix(3), id: \.id) { f in
                                if let a = byID[f.id] {
                                    HealthRow(asset: a, detail: ByteCountFormatter.string(fromByteCount: f.bytes, countStyle: .file)) {
                                        Button { model.reveal([f.id]) } label: { Image(systemName: "folder") }.controlSize(.small).help("Reveal in Finder")
                                    }
                                }
                            }
                        }
                    }
                    if !model.catalog.sourceRefreshHistory.isEmpty {
                        HealthCard(symbol: "clock.arrow.circlepath", tint: Theme.accent,
                                   title: "Source refresh history · \(model.catalog.sourceRefreshHistory.count)",
                                   detail: "Catalog receipts only. Old source bytes are not saved or recoverable here.",
                                   action: model.catalog.sourceRefreshHistory.count > 5
                                       ? (model.sourceHistoryExpanded ? "Show Recent" : "Show All", { model.sourceHistoryExpanded.toggle() }) : nil) {
                            ForEach(Array(model.catalog.sourceRefreshHistory.reversed().prefix(model.sourceHistoryExpanded ? model.catalog.sourceRefreshHistory.count : 5))) { entry in
                                VStack(alignment: .leading, spacing: 3) {
                                    let title = byID[entry.assetID]?.title ?? "Removed asset"
                                    Text("\(title) · \(entry.refreshedAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text("\((entry.path as NSString).abbreviatingWithTildeInPath) · \(ByteCountFormatter.string(fromByteCount: entry.before.size, countStyle: .file)) → \(ByteCountFormatter.string(fromByteCount: entry.after.size, countStyle: .file)) · \(entry.beforeResolution) → \(entry.afterResolution)")
                                        .font(.caption2).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
                                    Text("Palette: \(entry.beforePalette.prefix(3).joined(separator: ", ")) → \(entry.afterPalette.prefix(3).joined(separator: ", ")) · SHA-256: \(entry.before.sha256.prefix(10)) → \(entry.after.sha256.prefix(10))")
                                        .font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
                                }.padding(.leading, 42)
                            }
                        }
                    }
                    HealthAllClear(h: h, scanned: h.duplicateSets != nil)
                }
                .padding(20)
            }
            .onChange(of: model.sourceQueueAnchor) { _, anchor in
                if anchor != nil {
                    withAnimation { proxy.scrollTo("source-review-queue", anchor: .top) }
                    model.sourceQueueAnchor = nil
                }
            }
            }
            Divider().overlay(Theme.hairline)
            HStack {
                Text("Files on disk are only changed by Clean Up, which deletes unused copies in the library's Licenses folder.").font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Button("Done") { model.healthOpen = false }.keyboardShortcut(.cancelAction)
            }.padding(16)
        }
        .frame(minWidth: 720, idealWidth: 780, minHeight: 520, idealHeight: 640)
        .background(Theme.panel)
        .sheet(isPresented: $model.folderRelinkOpen) { FolderRelinkSheet().environmentObject(model) }
    }
}

/// Preview exact relative paths before changing any library identity or touching the disk.
struct FolderRelinkSheet: View {
    @EnvironmentObject var model: StudioLibrary
    @State private var oldRoot = ""
    @State private var newRoot = ""
    @State private var matchedOpen = true
    @State private var unmatchedOpen = true
    @State private var ambiguousOpen = true
    var body: some View {
        let preview = model.folderRelinkPreview
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "folder.badge.arrow.forward").foregroundStyle(Theme.accent)
                Text("Relink Moved Folder").font(.system(size: 18, weight: .bold))
                Spacer()
                Text("Preview first · files on disk stay put").font(.caption).foregroundStyle(.secondary)
            }
            Text("Use the old folder path and the folder holding its files now. ASSSETS checks the same relative path under the new folder. It never searches by filename.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("Old folder").frame(width: 85, alignment: .leading)
                TextField("/old/project", text: $oldRoot).textFieldStyle(.roundedBorder)
            }
            HStack {
                Text("New folder").frame(width: 85, alignment: .leading)
                TextField("/new/project", text: $newRoot).textFieldStyle(.roundedBorder)
                Button("Choose…") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.prompt = "Use Folder"
                    if panel.runModal() == .OK, let url = panel.url { newRoot = url.standardizedFileURL.path; model.folderRelinkPreview = nil }
                }
            }
            HStack {
                Button("Preview Exact Paths") {
                    model.previewFolderRelink(oldRoot: oldRoot, newRoot: newRoot)
                }.disabled(oldRoot.isEmpty || newRoot.isEmpty || !oldRoot.hasPrefix("/") || !newRoot.hasPrefix("/"))
                Spacer()
                if let preview {
                    Text("\(preview.matched.count) matched · \(preview.unmatched.count) unmatched · \(preview.ambiguous.count) ambiguous · \(preview.outOfScopeCount) outside old folder")
                        .font(.caption.weight(.semibold)).foregroundStyle(preview.ambiguous.isEmpty ? Theme.accent : Theme.warning)
                }
            }
            if let preview {
                if !preview.watchMoves.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Move \(preview.watchMoves.count) watched folder(s) with this relink", isOn: $model.folderRelinkMoveWatches)
                            .disabled(preview.watchIssue != nil)
                        ForEach(preview.watchMoves, id: \.oldPath) { move in
                            Text(move.oldPath + " → " + move.newPath)
                                .font(.caption2.monospaced()).lineLimit(1).truncationMode(.middle)
                                .foregroundStyle(.secondary)
                        }
                        if let issue = preview.watchIssue {
                            Text(issue).font(.caption2).foregroundStyle(Theme.warning)
                        } else {
                            Text("This changes the watched folder in the same undo step. Leave off to keep the old watch.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }.padding(8).background(Theme.raised, in: RoundedRectangle(cornerRadius: 7))
                } else if let issue = preview.watchIssue {
                    Text(issue).font(.caption2).foregroundStyle(Theme.warning)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 7) {
                        relinkSection("Unmatched", rows: preview.unmatched, tint: Theme.warning, expanded: $unmatchedOpen)
                        relinkSection("Ambiguous", rows: preview.ambiguous, tint: Theme.danger, expanded: $ambiguousOpen)
                        relinkSection("Matched", rows: preview.matched, tint: Theme.watch, expanded: $matchedOpen)
                    }
                }.frame(height: 265)
            } else {
                Text("No changes yet. Preview the proposed mappings before relinking.")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 315)
                    .background(Theme.raised, in: RoundedRectangle(cornerRadius: 8))
            }
            HStack {
                Text("Only matched paths and the selected watch change. Unmatched and ambiguous files stay.")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { model.folderRelinkOpen = false }.keyboardShortcut(.cancelAction)
                Button("Relink \(preview?.matched.count ?? 0) Matches") { model.applyFolderRelink() }
                    .buttonStyle(.borderedProminent).disabled(preview?.matched.isEmpty ?? true)
            }
        }
        .padding(20).frame(width: 780).background(Theme.backdrop)
        .onChange(of: oldRoot) { _, _ in model.folderRelinkPreview = nil }
        .onChange(of: newRoot) { _, _ in model.folderRelinkPreview = nil }
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("folder-relink-collapsed") { matchedOpen = false }
            if let preview = model.folderRelinkPreview {
                oldRoot = preview.oldRoot; newRoot = preview.newRoot
                // The onChange handlers run as part of the same render; the demo also rechecks the preview below.
                DispatchQueue.main.async { model.previewFolderRelink(oldRoot: preview.oldRoot, newRoot: preview.newRoot) }
            } else if oldRoot.isEmpty,
                      let missing = model.health?.missingFiles.compactMap({ id in model.catalog.assets.first { $0.id == id }?.importedPath }).first {
                oldRoot = URL(fileURLWithPath: missing).deletingLastPathComponent().path
            }
        }
    }

    private func relinkSection(_ title: String, rows: [FolderRelinkPreview.Row], tint: Color,
                               expanded: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Button { expanded.wrappedValue.toggle() } label: {
                HStack {
                    Image(systemName: expanded.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.bold)).frame(width: 15)
                    Circle().fill(tint).frame(width: 6, height: 6)
                    Text("\(title) · \(rows.count)").font(.caption.weight(.semibold))
                    Spacer()
                    Text(expanded.wrappedValue ? "Hide" : "Show").font(.caption2).foregroundStyle(.secondary)
                }
                .foregroundStyle(rows.isEmpty ? .secondary : .primary)
                .padding(.horizontal, 9).padding(.vertical, 7)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 7))
            }.buttonStyle(.plain).accessibilityLabel("\(title), \(rows.count) files, \(expanded.wrappedValue ? "expanded" : "collapsed")")
            if expanded.wrappedValue {
                if rows.isEmpty {
                    Text("No \(title.lowercased()) files")
                        .font(.caption2).foregroundStyle(.tertiary).padding(.leading, 16).padding(.vertical, 3)
                } else {
                    ForEach(rows) { row in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: row.status == .matched ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(tint)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.title).font(.caption.weight(.semibold))
                                Text(row.oldPath + " → " + row.newPath).font(.caption2.monospaced())
                                    .lineLimit(2).truncationMode(.middle).foregroundStyle(.secondary)
                                Text(row.status.rawValue.capitalized + " · " + row.reason).font(.caption2)
                                    .foregroundStyle(tint)
                            }
                            Spacer(minLength: 0)
                        }.padding(8).background(Theme.raised, in: RoundedRectangle(cornerRadius: 7))
                    }
                }
            }
        }
    }
}

struct SourceReviewQueueCard: View {
    @EnvironmentObject var model: StudioLibrary
    let byID: [UUID: StudioAsset]
    var body: some View {
        let queue = model.sourceReviewQueue
        HealthCard(symbol: "arrow.triangle.2.circlepath.circle.fill", tint: Theme.warning,
                   title: "Changed sources · \(queue.pending.count)",
                   detail: "Review each file before accepting new bytes. Nothing is refreshed in bulk.",
                   action: ("Check Again", { model.refreshHealth(full: true) })) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(queue.position.map { "\($0) of \(queue.pending.count)" } ?? "Queue empty")
                        .font(.caption.monospacedDigit()).foregroundStyle(Theme.warning)
                    Spacer()
                    Button(model.sourceQueueOpen ? "Show selected" : "Show queue") { model.sourceQueueOpen.toggle() }
                        .buttonStyle(.plain).font(.caption).foregroundStyle(Theme.accent)
                }.padding(.leading, 42)
                if model.sourceQueueOpen {
                    ForEach(queue.pending, id: \.self) { id in
                        if let asset = byID[id] {
                            Button { model.selectSourceInQueue(id) } label: {
                                HStack(spacing: 7) {
                                    Image(systemName: queue.selected == id ? "largecircle.fill.circle" : "circle")
                                        .foregroundStyle(queue.selected == id ? Theme.warning : Color.secondary)
                                    Text(asset.title).lineLimit(1)
                                    Spacer(minLength: 3)
                                    Text(asset.importedPath.map { ($0 as NSString).lastPathComponent } ?? "")
                                        .font(.caption2).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                                }.font(.caption)
                                .padding(7).background(queue.selected == id ? Theme.warning.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                            }.buttonStyle(.plain).padding(.leading, 42)
                        }
                    }
                }
                if let id = queue.selected, let asset = byID[id] {
                    HealthRow(asset: asset, detail: asset.importedPath ?? "") {
                        Button("Review…") { model.reviewChangedSource(id) }
                            .controlSize(.small).disabled(model.sourceRefreshBusy || model.healthScanning)
                    }
                    Text("Only this file is reviewed. After accepting it, the next pending file is selected; Cancel changes nothing.")
                        .font(.caption2).foregroundStyle(.secondary).padding(.leading, 42)
                }
                if let error = model.sourceRefreshError {
                    Text(error).font(.caption2).foregroundStyle(Theme.warning).padding(.leading, 42)
                }
            }
        }
    }
}

struct HealthCard<Rows: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String
    let action: (String, () -> Void)?
    @ViewBuilder let rows: Rows
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(tint)
                    .frame(width: 30, height: 30).background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13.5, weight: .bold))
                    Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if let action {
                    Button(action.0, action: action.1).buttonStyle(.bordered).controlSize(.small).tint(tint).fixedSize()
                }
            }
            rows
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.raised))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(tint.opacity(0.28)))
    }
}

struct HealthRow<Trailing: View>: View {
    let asset: StudioAsset
    let detail: String
    @ViewBuilder let trailing: Trailing
    var body: some View {
        HStack(spacing: 10) {
            Thumbnail(asset: asset, pixels: 120).frame(width: 44, height: 32).clipShape(RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 1) {
                Text(asset.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(detail).font(.caption2).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 6)
            trailing
        }
        .padding(.leading, 42)
    }
}

struct HealthDocRow: View {
    let name: String
    let detail: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: name.lowercased().hasSuffix(".pdf") ? "doc.richtext" : "doc").font(.system(size: 13)).foregroundStyle(.secondary)
                .frame(width: 44, height: 32).background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 12, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                Text(detail).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer(minLength: 6)
        }
        .padding(.leading, 42)
    }
}

/// The checks that passed, so an empty section doesn't read as "not checked".
struct HealthAllClear: View {
    let h: LibraryHealth
    let scanned: Bool
    var body: some View {
        let passed: [String] = [
            h.missingFiles.isEmpty ? "Every file opens" : nil,
            h.changedSources.isEmpty ? "No changed sources" : nil,
            h.missingLicenseFiles.isEmpty ? "License files in place" : nil,
            scanned && h.duplicateSets == 0 ? "No identical files" : nil,
            h.noCredit.isEmpty ? "Licensed assets credited" : nil,
            h.licenseCleanupCount == 0 ? "No unused license files" : nil,
            h.bigFiles.isEmpty ? "No oversized files" : nil,
        ].compactMap { $0 }
        if !passed.isEmpty {
            WrapLayout(spacing: 6) {
                ForEach(passed, id: \.self) { t in
                    Label(t, systemImage: "checkmark.circle.fill").font(.system(size: 10.5, weight: .medium)).foregroundStyle(Theme.watch)
                        .padding(.horizontal, 8).padding(.vertical, 4).background(Theme.watch.opacity(0.1), in: Capsule())
                }
            }.padding(.top, 4)
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

/// Per-asset view of accepted source metadata, linked to the live Library Health check.
struct SourceChangesSection: View {
    @EnvironmentObject var model: StudioLibrary
    let asset: StudioAsset
    @State private var expanded = false

    var body: some View {
        let entries = model.catalog.sourceHistory(for: asset.id)
        let unreviewed = model.health?.changedSources.contains(asset.id) == true
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                InspectorLabel(text: "SOURCE CHANGES")
                Spacer(minLength: 2)
                if !entries.isEmpty {
                    Text("\(entries.count)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            if unreviewed {
                Label("Source changed on disk, not yet reviewed", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            } else if model.healthScanning {
                Label("Checking source files…", systemImage: "arrow.clockwise").font(.caption).foregroundStyle(.secondary)
            } else if entries.isEmpty {
                Text("No source refreshes recorded. Earlier catalogs start with an empty history.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Button { model.openLibraryHealth() } label: {
                Label(unreviewed ? "Review in Library Health" : "Check in Library Health", systemImage: "stethoscope")
            }.buttonStyle(.bordered).controlSize(.small).tint(unreviewed ? Theme.warning : Theme.accent)
            ForEach(Array(entries.prefix(expanded ? entries.count : 3))) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.refreshedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption.weight(.semibold))
                    Text((entry.path as NSString).abbreviatingWithTildeInPath)
                        .font(.caption2.monospaced()).lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                    Text("\(ByteCountFormatter.string(fromByteCount: entry.before.size, countStyle: .file)) → \(ByteCountFormatter.string(fromByteCount: entry.after.size, countStyle: .file)) · \(entry.beforeResolution) → \(entry.afterResolution)")
                        .font(.caption2).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 3) {
                        ForEach(Array(entry.beforePalette.prefix(3).enumerated()), id: \.offset) { _, hex in
                            RoundedRectangle(cornerRadius: 2).fill(Color(hex: hex)).frame(width: 13, height: 13)
                        }
                        Image(systemName: "arrow.right").font(.system(size: 9)).padding(.horizontal, 2)
                        ForEach(Array(entry.afterPalette.prefix(3).enumerated()), id: \.offset) { _, hex in
                            RoundedRectangle(cornerRadius: 2).fill(Color(hex: hex)).frame(width: 13, height: 13)
                        }
                    }.accessibilityLabel("Palette changed from \(entry.beforePalette.prefix(3).joined(separator: ", ")) to \(entry.afterPalette.prefix(3).joined(separator: ", "))")
                    Text("SHA-256 \(entry.before.sha256.prefix(10)) → \(entry.after.sha256.prefix(10))")
                        .font(.caption2.monospaced()).lineLimit(1).truncationMode(.middle)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(9).background(Theme.raised, in: RoundedRectangle(cornerRadius: 8))
            }
            if entries.count > 3 {
                Button(expanded ? "Show recent" : "Show all \(entries.count) receipts") { expanded.toggle() }
                    .buttonStyle(.plain).font(.caption).foregroundStyle(Theme.accent)
            }
            Text("Receipts save metadata, not old file bytes. A prior source cannot be restored here.")
                .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accent.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.accent.opacity(0.25)))
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
                if let recipe = asset.placementRecipe {
                    let status = model.catalog.placementStatus(recipe, exists: { FileManager.default.fileExists(atPath: $0) })
                    if status != .ready(art: recipe.artID, mockup: recipe.mockupID) {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
                            Text(status == .missingArt(recipe.artID) ? "Source art missing" : "PSD mockup missing")
                                .font(.caption.weight(.semibold))
                            Spacer(minLength: 4)
                            Button("Relink…") { model.editPlacement(asset) }.controlSize(.small)
                        }
                        .padding(9).background(Theme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.warning.opacity(0.4)))
                        .padding(.horizontal, 14).padding(.top, 8)
                    }
                }
                if asset.kind != .audio { EffectStrip(asset: asset).padding(.top, 10) }
                Divider().overlay(Theme.hairline).padding(.top, 10)
                ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        RightsSection(asset: asset)
                        if !asset.isStarter && asset.importedPath != nil && asset.placementRecipe == nil {
                            SourceChangesSection(asset: asset).id("source-changes")
                        }
                        OnBoardsSection(asset: asset)
                        if asset.stackID != nil { VersionStrip(asset: asset) }
                        if asset.kind != .audio { SimilarStrip(asset: asset) }
                        if asset.placementRecipe != nil { PlacementRecipeStrip(asset: asset) }
                        if model.canPlace(asset) { PlaceStrip(asset: asset) }
                        if asset.importedPath?.lowercased().hasSuffix(".psd") == true { PsdLayersPanel(asset: asset) }
                        InspectorLabel(text: "COLOR PALETTE")
                        HStack(spacing: 5) {
                            ForEach(Array(asset.palette.prefix(5).enumerated()), id: \.offset) { _, hex in
                                VStack(spacing: 3) {
                                    Color(hex: hex).frame(height: 30).clipShape(RoundedRectangle(cornerRadius: 6))
                                    Text(hex).font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary)
                                }
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(model.colorQuery?.hex == hex ? Color.white : Color.clear, lineWidth: 2).frame(height: 30), alignment: .top)
                                .contentShape(Rectangle())
                                .onTapGesture { model.searchColor(hex) }
                                .help("Find assets with this color")
                                .contextMenu {
                                    Button("Find Assets with This Color") { model.searchColor(hex) }
                                    Button("Copy \(hex)") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(hex, forType: .string); model.flash("Copied \(hex)") }
                                }
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
                .onChange(of: model.inspectorAnchor) { _, anchor in
                    // CI sets its target after selecting the asset. Scroll then as well as at first appearance.
                    if let anchor {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation { proxy.scrollTo(anchor, anchor: .top) }
                        }
                    }
                }
                .onAppear {
                    // Demo only: bring the tag rows into view for the suggested-tags screenshot.
                    if let anchor = model.inspectorAnchor {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { withAnimation { proxy.scrollTo(anchor, anchor: .top) } }
                        return
                    }
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

/// Swatch button in the search field; opens the color picker popover (1.15).
struct ColorSearchButton: View {
    @EnvironmentObject var model: StudioLibrary
    var body: some View {
        Button { model.showColorPicker.toggle() } label: {
            Group {
                if let q = model.colorQuery {
                    Circle().fill(Color(hex: q.hex)).overlay(Circle().stroke(Color.white.opacity(0.7), lineWidth: 1.5))
                } else {
                    Circle().fill(AngularGradient(colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
                        .overlay(Circle().stroke(Color.white.opacity(0.25)))
                }
            }
            .frame(width: 16, height: 16)
            .padding(3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Search by color")
        .popover(isPresented: $model.showColorPicker, arrowEdge: .bottom) { ColorSearchPopover().environmentObject(model) }
    }
}

struct ColorSearchPopover: View {
    @EnvironmentObject var model: StudioLibrary
    @State private var hexText = ""
    var body: some View {
        let q = model.colorQuery
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Search by Color").font(.headline)
                Spacer()
                if q != nil { Button("Clear") { model.clearColorSearch() }.buttonStyle(.borderless).font(.caption) }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 8), count: 5), spacing: 8) {
                ForEach(ColorSearch.swatches, id: \.self) { h in swatch(h, size: 30) }
            }
            if !model.catalog.recentColors.isEmpty {
                InspectorLabel(text: "RECENT")
                HStack(spacing: 8) { ForEach(model.catalog.recentColors, id: \.self) { h in swatch(h, size: 22) } }
            }
            HStack(spacing: 8) {
                Button { model.sampleScreenColor() } label: { Label("Pick", systemImage: "eyedropper").fixedSize() }.help("Pick a color anywhere on screen")
                ColorPicker("", selection: Binding(
                    get: { Color(hex: q?.hex ?? "#808080") },
                    set: { model.searchColor(StudioLibrary.hex(NSColor($0)), remember: false) }), supportsOpacity: false)
                    .labelsHidden().help("Open the color panel")
                TextField("#4DABF7", text: $hexText).textFieldStyle(.roundedBorder).font(.callout.monospaced()).frame(width: 92)
                    .onSubmit { model.searchColor(hexText) }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    InspectorLabel(text: "TOLERANCE")
                    Spacer()
                    Text(q.map { "\($0.closeness.capitalized) · ΔE \(Int($0.tolerance))" } ?? "Pick a color").font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Slider(value: Binding(get: { q?.tolerance ?? ColorQuery.defaultTolerance }, set: { model.setColorTolerance($0) }), in: ColorQuery.toleranceRange)
                    .disabled(q == nil)
                HStack { Text("Close").font(.caption2); Spacer(); Text("Loose").font(.caption2) }.foregroundStyle(.tertiary)
            }
            if q != nil {
                let n = model.filtered.count
                Text("\(n) \(n == 1 ? "match" : "matches"), closest first").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 272)
        .onAppear { hexText = q?.hex ?? "" }
        .onChange(of: model.colorQuery?.hex) { _, h in hexText = h ?? "" }
    }

    private func swatch(_ h: String, size: CGFloat) -> some View {
        let on = model.colorQuery?.hex == h
        return Button { model.searchColor(h) } label: {
            RoundedRectangle(cornerRadius: size / 4).fill(Color(hex: h)).frame(width: size, height: size)
                .overlay(RoundedRectangle(cornerRadius: size / 4).stroke(on ? Color.white : Color.white.opacity(0.18), lineWidth: on ? 2.5 : 1))
        }.buttonStyle(.plain).help(h)
    }
}

/// The smart editor's "contains a color near" rule.
struct SmartColorRule: View {
    @Binding var color: ColorQuery?
    @EnvironmentObject var model: StudioLibrary
    /// Recent colors first, then the standard swatches, no repeats.
    private var choices: [String] {
        var out: [String] = []
        for h in model.catalog.recentColors + ColorSearch.swatches where !out.contains(h) { out.append(h) }
        return Array(out.prefix(14))
    }
    var body: some View {
        // One line, so the editor stays the same height as before on small screens.
        HStack(spacing: 7) {
            if let c = color {
                Circle().fill(Color(hex: c.hex)).frame(width: 18, height: 18).overlay(Circle().stroke(Color.white.opacity(0.6)))
                Text(c.hex).font(.callout.monospaced()).fixedSize()
                Slider(value: Binding(get: { c.tolerance }, set: { color = ColorQuery(hex: c.hex, tolerance: $0) }), in: ColorQuery.toleranceRange)
                    .frame(width: 96).help("Tolerance: \(c.closeness) (ΔE \(Int(c.tolerance)))")
                Button { color = nil } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary).help("Remove the color rule")
                Rectangle().fill(Theme.hairline).frame(width: 1, height: 14)
            } else {
                Text("Any").font(.caption).foregroundStyle(.secondary).fixedSize()
            }
            ForEach(Array(choices.prefix(color == nil ? 14 : 7)), id: \.self) { h in
                Button { color = ColorQuery(hex: h, tolerance: color?.tolerance ?? ColorQuery.defaultTolerance) } label: {
                    Circle().fill(Color(hex: h)).frame(width: 16, height: 16)
                        .overlay(Circle().stroke(color?.hex == h ? Color.white : Color.white.opacity(0.2), lineWidth: color?.hex == h ? 2 : 1))
                }.buttonStyle(.plain).help(h)
            }
            Spacer(minLength: 0)
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
        ScrollViewReader { proxy in
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
                BulkRightsSection(assets: assets)
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
                // Two rows so no label truncates at the 1024-wide inspector (1.28 caught "Sh…" and "Key…").
                HStack(spacing: 8) {
                    ExportMenuButton(ids: ids, title: "Export \(ids.count)")
                    ShareButton(ids: ids)
                }
                HStack(spacing: 8) {
                    Button { model.copyKeywords(ids) } label: { Label("Keywords", systemImage: "doc.on.doc") }.buttonStyle(.bordered)
                    Button { model.exportRightsReport(assets.map(\.id), title: "\(assets.count) Selected Assets") } label: { Label("Rights Report…", systemImage: "list.bullet.rectangle") }.buttonStyle(.bordered)
                }
                Button(role: .destructive) { model.pendingRemoval = ids } label: { Label("Remove from Library…", systemImage: "trash") }.buttonStyle(.borderless).padding(.top, 4)
            }
            .padding(16)
        }
        .onAppear {
            // Demo only: scroll a section into view for its screenshot.
            if let anchor = model.inspectorAnchor {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { withAnimation { proxy.scrollTo(anchor, anchor: .top) } }
            }
        }
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
    private var generations: [String: Int] = [:]

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
        let generation = generations[key, default: 0]
        Task.detached(priority: .userInitiated) {
            let img = await MediaRenderer.thumbnail(for: snapshot, maxPixel: pixels)
            await MainActor.run {
                guard self.generations[key, default: 0] == generation else { return }
                self.cache[key] = img ?? MediaRenderer.generated(snapshot, width: pixels)
                self.inflight.remove(key)
                self.revision += 1
            }
        }
        return nil
    }

    func invalidate(id: UUID, path: String) {
        let prefix = id.uuidString + "|" + path + "|"
        cache.keys.filter { $0.hasPrefix(prefix) }.forEach { cache.removeValue(forKey: $0) }
        inflight.filter { $0.hasPrefix(prefix) }.forEach { key in
            generations[key, default: 0] += 1
            inflight.remove(key)
        }
        psdDocs.removeValue(forKey: path)
        psdImages.keys.filter { $0.hasPrefix(path + "|") }.forEach { psdImages.removeValue(forKey: $0) }
        tileCache.removeAll(); seamCache.removeAll(); fx.removeAll()
        revision += 1
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

// MARK: - Client rounds and versions on the board (1.20)

struct ClientPinBadge: View {
    let pin: BoardPin
    static let pink = Color(red: 1.0, green: 0.36, blue: 0.56)
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: pin.picked ? "heart.fill" : "text.bubble.fill").font(.system(size: 10, weight: .bold))
            if pin.picked {
                Text(pin.pickedBy.count == 1 ? ClientPinBadge.initials(pin.pickedBy[0]) : "\(pin.pickedBy.count)").font(.system(size: 10, weight: .heavy))
            }
            if !pin.comments.isEmpty && pin.picked {
                Image(systemName: "text.bubble.fill").font(.system(size: 9, weight: .bold)).opacity(0.85)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7).padding(.vertical, 4)
        .background(pin.picked ? ClientPinBadge.pink : Color(white: 0.22), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.9), lineWidth: 1.2))
        .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
        .help((pin.picked ? "Picked by " + pin.pickedBy.joined(separator: ", ") : "Commented") +
              pin.comments.map { "\n\($0.reviewer): \($0.text)" }.joined())
    }

    static func initials(_ name: String) -> String {
        let words = name.split { !$0.isLetter }.prefix(2)
        let s = words.compactMap(\.first).map { String($0).uppercased() }.joined()
        return s.isEmpty ? "C" : s
    }
}

struct ClientCommentCallout: View {
    let comments: [BoardPin.Comment]
    let width: Double
    var replies = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(comments.prefix(2).enumerated()), id: \.offset) { _, c in
                HStack(alignment: .top, spacing: 6) {
                    Text(ClientPinBadge.initials(c.reviewer)).font(.system(size: 8, weight: .heavy)).foregroundStyle(.white)
                        .frame(width: 17, height: 17).background(ClientPinBadge.pink.opacity(0.85), in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(c.reviewer).font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                        Text(c.text).font(.system(size: 11, weight: .medium)).foregroundStyle(.white).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if comments.count > 2 || replies > 0 {
                Text([comments.count > 2 ? "+\(comments.count - 2) more" : nil, replies > 0 ? "\(replies) \(replies == 1 ? "reply" : "replies")" : nil].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(8)
        .frame(width: width, alignment: .leading)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.12)))
    }
}

struct BoardVersionsPanel: View {
    @EnvironmentObject var model: StudioLibrary
    let board: Moodboard
    @State private var name = ""
    @State private var renaming: UUID?
    @State private var draft = ""

    static func nowStamp() -> String { ISO8601DateFormatter().string(from: Date()) }
    static func display(_ iso: String) -> String {
        guard let d = ISO8601DateFormatter().date(from: iso) else { return iso }
        let f = DateFormatter(); f.dateFormat = "MMM d, h:mm a"; return f.string(from: d)
    }
    static func describe(_ c: (added: Int, removed: Int, changed: Int)?) -> String {
        guard let c else { return "" }
        var parts: [String] = []
        if c.added > 0 { parts.append("\(c.added) added since") }
        if c.removed > 0 { parts.append("\(c.removed) removed") }
        if c.changed > 0 { parts.append("\(c.changed) moved or edited") }
        return parts.isEmpty ? "Same as the board now" : parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Versions").font(.headline)
            HStack(spacing: 6) {
                TextField("Version \(board.versions.count + 1)", text: $name).textFieldStyle(.roundedBorder)
                    .onSubmit(save)
                Button("Save Version", action: save).buttonStyle(.borderedProminent).tint(Theme.accent)
            }
            Divider()
            if board.versions.isEmpty {
                Text("Save a version before a client round or a big rework. Restoring keeps the current layout as its own version first.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(board.versions.reversed()) { v in row(v) }
                    }
                }.frame(maxHeight: 330)
            }
        }
        .padding(14).frame(width: 340)
    }

    private func save() {
        let n = name
        var made = UUID()
        model.updateBoard(board.id, "Save Version") { made = $0.saveVersion(named: n, saved: Self.nowStamp()) }
        name = ""
        if let v = model.catalog.board(board.id)?.versions.first(where: { $0.id == made }) { model.flash("Saved \(v.name)") }
    }

    private func row(_ v: BoardVersion) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "clock").foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                if renaming == v.id {
                    TextField("Name", text: $draft).textFieldStyle(.roundedBorder).onSubmit {
                        model.updateBoard(board.id, "Rename Version") { $0.renameVersion(v.id, to: draft) }; renaming = nil
                    }
                } else {
                    Text(v.name).font(.callout.weight(.semibold)).lineLimit(1)
                }
                Text("\(Self.display(v.saved)) · \(v.items.count) cards").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                Text(Self.describe(board.changes(since: v.id))).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Button("Restore") {
                model.updateBoard(board.id, "Restore Version") { _ = $0.restoreVersion(v.id, saved: Self.nowStamp()) }
                model.flash("Restored \(v.name)")
            }.controlSize(.small)
        }
        .padding(8)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 8))
        .contextMenu {
            Button("Rename…") { draft = v.name; renaming = v.id }
            Button("Delete Version", role: .destructive) { model.updateBoard(board.id, "Delete Version") { $0.deleteVersion(v.id) } }
        }
    }
}


// MARK: - Card approval and threads (1.21)

/// The corner badge on a card: status, client picks and the reply count. Clicking it opens the thread.
struct CardThreadBadge: View {
    let pin: BoardPin?
    let status: CardStatus
    let replies: Int

    static func color(_ s: CardStatus) -> Color {
        switch s {
        case .approved: return Theme.watch
        case .changes: return Theme.warning
        case .open: return Color(white: 0.6)
        }
    }
    static func symbol(_ s: CardStatus) -> String {
        switch s {
        case .approved: return "checkmark.seal.fill"
        case .changes: return "arrow.triangle.2.circlepath"
        case .open: return "circle.dashed"
        }
    }

    /// Rough width in points, for fitting the row inside its card.
    var estimatedWidth: Double {
        var w = 0.0, parts = 0
        if status != .open { w += status == .approved ? 74 : 70; parts += 1 }
        if let pin, pin.picked || !pin.comments.isEmpty { w += 22 + (pin.picked ? 20 : 0) + (pin.picked && !pin.comments.isEmpty ? 16 : 0); parts += 1 }
        if replies > 0 { w += 34; parts += 1 }
        return max(24, w + Double(max(0, parts - 1)) * 4)
    }

    var body: some View {
        HStack(spacing: 4) {
            if status != .open {
                HStack(spacing: 3) {
                    Image(systemName: Self.symbol(status)).font(.system(size: 9, weight: .bold))
                    Text(status.label).font(.system(size: 9, weight: .heavy))
                }
                .foregroundStyle(.black.opacity(0.85))
                .padding(.horizontal, 6).padding(.vertical, 4)
                .background(Self.color(status), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.9), lineWidth: 1.2))
            }
            if let pin, pin.picked || !pin.comments.isEmpty { ClientPinBadge(pin: pin) }
            if replies > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "arrowshape.turn.up.left.fill").font(.system(size: 8, weight: .bold))
                    Text("\(replies)").font(.system(size: 9, weight: .heavy))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 4)
                .background(Theme.accent, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.9), lineWidth: 1.2))
            }
            if status == .open && (pin == nil || (!pin!.picked && pin!.comments.isEmpty)) && replies == 0 {
                Color.clear.frame(width: 1, height: 20)   // an anchor for a thread opened from the menu
            }
        }
        .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
        .contentShape(Rectangle())
        .help("Comments & status")
    }
}

/// A card's thread: status, what the client said, the studio's replies and a reply box.
struct CardThreadPanel: View {
    @EnvironmentObject var model: StudioLibrary
    let boardID: UUID
    let itemID: UUID
    @State private var draft = ""
    @State private var editing: UUID?
    @State private var editDraft = ""

    var body: some View {
        let board = model.catalog.board(boardID)
        let item = board?.items.first { $0.id == itemID }
        let asset = item?.assetID.flatMap { id in model.catalog.assets.first { $0.id == id } }
        let pin = board?.pins()[itemID]
        let replies = board?.replies(for: itemID) ?? []
        let status = board?.status(of: itemID) ?? .open
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if let asset { Thumbnail(asset: asset, pixels: 120).frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 6)) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(asset?.title ?? "Card").font(.headline).lineLimit(1)
                    if let pin, pin.picked {
                        Label("Picked by " + pin.pickedBy.joined(separator: ", "), systemImage: "heart.fill").font(.caption).foregroundStyle(ClientPinBadge.pink).lineLimit(1)
                    } else {
                        Text("Not picked").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            HStack(spacing: 6) {
                ForEach(CardStatus.allCases, id: \.self) { st in
                    Button { model.updateBoard(boardID, "Mark \(st.label)") { $0.setStatus(st, for: [itemID]) } } label: {
                        Label(st.label, systemImage: CardThreadBadge.symbol(st)).font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                            .foregroundStyle(status == st ? Color.black.opacity(0.85) : Color.primary)
                            .background(status == st ? CardThreadBadge.color(st) : Theme.raised, in: RoundedRectangle(cornerRadius: 7))
                    }.buttonStyle(.plain)
                }
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if (pin?.comments ?? []).isEmpty && replies.isEmpty {
                        Text("No comments yet. Replies stay with the board and go in the round summary.").font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(Array((pin?.comments ?? []).enumerated()), id: \.offset) { _, c in
                        bubble(initials: ClientPinBadge.initials(c.reviewer), tint: ClientPinBadge.pink, who: c.reviewer, when: Self.day(c.imported), text: c.text, indent: false)
                    }
                    ForEach(replies) { r in
                        if editing == r.id {
                            HStack {
                                TextField("Reply", text: $editDraft, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(1...4)
                                Button("Save") { model.updateBoard(boardID, "Edit Reply") { $0.editReply(r.id, text: editDraft) }; editing = nil }.controlSize(.small)
                            }.padding(.leading, 22)
                        } else {
                            bubble(initials: ClientPinBadge.initials(r.author), tint: Theme.accent, who: r.author, when: BoardVersionsPanel.display(r.posted), text: r.text, indent: !(pin?.comments ?? []).isEmpty)
                                .contextMenu {
                                    Button("Edit") { editDraft = r.text; editing = r.id }
                                    Button("Delete Reply", role: .destructive) { model.updateBoard(boardID, "Delete Reply") { $0.deleteReply(r.id) } }
                                }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 260)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .bottom, spacing: 6) {
                    TextField(pin?.comments.isEmpty == false ? "Reply to \(pin!.comments[0].reviewer)…" : "Add a comment…", text: $draft, axis: .vertical)
                        .textFieldStyle(.roundedBorder).lineLimit(1...4)
                    Button("Reply", action: send).buttonStyle(.borderedProminent).tint(Theme.accent)
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .keyboardShortcut(.return, modifiers: .command)
                }
                HStack(spacing: 4) {
                    Text("as").font(.caption2).foregroundStyle(.tertiary)
                    TextField("Name", text: $model.replyAuthor).textFieldStyle(.plain).font(.caption2).foregroundStyle(.secondary).frame(width: 140)
                }
            }
        }
        .padding(14).frame(width: 360)
    }

    /// "2026-09-24" as "Sep 24", matching how replies show their time.
    static func day(_ ymd: String) -> String {
        let p = DateFormatter(); p.dateFormat = "yyyy-MM-dd"; p.locale = Locale(identifier: "en_US_POSIX")
        guard let d = p.date(from: ymd) else { return ymd }
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f.string(from: d)
    }

    private func send() {
        let text = draft, who = model.replyAuthor, stamp = BoardVersionsPanel.nowStamp()
        model.updateBoard(boardID, "Reply") { $0.addReply(to: itemID, author: who, text: text, posted: stamp) }
        draft = ""
    }

    private func bubble(initials: String, tint: Color, who: String, when: String, text: String, indent: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(initials).font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                .frame(width: 22, height: 22).background(tint.opacity(0.9), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(who).font(.caption.weight(.bold)).lineLimit(1)
                    Text(when).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                }
                Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 8))
        .padding(.leading, indent ? 22 : 0)
    }
}

/// The round summary as a printable page: light paper, one row per asset card (1.21).
struct RoundSummaryPage: View {
    let summary: RoundSummary
    let images: [UUID: CGImage]
    let date: String
    var credits: [CreditLine] = []
    static let width: CGFloat = 612

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("CLIENT ROUND SUMMARY").font(.system(size: 9, weight: .heavy)).tracking(1.5).foregroundStyle(Self.muted)
                Text(summary.board).font(.system(size: 24, weight: .heavy)).foregroundStyle(Self.ink)
                Text(([date] + (summary.reviewers.isEmpty ? [] : ["Reviewed by " + summary.reviewers.joined(separator: ", ")])).joined(separator: " · "))
                    .font(.system(size: 10)).foregroundStyle(Self.muted)
                HStack(spacing: 6) {
                    ForEach([CardStatus.approved, .changes, .open], id: \.self) { st in
                        chip("\(summary.counts[st] ?? 0) \(st.label)", st)
                    }
                }.padding(.top, 4)
            }
            .padding(.bottom, 14)
            Rectangle().fill(Self.rule).frame(height: 1)
            ForEach(Array(summary.rows.enumerated()), id: \.offset) { i, row in
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Color(white: 0.92)
                        if let a = row.asset, let img = images[a] { Image(decorative: img, scale: 1).resizable().scaledToFill() }
                    }
                    .frame(width: 92, height: 69).clipShape(RoundedRectangle(cornerRadius: 4))
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("\(i + 1). \(row.title)").font(.system(size: 12, weight: .bold)).foregroundStyle(Self.ink).lineLimit(1)
                            Spacer(minLength: 4)
                            chip(row.status.label, row.status)
                        }
                        if !row.pickedBy.isEmpty {
                            Text("♥ Picked by " + row.pickedBy.joined(separator: ", ")).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(Color(red: 0.82, green: 0.2, blue: 0.4))
                        }
                        ForEach(Array(row.comments.enumerated()), id: \.offset) { _, c in line(c.reviewer, c.text, reply: false) }
                        ForEach(row.replies) { r in line(r.author, r.text, reply: true) }
                        if row.pickedBy.isEmpty && row.comments.isEmpty && row.replies.isEmpty {
                            Text("No feedback").font(.system(size: 9.5)).foregroundStyle(Self.muted)
                        }
                    }
                }
                .padding(.vertical, 10)
                Rectangle().fill(Self.rule).frame(height: 1)
            }
            if !credits.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("CREDITS").font(.system(size: 9, weight: .heavy)).tracking(1.5).foregroundStyle(Self.muted)
                    ForEach(Array(credits.enumerated()), id: \.offset) { _, c in
                        (Text(c.credit).font(.system(size: 9.5, weight: .bold)).foregroundColor(Self.ink)
                         + Text("  \(c.license) · \(c.titles.joined(separator: ", "))").font(.system(size: 9.5)).foregroundColor(Self.muted)
                         + Text((c.files ?? []).isEmpty ? "" : "  📎 " + (c.files ?? []).map(\.name).joined(separator: ", ")).font(.system(size: 9)).foregroundColor(Self.muted))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 14)
            }
            Text("Made with ASSSETS").font(.system(size: 8, weight: .semibold)).foregroundStyle(Self.muted).padding(.top, 12)
        }
        .padding(40)
        .frame(width: Self.width, alignment: .topLeading)
        .background(Color.white)
    }

    static let ink = Color(white: 0.1), muted = Color(white: 0.45), rule = Color(white: 0.87)

    private func chip(_ text: String, _ st: CardStatus) -> some View {
        Text(text).font(.system(size: 9, weight: .heavy)).foregroundStyle(Self.ink)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(CardThreadBadge.color(st).opacity(st == .open ? 0.35 : 0.8), in: Capsule())
    }

    private func line(_ who: String, _ text: String, reply: Bool) -> some View {
        (Text(reply ? "↳ \(who): " : "\(who): ").font(.system(size: 9.5, weight: .bold)) + Text(text).font(.system(size: 9.5)))
            .foregroundStyle(reply ? Self.muted : Self.ink)
            .padding(.leading, reply ? 10 : 0)
            .fixedSize(horizontal: false, vertical: true)
    }
}

extension StudioLibrary {
    /// Renders the round summary to a PDF, with an optional PNG of the same page (CI keeps one).
    func writeRoundSummary(_ id: UUID, to url: URL, png: URL? = nil) async -> Int? {
        guard let summary = catalog.roundSummary(id) else { return nil }
        var images: [UUID: CGImage] = [:]
        for row in summary.rows {
            guard let aid = row.asset, images[aid] == nil, let a = catalog.assets.first(where: { $0.id == aid }) else { continue }
            images[aid] = await MediaRenderer.thumbnail(for: a, maxPixel: 320) ?? MediaRenderer.generated(a, width: 320)
        }
        let df = DateFormatter(); df.dateStyle = .long
        let creditLines = credits(summary.rows.compactMap(\.asset))
        let r = ImageRenderer(content: RoundSummaryPage(summary: summary, images: images, date: df.string(from: Date()), credits: creditLines))
        r.proposedSize = ProposedViewSize(width: RoundSummaryPage.width, height: nil)
        var ok = false
        r.render { size, draw in
            var box = CGRect(origin: .zero, size: size)
            guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            ctx.beginPDFPage(nil); draw(ctx); ctx.endPDFPage(); ctx.closePDF(); ok = true
        }
        if let png {
            r.scale = 2
            if let cg = r.cgImage, let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) { try? data.write(to: png, options: .atomic) }
        }
        return ok ? summary.rows.count : nil
    }

    func exportRoundSummary(_ id: UUID) {
        guard let board = catalog.board(id) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = board.name + " round summary.pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { @MainActor in
            if await self.writeRoundSummary(id, to: url) != nil { self.flash("Exported \(url.lastPathComponent)") } else { self.flash("Couldn't export the round summary") }
        }
    }
}

// MARK: - Board templates (1.22)

/// An empty image slot from a template.
struct TemplateSlot: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.035))
            RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.28), style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
            VStack(spacing: 6) {
                Image(systemName: "photo.badge.plus").font(.system(size: 22, weight: .light)).foregroundStyle(Theme.accent.opacity(0.9))
                Text("Drop an image").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
    }
}

/// A small drawing of a template's layout: sections as outlines, headings as bars, slots dashed, notes and palettes filled.
struct TemplatePreview: View {
    let template: BoardTemplate
    var body: some View {
        GeometryReader { geo in
            let b = Self.bounds(template.items)
            let s = min(Double(geo.size.width) / b.w, Double(geo.size.height) / b.h)
            let ox = (Double(geo.size.width) - b.w * s) / 2 - b.x * s, oy = (Double(geo.size.height) - b.h * s) / 2 - b.y * s
            ZStack(alignment: .topLeading) {
                ForEach(template.items.sorted { $0.z < $1.z }) { it in
                    shape(it)
                        .frame(width: max(2, it.w * s), height: max(2, it.h * s))
                        .offset(x: ox + it.x * s, y: oy + it.y * s)
                }
            }
        }
        .padding(10)
        .background(Color(red: 0.035, green: 0.04, blue: 0.065), in: RoundedRectangle(cornerRadius: 10))
    }

    static func bounds(_ items: [BoardItem]) -> BoardRect {
        guard !items.isEmpty else { return BoardRect(x: 0, y: 0, w: 100, h: 75) }
        let x0 = items.map(\.x).min()!, y0 = items.map(\.y).min()!
        let x1 = items.map { $0.x + $0.w }.max()!, y1 = items.map { $0.y + $0.h }.max()!
        return BoardRect(x: x0, y: y0, w: max(1, x1 - x0), h: max(1, y1 - y0))
    }

    @ViewBuilder private func shape(_ it: BoardItem) -> some View {
        switch it.kind {
        case .asset: RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.accent.opacity(0.85), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
        case .frame: RoundedRectangle(cornerRadius: 4).strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
        case .heading: VStack { Capsule().fill(Color.white.opacity(0.75)).frame(height: max(2, it.h * 0.02 + 3)); Spacer(minLength: 0) }
        case .note: RoundedRectangle(cornerRadius: 3).fill(Color(red: 0.98, green: 0.92, blue: 0.7).opacity(0.85))
        case .palette:
            HStack(spacing: 0) { ForEach(it.colors, id: \.self) { Color(hex: $0) } }.clipShape(RoundedRectangle(cornerRadius: 3))
        }
    }
}

struct TemplatePickerSheet: View {
    @EnvironmentObject var model: StudioLibrary
    @State private var renaming: UUID?
    @State private var draft = ""
    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 240), spacing: 14)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("New Board from Template").font(.title3.weight(.bold))
                    Text("Start from a layout, then drag images onto the empty slots.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { model.templatePickerOpen = false }.keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    section("BUILT IN", BoardTemplate.builtIns)
                    if !model.catalog.templates.isEmpty { section("YOUR TEMPLATES", model.catalog.templates) }
                    else {
                        Text("Save any board as a template from its menu (Save as Template…) and it shows up here.")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 760, height: 600)
        .background(Theme.panel)
    }

    private func section(_ title: String, _ list: [BoardTemplate]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 10, weight: .heavy)).tracking(1.4).foregroundStyle(.secondary)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                ForEach(list) { t in card(t) }
            }
        }
    }

    private func card(_ t: BoardTemplate) -> some View {
        Button { model.newBoard(fromTemplate: t.id) } label: {
            VStack(alignment: .leading, spacing: 6) {
                TemplatePreview(template: t).frame(height: 104)
                if renaming == t.id {
                    TextField("Name", text: $draft).textFieldStyle(.roundedBorder).onSubmit {
                        model.mutate("Rename Template") { $0.renameTemplate(t.id, to: draft) }; renaming = nil
                    }
                } else {
                    Text(t.name).font(.callout.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                }
                Text(t.summary.isEmpty ? "\(t.slotCount) image slots" : t.summary).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(t.slotCount) slots").font(.caption2.monospacedDigit()).foregroundStyle(Theme.accent)
            }
            .padding(10)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("New Board from \(t.name)") { model.newBoard(fromTemplate: t.id) }
            if !t.builtIn {
                Button("Rename…") { draft = t.name; renaming = t.id }
                Button("Delete Template", role: .destructive) { model.mutate("Delete Template") { $0.deleteTemplate(t.id) } }
            }
        }
    }
}

/// Feedback files read but not applied (1.23).
struct PendingFeedback: Identifiable {
    struct File: Identifiable {
        let id = UUID()
        let feedback: ReviewGallery.Feedback
        let preview: FeedbackPreview
        let name: String
    }
    let id = UUID()
    var files: [File]
    var unreadable: Int
}

/// Tidy plus align, distribute and match size for the selected cards. One undo step each.
struct ArrangeMenu: View {
    @EnvironmentObject var model: StudioLibrary
    let board: Moodboard
    let selection: Set<UUID>
    var inContextMenu = false

    var body: some View {
        if inContextMenu {
            Menu("Arrange \(selection.count)") { ops }
        } else {
            Menu {
                Button("Tidy Into Rows") { model.updateBoard(board.id, "Tidy Board") { $0.tidy() }; model.fitBoardRequest += 1 }
                Divider()
                if selection.count < 2 { Text("Select two or more cards to align") }
                ops
            } label: { Image(systemName: "rectangle.grid.2x2") }
            .menuIndicator(.hidden).fixedSize().help("Tidy and arrange")
        }
    }

    @ViewBuilder private var ops: some View {
        Section("Align") {
            ForEach([ArrangeOp.left, .centerX, .right, .top, .middle, .bottom], id: \.self) { item($0) }
        }
        Section("Distribute") { item(.distributeH); item(.distributeV) }
        Section("Size") { item(.matchWidth); item(.matchHeight) }
    }

    private func item(_ op: ArrangeOp) -> some View {
        let sel = selection, id = board.id
        return Button { model.updateBoard(id, op.label) { $0.arrange(sel, op) } } label: { Label(op.label, systemImage: ArrangeMenu.symbol(op)) }
            .disabled(sel.count < op.minimumCards)
    }

    static func symbol(_ op: ArrangeOp) -> String {
        switch op {
        case .left: return "align.horizontal.left"
        case .centerX: return "align.horizontal.center"
        case .right: return "align.horizontal.right"
        case .top: return "align.vertical.top"
        case .middle: return "align.vertical.center"
        case .bottom: return "align.vertical.bottom"
        case .distributeH: return "distribute.horizontal"
        case .distributeV: return "distribute.vertical"
        case .matchWidth: return "arrow.left.and.right"
        case .matchHeight: return "arrow.up.and.down"
        }
    }
}

/// What a client's feedback file will do, before it does it.
struct FeedbackPreviewSheet: View {
    @EnvironmentObject var model: StudioLibrary
    let pending: PendingFeedback

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Import Client Feedback").font(.title3.weight(.bold))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(pending.files) { f in file(f) }
                }
            }
            HStack {
                if pending.unreadable > 0 {
                    Label("\(pending.unreadable) file\(pending.unreadable == 1 ? "" : "s") skipped: not ASSSETS feedback", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(Theme.warning)
                }
                Spacer()
                Button("Cancel") { model.pendingFeedback = nil }.keyboardShortcut(.cancelAction)
                Button("Import") { model.applyPendingFeedback() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(Theme.accent)
                    .disabled(pending.files.allSatisfy { $0.preview.isEmpty })
            }
        }
        .padding(20)
        .frame(width: 720, height: 560)
        .background(Theme.panel)
    }

    private var subtitle: String {
        let n = pending.files.count
        return n == 1 ? "Check what this file changes. Nothing is applied until you press Import." : "\(n) files. Nothing is applied until you press Import."
    }

    private func file(_ f: PendingFeedback.File) -> some View {
        let p = f.preview
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(String(p.reviewer.prefix(1)).uppercased()).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 26, height: 26).background(Theme.accent, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(p.reviewer).font(.callout.weight(.semibold))
                    Text(p.boardName.map { "Round on board \u{201C}\($0)\u{201D}" } ?? "Gallery \u{201C}\(p.title)\u{201D} · goes to Client Picks").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                chip("\(p.picks)", "heart.fill", Color(red: 1, green: 0.36, blue: 0.54))
                chip("\(p.approvals)", CardThreadBadge.symbol(.approved), CardThreadBadge.color(.approved))
                chip("\(p.changeRequests)", CardThreadBadge.symbol(.changes), CardThreadBadge.color(.changes))
                chip("\(p.notes)", "text.bubble.fill", Color(white: 0.75))
            }
            if p.replaces {
                Label("\(p.reviewer) already sent feedback on this round. Importing replaces their earlier picks and notes.", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption2).foregroundStyle(Theme.warning)
            }
            VStack(spacing: 0) {
                ForEach(Array(p.rows.enumerated()), id: \.offset) { i, r in
                    row(r)
                    if i < p.rows.count - 1 { Divider().opacity(0.4) }
                }
            }
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline))
        }
    }

    private func chip(_ n: String, _ symbol: String, _ c: Color) -> some View {
        HStack(spacing: 3) { Image(systemName: symbol).font(.system(size: 9, weight: .bold)); Text(n).font(.caption2.monospacedDigit().weight(.semibold)) }
            .foregroundStyle(c).padding(.horizontal, 7).padding(.vertical, 3)
            .background(c.opacity(0.14), in: Capsule())
    }

    private func row(_ r: FeedbackPreview.Row) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if let id = r.asset, let a = model.catalog.assets.first(where: { $0.id == id }) {
                    Thumbnail(asset: a, pixels: 160)
                } else {
                    Image(systemName: "questionmark.square.dashed").font(.system(size: 18)).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.black.opacity(0.25))
                }
            }
            .frame(width: 58, height: 42).clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(r.title).font(.caption.weight(.semibold)).foregroundStyle(r.known ? .primary : .secondary).lineLimit(1)
                    if r.favorite && r.known { Image(systemName: "heart.fill").font(.system(size: 9)).foregroundStyle(Color(red: 1, green: 0.36, blue: 0.54)) }
                }
                if !r.note.isEmpty {
                    Text("\u{201C}\(r.note)\u{201D}").font(.caption2).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                if !r.known { Text("Not in this library, so it's skipped").font(.caption2).foregroundStyle(.tertiary) }
            }
            Spacer(minLength: 8)
            if r.known, let to = r.to { statusChange(r.from, to) }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
    }

    @ViewBuilder private func statusChange(_ from: CardStatus?, _ to: CardStatus) -> some View {
        HStack(spacing: 5) {
            if let from, from != to {
                Text(from.label).font(.caption2.weight(.semibold)).foregroundStyle(CardThreadBadge.color(from))
                Image(systemName: "arrow.right").font(.system(size: 8, weight: .bold)).foregroundStyle(.tertiary)
            }
            Label(to.label, systemImage: CardThreadBadge.symbol(to)).font(.caption2.weight(.bold)).foregroundStyle(CardThreadBadge.color(to))
            if from == to { Text("no change").font(.caption2).foregroundStyle(.tertiary) }
            if from == nil { Text("no board").font(.caption2).foregroundStyle(.tertiary) }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(CardThreadBadge.color(to).opacity(0.1), in: Capsule())
    }
}

/// "N licenses expired since your last visit" (1.26). Shown once per launch.
struct RightsNoticeBanner: View {
    @EnvironmentObject var model: StudioLibrary
    let issues: [RightsIssue]
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.octagon.fill").font(.system(size: 16)).foregroundStyle(Theme.danger)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(issues.count) license\(issues.count == 1 ? "" : "s") expired since your last visit").font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                Text(issues.prefix(3).map(\.title).joined(separator: ", ") + (issues.count > 3 ? " and \(issues.count - 3) more" : ""))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button("Review") {
                if let smart = model.catalog.smartCollections.first(where: { $0.rules.rights == .expired }) { model.show(smart: smart.id) }
                model.selection = Set(issues.map(\.asset)); model.focusID = issues.first?.asset
                model.rightsNotice = nil
            }
            .buttonStyle(.borderedProminent).tint(Theme.danger).controlSize(.small).fixedSize().layoutPriority(2)
            Button { model.rightsNotice = nil } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Dismiss")
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(Theme.danger.opacity(0.14))
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.danger.opacity(0.45)).frame(height: 1) }
    }
}

/// Rights for a multi-selection (1.26): fields that differ read "Mixed" and stay as they are unless edited.
struct BulkRightsSection: View {
    @EnvironmentObject var model: StudioLibrary
    let assets: [StudioAsset]
    @State private var license: RightsLicense?
    @State private var credit = ""
    @State private var source = ""
    @State private var uses = ""
    @State private var touched: Set<String> = []
    @State private var endMode = 0          // 0 leave, 1 set, 2 remove
    @State private var endDate = Date()
    @State private var loadedFor: Set<UUID> = []

    var body: some View {
        let ids = assets.map(\.id)
        let common = model.catalog.commonRights(ids)
        let problems = assets.filter { $0.rightsStatus().isProblem }.count
        let withEnd = assets.filter { $0.rights?.expires != nil }.count
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                InspectorLabel(text: "RIGHTS · \(assets.count) ASSETS")
                Spacer()
                if problems > 0 {
                    Text("\(problems) need\(problems == 1 ? "s" : "") a look").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.danger)
                        .padding(.horizontal, 7).padding(.vertical, 2).background(Theme.danger.opacity(0.15), in: Capsule())
                }
            }
            RightsPresetBar(ids: ids)
            Menu {
                ForEach(RightsLicense.allCases) { l in Button { license = l } label: { Label(l.rawValue, systemImage: l.symbol) } }
            } label: {
                HStack(spacing: 7) {
                    let shown = license ?? common.license.value
                    Image(systemName: shown?.symbol ?? "square.stack.3d.up").foregroundStyle(Theme.accent)
                    Text(shown?.rawValue ?? "Mixed").font(.caption.weight(.semibold)).foregroundStyle(shown == nil ? .secondary : .primary)
                    if license != nil { Text("edited").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.accent) }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(license != nil ? Theme.accent.opacity(0.6) : Theme.hairline))
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden)
            field("Credit", key: "credit", shared: common.credit, text: $credit, hint: "Use {title} or {n} for per-file credits")
            field("Source", key: "source", shared: common.source, text: $source)
            field("Allowed uses", key: "uses", shared: common.uses, text: $uses)
            HStack(spacing: 8) {
                Picker("", selection: $endMode) {
                    Text(common.expires.isMixed ? "Ends: Mixed" : (common.expires.value ?? nil).map { "Ends \($0)" } ?? "No end date").tag(0)
                    Text("Set end date").tag(1)
                    Text("Remove end date").tag(2)
                }
                .labelsHidden().controlSize(.small).frame(maxWidth: 150)
                if endMode == 1 { DatePicker("", selection: $endDate, displayedComponents: .date).labelsHidden().datePickerStyle(.field).controlSize(.small) }
                Spacer(minLength: 0)
            }
            if pending {
                HStack {
                    Button("Revert") { reset() }.buttonStyle(.plain).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Button { model.applyRights(edit, to: ids); reset() } label: {
                        Text("Apply to \(assets.count)").font(.caption.weight(.bold)).padding(.horizontal, 12).padding(.vertical, 5)
                            .background(Theme.accent, in: Capsule()).foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            } else if withEnd > 0 {
                HStack(spacing: 6) {
                    Button { model.extendRights(Set(ids)) } label: { Label(withEnd == assets.count ? "Extend All 1 Year" : "Extend \(withEnd) · 1 Year", systemImage: "calendar.badge.plus").lineLimit(1).fixedSize() }
                    Button { model.markRenewed(Set(ids)) } label: { Label("Mark Renewed", systemImage: "arrow.clockwise.circle") }
                }
                .buttonStyle(.bordered).controlSize(.small).font(.caption)
            }
            LicenseFilesBlock(ids: ids).padding(.top, 2).id("license-files")
        }
        .onAppear { if loadedFor != Set(ids) { reset() } }
        .onChange(of: ids) { _, _ in reset() }
    }

    private var pending: Bool { !edit.isEmpty }

    private var edit: RightsEdit {
        RightsEdit(license: license,
                   source: touched.contains("source") ? source : nil,
                   credit: touched.contains("credit") ? credit : nil,
                   uses: touched.contains("uses") ? uses : nil,
                   expires: endMode == 1 ? .some(UsageRights.day(endDate)) : endMode == 2 ? .some(nil) : nil)
    }

    private func reset() {
        loadedFor = Set(assets.map(\.id))
        let common = model.catalog.commonRights(assets.map(\.id))
        license = nil; touched = []; endMode = 0
        credit = common.credit.value ?? ""; source = common.source.value ?? ""; uses = common.uses.value ?? ""
        endDate = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    }

    private func field(_ title: String, key: String, shared: Shared<String>, text: Binding<String>, hint: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                if touched.contains(key) { Text("edited").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.accent) }
            }
            TextField(shared.isMixed ? "Mixed" : (hint ?? ""), text: Binding(get: { text.wrappedValue }, set: { text.wrappedValue = $0; touched.insert(key) }))
                .textFieldStyle(.plain).font(.caption)
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(touched.contains(key) ? Theme.accent.opacity(0.6) : Theme.hairline))
                .help(hint ?? "")
        }
    }
}

/// One landscape letter page of the rights report (1.26).
struct RightsReportPage: View {
    let report: RightsReport
    let rows: [RightsReport.Row]
    let page: Int
    let pages: Int
    static let size = CGSize(width: 792, height: 612)
    static let rowsPerPage = 9   // rows can wrap to three lines (source + uses)
    static let ink = Color(white: 0.1), muted = Color(white: 0.45), rule = Color(white: 0.87)
    // Title, Status, License, Credit, Source / uses, Ends
    static let widths: [CGFloat] = [140, 100, 78, 140, 140, 70]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("RIGHTS REPORT").font(.system(size: 9, weight: .heavy)).tracking(1.5).foregroundStyle(Self.muted)
                    Text(report.title).font(.system(size: 20, weight: .heavy)).foregroundStyle(Self.ink).lineLimit(1)
                }
                Spacer()
                let c = report.counts
                HStack(spacing: 6) {
                    pill("\(c.problems) expired or editorial", Color(red: 0.95, green: 0.3, blue: 0.33))
                    pill("\(c.expiring) ending soon", Color(red: 1.0, green: 0.72, blue: 0.28))
                    pill("\(c.missing) no info", Color(white: 0.75))
                    pill("\(c.ok) OK", Color(red: 0.45, green: 0.85, blue: 0.55))
                }
            }
            Text("\(report.rows.count) assets · as of \(report.date)").font(.system(size: 9.5)).foregroundStyle(Self.muted).padding(.top, 4).padding(.bottom, 10)
            HStack(spacing: 8) {
                ForEach(Array(["ASSET", "STATUS", "LICENSE", "CREDIT", "SOURCE · ALLOWED USES", "ENDS"].enumerated()), id: \.offset) { i, h in
                    Text(h).font(.system(size: 7.5, weight: .heavy)).tracking(0.8).foregroundStyle(Self.muted).frame(width: Self.widths[i], alignment: .leading)
                }
            }
            .padding(.vertical, 5)
            Rectangle().fill(Self.ink.opacity(0.6)).frame(height: 1)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r.title).font(.system(size: 9.5, weight: .bold)).foregroundStyle(Self.ink).lineLimit(1)
                        Text(r.file).font(.system(size: 7.5)).foregroundStyle(Self.muted).lineLimit(1)
                        if let f = r.licenseFiles.first {
                            Text("📎 " + f + (r.licenseFiles.count > 1 ? " +\(r.licenseFiles.count - 1)" : ""))
                                .font(.system(size: 7, weight: .semibold)).foregroundStyle(Color(red: 0.42, green: 0.27, blue: 0.85)).lineLimit(1).truncationMode(.middle)
                        }
                    }.frame(width: Self.widths[0], alignment: .leading)
                    Text(r.status).font(.system(size: 8.5, weight: .bold)).foregroundStyle(statusColor(r.rank)).lineLimit(2).frame(width: Self.widths[1], alignment: .leading)
                    Text(r.license).font(.system(size: 8.5)).foregroundStyle(Self.ink).lineLimit(1).frame(width: Self.widths[2], alignment: .leading)
                    Text(r.credit).font(.system(size: 8.5)).foregroundStyle(Self.ink).lineLimit(2).frame(width: Self.widths[3], alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r.source).font(.system(size: 8.5)).foregroundStyle(Self.ink).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        Text(r.uses).font(.system(size: 7.5)).foregroundStyle(Self.muted).lineLimit(1)
                    }.frame(width: Self.widths[4], alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r.expires.isEmpty ? "—" : r.expires).font(.system(size: 8.5).monospacedDigit()).foregroundStyle(Self.ink)
                        if !r.renewed.isEmpty { Text("renewed \(r.renewed)").font(.system(size: 7)).foregroundStyle(Self.muted) }
                    }.frame(width: Self.widths[5], alignment: .leading)
                }
                .padding(.vertical, 6)
                Rectangle().fill(Self.rule).frame(height: 1)
            }
            Spacer(minLength: 0)
            HStack {
                Text("Made with ASSSETS · CSV with the same rows saved alongside" + (report.docs.isEmpty ? "" : " · \(report.docs.count) license file\(report.docs.count == 1 ? "" : "s") on record")).font(.system(size: 7.5, weight: .semibold)).foregroundStyle(Self.muted)
                Spacer()
                Text("\(page) of \(pages)").font(.system(size: 7.5, weight: .semibold)).foregroundStyle(Self.muted)
            }
        }
        .padding(.horizontal, 36).padding(.vertical, 30)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(Color.white)
    }

    private func statusColor(_ rank: Int) -> Color {
        switch rank {
        case 0, 1: return Color(red: 0.8, green: 0.15, blue: 0.2)
        case 2: return Color(red: 0.72, green: 0.45, blue: 0.0)
        case 3: return Self.muted
        default: return Color(red: 0.15, green: 0.55, blue: 0.3)
        }
    }

    private func pill(_ t: String, _ c: Color) -> some View {
        Text(t).font(.system(size: 8.5, weight: .heavy)).foregroundStyle(Self.ink)
            .padding(.horizontal, 7).padding(.vertical, 3).background(c.opacity(0.55), in: Capsule())
    }
}

struct RightsWarning: Identifiable {
    let id = UUID()
    let action: String
    let issues: [RightsIssue]
    var cleared: [UUID] = []
    let proceed: () -> Void
    /// Goes ahead with only the cleared assets; nil when that isn't offered.
    var skip: (([UUID]) -> Void)? = nil
}

/// A made-up license document for the demo library (1.27).
struct DemoLicensePage: View {
    let vendor: String
    let doc: String
    let lines: [(String, String, String)]
    let terms: String
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(vendor.uppercased()).font(.system(size: 11, weight: .heavy)).tracking(2).foregroundStyle(Color(red: 0.3, green: 0.2, blue: 0.7))
            Text(doc).font(.system(size: 22, weight: .bold))
            Text("Sample document made for the ASSSETS demo library").font(.system(size: 9)).foregroundStyle(.gray)
            Divider()
            ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                HStack { VStack(alignment: .leading) { Text(l.0).bold(); Text(l.1).font(.system(size: 10)).foregroundStyle(.gray) }; Spacer(); Text(l.2).monospacedDigit() }
            }
            Divider()
            Text(terms).font(.system(size: 10)).foregroundStyle(.gray)
            Spacer()
        }
        .foregroundStyle(Color(white: 0.1))
        .padding(48).frame(width: 612, height: 792, alignment: .topLeading).background(Color.white)
    }
}

struct PresetDraft: Identifiable {
    let id = UUID()
    var name: String
    var rights: UsageRights
    var termYears: Int?
    var docs: [UUID]
    var count: Int
    var includeFiles = true
}

/// Shown before expired or editorial-only assets leave the app (1.25, redesigned in 1.27).
struct RightsWarningSheet: View {
    @EnvironmentObject var model: StudioLibrary
    let warning: RightsWarning

    var body: some View {
        let n = warning.issues.count
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.shield.fill").font(.system(size: 26)).foregroundStyle(Theme.danger)
                    .frame(width: 44, height: 44).background(Theme.danger.opacity(0.14), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(n) \(n == 1 ? "asset isn't" : "assets aren't") cleared for client use").font(.system(size: 17, weight: .bold))
                    Text("Check the license before this goes to a client.\(warning.cleared.isEmpty ? "" : " The other \(warning.cleared.count) \(warning.cleared.count == 1 ? "is" : "are") fine.")")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(warning.issues, id: \.asset) { issue in row(issue) }
                }
            }
            .frame(maxHeight: 230)
            HStack(spacing: 10) {
                Button("Cancel") { model.rightsWarning = nil }.keyboardShortcut(.cancelAction)
                Spacer()
                if let skip = warning.skip {
                    Button("Leave Out \(n) · \(warning.action) \(warning.cleared.count)") {
                        let ids = warning.cleared; model.rightsWarning = nil
                        DispatchQueue.main.async { skip(ids) }
                    }
                    .help("Go ahead with only the assets that are cleared")
                }
                Button("\(warning.action) Anyway") {
                    let go = warning.proceed; model.rightsWarning = nil
                    DispatchQueue.main.async { go() }
                }
                .buttonStyle(.borderedProminent).tint(Theme.danger).keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
        .padding(22)
        .frame(width: 520)
        .background(Theme.panel)
    }

    private func row(_ issue: RightsIssue) -> some View {
        let asset = model.catalog.assets.first { $0.id == issue.asset }
        let files = model.catalog.licenseDocs(for: issue.asset)
        return HStack(spacing: 10) {
            if let asset { Thumbnail(asset: asset, pixels: 120).frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 7)) }
            VStack(alignment: .leading, spacing: 2) {
                Text(issue.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                Text([asset?.rights?.source, asset?.rights?.uses].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ").ifEmpty("No source entered"))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            if let f = files.first {
                Button { model.quickLook(f) } label: { Image(systemName: "paperclip").font(.system(size: 11, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(Theme.accent).help("Open \(f.name)")
            }
            Text(issue.status.label).font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.danger).lineLimit(1).fixedSize()
                .padding(.horizontal, 7).padding(.vertical, 3).background(Theme.danger.opacity(0.15), in: Capsule())
        }
        .padding(8)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.hairline))
    }
}

extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}

/// License documents on one asset or across a selection (1.27). Click opens Quick Look; drop files to attach.
struct LicenseFilesBlock: View {
    @EnvironmentObject var model: StudioLibrary
    let ids: [UUID]
    @State private var targeted = false

    var body: some View {
        let coverage = model.catalog.licenseDocCoverage(ids)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                InspectorLabel(text: "LICENSE FILES")
                Spacer()
                if !coverage.isEmpty { Text("\(coverage.count)").font(.caption2.weight(.bold)).foregroundStyle(.secondary) }
            }
            ForEach(coverage, id: \.doc.id) { item in row(item.doc, count: item.count) }
            Button { model.chooseLicenseFiles(for: ids) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "paperclip").font(.system(size: 11, weight: .semibold))
                    Text(coverage.isEmpty ? "Attach license, order or receipt…" : "Attach Another…").font(.caption.weight(.semibold))
                    Spacer()
                    Text("or drop files").font(.caption2).foregroundStyle(.tertiary)
                }
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(targeted ? Theme.accent.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.accent.opacity(targeted ? 0.8 : 0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            let target = ids, lib = model
            for p in providers where p.canLoadObject(ofClass: URL.self) {
                _ = p.loadObject(ofClass: URL.self) { u, _ in
                    guard let u else { return }
                    DispatchQueue.main.async { lib.attachLicenseFiles([u], to: target) }
                }
            }
            return true
        }
    }

    private func row(_ d: LicenseDoc, count: Int) -> some View {
        let partial = ids.count > 1 && count < ids.count
        return HStack(spacing: 9) {
            Image(systemName: d.symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accent)
                .frame(width: 28, height: 28).background(Theme.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 1) {
                Text(d.name).font(.caption.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 6) {
                    Text(ids.count > 1 ? "\(d.kind.rawValue) · on \(count) of \(ids.count)" : "\(d.kind.rawValue) · \(d.sizeLabel) · added \(d.added)")
                        .font(.system(size: 10)).foregroundStyle(partial ? Theme.warning : .secondary).lineLimit(1)
                    if partial {
                        Button { model.attachExistingLicenseDoc(d.id, to: ids) } label: { Text("Add to all").font(.system(size: 10, weight: .bold)) }
                            .buttonStyle(.plain).foregroundStyle(Theme.accent).fixedSize()
                    }
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "eye").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline))
        .contentShape(Rectangle())
        .onTapGesture { model.quickLook(d) }
        .help("Quick Look \(d.name)")
        .contextMenu {
            Button("Quick Look") { model.quickLook(d) }
            Button("Show in Finder") { model.revealLicense(d) }
            Divider()
            Button(ids.count == 1 ? "Remove from This Asset" : "Remove from All \(ids.count)", role: .destructive) { model.detachLicenseDoc(d.id, from: ids) }
        }
    }
}

/// Saved rights presets as one-click chips (1.27).
struct RightsPresetBar: View {
    @EnvironmentObject var model: StudioLibrary
    let ids: [UUID]

    var body: some View {
        let presets = model.catalog.rightsPresets
        WrapLayout(spacing: 6) {
                ForEach(presets) { p in
                    Button { model.applyPreset(p.id, to: ids) } label: {
                        HStack(spacing: 5) {
                            Image(systemName: p.rights.license.symbol).font(.system(size: 10, weight: .semibold))
                            Text(p.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                            if !p.docs.isEmpty { Image(systemName: "paperclip").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary) }
                        }
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(Theme.accent.opacity(0.16), in: Capsule())
                        .overlay(Capsule().stroke(Theme.accent.opacity(0.4)))
                        .fixedSize()
                    }
                    .buttonStyle(.plain)
                    .help("Apply \(p.name) to \(ids.count == 1 ? "this asset" : "all \(ids.count)"): \(p.summary(docCount: p.docs.count))")
                    .contextMenu {
                        Button("Apply to \(ids.count == 1 ? "This Asset" : "All \(ids.count)")") { model.applyPreset(p.id, to: ids) }
                        Divider()
                        Button("Delete Preset", role: .destructive) { model.deletePreset(p.id) }
                    }
                }
                Button { model.startPresetDraft(from: ids) } label: {
                    Label(presets.isEmpty ? "Save as Preset" : "Save…", systemImage: "plus").font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .overlay(Capsule().stroke(Theme.hairline))
                        .fixedSize()
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("Save these rights\(ids.count > 1 ? " (fields they share)" : "") and license files as a preset")
        }
    }
}

struct PresetSaveSheet: View {
    @EnvironmentObject var model: StudioLibrary
    @State var draft: PresetDraft

    var body: some View {
        let docs = draft.docs.compactMap { model.catalog.licenseDoc($0) }
        let replacing = model.catalog.rightsPresets.contains { $0.name.caseInsensitiveCompare(draft.name.trimmingCharacters(in: .whitespaces)) == .orderedSame }
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Save Rights Preset").font(.system(size: 20, weight: .bold))
                Text(draft.count == 1 ? "From this asset's rights" : "From the fields all \(draft.count) assets share").font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                InspectorLabel(text: "NAME")
                TextField("e.g. Northlight · order NL-20417", text: $draft.name).textFieldStyle(.roundedBorder)
                if replacing { Text("Replaces the preset with this name").font(.caption2).foregroundStyle(Theme.warning) }
            }
            VStack(alignment: .leading, spacing: 5) {
                InspectorLabel(text: "SAVES")
                line("License", draft.rights.license.rawValue)
                line("Source", draft.rights.source)
                line("Credit", draft.rights.credit)
                line("Allowed uses", draft.rights.uses)
            }
            .padding(10).background(Theme.raised, in: RoundedRectangle(cornerRadius: 9))
            HStack {
                InspectorLabel(text: "END DATE")
                Spacer()
                Picker("", selection: $draft.termYears) {
                    Text(draft.rights.expires.map { "Keep \($0)" } ?? "No end date").tag(Int?.none)
                    Text("1 year from when applied").tag(Int?.some(1))
                    Text("2 years from when applied").tag(Int?.some(2))
                    Text("3 years from when applied").tag(Int?.some(3))
                }
                .labelsHidden().frame(width: 230)
            }
            if !docs.isEmpty {
                Toggle(isOn: $draft.includeFiles) {
                    Text("Attach \(docs.count == 1 ? docs[0].name : "\(docs.count) license files") whenever it's applied").font(.caption).lineLimit(1).truncationMode(.middle)
                }
                .toggleStyle(.checkbox)
            }
            HStack {
                Button("Cancel") { model.presetDraft = nil }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(replacing ? "Replace Preset" : "Save Preset") { model.savePreset(draft) }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .controlSize(.large)
        }
        .padding(22)
        .frame(width: 460)
        .background(Theme.panel)
    }

    private func line(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(k).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).frame(width: 84, alignment: .leading)
            Text(v.isEmpty ? "—" : v).font(.caption).foregroundStyle(v.isEmpty ? .tertiary : .primary).lineLimit(2)
            Spacer(minLength: 0)
        }
    }
}

/// Usage rights for one asset (1.25): license, source, credit, allowed uses, end date.
struct RightsSection: View {
    @EnvironmentObject var model: StudioLibrary
    let asset: StudioAsset
    @State private var draft = UsageRights()
    @State private var ends = false
    @State private var endDate = Date()
    @State private var loadedFor: UUID?

    private var edited: UsageRights {
        var r = draft
        r.expires = ends ? UsageRights.day(endDate) : nil
        return r
    }
    private var dirty: Bool { edited != (asset.rights ?? UsageRights()) }

    var body: some View {
        let status = asset.rightsStatus()
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                InspectorLabel(text: "RIGHTS")
                Spacer()
                statusChip(status)
            }
            RightsPresetBar(ids: [asset.id])
            if asset.rights == nil, asset.isStarter || asset.sourceKey?.hasPrefix("generated:") == true, !dirty {
                Text("Bundled with ASSSETS. Add a credit or terms here if you change it.").font(.caption2).foregroundStyle(.secondary)
            }
            Menu {
                ForEach(RightsLicense.allCases) { l in
                    Button { draft.license = l } label: { Label(l.rawValue, systemImage: l.symbol) }
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: draft.license.symbol).foregroundStyle(Theme.accent)
                    Text(draft.license.rawValue).font(.caption.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline))
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden)
            field("Credit", "e.g. Photo: Lena Ortiz / Northlight", $draft.credit)
            field("Source", "Agency, client or link", $draft.source)
            field("Allowed uses", "e.g. Web and social, 1 year", $draft.uses)
            HStack(spacing: 8) {
                Toggle("Ends", isOn: $ends).toggleStyle(.switch).controlSize(.mini).font(.caption.weight(.semibold))
                if ends {
                    DatePicker("", selection: $endDate, displayedComponents: .date).labelsHidden().datePickerStyle(.field).controlSize(.small)
                } else {
                    Text("No end date").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }
            if let rn = asset.rights?.renewed, !dirty {
                Text("Renewed \(rn)").font(.caption2).foregroundStyle(.secondary)
            }
            if !dirty, asset.rights?.expires != nil {
                HStack(spacing: 6) {
                    Button { model.extendRights([asset.id]) } label: { Label("Extend 1 Year", systemImage: "calendar.badge.plus") }
                    Button { model.markRenewed([asset.id]) } label: { Label("Mark Renewed", systemImage: "arrow.clockwise.circle") }
                }
                .buttonStyle(.bordered).controlSize(.small).font(.caption)
            }
            if dirty {
                HStack {
                    Button("Revert") { load() }.buttonStyle(.plain).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Button { model.setRights(edited, for: [asset.id]) } label: {
                        Text("Save Rights").font(.caption.weight(.bold)).padding(.horizontal, 12).padding(.vertical, 5)
                            .background(Theme.accent, in: Capsule()).foregroundStyle(.white)
                    }
                    .buttonStyle(.plain).keyboardShortcut(.return, modifiers: [.command])
                }
            }
            LicenseFilesBlock(ids: [asset.id]).padding(.top, 4).id("license-files")
        }
        .onAppear { if loadedFor != asset.id { load() } }
        .onChange(of: asset.id) { _, _ in load() }
        .onChange(of: asset.rights) { _, _ in load() }
    }

    private func load() {
        loadedFor = asset.id
        draft = asset.rights ?? UsageRights()
        ends = draft.expires != nil
        endDate = draft.expires.flatMap { UsageRights.localDate($0) } ?? Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    }

    private func field(_ title: String, _ prompt: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            TextField(prompt, text: text)
                .textFieldStyle(.plain).font(.caption)
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline))
                .onSubmit { if dirty { model.setRights(edited, for: [asset.id]) } }
        }
    }

    @ViewBuilder private func statusChip(_ st: RightsStatus) -> some View {
        let c: Color = {
            switch st {
            case .ok: return Theme.watch
            case .expiring: return Theme.warning
            case .expired, .editorial: return Theme.danger
            case .missing: return Color.white.opacity(0.5)
            }
        }()
        Text(st.label).font(.system(size: 10, weight: .bold)).foregroundStyle(c)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(c.opacity(0.15), in: Capsule())
    }
}

/// Where this asset (or another version of it) sits on boards (1.24). A click jumps to the card.
struct OnBoardsSection: View {
    @EnvironmentObject var model: StudioLibrary
    let asset: StudioAsset

    var body: some View {
        let uses = model.catalog.boardsUsing(asset.id)
        if !uses.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    InspectorLabel(text: "ON BOARDS")
                    Spacer()
                    let boards = Set(uses.map(\.board)).count
                    Text("\(boards) board\(boards == 1 ? "" : "s")").font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(uses) { u in
                    Button { model.show(board: u.board); model.boardSelection = [u.item] } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "rectangle.3.group").font(.system(size: 11)).foregroundStyle(Theme.accent)
                            Text(u.boardName).font(.caption.weight(.semibold)).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(u.label).font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background((u.asset == asset.id ? Theme.accent : Color.white).opacity(u.asset == asset.id ? 0.3 : 0.1), in: Capsule())
                            if let n = u.newer, let top = model.catalog.assets.first(where: { $0.id == n }) {
                                Label(VersionStacks.rank(top).1, systemImage: "arrow.up.circle.fill").font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Theme.warning).help("A newer version is available")
                            }
                        }
                        .padding(.horizontal, 9).padding(.vertical, 7)
                        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).help("Show this card on \(u.boardName)")
                }
            }
        }
    }
}

#else
@main struct LinuxBuildStub { static func main() { print("ASSSETS requires macOS 14 or later.") } }

#endif
