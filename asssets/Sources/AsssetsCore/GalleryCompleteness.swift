import Foundation

/// The manifest must describe every requested image exactly once, with all referenced outputs present.
public enum GalleryCompleteness {
    public static func valid(requested: [UUID], manifest: ReviewGallery.Manifest, files: Set<String>,
                             requiredLicenses: [String] = [], needsBoard: Bool = false, needsSummary: Bool = false) -> Bool {
        guard !requested.isEmpty, requested.count == Set(requested).count,
              manifest.items.count == requested.count,
              manifest.items.map(\.id) == requested.map(\.uuidString),
              files.contains("index.html"),
              manifest.items.allSatisfy({ item in
                  item.image.hasPrefix("images/") && item.thumb.hasPrefix("thumbs/") &&
                  files.contains(item.image) && files.contains(item.thumb)
              }),
              !needsBoard || (manifest.board?.image == "board.png" && files.contains("board.png")),
              !needsSummary || (manifest.summary == "round-summary.pdf" && files.contains("round-summary.pdf")),
              requiredLicenses.allSatisfy(files.contains) else { return false }
        return true
    }
}
