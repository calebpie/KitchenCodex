import RecipeModel
import SwiftData
import SwiftUI

/// What the iPhone Recipes stack pushes: a recipe, or Needs a Look.
enum LibraryRoute: Hashable {
    case recipe(Recipe)
    case needsReview
}

/// The library, with a view switch between the recipe collection and the cookbook shelf (03 §3.2, §3.7).
/// iPhone (compact width) is a stack with the Recipes · Books switch; iPad (regular width) is a
/// three-column split view: sidebar (All, Collections, Books), the recipes, and the recipe (03 §4).
/// Only the navigation bar floats: the switch, the review prompt and the filter tokens are the first
/// items of the scrolling content (04 §5.1 Floating headers).
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
    @AppStorage("recipes.groupBy") private var grouping: RecipeGrouping = .course
    @State private var filter = RecipeFilter()
    @State private var isAddingRecipe = false
    @State private var isImportingFromWeb = false
    @State private var isImportingLibrary = false
    /// iPhone: the pushed recipes.
    @State private var path: [LibraryRoute] = []
    /// iPad: the sidebar's scope and the recipe shown in the detail column.
    @State private var scope: LibraryScope? = .all
    @State private var selectedRecipeID: PersistentIdentifier?
    /// Set by the import sheet; opened once the sheet has gone.
    @State private var importedRecipe: Recipe?
    @State private var isCreatingCollection = false
    @State private var isRenamingCollection = false
    @State private var isConfirmingCollectionDeletion = false

    /// Unsorted; used for the empty state, the Filter menu's courses and resolving the selection.
    /// The collection runs its own sorted query.
    @Query private var allRecipes: [Recipe]
    @Query(sort: [SortDescriptor(\Book.title, comparator: .localizedStandard)]) private var books: [Book]
    @Query(sort: CollectionActions.sortDescriptors) private var collections: [RecipeCollection]
    @Query(sort: [SortDescriptor(\Tag.name, comparator: .localizedStandard)]) private var tags: [Tag]

    private var isSplit: Bool { sizeClass == .regular }

    /// Which view the Add and More menus follow: the switch on iPhone, the sidebar on iPad.
    private var activeView: LibraryView {
        if isSplit { return scope == .shelf ? .books : .recipes }
        return libraryView
    }

    /// The collection on screen: the sidebar's on iPad, the Filter menu's on iPhone.
    private var currentCollection: RecipeCollection? {
        let id: PersistentIdentifier?
        if isSplit, case let .collection(scopeID)? = scope {
            id = scopeID
        } else {
            id = filter.collection
        }
        return id.flatMap { id in collections.first { $0.persistentModelID == id } }
    }

    private var reviewCount: Int { allRecipes.count(where: \.needsReview) }

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
            Group {
                if libraryView == .books || allRecipes.isEmpty {
                    ScrollView {
                        VStack(spacing: 32) {
                            libraryHeader(showsSwitch: true)
                            emptyLibrary(scope: libraryView == .books ? .shelf : .all)
                        }
                    }
                } else {
                    LibraryRecipes(sort: sort, layout: layout, grouping: grouping, scope: .all, filter: $filter, collections: collections, selection: nil) {
                        libraryHeader(showsSwitch: true)
                    }
                }
            }
            .navigationTitle("Recipes")
            .navigationDestination(for: LibraryRoute.self) { route in
                switch route {
                case let .recipe(recipe): RecipeDetailView(recipe: recipe)
                case .needsReview: NeedsALookView()
                }
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
            Group {
                if scope == .shelf || allRecipes.isEmpty {
                    emptyLibrary(scope: scope)
                } else {
                    LibraryRecipes(sort: sort, layout: layout, grouping: grouping, scope: scope, filter: $filter, collections: collections, selection: $selectedRecipeID) {
                        libraryHeader(showsSwitch: false)
                    }
                }
            }
            .navigationTitle(LibrarySidebar.title(for: scope, books: books, collections: collections))
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

    /// The first items of the scrolling content: the view switch (iPhone), the review prompt while
    /// imports wait for a check, and one token per active filter.
    @ViewBuilder
    private func libraryHeader(showsSwitch: Bool) -> some View {
        let showsPrompt = activeView == .recipes && reviewCount > 0 && scope != .needsReview
        let showsTokens = activeView == .recipes && filter.isActive
        if showsSwitch || showsPrompt || showsTokens {
            VStack(alignment: .leading, spacing: 12) {
                if showsSwitch {
                    Picker("View", selection: $libraryView) {
                        ForEach(LibraryView.allCases) { view in
                            Text(view.rawValue).tag(view)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                }
                if showsPrompt {
                    NeedsALookRow(count: reviewCount) {
                        if isSplit {
                            scope = .needsReview
                        } else {
                            path.append(.needsReview)
                        }
                    }
                    .padding(.horizontal)
                }
                if showsTokens {
                    FilterTokens(tokens: filterTokens) { filter = RecipeFilter() }
                }
            }
            .padding(.bottom, 4)
        }
    }

    @ViewBuilder
    private func emptyLibrary(scope: LibraryScope) -> some View {
        if scope == .shelf {
            ContentUnavailableView {
                Label("Your shelf is empty", systemImage: "books.vertical")
            } description: {
                Text("Cookbooks you add will be listed here with their recipes.")
            }
        } else {
            ContentUnavailableView {
                Label("No recipes yet", systemImage: "book.closed")
            } description: {
                Text("Import one from the web or from Paprika or Mela, share one from Safari, or enter one manually.")
            }
        }
    }

    // MARK: - Filter

    /// Courses the library uses, in the standard order.
    private var filterCourses: [String] {
        let used = Set(allRecipes.compactMap(\.course))
        return RecipeCourse.options(including: allRecipes).filter(used.contains)
    }

    /// One token per active filter, each removing only itself.
    private var filterTokens: [FilterTokens.Token] {
        var tokens: [FilterTokens.Token] = []
        for course in filterCourses where filter.courses.contains(course) {
            tokens.append(.init(id: "course:\(course)", title: course) { filter.courses.remove(course) })
        }
        if filter.cooked != .any {
            tokens.append(.init(id: "cooked", title: filter.cooked.title) { filter.cooked = .any })
        }
        if filter.favorites {
            tokens.append(.init(id: "favorites", title: "Favorites") { filter.favorites = false })
        }
        if filter.needsReview {
            tokens.append(.init(id: "needsReview", title: "Needs a Look") { filter.needsReview = false })
        }
        if let id = filter.collection {
            let name = collections.first { $0.persistentModelID == id }?.name ?? "Collection"
            tokens.append(.init(id: "collection", title: name) { filter.collection = nil })
        }
        if let id = filter.book {
            let title = books.first { $0.persistentModelID == id }?.title ?? "Book"
            tokens.append(.init(id: "book", title: title) { filter.book = nil })
        }
        if let id = filter.tag {
            let name = tags.first { $0.persistentModelID == id }?.name ?? "Tag"
            tokens.append(.init(id: "tag", title: name) { filter.tag = nil })
        }
        return tokens
    }

    /// Filter (04 §5.1 Recipes filters): checkable sections; the menu closes after each choice, as
    /// menus do. Collections are picked in the sidebar on iPad, so the section is iPhone only.
    private var filterMenu: some View {
        Menu {
            let courses = filterCourses
            if !courses.isEmpty {
                Section("Course") {
                    ForEach(courses, id: \.self) { course in
                        Toggle(course, isOn: Binding {
                            filter.courses.contains(course)
                        } set: { isOn in
                            if isOn { filter.courses.insert(course) } else { filter.courses.remove(course) }
                        })
                    }
                }
            }
            Section("Cooked") {
                ForEach([CookedFilter.neverCooked, .cooked]) { option in
                    Toggle(option.title, isOn: Binding { filter.cooked == option } set: { filter.cooked = $0 ? option : .any })
                }
            }
            Section {
                Toggle("Favorites", systemImage: "heart", isOn: $filter.favorites)
                Toggle("Needs a Look", systemImage: "exclamationmark.bubble", isOn: $filter.needsReview)
            }
            if !isSplit, !collections.isEmpty {
                filterSubmenu("Collection", systemImage: "rectangle.stack", items: collections.map { ($0.persistentModelID, $0.name) }, selection: $filter.collection)
            }
            if !books.isEmpty {
                filterSubmenu("Book", systemImage: "book", items: books.map { ($0.persistentModelID, $0.title.isEmpty ? "Untitled Book" : $0.title) }, selection: $filter.book)
            }
            if !tags.isEmpty {
                filterSubmenu("Tag", systemImage: "tag", items: tags.map { ($0.persistentModelID, $0.name) }, selection: $filter.tag)
            }
            if filter.isActive {
                Section {
                    Button("Clear Filters", systemImage: "xmark.circle") { filter = RecipeFilter() }
                }
            }
        } label: {
            Label("Filter", systemImage: filter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .tint(filter.isActive ? .accentColor : nil)
        .accessibilityValue(filter.isActive ? "\(filterTokens.count) active" : "None")
    }

    /// A submenu with one checkable item per collection, book or tag; checking another replaces it.
    private func filterSubmenu(_ title: String, systemImage: String, items: [(PersistentIdentifier, String)], selection: Binding<PersistentIdentifier?>) -> some View {
        Menu {
            ForEach(items, id: \.0) { id, name in
                Toggle(name, isOn: Binding { selection.wrappedValue == id } set: { selection.wrappedValue = $0 ? id : nil })
            }
        } label: {
            Label(title, systemImage: systemImage)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var libraryToolbar: some ToolbarContent {
        if activeView == .recipes {
            ToolbarItem(placement: .primaryAction) {
                // Add names the ways in (04 §5.1 Add menu); methods that haven't shipped are hidden.
                Menu {
                    Button("Import from Web", systemImage: "link") {
                        isImportingFromWeb = true
                    }
                    Button("Enter Manually", systemImage: "square.and.pencil") {
                        isAddingRecipe = true
                    }
                    .keyboardShortcut("n")
                    Divider()
                    Button("Import from Paprika or Mela…", systemImage: "tray.and.arrow.down") {
                        isImportingLibrary = true
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                filterMenu
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

                    Picker(selection: $grouping) {
                        ForEach(RecipeGrouping.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    } label: {
                        Label("Group By", systemImage: "rectangle.3.group")
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
            path = [.recipe(recipe)]
        }
    }

    /// A new collection: selected in the sidebar on iPad, set as the Collection filter on iPhone.
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

/// The filtered, sorted, grouped recipes as a grid or a list, under `header`. With a `selection`
/// (iPad) a tap selects the recipe for the detail column and a recipe can be dragged onto a sidebar
/// collection; without one (iPhone) a tap pushes the recipe.
private struct LibraryRecipes<Header: View>: View {
    @Query private var recipes: [Recipe]
    let layout: RecipeLayout
    let grouping: RecipeGrouping
    let scope: LibraryScope
    @Binding var filter: RecipeFilter
    let collections: [RecipeCollection]
    let selection: Binding<PersistentIdentifier?>?
    @ViewBuilder let header: Header

    @Environment(\.modelContext) private var modelContext
    @State private var pendingDeletion: Recipe?
    /// Long-press → Add to Collection → New Collection…: the recipe to put in it once named.
    @State private var collectingRecipe: Recipe?

    init(sort: RecipeSort, layout: RecipeLayout, grouping: RecipeGrouping, scope: LibraryScope, filter: Binding<RecipeFilter>, collections: [RecipeCollection], selection: Binding<PersistentIdentifier?>?, @ViewBuilder header: () -> Header) {
        _recipes = Query(sort: sort.descriptors, animation: .default)
        self.layout = layout
        self.grouping = grouping
        self.scope = scope
        _filter = filter
        self.collections = collections
        self.selection = selection
        self.header = header()
    }

    /// The collection being shown, by the sidebar or by the filter, for its empty state.
    private var shownCollection: RecipeCollection? {
        var id = filter.collection
        if case let .collection(scopeID) = scope { id = scopeID }
        return id.flatMap { id in collections.first { $0.persistentModelID == id } }
    }

    var body: some View {
        let visible = recipes.filter { scope.contains($0) && filter.matches($0) }
        let sections = grouping.sections(visible, collections: collections)
        // The grid or list stays in place even when empty, so the large title keeps tracking a scroll view.
        Group {
            switch layout {
            case .grid: grid(sections, isEmpty: visible.isEmpty)
            case .list: list(sections, isEmpty: visible.isEmpty)
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

    @ViewBuilder
    private var emptyState: some View {
        let isCollectionOnly = filter.isOnlyCollection || (!filter.isActive && { if case .collection = scope { true } else { false } }())
        if let collection = shownCollection, isCollectionOnly {
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

    private func grid(_ sections: [RecipeGrouping.Section], isEmpty: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                if isEmpty {
                    emptyState
                        .padding(.top, 40)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                        ForEach(sections) { section in
                            Section {
                                ForEach(section.recipes) { recipe in
                                    card(recipe)
                                }
                            } header: {
                                // A lone section hides its header (04 §5.1 Recipes filters).
                                if sections.count > 1 {
                                    Text(section.title)
                                        .font(.title3.bold())
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.top, 12)
                                        .accessibilityAddTraits(.isHeader)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.bottom)
        }
    }

    private func card(_ recipe: Recipe) -> some View {
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
                NavigationLink(value: LibraryRoute.recipe(recipe)) {
                    RecipeCard(recipe: recipe)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu { actions(for: recipe) }
        .modifier(RecipeDragSource(recipe: recipe, isEnabled: selection != nil))
    }

    @ViewBuilder
    private func list(_ sections: [RecipeGrouping.Section], isEmpty: Bool) -> some View {
        if let selection {
            List(selection: selection) {
                listContent(sections, isEmpty: isEmpty) { recipe in
                    RecipeRow(recipe: recipe)
                        .tag(recipe.persistentModelID)
                        .draggable(RecipeDragItem(id: recipe.id)) { RecipeRow(recipe: recipe).frame(width: 320) }
                }
            }
            .listStyle(.plain)
        } else {
            List {
                listContent(sections, isEmpty: isEmpty) { recipe in
                    NavigationLink(value: LibraryRoute.recipe(recipe)) {
                        RecipeRow(recipe: recipe)
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    /// The header as the first row, then the recipes under section headers when there are several.
    @ViewBuilder
    private func listContent(_ sections: [RecipeGrouping.Section], isEmpty: Bool, @ViewBuilder row: @escaping (Recipe) -> some View) -> some View {
        header
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        if isEmpty {
            emptyState
                .padding(.top, 40)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        } else {
            ForEach(sections) { section in
                Section {
                    ForEach(section.recipes) { recipe in
                        row(recipe)
                            .contextMenu { actions(for: recipe) }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) { favoriteSwipe(recipe) }
                    }
                } header: {
                    if sections.count > 1 {
                        Text(section.title)
                    }
                }
            }
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

/// The active filters as removable tokens, one per filter, and Clear, scrolling with the content
/// (04 §5.1 Recipes filters). Never shown while nothing is filtered.
private struct FilterTokens: View {
    struct Token: Identifiable {
        let id: String
        let title: String
        let remove: () -> Void
    }

    let tokens: [Token]
    var onClear: () -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(tokens) { token in
                    Button {
                        withAnimation { token.remove() }
                    } label: {
                        HStack(spacing: 6) {
                            Text(token.title)
                            Image(systemName: "xmark")
                                .imageScale(.small)
                                .fontWeight(.semibold)
                        }
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 34)
                        .foregroundStyle(.tint)
                        .background(.tint.quaternary, in: .capsule)
                        // The capsule is 34 pt; the hit area keeps the 44 pt minimum.
                        .padding(.vertical, 5)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove filter: \(token.title)")
                }
                Button("Clear") {
                    withAnimation { onClear() }
                }
                .font(.subheadline)
                .frame(minHeight: 44)
                .accessibilityLabel("Clear Filters")
            }
            .padding(.horizontal)
        }
        .scrollIndicators(.hidden)
    }
}

#Preview {
    RecipesView()
        .environment(AppRouter())
        .modelContainer(try! RecipeStore.makeContainer(inMemory: true))
}
