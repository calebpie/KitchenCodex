import RecipeModel
import SwiftData
import SwiftUI

/// The library, with a view switch between the recipe collection and the cookbook shelf (03 §3.2, §3.7).
/// iPhone (compact width) is a stack with the Recipes · Books switch; iPad (regular width) is a
/// three-column split view: sidebar (All, Collections, Books), the recipes, and the recipe (03 §4).
struct RecipesView: View {
    enum LibraryView: String, CaseIterable, Identifiable {
        case recipes = "Recipes"
        case books = "Books"
        var id: Self { self }
    }

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var modelContext

    @State private var libraryView: LibraryView = .recipes
    @AppStorage("recipes.layout") private var layout: RecipeLayout = .grid
    @AppStorage("recipes.sort") private var sort: RecipeSort = .title
    @State private var filter = RecipeFilter()
    @State private var isAddingRecipe = false
    @State private var isImportingFromWeb = false
    @State private var isImportingLibrary = false
    /// iPhone: the pushed recipes.
    @State private var path: [Recipe] = []
    /// iPad: the sidebar's scope and the recipe shown in the detail column.
    @State private var scope: LibraryScope? = .all
    @State private var selectedRecipeID: PersistentIdentifier?
    /// Set by the import sheet; opened once the sheet has gone.
    @State private var importedRecipe: Recipe?
    @State private var isCreatingCollection = false
    @State private var isRenamingCollection = false
    @State private var isConfirmingCollectionDeletion = false

    /// Unsorted; used for the empty state, the Course chip's options and resolving the selection.
    /// The collection runs its own sorted query.
    @Query private var allRecipes: [Recipe]
    @Query private var books: [Book]
    @Query(sort: CollectionActions.sortDescriptors) private var collections: [RecipeCollection]

    private var isSplit: Bool { sizeClass == .regular }

    /// Which view the Add and More menus follow: the switch on iPhone, the sidebar on iPad.
    private var activeView: LibraryView {
        if isSplit { return scope == .shelf ? .books : .recipes }
        return libraryView
    }

    /// The collection on screen: the sidebar's on iPad, the Collection chip's on iPhone.
    private var currentCollection: RecipeCollection? {
        let id: PersistentIdentifier?
        if isSplit, case let .collection(scopeID)? = scope {
            id = scopeID
        } else {
            id = filter.collection
        }
        return id.flatMap { id in collections.first { $0.persistentModelID == id } }
    }

    var body: some View {
        Group {
            if isSplit { splitLayout } else { stackLayout }
        }
        .sheet(isPresented: $isAddingRecipe) {
            RecipeEditorView(recipe: nil)
        }
        .sheet(isPresented: $isImportingFromWeb, onDismiss: openImportedRecipe) {
            WebImportView { recipe in importedRecipe = recipe }
        }
        .sheet(isPresented: $isImportingLibrary) {
            LibraryImportView()
        }
        .collectionNamePrompt("New Collection", isPresented: $isCreatingCollection, actionTitle: "Create") { name in
            show(CollectionActions.create(named: name, in: modelContext))
        }
        .collectionNamePrompt("Rename Collection", isPresented: $isRenamingCollection, initialName: currentCollection?.name ?? "") { name in
            currentCollection?.name = name
            try? modelContext.save()
        }
        .confirmationDialog(
            "Delete “\(currentCollection?.name ?? "")”?",
            isPresented: $isConfirmingCollectionDeletion,
            titleVisibility: .visible,
            presenting: currentCollection
        ) { collection in
            Button("Delete Collection", role: .destructive) { deleteCollection(collection) }
        } message: { _ in
            Text("The recipes stay in your library.")
        }
        .onChange(of: router.requestedRecipeID, initial: true) { _, id in
            guard let id else { return }
            router.requestedRecipeID = nil
            if let recipe = allRecipes.first(where: { $0.id == id }) { open(recipe) }
        }
    }

    // MARK: - iPhone

