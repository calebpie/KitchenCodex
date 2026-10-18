import Foundation
import Intelligence

/// How an import found its recipe, from most to least trustworthy.
public enum ImportMethod: String, Sendable, Codable, CaseIterable {
    /// schema.org `Recipe` JSON-LD in the page.
    case jsonLD
    /// schema.org microdata (`itemprop="recipeIngredient"` and friends).
    case microdata
    /// The deterministic reading of the page's visible text.
    case pageText
    /// The on-device model structuring the page's visible text.
    case model
    /// Another recipe app's export (Paprika, Mela): already structured by the cook.
    case libraryFile
}

/// One instruction as the source wrote it, with the photo the source shows for it, if any.
public struct ImportedStep: Sendable, Equatable, Hashable, ExpressibleByStringLiteral, CustomStringConvertible {
    public var text: String
    public var imageURL: URL?

    public init(text: String, imageURL: URL? = nil) {
        self.text = text
        self.imageURL = imageURL
    }

    public init(stringLiteral text: String) {
        self.init(text: text)
    }

    public var description: String { text }
}

/// A recipe as it arrives from the outside world, before it becomes a RecipeModel object.
public struct ImportedRecipe: Sendable, Equatable {
    public var title: String
    /// Ingredient lines as written, one per entry, group headings removed (see `ingredientGroups`).
    public var ingredients: [String]
    public var steps: [ImportedStep]
    /// Notes as separate paragraphs, in the source's order: a library export's notes, and asides the
    /// source posted as steps ("DO AHEAD: …", "Tip: …"), which `movingAsidesToNotes()` moves here.
    public var notes: [String] = []
    /// The introduction above the recipe, when the source keeps one apart (Mela's `text`).
    public var headnote: String?
    /// The yield as the page states it ("Serves 6", "Makes 30 cookies", "4"). See `servings`.
    public var yield: String?
    public var author: String?
    public var siteName: String?
    public var sourceURL: URL?
    public var imageURL: URL?
    public var prepTime: Duration?
    public var cookTime: Duration?
    public var totalTime: Duration?
    /// Raw `recipeCategory` and `recipeCuisine`, when the page gives them.
    public var category: String?
    public var cuisine: String?
    /// Group headings ("For the dressing") keyed by the index of the first ingredient in the group.
    public var ingredientGroups: [Int: String]
    public var method: ImportMethod?
    /// 0…1. JSON-LD is high, the page-text reading low; below `reviewThreshold` the recipe needs a look.
    public var confidence: Double
    /// Set by library imports that carry the cook's favorite flag.
    public var isFavorite = false
    /// The cover's bytes when the source embeds them (Paprika's `photo_data`, Mela's `images`).
    public var imageData: Data?
    /// When the recipe was first added in the app it came from.
    public var createdAt: Date?
    /// The app an export came from ("Paprika", "Mela"), for the change summary. Nil for the web.
    public var importedFrom: String?

    /// Imports below this confidence are saved with `needsReview` set.
    public static let reviewThreshold = 0.7

    public init(
        title: String,
        ingredients: [String] = [],
        steps: [ImportedStep] = [],
        yield: String? = nil,
        author: String? = nil,
        siteName: String? = nil,
        sourceURL: URL? = nil,
        imageURL: URL? = nil,
        prepTime: Duration? = nil,
        cookTime: Duration? = nil,
        totalTime: Duration? = nil,
        category: String? = nil,
        cuisine: String? = nil,
        ingredientGroups: [Int: String] = [:],
        method: ImportMethod? = nil,
        confidence: Double = 1
    ) {
        self.title = title
        self.ingredients = ingredients
        self.steps = steps
        self.yield = yield
        self.author = author
        self.siteName = siteName
        self.sourceURL = sourceURL
        self.imageURL = imageURL
        self.prepTime = prepTime
        self.cookTime = cookTime
        self.totalTime = totalTime
        self.category = category
        self.cuisine = cuisine
        self.ingredientGroups = ingredientGroups
        self.method = method
        self.confidence = confidence
    }

    public init(draft: StructuredRecipeDraft, sourceURL: URL? = nil) {
        self.init(title: draft.title, ingredients: draft.ingredients, steps: draft.steps.map { ImportedStep(text: $0) }, sourceURL: sourceURL, confidence: draft.confidence)
    }

    public var needsReview: Bool { confidence < Self.reviewThreshold }

    /// Each ingredient line read by the deterministic parser.
    public var parsedIngredients: [ParsedIngredient] { ingredients.map(IngredientParser.parse) }

    /// The group heading that applies to the ingredient at `index`, if any.
    public func group(forIngredientAt index: Int) -> String? {
        ingredientGroups.filter { $0.key <= index }.max { $0.key < $1.key }?.value
    }

    /// Servings read from `yield` when it states them ("Serves 6", "4 to 6 servings", "8").
    public var servings: Int? { YieldText.parse(yield).servings }

    /// `yield` when it says more than a servings count ("Makes 30 cookies", "Serves 8 to 10"), else nil.
    public var yieldDescription: String? { YieldText.parse(yield).description }

    /// Steps that carry a photo URL from the source.
    public var stepImageCount: Int { steps.count(where: { $0.imageURL != nil }) }

    /// Moves asides the source posted as steps ("DO AHEAD: Lamb can be cut 2 hours ahead.",
    /// "Tip: …", "Make ahead: …", "Note: …") to the end of `notes`, keeping their order. Steps are
    /// never split or merged; a recipe whose every step is an aside keeps them as steps.
    public mutating func movingAsidesToNotes() {
        let asides = steps.filter { Self.isAside($0.text) }
        guard !asides.isEmpty, asides.count < steps.count else { return }
        steps.removeAll { Self.isAside($0.text) }
        notes += asides.map(\.text).filter { !notes.contains($0) }
    }

    /// "DO AHEAD", "Do Ahead:", "Make-ahead:", "Note:", "Tip:", "TIP " at the start of a step. "Note"
    /// and "Tip" need a colon (or capitals), so "Tip the batter into the pan" stays a step.
    static func isAside(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.range(of: #"^(do|make)[\s-]+ahead\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        if trimmed.range(of: #"^(notes?|tips?|cook'?s note)\s*[:—–]"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        return trimmed.range(of: #"^(NOTES?|TIPS?)\b"#, options: .regularExpression) != nil
    }
}
