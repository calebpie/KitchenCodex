import Foundation
import Units

/// One ingredient line split into amount, unit, item and preparation.
public struct ParsedIngredient: Sendable, Equatable {
    /// `nil` when the line names no amount ("salt to taste", "freshly ground pepper").
    public var quantity: Rational?
    /// `nil` for counted items ("3 large eggs"); `.toTaste` when the line says so and gives no amount.
    public var unit: CookingUnit?
    public var item: String
    /// Whatever follows the first comma: "finely chopped", "divided", "at room temperature".
    public var preparation: String?
    public var isOptional: Bool
    /// The line as typed, trimmed. Kept so nothing the parser misreads is lost.
    public var rawText: String

    public init(
        quantity: Rational? = nil,
        unit: CookingUnit? = nil,
        item: String,
        preparation: String? = nil,
        isOptional: Bool = false,
        rawText: String = ""
    ) {
        self.quantity = quantity
        self.unit = unit
        self.item = item
        self.preparation = preparation
        self.isOptional = isOptional
        self.rawText = rawText
    }
}

/// The deterministic ingredient-line parser used by manual entry and, later, by every import path
/// before a model is asked (04 §1 "deterministic first").
///
/// Reads a leading amount (whole numbers, fractions, mixed numbers, decimals, Unicode fractions,
/// "1-1/2", ranges such as "2-3" or "2 to 3", which keep the low end), an optional unit from
/// `CookingUnit`, then the item, with anything after the first comma as preparation.
/// "to taste" and "(optional)" are recognised anywhere in the line.
public enum IngredientParser {
    /// Parses each non-blank line of `text`.
    public static func parseLines(_ text: String) -> [ParsedIngredient] {
        text.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map(parse)
    }

    public static func parse(_ line: String) -> ParsedIngredient {
        let rawText = line.trimmingCharacters(in: .whitespacesAndNewlines)
        var text = normalize(stripBullet(rawText))

        var isOptional = false
        if let range = text.range(of: #"\(\s*optional\s*\)|,\s*optional\s*$|^optional:?\s+"#, options: [.regularExpression, .caseInsensitive]) {
            isOptional = true
            text.removeSubrange(range)
        }

        var saysToTaste = false
        if let range = text.range(of: #",?\s*\(?\s*(or\s+)?\bto taste\b\s*\)?"#, options: [.regularExpression, .caseInsensitive]) {
            saysToTaste = true
            text.removeSubrange(range)
        }

        var tokens = Tokens(text)
        var quantity = readQuantity(&tokens)
        var unit: CookingUnit?
        if quantity != nil {
            unit = readUnit(&tokens)
        } else if let informal = readUnit(&tokens), informal == .pinch || informal == .dash {
            // "Pinch of cayenne": an informal unit with no number means one of it.
            quantity = .one
            unit = informal
        } else {
            tokens.reset()
        }
        if unit != nil {
            dropEquivalentMeasure(&tokens)
        }
        tokens.skip(word: "of")

        var (item, preparation) = splitPreparation(tokens.remainder)
        if saysToTaste {
            if quantity == nil {
                unit = .toTaste
            } else {
                preparation = [preparation, "to taste"].compactMap(\.self).joined(separator: ", ")
            }
        }
        if item.isEmpty, let prep = preparation {
            item = prep
            preparation = nil
        }

        return ParsedIngredient(
            quantity: quantity,
            unit: unit,
            item: item,
            preparation: preparation,
            isOptional: isOptional,
            rawText: rawText
        )
    }

    // MARK: - Normalising the line

    private static let vulgarFractions: [Character: String] = [
        "½": "1/2", "⅓": "1/3", "⅔": "2/3", "¼": "1/4", "¾": "3/4",
        "⅕": "1/5", "⅖": "2/5", "⅗": "3/5", "⅘": "4/5", "⅙": "1/6", "⅚": "5/6",
        "⅛": "1/8", "⅜": "3/8", "⅝": "5/8", "⅞": "7/8",
    ]

