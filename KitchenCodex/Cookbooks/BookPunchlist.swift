import Capture
import Foundation
import RecipeModel
import SwiftData

// A book's punchlist (02 Flow C step 3, 03 §3.7–3.8): the sections and entries read off its
// contents pages, kept in step by the whole-book session, corrected inline by the cook.

extension Book {
    var orderedSections: [BookSection] {
        (sections ?? []).sorted { ($0.sortOrder, $0.startPage ?? .max) < ($1.sortOrder, $1.startPage ?? .max) }
    }

    /// Every entry in the list's order: section by section, each in its own order.
    var orderedEntries: [BookEntry] { orderedSections.flatMap(\.orderedEntries) }

    /// The review queue (02 Flow C step 7): the book's scanned recipes waiting for a look, the
    /// oldest first, so the recipe that confirms the layout leads.
    var reviewQueue: [Recipe] {
        (recipes ?? []).filter { $0.needsReview && $0.isScanned }.sorted { $0.createdAt < $1.createdAt }
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
    /// and page); the rest are new sections after it. Nothing on the list is removed, so building
    /// it again after a session keeps the progress.
    func apply(_ contents: BookContents, in context: ModelContext) {
        var nextSection = (orderedSections.map(\.sortOrder).max() ?? -1) + 1
        for read in contents.sections {
            let title = read.title.isEmpty ? (orderedSections.last?.title ?? "") : read.title
            let section: BookSection
            if let existing = orderedSections.first(where: { PunchlistMatcher.similarity($0.title, title) >= 0.99 || $0.title == title }) {
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
                let listed = section.orderedEntries.contains { $0.page == item.page && PunchlistMatcher.similarity($0.title, item.title) >= 0.99 }
                guard !listed else { continue }
                let entry = BookEntry(title: item.title, page: item.page)
                entry.sortOrder = nextEntry
                nextEntry += 1
                context.insert(entry)
                entry.section = section
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

    /// The list as the matcher sees it.
    var matcherEntries: [PunchlistMatcher.Entry] {
        orderedEntries.map { PunchlistMatcher.Entry(title: $0.title, page: $0.page, isCaptured: $0.status != .listed) }
    }

    /// A `listed` entry the contents didn't have, placed by its page in the chapter the page falls
    /// in (the last chapter when the page comes after every first page); nil for a book with no
    /// chapters.
    func addEntry(title: String, page: Int, in context: ModelContext) -> BookEntry? {
        guard let section = section(forPage: page) ?? orderedSections.last else { return nil }
        let entry = BookEntry(title: title, page: page)
        entry.sortOrder = (section.orderedEntries.firstIndex { ($0.page ?? .max) > page }).map { section.orderedEntries[$0].sortOrder } ?? ((section.orderedEntries.map(\.sortOrder).max() ?? -1) + 1)
        for later in section.orderedEntries where later.sortOrder >= entry.sortOrder { later.sortOrder += 1 }
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

    static func match(titles: [String], pages: [Int], in book: Book, current: BookEntry?, courses choices: [UUID: String], createsMissing: Bool = true, context: ModelContext) -> Match {
        let entries = book.orderedEntries
        guard !entries.isEmpty || !book.orderedSections.isEmpty else {
            let course = ScanSession.lastCourse(of: book)
            return Match(entries: titles.map { _ in nil }, courses: titles.map { _ in course })
        }
        let indices = PunchlistMatcher.match(titles: titles, pages: pages, entries: book.matcherEntries, current: current.flatMap { entries.firstIndex(of: $0) })
        var matched: [BookEntry?] = []
        var created: [BookEntry] = []
        for (offset, index) in indices.enumerated() {
            if let index {
                matched.append(entries[index])
            } else if createsMissing, let page = pages.first, let entry = book.addEntry(title: titles[offset], page: page, in: context) {
                // A recipe the contents didn't list: the punchlist gains it, so the counts stay true.
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
