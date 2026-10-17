import Foundation
import Intelligence

/// A recipe as it arrives from the outside world, before it becomes a RecipeModel object.
public struct ImportedRecipe: Sendable, Equatable {
    public var title: String
    public var ingredients: [String]
    public var steps: [String]
    public var yield: String?
    public var author: String?
    public var sourceURL: URL?
    public var imageURL: URL?
    public var totalTime: Duration?

    public init(
        title: String,
        ingredients: [String] = [],
        steps: [String] = [],
        yield: String? = nil,
        author: String? = nil,
        sourceURL: URL? = nil,
        imageURL: URL? = nil,
        totalTime: Duration? = nil
    ) {
        self.title = title
        self.ingredients = ingredients
        self.steps = steps
        self.yield = yield
        self.author = author
        self.sourceURL = sourceURL
        self.imageURL = imageURL
        self.totalTime = totalTime
    }

    public init(draft: StructuredRecipeDraft, sourceURL: URL? = nil) {
        self.init(title: draft.title, ingredients: draft.ingredients, steps: draft.steps, sourceURL: sourceURL)
    }
}
