import Foundation
import Observation
import RecipeModel
import SwiftData

/// App-wide navigation requests that come from outside a tab: a Spotlight result, another tab
/// asking Recipes to show a recipe, a sidebar tab picked from a page (the review row, a hub row),
/// or the tab Search was opened from. RootTabView owns it and passes it down in the environment.
@Observable
final class AppRouter {
    var selectedTab: AppTab = .recipes
    /// A recipe Recipes should open, by `Recipe.id`. Recipes clears it once it has.
    var requestedRecipeID: UUID?
    /// Search's scope, set to the tab the cook came from each time Search opens (04 §5.1 Search tab).
    var searchScope: SearchScope = .recipes
    /// The sidebar's New Collection (the Collections section's action) asks for a name.
    var isCreatingCollection = false
    /// A collection whose selected tab is giving way to Recipes; deleted once it has.
    @ObservationIgnored private var pendingDeletion: (() -> Void)?

    func openRecipe(id: UUID) {
        selectedTab = .recipes
        requestedRecipeID = id
    }

    /// iPad: selects the sidebar tab showing `scope`; All Recipes is the Recipes tab itself.
    func show(_ scope: LibraryScope) {
        selectedTab = scope == .all ? .recipes : .library(scope)
    }

    /// Deletes a collection; its recipes stay. When its sidebar tab is selected, Recipes is
    /// selected first and the collection goes once the tab view has shown it (RootTabView calls
    /// `selectionDidChange()`): removed while still selected, its tab gives way to the
    /// neighbouring one, which the tab view writes back over Recipes.
    func delete(_ collection: RecipeCollection, in context: ModelContext) {
        guard selectedTab == .library(.collection(collection.persistentModelID)) else {
            CollectionActions.delete(collection, in: context)
            return
        }
        pendingDeletion = { CollectionActions.delete(collection, in: context) }
        selectedTab = .recipes
    }

    /// Finishes a deletion waiting for its tab to be deselected.
    func selectionDidChange() {
        guard let deletion = pendingDeletion else { return }
        pendingDeletion = nil
        deletion()
    }
}
