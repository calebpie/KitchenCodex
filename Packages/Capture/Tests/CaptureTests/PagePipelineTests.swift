import CoreGraphics
import CoreImage
import CoreText
import Foundation
import ImageIO
import Intelligence
import Synchronization
import Testing
@testable import Capture

/// The page pipeline on hand-made pages: blocks laid out as a reader would return them, and a page
/// rendered with Core Text for the reader and the gate. The text is made up. The private photos are
/// `PrivatePageTests`'.
@Suite("Page pipeline")
struct PagePipelineTests {
    // MARK: - Hand-made blocks

    /// A line at (x, y) in unit page coordinates; body type is about 0.012 of the page high with
    /// letters half as wide.
    static func line(_ text: String, x: Double, y: Double, size: Double = 0.012, spacing: Double = 0.5, confidence: Double = 0.65) -> PageTextLine {
        PageTextLine(text: text, rect: PageRect(x: x, y: y, width: Double(text.count) * size * spacing, height: size), confidence: confidence, size: size)
    }

    static func block(_ lines: [PageTextLine], kind: PageBlock.Kind? = nil) -> PageBlock {
        let rect = lines.dropFirst().reduce(lines[0].rect) { $0.union($1.rect) }
        return PageBlock(id: 0, kind: kind ?? (lines.count == 1 ? .line : .paragraph), rect: rect, lines: lines)
    }

    /// Lines of a paragraph from `y`, one every 0.016; the first indented by `indent`.
    static func paragraph(_ texts: [String], x: Double, y: Double, indent: Double = 0) -> PageBlock {
        block(texts.enumerated().map { line($0.element, x: x + ($0.offset == 0 ? indent : 0), y: y + Double($0.offset) * 0.016) })
    }

    static func scan(_ blocks: [PageBlock], duration: Duration = .zero) -> PageScan {
        var ordered = ReadingOrder.sorted(blocks)
        for index in ordered.indices { ordered[index].id = index }
        var scan = PageScan(blocks: ordered, paper: PageRect(x: 0.02, y: 0.02, width: 0.96, height: 0.96), duration: duration)
        scan.pageCore = scan.paper
        scan.paperFraction = 0.9
        return scan
    }

    /// A one-column recipe page: title, headnote, yield, ingredients, a method of two paragraphs
    /// with first-line indents, a folio.
    static func leekPage(folio: String = "34 | Vegetables", extraStep: Bool = false) -> PageScan {
        var blocks: [PageBlock] = [
            Self.block([Self.line("Braised Leeks with Mustard", x: 0.12, y: 0.10, size: 0.022, spacing: 0.55)]),
            Self.paragraph([
                "We make these when the first leeks come in and the",
                "evenings are still cold enough for something braised.",
            ], x: 0.12, y: 0.16),
            Self.block([Self.line("Serves 4", x: 0.12, y: 0.24)]),
            Self.block([Self.line("4 large leeks, trimmed and halved", x: 0.12, y: 0.27)]),
            Self.block([Self.line("2 tablespoons unsalted butter", x: 0.12, y: 0.286)]),
            Self.block([Self.line("1 cup Chicken Stock (page 212)", x: 0.12, y: 0.302)]),
            Self.block([Self.line("1 tablespoon Dijon mustard", x: 0.12, y: 0.318)]),
            Self.block([Self.line("Kosher salt and black pepper", x: 0.12, y: 0.334)]),
            Self.paragraph([
                "Melt the butter in a wide pan over medium heat. Lay the",
                "leeks in cut side down and cook until browned, about 8",
                "minutes.",
            ], x: 0.12, y: 0.38, indent: 0.025),
            Self.paragraph([
                "Pour in the stock, cover and simmer until the leeks are",
                "tender, 20 to 25 minutes. Stir in the mustard and season.",
            ], x: 0.12, y: 0.428, indent: 0.025),
            Self.block([line(folio, x: 0.12, y: 0.92, size: 0.009)]),
        ]
        if extraStep {
            blocks.append(Self.paragraph(["Serve warm, with the pan juices spooned over the top and a", "little more mustard on the side."], x: 0.12, y: 0.462, indent: 0.025))
        }
        return scan(blocks)
    }

