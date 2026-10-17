import Foundation

/// Measurement systems a cook can ask the app to display in.
public enum MeasurementSystem: String, Sendable, Codable, CaseIterable {
    case us
    case metric
}

/// Cooking units the parser recognizes. Phase 1 adds conversion tables and densities.
public enum CookingUnit: String, Sendable, Codable, CaseIterable {
    // Volume
    case teaspoon, tablespoon, fluidOunce, cup, pint, quart, gallon, milliliter, liter
    // Mass
    case ounce, pound, gram, kilogram
    // Count and informal
    case piece, pinch, dash, toTaste

    public var isVolume: Bool {
        switch self {
        case .teaspoon, .tablespoon, .fluidOunce, .cup, .pint, .quart, .gallon, .milliliter, .liter: true
        default: false
        }
    }

    public var isMass: Bool {
        switch self {
        case .ounce, .pound, .gram, .kilogram: true
        default: false
        }
    }
}

/// An amount of something: an exact rational value and an optional unit.
public struct Quantity: Hashable, Sendable, Codable {
    public var value: Rational
    public var unit: CookingUnit?

    public init(_ value: Rational, _ unit: CookingUnit? = nil) {
        self.value = value
        self.unit = unit
    }

    /// Scales the quantity exactly. Friendly rounding to measurable fractions is a Phase 1 feature.
    public func scaled(by factor: Rational) -> Quantity {
        Quantity(value * factor, unit)
    }
}
