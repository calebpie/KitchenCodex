import CoreGraphics
import Foundation
import Testing
@testable import Capture

/// The camera's cleanup (Phase 2 slice 4) over Caleb's private page photos, which were taken with
/// the phone as a capture would be: each photo read as it is and again after the page is found,
/// deskewed, cropped, levelled and sharpened, and the two readings compared by their counts. Prints
/// counts only. About three minutes, so it runs only when asked: `RECIPE_CODEX_CLEANUP=1`, with
/// `CLEANUP_VARIANT` = `both` (the camera's cleanup, the default), `crop`, `enhance` (levels and
/// sharpening on the whole frame) or `levels` (crop and levels, no sharpening).
@Suite("Page cleanup, private page photos", .enabled(if: PageFixtures.available && ProcessInfo.processInfo.environment["RECIPE_CODEX_CLEANUP"] == "1", "Set RECIPE_CODEX_CLEANUP=1 to compare cleaned pages (needs Docs/Fixtures/Private/Pages)"), .serialized)
struct PrivatePageCleanupTests {
    @Test(.timeLimit(.minutes(30)))
    func cleanedPagesReadAsTheOriginalsDo() async throws {
        let pipeline = PagePipeline()
        var compared = 0, cropped = 0
        var differences: [String] = []
        for book in PageFixtures.books() {
            for file in book.files.dropFirst() {
                let image = try PageImage.load(contentsOf: file)
                let original = try await pipeline.readPage(image, file: file.lastPathComponent, page: 0, of: 1, quality: nil, progress: nil)
                let variant = ProcessInfo.processInfo.environment["CLEANUP_VARIANT"] ?? "both"
                let page = variant == "enhance" ? nil : await PageCleanup.detectPage(in: image)
                if page != nil { cropped += 1 }
                let cleaned = try #require(PageCleanup.clean(image, page: page, enhances: variant != "crop", sharpens: variant != "levels"))
                let read = try await pipeline.readPage(cleaned, file: file.lastPathComponent, page: 0, of: 1, quality: original.quality, progress: nil)
                compared += 1
                let before = Self.counts(original.reading), after = Self.counts(read.reading)
                if before != after {
                    differences.append("\(book.slug)/\(file.lastPathComponent) (\(page == nil ? "whole frame" : "cropped")): \(before) → \(after)")
                }
            }
        }
        print("Cleanup: \(compared) photos, \(cropped) cropped to a detected page, \(differences.count) read differently")
        for line in differences { print("  " + line) }
        #expect(compared > 0)
    }

    /// Kind, page number, and per recipe its ingredient, unparsed and step counts.
    static func counts(_ reading: PageReading) -> String {
        let recipes = reading.recipes.map { "\($0.ingredients.count)i\($0.unparsedIngredientCount > 0 ? "/\($0.unparsedIngredientCount)u" : "") \($0.steps.count)s\($0.title.isEmpty ? " untitled" : "")" }
        return "\(reading.kind.rawValue)\(reading.isContinuation ? "+" : "") p\(reading.pageNumber.map(String.init) ?? "–") [\(recipes.joined(separator: ", "))]"
    }
}
