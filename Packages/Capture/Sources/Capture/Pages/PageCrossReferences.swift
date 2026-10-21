import Foundation

/// Finds pointers to other pages in a recipe's text (Flow B step 6): "(see page 88 for a
/// quicker method)", "Herb Butter (page 214)", "(see Sources, page 301)", "PHOTOGRAPH ON
/// PAGE 6", "PHOTOGRAPHS ON PAGES 31 AND 97". Listed, not resolved.
enum PageCrossReferences {
    static func find(in text: String, kind context: PageCrossReference.Kind? = nil) -> [PageCrossReference] {
        var found: [PageCrossReference] = []
        let lower = text.lowercased()
        // Photographs.
        for match in text.matches(of: /(?i)photographs?\s+on\s+pages?\s+(\d{1,3})(?:\s*(?:and|,|&)\s*(\d{1,3}))?/) {
            let pages = [match.output.1, match.output.2].compactMap { $0.flatMap { Int($0) } }
            found.append(PageCrossReference(kind: .photograph, phrase: String(text[match.range]), pages: pages))
        }
        // Parenthesized pointers: "(page 214)", "(see page 88 for…)", "(see Sources, page 301)", "(pages 31 and 32)".
        for match in text.matches(of: /\(([^()]{0,80}?\bpages?\s+(\d{1,3})(?:\s*(?:and|,|–|-|&)\s*(\d{1,3}))?[^()]{0,80})\)/) {
            let inside = String(match.output.1)
            let insideLower = inside.lowercased()
            let pages = [match.output.2, match.output.3].compactMap { $0.flatMap { Int($0) } }
            let kind: PageCrossReference.Kind
            if insideLower.contains("sources") || insideLower.contains("resources") {
                kind = .sources
            } else if insideLower.contains("photo") {
                kind = .photograph
            } else if insideLower.range(of: #"^see page \d+ for"#, options: .regularExpression) != nil
                        || insideLower.contains("method") || insideLower.contains("technique") {
                kind = .technique
            } else {
                kind = context ?? .recipe
            }
            let target = kind == .recipe ? Self.target(before: match.range.lowerBound, in: text) : nil
            found.append(PageCrossReference(kind: kind, phrase: String(text[match.range]), pages: pages, target: target))
        }
        // Bare "see page 84" outside parentheses.
        for match in text.matches(of: /(?i)\bsee\s+page\s+(\d{1,3})\b/) {
            let alreadyFound = found.contains { $0.phrase.lowercased().contains(String(text[match.range]).lowercased()) }
            guard !alreadyFound, let page = Int(match.output.1) else { continue }
            found.append(PageCrossReference(kind: context ?? .technique, phrase: String(text[match.range]), pages: [page]))
        }
        // "Aioli (recipe follows)", "2 cups Pickled Shallots (recipe below)": a component printed
        // on this page or the next, with no page number; the name before it says which.
        for match in text.matches(of: /(?i)\(\s*(?:the\s+)?recipes?\s+(?:follows?|below|opposite|on\s+the\s+(?:following|next|facing)\s+page)\s*\)/) {
            found.append(PageCrossReference(kind: .recipe, phrase: String(text[match.range]), pages: [], target: Self.target(before: match.range.lowerBound, in: text)))
        }
        _ = lower
        return found
    }

    /// The capitalized name just before a parenthesized page reference: "2 tablespoons Herb Butter
    /// (page 214)" → "Herb Butter"; "Chicken Stock (page 40)" → "Chicken Stock".
    static func target(before index: String.Index, in text: String) -> String? {
        let before = text[..<index].trimmingCharacters(in: .whitespaces)
        var words: [Substring] = []
        for word in before.split(separator: " ").reversed() {
            guard let first = word.first, first.isUppercase || (["de", "and", "with", "à", "la", "of"].contains(word) && !words.isEmpty) else { break }
            words.insert(word, at: 0)
            if words.count >= 5 { break }
        }
        while let first = words.first, ["de", "and", "with", "à", "la", "of"].contains(first) { words.removeFirst() }
        let name = words.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: ",.;: "))
        return name.count >= 3 ? name : nil
    }
}
