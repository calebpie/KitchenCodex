import Foundation
import Testing
@testable import Capture

/// The accuracy pass's rules on made-up pages (phase2-plan "Slice 8"; ux-notes rows 69, 124, 125,
/// 131, 160, 166 and the phone's split titles): each a page laid out as the reader returns one,
/// with invented titles and lines.
@Suite("Accuracy pass")
struct AccuracyPassTests {
    typealias P = PagePipelineTests

    // MARK: - Titles

    @Test func aKeptSecondNameGetsASpacedEmDash() {
        // Row 69: OCR's hyphen with a space on one side between two names that both read as the
        // second language; a hyphen inside a word stays.
        #expect(PageLines.mendTitleDash("Orrindle -Crème d’Orrindle") == "Orrindle — Crème d’Orrindle")
        #expect(PageLines.mendTitleDash("Quillet- Pâté de Quillet") == "Quillet — Pâté de Quillet")
        #expect(PageLines.mendTitleDash("Braised Varnum—Varnum Braisé") == "Braised Varnum — Varnum Braisé")
        #expect(PageLines.mendTitleDash("Mint-Pistachio Pesto") == "Mint-Pistachio Pesto")
        // Both halves in the second language: both kept, the dash set off.
        #expect(PageRegionText.title(["SOUPE AUX ORRINDLES -CRÈME AUX ORRINDLES"]) == "Soupe aux Orrindles — Crème aux Orrindles")
    }

    @Test func aOneLineTitleReadAsTwoBlocksIsOneTitle() throws {
        // A phone reads a long title as two blocks side by side (ux-notes row 63); the second half
        // is level with the first, set in the same type, and the ingredient lines under it belong
        // to the one recipe's list.
        let scan = P.scan([
            P.block([P.line("Orrindle Gratin with", x: 0.18, y: 0.24, size: 0.022, spacing: 0.55)]),
            P.block([P.line("Pellow Crumbs", x: 0.44, y: 0.238, size: 0.022, spacing: 0.55)]),
            P.block([P.line("3 cups diced orrindle", x: 0.10, y: 0.30)]),
            P.block([P.line("1 cup grated quillet", x: 0.10, y: 0.316)]),
            P.block([P.line("2 tablespoons pellow crumbs", x: 0.10, y: 0.332)]),
            P.block([P.line("Varnum oil", x: 0.52, y: 0.30)]),
            P.block([P.line("Flaky salt", x: 0.52, y: 0.316)]),
            P.paragraph(["Toss the orrindle with the quillet and spread it in a wide", "dish, then scatter the crumbs over the top."], x: 0.10, y: 0.40, indent: 0.025),
            P.paragraph(["Bake until the crumbs brown and the dish bubbles at the", "edges, then let it settle before serving."], x: 0.10, y: 0.44, indent: 0.025),
        ])
        let reading = PageStructurer().read(scan)
        #expect(reading.recipes.count == 1)
        let recipe = try #require(reading.recipes.first)
        #expect(recipe.title == "Orrindle Gratin with Pellow Crumbs")
        #expect(recipe.ingredients.count == 5)
        #expect(recipe.steps.count == 2)
    }

    // MARK: - Steps

