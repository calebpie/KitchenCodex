import Foundation
import Units

/// Produce a line comes from, as its note says: "about 3 oranges" is 3 and "oranges". Shopping
/// (Phase 4) buys the produce rather than the juice or zest (04 §5.1 Ingredient lines).
public struct ProduceEquivalent: Sendable, Equatable {
    /// How many, exactly as written ("1 1/2 pears" is 3/2); a range keeps its low end, as amounts do.
    public var count: Rational
    /// The produce as written: "oranges", "large lemons", "onion".
    public var item: String

    public init(count: Rational, item: String) {
        self.count = count
        self.item = item
    }
}

/// How a note stood in its line, which decides how it reads (04 §5.1 Ingredient lines): a closing
/// clause follows a comma, a parenthetical keeps its parentheses, so notes never nest.
public enum NoteForm: String, Sendable, Equatable, CaseIterable {
    /// "plus extra (for kneading)", "for frying, as needed": the closing clauses of the preparation.
    case clause
    /// "(about 3 oranges)": a trailing parenthetical of the item or the preparation.
    case parenthetical

    /// The note as it reads after the item and preparation: ", plus extra (for kneading)" or
    /// " (about 3 oranges)". A note whose own words hold parentheses reads after a comma whatever
    /// its form, so parentheses never nest; a note stored without a form reads as a parenthetical.
    public static func suffix(for note: String, form: NoteForm?) -> String {
        if form == .clause || note.contains("(") || note.contains(")") { return ", \(note)" }
        return " (\(note))"
    }
}

/// One ingredient line split into amount, unit, item, preparation and note.
public struct ParsedIngredient: Sendable, Equatable {
    /// `nil` when the line names no amount ("salt to taste", "freshly ground pepper").
    public var quantity: Rational?
    /// `nil` for counted items ("3 large eggs"); `.toTaste` when the line says so and gives no amount.
    public var unit: CookingUnit?
    public var item: String
    /// Whatever follows the first comma: "finely chopped", "divided", "at room temperature". Or
    /// the preparation a cookbook writes before it: "packed" in "1 cup packed, fresh spinach leaves".
    public var preparation: String?
    /// Trailing asides that are neither preparation nor a unit equivalent, without their
    /// parentheses: "about 3 oranges", "plus more for the pan", "ask your butcher to do this".
    /// Several are joined with "; ".
    public var note: String?
    /// How the note stood in the line: `.clause` when it ends with closing clauses ("plus more for
    /// the pan"), even after parentheticals; otherwise `.parenthetical`. Nil without a note.
    public var noteForm: NoteForm?
    /// Set when the note counts the produce the line comes from ("about 3 oranges", "from 2 lemons").
    public var equivalent: ProduceEquivalent?
    public var isOptional: Bool
    /// The line as typed, trimmed. Kept so nothing the parser misreads is lost.
    public var rawText: String

    public init(
        quantity: Rational? = nil,
        unit: CookingUnit? = nil,
        item: String,
        preparation: String? = nil,
        note: String? = nil,
        noteForm: NoteForm? = nil,
        equivalent: ProduceEquivalent? = nil,
        isOptional: Bool = false,
        rawText: String = ""
    ) {
        self.quantity = quantity
        self.unit = unit
        self.item = item
        self.preparation = preparation
        self.note = note
        self.noteForm = noteForm
        self.equivalent = equivalent
        self.isOptional = isOptional
        self.rawText = rawText
    }
}

