import Testing
import Units
@testable import Capture

@Suite("Ingredient parsing")
struct IngredientParserTests {
    struct Case: CustomTestStringConvertible, Sendable {
        let line: String
        let quantity: Rational?
        let unit: CookingUnit?
        let item: String
        var preparation: String? = nil
        var isOptional = false

        var testDescription: String { line }
    }

    @Test(arguments: [
        // The four lines from the Phase 1 brief.
        Case(line: "2 cups flour", quantity: Rational(2), unit: .cup, item: "flour"),
        Case(line: "1 1/2 tsp kosher salt", quantity: Rational(3, 2), unit: .teaspoon, item: "kosher salt"),
        Case(line: "3 large eggs", quantity: Rational(3), unit: nil, item: "large eggs"),
        Case(line: "salt to taste", quantity: nil, unit: .toTaste, item: "salt"),
        // Fractions in every spelling.
        Case(line: "1/2 cup sugar", quantity: Rational(1, 2), unit: .cup, item: "sugar"),
        Case(line: "½ cup whole milk", quantity: Rational(1, 2), unit: .cup, item: "whole milk"),
        Case(line: "1½ cups water", quantity: Rational(3, 2), unit: .cup, item: "water"),
        Case(line: "1-1/2 cups light brown sugar", quantity: Rational(3, 2), unit: .cup, item: "light brown sugar"),
        Case(line: "1.5 kg potatoes", quantity: Rational(3, 2), unit: .kilogram, item: "potatoes"),
        Case(line: ".25 tsp cayenne", quantity: Rational(1, 4), unit: .teaspoon, item: "cayenne"),
        // Units: attached, abbreviated with periods, cookbook T/t, two-word, metric.
        Case(line: "500g bread flour", quantity: Rational(500), unit: .gram, item: "bread flour"),
        Case(line: "2 Tbsp. unsalted butter, softened", quantity: Rational(2), unit: .tablespoon, item: "unsalted butter", preparation: "softened"),
        Case(line: "1 T honey", quantity: Rational(1), unit: .tablespoon, item: "honey"),
        Case(line: "1 t vanilla extract", quantity: Rational(1), unit: .teaspoon, item: "vanilla extract"),
        Case(line: "8 fl oz heavy cream", quantity: Rational(8), unit: .fluidOunce, item: "heavy cream"),
        Case(line: "250 ml chicken stock", quantity: Rational(250), unit: .milliliter, item: "chicken stock"),
        Case(line: "- 1 lb. ground beef", quantity: Rational(1), unit: .pound, item: "ground beef"),
        // Preparation, "of", ranges, informal units.
        Case(line: "1 onion, finely chopped", quantity: Rational(1), unit: nil, item: "onion", preparation: "finely chopped"),
        Case(line: "2 cups of chicken stock", quantity: Rational(2), unit: .cup, item: "chicken stock"),
        Case(line: "2-3 cloves garlic", quantity: Rational(2), unit: nil, item: "cloves garlic"),
        Case(line: "2 to 3 tablespoons lemon juice", quantity: Rational(2), unit: .tablespoon, item: "lemon juice"),
        Case(line: "a pinch of nutmeg", quantity: Rational(1), unit: .pinch, item: "nutmeg"),
        Case(line: "Pinch of cayenne", quantity: Rational(1), unit: .pinch, item: "cayenne"),
        // Optional, to taste, equivalent measures, no amount at all.
        Case(line: "1/4 cup chopped walnuts (optional)", quantity: Rational(1, 4), unit: .cup, item: "chopped walnuts", isOptional: true),
        Case(line: "Kosher salt and freshly ground pepper, to taste", quantity: nil, unit: .toTaste, item: "Kosher salt and freshly ground pepper"),
        Case(line: "1 cup (240 ml) whole milk", quantity: Rational(1), unit: .cup, item: "whole milk"),
        Case(line: "1 (14 oz) can diced tomatoes", quantity: Rational(1), unit: nil, item: "(14 oz) can diced tomatoes"),
        Case(line: "Freshly ground black pepper", quantity: nil, unit: nil, item: "Freshly ground black pepper"),
        Case(line: "an onion", quantity: nil, unit: nil, item: "an onion"),
    ])
    func parsesLine(_ expected: Case) {
        let parsed = IngredientParser.parse(expected.line)
        #expect(parsed.quantity == expected.quantity)
        #expect(parsed.unit == expected.unit)
        #expect(parsed.item == expected.item)
        #expect(parsed.preparation == expected.preparation)
        #expect(parsed.isOptional == expected.isOptional)
    }

    @Test func keepsTheLineAsTyped() {
        let parsed = IngredientParser.parse("  1 ½ cups water  ")
        #expect(parsed.rawText == "1 ½ cups water")
        #expect(parsed.quantity == Rational(3, 2))
    }

    @Test func keepsAnAmountWhenTheLineAlsoSaysToTaste() {
        let parsed = IngredientParser.parse("1 tsp salt, or to taste")
        #expect(parsed.quantity == Rational(1))
        #expect(parsed.unit == .teaspoon)
        #expect(parsed.item == "salt")
        #expect(parsed.preparation == "to taste")
    }

    @Test func parsesOneIngredientPerNonBlankLine() {
        let text = """
        2 cups flour

        1 1/2 tsp kosher salt
           \t
        3 large eggs
        """
        let parsed = IngredientParser.parseLines(text)
        #expect(parsed.map(\.item) == ["flour", "kosher salt", "large eggs"])
    }

    @Test func doesNotReadAWordAsAUnitWithoutAnAmount() {
        // "G" and "L" are units only after a number.
        let parsed = IngredientParser.parse("L'Antica ricotta")
        #expect(parsed.quantity == nil)
        #expect(parsed.unit == nil)
        #expect(parsed.item == "L'Antica ricotta")
    }
}

@Suite("Step splitting")
struct StepSplitterTests {
    @Test func splitsOnLinesWhenThereAreNoParagraphs() {
        let steps = StepSplitter.steps(from: "Preheat the oven.\nMix the dough.\n\n")
        #expect(steps == ["Preheat the oven.", "Mix the dough."])
    }

    @Test func splitsOnParagraphsAndJoinsWrappedLines() {
        let text = """
        Preheat the oven to 425°F and set a rack
        in the middle.

        Roast for 1.5 hours.
        """
        #expect(StepSplitter.steps(from: text) == [
            "Preheat the oven to 425°F and set a rack in the middle.",
            "Roast for 1.5 hours.",
        ])
    }

    @Test func dropsTypedNumbering() {
        let steps = StepSplitter.steps(from: "1. Salt the chicken.\n2) Rest it.\nStep 3: Roast it.\n1.5 hours later, carve.")
        #expect(steps == ["Salt the chicken.", "Rest it.", "Roast it.", "1.5 hours later, carve."])
    }
}
