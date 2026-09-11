#if os(macOS)
import SwiftUI
import AppKit
import QuickLookThumbnailing
import AsssetsCore

@main
struct ASSSETSApp: App {
    @StateObject private var model = LibraryModel()
    var body: some Scene {
        WindowGroup("ASSSETS") {
            BrowserView()
                .environmentObject(model)
                .frame(minWidth: 860, minHeight: 560)
        }
    }
}

@MainActor
final class LibraryModel: ObservableObject {
    @Published var library = Library()
    @Published var queryText = ""
    @Published var selectedKind: AssetKind?
    @Published var selectedCollection: UUID?
    @Published var selectedSmartCollection: UUID?

    var storeURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("ASSSETS/library.json")
    }

    var thumbsDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("ASSSETS/thumbnails")
    }

    init() {
        if let loaded = try? LibraryStore(fileURL: storeURL).load() { library = loaded }
    }

    func save() { try? LibraryStore(fileURL: storeURL).save(library) }

    func importFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url {
            _ = try? library.importFolder(url.path)
            _ = library.generateDerivatives(thumbnailsDir: thumbsDir.path)
            save()
        }
    }

    var visibleAssets: [Asset] {
        var q = Library.Query(text: queryText.isEmpty ? nil : queryText)
        if let k = selectedKind { q.kinds = [k] }
        var results = library.search(q)
        if let cid = selectedCollection,
           let c = library.collections.first(where: { $0.id == cid }) {
            results = results.filter { c.assetIDs.contains($0.id) }
        }
        if let sid = selectedSmartCollection {
            let live = Set(library.smartCollectionAssets(sid).map(\.id))
            results = results.filter { live.contains($0.id) }
        }
        return results
    }
}

struct BrowserView: View {
    @EnvironmentObject var model: LibraryModel

    private let cols = [GridItem(.adaptive(minimum: 140), spacing: 12)]

    var body: some View {
        NavigationSplitView {
            List {
                Section("Library") {
                    Label("All assets", systemImage: "square.grid.2x2")
                        .onTapGesture { model.selectedCollection = nil }
                }
                Section("Smart Collections") {
                    ForEach(model.library.smartCollections) { sc in
                        Label(sc.name, systemImage: "sparkle.magnifyingglass")
                            .onTapGesture {
                                model.selectedSmartCollection =
                                    model.selectedSmartCollection == sc.id ? nil : sc.id
                            }
                    }
                }
                Section("Collections") {
                    ForEach(model.library.collections) { c in
                        Label(c.name, systemImage: "folder")
                            .onTapGesture { model.selectedCollection = c.id }
                    }
                    Button("New collection") {
                        _ = model.library.createCollection("Collection \(model.library.collections.count + 1)")
                        model.save()
                    }
                }
                Section("Kind") {
                    ForEach(AssetKind.allCases, id: \.self) { k in
                        Label(k.rawValue, systemImage: icon(for: k))
                            .onTapGesture { model.selectedKind = model.selectedKind == k ? nil : k }
                    }
                }
            }
        } detail: {
            VStack(spacing: 0) {
                HStack {
                    TextField("Search filenames, paths, tags…", text: $model.queryText)
                        .textFieldStyle(.roundedBorder)
                    Button("Import folder…") { model.importFolder() }
                }
                .padding()
                Divider()
                ScrollView {
                    LazyVGrid(columns: cols, spacing: 12) {
                        ForEach(model.visibleAssets) { asset in
                            AssetCell(asset: asset)
                        }
                    }
                    .padding()
                }
            }
        }
    }

    private func icon(for kind: AssetKind) -> String {
        switch kind {
        case .psd: return "square.3.layers.3d"
        case .illustrator: return "paintbrush.pointed"
        case .vector: return "point.topleft.down.curvedto.point.bottomright.up"
        case .image: return "photo"
        case .video: return "film"
        case .other: return "doc"
        }
    }
}

struct AssetCell: View {
    let asset: Asset

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ThumbnailImage(asset: asset)
            Text(asset.filename).font(.caption).lineLimit(1)
            if let palette = asset.palette, !palette.isEmpty {
                HStack(spacing: 2) {
                    ForEach(palette, id: \.self) { hex in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: hex) ?? .clear)
                            .frame(height: 6)
                    }
                }
            }
            if !asset.tags.isEmpty {
                Text(asset.tags.sorted().joined(separator: ", "))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

/// Shows the library's own PNG thumbnail when one was derived; otherwise
/// asks QuickLook for a system thumbnail (PSD, AI, video, JPEG, TIFF).
struct ThumbnailImage: View {
    let asset: Asset
    @State private var quickLookImage: NSImage?

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(.quaternary)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let file = asset.thumbnailFile, let img = NSImage(contentsOfFile: file) {
                    Image(nsImage: img).resizable().scaledToFit().padding(4)
                } else if let img = quickLookImage {
                    Image(nsImage: img).resizable().scaledToFit().padding(4)
                } else {
                    VStack {
                        Image(systemName: "doc.text.image").font(.largeTitle)
                        if let w = asset.width, let h = asset.height {
                            Text("\(w)\u{00D7}\(h)").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .clipped()
            .task { await loadQuickLook() }
    }

    private func loadQuickLook() async {
        guard asset.thumbnailFile == nil, quickLookImage == nil else { return }
        let url = URL(fileURLWithPath: asset.path)
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: 256, height: 256),
            scale: 2, representationTypes: .thumbnail)
        if let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
            quickLookImage = rep.nsImage
        }
    }
}

extension Color {
    init?(hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt64(s, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xFF) / 255.0,
                  green: Double((v >> 8) & 0xFF) / 255.0,
                  blue: Double(v & 0xFF) / 255.0)
    }
}

#else
@main
struct LinuxBuildStub {
    static func main() {
        print("ASSSETS is a native macOS app. On this platform, use the AsssetsCore library and its test suite.")
    }
}
#endif
