import Foundation

/// The units recipes write lengths of time in.
public enum DurationUnit: String, Hashable, Sendable, Codable, CaseIterable, Comparable {
    case seconds
    case minutes
    case hours
    case days

    /// How many seconds one of the unit is.
    public var seconds: Rational {
        switch self {
        case .seconds: 1
        case .minutes: 60
        case .hours: 3600
        case .days: 86_400
        }
    }

    public static func < (lhs: DurationUnit, rhs: DurationUnit) -> Bool {
        lhs.seconds < rhs.seconds
    }
}

/// A length of time as a recipe states it, exact to the second: "12 minutes", "1½ hours",
/// "90 seconds". Held as seconds in a ``Rational`` so that ⅓ hour is 1200 seconds, not 1199.99,
/// and a timer started from it runs for exactly what was written.
///
/// Named a *cooking* duration so that a file importing both Units and the standard library, whose
/// own `Duration` measures time in attoseconds, sees no clash between the two.
public struct CookingDuration: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    public var seconds: Rational

    public init(seconds: Rational) {
        self.seconds = seconds
    }

    public init(minutes: Rational) {
        self.init(seconds: minutes * DurationUnit.minutes.seconds)
    }

    public init(hours: Rational) {
        self.init(seconds: hours * DurationUnit.hours.seconds)
    }

    /// `value` of `unit`: `CookingDuration(90, .minutes)` is 5400 seconds.
    public init(_ value: Rational, _ unit: DurationUnit) {
        self.init(seconds: value * unit.seconds)
    }

    /// The whole duration in minutes: 90 seconds is 1½ minutes.
    public var minutes: Rational { seconds / DurationUnit.minutes.seconds }

    /// The whole duration in hours: 90 minutes is 1½ hours.
    public var hours: Rational { seconds / DurationUnit.hours.seconds }

    /// Whole hours, whole minutes and the seconds left over, as a timer shows them: 5400 seconds
    /// is (1, 30, 0) and 90 seconds is (0, 1, 30).
    public var components: (hours: Int, minutes: Int, seconds: Rational) {
        let hours = (seconds / DurationUnit.hours.seconds).floor
        var rest = seconds - Rational(hours) * DurationUnit.hours.seconds
        let minutes = (rest / DurationUnit.minutes.seconds).floor
        rest -= Rational(minutes) * DurationUnit.minutes.seconds
        return (hours, minutes, rest)
    }

    /// What "overnight" stands for when a recipe says to chill or soak overnight: 12 hours, an
    /// evening to the next morning. See ``DurationParser``.
    public static let overnight = CookingDuration(hours: 12)

    public var description: String { formatted() }

    public static func < (lhs: CookingDuration, rhs: CookingDuration) -> Bool {
        lhs.seconds < rhs.seconds
    }

    public static func + (lhs: CookingDuration, rhs: CookingDuration) -> CookingDuration {
        CookingDuration(seconds: lhs.seconds + rhs.seconds)
    }
}
