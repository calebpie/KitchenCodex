import Foundation
import Testing
@testable import Capture

/// Reference reading off a scanned page (02 §4.2, 04 §5.1 "Page pointers"): a glossary page whose
/// sections are its entries, a chapter opener, a technique, and the pages that are not one. The
/// pages are made up, laid out as `PagePipelineTests` lays its pages out.
@Suite("Reference pages")
struct ReferenceReaderTests {
    typealias Pages = PagePipelineTests

    /// A term on its own line over its definition, three times, under a running head.
    static func glossaryPage() -> PageScan {
        Pages.scan([
            Pages.block([Pages.line("GLOSSARY", x: 0.12, y: 0.05, size: 0.009)]),
            Pages.block([Pages.line("Kombu", x: 0.12, y: 0.12)]),
            Pages.paragraph([
                "A dried kelp sold in stiff, dusty sheets. It is the backbone of the stock in",
                "this book: soaked in cold water, warmed slowly and lifted out before the boil.",
            ], x: 0.12, y: 0.138),
            Pages.block([Pages.line("Konnyaku", x: 0.12, y: 0.19)]),
            Pages.paragraph([
                "A firm grey jelly that turns springy when simmered. Simmer it in the",
                "finest side of the grater and season it at the last moment.",
            ], x: 0.12, y: 0.208),
            Pages.block([Pages.line("Yuzu", x: 0.12, y: 0.26)]),
            Pages.paragraph([
                "A small, knobbly citrus with a fragrance somewhere between a mandarin and a",
                "grapefruit. The zest is used far more than the juice.",
            ], x: 0.12, y: 0.278),
            Pages.block([Pages.line("252", x: 0.12, y: 0.92, size: 0.009)]),
        ])
    }

    @Test func readsAGlossaryPageIntoEntries() throws {
        let reading = PageStructurer().read(Self.glossaryPage(), file: "glossary.heic")
        #expect(reading.kind == .prose)
        #expect(reading.recipes.isEmpty)
        #expect(reading.pageNumber == 252)
        let reference = try #require(reading.reference)
        #expect(reference.kind == .glossary)
        #expect(reference.title == "Glossary")
        #expect(reference.sections.map(\.heading) == ["Kombu", "Konnyaku", "Yuzu"])
        #expect(reference.sections[1].body.hasPrefix("A firm grey jelly"))
        #expect(reference.reason == "a glossary page: 3 entries")
        // Not a page the stitcher would join to the one before.
        #expect(!reading.isContinuation)
    }

    @Test func readsTermsSetInOneLineWithTheirDefinitions() {
        let lines = [
            "Kombu: A dried kelp sold in stiff, dusty sheets, the backbone of the stock in this book and most others.",
            "KONNYAKU Firm grey jelly that turns springy when simmered and is seasoned at the last moment.",
            "Yuzu — A small, knobbly citrus with a fragrance between a mandarin and a grapefruit, used for its zest.",
            "Shiso: A broad, jagged leaf of the mint family, green or purple, eaten raw with fish and in pickles.",
        ]
        let blocks = lines.enumerated().map { Pages.block([Pages.line($0.element, x: 0.12, y: 0.12 + Double($0.offset) * 0.03)]) }
        let reading = PageStructurer().read(Pages.scan(blocks))
        #expect(reading.reference?.kind == .glossary)
        #expect(reading.reference?.sections.map(\.heading) == ["Kombu", "Konnyaku", "Yuzu", "Shiso"])
        #expect(reading.reference?.sections[1].body.hasPrefix("Firm grey jelly") == true)
    }

    /// Terms set in lowercase over their definitions, in two columns, each column one block, as
    /// the recognizer often reads a printed glossary. The terms keep the page's case.
    @Test func readsLowercaseTermsLineByLine() throws {
        let column = { (x: Double, lines: [String]) -> PageBlock in
            Pages.block(lines.enumerated().map { Pages.line($0.element, x: x, y: 0.12 + Double($0.offset) * 0.016) })
        }
        let page = Pages.scan([
            Pages.block([Pages.line("Glossary", x: 0.10, y: 0.06, size: 0.022, spacing: 0.55)]),
            column(0.10, [
                "kombu",
                "A dried kelp sold in stiff, dusty sheets, the",
                "backbone of the stock in this book.",
                "mirin",
                "A sweet rice wine for cooking, syrupy and golden;",
                "it gives glazes their shine.",
                "konnyaku",
                "A firm grey jelly that turns springy",
                "when simmered. Season it at the last moment.",
            ]),
            column(0.55, [
                "shiso",
                "A broad, jagged leaf of the mint family, eaten",
                "raw with fish and in pickles.",
                "yuzu",
                "A small, knobbly citrus; the zest is used far",
                "more than the juice.",
            ]),
        ])
        let reading = PageStructurer().read(page)
        let reference = try #require(reading.reference)
        #expect(reference.kind == .glossary)
        #expect(reference.title == "Glossary")
        #expect(reference.sections.map(\.heading) == ["kombu", "mirin", "konnyaku", "shiso", "yuzu"])
        #expect(reference.sections[2].body == "A firm grey jelly that turns springy when simmered. Season it at the last moment.")
    }

