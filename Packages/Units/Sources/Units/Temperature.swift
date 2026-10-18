import Foundation

/// The scales a recipe writes oven and probe temperatures in.
public enum TemperatureScale: String, Hashable, Sendable, Codable, CaseIterable {
    case fahrenheit
    case celsius
    /// The British gas-oven dial: marks ¼, ½ and 1 through 10.
    case gasMark
}

/// A temperature as a recipe states it: exact degrees (or a gas mark), the scale, and whether
/// the value is for a fan (convection) oven, as in "240C/fan 220C/gas 9".
///
/// Conversion is exact between Fahrenheit and Celsius; gas marks go through the standard
/// table, see ``converted(to:)``. The `fan` flag is carried through unchanged: it describes
/// which oven the number is for, not a different scale.
public struct Temperature: Hashable, Sendable, Codable, CustomStringConvertible {
    public var degrees: Rational
    public var scale: TemperatureScale
    public var fan: Bool

    public init(_ degrees: Rational, _ scale: TemperatureScale, fan: Bool = false) {
        self.degrees = degrees
        self.scale = scale
        self.fan = fan
    }

    public var description: String { formatted() }

    /// The same temperature in `scale`.
    ///
    /// - Fahrenheit and Celsius convert exactly: 350°F is 176⅔°C, not 176.666.
    /// - Converting *to* a gas mark picks the mark whose table value, in the source scale, is
    ///   nearest (ties go to the hotter mark). Values beyond the table clamp to ¼ or 10.
    /// - Converting *from* a gas mark uses the table value for that mark (snapping an off-table
    ///   mark such as 5½ to the nearest listed one first), so gas 4 is 350°F and 180°C even though
    ///   those two are not exact conversions of each other.
    /// - A gas mark converted to a gas mark is returned as written.
    public func converted(to target: TemperatureScale) -> Temperature {
        guard scale != target else { return self }
        let value: Rational
        switch (scale, target) {
        case (.fahrenheit, .celsius):
            value = (degrees - 32) * Rational(5, 9)
        case (.celsius, .fahrenheit):
            value = degrees * Rational(9, 5) + 32
        case (.gasMark, .fahrenheit):
            value = GasMarkTable.nearestEntry(mark: degrees).fahrenheit
        case (.gasMark, .celsius):
            value = GasMarkTable.nearestEntry(mark: degrees).celsius
        case (.fahrenheit, .gasMark):
            value = GasMarkTable.nearestEntry(fahrenheit: degrees).mark
        case (.celsius, .gasMark):
            value = GasMarkTable.nearestEntry(celsius: degrees).mark
        case (.fahrenheit, .fahrenheit), (.celsius, .celsius), (.gasMark, .gasMark):
            value = degrees
        }
        return Temperature(value, target, fan: fan)
    }
}

/// The conventional gas mark table used by British recipes and conversion charts.
///
/// The Fahrenheit and Celsius columns are the chart values, not exact conversions of each other
/// (gas 4 is listed as 350°F and 180°C; 180°C is really 356°F). That is deliberate: a recipe that
/// says "180°C/gas 4" means 350°F to an American reader.
enum GasMarkTable {
    struct Entry: Hashable, Sendable {
        let mark: Rational
        let fahrenheit: Rational
        let celsius: Rational
    }

    /// Coldest first.
    static let entries: [Entry] = [
        Entry(mark: Rational(1, 4), fahrenheit: 225, celsius: 110),
        Entry(mark: Rational(1, 2), fahrenheit: 250, celsius: 120),
        Entry(mark: 1, fahrenheit: 275, celsius: 140),
        Entry(mark: 2, fahrenheit: 300, celsius: 150),
        Entry(mark: 3, fahrenheit: 325, celsius: 170),
        Entry(mark: 4, fahrenheit: 350, celsius: 180),
        Entry(mark: 5, fahrenheit: 375, celsius: 190),
        Entry(mark: 6, fahrenheit: 400, celsius: 200),
        Entry(mark: 7, fahrenheit: 425, celsius: 220),
        Entry(mark: 8, fahrenheit: 450, celsius: 230),
        Entry(mark: 9, fahrenheit: 475, celsius: 240),
        Entry(mark: 10, fahrenheit: 500, celsius: 260),
    ]

    static func nearestEntry(mark: Rational) -> Entry { nearest(mark, by: \.mark) }
    static func nearestEntry(fahrenheit: Rational) -> Entry { nearest(fahrenheit, by: \.fahrenheit) }
    static func nearestEntry(celsius: Rational) -> Entry { nearest(celsius, by: \.celsius) }

    /// The entry whose `column` is nearest to `value`; an exact midpoint goes to the hotter entry.
    private static func nearest(_ value: Rational, by column: KeyPath<Entry, Rational>) -> Entry {
        var best = entries[0]
        var bestDistance = (best[keyPath: column] - value).magnitude
        for entry in entries.dropFirst() {
            let distance = (entry[keyPath: column] - value).magnitude
            if distance <= bestDistance {
                best = entry
                bestDistance = distance
            }
        }
        return best
    }
}