/// The deterministic ingredient-line parser used by manual entry and, later, by every import path
/// before a model is asked (04 §1 "deterministic first").
///
/// Reads a leading amount (whole numbers, fractions, mixed numbers, decimals, Unicode fractions,
/// "1-1/2", ranges such as "2-3" or "2 to 3", which keep the low end), an optional unit from
/// `CookingUnit`, then the item, with anything after the first comma as preparation; when only a
/// preparation word stands before the comma ("1 cup packed, fresh spinach leaves") the item is the
/// clause after it. "to taste" and "(optional)" are recognised anywhere in the line. Trailing
/// parentheticals and closing clauses such as "plus more for the pan" are the note, and a note
/// that counts produce ("about 3 oranges") also gives the equivalent.
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
        var saysToTasteAtEnd = false
        if let range = text.range(of: #",?\s*\(?\s*(or\s+)?\bto taste\b\s*\)?"#, options: [.regularExpression, .caseInsensitive]) {
            saysToTaste = true
            saysToTasteAtEnd = text[range.upperBound...].trimmingCharacters(in: .whitespaces).isEmpty
            text.removeSubrange(range)
        }

        // "About 2 cups", "Zest of 1 lemon", "Juice of 2 limes": an opening before the amount.
        let opening = takeOpening(&text)

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
        var equivalentUnit: CookingUnit?
        if unit != nil {
            equivalentUnit = dropEquivalentMeasure(&tokens)
        }
        tokens.skip(word: "of")

        var (item, preparation) = splitPreparation(tokens.remainder)
        // "1 cup packed, fresh spinach leaves": the measure's preparation, written before the comma.
        if quantity != nil, let prep = preparation, let swapped = leadingPreparation(item, before: prep) {
            item = swapped.item
            preparation = swapped.preparation
        }
        // "Juice of 2 limes" reads "2 limes, juiced": the produce to buy, and what to do with it.
        if let opening {
            preparation = [opening, preparation].compactMap(\.self).joined(separator: ", ")
        }
        // Ounces of a liquid are fluid ounces, "fl" or not (04 §5.1 Liquid ounces).
        if unit == .ounce, LiquidIngredients.ouncesAreFluid(item: item, equivalent: equivalentUnit) {
            unit = .fluidOunce
        }

        // Notes, in the order the line gives them: the item's trailing parentheticals, the
        // preparation's, then closing clauses ("plus more for the pan").
        let itemNotes = takeTrailingParentheticals(&item)
        var clauseNote: String?
        var preparationNotes: [String] = []
        if var prep = preparation {
            clauseNote = takeNoteClauses(&prep)
            preparationNotes = takeTrailingParentheticals(&prep)
            preparation = prep.isEmpty ? nil : prep
        }
        if saysToTaste {
            if quantity == nil {
                unit = .toTaste
            } else if let note = clauseNote, saysToTasteAtEnd {
                // "plus more to taste" stays one note.
                clauseNote = "\(note) to taste"
            } else {
                preparation = [preparation, "to taste"].compactMap(\.self).joined(separator: ", ")
            }
        }
        let notes = itemNotes + preparationNotes + [clauseNote].compactMap(\.self)
        if item.isEmpty, let prep = preparation {
            item = prep
            preparation = nil
        }

        return ParsedIngredient(
            quantity: quantity,
            unit: unit,
            item: item,
            preparation: preparation,
            note: notes.isEmpty ? nil : notes.joined(separator: "; "),
            noteForm: notes.isEmpty ? nil : (clauseNote != nil ? .clause : .parenthetical),
            equivalent: notes.lazy.compactMap(produceEquivalent(in:)).first,
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
        // "½-inch" stays one word: "1/2-inch", not "1/2 -inch".
        result = result.replacingOccurrences(of: #"(\d/\d+) -(?=[A-Za-z])"#, with: "$1-", options: .regularExpression)
        return result
    }

    // MARK: - Amount

    /// Amounts written as words, as cookbooks set a count at the start of a line ("Two large eggs",
    /// "One 3-pound chicken").
    private static let numberWords: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8,
        "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "fifteen": 15, "twenty": 20,
    ]

    private static func numberWord(_ token: String?) -> Int? {
        token.flatMap { numberWords[$0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ","))] }
    }

    /// The openings a cookbook sets before the amount (ux-notes row 58): "About 2 cups" (dropped;
    /// the line as written keeps it), "Zest of 1 lemon", "Juice of 2 limes", "Zest and juice of 1
    /// orange", which read as the produce with its preparation ("1 lemon, zested"). Taken only when
    /// an amount follows, so "Juice of the lemon" stays an item. Returns the preparation.
    private static func takeOpening(_ text: inout String) -> String? {
        let approximately = #"^(about|approximately|approx\.|roughly)\s+"#
        let produce: [(pattern: String, preparation: String?)] = [
            (#"^zest\s+and\s+juice\s+of\s+"#, "zested and juiced"),
            (#"^juice\s+and\s+zest\s+of\s+"#, "juiced and zested"),
            (#"^finely\s+grated\s+zest\s+of\s+"#, "finely grated zest"),
            (#"^grated\s+zest\s+of\s+"#, "grated zest"),
            (#"^zest\s+of\s+"#, "zested"),
            (#"^juice\s+of\s+"#, "juiced"),
        ]
        var preparation: String?
        // At most an opening and an "about" ("Juice of about 2 lemons").
        for _ in 0..<2 {
            var candidate: (rest: String, preparation: String?)?
            let current = text
            if let range = current.range(of: approximately, options: [.regularExpression, .caseInsensitive]) {
                candidate = (String(current[range.upperBound...]), nil)
            } else if preparation == nil {
                for entry in produce {
                    guard let range = current.range(of: entry.pattern, options: [.regularExpression, .caseInsensitive]) else { continue }
                    candidate = (String(current[range.upperBound...]), entry.preparation)
                    break
                }
            }
            guard let candidate else { break }
            // An "about" may stand between an opening and its amount.
            let amount = candidate.rest.replacingOccurrences(of: approximately, with: "", options: [.regularExpression, .caseInsensitive])
            var probe = Tokens(amount)
            guard readQuantity(&probe) != nil else { break }
            text = candidate.rest
            preparation = preparation ?? candidate.preparation
        }
        return preparation
    }

    private static func readQuantity(_ tokens: inout Tokens) -> Rational? {
        guard let first = tokens.peek() else { return nil }
        let word = first.lowercased()

        // "a dozen eggs", "half a lemon", "half an onion".
        if ["a", "an"].contains(word), tokens.peek(1)?.lowercased() == "dozen" {
            tokens.advance(2)
            return Rational(12)
        }
        if word == "half", let next = tokens.peek(1)?.lowercased(), ["a", "an"].contains(next) {
            tokens.advance(2)
            return Rational(1, 2)
        }

        // "a pinch", "an 8 oz" — only when a unit follows, so "an onion" stays an item.
        if ["a", "an"].contains(word), let next = tokens.peek(1), unit(for: next) != nil {
            tokens.advance()
            return .one
        }

        // "Two large eggs", "one and a half cups", "two dozen", "two or three cloves".
        if let count = numberWord(first) {
            tokens.advance()
            var value = Rational(count)
            if tokens.peek()?.lowercased() == "and", tokens.peek(1)?.lowercased() == "a", tokens.peek(2)?.lowercased() == "half" {
                tokens.advance(3)
                value = value + Rational(1, 2)
            }
            if tokens.peek()?.lowercased() == "dozen" {
                tokens.advance()
                value = value * Rational(12)
            }
            if let joiner = tokens.peek()?.lowercased(), ["-", "to", "or"].contains(joiner),
               numberWord(tokens.peek(1)) != nil || tokens.peek(1).flatMap(number) != nil {
                tokens.advance(2)
            }
            return value
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
        // "2 dozen clams".
        if tokens.peek()?.lowercased() == "dozen" {
            tokens.advance()
            value = value * Rational(12)
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

    /// "1 cup (240 ml) milk", "4 pounds (about 2kg) potatoes": the parenthetical repeats the amount
    /// in other units, which scaling and the unit toggle regenerate, so it is dropped, an "about"
    /// with it. Other parentheticals ("(14-ounce) can") stay. Returns the dropped measure's unit,
    /// which tells fluid ounces from ounces of weight.
    private static func dropEquivalentMeasure(_ tokens: inout Tokens) -> CookingUnit? {
        let rest = tokens.remainder
        let approximately = #"(?:(?:about|approximately|approx\.?|roughly|around|~)\s*)?"#
        guard let range = rest.range(of: #"^\(\s*"# + approximately + #"[\d./\s-]+\s*[A-Za-z. ]+\)\s*"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        let inner = rest[range].trimmingCharacters(in: CharacterSet(charactersIn: "() ").union(.whitespaces))
            .replacingOccurrences(of: "^" + approximately, with: "", options: [.regularExpression, .caseInsensitive])
        var innerTokens = Tokens(inner)
        guard readQuantity(&innerTokens) != nil, let unit = readUnit(&innerTokens), innerTokens.remainder.isEmpty else { return nil }
        tokens = Tokens(String(rest[range.upperBound...]))
        return unit
    }

    /// `item` without the approximate equivalent measure it starts with: "(about 2 kg) russet
    /// potatoes" is "russet potatoes". Lines parsed before the parser dropped an approximate
    /// leading equivalent stored it in the item, and the app's one-time re-read finds them with
    /// this. Nil when the item doesn't start with one: a bare measure ("(240 ml)") was always
    /// dropped, a parenthetical that isn't a measure ("(1-inch) piece") is part of the item, and
    /// nothing is left of an item that is only the measure.
    public static func removingLeadingApproximateEquivalent(from item: String) -> String? {
        let text = normalize(item)
        guard text.range(of: #"^\(\s*(?:about|approximately|approx\.?|roughly|around|~)"#, options: [.regularExpression, .caseInsensitive]) != nil else { return nil }
        var tokens = Tokens(text)
        guard dropEquivalentMeasure(&tokens) != nil, !tokens.remainder.isEmpty else { return nil }
        return tokens.remainder
    }

    // MARK: - Item and preparation

    /// The item is everything before the first comma outside parentheses, so "orange juice (from
    /// 3 oranges, strained)" keeps its parenthetical whole.
    private static func splitPreparation(_ text: String) -> (item: String, preparation: String?) {
        let cleaned = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ",;")))
        guard let comma = topLevelCommas(in: cleaned).first else { return (cleaned, nil) }
        let item = cleaned[..<comma].trimmingCharacters(in: .whitespaces)
        let preparation = cleaned[cleaned.index(after: comma)...].trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ",")))
        return (item, preparation.isEmpty ? nil : preparation)
    }

    /// The commas in `text` that are not inside parentheses.
    private static func topLevelCommas(in text: String) -> [String.Index] {
        var depth = 0
        var commas: [String.Index] = []
        for index in text.indices {
            switch text[index] {
            case "(": depth += 1
            case ")": depth = max(0, depth - 1)
            case "," where depth == 0: commas.append(index)
            default: break
            }
        }
        return commas
    }

    /// `text` split at its top-level commas: each clause trimmed, with where it starts.
    private static func clauses(of text: String) -> [(start: String.Index, text: String)] {
        var start = text.startIndex
        var result: [(start: String.Index, text: String)] = []
        for comma in topLevelCommas(in: text) + [text.endIndex] {
            result.append((start, text[start..<comma].trimmingCharacters(in: .whitespaces)))
            if comma < text.endIndex { start = text.index(after: comma) }
        }
        return result
    }

    /// How a measure is taken or its contents readied, which a cookbook may write before the
    /// comma: "1 cup packed, fresh spinach leaves". Participles only; `preparationAdverbs` qualify them.
    private static let preparationWords: Set<String> = [
        "packed", "heaping", "heaped", "chopped", "sifted", "melted", "softened", "cooked", "drained",
        "rinsed", "minced", "grated", "shredded", "sliced", "diced", "crushed", "toasted", "beaten",
        "peeled", "cubed", "crumbled", "mashed", "ground", "torn", "trimmed", "thawed", "pitted",
        "seeded", "cored", "halved", "quartered", "roasted", "blanched", "cooled", "chilled", "warmed",
    ]

    /// "loosely packed", "finely chopped", "well drained": what may qualify a preparation word.
    private static let preparationAdverbs: Set<String> = [
        "loosely", "lightly", "firmly", "tightly", "finely", "coarsely", "roughly", "thinly", "thickly",
        "freshly", "well", "very",
    ]

    private static func isPreparationWord(_ word: String) -> Bool {
        preparationWords.contains(word) || preparationAdverbs.contains(word)
    }

    /// "1 cup packed, fresh spinach leaves (3.5 ounces)", "2 cups chopped, fresh parsley": a cookbook
    /// puts the preparation before the comma when it says how the measure is taken. When the words
    /// between the measure and the first comma are one preparation word, or an adverb and one, the
    /// clause after the comma is the item and those words are the preparation; later clauses stay
    /// with the preparation, so "plus more for serving" is still a note. Nil, so the line reads as
    /// it did, when the words before the comma are not a preparation ("2 cloves garlic, minced")
    /// or the clause after it names no thing: a note clause, or preparation words only.
    private static func leadingPreparation(_ item: String, before preparation: String) -> (item: String, preparation: String)? {
        let words = item.split(separator: " ").map { $0.lowercased() }
        guard let last = words.last, preparationWords.contains(last),
              words.count == 1 || (words.count == 2 && preparationAdverbs.contains(words[0])) else { return nil }
        let rest = clauses(of: preparation).map { $0.text }.filter { !$0.isEmpty }
        guard let first = rest.first,
              first.range(of: noteClause, options: [.regularExpression, .caseInsensitive]) == nil,
              first.split(separator: " ").contains(where: { !isPreparationWord($0.lowercased()) }) else { return nil }
        return (item: first, preparation: ([item] + rest.dropFirst()).joined(separator: ", "))
    }

    // MARK: - Notes

    /// Removes the parentheticals that end `text` ("orange juice (about 3 oranges)") and returns
    /// their contents in order. A parenthetical must stand as its own word, so "stick(s)" stays,
    /// and is never the whole text, so "(14 oz) can" keeps its can.
    private static func takeTrailingParentheticals(_ text: inout String) -> [String] {
        var notes: [String] = []
        while true {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasSuffix(")") else { break }
            var depth = 0
            var opening: String.Index?
            for index in trimmed.indices.reversed() {
                if trimmed[index] == ")" { depth += 1 }
                if trimmed[index] == "(" {
                    depth -= 1
                    if depth == 0 { opening = index; break }
                }
            }
            guard let opening, opening > trimmed.startIndex,
                  trimmed[trimmed.index(before: opening)].isWhitespace else { break }
            let remaining = trimmed[..<opening].trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ",;")))
            let inner = trimmed[trimmed.index(after: opening)..<trimmed.index(before: trimmed.endIndex)].trimmingCharacters(in: .whitespaces)
            guard !remaining.isEmpty else { break }
            text = remaining
            if !inner.isEmpty { notes.insert(inner, at: 0) }
        }
        return notes
    }

    /// Clauses that say what a line is for or how much more to have, not how to prepare it:
    /// "plus more for the pan", "for serving", "about a handful", "if using", "such as Maldon".
    private static let noteClause = #"^(plus|about|approximately|approx\.?|roughly|around|from|such as|like|preferably|ideally|if|as needed|or as needed|or more|for|to serve|to garnish|to finish|see)\b"#

    /// Removes the closing run of note clauses from a preparation ("softened, plus more for the
    /// pan" keeps "softened") and returns them as written.
    private static func takeNoteClauses(_ preparation: inout String) -> String? {
        var first: String.Index?
        for clause in clauses(of: preparation).reversed() {
            guard clause.text.range(of: noteClause, options: [.regularExpression, .caseInsensitive]) != nil else { break }
            first = clause.start
        }
        guard let first else { return nil }
        let note = preparation[first...].trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ",")))
        preparation = preparation[..<first].trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ",")))
        return note.isEmpty ? nil : note
    }

    /// Words that name a size, not a thing, so "(2 large)" counts nothing.
    private static let sizeWords: Set<String> = ["small", "medium", "large", "extra-large", "jumbo", "whole", "big"]

    /// Packaging, portions and lengths: counted, but not produce to buy.
    private static let nonProduceWords: Set<String> = [
        "can", "cans", "tin", "tins", "jar", "jars", "package", "packages", "pkg", "packet", "packets",
        "box", "boxes", "bag", "bags", "bottle", "bottles", "carton", "cartons", "container", "containers",
        "tube", "tubes", "stick", "sticks", "slice", "slices", "serving", "servings", "portion", "portions",
        "batch", "batches", "handful", "handfuls", "inch", "inches", "cm", "minute", "minutes", "hour", "hours",
        "total", "each",
    ]

    /// "about 3 oranges", "from 2 lemons", "about 1 1/2 pears", "2 lemons": a count and the
    /// produce it counts. Measures ("about 12 ounces"), bare counts ("about 12"), sizes ("2 large"),
    /// packaging ("5 (10-ounce) packages") and alternatives ("or 1/2 teaspoon dried thyme") are not.
    static func produceEquivalent(in note: String) -> ProduceEquivalent? {
        let text = normalize(note)
            .replacingOccurrences(of: #"^(from about|about|approximately|approx\.?|roughly|around|from|made from)\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
        var tokens = Tokens(text)
        guard let count = readQuantity(&tokens), count > .zero, readUnit(&tokens) == nil else { return nil }
        let words = tokens.remainder.split(separator: " ").map(String.init)
        guard (1...4).contains(words.count),
              words.allSatisfy({ $0.allSatisfy { $0.isLetter || $0 == "-" || $0 == "'" || $0 == "’" } }),
              !words.allSatisfy({ sizeWords.contains($0.lowercased()) }),
              !words.contains(where: { nonProduceWords.contains($0.lowercased()) }) else { return nil }
        return ProduceEquivalent(count: count, item: words.joined(separator: " "))
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
