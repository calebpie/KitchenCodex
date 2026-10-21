import Foundation
import Intelligence

/// A book's contents as read off its contents pages (02 Flow C step 3): its chapters in order, each
/// with the page it starts on, and the recipe titles each lists with theirs. What the app turns
/// into the book's `BookSection`s and `BookEntry`s, the punchlist.
public struct BookContents: Sendable, Equatable {
    public struct Entry: Sendable, Equatable, Hashable {
        public var title: String
        public var page: Int?

        public init(title: String, page: Int? = nil) {
            self.title = title
            self.page = page
        }
    }

    public struct Section: Sendable, Equatable {
        /// Empty for entries before a page's first heading, which continue the page before.
        public var title: String
        /// The page the chapter starts on, when the contents prints it.
        public var page: Int?
        public var entries: [Entry]

        public init(title: String, page: Int? = nil, entries: [Entry] = []) {
            self.title = title
            self.page = page
            self.entries = entries
        }
    }

    public var sections: [Section]
    /// The page lists chapters with their first pages and no recipes, as a book's opening contents
    /// page often does before the detailed one.
    public var isOverview: Bool
    /// `.pageText` for the deterministic reading, `.model` once the on-device model read it.
    public var method: ImportMethod

    public init(sections: [Section] = [], isOverview: Bool = false, method: ImportMethod = .pageText) {
        self.sections = sections
        self.isOverview = isOverview
        self.method = method
    }

    public var entries: [Entry] { sections.flatMap(\.entries) }
    /// Entries with a page number: the ones a scan's page number can find.
    public var pagedEntryCount: Int { entries.count { $0.page != nil } }
}

/// Reads a contents page into chapters and `[title, page]` entries, deterministically (04 §1:
/// deterministic first, model second), from the reader's lines and where they sit:
///
/// - Entries are lines that end in a page number, with dotted leaders and the recognizer's digit
///   slips ("5l", "1OO") mended; a page number set in its own column is paired with the title on
///   its line. A number that would run backwards among its neighbours is a misreading, and the
///   entry keeps no page rather than a wrong one.
/// - A title wrapped onto a second line (the first ends on "with", "&" or a comma, the second is
///   indented, starts in lowercase, or sits closer than the entries do) is one entry.
/// - Chapter headings are lines set apart: larger than the entries, in capitals or in lowercase
///   where the entries are not, or, without a page number, with more space above than the entries
///   have. "Chapter One" and the page's own "Contents" are labels, not chapters; front and back
///   matter (an introduction, the index, acknowledgments) is dropped.
/// - Columns are read left to right. A page whose page numbers jump by six or more from one line
///   to the next lists chapters, not recipes (an overview): its lines become chapters with their
///   first pages, which the detailed pages fill in (`combine`).
/// - An index page's lines ("Leek soup, 16, 42") are entries too, by their first page, in one
///   section; they are worth less than a contents page's, so contents pages come first.
public enum ContentsReader {
    /// One page's reading. `reading` is the page pipeline's (`PagePipeline.readPage`): every block
    /// but noise is read, whatever kind the structurer made of the page.
    public static func read(_ reading: PageReading) -> BookContents {
        if reading.kind == .index { return readIndex(reading) }
        var lines = contentLines(of: reading)
        guard !lines.isEmpty else { return BookContents() }
        pairNumbers(&lines)
        let entrySize = Self.entrySize(lines)
        let columns = Self.columns(lines.filter { !$0.isNumberOnly })
        let paged = columns.flatMap { $0 }.filter { $0.page != nil }
        let overview = isOverview(paged.map { $0.page! })
        var sections: [BookContents.Section] = []
        let style = Style(lines: paged.isEmpty ? columns.flatMap { $0 } : paged, entrySize: entrySize)
        for column in columns {
            read(column, style: style, overview: overview, into: &sections)
        }
        return BookContents(sections: tidy(sections, overview: overview), isOverview: overview)
    }

    /// Whether the model should read the page too: the deterministic reading found few entries, or
    /// none with a page number. An overview page that read as chapters with pages is complete.
    public static func wantsModel(_ contents: BookContents) -> Bool {
        if contents.isOverview, contents.sections.contains(where: { $0.page != nil }) { return false }
        return contents.entries.count < 4 || contents.pagedEntryCount == 0
    }

