import CoreSpotlight
import RecipeModel
import SwiftData
import SwiftUI

/// What the root tab view has selected: one of the five top-level destinations (02 §1.1), in the
/// order the work happens (collect recipes, stock the kitchen, plan the dinner, cook it, and the
/// system Search tab), or on iPad one of the system sidebar's section tabs below them (04 §5.1
/// iPad tabs): a Recipes section tab, a Pantry pane, or Profile from the sidebar's bottom bar.
enum AppTab: Hashable {
    case recipes
    /// iPad: All Cookbooks, a smart collection or a collection, each the Recipes page in that scope.
    case library(LibraryScope)
    case pantry
    /// iPad: a Pantry pane, also reached from the hub's rows.
    case pantryPane(PantryView.Pane)
    case plan
    case cook
    case search
    /// iPad: Profile, from the account glyph in the sidebar's bottom bar.
    case profile

    /// The tab that shows this page: a section tab's own, Recipes for the library on iPhone.
    static func page(for scope: LibraryScope) -> AppTab {
        scope == .all ? .recipes : .library(scope)
    }

    /// The Recipes tab or one of its sidebar sections: a page of the library.
    var isLibraryPage: Bool { topLevel == .recipes }

    /// The top-level tab this one sits under, which Search takes its scope from and a compact
    /// window falls back to.
    var topLevel: AppTab {
        switch self {
        case .library: .recipes
        case .pantryPane, .profile: .pantry
        default: self
        }
    }
}

