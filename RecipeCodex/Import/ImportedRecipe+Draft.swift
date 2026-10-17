import Capture
import Foundation
import RecipeModel
import SwiftData
import UIKit

// Shared by the app's Import from Web sheet and the Share Extension (compiled into both targets), so
// every import is saved the way manual entry saves: through `RecipeDraft`.

extension RecipeDraft {
    /// A draft prefilled from an import: one ingredient per line, steps separated by blank lines.
    init(imported: ImportedRecipe) {
        self.init()
        title = imported.title
        course = RecipeCourse.match(category: imported.category)
        servings = imported.servings.map(String.init) ?? ""
        yieldText = imported.yieldDescription ?? ""
        prepMinutes = imported.prepTime.map(Self.minutesText) ?? ""
        cookMinutes = imported.cookTime.map(Self.minutesText) ?? ""
        totalMinutes = imported.totalTime.map(Self.minutesText) ?? ""
        ingredientsText = imported.ingredients.joined(separator: "\n")
        stepsText = imported.steps.joined(separator: "\n\n")
    }

    private static func minutesText(_ duration: Duration) -> String {
        String((duration.components.seconds + 30) / 60)
    }

    /// Saves a new recipe from an import (or a manual entry started from a failed one), then records
    /// where it came from: the source line, the capture confidence, the review flag and the
    /// ingredient groups. `imported.method == nil` means the cook typed it in.
    @discardableResult
    func saveImport(_ imported: ImportedRecipe, in context: ModelContext) -> Recipe {
        var draft = self
        if draft.changeSummary.trimmed.isEmpty {
            draft.changeSummary = imported.method == nil ? "Added by hand" : "Imported from \(imported.sourceName)"
        }
        let recipe = draft.save(to: nil, comparedWith: RecipeDraft(), in: context)
        recipe.cuisine = recipe.cuisine ?? imported.cuisine

        let source = SourceInfo(url: imported.sourceURL, author: imported.author)
        source.siteName = imported.siteName ?? imported.sourceURL?.host()
        source.importedAt = .now
        context.insert(source)
        recipe.source = source

        if let version = recipe.currentVersion, imported.method != nil {
            version.captureConfidence = imported.confidence
            version.needsReview = imported.needsReview
            // Groups follow the line they started on, so edits in the preview don't shift them.
            let groupByLine = Dictionary(
                imported.ingredients.enumerated().map { ($0.element, imported.group(forIngredientAt: $0.offset)) },
                uniquingKeysWith: { first, _ in first }
            )
            for ingredient in version.sortedIngredients {
                ingredient.group = groupByLine[ingredient.rawText] ?? nil
            }
        }
        try? context.save()
        return recipe
    }

    /// Downloads and prepares the import's cover the way the editor prepares a picked photo.
    static func coverPhoto(for imported: ImportedRecipe) async -> (change: PhotoChange, preview: UIImage?) {
        guard let url = imported.imageURL,
              let data = try? await WebPageFetcher().fetchImage(url, referrer: imported.sourceURL),
              let photo = await ImageProcessing.jpeg(from: data, maxPixelSize: 2_400, quality: 0.85),
              let cover = await ImageProcessing.jpeg(from: data, maxPixelSize: 900, quality: 0.8) else {
            return (.unchanged, nil)
        }
        return (.replaced(photo: photo, cover: cover), await ImageProcessing.thumbnail(from: cover, maxPixelSize: 900))
    }
}

extension ImportedRecipe {
    /// "Serious Eats", or the host when the page names no site.
    var sourceName: String {
        siteName ?? sourceURL?.host()?.replacingOccurrences(of: "www.", with: "") ?? "the web"
    }

    /// The one-line status from 03 §3.4, saying how the recipe was found.
    var statusLine: String {
        switch method {
        case .jsonLD?, .microdata?:
            "Found a recipe on this page."
        case .pageText?:
            "No recipe data on this page, so it was read from the page text. Check it before you cook."
        case .model?:
            "No recipe data on this page, so Apple Intelligence read the page text. Check it before you cook."
        case nil:
            "Couldn't read a recipe from this page. Add it by hand; the link is kept."
        }
    }

    /// An empty recipe that keeps the page's title and link, for "Add Manually Instead".
    static func manual(title: String, url: URL?) -> ImportedRecipe {
        ImportedRecipe(title: title, sourceURL: url, method: nil, confidence: 1)
    }
}

extension RecipeCourse {
    /// The standard course for a page's `recipeCategory` ("Main Course", "side-dish",
    /// "Dinner, Main Course, Poultry", "Desserts or Baked Goods"), if one fits.
    static func match(category: String?) -> String? {
        guard let category else { return nil }
        let table: [(course: String, words: [String])] = [
            ("Main", ["main", "mains", "main course", "main dish", "main-dish", "entree", "entrée", "entrees", "dinner", "lunch"]),
            ("Side", ["side", "sides", "side dish", "side-dish", "side dishes"]),
            ("Dessert", ["dessert", "desserts", "desserts or baked goods", "cake", "cookies", "pie"]),
            ("Starter", ["starter", "starters", "appetizer", "appetizers", "hors d'oeuvres", "first course"]),
            ("Soup", ["soup", "soups", "stew", "stews"]),
            ("Salad", ["salad", "salads"]),
            ("Breakfast", ["breakfast", "brunch"]),
            ("Bread", ["bread", "breads"]),
            ("Sauce", ["sauce", "sauces", "condiment", "condiments", "condiments and sauces", "sauces & condiments"]),
            ("Drink", ["drink", "drinks", "beverage", "beverages", "cocktail", "cocktails"]),
            ("Snack", ["snack", "snacks"]),
        ]
        let parts = category.lowercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        for part in parts {
            if let match = table.first(where: { $0.words.contains(part) }) { return match.course }
        }
        return nil
    }
}
