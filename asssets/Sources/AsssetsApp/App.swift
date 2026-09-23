#if os(macOS)
import SwiftUI
import AppKit
import AVFoundation
import AVKit
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UniformTypeIdentifiers
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
                Button("New Collection") { library.newCollection(with: []) }.keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandGroup(after: .pasteboard) {
                Button("Select All Assets") { library.selectAllVisible() }.keyboardShortcut("a", modifiers: [.command, .option])
                Button("Deselect All") { library.clearSelection() }.keyboardShortcut("d", modifiers: [.command])
                Button("Toggle Favorite") { library.toggleFavorite(library.selection) }.keyboardShortcut("l", modifiers: [.command])
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
    private var keyMonitor: Any?

    func openViewer() {
        guard smartEditor == nil else { return }
        viewerID = focusID ?? selection.first ?? filtered.first?.id
    }
    func closeViewer() { viewerID = nil }
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
    }

    private func handleKey(_ e: NSEvent) -> Bool {
        guard e.modifierFlags.intersection([.command, .control, .option]).isEmpty, smartEditor == nil else { return false }
        if viewerID == nil, NSApp.keyWindow?.firstResponder is NSText { return false }
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

    /// Reads real dimensions, durations and vector colors for the bundled files.
    private func enrichStarterMetadata(_ c: inout StudioCatalog) {
        for i in c.assets.indices where c.assets[i].isStarter {
            guard let path = c.assets[i].importedPath else { continue }
            let url = URL(fileURLWithPath: path)
            switch url.pathExtension.lowercased() {
            case "svg":
                if let text = try? String(contentsOf: url, encoding: .utf8), let scene = VectorScene.parse(text) {
                    let colors = Array(scene.colors.prefix(5))
                    if colors.count >= 3 { c.assets[i].palette = colors }
                    c.assets[i].resolution = "SVG • \(Int(scene.width)) × \(Int(scene.height))"
                }
            case "psd":
                // Read once: on first install, or when the palette is still the collection default (0.6.0 installs).
                let defaultPalette = StarterCatalog.describe(filename: url.lastPathComponent)?.palette
                if !c.assets[i].resolution.hasPrefix("PSD") || c.assets[i].palette == defaultPalette,
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
                    if c.assets[i].palette == StarterCatalog.describe(filename: url.lastPathComponent)?.palette,
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

    func mutate(_ change: (inout StudioCatalog) -> Void) {
        change(&catalog)
        selection = selection.filter { id in catalog.assets.contains { $0.id == id } }
        if let f = focusID, !selection.contains(f) { focusID = selection.first }
        save()
    }

    // MARK: Browsing and selection

    var filtered: [StudioAsset] {
        if let id = selectedSmart { return catalog.filtered(search: search, kind: selectedKind, smart: id) }
        return catalog.filtered(search: search, kind: selectedKind, collection: selectedCollection)
    }
    var browsingTitle: String { selectedSmart.flatMap { catalog.smartCollection($0)?.name } ?? selectedCollection }
    var canSaveSearch: Bool { selectedSmart == nil && (!search.trimmingCharacters(in: .whitespaces).isEmpty || selectedKind != nil) }
    var focused: StudioAsset? { focusID.flatMap { id in catalog.assets.first { $0.id == id } } }
    var selectedAssets: [StudioAsset] { catalog.assets.filter { selection.contains($0.id) } }

    func show(collection: String) { selectedCollection = collection; selectedSmart = nil; anchorID = nil }
    func show(smart id: UUID) { selectedSmart = id; selectedCollection = StudioCatalog.allAssets; anchorID = nil }

    // MARK: Smart collections

    func beginNewSmart() {
        var rules = SmartRules(text: search, kinds: selectedKind.map { [$0] } ?? [])
        if selectedCollection == StudioCatalog.favorites { rules.favoritesOnly = true }
        else if selectedCollection != StudioCatalog.allAssets { rules.collection = selectedCollection }
        let t = search.trimmingCharacters(in: .whitespaces)
        smartEditor = SmartEditorState(existing: nil, name: t.isEmpty ? (selectedKind?.rawValue ?? "Smart Collection") : t.capitalized, rules: rules)
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
            search = ""; selectedKind = nil
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

    func toggleFavorite(_ ids: Set<UUID>) { guard !ids.isEmpty else { return }; mutate { $0.toggleFavorite(ids) } }
    func addTags(_ raw: String, to ids: Set<UUID>) {
        var n = 0
        mutate { n = $0.addTags(raw, to: ids) }
        if n > 1 { flash("Tagged \(n) assets") }
    }
    func removeTag(_ tag: String, from ids: Set<UUID>) { mutate { $0.removeTag(tag, from: ids) } }
    func move(_ ids: Set<UUID>, to collection: String) {
        var n = 0
        mutate { n = $0.move(ids, to: collection) }
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
        mutate { n = $0.remove(ids) }
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

    func dragFile(for a: StudioAsset) -> URL? {
        let look = DragOut.Look(effectApplied: effect != .original, psdLayersChanged: !(psdToggled[a.id] ?? []).isEmpty,
                                tiled: tiles(for: a) > 1, seamsFixed: fixSeams.contains(a.id))
        let exists = a.importedPath.map { FileManager.default.fileExists(atPath: $0) } ?? false
        switch DragOut.plan(title: a.title, importedPath: a.importedPath, fileExists: exists, look: look) {
        case .file(let path): return URL(fileURLWithPath: path)
        case .render(let name):
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ASSSETS-drag/\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(name)
            let ok = MediaRenderer.exportPNG(a, effect: effect, amount: intensity, psdToggled: psdToggled[a.id] ?? [],
                                             tiles: tiles(for: a), fixSeams: fixSeams.contains(a.id), to: url)
            return ok ? url : nil
        }
    }

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
        }
        if !added.isEmpty { show(collection: StudioCatalog.importedCollection); selection = Set(added); focusID = added.first; flash("Imported \(added.count) files") }
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

    func exportProcessed(_ ids: Set<UUID>) {
        let picked = catalog.assets.filter { ids.contains($0.id) && $0.kind != .audio }
        guard !picked.isEmpty else { return }
        if picked.count == 1, let a = picked.first {
            let p = NSSavePanel(); p.nameFieldStringValue = a.title.replacingOccurrences(of: " ", with: "-") + "-\(effect.rawValue.lowercased().replacingOccurrences(of: " ", with: "-")).png"; p.allowedContentTypes = [.png]
            guard p.runModal() == .OK, let url = p.url else { return }
            let ok = MediaRenderer.exportPNG(a, effect: effect, amount: intensity, psdToggled: psdToggled[a.id] ?? [], tiles: tiles(for: a), fixSeams: fixSeams.contains(a.id), to: url)
            flash(ok ? "Exported \(url.lastPathComponent)" : "Export failed")
        } else {
            let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true; p.prompt = "Export Here"
            guard p.runModal() == .OK, let dir = p.url else { return }
            var n = 0
            for a in picked where MediaRenderer.exportPNG(a, effect: effect, amount: intensity, psdToggled: psdToggled[a.id] ?? [], tiles: tiles(for: a), fixSeams: fixSeams.contains(a.id), to: dir.appendingPathComponent(a.title.replacingOccurrences(of: " ", with: "-") + ".png")) { n += 1 }
            flash("Exported \(n) of \(picked.count) previews")
        }
    }

    // MARK: Screenshot harness (CI launches the app with these arguments)

    private func applyLaunchArguments() {
        let args = ProcessInfo.processInfo.arguments
        func value(_ flag: String) -> String? { args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
        let demo = value("-asssets-demo")
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
        .overlay {
            if let id = model.viewerID, let asset = model.catalog.assets.first(where: { $0.id == id }) {
                AssetViewer(asset: asset).transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.16), value: model.viewerID)
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
                        Text("\(model.catalog.assets.count) original assets").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.horizontal, 6).padding(.top, 4)

                SidebarSection(title: "LIBRARY") {
                    SidebarRow(title: StudioCatalog.allAssets, symbol: "square.grid.2x2", count: model.catalog.count(in: StudioCatalog.allAssets), selected: model.selectedSmart == nil && model.selectedCollection == StudioCatalog.allAssets) { model.show(collection: StudioCatalog.allAssets) }
                    SidebarRow(title: StudioCatalog.favorites, symbol: "heart.fill", count: model.catalog.count(in: StudioCatalog.favorites), selected: model.selectedSmart == nil && model.selectedCollection == StudioCatalog.favorites, dropTarget: StudioCatalog.favorites) { model.show(collection: StudioCatalog.favorites) }
                }

                SidebarSection(title: "COLLECTIONS", trailing: AnyView(
                    Button { model.newCollection(with: []) } label: { Image(systemName: "plus").font(.caption.bold()) }.buttonStyle(.plain).foregroundStyle(.secondary).help("New collection")
                )) {
                    ForEach(model.catalog.collections.filter { $0 != StudioCatalog.allAssets && $0 != StudioCatalog.favorites }, id: \.self) { name in
                        SidebarRow(title: name, symbol: symbol(for: name), count: model.catalog.count(in: name), selected: model.selectedSmart == nil && model.selectedCollection == name, dropTarget: name) { model.show(collection: name) }
                            .contextMenu {
                                Button("Rename…") { renameText = name; model.renamingCollection = name }
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
                                Button("Delete Smart Collection", role: .destructive) { model.deleteSmart(smart.id) }
                            }
                    }
                    if model.catalog.smartCollections.isEmpty {
                        Text("Save any search as a live collection.").font(.caption2).foregroundStyle(.tertiary).padding(.horizontal, 9)
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
        default: return "folder"
        }
    }
}

struct SidebarSection<Content: View>: View {
    let title: String
    var trailing: AnyView? = nil
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.system(size: 10, weight: .bold)).tracking(1.4).foregroundStyle(.secondary)
                Spacer()
                if let trailing { trailing }
            }.padding(.horizontal, 8).padding(.bottom, 4)
            content
        }
    }
}

enum RowAccent { case standard, smart }

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
                .foregroundStyle(accent == .smart ? Theme.smart : (selected ? Theme.accent : Color.secondary))
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
    var body: some View {
        let items = model.filtered
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    if model.selectedSmart != nil { Image(systemName: "sparkles").foregroundStyle(Theme.smart).font(.title3) }
                    Text(model.browsingTitle).font(.system(size: 22, weight: .bold)).lineLimit(1)
                    Text("\(items.count) \(items.count == 1 ? "asset" : "assets")").font(.callout).foregroundStyle(.secondary).fixedSize()
                    Spacer()
                    if let id = model.selectedSmart {
                        Button { model.beginEdit(smart: id) } label: { Label("Edit Rules", systemImage: "slider.horizontal.3").fixedSize() }
                            .buttonStyle(.bordered).controlSize(.small)
                    } else if model.canSaveSearch {
                        Button { model.beginNewSmart() } label: { Label("Save as Smart", systemImage: "sparkles").fixedSize() }
                            .buttonStyle(.borderedProminent).controlSize(.small).help("Save this search as a live smart collection")
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
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        KindChip(title: "All", symbol: "circle.grid.3x3", on: model.selectedKind == nil) { model.selectedKind = nil }
                        ForEach(MediaKind.allCases) { k in KindChip(title: k.rawValue, symbol: k.symbol, on: model.selectedKind == k) { model.selectedKind = model.selectedKind == k ? nil : k } }
                    }
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
            MoveMenu(ids: model.selection, compact: compact)
            Spacer(minLength: 0)
            Button { model.clearSelection() } label: {
                if compact { Image(systemName: "xmark.circle") } else { Text("Clear").fixedSize() }
            }.help("Clear selection")
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
        Button("Copy Keywords") { model.copyKeywords(ids) }
        Button(many ? "Export \(ids.count) Processed Previews…" : "Export Processed Preview…") { model.exportProcessed(ids) }
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
                        if asset.importedPath?.lowercased().hasSuffix(".psd") == true {
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
                if selected && model.selection.count > 1 {
                    Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(.white, Theme.accent).padding(7)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(asset.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                Text("\(asset.kind.singular) • \(asset.resolution)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack(spacing: 2) { ForEach(Array(asset.palette.prefix(5).enumerated()), id: \.offset) { _, hex in Color(hex: hex).frame(height: 4) } }.clipShape(Capsule())
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 15).fill(selected ? Theme.accent.opacity(0.17) : hovering ? Color.white.opacity(0.075) : Theme.raised))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(selected ? Theme.accent : Theme.hairline, lineWidth: selected ? 2 : 1))
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
                if asset.kind != .audio { EffectStrip(asset: asset).padding(.top, 10) }
                Divider().overlay(Theme.hairline).padding(.top, 10)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
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
                        InspectorLabel(text: "TAGS")
                        WrapLayout(spacing: 5) { ForEach(asset.tags, id: \.self) { tag in TagChip(tag: tag) { model.removeTag(tag, from: [asset.id]) } } }
                        HStack {
                            TextField("Add tags, comma separated", text: $newTag).textFieldStyle(.roundedBorder)
                                .onSubmit { model.addTags(newTag, to: [asset.id]); newTag = "" }
                            Button { model.addTags(newTag, to: [asset.id]); newTag = "" } label: { Image(systemName: "plus.circle.fill").font(.title3) }.buttonStyle(.plain).foregroundStyle(Theme.accent)
                        }
                        HStack(spacing: 8) {
                            if asset.kind != .audio {
                                Button { model.exportProcessed([asset.id]) } label: { Label("Export PNG", systemImage: "square.and.arrow.up") }.buttonStyle(.borderedProminent)
                            }
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
                InspectorLabel(text: "ORGANIZE")
                HStack(spacing: 8) {
                    Button { model.toggleFavorite(ids) } label: { Label(assets.allSatisfy { $0.favorite } ? "Unfavorite" : "Favorite All", systemImage: "heart") }.buttonStyle(.bordered)
                    MoveMenu(ids: ids).buttonStyle(.bordered)
                }
                Button { model.newCollection(with: ids) } label: { Label("New Collection from Selection", systemImage: "folder.badge.plus") }.buttonStyle(.bordered)
                InspectorLabel(text: "OUTPUT")
                HStack(spacing: 8) {
                    Button { model.exportProcessed(ids) } label: { Label("Export \(model.effect == .original ? "PNGs" : model.effect.rawValue)", systemImage: "square.and.arrow.up") }.buttonStyle(.borderedProminent)
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
        guard let img = base, let out = apply(effect, amount: amount, to: img),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(dest, out, nil)
        return CGImageDestinationFinalize(dest)
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