    private var stackLayout: some View {
        NavigationStack(path: $path) {
            libraryContent(scope: libraryView == .books ? .shelf : .all, selection: nil)
                .navigationTitle("Recipes")
                .navigationDestination(for: Recipe.self) { recipe in
                    RecipeDetailView(recipe: recipe)
                }
                .safeAreaInset(edge: .top) {
                    VStack(spacing: 8) {
                        Picker("View", selection: $libraryView) {
                            ForEach(LibraryView.allCases) { view in
                                Text(view.rawValue).tag(view)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)

                        if libraryView == .recipes, !allRecipes.isEmpty {
                            FilterChips(filter: $filter, courses: RecipeCourse.options(including: allRecipes), collections: collections)
                        }
                    }
                    .padding(.bottom, 8)
                }
                .toolbar { libraryToolbar }
        }
    }

    // MARK: - iPad

    private var splitLayout: some View {
        NavigationSplitView {
            LibrarySidebar(selection: $scope)
                .navigationTitle("Recipes")
        } content: {
            let scope = scope ?? .all
            libraryContent(scope: scope, selection: $selectedRecipeID)
                .navigationTitle(LibrarySidebar.title(for: scope, books: books, collections: collections))
                .safeAreaInset(edge: .top) {
                    if scope != .shelf, !allRecipes.isEmpty {
                        // Collections are picked in the sidebar here; the chip only shows to clear one
                        // chosen in a compact window.
                        FilterChips(filter: $filter, courses: RecipeCourse.options(including: allRecipes), collections: filter.collection == nil ? [] : collections)
                            .padding(.bottom, 8)
                    }
                }
                .toolbar { libraryToolbar }
        } detail: {
            NavigationStack {
                if let recipe = selectedRecipe {
                    RecipeDetailView(recipe: recipe, onDelete: { delete(recipe) })
                        // A new recipe starts from its own servings and units.
                        .id(recipe.persistentModelID)
                } else {
                    ContentUnavailableView {
                        Label("No Recipe Selected", systemImage: "book.closed")
                    } description: {
                        Text(allRecipes.isEmpty ? "Add a recipe to see it here." : "Choose a recipe to read, scale or cook it.")
                    }
                }
            }
        }
    }

    private var selectedRecipe: Recipe? {
        guard let selectedRecipeID else { return nil }
        return allRecipes.first { $0.persistentModelID == selectedRecipeID }
    }

    // MARK: - Shared

    @ViewBuilder
    private func libraryContent(scope: LibraryScope, selection: Binding<PersistentIdentifier?>?) -> some View {
        if scope == .shelf {
            ContentUnavailableView {
                Label("Your shelf is empty", systemImage: "books.vertical")
            } description: {
                Text("Add a cookbook by scanning its ISBN to start building its recipe list.")
            }
        } else if allRecipes.isEmpty {
            ContentUnavailableView {
                Label("No recipes yet", systemImage: "book.closed")
            } description: {
                Text("Share a recipe from Safari, scan a cookbook page, or add one by hand.")
            }
        } else {
            LibraryRecipes(sort: sort, layout: layout, scope: scope, filter: $filter, collections: collections, selection: selection)
        }
    }

    @ToolbarContentBuilder
    private var libraryToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            // Contextual Add: the items follow the view (02 §1.3).
            Menu {
                switch activeView {
                case .recipes:
                    Button("Import from Web", systemImage: "link") {
                        isImportingFromWeb = true
                    }
                    // Scanning arrives in Phase 2.
                    Button("Scan Page", systemImage: "text.viewfinder") {}
                        .disabled(true)
                    Button("New Recipe", systemImage: "square.and.pencil") {
                        isAddingRecipe = true
                    }
                    .keyboardShortcut("n")
                case .books:
                    Button("Add Book", systemImage: "barcode.viewfinder") {}
                        .disabled(true)
                }
            } label: {
                Label("Add", systemImage: "plus")
            }
        }
        // Primary placement, not .secondaryAction: the latter nests this menu inside the
        // system overflow menu, so More would open a menu holding only "More".
        ToolbarItem(placement: .primaryAction) {
            Menu {
                switch activeView {
                case .recipes:
                    Picker(selection: $layout) {
                        ForEach(RecipeLayout.allCases) { option in
                            Label(option.title, systemImage: option.systemImage).tag(option)
                        }
                    } label: {
                        Label("View As", systemImage: layout.systemImage)
                    }
                    .pickerStyle(.inline)

                    Picker(selection: $sort) {
                        ForEach(RecipeSort.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    } label: {
                        Label("Sort By", systemImage: "arrow.up.arrow.down")
                    }
                    .pickerStyle(.menu)

                    Button("Select", systemImage: "checkmark.circle") {}
                        .disabled(true)
                    Divider()
                    Button("New Collection…", systemImage: "rectangle.stack.badge.plus") {
                        isCreatingCollection = true
                    }
                    if let collection = currentCollection {
                        Button("Rename “\(collection.name)”…", systemImage: "pencil") {
                            isRenamingCollection = true
                        }
                        Button("Delete “\(collection.name)”…", systemImage: "trash", role: .destructive) {
                            isConfirmingCollectionDeletion = true
                        }
                    }
                    Divider()
                    Button("Import Library…", systemImage: "tray.and.arrow.down") {
                        isImportingLibrary = true
                    }
                case .books:
                    Button("Sort", systemImage: "arrow.up.arrow.down") {}
                        .disabled(true)
                }
            } label: {
                Label("More", systemImage: "ellipsis")
            }
        }
    }

