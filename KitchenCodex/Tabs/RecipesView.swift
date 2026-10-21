import RecipeModel
import SwiftData
import SwiftUI

/// What the Recipes stack pushes: a recipe by its identifier, the Collections list, and on iPhone
/// Needs a Look. On iPad each sidebar tab's page pushes the same routes over its grid or the shelf.
enum LibraryRoute: Hashable {
    case recipe(PersistentIdentifier)
    case needsReview
    case collections
    /// A book's detail (03 §3.7), pushed over the shelf as a recipe is over the grid.
    case book(PersistentIdentifier)
    /// A reference's page, from a book's detail (04 §5.1 "References home").
    case reference(PersistentIdentifier)
}

/// The library, with a view switch between the recipe collection and the cookbook shelf (03 §3.2, §3.7).
/// iPhone (compact width) is the Recipes tab's stack with the Recipes · Cookbooks switch. On iPad each
/// Recipes tab in the system sidebar (04 §5.1 iPad tabs) is one of these in its own `scope`: the
/// Recipes tab itself the whole library, then All Cookbooks, the smart collections and each
/// collection, each one wide column with the grid or list under the content toolbar, where a recipe
/// pushes over the grid (04 §5.1 iPad columns). Only the navigation bar floats: the switch, the
/// review prompt and the filter tokens are the first items of the scrolling content (04 §5.1
/// Floating headers).
struct RecipesView: View {
    enum LibraryView: String, CaseIterable, Identifiable {
        case recipes = "Recipes"
        case books = "Cookbooks"
        var id: Self { self }
    }

