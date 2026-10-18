import RecipeModel
import SwiftData
import SwiftUI

/// Today: the active cook session, tonight's plan, timers, and suggestions. Phase 1 adds the quiet
/// "new recipes need a look" row for low-confidence imports (02 Flow A step 5); the rest arrives
/// with cook mode and planning.
struct CookView: View {
    @Query(sort: [SortDescriptor(\Recipe.createdAt, order: .reverse)]) private var recipes: [Recipe]

    private var needingReview: [Recipe] { recipes.filter(\.needsReview) }

    var body: some View {
        NavigationStack {
            Group {
                let pending = needingReview
                if pending.isEmpty {
                    nothingPlanned
                } else {
                    List {
                        Section {
                            NavigationLink {
                                ReviewQueueView()
                            } label: {
                                Label {
                                    Text(pending.count == 1 ? "1 new recipe needs a look" : "\(pending.count) new recipes need a look")
                                } icon: {
                                    Image(systemName: "exclamationmark.bubble")
                                        .foregroundStyle(.yellow)
                                }
                            }
                        } footer: {
                            Text("Imported with low confidence. A quick check against the page keeps them right.")
                        }

                        nothingPlanned
                            .listRowBackground(Color.clear)
                    }
                }
            }
            .navigationTitle("Cook")
        }
    }

    private var nothingPlanned: some View {
        ContentUnavailableView {
            Label("Nothing on the stove", systemImage: "frying.pan")
        } description: {
            Text("Plan an event to see tonight's tasks here, or start a recipe from Recipes.")
        }
    }
}

/// The recipes waiting for a check, newest first. A recipe leaves the list once it is reviewed.
private struct ReviewQueueView: View {
    @Query(sort: [SortDescriptor(\Recipe.createdAt, order: .reverse)]) private var recipes: [Recipe]

    var body: some View {
        let pending = recipes.filter(\.needsReview)
        List(pending) { recipe in
            // A view destination: a value link here, under a page pushed by a view link, stalls the push.
            NavigationLink {
                RecipeDetailView(recipe: recipe)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    RecipeRow(recipe: recipe)
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                            .accessibilityHidden(true)
                        Text(recipe.reviewTitle)
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .padding(.leading, 68)
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if pending.isEmpty {
                ContentUnavailableView {
                    Label("All checked", systemImage: "checkmark.circle")
                } description: {
                    Text("Every imported recipe has had its look.")
                }
            }
        }
        .navigationTitle("Needs a Look")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.default, value: pending.count)
    }
}

#Preview {
    CookView()
        .modelContainer(try! RecipeStore.makeContainer(inMemory: true))
}
