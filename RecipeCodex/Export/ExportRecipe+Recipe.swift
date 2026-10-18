import Capture
import Foundation
import RecipeModel
import SwiftUI
import UniformTypeIdentifiers

extension ExportRecipe {
    /// The recipe's current version, as written (no scaling or unit conversion).
    init(recipe: Recipe) {
        let version = recipe.currentVersion
        var yield: String?
        if let text = version?.yieldText, !text.isEmpty {
            yield = text
        } else if let servings = version?.servings {
            yield = "Serves \(servings)"
        }
        self.init(
            title: recipe.title,
            sourceLine: recipe.sourceLine,
            sourceURL: recipe.source?.url,
            yield: yield,
            prepMinutes: version?.prepMinutes,
            cookMinutes: version?.cookMinutes,
            totalMinutes: version?.totalMinutes,
            ingredients: (version?.sortedIngredients ?? []).map { ingredient in
                ExportRecipe.Ingredient(
                    group: ingredient.group,
                    quantity: ingredient.quantity,
                    item: ingredient.item.isEmpty ? ingredient.rawText : ingredient.item,
                    preparation: ingredient.preparation,
                    isOptional: ingredient.isOptional
                )
            },
            steps: (version?.sortedSteps ?? []).map(\.text),
            notes: version?.notes
        )
    }
}

extension Recipe {
    /// Where the recipe came from, as detail and exports show it: a book and page, a site and author,
    /// or "Added by hand" with the date.
    var sourceLine: String {
        if let book {
            let page = pageNumber.map { ", p. \($0)" } ?? ""
            return "\(book.title)\(page)"
        }
        if let source {
            let site = source.siteName ?? source.url?.host() ?? ""
            return [site, source.author].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
        }
        return "Added by hand · \(createdAt.formatted(date: .abbreviated, time: .omitted))"
    }
}

// MARK: - Share items

/// The recipe as a Markdown file ("Roast Chicken.md").
struct RecipeMarkdownFile: Transferable {
    let recipe: ExportRecipe

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .markdown) { item in
            Data(RecipeExporter.markdown(item.recipe).utf8)
        }
        .suggestedFileName { RecipeExporter.fileName(for: $0.recipe.title, extension: "md") }
    }
}

/// The recipe as plain text, for Messages, Notes, Mail or a .txt file.
struct RecipePlainText: Transferable {
    let recipe: ExportRecipe

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .utf8PlainText) { item in
            Data(RecipeExporter.plainText(item.recipe).utf8)
        }
        .suggestedFileName { RecipeExporter.fileName(for: $0.recipe.title, extension: "txt") }
        ProxyRepresentation { RecipeExporter.plainText($0.recipe) }
    }
}

/// The recipe as a printable PDF, laid out when the share sheet asks for it.
struct RecipePDFFile: Transferable {
    let recipe: ExportRecipe
    /// The cover photo's bytes, decoded at print size when the PDF is made.
    let coverData: Data?

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .pdf) { item in
            await RecipePDFRenderer.pdf(for: item.recipe, coverData: item.coverData)
        }
        .suggestedFileName { RecipeExporter.fileName(for: $0.recipe.title, extension: "pdf") }
    }
}
