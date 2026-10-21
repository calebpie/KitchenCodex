import RecipeModel
import SwiftData
import SwiftUI

/// What a search covers (04 §5.1 Search tab): everything, or one tab's content. It defaults to the
/// tab the cook came from, so searching from Recipes reads as filtering the recipes.
enum SearchScope: String, CaseIterable, Identifiable {
    case all, recipes, pantry, plan

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All"
        case .recipes: "Recipes"
        case .pantry: "Pantry"
        case .plan: "Plan"
        }
    }

    /// The scope for a search started from `tab`: a Recipes section tab counts as Recipes, a Pantry
    /// pane or Profile as Pantry. Cook searches recipes.
    init(origin tab: AppTab) {
        switch tab.topLevel {
        case .recipes, .cook: self = .recipes
        case .pantry: self = .pantry
        case .plan: self = .plan
        default: self = .all
        }
    }

    var prompt: String {
        switch self {
        case .all: "Recipes, cookbooks, events…"
        case .recipes: "Recipes and ingredients"
        case .pantry: "Staples, tools, bottles, sources"
        case .plan: "Events"
        }
    }
}

/// What the search stack pushes: a recipe, or a set of recipes (Never Cooked, a collection, a book).
enum SearchRoute: Hashable {
    case recipe(Recipe)
    case recipes(LibraryScope)
}

