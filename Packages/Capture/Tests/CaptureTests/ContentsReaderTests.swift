import Foundation
import Intelligence
import Synchronization
import Testing
@testable import Capture

/// The contents reader and the punchlist helpers on hand-made pages: lines laid out as the reader
/// returns them, with made-up titles. The private contents photos are `PrivatePageTests`'.
@Suite("Contents pages")
struct ContentsReaderTests {
    /// A line at (x, y), its letters half as wide as it is high.
    static func line(_ text: String, x: Double, y: Double, size: Double = 0.012) -> PageTextLine {
        PageTextLine(text: text, rect: PageRect(x: x, y: y, width: Double(text.count) * size * 0.5, height: size), confidence: 0.6, size: size)
    }

    /// A page of one-line blocks, as a contents page reads.
    static func page(_ lines: [PageTextLine], kind: PageKind = .contents) -> PageReading {
        let blocks = lines.enumerated().map { index, line in PageBlock(id: index, kind: .line, rect: line.rect, lines: [line]) }
        return PageReading(files: ["contents.heic"], blocks: blocks, kind: kind)
    }

    // MARK: - One page

    @Test func readsHeadingsEntriesWrapsAndSlips() throws {
        let contents = ContentsReader.read(Self.page([
            Self.line("CONTENTS", x: 0.14, y: 0.08, size: 0.024),
            Self.line("INTRODUCTION 9", x: 0.14, y: 0.14, size: 0.014),
            Self.line("CHAPTER ONE", x: 0.14, y: 0.18, size: 0.014),
            Self.line("SOUPS 14", x: 0.14, y: 0.20, size: 0.022),
            Self.line("Weeknight Leek Soup 16", x: 0.14, y: 0.24),
            Self.line("Chilled Cucumber Soup with", x: 0.14, y: 0.26),
            Self.line("Dill & Yogurt 18", x: 0.14, y: 0.275),
            Self.line("White Bean Soup ........ 2l", x: 0.14, y: 0.295),
            Self.line("Smoky Tomato Broth 3a", x: 0.14, y: 0.315),
            Self.line("Barley & Kale Soup 23", x: 0.14, y: 0.335),
            Self.line("CHAPTER TWO", x: 0.14, y: 0.375, size: 0.014),
            Self.line("SALADS 30", x: 0.14, y: 0.395, size: 0.022),
            Self.line("Shaved Fennel Salad 32", x: 0.14, y: 0.435),
            Self.line("Warm Lentil Salad 3S", x: 0.14, y: 0.455),
            Self.line("Bitter Greens II", x: 0.14, y: 0.475),
            Self.line("Peach & Burrata Salad 38", x: 0.14, y: 0.495),
        ]))
        #expect(!contents.isOverview)
        #expect(contents.sections.map(\.title) == ["Soups", "Salads"])
        #expect(contents.sections.map(\.page) == [14, 30])
        let soups = try #require(contents.sections.first).entries
        #expect(soups == [
            BookContents.Entry(title: "Weeknight Leek Soup", page: 16),
            BookContents.Entry(title: "Chilled Cucumber Soup with Dill & Yogurt", page: 18),
            BookContents.Entry(title: "White Bean Soup", page: 21),
            BookContents.Entry(title: "Smoky Tomato Broth", page: nil),
            BookContents.Entry(title: "Barley & Kale Soup", page: 23),
        ])
        // "3S" mends to 35; "II" would run back to 11, so it keeps no page.
        #expect(contents.sections[1].entries.map(\.page) == [32, 35, nil, 38])
        #expect(contents.entries.count == 9)
        #expect(contents.pagedEntryCount == 7)
        #expect(!ContentsReader.wantsModel(contents))
    }

    @Test func pairsANumberColumnAndFindsTitleCaseHeadings() {
        let titles: [(String, Double, Double, String?)] = [
            ("Roots", 0.15, 0.20, nil),
            ("Poached baby turnips with herb oil", 0.15, 0.215, "12"),
            ("Spiced carrot salad", 0.15, 0.232, "14"),
            ("Roasted squash with", 0.15, 0.249, nil),
            ("sage butter", 0.167, 0.266, "16"),
            ("Shakshuka", 0.15, 0.283, "18"),
            ("Funny Onions", 0.15, 0.318, "21"),
            ("Leek fritters", 0.15, 0.335, "22"),
            ("Stuffed onions", 0.15, 0.352, "24"),
        ]
        var lines = titles.map { Self.line($0.0, x: $0.1, y: $0.2) }
        lines += titles.compactMap { title in title.3.map { Self.line($0, x: 0.47, y: title.2) } }
        // The facing page's numbers at the frame's edge go with no title.
        lines.append(Self.line("8", x: 0.01, y: 0.30))
        let contents = ContentsReader.read(Self.page(lines))
        #expect(contents.sections.map(\.title) == ["Roots", "Funny Onions"])
        #expect(contents.sections.map(\.page) == [nil, 21])
        #expect(contents.sections[0].entries.map(\.title) == ["Poached baby turnips with herb oil", "Spiced carrot salad", "Roasted squash with sage butter", "Shakshuka"])
        #expect(contents.sections[0].entries.map(\.page) == [12, 14, 16, 18])
        #expect(contents.sections[1].entries.map(\.page) == [22, 24])
    }

    @Test func readsAnOverviewThenFillsItFromTheDetailedPage() {
        let overview = ContentsReader.read(Self.page([
            Self.line("contents", x: 0.70, y: 0.14, size: 0.026),
            Self.line("introduction 8", x: 0.16, y: 0.20, size: 0.016),
            Self.line("cold starters 10", x: 0.16, y: 0.24, size: 0.016),
            Self.line("soups 24", x: 0.16, y: 0.28, size: 0.016),
            Self.line("grill 40", x: 0.16, y: 0.32, size: 0.016),
            Self.line("desserts 60", x: 0.16, y: 0.36, size: 0.016),
            Self.line("glossary", x: 0.16, y: 0.40, size: 0.016),
            Self.line("index 80", x: 0.16, y: 0.44, size: 0.016),
        ]))
        #expect(overview.isOverview)
        #expect(overview.entries.isEmpty)
        #expect(overview.sections.map(\.title) == ["Cold Starters", "Soups", "Grill", "Desserts"])
        #expect(overview.sections.map(\.page) == [10, 24, 40, 60])
        #expect(!ContentsReader.wantsModel(overview))

        let detailed = ContentsReader.read(Self.page([
            Self.line("Contents", x: 0.17, y: 0.10, size: 0.024),
            Self.line("cold starters", x: 0.17, y: 0.20, size: 0.018),
            Self.line("Chilled Pea Soup with Mint 12", x: 0.17, y: 0.25),
            Self.line("Crab Salad Cups 15", x: 0.17, y: 0.275),
            Self.line("Seared Scallops, Brown Butter 19", x: 0.17, y: 0.30),
            Self.line("desser", x: 0.57, y: 0.20, size: 0.016),
            Self.line("Ginger Ice Cream 62", x: 0.57, y: 0.25),
            Self.line("Plum Tart 65", x: 0.57, y: 0.275),
        ]))
        #expect(detailed.sections.map(\.title) == ["Cold Starters", "Desser"])
        let combined = ContentsReader.combine([overview, detailed])
        #expect(combined.sections.map(\.title) == ["Cold Starters", "Soups", "Grill", "Desserts"])
        #expect(combined.sections.map(\.page) == [10, 24, 40, 60])
        #expect(combined.sections.map(\.entries.count) == [3, 0, 0, 2])
    }

    @Test func aChapterRunsOnToTheNextPage() {
        let first = ContentsReader.read(Self.page([
            Self.line("SOUPS 10", x: 0.14, y: 0.20, size: 0.022),
            Self.line("Leek Soup 12", x: 0.14, y: 0.24),
            Self.line("Onion Soup 13", x: 0.14, y: 0.26),
        ]))
        let second = ContentsReader.read(Self.page([
            Self.line("Bean Soup 14", x: 0.14, y: 0.10),
            Self.line("Corn Chowder 16", x: 0.14, y: 0.12),
            Self.line("SALADS 20", x: 0.14, y: 0.16, size: 0.022),
            Self.line("Fennel Salad 22", x: 0.14, y: 0.20),
        ]))
        #expect(second.sections.first?.title == "")
        let combined = ContentsReader.combine([first, second])
        #expect(combined.sections.map(\.title) == ["Soups", "Salads"])
        #expect(combined.sections[0].entries.map(\.page) == [12, 13, 14, 16])
        #expect(combined.entries.count == 5)
    }

    /// Page numbers that run backwards are misreadings; a title can wrap over three lines; a column
    /// full of wrapped titles keeps the entries' own spacing.
    @Test func backwardPagesLongWrapsAndWrappedColumns() {
        let contents = ContentsReader.read(Self.page([
            Self.line("VEGETABLES 130", x: 0.14, y: 0.10, size: 0.022),
            Self.line("Roasted Leeks with Brown Butter 131", x: 0.14, y: 0.14),
            Self.line("Charred Cabbage with Anchovy, Lemon &", x: 0.14, y: 0.16),
            Self.line("Toasted Breadcrumbs 13", x: 0.14, y: 0.175),
            Self.line("Braised Fennel with Orange, Olives,", x: 0.14, y: 0.195),
            Self.line("Chile & Pine Nuts 136", x: 0.14, y: 0.21),
            Self.line("Glazed Turnips with Honey,", x: 0.14, y: 0.23),
            Self.line("Thyme & Black Pepper Butter on", x: 0.14, y: 0.245),
            Self.line("Grilled Bread 139", x: 0.14, y: 0.26),
            Self.line("Smashed Squash with Sage 941", x: 0.14, y: 0.28),
            Self.line("Grilled Corn with Lime 142", x: 0.14, y: 0.30),
            Self.line("Shaved Carrot Salad with Dates", x: 0.14, y: 0.32),
            Self.line("and Pistachios 144", x: 0.14, y: 0.335),
        ]))
        #expect(contents.sections.map(\.title) == ["Vegetables"])
        #expect(contents.entries.map(\.title) == [
            "Roasted Leeks with Brown Butter",
            "Charred Cabbage with Anchovy, Lemon & Toasted Breadcrumbs",
            "Braised Fennel with Orange, Olives, Chile & Pine Nuts",
            "Glazed Turnips with Honey, Thyme & Black Pepper Butter on Grilled Bread",
            "Smashed Squash with Sage",
            "Grilled Corn with Lime",
            "Shaved Carrot Salad with Dates and Pistachios",
        ])
        // 13 runs back after 131; 941 is the outlier before 142.
        #expect(contents.entries.map(\.page) == [131, nil, 136, 139, nil, 142, 144])
    }

    /// The iOS Simulator's recognizer can read one printed heading as two pieces side by side.
    @Test func piecesOfOnePrintedLineAreOneLine() {
        let contents = ContentsReader.read(Self.page([
            Self.line("SOU", x: 0.14, y: 0.20, size: 0.022),
            Self.line("PS & STEWS 10", x: 0.19, y: 0.20, size: 0.022),
            Self.line("Leek Soup 12", x: 0.14, y: 0.24),
            Self.line("Onion Soup 13", x: 0.14, y: 0.26),
            Self.line("Bean Soup 14", x: 0.14, y: 0.28),
        ]))
        #expect(contents.sections.map(\.title) == ["Sou Ps & Stews"])
        #expect(contents.sections.map(\.page) == [10])
        #expect(contents.entries.count == 3)
    }

    @Test func readsAnIndexPage() {
        let contents = ContentsReader.read(Self.page([
            Self.line("Leek soup, 16, 42", x: 0.1, y: 0.2),
            Self.line("Lentils: warm salad, 27", x: 0.1, y: 0.22),
            Self.line("Lemon curd, 88–89", x: 0.1, y: 0.24),
        ], kind: .index))
        #expect(contents.sections.map(\.title) == ["Index"])
        #expect(contents.entries == [
            BookContents.Entry(title: "Leek soup", page: 16),
            BookContents.Entry(title: "Lentils: warm salad", page: 27),
            BookContents.Entry(title: "Lemon curd", page: 88),
        ])
        // An index fills in only where the contents pages listed no recipes.
        let chapters = BookContents(sections: [BookContents.Section(title: "Soups", page: 10)], isOverview: true)
        #expect(ContentsReader.combine([chapters], indexPages: [contents]).entries.count == 3)
        let listed = BookContents(sections: [BookContents.Section(title: "Soups", entries: [BookContents.Entry(title: "Leek Soup", page: 16)])])
        #expect(ContentsReader.combine([listed], indexPages: [contents]).entries.count == 1)
    }

    // MARK: - The model

    /// A stand-in model that reads the contents it is given and counts how often it is asked.
    final class ContentsModel: PageStructuring, Sendable {
        let draft: StructuredContentsDraft
        let calls = Mutex(0)

        init(_ draft: StructuredContentsDraft) { self.draft = draft }

        var isAvailable: Bool { true }
        func structure(pageText: String) async throws -> StructuredPageDraft {
            StructuredPageDraft(title: "", ingredients: [], steps: [], confidence: 0)
        }
        func structureContents(pageText: String) async throws -> StructuredContentsDraft {
            calls.withLock { $0 += 1 }
            return draft
        }
    }

    @Test func theModelReadsOnlyAWeakPageAndOnlyKeepsABetterReading() async {
        let weak = Self.page([
            Self.line("Soups", x: 0.14, y: 0.20, size: 0.022),
            Self.line("Leek Soup", x: 0.14, y: 0.24),
            Self.line("Onion Soup", x: 0.14, y: 0.26),
        ])
        let read = StructuredContentsDraft(sections: [
            .init(title: "Soups", page: 10, entries: [.init(title: "Leek Soup", page: 12), .init(title: "Onion Soup", page: 13), .init(title: "Bean Soup", page: 15)]),
            .init(title: "Salads", page: 20, entries: [.init(title: "Fennel Salad", page: 22), .init(title: "Herb Salad", page: 24)]),
        ])
        let model = ContentsModel(read)
        let pipeline = PagePipeline(model: model)
        let contents = await pipeline.readContents(weak)
        #expect(contents.method == .model)
        #expect(contents.pagedEntryCount == 5)
        #expect(contents.sections.map(\.title) == ["Soups", "Salads"])

        // Page numbers no contents page would print are not kept.
        let scrambled = ContentsModel(StructuredContentsDraft(sections: [
            .init(title: "", entries: [.init(title: "A", page: 300), .init(title: "Bb", page: 12), .init(title: "Cc", page: 250), .init(title: "Dd", page: 4), .init(title: "Ee", page: 190)]),
        ]))
        #expect(await PagePipeline(model: scrambled).readContents(weak).method == .pageText)

        // A page that reads well is never sent.
        let full = Self.page([
            Self.line("SOUPS 10", x: 0.14, y: 0.20, size: 0.022),
            Self.line("Leek Soup 12", x: 0.14, y: 0.24),
            Self.line("Onion Soup 13", x: 0.14, y: 0.26),
            Self.line("Bean Soup 14", x: 0.14, y: 0.28),
            Self.line("Corn Chowder 16", x: 0.14, y: 0.30),
        ])
        let unused = ContentsModel(read)
        #expect(await PagePipeline(model: unused).readContents(full).method == .pageText)
        #expect(unused.calls.withLock { $0 } == 0)
        #expect(model.calls.withLock { $0 } == 1)
    }

    // MARK: - Courses and the punchlist

    @Test(arguments: [
        ("SALADS", "Salad"), ("Soups, Stews & Grains", "Soup"), ("cold appetizers", "Starter"), ("Starters", "Starter"),
        ("Vegetables", "Side"), ("Sides", "Side"), ("Fish and Shellfish", "Main"), ("Meat", "Main"), ("Poultry", "Main"),
        ("Pasta", "Main"), ("Main Courses", "Main"), ("First Courses", "Starter"), ("Desserts", "Dessert"),
        ("Sweets", "Dessert"), ("Breads", "Bread"), ("Condiments & Pickles", "Sauce"), ("Sauces", "Sauce"),
        ("Basics", "Sauce"), ("Drinks", "Drink"), ("cocktails", "Drink"), ("Breakfast", "Breakfast"), ("Snacks", "Snack"),
        ("Small Plates", "Starter"),
    ])
    func chaptersSuggestACourse(title: String, course: String) {
        #expect(ChapterCourse.course(forChapter: title) == course)
    }

    @Test(arguments: ["Grains", "Fry", "Roots", "The Mighty Squash", "Small Batch Ferments"])
    func otherChaptersSuggestNone(title: String) {
        #expect(ChapterCourse.course(forChapter: title) == nil)
    }

    static let entries: [PunchlistMatcher.Entry] = [
        .init(title: "Herb Oil", page: 44),
        .init(title: "Smoked Paprika Butter", page: 46),
        .init(title: "Charred Scallion Relish", page: 46),
        .init(title: "Green Olive Tapenade", page: 47),
        .init(title: "Quick Pickled Shallots", page: 48),
        .init(title: "Toasted Seed Crunch", page: nil),
    ]

    @Test func matchesAPagesRecipesToItsEntries() {
        // Two recipes on page 46, read in either order, each finds its own entry by title.
        #expect(PunchlistMatcher.match(titles: ["Charred Scalion Relish", "Smoked Paprika Butter"], pages: [46], entries: Self.entries, current: 0) == [2, 1])
        // Titles that tell nothing: the page's entries in order.
        #expect(PunchlistMatcher.match(titles: ["", ""], pages: [46], entries: Self.entries, current: 0) == [1, 2])
        // A page number one off finds its entry only when the title agrees.
        #expect(PunchlistMatcher.match(titles: ["Green Olive Tapenade"], pages: [48], entries: Self.entries, current: 0) == [3])
        #expect(PunchlistMatcher.match(titles: ["A Recipe Not Listed"], pages: [49], entries: Self.entries, current: 0) == [nil])
        // A page number misread: the title finds it anywhere on the list.
        #expect(PunchlistMatcher.match(titles: ["Quick Pickled Shallots"], pages: [16], entries: Self.entries, current: 0) == [4])
    }

    /// A recipe over two photos whose first page read no number starts the page before the second.
    @Test func aJoinedReadingCountsItsFirstPageBack() {
        #expect(PunchlistMatcher.pages(read: [nil, 26]) == [25, 26])
        #expect(PunchlistMatcher.pages(read: [46]) == [46])
        #expect(PunchlistMatcher.pages(read: [12, nil]) == [12, 13])
        #expect(PunchlistMatcher.pages(read: [nil]).isEmpty)
        // Matched by the page it starts on, a title that agrees beating the second page's entry.
        let entries: [PunchlistMatcher.Entry] = [.init(title: "Clams with Lemon Butter", page: 25), .init(title: "Mussels in Cider", page: 26)]
        #expect(PunchlistMatcher.match(titles: ["Clams with Lemon Butter"], pages: PunchlistMatcher.pages(read: [nil, 26]), entries: entries, current: nil) == [0])
    }

    @Test func aCaptureWithNoPageNumberIsTheCurrentItem() {
        #expect(PunchlistMatcher.match(titles: ["Toasted Seed Crunch"], pages: [], entries: Self.entries, current: 5) == [5])
        #expect(PunchlistMatcher.match(titles: [""], pages: [], entries: Self.entries, current: 3) == [3])
        // Unless its title is plainly another entry's.
        #expect(PunchlistMatcher.match(titles: ["Herb Oil"], pages: [], entries: Self.entries, current: 3) == [0])
    }

    @Test func theCurrentItemMovesToTheNextUncaptured() {
        var entries = Self.entries
        entries[2].isCaptured = true
        entries[3].isCaptured = true
        #expect(PunchlistMatcher.next(after: 1, in: entries) == 4)
        #expect(PunchlistMatcher.next(after: 5, in: entries) == 0)
        #expect(PunchlistMatcher.next(after: nil, in: entries) == 0)
        #expect(PunchlistMatcher.next(after: 0, in: entries.map { var entry = $0; entry.isCaptured = true; return entry }) == nil)
    }
}
