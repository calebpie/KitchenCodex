import Testing
@testable import Units

@Suite("Unit conversion")
struct UnitConversionTests {
    static let volumeUnits = CookingUnit.allCases.filter { $0.dimension == .volume }
    static let massUnits = CookingUnit.allCases.filter { $0.dimension == .mass }
    static let convertibleUnits = volumeUnits + massUnits

    @Test func classifiesEveryUnit() {
        for unit in CookingUnit.allCases {
            #expect(unit.isVolume == (unit.dimension == .volume))
            #expect(unit.isMass == (unit.dimension == .mass))
            #expect(unit.isConvertible == (unit.isVolume || unit.isMass))
            #expect((unit.system == nil) == !unit.isConvertible)
        }
        #expect(CookingUnit.piece.dimension == .count)
        #expect(CookingUnit.pinch.dimension == .informal)
        #expect(CookingUnit.cup.system == .us)
        #expect(CookingUnit.gram.system == .metric)
    }

    @Test(arguments: [
        (CookingUnit.cup, CookingUnit.tablespoon, Rational(16)),
        (.cup, .teaspoon, Rational(48)),
        (.cup, .fluidOunce, Rational(8)),
        (.tablespoon, .teaspoon, Rational(3)),
        (.pint, .cup, Rational(2)),
        (.quart, .pint, Rational(2)),
        (.gallon, .quart, Rational(4)),
        (.gallon, .cup, Rational(16)),
        (.liter, .milliliter, Rational(1_000)),
        (.pound, .ounce, Rational(16)),
        (.kilogram, .gram, Rational(1_000)),
        (.teaspoon, .cup, Rational(1, 48)),
        (.ounce, .pound, Rational(1, 16)),
    ])
    func exactTablesWithinASystem(from: CookingUnit, to: CookingUnit, factor: Rational) {
        #expect(from.conversionFactor(to: to) == factor)
        #expect(to.conversionFactor(to: from) == factor.reciprocal)
    }

    @Test func crossSystemFactorsAreTheDocumentedRationals() {
        #expect(CookingUnit.millilitersPerCup == Rational(59_147, 250))
        #expect(CookingUnit.gramsPerOunce == Rational(56_699, 2_000))
        #expect(CookingUnit.cup.conversionFactor(to: .milliliter) == Rational(236_588, 1_000))
        #expect(CookingUnit.ounce.conversionFactor(to: .gram) == Rational(283_495, 10_000))
        #expect(CookingUnit.teaspoon.conversionFactor(to: .milliliter) == Rational(236_588, 48_000))
        #expect(CookingUnit.pound.conversionFactor(to: .gram) == Rational(283_495, 10_000) * 16)
        #expect(CookingUnit.gallon.conversionFactor(to: .liter) == Rational(236_588, 1_000) * 16 / 1_000)
        #expect(abs(CookingUnit.milliliter.conversionFactor(to: .cup)!.doubleValue - 1 / 236.588) < 1e-12)
        #expect(abs(CookingUnit.kilogram.conversionFactor(to: .pound)!.doubleValue - 2.2046244) < 1e-6)
    }

    @Test(arguments: [
        (CookingUnit.cup, CookingUnit.gram),
        (.gram, .cup),
        (.milliliter, .kilogram),
        (.piece, .cup),
        (.piece, .gram),
        (.pinch, .teaspoon),
        (.dash, .pinch),
        (.toTaste, .piece),
    ])
    func incompatibleUnitsDoNotConvert(from: CookingUnit, to: CookingUnit) {
        #expect(from.conversionFactor(to: to) == nil)
        #expect(!from.canConvert(to: to))
        #expect(Quantity(1, from).converted(to: to) == nil)
    }

    @Test func quantityConversionExamples() {
        #expect(Quantity(48, .teaspoon).converted(to: .cup) == Quantity(1, .cup))
        #expect(Quantity(Rational(1, 3), .cup).converted(to: .tablespoon) == Quantity(Rational(16, 3), .tablespoon))
        #expect(Quantity(2, .cup).converted(to: .milliliter) == Quantity(Rational(236_588, 500), .milliliter))
        #expect(Quantity(1, .pound).converted(to: .gram) == Quantity(Rational(283_495, 625), .gram))
        #expect(Quantity(1_500, .milliliter).converted(to: .liter) == Quantity(Rational(3, 2), .liter))
        #expect(Quantity(3, .piece).converted(to: .piece) == Quantity(3, .piece))
        #expect(Quantity(3, nil).converted(to: .cup) == nil)
    }