    /// The model's reading of the page where the deterministic one falls short (`wantsModel`), kept
    /// only when it finds more entries with page numbers, in an order a contents page could print.
    public static func refine(_ contents: BookContents, page reading: PageReading, model: any PageStructuring) async -> BookContents {
        guard wantsModel(contents), model.isAvailable else { return contents }
        let text = modelText(of: reading)
        guard !text.isEmpty, let draft = try? await model.structureContents(pageText: text) else { return contents }
        let sections = draft.sections.map { section in
            BookContents.Section(
                title: cleanTitle(section.title),
                page: section.page,
                entries: section.entries.map { BookContents.Entry(title: cleanTitle($0.title), page: $0.page) }.filter { !$0.title.isEmpty }
            )
        }
        let pages = sections.flatMap(\.entries).compactMap(\.page)
        let candidate = BookContents(sections: tidy(sections, overview: false), isOverview: false, method: .model)
        // Pages a contents page could print: mostly rising, as the book runs.
        let rising = zip(pages, pages.dropFirst()).count { $0 <= $1 }
        guard candidate.pagedEntryCount > contents.pagedEntryCount, candidate.pagedEntryCount >= 2,
              Double(rising) >= Double(max(1, pages.count - 1)) * 0.7 else { return contents }
        return candidate
    }

    /// Several pages in the order photographed, as one contents: a section on a later page with the
    /// same title as one before (an overview's chapter and its detailed listing) is that section;
    /// entries before a page's first heading continue the section the page before ended on. Index
    /// pages come after the contents pages, and add only entries the contents pages lack.
    public static func combine(_ pages: [BookContents], indexPages: [BookContents] = []) -> BookContents {
        var sections: [BookContents.Section] = []
        var last: Int?
        for page in pages {
            for section in page.sections {
                if section.title.isEmpty, let index = last ?? sections.indices.last {
                    sections[index].entries += section.entries
                    last = index
                } else if let index = sections.firstIndex(where: { sameTitle($0.title, section.title) }) {
                    if sections[index].page == nil { sections[index].page = section.page }
                    if sections[index].title.count < section.title.count, !section.title.isEmpty { sections[index].title = section.title }
                    sections[index].entries += section.entries
                    last = index
                } else {
                    let at = last.map { $0 + 1 } ?? sections.count
                    sections.insert(section, at: at)
                    last = at
                }
            }
        }
        let listed = Set(sections.flatMap(\.entries).map { normalized($0.title) })
        let indexed = indexPages.flatMap(\.entries).filter { !listed.contains(normalized($0.title)) }
        if !indexed.isEmpty, sections.flatMap(\.entries).isEmpty {
            sections.append(BookContents.Section(title: "Index", entries: indexed))
        }
        let method: ImportMethod = pages.contains { $0.method == .model } ? .model : .pageText
        return BookContents(sections: sections, isOverview: !pages.isEmpty && pages.allSatisfy(\.isOverview), method: method)
    }

    // MARK: - Lines

    struct Line {
        var text: String
        var rect: PageRect
        var size: Double
        var page: Int?
        /// A page number set alone, in its own column.
        var isNumberOnly: Bool
        /// The trailing number was read through a digit slip ("5l"), so it must agree with its
        /// neighbours to count.
        var isMended = false
    }

