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
        ingredientsText = Self.ingredientsText(version.sortedIngredients.map { ($0.group, $0.rawText) })
        // Blank lines between steps, so a step typed across several lines survives a round trip.
        stepsText = version.sortedSteps.map(\.text).joined(separator: "\n\n")
        notes = version.notes
    }

    var canSave: Bool { !title.trimmed.isEmpty }

    var parsedIngredients: [ParsedIngredient] { groupedIngredients.map(\.parsed) }

    /// Each ingredient line with the group heading above it. A line ending with a colon ("For the
    /// dressing:") is a heading, so groups survive the editor's plain-text round trip.
    var groupedIngredients: [(group: String?, parsed: ParsedIngredient)] {
        var group: String?
        var result: [(group: String?, parsed: ParsedIngredient)] = []
        for line in ingredientsText.components(separatedBy: .newlines) {
            let text = line.trimmed
            guard !text.isEmpty else { continue }
            if let heading = Self.groupHeading(in: text) {
                group = heading
            } else {
                result.append((group, IngredientParser.parse(text)))
            }
        }
        return result
    }

    /// "For the dressing:" → "For the dressing". Nil for an ingredient line.
    static func groupHeading(in line: String) -> String? {
        let text = line.trimmed
        guard text.count > 1, text.count <= 60, text.hasSuffix(":") else { return nil }
        let name = String(text.dropLast()).trimmed
        return name.isEmpty ? nil : name
    }

    /// Ingredient lines with a "Heading:" line wherever the group changes.
    static func ingredientsText(_ lines: [(group: String?, rawText: String)]) -> String {
        var text: [String] = []
        var current: String?
        for (group, rawText) in lines {
            if let group, !group.isEmpty, group != current { text.append("\(group):") }
            current = group
            text.append(rawText)
        }
        return text.joined(separator: "\n")
    }

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
            if let previous = recipe.currentVersion {
                Self.carryStepPhotos(from: previous, to: version)
            }
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

        version.ingredients = groupedIngredients.enumerated().map { index, line in
            let parsed = line.parsed
            let ingredient = Ingredient(item: parsed.item, rawText: parsed.rawText, sortOrder: index)
            context.insert(ingredient)
            ingredient.group = line.group
            ingredient.quantityNumerator = parsed.quantity?.numerator
            ingredient.quantityDenominator = parsed.quantity?.denominator
            ingredient.unit = parsed.unit?.rawValue
            ingredient.isOptional = parsed.isOptional
            ingredient.setWording(from: parsed)
            return ingredient
        }

        version.steps = StepSplitter.steps(from: stepsText).enumerated().map { index, text in
            let step = Step(text: text, sortOrder: index)
            context.insert(step)
            return step
        }
    }

    /// Step photos follow their step into a new version: to the step with the same text, else, when
    /// the number of steps is unchanged, to the step in the same place. The old version keeps its
    /// text as history; a photo lives on one step at a time.
    static func carryStepPhotos(from previous: RecipeVersion, to version: RecipeVersion) {
        let oldSteps = previous.sortedSteps
        let newSteps = version.sortedSteps
        for (index, old) in oldSteps.enumerated() {
            guard let photos = old.images, !photos.isEmpty else { continue }
            let target = newSteps.first { $0.text == old.text }
                ?? (oldSteps.count == newSteps.count ? newSteps[index] : nil)
            guard let target else { continue }
            for photo in photos { photo.step = target }
        }
    }

    /// Only one cover is kept; scans and cook photos are untouched.
    private func removeCoverPhotos(of recipe: Recipe, in context: ModelContext) {
        let photos = (recipe.images ?? []).filter { $0.role == .photo }
        recipe.images = (recipe.images ?? []).filter { $0.role != .photo }
        for image in photos { context.delete(image) }
    }
}

extension Ingredient {
    /// The words of a parsed line: item, preparation, note and the produce the note counts
    /// (04 §5.1 Ingredient lines). Amount and unit are set by the caller.
    func setWording(from parsed: ParsedIngredient) {
        item = parsed.item
        preparation = parsed.preparation
        note = parsed.note
        equivalentCountNumerator = parsed.equivalent?.count.numerator
        equivalentCountDenominator = parsed.equivalent?.count.denominator
        equivalentItem = parsed.equivalent?.item
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
