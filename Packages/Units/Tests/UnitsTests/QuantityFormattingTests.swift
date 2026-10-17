import Testing
@testable import Units

@Suite("Quantity formatting")
struct QuantityFormattingTests {
    @Test(arguments: [
        (Quantity(Rational(3, 2), .cup), "1½ cups"),
        (Quantity(2, .tablespoon), "2 tbsp"),
        (Quantity(350, .gram), "350 g"),
        (Quantity(Rational(1, 3), .cup), "⅓ cup"),
        (Quantity(1, .cup), "1 cup"),
        (Quantity(Rational(1, 2), .cup), "½ cup"),
        (Quantity(Rational(2, 3), .cup), "⅔ cup"),
        (Quantity(Rational(3, 4), .teaspoon), "¾ tsp"),
        (Quantity(Rational(1, 8), .teaspoon), "⅛ tsp"),
        (Quantity(Rational(7, 16), .cup), "7/16 cup"),
        (Quantity(Rational(23, 16), .cup), "1 7/16 cups"),
        (Quantity(Rational(5, 2), .quart), "2½ qt"),
        (Quantity(1, .gallon), "1 gal"),
        (Quantity(Rational(3, 2), .liter), "1.5 L"),
        (Quantity(Rational(5, 4), .kilogram), "1.25 kg"),
        (Quantity(2, .kilogram), "2 kg"),
        (Quantity(Rational(236_588, 1_000), .milliliter), "236.59 mL"),
        (Quantity(Rational(1, 2), .pound), "½ lb"),
        (Quantity(12, .ounce), "12 oz"),
        (Quantity(8, .fluidOunce), "8 fl oz"),
        (Quantity(1, .pint), "1 pt"),
        (Quantity(1, .pinch), "1 pinch"),
        (Quantity(2, .pinch), "2 pinches"),
        (Quantity(3, .dash), "3 dashes"),
        (Quantity(1, .toTaste), "to taste"),
        (Quantity(2, .piece), "2"),
        (Quantity(Rational(3, 2), .piece), "1½"),
        (Quantity(Rational(5, 2), nil), "2½"),
        (Quantity(0, .cup), "0 cups"),
        (Quantity(Rational(-1, 2), .cup), "-½ cup"),
    ])
    func abbreviated(quantity: Quantity, text: String) {
        #expect(quantity.formatted() == text)
        #expect(quantity.formatted(style: .abbreviated) == text)
    }

    @Test(arguments: [
        (Quantity(Rational(3, 2), .cup), "1½ cups"),
        (Quantity(2, .tablespoon), "2 tablespoons"),
        (Quantity(1, .tablespoon), "1 tablespoon"),
        (Quantity(Rational(1, 2), .teaspoon), "½ teaspoon"),
        (Quantity(350, .gram), "350 grams"),
        (Quantity(1, .gram), "1 gram"),
        (Quantity(Rational(3, 2), .liter), "1.5 liters"),
        (Quantity(250, .milliliter), "250 milliliters"),
        (Quantity(2, .kilogram), "2 kilograms"),
        (Quantity(8, .fluidOunce), "8 fluid ounces"),
        (Quantity(1, .fluidOunce), "1 fluid ounce"),
        (Quantity(Rational(1, 2), .pound), "½ pound"),
        (Quantity(2, .pound), "2 pounds"),
        (Quantity(3, .ounce), "3 ounces"),
        (Quantity(2, .pint), "2 pints"),
        (Quantity(1, .quart), "1 quart"),
        (Quantity(2, .gallon), "2 gallons"),
        (Quantity(2, .piece), "2 pieces"),
        (Quantity(1, .piece), "1 piece"),
        (Quantity(2, .pinch), "2 pinches"),
        (Quantity(1, .dash), "1 dash"),
        (Quantity(1, .toTaste), "to taste"),
    ])
    func fullNames(quantity: Quantity, text: String) {
        #expect(quantity.formatted(style: .full) == text)
    }

    @Test func everyVulgarFractionGlyph() {
        let cases: [(Rational, String)] = [
            (Rational(1, 2), "½"), (Rational(1, 3), "⅓"), (Rational(2, 3), "⅔"), (Rational(1, 4), "¼"), (Rational(3, 4), "¾"),
            (Rational(1, 5), "⅕"), (Rational(2, 5), "⅖"), (Rational(3, 5), "⅗"), (Rational(4, 5), "⅘"),
            (Rational(1, 6), "⅙"), (Rational(5, 6), "⅚"), (Rational(1, 7), "⅐"),
            (Rational(1, 8), "⅛"), (Rational(3, 8), "⅜"), (Rational(5, 8), "⅝"), (Rational(7, 8), "⅞"),
            (Rational(1, 9), "⅑"), (Rational(1, 10), "⅒"),
        ]
        for (value, glyph) in cases {
            #expect(value.mixedNumberString == glyph)
            #expect((value + 2).mixedNumberString == "2\(glyph)")
        }
        #expect(Rational(2, 7).mixedNumberString == "2/7")
        #expect(Rational(16, 7).mixedNumberString == "2 2/7")
        #expect(Rational(4).mixedNumberString == "4")
        #expect(Rational(-5, 4).mixedNumberString == "-1¼")
    }

    @Test func decimalStrings() {
        #expect(Rational(3, 2).decimalString() == "1.5")
        #expect(Rational(5, 4).decimalString() == "1.25")
        #expect(Rational(2).decimalString() == "2")
        #expect(Rational(1, 3).decimalString() == "0.33")
        #expect(Rational(2, 3).decimalString() == "0.67")
        #expect(Rational(1, 1_000).decimalString() == "0")
        #expect(Rational(1, 1_000).decimalString(maximumFractionDigits: 3) == "0.001")
        #expect(Rational(7, 2).decimalString(maximumFractionDigits: 0) == "4")
        #expect(Rational(-3, 2).decimalString() == "-1.5")
        #expect(Rational(2_999, 1_000).decimalString() == "3")
    }

    @Test func unitNamesCoverEveryUnit() {
        for unit in CookingUnit.allCases {
            for style in UnitNameStyle.allCases {
                let singular = unit.name(style: style, plural: false)
                let plural = unit.name(style: style, plural: true)
                if unit == .piece && style == .abbreviated {
                    #expect(singular.isEmpty && plural.isEmpty)
                } else {
                    #expect(!singular.isEmpty && !plural.isEmpty, "\(unit) \(style)")
                }
                if style == .full && unit != .toTaste {
                    #expect(plural.hasSuffix("s") && plural.hasPrefix(singular), "\(unit)")
                }
            }
        }
    }
}
