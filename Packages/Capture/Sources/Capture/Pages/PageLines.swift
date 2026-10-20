import Foundation
import Units

/// Line-level readings shared by the page structurer: what a printed line looks like it is.
enum PageLines {
    // MARK: - Cleanup

    /// An ingredient line as the parser reads it best: OCR's run-together mixed fractions mended
    /// ("13/4 cups" → "1 3/4 cups", "11/2-inch" → "1 1/2-inch": a whole number glued to a proper
    /// fraction is never a quantity a book prints), bullets and stray marks dropped.
    static func ingredientText(_ line: String) -> String {
        var text = line.trimmingCharacters(in: .whitespaces)
        text = text.replacingOccurrences(of: #"^([•·▪■□☐*\-–]\s+)"#, with: "", options: .regularExpression)
        if let match = text.firstMatch(of: /^(\d)(\d)\/(\d{1,2})(?=[\s\-]|$)/),
           let numerator = Int(match.output.2), let denominator = Int(match.output.3), numerator < denominator {
            text = "\(match.output.1) \(numerator)/\(denominator)" + text[match.range.upperBound...]
        }
        // A small "¼" read as "1%" before a unit ("1% ounce dried mushrooms").
        text = text.replacingOccurrences(of: #"^1%\s*(?=(ounces?|oz|cups?|teaspoons?|tablespoons?|tsp|tbsp|pounds?|lbs?|inch)\b)"#, with: "1/4 ", options: .regularExpression)
        // OCR's capital I for a lowercase l in "lbs".
        text = text.replacingOccurrences(of: #"(?<=\d )Ibs?\b"#, with: "lbs", options: .regularExpression)
        return ImportText.ingredientLine(text)
    }

    /// Text joined for a title or heading: all-capital titles in title case ("SLOW-ROASTED
    /// DUCK—CANARD RÔTI" → "Slow-Roasted Duck—Canard Rôti"),
    /// mixed case as printed.
    static func titleText(_ text: String) -> String {
        let letters = text.filter(\.isLetter)
        guard !letters.isEmpty, letters.allSatisfy({ !$0.isLowercase }) else { return text }
        let small: Set<String> = ["a", "an", "and", "as", "at", "but", "by", "de", "des", "du", "en", "et", "for", "from", "in", "into", "la", "le", "les", "of", "on", "or", "the", "to", "with", "à", "au", "aux"]
        var result = ""
        var wordStart = true
        var word = ""
        func flush() {
            guard !word.isEmpty else { return }
            let lower = word.lowercased()
            if !result.isEmpty, small.contains(lower), !(result.last.map { "—–-:/(".contains($0) } ?? true) {
                result += lower
            } else {
                result += lower.prefix(1).uppercased() + lower.dropFirst()
            }
            word = ""
        }
        for character in text {
            if character.isLetter || character == "'" || character == "’" {
                word.append(character)
                wordStart = false
            } else {
                flush()
                result.append(character)
                wordStart = true
            }
        }
        _ = wordStart
        flush()
        return result
    }

    // MARK: - Kinds of lines

    /// "Serves 4", "serves 4", "MAKES 2 TO 4 SERVINGS", "Makes about 1 cup", "Yield: 6".
    static func isYield(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespaces)
        guard lower.count <= 60 else { return false }
        return lower.range(of: #"^(serves|makes|yield|yields|serving|servings|portions)\b"#, options: .regularExpression) != nil
    }

    /// "MAKES 2 CUPS (480 ML) / A sauce we keep on hand…": a yield set at the head of the headnote.
    static func leadingYield(_ text: String) -> (yield: String, rest: String)? {
        guard let match = text.firstMatch(of: /^((?i:makes|serves|yield)[^\/]{1,40}?)\s*\/\s*(.+)$/) else { return nil }
        return (String(match.output.1).trimmingCharacters(in: .whitespaces), String(match.output.2))
    }

    /// The yield as it reads in the app: capitals made sentence case ("MAKES 2 TO 4 SERVINGS" →
    /// "Makes 2 to 4 servings"), a stray separator dropped.
    static func yieldText(_ text: String) -> String {
        var result = text.trimmingCharacters(in: CharacterSet(charactersIn: " .;:/"))
        let letters = result.filter(\.isLetter)
        if !letters.isEmpty, letters.allSatisfy({ !$0.isLowercase }) {
            let lower = result.lowercased()
            result = lower.prefix(1).uppercased() + lower.dropFirst()
        } else if let first = result.first, first.isLowercase {
            result = first.uppercased() + result.dropFirst()
        }
        return YieldText.strippingLabel(result)
    }

    /// "Prep time: 20 minutes", "Active time 1 hour", "Total: 2 hours".
    static func time(_ text: String) -> (kind: String, duration: Duration)? {
        guard let match = text.firstMatch(of: /^(?i)(prep(?:aration)?|active|hands-on|cook(?:ing)?|total)(?:\s+time)?\s*[:\-–]?\s*(.+)$/) else { return nil }
        guard let parsed = DurationParser.mentions(in: String(match.output.2)).first?.duration else { return nil }
        let seconds = Double(parsed.duration.seconds.numerator) / Double(parsed.duration.seconds.denominator)
        let kind = match.output.1.lowercased()
        let label = kind.hasPrefix("prep") || kind == "active" || kind == "hands-on" ? "prep" : kind.hasPrefix("cook") ? "cook" : "total"
        return (label, .seconds(seconds))
    }

    /// A caps phrase and a colon opening a paragraph: "FOR THE SAUCE:", "TO FINISH:", "DAY 2.
    /// CURING THE DUCK:". Always starts a new step.
    static func runInHead(_ text: String) -> String? {
        guard let match = text.firstMatch(of: /^(\p{Lu}[\p{Lu}0-9 ,.'’&\-]{2,70}:)\s*/) else { return nil }
        let head = String(match.output.1)
        guard head.filter(\.isLetter).count >= 4 else { return nil }
        return head
    }

    private static let stepVerbs: Set<String> = [
        "add", "adjust", "allow", "arrange", "assemble", "bake", "baste", "beat", "blanch", "blend", "boil", "braise",
        "break", "bring", "brown", "brush", "butterfly", "carefully", "check", "chill", "chop", "clean", "coat", "combine",
        "cook", "cool", "core", "cover", "crush", "cut", "debone", "deep-fry", "discard", "dip", "dissolve", "divide", "drain",
        "dress", "drizzle", "dry", "dry-roast", "dust", "fill", "finish", "first", "fit", "fold", "fry", "garnish", "grate",
        "grill", "grind", "halve", "heat", "hold", "insert", "julienne", "knead", "ladle", "lay", "layer", "leave", "let",
        "lift", "line", "make", "marinate", "mash", "meanwhile", "melt", "mince", "mix", "moisten", "next", "oil", "open",
        "peel", "pick", "pierce", "pipe", "place", "poach", "pour", "preheat", "prepare", "press", "pull", "pulse", "puree",
        "purée", "push", "put", "quickly", "refresh", "refrigerate", "reheat", "remove", "repeat", "reserve", "rest", "return",
        "rinse", "roast", "roll", "rub", "salt", "sauté", "saute", "scatter", "scoop", "scrape", "sear", "season", "separate",
        "serve", "set", "shake", "shape", "shell", "shred", "sift", "simmer", "skim", "slice", "soak", "spoon", "spread",
        "sprinkle", "squeeze", "stand", "start", "steam", "steep", "stir", "store", "strain", "stuff", "swirl", "taste",
        "thread", "tie", "toast", "top", "toss", "transfer", "trim", "truss", "turn", "unmold", "unwrap", "use", "using",
        "warm", "wash", "whisk", "wipe", "wrap", "wring", "then", "finally", "once", "when", "while", "if", "after", "before",
        "just", "to", "for", "in", "on", "with", "at", "about", "as", "working", "holding", "starting", "spoon",
    ]

    /// Whether a paragraph reads as an instruction: it opens with a cooking verb ("Preheat",
    /// "Combine"), a run-in head or a step number, or a clause that sets one up ("In a small
    /// bowl,", "When ready to serve,", "To make the mayonnaise.").
    static func readsAsInstruction(_ text: String) -> Bool {
        var body = text
        if let head = runInHead(body) { _ = head; return true }
        if let match = body.firstMatch(of: /^\d{1,2}\s+/) { body = String(body[match.range.upperBound...]) }
        guard let first = body.split(whereSeparator: { $0.isWhitespace || $0 == "," }).first else { return false }
        let word = first.lowercased().trimmingCharacters(in: .punctuationCharacters)
        guard stepVerbs.contains(word) else { return false }
        // "For me, the best part…", "In summer, when the tomatoes…", "As cooks, we…": a
        // preposition opens a step only when a cooking clause follows.
        if ["for", "in", "on", "with", "at", "as", "about", "after", "before", "if", "when", "while", "once", "to", "just"].contains(word) {
            let lower = body.lowercased()
            if lower.range(of: #"^(for|as|in|on) (me|us|you|cooks|summer|winter|spring|fall|autumn|france|the restaurant|our|this|these|most|many|some)\b"#, options: .regularExpression) != nil { return false }
            if lower.range(of: #"\b(i|we|my|our|us)\b"#, options: .regularExpression) != nil,
               lower.range(of: #"\b(preheat|combine|add|place|put|stir|bring|heat|cook|remove|cut|serve|transfer|pour|mix|toss|season)\b"#, options: .regularExpression) == nil {
                return false
            }
        }
        return true
    }

    /// A verb of the method first, as a numbered step reads once its number is taken off ("When
    /// ready to serve, ladle…" is not; "Grate the cheese…" is). Prepositions and conjunctions don't
    /// count: "(about 2 cups packed) basil leaves" is an ingredient.
    static func opensWithVerb(_ text: String) -> Bool {
        guard let first = text.split(whereSeparator: { $0.isWhitespace || $0 == "," }).first, first.first?.isLetter == true else { return false }
        let word = first.lowercased().trimmingCharacters(in: .punctuationCharacters)
        let connectives: Set<String> = ["to", "for", "in", "on", "with", "at", "about", "as", "then", "finally", "once", "when", "while", "if", "after", "before", "just", "first", "next", "meanwhile", "quickly", "carefully", "working", "holding", "starting", "using"]
        return stepVerbs.contains(word) && !connectives.contains(word)
    }

    /// First person or a description of the dish: the voice of a headnote.
    static func readsAsHeadnote(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.range(of: #"\b(i|i'm|i’m|i've|my|we|we're|our|us)\b"#, options: .regularExpression) != nil { return true }
        return lower.range(of: #"^(this|these|here|there|it's|it’s|a |an |the |traditionally|in summer|whether)"#, options: .regularExpression) != nil
    }

    /// "note", "Note:", "NOTE", "Cook's note" opening an aside, or the label read after its text
    /// ("…keeps for a week. note").
    static func isNote(_ text: String) -> Bool {
        text.range(of: #"^(notes?|cook'?s note|tip)\b([:\s]|$)"#, options: [.regularExpression, .caseInsensitive]) != nil
            || text.range(of: #"[.)]\s+notes?$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// The note's text without its label, wherever the recognizer put it.
    static func noteText(_ text: String) -> String {
        var result = text.replacingOccurrences(of: #"^(notes?|cook'?s note|tip)\b[:\s]*"#, with: "", options: [.regularExpression, .caseInsensitive])
        result = result.replacingOccurrences(of: #"\s+notes?$"#, with: "", options: [.regularExpression, .caseInsensitive])
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// A step number set before a step: "2 When ready to serve…", "3. Grate the cheese…". The
    /// number and the text after it.
    static func stepNumber(_ text: String) -> (Int, String)? {
        guard let match = text.firstMatch(of: /^(\d{1,2})[.)]?\s+(.+)$/), let number = Int(match.output.1) else { return nil }
        let rest = String(match.output.2)
        guard let first = rest.first, first.isUppercase else { return nil }
        let word = rest.split(separator: " ").first.map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) } ?? ""
        guard stepVerbs.contains(word) || rest.split(separator: " ").count >= 8 else { return nil }
        return (number, rest)
    }

    /// A line set apart as a cross-reference: "PHOTOGRAPH ON PAGE 6", "PHOTOGRAPHS ON PAGES 31 AND 97",
    /// "PHOTOGRAPHS OPPOSITE".
    static func isCrossReferenceLine(_ text: String) -> Bool {
        text.range(of: #"^(photographs?|photo|see)\b.{0,40}$"#, options: [.regularExpression, .caseInsensitive]) != nil
            && text.count <= 50
    }

    // MARK: - Ingredient lines

    enum IngredientShape: Equatable {
        /// An amount and an item; strength 1 with a unit, 0.85 counted, 0.8 "to taste".
        case strong(Double)
        /// Short, no amount, no sentence: "Kosher salt", "Dijon mustard", "Fleur de sel".
        case bare
        case not
    }

    static func ingredientShape(_ line: String) -> IngredientShape {
        let text = ingredientText(line)
        let words = text.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty, text.count <= 110, words.count <= 16 else { return .not }
        if stepNumber(text) != nil, words.count >= 6 { return .not }
        if isYield(text) || runInHead(text) != nil { return .not }
        let endsSentence = text.last.map { ".!?".contains($0) } ?? false
        let parsed = IngredientParser.parse(text)
        if parsed.unit == .toTaste, parsed.quantity == nil, words.count <= 10 { return .strong(0.8) }
        if parsed.quantity != nil, !parsed.item.isEmpty {
            if endsSentence, words.count > 8 { return .not }
            // "2 Grate the cheese over the top and…": a step with its number has no unit and a
            // capitalized verb, unlike "½ to ¾ cup dry vermouth, such as".
            if parsed.unit == nil, parsed.item.first?.isUppercase == true, opensWithVerb(parsed.item), words.count >= 6 { return .not }
            return .strong(parsed.unit == nil ? 0.85 : 1)
        }
        // An amount the parser could not read: "One 5-pound chicken…", "About 1½ pounds…", "Zest of 1 orange".
        if text.range(of: #"^(one|two|three|four|five|six|eight|ten|twelve|a|about|zest of|juice of|grated zest|finely grated)\b.*\d"#, options: [.regularExpression, .caseInsensitive]) != nil,
           !endsSentence, words.count <= 12 {
            return .strong(0.6)
        }
        // "Kosher salt and black pepper", "salt and black pepper" (salt is a verb too, but a step
        // runs longer), "Fleur de sel".
        if !endsSentence, words.count <= 8, text.count <= 60, text.contains(where: \.isLetter),
           !(opensWithVerb(text) && words.count >= 5), !(readsAsInstruction(text) && !opensWithVerb(text) && words.count >= 5) {
            return .bare
        }
        return .not
    }

    /// A line that names an ingredient group: "SAUCE", "Dressing", "stock", "For the dressing:",
    /// "Pickling liquid". Decided with the lines around it (a group heading heads a list).
    static func couldBeGroupHeading(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 40, !trimmed.contains(where: \.isNumber) else { return false }
        let words = trimmed.split(whereSeparator: \.isWhitespace)
        guard words.count <= 5 else { return false }
        if trimmed.hasSuffix(":") { return true }
        if ImportText.isGroupHeading(trimmed) { return true }
        return !(trimmed.last.map { ".,;".contains($0) } ?? false)
    }

    /// Whether the parser read the line well enough: an item, and an amount read where the line has
    /// digits for one.
    static func isUnparsed(_ text: String, parsed: ParsedIngredient) -> Bool {
        if parsed.item.trimmingCharacters(in: .whitespaces).isEmpty { return true }
        if parsed.quantity == nil, parsed.unit != .toTaste, text.contains(where: { $0.isNumber || "½¼¾⅓⅔⅛⅜⅝⅞".contains($0) }) {
            // "(see page 214)" alone is no amount.
            let withoutPages = text.replacingOccurrences(of: #"\((see )?[^)]*pages? \d+[^)]*\)"#, with: "", options: [.regularExpression, .caseInsensitive])
            return withoutPages.contains(where: { $0.isNumber || "½¼¾⅓⅔⅛⅜⅝⅞".contains($0) })
        }
        // Two lines read as one: an amount inside where one item should be ("2 eggs 1 cup milk").
        return text.split(separator: " ").count > 30
    }

    /// The parser's confidence in a line.
    static func parserConfidence(_ parsed: ParsedIngredient, unparsed: Bool) -> Double {
        if unparsed { return 0.3 }
        if parsed.quantity != nil { return parsed.unit == nil ? 0.85 : 1 }
        if parsed.unit == .toTaste { return 0.9 }
        return 0.7
    }
}