    private static func stripBullet(_ text: String) -> String {
        guard let range = text.range(of: #"^([-•*▢◻︎□]|\d+[.)])\s+"#, options: .regularExpression) else { return text }
        // "1. 2 cups flour" is a numbered list; "1 cup flour" is not, because it has no "." or ")".
        return String(text[range.upperBound...])
    }

    private static func normalize(_ text: String) -> String {
        var result = ""
        for character in text {
            if let fraction = vulgarFractions[character] {
                result += " \(fraction) "
            } else if character == "\u{2044}" { // fraction slash
                result.append("/")
            } else if character == "–" || character == "—" {
                result.append("-")
            } else {
                result.append(character)
            }
        }
        // "500g" → "500 g", "2tbsp" → "2 tbsp".
        result = result.replacingOccurrences(of: #"(\d)([A-Za-z])"#, with: "$1 $2", options: .regularExpression)
        return result
    }

    // MARK: - Amount

    private static func readQuantity(_ tokens: inout Tokens) -> Rational? {
        guard let first = tokens.peek() else { return nil }

        // "a pinch", "an 8 oz" — only when a unit follows, so "an onion" stays an item.
        if ["a", "an"].contains(first.lowercased()), let next = tokens.peek(1), unit(for: next) != nil {
            tokens.advance()
            return .one
        }

        // "2-3" or "1-1/2" in one token.
        let hyphenParts = first.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        if hyphenParts.count == 2, let low = number(hyphenParts[0]), let high = number(hyphenParts[1]) {
            tokens.advance()
            if low.denominator == 1, high < .one, high > .zero { return low + high }
            return low
        }

        guard var value = number(first) else { return nil }
        tokens.advance()

        // Mixed number: "1 1/2".
        if value.denominator == 1, let next = tokens.peek(), next.contains("/"), let fraction = number(next), fraction < .one {
            value = value + fraction
            tokens.advance()
        }

        // Range: "2 to 3", "2 - 3", "2 or 3". Keep the low end; the raw text keeps the rest.
        if let joiner = tokens.peek()?.lowercased(), ["-", "to", "or"].contains(joiner),
           let upper = tokens.peek(1), number(upper) != nil {
            tokens.advance(2)
            if let next = tokens.peek(), next.contains("/"), let fraction = number(next), fraction < .one {
                tokens.advance()
            }
        }
        return value
    }

    private static func number(_ token: String) -> Rational? {
        let token = token.trimmingCharacters(in: CharacterSet(charactersIn: ","))
        if let whole = Int(token), whole >= 0 { return Rational(whole) }

        let parts = token.split(separator: "/", omittingEmptySubsequences: false)
        if parts.count == 2, let numerator = Int(parts[0]), let denominator = Int(parts[1]),
           numerator >= 0, denominator > 0 {
            return Rational(numerator, denominator)
        }

        // Decimals: "1.5", ".25". Capped at four places so the fraction stays small.
        let decimal = token.split(separator: ".", omittingEmptySubsequences: false)
        if decimal.count == 2, decimal[1].count <= 4, !decimal[1].isEmpty,
           decimal[0].allSatisfy(\.isNumber), decimal[1].allSatisfy(\.isNumber),
           let whole = Int(decimal[0].isEmpty ? "0" : decimal[0]), let fraction = Int(decimal[1]) {
            var scale = 1
            for _ in 0..<decimal[1].count { scale *= 10 }
            return Rational(whole * scale + fraction, scale)
        }
        return nil
    }

    // MARK: - Unit

    private static let unitWords: [String: CookingUnit] = {
        let table: [CookingUnit: [String]] = [
            .teaspoon: ["tsp", "tsps", "tspn", "teaspoon", "teaspoons"],
            .tablespoon: ["tbsp", "tbsps", "tbs", "tbl", "tbls", "tablespoon", "tablespoons"],
            .cup: ["c", "cup", "cups"],
            .pint: ["pt", "pts", "pint", "pints"],
            .quart: ["qt", "qts", "quart", "quarts"],
            .gallon: ["gal", "gals", "gallon", "gallons"],
            .milliliter: ["ml", "mls", "milliliter", "milliliters", "millilitre", "millilitres"],
            .liter: ["l", "liter", "liters", "litre", "litres"],
            .ounce: ["oz", "ounce", "ounces"],
            .pound: ["lb", "lbs", "pound", "pounds"],
            .gram: ["g", "gr", "gram", "grams", "gramme", "grammes"],
            .kilogram: ["kg", "kgs", "kilo", "kilos", "kilogram", "kilograms"],
            .piece: ["pc", "pcs", "piece", "pieces"],
            .pinch: ["pinch", "pinches"],
            .dash: ["dash", "dashes"],
        ]
        var words: [String: CookingUnit] = [:]
        for (unit, spellings) in table {
            for spelling in spellings { words[spelling] = unit }
        }
        return words
    }()

    private static func unit(for token: String) -> CookingUnit? {
        let bare = token.trimmingCharacters(in: CharacterSet(charactersIn: ".,"))
        // The old cookbook shorthand: capital T is a tablespoon, small t a teaspoon.
        if bare == "T" { return .tablespoon }
        if bare == "t" { return .teaspoon }
        return unitWords[bare.lowercased()]
    }

    private static func readUnit(_ tokens: inout Tokens) -> CookingUnit? {
        guard let first = tokens.peek() else { return nil }
        let bare = first.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if ["fl", "fluid"].contains(bare), let next = tokens.peek(1),
           ["oz", "ounce", "ounces"].contains(next.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".,"))) {
            tokens.advance(2)
            return .fluidOunce
        }
        guard let unit = unit(for: first) else { return nil }
        tokens.advance()
        return unit
    }

