#if os(macOS)
import SwiftUI
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers

@main
struct ASSSETSApp: App {
    @StateObject private var library = StudioLibrary()
    var body: some Scene {
        WindowGroup("ASSSETS") { StudioView().environmentObject(library).frame(minWidth: 1120, minHeight: 720) }
        .commands { CommandGroup(after: .newItem) { Button("Import Files…") { library.importFiles() }.keyboardShortcut("i") } }
    }
}

enum MediaKind: String, CaseIterable, Identifiable, Codable {
    case image = "Images", vector = "Vectors", mockup = "Mockups", texture = "Textures", video = "Footage", audio = "Audio"
    var id: String { rawValue }
    var symbol: String { switch self { case .image: "photo"; case .vector: "scribble.variable"; case .mockup: "square.3.layers.3d"; case .texture: "circle.hexagongrid"; case .video: "film"; case .audio: "waveform" } }
}

struct StudioAsset: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var kind: MediaKind
    var tags: [String]
    var collection: String
    var palette: [String]
    var seed: Int
    var favorite: Bool = false
    var importedPath: String? = nil
    var resolution: String
}

enum EffectPreset: String, CaseIterable, Identifiable {
    case original = "Original", vivid = "Vivid", mono = "Noir", warm = "Warm Film", cool = "Arctic", chrome = "Chrome", blur = "Dream Blur", poster = "Poster"
    var id: String { rawValue }
}

@MainActor
final class StudioLibrary: ObservableObject {
    @Published var assets: [StudioAsset] = []
    @Published var search = ""
    @Published var selectedKind: MediaKind?
    @Published var selectedCollection = "All Assets"
    @Published var selectedID: UUID?
    @Published var effect: EffectPreset = .original
    @Published var intensity = 0.75
    @Published var gridScale = 210.0
    @Published var inspectorVisible = true

    private let stateURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ASSSETS/studio-library.json")

    init() {
        installBundledLibraryIfNeeded()
        load()
    }

