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

    public init(range: Range<String.Index>, text: String, pages: [Int], kind: PageCrossReference.Kind, target: String? = nil) {
        self.range = range
        self.text = text
        self.pages = pages
        self.kind = kind
        self.target = target
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
            found.append(PagePointer(range: match.range, text: String(text[match.range]), pages: pages, kind: kind, target: kind == .recipe ? target : nil))
        }
        return found
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
