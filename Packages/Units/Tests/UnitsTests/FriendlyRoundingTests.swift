import Testing
@testable import Units

@Suite("Friendly rounding")
struct FriendlyRoundingTests {
    @Test(arguments: [
        // Teaspoons: halves and quarters first, then thirds and eighths.
        (Quantity(Rational(7, 16), .teaspoon), Rational(1, 2)),
        (Quantity(Rational(3, 10), .teaspoon), Rational(1, 3)),
        (Quantity(Rational(29, 100), .teaspoon), Rational(1, 4)),
        (Quantity(Rational(13, 100), .teaspoon), Rational(1, 8)),
        (Quantity(Rational(9, 4), .teaspoon), Rational(9, 4)),
        // Tablespoons: halves first; thirds, quarters and eighths only when nothing else is close.
        (Quantity(Rational(5, 3), .tablespoon), Rational(5, 3)),
        (Quantity(Rational(11, 10), .tablespoon), Rational(9, 8)),
        (Quantity(Rational(49, 50), .tablespoon), Rational(1)),
        (Quantity(Rational(20, 3), .tablespoon), Rational(13, 2)),
        (Quantity(Rational(9, 4), .tablespoon), Rational(9, 4)),
        (Quantity(Rational(23, 8), .tablespoon), Rational(3)),
        // Cups: halves, thirds, quarters first; eighths when nothing coarser is within 5 percent.
        (Quantity(Rational(11, 30), .cup), Rational(3, 8)),
        (Quantity(Rational(3, 8), .cup), Rational(3, 8)),
        (Quantity(Rational(5, 12), .cup), Rational(3, 8)),
        (Quantity(Rational(7, 10), .cup), Rational(2, 3)),
        (Quantity(Rational(1, 8), .cup), Rational(1, 8)),
        (Quantity(Rational(9, 8), .cup), Rational(9, 8)),
        (Quantity(Rational(6, 5), .cup), Rational(5, 4)),
        (Quantity(Rational(33, 100), .cup), Rational(1, 3)),
        (Quantity(Rational(23, 10), .cup), Rational(7, 3)),
        (Quantity(Rational(14, 5), .cup), Rational(11, 4)),
        // Larger US units: halves and quarters.
        (Quantity(Rational(33, 10), .fluidOunce), Rational(13, 4)),
        (Quantity(Rational(17, 16), .pound), Rational(1)),
        (Quantity(Rational(21, 10), .quart), Rational(2)),
        (Quantity(Rational(17_637, 1_000), .ounce), Rational(71, 4)),
        // Grams and millilitres: whole below 30, 5s below 300, 10s from 300; existing 5s stay.
        (Quantity(Rational(49, 10), .gram), Rational(5)),
        (Quantity(Rational(283_495, 10_000), .gram), Rational(28)),
        (Quantity(Rational(236_588, 2_000), .milliliter), Rational(120)),
        (Quantity(Rational(236_588, 1_000), .milliliter), Rational(235)),
        (Quantity(Rational(283_495, 625), .gram), Rational(450)),
        (Quantity(Rational(347), .gram), Rational(350)),
        (Quantity(Rational(375), .gram), Rational(375)),
        (Quantity(Rational(3, 10), .gram), Rational(1)),
        // Litres and kilograms: 0.05.
        (Quantity(Rational(1_234, 1_000), .kilogram), Rational(5, 4)),
        (Quantity(Rational(1_49, 100), .liter), Rational(3, 2)),
        (Quantity(Rational(1_125, 1_000), .liter), Rational(23, 20)),
        // Counts: quarters and thirds below one, halves below ten, whole numbers above.
        (Quantity(Rational(7, 3), .piece), Rational(5, 2)),
        (Quantity(Rational(3, 4), .piece), Rational(3, 4)),
        (Quantity(Rational(1, 10), .piece), Rational(1, 4)),
        (Quantity(Rational(75, 2), .piece), Rational(38)),
        (Quantity(Rational(7, 3), nil), Rational(5, 2)),
        (Quantity(Rational(1, 4), nil), Rational(1, 4)),
        // Pinches and dashes: whole numbers.
        (Quantity(Rational(3, 2), .pinch), Rational(2)),
        (Quantity(Rational(7, 13), .dash), Rational(1)),
    ])
    func snapsToMeasurableFractions(input: Quantity, expected: Rational) {
        let rounded = input.friendlyRounded()
        #expect(rounded.value == expected, "\(input.value) \(String(describing: input.unit)) -> \(rounded.value)")
        #expect(rounded.unit == input.unit)
    }

    @Test func leavesToTasteAlone() {
        let quantity = Quantity(Rational(7, 13), .toTaste)
        #expect(quantity.friendlyRounded() == quantity)
    }

