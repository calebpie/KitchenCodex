import Foundation
import Observation

/// App-wide navigation requests that come from outside a tab: a Spotlight result, another tab
/// asking Recipes to show a recipe, or the tab Search was opened from. RootTabView owns it and
/// passes it down in the environment.
@Observable
final class AppRouter {
    var selectedTab: AppTab = .recipes
    /// A recipe Recipes should open, by `Recipe.id`. Recipes clears it once it has.
    var requestedRecipeID: UUID?
    /// Search's scope, set to the tab the cook came from each time Search opens (04 §5.1 Search tab).
    var searchScope: SearchScope = .recipes

    func openRecipe(id: UUID) {
        selectedTab = .recipes
        requestedRecipeID = id
    }
}