/// The one place to find anything (03 §3.18): the system search tab, a scope under the field,
/// suggestions from the scope before typing, and results in the scope's own cells. Phase 6 adds
/// natural language.
struct SearchView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var query = ""
    /// The search field's focus, which ⌘F sets; the system presents the search around it.
    @FocusState private var isSearchFieldFocused: Bool
    @State private var path: [SearchRoute] = []
    /// Recent searches, newest first, one per line.
    @AppStorage("search.recent") private var recentText = ""
    @AppStorage("recipes.layout") private var layout: RecipeLayout = .grid

    @Query(sort: [SortDescriptor(\Recipe.title, comparator: .localizedStandard)]) private var recipes: [Recipe]
    @Query(sort: CollectionActions.sortDescriptors) private var collections: [RecipeCollection]
    @Query(sort: [SortDescriptor(\Book.title, comparator: .localizedStandard)]) private var books: [Book]
    @Query(sort: [SortDescriptor(\Source.name, comparator: .localizedStandard)]) private var sources: [Source]
    @Query(sort: [SortDescriptor(\BeverageItem.name, comparator: .localizedStandard)]) private var bottles: [BeverageItem]
    @Query(sort: [SortDescriptor(\PantryItem.item, comparator: .localizedStandard)]) private var staples: [PantryItem]
    @Query(sort: [SortDescriptor(\Tool.name, comparator: .localizedStandard)]) private var tools: [Tool]
    @Query(sort: [SortDescriptor(\Event.date)]) private var events: [Event]

    private var recents: [String] {
        recentText.split(separator: "\n").map(String.init)
    }

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $path) {
            Group {
                if query.trimmed.isEmpty {
                    suggestions
                } else {
                    results
                }
            }
            // The header is drawn by the app as the first scrolling item, as the Recipes title is, so
            // it keeps the lists' leading inset in both widths, the iPad's tabs along the top
            // included (ux-notes row 53); the bar keeps the title for Back.
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(removing: .title)
            .navigationDestination(for: SearchRoute.self) { route in
                switch route {
                case let .recipe(recipe):
                    RecipeDetailView(recipe: recipe)
                case let .recipes(scope):
                    RecipeResults(recipes: recipes.filter(scope.contains), layout: layout)
                        .navigationTitle(scope.title(books: books, collections: collections))
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
            .searchable(text: $query, prompt: router.searchScope.prompt)
            .searchFocused($isSearchFieldFocused)
            .searchScopes($router.searchScope, activation: .onSearchPresentation) {
                ForEach(SearchScope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .onSubmit(of: .search) { remember(query) }
            // ⌘F (KitchenCodexCommands) and choosing Search in the iPad sidebar (RootTabView): on
            // iPhone selecting the tab starts the search, scopes and all; in the iPad sidebar it
            // shows Search without starting it, so there both focus the field, ready to type. Not
            // an `isPresented` binding, which kept the scope bar from appearing when the iPhone's
            // bubble was tapped.
            .onChange(of: router.isSearchFieldRequested, initial: true) { _, isRequested in
                guard isRequested else { return }
                router.isSearchFieldRequested = false
                if sizeClass == .regular { isSearchFieldFocused = true }
            }
            .onChange(of: path) { old, new in
                // Opening a result keeps the search that found it.
                if new.count > old.count { remember(query) }
            }
        }
    }

    // MARK: - Before typing

    @ViewBuilder
    private var suggestions: some View {
        switch router.searchScope {
        case .all:
            if recents.isEmpty {
                Scrolling {
                    ContentUnavailableView {
                        Label("Search Kitchen Codex", systemImage: "magnifyingglass")
                    } description: {
                        Text("Recipes, cookbooks, events, ingredients and what is in your pantry.")
                    }
                }
            } else {
                List {
                    SearchHeader()
                    recentSection
                }
            }
        case .recipes:
            if recipes.isEmpty {
                Scrolling {
                    ContentUnavailableView {
                        Label("No recipes yet", systemImage: "book.closed")
                    } description: {
                        Text("Recipes you add in Recipes can be searched here by title or ingredient.")
                    }
                }
            } else {
                List {
                    SearchHeader()
                    recentSection
                    Section("Suggestions") {
                        suggestionRow("Never Cooked", systemImage: "sparkles", count: recipes.count(where: \.isNeverCooked), route: .recipes(.neverCooked))
                        suggestionRow("Favorites", systemImage: "heart", count: recipes.count(where: \.isFavorite), route: .recipes(.favorites))
                    }
                    if !collections.isEmpty {
                        Section("Collections") {
                            ForEach(collections) { collection in
                                suggestionRow(collection.name, systemImage: "rectangle.stack", count: collection.recipes?.count ?? 0, route: .recipes(.collection(collection.persistentModelID)))
                            }
                        }
                    }
                    if !books.isEmpty {
                        Section("Cookbooks") {
                            ForEach(books) { book in
                                suggestionRow(book.title.isEmpty ? "Untitled Cookbook" : book.title, systemImage: "book", count: book.recipes?.count ?? 0, route: .recipes(.book(book.persistentModelID)))
                            }
                        }
                    }
                }
            }
        case .pantry:
            if sources.isEmpty, bottles.isEmpty {
                Scrolling {
                    ContentUnavailableView {
                        Label("Nothing in Pantry yet", systemImage: "cabinet")
                    } description: {
                        Text("Sources and bottles you add in Pantry can be searched here.")
                    }
                }
            } else {
                List {
                    SearchHeader()
                    recentSection
                    if !sources.isEmpty {
                        Section("Sources") {
                            ForEach(sources) { source in
                                Label(source.name, systemImage: "storefront")
                            }
                        }
                    }
                    if !bottles.isEmpty {
                        Section("Cellar & Bar") {
                            ForEach(bottles) { bottle in
                                Label(bottle.name, systemImage: "wineglass")
                            }
                        }
                    }
                }
            }
        case .plan:
            let upcoming = events.filter { $0.date >= Calendar.current.startOfDay(for: .now) }
            if upcoming.isEmpty {
                Scrolling {
                    ContentUnavailableView {
                        Label("No events yet", systemImage: "calendar")
                    } description: {
                        Text("Events you plan can be searched here by name.")
                    }
                }
            } else {
                List {
                    SearchHeader()
                    recentSection
                    Section("Upcoming") {
                        ForEach(upcoming) { event in
                            EventRow(event: event)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        if !recents.isEmpty {
            Section {
                ForEach(recents, id: \.self) { recent in
                    Button {
                        query = recent
                    } label: {
                        Label(recent, systemImage: "clock.arrow.circlepath")
                            .foregroundStyle(.primary)
                    }
                }
            } header: {
                HStack {
                    Text("Recent")
                    Spacer()
                    Button("Clear") { recentText = "" }
                        .font(.subheadline)
                        .textCase(nil)
                }
            }
        }
    }

    private func suggestionRow(_ title: String, systemImage: String, count: Int, route: SearchRoute) -> some View {
        NavigationLink(value: route) {
            Label(title, systemImage: systemImage)
                .badge(count)
        }
    }

    // MARK: - Results

    @ViewBuilder
    private var results: some View {
        let found = LibrarySearch.results(for: query, in: recipes)
        switch router.searchScope {
        case .recipes:
            if found.isEmpty {
                Scrolling { ContentUnavailableView.search(text: query) }
            } else {
                // The Recipes tab's own cells, so searching from Recipes reads as filtering it.
                RecipeResults(recipes: found.map(\.recipe), matchedIngredients: Dictionary(found.compactMap { result in
                    result.matchedIngredient.map { (result.recipe.persistentModelID, $0) }
                }, uniquingKeysWith: { first, _ in first }), layout: layout, showsHeader: true)
            }
        case .pantry:
            let matches = pantryMatches
            if matches.isEmpty {
                Scrolling { ContentUnavailableView.search(text: query) }
            } else {
                List {
                    SearchHeader()
                    pantrySections(matches)
                }
            }
        case .plan:
            let matching = matchingEvents
            if matching.isEmpty {
                Scrolling { ContentUnavailableView.search(text: query) }
            } else {
                List {
                    SearchHeader()
                    ForEach(matching) { EventRow(event: $0) }
                }
            }
        case .all:
            let matchingBooks = books.filter { SearchText.matches(query, in: [$0.title, $0.author]) }
            let matchingEvents = matchingEvents
            let matches = pantryMatches
            if found.isEmpty, matchingBooks.isEmpty, matchingEvents.isEmpty, matches.isEmpty {
                Scrolling { ContentUnavailableView.search(text: query) }
            } else {
                List {
                    SearchHeader()
                    if !found.isEmpty {
                        Section("Recipes") {
                            ForEach(found) { result in
                                NavigationLink(value: SearchRoute.recipe(result.recipe)) {
                                    RecipeRow(recipe: result.recipe, matchedIngredient: result.matchedIngredient)
                                }
                            }
                        }
                    }
                    if !matchingBooks.isEmpty {
                        Section("Cookbooks") {
                            ForEach(matchingBooks) { book in
                                suggestionRow(book.title.isEmpty ? "Untitled Cookbook" : book.title, systemImage: "book", count: book.recipes?.count ?? 0, route: .recipes(.book(book.persistentModelID)))
                            }
                        }
                    }
                    if !matchingEvents.isEmpty {
                        Section("Events") {
                            ForEach(matchingEvents) { EventRow(event: $0) }
                        }
                    }
                    pantrySections(matches)
                }
            }
        }
    }

    private var matchingEvents: [Event] {
        events.filter { SearchText.matches(query, in: [$0.name, $0.notes]) }
    }

    private struct PantryMatches {
        var staples: [PantryItem]
        var tools: [Tool]
        var bottles: [BeverageItem]
        var sources: [Source]
        var isEmpty: Bool { staples.isEmpty && tools.isEmpty && bottles.isEmpty && sources.isEmpty }
    }

    private var pantryMatches: PantryMatches {
        PantryMatches(
            staples: staples.filter { SearchText.matches(query, in: [$0.item]) },
            tools: tools.filter { SearchText.matches(query, in: [$0.name, $0.type]) },
            bottles: bottles.filter { SearchText.matches(query, in: [$0.name, $0.producer, $0.style, $0.region]) },
            sources: sources.filter { SearchText.matches(query, in: [$0.name, $0.carries]) }
        )
    }

    /// Pantry results in the order of the Pantry hub.
    @ViewBuilder
    private func pantrySections(_ matches: PantryMatches) -> some View {
        if !matches.staples.isEmpty {
            Section("Staples") { ForEach(matches.staples) { Label($0.item, systemImage: "basket") } }
        }
        if !matches.tools.isEmpty {
            Section("Tools") { ForEach(matches.tools) { Label($0.name, systemImage: "oven") } }
        }
        if !matches.bottles.isEmpty {
            Section("Cellar & Bar") { ForEach(matches.bottles) { Label($0.name, systemImage: "wineglass") } }
        }
        if !matches.sources.isEmpty {
            Section("Sources") { ForEach(matches.sources) { Label($0.name, systemImage: "storefront") } }
        }
    }

    /// Keeps `text` at the top of the recent searches, eight at most.
    private func remember(_ text: String) {
        let search = text.trimmed
        guard !search.isEmpty else { return }
        let kept = [search] + recents.filter { $0.caseInsensitiveCompare(search) != .orderedSame }
        recentText = kept.prefix(8).joined(separator: "\n")
    }
}

/// An empty state inside a scroll view, so the search scopes stay on screen above it, under the
/// Search header.
private struct Scrolling<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                SearchHeader()
                    .padding(.horizontal)
                content
                    .containerRelativeFrame(.vertical) { height, _ in height * 0.8 }
            }
        }
    }
}

/// "Search" in large-title type, the first item of the page's scrolling content (ux-notes row 53).
/// In a list it is a row without a background, so it starts where the rows' text starts.
private struct SearchHeader: View {
    var body: some View {
        Text("Search")
            .font(.largeTitle.bold())
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
    }
}

/// Recipes in the Recipes tab's cells: cards in the grid layout, rows in the list layout.
private struct RecipeResults: View {
    let recipes: [Recipe]
    var matchedIngredients: [PersistentIdentifier: String] = [:]
    let layout: RecipeLayout
    /// The search page's own results carry the Search header; a pushed set of recipes has its title.
    var showsHeader = false

    var body: some View {
        switch layout {
        case .grid:
            ScrollView {
                if showsHeader {
                    SearchHeader()
                        .padding(.horizontal)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                    ForEach(recipes) { recipe in
                        NavigationLink(value: SearchRoute.recipe(recipe)) {
                            RecipeCard(recipe: recipe)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .overlay {
                if recipes.isEmpty { emptyState }
            }
        case .list:
            List {
                if showsHeader { SearchHeader() }
                ForEach(recipes) { recipe in
                    NavigationLink(value: SearchRoute.recipe(recipe)) {
                        RecipeRow(recipe: recipe, matchedIngredient: matchedIngredients[recipe.persistentModelID])
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if recipes.isEmpty { emptyState }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Nothing here yet", systemImage: "book.closed")
        }
    }
}

/// An event's name and date.
private struct EventRow: View {
    let event: Event

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(event.name.isEmpty ? "Untitled Event" : event.name)
            Text(event.date.formatted(date: .abbreviated, time: .omitted))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

/// Every word of a query must appear in one of the fields.
private enum SearchText {
    static func matches(_ query: String, in fields: [String]) -> Bool {
        let terms = query.split(whereSeparator: \.isWhitespace)
        guard !terms.isEmpty else { return false }
        return terms.allSatisfy { term in fields.contains { $0.localizedStandardContains(term) } }
    }
}

/// Title and ingredient search over the library. Every word must appear in the title or in one of
/// the current version's ingredients; title matches come first.
enum LibrarySearch {
    struct Result: Identifiable {
        let recipe: Recipe
        /// Set when an ingredient, not the title, carried the match.
        let matchedIngredient: String?
        var id: PersistentIdentifier { recipe.persistentModelID }
    }

    static func results(for query: String, in recipes: [Recipe]) -> [Result] {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return [] }

        var titleMatches: [Result] = []
        var ingredientMatches: [Result] = []
        for recipe in recipes {
            let ingredients = recipe.currentVersion?.sortedIngredients ?? []
            var matchedIngredient: String?
            let matchesAll = terms.allSatisfy { term in
                if recipe.title.localizedStandardContains(term) { return true }
                guard let ingredient = ingredients.first(where: {
                    $0.item.localizedStandardContains(term) || $0.rawText.localizedStandardContains(term)
                }) else { return false }
                matchedIngredient = matchedIngredient ?? ingredient.item
                return true
            }
            guard matchesAll else { continue }
            if let matchedIngredient {
                ingredientMatches.append(Result(recipe: recipe, matchedIngredient: matchedIngredient))
            } else {
                titleMatches.append(Result(recipe: recipe, matchedIngredient: nil))
            }
        }
        return titleMatches + ingredientMatches
    }
}

#Preview {
    SearchView()
        .environment(AppRouter())
        .modelContainer(try! RecipeStore.makeContainer(inMemory: true))
}
