import RecipeModel
import SwiftData
import SwiftUI

/// The library, with a view switch between the recipe collection and the cookbook shelf (03 §3.2, §3.7).
/// Phase 1 adds browsing, filters and collections; Phase 2 fills the Books view.
struct RecipesView: View {
    enum LibraryView: String, CaseIterable, Identifiable {
        case recipes = "Recipes"
        case books = "Books"
        var id: Self { self }
    }

    @State private var libraryView: LibraryView = .recipes
    @AppStorage("recipes.layout") private var layout: RecipeLayout = .grid
    @AppStorage("recipes.sort") private var sort: RecipeSort = .title
    @State private var filter = RecipeFilter()
    @State private var isAddingRecipe = false
    @State private var isImportingFromWeb = false
    @State private var isImportingLibrary = false
    @State private var path: [Recipe] = []
    /// Set by the import sheet; opened once the sheet has gone.
    @State private var importedRecipe: Recipe?

    /// Unsorted; used for the empty state and the Course chip's options. The collection runs its own sorted query.
    @Query private var allRecipes: [Recipe]

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch libraryView {
                case .recipes:
                    if allRecipes.isEmpty {
                        ContentUnavailableView {
                            Label("No recipes yet", systemImage: "book.closed")
                        } description: {
                            Text("Share a recipe from Safari, scan a cookbook page, or add one by hand.")
                        }
                    } else {
                        RecipeCollection(sort: sort, layout: layout, filter: $filter)
                    }
                case .books:
                    ContentUnavailableView {
                        Label("Your shelf is empty", systemImage: "books.vertical")
                    } description: {
                        Text("Add a cookbook by scanning its ISBN to start building its recipe list.")
                    }
                }
            }
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
                        FilterChips(filter: $filter, courses: RecipeCourse.options(including: allRecipes))
                    }
                }
                .padding(.bottom, 8)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    // Contextual Add: the items follow the view (02 §1.3).
                    Menu {
                        switch libraryView {
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
                        switch libraryView {
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
            .sheet(isPresented: $isAddingRecipe) {
                RecipeEditorView(recipe: nil)
            }
            .sheet(isPresented: $isImportingFromWeb, onDismiss: openImportedRecipe) {
                WebImportView { recipe in importedRecipe = recipe }
            }
            .sheet(isPresented: $isImportingLibrary) {
                LibraryImportView()
            }
        }
    }
}

/// The filtered, sorted recipes as a grid or a list.
private struct RecipeCollection: View {
    @Query private var recipes: [Recipe]
    let layout: RecipeLayout
    @Binding var filter: RecipeFilter

    @Environment(\.modelContext) private var modelContext
    @State private var pendingDeletion: Recipe?

    init(sort: RecipeSort, layout: RecipeLayout, filter: Binding<RecipeFilter>) {
        _recipes = Query(sort: sort.descriptors, animation: .default)
        self.layout = layout
        _filter = filter
    }

    var body: some View {
        let visible = recipes.filter(filter.matches)
        // The grid or list stays in place even when empty, so the large title keeps tracking a scroll view.
        Group {
            switch layout {
            case .grid: grid(visible)
            case .list: list(visible)
            }
        }
        .overlay {
            if visible.isEmpty {
                ContentUnavailableView {
                    Label("No matching recipes", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("No recipes match these filters.")
                } actions: {
                    Button("Clear Filters") { filter = RecipeFilter() }
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
    }

    private func grid(_ recipes: [Recipe]) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                ForEach(recipes) { recipe in
                    NavigationLink(value: recipe) {
                        RecipeCard(recipe: recipe)
                    }
                    .buttonStyle(.plain)
                    .contextMenu { actions(for: recipe) }
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
    }

    private func list(_ recipes: [Recipe]) -> some View {
        List(recipes) { recipe in
            NavigationLink(value: recipe) {
                RecipeRow(recipe: recipe)
            }
            .contextMenu { actions(for: recipe) }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    recipe.isFavorite.toggle()
                } label: {
                    Label(recipe.isFavorite ? "Unfavorite" : "Favorite", systemImage: recipe.isFavorite ? "heart.slash" : "heart")
                }
                .tint(.accentColor)
            }
        }
        .listStyle(.plain)
    }

    /// Long-press actions (03 §2 Menus): Cook, Favorite, Delete. Add to menu and Share arrive with Plan and export.
    @ViewBuilder
    private func actions(for recipe: Recipe) -> some View {
        Button("Cook", systemImage: "frying.pan") {}
            .disabled(true) // Cook mode is Phase 3.
        Button(recipe.isFavorite ? "Unfavorite" : "Favorite", systemImage: recipe.isFavorite ? "heart.slash" : "heart") {
            recipe.isFavorite.toggle()
        }
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

/// Course and Cooked state chips under the view switch. Each chip is a menu; an active chip is
/// filled and names its value.
private struct FilterChips: View {
    @Binding var filter: RecipeFilter
    let courses: [String]

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

extension RecipesView {
    private func openImportedRecipe() {
        guard let recipe = importedRecipe else { return }
        importedRecipe = nil
        libraryView = .recipes
        path = [recipe]
    }
}

#Preview {
    RecipesView()
        .modelContainer(try! RecipeStore.makeContainer(inMemory: true))
}
