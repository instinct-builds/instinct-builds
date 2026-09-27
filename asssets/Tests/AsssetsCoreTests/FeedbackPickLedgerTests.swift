import Foundation
import Testing
@testable import AsssetsCore

@Suite("Feedback pick replacement and migration")
struct FeedbackPickLedgerTests {
    typealias E = ReviewGallery.Feedback.Entry
    func fixture(legacy: Bool = false) -> (StudioCatalog, UUID, UUID, String) {
        var c = StudioCatalog()
        let a = c.importFile(path: "/x/one.png")!, b = c.importFile(path: "/x/two.png")!
        if legacy { c.assets[0].tags.append(ReviewGallery.clientPickTag) }
        let gallery = UUID().uuidString
        _ = c.recordGallery(GalleryRoster(gallery: gallery, title: "Round", created: "2026-09-26", assets: [a, b])!)
        return (c, a, b, gallery)
    }
    func feedback(_ gallery: String, _ who: String, _ entries: [E]) -> ReviewGallery.Feedback {
        .init(gallery: gallery, title: "Round", reviewer: who, items: entries)
    }
    @Test func withdrawalAndOtherReviewer() throws {
        var (c, a, b, g) = fixture()
        let mara = feedback(g, "Mara", [.init(id: a.uuidString, favorite: true, note: "")])
        let sam = feedback(g, "Sam", [.init(id: a.uuidString, favorite: true, note: "")])
        let first = c.applyFeedback(mara)
        #expect(first.favorites == 1)
        let second = c.applyFeedback(sam)
        #expect(second.favorites == 1)
        let noPick = feedback(g, "Mara", [.init(id: a.uuidString, favorite: false, note: "")])
        let p = c.previewFeedback(noPick)
        #expect(p.replaces && p.withdrawals == 1 && p.canImport && p.rows[0].remainsPicked)
        let third = c.applyFeedback(noPick)
        #expect(third.withdrawn == 1)
        #expect(c.assets.first { $0.id == a }!.tags.contains(ReviewGallery.clientPickTag))
        let empty = feedback(g, "Sam", [])
        #expect(c.previewFeedback(empty).withdrawals == 1 && c.previewFeedback(empty).canImport)
        let fourth = c.applyFeedback(empty)
        #expect(fourth.withdrawn == 1)
        #expect(!c.assets.first { $0.id == a }!.tags.contains(ReviewGallery.clientPickTag))
        #expect(c.feedbackRound(gallery: g, reviewer: "Sam")?.assets.isEmpty == true)
        let back = StudioCatalog.decode(try c.encoded())!
        #expect(back.feedbackPickLedger == c.feedbackPickLedger && back.ledgerOwnedPickTags == c.ledgerOwnedPickTags)
        #expect(back.assets.first { $0.id == b }!.tags == c.assets.first { $0.id == b }!.tags)
    }
    @Test func legacyTagsNeverAttributedAndOutsiderOnlyCannotWithdraw() throws {
        var (c, a, b, g) = fixture(legacy: true)
        let old = StudioCatalog.decode(try c.encoded())!
        #expect(old.feedbackPickLedger.isEmpty && old.ledgerOwnedPickTags.isEmpty)
        _ = c.applyFeedback(feedback(g, "Mara", [.init(id: a.uuidString, favorite: true, note: ""), .init(id: b.uuidString, favorite: true, note: "")]))
        #expect(c.preservedPickTags.contains(a) && !c.preservedPickTags.contains(b))
        let outsider = feedback(g, "Mara", [.init(id: UUID().uuidString, favorite: true, note: "")])
        #expect(c.previewFeedback(outsider).withdrawals == 0)
        let ignored = c.applyFeedback(outsider)
        #expect(ignored.unknown == 1)
        #expect(c.feedbackRound(gallery: g, reviewer: "Mara")?.assets.count == 2)
        let empty = feedback(g, "Mara", [])
        let removed = c.applyFeedback(empty)
        #expect(removed.withdrawn == 2)
        #expect(c.assets.first { $0.id == a }!.tags.contains(ReviewGallery.clientPickTag))
        #expect(!c.assets.first { $0.id == b }!.tags.contains(ReviewGallery.clientPickTag))
        let back = StudioCatalog.decode(try c.encoded())!
        #expect(back.preservedPickTags == Set([a]) && back.feedbackPickLedger == c.feedbackPickLedger)
    }
    @Test func emptyReplacementClearsBoardPickButNotApproval() {
        var (c, a, _, g) = fixture()
        let board = c.createBoard(named: "Round")
        _ = c.addToBoard(board, assets: [a])
        let card = c.board(board)!.items[0].id
        c.galleryRosters = [GalleryRoster(gallery: g, title: "Round", created: "2026-09-26", assets: [a],
            board: board, cards: [.init(id: card, asset: a)])!]
        let first = feedback(g, "Mara", [.init(id: a.uuidString, favorite: true, note: "", status: "approved")])
        _ = c.applyFeedback(first)
        #expect(c.board(board)!.status(of: card) == .approved && c.board(board)!.pins()[card]?.picked == true)
        let empty = feedback(g, "Mara", [])
        let removed = c.applyFeedback(empty)
        #expect(removed.withdrawn == 1)
        #expect(c.board(board)!.status(of: card) == .approved)
        #expect(c.board(board)!.pins()[card] == nil)
    }

}