    private func installBundledLibraryIfNeeded() {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ASSSETS/StarterLibrary", isDirectory: true)
        guard !FileManager.default.fileExists(atPath: root.path), let bundled = Bundle.module.url(forResource: "StarterLibrary", withExtension: nil) else { return }
        try? FileManager.default.createDirectory(at: root.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.copyItem(at: bundled, to: root)
    }

    var collections: [String] { ["All Assets", "Favorites"] + Array(Set(assets.map(\.collection))).sorted() }
    var selected: StudioAsset? { assets.first { $0.id == selectedID } }
    var filtered: [StudioAsset] {
        let terms = search.lowercased().split(separator: " ").map(String.init)
        return assets.filter { asset in
            let kindOK = selectedKind == nil || asset.kind == selectedKind
            let collectionOK = selectedCollection == "All Assets" || (selectedCollection == "Favorites" ? asset.favorite : asset.collection == selectedCollection)
            let haystack = ([asset.title, asset.kind.rawValue, asset.collection] + asset.tags).joined(separator: " ").lowercased()
            return kindOK && collectionOK && terms.allSatisfy(haystack.contains)
        }
    }

    func load() {
        if let data = try? Data(contentsOf: stateURL), let saved = try? JSONDecoder().decode([StudioAsset].self, from: data), !saved.isEmpty { assets = saved }
        else {
            assets = Self.starterLibrary()
            let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ASSSETS/StarterLibrary")
            if let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) { for case let file as URL in e { importFile(file) } }
            save()
        }
        selectedID = assets.first?.id
    }
    func save() {
        try? FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(assets) { try? data.write(to: stateURL, options: .atomic) }
    }
    func toggleFavorite(_ id: UUID) { if let i = assets.firstIndex(where: { $0.id == id }) { assets[i].favorite.toggle(); save() } }
    func addTag(_ tag: String, to id: UUID) { let t = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(); guard !t.isEmpty, let i = assets.firstIndex(where: { $0.id == id }), !assets[i].tags.contains(t) else { return }; assets[i].tags.append(t); save() }
    func importFiles() {
        let p = NSOpenPanel(); p.allowsMultipleSelection = true; p.canChooseDirectories = true; p.canChooseFiles = true
        if p.runModal() == .OK {
            for u in p.urls { importURL(u) }
            save(); selectedCollection = "Imported"
        }
    }
    private func importURL(_ url: URL) {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            if let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey]) { for case let file as URL in e { importFile(file) } }
        } else { importFile(url) }
    }
    private func importFile(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        let kind: MediaKind? = if ["png","jpg","jpeg","heic","tiff","gif","webp"].contains(ext) { .image } else if ["svg","ai","eps","pdf"].contains(ext) { .vector } else if ["psd"].contains(ext) { .mockup } else if ["mov","mp4","m4v","webm"].contains(ext) { .video } else if ["wav","aif","aiff","mp3","m4a"].contains(ext) { .audio } else { nil }
        guard let kind, !assets.contains(where: { $0.importedPath == url.path }) else { return }
        assets.insert(StudioAsset(id: UUID(), title: url.deletingPathExtension().lastPathComponent, kind: kind, tags: [ext, "imported"], collection: "Imported", palette: ["#20242C","#586174","#B8C0CF"], seed: abs(url.path.hashValue), importedPath: url.path, resolution: "Local file"), at: 0)
    }

    static func starterLibrary() -> [StudioAsset] {
        let groups: [(MediaKind,String,[String],[String],String)] = [
            (.mockup,"Device Mockups",["phone","laptop","screen","presentation"],["#101319","#596273","#DCE4F2","#8C5CFF"],"6000 × 4000"),
            (.vector,"Editorial Vectors",["geometric","editorial","brand","scalable"],["#14162B","#EF476F","#FFD166","#06D6A0"],"SVG • infinite"),
            (.texture,"Material Textures",["paper","grain","concrete","overlay"],["#1E2025","#72665A","#CDBDA7","#F0E7DC"],"4096 × 4096"),
            (.image,"Studio Photography",["product","still life","campaign","photo"],["#0A0B0F","#315F74","#E1A66E","#F7E9D2"],"7200 × 4800"),
            (.video,"Motion Loops",["loop","abstract","4k","motion"],["#090C22","#3157FF","#00C2FF","#E7F0FF"],"4K • 00:12"),
            (.audio,"Sound Beds",["ambient","cinematic","loop","stereo"],["#111318","#28324A","#C25BFF","#F2CAFF"],"48 kHz • 00:24")
        ]
        let nouns = ["Aurora","Obsidian","Halo","Monolith","Prism","Tidal","Sienna","Signal","Flux","Afterglow","Orbit","Nocturne"]
        var out: [StudioAsset] = []
        for (g,(kind,collection,tags,palette,res)) in groups.enumerated() {
            for i in 0..<12 { out.append(StudioAsset(id: UUID(), title: "\(nouns[i]) \(kind == .audio ? "Sound" : kind == .video ? "Loop" : kind == .mockup ? "Scene" : "Study")", kind: kind, tags: tags + [i % 2 == 0 ? "minimal" : "bold", "original"], collection: collection, palette: palette.rotated(i % palette.count), seed: g * 101 + i * 17, favorite: i == 0, resolution: res)) }
        }
        return out
    }
}

extension Array { func rotated(_ n: Int) -> [Element] { guard !isEmpty else { return self }; let i = n % count; return Array(self[i...] + self[..<i]) } }

struct StudioView: View {
    @EnvironmentObject var model: StudioLibrary
    var body: some View {
        NavigationSplitView {
            Sidebar()
        } content: {
            AssetBrowser()
        } detail: {
            if let asset = model.selected { Inspector(asset: asset) } else { ContentUnavailableView("Select an asset", systemImage: "square.dashed") }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItemGroup {
                Button { model.importFiles() } label: { Label("Import", systemImage: "plus") }
                Slider(value: $model.gridScale, in: 150...300).frame(width: 100)
                Button { model.inspectorVisible.toggle() } label: { Image(systemName: "sidebar.trailing") }
            }
        }
    }
}