    @Test func onlyABrokenRunOfNumeralsFlagsTheStepCount() throws {
        // Row 124: three numbered steps and an unnumbered closing paragraph don't disagree with the
        // page; a gap in the numerals does.
        func page(numbers: [String]) -> PageScan {
            P.scan([
                P.block([P.line("Pickled Orrindles", x: 0.12, y: 0.10, size: 0.022, spacing: 0.55)]),
                P.block([P.line("6 orrindles, sliced", x: 0.12, y: 0.16)]),
                P.block([P.line("1 cup pale vinegar", x: 0.12, y: 0.176)]),
                P.paragraph(["\(numbers[0]) Slice the orrindles thinly and pack them into a clean jar with", "a lid, pressing them down."], x: 0.12, y: 0.22),
                P.paragraph(["\(numbers[1]) Bring the vinegar to a boil with a pinch of pellow and pour it", "over the orrindles to cover."], x: 0.12, y: 0.26),
                P.paragraph(["\(numbers[2]) Cool to room temperature, then refrigerate for a day before", "using; they keep for a month."], x: 0.12, y: 0.30),
            ])
        }
        let inOrder = try #require(PageStructurer().read(page(numbers: ["1", "2", "3"])).recipes.first)
        #expect(inOrder.steps.map(\.number) == [1, 2, 3])
        #expect(!inOrder.stepCountDisagrees)
        let gap = try #require(PageStructurer().read(page(numbers: ["1", "2", "4"])).recipes.first)
        #expect(gap.steps.map(\.number) == [1, 2, 4])
        #expect(gap.stepCountDisagrees)
        let repeated = try #require(PageStructurer().read(page(numbers: ["1", "2", "2"])).recipes.first)
        #expect(repeated.stepCountDisagrees)
        // The largest numeral short of the steps read is no reason: an unnumbered closing paragraph.
        var extra = P.leekPage(extraStep: true)
        _ = extra
        extra = page(numbers: ["1", "2", "Finally,"])
        let unnumberedEnd = try #require(PageStructurer().read(extra).recipes.first)
        #expect(unnumberedEnd.steps.count == 3)
        #expect(!unnumberedEnd.stepCountDisagrees)
    }

    @Test func aStepSetBesideTheIngredientsReadsInColumnOrder() throws {
        // Row 166: the method's third step runs on at the top right beside the headnote, the first
        // two under the ingredients at the left; the steps read column by column, each to its foot.
        let scan = P.scan([
            P.block([P.line("Quillet Cups with Pellow Dust", x: 0.13, y: 0.12, size: 0.020, spacing: 0.55)]),
            P.paragraph(["We first made these for a long table in the orchard, when", "the quillets were small and sweet; they keep for an hour", "or two once filled, which suits a crowd."], x: 0.13, y: 0.19),
            P.paragraph(["Fill each cup with a spoonful of the mash, dust the tops", "with pellow and set them on a cold plate until everyone", "is seated."], x: 0.54, y: 0.19),
            P.block([P.line("makes 5", x: 0.13, y: 0.35, size: 0.010)]),
            P.block([P.line("4 ripe quillets, halved", x: 0.13, y: 0.38)]),
            P.block([P.line("2 tablespoons varnum oil", x: 0.13, y: 0.396)]),
            P.block([P.line("1 pinch ground pellow", x: 0.13, y: 0.412)]),
            P.block([P.line("5 small cups or glasses", x: 0.13, y: 0.428)]),
            P.paragraph(["Scoop the quillet flesh into a bowl and crush it with a", "fork, leaving some pieces whole."], x: 0.13, y: 0.54),
            P.paragraph(["Stir in the varnum oil, taste for salt, and chill the mash", "for half an hour while you set out the cups."], x: 0.13, y: 0.60),
        ])
        let recipe = try #require(PageStructurer().read(scan).recipes.first)
        #expect(recipe.ingredients.count == 4)
        #expect(recipe.steps.count == 3)
        #expect(recipe.steps[0].text.hasPrefix("Scoop the quillet"))
        #expect(recipe.steps[1].text.hasPrefix("Stir in the varnum"))
        #expect(recipe.steps[2].text.hasPrefix("Fill each cup"))
        #expect(recipe.headnote?.hasPrefix("We first made") == true)
    }

    @Test func numberedStepsReadByTheirNumerals() {
        let steps = [PageStep(text: "c", number: 3, blocks: []), PageStep(text: "a", number: 1, blocks: []), PageStep(text: "b", number: 2, blocks: [])]
        #expect(PageStructurer.stepOrder(steps, rects: [[.zero], [.zero], [.zero]]) == [1, 2, 0])
        // Without numerals and in one column, as read.
        let plain = steps.map { PageStep(text: $0.text, blocks: []) }
        let column = [[PageRect(x: 0.1, y: 0.5, width: 0.3, height: 0.02)], [PageRect(x: 0.1, y: 0.6, width: 0.3, height: 0.02)], [PageRect(x: 0.1, y: 0.7, width: 0.3, height: 0.02)]]
        #expect(PageStructurer.stepOrder(plain, rects: column) == [0, 1, 2])
    }

