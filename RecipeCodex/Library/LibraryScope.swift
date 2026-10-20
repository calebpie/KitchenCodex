import RecipeModel
import SwiftData
import SwiftUI

/// Which part of the library a page shows (03 §3.2, §4): the whole library, a smart collection, one
/// of the cook's collections, the cookbook shelf, or one book's recipes. On iPad each but the whole
/// library and a book is a tab in the system sidebar's Recipes sections (04 §5.1 iPad tabs); Search
/// pushes the smart collections, collections and books.
enum LibraryScope: Hashable {
    case all
    case favorites
    case neverCooked
    case needsReview
    case collection(PersistentIdentifier)
    case shelf
    case book(PersistentIdentifier)

    /// Whether `recipe` belongs to this scope. The shelf holds books, not recipes.
    func contains(_ recipe: Recipe) -> Bool {
        switch self {
        case .all: true
        case .favorites: recipe.isFavorite
        case .neverCooked: recipe.isNeverCooked
        case .needsReview: recipe.needsReview
        case let .collection(id): recipe.isInCollection(id)
        case .shelf: false
        case let .book(id): recipe.book?.persistentModelID == id
        }
    }

    /// The page's title, which is also the sidebar tab's name. The whole library is the Recipes tab.
    func title(books: [Book], collections: [RecipeCollection]) -> String {
        switch self {
        case .all: "Recipes"
        case .favorites: "Favorites"
        case .neverCooked: "Never Cooked"
        case .needsReview: "Needs a Look"
        case let .collection(id): collections.first { $0.persistentModelID == id }?.name ?? "Collection"
        case .shelf: "All Cookbooks"
        case let .book(id): books.first { $0.persistentModelID == id }?.title ?? "Cookbook"
        }
    }
}

extension Recipe {
    /// The current version was imported with low confidence and hasn't been checked yet.
    var needsReview: Bool { currentVersion?.needsReview == true }

    func isInCollection(_ id: PersistentIdentifier) -> Bool {
        collections?.contains { $0.persistentModelID == id } == true
    }
}
