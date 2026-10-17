import Foundation

/// What a unit measures. Conversion is only defined within `volume` and within `mass`.
public enum UnitDimension: String, Hashable, Sendable, Codable, CaseIterable {
    case volume
    case mass
    case count
    case informal
}

extension CookingUnit {
    /// Millilitres in one US cup, as the exact rational 236588/1000.
    public static let millilitersPerCup = Rational(236_588, 1_000)

    /// Grams in one avoirdupois ounce, as the exact rational 283495/10000.
    public static let gramsPerOunce = Rational(283_495, 10_000)

    public var dimension: UnitDimension {
        switch self {
        case .teaspoon, .tablespoon, .fluidOunce, .cup, .pint, .quart, .gallon, .milliliter, .liter:
            .volume
        case .ounce, .pound, .gram, .kilogram:
            .mass
        case .piece:
            .count
        case .pinch, .dash, .toTaste:
            .informal
        }
    }

    /// The measurement system the unit belongs to, or nil for count and informal units.
    public var system: MeasurementSystem? {
        switch self {
        case .teaspoon, .tablespoon, .fluidOunce, .cup, .pint, .quart, .gallon, .ounce, .pound:
            .us
        case .milliliter, .liter, .gram, .kilogram:
            .metric
        case .piece, .pinch, .dash, .toTaste:
            nil
        }
    }

    /// True for volume and mass units, which have conversion tables.
    public var isConvertible: Bool {
        dimension == .volume || dimension == .mass
    }

    /// Whether a value in this unit can be expressed in `other`: both must be volume or both mass.
    public func canConvert(to other: CookingUnit) -> Bool {
        isConvertible && dimension == other.dimension
    }

    /// The exact factor that turns a value in this unit into the same amount in `other`,
    /// or nil when the units are incompatible (volume to mass, counts, informal units).
    ///
    /// Within a system the tables are exact: 1 cup = 16 tbsp = 48 tsp = 8 fl oz, 1 pint = 2 cups,
    /// 1 quart = 2 pints, 1 gallon = 4 quarts, 1 L = 1000 mL; 1 lb = 16 oz, 1 kg = 1000 g.
    /// Across systems 1 cup = 236.588 mL and 1 oz = 28.3495 g, held as rationals.
    public func conversionFactor(to other: CookingUnit) -> Rational? {
        guard canConvert(to: other), let from = system, let to = other.system else { return nil }
        var factor = factorToSystemBase
        if from != to {
            factor = factor * CookingUnit.crossSystemFactor(dimension: dimension, from: from, to: to)
        }
        return factor * other.factorToSystemBase.reciprocal
    }

    /// Factor to the base unit of this unit's system: teaspoon or millilitre for volume,
    /// ounce or gram for mass. Count and informal units map to 1 but are never converted.
    var factorToSystemBase: Rational {
        switch self {
        case .teaspoon: 1
        case .tablespoon: 3
        case .fluidOunce: 6
        case .cup: 48
        case .pint: 96
        case .quart: 192
        case .gallon: 768
        case .milliliter: 1
        case .liter: 1_000
        case .ounce: 1
        case .pound: 16
        case .gram: 1
        case .kilogram: 1_000
        case .piece, .pinch, .dash, .toTaste: 1
        }
    }

    /// Factor from the base unit of `from` to the base unit of `to` for one dimension.
    static func crossSystemFactor(dimension: UnitDimension, from: MeasurementSystem, to: MeasurementSystem) -> Rational {
        guard from != to else { return 1 }
        let usToMetric: Rational
        switch dimension {
        case .volume: usToMetric = millilitersPerCup / CookingUnit.cup.factorToSystemBase  // mL per tsp
        case .mass: usToMetric = gramsPerOunce                                               // g per oz
        case .count, .informal: return 1
        }
        return from == .us ? usToMetric : usToMetric.reciprocal
    }
}

extension Quantity {
    /// The same amount expressed in `target`, exactly, or nil when there is no unit or the units
    /// are incompatible. A quantity already in `target` is returned unchanged, whatever its unit.
    public func converted(to target: CookingUnit) -> Quantity? {
        guard let unit else { return nil }
        if unit == target { return self }
        guard let factor = unit.conversionFactor(to: target) else { return nil }
        return Quantity(value * factor, target)
    }

