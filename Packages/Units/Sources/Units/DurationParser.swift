import Foundation

/// A duration as a recipe wrote it: a single value or a range ("8–10 minutes", "45 minutes to
/// 1 hour"), with the original words so the app can keep them alongside.
///
/// A single value is held in `lower`, a range in `lower` and `upper`; ``duration`` reads the
/// low end either way, which is what a timer started from "8–10 minutes" should count down from.
public struct ParsedDuration: Hashable, Sendable, Codable {
    /// The duration, or the low end when the text gives a range.
    public var lower: CookingDuration
    /// The high end of a range; nil for a single value.
    public var upper: CookingDuration?
    /// The exact text that was parsed, as written.
    public var originalText: String
    /// How the text spelled `lower`, so that formatting follows the recipe.
    var lowerSpelling: Spelling
    /// How the text spelled `upper`; nil for a single value.
    var upperSpelling: Spelling?

    /// A duration made in code rather than read from text; it formats in whole hours, minutes and
    /// seconds, as ``CookingDuration/formatted(style:)`` does.
    public init(lower: CookingDuration, upper: CookingDuration? = nil, originalText: String) {
        self.init(lower: lower, upper: upper, originalText: originalText,
                  lowerSpelling: .canonical, upperSpelling: upper == nil ? nil : .canonical)
    }

    init(lower: CookingDuration, upper: CookingDuration?, originalText: String,
         lowerSpelling: Spelling, upperSpelling: Spelling?) {
        self.lower = lower
        self.upper = upper
        self.originalText = originalText
        self.lowerSpelling = lowerSpelling
        self.upperSpelling = upperSpelling
    }

    /// The duration a single value reads, and the low end of a range.
    public var duration: CookingDuration { lower }

    /// Whether the text gave two ends, as "8–10 minutes" does.
    public var isRange: Bool { upper != nil }

    /// Whether the text said "overnight", which ``DurationParser`` reads as 12 hours; a caller
    /// that would rather not start a 12-hour timer can tell from this.
    public var isOvernight: Bool { lowerSpelling == .overnight && upper == nil }

    /// How a value was spelled, kept so that formatting follows the recipe: "90 minutes" stays
    /// "90 min" rather than becoming "1 hr 30 min".
    enum Spelling: Hashable, Sendable, Codable {
        /// One number in one unit, fractions included: "12 minutes", "1½ hours", "90 seconds".
        case single(DurationUnit)
        /// Whole numbers in descending units, the largest named: "1 hour 30 minutes", "1h30".
        case compound(DurationUnit)
        /// The word "overnight".
        case overnight

        /// How a duration made in code is spelled: whole hours, minutes and seconds.
        static let canonical = Spelling.compound(.hours)
    }
}

/// A duration found inside a longer sentence, with where it sits so the app can put a pill in
/// its place.
public struct DurationMention: Hashable, Sendable {
    public var range: Range<String.Index>
    public var duration: ParsedDuration

    public init(range: Range<String.Index>, duration: ParsedDuration) {
        self.range = range
        self.duration = duration
    }

    /// The words the mention replaces, as written.
    public var originalText: String { duration.originalText }
}