    @Test func zeroStaysZeroAndNonzeroNeverVanishes() {
        #expect(Quantity(0, .cup).friendlyRounded().value == 0)
        #expect(Quantity(Rational(1, 1_000), .teaspoon).friendlyRounded().value == Rational(1, 8))
        #expect(Quantity(Rational(1, 1_000), .cup).friendlyRounded().value == Rational(1, 8))
        #expect(Quantity(Rational(1, 1_000), .gram).friendlyRounded().value == 1)
        #expect(Quantity(Rational(1, 1_000), .kilogram).friendlyRounded().value == Rational(1, 20))
        #expect(Quantity(Rational(1, 1_000), .piece).friendlyRounded().value == Rational(1, 4))
        #expect(Quantity(Rational(1, 1_000), .pinch).friendlyRounded().value == 1)
        #expect(Quantity(Rational(-1, 1_000), .teaspoon).friendlyRounded().value == Rational(-1, 8))
    }

    /// Amounts a cook wrote down are never second-guessed, however fine.
    @Test(arguments: [
        Quantity(Rational(3, 8), .teaspoon), Quantity(12, .tablespoon), Quantity(Rational(9, 4), .tablespoon),
        Quantity(Rational(9, 8), .cup), Quantity(375, .gram), Quantity(12, .milliliter),
        Quantity(Rational(3, 4), .piece), Quantity(Rational(1, 3), nil),
    ])
    func leavesWrittenAmountsAlone(written: Quantity) {
        #expect(written.friendlyRounded() == written)
    }

    static let factors: [Rational] = {
        var result: [Rational] = []
        for numerator in 1...24 {
            for denominator in 1...8 {
                result.append(Rational(numerator, denominator))
            }
        }
        return result
    }()

    static let baseQuantities: [Quantity] = [
        Quantity(Rational(1, 8), .teaspoon), Quantity(Rational(1, 2), .teaspoon), Quantity(Rational(3, 4), .teaspoon),
        Quantity(1, .tablespoon), Quantity(Rational(3, 2), .tablespoon),
        Quantity(Rational(1, 4), .cup), Quantity(Rational(1, 3), .cup), Quantity(Rational(2, 3), .cup), Quantity(Rational(7, 4), .cup),
        Quantity(Rational(1, 2), .pound), Quantity(Rational(3, 2), .quart),
        Quantity(7, .gram), Quantity(125, .gram), Quantity(350, .gram), Quantity(Rational(3, 2), .kilogram),
        Quantity(15, .milliliter), Quantity(240, .milliliter), Quantity(Rational(5, 4), .liter),
        Quantity(1, .piece), Quantity(3, .piece), Quantity(2, nil),
        Quantity(1, .pinch), Quantity(2, .dash), Quantity(1, .toTaste),
    ]

    private static func finestStep(for quantity: Quantity) -> Rational? {
        switch quantity.unit {
        case .gram?, .milliliter?: FriendlyRounding.metricWholeStep(for: quantity.value.magnitude)
        default: FriendlyRounding.steps(for: quantity.value, unit: quantity.unit).fine.last
        }
    }

    private static func isOnGrid(_ quantity: Quantity) -> Bool {
        FriendlyRounding.steps(for: quantity.value, unit: quantity.unit).fine.contains { quantity.value.isMultiple(of: $0) }
    }

    @Test func scaleThenRoundStaysCloseIdempotentAndOnGrid() {
        var checked = 0
        for base in Self.baseQuantities {
            for factor in Self.factors {
                let scaled = base.scaled(by: factor)
                let rounded = scaled.friendlyRounded()
                checked += 1

                #expect(rounded.unit == base.unit)
                #expect(rounded.friendlyRounded() == rounded, "idempotent: \(scaled) -> \(rounded)")
                #expect(rounded.value > 0, "positive: \(scaled) -> \(rounded)")

                guard let step = Self.finestStep(for: scaled) else {
                    #expect(rounded == scaled, "to taste unchanged")
                    continue
                }
                #expect(Self.isOnGrid(rounded), "on grid: \(scaled) -> \(rounded)")
                let error = (rounded.value - scaled.value).magnitude
                // Within half the finest step, plus 5 percent when a coarser mark was preferred.
                let tolerance = max(step / 2, step - scaled.value.magnitude) + scaled.value.magnitude * FriendlyRounding.tolerance
                #expect(error <= tolerance, "close enough: \(scaled) -> \(rounded)")
            }
        }
        #expect(checked == Self.baseQuantities.count * Self.factors.count)
    }

    @Test func scalingThenRoundingIsMonotonicInTheFactor() {
        let base = Quantity(Rational(1, 3), .cup)
        var previous = Rational.zero
        for factor in Self.factors.sorted() {
            let rounded = base.scaled(by: factor).friendlyRounded().value
            #expect(rounded >= previous, "factor \(factor): \(rounded) < \(previous)")
            previous = rounded
        }
    }

