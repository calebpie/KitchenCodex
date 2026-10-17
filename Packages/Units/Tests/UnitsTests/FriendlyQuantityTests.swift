import Foundation
import Testing
@testable import Units

private let english = Locale(identifier: "en_US")

@Suite("Scaling with friendly rounding")
struct FriendlyScalingTests {
    struct Case: CustomTestStringConvertible, Sendable {
        let quantity: Quantity
        let expected: String
        var testDescription: String { "\(quantity.value) \(quantity.unit?.rawValue ?? "count") → \(expected)" }

        init(_ value: Rational, _ unit: CookingUnit?, _ expected: String) {
            quantity = Quantity(value, unit)
            self.expected = expected
        }
    }

    /// The Phase 1 acceptance case: a recipe for 4 cooked for 6.
    @Test(arguments: [
        Case(Rational(2), .cup, "3 cups"),
        Case(Rational(1), .cup, "1 1/2 cups"),
        Case(Rational(3, 2), .teaspoon, "2 1/4 tsp"),
        Case(Rational(3), nil, "4 1/2"),
        Case(Rational(1, 3), .cup, "1/2 cup"),
        Case(Rational(2, 3), .cup, "1 cup"),
        Case(Rational(1, 4), .cup, "6 tbsp"),
        // 9 tbsp has no close cup measure; the original unit holds it exactly.
        Case(Rational(6), .tablespoon, "9 tbsp"),
        Case(Rational(3, 4), .cup, "1 1/8 cups"),
        Case(Rational(2), .teaspoon, "1 tbsp"),
        Case(Rational(1), .tablespoon, "1 1/2 tbsp"),
        Case(Rational(1), .pound, "1 1/2 lb"),
        Case(Rational(12), .ounce, "18 oz"),
        Case(Rational(500), .gram, "750 g"),
        Case(Rational(250), .gram, "375 g"),
        Case(Rational(750), .milliliter, "1.15 L"),
        Case(Rational(1), .pinch, "2 pinches"),
        Case(Rational(1), .pint, "1 1/2 pints"),
    ])
    func scalesFourToSix(_ scenario: Case) {
        let scaled = scenario.quantity.friendly(scaledBy: Rational(6, 4))
        #expect(scaled.formatted(locale: english) == scenario.expected)
    }

    /// Cooking for one from a recipe for 4.
    @Test(arguments: [
        Case(Rational(2), .tablespoon, "1 1/2 tsp"),
        Case(Rational(1, 4), .teaspoon, "1/8 tsp"),
        Case(Rational(1), nil, "1/4"),
        Case(Rational(1), .cup, "1/4 cup"),
        Case(Rational(1, 2), .cup, "2 tbsp"),
        Case(Rational(1), .pound, "4 oz"),
    ])
    func scalesFourToOne(_ scenario: Case) {
        let scaled = scenario.quantity.friendly(scaledBy: Rational(1, 4))
        #expect(scaled.formatted(locale: english) == scenario.expected)
    }

    @Test func roundsAwkwardScalesToTheNearestMeasure() {
        // 4 → 5 servings: 1/3 cup × 5/4 = 0.42 cup, which no cup holds; 6 1/2 tbsp is within 3%.
        #expect(Quantity(Rational(1, 3), .cup).friendly(scaledBy: Rational(5, 4)).formatted(locale: english) == "6 1/2 tbsp")
        #expect(Quantity(Rational(1), .cup).friendly(scaledBy: Rational(6, 5)).formatted(locale: english) == "1 1/4 cups")
    }

    @Test func leavesWrittenAmountsAloneAtOneTimes() {
        let written = Quantity(Rational(3, 8), .teaspoon)
        #expect(written.friendly() == written)
        #expect(Quantity(Rational(12), .tablespoon).friendly() == Quantity(Rational(12), .tablespoon))
        // ...unless nobody could measure them.
        #expect(Quantity(Rational(33, 100), .cup).friendly() == Quantity(Rational(1, 3), .cup))
    }

