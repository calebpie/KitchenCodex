import RecipeModel
import SwiftData
import SwiftUI

/// What the iPad sidebar has selected (03 §3.2, §4): the whole library, a smart collection, one of
/// the cook's collections, the cookbook shelf, or one book's recipes.
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
}

/// The Recipes sidebar on iPad: All Recipes, smart collections, the cook's collections, and Books.
/// A recipe dragged from the list onto a collection joins it (03 §3.2, §4).
struct LibrarySidebar: View {
    @Binding var selection: LibraryScope?

    @Environment(\.modelContext) private var modelContext
    @Query private var recipes: [Recipe]
    @Query(sort: [SortDescriptor(\Book.title, comparator: .localizedStandard)]) private var books: [Book]
    @Query(sort: CollectionActions.sortDescriptors) private var collections: [RecipeCollection]

    @State private var isCreatingCollection = false
    @State private var renamingCollection: RecipeCollection?
    @State private var deletingCollection: RecipeCollection?
    /// The collection a drag is hovering over, for the drop highlight.
    @State private var dropTarget: PersistentIdentifier?

    var body: some View {
        List(selection: $selection) {
            Section {
                Label("All Recipes", systemImage: "book.closed")
                    .badge(recipes.count)
                    .tag(LibraryScope.all)
            }

            Section("Smart Collections") {
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

            Section("Collections") {
                ForEach(collections) { collection in
                    collectionRow(collection)
                }
                Button {
                    isCreatingCollection = true
                } label: {
                    Label("New Collection", systemImage: "plus")
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
        .collectionNamePrompt("New Collection", isPresented: $isCreatingCollection, actionTitle: "Create") { name in
            let collection = CollectionActions.create(named: name, in: modelContext)
            selection = .collection(collection.persistentModelID)
        }
        .collectionNamePrompt(
            "Rename Collection",
            isPresented: Binding { renamingCollection != nil } set: { if !$0 { renamingCollection = nil } },
            initialName: renamingCollection?.name ?? ""
        ) { name in
            renamingCollection?.name = name
            try? modelContext.save()
        }
        .confirmationDialog(
            "Delete “\(deletingCollection?.name ?? "")”?",
            isPresented: Binding { deletingCollection != nil } set: { if !$0 { deletingCollection = nil } },
            titleVisibility: .visible,
            presenting: deletingCollection
        ) { collection in
            Button("Delete Collection", role: .destructive) {
                if selection == .collection(collection.persistentModelID) { selection = .all }
                CollectionActions.delete(collection, in: modelContext)
            }
        } message: { _ in
            Text("The recipes stay in your library.")
        }
    }

    private func collectionRow(_ collection: RecipeCollection) -> some View {
        let id = collection.persistentModelID
        return Label(collection.name, systemImage: "rectangle.stack")
            .badge(collection.recipes?.count ?? 0)
            .tag(LibraryScope.collection(id))
            .listRowBackground(dropTarget == id ? RoundedRectangle(cornerRadius: 10).fill(.tint.opacity(0.2)) : nil)
            .dropDestination(for: RecipeDragItem.self) { items, _ in
                CollectionActions.add(items.map(\.id), to: collection, in: modelContext)
            } isTargeted: { targeted in
                if targeted { dropTarget = id } else if dropTarget == id { dropTarget = nil }
            }
            .contextMenu {
                Button("Rename…", systemImage: "pencil") { renamingCollection = collection }
                Button("Delete", systemImage: "trash", role: .destructive) { deletingCollection = collection }
            }
    }

    private func count(_ scope: LibraryScope) -> Int {
        recipes.count { scope.contains($0) }
    }

    /// The content column's title for a scope.
    static func title(for scope: LibraryScope, books: [Book], collections: [RecipeCollection]) -> String {
        switch scope {
        case .all: "All Recipes"
        case .favorites: "Favorites"
        case .neverCooked: "Never Cooked"
        case .needsReview: "Needs a Look"
        case let .collection(id): collections.first { $0.persistentModelID == id }?.name ?? "Collection"
        case .shelf: "Shelf"
        case let .book(id): books.first { $0.persistentModelID == id }?.title ?? "Book"
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
