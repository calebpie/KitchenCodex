import Capture
import Foundation
import RecipeModel
import SwiftData
import UIKit

// Reference reading read off a page (02 §4.2, 04 §5.1 "Page pointers", "References home"): a
// glossary, a chapter opener or a technique saved as a `Reference` with its sections, its source
// (the book and pages) and its page scans, kept as a recipe keeps its own; linked to the entry at
// its page and, as related reading, to the recipes whose pointers put that page on the book's
// to-scan list. An article from the web saves through `ImportedReference.save(in:)`, which the
// Share Extension shares.

@MainActor
enum ReferenceSaving {
    /// A page's reading saved into `book` with the page scans of `model`: a new Reference, or the
    /// glossary it continues when the pages run on from one already captured (its entries follow,
    /// its pages extend), so a glossary over four pages is one Reference.
    @discardableResult
    static func save(_ imported: ImportedReference, model: ScanReviewModel, book: Book, images: ScanSaving.PageImages, reviewed: Bool, in context: ModelContext) async -> Reference {
        let pages = model.pages.compactMap(\.pageNumber)
        let reference: Reference
        if imported.kind == .glossary, let glossary = book.glossary(adjacentTo: pages) {
            reference = glossary
            let next = (reference.sections ?? []).map(\.sortOrder).max().map { $0 + 1 } ?? 0
            add(imported.sections, to: reference, from: next, in: context)
            if let source = reference.source, let first = pages.min(), let last = pages.max() {
                let low = min(source.firstPage ?? first, first)
                let high = max(source.lastPage ?? source.firstPage ?? last, last)
                source.firstPage = low
                source.lastPage = high == low ? nil : high
            }
        } else {
            reference = Reference(title: imported.title, author: book.author, kind: imported.referenceKind)
            context.insert(reference)
            reference.book = book
            add(imported.sections, to: reference, from: 0, in: context)
            let source = SourceInfo()
            source.captureMethod = .photo
            source.importedAt = .now
            source.firstPage = pages.min()
            source.lastPage = pages.count > 1 ? pages.max() : nil
            source.reviewedAt = reviewed ? .now : nil
            context.insert(source)
            reference.source = source
        }
        await attachPageScans(model, to: reference, book: book, images: images, in: context)
        try? context.save()
        link(reference, pages: pages, in: book, context: context)
        if reference.title.isEmpty {
            reference.title = reference.bookEntry?.title ?? pages.first.map { "Page \($0)" } ?? "Reference"
        }
        try? context.save()
        return reference
    }

    private static func add(_ sections: [ImportedReference.Section], to reference: Reference, from start: Int, in context: ModelContext) {
        for (offset, section) in sections.enumerated() {
            let stored = ReferenceSection(heading: section.heading, body: section.body, sortOrder: start + offset)
            context.insert(stored)
            stored.reference = reference
        }
    }

