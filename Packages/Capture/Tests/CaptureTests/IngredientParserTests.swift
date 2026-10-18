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

/// 04 §5.1 Liquid ounces: ounces of a liquid are fluid ounces; a parenthetical decides first.
@Suite("Liquid ounces")
struct LiquidOunceTests {
    struct Case: CustomTestStringConvertible, Sendable {
        let line: String
        let unit: CookingUnit
        let item: String

        var testDescription: String { line }
    }

    @Test(arguments: [
        // A metric volume in parentheses confirms fluid ounces, whatever the item.
        Case(line: "5 ounces (142 ml) orange juice", unit: .fluidOunce, item: "orange juice"),
        Case(line: "6 oz (180 mL) dashi or water", unit: .fluidOunce, item: "dashi or water"),
        Case(line: "3 ounces (90 ml) Thai basil syrup", unit: .fluidOunce, item: "Thai basil syrup"),
        // A weight in parentheses keeps ounces of weight, even for a liquid word.
        Case(line: "4 ounces (113 g) butter", unit: .ounce, item: "butter"),
        Case(line: "12 oz (340 g) honey", unit: .ounce, item: "honey"),
        // No parenthetical: the liquid lexicon decides.
        Case(line: "8 ounces whole milk", unit: .fluidOunce, item: "whole milk"),
        Case(line: "4 oz. heavy cream, cold", unit: .fluidOunce, item: "heavy cream"),
        Case(line: "16 ounces low-sodium chicken or vegetable broth", unit: .fluidOunce, item: "low-sodium chicken or vegetable broth"),
        Case(line: "2 ounces extra-virgin olive oil for drizzling", unit: .fluidOunce, item: "extra-virgin olive oil for drizzling"),
        Case(line: "12 ounces lager", unit: .fluidOunce, item: "lager"),
        Case(line: "1 ounce soy sauce", unit: .fluidOunce, item: "soy sauce"),
        Case(line: "3 oz pure maple syrup", unit: .fluidOunce, item: "pure maple syrup"),
        Case(line: "4 ounces half-and-half", unit: .fluidOunce, item: "half-and-half"),
        Case(line: "6 ounces dry white wine (such as Sauvignon Blanc)", unit: .fluidOunce, item: "dry white wine (such as Sauvignon Blanc)"),
        // Solids named after a liquid stay ounces of weight.
        Case(line: "8 ounces cream cheese, softened", unit: .ounce, item: "cream cheese"),
        Case(line: "4 ounces milk chocolate, chopped", unit: .ounce, item: "milk chocolate"),
        Case(line: "8 oz sour cream", unit: .ounce, item: "sour cream"),
        Case(line: "5 ounces oil-packed tuna", unit: .ounce, item: "oil-packed tuna"),
        Case(line: "4 ounces sardines in olive oil", unit: .ounce, item: "sardines in olive oil"),
        Case(line: "6 ounces pancetta", unit: .ounce, item: "pancetta"),
    ])
    func readsOunces(_ expected: Case) {
        let parsed = IngredientParser.parse(expected.line)
        #expect(parsed.unit == expected.unit)
        #expect(parsed.item == expected.item)
    }

    @Test func fluidOuncesConvertAsVolume() {
        let parsed = IngredientParser.parse("5 ounces (142 ml) orange juice")
        let quantity = Quantity(parsed.quantity!, parsed.unit)
        // 5 fl oz is 148 mL, shown as 150 mL; ounces of weight would have read 140 g.
        #expect(quantity.displayed(in: .metric).friendlyRounded().formatted() == "150 mL")
    }

    @Test func spelledOutFluidOuncesAreUnchanged() {
        #expect(IngredientParser.parse("8 fl oz heavy cream").unit == .fluidOunce)
        #expect(IngredientParser.parse("1 cup (8 ounces) milk").unit == .cup)
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
