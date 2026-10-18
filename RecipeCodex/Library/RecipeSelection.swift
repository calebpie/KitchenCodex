import Capture
import RecipeModel
import SwiftData
import SwiftUI

/// The bottom bar of Select mode (03 §3.2): Add to Collection, Favorite, Share, then Delete and Done.
/// Each action applies to every selected recipe and is disabled while nothing is selected.
struct RecipeSelectionToolbar: ToolbarContent {
    let recipes: [Recipe]
    /// Asks the host to prompt for a name; the host then creates the collection with the selection.
    let onNewCollection: () -> Void
    /// Deletes the recipes, once the cook has confirmed.
    let onDelete: ([Recipe]) -> Void
    let onDone: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .bottomBar) {
            AddSelectionToCollectionMenu(recipes: recipes, onNewCollection: onNewCollection)
                .disabled(recipes.isEmpty)
        }
        ToolbarItem(placement: .bottomBar) {
            let allFavorites = !recipes.isEmpty && recipes.allSatisfy(\.isFavorite)
            Button(allFavorites ? "Unfavorite" : "Favorite", systemImage: allFavorites ? "heart.slash" : "heart") {
                for recipe in recipes { recipe.isFavorite = !allFavorites }
            }
            .disabled(recipes.isEmpty)
        }
        ToolbarItem(placement: .bottomBar) {
            ShareRecipesMenu(recipes: recipes)
                .disabled(recipes.isEmpty)
        }
        ToolbarSpacer(.flexible, placement: .bottomBar)
        ToolbarItem(placement: .bottomBar) {
            DeleteSelectionButton(recipes: recipes, onDelete: onDelete)
                .disabled(recipes.isEmpty)
        }
        ToolbarItem(placement: .bottomBar) {
            Button("Done", action: onDone)
        }
    }
}

/// Add to Collection for several recipes: each collection, checked when every selected recipe is in
/// it (tap to add them all, or, when checked, to take them all out), then New Collection….
private struct AddSelectionToCollectionMenu: View {
    let recipes: [Recipe]
    let onNewCollection: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: CollectionActions.sortDescriptors) private var collections: [RecipeCollection]

    var body: some View {
        Menu {
            ForEach(collections) { collection in
                let holdsAll = !recipes.isEmpty && recipes.allSatisfy { $0.isIn(collection) }
                Toggle(isOn: Binding {
                    holdsAll
                } set: { _ in
                    for recipe in recipes where recipe.isIn(collection) == holdsAll {
                        recipe.toggleMembership(in: collection)
                    }
                    try? modelContext.save()
                }) {
                    Text(collection.name)
                }
            }
            if !collections.isEmpty { Divider() }
            Button("New Collection…", systemImage: "plus", action: onNewCollection)
        } label: {
            Label("Add to Collection", systemImage: "rectangle.stack.badge.plus")
        }
    }
}

/// Delete for the selection, after a confirmation that names how many.
private struct DeleteSelectionButton: View {
    let recipes: [Recipe]
    let onDelete: ([Recipe]) -> Void

    @State private var isConfirming = false

    private var title: String {
        recipes.count == 1 ? "Delete Recipe" : "Delete \(recipes.count) Recipes"
    }

    var body: some View {
        Button("Delete", systemImage: "trash", role: .destructive) {
            isConfirming = true
        }
        .confirmationDialog("\(title)?", isPresented: $isConfirming, titleVisibility: .visible) {
            Button(title, role: .destructive) { onDelete(recipes) }
        } message: {
            Text(recipes.count == 1 ? "The recipe and all its versions will be deleted." : "The recipes and all their versions will be deleted.")
        }
    }
}

/// Share for one recipe or several. One recipe offers the same submenu as its long-press menu; several
/// offer the same three formats, one file per recipe in a single share sheet. The PDFs of several
/// recipes use each card's cover, which is already small, rather than reading every full photo. Their
/// previews name the recipe only: with an image or icon, the share sheet called two files "2 Images".
struct ShareRecipesMenu: View {
    let recipes: [Recipe]

    var body: some View {
        if recipes.count == 1, let recipe = recipes.first {
            ShareRecipeMenu(recipe: recipe) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        } else {
            let exports = recipes.map { (export: ExportRecipe(recipe: $0), cover: $0.coverImageData) }
            Menu {
                ShareLink(items: exports.map { RecipePDFFile(recipe: $0.export, coverData: $0.cover) }) { file in
                    SharePreview(file.recipe.title)
                } label: {
                    Label("PDF", systemImage: "doc.richtext")
                }
                ShareLink(items: exports.map { RecipeMarkdownFile(recipe: $0.export) }) { file in
                    SharePreview(file.recipe.title)
                } label: {
                    Label("Markdown", systemImage: "number")
                }
                ShareLink(items: exports.map { RecipePlainText(recipe: $0.export) }) { file in
                    SharePreview(file.recipe.title)
                } label: {
                    Label("Plain Text", systemImage: "doc.plaintext")
                }
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
    }
}

/// The circle a card shows in Select mode: empty, or filled with a checkmark once selected.
struct SelectionCircle: View {
    let isSelected: Bool

    var body: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title2)
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear))
            .background {
                if !isSelected {
                    Circle().fill(.black.opacity(0.2))
                }
            }
            .shadow(color: .black.opacity(0.25), radius: 2)
            .accessibilityHidden(true)
    }
}