    /// The amount re-expressed in the unit of `system` that reads best for its size.
    ///
    /// Quantities without a unit, counts and informal units come back unchanged. The result is
    /// exact; call ``friendlyRounded()`` afterwards to snap the value to measurable fractions.
    ///
    /// Metric: millilitres and grams, switching to litres and kilograms at 1000.
    ///
    /// US volume: teaspoons below 1 tbsp, tablespoons below ¼ cup, cups below 2 quarts, then
    /// quarts and gallons. A unit is only chosen when the value reads cleanly in it (whole
    /// teaspoons up to 8, tablespoons in halves up to 16, cups in quarters or thirds, quarts and
    /// gallons in halves), so 5 tsp stays 5 tsp and 6 tbsp stays 6 tbsp while 48 tsp becomes
    /// 1 cup. When no unit reads cleanly the largest unit that fits is used and friendly rounding
    /// does the rest, so 1.1 cups stays in cups rather than becoming 17.6 tbsp.
    ///
    /// US mass: ounces, or pounds when the amount is at least a pound and a multiple of ¼ lb.
    public func displayed(in system: MeasurementSystem) -> Quantity {
        guard let unit, unit.isConvertible else { return self }
        let candidates = CookingUnit.displayCandidates(dimension: unit.dimension, system: system)
        let converted = candidates.compactMap { candidate -> (unit: CookingUnit, value: Rational, threshold: Rational, clean: Bool)? in
            guard let factor = unit.conversionFactor(to: candidate.unit) else { return nil }
            let v = value * factor
            let withinCeiling = candidate.ceiling.map { v.magnitude <= $0 } ?? true
            let onGrid = candidate.cleanSteps.isEmpty || candidate.cleanSteps.contains { v.magnitude.isMultiple(of: $0) }
            return (candidate.unit, v, candidate.threshold, withinCeiling && onGrid)
        }
        let fitting = converted.filter { $0.value.magnitude >= $0.threshold }
        // US mass falls back to ounces (a scale reads whole ounces); everything else to the largest unit that fits.
        let fallback = unit.dimension == .mass && system == .us ? fitting.last : fitting.first
        if let best = fitting.first(where: { $0.clean }) ?? fallback {
            return Quantity(best.value, best.unit)
        }
        // Below every threshold: the smallest candidate.
        if let smallest = converted.last { return Quantity(smallest.value, smallest.unit) }
        return self
    }
}

extension CookingUnit {
    struct DisplayCandidate {
        var unit: CookingUnit
        /// Smallest magnitude, in `unit`, at which the unit is considered.
        var threshold: Rational
        /// Largest magnitude, in `unit`, at which the unit is still preferred over a larger one.
        var ceiling: Rational? = nil
        /// Steps a value must be a multiple of to read cleanly; empty means any value is fine.
        var cleanSteps: [Rational]
    }

    /// Display units from largest to smallest.
    static func displayCandidates(dimension: UnitDimension, system: MeasurementSystem) -> [DisplayCandidate] {
        switch (dimension, system) {
        case (.volume, .us):
            [
                DisplayCandidate(unit: .gallon, threshold: 1, cleanSteps: [Rational(1, 2)]),
                DisplayCandidate(unit: .quart, threshold: 2, cleanSteps: [Rational(1, 2)]),
                DisplayCandidate(unit: .cup, threshold: Rational(1, 4), cleanSteps: [Rational(1, 4), Rational(1, 3)]),
                DisplayCandidate(unit: .tablespoon, threshold: 1, ceiling: 16, cleanSteps: [Rational(1, 2)]),
                DisplayCandidate(unit: .teaspoon, threshold: 0, ceiling: 8, cleanSteps: [1]),
            ]
        case (.volume, .metric):
            [
                DisplayCandidate(unit: .liter, threshold: 1, cleanSteps: []),
                DisplayCandidate(unit: .milliliter, threshold: 0, cleanSteps: []),
            ]
        case (.mass, .us):
            [
                DisplayCandidate(unit: .pound, threshold: 1, cleanSteps: [Rational(1, 4)]),
                DisplayCandidate(unit: .ounce, threshold: 0, cleanSteps: []),
            ]
        case (.mass, .metric):
            [
                DisplayCandidate(unit: .kilogram, threshold: 1, cleanSteps: []),
                DisplayCandidate(unit: .gram, threshold: 0, cleanSteps: []),
            ]
        case (.count, _), (.informal, _):
            []
        }
    }
}
