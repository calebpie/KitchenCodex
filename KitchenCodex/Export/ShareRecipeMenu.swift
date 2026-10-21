import Capture
import RecipeModel
import SwiftUI

/// Share Recipe: PDF, Markdown or plain text of the current version as written. Used in the
/// Recipes long-press menu and on recipe detail's bottom toolbar (03 §3.3).
struct ShareRecipeMenu<MenuLabel: View>: View {
    let recipe: Recipe
    @ViewBuilder var label: MenuLabel

    var body: some View {
        let export = ExportRecipe(recipe: recipe)
        let preview = SharePreview(recipe.title, image: Image(systemName: "fork.knife"))
        Menu {
            ShareLink(item: RecipePDFFile(recipe: export, coverData: recipe.coverImage?.imageData ?? recipe.coverImageData), preview: preview) {
                Label("PDF", systemImage: "doc.richtext")
            }
            ShareLink(item: RecipeMarkdownFile(recipe: export), preview: preview) {
                Label("Markdown", systemImage: "number")
            }
            ShareLink(item: RecipePlainText(recipe: export), preview: preview) {
                Label("Plain Text", systemImage: "doc.plaintext")
            }
        } label: {
            label
        }
    }
}

extension ShareRecipeMenu where MenuLabel == Label<Text, Image> {
    init(recipe: Recipe) {
        self.init(recipe: recipe) { Label("Share Recipe", systemImage: "square.and.arrow.up") }
    }
}
