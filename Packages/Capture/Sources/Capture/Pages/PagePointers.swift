import Foundation

/// A page pointer where it is printed in a recipe's text (04 §5.1 "Page pointers", ux-notes row
/// 74): "Dashi (see page 17)", "yama-imo, see page 253", "Herb Butter (page 214)", "(see Sources,
/// page 301)". The app draws the words as a pill and resolves the page at display time; the words
/// themselves never change.
public struct PagePointer: Sendable, Equatable {
    /// The words the pill covers: "see page 17", "page 214", "pages 31 and 97".
    public var range: Range<String.Index>
    /// The words as printed.
    public var text: String
    public var pages: [Int]
    /// What the pointer reads as: a recipe (a component), the book's Sources page, or a technique
    /// described elsewhere. Whether the page holds a recipe is the book's to say (its contents list,
    /// or a page scanned since).
    public var kind: PageCrossReference.Kind
    /// The name the text gives the thing pointed to ("Herb Butter"), when a capitalized name stands
    /// just before the parentheses.
    public var target: String?
    /// The name inside the parentheses beside the pointer's words ("yama-imo" in "(yama-imo, see
    /// page 253)"), for a recipe pointer with no capitalized name before them.
    public var name: String?

    public init(range: Range<String.Index>, text: String, pages: [Int], kind: PageCrossReference.Kind, target: String? = nil, name: String? = nil) {
        self.range = range
        self.text = text
        self.pages = pages
        self.kind = kind
        self.target = target
        self.name = name
    }

    /// The title a to-scan entry takes from the pointer (ux-notes row 102): the name before the
    /// parentheses ("Herb Butter"), else the name inside them ("Yama-imo"), else the ingredient it
    /// sits on without its size and count words ("Mountain yam"), else "Page 253".
    public func entryTitle(item: String? = nil) -> String {
        if let target, !target.isEmpty { return target }
        if let name, !name.isEmpty { return Self.capitalized(name) }
        if let item = item.map(PagePointers.itemName), !item.isEmpty { return Self.capitalized(item) }
        return "Page \(pages.first ?? 0)"
    }

    static func capitalized(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}

public enum PagePointers {
    /// Every pointer with a page number in `text`, in order. Photograph pointers ("photograph on page
    /// 6") are left out: the photo plate they name is attached as a cover, not opened.
    public static func find(in text: String) -> [PagePointer] {
        var found: [PagePointer] = []
        for match in text.matches(of: /(?i)\b(?:see\s+(?:also\s+)?)?pages?\s+(\d{1,3})(?:\s*(?:and|or|,|–|-|&)\s*(\d{1,3}))?\b/) {
            let pages = [match.output.1, match.output.2].compactMap { $0.flatMap { Int($0) } }
            guard !pages.isEmpty, !isPhotograph(before: match.range.lowerBound, in: text) else { continue }
            let context = parentheses(around: match.range, in: text)
            let words = (context.map { String(text[$0]) } ?? String(text[match.range])).lowercased()
            let kind: PageCrossReference.Kind
            if words.contains("sources") || words.contains("resources") {
                kind = .sources
            } else if words.range(of: #"\bsee\s+(also\s+)?pages?\s+\d+\s+for\b"#, options: .regularExpression) != nil
                        || words.contains("method") || words.contains("technique") {
                kind = .technique
            } else {
                kind = .recipe
            }
            let target = context.flatMap { PageCrossReferences.target(before: text.index(before: $0.lowerBound), in: text) }
            let name = kind == .recipe ? context.flatMap { parentheticalName(in: $0, pointer: match.range, text: text) } : nil
            found.append(PagePointer(range: match.range, text: String(text[match.range]), pages: pages, kind: kind, target: kind == .recipe ? target : nil, name: name))
        }
        return found
    }

    /// The words inside the parentheses other than the pointer's own: "yama-imo" in "(yama-imo, see
    /// page 253)", "Dashi" in "(or Dashi, page 17)". Nil when nothing but the pointer is there, or
    /// what is there runs to a clause.
    static func parentheticalName(in context: Range<String.Index>, pointer: Range<String.Index>, text: String) -> String? {
        let before = text[context.lowerBound..<pointer.lowerBound]
        let after = text[pointer.upperBound..<context.upperBound]
        var words = (before + " " + after).split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == ";" }).map(String.init)
        while let first = words.first, ["or", "and", "also", "see", "the", "a", "an", "i.e.", "i.e", "ie"].contains(first.lowercased()) { words.removeFirst() }
        while let last = words.last, ["or", "and", "see", "also"].contains(last.lowercased()) { words.removeLast() }
        guard (1...5).contains(words.count), words.contains(where: { $0.contains(where: \.isLetter) }) else { return nil }
        return words.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " ,;:."))
    }

    /// An ingredient without its size and count words ("12-inch piece of mountain yam" → "mountain
    /// yam", "2 large onions" → "onions"), for a to-scan entry's title.
    public static func itemName(_ item: String) -> String {
        var text = item.replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        var words = text.split(separator: " ").map(String.init)
        let counts: Set<String> = ["a", "an", "one", "two", "three", "four", "five", "six", "eight", "ten", "twelve", "about", "approximately", "roughly", "of"]
        let sizes: Set<String> = ["large", "small", "medium", "big", "little", "thick", "thin", "whole", "half", "long", "short", "wide"]
        let units: Set<String> = ["inch", "inches", "cm", "centimeter", "centimeters", "pound", "pounds", "lb", "lbs", "ounce", "ounces", "oz", "gram", "grams", "g", "kg", "kilo", "kilos", "piece", "pieces", "slice", "slices", "chunk", "chunks", "knob", "sprig", "sprigs", "bunch", "bunches", "head", "heads", "clove", "cloves", "stalk", "stalks", "length", "lengths", "section", "sections"]
        while let first = words.first {
            let lower = first.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ",.-"))
            let parts = lower.split(separator: "-").map(String.init)
            let measured = lower.first.map { $0.isNumber || "½¼¾⅓⅔⅛⅜⅝⅞".contains($0) } ?? false
            guard measured || counts.contains(lower) || sizes.contains(lower) || units.contains(lower) || parts.allSatisfy({ $0.first?.isNumber == true || units.contains($0) || sizes.contains($0) }) else { break }
            words.removeFirst()
        }
        return words.isEmpty ? text : words.joined(separator: " ")
    }

    /// The cross-references in a recipe's stored text (an ingredient line, a step, the headnote), as
    /// the structurer lists them for a fresh scan: for the cross-reference card on a recipe reviewed
    /// again, photographs left out.
    public static func crossReferences(in text: String) -> [PageCrossReference] {
        PageCrossReferences.find(in: text, kind: .recipe).filter { $0.kind != .photograph }
    }

    /// "PHOTOGRAPH ON " (or "photographs on ") just before the page words.
    private static func isPhotograph(before index: String.Index, in text: String) -> Bool {
        let before = text[..<index].suffix(20).lowercased()
        return before.range(of: #"photo(graph)?s?\s+on\s+$"#, options: .regularExpression) != nil
    }

    /// The inside of the parentheses the range sits in, when it does: "see Sources, page 301".
    private static func parentheses(around range: Range<String.Index>, in text: String) -> Range<String.Index>? {
        guard let open = text[..<range.lowerBound].lastIndex(of: "("),
              !text[open..<range.lowerBound].contains(")"),
              let close = text[range.upperBound...].firstIndex(of: ")"),
              !text[range.upperBound..<close].contains("(") else { return nil }
        return text.index(after: open)..<close
    }
}