    /// Every line of text off the page but noise, a price on a jacket flap and the page's own
    /// running foot ("contents"). The structurer's own noise marks are not used: a contents page
    /// printed white on black reads to it as a photo with text inside, so the reader judges noise
    /// itself, by the recognizer's confidence, a scrap with too few letters, or a sliver at the
    /// frame's edge.
    static func contentLines(of reading: PageReading) -> [Line] {
        reading.blocks.filter { $0.kind != .photo }.flatMap(\.lines).compactMap { line in
            let text = line.text.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty, !text.contains("$"), text.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
            let letters = text.count(where: \.isLetter)
            if line.confidence < 0.15 || (letters > 0 && letters < 3 && !text.contains(where: \.isNumber)) { return nil }
            if line.rect.width < 0.08, line.rect.minX < 0.03 || line.rect.maxX > 0.97 { return nil }
            if text.allSatisfy(\.isNumber), text.count <= 3 {
                return Line(text: text, rect: line.rect, size: line.size, page: Int(text), isNumberOnly: true)
            }
            var result = Line(text: text, rect: line.rect, size: line.size, page: nil, isNumberOnly: false)
            if let (title, page, mended) = trailingPage(text) {
                result.text = title
                result.page = page
                result.isMended = mended
            } else if let match = text.firstMatch(of: /^(.+?)\s+(?:[0-9IlOo|]{1,3}[A-Za-z?]?|[Il|])$/), match.output.0.split(separator: " ").last?.contains(where: \.isNumber) == true || "Il|".contains(text.last!) {
                // A page number the recognizer couldn't read ("3a"): the title without it.
                result.text = cleanTitle(String(match.output.1))
            } else {
                result.text = cleanTitle(text)
            }
            return result.text.contains(where: \.isLetter) ? result : nil
        }
    }

    /// The title and page number of "Leek Soup 16", "Leek Soup ........ 16", "Leek Soup · 16",
    /// "Leek Soup 5l" (a digit read as a letter, `mended`). Nil when the line doesn't end in one.
    static func trailingPage(_ text: String) -> (String, Int, mended: Bool)? {
        guard let match = text.firstMatch(of: /^(.+?)(?:\s*[.·•_]{2,}\s*|\s*…+\s*|\s+)([0-9IlOoUDSZB|]{1,3})\??$/) else { return nil }
        let token = String(match.output.2)
        let digits = token.filter(\.isNumber).count
        // A word of letters alone ("So") is no page number; capital I's alone ("III") are ones.
        guard digits > 0 || (token.count >= 2 && token.allSatisfy { "Il|".contains($0) }) else { return nil }
        let mapped = String(token.map { character -> Character in
            switch character {
            case "I", "l", "|": "1"
            case "O", "o", "U", "D": "0"
            case "S": "5"
            case "Z": "2"
            case "B": "8"
            default: character
            }
        })
        guard let page = Int(mapped), page > 0 else { return nil }
        let title = cleanTitle(String(match.output.1))
        guard !title.isEmpty else { return nil }
        return (title, page, digits < token.count)
    }