struct Sidebar: View {
    @EnvironmentObject var model: StudioLibrary
    var body: some View {
        List {
            Section { Label("ASSSETS Library", systemImage: "sparkles").font(.headline); Text("\(model.assets.count) original assets").font(.caption).foregroundStyle(.secondary) }
            Section("Collections") { ForEach(model.collections, id: \.self) { name in Label(name, systemImage: name == "Favorites" ? "heart.fill" : name == "All Assets" ? "square.grid.2x2" : "folder").tag(name).contentShape(Rectangle()).onTapGesture { model.selectedCollection = name } } }
            Section("Media") { Label("Everything", systemImage: "circle.grid.3x3").contentShape(Rectangle()).onTapGesture { model.selectedKind = nil }; ForEach(MediaKind.allCases) { kind in Label(kind.rawValue, systemImage: kind.symbol).contentShape(Rectangle()).onTapGesture { model.selectedKind = model.selectedKind == kind ? nil : kind } } }
        }.listStyle(.sidebar).navigationTitle("ASSSETS")
    }
}

struct AssetBrowser: View {
    @EnvironmentObject var model: StudioLibrary
    var body: some View {
        VStack(spacing: 0) {
            HStack { Image(systemName: "magnifyingglass"); TextField("Search 72 assets, tags, colors…", text: $model.search).textFieldStyle(.plain); if !model.search.isEmpty { Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain) }; Text("\(model.filtered.count)").font(.caption).foregroundStyle(.secondary) }
                .padding(10).background(.regularMaterial)
            Divider()
            if model.filtered.isEmpty { ContentUnavailableView.search(text: model.search) }
            else { ScrollView { LazyVGrid(columns: [GridItem(.adaptive(minimum: model.gridScale), spacing: 14)], spacing: 18) { ForEach(model.filtered) { asset in AssetCard(asset: asset).onTapGesture { model.selectedID = asset.id } } }.padding(18) } }
        }
        .navigationTitle(model.selectedCollection)
    }
}

struct AssetCard: View {
    @EnvironmentObject var model: StudioLibrary
    let asset: StudioAsset
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .topTrailing) {
                Artwork(asset: asset, effect: .original, intensity: 0).aspectRatio(1.36, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 12))
                Button { model.toggleFavorite(asset.id) } label: { Image(systemName: asset.favorite ? "heart.fill" : "heart").foregroundStyle(asset.favorite ? .pink : .white).padding(8).background(.black.opacity(0.35), in: Circle()) }.buttonStyle(.plain).padding(8)
                if asset.kind == .video { Image(systemName: "play.fill").font(.title2).padding(15).background(.ultraThinMaterial, in: Circle()) }
                if asset.kind == .audio { Waveform(seed: asset.seed).padding(22) }
            }
            HStack { VStack(alignment: .leading, spacing: 2) { Text(asset.title).font(.headline).lineLimit(1); Text("\(asset.kind.rawValue.dropLast(asset.kind == .audio ? 0 : 1)) • \(asset.resolution)").font(.caption).foregroundStyle(.secondary).lineLimit(1) }; Spacer(); Menu { Button("Add to favorites") { model.toggleFavorite(asset.id) }; Button("Reveal source") { if let p = asset.importedPath { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)]) } } } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 24) }
            HStack(spacing: 3) { ForEach(asset.palette, id: \.self) { hex in Color(hex: hex).frame(height: 5) } }.clipShape(Capsule())
        }
        .padding(9).background(model.selectedID == asset.id ? Color.accentColor.opacity(0.16) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(model.selectedID == asset.id ? Color.accentColor : .clear, lineWidth: 2))
    }
}

