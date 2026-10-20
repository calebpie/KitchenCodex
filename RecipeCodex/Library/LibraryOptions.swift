import Foundation
import RecipeModel
import SwiftData

/// How the Recipes view lays out the library (More → View as).
enum RecipeLayout: String, CaseIterable, Identifiable {
    case grid, list

    var id: Self { self }

    var title: String {
        switch self {
        case .grid: "Grid"
        case .list: "List"
        }
    }

    var systemImage: String {
        switch self {
        case .grid: "square.grid.2x2"
        case .list: "list.bullet"
        }
    }
}

/// Library sort order (More → Sort By).
enum RecipeSort: String, CaseIterable, Identifiable {
    case title, recentlyAdded

    var id: Self { self }

    var title: String {
        switch self {
        case .title: "Title"
        case .recentlyAdded: "Recently Added"
        }
    }

    var descriptors: [SortDescriptor<Recipe>] {
        switch self {
        case .title: [SortDescriptor(\Recipe.title, comparator: .localizedStandard)]
        case .recentlyAdded: [SortDescriptor(\Recipe.createdAt, order: .reverse)]
        }
    }
}

/// How the library groups its recipes (More → Group By, 04 §5.1 Recipes filters). Default Course.
enum RecipeGrouping: String, CaseIterable, Identifiable {
    case none, course, book, collection

    var id: Self { self }

    var title: String {
        switch self {
        case .none: "None"
        case .course: "Course"
        case .book: "Cookbook"
        case .collection: "Collection"
        }
    }

    /// One run of recipes under a header. A single section hides its header.
    struct Section: Identifiable {
        let id: String
        let title: String
        let recipes: [Recipe]
    }

    /// `recipes`, in their sorted order, split into sections: courses in the standard order then
    /// any others, books by title, collections in the cook's order, and what fits none last. A
    /// recipe in two collections appears under both.
    func sections(_ recipes: [Recipe], collections: [RecipeCollection]) -> [Section] {
        switch self {
        case .none:
            return [Section(id: "all", title: "All Recipes", recipes: recipes)]
        case .course:
            let order = RecipeCourse.options(including: recipes)
            var sections = order.compactMap { course in
                let matching = recipes.filter { $0.course == course }
                return matching.isEmpty ? nil : Section(id: "course:\(course)", title: course, recipes: matching)
            }
            let none = recipes.filter { $0.course == nil }
            if !none.isEmpty { sections.append(Section(id: "course:none", title: "No Course", recipes: none)) }
            return sections
        case .book:
            var books: [PersistentIdentifier: Book] = [:]
            for book in recipes.compactMap(\.book) { books[book.persistentModelID] = book }
            var sections = books.values
                .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                .map { book in
                    Section(id: "book:\(book.id)", title: book.title.isEmpty ? "Untitled Cookbook" : book.title,
                            recipes: recipes.filter { $0.book?.persistentModelID == book.persistentModelID })
                }
            let none = recipes.filter { $0.book == nil }
            if !none.isEmpty { sections.append(Section(id: "book:none", title: "No Cookbook", recipes: none)) }
            return sections
        case .collection:
            var sections = collections.compactMap { collection in
                let matching = recipes.filter { $0.isIn(collection) }
                return matching.isEmpty ? nil : Section(id: "collection:\(collection.id)", title: collection.name, recipes: matching)
            }
            let none = recipes.filter { $0.collections?.isEmpty ?? true }
            if !none.isEmpty { sections.append(Section(id: "collection:none", title: "No Collection", recipes: none)) }
            return sections
        }
    }
}

/// Filter → Cooked: one or the other, or neither.
enum CookedFilter: String, CaseIterable, Identifiable {
    case any, neverCooked, cooked

    var id: Self { self }

    var title: String {
        switch self {
        case .any: "Any"
        case .neverCooked: "Never Cooked"
        case .cooked: "Cooked"
        }
    }
}

/// The library's view filter, set from the Filter toolbar menu and shown as removable tokens while
/// active (04 §5.1 Recipes filters). Not a search: search is the Search tab (03 §3.2). Several
/// courses match any of them; every other section narrows further.
struct RecipeFilter: Equatable {
    var courses: Set<String> = []
    var cooked: CookedFilter = .any
    var favorites = false
    var needsReview = false
    var collection: PersistentIdentifier?
    var book: PersistentIdentifier?
    var tag: PersistentIdentifier?

    var isActive: Bool { self != RecipeFilter() }

    func matches(_ recipe: Recipe) -> Bool {
        if !courses.isEmpty, !courses.contains(recipe.course ?? "") { return false }
        if favorites, !recipe.isFavorite { return false }
        if needsReview, recipe.currentVersion?.needsReview != true { return false }
        if let collection, recipe.collections?.contains(where: { $0.persistentModelID == collection }) != true { return false }
        if let book, recipe.book?.persistentModelID != book { return false }
        if let tag, recipe.tags?.contains(where: { $0.persistentModelID == tag }) != true { return false }
        switch cooked {
        case .any: return true
        case .neverCooked: return recipe.isNeverCooked
        case .cooked: return !recipe.isNeverCooked
        }
    }

    /// Whether only `collection` is set, so an empty result means the collection is empty.
    var isOnlyCollection: Bool {
        var other = self
        other.collection = nil
        return collection != nil && !other.isActive
    }
}

/// Courses offered when entering a recipe and in the Course chip. Stored on `Recipe.course` as plain
/// text, so imports can bring other values; the chip lists those too.
enum RecipeCourse {
    static let standard = [
        "Breakfast", "Starter", "Soup", "Salad", "Main", "Side",
        "Dessert", "Bread", "Sauce", "Drink", "Snack",
    ]

    /// The standard courses followed by any others found in the library.
    static func options(including recipes: [Recipe]) -> [String] {
        let extra = Set(recipes.compactMap(\.course)).subtracting(standard).sorted()
        return standard + extra
    }
}

extension RecipeVersion {
    /// "1 hr 30 min", for cards and rows.
    var displayTime: String? {
        displayMinutes.map { Duration.seconds($0 * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)) }
    }
}