    @Test func displayPipelineExamples() {
        // 1/3 cup of flour, recipe scaled from 4 to 6 servings.
        let flour = Quantity(Rational(1, 3), .cup).scaled(by: Rational(3, 2))
        #expect(flour.displayed(in: .us).friendlyRounded().formatted() == "½ cup")
        #expect(flour.displayed(in: .metric).friendlyRounded().formatted() == "120 mL")

        // 1/4 cup scaled by 1.5 is 6 tbsp, not ⅜ cup.
        let butter = Quantity(Rational(1, 4), .cup).scaled(by: Rational(3, 2))
        #expect(butter.displayed(in: .us).friendlyRounded().formatted() == "6 tbsp")

        // 1 tsp scaled down by a third.
        let salt = Quantity(1, .teaspoon).scaled(by: Rational(1, 3))
        #expect(salt.displayed(in: .us).friendlyRounded().formatted() == "⅓ tsp")

        // 8 oz of chocolate, doubled, in metric.
        let chocolate = Quantity(8, .ounce).scaled(by: 2)
        #expect(chocolate.displayed(in: .us).friendlyRounded().formatted() == "1 lb")
        #expect(chocolate.displayed(in: .metric).friendlyRounded().formatted() == "450 g")

        // 2 eggs for half a batch.
        let eggs = Quantity(2, .piece).scaled(by: Rational(1, 2))
        #expect(eggs.displayed(in: .us).friendlyRounded().formatted() == "1")

        // 3 cups of stock, quadrupled.
        let stock = Quantity(3, .cup).scaled(by: 4)
        #expect(stock.displayed(in: .us).friendlyRounded().formatted() == "3 qt")
        #expect(stock.displayed(in: .metric).friendlyRounded().formatted() == "2.85 L")
    }
}

/// The amount the detail view shows: scaled exactly, re-expressed in `system` when one is given,
/// then rounded. Mirrors `IngredientLine` in the app.
private func shown(_ quantity: Quantity, scaledBy factor: Rational = 1, in system: MeasurementSystem? = nil) -> String {
    var result = quantity.scaled(by: factor)
    if let system { result = result.displayed(in: system) }
    return result.friendlyRounded().formatted()
}

@Suite("Scaling as a cook would measure")
struct FriendlyScalingTests {
    struct Case: CustomTestStringConvertible, Sendable {
        let quantity: Quantity
        let system: MeasurementSystem
        let expected: String
        var testDescription: String { "\(quantity.value) \(quantity.unit?.rawValue ?? "count") in \(system) → \(expected)" }

        init(_ value: Rational, _ unit: CookingUnit?, in system: MeasurementSystem = .us, _ expected: String) {
            quantity = Quantity(value, unit)
            self.system = system
            self.expected = expected
        }
    }

    /// The Phase 1 acceptance case: a recipe for 4 cooked for 6.
    @Test(arguments: [
        Case(Rational(2), .cup, "3 cups"),
        Case(Rational(1), .cup, "1½ cups"),
        Case(Rational(3, 2), .teaspoon, "2¼ tsp"),
        Case(Rational(3), nil, "4½"),
        Case(Rational(1, 3), .cup, "½ cup"),
        Case(Rational(2, 3), .cup, "1 cup"),
        Case(Rational(1, 4), .cup, "6 tbsp"),
        // 9 tbsp has no close cup measure (½ cup is 11 percent short); the tablespoons hold it exactly.
        Case(Rational(6), .tablespoon, "9 tbsp"),
        // 1⅛ cups: 1 cup and 2 tbsp, rather than a cup that is 11 percent short.
        Case(Rational(3, 4), .cup, "1⅛ cups"),
        Case(Rational(2), .teaspoon, "1 tbsp"),
        Case(Rational(1), .tablespoon, "1½ tbsp"),
        Case(Rational(1), .pound, "1½ lb"),
        Case(Rational(12), .ounce, "18 oz"),
        Case(Rational(500), .gram, in: .metric, "750 g"),
        Case(Rational(250), .gram, in: .metric, "375 g"),
        Case(Rational(750), .milliliter, in: .metric, "1.15 L"),
        Case(Rational(1), .pinch, "2 pinches"),
        // Pints are not a display unit: cooks measure in cups.
        Case(Rational(1), .pint, "3 cups"),
    ])
    func scalesFourToSix(_ scenario: Case) {
        #expect(shown(scenario.quantity, scaledBy: Rational(6, 4), in: scenario.system) == scenario.expected)
    }

    /// Cooking for one from a recipe for 4.
    @Test(arguments: [
        Case(Rational(2), .tablespoon, "1½ tsp"),
        Case(Rational(1, 4), .teaspoon, "⅛ tsp"),
        Case(Rational(1), nil, "¼"),
        Case(Rational(1), .cup, "¼ cup"),
        Case(Rational(1, 2), .cup, "2 tbsp"),
        Case(Rational(1), .pound, "4 oz"),
    ])
    func scalesFourToOne(_ scenario: Case) {
        #expect(shown(scenario.quantity, scaledBy: Rational(1, 4), in: scenario.system) == scenario.expected)
    }

