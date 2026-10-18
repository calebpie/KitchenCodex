import Foundation
import Testing
@testable import Capture

/// The fixes from the Oct 17, 2026 extraction review, and photos per step, on hand-written pages.
@Suite("Import fixes and step photos")
struct ImportFixesTests {
    let pageURL = URL(string: "https://example.test/recipes/7")!

    // (a) Headings borrowed from the page when structured data lists ingredients flat.
    @Test func borrowsPageHeadingsForAFlatStructuredList() throws {
        let recipe = try WebRecipeImporter.parse(html: Fixtures.synthetic("jsonld-flat-page-headings.html"), url: pageURL)
        #expect(recipe.method == .jsonLD)
        #expect(recipe.ingredients.count == 9)
        #expect(recipe.ingredientGroups == [0: "Making the Sauce", 4: "Making the White Sauce", 7: "Assembling"])
        #expect(recipe.group(forIngredientAt: 5) == "Making the White Sauce")
        #expect(recipe.steps.count == 3)
    }

    @Test func keepsAFlatListWhenThePageHasNoMatchingHeadings() throws {
        // Same structured data, and a page that shows the lines under one "Ingredients" heading.
        let page = try Fixtures.synthetic("jsonld-flat-page-headings.html")
        let body = page.range(of: "<body>")!.lowerBound
        let html = page[..<body] + "<body><h1>Weeknight Lasagne</h1><h2>Ingredients</h2><ul><li>2 cloves garlic</li><li>1 onion</li><li>1 lb ground beef</li><li>1 cup crushed tomatoes</li><li>3 tbsp butter</li></ul></body></html>"
        let recipe = try WebRecipeImporter.parse(html: String(html), url: pageURL)
        #expect(recipe.ingredientGroups.isEmpty)
    }

    // (b) Yield labels.
    @Test(arguments: [
        ("YIELD — 4 servings", "4 servings"), ("Yield: 6", "6"), ("Servings: 4-6", "4-6"), ("Yields 2 loaves", "2 loaves"),
        ("Serves: 4", "Serves 4"), ("Serves 4", "Serves 4"), ("Makes 30 cookies", "Makes 30 cookies"), ("4 servings", "4 servings"),
        ("Yield", "Yield"),
    ])
    func stripsYieldLabels(_ raw: String, _ expected: String) {
        #expect(YieldText.strippingLabel(raw) == expected)
    }

    @Test func storesTheYieldWithoutItsLabel() throws {
        let recipe = try WebRecipeImporter.parse(html: Fixtures.synthetic("jsonld-step-images-asides.html"), url: pageURL)
        #expect(recipe.yield == "4 servings")
        #expect(recipe.servings == 4)
        let duck = try WebRecipeImporter.parse(html: Fixtures.synthetic("page-text-step-photos.html"), url: pageURL)
        #expect(duck.yield == "4 servings")
    }

    // (c) Asides posted as steps move to notes, in order; "Tip the pan…" is an instruction.
    @Test func movesAsidesToNotes() throws {
        let recipe = try WebRecipeImporter.parse(html: Fixtures.synthetic("jsonld-step-images-asides.html"), url: pageURL)
        #expect(recipe.steps.map(\.text) == [
            "Pat the chops dry and season them.",
            "Sear in the oil, 3 minutes a side.",
            "Tip the pan juices over the chops to serve.",
        ])
        #expect(recipe.notes == [
            "Tip: Salt them an hour ahead if you can.",
            "DO AHEAD: Chops can be seasoned 1 day ahead. Keep chilled.",
            "Make ahead the sauce up to 2 days.",
        ])
    }

    @Test(arguments: [
        ("DO AHEAD: Lamb can be cut 2 hours ahead.", true), ("Do Ahead Make the dough a day early.", true),
        ("Make-ahead: Freeze for a month.", true), ("note: use a cast-iron pan.", true), ("NOTE This recipe has been updated.", true),
        ("Tip: Warm the plates.", true), ("TIP Warm the plates.", true), ("Tip the batter into the pan.", false),
        ("Notes of citrus come through once the sauce reduces.", false), ("Preheat the oven.", false),
    ])
    func recognizesAsides(_ step: String, _ isAside: Bool) {
        #expect(ImportedRecipe.isAside(step) == isAside)
    }

    @Test func aRecipeOfOnlyAsidesKeepsThemAsSteps() {
        var recipe = ImportedRecipe(title: "Odd", steps: ["Note: just assemble."])
        recipe.movingAsidesToNotes()
        #expect(recipe.steps.count == 1)
        #expect(recipe.notes.isEmpty)
    }

    // (d) Amount, item and modifier in separate elements.
    @Test func rejoinsAnItemAndItsModifier() throws {
        let recipe = try WebRecipeImporter.parse(html: Fixtures.synthetic("page-text-step-photos.html"), url: pageURL)
        #expect(recipe.method == .pageText)
        #expect(recipe.ingredients == ["1 Pekin duck, whole", "35 g Kosher salt, divided", "100 g Hoisin sauce", "2 L Water, cold"])
    }

    @Test func leavesOrdinaryInlineTextAlone() {
        #expect(PageTextReader.itemAndModifier(["Pekin duck", "whole"])! == ("Pekin duck", "whole"))
        #expect(PageTextReader.itemAndModifier(["large", "eggs"]) == nil)
        #expect(PageTextReader.itemAndModifier(["Butter"]) == nil)
        #expect(PageTextReader.itemAndModifier(["Flour", "2 cups"]) == nil)
    }

    // Step photos from JSON-LD: a URL, an ImageObject, or an array (first kept); relative URLs resolved.
    @Test func readsHowToStepImages() throws {
        let recipe = try WebRecipeImporter.parse(html: Fixtures.synthetic("jsonld-step-images-asides.html"), url: pageURL)
        #expect(recipe.steps.map(\.imageURL?.absoluteString) == [
            "https://example.test/img/step-1.jpg",
            "https://example.test/img/step-2.jpg",
            "https://example.test/img/step-3-large.jpg",
        ])
        #expect(recipe.stepImageCount == 3)
        #expect(recipe.imageURL?.absoluteString == "https://example.test/img/hero.jpg")
    }

    // Step photos from the page text: only one content image inside a numbered step's block.
    @Test func attachesAnUnambiguousImageToANumberedStep() throws {
        let recipe = try WebRecipeImporter.parse(html: Fixtures.synthetic("page-text-step-photos.html"), url: pageURL)
        #expect(recipe.steps.count == 4)
        #expect(recipe.steps[0].text.hasPrefix("Dry the duck. Pat the duck dry"))
        #expect(recipe.steps.map(\.imageURL?.absoluteString) == [
            "https://example.test/img/dry.jpg",
            nil,                                  // no photo
            nil,                                  // two photos: ambiguous
            "https://cdn.example.test/carve.jpg", // lazy-loaded source; the icon is ignored
        ])
    }

    @Test func modelReadingKeepsThePhotoOfACopiedStep() {
        let recipe = ImportedRecipe(title: "Duck", steps: [ImportedStep(text: "Roast it.", imageURL: URL(string: "https://example.test/a.jpg"))])
        #expect(WebRecipeImporter.imageURL(forStep: "roast it", in: recipe)?.absoluteString == "https://example.test/a.jpg")
        #expect(WebRecipeImporter.imageURL(forStep: "Carve it.", in: recipe) == nil)
    }
}