/// Reads the durations recipes write.
///
/// Single values: "12 minutes", "12 min", "12 mins", "12m", "1 hour", "1 hr", "1 h", "90 seconds",
/// "45 sec", "2 days"; fractions and decimals: "1½ hours", "1 1/2 hours", "1.5 hours", "½ hour";
/// compounds: "1 hr 30 min", "1 hour and 30 minutes", "1h30", "1h30m", "1m30s", and "1:30 hours"
/// or "2:30 minutes" when a time word follows the colon; words: "five minutes", "twenty-five
/// minutes", "two and a half hours", "an hour", "a minute", "half an hour", "an hour and a half",
/// "another minute"; adjectives: "a 20-minute rest", "a 20 minute rest"; and "overnight".
/// Ranges keep both ends: "8–10 minutes", "8-10 min", "8 to 10 minutes", "5 or 6 minutes",
/// "between 8 and 10 minutes", "1 to 1½ hours", "45 minutes to 1 hour", "a minute or two".
///
/// Words that qualify the amount are part of the mention, so a pill replaces the whole run:
/// "about 20 minutes", "at least an hour", "up to 2 days", "another 5 minutes", "5 more minutes",
/// "10 minutes longer", "20 minutes or so". Prepositions are not: in "simmer for 20 minutes" the
/// mention is "20 minutes".
///
/// Like ``UnitParser`` and ``TemperatureParser`` it never guesses. A bare number is not a
/// duration, nor is "a few minutes", "a couple of minutes" or "several hours". "2 C" is two cups.
/// "12 m" with a space is not twelve minutes (only "12m" attached is), and a lone "30s" is not
/// thirty seconds (only "1m30s" is). "1:30" alone is a clock time. "last-minute" and "second
/// bowl" have no number, "a second" is an ordinal, "2 day-old bread" is an age, and
/// "overnight oats" is a dish. Matching ignores case.
///
/// "overnight" is read as 12 hours, ``CookingDuration/overnight``, so that a timer can be started
/// from it; ``ParsedDuration/isOvernight`` says when that happened, and formatting keeps the word.
public struct DurationParser: Hashable, Sendable, Codable {
    public init() {}

    /// The whole of `text`, give or take whitespace, punctuation, parentheses and a leading
    /// "for", as a duration.
    public func parse(_ text: String) -> ParsedDuration? {
        DurationParser.parse(text)
    }