struct RootTabView: View {
    @State private var router = AppRouter()
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.modelContext) private var modelContext

    @Query private var recipes: [Recipe]
    @Query(sort: CollectionActions.sortDescriptors) private var collections: [RecipeCollection]
    @State private var renamingCollection: RecipeCollection?
    @State private var deletingCollection: RecipeCollection?

    private var reviewCount: Int { recipes.count(where: \.needsReview) }

    /// iPad, regular width: the system sidebar with its sections.
    private var isWide: Bool { sizeClass == .regular }

    /// The tab view's selection. In compact width a section tab stands for its top-level tab, so
    /// the tab view never selects a tab it no longer has while the width changes.
    private var selection: Binding<AppTab> {
        Binding { isWide ? router.selectedTab : router.selectedTab.topLevel } set: { router.selectedTab = $0 }
    }

    var body: some View {
        TabView(selection: selection) {
            // The five tabs: the iPhone's tab bar, and the top of the iPad sidebar.
            Tab("Recipes", systemImage: "book.closed", value: AppTab.recipes) {
                RecipesView(scope: .all)
            }
            Tab("Pantry", systemImage: "cabinet", value: AppTab.pantry) {
                PantryView()
            }
            Tab("Plan", systemImage: "calendar", value: AppTab.plan) {
                PlanView()
            }
            Tab("Cook", systemImage: "frying.pan", value: AppTab.cook) {
                CookView()
            }
            Tab(value: AppTab.search, role: .search) {
                SearchView()
            }

            // Each tab's own navigation, as sidebar sections under the tabs (04 §5.1 iPad tabs).
            // Regular width only: on iPhone and in a compact window even sidebar-only tabs would
            // fill a More tab and push Search out of its bubble, so the tab bar keeps the five tabs,
            // the title switch and the Pantry hub. Sidebar-only keeps them out of the floating tab
            // bar the iPad sidebar collapses into.
            if isWide {
                TabSection("Bookshelf") {
                    libraryTab(.shelf, title: "All Cookbooks", systemImage: "books.vertical")
                }
                .tabPlacement(.sidebarOnly)

                TabSection("Smart Collections") {
                    libraryTab(.favorites, title: "Favorites", systemImage: "heart")
                    libraryTab(.neverCooked, title: "Never Cooked", systemImage: "sparkles")
                    if reviewCount > 0 || router.selectedTab == .library(.needsReview) {
                        libraryTab(.needsReview, title: "Needs a Look", systemImage: "exclamationmark.bubble")
                            .badge(reviewCount)
                    }
                }
                .tabPlacement(.sidebarOnly)

                TabSection("Collections") {
                    ForEach(collections) { collection in
                        libraryTab(.collection(collection.persistentModelID), title: collection.name, systemImage: "rectangle.stack")
                            // A recipe dragged from the grid or the list joins the collection (03 §4).
                            .dropDestination(for: RecipeDragItem.self) { items in
                                _ = CollectionActions.add(items.map(\.id), to: collection, in: modelContext)
                            }
                            .contextMenu {
                                Button("Rename…", systemImage: "pencil") { renamingCollection = collection }
                                Button("Delete", systemImage: "trash", role: .destructive) { deletingCollection = collection }
                            }
                    }
                }
                .sectionActions {
                    Button("New Collection", systemImage: "plus") { router.isCreatingCollection = true }
                }
                .tabPlacement(.sidebarOnly)

                TabSection("Pantry") {
                    ForEach(PantryView.Pane.allCases) { pane in
                        Tab(pane.rawValue, systemImage: pane.symbol, value: AppTab.pantryPane(pane)) {
                            NavigationStack {
                                PantryPaneView(pane: pane)
                            }
                        }
                    }
                }
                .tabPlacement(.sidebarOnly)

                // Reached from the sidebar's bottom bar, never listed (04 §5.1 Pantry hub). Not
                // `.hidden()`: a hidden tab leaves the tab model, and selecting it throws.
                Tab("Profile", systemImage: "person.crop.circle", value: AppTab.profile) {
                    NavigationStack {
                        ProfilePane()
                            .navigationTitle("Profile")
                    }
                }
                .defaultVisibility(.hidden, for: .sidebar, .tabBar)
            }
        }
        // iPhone: the bottom tab bar. iPad: the tabs at the top of the system sidebar with each
        // tab's sections below them, the only left column; the cook may collapse it into the
        // floating tab bar (04 §5.1 iPad tabs).
        .tabViewStyle(.sidebarAdaptable)
        .defaultTabBarPlacement(.sidebar)
        // iOS 27 sets the search tab apart as its own bubble only when selecting it starts the
        // search; without this it is a fifth inline tab.
        .tabViewSearchActivation(.searchTabSelection)
        // Profile at the sidebar's foot, where Notes and Reminders put the sidebar's own control;
        // filled while it shows, since no sidebar row is selected then.
        .tabViewSidebarBottomBar {
            let isShown = router.selectedTab == .profile
            HStack {
                Button("Profile", systemImage: isShown ? "person.crop.circle.fill" : "person.crop.circle") {
                    router.selectedTab = .profile
                }
                .labelStyle(.iconOnly)
                .font(.title3)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .accessibilityAddTraits(isShown ? .isSelected : [])
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .onChange(of: router.selectedTab) { previous, selected in
            // Search opens on the scope of the tab the cook came from. Chosen in the iPad sidebar,
            // where the system shows it without starting the search, it focuses the field as ⌘F
            // does (ux-notes row 45); the iPhone's bubble starts the search itself.
            if selected == .search, previous != .search {
                router.searchScope = SearchScope(origin: previous)
                if isWide { router.isSearchFieldRequested = true }
            }
            router.selectionDidChange()
        }
        .onChange(of: sizeClass, initial: true) { _, sizeClass in
            // A compact window has the iPhone's tab bar, which lists no section tab.
            if sizeClass == .compact { router.selectedTab = router.selectedTab.topLevel }
        }
        .collectionNamePrompt("New Collection", isPresented: $router.isCreatingCollection, actionTitle: "Create") { name in
            let collection = CollectionActions.create(named: name, in: modelContext)
            router.show(.collection(collection.persistentModelID))
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
                router.delete(collection, in: modelContext)
            }
        } message: { _ in
            Text("The recipes stay in your library.")
        }
        .environment(router)
        // The menu bar and keyboard shortcuts act on this window (KitchenCodexCommands).
        .focusedSceneValue(router)
        // A recipe, or one of its ingredients, tapped in Spotlight (RecipeSpotlightIndexer) opens in
        // Recipes; a reference in Pantry → References.
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return }
            if let id = RecipeSpotlightIndexer.referenceID(fromItemIdentifier: identifier) {
                router.openReference(id: id)
            } else if let id = RecipeSpotlightIndexer.recipeID(fromItemIdentifier: identifier) {
                router.openRecipe(id: id)
            }
        }
        // Open in app (ux-notes row 44): kitchencodex://recipe/<uuid> opens the recipe in Recipes,
        // kitchencodex://reference/<uuid> the reference. The router lives here, not in the App.
        .onOpenURL { url in
            guard url.scheme?.lowercased() == "kitchencodex", let id = UUID(uuidString: url.lastPathComponent) else { return }
            switch url.host()?.lowercased() {
            case "recipe": router.openRecipe(id: id)
            case "reference": router.openReference(id: id)
            default: break
            }
        }
    }

    /// A Recipes section tab: the Recipes page in `scope`.
    private func libraryTab(_ scope: LibraryScope, title: String, systemImage: String) -> some TabContent<AppTab> {
        Tab(title, systemImage: systemImage, value: AppTab.library(scope)) {
            RecipesView(scope: scope)
        }
    }
}

#Preview("Root") {
    RootTabView()
        .environment(SyncMonitor(store: .inMemory(reason: "Preview")))
        .modelContainer(try! RecipeStore.makeContainer(inMemory: true))
}