struct Inspector: View {
    @EnvironmentObject var model: StudioLibrary
    let asset: StudioAsset
    @State private var newTag = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Artwork(asset: asset, effect: model.effect, intensity: model.intensity).aspectRatio(1.2, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 14)).shadow(radius: 16, y: 8)
                VStack(alignment: .leading, spacing: 5) { Text(asset.title).font(.title2.bold()); Label(asset.collection, systemImage: "folder").font(.caption).foregroundStyle(.secondary); Text(asset.resolution).font(.caption.monospaced()).foregroundStyle(.secondary) }
                Divider()
                Text("LIVE EFFECTS").font(.caption.bold()).foregroundStyle(.secondary)
                Picker("Preset", selection: $model.effect) { ForEach(EffectPreset.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.menu)
                HStack { Text("Amount"); Slider(value: $model.intensity); Text("\(Int(model.intensity * 100))%").monospacedDigit().frame(width: 40) }
                Button("Reset Effects") { model.effect = .original; model.intensity = 0.75 }.buttonStyle(.bordered)
                Divider()
                Text("COLOR PALETTE").font(.caption.bold()).foregroundStyle(.secondary)
                HStack(spacing: 6) { ForEach(asset.palette, id: \.self) { hex in VStack { Color(hex: hex).frame(height: 44).clipShape(RoundedRectangle(cornerRadius: 6)); Text(hex).font(.system(size: 8, design: .monospaced)) } } }
                Text("TAGS").font(.caption.bold()).foregroundStyle(.secondary)
                FlowLayout(spacing: 5) { ForEach(asset.tags, id: \.self) { Text($0).font(.caption).padding(.horizontal, 8).padding(.vertical, 4).background(.quaternary, in: Capsule()) } }
                HStack { TextField("Add tag", text: $newTag).onSubmit { model.addTag(newTag, to: asset.id); newTag = "" }; Button { model.addTag(newTag, to: asset.id); newTag = "" } label: { Image(systemName: "plus.circle.fill") }.buttonStyle(.plain) }
                Divider()
                Button { exportPreview() } label: { Label("Export Processed Preview…", systemImage: "square.and.arrow.up") }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
                Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(asset.tags.joined(separator: ", "), forType: .string) } label: { Label("Copy Keywords", systemImage: "doc.on.doc") }
            }.padding(18)
        }.frame(minWidth: 290, idealWidth: 330).background(Color(nsColor: .windowBackgroundColor))
    }
    private func exportPreview() {
        let p = NSSavePanel(); p.nameFieldStringValue = asset.title.replacingOccurrences(of: " ", with: "-") + "-preview.png"; p.allowedContentTypes = [.png]
        if p.runModal() == .OK, let url = p.url, let image = renderedArtwork(asset: asset, effect: model.effect, intensity: model.intensity, size: CGSize(width: 1600, height: 1200)), let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let data = rep.representation(using: .png, properties: [:]) { try? data.write(to: url) }
    }
}

struct Artwork: View {
    let asset: StudioAsset; let effect: EffectPreset; let intensity: Double
    var body: some View {
        GeometryReader { geo in
            if let path = asset.importedPath, let image = NSImage(contentsOfFile: path) { Image(nsImage: processed(image, preset: effect, amount: intensity)).resizable().scaledToFill().frame(width: geo.size.width, height: geo.size.height).clipped() }
            else { Image(nsImage: renderedArtwork(asset: asset, effect: effect, intensity: intensity, size: CGSize(width: max(600, geo.size.width * 2), height: max(440, geo.size.height * 2))) ?? NSImage()).resizable().scaledToFill().frame(width: geo.size.width, height: geo.size.height).clipped() }
        }
    }
}