    @Test func roundTripsAreExactForEveryConvertiblePair() {
        let samples: [Rational] = [Rational(1, 3), Rational(1), Rational(7, 4), Rational(250), Rational(2_000)]
        for from in Self.convertibleUnits {
            for to in Self.convertibleUnits where from.dimension == to.dimension {
                for sample in samples {
                    let quantity = Quantity(sample, from)
                    let there = quantity.converted(to: to)
                    #expect(there != nil, "\(from) -> \(to)")
                    #expect(there?.unit == to)
                    #expect(there?.converted(to: from) == quantity, "\(from) -> \(to) -> \(from)")
                }
            }
        }
    }

    @Test func conversionChainsMatchDirectFactors() {
        for a in Self.convertibleUnits {
            for b in Self.convertibleUnits where a.dimension == b.dimension {
                for c in Self.convertibleUnits where a.dimension == c.dimension {
                    let direct = a.conversionFactor(to: c)!
                    let chained = a.conversionFactor(to: b)! * b.conversionFactor(to: c)!
                    #expect(direct == chained, "\(a) -> \(b) -> \(c)")
                }
            }
        }
    }
}

@Suite("Display unit selection")
struct DisplayUnitTests {
    @Test(arguments: [
        (Quantity(48, .teaspoon), MeasurementSystem.us, Quantity(1, .cup)),
        (Quantity(1_500, .milliliter), .metric, Quantity(Rational(3, 2), .liter)),
        (Quantity(Rational(1, 2), .teaspoon), .us, Quantity(Rational(1, 2), .teaspoon)),
        (Quantity(2_000, .gram), .metric, Quantity(2, .kilogram)),
        (Quantity(3, .teaspoon), .us, Quantity(1, .tablespoon)),
        (Quantity(2, .teaspoon), .us, Quantity(2, .teaspoon)),
        (Quantity(Rational(9, 2), .teaspoon), .us, Quantity(Rational(3, 2), .tablespoon)),
        (Quantity(4, .teaspoon), .us, Quantity(4, .teaspoon)),
        (Quantity(7, .teaspoon), .us, Quantity(7, .teaspoon)),
        // 17 tsp is within 5 percent of 5½ tbsp, so tablespoons win over 17/48 cup.
        (Quantity(17, .teaspoon), .us, Quantity(Rational(17, 3), .tablespoon)),
        (Quantity(Rational(53, 10), .teaspoon), .us, Quantity(Rational(53, 30), .tablespoon)),
        (Quantity(15, .tablespoon), .us, Quantity(15, .tablespoon)),
        (Quantity(19, .tablespoon), .us, Quantity(Rational(19, 16), .cup)),
        (Quantity(20, .tablespoon), .us, Quantity(Rational(5, 4), .cup)),
        (Quantity(Rational(11, 10), .cup), .us, Quantity(Rational(11, 10), .cup)),
        (Quantity(4, .tablespoon), .us, Quantity(Rational(1, 4), .cup)),
        (Quantity(Rational(16, 3), .tablespoon), .us, Quantity(Rational(1, 3), .cup)),
        (Quantity(6, .tablespoon), .us, Quantity(6, .tablespoon)),
        (Quantity(Rational(1, 8), .cup), .us, Quantity(2, .tablespoon)),
        (Quantity(Rational(3, 8), .cup), .us, Quantity(6, .tablespoon)),
        (Quantity(Rational(11, 30), .cup), .us, Quantity(Rational(88, 15), .tablespoon)),
        (Quantity(Rational(5, 12), .cup), .us, Quantity(Rational(20, 3), .tablespoon)),
        (Quantity(Rational(6, 5), .cup), .us, Quantity(Rational(6, 5), .cup)),
        (Quantity(4, .cup), .us, Quantity(4, .cup)),
        (Quantity(1, .pint), .us, Quantity(2, .cup)),
        (Quantity(8, .fluidOunce), .us, Quantity(1, .cup)),
        (Quantity(10, .cup), .us, Quantity(Rational(5, 2), .quart)),
        (Quantity(9, .cup), .us, Quantity(9, .cup)),
        (Quantity(16, .cup), .us, Quantity(1, .gallon)),
        (Quantity(999, .milliliter), .metric, Quantity(999, .milliliter)),
        (Quantity(1_000, .milliliter), .metric, Quantity(1, .liter)),
        (Quantity(Rational(1, 2), .liter), .metric, Quantity(500, .milliliter)),
        (Quantity(Rational(3, 4), .kilogram), .metric, Quantity(750, .gram)),
        (Quantity(12, .ounce), .us, Quantity(12, .ounce)),
        (Quantity(16, .ounce), .us, Quantity(1, .pound)),
        (Quantity(20, .ounce), .us, Quantity(Rational(5, 4), .pound)),
        (Quantity(18, .ounce), .us, Quantity(18, .ounce)),
        (Quantity(Rational(1, 2), .pound), .us, Quantity(8, .ounce)),
        // Spoons stay spoons in metric up to half a cup, then become millilitres.
        (Quantity(1, .tablespoon), .metric, Quantity(1, .tablespoon)),
        (Quantity(Rational(3, 2), .teaspoon), .metric, Quantity(Rational(3, 2), .teaspoon)),
        (Quantity(3, .teaspoon), .metric, Quantity(1, .tablespoon)),
        (Quantity(8, .tablespoon), .metric, Quantity(8, .tablespoon)),
        (Quantity(12, .tablespoon), .metric, Quantity(Rational(236_588 * 3, 4_000), .milliliter)),
        (Quantity(25, .teaspoon), .metric, Quantity(Rational(236_588 * 25, 48_000), .milliliter)),
    ])
    func picksTheMostReadableUnit(input: Quantity, system: MeasurementSystem, expected: Quantity) {
        #expect(input.displayed(in: system) == expected)
    }