    /// The sidebar tab's scope; the whole library for the Recipes tab, and on iPhone.
    let scope: LibraryScope

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncMonitor.self) private var sync

    /// iPhone: the title switch's view.
    @State private var libraryView: LibraryView = .recipes
    @AppStorage("recipes.layout") private var layout: RecipeLayout = .grid
    @AppStorage("recipes.sort") private var sort: RecipeSort = .title
    @AppStorage("recipes.groupBy") private var grouping: RecipeGrouping = .course
    @AppStorage("books.sort") private var bookSort: BookSort = .title
    @State private var filter = RecipeFilter()
    /// The Filter list: a popover from the Filter button on iPad, a sheet on iPhone.
    @State private var isShowingFilter = false
    @State private var isAddingRecipe = false
    @State private var isImportingFromWeb = false
    @State private var isImportingLibrary = false
    /// Add → Scan Cookbook (02 Flow C): the barcode, the recipe list, the whole-book session.
    @State private var isScanningCookbook = false
    /// Add → Scan Page (02 Flow B): the camera on a device, From Photo and Files.
    @State private var isScanningPage = false
    /// Set by Scan Cookbook; its detail opens once the sheet has gone.
    @State private var addedBook: Book?
    /// What is pushed over the grid. One path for both widths, so an open recipe stays open when
    /// an iPad window changes width.
    @State private var path: [LibraryRoute] = []
    /// Set by the import and scan sheets; opened once the sheet has gone.
    @State private var importedRecipe: Recipe?
    @State private var isCreatingCollection = false
    @State private var isRenamingCollection = false
    @State private var isConfirmingCollectionDeletion = false
    /// More → Select (03 §3.2): circles on every recipe and the selection bar at the bottom.
    @State private var isSelecting = false
    @State private var selectedIDs: Set<PersistentIdentifier> = []
    /// Select mode → Add to Collection → New Collection…
    @State private var isCollectingSelection = false
    /// The sync flag's detail.
    @State private var isShowingSync = false

    /// Unsorted; used for the empty state, the Filter menu's courses and resolving the selection.
    /// The collection runs its own sorted query.
    @Query private var allRecipes: [Recipe]
    @Query(sort: [SortDescriptor(\Book.title, comparator: .localizedStandard)]) private var books: [Book]
    @Query(sort: CollectionActions.sortDescriptors) private var collections: [RecipeCollection]
    @Query(sort: [SortDescriptor(\Tag.name, comparator: .localizedStandard)]) private var tags: [Tag]
    @Query private var references: [Reference]

    /// iPad, regular width: one wide column under a sidebar tab.
    private var isWide: Bool { sizeClass == .regular }

    /// iPhone, and the Recipes tab in a compact window: the title is the Recipes · Cookbooks switch.
    private var usesTitleSwitch: Bool { !isWide && scope == .all }

    /// The scope on screen: the tab's own, or the title switch's.
    private var shownScope: LibraryScope {
        guard usesTitleSwitch else { return scope }
        return libraryView == .books ? .shelf : .all
    }

    /// Which view the Add and More menus follow.
    private var activeView: LibraryView { shownScope == .shelf ? .books : .recipes }

    /// The collection on screen: the tab's on iPad, the Filter menu's on iPhone.
    private var currentCollection: RecipeCollection? {
        let id: PersistentIdentifier?
        if case let .collection(scopeID) = scope {
            id = scopeID
        } else {
            id = filter.collection
        }
        return id.flatMap { id in collections.first { $0.persistentModelID == id } }
    }

    private var reviewCount: Int { allRecipes.count(where: \.needsReview) }

    /// The recipes on screen: the scope and the filter.
    private var visibleRecipes: [Recipe] {
        allRecipes.filter { shownScope.contains($0) && filter.matches($0) }
    }

    /// The selected recipes still on screen, which the selection bar acts on.
    private var selectedRecipes: [Recipe] {
        visibleRecipes.filter { selectedIDs.contains($0.persistentModelID) }
    }

    private var selectionTitle: String {
        let count = selectedRecipes.count
        return count == 0 ? "Select Recipes" : "\(count) Selected"
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if shownScope == .shelf, !books.isEmpty {
                    BookShelf(books: bookSort.sorted(books), isWide: isWide) {
                        libraryHeader(showsSwitch: usesTitleSwitch)
                    }
                } else if shownScope == .shelf || allRecipes.isEmpty {
                    if usesTitleSwitch {
                        // The switch stays at the top, above the empty shelf or library.
                        ScrollView {
                            VStack(spacing: 32) {
                                libraryHeader(showsSwitch: true)
                                emptyLibrary(scope: shownScope)
                            }
                        }
                    } else {
                        emptyLibrary(scope: shownScope)
                    }
                } else {
                    LibraryRecipes(sort: sort, layout: layout, grouping: grouping, scope: shownScope, filter: $filter, collections: collections, isWide: isWide, multiSelection: isSelecting ? $selectedIDs : nil) {
                        libraryHeader(showsSwitch: usesTitleSwitch && !isSelecting)
                    }
                }
            }
            // iPhone: the title is the switch in the content (04 §5.1 Title switch), so the bar shows
            // no title and nothing collapses into it on scroll, but the title stays set for the Back
            // button. iPad: the bar's large title, the sidebar tab's name. Select mode titles the bar
            // with the count, and on iPhone trades the tab bar for its own.
            .navigationTitle(isSelecting ? selectionTitle : pageTitle)
            .navigationBarTitleDisplayMode(usesTitleSwitch ? .inline : .automatic)
            .toolbar(removing: usesTitleSwitch && !isSelecting ? .title : nil)
            .toolbarVisibility(isSelecting && !isWide ? .hidden : .automatic, for: .tabBar)
            .navigationDestination(for: LibraryRoute.self) { destination($0) }
            .toolbar { libraryToolbar }
        }
        .sheet(isPresented: $isAddingRecipe) {
            RecipeEditorView(recipe: nil)
        }
        .sheet(isPresented: $isImportingFromWeb, onDismiss: openImportedRecipe) {
            WebImportView { recipe in importedRecipe = recipe } onSavedReference: { reference in
                // An article lands in Pantry → References, which shows it.
                router.openReference(id: reference.id)
            }
        }
        .sheet(isPresented: $isImportingLibrary) {
            LibraryImportView()
        }
        .sheet(isPresented: $isScanningCookbook, onDismiss: openAddedBook) {
            ScanCookbookView { book in addedBook = book }
                // iPad: the recipe list and its corrections want the room.
                .presentationSizing(.page)
        }
        .sheet(isPresented: $isScanningPage, onDismiss: openImportedRecipe) {
            // One recipe saved opens it; several leave the library to show them.
            ScanPageView { recipes in importedRecipe = recipes.count == 1 ? recipes.first : nil }
                // iPad: the page beside the recipe in review wants the room (03 §3.6).
                .presentationSizing(.page)
        }
        .sheet(isPresented: $isShowingSync) {
            NavigationStack {
                SyncStatusView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done", role: .confirm) { isShowingSync = false }
                                .keyboardShortcut(.cancelAction)
                        }
                    }
            }
        }
        .collectionNamePrompt("New Collection", isPresented: $isCreatingCollection, actionTitle: "Create") { name in
            show(CollectionActions.create(named: name, in: modelContext))
        }
        .collectionNamePrompt("New Collection", isPresented: $isCollectingSelection, actionTitle: "Create") { name in
            let collection = CollectionActions.create(named: name, in: modelContext)
            for recipe in selectedRecipes where !recipe.isIn(collection) {
                recipe.toggleMembership(in: collection)
            }
            try? modelContext.save()
        }
        .collectionNamePrompt("Rename Collection", isPresented: $isRenamingCollection, initialName: currentCollection?.name ?? "") { name in
            currentCollection?.name = name
            try? modelContext.save()
        }
        .onChange(of: router.libraryRequest, initial: true) { _, request in
            // File menu requests go to the library page on screen (KitchenCodexCommands).
            guard let request, router.selectedTab == AppTab.page(for: scope) else { return }
            router.libraryRequest = nil
            start(request)
        }
        // The View menu acts on this page while its grid or shelf is on screen.
        .focusedSceneValue(\.libraryPage, isPageOnScreen ? pageCommands : nil)
        .onChange(of: router.requestedRecipeID, initial: true) { _, id in
            // Spotlight and other tabs open recipes in the Recipes tab, the whole library.
            guard scope == .all, let id else { return }
            router.requestedRecipeID = nil
            if let recipe = allRecipes.first(where: { $0.id == id }) { open(recipe) }
        }
        // The other view ends Select mode, and so does leaving the tab, which would otherwise keep
        // the tab bar hidden.
        .onChange(of: libraryView) { endSelection() }
        .onDisappear { endSelection() }
        // A deleted cookbook leaves the Cookbook filter.
        .onChange(of: books.map(\.persistentModelID)) { _, ids in
            if let book = filter.book, !ids.contains(book) { filter.book = nil }
        }
    }

    // MARK: - Menu bar

    /// This page's grid, list or shelf is what the window shows: its tab is selected, nothing is
    /// pushed over it and Select mode is off.
    private var isPageOnScreen: Bool {
        router.selectedTab == AppTab.page(for: scope) && path.isEmpty && !isSelecting
    }

    /// What the View menu changes on this page (03 §4): the Recipes · Cookbooks view (the title
    /// switch on iPhone, the Recipes and All Cookbooks tabs on iPad), Grid or List, and the filter.
    private var pageCommands: LibraryPageCommands {
        LibraryPageCommands(
            view: Binding {
                activeView
            } set: { view in
                guard view != activeView else { return }
                if isWide {
                    router.show(view == .books ? .shelf : .all)
                } else {
                    libraryView = view
                }
            },
            layout: $layout,
            showsRecipes: activeView == .recipes && !allRecipes.isEmpty,
            showFilter: { isShowingFilter = true }
        )
    }

    /// Starts what the File menu asked for, unless one of this page's sheets is already up.
    private func start(_ request: LibraryRequest) {
        guard !isAddingRecipe, !isImportingFromWeb, !isImportingLibrary, !isScanningCookbook, !isScanningPage, !isShowingFilter else { return }
        switch request {
        case .enterManually: isAddingRecipe = true
        case .importFromWeb: isImportingFromWeb = true
        case .scanPage: isScanningPage = true
        case .scanCookbook: isScanningCookbook = true
        case .importLibrary: isImportingLibrary = true
        }
    }

    /// The page's title: on iPhone the switch's view, which Back reads; on iPad the sidebar tab's name.
    private var pageTitle: String {
        if usesTitleSwitch { return libraryView.rawValue }
        return scope.title(books: books, collections: collections)
    }

    // MARK: - Shared

    @ViewBuilder
    private func destination(_ route: LibraryRoute) -> some View {
        switch route {
        case let .recipe(id):
            if let recipe = allRecipes.first(where: { $0.persistentModelID == id }) {
                RecipeDetailView(recipe: recipe)
                    // Each recipe opens on its own servings and units.
                    .id(id)
            }
        case .needsReview:
            NeedsALookView()
        case .collections:
            // Rename, reorder and delete, on iPad too: the system sidebar is not reordered by hand.
            CollectionsList { collection in
                path.removeLast()
                if isWide {
                    router.show(.collection(collection.persistentModelID))
                } else {
                    filter.collection = collection.persistentModelID
                }
            } onDelete: { collection in
                if filter.collection == collection.persistentModelID { filter.collection = nil }
            }
        case let .book(id):
            if let book = books.first(where: { $0.persistentModelID == id }) {
                BookDetailView(book: book)
                    .id(id)
            }
        case let .reference(id):
            if let reference = references.first(where: { $0.persistentModelID == id }) {
                ReferencePageView(reference: reference) { recipe in path.append(.recipe(recipe.persistentModelID)) }
                    .id(id)
            }
        }
    }

    /// The first items of the scrolling content: the view switch (iPhone), the sync flag while a sync
    /// issue stands, the review prompt while imports wait for a check, and one token per active filter.
    @ViewBuilder
    private func libraryHeader(showsSwitch: Bool) -> some View {
        let showsSyncFlag = shownScope == .all && sync.hasIssue && !isSelecting
        let showsPrompt = activeView == .recipes && reviewCount > 0 && scope != .needsReview && !isSelecting
        let showsTokens = activeView == .recipes && filter.isActive
        if showsSwitch || showsSyncFlag || showsPrompt || showsTokens {
            VStack(alignment: .leading, spacing: 12) {
                if showsSwitch {
                    LibraryTitleSwitch(selection: $libraryView)
                        .padding(.horizontal)
                }
                if showsSyncFlag {
                    // The app no longer keeps a library that doesn't sync quietly (ux-notes row 56).
                    SyncIssueRow(state: sync.state) { isShowingSync = true }
                        .padding(.horizontal)
                }
                if showsPrompt {
                    NeedsALookRow(count: reviewCount) {
                        if isWide {
                            router.show(.needsReview)
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
                Label("No cookbooks yet", systemImage: "books.vertical")
            } description: {
                Text("Cookbooks you add will be listed here with their recipes.")
            } actions: {
                Button("Scan Cookbook") { isScanningCookbook = true }
            }
        } else {
            ContentUnavailableView {
                Label("No recipes yet", systemImage: "book.closed")
            } description: {
                Text("Scan a cookbook page, import one from the web or from Paprika or Mela, share one from Safari, or enter one manually.")
            }
        }
    }

    // MARK: - Filter

    /// Courses the library uses, in the standard order.
    private var filterCourses: [String] {
        let used = Set(allRecipes.compactMap(\.course))
        return RecipeCourse.options(including: allRecipes).filter(used.contains)
    }

    /// One token per active kind, reading the kind and its selection ("Course: Main, Side"), each
    /// removing only its kind (04 §5.1 Recipes filters).
    private var filterTokens: [FilterTokens.Token] {
        let options = filterOptions
        return RecipeFilterKind.allCases.compactMap { kind in
            filter.token(for: kind, options: options).map { title in
                FilterTokens.Token(id: kind.rawValue, title: title) { filter.clear(kind) }
            }
        }
    }

    /// Filter (04 §5.1 Recipes filters, ux-notes row 41): the funnel, tinted while a filter is
    /// active, opening the Filter list, a popover on iPad that adapts to a sheet on iPhone.
    private var filterButton: some View {
        Button {
            isShowingFilter = true
        } label: {
            Label("Filter", systemImage: filter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .tint(filter.isActive ? .accentColor : nil)
        .accessibilityValue(filter.isActive ? "\(filterTokens.count) active" : "None")
        .popover(isPresented: $isShowingFilter) {
            RecipeFilterList(filter: $filter, options: filterOptions)
                .frame(minWidth: isWide ? 340 : nil, idealWidth: isWide ? 360 : nil, minHeight: isWide ? 420 : nil, idealHeight: isWide ? 480 : nil)
                .presentationDetents([.medium, .large])
        }
    }

    /// What the Filter list offers. Collections are sidebar tabs on iPad, so the kind is iPhone only.
    private var filterOptions: RecipeFilterOptions {
        RecipeFilterOptions(
            courses: filterCourses,
            collections: isWide ? [] : collections.map { ($0.persistentModelID, $0.name) },
            books: books.map { ($0.persistentModelID, $0.displayTitle) },
            tags: tags.map { ($0.persistentModelID, $0.name) }
        )
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var libraryToolbar: some ToolbarContent {
        if isSelecting {
            ToolbarItem(placement: .topBarLeading) {
                let visible = visibleRecipes
                let allSelected = !visible.isEmpty && visible.allSatisfy { selectedIDs.contains($0.persistentModelID) }
                Button(allSelected ? "Deselect All" : "Select All") {
                    selectedIDs = allSelected ? [] : Set(visible.map(\.persistentModelID))
                }
                .disabled(visible.isEmpty)
            }
            RecipeSelectionToolbar(
                recipes: selectedRecipes,
                onNewCollection: { isCollectingSelection = true },
                onDelete: delete,
                onDone: endSelection
            )
        } else if activeView == .recipes {
            ToolbarItem(placement: .primaryAction) {
                addMenu
            }
            ToolbarItem(placement: .primaryAction) {
                filterButton
            }
            // Primary placement, not .secondaryAction: the latter nests this menu inside the
            // system overflow menu, so More would open a menu holding only "More".
            ToolbarItem(placement: .primaryAction) {
                Menu {
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

                    if !allRecipes.isEmpty {
                        Button("Select", systemImage: "checkmark.circle") {
                            selectedIDs = []
                            isSelecting = true
                        }
                    }
                    Divider()
                    Button("New Collection…", systemImage: "rectangle.stack.badge.plus") {
                        isCreatingCollection = true
                    }
                    // Rename, reorder and delete in a list.
                    if !collections.isEmpty {
                        Button("Collections", systemImage: "rectangle.stack") {
                            path.append(.collections)
                        }
                    }
                    if let collection = currentCollection {
                        Button("Rename “\(collection.name)”…", systemImage: "pencil") {
                            isRenamingCollection = true
                        }
                        Button("Delete “\(collection.name)”…", systemImage: "trash", role: .destructive) {
                            isConfirmingCollectionDeletion = true
                        }
                    }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
                // On the menu, so on iPad the confirmation points at More.
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
            }
        } else {
            // The Cookbooks view (03 §3.7): the same Add menu. More appears once the shelf has
            // something to sort.
            ToolbarItem(placement: .primaryAction) {
                addMenu
            }
            if !books.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker(selection: $bookSort) {
                            ForEach(BookSort.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        } label: {
                            Label("Sort By", systemImage: "arrow.up.arrow.down")
                        }
                        .pickerStyle(.menu)
                    } label: {
                        Label("More", systemImage: "ellipsis")
                    }
                }
            }
        }
    }

    /// Add (+), identical on Recipes and Cookbooks (04 §5.1 Add menu, ux-notes rows 51 and 90): the
    /// ways in, never the outcome; methods that haven't shipped are hidden. Add Cookbook is Scan
    /// Cookbook's first step (04 §5.1 "Add Cookbook").
    private var addMenu: some View {
        Menu {
            // ⌘N is File → New Recipe, from any tab (KitchenCodexCommands).
            Button("Enter Manually", systemImage: "square.and.pencil") {
                isAddingRecipe = true
            }
            Button("Import from Web", systemImage: "link") {
                isImportingFromWeb = true
            }
            Button("Scan Page", systemImage: "doc.viewfinder") {
                isScanningPage = true
            }
            Button("Scan Cookbook", systemImage: "books.vertical") {
                isScanningCookbook = true
            }
            Divider()
            Button("Import from Paprika or Mela…", systemImage: "tray.and.arrow.down") {
                isImportingLibrary = true
            }
        } label: {
            Label("Add", systemImage: "plus")
        }
    }

    /// Shows `recipe` pushed over the grid: here when this page's scope holds it, otherwise in the
    /// Recipes tab, which holds every recipe (a web import from Favorites).
    private func open(_ recipe: Recipe) {
        guard scope == .all || scope.contains(recipe) else {
            router.openRecipe(id: recipe.id)
            return
        }
        libraryView = .recipes
        path = [.recipe(recipe.persistentModelID)]
    }

    /// A new collection: its sidebar tab on iPad, the Collection filter on iPhone.
    private func show(_ collection: RecipeCollection) {
        if isWide {
            router.show(.collection(collection.persistentModelID))
        } else {
            libraryView = .recipes
            filter.collection = collection.persistentModelID
        }
    }

    private func deleteCollection(_ collection: RecipeCollection) {
        if filter.collection == collection.persistentModelID { filter.collection = nil }
        router.delete(collection, in: modelContext)
    }

    /// The book Scan Cookbook added or found on the shelf, pushed over the shelf.
    private func openAddedBook() {
        guard let book = addedBook else { return }
        addedBook = nil
        libraryView = .books
        path = [.book(book.persistentModelID)]
    }

    private func openImportedRecipe() {
        guard let recipe = importedRecipe else { return }
        importedRecipe = nil
        open(recipe)
    }

    /// Delete from Select mode: the selection and any pushed copy first, so nothing renders a
    /// deleted model, then the recipes on the next turn of the run loop.
    private func delete(_ recipes: [Recipe]) {
        let ids = Set(recipes.map(\.persistentModelID))
        path.removeAll { if case let .recipe(id) = $0 { ids.contains(id) } else { false } }
        selectedIDs.subtract(ids)
        Task {
            await Task.yield()
            withAnimation {
                for recipe in recipes { modelContext.delete(recipe) }
            }
            try? modelContext.save()
        }
    }

    /// Leaves Select mode; the selection goes with it.
    private func endSelection() {
        isSelecting = false
        selectedIDs = []
    }
}

/// The filtered, sorted, grouped recipes as a grid or a list, under `header`. A tap pushes the
/// recipe. On iPad (`isWide`) a recipe can also be dragged onto a collection's sidebar tab, and the
/// cards are wider so the page's one column holds about four across. With a
/// `multiSelection` (Select mode) every recipe shows a selection circle and a tap toggles it; the
/// list's own selection extends with ⌘-click and shift-click on iPad.
private struct LibraryRecipes<Header: View>: View {
    @Query private var recipes: [Recipe]
    let layout: RecipeLayout
    let grouping: RecipeGrouping
    let scope: LibraryScope
    @Binding var filter: RecipeFilter
    let collections: [RecipeCollection]
    let isWide: Bool
    let multiSelection: Binding<Set<PersistentIdentifier>>?
    @ViewBuilder let header: Header

    @Environment(\.modelContext) private var modelContext
    @State private var pendingDeletion: Recipe?
    /// Long-press → Add to Collection → New Collection…: the recipe to put in it once named.
    @State private var collectingRecipe: Recipe?

    init(sort: RecipeSort, layout: RecipeLayout, grouping: RecipeGrouping, scope: LibraryScope, filter: Binding<RecipeFilter>, collections: [RecipeCollection], isWide: Bool, multiSelection: Binding<Set<PersistentIdentifier>>? = nil, @ViewBuilder header: () -> Header) {
        _recipes = Query(sort: sort.descriptors, animation: .default)
        self.layout = layout
        self.grouping = grouping
        self.scope = scope
        _filter = filter
        self.collections = collections
        self.isWide = isWide
        self.multiSelection = multiSelection
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
                Text(isWide
                    ? "Drag recipes onto the collection in the sidebar, or use Add to Collection in their long-press menu."
                    : "Add a recipe from its long-press menu: Add to Collection.")
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
        case .book: "No recipes from this cookbook are in the library yet."
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
                    // 160 pt gives two cards across an iPhone; 200 gives about four across iPad's
                    // page beside the sidebar.
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: isWide ? 200 : 160), spacing: 12)], spacing: 12) {
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
            if let multiSelection {
                let id = recipe.persistentModelID
                let isSelected = multiSelection.wrappedValue.contains(id)
                Button {
                    if isSelected { multiSelection.wrappedValue.remove(id) } else { multiSelection.wrappedValue.insert(id) }
                } label: {
                    RecipeCard(recipe: recipe)
                        .overlay {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 22)
                                    .strokeBorder(.tint, lineWidth: 3)
                            }
                        }
                        .overlay(alignment: .topLeading) {
                            SelectionCircle(isSelected: isSelected)
                                .padding(14)
                        }
                }
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            } else {
                NavigationLink(value: LibraryRoute.recipe(recipe.persistentModelID)) {
                    RecipeCard(recipe: recipe)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu { actions(for: recipe) }
        .modifier(RecipeDragSource(recipe: recipe, isEnabled: isWide))
    }

    @ViewBuilder
    private func list(_ sections: [RecipeGrouping.Section], isEmpty: Bool) -> some View {
        if let multiSelection {
            // The list's own circles, in edit mode; rows select rather than push.
            List(selection: multiSelection) {
                listContent(sections, isEmpty: isEmpty) { recipe in
                    RecipeRow(recipe: recipe)
                        .tag(recipe.persistentModelID)
                }
            }
            .listStyle(.plain)
            .environment(\.editMode, .constant(.active))
        } else {
            List {
                listContent(sections, isEmpty: isEmpty) { recipe in
                    NavigationLink(value: LibraryRoute.recipe(recipe.persistentModelID)) {
                        RecipeRow(recipe: recipe)
                    }
                    .modifier(RecipeRowDragSource(recipe: recipe, isEnabled: isWide))
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
        withAnimation {
            modelContext.delete(recipe)
        }
        try? modelContext.save()
        pendingDeletion = nil
    }
}

/// iPad: a card can be dragged onto a collection's tab in the sidebar.
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

/// iPad: a list row can be dragged onto a collection's tab in the sidebar too.
private struct RecipeRowDragSource: ViewModifier {
    let recipe: Recipe
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.draggable(RecipeDragItem(id: recipe.id)) {
                RecipeRow(recipe: recipe).frame(width: 320)
            }
        } else {
            content
        }
    }
}

/// The active filters as removable tokens, one per kind, and Clear, scrolling with the content
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

/// The large title as the view switch (04 §5.1 Title switch): "Recipes" and "Cookbooks" side by side in
/// large-title type a fixed gap apart, the shown view in the primary color and the other in
/// secondary. Each word is a button with the selected trait; VoiceOver reads the pair as a segmented
/// control. At accessibility sizes the words stack, and so they do at any size where the pair is
/// wider than the screen (the larger standard sizes on a narrow iPhone).
private struct LibraryTitleSwitch: View {
    @Binding var selection: RecipesView.LibraryView

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                words(in: VStackLayout(alignment: .leading, spacing: 4))
            } else {
                ViewThatFits(in: .horizontal) {
                    words(in: HStackLayout(alignment: .firstTextBaseline, spacing: 20))
                    words(in: VStackLayout(alignment: .leading, spacing: 4))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityRepresentation {
            Picker("Library", selection: $selection) {
                ForEach(RecipesView.LibraryView.allCases) { view in
                    Text(view.rawValue).tag(view)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func words(in layout: some Layout) -> some View {
        layout {
            ForEach(RecipesView.LibraryView.allCases) { view in
                let isSelected = selection == view
                Button {
                    selection = view
                } label: {
                    Text(view.rawValue)
                        .font(.largeTitle.bold())
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

#Preview {
    RecipesView(scope: .all)
        .environment(AppRouter())
        .environment(SyncMonitor(store: .inMemory(reason: "Preview")))
        .modelContainer(try! RecipeStore.makeContainer(inMemory: true))
}
