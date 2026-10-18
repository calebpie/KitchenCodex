import Foundation

/// A temperature as a recipe wrote it: every alternative the text names, in order, and the
/// original words so the app can keep them alongside the converted value.
///
/// "240C/fan 220C/gas 9" parses to three alternatives: 240°C, 220°C tagged `fan`, and gas 9.
public struct ParsedTemperature: Hashable, Sendable, Codable {
    /// The alternatives in the order the text names them; never empty.
    public var alternatives: [Temperature]
    /// The exact text that was parsed, as written.
    public var originalText: String

    public init(alternatives: [Temperature], originalText: String) {
        precondition(!alternatives.isEmpty, "A parsed temperature names at least one alternative")
        self.alternatives = alternatives
        self.originalText = originalText
    }

    /// The first alternative the text names.
    public var primary: Temperature { alternatives[0] }

    /// The alternative to show a cook who prefers `scale`, converted and rounded where needed.
    ///
    /// A value written in `scale` for a conventional oven wins and is shown as written. Otherwise
    /// a gas mark is converted before a degree value, because the table gives the chart numbers
    /// a cook expects (180°C/gas 4 reads as 350°F, not 355°F). Fan-oven values are used only when
    /// nothing else was written, and keep their `fan` tag.
    public func displayed(in scale: TemperatureScale) -> Temperature {
        let conventional = alternatives.filter { !$0.fan }
        let candidates = conventional.isEmpty ? alternatives : conventional
        if let written = candidates.first(where: { $0.scale == scale }) { return written }
        if let gas = candidates.first(where: { $0.scale == .gasMark }) { return gas.displayed(in: scale) }
        return candidates[0].displayed(in: scale)
    }

    /// ``displayed(in:)`` formatted: "350°F" for "180°C/gas 4" when the cook prefers Fahrenheit.
    public func formatted(in scale: TemperatureScale, style: TemperatureNameStyle = .abbreviated) -> String {
        displayed(in: scale).formatted(style: style)
    }
}

/// A temperature found inside a longer sentence, with where it sits so the app can put a pill
/// in its place.
public struct TemperatureMention: Hashable, Sendable {
    public var range: Range<String.Index>
    public var temperature: ParsedTemperature

    public init(range: Range<String.Index>, temperature: ParsedTemperature) {
        self.range = range
        self.temperature = temperature
    }

    /// The words the mention replaces, as written.
    public var originalText: String { temperature.originalText }
}

/// Reads the temperatures recipes write: "350°F", "350 degrees F", "180 C", "gas mark 6",
/// "moderate oven", and British combined forms such as "240C/fan 220C/gas 9" or
/// "200°C (180°C fan), gas 6, 400°F". A degree sign may be doubled up with the word, as some
/// sites write it: "375º degrees Fahrenheit" reads as 375°F.
///
/// Like ``UnitParser`` it never guesses: "350 degrees" with no scale is not a temperature (nor
/// is "350° degrees"), and a bare letter ("180 C") needs a value of at least 10 so that
/// "2 C flour" stays two cups. Matching ignores case.
public struct TemperatureParser: Hashable, Sendable, Codable {
    public init() {}

    /// Gas marks the descriptive oven words stand for.
    static let descriptions: [String: Rational] = [
        "very cool": Rational(1, 2), "very slow": Rational(1, 2),
        "cool": 1,
        "slow": 2,
        "moderately slow": 3,
        "moderate": 4, "medium": 4,
        "moderately hot": 5,
        "fairly hot": 6, "medium hot": 6,
        "hot": 7,
        "very hot": 9,
    ]

    /// The whole of `text`, give or take whitespace, punctuation and parentheses, as a temperature.
    public func parse(_ text: String) -> ParsedTemperature? {
        TemperatureParser.parse(text)
    }

