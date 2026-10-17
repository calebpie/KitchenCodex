import Capture
import Foundation
import RecipeModel
import SwiftData
import Units

/// The editable form of a recipe, shared by New Recipe and Edit. Text fields stay text until save so
/// nothing is lost mid-typing; saving parses ingredients and steps through Capture.
struct RecipeDraft: Equatable {
    enum PhotoChange: Equatable {
        case unchanged
        /// `photo` is the stored original (RecipeImage); `cover` the smaller copy cards and rows decode.
        case replaced(photo: Data, cover: Data)
        case removed
    }

    var title = ""
    var course: String?
    var servings = ""
    var yieldText = ""
    var prepMinutes = ""
    var cookMinutes = ""
    var totalMinutes = ""
    var ingredientsText = ""
    var stepsText = ""
    var notes = ""
    var changeSummary = ""
    var photo: PhotoChange = .unchanged

    init() {}

    init(recipe: Recipe) {
        title = recipe.title
        course = recipe.course
        guard let version = recipe.currentVersion else { return }
        servings = version.servings.map(String.init) ?? ""
        yieldText = version.yieldText
        prepMinutes = version.prepMinutes.map(String.init) ?? ""
        cookMinutes = version.cookMinutes.map(String.init) ?? ""
        totalMinutes = version.totalMinutes.map(String.init) ?? ""
        ingredientsText = version.sortedIngredients.map(\.rawText).joined(separator: "\n")
        // Blank lines between steps, so a step typed across several lines survives a round trip.
        stepsText = version.sortedSteps.map(\.text).joined(separator: "\n\n")
        notes = version.notes
    }

    var canSave: Bool { !title.trimmed.isEmpty }

    var parsedIngredients: [ParsedIngredient] { IngredientParser.parseLines(ingredientsText) }

    /// Whether anything that lives on `RecipeVersion` changed. Title, course and photo live on
    /// `Recipe` and change in place without a new version.
    func versionContentDiffers(from other: RecipeDraft) -> Bool {
        servings != other.servings || yieldText != other.yieldText
            || prepMinutes != other.prepMinutes || cookMinutes != other.cookMinutes || totalMinutes != other.totalMinutes
            || ingredientsText.trimmed != other.ingredientsText.trimmed
            || StepSplitter.steps(from: stepsText) != StepSplitter.steps(from: other.stepsText)
            || notes.trimmed != other.notes.trimmed
    }

    /// Creates a recipe, or updates `existing`. New recipes get version 1; an edit that changes the
    /// content adds a version and makes it current, keeping the old one as history.
    @discardableResult
    func save(to existing: Recipe?, comparedWith original: RecipeDraft, in context: ModelContext) -> Recipe {
        let recipe: Recipe
        if let existing {
            recipe = existing
        } else {
            recipe = Recipe(title: title.trimmed)
            context.insert(recipe)
        }
        recipe.title = title.trimmed
        recipe.course = course

        if existing == nil || versionContentDiffers(from: original) {
            let summary = changeSummary.trimmed
            let version = RecipeVersion(changeSummary: summary.isEmpty ? (existing == nil ? "Added by hand" : "Edited") : summary)
            context.insert(version)
            fill(version, in: context)
            recipe.addVersion(version)
        }

        switch photo {
        case .unchanged:
            break
        case let .replaced(photoData, coverData):
            removeCoverPhotos(of: recipe, in: context)
            let image = RecipeImage(role: .photo, imageData: photoData)
            image.caption = "Cover"
            context.insert(image)
            recipe.images = (recipe.images ?? []) + [image]
            recipe.coverImageData = coverData
        case .removed:
            removeCoverPhotos(of: recipe, in: context)
            recipe.coverImageData = nil
        }
        recipe.updatedAt = .now

        try? context.save()
        return recipe
    }

    private func fill(_ version: RecipeVersion, in context: ModelContext) {
        version.servings = Int(servings.trimmed).flatMap { $0 > 0 ? $0 : nil }
        version.yieldText = yieldText.trimmed
        version.prepMinutes = Int(prepMinutes.trimmed)
        version.cookMinutes = Int(cookMinutes.trimmed)
        version.totalMinutes = Int(totalMinutes.trimmed)
        version.notes = notes.trimmed

        version.ingredients = parsedIngredients.enumerated().map { index, parsed in
            let ingredient = Ingredient(item: parsed.item, rawText: parsed.rawText, sortOrder: index)
            context.insert(ingredient)
            ingredient.quantityNumerator = parsed.quantity?.numerator
            ingredient.quantityDenominator = parsed.quantity?.denominator
            ingredient.unit = parsed.unit?.rawValue
            ingredient.preparation = parsed.preparation
            ingredient.isOptional = parsed.isOptional
            return ingredient
        }

        version.steps = StepSplitter.steps(from: stepsText).enumerated().map { index, text in
            let step = Step(text: text, sortOrder: index)
            context.insert(step)
            return step
        }
    }

    /// Only one cover is kept; scans and cook photos are untouched.
    private func removeCoverPhotos(of recipe: Recipe, in context: ModelContext) {
        let photos = (recipe.images ?? []).filter { $0.role == .photo }
        recipe.images = (recipe.images ?? []).filter { $0.role != .photo }
        for image in photos { context.delete(image) }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
