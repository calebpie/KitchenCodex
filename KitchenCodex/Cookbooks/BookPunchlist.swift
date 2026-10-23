import Capture
import Foundation
import RecipeModel
import SwiftData

// A book's punchlist (02 Flow C step 3, 03 §3.7–3.8): the sections and entries read off its
// contents pages, kept in step by the whole-book session, corrected inline by the cook.

extension Book {
    /// The chapters, in order. The book's index (`indexSection`) is not one.
    var orderedSections: [BookSection] {
        (sections ?? []).filter { !$0.isIndex }.sorted { ($0.sortOrder, $0.startPage ?? .max) < ($1.sortOrder, $1.startPage ?? .max) }
    }

    /// What the book's index pages list (ux-notes row 117): kept as a section titled Index beside
    /// the chapters, never one of them, so the punchlist's counts are the recipes the contents
    /// list and the session finds. The Index tab shows it.
    var indexSection: BookSection? { (sections ?? []).first(where: \.isIndex) }

    /// The index's entries in its order.
    var indexEntries: [BookEntry] { indexSection?.orderedEntries ?? [] }

    /// Every entry in the list's order: section by section, each in its own order.
    var orderedEntries: [BookEntry] { orderedSections.flatMap(\.orderedEntries) }

    /// The review queue (02 Flow C step 7): the book's scanned recipes waiting for a look, the
    /// oldest first, so the recipe that confirms the layout leads.
    var reviewQueue: [Recipe] {
        // A recipe deleted but not yet saved away stays in the book's array (ux-notes row 164).
        (recipes ?? []).filter { !$0.isDeleted && $0.needsReview && $0.isScanned }.sorted { $0.createdAt < $1.createdAt }
    }

    /// The section a page falls in: the last whose first page is at or before it, by its entries'
    /// pages where it prints none.
    func section(forPage page: Int) -> BookSection? {
        let starts = orderedSections.compactMap { section -> (BookSection, Int)? in
            guard let start = section.startPage ?? section.orderedEntries.compactMap(\.page).min() else { return nil }
            return (section, start)
        }
        return starts.last { $0.1 <= page }?.0 ?? starts.first?.0
    }

    /// The contents read off the book's contents pages, added to its punchlist as `listed` entries.
    /// A section already on the list with the same title gains the entries it lacks (same title
    /// and page), unless its first page says it is another chapter of that name; the rest are new
    /// sections after it. The index pages' entries go to the book's index. Nothing on the list is
    /// removed, so building it again after a session keeps the progress.
    func apply(_ contents: BookContents, in context: ModelContext) {
        var nextSection = (orderedSections.map(\.sortOrder).max() ?? -1) + 1
        for read in contents.sections {
            let title = read.title.isEmpty ? (orderedSections.last?.title ?? "") : read.title
            let section: BookSection
            if let existing = orderedSections.first(where: { section in
                (PunchlistMatcher.similarity(section.title, title) >= 0.99 || section.title == title)
                    && ContentsReader.sameChapter(BookContents.Section(title: section.title, page: section.startPage), BookContents.Section(title: section.title, page: read.page))
            }) {
                section = existing
                if section.startPage == nil { section.startPage = read.page }
            } else {
                section = BookSection(title: title, sortOrder: nextSection)
                nextSection += 1
                section.startPage = read.page
                context.insert(section)
                section.book = self
            }
            var nextEntry = (section.orderedEntries.map(\.sortOrder).max() ?? -1) + 1
            for item in read.entries {
                // Already listed in this chapter at this page with a close title (a second photo of
                // the same page read a letter off, ux-notes row 146): not listed twice.
                let listed = section.orderedEntries.contains { $0.page == item.page && PunchlistMatcher.similarity($0.title, item.title) >= (item.page == nil ? 0.99 : 0.6) }
                guard !listed else { continue }
                let entry = BookEntry(title: item.title, page: item.page)
                entry.sortOrder = nextEntry
                nextEntry += 1
                context.insert(entry)
                entry.section = section
            }
        }
        if !contents.index.isEmpty {
            let index = indexSection ?? {
                let made = BookSection(title: BookSection.indexTitle, sortOrder: 0)
                context.insert(made)
                made.book = self
                return made
            }()
            var nextEntry = (index.orderedEntries.map(\.sortOrder).max() ?? -1) + 1
            let listed = Set(index.orderedEntries.map { "\($0.title.lowercased())|\($0.page ?? -1)" })
            for item in contents.index where !listed.contains("\(item.title.lowercased())|\(item.page ?? -1)") {
                let entry = BookEntry(title: item.title, page: item.page)
                entry.sortOrder = nextEntry
                nextEntry += 1
                context.insert(entry)
                entry.section = index
            }
        }
        try? context.save()
    }

