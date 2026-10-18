import CoreSpotlight
import SwiftUI

/// The five top-level destinations (02 §1.1), in the order the work happens: collect recipes,
/// stock the kitchen, plan the dinner, cook it. The trailing Search tab uses the system search
/// role so iPhone shows it as the dedicated search button and iPad puts it in the sidebar.
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
        // iPhone: bottom tab bar. iPad: top tab bar that the user can convert into a sidebar.
        .tabViewStyle(.sidebarAdaptable)
        .environment(router)
        // A recipe tapped in Spotlight (RecipeSpotlightIndexer) opens in Recipes.
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                  let id = UUID(uuidString: identifier) else { return }
            router.openRecipe(id: id)
        }
    }
}

#Preview("Root") {
    RootTabView()
}
