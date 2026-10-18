import CoreSpotlight
import SwiftUI

/// The five top-level destinations (02 §1.1), in the order the work happens: collect recipes,
/// stock the kitchen, plan the dinner, cook it. The trailing Search tab uses the system search
/// role: on iPhone the separate Liquid Glass bubble that morphs into the field (04 §5.1 Search tab).
enum AppTab: String, Hashable, CaseIterable {
    case recipes, pantry, plan, cook, search
}

struct RootTabView: View {
    @State private var router = AppRouter()

    var body: some View {
        TabView(selection: $router.selectedTab) {
            Tab("Recipes", systemImage: "book.closed", value: .recipes) {
                RecipesView()
            }
            Tab("Pantry", systemImage: "cabinet", value: .pantry) {
                PantryView()
            }
            Tab("Plan", systemImage: "calendar", value: .plan) {
                PlanView()
            }
            Tab("Cook", systemImage: "frying.pan", value: .cook) {
                CookView()
            }
            Tab(value: .search, role: .search) {
                SearchView()
            }
        }
        // iPhone: the bottom tab bar. iPad: the floating tab bar at the top, never a tab sidebar, so
        // each tab's own split-view sidebar is the only left column (04 §5.1 iPad tabs).
        .tabViewStyle(.tabBarOnly)
        // iOS 27 sets the search tab apart as its own bubble only when selecting it starts the
        // search; without this it is a fifth inline tab.
        .tabViewSearchActivation(.searchTabSelection)
        .onChange(of: router.selectedTab) { previous, selected in
            // Search opens on the scope of the tab the cook came from.
            if selected == .search, previous != .search {
                router.searchScope = SearchScope(origin: previous)
            }
        }
        .environment(router)
        // A recipe, or one of its ingredients, tapped in Spotlight (RecipeSpotlightIndexer) opens in Recipes.
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                  let id = RecipeSpotlightIndexer.recipeID(fromItemIdentifier: identifier) else { return }
            router.openRecipe(id: id)
        }
    }
}

#Preview("Root") {
    RootTabView()
}
