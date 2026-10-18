import Foundation
import Intelligence
import Testing
import Units
@testable import Capture

/// Edge cases from hand-written fixtures in `Fixtures/Synthetic`.
@Suite("Web import, synthetic pages")
struct SyntheticImportTests {
    let pageURL = URL(string: "https://example.test/recipes/1?utm_source=share")!

    @Test func graphWithSectionsReferencesAndImageArrays() throws {
        let recipe = try JSONLDRecipeParser.parse(Fixtures.syntheticData("jsonld-graph-sections.json"), sourceURL: pageURL)
        #expect(recipe.title == "Sheet-Pan Chicken & Potatoes")
        #expect(recipe.author == "Pat Example")
        #expect(recipe.siteName == "Test Kitchen Notes")
        #expect(recipe.imageURL?.absoluteString == "https://example.test/img/hero-16x9.jpg")
        #expect(recipe.yield == "4")
        #expect(recipe.servings == 4)
        #expect(recipe.yieldDescription == nil)
        #expect(recipe.prepTime == .seconds(20 * 60))
        #expect(recipe.cookTime == .seconds(65 * 60))
        #expect(recipe.totalTime == .seconds(85 * 60))
        #expect(recipe.category == "Main Course")
        #expect(recipe.cuisine == "American")
        #expect(recipe.ingredients == [
            "2 lb chicken thighs", "1 1/2 lb small potatoes, halved", "Salt & pepper", "2 Tbsp. honey", "1 tbsp Dijon mustard",
        ])
        #expect(recipe.ingredientGroups == [3: "For the glaze"])
        #expect(recipe.group(forIngredientAt: 4) == "For the glaze")
        #expect(recipe.group(forIngredientAt: 1) == nil)
        // Two HowToSections; the last step has only a name.
        #expect(recipe.steps.count == 3)
        #expect(recipe.steps.last?.text.hasPrefix("Brush with the honey") == true)
        #expect(recipe.method == .jsonLD)
        #expect(!recipe.needsReview)
    }

    @Test func packedIngredientStringsHTMLInstructionsAndYieldArrays() throws {
        let recipe = try JSONLDRecipeParser.parse(Fixtures.syntheticData("jsonld-packed-strings.json"), sourceURL: pageURL)
        #expect(recipe.ingredients == ["2 1/4 cups flour", "1 tsp baking soda", "1 cup butter, browned", "flaky salt"])
        #expect(recipe.ingredientGroups == [0: "For the dough", 3: "To finish"])
        #expect(recipe.steps == [
            "Brown the butter and let it cool.",
            "Whisk the flour and baking soda.",
            "Mix, scoop and bake at 350°F for 11 minutes.",
        ])
        // The descriptive yield wins over the bare number.
        #expect(recipe.yield == "Makes 24 cookies")
        #expect(recipe.servings == nil)
        #expect(recipe.yieldDescription == "Makes 24 cookies")
        // "PT0S" means not given; a relative image resolves against the page.
        #expect(recipe.totalTime == nil)
        #expect(recipe.imageURL?.absoluteString == "https://example.test/images/cookies.jpg")
        #expect(recipe.author == "Sam Baker")
    }

    @Test func importerCleansTitleAndKeepsStructuredData() throws {
        let html = "<html><head><title>Brown Butter Cookies | Recipes | Bakehouse</title><meta property=\"og:site_name\" content=\"Bakehouse\"><script type=\"application/ld+json\">\(try Fixtures.synthetic("jsonld-packed-strings.json"))</script></head><body><h1>Brown Butter Cookies</h1></body></html>"
        let recipe = try WebRecipeImporter.parse(html: html, url: pageURL)
        #expect(recipe.title == "Brown Butter Cookies")
        #expect(recipe.siteName == "Bakehouse")
        #expect(recipe.method == .jsonLD)
        #expect(recipe.confidence >= ImportedRecipe.reviewThreshold)
    }

    @Test func picksTheRecipeMatchingThePageTitle() throws {
        let recipe = try WebRecipeImporter.parse(html: Fixtures.synthetic("multiple-recipes.html"), url: pageURL)
        #expect(recipe.title == "Roast Chicken With Lemon")
        #expect(recipe.ingredients.count == 3)
        #expect(recipe.steps == ["Salt the chicken a day ahead.", "Roast at 425°F for an hour."])
    }

    @Test func prefersTheFullListWhenJSONLDHoldsOnlyOneGroup() throws {
        let recipe = try WebRecipeImporter.parse(html: Fixtures.synthetic("jsonld-truncated-ingredients.html"), url: pageURL)
        #expect(recipe.method == .jsonLD)
        #expect(recipe.title == "Herbed Rice Salad")
        #expect(recipe.ingredients.count == 8)
        #expect(recipe.ingredients.first == "1 1/2 cups long-grain rice")
        #expect(recipe.ingredientGroups == [3: "For the Dressing", 5: "To Assemble"])
        #expect(recipe.steps.count == 3)
        #expect(recipe.author == "Pantry Notes Kitchen")
        #expect(recipe.servings == 6)
        #expect(!recipe.needsReview)
    }

    @Test func readsMicrodata() throws {
        let recipe = try WebRecipeImporter.parse(html: Fixtures.synthetic("microdata.html"), url: pageURL)
        #expect(recipe.method == .microdata)
        #expect(recipe.title == "Simple Pancakes")
        #expect(recipe.ingredients == ["1 1/2 cups flour", "2 tsp baking powder", "1 1/4 cups milk", "1 egg"])
        #expect(recipe.steps.count == 3)
        #expect(recipe.servings == 4)
        #expect(recipe.totalTime == .seconds(25 * 60))
        #expect(recipe.author == "Lee Sample")
        #expect(recipe.imageURL?.absoluteString == "https://example.test/img/pancakes.jpg")
        #expect(recipe.siteName == "Microdata Test")
        #expect(recipe.confidence == 0.85)
    }

    @Test func readsPageTextUnderHeadings() throws {
        let recipe = try WebRecipeImporter.parse(html: Fixtures.synthetic("page-text-headings.html"), url: pageURL)
        #expect(recipe.method == .pageText)
        #expect(recipe.needsReview)
        #expect(recipe.title == "Grilled Flank Steak")
        #expect(recipe.siteName == "Weekly Gazette")
        #expect(recipe.author == "Robin Writer")
        #expect(recipe.imageURL?.absoluteString == "https://example.test/flank.jpg")
        #expect(recipe.ingredients == [
            "½ cup (120 ml) soy sauce",
            "¼ cup (60 ml) lime juice",
            "3 garlic cloves, grated",
            "2 pounds (900 grams) flank steak, trimmed of any silverskin and patted completely dry before it goes into the marinade",
            "warm tortillas",
            "lime wedges",
            "flaky salt",
        ])
        #expect(recipe.ingredientGroups == [0: "for the marinade", 4: "to serve"])
        // The dual measure in a step reads like the ingredient lines; the newsletter line is left out.
        #expect(recipe.steps.count == 3)
        #expect(recipe.steps.first?.text.contains("¼ cup (60 ml) water") == true)
        #expect(recipe.yield == "4-6")
        #expect(recipe.servings == 4)
        #expect(recipe.yieldDescription == "Serves 4–6")
        #expect(recipe.prepTime == .seconds(15 * 60))
        #expect(recipe.totalTime == .seconds(60 * 60))
        // The reading's parsed amounts: the "(120 ml)" equivalent is dropped by the parser.
        let first = try #require(recipe.parsedIngredients.first)
        #expect(first.quantity == Rational(1, 2))
        #expect(first.unit == .cup)
        #expect(first.item == "soy sauce")
    }

    @Test func joinsSplitAmountsAndReadsNumberedStepTitles() throws {
        let recipe = try WebRecipeImporter.parse(html: Fixtures.synthetic("page-text-split-amounts.html"), url: pageURL)
        #expect(recipe.method == .pageText)
        #expect(recipe.title == "Slow-Roasted Salmon")
        #expect(recipe.ingredients == [
            "600 g Salmon fillet, skin on",
            "15 g Kosher salt, divided",
            "30 g Olive oil",
            "1 Lemon, zested",
            "Dill, for serving, as needed",
        ])
        #expect(recipe.steps == [
            "Season the salmon. Salt the salmon on both sides and let it sit while the oven heats to 275 °F.",
            "Roast low. Rub with the oil and roast until the center reaches 120 °F, about 25 minutes. Use a probe thermometer.",
            "Finish and serve. Scatter the lemon zest and dill over the fish and serve right away.",
        ])
        #expect(recipe.servings == 4)
        #expect(recipe.totalTime == .seconds(3_600))
        // The dash stood in for an amount; it is dropped and the line keeps its note.
        #expect(recipe.parsedIngredients.last?.item == "Dill")
        #expect(recipe.parsedIngredients.last?.quantity == nil)
    }

    @Test func findsStepsAboveTheIngredients() throws {
        let recipe = try WebRecipeImporter.parse(html: Fixtures.synthetic("page-text-steps-first.html"), url: pageURL)
        #expect(recipe.title == "Braised Leeks")
        #expect(recipe.ingredients == ["4 large leeks", "2 tablespoons butter", "1 cup chicken stock", "Fine sea salt"])
        #expect(recipe.steps.count == 3)
        #expect(recipe.servings == 4)
        #expect(recipe.siteName == "Chef's Table")
    }

    @Test func reportsNoRecipeOnAnArticle() {
        let extraction = WebRecipeImporter.extract(html: (try? Fixtures.synthetic("no-recipe.html")) ?? "", url: pageURL)
        #expect(extraction.recipe == nil)
        #expect(extraction.pageTitle == "Ten Kitchen Tools We Love")
        #expect(!extraction.recipeText.isEmpty)
        #expect(throws: WebImportError.noRecipeFound) {
            try WebRecipeImporter.parse(html: (try? Fixtures.synthetic("no-recipe.html")) ?? "", url: pageURL)
        }
    }
}

