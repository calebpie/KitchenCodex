import SwiftUI

/// What the View menu acts on: the Recipes page on screen (`RecipesView`), published while its
/// grid, list or shelf shows.
struct LibraryPageCommands {
    /// Recipes or Cookbooks.
    var view: Binding<RecipesView.LibraryView>
    var layout: Binding<RecipeLayout>
    /// The recipes view with recipes in it, where Grid, List and Filter apply.
    var showsRecipes: Bool
    /// Opens the Filter list, as the toolbar's Filter does (ux-notes row 41).
    var showFilter: () -> Void
}

extension FocusedValues {
    /// The Recipes page on screen; nil on other tabs, under a pushed recipe and in Select mode.
    @Entry var libraryPage: LibraryPageCommands?
}

/// The iPad menu bar and hardware-keyboard shortcuts for what Phase 1 has (03 §4 Menu bar and
/// keyboard); items for features that haven't shipped are left out, not disabled (04 §5.1 Add menu).
/// File starts a recipe from any tab, on the Recipes page. View acts on the Recipes page while it
/// is on screen and is disabled otherwise; its Filter… opens the Filter list. Search (⌘F) selects the search tab and starts the search
/// (`AppRouter.openSearch()`).
struct RecipeCodexCommands: Commands {
    @FocusedValue(AppRouter.self) private var router
    @FocusedValue(\.libraryPage) private var page

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Recipe") { router?.request(.enterManually) }
                .keyboardShortcut("n")
                .disabled(router == nil)
            Button("Import from Web") { router?.request(.importFromWeb) }
                .keyboardShortcut("i")
                .disabled(router == nil)
            Button("Scan Page…") { router?.request(.scanPage) }
                .disabled(router == nil)
            Button("Import from Paprika or Mela…") { router?.request(.importLibrary) }
                .disabled(router == nil)
        }

        CommandGroup(before: .toolbar) {
            Picker("Library", selection: page?.view ?? .constant(.recipes)) {
                ForEach(RecipesView.LibraryView.allCases) { view in
                    Text(view.rawValue).tag(view)
                }
            }
            .pickerStyle(.inline)
            .disabled(page == nil)

            Picker("View As", selection: page?.layout ?? .constant(.grid)) {
                ForEach(RecipeLayout.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.inline)
            .disabled(page?.showsRecipes != true)

            Button("Filter…") { page?.showFilter() }
                .disabled(page?.showsRecipes != true)

            Divider()
            Button("Search") { router?.openSearch() }
                .keyboardShortcut("f")
                .disabled(router == nil)
        }
    }
}