    @Test func readsAChapterOpenerAndATechnique() throws {
        let opener = Pages.scan([
            Pages.block([Pages.line("Soups", x: 0.12, y: 0.10, size: 0.026, spacing: 0.55)]),
            Pages.paragraph([
                "The soups in this chapter are the ones we cook at home on the nights the restaurant",
                "is closed. None of them asks for more than a pot, a ladle and an hour, and most of",
                "them are better the next day, which is the point of making a potful.",
            ], x: 0.12, y: 0.18),
            Pages.paragraph([
                "A word on stock. Water is fine for the vegetable soups; the others want the stock on",
                "page 212, which keeps for a week in the fridge and far longer in the freezer.",
            ], x: 0.12, y: 0.24),
        ])
        let reading = PageStructurer().read(opener)
        let reference = try #require(reading.reference)
        #expect(reading.kind == .prose)
        #expect(reference.kind == .chapter)
        #expect(reference.title == "Soups")
        #expect(reference.sections.count == 1)
        #expect(reference.sections[0].heading.isEmpty)
        #expect(reference.sections[0].body.contains("A word on stock."))

        let technique = Pages.scan([
            Pages.block([Pages.line("How to Clean Squid", x: 0.12, y: 0.10, size: 0.024, spacing: 0.55)]),
            Pages.paragraph([
                "Pull the head and tentacles away from the body in one motion; the innards come with",
                "them. Cut the tentacles off just below the eyes and press out the hard beak.",
            ], x: 0.12, y: 0.17, indent: 0.025),
            Pages.paragraph([
                "Reach into the body and pull out the clear quill. Peel the speckled skin away under",
                "running water, rinse the inside and pat everything dry before it goes near heat.",
            ], x: 0.12, y: 0.215, indent: 0.025),
            Pages.block([Pages.line("Keeping It", x: 0.12, y: 0.27, size: 0.018, spacing: 0.55)]),
            Pages.paragraph([
                "Cleaned squid keeps for a day on ice in the coldest part of the fridge, and freezes",
                "better than most seafood: it is one of the few things that loses nothing there.",
            ], x: 0.12, y: 0.30, indent: 0.025),
        ])
        let read = PageStructurer().read(technique)
        let write = try #require(read.reference)
        #expect(write.kind == .technique)
        #expect(write.title == "How to Clean Squid")
        #expect(write.sections.map(\.heading) == ["", "Keeping It"])
    }

    @Test func leavesRecipesAndTheirContinuationsAlone() {
        // A recipe page is never reference reading.
        let recipe = PageStructurer().read(Pages.leekPage())
        #expect(recipe.kind == .recipe)
        #expect(recipe.reference == nil)
        // A page that opens mid-method, no title, instructions all the way: the stitcher's.
        let continuation = Pages.scan([
            Pages.paragraph([
                "until the onions are soft and sweet, about 20 minutes. Add the stock and bring to",
                "a simmer, then cook until the potatoes fall apart when pressed against the pot.",
            ], x: 0.12, y: 0.12),
            Pages.paragraph([
                "Blend until smooth, in batches if the pot is full, and pass through a sieve if you",
                "want it silky. Season with salt and a squeeze of lemon and serve hot.",
            ], x: 0.12, y: 0.17, indent: 0.025),
            Pages.paragraph([
                "Serve in warm bowls with a spoon of crème fraîche and a scattering of chives, or let",
                "it cool and keep it for two days in the fridge, where it thickens a little.",
            ], x: 0.12, y: 0.22, indent: 0.025),
        ])
        let reading = PageStructurer().read(continuation)
        #expect(reading.kind == .recipe)
        #expect(reading.isContinuation)
        #expect(reading.reference == nil)
    }
}