/// The model fallback, with stubs in place of the on-device model.
@Suite("Web import, model fallback")
struct ModelFallbackTests {
    struct StubStructurer: RecipeStructuring {
        var isAvailable = true
        var draft = StructuredRecipeDraft(
            title: "Model Title",
            ingredients: ["1 cup rice", "2 cups water", "1 tsp salt"],
            steps: ["Rinse the rice.", "Simmer covered for 18 minutes."],
            confidence: 0.6
        )
        func structure(_ text: String) async throws -> StructuredRecipeDraft { draft }
    }

    struct FailingStructurer: RecipeStructuring {
        struct Failure: Error {}
        func structure(_ text: String) async throws -> StructuredRecipeDraft { throw Failure() }
    }

    let url = URL(string: "https://example.test/article")!

    @Test func modelReadsAPageWithNoRecipeData() async throws {
        let html = try Fixtures.synthetic("no-recipe.html")
        let recipe = try await WebRecipeImporter(structurer: StubStructurer()).importRecipe(html: html, url: url)
        #expect(recipe.method == .model)
        #expect(recipe.title == "Ten Kitchen Tools We Love")
        #expect(recipe.ingredients.count == 3)
        #expect(recipe.needsReview)
    }

    @Test func structuredDataNeverAsksTheModel() async throws {
        let html = try Fixtures.synthetic("multiple-recipes.html")
        let recipe = try await WebRecipeImporter(structurer: StubStructurer()).importRecipe(html: html, url: url)
        #expect(recipe.method == .jsonLD)
    }