    /// "1 cup (240 ml) milk": the parenthetical repeats the amount in other units, which scaling and
    /// the unit toggle regenerate, so it is dropped. Other parentheticals ("(14-ounce) can") stay.
    private static func dropEquivalentMeasure(_ tokens: inout Tokens) {
        let rest = tokens.remainder
        guard let range = rest.range(of: #"^\(\s*[\d./\s-]+\s*[A-Za-z. ]+\)\s*"#, options: .regularExpression) else { return }
        let inner = rest[range].trimmingCharacters(in: CharacterSet(charactersIn: "() ").union(.whitespaces))
        var innerTokens = Tokens(inner)
        guard readQuantity(&innerTokens) != nil, readUnit(&innerTokens) != nil, innerTokens.remainder.isEmpty else { return }
        tokens = Tokens(String(rest[range.upperBound...]))
    }

    // MARK: - Item and preparation

    private static func splitPreparation(_ text: String) -> (item: String, preparation: String?) {
        let cleaned = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ",;")))
        guard let comma = cleaned.firstIndex(of: ",") else { return (cleaned, nil) }
        let item = cleaned[..<comma].trimmingCharacters(in: .whitespaces)
        let preparation = cleaned[cleaned.index(after: comma)...].trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ",")))
        return (item, preparation.isEmpty ? nil : preparation)
    }
}

/// A whitespace-split line with a read cursor.
private struct Tokens {
    private let words: [String]
    private var index = 0

    init(_ text: String) {
        words = text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    func peek(_ offset: Int = 0) -> String? {
        words.indices.contains(index + offset) ? words[index + offset] : nil
    }

    mutating func advance(_ count: Int = 1) {
        index = min(index + count, words.count)
    }

    mutating func reset() {
        index = 0
    }

    mutating func skip(word: String) {
        if peek()?.lowercased() == word { advance() }
    }

    var remainder: String {
        words[index...].joined(separator: " ")
    }
}
