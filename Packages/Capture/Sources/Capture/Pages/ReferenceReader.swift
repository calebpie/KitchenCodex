import Foundation

/// Reads reference reading off a scanned page that holds no recipe (02 §4.2, 04 §5.1 "Page
/// pointers"): a glossary page whose entries are a term and its definition, a chapter opener or a
/// technique write-up with headings and prose, no ingredient list. Run by the structurer once a
/// page's blocks have their roles, so what a recipe would have claimed is known.
///
/// - A page with an ingredient run (two lines or more) is a recipe, never reference reading.
/// - A glossary is three or more term-and-definition pairs that make up most of the page: a term
///   set on its own line over its definition, a term and its definition on one line parted by a
///   colon or a dash ("Sumac — A tart red spice…"), or a term in capitals opening its paragraph
///   ("SUMAC A tart red spice…"). Each pair is a section headed by the term.
/// - A page with no title whose paragraphs read as instructions continues a recipe's method: it is
///   left for the stitcher. A titled page whose paragraphs read as instructions is a technique only
///   when its title says so ("How to…", "…Technique", "Making…"); otherwise it is a recipe whose
///   ingredients didn't read, which review takes.
/// - Any other prose of 300 characters or more is a chapter (or a technique, by its title), its
///   headings opening sections.
enum ReferenceReader {
    static let minimumCharacters = 300

    /// The page's reference reading, or nil when the page is a recipe, continues one, or holds too
    /// little prose. `blocks` carry the structurer's roles; `recipes` are what it read.
    static func read(blocks: [PageBlock], recipes: [PageRecipe], isContinuation: Bool) -> ImportedReference? {
        // An ingredient run makes a recipe; two short lines a glossary's columns happened to set
        // like one, under no title, do not (a glossary page from the phone read as a recipe's
        // continuation on them, slice 8).
        guard !recipes.contains(where: { $0.ingredients.count >= 3 || ($0.ingredients.count >= 2 && !$0.title.isEmpty) }) else { return nil }
        let content = blocks.filter { $0.kind != .photo && $0.role != .ignore && $0.role != .furniture && $0.role != .crossReference && $0.text.filter(\.isLetter).count >= 2 }
        guard content.reduce(0, { $0 + $1.characterCount }) >= minimumCharacters else { return nil }
        let furniture = blocks.filter { $0.role == .furniture }.map(\.text)

        if let glossary = glossary(in: content, furniture: furniture) ?? glossaryByLines(in: content) { return glossary }

        let headings = content.filter { isHeading($0) }
        let paragraphs = content.filter { !isHeading($0) && $0.text.count >= 20 }
        guard !paragraphs.isEmpty else { return nil }
        let instructions = paragraphs.count { PageLines.readsAsInstruction($0.text) }
        let instructionShare = Double(instructions) / Double(paragraphs.count)
        let title = headings.first.map { PageLines.titleText($0.text) } ?? recipes.first?.title ?? ""
        let technique = readsAsTechnique(title)
        if instructionShare >= 0.5 {
            // A method with no ingredients on this page: the page before holds them (a
            // continuation), or they didn't read (review's job). A technique says what it is.
            guard !title.isEmpty, technique, !isContinuation else { return nil }
        } else if isContinuation, headings.isEmpty, recipes.first?.title.isEmpty == true, instructionShare >= 0.3 {
            return nil
        }

        // Sections: each heading opens one; the first heading is the title.
        var sections = [ImportedReference.Section(body: "")]
        var parts: [[String]] = [[]]
        var titleBlock: Int?
        for block in content {
            if isHeading(block) {
                if titleBlock == nil, PageLines.titleText(block.text) == title {
                    titleBlock = block.id
                    continue
                }
                sections.append(ImportedReference.Section(heading: PageLines.titleText(block.text), body: ""))
                parts.append([])
            } else if block.text.count >= 20 {
                parts[parts.count - 1].append(block.text)
            }
        }
        for index in sections.indices { sections[index].body = parts[index].joined(separator: "\n\n") }
        sections.removeAll { $0.body.isEmpty }
        guard sections.reduce(0, { $0 + $1.body.count }) >= minimumCharacters else { return nil }
        let kind: ImportedReference.Kind = technique ? .technique : .chapter
        let count = paragraphs.count == 1 ? "1 paragraph" : "\(paragraphs.count) paragraphs"
        return ImportedReference(
            title: title,
            kind: kind,
            sections: sections,
            reason: technique ? "a technique: \(count), no ingredient list" : "a chapter opener: \(count) of prose, no ingredient list",
            confidence: 0.6
        )
    }

    /// A heading: a block the structurer called a title, or a short heading-sized block nothing claimed.
    static func isHeading(_ block: PageBlock) -> Bool {
        if block.role == .title { return true }
        return block.kind == .heading && block.role == nil && block.lines.count <= 2 && block.text.count <= 60 && block.text.first?.isUppercase == true
    }