    @Test func unavailableOrFailingModelKeepsTheDeterministicReading() async throws {
        let html = try Fixtures.synthetic("page-text-headings.html")
        let unavailable = try await WebRecipeImporter(structurer: StubStructurer(isAvailable: false)).importRecipe(html: html, url: url)
        #expect(unavailable.method == .pageText)
        let failing = try await WebRecipeImporter(structurer: FailingStructurer()).importRecipe(html: html, url: url)
        #expect(failing.method == .pageText)
        await #expect(throws: WebImportError.noRecipeFound) {
            try await WebRecipeImporter(structurer: FailingStructurer()).importRecipe(html: try Fixtures.synthetic("no-recipe.html"), url: url)
        }
    }

    @Test func modelThatDropsMostOfTheListIsIgnored() async throws {
        let html = try Fixtures.synthetic("page-text-headings.html")
        var stub = StubStructurer()
        stub.draft.ingredients = ["1 cup soy sauce", "2 limes"]
        let recipe = try await WebRecipeImporter(structurer: stub).importRecipe(html: html, url: url)
        #expect(recipe.method == .pageText)
        #expect(recipe.ingredients.count == 7)
    }

    @Test func modelReplacesAWeakReadingButKeepsPageMetadata() async throws {
        let html = try Fixtures.synthetic("page-text-headings.html")
        var stub = StubStructurer()
        stub.draft.ingredients = ["½ cup|120 ml soy sauce", "1/4 cup lime juice", "3 garlic cloves", "2 lb flank steak", "warm tortillas", "lime wedges"]
        stub.draft.steps = ["Marinate the steak with 1/4 cup|60 ml water.", "Grill it."]
        let recipe = try await WebRecipeImporter(structurer: stub).importRecipe(html: html, url: url)
        #expect(recipe.method == .model)
        #expect(recipe.title == "Grilled Flank Steak")
        #expect(recipe.imageURL?.absoluteString == "https://example.test/flank.jpg")
        #expect(recipe.ingredients.count == 6)
        #expect(recipe.steps.first == "Marinate the steak with 1/4 cup (60 ml) water.")
        // The page reading's groups follow their lines into the model's list.
        #expect(recipe.ingredientGroups == [0: "for the marinade", 4: "to serve"])
        #expect(recipe.confidence <= 0.6)
    }
}
