import Foundation
import Testing
@testable import AsssetsCore

@Suite("Complete gallery output")
struct GalleryCompletenessTests {
    @Test func missingOrDroppedAssetIsNotReady() {
        let a = UUID(), b = UUID()
        let item = ReviewGallery.Item(id: a.uuidString, title: "A", kind: "Image", resolution: "", palette: [], tags: [], image: "images/01.jpg", thumb: "thumbs/01.jpg")
        let manifest = ReviewGallery.Manifest(title: "Review", created: "2026-09-26", items: [item])
        let files: Set<String> = ["index.html", "images/01.jpg", "thumbs/01.jpg"]
        #expect(GalleryCompleteness.valid(requested: [a], manifest: manifest, files: files))
        #expect(!GalleryCompleteness.valid(requested: [a,b], manifest: manifest, files: files))
        #expect(!GalleryCompleteness.valid(requested: [a], manifest: manifest, files: ["index.html", "images/01.jpg"]))
        #expect(!GalleryCompleteness.valid(requested: [a], manifest: manifest, files: files, requiredLicenses: ["licenses/order.pdf"]))
        #expect(!GalleryCompleteness.valid(requested: [a], manifest: manifest, files: files, needsBoard: true))
        #expect(!GalleryCompleteness.valid(requested: [a], manifest: manifest, files: files, needsSummary: true))
    }
}