    /// The whole of `text`, give or take whitespace, punctuation and parentheses, as a temperature.
    public static func parse(_ text: String) -> ParsedTemperature? {
        let found = mentions(in: text)
        guard found.count == 1, let mention = found.first else { return nil }
        let leftover = text[..<mention.range.lowerBound] + text[mention.range.upperBound...]
        let ignorable = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".,;:()"))
        guard leftover.unicodeScalars.allSatisfy(ignorable.contains) else { return nil }
        return mention.temperature
    }

    /// Every temperature in `text`, in order, each with its range. Alternatives joined by "/",
    /// commas, "or", "and" or parentheses form one mention: "Bake at 180°C (350°F) for an hour"
    /// has one mention, "180°C (350°F)", with two alternatives.
    public func mentions(in text: String) -> [TemperatureMention] {
        TemperatureParser.mentions(in: text)
    }

    /// Every temperature in `text`, in order, each with its range; see the instance method.
    public static func mentions(in text: String) -> [TemperatureMention] {
        let atoms = Self.atoms(in: text)
        var result: [TemperatureMention] = []
        var group: [Atom] = []

        func flush() {
            guard let first = group.first, let last = group.last else { return }
            let range = Self.balancingParentheses(first.range.lowerBound..<last.range.upperBound, in: text)
            let parsed = ParsedTemperature(alternatives: group.map(\.temperature), originalText: String(text[range]))
            result.append(TemperatureMention(range: range, temperature: parsed))
            group.removeAll()
        }

        for atom in atoms {
            if let previous = group.last {
                let glue = text[previous.range.upperBound..<atom.range.lowerBound]
                if glue.wholeMatch(of: Self.glue) == nil { flush() }
            }
            group.append(atom)
        }
        flush()
        return result
    }

    // MARK: - Atoms

    /// One temperature term in the text, before combined forms are grouped.
    struct Atom {
        var range: Range<String.Index>
        var temperature: Temperature
    }

    // `Regex` is not `Sendable`, but these are immutable once built and matching does not
    // mutate them, so sharing them across threads is safe.

    /// Degrees with a scale: "350°F", "350 F", "350 degrees F", "180 C", "fan 220C", "160°C fan",
    /// "200°C (fan)", "350℉", "180 degrees Celsius". The marker is a degree sign (°, º or ˚),
    /// the word "degrees" or "degree" (or "deg."), or a sign followed by the word, as in
    /// "375º degrees Fahrenheit"; the scale letter or word is required either way.
    nonisolated(unsafe) static let degrees = #/
        (?<leadFan> \b(?:fan|convection)(?:[-\ ]?(?:assisted|forced|oven))?:?\s* )?
        \b(?<value> \d+(?:\.\d+)? )
        (?:
            \s*(?<combined> [℉℃] )
          |
            (?: \s*(?<marker> [°º˚](?:\s*(?:degrees?|deg\.?))? | degrees? | deg\.? ) )?
            \s*(?<letter> fahrenheit|celsius|centigrade|f|c )(?![a-z])
        )
        (?<trailFan> \s*(?: \(\s*(?:fan|convection)\s*\) | (?:fan|convection)(?:[-\ ]?(?:assisted|forced|oven))?(?![a-z]) ) )?
    /#.ignoresCase()

    /// "gas mark 6", "gas 9", "Gas Mark ½", "gas mk 4", "gas 6½", "gas mark 1/2"; a fan word
    /// before or after is accepted so that a formatted fan value reads back.
    nonisolated(unsafe) static let gas = #/
        (?<leadFan> \b(?:fan|convection)(?:[-\ ]?(?:assisted|forced|oven))?:?\s* )?
        \bgas (?:\s*mark|\s*mk\.?)? \s*
        (?<mark> \d+\s*[½¼¾] | \d+\s+\d/\d | \d/\d | [½¼¾] | \d+(?:\.\d+)? )
        (?![\d/])
        (?<trailFan> \s*(?: \(\s*(?:fan|convection)\s*\) | (?:fan|convection)(?:[-\ ]?(?:assisted|forced|oven))?(?![a-z]) ) )?
    /#.ignoresCase()

    /// "moderate oven", "very hot oven", "moderately slow oven". Longer phrases first.
    nonisolated(unsafe) static let descriptive = #/
        \b(?<words> very\s+hot | very\s+cool | very\s+slow | moderately\s+hot | moderately\s+slow
                  | fairly\s+hot | medium\s+hot | moderate | medium | cool | slow | hot )
        \s+oven\b
    /#.ignoresCase()

    /// What may sit between two alternatives of one temperature.
    nonisolated(unsafe) static let glue = #/
        (?: \s | [/,;|()\[\]=–—-] | or | and | about | approx\.? )*
    /#.ignoresCase()

    static func atoms(in text: String) -> [Atom] {
        var atoms: [Atom] = []
        for match in text.matches(of: degrees) {
            guard let value = rational(fromDecimal: match.value) else { continue }
            let hasMarker = match.combined != nil || match.marker != nil
            let hasFullWord = (match.letter?.count ?? 0) > 1
            // A bare letter is a temperature only above single digits: "2 C flour" is cups.
            if !hasMarker, !hasFullWord, value < 10 { continue }
            let scale: TemperatureScale
            if let combined = match.combined {
                scale = combined == "℉" ? .fahrenheit : .celsius
            } else {
                scale = match.letter?.lowercased().hasPrefix("f") == true ? .fahrenheit : .celsius
            }
            let fan = match.leadFan != nil || match.trailFan != nil
            atoms.append(Atom(range: match.range, temperature: Temperature(value, scale, fan: fan)))
        }
        for match in text.matches(of: gas) {
            guard let mark = rational(fromMixedNumber: match.mark) else { continue }
            let fan = match.leadFan != nil || match.trailFan != nil
            atoms.append(Atom(range: match.range, temperature: Temperature(mark, .gasMark, fan: fan)))
        }
        for match in text.matches(of: descriptive) {
            let key = match.words.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard let mark = descriptions[key] else { continue }
            atoms.append(Atom(range: match.range, temperature: Temperature(mark, .gasMark)))
        }
        atoms.sort { $0.range.lowerBound < $1.range.lowerBound }
        // Keep the earliest of any overlapping pair.
        var kept: [Atom] = []
        for atom in atoms where kept.last.map({ $0.range.upperBound <= atom.range.lowerBound }) ?? true {
            kept.append(atom)
        }
        return kept
    }

    /// "350" → 350, "176.5" → 353/2. Nil for anything too long to hold exactly.
    static func rational(fromDecimal text: Substring) -> Rational? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, parts[0].count <= 9, let whole = Int(parts[0]) else { return nil }
        guard parts.count == 2 else { return Rational(whole) }
        guard parts[1].count <= 6, let fraction = Int(parts[1]) else { return nil }
        var scale = 1
        for _ in 0..<parts[1].count { scale *= 10 }
        return Rational(whole) + Rational(fraction, scale)
    }

    /// A mixed number as recipes write one: "6" → 6, "½" → 1/2, "6½" → 13/2, "1 ½" → 3/2,
    /// "1/2" → 1/2, "6 1/2" → 13/2, "6.5" → 13/2. Shared with ``DurationParser``.
    static func rational(fromMixedNumber text: Substring) -> Rational? {
        let glyphs: [Character: Rational] = [
            "½": Rational(1, 2), "¼": Rational(1, 4), "¾": Rational(3, 4),
            "⅓": Rational(1, 3), "⅔": Rational(2, 3),
            "⅛": Rational(1, 8), "⅜": Rational(3, 8), "⅝": Rational(5, 8), "⅞": Rational(7, 8),
        ]
        var remainder = text.trimmingCharacters(in: .whitespaces)
        var fraction: Rational = .zero
        if let last = remainder.last, let glyph = glyphs[last] {
            fraction = glyph
            remainder.removeLast()
        } else if let slash = remainder.lastIndex(of: "/") {
            let start = remainder[..<slash].lastIndex(where: \.isWhitespace).map { remainder.index(after: $0) } ?? remainder.startIndex
            guard let numerator = Int(remainder[start..<slash]),
                  let denominator = Int(remainder[remainder.index(after: slash)...]), denominator != 0 else { return nil }
            fraction = Rational(numerator, denominator)
            remainder = String(remainder[..<start])
        }
        remainder = remainder.trimmingCharacters(in: .whitespaces)
        guard !remainder.isEmpty else { return fraction }
        guard let whole = rational(fromDecimal: Substring(remainder)) else { return nil }
        return whole + fraction
    }

    /// Grows `range` over a closing parenthesis it opened, or an opening one it closes, so
    /// "180°C (350°F)" is one mention including the ")".
    static func balancingParentheses(_ range: Range<String.Index>, in text: String) -> Range<String.Index> {
        var range = range
        while true {
            let inside = text[range]
            let opens = inside.filter { $0 == "(" }.count
            let closes = inside.filter { $0 == ")" }.count
            if opens > closes, let next = text[range.upperBound...].firstIndex(where: { !$0.isWhitespace }), text[next] == ")" {
                range = range.lowerBound..<text.index(after: next)
            } else if closes > opens, let previous = text[..<range.lowerBound].lastIndex(where: { !$0.isWhitespace }), text[previous] == "(" {
                range = previous..<range.upperBound
            } else {
                return range
            }
        }
    }
}

extension Temperature {
    /// The first alternative of a temperature spelling such as "350°F" or "gas mark 6";
    /// see ``TemperatureParser``.
    public init?(parsing text: String) {
        guard let parsed = TemperatureParser.parse(text) else { return nil }
        self = parsed.primary
    }
}