    /// "How to Fillet a Flat Fish", "The Braising Technique", "Making Stock", "Notes on Knives".
    static func readsAsTechnique(_ title: String) -> Bool {
        let lower = title.lowercased()
        if lower.range(of: #"\b(how to|technique|techniques|method|methods|basics|the basics|guide|primer|notes? on|a word on|a note on|about)\b"#, options: .regularExpression) != nil { return true }
        guard let first = lower.split(separator: " ").first else { return false }
        return first.count >= 6 && first.hasSuffix("ing") && !["something", "nothing", "evening", "morning", "spring", "during"].contains(String(first))
    }

    // MARK: - Glossary

    struct Pair {
        var term: String
        var definition: [String]
        var blocks: Int
    }

    /// Term-and-definition pairs when they make the page: three or more, taking at least half of
    /// its blocks, their definitions mostly not instructions.
    static func glossary(in content: [PageBlock], furniture: [String]) -> ImportedReference? {
        var pairs: [Pair] = []
        var index = 0
        var consumed = 0
        while index < content.count {
            let block = content[index]
            if let (term, rest) = termAndDefinition(block.text), block.lines.count <= 4 {
                // The term and its definition in one block, parted by a colon, a dash or capitals.
                var pair = Pair(term: term, definition: [rest], blocks: 1)
                index += 1
                while index < content.count, continuesDefinition(content[index], after: content[index - 1]) {
                    pair.definition.append(content[index].text)
                    pair.blocks += 1
                    index += 1
                }
                pairs.append(pair)
                consumed += pair.blocks
                continue
            }
            if block.lines.count == 1, isTerm(block.text), index + 1 < content.count, isDefinition(content[index + 1], under: block) {
                // The term on its own line over its definition.
                var pair = Pair(term: block.text, definition: [content[index + 1].text], blocks: 2)
                index += 2
                while index < content.count, continuesDefinition(content[index], after: content[index - 1]) {
                    pair.definition.append(content[index].text)
                    pair.blocks += 1
                    index += 1
                }
                pairs.append(pair)
                consumed += pair.blocks
                continue
            }
            index += 1
        }
        guard pairs.count >= 3, consumed * 2 >= content.count else { return nil }
        let instructions = pairs.count { PageLines.readsAsInstruction($0.definition[0]) }
        guard Double(instructions) < Double(pairs.count) * 0.4 else { return nil }
        let sections = pairs.map { ImportedReference.Section(heading: termText($0.term), body: $0.definition.joined(separator: "\n\n")) }
        let terms = Set(pairs.map(\.term))
        let heading = content.first { block in isHeading(block) && !terms.contains(block.text) }.map { PageLines.titleText($0.text) }
        let title = heading.flatMap { $0.count <= 40 ? $0 : nil }
            ?? (furniture.contains { $0.lowercased().contains("glossary") } ? "Glossary" : "Glossary")
        return ImportedReference(
            title: title,
            kind: .glossary,
            sections: sections,
            reason: "a glossary page: \(pairs.count) entries",
            confidence: 0.6
        )
    }

    // MARK: - Glossary, line by line

    struct Line {
        var text: String
        var rect: PageRect
        var block: Int
        var isHeading: Bool
    }

    /// A glossary set as terms on their own lines over their definitions, in columns, the way the
    /// recognizer often runs a term into the paragraph before or after it: read line by line. A
    /// term line is short against its column's lines, a few words with no sentence end, after a
    /// line that ends one (or at a column's top), and before a line that starts one. Three or more
    /// terms that take most of the page's lines make it a glossary; each term's definition is the
    /// lines up to the next.
    static func glossaryByLines(in content: [PageBlock]) -> ImportedReference? {
        var lines: [Line] = []
        for block in content {
            for line in block.lines {
                let text = line.text.trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty else { continue }
                lines.append(Line(text: text, rect: line.rect, block: block.id, isHeading: block.role == .title && block.lines.count == 1 && lines.isEmpty))
            }
        }
        guard lines.count >= 8 else { return nil }
        let heading = lines.first(where: \.isHeading).map { PageLines.titleText($0.text) }
        let body = lines.filter { !$0.isHeading }
        // Each column's measure: the median width of its longer lines.
        let widths = body.map(\.rect.width).sorted()
        let measure = widths[widths.count * 3 / 4]
        var terms: [Int] = []
        for (index, line) in body.enumerated() {
            let words = line.text.split(whereSeparator: \.isWhitespace)
            guard (1...6).contains(words.count), line.text.count <= 48, line.text.filter(\.isLetter).count >= 2,
                  !(line.text.last.map { ".,;:!?".contains($0) } ?? false), line.rect.width <= measure * 0.65 else { continue }
            if case .strong = PageLines.ingredientShape(line.text), line.text.first?.isNumber == true { continue }
            guard index + 1 < body.count else { continue }
            let next = body[index + 1]
            let nextSameColumn = next.rect.horizontalOverlap(with: line.rect) > 0.3 && next.rect.minY > line.rect.minY
            guard nextSameColumn, let first = next.text.first, first.isUppercase || first == "(" || first.isNumber else { continue }
            if index > 0 {
                let previous = body[index - 1]
                let sameColumn = previous.rect.horizontalOverlap(with: line.rect) > 0.3 && previous.rect.minY < line.rect.minY
                if sameColumn, !(previous.text.last.map { ".)!?\"”".contains($0) } ?? false) { continue }
            }
            terms.append(index)
        }
        guard terms.count >= 3 else { return nil }
        var sections: [ImportedReference.Section] = []
        for (position, start) in terms.enumerated() {
            let end = position + 1 < terms.count ? terms[position + 1] : body.count
            let definition = PageText.join(body[(start + 1)..<end].map(\.text))
            guard !definition.isEmpty else { continue }
            sections.append(ImportedReference.Section(heading: termText(body[start].text), body: definition))
        }
        // The terms and their definitions make the page: little before the first term.
        guard sections.count >= 3, terms[0] * 4 <= body.count else { return nil }
        let instructions = sections.count { PageLines.readsAsInstruction($0.body) }
        guard Double(instructions) < Double(sections.count) * 0.4 else { return nil }
        return ImportedReference(
            title: heading.flatMap { $0.count <= 40 ? $0 : nil } ?? "Glossary",
            kind: .glossary,
            sections: sections,
            reason: "a glossary page: \(sections.count) entries",
            confidence: 0.55
        )
    }

    /// A term: a few words, capitalised, no sentence, no amount.
    static func isTerm(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let words = trimmed.split(whereSeparator: \.isWhitespace)
        guard (1...6).contains(words.count), trimmed.count <= 48, let first = trimmed.first, first.isLetter, !first.isLowercase else { return false }
        guard trimmed.filter(\.isLetter).count >= 2, !(trimmed.last.map { ".!?,;".contains($0) } ?? false) else { return false }
        if PageLines.isYield(trimmed) || PageLines.runInHead(trimmed) != nil || PageLines.isCrossReferenceLine(trimmed) { return false }
        if case .strong = PageLines.ingredientShape(trimmed) { return false }
        return !(PageLines.opensWithVerb(trimmed) && words.count >= 3)
    }

    /// A definition under its term: a paragraph of some length, just below it in the same column.
    static func isDefinition(_ block: PageBlock, under term: PageBlock) -> Bool {
        guard block.kind != .photo, block.text.count >= 20, !isTerm(block.text) || block.lines.count > 1 else { return false }
        guard block.rect.minY >= term.rect.minY, block.rect.horizontalOverlap(with: term.rect) > 0.3 else { return false }
        return block.rect.minY - term.rect.maxY < term.typeSize * 2.5
    }

    /// A further paragraph of the same definition: prose, not a term, close under the one before.
    static func continuesDefinition(_ block: PageBlock, after previous: PageBlock) -> Bool {
        guard block.kind != .photo, block.text.count >= 40, termAndDefinition(block.text) == nil else { return false }
        if block.lines.count == 1, isTerm(block.text) { return false }
        guard block.rect.minY >= previous.rect.minY, block.rect.horizontalOverlap(with: previous.rect) > 0.3 else { return false }
        return block.text.first?.isLowercase == true || block.rect.minY - previous.rect.maxY < previous.typeSize * 1.2
    }

    /// "Sumac: A tart red spice…", "Sumac — A tart red spice…", "SUMAC A tart red spice…": the term
    /// and what follows it.
    static func termAndDefinition(_ text: String) -> (String, String)? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let match = trimmed.firstMatch(of: /^([^:—–]{2,40}?)\s*[:—–]\s+(\S.{19,})$/) {
            let term = String(match.output.1)
            if isTerm(term), PageLines.runInHead(trimmed) == nil || term.filter(\.isLetter).count <= 20 { return (term, String(match.output.2)) }
        }
        if let match = trimmed.firstMatch(of: /^(\p{Lu}[\p{Lu}'’\-]*(?:\s+\p{Lu}[\p{Lu}'’\-]*){0,3})\s+(\p{Lu}?\p{Ll}.{15,})$/) {
            let term = String(match.output.1)
            if term.filter(\.isLetter).count >= 3, !["NOTE", "NOTES", "TIP", "TO SERVE", "TO FINISH"].contains(term) { return (term, String(match.output.2)) }
        }
        return nil
    }

    /// The term as the entry's heading: capitals in title case, a trailing colon gone.
    static func termText(_ term: String) -> String {
        var text = term.trimmingCharacters(in: .whitespaces)
        while text.hasSuffix(":") { text.removeLast() }
        return PageLines.titleText(text.trimmingCharacters(in: .whitespaces))
    }
}