    /// Shows `recipe`: pushed on iPhone, selected on iPad (widening the scope if it hides the recipe).
    private func open(_ recipe: Recipe) {
        if isSplit {
            if !(scope ?? .all).contains(recipe) { scope = .all }
            selectedRecipeID = recipe.persistentModelID
        } else {
            libraryView = .recipes
            path = [recipe]
        }
    }

    /// A new collection: selected in the sidebar on iPad, chosen in the Collection chip on iPhone.
    private func show(_ collection: RecipeCollection) {
        if isSplit {
            scope = .collection(collection.persistentModelID)
        } else {
            libraryView = .recipes
            filter.collection = collection.persistentModelID
        }
    }

    private func deleteCollection(_ collection: RecipeCollection) {
        let id = collection.persistentModelID
        if scope == .collection(id) { scope = .all }
        if filter.collection == id { filter.collection = nil }
        CollectionActions.delete(collection, in: modelContext)
    }

    private func openImportedRecipe() {
        guard let recipe = importedRecipe else { return }
        importedRecipe = nil
        open(recipe)
    }

    /// Delete from the iPad detail column: clear the selection first so the column never renders a
    /// deleted model, then delete on the next turn of the run loop.
    private func delete(_ recipe: Recipe) {
        selectedRecipeID = nil
        Task {
            await Task.yield()
            modelContext.delete(recipe)
            try? modelContext.save()
        }
    }
}

/// The filtered, sorted recipes as a grid or a list. With a `selection` (iPad) a tap selects the
/// recipe for the detail column and a recipe can be dragged onto a sidebar collection; without one
/// (iPhone) a tap pushes the recipe.
private struct LibraryRecipes: View {
    @Query private var recipes: [Recipe]
    let layout: RecipeLayout
    let scope: LibraryScope
    @Binding var filter: RecipeFilter
    let collections: [RecipeCollection]
    let selection: Binding<PersistentIdentifier?>?

    @Environment(\.modelContext) private var modelContext
    @State private var pendingDeletion: Recipe?
    /// Long-press → Add to Collection → New Collection…: the recipe to put in it once named.
    @State private var collectingRecipe: Recipe?

    init(sort: RecipeSort, layout: RecipeLayout, scope: LibraryScope, filter: Binding<RecipeFilter>, collections: [RecipeCollection], selection: Binding<PersistentIdentifier?>?) {
        _recipes = Query(sort: sort.descriptors, animation: .default)
        self.layout = layout
        self.scope = scope
        _filter = filter
        self.collections = collections
        self.selection = selection
    }

    /// The collection being shown, by the sidebar or by the chip, for its empty state.
    private var shownCollection: RecipeCollection? {
        var id = filter.collection
        if case let .collection(scopeID) = scope { id = scopeID }
        return id.flatMap { id in collections.first { $0.persistentModelID == id } }
    }

