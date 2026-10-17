import RecipeModel
import SwiftData
import SwiftUI

/// The one place to find anything. Phase 1 wires it to the library; Phase 6 adds natural language.
struct SearchView: View {
    @State private var query = ""
    @Query(sort: [SortDescriptor(\Recipe.title, comparator: .localizedStandard)]) private var recipes: [Recipe]

    var body: some View {
        NavigationStack {
            Group {
                if query.trimmed.isEmpty {
                    ContentUnavailableView {
                        Label("Search Recipe Codex", systemImage: "magnifyingglass")
                    } description: {
                        Text("Recipes, books, events, ingredients and cook history.")
                    }
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List {
                        Section("Recipes") {
                            ForEach(results) { result in
                                NavigationLink(value: result.recipe) {
                                    RecipeRow(recipe: result.recipe, matchedIngredient: result.matchedIngredient)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Search")
            .navigationDestination(for: Recipe.self) { recipe in
                RecipeDetailView(recipe: recipe)
            }
            .searchable(text: $query, prompt: "Recipes, books, events…")
        }
    }

    private var results: [LibrarySearch.Result] {
        LibrarySearch.results(for: query, in: recipes)
    }
}

/// Title and ingredient search over the library. Every word must appear in the title or in one of
/// the current version's ingredients; title matches come first.
enum LibrarySearch {
    struct Result: Identifiable {
        let recipe: Recipe
        /// Set when an ingredient, not the title, carried the match.
        let matchedIngredient: String?
        var id: PersistentIdentifier { recipe.persistentModelID }
    }

    static func results(for query: String, in recipes: [Recipe]) -> [Result] {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return [] }

        var titleMatches: [Result] = []
        var ingredientMatches: [Result] = []
        for recipe in recipes {
            let ingredients = recipe.currentVersion?.sortedIngredients ?? []
            var matchedIngredient: String?
            let matchesAll = terms.allSatisfy { term in
                if recipe.title.localizedStandardContains(term) { return true }
                guard let ingredient = ingredients.first(where: {
                    $0.item.localizedStandardContains(term) || $0.rawText.localizedStandardContains(term)
                }) else { return false }
                matchedIngredient = matchedIngredient ?? ingredient.item
                return true
            }
            guard matchesAll else { continue }
            if let matchedIngredient {
                ingredientMatches.append(Result(recipe: recipe, matchedIngredient: matchedIngredient))
            } else {
                titleMatches.append(Result(recipe: recipe, matchedIngredient: nil))
            }
        }
        return titleMatches + ingredientMatches
    }
}

#Preview {
    SearchView()
        .modelContainer(try! RecipeStore.makeContainer(inMemory: true))
}
