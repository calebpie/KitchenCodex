import Foundation

extension CookingUnit {
    /// The system this unit belongs to. `nil` for units every kitchen uses: spoons, counts, pinches.
    /// Teaspoons and tablespoons stay spoons in metric (5 ml and 15 ml), so they are shared.
    public var system: MeasurementSystem? {
        switch self {
        case .cup, .fluidOunce, .pint, .quart, .gallon, .ounce, .pound: .us
        case .milliliter, .liter, .gram, .kilogram: .metric
        case .teaspoon, .tablespoon, .piece, .pinch, .dash, .toTaste: nil
        }
    }

    /// Milliliters for a volume unit, grams for a mass unit.
    var metricSize: Double? {
        switch self {
        case .teaspoon: 4.928_921_593_75
        case .tablespoon: 14.786_764_781_25
        case .fluidOunce: 29.573_529_562_5
        case .cup: 236.588_236_5
        case .pint: 473.176_473
        case .quart: 946.352_946
        case .gallon: 3_785.411_784
        case .milliliter, .gram: 1
        case .liter, .kilogram: 1_000
        case .ounce: 28.349_523_125
        case .pound: 453.592_37
        case .piece, .pinch, .dash, .toTaste: nil
        }
    }

    /// What follows the amount on screen: "tsp", "cup" or "cups", "g". Plural above one.
    public func label(for amount: Rational) -> String {
        let plural = amount > .one
        return switch self {
        case .teaspoon: "tsp"
        case .tablespoon: "tbsp"
        case .fluidOunce: "fl oz"
        case .cup: plural ? "cups" : "cup"
        case .pint: plural ? "pints" : "pint"
        case .quart: plural ? "quarts" : "quart"
        case .gallon: plural ? "gallons" : "gallon"
        case .milliliter: "ml"
        case .liter: "L"
        case .ounce: "oz"
        case .pound: "lb"
        case .gram: "g"
        case .kilogram: "kg"
        case .piece: plural ? "pieces" : "piece"
        case .pinch: plural ? "pinches" : "pinch"
        case .dash: plural ? "dashes" : "dash"
        case .toTaste: "to taste"
        }
    }
}

extension Quantity {
    /// The amount a cook would actually measure: scaled exactly by `factor`, converted when `system`
    /// is given and the unit belongs to the other system, then rounded to what cups, spoons and
    /// scales can hold. "1/3 cup" × 3/2 is "1/2 cup"; "1/4 cup" × 3/2 is "6 tbsp", not "3/8 cup";
    /// "1 cup" in metric is "240 ml".
    ///
    /// With no scaling and no conversion the amount is returned as written, unless it has a
    /// denominator nobody measures ("0.33 cup" becomes "1/3 cup").
    public func friendly(scaledBy factor: Rational = .one, in system: MeasurementSystem? = nil) -> Quantity {
        let exact = scaled(by: factor)
        let converts = system != nil && unit?.system != nil && unit?.system != system
        if factor == .one, !converts, exact.isMeasurable { return exact }

        let amount = exact.value.doubleValue
        guard amount > 0, let unit else {
            return amount > 0 ? Quantity(FriendlyRounding.count(amount), nil) : exact
        }

        switch unit {
        case .toTaste:
            return exact
        case .pinch, .dash:
            return Quantity(Rational(max(1, Int(amount.rounded()))), unit)
        case .piece:
            return Quantity(FriendlyRounding.count(amount), unit)
        default:
            break
        }

        guard let size = unit.metricSize else { return exact }
        let base = amount * size
        let target = converts ? system! : (unit.system ?? system ?? .us)
        let isVolume = unit.isVolume

        switch target {
        case .metric:
            // Spoons stay spoons in a metric kitchen until they add up to more than half a cup.
            if unit.system == nil, base <= 8 * CookingUnit.tablespoon.metricSize! {
                return FriendlyRounding.customary(base: base, preferred: unit, candidates: [.tablespoon, .teaspoon])
            }
            return FriendlyRounding.metric(base: base, isVolume: isVolume, keepsExactFives: !converts)
        case .us:
            return FriendlyRounding.customary(
                base: base,
                preferred: unit.system == .metric ? nil : unit,
                candidates: isVolume ? [.cup, .tablespoon, .teaspoon] : [.pound, .ounce]
            )
        }
    }

    /// The amount as shown: a mixed number for customary units and counts ("1 1/2"), a decimal for
    /// metric units ("1.5").
    public func formattedAmount(locale: Locale = .current) -> String {
        if unit?.system == .metric {
            return value.doubleValue.formatted(.number.precision(.fractionLength(0...2)).locale(locale))
        }
        return value.description
    }

    /// Amount and unit, "1 1/2 cups" or "240 ml". A counted item is just its amount; "to taste" has none.
    public func formatted(locale: Locale = .current) -> String {
        guard let unit else { return formattedAmount(locale: locale) }
        if unit == .toTaste { return unit.label(for: value) }
        return "\(formattedAmount(locale: locale)) \(unit.label(for: value))"
    }

    /// Whether the exact amount is already something a cook can measure.
    var isMeasurable: Bool {
        unit?.system == .metric || [1, 2, 3, 4, 8].contains(value.denominator)
    }
}

/// The rounding tables behind `Quantity.friendly`.
enum FriendlyRounding {
    /// Within this relative error a rounding is accepted without trying another unit.
    static let tolerance = 0.05