    @Test func scalingIsExactBeforeRounding() {
        // 1/3 × 3 is exactly 1, not 0.999…
        #expect(Quantity(Rational(1, 3), .cup).friendly(scaledBy: Rational(3)) == Quantity(Rational(1), .cup))
    }

    @Test func toTasteIgnoresScaling() {
        let salt = Quantity(.zero, .toTaste)
        #expect(salt.friendly(scaledBy: Rational(3)).formatted(locale: english) == "to taste")
    }
}

@Suite("US and metric conversion")
struct UnitConversionTests {
    @Test(arguments: [
        (Quantity(Rational(1), .cup), "240 ml"),
        (Quantity(Rational(1, 2), .cup), "120 ml"),
        (Quantity(Rational(3, 4), .cup), "180 ml"),
        (Quantity(Rational(1), .pound), "450 g"),
        (Quantity(Rational(1), .ounce), "28 g"),
        (Quantity(Rational(4), .cup), "950 ml"),
        (Quantity(Rational(1), .quart), "950 ml"),
        (Quantity(Rational(2), .pound), "910 g"),
        (Quantity(Rational(3), .pound), "1.35 kg"),
        // Spoons stay spoons in a metric kitchen.
        (Quantity(Rational(1), .tablespoon), "1 tbsp"),
        (Quantity(Rational(3, 2), .teaspoon), "1 1/2 tsp"),
    ])
    func convertsToMetric(quantity: Quantity, expected: String) {
        #expect(quantity.friendly(in: .metric).formatted(locale: english) == expected)
    }

    @Test(arguments: [
        (Quantity(Rational(240), .milliliter), "1 cup"),
        (Quantity(Rational(250), .milliliter), "1 cup"),
        (Quantity(Rational(15), .milliliter), "1 tbsp"),
        (Quantity(Rational(5), .milliliter), "1 tsp"),
        (Quantity(Rational(1), .liter), "4 1/4 cups"),
        (Quantity(Rational(1), .kilogram), "2 1/4 lb"),
        (Quantity(Rational(250), .gram), "8 3/4 oz"),
        (Quantity(Rational(500), .gram), "17 3/4 oz"),
    ])
    func convertsToUS(quantity: Quantity, expected: String) {
        #expect(quantity.friendly(in: .us).formatted(locale: english) == expected)
    }

    @Test func scalesAndConvertsTogether() {
        // 2 cups for 4, cooked for 6 in a metric kitchen: 3 cups ≈ 710 ml.
        #expect(Quantity(Rational(2), .cup).friendly(scaledBy: Rational(3, 2), in: .metric).formatted(locale: english) == "710 ml")
        // Spoons that add up past half a cup become milliliters in metric.
        #expect(Quantity(Rational(6), .tablespoon).friendly(scaledBy: Rational(2), in: .metric).formatted(locale: english) == "180 ml")
    }

    @Test func leavesTheMatchingSystemAlone() {
        let flour = Quantity(Rational(500), .gram)
        #expect(flour.friendly(in: .metric) == flour)
    }

    @Test func findsTheDominantSystem() {
        #expect(MeasurementSystem.dominant(in: [.gram, .gram, .cup, .teaspoon, nil]) == .metric)
        #expect(MeasurementSystem.dominant(in: [.cup, .gram]) == .us)
        #expect(MeasurementSystem.dominant(in: [.teaspoon, nil, .pinch]) == nil)
    }
}

@Suite("Formatting")
struct QuantityFormattingTests {
    @Test(arguments: [
        (Quantity(Rational(1, 2), .cup), "1/2 cup"),
        (Quantity(Rational(1), .cup), "1 cup"),
        (Quantity(Rational(3, 2), .cup), "1 1/2 cups"),
        (Quantity(Rational(3, 2), .kilogram), "1.5 kg"),
        (Quantity(Rational(7, 2), .gram), "3.5 g"),
        (Quantity(Rational(3), nil), "3"),
        (Quantity(Rational(2), .pinch), "2 pinches"),
    ])
    func formats(quantity: Quantity, expected: String) {
        #expect(quantity.formatted(locale: english) == expected)
    }
}