    @Test func crossesSystemsExactly() {
        #expect(Quantity(1, .cup).displayed(in: .metric) == Quantity(Rational(236_588, 1_000), .milliliter))
        #expect(Quantity(5, .cup).displayed(in: .metric) == Quantity(Rational(236_588 * 5, 1_000_000), .liter))
        #expect(Quantity(2, .pound).displayed(in: .metric) == Quantity(Rational(283_495 * 32, 10_000), .gram))
        #expect(Quantity(500, .gram).displayed(in: .us).unit == .ounce)
        // 1 kg is within 5 percent of 2¼ lb, so it reads in pounds.
        #expect(Quantity(1, .kilogram).displayed(in: .us).unit == .pound)
        #expect(Quantity(250, .milliliter).displayed(in: .us).unit == .cup)
        #expect(Quantity(15, .milliliter).displayed(in: .us).unit == .tablespoon)
        #expect(Quantity(5, .milliliter).displayed(in: .us).unit == .teaspoon)
    }

    @Test func leavesNonConvertibleQuantitiesAlone() {
        for unit: CookingUnit? in [.piece, .pinch, .dash, .toTaste, nil] {
            let quantity = Quantity(Rational(7, 2), unit)
            #expect(quantity.displayed(in: .us) == quantity)
            #expect(quantity.displayed(in: .metric) == quantity)
        }
    }

    @Test func displayedPreservesTheAmount() {
        for unit in UnitConversionTests.convertibleUnits {
            for value: Rational in [Rational(1, 8), Rational(7, 3), Rational(60), Rational(4_321)] {
                for system in MeasurementSystem.allCases {
                    let original = Quantity(value, unit)
                    let shown = original.displayed(in: system)
                    let keptSpoon = system == .metric && unit.isSpoon && shown.unit?.isSpoon == true
                    #expect(shown.unit?.system == system || keptSpoon, "\(original) shown in \(system) as \(shown)")
                    #expect(shown.converted(to: unit) == original, "\(original) shown in \(system) as \(shown)")
                }
            }
        }
    }
}
