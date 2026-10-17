import Foundation
import Testing
@testable import Capture

@Suite("JSON-LD recipe parsing")
struct JSONLDRecipeParserTests {
    let fixture = """
    {
      "@context": "https://schema.org",
      "@graph": [
        { "@type": "WebPage", "name": "Some page" },
        {
          "@type": ["Recipe", "Thing"],
          "name": "Roast Chicken",
          "author": { "@type": "Person", "name": "A. Cook" },
          "image": ["https://example.com/chicken.jpg"],
          "recipeYield": ["4 servings", "4"],
          "totalTime": "PT1H30M",
          "recipeIngredient": ["1 whole chicken", "Salt"],
          "recipeInstructions": [
            { "@type": "HowToStep", "text": "Salt the chicken." },
            { "@type": "HowToSection", "itemListElement": [ { "@type": "HowToStep", "text": "Roast at 425°F." } ] }
          ]
        }
      ]
    }
    """

    @Test func parsesGraphWithSectionsAndSteps() throws {
        let recipe = try JSONLDRecipeParser.parse(Data(fixture.utf8), sourceURL: URL(string: "https://example.com/roast"))
        #expect(recipe.title == "Roast Chicken")
        #expect(recipe.author == "A. Cook")
        #expect(recipe.imageURL?.absoluteString == "https://example.com/chicken.jpg")
        #expect(recipe.yield == "4 servings")
        #expect(recipe.totalTime == .seconds(90 * 60))
        #expect(recipe.ingredients == ["1 whole chicken", "Salt"])
        #expect(recipe.steps == ["Salt the chicken.", "Roast at 425°F."])
        #expect(recipe.sourceURL?.host() == "example.com")
    }

    @Test func rejectsPagesWithoutARecipe() {
        #expect(throws: JSONLDParseError.noRecipeFound) {
            try JSONLDRecipeParser.parse(Data(#"{"@type":"Article","name":"Nope"}"#.utf8))
        }
    }

    @Test func rejectsNonJSON() {
        #expect(throws: JSONLDParseError.notJSON) {
            try JSONLDRecipeParser.parse(Data("<html></html>".utf8))
        }
    }

    @Test(arguments: [("PT45M", 45 * 60), ("PT2H", 7_200), ("P1DT1H", 90_000)])
    func parsesISODurations(text: String, seconds: Int) {
        #expect(ISO8601Duration.parse(text) == .seconds(seconds))
    }
}