func renderedArtwork(asset: StudioAsset, effect: EffectPreset, intensity: Double, size: CGSize) -> NSImage? {
    let image = NSImage(size: size); image.lockFocus(); let ctx = NSGraphicsContext.current!.cgContext
    let colors = asset.palette.compactMap { NSColor(hex: $0)?.cgColor }
    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil) { ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: []) }
    var rng = Seeded(seed: UInt64(asset.seed + 500)); ctx.setBlendMode(.screen)
    for i in 0..<18 { let w = CGFloat(rng.next() % 300 + 40), x = CGFloat(rng.next() % UInt64(max(1, Int(size.width)))), y = CGFloat(rng.next() % UInt64(max(1, Int(size.height)))); ctx.setFillColor((colors.isEmpty ? NSColor.white.cgColor : colors[i % colors.count]).copy(alpha: 0.14) ?? NSColor.white.cgColor); if asset.kind == .vector { ctx.fillEllipse(in: CGRect(x: x-w/2,y: y-w/2,width:w,height:w)) } else { let p = CGMutablePath(); p.move(to: CGPoint(x:x,y:0)); p.addLine(to: CGPoint(x:min(size.width,x+w),y:size.height)); p.addLine(to: CGPoint(x:max(0,x-w),y:size.height)); p.closeSubpath(); ctx.addPath(p); ctx.fillPath() } }
    ctx.setBlendMode(.normal); let label = asset.kind == .mockup ? "ASSSETS\nSMART OBJECT" : asset.kind == .video ? "4K\nMOTION" : asset.kind == .audio ? "48 kHz\nSTEREO" : asset.title.uppercased()
    let para = NSMutableParagraphStyle(); para.alignment = .center
    (label as NSString).draw(in: CGRect(x: 30, y: size.height/2-70, width: size.width-60, height: 160), withAttributes: [.font:NSFont.systemFont(ofSize: min(58,size.width/10), weight:.heavy),.foregroundColor:NSColor.white.withAlphaComponent(0.9),.paragraphStyle:para,.kern:2])
    image.unlockFocus(); return processed(image, preset: effect, amount: intensity)
}

func processed(_ image: NSImage, preset: EffectPreset, amount: Double) -> NSImage {
    guard preset != .original, let data = image.tiffRepresentation, let ci = CIImage(data: data) else { return image }
    let context = CIContext(); var out = ci
    switch preset {
    case .vivid: let f = CIFilter.vibrance(); f.inputImage=ci; f.amount=Float(amount*1.4); out=f.outputImage ?? ci
    case .mono: let f=CIFilter.photoEffectNoir(); f.inputImage=ci; out=f.outputImage ?? ci
    case .warm: let f=CIFilter.temperatureAndTint(); f.inputImage=ci; f.neutral=CIVector(x:6500,y:0); f.targetNeutral=CIVector(x:6500-1800*amount,y:0); out=f.outputImage ?? ci
    case .cool: let f=CIFilter.temperatureAndTint(); f.inputImage=ci; f.neutral=CIVector(x:6500,y:0); f.targetNeutral=CIVector(x:6500+2200*amount,y:0); out=f.outputImage ?? ci
    case .chrome: let f=CIFilter.photoEffectChrome(); f.inputImage=ci; out=f.outputImage ?? ci
    case .blur: let f=CIFilter.gaussianBlur(); f.inputImage=ci; f.radius=Float(amount*18); out=(f.outputImage ?? ci).cropped(to: ci.extent)
    case .poster: let f=CIFilter.colorPosterize(); f.inputImage=ci; f.levels=Float(3+amount*9); out=f.outputImage ?? ci
    case .original: break
    }
    guard let cg=context.createCGImage(out, from: ci.extent) else{return image}; return NSImage(cgImage: cg, size: image.size)
}

struct Waveform: View { let seed: Int; var body: some View { GeometryReader { g in HStack(alignment:.center,spacing:2) { ForEach(0..<46,id:\.self) { i in Capsule().fill(.white.opacity(0.82)).frame(width:max(1,(g.size.width-90)/46),height:6+CGFloat(abs((i*13+seed)%28))) } }.frame(maxHeight:.infinity) } } }
struct Seeded { var state: UInt64; init(seed: UInt64){state=seed|1}; mutating func next()->UInt64{state=state&*6364136223846793005&+1442695040888963407;return state} }
struct FlowLayout<Content: View>: View { let spacing: CGFloat; @ViewBuilder let content: Content; var body: some View { HStack(spacing:spacing){content}.frame(maxWidth:.infinity,alignment:.leading) } }
extension Color { init(hex:String){self.init(nsColor:NSColor(hex:hex) ?? .gray)} }
extension NSColor { convenience init?(hex:String){var s=hex;if s.hasPrefix("#"){s.removeFirst()};guard s.count==6,let v=UInt64(s,radix:16)else{return nil};self.init(red:CGFloat((v>>16)&255)/255,green:CGFloat((v>>8)&255)/255,blue:CGFloat(v&255)/255,alpha:1)} }
#else
@main struct LinuxBuildStub { static func main(){ print("ASSSETS requires macOS 14 or later.") } }
#endif
