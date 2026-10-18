import RecipeModel
import SwiftData
import SwiftUI

/// What the iPad sidebar has selected (03 §3.2, §4): the whole library, a smart collection, the
/// cookbook shelf, or one book's recipes.
enum LibraryScope: Hashable {
    case all
    case favorites
    case neverCooked
    case needsReview
    case shelf
    case book(PersistentIdentifier)

    /// Whether `recipe` belongs to this scope. The shelf holds books, not recipes.
    func contains(_ recipe: Recipe) -> Bool {
        switch self {
        case .all: true
        case .favorites: recipe.isFavorite
        case .neverCooked: recipe.isNeverCooked
        case .needsReview: recipe.needsReview
        case .shelf: false
        case let .book(id): recipe.book?.persistentModelID == id
        }
    }
}

/// The Recipes sidebar on iPad: All Recipes, smart collections, and Books. User-made collections
/// arrive later in Phase 1; there is no collection model in schema v1 yet.
struct LibrarySidebar: View {
    @Binding var selection: LibraryScope?

    @Query private var recipes: [Recipe]
    @Query(sort: [SortDescriptor(\Book.title, comparator: .localizedStandard)]) private var books: [Book]

    var body: some View {
        List(selection: $selection) {
            Section {
                Label("All Recipes", systemImage: "book.closed")
                    .badge(recipes.count)
                    .tag(LibraryScope.all)
            }

            Section("Collections") {
                Label("Favorites", systemImage: "heart")
                    .badge(count(.favorites))
                    .tag(LibraryScope.favorites)
                Label("Never Cooked", systemImage: "sparkles")
                    .badge(count(.neverCooked))
                    .tag(LibraryScope.neverCooked)
                let reviewCount = count(.needsReview)
                if reviewCount > 0 || selection == .needsReview {
                    Label("Needs a Look", systemImage: "exclamationmark.bubble")
                        .badge(reviewCount)
                        .tag(LibraryScope.needsReview)
                }
            }

            Section("Books") {
                Label("Shelf", systemImage: "books.vertical")
                    .badge(books.count)
                    .tag(LibraryScope.shelf)
                ForEach(books) { book in
                    Label(book.title.isEmpty ? "Untitled Book" : book.title, systemImage: "book")
                        .badge(book.recipes?.count ?? 0)
                        .tag(LibraryScope.book(book.persistentModelID))
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func count(_ scope: LibraryScope) -> Int {
        recipes.count { scope.contains($0) }
    }

    /// The content column's title for a scope.
    static func title(for scope: LibraryScope, books: [Book]) -> String {
        switch scope {
        case .all: "All Recipes"
        case .favorites: "Favorites"
        case .neverCooked: "Never Cooked"
        case .needsReview: "Needs a Look"
        case .shelf: "Shelf"
        case let .book(id): books.first { $0.persistentModelID == id }?.title ?? "Book"
        }
    }
}

extension Recipe {
    /// The current version was imported with low confidence and hasn't been checked yet.
    var needsReview: Bool { currentVersion?.needsReview == true }
}
