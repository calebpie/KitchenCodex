import Foundation
import Testing
@testable import Capture

/// The saved recipe pages in `Docs/Fixtures/Private/HTML` (copyrighted, so gitignored): each must
/// import as `Fixtures/private-fixtures.json` says. The manifest holds titles and counts only.
/// Skipped, with the reason recorded, in checkouts without the pages (CI, cloud sessions).
@Suite("Web import, saved pages", .enabled(if: Fixtures.privatePagesAvailable, Fixtures.privateSkipReason))
struct PrivateFixtureTests {
    @Test("Imports as recorded", arguments: Fixtures.expectations)
    func importsAsRecorded(_ expected: Fixtures.Expectation) throws {
        let html = try Fixtures.privatePage(expected.file)
        let recipe = WebRecipeImporter.extract(html: html, url: nil).recipe
        let hint: Comment = "If this change is an improvement, update Fixtures/private-fixtures.json."

        guard let method = expected.method else {
            #expect(recipe == nil, hint)
            return
        }
        let imported = try #require(recipe)
        #expect(imported.method?.rawValue == method, hint)
        #expect(!imported.title.isEmpty)
        #expect(imported.title == expected.title, hint)
        #expect(imported.ingredients.count >= 3)
        // At least two steps, unless the manifest notes why the page has fewer.
        #expect(imported.steps.count >= (expected.note == nil ? 2 : 1))
        #expect(imported.ingredients.count == expected.ingredients, hint)
        #expect(imported.steps.count == expected.steps, hint)
        // Structured data is trusted; the page-text reading always asks for a review.
        #expect(imported.needsReview == (method == ImportMethod.pageText.rawValue))
    }

    @Test func everySavedPageHasAnExpectation() {
        let recorded = Set(Fixtures.expectations.map(\.file))
        let missing = Fixtures.privatePageNames().filter { !recorded.contains($0) }
        #expect(missing.isEmpty, "Add these pages to Fixtures/private-fixtures.json: \(missing)")
    }
}

/// Runs everywhere, including checkouts without the saved pages.
@Suite("Saved-page manifest")
struct PrivateFixtureManifestTests {
    @Test func manifestHoldsNoPageText() throws {
        // Titles and counts only: no entry carries ingredient or step text.
        let url = try #require(Bundle.module.url(forResource: "private-fixtures", withExtension: "json", subdirectory: "Fixtures"))
        let entries = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        let allowed: Set<String> = ["file", "title", "method", "ingredients", "steps", "note"]
        #expect(!entries.isEmpty)
        for entry in entries {
            #expect(Set(entry.keys).isSubset(of: allowed))
        }
    }
}
