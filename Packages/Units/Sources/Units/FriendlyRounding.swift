import Foundation

/// Rounding to the fractions a cook can actually measure.
enum FriendlyRounding {
    /// Within this relative error a coarse fraction is accepted over a closer fine one, and a
    /// display unit is accepted although the value is not exactly on its grid.
    static let tolerance = Rational(1, 20)

    /// Fraction steps a value in `unit` snaps to, coarsest first.
    ///
    /// `nice` are the marks on the measuring set itself and are tried first, accepted when within
    /// ``tolerance``; `fine` is the full list a value may land on when nothing nice is close.
    /// Ties between steps prefer the earlier (coarser) one. Empty means the value is left unchanged.
    static func fractionSteps(for unit: CookingUnit?) -> (nice: [Rational], fine: [Rational]) {
        guard let unit else { return ([], []) }
        switch unit {
        case .teaspoon:
            return ([Rational(1, 2), Rational(1, 4)],
                    [Rational(1, 2), Rational(1, 3), Rational(1, 4), Rational(1, 8)])
        case .tablespoon:
            return ([Rational(1, 2)],
                    [Rational(1, 2), Rational(1, 3), Rational(1, 4), Rational(1, 8)])
        case .cup:
            return ([Rational(1, 2), Rational(1, 3), Rational(1, 4)],
                    [Rational(1, 2), Rational(1, 3), Rational(1, 4), Rational(1, 8)])
        case .fluidOunce, .pint, .quart, .gallon, .ounce, .pound:
            let steps = [Rational(1, 2), Rational(1, 4)]
            return (steps, steps)
        case .liter, .kilogram:
            return ([Rational(1, 20)], [Rational(1, 20)])
        case .pinch, .dash:
            return ([1], [1])
        case .piece, .gram, .milliliter, .toTaste:
            return ([], [])
        }
    }

    /// Steps for pieces and unitless amounts: quarters and thirds below one (¼ onion), halves
    /// below ten (2½ eggs), whole numbers from ten up (38 shrimp).
    static func countSteps(for magnitude: Rational) -> (nice: [Rational], fine: [Rational]) {
        if magnitude < 1 { return ([Rational(1, 2)], [Rational(1, 2), Rational(1, 3), Rational(1, 4)]) }
        if magnitude < 10 { return ([Rational(1, 2)], [Rational(1, 2)]) }
        return ([1], [1])
    }

    /// Whole-number step for grams and millilitres: finer for small amounts.
    static func metricWholeStep(for magnitude: Rational) -> Rational {
        if magnitude < 30 { return 1 }
        if magnitude < 300 { return 5 }
        return 10
    }

    /// The grid a gram or millilitre amount may already sit on: whole numbers below 30, then
    /// fives. 375 g stays 375 g even though a fresh amount of that size rounds to tens.
    static func metricGridStep(for magnitude: Rational) -> Rational {
        magnitude < 30 ? 1 : 5
    }

    /// The steps `value` in `unit` is rounded with, nice first then fine.
    static func steps(for value: Rational, unit: CookingUnit?) -> (nice: [Rational], fine: [Rational]) {
        switch unit {
        case .gram?, .milliliter?:
            return ([metricWholeStep(for: value.magnitude)], [metricGridStep(for: value.magnitude)])
        case .piece?, nil:
            return countSteps(for: value.magnitude)
        default:
            return fractionSteps(for: unit)
        }
    }

    /// The multiple of one of `steps` nearest to `value`, ties to the earlier step; nil when
    /// `steps` is empty.
    static func nearest(_ value: Rational, among steps: [Rational]) -> Rational? {
        var best: Rational?
        var bestDistance: Rational = .zero
        for step in steps {
            let candidate = value.rounded(toNearestMultipleOf: step)
            let distance = (candidate - value).magnitude
            if best == nil || distance < bestDistance {
                best = candidate
                bestDistance = distance
            }
        }
        return best
    }

