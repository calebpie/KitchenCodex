import Foundation

/// Rounding to the fractions a cook can actually measure.
enum FriendlyRounding {
    /// Fraction steps a value in `unit` snaps to, coarsest first. Ties between steps prefer the
    /// earlier (coarser) one. Empty means the value is left unchanged.
    static func fractionSteps(for unit: CookingUnit?) -> [Rational] {
        guard let unit else { return [Rational(1, 2)] }
        switch unit {
        case .teaspoon, .tablespoon:
            return [Rational(1, 2), Rational(1, 3), Rational(1, 4), Rational(1, 8)]
        case .cup:
            return [Rational(1, 2), Rational(1, 3), Rational(1, 4)]
        case .fluidOunce, .pint, .quart, .gallon, .ounce, .pound:
            return [Rational(1, 2), Rational(1, 4)]
        case .liter, .kilogram:
            return [Rational(1, 20)]
        case .piece:
            return [Rational(1, 2)]
        case .gram, .milliliter, .pinch, .dash, .toTaste:
            return []
        }
    }

    /// Whole-number step for grams and millilitres: finer for small amounts.
    static func metricWholeStep(for magnitude: Rational) -> Rational {
        if magnitude < 30 { return 1 }
        if magnitude < 300 { return 5 }
        return 10
    }

    static func round(_ value: Rational, unit: CookingUnit?) -> Rational {
        if value.isZero { return value }
        let steps: [Rational]
        switch unit {
        case .gram?, .milliliter?:
            steps = [metricWholeStep(for: value.magnitude)]
        case .pinch?, .dash?, .toTaste?:
            return value
        default:
            steps = fractionSteps(for: unit)
        }
        guard let finest = steps.last else { return value }

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
        guard var result = best else { return value }
        // A nonzero amount never disappears: use the smallest measurable step instead.
        if result.isZero {
            result = value.isNegative ? -finest : finest
        }
        return result
    }
}

extension Quantity {
    /// The quantity snapped to a fraction a cook can measure, chosen by unit.
    ///
    /// Policy:
    /// - **Teaspoons and tablespoons** round to the nearest half, third, quarter or eighth.
    /// - **Cups** round to the nearest half, third or quarter (the measuring-cup set).
    /// - **Fluid ounces, pints, quarts, gallons, ounces and pounds** round to the nearest half or quarter.
    /// - **Grams and millilitres** round to the nearest whole number below 30, the nearest 5
    ///   below 300, and the nearest 10 from 300 up.
    /// - **Litres and kilograms** round to the nearest 0.05.
    /// - **Pieces** and quantities with no unit round to the nearest half.
    /// - **Pinch, dash and to taste** are returned unchanged.
    ///
    /// When two fractions are equally close the coarser one wins (½ over ⅜, ⅓ over ⅜), and
    /// exact midpoints within one fraction family round away from zero. A nonzero amount never
    /// rounds to zero: anything smaller than the finest step becomes that step (⅛ tsp, ¼ cup,
    /// 1 g, ½ piece). Rounding is idempotent, so a value already on the grid is unchanged.
    ///
    /// Call this after ``scaled(by:)`` and ``displayed(in:)`` so the unit is already the one the
    /// cook will see; snapping 1/8 cup to ¼ cup is avoided because `displayed(in:)` would have
    /// chosen 2 tbsp first.
    public func friendlyRounded() -> Quantity {
        Quantity(FriendlyRounding.round(value, unit: unit), unit)
    }
}
