import CoreGraphics
import Foundation
import Testing
@testable import Intelligence

@Suite("Page structuring")
struct PageStructuringTests {
    /// Hand-written, as a photographed page's recognized text arrives: a running head, the recipe,
    /// a folio.
    static let pageText = """
        SOUPS AND STEWS
        Weeknight Leek Soup
        This is the soup we make when the first leeks arrive.
        3 large leeks, white and light green parts, sliced
        2 tablespoons unsalted butter
        1 quart chicken stock
        Kosher salt
        Melt the butter in a large pot over medium heat. Add the leeks and a pinch of salt and cook until soft, about 10 minutes.
        Add the stock, bring to a simmer and cook for 20 minutes. Season to taste.
        MAKES 4 SERVINGS
        42
        """

    /// A stand-in that reads nothing from images, to check the protocol's defaults.
    struct TextOnly: PageStructuring {
        var isAvailable: Bool { true }
        func structure(pageText: String) async throws -> StructuredPageDraft {
            StructuredPageDraft(title: "From text", ingredients: ["1 leek"], steps: ["Cook."], confidence: 0.5)
        }
    }

    @Test func imageInputFallsBackToTextByDefault() async throws {
        let structurer = TextOnly()
        #expect(!structurer.acceptsImages)
        let context = try #require(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0))
        let image = try #require(context.makeImage())
        let draft = try await structurer.structure(pageText: Self.pageText, image: image)
        #expect(draft.title == "From text")
    }

    /// A structurer that only reads recipes says so when asked for a contents page, so Capture keeps
    /// its own reading.
    @Test func contentsAreUnsupportedByDefault() async {
        await #expect(throws: ModelUnavailabilityError(reason: .notConfigured)) {
            try await TextOnly().structureContents(pageText: Self.contentsText)
        }
    }

    /// A made-up contents page as the recognizer reads it, columns in reading order.
    static let contentsText = """
        CONTENTS
        INTRODUCTION 9
        SOUPS 14
        Weeknight Leek Soup 16
        Chilled Cucumber Soup with
        Dill & Yogurt 18
        SALADS 22
        Shaved Fennel Salad 24
        Warm Lentil Salad 27
        """

    @Test(.enabled(if: ProcessInfo.processInfo.environment["RECIPE_CODEX_PAGE_MODEL"] == "1" && OnDevicePageStructurer().isAvailable,
                   "Set RECIPE_CODEX_PAGE_MODEL=1 on a host with Apple Intelligence to run the model"),
          .timeLimit(.minutes(2)))
    func readsAContentsPageWithTheModel() async throws {
        let draft = try await OnDevicePageStructurer().structureContents(pageText: Self.contentsText)
        let entries = draft.sections.flatMap(\.entries)
        #expect(entries.count >= 3)
        #expect(entries.contains { $0.page == 24 })
        #expect(draft.sections.contains { $0.title.localizedCaseInsensitiveContains("salad") })
    }

    @Test func availabilityIsAnAnswerNotACrash() {
        let structurer = OnDevicePageStructurer()
        switch ModelAvailability.onDevice() {
        case .success: #expect(structurer.isAvailable)
        case .failure:
            #expect(!structurer.isAvailable)
            #expect(!structurer.acceptsImages)
        }
    }

    @Test func throwsWhenTheModelIsUnavailable() async {
        guard !OnDevicePageStructurer().isAvailable else { return }
        await #expect(throws: ModelUnavailabilityError.self) {
            try await OnDevicePageStructurer().structure(pageText: Self.pageText)
        }
    }

    /// The model only when asked (`RECIPE_CODEX_PAGE_MODEL=1`) and present, so a test run never
    /// waits on it otherwise.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["RECIPE_CODEX_PAGE_MODEL"] == "1" && OnDevicePageStructurer().isAvailable,
                   "Set RECIPE_CODEX_PAGE_MODEL=1 on a host with Apple Intelligence to run the model"),
          .timeLimit(.minutes(2)))
    func readsAPageWithTheModel() async throws {
        let draft = try await OnDevicePageStructurer().structure(pageText: Self.pageText)
        #expect(draft.title.localizedCaseInsensitiveContains("leek"))
        #expect(draft.ingredients.count >= 3)
        #expect(draft.steps.count >= 1)
        #expect(draft.confidence == OnDevicePageStructurer.reportedConfidence)
    }
}
