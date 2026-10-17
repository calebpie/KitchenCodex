import Testing
@testable import Units

@Suite("Friendly rounding")
struct FriendlyRoundingTests {
    @Test(arguments: [
        // Teaspoons and tablespoons: halves, thirds, quarters, eighths.
        (Quantity(Rational(7, 16), .teaspoon), Rational(1, 2)),
        (Quantity(Rational(3, 10), .teaspoon), Rational(1, 3)),
        (Quantity(Rational(29, 100), .teaspoon), Rational(1, 4)),
        (Quantity(Rational(13, 100), .teaspoon), Rational(1, 8)),
        (Quantity(Rational(5, 3), .tablespoon), Rational(5, 3)),
        (Quantity(Rational(11, 10), .tablespoon), Rational(9, 8)),
        (Quantity(Rational(49, 50), .tablespoon), Rational(1)),
        // Cups: halves, thirds, quarters. Never eighths.
        (Quantity(Rational(11, 30), .cup), Rational(1, 3)),
        (Quantity(Rational(3, 8), .cup), Rational(1, 3)),
        (Quantity(Rational(5, 12), .cup), Rational(1, 2)),
        (Quantity(Rational(7, 10), .cup), Rational(2, 3)),
        (Quantity(Rational(1, 8), .cup), Rational(1, 4)),
        (Quantity(Rational(23, 10), .cup), Rational(7, 3)),
        (Quantity(Rational(14, 5), .cup), Rational(11, 4)),
        // Larger US units: halves and quarters.
        (Quantity(Rational(33, 10), .fluidOunce), Rational(13, 4)),
        (Quantity(Rational(17, 16), .pound), Rational(1)),
        (Quantity(Rational(21, 10), .quart), Rational(2)),
        // Grams and millilitres: whole below 30, 5s below 300, 10s from 300.
        (Quantity(Rational(49, 10), .gram), Rational(5)),
        (Quantity(Rational(283_495, 10_000), .gram), Rational(28)),
        (Quantity(Rational(236_588, 2_000), .milliliter), Rational(120)),
        (Quantity(Rational(236_588, 1_000), .milliliter), Rational(235)),
        (Quantity(Rational(283_495, 625), .gram), Rational(450)),
        (Quantity(Rational(347), .gram), Rational(350)),
        (Quantity(Rational(3, 10), .gram), Rational(1)),
        // Litres and kilograms: 0.05.
        (Quantity(Rational(1_234, 1_000), .kilogram), Rational(5, 4)),
        (Quantity(Rational(1_49, 100), .liter), Rational(3, 2)),
        // Counts: halves.
        (Quantity(Rational(7, 3), .piece), Rational(5, 2)),
        (Quantity(Rational(3, 4), .piece), Rational(1)),
        (Quantity(Rational(1, 10), .piece), Rational(1, 2)),
        (Quantity(Rational(7, 3), nil), Rational(5, 2)),
    ])
    func snapsToMeasurableFractions(input: Quantity, expected: Rational) {
        let rounded = input.friendlyRounded()
        #expect(rounded.value == expected, "\(input.value) \(String(describing: input.unit)) -> \(rounded.value)")
        #expect(rounded.unit == input.unit)
    }

    @Test(arguments: [CookingUnit.pinch, .dash, .toTaste])
    func leavesInformalUnitsAlone(unit: CookingUnit) {
        let quantity = Quantity(Rational(7, 13), unit)
        #expect(quantity.friendlyRounded() == quantity)
    }

    @Test func zeroStaysZeroAndNonzeroNeverVanishes() {
        #expect(Quantity(0, .cup).friendlyRounded().value == 0)
        #expect(Quantity(Rational(1, 1_000), .teaspoon).friendlyRounded().value == Rational(1, 8))
        #expect(Quantity(Rational(1, 1_000), .cup).friendlyRounded().value == Rational(1, 4))
        #expect(Quantity(Rational(1, 1_000), .gram).friendlyRounded().value == 1)
        #expect(Quantity(Rational(1, 1_000), .kilogram).friendlyRounded().value == Rational(1, 20))
        #expect(Quantity(Rational(-1, 1_000), .teaspoon).friendlyRounded().value == Rational(-1, 8))
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
        default: FriendlyRounding.fractionSteps(for: quantity.unit).last
        }
    }

    private static func isOnGrid(_ quantity: Quantity) -> Bool {
        let steps: [Rational]
        switch quantity.unit {
        case .gram?, .milliliter?: steps = [1]
        default: steps = FriendlyRounding.fractionSteps(for: quantity.unit)
        }
        return steps.contains { quantity.value.isMultiple(of: $0) }
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
                    #expect(rounded == scaled, "informal units unchanged")
                    continue
                }
                #expect(Self.isOnGrid(rounded), "on grid: \(scaled) -> \(rounded)")
                let error = (rounded.value - scaled.value).magnitude
                let tolerance = max(step / 2, step - scaled.value.magnitude)
                #expect(error <= tolerance, "within half a step: \(scaled) -> \(rounded)")
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