    /// An entry whose recipe or reference was deleted from the library is listed again (the
    /// schema's nullify leaves its status as it was). An entry captured as the book's Sources page
    /// (a page scan, no recipe) stays captured while the scan does.
    func reconcilePunchlist() {
        let scans = self.sourcesPages
        let sourcesPages = Set(scans.compactMap(\.pageNumber))
        // A Sources page scan whose page didn't read still captures the book's Sources entry.
        let sourcesEntry = scans.contains { $0.pageNumber == nil } ? self.sourcesEntry : nil
        for entry in orderedEntries where entry.status != .listed && entry.recipe == nil && entry.reference == nil {
            if entry == sourcesEntry { continue }
            if let page = entry.page, sourcesPages.contains(page) || !references(onPage: page).isEmpty { continue }
            entry.status = .listed
        }
    }

    /// The list as the matcher sees it, the entries page pointers made marked (ux-notes rows 155,
    /// 156).
    var matcherEntries: [PunchlistMatcher.Entry] {
        let pointerMade = Set(BookScanStore.shared.state(for: self)?.pointerEntries.filter(\.madeEntry).map(\.entry) ?? [])
        return orderedEntries.map { PunchlistMatcher.Entry(title: $0.title, page: $0.page, isCaptured: $0.status != .listed, isPointerMade: pointerMade.contains($0.id)) }
    }

    /// A `listed` entry the contents didn't have, placed by its page in the chapter the page falls
    /// in (the last chapter when the page comes after every first page), or, when its page didn't
    /// read, at the end of `chapter` (ux-notes row 155); nil for a book with no chapters.
    func addEntry(title: String, page: Int?, chapter: BookSection? = nil, in context: ModelContext) -> BookEntry? {
        guard let section = page.flatMap(section(forPage:)) ?? chapter ?? orderedSections.last else { return nil }
        let entry = BookEntry(title: title, page: page)
        if let page {
            entry.sortOrder = (section.orderedEntries.firstIndex { ($0.page ?? .max) > page }).map { section.orderedEntries[$0].sortOrder } ?? ((section.orderedEntries.map(\.sortOrder).max() ?? -1) + 1)
            for later in section.orderedEntries where later.sortOrder >= entry.sortOrder { later.sortOrder += 1 }
        } else {
            entry.sortOrder = (section.orderedEntries.map(\.sortOrder).max() ?? -1) + 1
        }
        context.insert(entry)
        entry.section = section
        return entry
    }

    /// The entry to scan `page` from (Scan page N, the cross-reference card's Add to this book's
    /// to-scan list): one already listed at that page with nothing captured, or a new `listed` one
    /// titled `title` in the chapter the page falls in. A book with no list yet gains a "To Scan"
    /// chapter for it, so the ring and Missing count it.
    func toScanEntry(page: Int, title: String, in context: ModelContext) -> (entry: BookEntry, isNew: Bool) {
        let open = orderedEntries.filter { $0.page == page && $0.recipe == nil && $0.reference == nil }
        if let existing = open.max(by: { PunchlistMatcher.similarity($0.title, title) < PunchlistMatcher.similarity($1.title, title) }) {
            return (existing, false)
        }
        if orderedSections.isEmpty {
            let section = BookSection(title: "To Scan", sortOrder: 0)
            context.insert(section)
            section.book = self
        }
        let entry = addEntry(title: title, page: page, in: context)!
        try? context.save()
        return (entry, true)
    }
}

extension BookSection {
    var orderedEntries: [BookEntry] { (entries ?? []).sorted { $0.sortOrder < $1.sortOrder } }

    /// The book's index (`Book.indexSection`), by its title: the editor lists chapters only, so the
    /// cook never names one this.
    static let indexTitle = "Index"
    var isIndex: Bool { title == Self.indexTitle }

