import Capture
import Foundation
import RecipeModel
import SwiftData

// Cross-references (02 Flow C step 6, 04 §5.1 "Page pointers", ux-notes row 74): a scanned
// recipe's pointers to other pages, linked to the component recipe the page holds, put on the
// book's to-scan list, or ignored. Review asks with a card per pointer; the whole-book session,
// where recipes save straight, applies the same rules without one. A page the contents list has as
// a recipe, or that reads as one, is a recipe; any other page, and every technique or Sources
// pointer, is reference reading, remembered in the book's `BookScanState` for slice 7 to capture
// as a `Reference`.

/// The cook's answer on a pointer's card.
enum PointerChoice: Equatable {
    /// Nothing chosen: a link is made only where the page holds exactly one recipe.
    case undecided
    /// Link to this recipe (`Recipe.id`) as a component.
    case link(UUID)
    case addToList
    case ignore
}

/// One pointer on a recipe in review, with the cook's answer.
struct ReviewPointer: Identifiable, Equatable {
    let id: Int
    let reference: PageCrossReference
    var choice: PointerChoice = .undecided
}

@MainActor
enum CrossReferenceLinking {
    /// What a pointer is in its book: the recipe Link offers first, the page it is about, whether
    /// that page is reference reading, and the entry already listed there.
    struct Reading {
        var page: Int?
        var suggested: Recipe?
        var isReference: Bool
        var listed: BookEntry?
    }

    /// The pointers worth a card: every kind but photographs, which go to their recipe as covers.
    static func pointers(in references: [PageCrossReference]) -> [PageCrossReference] {
        var seen = Set<String>()
        return references.filter { $0.kind != .photograph && seen.insert($0.phrase.lowercased()).inserted }
    }

    /// The pointers in a stored recipe's text: its ingredient lines, steps and headnote.
    static func pointers(of recipe: Recipe) -> [PageCrossReference] {
        guard let version = recipe.currentVersion else { return [] }
        let texts = version.sortedIngredients.map(\.rawText) + version.sortedSteps.map(\.text) + [recipe.headnote]
        return pointers(in: texts.flatMap(PagePointers.crossReferences))
    }

    /// The pages a recipe is printed on: a pointer to one of them is the recipe's own page turn.
    static func ownPages(of recipe: Recipe?) -> Set<Int> {
        guard let recipe else { return [] }
        let first = recipe.source?.firstPage ?? recipe.pageNumber
        let last = recipe.source?.lastPage ?? first
        guard let first, let last, first <= last else { return [] }
        return Set(first...last)
    }

    static func read(_ reference: PageCrossReference, from recipe: Recipe?, in book: Book, state: BookScanState?) -> Reading {
        // "(recipe follows)": no page; the name says which recipe, on this page or the next.
        guard let page = reference.pages.first(where: { !ownPages(of: recipe).contains($0) }) ?? (reference.pages.isEmpty ? nil : reference.pages.first) else {
            let named = reference.target.flatMap { target in
                (book.recipes ?? []).filter { $0 != recipe }.max { PunchlistMatcher.similarity($0.title, target) < PunchlistMatcher.similarity($1.title, target) }
                    .flatMap { PunchlistMatcher.similarity($0.title, target) >= 0.6 ? $0 : nil }
            }
            return Reading(page: ownPages(of: recipe).max(), suggested: named, isReference: false, listed: nil)
        }
        let onPage = book.recipes(onPage: page).filter { $0 != recipe }
        let suggested = onPage.count == 1 ? onPage[0] : reference.target.flatMap { target in
            onPage.max { PunchlistMatcher.similarity($0.title, target) < PunchlistMatcher.similarity($1.title, target) }
                .flatMap { PunchlistMatcher.similarity($0.title, target) >= 0.5 ? $0 : nil }
        } ?? onPage.first
        let isReference = reference.kind != .recipe || !isRecipePage(page, in: book, state: state)
        let listed = book.orderedEntries.first { $0.page == page && $0.recipe == nil && $0.reference == nil }
        return Reading(page: page, suggested: suggested, isReference: isReference, listed: listed)
    }

    /// The page holds a recipe: one is captured from it, a page scan of it read as one, or the
    /// contents list has a recipe there (not an entry a reference pointer put on the list).
    static func isRecipePage(_ page: Int, in book: Book, state: BookScanState?) -> Bool {
        if !book.recipes(onPage: page).isEmpty { return true }
        let scans = (book.pageScans ?? []).filter { $0.pageNumber == page }
        if let scan = scans.first { return scan.pageKind == .recipe }
        let references = Set((state?.pointerEntries ?? []).filter(\.isReference).map(\.entry))
        return book.orderedEntries.contains { $0.page == page && !references.contains($0.id) }
    }

