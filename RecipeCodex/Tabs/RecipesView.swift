import SwiftUI

/// The library. Phase 1 adds browsing, filters and collections.
struct RecipesView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("No recipes yet", systemImage: "book.closed")
            } description: {
                Text("Share a recipe from Safari, scan a cookbook page, or add one by hand.")
            }
            .navigationTitle("Recipes")
        }
    }
}

#Preview {
    RecipesView()
}
