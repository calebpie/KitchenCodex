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
        /// The recipe Link offers first: the page's one recipe, the one the pointer names, else the
        /// first of several.
        var suggested: Recipe?
        /// The suggestion is the page's only recipe or the one the pointer names, so a link can be
        /// made without asking.
        var isPlain = false
        var isReference: Bool
        var listed: BookEntry?
        /// Reference reading already captured from the page (a glossary, a chapter): the recipe
        /// reads it as related reading rather than listing the page again.
        var reference: Reference?
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
            return Reading(page: ownPages(of: recipe).max(), suggested: named, isPlain: named != nil, isReference: false, listed: nil)
        }
        let onPage = book.recipes(onPage: page).filter { $0 != recipe }
        let named = onPage.count == 1 ? onPage[0] : reference.target.flatMap { target in
            onPage.max { PunchlistMatcher.similarity($0.title, target) < PunchlistMatcher.similarity($1.title, target) }
                .flatMap { PunchlistMatcher.similarity($0.title, target) >= 0.5 ? $0 : nil }
        }
        let isReference = reference.kind != .recipe || !isRecipePage(page, in: book, state: state)
        let listed = book.orderedEntries.first { $0.page == page && $0.recipe == nil && $0.reference == nil }
        let captured = onPage.isEmpty && reference.kind != .sources ? book.references(onPage: page).first : nil
        return Reading(page: page, suggested: named ?? onPage.first, isPlain: named != nil, isReference: isReference, listed: listed, reference: captured)
    }

    /// A pointer to a page captured as reference reading: the recipe reads it as related reading
    /// (02 §4.2), both ways.
    static func relate(_ recipe: Recipe, to reference: Reference) {
        guard !(recipe.references ?? []).contains(reference) else { return }
        recipe.references = (recipe.references ?? []) + [reference]
    }

    /// The same, and the recipe joins the page's pointer entry, so the reference captured again
    /// (after a delete) or a page shot again still finds it.
    static func relate(_ recipe: Recipe, to reference: Reference, page: Int, state: inout BookScanState) {
        relate(recipe, to: reference)
        if let index = state.pointerEntries.firstIndex(where: { $0.page == page && $0.kind != PageCrossReference.Kind.sources.rawValue }),
           !state.pointerEntries[index].recipes.contains(recipe.id) {
            state.pointerEntries[index].recipes.append(recipe.id)
        }
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
        // The page is captured as reference reading already: related reading, nothing new to list.
        if let captured = reading.reference {
            relate(recipe, to: captured, page: page, state: &state)
            return nil
        }
        // The book's Sources page is captured: its suppliers are in Pantry → Sources (row 103).
        if reference.kind == .sources, !book.sourcesPages.isEmpty { return nil }
        // A page of its own is a page turn; "recipe follows" needs the name to list it by.
        if reference.pages.isEmpty ? reference.target == nil : ownPages(of: recipe).contains(page) { return nil }
        // One pointer entry per page: a second pointer to it joins the first.
        if let index = state.pointerEntries.firstIndex(where: { $0.page == page && ($0.kind == PageCrossReference.Kind.sources.rawValue) == (reference.kind == .sources) }),
           let listed = book.orderedEntries.first(where: { $0.id == state.pointerEntries[index].entry }) {
            if !state.pointerEntries[index].recipes.contains(recipe.id) { state.pointerEntries[index].recipes.append(recipe.id) }
            return listed
        }
        let (entry, isNew) = book.toScanEntry(page: page, title: entryTitle(for: reference, in: recipe, page: page), in: context)
        if let index = state.pointerEntries.firstIndex(where: { $0.entry == entry.id }) {
            if !state.pointerEntries[index].recipes.contains(recipe.id) { state.pointerEntries[index].recipes.append(recipe.id) }
        } else {
            state.pointerEntries.append(BookScanState.PointerEntry(entry: entry.id, page: page, isReference: reading.isReference, phrase: reference.phrase,
                                                                   kind: reference.kind.rawValue, recipes: [recipe.id], madeEntry: isNew))
        }
        return entry
    }

    /// A to-scan entry's title (ux-notes row 102): the name the pointer gives ("Dashi (see page
    /// 17)" → "Dashi"), else the name inside its parentheses ("Yama-imo"), else the ingredient it
    /// sits on without its size and count words ("Mountain yam"), else "Page 17".
    static func entryTitle(for reference: PageCrossReference, in recipe: Recipe, page: Int) -> String {
        if let target = reference.target, !target.isEmpty { return target }
        let line = recipe.currentVersion?.sortedIngredients.first { $0.rawText.localizedCaseInsensitiveContains(reference.phrase) }
        let pointer = PagePointers.find(in: reference.phrase).first
            ?? PagePointer(range: reference.phrase.startIndex..<reference.phrase.endIndex, text: reference.phrase, pages: [page], kind: reference.kind)
        return pointer.entryTitle(item: line?.item)
    }

    /// The book's Sources page is captured (02 Flow C step 8, ux-notes row 103): the entry the
    /// pointers to it put on the list is captured (titled Sources when a pointer made it, since it
    /// took the pointer's words), and the pointers come off the session's state, having nothing to
    /// link.
    static func captureSourcesPage(pages: [Int], in book: Book, state: inout BookScanState, context: ModelContext) {
        for index in state.pointerEntries.indices.reversed() {
            let pointer = state.pointerEntries[index]
            guard pointer.kind == PageCrossReference.Kind.sources.rawValue || pages.contains(pointer.page) && pointer.isReference else { continue }
            if let entry = book.orderedEntries.first(where: { $0.id == pointer.entry }), entry.recipe == nil, entry.reference == nil {
                entry.status = .captured
                if pointer.madeEntry { entry.title = "Sources" }
            }
            state.pointerEntries.remove(at: index)
        }
        for entry in book.orderedEntries where pages.contains(entry.page ?? -1) && entry.recipe == nil && entry.reference == nil && entry.status == .listed {
            entry.status = .captured
        }
        try? context.save()
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

    /// Recipes deleted from the library point nowhere: they leave the pointer entries, and an entry
    /// a pointer made goes with its last pointing recipe while nothing was captured for it. Run when
    /// the book's detail or session opens, as `reconcilePunchlist` is.
    static func prune(in book: Book, state: inout BookScanState, context: ModelContext) {
        mergeDuplicatePointerEntries(in: book, state: &state, context: context)
        relateCapturedReferences(in: book)
        let alive = Set((book.recipes ?? []).filter { !$0.isDeleted }.map(\.id))
        let gone = Set(state.pointerEntries.flatMap(\.recipes)).subtracting(alive)
        guard !gone.isEmpty else { try? context.save(); return }
        forget(recipes: gone, in: book, state: &state, context: context)
        try? context.save()
    }

    /// Two pointer entries for one page (an older session made one per pointer) become one: the
    /// first whose entry is still on the list keeps every pointing recipe; a later one's entry
    /// that a pointer made, and nothing captured, goes.
    static func mergeDuplicatePointerEntries(in book: Book, state: inout BookScanState, context: ModelContext) {
        let entries = Dictionary(book.orderedEntries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var kept: [BookScanState.PointerEntry] = []
        for pointer in state.pointerEntries {
            let sources = pointer.kind == PageCrossReference.Kind.sources.rawValue
            guard let index = kept.firstIndex(where: { $0.page == pointer.page && ($0.kind == PageCrossReference.Kind.sources.rawValue) == sources }) else {
                kept.append(pointer)
                continue
            }
            // Keep the one whose entry still exists, preferring the list's own over a made one.
            var survivor = kept[index], other = pointer
            if entries[survivor.entry] == nil || (survivor.madeEntry && !other.madeEntry && entries[other.entry] != nil) { swap(&survivor, &other) }
            for id in other.recipes where !survivor.recipes.contains(id) { survivor.recipes.append(id) }
            survivor.isReference = survivor.isReference && other.isReference
            kept[index] = survivor
            if other.madeEntry, other.entry != survivor.entry, let entry = entries[other.entry],
               entry.recipe == nil, entry.reference == nil, entry.status == .listed {
                context.delete(entry)
            }
        }
        state.pointerEntries = kept
    }

    /// Every pointer in the book's recipes to a page captured as reference reading relates the
    /// recipe to it (02 §4.2), so a recipe saved, or shot again, before the page was captured
    /// still reads it.
    static func relateCapturedReferences(in book: Book) {
        guard !(book.references ?? []).isEmpty else { return }
        for recipe in book.recipes ?? [] where !recipe.isDeleted {
            for pointer in pointers(of: recipe) where pointer.kind != .sources {
                if let captured = read(pointer, from: recipe, in: book, state: nil).reference { relate(recipe, to: captured) }
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
        if let captured = reading.reference { relate(recipe, to: captured) }
        guard reading.isPlain, let component = reading.suggested else { return }
        link(recipe, to: component, phrase: reference.phrase, in: context)
    }

    /// The whole-book session's rule, where recipes save straight and no card is shown: link by page
    /// when the book has that page's recipe, otherwise the page goes on the to-scan list (a
    /// reference pointer when the page isn't a recipe). A page whose several recipes the pointer
    /// can't tell apart is left to the pill; "recipe follows" links by name or waits.
    static func applySessionRule(_ references: [PageCrossReference], for recipe: Recipe, in book: Book, state: inout BookScanState, context: ModelContext) {
        for reference in pointers(in: references) {
            let reading = read(reference, from: recipe, in: book, state: state)
            if reading.isPlain, let component = reading.suggested {
                link(recipe, to: component, phrase: reference.phrase, in: context)
            } else if let captured = reading.reference, let page = reading.page {
                relate(recipe, to: captured, page: page, state: &state)
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