    var displayTitle: String { title.isEmpty ? "Untitled Section" : title }

    /// "8 of 12": entries past `listed`.
    var capturedCount: Int { (entries ?? []).count { $0.status != .listed } }

    /// The course its recipes are saved with (ux-notes row 73): the one the cook chose for it in a
    /// session, else the one its saved recipes carry most, else what its title suggests.
    func course(choices: [UUID: String]) -> String? {
        if let chosen = choices[id] { return chosen.isEmpty ? nil : chosen }
        let carried = orderedEntries.compactMap { $0.recipe?.course }
        if let common = Dictionary(grouping: carried, by: \.self).max(by: { $0.value.count < $1.value.count })?.key { return common }
        return ChapterCourse.course(forChapter: title)
    }
}

extension BookEntry {
    var displayTitle: String { title.isEmpty ? "Untitled Recipe" : title }
}

extension Recipe {
    /// A recipe about to be deleted gives its punchlist entry back, listed again at once (ux-notes
    /// row 141), as the session's own delete does, so the book's list is right on return.
    func releaseBookEntry() {
        guard let entry = bookEntry else { return }
        entry.status = .listed
        bookEntry = nil
    }
}

/// Linking saved recipes to their punchlist entries, for the book session and for a page scanned on
/// its own into a book that has a punchlist: page first, then title (`PunchlistMatcher`).
@MainActor
enum PunchlistLinking {
    /// The entries for the recipes read off one capture, an entry made for a recipe the list
    /// lacks (in the section its page falls in), and the course each is saved with. Nothing is
    /// changed but the new entries.
    struct Match {
        var entries: [BookEntry?]
        var courses: [String?]
        /// The entries made for recipes the list lacked, so taking the capture back takes them too.
        var created: [BookEntry] = []
    }

    static func match(titles: [String], pages: [Int], in book: Book, current: BookEntry?, courses choices: [UUID: String], createsMissing: Bool = true, growsList: Bool = false, context: ModelContext) -> Match {
        let entries = book.orderedEntries
        guard !entries.isEmpty || !book.orderedSections.isEmpty || growsList && createsMissing && !pages.isEmpty else {
            let course = ScanSession.lastCourse(of: book)
            return Match(entries: titles.map { _ in nil }, courses: titles.map { _ in course })
        }
        // The book session with no list (Scan Recipes Instead, ux-notes row 114): the list grows
        // as pages are scanned, in a Recipes chapter.
        if book.orderedSections.isEmpty {
            let section = BookSection(title: "Recipes", sortOrder: 0)
            context.insert(section)
            section.book = book
        }
        let indices = PunchlistMatcher.match(titles: titles, pages: pages, entries: book.matcherEntries, current: current.flatMap { entries.firstIndex(of: $0) })
        var matched: [BookEntry?] = []
        var created: [BookEntry] = []
        for (offset, index) in indices.enumerated() {
            if let index {
                matched.append(entries[index])
            } else if createsMissing, let entry = book.addEntry(title: titles[offset], page: pages.first, chapter: current?.section, in: context) {
                // A recipe the contents didn't list: the punchlist gains it, so the counts stay
                // true, even when its page didn't read (ux-notes row 155), in the current entry's
                // chapter.
                matched.append(entry)
                created.append(entry)
            } else {
                matched.append(nil)
            }
        }
        let courses = matched.map { entry -> String? in
            if let section = entry?.section { return section.course(choices: choices) }
            // Not on the list: the chapter its page falls in.
            if let page = pages.first, let section = book.section(forPage: page) { return section.course(choices: choices) }
            return ScanSession.lastCourse(of: book)
        }
        return Match(entries: matched, courses: courses, created: created)
    }

    /// The recipe is its entry's: captured, or reviewed when the cook went through review. An entry
    /// another recipe already has keeps it (a page shot again); false then.
    @discardableResult
    static func link(_ recipe: Recipe, to entry: BookEntry?, reviewed: Bool) -> Bool {
        // The entry can go while the recipe is being saved (the list edited after Close).
        guard let entry, !entry.isDeleted else { return false }
        if let other = entry.recipe, other != recipe, other.modelContext != nil, !other.isDeleted { return false }
        recipe.bookEntry = entry
        entry.status = reviewed ? .reviewed : .captured
        return true
    }
}
