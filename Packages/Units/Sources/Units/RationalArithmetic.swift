import Foundation

/// Arithmetic that conversion and rounding need beyond what `Rational` itself provides.
///
/// Kept in its own file so that `Rational.swift` stays small and stable.
extension Rational: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self.init(value)
    }

    public var isZero: Bool { numerator == 0 }
    public var isNegative: Bool { numerator < 0 }
    public var isWhole: Bool { denominator == 1 }

    /// The absolute value.
    public var magnitude: Rational { Rational(abs(numerator), denominator) }

    /// `1 / self`. The value must not be zero.
    public var reciprocal: Rational {
        precondition(numerator != 0, "Cannot take the reciprocal of zero")
        return Rational(denominator, numerator)
    }

    /// The largest integer not greater than the value (floor division, correct for negatives).
    public var floor: Int {
        if numerator >= 0 { return numerator / denominator }
        return -((-numerator + denominator - 1) / denominator)
    }

    /// The nearest integer, with exact halves rounded away from zero.
    public var roundedToInt: Int {
        let m = (2 * abs(numerator) + denominator) / (2 * denominator)
        return numerator < 0 ? -m : m
    }

    /// The nearest multiple of `step`, with exact midpoints rounded away from zero.
    ///
    ///     Rational(7, 16).rounded(toNearestMultipleOf: Rational(1, 4)) == Rational(1, 2)
    public func rounded(toNearestMultipleOf step: Rational) -> Rational {
        precondition(step > .zero, "Rounding step must be positive")
        return Rational((self / step).roundedToInt) * step
    }

    /// Whether the value is an exact multiple of `step`.
    public func isMultiple(of step: Rational) -> Bool {
        (self / step).isWhole
    }

    public static prefix func - (value: Rational) -> Rational {
        Rational(-value.numerator, value.denominator)
    }

    public static func - (lhs: Rational, rhs: Rational) -> Rational {
        lhs + (-rhs)
    }

    public static func / (lhs: Rational, rhs: Rational) -> Rational {
        precondition(rhs.numerator != 0, "Division by zero")
        return lhs * rhs.reciprocal
    }

    public static func += (lhs: inout Rational, rhs: Rational) { lhs = lhs + rhs }
    public static func -= (lhs: inout Rational, rhs: Rational) { lhs = lhs - rhs }
    public static func *= (lhs: inout Rational, rhs: Rational) { lhs = lhs * rhs }
    public static func /= (lhs: inout Rational, rhs: Rational) { lhs = lhs / rhs }
}