    var body: some View {
        let visible = recipes.filter { scope.contains($0) && filter.matches($0) }
        // The grid or list stays in place even when empty, so the large title keeps tracking a scroll view.
        Group {
            switch layout {
            case .grid: grid(visible)
            case .list: list(visible)
            }
        }
        .overlay {
            if visible.isEmpty {
                if let collection = shownCollection, filter.course == nil, filter.cooked == .any {
                    ContentUnavailableView {
                        Label("Nothing in “\(collection.name)” yet", systemImage: "rectangle.stack")
                    } description: {
                        Text(selection == nil
                            ? "Add a recipe from its long-press menu: Add to Collection."
                            : "Drag recipes onto the collection in the sidebar, or use Add to Collection in their long-press menu.")
                    }
                } else if filter.isActive {
                    ContentUnavailableView {
                        Label("No matching recipes", systemImage: "line.3.horizontal.decrease.circle")
                    } description: {
                        Text("No recipes match these filters.")
                    } actions: {
                        Button("Clear Filters") { filter = RecipeFilter() }
                    }
                } else {
                    ContentUnavailableView {
                        Label("Nothing here yet", systemImage: "book.closed")
                    } description: {
                        Text(Self.emptyDescription(for: scope))
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete “\(pendingDeletion?.title ?? "")”?",
            isPresented: Binding { pendingDeletion != nil } set: { if !$0 { pendingDeletion = nil } },
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { recipe in
            Button("Delete Recipe", role: .destructive) { delete(recipe) }
        } message: { _ in
            Text("The recipe and all its versions will be deleted.")
        }
        .collectionNamePrompt(
            "New Collection",
            isPresented: Binding { collectingRecipe != nil } set: { if !$0 { collectingRecipe = nil } },
            actionTitle: "Create"
        ) { name in
            CollectionActions.create(named: name, adding: collectingRecipe, in: modelContext)
        }
    }

    private static func emptyDescription(for scope: LibraryScope) -> String {
        switch scope {
        case .favorites: "Favorite a recipe from its long-press menu or by swiping its row."
        case .neverCooked: "Every recipe here has been cooked."
        case .needsReview: "No imported recipe is waiting for a check."
        case .collection: "Add recipes from their long-press menu."
        case .book: "No recipes from this book are in the library yet."
        case .all, .shelf: "No recipes yet."
        }
    }

    private func grid(_ recipes: [Recipe]) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                ForEach(recipes) { recipe in
                    Group {
                        if let selection {
                            let isSelected = selection.wrappedValue == recipe.persistentModelID
                            Button {
                                selection.wrappedValue = recipe.persistentModelID
                            } label: {
                                RecipeCard(recipe: recipe)
                                    .overlay {
                                        if isSelected {
                                            RoundedRectangle(cornerRadius: 22)
                                                .strokeBorder(.tint, lineWidth: 3)
                                        }
                                    }
                            }
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                        } else {
                            NavigationLink(value: recipe) {
                                RecipeCard(recipe: recipe)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu { actions(for: recipe) }
                    .modifier(RecipeDragSource(recipe: recipe, isEnabled: selection != nil))
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
    }

    @ViewBuilder
    private func list(_ recipes: [Recipe]) -> some View {
        if let selection {
            List(selection: selection) {
                ForEach(recipes) { recipe in
                    RecipeRow(recipe: recipe)
                        .tag(recipe.persistentModelID)
                        .contextMenu { actions(for: recipe) }
                        .draggable(RecipeDragItem(id: recipe.id)) { RecipeRow(recipe: recipe).frame(width: 320) }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) { favoriteSwipe(recipe) }
                }
            }
            .listStyle(.plain)
        } else {
            List(recipes) { recipe in
                NavigationLink(value: recipe) {
                    RecipeRow(recipe: recipe)
                }
                .contextMenu { actions(for: recipe) }
                .swipeActions(edge: .leading, allowsFullSwipe: true) { favoriteSwipe(recipe) }
            }
            .listStyle(.plain)
        }
    }

    private func favoriteSwipe(_ recipe: Recipe) -> some View {
        Button {
            recipe.isFavorite.toggle()
        } label: {
            Label(recipe.isFavorite ? "Unfavorite" : "Favorite", systemImage: recipe.isFavorite ? "heart.slash" : "heart")
        }
        .tint(.accentColor)
    }

    /// Long-press actions (03 §2 Menus): Cook, Favorite, Add to Collection, Share, Delete. Add to menu
    /// arrives with Plan.
    @ViewBuilder
    private func actions(for recipe: Recipe) -> some View {
        Button("Cook", systemImage: "frying.pan") {}
            .disabled(true) // Cook mode is Phase 3.
        Button(recipe.isFavorite ? "Unfavorite" : "Favorite", systemImage: recipe.isFavorite ? "heart.slash" : "heart") {
            recipe.isFavorite.toggle()
        }
        AddToCollectionMenu(recipe: recipe) { collectingRecipe = recipe }
        ShareRecipeMenu(recipe: recipe)
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) {
            pendingDeletion = recipe
        }
    }

    private func delete(_ recipe: Recipe) {
        if selection?.wrappedValue == recipe.persistentModelID { selection?.wrappedValue = nil }
        withAnimation {
            modelContext.delete(recipe)
        }
        try? modelContext.save()
        pendingDeletion = nil
    }
}

/// iPad: a card can be dragged onto a collection in the sidebar.
private struct RecipeDragSource: ViewModifier {
    let recipe: Recipe
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.draggable(RecipeDragItem(id: recipe.id)) {
                RecipeCard(recipe: recipe).frame(width: 180)
            }
        } else {
            content
        }
    }
}

/// Course, Cooked state and Collection chips under the view switch. Each chip is a menu; an active
/// chip is filled and names its value. The Collection chip shows once there is a collection.
private struct FilterChips: View {
    @Binding var filter: RecipeFilter
    let courses: [String]
    let collections: [RecipeCollection]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                Menu {
                    Picker("Course", selection: $filter.course) {
                        Text("Any Course").tag(String?.none)
                        ForEach(courses, id: \.self) { course in
                            Text(course).tag(Optional(course))
                        }
                    }
                } label: {
                    ChipLabel(title: filter.course ?? "Course", isActive: filter.course != nil)
                }

                Menu {
                    Picker("Cooked", selection: $filter.cooked) {
                        ForEach(CookedFilter.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                } label: {
                    ChipLabel(title: filter.cooked == .any ? "Cooked" : filter.cooked.title, isActive: filter.cooked != .any)
                }

                if !collections.isEmpty {
                    Menu {
                        Picker("Collection", selection: $filter.collection) {
                            Text("Any Collection").tag(PersistentIdentifier?.none)
                            ForEach(collections) { collection in
                                Text(collection.name).tag(Optional(collection.persistentModelID))
                            }
                        }
                    } label: {
                        let name = collections.first { $0.persistentModelID == filter.collection }?.name
                        ChipLabel(title: name ?? "Collection", isActive: filter.collection != nil)
                    }
                }

                if filter.isActive {
                    Button("Clear", systemImage: "xmark.circle.fill") {
                        filter = RecipeFilter()
                    }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, minHeight: 44)
                }
            }
            .padding(.horizontal)
        }
        .scrollIndicators(.hidden)
    }
}

private struct ChipLabel: View {
    let title: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
            Image(systemName: "chevron.down")
                .imageScale(.small)
        }
        .font(.subheadline.weight(isActive ? .semibold : .regular))
        .padding(.horizontal, 14)
        .frame(minHeight: 36)
        .foregroundStyle(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        .background(isActive ? AnyShapeStyle(.tint.quaternary) : AnyShapeStyle(.fill.tertiary), in: .capsule)
        // The capsule is 36 pt; the hit area keeps the 44 pt minimum.
        .padding(.vertical, 4)
        .contentShape(.rect)
    }
}

#Preview {
    RecipesView()
        .environment(AppRouter())
        .modelContainer(try! RecipeStore.makeContainer(inMemory: true))
}
