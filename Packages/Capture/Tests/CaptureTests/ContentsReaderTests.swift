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
        #expect(contents.sections.isEmpty)
        #expect(contents.index == [
            BookContents.Entry(title: "Leek soup", page: 16),
            BookContents.Entry(title: "Lentils: warm salad", page: 27),
            BookContents.Entry(title: "Lemon curd", page: 88),
        ])
        #expect(!ContentsReader.wantsModel(contents))
        // The index is the book's Index tab, apart from its chapters (ux-notes row 117): a list of
        // chapters stays chapters, and the index pages add no entries to it.
        let chapters = BookContents(sections: [BookContents.Section(title: "Soups", page: 10)], isOverview: true)
        let combined = ContentsReader.combine([chapters], indexPages: [contents, contents])
        #expect(combined.sections.map(\.title) == ["Soups"])
        #expect(combined.entries.isEmpty)
        #expect(combined.index.count == 3)
    }

    /// A headword ending in a colon heads the indented lines under it; a line that runs over is one
    /// entry; "see also" and a letter heading are not entries.
    @Test func readsAnIndexWithHeadwords() {
        let contents = ContentsReader.read(Self.page([
            Self.line("chard:", x: 0.10, y: 0.20),
            Self.line("in spring gratin, 41", x: 0.115, y: 0.215),
            Self.line("with brown butter and toasted", x: 0.115, y: 0.23),
            Self.line("hazelnuts, 63–64", x: 0.13, y: 0.245),
            Self.line("see also greens", x: 0.115, y: 0.26),
            Self.line("cherry clafoutis, 280", x: 0.10, y: 0.275),
            Self.line("E", x: 0.10, y: 0.30, size: 0.02),
            Self.line("eggplant, smoked, 112", x: 0.10, y: 0.33),
        ], kind: .index))
        #expect(contents.index == [
            BookContents.Entry(title: "Chard, in spring gratin", page: 41),
            BookContents.Entry(title: "Chard, with brown butter and toasted hazelnuts", page: 63),
            BookContents.Entry(title: "Cherry clafoutis", page: 280),
            BookContents.Entry(title: "Eggplant, smoked", page: 112),
        ])
    }

    // MARK: - Ux-notes rows 118 and 119

    /// Caleb's rule: an entry is complete only when a page number closes it. A title wrapped at a
    /// plain word, with nothing else to say so, joins the line below; a short entry whose page
    /// didn't read, a line whose number is there but unread, and (in a sentence-case book) a line
    /// starting with a capital stay entries of their own.
    @Test func anEntryRunsOnUntilAPageNumberClosesIt() {
        let titles: [(String, Double, String?)] = [
            ("Seared Scallops with Charred Leeks and Smoked", 0.20, nil),
            ("Butter Sauce", 0.22, "41"),
            ("Pickled Plums", 0.24, nil),
            ("Chilled Melon Soup with Sumac and Lime Granita", 0.26, "45"),
            ("Duck Breast with Sour Cherries and Five-Spice", 0.28, nil),
            ("Glaze and Crisp Shallots", 0.30, "48"),
        ]
        var lines = titles.map { Self.line($0.0, x: 0.12, y: $0.1) }
        lines += titles.compactMap { title in title.2.map { Self.line($0, x: 0.56, y: title.1) } }
        lines.insert(Self.line("FIRST COURSES", x: 0.12, y: 0.15, size: 0.018), at: 0)
        let contents = ContentsReader.read(Self.page(lines))
        #expect(contents.entries == [
            BookContents.Entry(title: "Seared Scallops with Charred Leeks and Smoked Butter Sauce", page: 41),
            BookContents.Entry(title: "Pickled Plums", page: nil),
            BookContents.Entry(title: "Chilled Melon Soup with Sumac and Lime Granita", page: 45),
            BookContents.Entry(title: "Duck Breast with Sour Cherries and Five-Spice Glaze and Crisp Shallots", page: 48),
        ])

        // Sentence case: a capital starts a new entry, though the line above fills the column.
        let sentence = ContentsReader.read(Self.page([
            Self.line("Grains", x: 0.12, y: 0.18, size: 0.018),
            Self.line("Barley risotto with roasted squash and sage", x: 0.12, y: 0.20),
            Self.line("Farro salad with herbs 12", x: 0.12, y: 0.22),
            Self.line("Freekeh with charred onions and yogurt 14", x: 0.12, y: 0.24),
            Self.line("Millet cakes with a quick tomato sauce", x: 0.12, y: 0.26),
            Self.line("and greens 17", x: 0.12, y: 0.28),
        ]))
        #expect(sentence.entries.map(\.title) == ["Barley risotto with roasted squash and sage", "Farro salad with herbs", "Freekeh with charred onions and yogurt", "Millet cakes with a quick tomato sauce and greens"])
        #expect(sentence.entries.map(\.page) == [nil, 12, 14, 17])
    }

    /// Columns read in the order their page numbers run, whatever their place across the page; a
    /// column with no heading continues the section before, within a page as across pages.
    @Test func columnsFollowThePageNumbers() {
        let contents = ContentsReader.read(Self.page([
            // The right column holds the earlier pages (the book turned, the facing page's column).
            Self.line("SOUPS", x: 0.56, y: 0.15, size: 0.018),
            Self.line("Leek Soup 12", x: 0.56, y: 0.20),
            Self.line("Onion Soup 13", x: 0.56, y: 0.22),
            Self.line("Bean Soup 14", x: 0.56, y: 0.24),
            Self.line("Corn Chowder 16", x: 0.12, y: 0.20),
            Self.line("Fish Stew 18", x: 0.12, y: 0.22),
            Self.line("Pea Soup 19", x: 0.12, y: 0.24),
        ]))
        #expect(contents.sections.map(\.title) == ["Soups"])
        #expect(contents.entries.map(\.page) == [12, 13, 14, 16, 18, 19])
    }

    /// Text outside the page's outline (a label beside the book) is dropped; a heading just outside
    /// it that lines up with the page's column stays; a page-less heading over page-less entries
    /// on a page that prints pages is noise.
    @Test func whatLiesBesideTheBookIsDropped() {
        var reading = Self.page([
            Self.line("Shop Label Model X12", x: 0.02, y: 0.03),
            Self.line("Made in Somewhere", x: 0.02, y: 0.05),
            Self.line("STARTERS", x: 0.20, y: 0.14, size: 0.018),
            Self.line("Radish Butter Toast 10", x: 0.20, y: 0.20),
            Self.line("Smoked Trout Rillettes 12", x: 0.20, y: 0.22),
            Self.line("Fried Olives 14", x: 0.20, y: 0.24),
            Self.line("Chicken Liver Mousse 16", x: 0.20, y: 0.26),
            Self.line("Fava Bean Crostini 18", x: 0.20, y: 0.28),
            Self.line("Grilled Sardines 20", x: 0.20, y: 0.30),
            Self.line("Marinated Peppers 22", x: 0.20, y: 0.32),
            Self.line("Salt Cod Fritters 24", x: 0.20, y: 0.34),
            Self.line("Deviled Eggs 26", x: 0.20, y: 0.36),
            Self.line("Another Book's Cover", x: 0.60, y: 0.70, size: 0.02),
            Self.line("Weeknights and", x: 0.60, y: 0.73),
            Self.line("Everything Else", x: 0.60, y: 0.75),
        ])
        reading.outline = PageQuad(topLeft: PagePoint(x: 0.15, y: 0.16), topRight: PagePoint(x: 0.55, y: 0.16),
                                   bottomRight: PagePoint(x: 0.55, y: 0.40), bottomLeft: PagePoint(x: 0.15, y: 0.40))
        let contents = ContentsReader.read(reading)
        #expect(contents.sections.map(\.title) == ["Starters"])
        #expect(contents.entries.count == 9)

        // Without the outline the label still goes, as noise.
        reading.outline = nil
        #expect(!ContentsReader.read(reading).sections.map(\.title).contains("Another Book's Cover"))
    }

    /// An overview printed in groups: a chapter's line, then its name in a second language and its
    /// companion essay set close under it (ux-notes row 96): only the chapter, which takes the
    /// essay's page when its own didn't read. A chapter printed twice under two parts stays two.
    @Test func anOverviewsEssaysAreNeitherChapterNorEntry() {
        let first = ContentsReader.read(Self.page([
            Self.line("SOUPS", x: 0.12, y: 0.20),
            Self.line("LES SOUPES", x: 0.12, y: 0.215),
            Self.line("ON MAKING STOCK 30", x: 0.12, y: 0.23),
            Self.line("GRAINS 44", x: 0.12, y: 0.26),
            Self.line("ON SOAKING GRAINS 45", x: 0.12, y: 0.275),
            Self.line("FISH 60", x: 0.12, y: 0.305),
            Self.line("THE MARKET 72", x: 0.12, y: 0.32),
            Self.line("BREADS 90", x: 0.12, y: 0.35),
        ]))
        #expect(first.isOverview)
        #expect(first.sections.map(\.title) == ["Soups", "Grains", "Fish", "Breads"])
        #expect(first.sections.map(\.page) == [30, 44, 60, 90])
        let second = ContentsReader.read(Self.page([
            Self.line("MAINS 120", x: 0.12, y: 0.20),
            Self.line("FISH 128", x: 0.12, y: 0.23),
            Self.line("MEAT 150", x: 0.12, y: 0.26),
            Self.line("DESSERTS 190", x: 0.12, y: 0.29),
        ]))
        let combined = ContentsReader.combine([first, second])
        #expect(combined.sections.map(\.title) == ["Soups", "Grains", "Fish", "Breads", "Mains", "Fish", "Meat", "Desserts"])
    }

    /// Two photos overlapping list an entry once.
    @Test func overlappingPhotosListAnEntryOnce() {
        let first = BookContents(sections: [BookContents.Section(title: "Soups", page: 10, entries: [.init(title: "Leek Soup", page: 12), .init(title: "Onion Soup", page: 13)])])
        let second = BookContents(sections: [BookContents.Section(title: "", entries: [.init(title: "Onion Soup", page: 13), .init(title: "Bean Soup", page: 14)])])
        #expect(ContentsReader.combine([first, second]).entries.map(\.title) == ["Leek Soup", "Onion Soup", "Bean Soup"])
    }

    // MARK: - What the page is (ux-notes row 114)

    @Test func tellsAContentsPageFromARecipePage() {
        let contents = Self.page([
            Self.line("SOUPS 10", x: 0.14, y: 0.20, size: 0.022),
            Self.line("Leek Soup 12", x: 0.14, y: 0.24),
            Self.line("Onion Soup 13", x: 0.14, y: 0.26),
            Self.line("Bean Soup 14", x: 0.14, y: 0.28),
            Self.line("Corn Chowder 16", x: 0.14, y: 0.30),
            Self.line("Fish Stew 18", x: 0.14, y: 0.32),
        ])
        #expect(ContentsReader.judge(contents) == .contents)
        let recipe = Self.page([
            Self.line("Leek and Potato Soup", x: 0.14, y: 0.10, size: 0.024),
            Self.line("Serves 4", x: 0.14, y: 0.15),
            Self.line("2 tablespoons butter", x: 0.14, y: 0.20),
            Self.line("3 large leeks, sliced", x: 0.14, y: 0.22),
            Self.line("1 pound potatoes, diced", x: 0.14, y: 0.24),
            Self.line("4 cups chicken stock", x: 0.14, y: 0.26),
            Self.line("1 teaspoon salt", x: 0.14, y: 0.28),
            Self.line("Melt the butter in a large pot over medium heat and add the leeks.", x: 0.14, y: 0.32),
        ], kind: .recipe)
        #expect(ContentsReader.judge(recipe) == .recipe)
        #expect(ContentsReader.judge(Self.page([Self.line("A note on the text", x: 0.14, y: 0.2)], kind: .prose)) == .unsure)
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