    private static func fractions(_ denominators: Int...) -> [Rational] {
        var set: Set<Rational> = [.zero]
        for denominator in denominators {
            for numerator in 1..<denominator { set.insert(Rational(numerator, denominator)) }
        }
        return set.sorted()
    }

    private struct Spec {
        /// The amounts, in this unit, where the unit is the natural choice.
        var range: Range<Double>
        /// Fractional parts tried first, then the finer set when no unit fits the first.
        var nice: [Rational]
        var fine: [Rational]
    }

    private static func spec(for unit: CookingUnit) -> Spec {
        switch unit {
        // Bounds carry a small margin because amounts arrive through floating-point conversion.
        case .teaspoon: Spec(range: 0..<2.999, nice: fractions(4), fine: fractions(8))
        case .tablespoon: Spec(range: 0.999..<8.001, nice: fractions(2), fine: fractions(4))
        case .cup: Spec(range: 0.249..<Double.infinity, nice: fractions(3, 4), fine: fractions(3, 8))
        case .fluidOunce: Spec(range: 0.999..<Double.infinity, nice: fractions(2), fine: fractions(4))
        case .ounce: Spec(range: 0..<31.999, nice: fractions(4), fine: fractions(8))
        default: Spec(range: 0.999..<Double.infinity, nice: fractions(4), fine: fractions(8))
        }
    }

    /// Cups, spoons, ounces and pounds. Tries the original unit with its nice fractions, then the
    /// other candidates from largest to smallest, then whichever in-range unit (or the original unit,
    /// in range or not) rounds closest with finer fractions: 9 tbsp stays 9 tbsp rather than
    /// becoming a half cup that is 11% short.
    static func customary(base: Double, preferred: CookingUnit?, candidates: [CookingUnit]) -> Quantity {
        let order = ([preferred].compactMap(\.self) + candidates.filter { $0 != preferred })
        let fitting = order.filter { spec(for: $0).range.contains(amount(base, in: $0)) }

        for unit in fitting {
            let (value, error) = nearest(amount(base, in: unit), fractions: spec(for: unit).nice)
            if error <= tolerance { return Quantity(value, unit) }
        }

        var pool = fitting
        if let preferred, !pool.contains(preferred) { pool.insert(preferred, at: 0) }
        if pool.isEmpty { pool = Array(order.suffix(1)) }
        var best: (quantity: Quantity, error: Double)?
        for unit in pool {
            let (value, error) = nearest(amount(base, in: unit), fractions: spec(for: unit).fine)
            if best == nil || error < best!.error - 1e-9 { best = (Quantity(value, unit), error) }
        }
        return best!.quantity
    }

    /// Grams and kilograms, milliliters and liters, rounded to numbers a scale or jug shows.
    /// `keepsExactFives` leaves an amount that is already a multiple of 5 alone (375 g stays 375 g)
    /// when the source was metric; converted amounts round on the coarser grid (1 lb is 450 g).
    static func metric(base: Double, isVolume: Bool, keepsExactFives: Bool) -> Quantity {
        let (small, large): (CookingUnit, CookingUnit) = isVolume ? (.milliliter, .liter) : (.gram, .kilogram)
        let step: Rational = switch base {
        case ..<10: Rational(1, 2)
        case ..<50: .one
        case ..<100: Rational(5)
        default: isMultiple(base, of: 5) && keepsExactFives ? Rational(5) : Rational(10)
        }
        let rounded = step * Rational(max(1, Int((base / step.doubleValue).rounded())))
        guard rounded.doubleValue >= 1_000 else { return Quantity(rounded, small) }

        let fifties = max(1, Int((base / 50).rounded()))
        return Quantity(Rational(fifties * 50, 1_000), large)
    }

    /// Eggs, onions, pieces: quarters and thirds below one, halves below ten, whole numbers above.
    static func count(_ amount: Double) -> Rational {
        if amount < 1 { return nearest(amount, fractions: fractions(3, 4)).value }
        if amount < 10 { return nearest(amount, fractions: fractions(2)).value }
        return Rational(Int(amount.rounded()))
    }

    private static func amount(_ base: Double, in unit: CookingUnit) -> Double {
        base / (unit.metricSize ?? 1)
    }

    private static func isMultiple(_ value: Double, of step: Double) -> Bool {
        abs(value / step - (value / step).rounded()) < 1e-6
    }

    /// The closest non-zero `whole + fraction`, with its relative error.
    static func nearest(_ amount: Double, fractions: [Rational]) -> (value: Rational, error: Double) {
        let whole = Int(amount.rounded(.down))
        var best: (value: Rational, distance: Double)?
        for candidateWhole in [whole, whole + 1] {
            for fraction in fractions {
                let candidate = Rational(candidateWhole) + fraction
                guard candidate > .zero else { continue }
                let distance = abs(candidate.doubleValue - amount)
                if best == nil || distance < best!.distance - 1e-9 { best = (candidate, distance) }
            }
        }
        let value = best?.value ?? fractions.first { $0 > .zero } ?? .one
        return (value, amount > 0 ? abs(value.doubleValue - amount) / amount : 0)
    }
}

extension MeasurementSystem {
    /// The system most of a recipe's measured ingredients are written in, or `nil` when none of them
    /// belongs to one (spoons and counts only). Ties go to US.
    public static func dominant(in units: some Sequence<CookingUnit?>) -> MeasurementSystem? {
        var us = 0
        var metric = 0
        for unit in units {
            switch unit?.system {
            case .us: us += 1
            case .metric: metric += 1
            case nil: break
            }
        }
        if us == 0, metric == 0 { return nil }
        return metric > us ? .metric : .us
    }
}
