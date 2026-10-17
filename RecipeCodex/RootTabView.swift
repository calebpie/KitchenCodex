import SwiftUI

/// The five top-level destinations (02 §1.1). The trailing Search tab uses the system search role
/// so iPhone shows it as the dedicated search button and iPad puts it in the sidebar.
enum AppTab: String, Hashable, CaseIterable {
    case cook, recipes, books, plan, search
}

struct RootTabView: View {
    @State private var selection: AppTab = .cook

    var body: some View {
        TabView(selection: $selection) {
            Tab("Cook", systemImage: "frying.pan", value: .cook) {
                CookView()
            }
            Tab("Recipes", systemImage: "book.closed", value: .recipes) {
                RecipesView()
            }
            Tab("Books", systemImage: "books.vertical", value: .books) {
                BooksView()
            }
            Tab("Plan", systemImage: "calendar", value: .plan) {
                PlanView()
            }
            Tab(value: .search, role: .search) {
                SearchView()
            }
        }
        // iPhone: bottom tab bar. iPad: top tab bar that the user can convert into a sidebar.
        .tabViewStyle(.sidebarAdaptable)
    }
}

#Preview("Root") {
    RootTabView()
}
