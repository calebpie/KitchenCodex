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
    /// What the book's index pages list ("Chocolate, in chocolate bouchons", by its first page),
    /// kept apart from the chapters: it is the book's Index tab, not its punchlist (ux-notes row
    /// 117).
    public var index: [Entry]
    /// The page lists chapters with their first pages and no recipes, as a book's opening contents
    /// page often does before the detailed one.
    public var isOverview: Bool
    /// `.pageText` for the deterministic reading, `.model` once the on-device model read it.
    public var method: ImportMethod

    public init(sections: [Section] = [], index: [Entry] = [], isOverview: Bool = false, method: ImportMethod = .pageText) {
        self.sections = sections
        self.index = index
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
/// - Text outside the page's outline (things beside the book in the frame) is dropped first, when
///   the outline holds most of the page's lines (ux-notes row 119).
/// - Entries are lines that end in a page number, with dotted leaders and the recognizer's digit
///   slips ("5l", "1OO") mended; a page number set in its own column is paired with the title on
///   its line. A number that would run backwards among its neighbours is a misreading, and the
///   entry keeps no page rather than a wrong one.
/// - An entry is complete only when a page number closes it (ux-notes row 118): a line without one
///   carries on into the lines below it in its column until one has a page, unless it reads as a
///   heading. A wrapped line is told by filling the column, ending mid-phrase ("with", "&", a
///   comma), or the next line being indented, lowercase or set closer; a short line whose number
///   didn't read stays an entry of its own.
/// - Chapter headings are lines set apart: larger than the entries, in capitals or in lowercase
///   where the entries are not, or, without a page number, short with more space above than the
///   entries have. "Chapter One" and the page's own "Contents" are labels, not chapters; front and
///   back matter (an introduction, the index, acknowledgments) is dropped, and so is a heading
///   with no entries and no page.
/// - Columns are read top to bottom and placed in the order their page numbers run (ux-notes row
///   119); entries before a column's first heading continue the section before. A page whose page
///   numbers jump by six or more from one line to the next lists chapters, not recipes (an
///   overview): its lines become chapters with their first pages, which the detailed pages fill
///   in (`combine`). On an overview, a line set close under a chapter's (its name in a second
///   language, a companion essay) is neither chapter nor entry (ux-notes row 96), and lends the
///   chapter its page when the chapter's own didn't read.
/// - An index page's lines ("Leek soup, 16, 42", "chocolate:" over "in tart, 271") are the book's
///   index, by their first page, a sub-entry under its headword; they fill the Index tab, not the
///   punchlist (ux-notes row 117).
public enum ContentsReader {
    /// One page's reading. `reading` is the page pipeline's (`PagePipeline.readPage`): every block
    /// but noise is read, whatever kind the structurer made of the page.
    public static func read(_ reading: PageReading) -> BookContents {
        if reading.kind == .index { return readIndex(reading) }
        var lines = contentLines(of: reading)
        guard !lines.isEmpty else { return BookContents() }
        joinFragments(&lines)
        pairNumbers(&lines)
        let entrySize = Self.entrySize(lines)
        let columns = Self.columns(lines.filter { !$0.isNumberOnly })
        let paged = columns.flatMap { $0 }.filter { $0.page != nil }
        let overview = isOverview(paged.map { $0.page! })
        let style = Style(lines: paged.isEmpty ? columns.flatMap { $0 } : paged, entrySize: entrySize)
        let runs = pageOrder(columns.map { overview ? readOverview($0, style: style) : read($0, style: style) })
        var sections: [BookContents.Section] = []
        for item in runs.joined() {
            switch item {
            case let .heading(title, page):
                sections.append(BookContents.Section(title: title, page: page))
            case let .entry(title, page):
                // Before the column's first heading: the section the column before ended on.
                if sections.isEmpty { sections.append(BookContents.Section(title: "")) }
                sections[sections.count - 1].entries.append(BookContents.Entry(title: title, page: page))
            }
        }
        return BookContents(sections: tidy(sections, overview: overview), isOverview: overview)
    }

    /// Whether the model should read the page too: the deterministic reading found few entries, or
    /// none with a page number. An overview page that read as chapters with pages is complete, and
    /// so is an index page.
    public static func wantsModel(_ contents: BookContents) -> Bool {
        if !contents.index.isEmpty { return false }
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
                title: finalTitle(cleanTitle(section.title)),
                page: section.page,
                entries: section.entries.map { BookContents.Entry(title: finalTitle(cleanTitle($0.title)), page: $0.page) }.filter { !$0.title.isEmpty }
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

    /// Several pages in the order photographed, as one contents: a section on a later page that is
    /// one before (`sameChapter`: an overview's chapter and its detailed listing) is that section;
    /// entries before a page's first heading continue the section the page before ended on; an
    /// entry already read (two photos overlapping, the facing page in the frame) is not listed
    /// twice. Index pages give the book's index, apart from the chapters (ux-notes row 117).
    public static func combine(_ pages: [BookContents], indexPages: [BookContents] = []) -> BookContents {
        var sections: [BookContents.Section] = []
        var last: Int?
        var listed = Set<String>()
        for page in pages {
            for var section in page.sections {
                section.entries = section.entries.filter { listed.insert(entryKey($0)).inserted }
                if section.title.isEmpty, let index = last ?? sections.indices.last {
                    sections[index].entries += section.entries
                    last = index
                } else if let index = sections.firstIndex(where: { sameChapter($0, section) }) {
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
        var indexed = Set<String>()
        let index = (indexPages + pages).flatMap(\.index).filter { indexed.insert(entryKey($0)).inserted }
        let method: ImportMethod = pages.contains { $0.method == .model } ? .model : .pageText
        return BookContents(sections: sections, index: index, isOverview: !pages.isEmpty && pages.allSatisfy(\.isOverview), method: method)
    }

    /// The same chapter read twice (an overview's line and the detailed page's heading): the same
    /// title, and no two different first pages. A book that prints a chapter name under two parts
    /// (a Fish and Shellfish among the first courses and another among the main courses) has two.
    public static func sameChapter(_ a: BookContents.Section, _ b: BookContents.Section) -> Bool {
        guard sameTitle(a.title, b.title) else { return false }
        guard let first = a.page, let second = b.page else { return true }
        return abs(first - second) <= 2
    }

    /// An entry's title and page, for telling one already listed.
    static func entryKey(_ entry: BookContents.Entry) -> String {
        "\(normalized(entry.title))|\(entry.page.map(String.init) ?? "")"
    }

    // MARK: - What the page is (ux-notes row 114)

    /// Whether a page reads as a contents page or as a recipe page, so each session can say when
    /// it was offered the other kind: a contents page has many short lines ending in a page number;
    /// a recipe page has lines that read as ingredient amounts and few page numbers.
    public enum PageJudgement: Sendable, Equatable {
        case contents
        case recipe
        /// Neither clearly: read as offered.
        case unsure
    }

    public static func judge(_ reading: PageReading) -> PageJudgement {
        if reading.kind == .index { return .contents }
        var lines = contentLines(of: reading)
        joinFragments(&lines)
        pairNumbers(&lines)
        let text = lines.filter { !$0.isNumberOnly }
        let paged = text.count { $0.page != nil }
        let printed = reading.blocks.filter { $0.kind != .photo && $0.role != .furniture }.flatMap(\.lines).map(\.text)
        let amounts = printed.count { if case .strong = PageLines.ingredientShape($0) { true } else { false } }
        let share = Double(paged) / Double(max(1, text.count))
        if paged >= 5, share >= 0.35, amounts * 2 <= paged { return .contents }
        let recipe = reading.recipes.contains { $0.ingredients.count >= 3 && !$0.steps.isEmpty }
        if amounts >= 3, amounts > paged || recipe && share < 0.3 { return .recipe }
        return .unsure
    }

    // MARK: - Lines

    struct Line {
        var text: String
        var rect: PageRect
        var size: Double
        var page: Int?
        /// A page number set alone, in its own column.
        var isNumberOnly: Bool
        /// The line ends in something the recognizer couldn't read as a page number ("3a"): an
        /// entry complete without its page, which carries on into no line below.
        var endsInUnreadPage = false
    }

    /// The page's printed lines, the ones outside its outline dropped (ux-notes row 119): what lies
    /// beside the book in the frame. The outline is trusted only when it holds most of the lines;
    /// one that found a picture or a box on the page instead is not used. Vision's outline can
    /// clip a page's edge (a heading set on a dark band at the top), so a line outside it stays
    /// when it lines up with a column of the lines inside, within three lines of them, and the
    /// reader didn't set it aside as off the page.
    static func printedLines(of reading: PageReading) -> [PageTextLine] {
        let blocks = reading.blocks.filter { $0.kind != .photo }
        let lines = blocks.flatMap(\.lines)
        guard let outline = reading.outline?.expanded(by: 0.03) else { return lines }
        let isInside = { (line: PageTextLine) in outline.contains(PagePoint(x: line.rect.midX, y: line.rect.midY)) }
        let inside = lines.filter(isInside)
        guard Double(inside.count) >= Double(lines.count) * 0.6 else { return lines }
        let steps = inside.sorted { $0.rect.minY < $1.rect.minY }.adjacentSteps
        let reach = (median(steps.filter { $0 > 0.005 }) ?? 0.02) * 3
        return blocks.flatMap { block in
            block.lines.filter { line in
                if isInside(line) { return true }
                guard block.role != .ignore else { return false }
                return inside.contains { other in
                    abs(other.rect.minX - line.rect.minX) < 0.02 && abs(other.rect.midY - line.rect.midY) <= reach
                }
            }
        }
    }

    /// Every line of text off the page but noise, a price on a jacket flap and the page's own
    /// running foot ("contents"). The structurer's own noise marks are not used: a contents page
    /// printed white on black reads to it as a photo with text inside, so the reader judges noise
    /// itself, by the recognizer's confidence, a scrap with too few letters, a sliver at the frame's
    /// edge, or a place outside the page's outline.
    static func contentLines(of reading: PageReading) -> [Line] {
        printedLines(of: reading).compactMap { line in
            let text = line.text.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty, !text.contains("$"), text.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
            let letters = text.count(where: \.isLetter)
            if line.confidence < 0.15 || (letters > 0 && letters < 3 && !text.contains(where: \.isNumber)) { return nil }
            if line.rect.width < 0.08, line.rect.minX < 0.03 || line.rect.maxX > 0.97 { return nil }
            if text.allSatisfy(\.isNumber), text.count <= 3 {
                return Line(text: text, rect: line.rect, size: line.size, page: Int(text), isNumberOnly: true)
            }
            var result = Line(text: text, rect: line.rect, size: line.size, page: nil, isNumberOnly: false)
            if let (title, page) = trailingPage(text) {
                result.text = title
                result.page = page
            } else if let match = text.firstMatch(of: /^(.+?)\s+(?:[0-9IlOo|]{1,3}[A-Za-z?]?|[Il|])$/), match.output.0.split(separator: " ").last?.contains(where: \.isNumber) == true || "Il|".contains(text.last!) {
                // A page number the recognizer couldn't read ("3a"): the title without it.
                result.text = cleanTitle(String(match.output.1))
                result.endsInUnreadPage = true
            } else {
                result.text = cleanTitle(text)
            }
            return result.text.contains(where: \.isLetter) ? result : nil
        }
    }

    /// The title and page number of "Leek Soup 16", "Leek Soup ........ 16", "Leek Soup · 16",
    /// "Leek Soup 5l" (a digit read as a letter). Nil when the line doesn't end in one.
    static func trailingPage(_ text: String) -> (String, Int)? {
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
        return (title, page)
    }

    /// A line as printed, with its leaders, separators and spare spaces gone. A comma at its end
    /// stays: it says the title goes on below (`finalTitle` takes it off once joined).
    static func cleanTitle(_ text: String) -> String {
        var title = text.replacingOccurrences(of: #"[.·•…_]{2,}"#, with: " ", options: .regularExpression)
        title = title.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return title.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".·•…_-–—|:;")))
    }

    /// An entry's or chapter's title as the list shows it: no comma or colon left at its end.
    static func finalTitle(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ",:;")))
    }

    /// A printed line the recognizer read as two pieces side by side ("COI" and "IMENTS & PICKLES
    /// 42", as the iOS Simulator reads one heading) is one line again: pieces level with each other
    /// and close across, the left one without a page number, the right one not starting where a
    /// column of other lines starts. Page numbers set alone stay apart for `pairNumbers`.
    static func joinFragments(_ lines: inout [Line]) {
        var changed = true
        while changed {
            changed = false
            outer: for left in lines.indices where !lines[left].isNumberOnly && lines[left].page == nil {
                for right in lines.indices where right != left && !lines[right].isNumberOnly {
                    let a = lines[left].rect, b = lines[right].rect
                    let gap = b.minX - a.maxX
                    let size = max(lines[left].size, lines[right].size)
                    guard a.verticalOverlap(with: b) >= 0.5, gap > -size, gap < size * 2.5, a.minX < b.minX else { continue }
                    // A line starting where a column of others starts is the next column's, not a piece.
                    let aligned = lines.indices.count { $0 != left && $0 != right && abs(lines[$0].rect.minX - b.minX) < 0.015 }
                    guard aligned < 2 else { continue }
                    lines[left].text += " " + lines[right].text
                    lines[left].rect = a.union(b)
                    lines[left].size = size
                    lines[left].page = lines[right].page
                    lines.remove(at: right)
                    changed = true
                    break outer
                }
            }
        }
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

    /// Page numbers that jump by six or more from one entry to the next: chapters, not recipes. A
    /// detailed page's few misread numbers jump too, so most of the steps must be wide.
    static func isOverview(_ pages: [Int]) -> Bool {
        guard pages.count >= 3, pages.count <= 30 else { return false }
        let gaps = zip(pages, pages.dropFirst()).map { abs($1 - $0) }
        let close = gaps.count { $0 <= 3 }
        return (median(gaps.map(Double.init)) ?? 0) >= 6 && Double(close) < Double(gaps.count) * 0.4
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

    /// What a column holds, in order: chapter headings and entries.
    enum Item: Equatable {
        case heading(String, page: Int?)
        case entry(String, page: Int?)

        var page: Int? {
            switch self {
            case let .heading(_, page), let .entry(_, page): page
            }
        }
    }

    /// The columns in the order their page numbers run (ux-notes row 119), not as they sit across
    /// the page: each by the middle of its pages, a column with none after the one before it. A
    /// page shot at an angle, or with another page's column in the frame, still reads in the
    /// book's order.
    static func pageOrder(_ runs: [[Item]]) -> [[Item]] {
        var keyed: [(key: Double, position: Int, run: [Item])] = []
        var previous = -Double.infinity
        for (position, run) in runs.enumerated() {
            let pages = run.compactMap(\.page).map(Double.init)
            let key = median(pages) ?? previous
            keyed.append((key, position, run))
            previous = key
        }
        return keyed.sorted { ($0.key, $0.position) < ($1.key, $1.position) }.map(\.run)
    }

    /// The column's line pitch: the step from a line with a page number (an entry's last line) to
    /// the next, so a column of wrapped titles doesn't pull it down to the wrap's step.
    static func pitch(of column: [Line]) -> Double {
        let pairs = Array(zip(column, column.dropFirst()))
        let steps = pairs.filter { $0.0.page != nil }.map { $1.rect.minY - $0.rect.minY }.filter { $0 > 0.003 }
        return median(steps.count >= 3 ? steps : pairs.map { $1.rect.minY - $0.rect.minY }.filter { $0 > 0.003 }) ?? 0.02
    }

    /// A detailed page's column: its headings and entries, a title wrapped over several lines read
    /// as one.
    static func read(_ column: [Line], style: Style) -> [Item] {
        guard !column.isEmpty else { return [] }
        let pitch = pitch(of: column)
        var lines = column
        dropBackwardPages(&lines, style: style)
        // The column's measure: how wide its longer entries run, which a wrapped line fills.
        let widths = lines.filter { !style.isHeadingStyle($0) }.map(\.rect.width).sorted()
        let measure = widths.isEmpty ? 0 : widths[min(widths.count - 1, widths.count * 9 / 10)]

        var items: [Item] = []
        var index = 0
        var previousTop: Double?
        while index < lines.count {
            var line = lines[index]
            let gapAbove = previousTop.map { line.rect.minY - $0 } ?? .infinity
            previousTop = line.rect.minY
            index += 1
            if isLabel(line.text) { continue }
            let spaced = gapAbove >= pitch * 1.5
            if let run = wrappedRun(from: index - 1, in: lines, pitch: pitch, spaced: spaced, measure: measure, style: style) {
                // An entry is complete only when a page number closes it (ux-notes row 118).
                for next in lines[index..<(index + run)] {
                    line.text += " " + next.text
                    line.page = next.page
                    line.endsInUnreadPage = next.endsInUnreadPage
                    line.rect = line.rect.union(next.rect)
                    line.size = max(line.size, next.size)
                    previousTop = next.rect.minY
                }
                index += run
            } else if line.page == nil, style.isHeadingStyle(line) {
                // A heading wrapped onto the lines below it, each measured from the line before it.
                var tail = line
                while index < lines.count, continues(tail, lines[index], pitch: pitch, spaced: spaced && tail.rect == line.rect, style: style) {
                    let next = lines[index]
                    line.text += " " + next.text
                    line.page = next.page
                    line.rect = line.rect.union(next.rect)
                    line.size = max(line.size, next.size)
                    previousTop = next.rect.minY
                    tail = next
                    index += 1
                    if line.page != nil { break }
                }
            }
            if style.isHeadingStyle(line) || style.isTitleCaseHeading(line, spaced: spaced) {
                items.append(.heading(displayTitle(finalTitle(line.text)), page: line.page))
            } else if line.page != nil || line.endsInUnreadPage || !spaced {
                // An entry; one whose page number didn't read keeps none.
                items.append(.entry(PageLines.titleText(finalTitle(line.text)), page: line.page))
            } else {
                // Set apart with no page number: a heading ("Roots" over its recipes), the first
                // line of a column included.
                items.append(.heading(displayTitle(finalTitle(line.text)), page: nil))
            }
        }
        return items
    }

    /// How many lines below `start` its title runs on to (ux-notes row 118): a line with no page
    /// number carries on, up to three lines, until one has a page, unless it reads as a heading
    /// (set larger, in capitals or lowercase where the entries aren't, a title-case heading among
    /// sentence-case entries, or short with more space above) or its page token is there but
    /// unread. The run stops at a gap or a heading-styled line. That the line wraps at all is told
    /// by its filling the column, ending mid-phrase, or the next line being indented, lowercase or
    /// set closer, so a short entry whose page didn't read stays on its own. Nil for no run.
    static func wrappedRun(from start: Int, in lines: [Line], pitch: Double, spaced: Bool, measure: Double, style: Style) -> Int? {
        let line = lines[start]
        guard line.page == nil, !line.endsInUnreadPage, !style.isHeadingStyle(line), !style.isTitleCaseHeading(line, spaced: spaced) else { return nil }
        var tail = line
        for offset in 1...3 {
            guard start + offset < lines.count else { return nil }
            let next = lines[start + offset]
            guard !isLabel(next.text), !style.isHeadingStyle(next) else { return nil }
            let step = next.rect.minY - tail.rect.minY
            guard step > 0, step < pitch * 1.6 else { return nil }
            // Every line of the run but the last wraps: it ends mid-phrase, goes on into an
            // indented or lowercase line, or fills the column; or the next line, set closer than
            // the entries, closes it.
            let goesOn = endsMidPhrase(tail.text) || next.rect.minX >= line.rect.minX + 0.008
                || next.text.first?.isLowercase == true && style.lowercase < 0.3
            // Where the entries are in sentence case, a line starting with a capital is a new
            // entry, not the one above carried on.
            let startsAnew = next.text.first?.isUppercase == true && style.sentenceCase >= 0.6
            let fills = measure > 0 && tail.rect.width >= measure * 0.6 && !startsAnew
            let closes = next.page != nil && !(offset == 1 && spaced) && step < pitch * 0.85
            // A short line set apart over an entry is a heading.
            if offset == 1, spaced, !goesOn, !fills { return nil }
            guard goesOn || fills || closes else { return nil }
            if next.page != nil || next.endsInUnreadPage { return offset }
            tail = next
        }
        return nil
    }

    /// An overview's column: every line a chapter with its first page. Pages printed in groups (a
    /// chapter's line, then its name in a second language and its companion essays set close under
    /// it) keep only the chapter (ux-notes row 96); the chapter takes the group's first page when
    /// its own didn't read.
    static func readOverview(_ column: [Line], style: Style) -> [Item] {
        let steps = zip(column, column.dropFirst()).map { $1.rect.minY - $0.rect.minY }.filter { $0 > 0.003 }.sorted()
        let low = steps.isEmpty ? 0 : steps[steps.count / 4]
        let high = steps.isEmpty ? 0 : steps[steps.count * 3 / 4]
        // Two spacings, one within a group and one between: the lines closer than their middle
        // belong to the line above.
        let grouped = steps.count >= 4 && high >= low * 1.7
        let within = (low + high) / 2
        let pitch = pitch(of: column)

        var items: [Item] = []
        var chapter: (item: Int, line: Line)?
        var previousTop: Double?
        var index = 0
        while index < column.count {
            var line = column[index]
            let step = previousTop.map { line.rect.minY - $0 }
            index += 1
            if isLabel(line.text) {
                previousTop = line.rect.minY
                continue
            }
            // A chapter's name wrapped onto the next line: it ends mid-phrase, or goes on indented
            // or in lowercase.
            var tail = line
            while line.page == nil, index < column.count, !style.isHeadingStyle(column[index]) || style.isHeadingStyle(line),
                  continuesOverview(tail, column[index], pitch: pitch, style: style) {
                let next = column[index]
                line.text += " " + next.text
                line.page = next.page
                line.rect = line.rect.union(next.rect)
                tail = next
                index += 1
            }
            previousTop = tail.rect.minY
            // Set larger than the group's chapter, a line starts a group of its own.
            if grouped, let step, step < within, let (at, head) = chapter, !(style.isHeadingStyle(line) && !style.isHeadingStyle(head)) {
                if case let .heading(title, nil) = items[at], let page = line.page { items[at] = .heading(title, page: page) }
                continue
            }
            items.append(.heading(displayTitle(finalTitle(line.text)), page: line.page))
            chapter = (items.count - 1, line)
        }
        return items
    }

    /// An overview line carries on into the next: it ends mid-phrase, or the next is indented or
    /// starts in lowercase, within the line pitch.
    static func continuesOverview(_ line: Line, _ next: Line, pitch: Double, style: Style) -> Bool {
        guard !isLabel(next.text) else { return false }
        let step = next.rect.minY - line.rect.minY
        guard step > 0, step < pitch * 1.45 else { return false }
        if endsMidPhrase(line.text) { return true }
        if next.rect.minX >= line.rect.minX + 0.008 { return true }
        return next.text.first?.isLowercase == true && style.lowercase < 0.3
    }

    /// An entry's page number lower than the one before it in the column is a misreading (a
    /// dropped digit, a stray number paired with it): the page goes, or the one before it does when
    /// that one was the outlier (higher than the entry after it too). A chapter's own page is left
    /// alone.
    static func dropBackwardPages(_ lines: inout [Line], style: Style) {
        let entries = lines.indices.filter { lines[$0].page != nil && !style.isHeadingStyle(lines[$0]) }
        var previous: Int?
        for (position, index) in entries.enumerated() {
            guard let page = lines[index].page else { continue }
            if let before = previous, let last = lines[before].page, page < last {
                let next = entries.dropFirst(position + 1).first.flatMap { lines[$0].page }
                // Either way the line ended in a number: it is complete, with no page.
                if let next, next >= page, next < last {
                    lines[before].page = nil
                    lines[before].endsInUnreadPage = true
                } else {
                    lines[index].page = nil
                    lines[index].endsInUnreadPage = true
                    continue
                }
            }
            previous = index
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

    /// An index page (ux-notes row 117): "Leek soup, 16, 42" and "Leeks: braised, 30" by their
    /// first page; a headword ending in a colon ("chocolate:") heads the indented lines under it
    /// ("Chocolate, in tart"); a line that runs over ("salad with oranges and radishes," over
    /// "108") is one entry; "see also" lines and letter headings ("D") are not entries. Column by
    /// column, outside the page's outline dropped as on a contents page.
    static func readIndex(_ reading: PageReading) -> BookContents {
        let lines = printedLines(of: reading).compactMap { line -> Line? in
            let text = line.text.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty, line.confidence >= 0.15 else { return nil }
            return Line(text: text, rect: line.rect, size: line.size, page: nil, isNumberOnly: false)
        }
        var entries: [BookContents.Entry] = []
        for column in columns(lines) {
            let margin = column.map(\.rect.minX).sorted().dropFirst(column.count / 10).first ?? 0
            let indent = max(0.006, (median(column.map(\.size)) ?? 0.01) * 0.6)
            var headword: String?
            var pending: String?
            for line in column {
                let text = line.text
                let lower = text.lowercased()
                if lower.hasPrefix("see ") || lower.hasPrefix("(see ") || text.count == 1 || isLabel(text) {
                    pending = nil
                    continue
                }
                let atMargin = line.rect.minX < margin + indent
                if pending != nil, atMargin, text.range(of: #"^\d"#, options: .regularExpression) == nil {
                    // A new entry at the margin: the one before never read a page.
                    pending = nil
                }
                if pending == nil {
                    if text.hasSuffix(":") {
                        headword = finalTitle(String(text.dropLast()))
                        continue
                    }
                    if atMargin { headword = nil }
                    pending = text
                } else {
                    pending! += " " + text
                }
                guard let read = pending, let (title, page) = indexEntry(read) else { continue }
                pending = nil
                let named = headword.map { "\(capitalizedFirst($0)), \(title)" } ?? capitalizedFirst(title)
                entries.append(BookContents.Entry(title: named, page: page))
            }
        }
        return BookContents(index: entries)
    }

    /// "Leek soup, 16, 42", "pots de crème, 268–69": the title and the first page.
    static func indexEntry(_ text: String) -> (String, Int)? {
        guard let match = text.firstMatch(of: /^(.*?[\p{L}\)])\s*[,:]?\s*(\d{1,3})(?:\s*[,–\-]\s*\d{1,3})*$/),
              let page = Int(match.output.2) else { return nil }
        let title = finalTitle(cleanTitle(String(match.output.1)))
        guard title.filter(\.isLetter).count >= 2 else { return nil }
        return (title, page)
    }

    /// The first letter as a capital, the rest as printed ("chocolate" → "Chocolate").
    static func capitalizedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
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

    /// Drops front and back matter, chapters left with nothing (no entries and no page), a heading
    /// with no page over entries with none on a page that prints pages, and entries that are only
    /// a page's furniture.
    static func tidy(_ sections: [BookContents.Section], overview: Bool) -> [BookContents.Section] {
        // On a page whose entries mostly carry pages, a heading with no page over entries with none
        // is something beside the book (another book's cover, a label): noise, as an empty one is.
        let entries = sections.flatMap(\.entries)
        let mostlyPaged = entries.count >= 6 && Double(entries.count { $0.page != nil }) >= Double(entries.count) * 0.7
        return sections.compactMap { section in
            var section = section
            section.entries = section.entries.filter { $0.title.filter(\.isLetter).count >= 2 }
            if !section.title.isEmpty, isFrontOrBackMatter(section.title), section.entries.isEmpty { return nil }
            if !section.title.isEmpty, section.entries.isEmpty, section.page == nil { return nil }
            if mostlyPaged, !section.title.isEmpty, section.page == nil, section.entries.allSatisfy({ $0.page == nil }) { return nil }
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
        joinFragments(&lines)
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

private extension [PageTextLine] {
    /// The vertical steps from each line to the next, in the order given.
    var adjacentSteps: [Double] { zip(self, dropFirst()).map { $1.rect.minY - $0.rect.minY } }
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
