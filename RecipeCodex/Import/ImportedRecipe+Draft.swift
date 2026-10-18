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
        ingredientsText = Self.ingredientsText(imported.ingredients.enumerated().map { (imported.group(forIngredientAt: $0.offset), $0.element) })
        stepsText = imported.steps.map(\.text).joined(separator: "\n\n")
        notes = imported.notes.joined(separator: "\n\n")
    }

    private static func minutesText(_ duration: Duration) -> String {
        String((duration.components.seconds + 30) / 60)
    }

    /// Saves a new recipe from an import (or a manual entry started from a failed one), then records
    /// where it came from: the source line, the capture confidence and the review flag. Ingredient
    /// groups travel in the ingredients text as "Heading:" lines. A library export's categories
    /// become tags (see `tags(named:in:)`). `imported.method == nil` means the cook typed it in.
    /// Step photos the source shows are downloaded after the save and attached as they arrive (see
    /// `attachStepPhotos`).
    @discardableResult
    func saveImport(_ imported: ImportedRecipe, in context: ModelContext) -> Recipe {
        var draft = self
        if draft.changeSummary.trimmed.isEmpty {
            draft.changeSummary = imported.method == nil ? "Added by hand" : "Imported from \(imported.importedFrom ?? imported.sourceName)"
        }
        let recipe = draft.save(to: nil, comparedWith: RecipeDraft(), in: context)
        recipe.cuisine = recipe.cuisine ?? imported.cuisine
        recipe.isFavorite = imported.isFavorite
        if !imported.categories.isEmpty {
            recipe.tags = Self.tags(named: imported.categories, in: context)
        }
        if let headnote = imported.headnote?.trimmed, !headnote.isEmpty { recipe.headnote = headnote }
        if let created = imported.createdAt {
            recipe.createdAt = created
            recipe.currentVersion?.createdAt = created
        }

        let source = SourceInfo(url: imported.sourceURL, author: imported.author)
        source.siteName = imported.siteName ?? imported.sourceURL?.host()
        source.importedAt = .now
        context.insert(source)
        recipe.source = source

        if let version = recipe.currentVersion, imported.method != nil {
            version.captureConfidence = imported.confidence
            version.needsReview = imported.needsReview
        }
        try? context.save()

        if imported.stepImageCount > 0 {
            Task {
                let photos = await Self.stepPhotos(for: imported)
                Self.attachStepPhotos(photos, from: imported, to: recipe, in: context)
            }
        }
        return recipe
    }

    /// One tag per name: the library's tag of that name, ignoring case and accents, else a new one
    /// named as written. Paprika and Mela categories arrive this way, so "weeknight" from one recipe
    /// and "Weeknight" from the next share a tag.
    static func tags(named names: [String], in context: ModelContext) -> [Tag] {
        var existing = (try? context.fetch(FetchDescriptor<Tag>())) ?? []
        var result: [Tag] = []
        for name in names {
            let tag: Tag
            if let match = existing.first(where: { $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
                tag = match
            } else {
                tag = Tag(name: name)
                context.insert(tag)
                existing.append(tag)
            }
            if !result.contains(where: { $0 === tag }) { result.append(tag) }
        }
        return result
    }

    /// Downloads and prepares the import's cover the way the editor prepares a picked photo. An
    /// embedded photo (Paprika, Mela) is used as is, without a download.
    static func coverPhoto(for imported: ImportedRecipe) async -> (change: PhotoChange, preview: UIImage?) {
        var source = imported.imageData
        if source == nil, let url = imported.imageURL {
            source = try? await WebPageFetcher().fetchImage(url, referrer: imported.sourceURL)
        }
        guard let data = source,
              let photo = await ImageProcessing.jpeg(from: data, maxPixelSize: 2_400, quality: 0.85),
              let cover = await ImageProcessing.jpeg(from: data, maxPixelSize: 900, quality: 0.8) else {
            return (.unchanged, nil)
        }
        return (.replaced(photo: photo, cover: cover), await ImageProcessing.thumbnail(from: cover, maxPixelSize: 900))
    }

    /// Step photos larger than this as downloaded are skipped.
    static let stepPhotoByteLimit = 15_000_000

    /// Downloads every step photo the import names, four at a time, with the page as referrer, and
    /// re-encodes each as JPEG with its longest side at most 1,600 px. Failures are left out.
    static func stepPhotos(for imported: ImportedRecipe) async -> [URL: Data] {
        let urls = Array(Set(imported.steps.compactMap(\.imageURL)))
        let referrer = imported.sourceURL
        let limit = stepPhotoByteLimit
        var photos: [URL: Data] = [:]
        await withTaskGroup(of: (URL, Data?).self) { group in
            var next = 0
            func enqueue() {
                guard next < urls.count else { return }
                let url = urls[next]
                next += 1
                group.addTask {
                    guard let data = try? await WebPageFetcher().fetchImage(url, referrer: referrer),
                          data.count <= limit else { return (url, nil) }
                    return (url, await ImageProcessing.jpeg(from: data, maxPixelSize: 1_600, quality: 0.82))
                }
            }
            for _ in 0..<4 { enqueue() }
            while let (url, data) = await group.next() {
                if let data { photos[url] = data }
                enqueue()
            }
        }
        return photos
    }

    /// Saves downloaded step photos as `.stepPhoto` images on the recipe's current steps, with no
    /// cook session (they came from the source). Each photo goes to the step whose text matches the
    /// imported step, or to the same position when the preview kept the number of steps.
    static func attachStepPhotos(_ photos: [URL: Data], from imported: ImportedRecipe, to recipe: Recipe, in context: ModelContext) {
        guard !photos.isEmpty, let version = recipe.currentVersion, recipe.modelContext != nil else { return }
        let steps = version.sortedSteps
        func key(_ text: String) -> String {
            text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        for (index, importedStep) in imported.steps.enumerated() {
            guard let url = importedStep.imageURL, let data = photos[url] else { continue }
            let target = steps.first { key($0.text) == key(importedStep.text) }
                ?? (steps.count == imported.steps.count ? steps[index] : nil)
            guard let target else { continue }
            let image = RecipeImage(role: .stepPhoto, imageData: data)
            context.insert(image)
            image.step = target
            image.recipe = recipe
        }
        try? context.save()
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
        case .libraryFile?:
            "Imported from \(importedFrom ?? "another app")."
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
    /// "Dinner, Main Course, Poultry", "Desserts or Baked Goods"), if one fits: the first
    /// comma-separated part that names a course decides. Paprika and Mela categories arrive joined
    /// the same way, so "Weeknight, Dinner" is a Main; every one of them is also a tag.
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