    @Test func readsASinglePageRecipe() throws {
        let reading = PageStructurer().read(Self.leekPage(), file: "leeks.heic")
        #expect(reading.kind == .recipe)
        #expect(reading.pageNumber == 34)
        #expect(!reading.isContinuation)
        let recipe = try #require(reading.recipes.first)
        #expect(reading.recipes.count == 1)
        #expect(recipe.title == "Braised Leeks with Mustard")
        #expect(recipe.yield == "Serves 4")
        #expect(recipe.headnote?.hasPrefix("We make these") == true)
        #expect(recipe.ingredients.map(\.text) == [
            "4 large leeks, trimmed and halved", "2 tablespoons unsalted butter", "1 cup Chicken Stock (page 212)",
            "1 tablespoon Dijon mustard", "Kosher salt and black pepper",
        ])
        #expect(recipe.unparsedIngredientCount == 0)
        #expect(recipe.steps.count == 2)
        #expect(recipe.steps[0].text.hasSuffix("about 8 minutes."))
        #expect(recipe.steps[1].text.hasPrefix("Pour in the stock"))
        #expect(recipe.crossReferences.contains { $0.pages == [212] && $0.target == "Chicken Stock" })
        #expect(recipe.isComplete)
        #expect(!PagePipeline.wantsModel(recipe))
        // The draft the app saves.
        let draft = recipe.draft
        #expect(draft.title == recipe.title && draft.ingredients.count == 5 && draft.steps.count == 2)
        #expect(draft.servings == 4)
        #expect(draft.method == .pageText)
        // Block roles for review.
        #expect(reading.blocks.contains { $0.role == .title })
        #expect(reading.blocks.filter { $0.role == .ingredient }.count == 5)
        #expect(reading.blocks.contains { $0.role == .furniture && $0.text.contains("34") })
    }

    /// A paragraph the recognizer split in two is one step; an indent, a run-in head or a number
    /// starts one; a paragraph running on into the next column stays one step.
    @Test func stepsFollowThePrintedParagraphs() throws {
        let blocks: [PageBlock] = [
            Self.block([Self.line("Smoky Bean Stew", x: 0.10, y: 0.08, size: 0.024, spacing: 0.55)]),
            Self.block([Self.line("2 cups dried white beans", x: 0.10, y: 0.15)]),
            Self.block([Self.line("1 smoked ham hock", x: 0.10, y: 0.166)]),
            Self.block([Self.line("1 onion, halved", x: 0.10, y: 0.182)]),
            // Left column: one printed paragraph read as two blocks, then an indented one.
            Self.paragraph(["Soak the beans overnight in plenty of cold water, then", "drain them and put them in a large pot with the"], x: 0.10, y: 0.25, indent: 0.025),
            Self.paragraph(["ham hock and onion. Cover with water by two inches."], x: 0.10, y: 0.282),
            Self.paragraph(["Bring to a boil, skim, and simmer gently until the", "beans are creamy, about 2 hours. Take out the"], x: 0.10, y: 0.30, indent: 0.025),
            // Right column: the paragraph runs on, then a run-in head.
            Self.paragraph(["hock, shred the meat and stir it back into the pot."], x: 0.55, y: 0.25),
            Self.paragraph(["TO SERVE: Ladle into warm bowls with good olive oil."], x: 0.55, y: 0.268),
        ]
        let reading = PageStructurer().read(Self.scan(blocks))
        let recipe = try #require(reading.recipes.first)
        #expect(recipe.steps.count == 3, "\(recipe.steps.map(\.text))")
        #expect(recipe.steps[0].text == "Soak the beans overnight in plenty of cold water, then drain them and put them in a large pot with the ham hock and onion. Cover with water by two inches.")
        #expect(recipe.steps[1].text.hasSuffix("Take out the hock, shred the meat and stir it back into the pot."))
        #expect(recipe.steps[2].text.hasPrefix("TO SERVE:"))
        #expect(recipe.ingredients.count == 3)
    }

    @Test func readsTwoRecipesOnAPage() {
        let blocks: [PageBlock] = [
            Self.block([Self.line("Quick Pickled Onions", x: 0.10, y: 0.08, size: 0.022, spacing: 0.55)]),
            Self.block([Self.line("1 red onion, thinly sliced", x: 0.10, y: 0.13)]),
            Self.block([Self.line("½ cup red wine vinegar", x: 0.10, y: 0.146)]),
            Self.block([Self.line("1 teaspoon sugar", x: 0.10, y: 0.162)]),
            Self.paragraph(["Pack the onion into a jar, pour over the vinegar and", "sugar and leave for an hour before using."], x: 0.10, y: 0.19),
            Self.block([Self.line("Herb Oil", x: 0.10, y: 0.30, size: 0.022, spacing: 0.55)]),
            Self.block([Self.line("1 cup parsley leaves", x: 0.10, y: 0.35)]),
            Self.block([Self.line("½ cup olive oil", x: 0.10, y: 0.366)]),
            Self.paragraph(["Blend the parsley and oil until smooth, then strain", "through a fine sieve."], x: 0.10, y: 0.395),
        ]
        let reading = PageStructurer().read(Self.scan(blocks))
        #expect(reading.recipes.map(\.title) == ["Quick Pickled Onions", "Herb Oil"])
        #expect(reading.recipes.map(\.ingredients.count) == [3, 2])
        #expect(reading.recipes.map(\.steps.count) == [1, 1])
        // Each block knows its recipe, title included.
        #expect(reading.blocks.filter { $0.recipe == 0 }.count == 5)
        #expect(reading.blocks.filter { $0.recipe == 1 }.count == 4)
        #expect(reading.blocks.first { $0.text == "Herb Oil" }?.recipe == 1)
    }

    /// ux-notes row 59: a second-language name leaves the title. Made-up titles.
    @Test func leavesASecondLanguageNameOutOfTheTitle() {
        func title(_ parts: [String]) -> String {
            PageLines.titleText(PageLines.titleWithoutAlternate(parts, pageLanguage: .english))
        }
        #expect(title(["PEAR TART—TARTE AUX POIRES"]) == "Pear Tart")
        // OCR reads the dash as a hyphen.
        #expect(title(["Roast Chicken-Poulet Rôti"]) == "Roast Chicken")
        #expect(title(["BRAISED LEEKS", "POIREAUX BRAISÉS"]) == "Braised Leeks")
        // A second line in English stays, its own alternate after the dash does not.
        #expect(title(["GRILLED TROUT", "WITH HERB BUTTER—AU BEURRE D'HERBES"]) == "Grilled Trout with Herb Butter")
        // Compounds and English names after a dash stay.
        #expect(title(["Lemon-Basil Granita"]) == "Lemon-Basil Granita")
        #expect(title(["TWICE-BAKED POTATOES"]) == "Twice-Baked Potatoes")
        #expect(title(["Mint-Walnut Pesto"]) == "Mint-Walnut Pesto")
        #expect(title(["SPICED CARROTS", "WITH YOGURT AND DILL"]) == "Spiced Carrots with Yogurt and Dill")
        // The other name begins after a dash and wraps to the next line.
        #expect(title(["PEAR TART—TARTE FINE", "AUX POIRES"]) == "Pear Tart")
        #expect(title(["SLOW-ROASTED DUCK", "CANARD RÔTI"]) == "Slow-Roasted Duck")
    }

    @Test func aTitleKeepsItsAlternateInTheRegions() {
        let blocks: [PageBlock] = [
            Self.block([Self.line("PEAR TART—TARTE AUX POIRES", x: 0.10, y: 0.08, size: 0.022, spacing: 0.55)]),
            Self.block([Self.line("3 ripe pears, peeled and sliced", x: 0.10, y: 0.13)]),
            Self.block([Self.line("1 sheet puff pastry", x: 0.10, y: 0.146)]),
            Self.block([Self.line("2 tablespoons sugar", x: 0.10, y: 0.162)]),
            Self.paragraph(["Lay the pears over the pastry, sprinkle with the sugar and", "bake until the pastry is puffed and brown."], x: 0.10, y: 0.19),
        ]
        let reading = PageStructurer().read(Self.scan(blocks))
        #expect(reading.recipes.first?.title == "Pear Tart")
        #expect(reading.blocks.first { $0.role == .title }?.text == "PEAR TART—TARTE AUX POIRES")
    }

    @Test func regionTextReadsAsTheStructurerReadsIt() {
        #expect(PageRegionText.title(["SLOW-COOKED", "BEANS"]) == "Slow-Cooked Beans")
        #expect(PageRegionText.yield(["MAKES 2 CUPS"]) == "Makes 2 cups")
        #expect(PageRegionText.paragraph(["Stir in the re-", "maining stock."]) == "Stir in the remaining stock.")
        #expect(PageRegionText.ingredientLines(["13/4 cups stock", "2 onions, peeled and", "thinly sliced", "Kosher salt"])
            == ["1 3/4 cups stock", "2 onions, peeled and thinly sliced", "Kosher salt"])
    }

    @Test func readsNumberedStepsAndNotes() throws {
        let blocks: [PageBlock] = [
            Self.block([Self.line("Cucumber Salad", x: 0.10, y: 0.08, size: 0.022, spacing: 0.55)]),
            Self.block([Self.line("serves 2", x: 0.10, y: 0.14)]),
            Self.block([Self.line("2 small cucumbers, sliced", x: 0.10, y: 0.17)]),
            Self.block([Self.line("1 tablespoon rice vinegar", x: 0.10, y: 0.186)]),
            Self.block([Self.line("pinch of salt", x: 0.10, y: 0.202)]),
            Self.paragraph(["1 Toss the cucumbers with the salt and leave for ten", "minutes."], x: 0.55, y: 0.14),
            Self.paragraph(["2 Drain, then dress with the vinegar and serve cold."], x: 0.55, y: 0.18),
            Self.paragraph(["note Slice the cucumbers as thinly as you can."], x: 0.55, y: 0.22),
        ]
        let reading = PageStructurer().read(Self.scan(blocks))
        let recipe = try #require(reading.recipes.first)
        #expect(recipe.steps.map(\.number) == [1, 2])
        #expect(recipe.steps[0].text.hasPrefix("Toss the cucumbers"))
        #expect(recipe.notes == ["Slice the cucumbers as thinly as you can."], "\(recipe.notes) \(recipe.steps.map(\.text))")
        #expect(!recipe.stepCountDisagrees)
        #expect(recipe.yield == "Serves 2")
        #expect(recipe.layoutSignature.contains("m:num-1"))
    }

    @Test func saysWhyAPageIsNotARecipe() {
        let entries = (0..<14).map { index in
            Self.block([Self.line("Something Good with Something Else \(20 + index * 3)", x: 0.12, y: 0.12 + Double(index) * 0.03)])
        }
        let contents = PageStructurer().read(Self.scan([Self.block([Self.line("Contents", x: 0.12, y: 0.06, size: 0.024)])] + entries))
        #expect(contents.kind == .contents)
        #expect(contents.reason?.hasPrefix("a contents page") == true)
        #expect(contents.recipes.isEmpty)

        var plate = Self.scan([PageBlock(id: 0, kind: .photo, rect: PageRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8))])
        plate.paperFraction = 0.2
        #expect(PageStructurer().read(plate).kind == .photo)

        let blank = PageStructurer().read(Self.scan([]))
        #expect(blank.kind == .blank)
    }

    // MARK: - Stitching

    @Test func stitchesARecipeOverAPageTurn() throws {
        let first = Self.scan([
            Self.block([Self.line("Slow Onion Tart", x: 0.10, y: 0.08, size: 0.024, spacing: 0.55)]),
            Self.block([Self.line("1 sheet puff pastry", x: 0.10, y: 0.14)]),
            Self.block([Self.line("6 onions, thinly sliced", x: 0.10, y: 0.156)]),
            Self.paragraph(["Cook the onions slowly in butter until deep brown, about", "an hour, stirring now and then."], x: 0.10, y: 0.20, indent: 0.025),
            Self.paragraph(["Heat the oven to 400°F. Roll out the pastry and spread", "the onions over it, leaving a border, then fold in the"], x: 0.10, y: 0.24, indent: 0.025),
        ])
        let second = Self.scan([
            Self.paragraph(["edges and bake until puffed and golden, 25 minutes."], x: 0.10, y: 0.10),
            Self.paragraph(["Serve warm or at room temperature, in squares, with a green salad", "dressed with a sharp mustard vinaigrette and a glass of something cold."], x: 0.10, y: 0.13, indent: 0.025),
        ])
        let structurer = PageStructurer()
        let readings = [structurer.read(first, file: "a.heic"), structurer.read(second, file: "b.heic")]
        #expect(readings[1].isContinuation)
        #expect(readings[0].recipes.first?.endsMidStep == true)
        let stitched = PageStitcher.stitch(readings)
        #expect(stitched.count == 1)
        let reading = try #require(stitched.first)
        #expect(reading.files == ["a.heic", "b.heic"])
        let recipe = try #require(reading.recipes.first)
        #expect(recipe.steps.count == 3)
        #expect(recipe.steps[1].text.hasSuffix("then fold in the edges and bake until puffed and golden, 25 minutes."))
        #expect(recipe.ingredients.count == 2)
        // The later page's blocks belong to the recipe they continue.
        #expect(reading.blocks.filter { $0.file == 1 }.allSatisfy { $0.recipe == 0 })
        // A titled page after a finished recipe stands alone.
        let separate = PageStitcher.stitch([structurer.read(Self.leekPage(), file: "c"), structurer.read(Self.leekPage(), file: "d")])
        #expect(separate.count == 2)
    }

    // MARK: - Layout signature and reading order

    @Test func layoutSignatureIsTheSameForOneLayout() throws {
        let short = try #require(PageStructurer().read(Self.leekPage()).recipes.first)
        let long = try #require(PageStructurer().read(Self.leekPage(extraStep: true)).recipes.first)
        #expect(short.layoutSignature == long.layoutSignature)
        // Ingredients beside the method rather than above it: another layout.
        let beside = Self.scan([
            Self.block([Self.line("Braised Leeks with Mustard", x: 0.12, y: 0.10, size: 0.022, spacing: 0.55)]),
            Self.block([Self.line("4 large leeks, trimmed", x: 0.12, y: 0.20)]),
            Self.block([Self.line("2 tablespoons butter", x: 0.12, y: 0.216)]),
            Self.block([Self.line("1 cup stock", x: 0.12, y: 0.232)]),
            Self.paragraph(["Melt the butter in a wide pan and brown the leeks,", "then add the stock and simmer until tender."], x: 0.52, y: 0.20),
        ])
        let other = try #require(PageStructurer().read(beside).recipes.first)
        #expect(other.layoutSignature != short.layoutSignature)
        #expect(other.layoutSignature.contains("i:left"))
    }

    @Test func readsColumnsWholeAndTitlesFirst() {
        // Two columns whose paragraphs break at the same height: one column, then the other.
        let columns = [
            Self.paragraph(["Left one", "left one"], x: 0.1, y: 0.20), Self.paragraph(["Left two", "left two"], x: 0.1, y: 0.30),
            Self.paragraph(["Right one", "right one"], x: 0.55, y: 0.20), Self.paragraph(["Right two", "right two"], x: 0.55, y: 0.30),
        ]
        #expect(ReadingOrder.sorted(columns).map { $0.lines[0].text } == ["Left one", "Left two", "Right one", "Right two"])
        // A centred title over a band of columns, the first of which starts left of it.
        let band = [
            Self.block([Self.line("A Centred Title", x: 0.35, y: 0.10, size: 0.02)]),
            Self.block([Self.line("1 lemon", x: 0.05, y: 0.16)]), Self.block([Self.line("2 limes", x: 0.05, y: 0.176)]),
            Self.block([Self.line("1 cup sugar", x: 0.45, y: 0.16)]),
        ]
        #expect(ReadingOrder.sorted(band).first?.lines[0].text == "A Centred Title")
    }

    // MARK: - Lines

    @Test func readsFolios() {
        #expect(PageStructurer.folioNumber(in: ["112 | Vegetables"]) == 112)
        #expect(PageStructurer.folioNumber(in: ["Vegetables | 113"]) == 113)
        #expect(PageStructurer.folioNumber(in: ["SMALL PLATES · 8"]) == 8)
        #expect(PageStructurer.folioNumber(in: ["SMALL PLATES-16"]) == 16)
        #expect(PageStructurer.folioNumber(in: ["INTRODUCTION · xii"]) == 12)
        #expect(PageStructurer.folioNumber(in: ["14 cold dishes"]) == 14)
        #expect(PageStructurer.folioNumber(in: ["PHOTOGRAPH ON PAGE 23", "MAKES ABOUT 2 CUPS", "SOUPS / 47"]) == 47)
        #expect(PageStructurer.folioNumber(in: ["Soups 1 41"]) == 41)
        #expect(PageStructurer.folioNumber(in: ["Serves 4"]) == nil)
    }

    @Test func findsCrossReferences() {
        let references = PageCrossReferences.find(in: "Truss the bird (see page 88 for a quicker method) and add 2 tablespoons Herb Butter (page 214) and fleur de sel (see Sources, page 301).")
        #expect(references.map(\.kind) == [.technique, .recipe, .sources])
        #expect(references.map(\.pages) == [[88], [214], [301]])
        #expect(references[1].target == "Herb Butter")
        let photos = PageCrossReferences.find(in: "PHOTOGRAPHS ON PAGES 31 AND 97")
        #expect(photos.first?.kind == .photograph && photos.first?.pages == [31, 97])
    }

    @Test func readsIngredientLines() {
        #expect(PageLines.ingredientText("13/4 cups stock") == "1 3/4 cups stock")
        #expect(PageLines.ingredientText("11/2-inch piece of ginger") == "1 1/2-inch piece of ginger")
        #expect(PageLines.ingredientText("12 cloves garlic") == "12 cloves garlic")
        func unparsed(_ line: String) -> Bool { PageLines.isUnparsed(line, parsed: IngredientParser.parse(line)) }
        // Number words read as amounts since slice 3 (ux-notes row 58); a slip in the digits still asks.
        #expect(!unparsed("One 3-pound chicken"))
        #expect(unparsed("I½ cups heavy cream"))
        #expect(!unparsed("Kosher salt"))
        #expect(!unparsed("1 cup Chicken Stock (page 212)"))
        #expect(PageLines.ingredientShape("2 Grate the cheese over the top and serve at once") == .not)
        #expect(PageLines.ingredientShape("½ to ¾ cup dry vermouth, such as") == .strong(1))
        #expect(PageLines.ingredientShape("salt and black pepper") == .bare)
        #expect(PageLines.titleText("SLOW-ROASTED DUCK—CANARD RÔTI") == "Slow-Roasted Duck—Canard Rôti")
        #expect(PageLines.yieldText("MAKES 2 TO 4 SERVINGS") == "Makes 2 to 4 servings")
    }

    // MARK: - The model, only when the reading falls short

    final class CountingModel: PageStructuring, @unchecked Sendable {
        var calls = 0
        var isAvailable: Bool { true }
        func structure(pageText: String) async throws -> StructuredPageDraft {
            calls += 1
            return StructuredPageDraft(title: "Model Title", ingredients: ["1 cup flour", "2 eggs"], steps: ["Mix.", "Bake."], confidence: 0.6)
        }
    }

    @Test func asksTheModelOnlyWhenTheReadingFallsShort() async throws {
        let model = CountingModel()
        let pipeline = PagePipeline(model: model)
        let complete = PageStructurer().read(Self.leekPage())
        _ = await pipeline.refine(complete, image: nil)
        #expect(model.calls == 0)

        var short = complete
        short.recipes[0].steps = []
        let refined = await pipeline.refine(short, image: nil)
        #expect(model.calls == 1)
        let recipe = try #require(refined.recipes.first)
        #expect(recipe.title == "Braised Leeks with Mustard")
        #expect(recipe.ingredients.count == 5)
        #expect(recipe.steps.map(\.text) == ["Mix.", "Bake."])
        #expect(recipe.method == .model)
        #expect(recipe.confidence.combined <= 0.6)
    }

    // MARK: - A rendered page through Vision

    /// A page of made-up text drawn with Core Text: a title, ingredient lines and a method.
    static func renderedPage(width: Int = 1700, height: Int = 2200) throws -> CGImage {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        func draw(_ text: String, size: CGFloat, x: CGFloat, top: CGFloat, bold: Bool = false) {
            let font = CTFontCreateWithName((bold ? "Helvetica-Bold" : "Times-Roman") as CFString, size, nil)
            let attributes: [NSAttributedString.Key: Any] = [.init(kCTFontAttributeName as String): font, .init(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
            context.textPosition = CGPoint(x: x, y: CGFloat(height) - top)
            CTLineDraw(line, context)
        }
        draw("Lemon Barley Soup", size: 64, x: 180, top: 260, bold: true)
        var top: CGFloat = 400
        for ingredient in ["1 cup pearl barley", "6 cups vegetable stock", "2 lemons, zested and juiced", "1 bunch dill, chopped", "Kosher salt"] {
            draw(ingredient, size: 30, x: 180, top: top)
            top += 46
        }
        top += 60
        for (index, text) in [
            "Rinse the barley and put it in a pot with the stock. Bring to",
            "a boil, then simmer until tender, about 40 minutes.",
            "Stir in the lemon zest and juice and the dill. Season with",
            "salt and serve hot.",
        ].enumerated() {
            draw(text, size: 30, x: index % 2 == 0 ? 230 : 180, top: top)
            top += index % 2 == 0 ? 42 : 70
        }
        draw("Soups | 41", size: 22, x: 180, top: 2050)
        return try #require(context.makeImage())
    }

    @Test func gateReadsBlurAsHoldStill() async throws {
        let page = try Self.renderedPage()
        let gate = PageQualityGate()
        let sharp = await gate.assess(page)
        #expect(sharp.quality == .sharp, "sharpness \(sharp.sharpness)")
        let source = CIImage(cgImage: page)
        let filter = try #require(CIFilter(name: "CIGaussianBlur"))
        filter.setValue(source, forKey: kCIInputImageKey)
        filter.setValue(4.0, forKey: kCIInputRadiusKey)
        let output = try #require(filter.outputImage)
        let blurred = try #require(CIContext().createCGImage(output.cropped(to: source.extent), from: source.extent))
        let soft = await gate.assess(blurred)
        #expect(soft.quality == .holdStill, "sharpness \(soft.sharpness)")
        #expect(soft.sharpness < sharp.sharpness)
    }

    /// Flow B step 4: the processing sheet's stages, in order, from the pipeline itself.
    @Test(.timeLimit(.minutes(3)))
    func reportsItsStages() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "stages-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "soup.png")
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try Self.renderedPage(), nil)
        #expect(CGImageDestinationFinalize(destination))

        let stages = Mutex<[PagePipeline.Stage]>([])
        let readings = try await PagePipeline().read(contentsOf: [url]) { stage in stages.withLock { $0.append(stage) } }
        let recorded = stages.withLock { $0 }
        #expect(recorded.count == 4)
        #expect(recorded.first == .checking(page: 0, of: 1))
        if case let .reading(page, count, quality) = recorded[1] {
            #expect(page == 0 && count == 1 && quality.quality == .sharp)
        } else { Issue.record("\(recorded[1])") }
        if case let .structuring(_, _, lines) = recorded[2] { #expect(lines > 5) } else { Issue.record("\(recorded[2])") }
        #expect(recorded.last == .read(page: 0, of: 1, kind: .recipe, recipes: 1, ingredients: 5, steps: 2))
        #expect(readings.first?.quarterTurns == [0])
    }

    @Test(.timeLimit(.minutes(3)))
    func readsARenderedPageEndToEnd() async throws {
        let scan = try await PageReader().read(try Self.renderedPage())
        #expect(scan.blocks.contains { $0.text.contains("Lemon Barley Soup") })
        let reading = PageStructurer().read(scan)
        #expect(reading.kind == .recipe)
        let recipe = try #require(reading.recipes.first)
        #expect(recipe.title == "Lemon Barley Soup")
        #expect(recipe.ingredients.count == 5)
        #expect(recipe.steps.count == 2)
        #expect(reading.pageNumber == 41, "\(scan.blocks.map { "\($0.role?.rawValue ?? "-"): \($0.text) \($0.rect)" })")
    }
}
