import Foundation

/// How unit names appear in formatted quantities.
public enum UnitNameStyle: String, Hashable, Sendable, Codable, CaseIterable {
    /// "tsp", "tbsp", "cup", "fl oz", "mL", "g", "lb". Cups, pinches and dashes have no
    /// abbreviation and pluralize; pieces are omitted so "2 eggs" reads as "2".
    case abbreviated
    /// "teaspoon", "tablespoons", "fluid ounces", "milliliters", "pieces".
    case full
}

extension CookingUnit {
    /// Units whose values read as decimals ("1.5 L", "350 g") rather than fractions.
    public var prefersDecimals: Bool {
        switch self {
        case .milliliter, .liter, .gram, .kilogram: true
        default: false
        }
    }

    /// The unit's name for display. Abbreviated US and metric units are invariant ("2 tbsp");
    /// cups, pinches, dashes and full names take an "s" when `plural` is true.
    public func name(style: UnitNameStyle, plural: Bool) -> String {
        switch style {
        case .abbreviated:
            return switch self {
            case .teaspoon: "tsp"
            case .tablespoon: "tbsp"
            case .fluidOunce: "fl oz"
            case .cup: plural ? "cups" : "cup"
            case .pint: "pt"
            case .quart: "qt"
            case .gallon: "gal"
            case .milliliter: "mL"
            case .liter: "L"
            case .ounce: "oz"
            case .pound: "lb"
            case .gram: "g"
            case .kilogram: "kg"
            case .piece: ""
            case .pinch: plural ? "pinches" : "pinch"
            case .dash: plural ? "dashes" : "dash"
            case .toTaste: "to taste"
            }
        case .full:
            let singular: String
            switch self {
            case .teaspoon: singular = "teaspoon"
            case .tablespoon: singular = "tablespoon"
            case .fluidOunce: singular = "fluid ounce"
            case .cup: singular = "cup"
            case .pint: singular = "pint"
            case .quart: singular = "quart"
            case .gallon: singular = "gallon"
            case .milliliter: singular = "milliliter"
            case .liter: singular = "liter"
            case .ounce: singular = "ounce"
            case .pound: singular = "pound"
            case .gram: singular = "gram"
            case .kilogram: singular = "kilogram"
            case .piece: singular = "piece"
            case .pinch: singular = "pinch"
            case .dash: singular = "dash"
            case .toTaste: return "to taste"
            }
            guard plural else { return singular }
            switch self {
            case .pinch, .dash: return singular + "es"
            default: return singular + "s"
            }
        }
    }
}

extension Rational {
    private static let vulgarFractions: [Rational: String] = [
        Rational(1, 2): "½",
        Rational(1, 3): "⅓", Rational(2, 3): "⅔",
        Rational(1, 4): "¼", Rational(3, 4): "¾",
        Rational(1, 5): "⅕", Rational(2, 5): "⅖", Rational(3, 5): "⅗", Rational(4, 5): "⅘",
        Rational(1, 6): "⅙", Rational(5, 6): "⅚",
        Rational(1, 7): "⅐",
        Rational(1, 8): "⅛", Rational(3, 8): "⅜", Rational(5, 8): "⅝", Rational(7, 8): "⅞",
        Rational(1, 9): "⅑",
        Rational(1, 10): "⅒",
    ]

    /// A mixed number using Unicode vulgar fractions where one exists: "1½", "⅓", "2 7/16", "3".
    public var mixedNumberString: String {
        let sign = isNegative ? "-" : ""
        let (whole, fraction) = magnitude.mixed
        if fraction.isZero { return sign + "\(whole)" }
        if let glyph = Rational.vulgarFractions[fraction] {
            return sign + (whole == 0 ? glyph : "\(whole)\(glyph)")
        }
        let plain = "\(fraction.numerator)/\(fraction.denominator)"
        return sign + (whole == 0 ? plain : "\(whole) \(plain)")
    }

    /// A decimal with at most `maximumFractionDigits` digits, trailing zeros removed: "1.5", "350", "0.25".
    /// Always uses "." as the separator; the digits come from integer arithmetic, not `Double`.
    public func decimalString(maximumFractionDigits: Int = 2) -> String {
        precondition(maximumFractionDigits >= 0)
        var scale = 1
        for _ in 0..<maximumFractionDigits { scale *= 10 }
        let scaled = (Rational(scale) * magnitude).roundedToInt
        let whole = scaled / scale
        var fractionDigits = String(scaled % scale)
        if maximumFractionDigits > 0 {
            fractionDigits = String(repeating: "0", count: maximumFractionDigits - fractionDigits.count) + fractionDigits
            while fractionDigits.hasSuffix("0") { fractionDigits.removeLast() }
        } else {
            fractionDigits = ""
        }
        let sign = isNegative && scaled != 0 ? "-" : ""
        return fractionDigits.isEmpty ? "\(sign)\(whole)" : "\(sign)\(whole).\(fractionDigits)"
    }
}

extension Quantity {
    /// The quantity as the cook reads it: "1½ cups", "2 tbsp", "350 g", "⅓ cup", "to taste".
    ///
    /// Metric units show decimals ("1.5 L"); everything else shows a mixed number with a Unicode
    /// vulgar fraction where one exists and a plain "7/16" otherwise. Unit names are singular for
    /// amounts above 0 up to and including 1 and plural otherwise ("½ cup", "1 cup", "1½ cups",
    /// "0 cups"). A quantity
    /// with no unit is just the number; `toTaste` is the words alone.
    public func formatted(style: UnitNameStyle = .abbreviated) -> String {
        guard let unit else { return value.mixedNumberString }
        if unit == .toTaste { return unit.name(style: style, plural: false) }
        let number = unit.prefersDecimals ? value.decimalString() : value.mixedNumberString
        let plural = value.isZero || value.magnitude > 1
        let name = unit.name(style: style, plural: plural)
        return name.isEmpty ? number : "\(number) \(name)"
    }
}