    // MARK: - Continued lines

    @Test func aContinuedLineIsFurnitureAndTheStitchersCue() throws {
        // Row 131: "continued" at the first page's foot is no step, and the next page continues
        // the recipe though the first closed with its yield and a full stop.
        #expect(PageLines.isContinuedLine("continued"))
        #expect(PageLines.isContinuedLine("(continued on next page)"))
        #expect(PageLines.isContinuedLine("Braised Lamb Shanks, continued"))
        #expect(PageLines.isContinuedLine("recipe continues"))
        #expect(PageLines.isContinuedLine("Continued from previous page"))
        #expect(!PageLines.isContinuedLine("Continue to cook until the sauce thickens, about 10 minutes."))
        #expect(!PageLines.isContinuedLine("Continue"))
        let first = P.scan([
            P.block([P.line("Slow Onion Tart", x: 0.10, y: 0.08, size: 0.024, spacing: 0.55)]),
            P.block([P.line("Serves 6", x: 0.10, y: 0.12)]),
            P.block([P.line("1 sheet puff pastry", x: 0.10, y: 0.14)]),
            P.block([P.line("6 onions, thinly sliced", x: 0.10, y: 0.156)]),
            P.paragraph(["Cook the onions slowly in butter until deep brown, about", "an hour, stirring now and then."], x: 0.10, y: 0.20, indent: 0.025),
            P.paragraph(["Heat the oven to 400°F. Roll out the pastry and spread", "the onions over it, leaving a border."], x: 0.10, y: 0.24, indent: 0.025),
            P.block([P.line("continued", x: 0.10, y: 0.86, size: 0.011)]),
            P.block([P.line("210", x: 0.10, y: 0.92, size: 0.009)]),
        ])
        let second = P.scan([
            P.paragraph(["Bake until puffed and golden, 25 minutes, then cool a little", "on the sheet before cutting."], x: 0.10, y: 0.10, indent: 0.025),
            P.paragraph(["Serve warm or at room temperature, in squares, with a green salad", "dressed with a sharp mustard vinaigrette."], x: 0.10, y: 0.14, indent: 0.025),
            P.block([P.line("212", x: 0.10, y: 0.92, size: 0.009)]),
        ])
        let structurer = PageStructurer()
        let readings = [structurer.read(first, file: "a.heic"), structurer.read(second, file: "b.heic")]
        let opening = try #require(readings[0].recipes.first)
        #expect(opening.steps.count == 2)
        #expect(opening.continuesOverPage)
        #expect(readings[0].blocks.first { $0.text == "continued" }?.role == .furniture)
        #expect(readings[1].isContinuation)
        let stitched = PageStitcher.stitch(readings)
        #expect(stitched.count == 1)
        #expect(stitched.first?.recipes.first?.steps.count == 4)
    }

    @Test func theVeryNextPageContinuesARecipeThatClosedCleanly() throws {
        // Row 131's neighbour: a titleless page of steps numbered one after a finished recipe's
        // page continues it; a page from elsewhere in the book does not.
        let first = PageStructurer().read(P.leekPage(folio: "216"), file: "a")
        let steps = P.scan([
            P.paragraph(["Serve warm, with the pan juices spooned over the top and a", "little more mustard on the side."], x: 0.12, y: 0.10, indent: 0.025),
            P.paragraph(["Leftovers keep for three days and are good cold, sliced into", "a salad with the dressing."], x: 0.12, y: 0.14, indent: 0.025),
        ])
        let next = PageStructurer().read(steps, file: "b")
        #expect(next.isContinuation)
        var adjacent = next
        adjacent.pageNumbers = [217]
        #expect(PageStitcher.stitch([first, adjacent]).count == 1)
        var elsewhere = next
        elsewhere.pageNumbers = [240]
        #expect(PageStitcher.stitch([first, elsewhere]).count == 2)
    }

    // MARK: - Layouts

