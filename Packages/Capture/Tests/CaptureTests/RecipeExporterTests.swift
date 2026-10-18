import Foundation
import Testing
import Units
@testable import Capture

/// Snapshots of the Markdown and plain-text exports.
@Suite("Recipe export")
struct RecipeExporterTests {
    static let chicken = ExportRecipe(
        title: "Roast Chicken with Pan Sauce",
        sourceLine: "Test Kitchen · Pat Example",
        sourceURL: URL(string: "https://example.test/roast-chicken"),
        yield: "Serves 4",
        prepMinutes: 15,
        cookMinutes: 70,
        totalMinutes: 85,
        ingredients: [
            .init(quantity: Quantity(1), item: "whole chicken", note: "about 4 lb"),
            .init(quantity: Quantity(Rational(3, 2), .teaspoon), item: "kosher salt"),
            .init(quantity: Quantity(.zero, .toTaste), item: "black pepper"),
            .init(group: "For the pan sauce", quantity: Quantity(1, .cup), item: "chicken stock"),
            .init(group: "For the pan sauce", quantity: Quantity(2, .tablespoon), item: "unsalted butter", preparation: "cold"),
            .init(group: "For the pan sauce", item: "lemon juice", isOptional: true),
        ],
        steps: [
            "Salt the chicken a day ahead and leave it uncovered in the fridge.",
            "Roast at 425°F until the thigh reads 165°F,\nabout 1 hour 10 minutes.",
            "Whisk the stock and butter into the pan juices; it's *very* good.",
        ],
        notes: "Use a cast-iron pan.\n\nLeftovers make great stock."
    )

    @Test func markdownSnapshot() {
        #expect(RecipeExporter.markdown(Self.chicken) == """
        # Roast Chicken with Pan Sauce

        *Test Kitchen · Pat Example*  
        <https://example.test/roast-chicken>

        Serves 4 · Prep 15 min · Cook 1 hr 10 min · Total 1 hr 25 min

        ## Ingredients

        - **1** whole chicken (about 4 lb)
        - **1½ tsp** kosher salt
        - black pepper, to taste

        ### For the pan sauce

        - **1 cup** chicken stock
        - **2 tbsp** unsalted butter, cold
        - lemon juice (optional)

        ## Steps

        1. Salt the chicken a day ahead and leave it uncovered in the fridge.
        2. Roast at 425°F until the thigh reads 165°F, about 1 hour 10 minutes.
        3. Whisk the stock and butter into the pan juices; it's \\*very\\* good.

        ## Notes

        Use a cast-iron pan.

        Leftovers make great stock.

        """)
    }

    @Test func plainTextSnapshot() {
        #expect(RecipeExporter.plainText(Self.chicken) == """
        Roast Chicken with Pan Sauce
        Test Kitchen · Pat Example
        https://example.test/roast-chicken
        Serves 4 · Prep 15 min · Cook 1 hr 10 min · Total 1 hr 25 min

        INGREDIENTS
        - 1 whole chicken (about 4 lb)
        - 1½ tsp kosher salt
        - black pepper, to taste

        For the pan sauce
        - 1 cup chicken stock
        - 2 tbsp unsalted butter, cold
        - lemon juice (optional)

        STEPS
        1. Salt the chicken a day ahead and leave it uncovered in the fridge.
        2. Roast at 425°F until the thigh reads 165°F, about 1 hour 10 minutes.
        3. Whisk the stock and butter into the pan juices; it's *very* good.

        NOTES
        Use a cast-iron pan.

        Leftovers make great stock.

        """)
    }

    @Test func minimalRecipe() {
        let recipe = ExportRecipe(title: "Toast", steps: ["Toast the bread."])
        #expect(RecipeExporter.markdown(recipe) == "# Toast\n\n## Steps\n\n1. Toast the bread.\n")
        #expect(RecipeExporter.plainText(recipe) == "Toast\n\nSTEPS\n1. Toast the bread.\n")
    }

    @Test func timesAndFileNames() {
        #expect(RecipeExporter.minutesText(45) == "45 min")
        #expect(RecipeExporter.minutesText(60) == "1 hr")
        #expect(RecipeExporter.minutesText(70) == "1 hr 10 min")
        #expect(RecipeExporter.minutesText(1_560) == "1 day 2 hr")
        #expect(RecipeExporter.fileName(for: "Salt/Pepper: A Story", extension: "md") == "Salt-Pepper- A Story.md")
        #expect(RecipeExporter.fileName(for: "  ", extension: "pdf") == "Recipe.pdf")
    }
}