    /// The pointers to `pages` on the book's to-scan list: the recipes pointing there read this as
    /// related reading, the entry at the page is the reference's (or, made by a pointer, goes now
    /// that the page is captured), and a listed entry with nothing captured takes it.
    static func link(_ reference: Reference, pages: [Int], in book: Book, context: ModelContext) {
        let fetch = { (id: UUID) in try? context.fetch(FetchDescriptor<Recipe>(predicate: #Predicate { $0.id == id })).first }
        BookScanStore.shared.updateState(for: book) { state in
            for pointer in state.pointerEntries where pages.contains(pointer.page) && pointer.kind != PageCrossReference.Kind.sources.rawValue {
                for id in pointer.recipes {
                    guard let recipe = fetch(id), !(reference.recipes ?? []).contains(recipe) else { continue }
                    reference.recipes = (reference.recipes ?? []) + [recipe]
                }
                guard let entry = book.orderedEntries.first(where: { $0.id == pointer.entry }) else { continue }
                if reference.bookEntry == nil, entry.reference == nil, entry.recipe == nil {
                    entry.reference = reference
                    entry.status = .captured
                } else if pointer.madeEntry, entry.recipe == nil, entry.reference == nil {
                    context.delete(entry)
                } else if entry.recipe == nil {
                    entry.status = .captured
                }
            }
        }
        if reference.bookEntry == nil,
           let entry = book.orderedEntries.first(where: { entry in pages.contains(entry.page ?? -1) && entry.recipe == nil && entry.reference == nil }) {
            entry.reference = reference
            entry.status = .captured
        }
        try? context.save()
    }

    /// The page scans, with their regions and no recipe, on the reference and the book.
    private static func attachPageScans(_ model: ScanReviewModel, to reference: Reference, book: Book, images: ScanSaving.PageImages, in context: ModelContext) async {
        for page in model.pages {
            guard let data = await images.jpeg(page) else { continue }
            let scan = RecipeImage(role: .pageScan, imageData: data)
            context.insert(scan)
            scan.caption = "Page"
            scan.pageNumber = page.pageNumber
            scan.pageKind = .reference
            scan.regions = try? model.scanRegions(page: page.id).encoded()
            scan.book = book
            scan.reference = reference
        }
    }

    /// The cook has looked (the review queue's Save): its entry reviewed, its source dated.
    static func markReviewed(_ reference: Reference, in context: ModelContext) {
        reference.source?.reviewedAt = .now
        if let entry = reference.bookEntry { entry.status = .reviewed }
        if let book = reference.book {
            let id = reference.id
            BookScanStore.shared.updateState(for: book) { state in
                for index in state.captures.indices where state.captures[index].references.contains(id) {
                    state.captures[index].queued = false
                }
            }
        }
        try? context.save()
    }

    /// Deleting a reference takes its sections, source and images (the schema cascades) and
    /// unlinks its recipes; its entry is listed again.
    static func delete(_ reference: Reference, in context: ModelContext) {
        reference.recipes = []
        if let entry = reference.bookEntry {
            entry.status = .listed
            reference.bookEntry = nil
        }
        context.delete(reference)
        try? context.save()
    }

    /// The references waiting in a book's review queue (02 Flow C step 7): the ones a session
    /// marked for a look, the cook's Needs Review or a reading that fell short, not yet saved
    /// there.
    static func reviewQueue(for book: Book) -> [Reference] {
        guard let state = BookScanStore.shared.state(for: book) else { return [] }
        let queued = Set(state.captures.filter(\.queued).flatMap(\.references))
        return (book.references ?? []).filter { queued.contains($0.id) && $0.source?.reviewedAt == nil }.sorted { $0.capturedAt < $1.capturedAt }
    }
}

extension Book {
    /// The glossary a page continues: a glossary Reference whose pages run on to these, or that
    /// these run on to.
    func glossary(adjacentTo pages: [Int]) -> Reference? {
        guard let low = pages.min(), let high = pages.max() else { return nil }
        return (references ?? []).first { reference in
            guard reference.kind == .chapter, reference.title.localizedCaseInsensitiveCompare("Glossary") == .orderedSame,
                  let first = reference.source?.firstPage else { return false }
            let last = reference.source?.lastPage ?? first
            return (first - 1)...(last + 1) ~= low || (first - 1)...(last + 1) ~= high
        }
    }

    /// The book's page scans read as its Sources page (02 Flow C step 8).
    var sourcesPages: [RecipeImage] {
        (pageScans ?? []).filter { $0.pageKind == .sources }
    }
}

extension Reference {
    /// Where it came from, as the page and the pane show it: "Nobu West, pp. 250–253", "A scanned
    /// page", or the site and author.
    var sourceLine: String {
        if let book {
            if let first = source?.firstPage, let last = source?.lastPage, last != first {
                return "\(book.displayTitle), pp. \(first)–\(last)"
            }
            if let page = source?.firstPage ?? bookEntry?.page { return "\(book.displayTitle), p. \(page)" }
            return book.displayTitle
        }
        if let source, source.url == nil, source.captureMethod == .photo || source.captureMethod == .scan {
            return (source.firstPage).map { "A scanned page, p. \($0)" } ?? "A scanned page"
        }
        if let source {
            let site = source.siteName ?? source.url?.host()?.replacingOccurrences(of: "www.", with: "") ?? ""
            let line = [site, source.author].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
            return line.isEmpty ? "Saved \(capturedAt.formatted(date: .abbreviated, time: .omitted))" : line
        }
        return "Saved \(capturedAt.formatted(date: .abbreviated, time: .omitted))"
    }

    /// Its sections in order.
    var sortedSections: [ReferenceSection] {
        (sections ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Its page scans in page order.
    var pageScans: [RecipeImage] {
        (images ?? []).filter { $0.role == .pageScan }.sorted { ($0.pageNumber ?? .max, $0.createdAt) < ($1.pageNumber ?? .max, $1.createdAt) }
    }

    /// The recipes it informs, by title.
    var sortedRecipes: [Recipe] {
        (recipes ?? []).sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// The section a pointer's term names ("yama-imo"): the entry headed by it, or the nearest.
    func section(matching term: String?) -> ReferenceSection? {
        guard let term, !term.isEmpty else { return nil }
        let key = Self.key(term)
        guard !key.isEmpty else { return nil }
        let sections = sortedSections.filter { !$0.heading.isEmpty }
        if let exact = sections.first(where: { Self.key($0.heading) == key }) { return exact }
        if let within = sections.first(where: { let heading = Self.key($0.heading); return !heading.isEmpty && (heading.contains(key) || key.contains(heading)) }) { return within }
        let best = sections.max { PunchlistMatcher.similarity($0.heading, term) < PunchlistMatcher.similarity($1.heading, term) }
        return best.flatMap { PunchlistMatcher.similarity($0.heading, term) >= 0.6 ? $0 : nil }
    }

    /// Letters and digits, folded, with single spaces, for matching a term to a heading.
    private static func key(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return folded.split { !($0.isLetter || $0.isNumber) }.joined(separator: " ")
    }
}

extension ReferenceKind {
    /// The word the pane and the page use.
    var word: String {
        switch self {
        case .article: "Article"
        case .technique: "Technique"
        case .chapter: "Chapter"
        case .clipping: "Clipping"
        }
    }

    var plural: String {
        switch self {
        case .article: "articles"
        case .technique: "techniques"
        case .chapter: "chapters"
        case .clipping: "clippings"
        }
    }
}
