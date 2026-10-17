import SwiftUI

/// The one place to find anything. Phase 1 wires it to the library; Phase 6 adds natural language.
struct SearchView: View {
    @State private var query = ""

    var body: some View {
        NavigationStack {
            Group {
                if query.isEmpty {
                    ContentUnavailableView {
                        Label("Search Recipe Codex", systemImage: "magnifyingglass")
                    } description: {
                        Text("Recipes, books, events, ingredients and cook history.")
                    }
                } else {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Recipes, books, events…")
        }
    }
}

#Preview {
    SearchView()
}