    @Test func aLayoutDifferingOnlyInTheIngredientsPlacementIsConfirmed() {
        // Row 125.
        let confirmed: Set<String> = ["t:wc i:left-1 m:para-1"]
        #expect(LayoutSignature.matches("t:wc i:left-1 m:para-1", confirmed: confirmed))
        #expect(LayoutSignature.matches("t:wc i:right-n m:para-1", confirmed: confirmed))
        #expect(!LayoutSignature.matches("t:s i:left-1 m:para-1", confirmed: confirmed))
        #expect(!LayoutSignature.matches("t:wc i:left-1 m:num-2", confirmed: confirmed))
        #expect(!LayoutSignature.matches("t:wc i:right-n m:para-1", confirmed: []))
        var recipe = PageRecipe(title: "A", layoutSignature: "t:wc i:right-n m:para-1")
        recipe.confidence = PageConfidence(ocr: 0.6, parser: 1, structure: 1)
        #expect(recipe.reviewReasons(bookHasRecipes: true, reviewedLayouts: confirmed).isEmpty)
        #expect(recipe.reviewReasons(bookHasRecipes: true, reviewedLayouts: []) == [.unseenLayout])
    }

    // MARK: - Folios and languages

    @Test func theMarginPassFillsOnlyAMissingFolio() {
        // Row 160: the page-wide pass's number stands; the margin crops' number fills a gap, and a
        // crop's "• 17" reads as 17.
        var reading = PageReading(files: ["a"], blocks: [], kind: .recipe, pageNumbers: [16])
        reading.pageNumberConfidence = 0.3
        #expect(!PagePipeline.prefersMarginFolio(reading, margins: 10))
        reading.pageNumbers = [nil]
        #expect(PagePipeline.prefersMarginFolio(reading, margins: 10))
        #expect(PageStructurer.folioNumber(in: ["• 17", "something else"]) == 17)
        #expect(PageStructurer.folioNumber(in: ["Makes 4 servings", "— 212"]) == 212)
    }

    @Test func linesInAnotherScriptAreSetAside() {
        // Row 126: a Latin word read in Cyrillic letters is a misreading; a Latin line with an
        // accented letter or two is not.
        #expect(PageReader.isMostlyNonLatin("Бурре"))
        #expect(!PageReader.isMostlyNonLatin("Crème fraîche"))
        #expect(!PageReader.isMostlyNonLatin("2 cups"))
        #expect(PageReader.language(forCode: "fr")?.minimalIdentifier == "fr")
        #expect(PageReader.language(forCode: "xx") == nil)
        #expect(PageLines.alternateLanguage(["Roast Duck—Canard Rôti aux Navets"], pageLanguage: .english) == .french)
        #expect(PageLines.alternateLanguage(["Mint-Pistachio Pesto"], pageLanguage: .english) == nil)
    }

    @Test func aGlossaryPageWithTwoStrayIngredientLinesIsStillAGlossary() throws {
        // Two short lines a glossary's columns set like an ingredient run, under no title, don't
        // make the page a recipe's continuation.
        var blocks: [PageBlock] = []
        let terms = ["Varnum", "Quillet", "Brisket Stone", "Orrindle", "Pellow"]
        var y = 0.12
        for term in terms {
            blocks.append(P.block([P.line(term, x: 0.10, y: y, size: 0.012)]))
            blocks.append(P.paragraph(["A made-up thing for the test, kept in a cool place and used in", "small amounts; it reads as a definition and not as a step."], x: 0.10, y: y + 0.016))
            y += 0.07
        }
        blocks.append(P.block([P.line("2 cups sifted gravel", x: 0.52, y: 0.12)]))
        blocks.append(P.block([P.line("1 pinch sand", x: 0.52, y: 0.136)]))
        blocks.append(P.paragraph(["Another made-up definition that runs on for a line or two in the", "second column, as the page's columns do."], x: 0.52, y: 0.17))
        let reading = PageStructurer().read(P.scan(blocks))
        #expect(reading.kind == .prose)
        #expect(reading.reference?.kind == .glossary)
        #expect((reading.reference?.sections.count ?? 0) >= 5)
    }
}