    // MARK: - The answers

    /// Link: `recipe` gains a component link to `component` (unless it has one), its note the
    /// pointer as printed.
    static func link(_ recipe: Recipe, to component: Recipe, phrase: String, in context: ModelContext) {
        guard recipe != component, !(recipe.links ?? []).contains(where: { $0.role == .component && $0.subRecipe == component }) else { return }
        let link = RecipeLink(role: .component, note: phrase)
        context.insert(link)
        link.parent = recipe
        link.subRecipe = component
    }

    /// Takes back a component link to the recipe on `page`, when one was made.
    static func unlink(_ recipe: Recipe, page: Int?, in context: ModelContext) {
        for link in recipe.links ?? [] where link.role == .component {
            guard let sub = link.subRecipe else { continue }
            if let page, ownPages(of: sub).contains(page) || sub.pageNumber == page { context.delete(link) }
        }
    }

    /// Add to this book's to-scan list: the page's listed entry, or a new one titled from the
    /// pointer, remembered with the recipes that point there.
    @discardableResult
    static func addToList(_ reference: PageCrossReference, from recipe: Recipe, in book: Book, state: inout BookScanState, context: ModelContext) -> BookEntry? {
        let reading = read(reference, from: recipe, in: book, state: state)
        guard let page = reading.page else { return nil }
        // A page of its own is a page turn; "recipe follows" needs the name to list it by.
        if reference.pages.isEmpty ? reference.target == nil : ownPages(of: recipe).contains(page) { return nil }
        let (entry, isNew) = book.toScanEntry(page: page, title: entryTitle(for: reference, in: recipe, page: page), in: context)
        if let index = state.pointerEntries.firstIndex(where: { $0.entry == entry.id }) {
            if !state.pointerEntries[index].recipes.contains(recipe.id) { state.pointerEntries[index].recipes.append(recipe.id) }
        } else {
            state.pointerEntries.append(BookScanState.PointerEntry(entry: entry.id, page: page, isReference: reading.isReference, phrase: reference.phrase,
                                                                   kind: reference.kind.rawValue, recipes: [recipe.id], madeEntry: isNew))
        }
        return entry
    }

    /// A to-scan entry's title: the name the pointer gives, else the ingredient it sits on ("dashi
    /// (see page 17)" → "Dashi"), else "Page 17".
    static func entryTitle(for reference: PageCrossReference, in recipe: Recipe, page: Int) -> String {
        if let target = reference.target, !target.isEmpty { return target }
        let line = recipe.currentVersion?.sortedIngredients.first { $0.rawText.localizedCaseInsensitiveContains(reference.phrase) }
        let pointer = PagePointer(range: reference.phrase.startIndex..<reference.phrase.endIndex, text: reference.phrase, pages: [page], kind: reference.kind)
        return pointer.entryTitle(item: line?.item)
    }

    /// Ignore: whatever the pointer made for this recipe goes (its link, its place on an entry it
    /// put on the list).
    static func ignore(_ reference: PageCrossReference, from recipe: Recipe, in book: Book?, state: inout BookScanState, context: ModelContext) {
        let page = book.flatMap { read(reference, from: recipe, in: $0, state: state).page } ?? reference.pages.first
        unlink(recipe, page: page, in: context)
        if let page { forget(recipes: [recipe.id], page: page, in: book, state: &state, context: context) }
    }

    /// Takes `ids` off the pointer entries (at `page`, or all); an entry a pointer made goes once
    /// nothing points there and nothing was captured for it.
    static func forget(recipes ids: Set<UUID>, page: Int? = nil, in book: Book?, state: inout BookScanState, context: ModelContext) {
        for index in state.pointerEntries.indices.reversed() where page == nil || state.pointerEntries[index].page == page {
            state.pointerEntries[index].recipes.removeAll { ids.contains($0) }
            guard state.pointerEntries[index].recipes.isEmpty else { continue }
            let pointer = state.pointerEntries.remove(at: index)
            if pointer.madeEntry, let entry = book?.orderedEntries.first(where: { $0.id == pointer.entry }),
               entry.recipe == nil, entry.reference == nil, entry.status == .listed {
                context.delete(entry)
            }
        }
    }

