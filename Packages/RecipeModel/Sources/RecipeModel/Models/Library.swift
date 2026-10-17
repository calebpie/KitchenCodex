import Foundation
import SwiftData

// Inverses are declared on the to-many (or owning) side only; SwiftData infers the other side.

extension RecipeSchemaV1 {
    /// A cookbook on the shelf.
    @Model
    public final class Book {
        public var id: UUID = UUID()
        public var title: String = ""
        public var author: String = ""
        public var isbn: String?
        public var publicationYear: Int?
        public var addedAt: Date = Date.now
        @Attribute(.externalStorage) public var coverImageData: Data?

        @Relationship(deleteRule: .cascade, inverse: \BookSection.book) public var sections: [BookSection]?
        @Relationship(deleteRule: .nullify, inverse: \Recipe.book) public var recipes: [Recipe]?

        public init(title: String = "", author: String = "", isbn: String? = nil) {
            self.title = title
            self.author = author
            self.isbn = isbn
        }
    }

    /// A chapter or section of a book, from the table of contents.
    @Model
    public final class BookSection {
        public var id: UUID = UUID()
        public var title: String = ""
        public var sortOrder: Int = 0
        public var startPage: Int?

        public var book: Book?
        @Relationship(deleteRule: .cascade, inverse: \BookEntry.section) public var entries: [BookEntry]?

        public init(title: String = "", sortOrder: Int = 0) {
            self.title = title
            self.sortOrder = sortOrder
        }
    }

    /// One recipe title on a book's punchlist, with its capture status.
    @Model
    public final class BookEntry {
        public var id: UUID = UUID()
        public var title: String = ""
        public var page: Int?
        public var sortOrder: Int = 0
        public var status: BookEntryStatus = BookEntryStatus.listed

        public var section: BookSection?
        @Relationship(deleteRule: .nullify, inverse: \Recipe.bookEntry) public var recipe: Recipe?

        public init(title: String = "", page: Int? = nil) {
            self.title = title
            self.page = page
        }
    }

    /// The library's unit. Content lives on `RecipeVersion`; this holds identity and history.
    @Model
    public final class Recipe {
        public var id: UUID = UUID()
        public var title: String = ""
        public var headnote: String = ""
        public var course: String?
        public var cuisine: String?
        public var isFavorite: Bool = false
        public var createdAt: Date = Date.now
        public var updatedAt: Date = Date.now
        public var pageNumber: Int?
        @Attribute(.externalStorage) public var coverImageData: Data?

        public var book: Book?
        public var bookEntry: BookEntry?
        @Relationship(deleteRule: .cascade, inverse: \RecipeVersion.recipe) public var versions: [RecipeVersion]?
        @Relationship(deleteRule: .nullify, inverse: \RecipeVersion.isCurrentOf) public var currentVersion: RecipeVersion?
        @Relationship(deleteRule: .cascade, inverse: \RecipeLink.parent) public var links: [RecipeLink]?
        @Relationship(deleteRule: .nullify, inverse: \RecipeLink.subRecipe) public var linkedFrom: [RecipeLink]?
        @Relationship(deleteRule: .nullify, inverse: \Tag.recipes) public var tags: [Tag]?
        @Relationship(deleteRule: .cascade, inverse: \CookSession.recipe) public var cookSessions: [CookSession]?
        @Relationship(deleteRule: .cascade, inverse: \SourceInfo.recipe) public var source: SourceInfo?
        @Relationship(deleteRule: .cascade, inverse: \NutritionEstimate.recipe) public var nutrition: NutritionEstimate?
        @Relationship(deleteRule: .cascade, inverse: \RecipeImage.recipe) public var images: [RecipeImage]?
        @Relationship(deleteRule: .nullify, inverse: \Candidate.recipe) public var candidates: [Candidate]?
        @Relationship(deleteRule: .nullify, inverse: \ScheduleTask.recipe) public var scheduleTasks: [ScheduleTask]?

        public init(title: String = "") {
            self.title = title
        }
    }

    /// One immutable snapshot of a recipe's content. Editing creates a new version.
    @Model
    public final class RecipeVersion {
        public var id: UUID = UUID()
        public var versionNumber: Int = 1
        public var createdAt: Date = Date.now
        public var changeSummary: String = ""
        public var yieldText: String = ""
        public var servings: Int?
        public var prepMinutes: Int?
        public var cookMinutes: Int?
        public var totalMinutes: Int?
        public var notes: String = ""