    /// A title as printed, with its leaders, separators and spare spaces gone.
    static func cleanTitle(_ text: String) -> String {
        var title = text.replacingOccurrences(of: #"[.·•…_]{2,}"#, with: " ", options: .regularExpression)
        title = title.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return title.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".·•…_-–—|,:;")))
    }

    /// Page numbers set in their own column go with the title on their line: the nearest title to
    /// their left whose middle is level with theirs. A number with no title beside it (the facing
    /// page's edge, a chapter's large numeral) is dropped.
    static func pairNumbers(_ lines: inout [Line]) {
        let body = median(lines.filter { !$0.isNumberOnly }.map(\.size)) ?? 0.012
        for index in lines.indices where lines[index].isNumberOnly {
            let number = lines[index]
            guard number.size < body * 1.6 else { lines[index].page = nil; continue }
            let candidates = lines.indices.filter { other in
                let title = lines[other]
                guard !title.isNumberOnly, title.page == nil, title.rect.maxX <= number.rect.minX + 0.01,
                      number.rect.minX - title.rect.maxX < 0.55 else { return false }
                return abs(title.rect.midY - number.rect.midY) < max(title.rect.height, number.rect.height) * 0.6
            }
            if let nearest = candidates.min(by: { number.rect.minX - lines[$0].rect.maxX < number.rect.minX - lines[$1].rect.maxX }) {
                lines[nearest].page = number.page
            }
            lines[index].page = nil
        }
    }

    /// The entries' type size: the median of the lines with a page number, else of every line.
    static func entrySize(_ lines: [Line]) -> Double {
        let text = lines.filter { !$0.isNumberOnly }
        let paged = text.filter { $0.page != nil }
        return median((paged.count >= 3 ? paged : text).map(\.size)) ?? 0.012
    }

    /// Lines grouped into columns by where they start across, left to right, each top to bottom. A
    /// column's indents and a page's tilt move a line's start a little; a gutter moves it a lot.
    static func columns(_ lines: [Line]) -> [[Line]] {
        let sorted = lines.sorted { $0.rect.minX < $1.rect.minX }
        var columns: [[Line]] = []
        var previous: Double?
        for line in sorted {
            if let previous, line.rect.minX - previous <= 0.10 {
                columns[columns.count - 1].append(line)
            } else {
                columns.append([line])
            }
            previous = line.rect.minX
        }
        return columns.map { $0.sorted { $0.rect.minY < $1.rect.minY } }
    }

    /// Page numbers that jump by six or more from one entry to the next: chapters, not recipes.
    static func isOverview(_ pages: [Int]) -> Bool {
        guard pages.count >= 3, pages.count <= 30 else { return false }
        let gaps = zip(pages, pages.dropFirst()).map { abs($1 - $0) }
        return (median(gaps.map(Double.init)) ?? 0) >= 6
    }

    // MARK: - Reading a column

    /// What the entries look like, so a heading can be told from them.
    struct Style {
        let entrySize: Double
        /// Share of the entries set in capitals, and starting in lowercase.
        let capitals: Double
        let lowercase: Double
        /// Share of the entries of two words or more set in sentence case ("Leek soup with
        /// thyme"), where a heading in title case stands out.
        let sentenceCase: Double

        init(lines: [Line], entrySize: Double) {
            self.entrySize = entrySize
            let count = Double(max(1, lines.count))
            capitals = Double(lines.count { ContentsReader.isCapitals($0.text) }) / count
            lowercase = Double(lines.count { $0.text.first?.isLowercase == true }) / count
            let worded = lines.filter { ContentsReader.majorWords($0.text).count >= 2 }
            sentenceCase = worded.isEmpty ? 0 : Double(worded.count { !ContentsReader.isTitleCase($0.text) }) / Double(worded.count)
        }

        /// Set apart from the entries by size, capitals or lowercase.
        func isHeadingStyle(_ line: Line) -> Bool {
            if line.size >= entrySize * 1.4 { return true }
            if ContentsReader.isCapitals(line.text), capitals < 0.5 { return true }
            if line.text.first?.isLowercase == true, lowercase < 0.3, line.size >= entrySize * 1.08 { return true }
            return false
        }

        /// A heading in title case among entries in sentence case, with more space above it than
        /// the entries have ("Funny Onions 35" over "Leek fritters 36"): a single word at the
        /// entries' spacing is a recipe ("Shakshuka 87").
        func isTitleCaseHeading(_ line: Line, spaced: Bool) -> Bool {
            guard sentenceCase >= 0.6, ContentsReader.isTitleCase(line.text), !ContentsReader.endsMidPhrase(line.text) else { return false }
            return spaced || line.page == nil && ContentsReader.majorWords(line.text).count >= 2
        }
    }

    static func read(_ column: [Line], style: Style, overview: Bool, into sections: inout [BookContents.Section]) {
        guard !column.isEmpty else { return }
        // The column's line pitch: the step from one entry's top to the next.
        let steps = zip(column, column.dropFirst()).map { $1.rect.minY - $0.rect.minY }.filter { $0 > 0.003 }
        let pitch = median(steps) ?? 0.02
        var lines = column
        // A mended page number that runs backwards among its neighbours is a misreading.
        var lastPage: Int?
        for index in lines.indices {
            guard let page = lines[index].page else { continue }
            if lines[index].isMended, let lastPage, page < lastPage { lines[index].page = nil; continue }
            if !style.isHeadingStyle(lines[index]) { lastPage = page }
        }

        var index = 0
        var previousTop: Double?
        func addEntry(_ title: String, page: Int?) {
            if sections.isEmpty { sections.append(BookContents.Section(title: "")) }
            sections[sections.count - 1].entries.append(BookContents.Entry(title: title, page: page))
        }
        while index < lines.count {
            var line = lines[index]
            let gapAbove = previousTop.map { line.rect.minY - $0 } ?? .infinity
            previousTop = line.rect.minY
            index += 1
            if isLabel(line.text) { continue }
            let spaced = gapAbove >= pitch * 1.5
            // A title wrapped onto the lines below it.
            while line.page == nil, index < lines.count, continues(line, lines[index], pitch: pitch, spaced: spaced, style: style) {
                let next = lines[index]
                line.text = line.text + " " + next.text
                line.page = next.page
                line.rect = line.rect.union(next.rect)
                line.size = max(line.size, next.size)
                previousTop = next.rect.minY
                index += 1
            }
            if style.isHeadingStyle(line) || style.isTitleCaseHeading(line, spaced: spaced) || overview && line.page != nil {
                sections.append(BookContents.Section(title: displayTitle(line.text), page: line.page))
            } else if line.page != nil {
                addEntry(PageLines.titleText(line.text), page: line.page)
            } else if overview || spaced {
                // Set apart with no page number: a heading ("Roots" over its recipes), the first
                // line of a column included.
                sections.append(BookContents.Section(title: displayTitle(line.text)))
            } else {
                // An entry whose page number didn't read.
                addEntry(PageLines.titleText(line.text), page: nil)
            }
        }
    }

    /// Whether `next` carries on `line`'s title: the first ends mid-phrase, or the second is
    /// indented under it, starts in lowercase, or sits closer than the entries do (not after a
    /// gap, where a line is more likely a heading over its first entry). A heading carries on only
    /// into a heading.
    static func continues(_ line: Line, _ next: Line, pitch: Double, spaced: Bool, style: Style) -> Bool {
        guard !isLabel(next.text) else { return false }
        let step = next.rect.minY - line.rect.minY
        guard step > 0, step < pitch * 1.45 else { return false }
        if style.isHeadingStyle(line) != style.isHeadingStyle(next) { return false }
        if endsMidPhrase(line.text) { return true }
        if style.isTitleCaseHeading(line, spaced: spaced) { return false }
        if next.rect.minX >= line.rect.minX + 0.008 { return true }
        if next.text.first?.isLowercase == true, style.lowercase < 0.3 { return true }
        return !spaced && next.page != nil && step < pitch * 0.85
    }

    /// The line stops on a joining word or a comma, so the title goes on below.
    static func endsMidPhrase(_ text: String) -> Bool {
        let last = text.split(separator: " ").last.map { String($0).lowercased() } ?? ""
        return ["with", "and", "&", "of", "in", "on", "or", "for", "the", "a", "de", "au", "à", "en", "y"].contains(last) || text.hasSuffix(",")
    }

    static let smallWords: Set<String> = ["a", "an", "and", "as", "at", "by", "de", "del", "di", "du", "en", "for", "from", "in", "into", "la", "le", "of", "on", "or", "the", "to", "with", "à", "au", "&"]

    /// The words that title case capitalizes.
    static func majorWords(_ text: String) -> [Substring] {
        text.split(separator: " ").filter { word in
            word.first?.isLetter == true && !smallWords.contains(word.lowercased())
        }
    }

    /// Every major word starts with a capital ("Zucchini and Other Squashes").
    static func isTitleCase(_ text: String) -> Bool {
        let words = majorWords(text)
        return !words.isEmpty && words.allSatisfy { $0.first?.isUppercase == true }
    }

    // MARK: - Index pages

    /// "Leek soup, 16, 42" and "Leeks: braised, 30": each line an entry by its first page, in one
    /// section.
    static func readIndex(_ reading: PageReading) -> BookContents {
        var entries: [BookContents.Entry] = []
        for line in contentLines(of: reading) where !line.isNumberOnly {
            let text = line.text
            if let match = text.firstMatch(of: /^(.*?[\p{L}\)])\s*[,:]?\s*(\d{1,3})(?:\s*[,–\-]\s*\d{1,3})*$/) {
                entries.append(BookContents.Entry(title: cleanTitle(String(match.output.1)), page: Int(match.output.2)))
            } else if let page = line.page {
                entries.append(BookContents.Entry(title: text, page: page))
            }
        }
        return BookContents(sections: entries.isEmpty ? [] : [BookContents.Section(title: "Index", entries: entries)])
    }

    // MARK: - Tidying

    /// Labels before a chapter's name ("CHAPTER ONE", "Part 2"), the page's own title.
    static func isLabel(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespaces)
        if ["contents", "table of contents", "index", "recipes"].contains(lower) { return true }
        return lower.firstMatch(of: /^(chapter|part|section|book)\s+([0-9ivxlc]+|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen)$/) != nil
    }

    /// Front and back matter: not chapters of recipes.
    static func isFrontOrBackMatter(_ title: String) -> Bool {
        let words = normalized(title).split(separator: " ").map(String.init)
        let matter: Set<String> = ["introduction", "foreword", "preface", "acknowledgments", "acknowledgements", "index", "glossary",
                                   "sources", "resources", "suppliers", "epilogue", "contents", "bibliography", "credits", "dedication"]
        guard let first = words.first else { return true }
        if matter.contains(first) || words.allSatisfy({ matter.contains($0) || $0 == "and" }) { return true }
        return normalized(title).hasPrefix("about the author") || normalized(title).hasPrefix("metric") || normalized(title).hasPrefix("conversion")
    }

    /// Drops front and back matter and chapters left with nothing (no entries and no page), and
    /// entries that are only a page's furniture.
    static func tidy(_ sections: [BookContents.Section], overview: Bool) -> [BookContents.Section] {
        sections.compactMap { section in
            var section = section
            section.entries = section.entries.filter { $0.title.filter(\.isLetter).count >= 2 }
            if !section.title.isEmpty, isFrontOrBackMatter(section.title), section.entries.isEmpty { return nil }
            if !section.title.isEmpty, section.entries.isEmpty, section.page == nil { return nil }
            if section.title.isEmpty, section.entries.isEmpty { return nil }
            return section
        }
    }

    /// A chapter's name for the list: capitals and all-lowercase set in title case ("COLD
    /// APPETIZERS", "cold appetizers" → "Cold Appetizers"), anything else as printed.
    static func displayTitle(_ text: String) -> String {
        let letters = text.filter(\.isLetter)
        guard !letters.isEmpty else { return text }
        if letters.allSatisfy({ !$0.isUppercase }) { return PageLines.titleText(text.uppercased()) }
        return PageLines.titleText(text)
    }

    static func isCapitals(_ text: String) -> Bool {
        let letters = text.filter(\.isLetter)
        return letters.count >= 3 && letters.allSatisfy { !$0.isLowercase }
    }

    /// Titles compared without case, accents, punctuation or "and"/"&"; a title the recognizer cut
    /// short ("cocktai") matches the whole one.
    static func sameTitle(_ a: String, _ b: String) -> Bool {
        let first = normalized(a), second = normalized(b)
        guard !first.isEmpty, !second.isEmpty else { return false }
        if first == second { return true }
        let shorter = first.count < second.count ? first : second
        let longer = first.count < second.count ? second : first
        return shorter.count >= 5 && longer.hasPrefix(shorter)
    }

    static func normalized(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en"))
            .replacingOccurrences(of: "&", with: " and ")
        let words = folded.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        return words.joined(separator: " ")
    }

    /// The page's text for the model: each column's lines top to bottom, page numbers set in their
    /// own column put back at the end of their titles.
    static func modelText(of reading: PageReading) -> String {
        var lines = contentLines(of: reading)
        pairNumbers(&lines)
        return columns(lines.filter { !$0.isNumberOnly }).flatMap { $0 }
            .map { line in line.page.map { "\(line.text) \($0)" } ?? line.text }
            .joined(separator: "\n")
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
}

extension PagePipeline {
    /// A contents or index page's chapters and entries (02 Flow C step 3): the deterministic
    /// reading, and the on-device model only where it falls short (`ContentsReader.wantsModel`).
    public func readContents(_ reading: PageReading) async -> BookContents {
        let contents = ContentsReader.read(reading)
        guard let model else { return contents }
        return await ContentsReader.refine(contents, page: reading, model: model)
    }
}