    /// What review's cards say, applied once the recipe is saved: Link, Add, Ignore; a pointer left
    /// undecided links only where its page holds exactly one recipe.
    static func apply(_ pointers: [ReviewPointer], to recipe: Recipe, in book: Book?, context: ModelContext) {
        guard !pointers.isEmpty else { return }
        let fetch = { (id: UUID) in try? context.fetch(FetchDescriptor<Recipe>(predicate: #Predicate { $0.id == id })).first }
        BookScanStore.shared.updateState(for: book) { state in
            for pointer in pointers {
                switch pointer.choice {
                case let .link(id):
                    if let component = fetch(id) { link(recipe, to: component, phrase: pointer.reference.phrase, in: context) }
                    if let book { forget(recipes: [recipe.id], page: read(pointer.reference, from: recipe, in: book, state: state).page, in: book, state: &state, context: context) }
                case .addToList:
                    if let book { addToList(pointer.reference, from: recipe, in: book, state: &state, context: context) }
                case .ignore:
                    ignore(pointer.reference, from: recipe, in: book, state: &state, context: context)
                case .undecided:
                    if let book { linkIfOne(pointer.reference, from: recipe, in: book, state: state, context: context) }
                }
            }
        }
        try? context.save()
    }

    /// The link the page makes plain: its one recipe (or the one the pointer names).
    static func linkIfOne(_ reference: PageCrossReference, from recipe: Recipe, in book: Book, state: BookScanState?, context: ModelContext) {
        let reading = read(reference, from: recipe, in: book, state: state)
        guard !reading.isReference || reference.kind == .recipe, let component = reading.suggested else { return }
        link(recipe, to: component, phrase: reference.phrase, in: context)
    }

    /// The whole-book session's rule, where recipes save straight and no card is shown: link by page
    /// when the book has that page's recipe, otherwise the page goes on the to-scan list (a
    /// reference pointer when the page isn't a recipe). A page whose several recipes the pointer
    /// can't tell apart is left to the pill; "recipe follows" links by name or waits.
    static func applySessionRule(_ references: [PageCrossReference], for recipe: Recipe, in book: Book, state: inout BookScanState, context: ModelContext) {
        for reference in pointers(in: references) {
            let reading = read(reference, from: recipe, in: book, state: state)
            if let component = reading.suggested {
                link(recipe, to: component, phrase: reference.phrase, in: context)
            } else if !reference.pages.isEmpty, let page = reading.page, book.recipes(onPage: page).filter({ $0 != recipe }).isEmpty {
                addToList(reference, from: recipe, in: book, state: &state, context: context)
            }
        }
    }

    /// A recipe just captured from `pages`: the recipes whose pointers put those pages on the list
    /// link to it, and an entry a pointer called reference reading reads as a recipe after all.
    static func linkWaiting(to recipe: Recipe, pages: [Int], in book: Book, state: inout BookScanState, context: ModelContext) {
        let fetch = { (id: UUID) in try? context.fetch(FetchDescriptor<Recipe>(predicate: #Predicate { $0.id == id })).first }
        for index in state.pointerEntries.indices where pages.contains(state.pointerEntries[index].page) {
            state.pointerEntries[index].isReference = false
            for id in state.pointerEntries[index].recipes where id != recipe.id {
                if let pointing = fetch(id) { link(pointing, to: recipe, phrase: state.pointerEntries[index].phrase, in: context) }
            }
        }
    }
}

extension BookScanStore {
    /// Changes a book's session state, through its live session when one is open (so the session's
    /// next save keeps the change), else on disk. A recipe with no book has no state; the change
    /// gets a scratch one.
    func updateState(for book: Book?, _ change: (inout BookScanState) -> Void) {
        guard let book else {
            var scratch = BookScanState()
            change(&scratch)
            return
        }
        if let session = liveSession(for: book.id) {
            session.updateState(change)
        } else {
            var state = BookScanState.load(bookID: book.id) ?? BookScanState()
            let before = try? JSONEncoder().encode(state)
            change(&state)
            // A book with no session gets a file only when something changed.
            if (try? JSONEncoder().encode(state)) != before { state.save(bookID: book.id) }
        }
    }

    /// The book's state as it stands, for reading.
    func state(for book: Book?) -> BookScanState? {
        guard let book else { return nil }
        return liveSession(for: book.id)?.state ?? BookScanState.load(bookID: book.id)
    }
}