    @Test func roundsAwkwardScalesToTheNearestMeasure() {
        // 4 → 5 servings: 1/3 cup × 5/4 = 5/12 cup, which no cup holds; 6½ tbsp is within 3 percent.
        #expect(shown(Quantity(Rational(1, 3), .cup), scaledBy: Rational(5, 4), in: .us) == "6½ tbsp")
        #expect(shown(Quantity(1, .cup), scaledBy: Rational(6, 5), in: .us) == "1¼ cups")
        // 5 tsp has no clean tablespoon reading, so it stays in teaspoons.
        #expect(shown(Quantity(Rational(5, 2), .teaspoon), scaledBy: 2, in: .us) == "5 tsp")
    }

    @Test func leavesWrittenAmountsAloneAtOneTimes() {
        #expect(shown(Quantity(Rational(3, 8), .teaspoon)) == "⅜ tsp")
        #expect(shown(Quantity(12, .tablespoon)) == "12 tbsp")
        // ...unless nobody could measure them.
        #expect(shown(Quantity(Rational(33, 100), .cup)) == "⅓ cup")
    }

    @Test func scalingIsExactBeforeRounding() {
        // 1/3 × 3 is exactly 1, not 0.999…
        #expect(Quantity(Rational(1, 3), .cup).scaled(by: 3).friendlyRounded() == Quantity(1, .cup))
    }

    @Test func toTasteIgnoresScaling() {
        #expect(shown(Quantity(.zero, .toTaste), scaledBy: 3, in: .us) == "to taste")
    }
}

@Suite("US and metric kitchens")
struct KitchenConversionTests {
    @Test(arguments: [
        (Quantity(1, .cup), "235 mL"),
        (Quantity(Rational(1, 2), .cup), "120 mL"),
        (Quantity(Rational(3, 4), .cup), "175 mL"),
        (Quantity(1, .pound), "450 g"),
        (Quantity(1, .ounce), "28 g"),
        (Quantity(4, .cup), "950 mL"),
        (Quantity(1, .quart), "950 mL"),
        (Quantity(2, .pound), "910 g"),
        (Quantity(3, .pound), "1.35 kg"),
        // Spoons stay spoons in a metric kitchen.
        (Quantity(1, .tablespoon), "1 tbsp"),
        (Quantity(Rational(3, 2), .teaspoon), "1½ tsp"),
        (Quantity(3, .teaspoon), "1 tbsp"),
        (Quantity(8, .tablespoon), "8 tbsp"),
    ])
    func showsInMetric(quantity: Quantity, expected: String) {
        #expect(shown(quantity, in: .metric) == expected)
    }

    @Test(arguments: [
        (Quantity(240, .milliliter), "1 cup"),
        (Quantity(250, .milliliter), "1 cup"),
        (Quantity(15, .milliliter), "1 tbsp"),
        (Quantity(5, .milliliter), "1 tsp"),
        (Quantity(1, .liter), "4¼ cups"),
        (Quantity(1, .kilogram), "2¼ lb"),
        (Quantity(250, .gram), "8¾ oz"),
        (Quantity(500, .gram), "17¾ oz"),
    ])
    func showsInUS(quantity: Quantity, expected: String) {
        #expect(shown(quantity, in: .us) == expected)
    }

    @Test func scalesAndConvertsTogether() {
        // 2 cups for 4, cooked for 6 in a metric kitchen: 3 cups ≈ 710 mL.
        #expect(shown(Quantity(2, .cup), scaledBy: Rational(3, 2), in: .metric) == "710 mL")
        // Spoons that add up past half a cup become millilitres in metric.
        #expect(shown(Quantity(6, .tablespoon), scaledBy: 2, in: .metric) == "175 mL")
    }

    @Test func leavesTheMatchingSystemAlone() {
        let flour = Quantity(500, .gram)
        #expect(flour.displayed(in: .metric).friendlyRounded() == flour)
        #expect(Quantity(5, .milliliter).displayed(in: .metric) == Quantity(5, .milliliter))
    }

    @Test func findsTheDominantSystem() {
        #expect(MeasurementSystem.dominant(in: [.gram, .gram, .cup, .teaspoon, nil]) == .metric)
        #expect(MeasurementSystem.dominant(in: [.cup, .gram]) == .us)
        #expect(MeasurementSystem.dominant(in: [.teaspoon, nil, .pinch]) == nil)
        #expect(MeasurementSystem.dominant(in: [.tablespoon, .tablespoon, .gram]) == .metric)
    }
}