    /// The whole of `text`, give or take whitespace, punctuation, parentheses and a leading
    /// "for", as a duration.
    public static func parse(_ text: String) -> ParsedDuration? {
        let found = mentions(in: text)
        guard found.count == 1, let mention = found.first else { return nil }
        let leftover = text[..<mention.range.lowerBound] + text[mention.range.upperBound...]
        let ignorable = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".,;:()"))
        let words = String(String.UnicodeScalarView(leftover.unicodeScalars.filter { !ignorable.contains($0) })).lowercased()
        guard words.isEmpty || words == "for" else { return nil }
        return mention.duration
    }

    /// Every duration in `text`, in order, each with its range. "Bake 1 hour 15 minutes, then
    /// rest 10 to 15 minutes" has two mentions, "1 hour 15 minutes" and "10 to 15 minutes".
    public func mentions(in text: String) -> [DurationMention] {
        DurationParser.mentions(in: text)
    }

    /// Every duration in `text`, in order, each with its range; see the instance method.
    public static func mentions(in text: String) -> [DurationMention] {
        let compounded = compounds(of: atoms(in: text), in: text)
        return ranges(of: compounded, in: text).map { atom in
            let parsed = ParsedDuration(lower: atom.lower, upper: atom.upper, originalText: String(text[atom.range]),
                                        lowerSpelling: atom.lowerSpelling, upperSpelling: atom.upperSpelling)
            return DurationMention(range: atom.range, duration: parsed)
        }
    }

    // MARK: - Atoms

    /// One duration term in the text, before compounds and two-sided ranges are joined.
    struct Atom {
        var range: Range<String.Index>
        var lower: CookingDuration
        var upper: CookingDuration?
        var lowerSpelling: ParsedDuration.Spelling
        var upperSpelling: ParsedDuration.Spelling?
        /// The largest and smallest unit written; nil for "overnight".
        var largestUnit: DurationUnit?
        var smallestUnit: DurationUnit?
    }

    // MARK: Grammar

    /// Unicode fractions a number may end in.
    static let vulgar = #"[½¼¾⅓⅔⅛⅜⅝⅞]"#

    /// "one" through "ninety-nine" as recipes spell them, without "hundred".
    static let numberWord: String = {
        let ones = "one|two|three|four|five|six|seven|eight|nine"
        let teens = "ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen"
        let tens = "twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety"
        // Atomic, so that "twenty-five" is never given up as "twenty" and a hyphen range to "five".
        return #"(?>(?:\#(tens))(?:[-\s](?:\#(ones)))?|\#(teens)|\#(ones))"#
    }()

    /// A count of units: digits with an optional fraction ("12", "1.5", "1½", "1 ½", "1 1/2",
    /// "1-1/2", "½", "1/2"), a number word, "half an hour", or an article standing for one ("an
    /// hour", "a minute", "another minute"); any of them may take "and a half" or "and a quarter".
    static let number = #"""
    (?:\b(?:a\s+)?half(?:\s+an?)?(?![a-z])|\b\d+\s?\#(vulgar)|\b\d+(?:\s+|-)\d+/\d+|\b\d+/\d+|\b\d+(?:\.\d+)?|\#(vulgar)|\b\#(numberWord)(?![a-z])|\banother(?![a-z])|\ban?(?![a-z]))(?:\s+and\s+a\s+(?:half|quarter)(?![a-z]))?
    """#

    /// Words before the number that qualify the amount and belong in the mention.
    static let qualifier = #"(?:about|approximately|approx\.?|around|roughly|nearly|almost|at\s+least|at\s+most|up\s+to|no\s+more\s+than|no\s+longer\s+than|(?:just\s+)?under|just\s+over|another|an?\s+additional|a\s+further|an?\s+extra|a\s+good|a\s+full|a\s+generous)"#

    /// Words between the number and the unit: "5 more minutes", "a full hour".
    static let midWord = #"(?:more|additional|extra|further|full|good|generous|whole|solid|scant)"#

    /// A unit word after optional space or a hyphen ("12 minutes", "20-minute", "1h"), or "m"
    /// attached to the digits ("12m"). Never followed by a letter, so "5 ml" and "2 hot" stay
    /// what they are, nor by "old": "2 day-old" is an age.
    static let unit = #"(?:(?:\s*|-)(?:hours?|hrs?|h|minutes?|mins?|seconds?|secs?|days?)|m)(?![a-z])(?![\s-]*old\b)"#

    /// A low end and connector before the main number: "8–10", "8 to 10", "5 or 6", "between 8 and
    /// 10", "from 8 to 10". A hyphen before a fraction is a mixed number ("1-1/2"), not a range, and
    /// "and" before "a half" belongs to the number ("two and a half").
    static let rangeLead = #"(?:(?<leadWord>between|from)\s+)?(?<low>\#(number))(?<connector>\s*(?:[–—]|-(?!\d+/))\s*|\s+(?:to|or|and)\s+(?!a\s+(?:half|quarter)\b))"#

    /// A duration term: qualifiers, an optional low end, the number, the unit and trailing words.
    static let termPattern = #"(?<prefix>(?:\#(qualifier)\s+){0,2})(?:\#(rangeLead))?(?<main>\#(number))(?<mid>\s+\#(midWord))?(?<unit>\#(unit))(?<trail>(?:\s+and\s+a\s+(?:half|quarter)(?![a-z]))?(?:\s+(?:more|longer|or\s+so)(?![a-z]))?)(?<orTwo>\s+or\s+two(?![\s-]*[a-z]))?"#

    // `Regex` is not `Sendable`, but these are immutable once built and matching does not
    // mutate them, so sharing them across threads is safe.

    nonisolated(unsafe) static let term = regex(termPattern)

    /// "1h30", "1h30m", "1h30m15s", "1hr30min": hours, minutes and optional seconds run together.
    nonisolated(unsafe) static let compactHours = regex(#"\b(?<hours>\d+)h(?:rs?)?(?<minutes>[0-5]?\d)(?:m(?:ins?)?(?:(?<seconds>[0-5]?\d)s(?:ecs?)?)?)?(?![a-z\d])"#)

    /// "1m30s", "1min30sec": minutes and seconds run together.
    nonisolated(unsafe) static let compactMinutes = regex(#"\b(?<minutes>\d+)m(?:ins?)?(?<seconds>[0-5]?\d)s(?:ecs?)?(?![a-z\d])"#)

    /// "1:30 hours" is an hour and a half, "2:30 minutes" two and a half minutes; without the
    /// time word a colon form is a clock time and is left alone.
    nonisolated(unsafe) static let clock = regex(#"\b(?<first>\d{1,2}):(?<second>[0-5]\d)(?!\d)(?:\s*|-)(?<unit>hours?|hrs?|h|minutes?|mins?)(?![a-z])"#)

    nonisolated(unsafe) static let overnight = regex(#"\bovernight\b"#)

    /// Words that may follow "overnight" when it is a duration ("overnight in the fridge",
    /// "overnight or up to 2 days"); any other word makes it an adjective, as in "overnight oats".
    static let overnightFollowers: Set<String> = [
        "in", "at", "or", "and", "to", "if", "so", "then", "before", "until", "till", "for", "with", "on",
        "while", "is", "as", "but", "the", "a", "an", "covered", "uncovered", "preferably", "ideally",
        "up", "would", "will", "works", "when", "after", "though", "which", "where",
    ]

    /// What may sit between the parts of a compound: "1 hour 30 minutes", "1 hour and 30 minutes",
    /// "1hr30min".
    nonisolated(unsafe) static let compoundGlue = regex(#"\s*(?:and\s+)?"#)

    /// What joins the two ends of a range: "45 minutes to 1 hour", "1 – 2 hours", "10 minutes or
    /// up to 1 hour", "2 hours, or overnight", "between 1 and 2 hours".
    nonisolated(unsafe) static let rangeGlue = regex(#"(?:\s*[–—-]\s*|\s+(?:to|and)\s+|,?\s+or\s+)(?:\#(qualifier)\s+)?"#)

    /// "between" or "from" just before the low end of a two-sided range.
    nonisolated(unsafe) static let rangeLeadWord = regex(#"\b(?<word>between|from)\s+$"#)

    static func regex(_ pattern: String) -> Regex<AnyRegexOutput> {
        do {
            return try Regex(pattern).ignoresCase()
        } catch {
            fatalError("DurationParser grammar does not compile: \(error)")
        }
    }

    // MARK: Finding atoms

    static func atoms(in text: String) -> [Atom] {
        var atoms: [Atom] = []
        for match in text.matches(of: term) {
            if let atom = atom(from: match, in: text) { atoms.append(atom) }
        }
        for match in text.matches(of: compactHours) {
            guard let hours = match.capture("hours").flatMap(TemperatureParser.rational(fromDecimal:)),
                  let minutes = match.capture("minutes").flatMap(TemperatureParser.rational(fromDecimal:)) else { continue }
            let seconds = match.capture("seconds").flatMap(TemperatureParser.rational(fromDecimal:)) ?? .zero
            let total = CookingDuration(hours, .hours) + CookingDuration(minutes, .minutes) + CookingDuration(seconds, .seconds)
            atoms.append(Atom(range: match.range, lower: total, lowerSpelling: .compound(.hours),
                              largestUnit: .hours, smallestUnit: match.capture("seconds") == nil ? .minutes : .seconds))
        }
        for match in text.matches(of: compactMinutes) {
            guard let minutes = match.capture("minutes").flatMap(TemperatureParser.rational(fromDecimal:)),
                  let seconds = match.capture("seconds").flatMap(TemperatureParser.rational(fromDecimal:)) else { continue }
            let total = CookingDuration(minutes, .minutes) + CookingDuration(seconds, .seconds)
            atoms.append(Atom(range: match.range, lower: total, lowerSpelling: .compound(.minutes),
                              largestUnit: .minutes, smallestUnit: .seconds))
        }
        for match in text.matches(of: clock) {
            guard let first = match.capture("first").flatMap(TemperatureParser.rational(fromDecimal:)),
                  let second = match.capture("second").flatMap(TemperatureParser.rational(fromDecimal:)),
                  let unit = match.capture("unit").flatMap(durationUnit(from:)) else { continue }
            let smaller: DurationUnit = unit == .hours ? .minutes : .seconds
            let total = CookingDuration(first, unit) + CookingDuration(second, smaller)
            guard total.seconds > .zero else { continue }
            atoms.append(Atom(range: match.range, lower: total, lowerSpelling: .compound(unit),
                              largestUnit: unit, smallestUnit: smaller))
        }
        for match in text.matches(of: overnight) where isDuration(overnightAt: match.range, in: text) {
            atoms.append(Atom(range: match.range, lower: .overnight, lowerSpelling: .overnight))
        }
        // Earliest first; of two starting together the longer wins, and overlaps are dropped.
        atoms.sort {
            $0.range.lowerBound != $1.range.lowerBound
                ? $0.range.lowerBound < $1.range.lowerBound
                : $0.range.upperBound > $1.range.upperBound
        }
        var kept: [Atom] = []
        for atom in atoms where kept.last.map({ $0.range.upperBound <= atom.range.lowerBound }) ?? true {
            kept.append(atom)
        }
        return kept
    }

    /// The atom for one match of ``term``, or nil when the words turn out not to be a duration.
    static func atom(from match: Regex<AnyRegexOutput>.Match, in text: String) -> Atom? {
        guard let mainText = match.capture("main"), let unitText = match.capture("unit"),
              let unit = durationUnit(from: unitText),
              var value = number(from: mainText), value > .zero else { return nil }
        // "a second bowl", "a second time": an ordinal, not one second.
        if unit == .seconds, isArticle(mainText) { return nil }
        if let trail = match.capture("trail")?.lowercased() {
            if trail.contains("half") { value += Rational(1, 2) }
            if trail.contains("quarter") { value += Rational(1, 4) }
        }
        var start = match.range.lowerBound
        var end = match.range.upperBound
        var lower = CookingDuration(value, unit)
        var upper: CookingDuration?
        if let low = match.capture("low") {
            let connector = match.capture("connector")?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
            let leadWord = match.capture("leadWord")?.lowercased()
            let allowed = connector != "and" || leadWord == "between"
            if allowed, let lowValue = number(from: low), lowValue > .zero, lowValue < value {
                lower = CookingDuration(lowValue, unit)
                upper = CookingDuration(value, unit)
            } else {
                // "8 and 10 minutes" without "between", or a low end that is not lower: the
                // leading number is something else, and so are the qualifiers before it.
                start = mainText.startIndex
            }
        }
        if let orTwo = match.capture("orTwo") {
            if upper == nil, value == 1 {
                upper = CookingDuration(2, unit)
            } else {
                end = orTwo.startIndex
            }
        }
        return Atom(range: start..<end, lower: lower, upper: upper,
                    lowerSpelling: .single(unit), upperSpelling: upper == nil ? nil : .single(unit),
                    largestUnit: unit, smallestUnit: unit)
    }

    /// "overnight" is a duration unless a word that makes it an adjective follows ("overnight
    /// oats", "an overnight rise"); punctuation, the end of the text and function words are fine.
    static func isDuration(overnightAt range: Range<String.Index>, in text: String) -> Bool {
        let after = text[range.upperBound...].drop(while: { $0 == " " || $0 == "\t" })
        guard let first = after.first, first.isLetter else { return true }
        let word = after.prefix(while: \.isLetter).lowercased()
        return overnightFollowers.contains(word)
    }

    // MARK: Joining atoms

    /// Adjacent atoms in descending units become one compound: "1 hour" "30 minutes" is 1½ hours
    /// written as hours and minutes.
    static func compounds(of atoms: [Atom], in text: String) -> [Atom] {
        var result: [Atom] = []
        for atom in atoms {
            if var previous = result.last, canCompound(previous, with: atom, in: text) {
                previous.range = previous.range.lowerBound..<atom.range.upperBound
                previous.lower = previous.lower + atom.lower
                previous.lowerSpelling = .compound(previous.largestUnit ?? .hours)
                previous.smallestUnit = atom.smallestUnit
                result[result.count - 1] = previous
            } else {
                result.append(atom)
            }
        }
        return result
    }

    static func canCompound(_ previous: Atom, with next: Atom, in text: String) -> Bool {
        guard previous.upper == nil, next.upper == nil,
              let smallest = previous.smallestUnit, let largest = next.largestUnit, largest < smallest,
              case .single = next.lowerSpelling else { return false }
        let glue = text[previous.range.upperBound..<next.range.lowerBound]
        guard glue.isEmpty || glue.wholeMatch(of: compoundGlue) != nil else { return false }
        // "between 1 hour and 30 minutes" is a range, however odd, not an hour and a half.
        if glue.lowercased().contains("and"), text[..<previous.range.lowerBound].firstMatch(of: rangeLeadWord) != nil {
            return false
        }
        return true
    }

    /// Two single values joined by a range connector become one range: "45 minutes to 1 hour",
    /// "between 1 and 2 hours", "8 hours or overnight".
    static func ranges(of atoms: [Atom], in text: String) -> [Atom] {
        var result: [Atom] = []
        var index = 0
        while index < atoms.count {
            if index + 1 < atoms.count, let joined = range(from: atoms[index], to: atoms[index + 1], in: text) {
                result.append(joined)
                index += 2
            } else {
                result.append(atoms[index])
                index += 1
            }
        }
        return result
    }

    static func range(from low: Atom, to high: Atom, in text: String) -> Atom? {
        guard low.upper == nil, high.upper == nil, low.lower < high.lower else { return nil }
        let glue = text[low.range.upperBound..<high.range.lowerBound]
        guard glue.wholeMatch(of: rangeGlue) != nil else { return nil }
        let leadWord = text[..<low.range.lowerBound].firstMatch(of: rangeLeadWord)
        let isAnd = glue.lowercased().split(whereSeparator: \.isWhitespace).first == "and"
        if isAnd, leadWord?.capture("word")?.lowercased() != "between" { return nil }
        let start = leadWord?.range.lowerBound ?? low.range.lowerBound
        return Atom(range: start..<high.range.upperBound, lower: low.lower, upper: high.lower,
                    lowerSpelling: low.lowerSpelling, upperSpelling: high.lowerSpelling,
                    largestUnit: low.largestUnit, smallestUnit: low.smallestUnit)
    }

    // MARK: Reading the pieces

    /// Number words recipes use, "one" through "ninety"; "twenty-five" is the sum of its words.
    static let numberWords: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
        "seventeen": 17, "eighteen": 18, "nineteen": 19,
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]

    /// The value of a ``number`` match: "12" → 12, "1½" → 3/2, "1-1/2" → 3/2, "twenty-five" → 25,
    /// "two and a half" → 5/2, "half an hour"'s "half an" → 1/2, "an" → 1, "another" → 1.
    static func number(from text: Substring) -> Rational? {
        var words = text.lowercased().split(whereSeparator: { $0.isWhitespace || $0 == "-" }).map(String.init)
        var extra: Rational = .zero
        if words.count >= 3, words[words.count - 3] == "and", words[words.count - 2] == "a" {
            switch words[words.count - 1] {
            case "half": extra = Rational(1, 2)
            case "quarter": extra = Rational(1, 4)
            default: return nil
            }
            words.removeLast(3)
        }
        guard let first = words.first else { return nil }
        if first.first?.isNumber == true {
            guard let value = TemperatureParser.rational(fromMixedNumber: Substring(words.joined(separator: " "))) else { return nil }
            return value + extra
        }
        if words.contains("half") {
            guard words.allSatisfy({ ["half", "a", "an"].contains($0) }) else { return nil }
            return Rational(1, 2) + extra
        }
        if words == ["a"] || words == ["an"] || words == ["another"] { return 1 + extra }
        var total = 0
        for word in words {
            guard let value = numberWords[word] else { return nil }
            total += value
        }
        return Rational(total) + extra
    }

    static func isArticle(_ text: Substring) -> Bool {
        let word = text.lowercased().trimmingCharacters(in: .whitespaces)
        return word == "a" || word == "an"
    }

    /// The unit a ``unit`` match names, from its first letter: "hours", "hr" and "h" are hours.
    static func durationUnit(from text: Substring) -> DurationUnit? {
        let word = text.lowercased().trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "-")))
        switch word.first {
        case "h": return .hours
        case "m": return .minutes
        case "s": return .seconds
        case "d": return .days
        default: return nil
        }
    }
}

extension Regex.Match where Output == AnyRegexOutput {
    /// The text a named capture matched, or nil when the group did not take part.
    func capture(_ name: String) -> Substring? {
        output[name]?.substring
    }
}

extension CookingDuration {
    /// The duration, or the low end of a range, in a spelling such as "12 minutes" or "1½ hours";
    /// see ``DurationParser``.
    public init?(parsing text: String) {
        guard let parsed = DurationParser.parse(text) else { return nil }
        self = parsed.lower
    }
}