    /// Whether a positive `magnitude` is exactly on, or within ``tolerance`` of, the grid of `steps`.
    static func isClose(_ magnitude: Rational, toGridOf steps: [Rational]) -> Bool {
        guard magnitude > .zero, let candidate = nearest(magnitude, among: steps), !candidate.isZero else { return false }
        return (candidate - magnitude).magnitude <= magnitude * tolerance
    }

    static func round(_ value: Rational, unit: CookingUnit?) -> Rational {
        if value.isZero { return value }
        let (nice, fine) = steps(for: value, unit: unit)
        guard let finest = fine.last else { return value }

        // A scale reads what it reads: 375 g stays 375 g although fresh amounts that size round to tens.
        if unit == .gram || unit == .milliliter, fine.contains(where: { value.isMultiple(of: $0) }) { return value }

        // A mark on the measuring set that is close enough wins over a finer, closer fraction
        // (6⅔ tbsp reads as 6½ tbsp); anything already on a nice mark is unchanged.
        if let coarse = nearest(value, among: nice), !coarse.isZero,
           (coarse - value).magnitude <= value.magnitude * tolerance {
            return coarse
        }

        // Otherwise a fine fraction, exactly when the value is already on one (2¼ tbsp stays).
        guard var result = nearest(value, among: fine) else { return value }
        // A nonzero amount never disappears: use the smallest measurable step instead.
        if result.isZero {
            result = value.isNegative ? -finest : finest
        }
        // A fine fraction that is itself within tolerance of a nice mark becomes that mark
        // (2⅞ tbsp reads as 3 tbsp), which also keeps rounding idempotent.
        if let coarse = nearest(result, among: nice), !coarse.isZero,
           (coarse - result).magnitude <= result.magnitude * tolerance {
            return coarse
        }
        return result
    }
}

extension Quantity {
    /// The quantity snapped to a fraction a cook can measure, chosen by unit.
    ///
    /// Policy:
    /// - **Teaspoons** round to halves and quarters, falling back to thirds and eighths.
    /// - **Tablespoons** round to halves, falling back to thirds (⅓ tbsp is 1 tsp), quarters and eighths.
    /// - **Cups** round to halves, thirds and quarters (the measuring-cup set), falling back to
    ///   eighths (¾ cup × 1.5 is 1⅛ cups, measured as 1 cup and 2 tbsp).
    /// - **Fluid ounces, pints, quarts, gallons, ounces and pounds** round to the nearest half or quarter.
    /// - **Grams and millilitres** round to the nearest whole number below 30, the nearest 5
    ///   below 300, and the nearest 10 from 300 up. An amount already on a 5 g grid stays as it is
    ///   (250 g × 1.5 is 375 g).
    /// - **Litres and kilograms** round to the nearest 0.05.
    /// - **Pieces** and quantities with no unit round to the nearest half, with quarters and
    ///   thirds below one (¼ onion) and whole numbers from ten up (38 shrimp).
    /// - **Pinches and dashes** round to whole numbers, at least one.
    /// - **To taste** is returned unchanged.
    ///
    /// The nearest mark on the measuring set is used when it is within 5 percent (6⅔ tbsp reads
    /// as 6½ tbsp), and only then the nearest fine fraction (⅓ tsp for 1 tsp ÷ 3, and "2¼ tbsp"
    /// survives as written); a fine fraction that lands within 5 percent of a mark becomes the
    /// mark (2⅞ tbsp reads as 3 tbsp). Rounding is idempotent: a value on the grid stays. A gram
    /// or millilitre amount already on the 5 g grid is never touched (375 g stays 375 g). When
    /// two fractions are equally close the coarser one wins, and exact
    /// midpoints within one fraction family round away from zero. A nonzero amount never rounds to
    /// zero: anything smaller than the finest step becomes that step (⅛ tsp, ⅛ cup, 1 g, ¼ piece).
    ///
    /// Call this after ``scaled(by:)`` and ``displayed(in:)`` so the unit is already the one the
    /// cook will see; `displayed(in:)` turns ⅛ cup into 2 tbsp before this is reached.
    public func friendlyRounded() -> Quantity {
        Quantity(FriendlyRounding.round(value, unit: unit), unit)
    }
}
