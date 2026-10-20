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
        /// Page-layout signatures the cook has confirmed in review. Scan review is forced for the
        /// first recipe from a book and for any layout not in this list (02 Flow B step 5).
        public var reviewedLayouts: [String] = []

        @Relationship(deleteRule: .cascade, inverse: \BookSection.book) public var sections: [BookSection]?
        @Relationship(deleteRule: .nullify, inverse: \Recipe.book) public var recipes: [Recipe]?
        @Relationship(deleteRule: .nullify, inverse: \Source.book) public var sources: [Source]?
        /// Prose captured from this book: technique chapters and essays.
        @Relationship(deleteRule: .nullify, inverse: \Reference.book) public var references: [Reference]?
        /// The book's own scanned pages: contents and index pages (the punchlist), a Sources page, and
        /// pages captured in a scanning session that are not a recipe yet (Flow C). A recipe's page
        /// scan has its book set too. Deleting the book leaves its scans, as it leaves its recipes.
        @Relationship(deleteRule: .nullify, inverse: \RecipeImage.book) public var pageScans: [RecipeImage]?

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
        /// Set when the entry is an essay or technique chapter ("The Importance of Brown Butter")
        /// captured as a reference rather than a recipe.
        @Relationship(deleteRule: .nullify, inverse: \Reference.bookEntry) public var reference: Reference?

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
        /// 0…1: how sure the page reading behind a scanned recipe was, OCR, ingredient parser and
        /// structure (and the model, when it was asked) combined. Nil for recipes that were not
        /// read from a page. Kept on the recipe, unlike a version's `captureConfidence`, so it
        /// still says how the scan went after the cook's edits.
        public var extractionConfidence: Double?

        public var book: Book?
        public var bookEntry: BookEntry?
        @Relationship(deleteRule: .cascade, inverse: \RecipeVersion.recipe) public var versions: [RecipeVersion]?
        @Relationship(deleteRule: .nullify, inverse: \RecipeVersion.isCurrentOf) public var currentVersion: RecipeVersion?
        @Relationship(deleteRule: .cascade, inverse: \RecipeLink.parent) public var links: [RecipeLink]?
        @Relationship(deleteRule: .nullify, inverse: \RecipeLink.subRecipe) public var linkedFrom: [RecipeLink]?
        @Relationship(deleteRule: .nullify, inverse: \Tag.recipes) public var tags: [Tag]?
        @Relationship(deleteRule: .nullify, inverse: \RecipeCollection.recipes) public var collections: [RecipeCollection]?
        @Relationship(deleteRule: .cascade, inverse: \CookSession.recipe) public var cookSessions: [CookSession]?
        @Relationship(deleteRule: .cascade, inverse: \SourceInfo.recipe) public var source: SourceInfo?
        @Relationship(deleteRule: .cascade, inverse: \NutritionEstimate.recipe) public var nutrition: NutritionEstimate?
        @Relationship(deleteRule: .cascade, inverse: \RecipeImage.recipe) public var images: [RecipeImage]?
        @Relationship(deleteRule: .nullify, inverse: \Candidate.recipe) public var candidates: [Candidate]?
        @Relationship(deleteRule: .nullify, inverse: \ScheduleTask.recipe) public var scheduleTasks: [ScheduleTask]?
        /// Related reading: the references that inform this recipe, and that list it back.
        @Relationship(deleteRule: .nullify, inverse: \Reference.recipes) public var references: [Reference]?

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
        /// 0…1 from the capture pipeline (web, scan and library imports); nil for manual entry.
        public var captureConfidence: Double?
        /// Set when capture confidence was low or the book's layout was new, until the cook reviews it.
        public var needsReview: Bool = false
        /// Why a scanned version wants review, as Capture's `ReviewReason` raw values: the book's
        /// first recipe, a layout not yet confirmed, low OCR confidence, unparsed ingredient lines,
        /// a step count that disagrees with the page, a region nothing claimed (04 §5.1 "Scan
        /// review"). Empty when nothing asked for review.
        public var reviewReasons: [String] = []

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
        /// A trailing aside that is neither preparation nor a unit equivalent: "about 3 oranges",
        /// "plus more for the pan", "ask your butcher to do this" (04 §5.1 Ingredient lines).
        public var note: String?
        /// How the note stood in the line, the raw value of Capture's `NoteForm`: "clause" reads
        /// after a comma ("all-purpose flour, plus extra (for kneading)"), "parenthetical" in
        /// parentheses, so notes never nest. Nil without a note, and for notes stored before it.
        public var noteForm: String?
        /// When the note names produce the line comes from ("about 3 oranges", "from 2 lemons"), how
        /// many, as an exact rational like the quantity, so shopping can buy oranges, not juice.
        public var equivalentCountNumerator: Int?
        public var equivalentCountDenominator: Int?
        /// The produce the equivalent counts, as written: "oranges", "large lemons".
        public var equivalentItem: String?
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
        /// Photos of this step (role `.stepPhoto`). One with a cook session is the cook's own; one
        /// without came from the source.
        @Relationship(deleteRule: .cascade, inverse: \RecipeImage.step) public var images: [RecipeImage]?

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

    /// A collection the cook made ("Sunday Suppers", "Weeknights"): any recipes, in no particular
    /// order, shown in the iPad sidebar below the smart collections (03 §3.2, §4). A recipe can be in
    /// several; deleting a collection leaves its recipes in the library.
    @Model
    public final class RecipeCollection {
        public var id: UUID = UUID()
        public var name: String = ""
        /// Position among the collections, lowest first.
        public var sortOrder: Int = 0
        public var createdAt: Date = Date.now

        public var recipes: [Recipe]?

        public init(name: String = "", sortOrder: Int = 0) {
            self.name = name
            self.sortOrder = sortOrder
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
        /// How the recipe came in (04 §5.1 "Which book"). Nil for recipes saved before Phase 2.
        public var captureMethod: CaptureMethod?
        /// The pages it was read from, for a recipe or reference scanned from a book: one page, or
        /// a range when it runs over a spread or a chapter. The book is the recipe's or reference's.
        public var firstPage: Int?
        public var lastPage: Int?
        /// When the cook went through scan review for it. Nil on a scan saved straight to the
        /// library, which its source line calls "Accepted automatically".
        public var reviewedAt: Date?

        public var recipe: Recipe?
        /// The reference this is the source of. Every reference has one (02 §4.2): a URL, or its
        /// book and pages.
        public var reference: Reference?

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

    /// A page scan, a cook photo, a step photo, or an extra photo. Bytes live in external storage.
    @Model
    public final class RecipeImage {
        public var id: UUID = UUID()
        public var role: RecipeImageRole = RecipeImageRole.photo
        public var caption: String = ""
        public var pageNumber: Int?
        public var createdAt: Date = Date.now
        @Attribute(.externalStorage) public var imageData: Data?
        /// A page scan's regions for review: `ScanRegions` as JSON. Nil for other images and for
        /// scans not read yet.
        public var regions: Data?
        /// What a page scan turned out to be once read; nil for other images and for a captured page
        /// still waiting in the queue.
        public var pageKind: ScanPageKind?

        public var recipe: Recipe?
        public var cookSession: CookSession?
        /// Set for `.stepPhoto` images. Deleting the step deletes its photos; deleting a photo leaves the step.
        public var step: Step?
        /// The book a page scan came from.
        public var book: Book?
        /// Set for the pages and pictures of a reference.
        public var reference: Reference?

        public init(role: RecipeImageRole = .photo, imageData: Data? = nil) {
            self.role = role
            self.imageData = imageData
        }
    }
}

// MARK: - References

extension RecipeSchemaV1 {
    /// Prose that is not a recipe (02 §4.2): a technique essay saved from the web, a cookbook's
    /// technique chapter, a clipping. Captured by the same pipelines as recipes, it keeps its source
    /// (a URL, or its book and pages), links to the recipes it informs in both directions, and is
    /// what cook mode's technique lookups consult before the model. Added in Phase 2's schema
    /// change (slice 2); where it shows in the library is 04 §5.2's question.
    @Model
    public final class Reference {
        public var id: UUID = UUID()
        public var title: String = ""
        public var author: String = ""
        public var kind: ReferenceKind = ReferenceKind.article
        public var capturedAt: Date = Date.now
        public var tags: [String] = []

        public var book: Book?
        public var bookEntry: BookEntry?
        public var recipes: [Recipe]?
        @Relationship(deleteRule: .cascade, inverse: \ReferenceSection.reference) public var sections: [ReferenceSection]?
        /// Required in use (a URL, or a book and pages); optional in the schema, as CloudKit asks.
        @Relationship(deleteRule: .cascade, inverse: \SourceInfo.reference) public var source: SourceInfo?
        /// Page scans and pictures, as a recipe keeps its own.
        @Relationship(deleteRule: .cascade, inverse: \RecipeImage.reference) public var images: [RecipeImage]?

        public init(title: String = "", author: String = "", kind: ReferenceKind = .article) {
            self.title = title
            self.author = author
            self.kind = kind
        }
    }

    /// One headed section of a reference, in order.
    @Model
    public final class ReferenceSection {
        public var id: UUID = UUID()
        /// Empty for a reference's opening text, before its first heading.
        public var heading: String = ""
        public var body: String = ""
        /// Position in the reference, lowest first (02's "order").
        public var sortOrder: Int = 0

        public var reference: Reference?

        public init(heading: String = "", body: String = "", sortOrder: Int = 0) {
            self.heading = heading
            self.body = body
            self.sortOrder = sortOrder
        }
    }
}
