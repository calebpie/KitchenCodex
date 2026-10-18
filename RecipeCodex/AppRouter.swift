import Foundation
import Observation

/// App-wide navigation requests that come from outside a tab: a Spotlight result, or another tab
/// asking Recipes to show a recipe. RootTabView owns it and passes it down in the environment.
@Observable
final class AppRouter {
    var selectedTab: AppTab = .recipes
    /// A recipe Recipes should open, by `Recipe.id`. Recipes clears it once it has.
    var requestedRecipeID: UUID?

    func openRecipe(id: UUID) {
        selectedTab = .recipes
        requestedRecipeID = id
    }
}
