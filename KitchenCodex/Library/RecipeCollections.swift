import CoreTransferable
import RecipeModel
import SwiftData
import SwiftUI

/// Collections the cook makes (03 §3.2): New Collection in Recipes' More menu, Add to Collection in
/// the long-press menu, on detail and in Select mode, the Collections list, the iPad sidebar's
/// Collections section, and on iPhone the Collection filter.
enum CollectionActions {
    /// Collections in their sidebar order.
    static let sortDescriptors = [SortDescriptor(\RecipeCollection.sortOrder), SortDescriptor(\RecipeCollection.createdAt)]

    /// Makes a collection called `name` (or finds the one already called that, ignoring case) and
    /// puts `recipe` in it.
    @discardableResult
    static func create(named name: String, adding recipe: Recipe? = nil, in context: ModelContext) -> RecipeCollection {
        let existing = (try? context.fetch(FetchDescriptor<RecipeCollection>())) ?? []
        let collection: RecipeCollection
        if let match = existing.first(where: { $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
            collection = match
        } else {
            collection = RecipeCollection(name: name, sortOrder: RecipeCollection.nextSortOrder(after: existing))
            context.insert(collection)
        }
        if let recipe, !recipe.isIn(collection) {
            recipe.toggleMembership(in: collection)
        }
        try? context.save()
        return collection
    }

    /// Deletes the collection; its recipes stay in the library.
    static func delete(_ collection: RecipeCollection, in context: ModelContext) {
        context.delete(collection)
        try? context.save()
    }

    /// Moves collections in the cook's order (Edit in the Collections list)
    /// and renumbers every `sortOrder` from 0.
    static func move(_ collections: [RecipeCollection], from source: IndexSet, to destination: Int, in context: ModelContext) {
        var ordered = collections
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, collection) in ordered.enumerated() where collection.sortOrder != index {
            collection.sortOrder = index
        }
        try? context.save()
    }

    /// Puts the recipes named by `ids` in `collection`. False when none of them was found.
    static func add(_ ids: [UUID], to collection: RecipeCollection, in context: ModelContext) -> Bool {
        let wanted = Set(ids)
        let recipes = ((try? context.fetch(FetchDescriptor<Recipe>())) ?? []).filter { wanted.contains($0.id) }
        for recipe in recipes where !recipe.isIn(collection) {
            recipe.toggleMembership(in: collection)
        }
        try? context.save()
        return !recipes.isEmpty
    }
}

/// Add to Collection: each collection with a checkmark when the recipe is in it (tap to add or take
/// it out), then New Collection…, which asks for a name and adds the recipe.
struct AddToCollectionMenu: View {
    let recipe: Recipe
    /// Asks the host to prompt for a name; the host then creates the collection with this recipe.
    let onNewCollection: () -> Void

    @Query(sort: CollectionActions.sortDescriptors) private var collections: [RecipeCollection]

    var body: some View {
        Menu {
            ForEach(collections) { collection in
                Toggle(isOn: Binding { recipe.isIn(collection) } set: { _ in recipe.toggleMembership(in: collection) }) {
                    Text(collection.name)
                }
            }
            if !collections.isEmpty { Divider() }
            Button("New Collection…", systemImage: "plus") { onNewCollection() }
        } label: {
            Label("Add to Collection", systemImage: "rectangle.stack.badge.plus")
        }
    }
}

/// Recipes → More → Collections, on iPhone and iPad (whose system sidebar is not reordered by
/// hand). The cook's collections in their order, each with its count; tap one to show it, Edit to
/// reorder or delete, and Rename… or Delete from a row's menu or swipe. New Collection stays in
/// More and, on iPad, in the sidebar's Collections section.
struct CollectionsList: View {
    /// Shows the collection's recipes.
    let onShow: (RecipeCollection) -> Void
    /// Called before a collection is deleted, so the host can clear a filter that names it.
    let onDelete: (RecipeCollection) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    @Query(sort: CollectionActions.sortDescriptors) private var collections: [RecipeCollection]
    @State private var renamingCollection: RecipeCollection?
    @State private var deletingCollection: RecipeCollection?

    var body: some View {
        List {
            ForEach(collections) { collection in
                Button {
                    onShow(collection)
                } label: {
                    Label(collection.name, systemImage: "rectangle.stack")
                        .badge(collection.recipes?.count ?? 0)
                }
                .tint(.primary)
                .contextMenu {
                    Button("Rename…", systemImage: "pencil") { renamingCollection = collection }
                    Button("Delete", systemImage: "trash", role: .destructive) { deletingCollection = collection }
                }
                .swipeActions(edge: .trailing) {
                    Button("Delete", systemImage: "trash", role: .destructive) { deletingCollection = collection }
                    Button("Rename", systemImage: "pencil") { renamingCollection = collection }
                }
            }
            .onMove { source, destination in
                CollectionActions.move(collections, from: source, to: destination, in: modelContext)
            }
            .onDelete { offsets in
                deletingCollection = offsets.first.map { collections[$0] }
            }
        }
        .overlay {
            if collections.isEmpty {
                ContentUnavailableView {
                    Label("No Collections", systemImage: "rectangle.stack")
                } description: {
                    Text("Make one with New Collection in the Recipes More menu.")
                }
            }
        }
        .navigationTitle("Collections")
        .toolbar {
            if collections.count > 1 {
                ToolbarItem(placement: .primaryAction) {
                    EditButton()
                }
            }
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
                onDelete(collection)
                router.delete(collection, in: modelContext)
            }
        } message: { _ in
            Text("The recipes stay in your library.")
        }
    }
}

extension View {
    /// An alert asking for a collection's name, prefilled with `initialName`; Save is ignored while
    /// the name is blank.
    func collectionNamePrompt(
        _ title: String,
        isPresented: Binding<Bool>,
        initialName: String = "",
        actionTitle: String = "Save",
        onSave: @escaping (String) -> Void
    ) -> some View {
        modifier(CollectionNamePrompt(title: title, isPresented: isPresented, initialName: initialName, actionTitle: actionTitle, onSave: onSave))
    }
}

private struct CollectionNamePrompt: ViewModifier {
    let title: String
    @Binding var isPresented: Bool
    let initialName: String
    let actionTitle: String
    let onSave: (String) -> Void

    @State private var name = ""

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    func body(content: Content) -> some View {
        content
            .alert(title, isPresented: $isPresented) {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.words)
                Button("Cancel", role: .cancel) {}
                Button(actionTitle) {
                    if !trimmed.isEmpty { onSave(trimmed) }
                }
                .disabled(trimmed.isEmpty)
            }
            .onChange(of: isPresented) { _, presented in
                if presented { name = initialName }
            }
    }
}

/// A recipe dragged from the library onto a collection in the iPad sidebar. It travels as text
/// naming the recipe's id, so no custom type has to be declared in Info.plist.
struct RecipeDragItem: Transferable {
    let id: UUID

    static let prefix = "kitchencodex-recipe:"

    struct NotARecipe: Error {}

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation { (item: RecipeDragItem) in
            prefix + item.id.uuidString
        } importing: { (text: String) in
            guard text.hasPrefix(prefix), let id = UUID(uuidString: String(text.dropFirst(prefix.count))) else {
                throw NotARecipe()
            }
            return RecipeDragItem(id: id)
        }
    }
}
