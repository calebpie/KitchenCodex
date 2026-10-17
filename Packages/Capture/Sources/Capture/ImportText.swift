import Foundation

/// Text cleanup shared by every import path.
enum ImportText {
    /// Entities decoded, tags removed, whitespace collapsed. For names, ingredient lines and other
    /// one-line values, which pages sometimes fill with markup ("Salt &amp; pepper", "<b>2</b> eggs").
    static func inline(_ text: String) -> String {
        var result = text
        if result.contains("<") {
            result = result.replacingOccurrences(of: #"<[^>]*>"#, with: " ", options: .regularExpression)
        }
        // Twice, for pages that encode their entities again ("&amp;frac12;").
        result = HTMLEntities.decode(HTMLEntities.decode(result))
        return result.collapsingWhitespace
    }

    /// Like `inline`, but block markup becomes paragraph breaks, so `StepSplitter` sees the structure
    /// of instruction text such as "<p>Preheat…</p><p>Toss…</p>".
    static func paragraphs(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "\r\n", with: "\n")
        if result.contains("<") {
            result = result.replacingOccurrences(
                of: #"<\s*(br|/p|/li|/div|/h[1-6]|p|li|div|h[1-6])\b[^>]*>"#,
                with: "\n\n",
                options: [.regularExpression, .caseInsensitive]
            )
            result = result.replacingOccurrences(of: #"<[^>]*>"#, with: " ", options: .regularExpression)
        }
        result = HTMLEntities.decode(HTMLEntities.decode(result))
        return result
            .components(separatedBy: "\n")
            .map(\.collapsingWhitespace)
            .joined(separator: "\n")
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Steps from one block of instruction text: markup to paragraphs, then `StepSplitter`.
    static func steps(from text: String) -> [String] {
        StepSplitter.steps(from: paragraphs(text)).filter { !isSectionLabel($0) }
    }

    /// "To Finish the Stew:" or "For the sauce:." posted as a step of its own.
    static func isSectionLabel(_ step: String) -> Bool {
        step.count <= 50 && step.range(of: #"^[^.!?]+:\.?$"#, options: .regularExpression) != nil
    }

    // MARK: - Ingredient lines

    /// Puts a page's ingredient line in the shape `IngredientParser` reads best:
    /// "1 ¼ cups|284 ml soy sauce" → "1 ¼ cups (284 ml) soy sauce" (a dual measure the parser then
    /// drops), checkbox glyphs removed.
    static func ingredientLine(_ line: String) -> String {
        var text = inline(line)
        text = text.replacingOccurrences(of: #"^([▢☐□◻︎◻✓✔•·*]\s*|[-–]\s+)"#, with: "", options: .regularExpression)
        if text.contains("|") {
            text = text.replacingOccurrences(
                of: #"^([^|]*?[A-Za-z.]+)\s*\|\s*([\d.,/½¼¾⅓⅔⅛⅜⅝⅞\s-]+\s*[A-Za-z.]+)"#,
                with: "$1 ($2)",
                options: .regularExpression
            )
        }
        return text.collapsingWhitespace
    }

    /// "1 ¼ cups|284 ml water" inside step text → "1 ¼ cups (284 ml) water".
    static func dualMeasures(_ text: String) -> String {
        guard text.contains("|") else { return text }
        return text.replacingOccurrences(
            of: #"([\d½¼¾⅓⅔⅛⅜⅝⅞][\d\s/.½¼¾⅓⅔⅛⅜⅝⅞]*\s*[A-Za-z]+\.?)\s*\|\s*(\d[\d.,/]*\s*[A-Za-z]+\.?)"#,
            with: "$1 ($2)",
            options: .regularExpression
        )
    }

    /// A line that names an ingredient group rather than an ingredient: "For the dressing:",
    /// "To Assemble:", "for the beef:", "Garnish".
    static func isGroupHeading(_ line: String) -> Bool {
        let text = line.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, text.count <= 50 else { return false }
        if text.first?.isNumber == true { return false }
        if text.hasSuffix(":") { return true }
        let lower = text.lowercased()
        if lower.range(of: #"^(for|to)\s+(the\s+)?[\p{L}'’ -]{2,40}$"#, options: .regularExpression) != nil,
           !lower.contains(" taste") {
            return lower.hasPrefix("for ") || ["to serve", "to finish", "to garnish", "to assemble", "to top"].contains { lower.hasPrefix($0) }
        }
        return false
    }

    /// The heading text without its trailing colon.
    static func groupName(_ line: String) -> String {
        var text = line.trimmingCharacters(in: .whitespaces)
        while text.hasSuffix(":") { text.removeLast() }
        return text.trimmingCharacters(in: .whitespaces)
    }

    /// Splits each raw ingredient entry on line breaks (some pages pack a whole list into one string),
    /// pulls out group headings, and drops blanks.
    static func ingredientList(_ entries: [String]) -> (lines: [String], groups: [Int: String]) {
        var lines: [String] = []
        var groups: [Int: String] = [:]
        for entry in entries {
            for piece in paragraphs(entry).components(separatedBy: "\n") {
                let line = ingredientLine(piece)
                guard !line.isEmpty else { continue }
                if isGroupHeading(line) {
                    groups[lines.count] = groupName(line)
                } else {
                    lines.append(line)
                }
            }
        }
        // A heading after the last ingredient names nothing.
        groups = groups.filter { $0.key < lines.count }
        return (lines, groups)
    }

    // MARK: - Titles

    private static let titleSeparators = [" | ", " - ", " — ", " – ", " :: ", " · ", " • "]

    /// "Orzo with Roasted Vegetables | Recipes" → "Orzo with Roasted Vegetables";
    /// "Lamb Tartare Recipe | Bon Appétit" → "Lamb Tartare". Segments naming the site or a generic
    /// section are dropped, and a trailing "Recipe" goes when the rest still reads as a title.
    static func cleanTitle(_ raw: String, siteName: String? = nil, host: String? = nil) -> String {
        var segments = [inline(raw)]
        for separator in titleSeparators {
            segments = segments.flatMap { $0.components(separatedBy: separator) }
        }
        segments = segments.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        let site = siteName.map(normalizedForComparison)
        let hostName = host.map { normalizedForComparison($0.replacingOccurrences(of: "www.", with: "").components(separatedBy: ".").first ?? $0) }
        let generic: Set<String> = ["recipe", "recipes", "home", "cooking", "food", "blog"]
        let kept = segments.filter { segment in
            let key = normalizedForComparison(segment)
            if generic.contains(key) { return false }
            if let site, key == site || (key.count > 3 && site.contains(key)) { return false }
            if let hostName, key.replacingOccurrences(of: " ", with: "") == hostName { return false }
            return true
        }
        var title = kept.first ?? segments.first ?? ""
        title = stripRecipeSuffix(title)
        return title
    }

    static func stripRecipeSuffix(_ title: String) -> String {
        guard let range = title.range(of: #"\s+recipe$"#, options: [.regularExpression, .caseInsensitive]) else { return title }
        let rest = String(title[..<range.lowerBound])
        return rest.split(separator: " ").count >= 2 ? rest : title
    }

    /// Lowercased letters and digits with single spaces, for loose matching of titles and lines.
    static func normalizedForComparison(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        var result = ""
        var pendingSpace = false
        for character in folded {
            if character.isLetter || character.isNumber {
                if pendingSpace, !result.isEmpty { result.append(" ") }
                pendingSpace = false
                result.append(character)
            } else if character == "'" || character == "’" {
                continue
            } else {
                pendingSpace = true
            }
        }
        return result
    }

    // MARK: - URLs

    static func url(_ text: String?, relativeTo base: URL?) -> URL? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        let candidate = text.hasPrefix("//") ? "https:" + text : text
        guard let url = URL(string: candidate, relativeTo: base)?.absoluteURL,
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        return url
    }
}

// MARK: - Yield

/// Reads servings out of a yield statement.
enum YieldText {
    struct Reading: Equatable {
        var servings: Int?
        /// The statement when it says more than a single servings count, else nil.
        var description: String?
    }

    static func parse(_ text: String?) -> Reading {
        guard let raw = text.map(ImportText.inline), !raw.isEmpty else { return Reading() }
        let lower = raw.lowercased()
        let servingsWords = #"^(servings?|serving\(s\)|people|persons?|portions?|as an? [\w ]+)\b"#
        let labelPattern = #"^(yields?|serves|servings|makes|portions)\b\s*[:—–-]?\s*"#
        let label = lower.range(of: labelPattern, options: .regularExpression).map { String(lower[$0]) } ?? ""
        let body = String(lower.dropFirst(label.count)).trimmingCharacters(in: .whitespaces)

        guard let numberRange = body.range(of: #"^\d+"#, options: .regularExpression),
              let number = Int(body[numberRange]), number > 0 else {
            return Reading(servings: nil, description: raw)
        }
        var rest = body[numberRange.upperBound...].trimmingCharacters(in: .whitespaces)
        var upper: Int?
        if let range = rest.range(of: #"^(-|–|to|or)\s*\d+"#, options: .regularExpression) {
            upper = Int(rest[range].filter(\.isNumber))
            rest = rest[range.upperBound...].trimmingCharacters(in: .whitespaces)
        }
        let labelSaysServes = label.hasPrefix("serves") || label.hasPrefix("servings") || label.hasPrefix("portions")
        let restIsServings = rest.isEmpty || rest.range(of: servingsWords, options: .regularExpression) != nil
        guard labelSaysServes || restIsServings else {
            // "Makes 30 cookies", "1 loaf", "2 cups".
            return Reading(servings: nil, description: raw)
        }
        // "Serves 6", "6 servings", "8": the number says it all. A range keeps its top end in words.
        return Reading(servings: number, description: upper.map { "Serves \(number)–\($0)" })
    }

    /// Picks the best statement from schema.org's string-or-number-or-array `recipeYield`.
    static func best(_ candidates: [String]) -> String? {
        let cleaned = candidates.map(ImportText.inline).filter { !$0.isEmpty }
        // A descriptive statement beats a bare number; "4 servings" beats "4".
        return cleaned.first { parse($0).description != nil && parse($0).servings == nil }
            ?? cleaned.first { $0.contains(where: \.isLetter) }
            ?? cleaned.first
    }
}

// MARK: - Durations

/// schema.org times such as "PT1H30M" or "P0Y0M0DT0H20M0.000S".
enum ISO8601Duration {
    static func parse(_ text: String) -> Duration? {
        let text = text.trimmingCharacters(in: .whitespaces).uppercased()
        guard text.hasPrefix("P"), text.count > 1 else { return nil }
        var seconds = 0.0
        var number = ""
        var inTime = false
        for character in text.dropFirst() {
            switch character {
            case "T": inTime = true
            case "0"..."9", ".", ",": number.append(character == "," ? "." : character)
            case "Y": seconds += value(number) * 365 * 86_400; number = ""
            case "W": seconds += value(number) * 7 * 86_400; number = ""
            case "D": seconds += value(number) * 86_400; number = ""
            case "H": seconds += value(number) * 3_600; number = ""
            case "M": seconds += value(number) * (inTime ? 60 : 30 * 86_400); number = ""
            case "S": seconds += value(number); number = ""
            default: return nil
            }
        }
        guard number.isEmpty else { return nil }
        return .seconds(Int(seconds.rounded()))
    }

    private static func value(_ text: String) -> Double {
        Double(text) ?? 0
    }
}

/// Times written for people: "1 hour 10 minutes", "55 minutes, plus overnight", "4 hrs", "1½ hours".
enum TextDuration {
    static func parse(_ text: String) -> Duration? {
        let normalized = text.lowercased()
            .replacingOccurrences(of: "½", with: ".5")
            .replacingOccurrences(of: "¼", with: ".25")
            .replacingOccurrences(of: "¾", with: ".75")
            .replacingOccurrences(of: #"(\d)\s+\.(\d)"#, with: "$1.$2", options: .regularExpression)
            .replacingOccurrences(of: #"(\d+)\s+1/2"#, with: "$1.5", options: .regularExpression)
        let pattern = #"(\d+(?:\.\d+)?|\.\d+)\s*(days?|d|hours?|hrs?|hr|h|minutes?|mins?|min|m)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(normalized.startIndex..., in: normalized)
        var seconds = 0.0
        for match in regex.matches(in: normalized, range: range) {
            guard let numberRange = Range(match.range(at: 1), in: normalized),
                  let unitRange = Range(match.range(at: 2), in: normalized),
                  let number = Double(normalized[numberRange]) else { continue }
            let unit = normalized[unitRange]
            switch unit.first {
            case "d": seconds += number * 86_400
            case "h": seconds += number * 3_600
            default: seconds += number * 60
            }
        }
        return seconds > 0 ? .seconds(Int(seconds.rounded())) : nil
    }
}
