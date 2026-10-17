import Foundation

/// Maps the unit words found in recipes ("Tbsp", "tablespoons", "fl. oz.", "lbs") to `CookingUnit`.
///
/// Matching ignores case, surrounding whitespace, periods and repeated spaces, with one
/// exception: the single letters follow the cookbook convention that "T" is a tablespoon and
/// "t" is a teaspoon. Unknown strings give nil; the parser never guesses.
public struct UnitParser: Hashable, Sendable, Codable {
    public init() {}

    /// Spellings that depend on case. Checked before the case-insensitive table.
    static let caseSensitiveAliases: [String: CookingUnit] = [
        "T": .tablespoon,
        "t": .teaspoon,
    ]

    /// Lower-case spellings, periods removed and whitespace collapsed.
    static let aliases: [String: CookingUnit] = {
        let table: [(CookingUnit, [String])] = [
            (.teaspoon, ["tsp", "tsps", "tspn", "tspns", "teaspoon", "teaspoons", "teaspoonful", "teaspoonfuls"]),
            (.tablespoon, ["tbsp", "tbsps", "tbs", "tbl", "tbls", "tblsp", "tblsps", "tablespoon", "tablespoons", "tablespoonful", "tablespoonfuls"]),
            (.fluidOunce, ["fl oz", "floz", "fl ozs", "flozs", "fluid ounce", "fluid ounces", "fl ounce", "fl ounces"]),
            (.cup, ["c", "cup", "cups"]),
            (.pint, ["pt", "pts", "pint", "pints"]),
            (.quart, ["qt", "qts", "quart", "quarts"]),
            (.gallon, ["gal", "gals", "gallon", "gallons"]),
            (.milliliter, ["ml", "mls", "milliliter", "milliliters", "millilitre", "millilitres", "cc"]),
            (.liter, ["l", "lt", "ltr", "ltrs", "liter", "liters", "litre", "litres"]),
            (.ounce, ["oz", "ozs", "ounce", "ounces"]),
            (.pound, ["lb", "lbs", "pound", "pounds"]),
            (.gram, ["g", "gm", "gms", "gr", "grs", "gram", "grams", "gramme", "grammes"]),
            (.kilogram, ["kg", "kgs", "kilo", "kilos", "kilogram", "kilograms", "kilogramme", "kilogrammes"]),
            (.piece, ["piece", "pieces", "pc", "pcs", "ea", "each", "whole"]),
            (.pinch, ["pinch", "pinches"]),
            (.dash, ["dash", "dashes"]),
            (.toTaste, ["to taste", "totaste"]),
        ]
        var result: [String: CookingUnit] = [:]
        for (unit, spellings) in table {
            for spelling in spellings { result[spelling] = unit }
        }
        return result
    }()

    /// The unit named by `text`, or nil if it is not recognized.
    public func parse(_ text: String) -> CookingUnit? {
        UnitParser.parse(text)
    }

    /// The unit named by `text`, or nil if it is not recognized.
    public static func parse(_ text: String) -> CookingUnit? {
        let stripped = text.replacingOccurrences(of: ".", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let unit = caseSensitiveAliases[stripped] { return unit }
        return aliases[normalize(stripped)]
    }

    /// Lower-cases, strips periods and collapses whitespace runs to single spaces.
    static func normalize(_ text: String) -> String {
        let withoutPeriods = text.replacingOccurrences(of: ".", with: "")
        let words = withoutPeriods.lowercased()
            .split(whereSeparator: { $0.isWhitespace })
        return words.joined(separator: " ")
    }
}

extension CookingUnit {
    /// Parses a unit spelling such as "Tbsp" or "fluid ounces"; see ``UnitParser``.
    public init?(parsing text: String) {
        guard let unit = UnitParser.parse(text) else { return nil }
        self = unit
    }
}
