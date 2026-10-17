import Foundation

/// An exact fraction used for ingredient quantities, so that scaling "1/3 cup" by 1.5
/// yields "1/2 cup" rather than 0.49999.
///
/// Always stored in lowest terms with a positive denominator.
public struct Rational: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    public let numerator: Int
    public let denominator: Int

    public init(_ numerator: Int, _ denominator: Int = 1) {
        precondition(denominator != 0, "Rational denominator must not be zero")
        let sign = denominator < 0 ? -1 : 1
        let g = Rational.gcd(abs(numerator), abs(denominator))
        self.numerator = sign * numerator / g
        self.denominator = abs(denominator) / g
    }

    public static let zero = Rational(0)
    public static let one = Rational(1)

    public var doubleValue: Double { Double(numerator) / Double(denominator) }

    /// Whole and fractional parts, e.g. 7/4 → (1, 3/4).
    public var mixed: (whole: Int, fraction: Rational) {
        let whole = numerator / denominator
        return (whole, Rational(numerator - whole * denominator, denominator))
    }

    public var description: String {
        let (whole, fraction) = mixed
        switch (whole, fraction.numerator) {
        case (_, 0): return "\(whole)"
        case (0, _): return "\(fraction.numerator)/\(fraction.denominator)"
        default: return "\(whole) \(abs(fraction.numerator))/\(fraction.denominator)"
        }
    }

    public static func + (lhs: Rational, rhs: Rational) -> Rational {
        Rational(lhs.numerator * rhs.denominator + rhs.numerator * lhs.denominator,
                 lhs.denominator * rhs.denominator)
    }

    public static func * (lhs: Rational, rhs: Rational) -> Rational {
        Rational(lhs.numerator * rhs.numerator, lhs.denominator * rhs.denominator)
    }

    public static func < (lhs: Rational, rhs: Rational) -> Bool {
        lhs.numerator * rhs.denominator < rhs.numerator * lhs.denominator
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        var (a, b) = (a, b)
        while b != 0 { (a, b) = (b, a % b) }
        return a == 0 ? 1 : a
    }
}