        public var recipe: Recipe?
        public var isCurrentOf: Recipe?
        @Relationship(deleteRule: .cascade, inverse: \Ingredient.version) public var ingredients: [Ingredient]?
        @Relationship(deleteRule: .cascade, inverse: \Step.version) public var steps: [Step]?

        public init(versionNumber: Int = 1, changeSummary: String = "") {
            self.versionNumber = versionNumber
            self.changeSummary = changeSummary
        }
    }

    /// A structured ingredient line. Quantity is an exact rational; `nil` numerator means "to taste".
    /// Unit is the raw value of `Units.CookingUnit`, kept as a string so this package stays dependency-free.
    @Model
    public final class Ingredient {
        public var id: UUID = UUID()
        public var sortOrder: Int = 0
        public var quantityNumerator: Int?
        public var quantityDenominator: Int?
        public var unit: String?
        public var item: String = ""
        public var preparation: String?
        public var isOptional: Bool = false
        public var group: String?
        public var rawText: String = ""

        public var version: RecipeVersion?

        public init(item: String = "", rawText: String = "", sortOrder: Int = 0) {
            self.item = item
            self.rawText = rawText
            self.sortOrder = sortOrder
        }
    }

    /// One instruction, with the annotations the scheduler needs.
    @Model
    public final class Step {
        public var id: UUID = UUID()
        public var sortOrder: Int = 0
        public var text: String = ""
        public var activeMinutes: Int?
        public var passiveMinutes: Int?
        public var waitMinutes: Int?
        public var equipment: [String] = []
        public var holdRule: String?

        public var version: RecipeVersion?
        @Relationship(deleteRule: .nullify, inverse: \ScheduleTask.step) public var scheduleTasks: [ScheduleTask]?

        public init(text: String = "", sortOrder: Int = 0) {
            self.text = text
            self.sortOrder = sortOrder
        }
    }

    /// Parent recipe → sub-recipe, variation, or reference.
    @Model
    public final class RecipeLink {
        public var id: UUID = UUID()
        public var role: RecipeLinkRole = RecipeLinkRole.component
        public var note: String = ""

        public var parent: Recipe?
        public var subRecipe: Recipe?

        public init(role: RecipeLinkRole = .component, note: String = "") {
            self.role = role
            self.note = note
        }
    }

    /// A user or system tag (dietary, cuisine, practicality…).
    @Model
    public final class Tag {
        public var id: UUID = UUID()
        public var name: String = ""
        public var kind: String?

        public var recipes: [Recipe]?

        public init(name: String = "", kind: String? = nil) {
            self.name = name
            self.kind = kind
        }
    }

    /// One time the recipe was cooked.
    @Model
    public final class CookSession {
        public var id: UUID = UUID()
        public var startedAt: Date = Date.now
        public var endedAt: Date?
        public var placeName: String?
        public var rating: Int?
        public var notes: String = ""
        public var observedYieldText: String?
        public var observedServings: Int?

        public var recipe: Recipe?
        public var event: Event?
        @Relationship(deleteRule: .cascade, inverse: \RecipeImage.cookSession) public var photos: [RecipeImage]?

        public init(startedAt: Date = .now) {
            self.startedAt = startedAt
        }
    }

    /// Where the recipe came from.
    @Model
    public final class SourceInfo {
        public var id: UUID = UUID()
        public var url: URL?
        public var author: String?
        public var siteName: String?
        public var sourceRating: Double?
        public var importedAt: Date?
        public var readerSummary: String?
        public var isOriginal: Bool = false

        public var recipe: Recipe?

        public init(url: URL? = nil, author: String? = nil) {
            self.url = url
            self.author = author
        }
    }

    /// Per-serving macros with the confidence shown beside them.
    @Model
    public final class NutritionEstimate {
        public var id: UUID = UUID()
        public var caloriesPerServing: Double?
        public var proteinGrams: Double?
        public var fatGrams: Double?
        public var carbohydrateGrams: Double?
        public var confidence: Double = 0
        public var computedAt: Date?

        public var recipe: Recipe?

        public init(confidence: Double = 0) {
            self.confidence = confidence
        }
    }

    /// A page scan, a cook photo, or an extra photo. Bytes live in external storage.
    @Model
    public final class RecipeImage {
        public var id: UUID = UUID()
        public var role: RecipeImageRole = RecipeImageRole.photo
        public var caption: String = ""
        public var pageNumber: Int?
        public var createdAt: Date = Date.now
        @Attribute(.externalStorage) public var imageData: Data?

        public var recipe: Recipe?
        public var cookSession: CookSession?

        public init(role: RecipeImageRole = .photo, imageData: Data? = nil) {
            self.role = role
            self.imageData = imageData
        }
    }
}
