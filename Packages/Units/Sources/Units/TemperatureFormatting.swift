import Foundation

/// How temperatures read when formatted.
public enum TemperatureNameStyle: String, Hashable, Sendable, Codable, CaseIterable {
    /// "350°F", "180°C fan", "gas 6".
    case abbreviated
    /// "350 degrees Fahrenheit", "180 degrees Celsius (fan)", "gas mark 6".
    case full
}

extension Temperature {
    /// The step the display rounds converted degrees to: 176⅔°C reads as 175°C.
    public static let displayRoundingStep: Rational = 5

    /// The temperature as the cook will see it in `scale`.
    ///
    /// A value already in `scale` is returned exactly as written, because the recipe's own
    /// number is the right one to show. A converted value is rounded to the nearest 5 degrees
    /// (``displayRoundingStep``) for Fahrenheit and Celsius; gas marks are already whole marks.
    public func displayed(in scale: TemperatureScale) -> Temperature {
        guard self.scale != scale else { return self }
        var result = converted(to: scale)
        if scale != .gasMark {
            result.degrees = result.degrees.rounded(toNearestMultipleOf: Temperature.displayRoundingStep)
        }
        return result
    }

    /// The temperature in its own scale, no conversion or rounding: "350°F", "176.7°C",
    /// "180°C fan", "gas 6", "gas mark ½".
    public func formatted(style: TemperatureNameStyle = .abbreviated) -> String {
        switch (scale, style) {
        case (.fahrenheit, .abbreviated):
            return "\(degreeString)°F" + (fan ? " fan" : "")
        case (.celsius, .abbreviated):
            return "\(degreeString)°C" + (fan ? " fan" : "")
        case (.fahrenheit, .full):
            return "\(degreeString) degrees Fahrenheit" + (fan ? " (fan)" : "")
        case (.celsius, .full):
            return "\(degreeString) degrees Celsius" + (fan ? " (fan)" : "")
        case (.gasMark, .abbreviated):
            return "gas \(degrees.mixedNumberString)" + (fan ? " fan" : "")
        case (.gasMark, .full):
            return "gas mark \(degrees.mixedNumberString)" + (fan ? " (fan)" : "")
        }
    }

    /// The temperature converted to the cook's preferred `scale` and rounded for display;
    /// see ``displayed(in:)``. 180°C in Fahrenheit is "355°F"; gas 4 in Fahrenheit is "350°F".
    public func formatted(in scale: TemperatureScale, style: TemperatureNameStyle = .abbreviated) -> String {
        displayed(in: scale).formatted(style: style)
    }

    /// Whole degrees as an integer, anything else with one decimal: "350", "176.7".
    var degreeString: String {
        degrees.isWhole ? "\(degrees.numerator)" : degrees.decimalString(maximumFractionDigits: 1)
    }
}
