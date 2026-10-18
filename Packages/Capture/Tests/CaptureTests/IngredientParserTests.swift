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
        Case(line: "4 pounds (about 2kg) russet potatoes", quantity: Rational(4), unit: .pound, item: "russet potatoes"),
        Case(line: "4 lb (about 2 kg) russet or Yukon Gold potatoes, peeled", quantity: Rational(4), unit: .pound, item: "russet or Yukon Gold potatoes", preparation: "peeled"),
        Case(line: "1 cup (approximately 240 ml) whole milk", quantity: Rational(1), unit: .cup, item: "whole milk"),
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

    /// The slice 7 finding: a cookbook writes the measure's preparation before the comma.
    struct LeadingPreparationCase: CustomTestStringConvertible, Sendable {
        let line: String
        let quantity: Rational
        let unit: CookingUnit?
        let item: String
        var preparation: String? = nil
        var note: String? = nil
        var form: NoteForm? = nil

        var testDescription: String { line }
    }

    @Test(arguments: [
        // One preparation word before the comma: the clause after it is the item.
        LeadingPreparationCase(line: "1 cup packed, fresh spinach leaves (3.5 ounces)", quantity: Rational(1), unit: .cup, item: "fresh spinach leaves", preparation: "packed", note: "3.5 ounces", form: .parenthetical),
        LeadingPreparationCase(line: "2 cups chopped, fresh parsley", quantity: Rational(2), unit: .cup, item: "fresh parsley", preparation: "chopped"),
        // An adverb and a preparation word.
        LeadingPreparationCase(line: "1 cup loosely packed, fresh basil leaves", quantity: Rational(1), unit: .cup, item: "fresh basil leaves", preparation: "loosely packed"),
        LeadingPreparationCase(line: "1/2 cup finely chopped, fresh cilantro", quantity: Rational(1, 2), unit: .cup, item: "fresh cilantro", preparation: "finely chopped"),
        LeadingPreparationCase(line: "1 teaspoon Freshly Ground, black pepper", quantity: Rational(1), unit: .teaspoon, item: "black pepper", preparation: "Freshly Ground"),
        // Later clauses stay with the preparation, and a closing clause is still the note.
        LeadingPreparationCase(line: "1 cup packed, fresh spinach, plus more for serving", quantity: Rational(1), unit: .cup, item: "fresh spinach", preparation: "packed", note: "plus more for serving", form: .clause),
        LeadingPreparationCase(line: "2 cups cooked, shredded chicken, cooled", quantity: Rational(2), unit: .cup, item: "shredded chicken", preparation: "cooked, cooled"),
        // Controls: without a comma, and with the preparation after the comma, lines read as before.
        LeadingPreparationCase(line: "1 cup packed brown sugar", quantity: Rational(1), unit: .cup, item: "packed brown sugar"),
        LeadingPreparationCase(line: "2 cloves garlic, minced", quantity: Rational(2), unit: nil, item: "cloves garlic", preparation: "minced"),
        LeadingPreparationCase(line: "4 tablespoons unsalted butter, melted", quantity: Rational(4), unit: .tablespoon, item: "unsalted butter", preparation: "melted"),
        // The clause after the comma must name a thing: a note clause or more preparation does not.
        LeadingPreparationCase(line: "1 cup chopped, plus more for garnish", quantity: Rational(1), unit: .cup, item: "chopped", note: "plus more for garnish", form: .clause),
        LeadingPreparationCase(line: "1 cup packed, sifted", quantity: Rational(1), unit: .cup, item: "packed", preparation: "sifted"),
    ])
    func readsALeadingPreparation(_ expected: LeadingPreparationCase) {
        let parsed = IngredientParser.parse(expected.line)
        #expect(parsed.quantity == expected.quantity)
        #expect(parsed.unit == expected.unit)
        #expect(parsed.item == expected.item)
        #expect(parsed.preparation == expected.preparation)
        #expect(parsed.note == expected.note)
        #expect(parsed.noteForm == expected.form)
        #expect(parsed.equivalent == nil)
        #expect(parsed.rawText == expected.line)
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
        Case(line: "6 ounces dry white wine (such as Sauvignon Blanc)", unit: .fluidOunce, item: "dry white wine"),
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

/// 04 §5.1 Ingredient lines: trailing asides are the note; a note that counts produce is also the equivalent.
@Suite("Ingredient notes")
struct IngredientNoteTests {
    struct Case: CustomTestStringConvertible, Sendable {
        let line: String
        let item: String
        var preparation: String? = nil
        let note: String?
        var equivalent: ProduceEquivalent? = nil
        /// How the note stood; a note without one given is a parenthetical.
        var form: NoteForm? = nil

        var testDescription: String { line }
    }

    @Test(arguments: [
        // A produce equivalent, with or without "about" or "from".
        Case(line: "5 ounces (142 ml) orange juice (about 3 oranges)", item: "orange juice", note: "about 3 oranges", equivalent: ProduceEquivalent(count: Rational(3), item: "oranges")),
        Case(line: "2 tablespoons lemon juice (from 2 lemons)", item: "lemon juice", note: "from 2 lemons", equivalent: ProduceEquivalent(count: Rational(2), item: "lemons")),
        Case(line: "1 cup (236 ml) pear juice (about 1 ½ pears)", item: "pear juice", note: "about 1 1/2 pears", equivalent: ProduceEquivalent(count: Rational(3, 2), item: "pears")),
        Case(line: "1/3 cup freshly squeezed lemon juice (2 lemons)", item: "freshly squeezed lemon juice", note: "2 lemons", equivalent: ProduceEquivalent(count: Rational(2), item: "lemons")),
        Case(line: "2 tbsp orange zest (about 2 large oranges)", item: "orange zest", note: "about 2 large oranges", equivalent: ProduceEquivalent(count: Rational(2), item: "large oranges")),
        // Notes that count no produce: a measure, a bare count, a size, packaging, an alternative, prose.
        Case(line: "1 rack American lamb (about 12 ounces)", item: "rack American lamb", note: "about 12 ounces"),
        Case(line: "1 (2-ounce) can anchovy fillets (about 12), drained", item: "(2-ounce) can anchovy fillets", preparation: "drained", note: "about 12"),
        Case(line: "4 cups chopped yellow onions (2 large)", item: "chopped yellow onions", note: "2 large"),
        Case(line: "3 pounds frozen chopped spinach, defrosted (5 (10-ounce) packages)", item: "frozen chopped spinach", preparation: "defrosted", note: "5 (10-ounce) packages"),
        Case(line: "1 sprig thyme (or 1/2 teaspoon dried thyme)", item: "sprig thyme", note: "or 1/2 teaspoon dried thyme"),
        Case(line: "5 pounds (2.2 kilograms) beef short ribs, bone-in, thinly sliced lengthwise into ½-inch thick strips (ask your butcher to do this)", item: "beef short ribs", preparation: "bone-in, thinly sliced lengthwise into 1/2-inch thick strips", note: "ask your butcher to do this"),
        // Closing clauses that say what the line is for, or how much more.
        Case(line: "2 tablespoons unsalted butter, softened, plus more for the pan", item: "unsalted butter", preparation: "softened", note: "plus more for the pan", form: .clause),
        Case(line: "3 1/2 cups all-purpose flour, plus extra (for kneading)", item: "all-purpose flour", note: "plus extra (for kneading)", form: .clause),
        Case(line: "1 teaspoon red-pepper flakes, plus more to taste", item: "red-pepper flakes", note: "plus more to taste", form: .clause),
        Case(line: "Canola oil, for frying, as needed", item: "Canola oil", note: "for frying, as needed", form: .clause),
        Case(line: "Olive oil (for serving)", item: "Olive oil", note: "for serving"),
        // A parenthetical, then a closing clause: the note ends with the clause, so it is one.
        Case(line: "1 cup orange juice (about 3 oranges), plus more for serving", item: "orange juice", note: "about 3 oranges; plus more for serving", equivalent: ProduceEquivalent(count: Rational(3), item: "oranges"), form: .clause),
        // Several parentheticals, and commas inside one.
        Case(line: "4 split chicken breasts (bone-in, skin-on)", item: "split chicken breasts", note: "bone-in, skin-on"),
        Case(line: "2 tomatoes (about 12 ounces total weight) (peeled, seeded, and finely diced)", item: "tomatoes", note: "about 12 ounces total weight; peeled, seeded, and finely diced"),
        Case(line: "2 scallions (white and green parts), sliced diagonally", item: "scallions", preparation: "sliced diagonally", note: "white and green parts"),
        // Not notes: a parenthetical inside a word, one that is the whole item, a leading unit equivalent.
        Case(line: "12 g Cinnamon stick(s), divided", item: "Cinnamon stick(s)", preparation: "divided", note: nil),
        Case(line: "1 (14 oz) can diced tomatoes", item: "(14 oz) can diced tomatoes", note: nil),
        Case(line: "1 cup (240 ml) whole milk", item: "whole milk", note: nil),
        Case(line: "4 pounds (about 2kg) russet potatoes", item: "russet potatoes", note: nil),
        Case(line: "1 onion, finely chopped", item: "onion", preparation: "finely chopped", note: nil),
    ])
    func readsNote(_ expected: Case) {
        let parsed = IngredientParser.parse(expected.line)
        #expect(parsed.item == expected.item)
        #expect(parsed.preparation == expected.preparation)
        #expect(parsed.note == expected.note)
        #expect(parsed.equivalent == expected.equivalent)
        #expect(parsed.noteForm == (expected.note == nil ? nil : expected.form ?? .parenthetical))
    }

    @Test func notesReadInTheirForm() {
        #expect(NoteForm.suffix(for: "plus extra (for kneading)", form: .clause) == ", plus extra (for kneading)")
        #expect(NoteForm.suffix(for: "about 3 oranges", form: .parenthetical) == " (about 3 oranges)")
        #expect(NoteForm.suffix(for: "about 3 oranges", form: nil) == " (about 3 oranges)")
        // Parentheses in the note itself: after a comma, so they never nest.
        #expect(NoteForm.suffix(for: "5 (10-ounce) packages", form: .parenthetical) == ", 5 (10-ounce) packages")
    }

    /// The slice 6 finding: an "about" inside the leading equivalent no longer keeps it in the item.
    @Test func dropsAnApproximateLeadingEquivalent() {
        let potatoes = IngredientParser.parse("4 pounds (about 2kg) russet potatoes")
        #expect(potatoes.quantity == Rational(4))
        #expect(potatoes.unit == .pound)
        #expect(potatoes.item == "russet potatoes")
        #expect(potatoes.note == nil)
        // Ounces with an approximate volume beside them are still fluid ounces.
        #expect(IngredientParser.parse("5 ounces (about 150 ml) orange juice").unit == .fluidOunce)
        // A count's parenthetical is not a unit equivalent and stays where it was.
        #expect(IngredientParser.parse("2 (about 1 pound) eggplants").item == "(about 1 pound) eggplants")
    }

    /// Items stored before that keep the equivalent; the app's one-time re-read finds it this way
    /// and takes the fresh reading only when the two then agree.
    @Test func findsAnApproximateLeadingEquivalentInAStoredItem() {
        #expect(IngredientParser.removingLeadingApproximateEquivalent(from: "(about 2 kg) russet or Yukon Gold potatoes") == "russet or Yukon Gold potatoes")
        #expect(IngredientParser.removingLeadingApproximateEquivalent(from: "(about 2kg) russet potatoes") == "russet potatoes")
        #expect(IngredientParser.removingLeadingApproximateEquivalent(from: "(Approximately 240 ml) whole milk") == "whole milk")
        #expect(IngredientParser.removingLeadingApproximateEquivalent(from: "(approx. 1 1/2 cups) chicken stock") == "chicken stock")
        #expect(IngredientParser.removingLeadingApproximateEquivalent(from: "(roughly 450 g) pork shoulder") == "pork shoulder")
        #expect(IngredientParser.removingLeadingApproximateEquivalent(from: "(~150 ml) orange juice") == "orange juice")
        // Not approximate, not a measure, not leading, or nothing after it.
        #expect(IngredientParser.removingLeadingApproximateEquivalent(from: "(240 ml) whole milk") == nil)
        #expect(IngredientParser.removingLeadingApproximateEquivalent(from: "(14 oz) can diced tomatoes") == nil)
        #expect(IngredientParser.removingLeadingApproximateEquivalent(from: "(1-inch) piece ginger") == nil)
        #expect(IngredientParser.removingLeadingApproximateEquivalent(from: "(about 3 oranges) juice") == nil)
        #expect(IngredientParser.removingLeadingApproximateEquivalent(from: "russet potatoes (about 2 kg)") == nil)
        #expect(IngredientParser.removingLeadingApproximateEquivalent(from: "(about 2 kg)") == nil)
        #expect(IngredientParser.removingLeadingApproximateEquivalent(from: "russet potatoes") == nil)
        // The roast potatoes as stored, against a fresh reading of their line.
        let line = "4 pounds (about 2kg) russet or Yukon Gold potatoes, peeled and cut into quarters, sixths, or eighths, depending on size (see note)"
        let fresh = IngredientParser.parse(line)
        #expect(IngredientParser.removingLeadingApproximateEquivalent(from: "(about 2 kg) russet or Yukon Gold potatoes") == fresh.item)
        #expect(fresh.preparation == "peeled and cut into quarters, sixths, or eighths, depending on size")
        #expect(fresh.note == "see note")
        // A count's parenthetical stays in a fresh reading, so the re-read leaves such an item be.
        #expect(IngredientParser.parse("2 (about 1 pound) eggplants").item == "(about 1 pound) eggplants")
        #expect(IngredientParser.removingLeadingApproximateEquivalent(from: "(about 1 pound) eggplants") == "eggplants")
    }

    @Test func optionalAndToTasteAreNotNotes() {
        let walnuts = IngredientParser.parse("1/4 cup chopped walnuts (optional)")
        #expect(walnuts.note == nil)
        #expect(walnuts.isOptional)
        let salt = IngredientParser.parse("sea salt (to taste)")
        #expect(salt.note == nil)
        #expect(salt.unit == .toTaste)
    }

    @Test func aNoteNeverChangesTheAmount() {
        let parsed = IngredientParser.parse("5 ounces (142 ml) orange juice (about 3 oranges)")
        #expect(parsed.quantity == Rational(5))
        #expect(parsed.unit == .fluidOunce)
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
